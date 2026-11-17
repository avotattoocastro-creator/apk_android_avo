// AVO Base científica KB-1: modelo de fatiga ósea (valores de referencia del estudio ampliado del 17/11/2026), bandas,
// contadores de Verheyen, reglas A1–A6 y fatiga ósea semanal, e integración con Track Work y Training Analytics.
#include <cmath>
#include <string>
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/engine.h"
#include "avo_eq/json.h"
#include "avo_eq/knowledge.h"
#include "avo_eq/training.h"
#include "eq_test.h"

using namespace avoeq;

namespace {
// Trabajo a velocidad constante integrado en épocas de 0,1 s (como el GNSS a 10 Hz).
KbSessionLoad constant_work(double dist_m, double v, const BoneModelConfig& m, double race_pace = 16.7, double work = 11.0) {
  SpeedBandConfig b; b.work_speed = work; b.race_pace = race_pace;
  KbSessionLoad L;
  double t = dist_m / v, dt = 0.1;
  int n = (int)std::floor(t / dt);
  for (int i = 0; i < n; i++) L.add(dt, v * dt, v, b, m);
  double rest = t - n * dt;
  if (rest > 1e-9) L.add(rest, v * rest, v, b, m);
  return L;
}
KbDay day_with(long d, double canter_m, double gallop_m, double bone_pct) {
  KbDay k; k.day = d; k.band_m[0] = canter_m; k.band_m[1] = 0; k.band_m[2] = gallop_m;
  k.canter_m = canter_m; k.gallop_m = gallop_m; k.bone_pct = bone_pct;
  return k;
}
const KbFlag* flag(const KbStatus& s, const std::string& rule) {
  for (const auto& f : s.flags) if (f.rule == rule) return &f;
  return nullptr;
}
}  // namespace

EQ_TEST(kb, bone_model_reference_values) {
  BoneModelConfig m;
  // T1: 1.200 m a 16,7 m/s, σmax 90 → 8,64 % (publicado: 9,34 % de media por carrera)
  KbSessionLoad t1 = constant_work(1200, 16.7, m);
  REPORT("T1 %.3f %% (%.1f zancadas), σ = %.2f MPa\n", 100 * t1.bone_fl, t1.strides, 90 * bone_vertical_force_n_kg(16.7) / 24.13);
  CHECK_NEAR(100 * t1.bone_fl, 8.64, 0.05);
  CHECK_NEAR(t1.strides, 167.1, 0.3);
  CHECK_NEAR(1.0 / bone_stride_damage(16.7, m), 1935, 5);
  // T2: σmax 54 → 0,028 %
  BoneModelConfig m54; m54.sigma_max_mpa = 54;
  CHECK_NEAR(100 * constant_work(1200, 16.7, m54).bone_fl, 0.028, 0.002);
  // T3: breeze de 600 m a 16 m/s → 3,77 %
  CHECK_NEAR(100 * constant_work(600, 16.0, m).bone_fl, 3.77, 0.05);
  // T4: 2.000 m de canter a 12 m/s → 3,27 %, fuera del rango validado (se acumula como extrapolado)
  KbSessionLoad t4 = constant_work(2000, 12.0, m);
  CHECK(t4.bone_fl == 0);
  CHECK_NEAR(100 * t4.bone_fl_low, 3.27, 0.05);
  CHECK_NEAR(t4.strides_low, 354.8, 0.5);
  // T5: σ0 = 139,0 MPa → 3,94 %
  BoneModelConfig m139; m139.sn_a_mpa = 139.0;
  CHECK_NEAR(100 * constant_work(1200, 16.7, m139).bone_fl, 3.94, 0.05);
  // T6: fuerza saturada por encima del máximo de la parábola, sin NaN ni negativos
  CHECK_NEAR(bone_vertical_force_n_kg(25.0), 24.13, 0.01);
  CHECK_NEAR(bone_vertical_force_n_kg(19.98), 24.13, 0.01);
  double d25 = bone_stride_damage(25.0, m);
  CHECK(d25 > 0 && std::isfinite(d25));
  CHECK(bone_stride_damage(26.0, m) == 0);
  CHECK(bone_stride_damage(NAN, m) == 0);
  CHECK_NEAR(model_stride_frequency_hz(16.0), 2.296, 0.001);
}

EQ_TEST(kb, speed_bands_and_verheyen_counters) {
  SpeedBandConfig psi; psi.work_speed = 11; psi.race_pace = 16.7;
  CHECK(kb_speed_band(8, psi) == -1);
  CHECK(kb_speed_band(12, psi) == 0);
  CHECK(kb_speed_band(14, psi) == 1);
  CHECK(kb_speed_band(16, psi) == 2);
  CHECK_NEAR(psi.b2_lo(), 13.36, 0.01);
  CHECK_NEAR(psi.b3_lo(), 15.53, 0.01);
  CHECK_NEAR(psi.gallop_lo(), 14.0, 1e-9);
  SpeedBandConfig ar; ar.work_speed = 10; ar.race_pace = 14.5;
  CHECK_NEAR(ar.b2_lo(), 11.6, 0.01);
  CHECK_NEAR(ar.b3_lo(), 13.485, 0.01);
  CHECK(kb_speed_band(13.6, ar) == 2);
  SpeedBandConfig gen; gen.work_speed = 9;   // GENERICO: sin v_carrera, todo en B1
  CHECK(kb_speed_band(17, gen) == 0);
  BoneModelConfig m;
  KbSessionLoad L = constant_work(1000, 14.0, m);   // exactamente en el corte: canter (≤ 14 m/s)
  CHECK_NEAR(L.canter_m, 1000, 1);
  CHECK(L.gallop_m == 0);
  KbSessionLoad G = constant_work(800, 15.0, m);
  CHECK_NEAR(G.gallop_m, 800, 1);
  CHECK_NEAR(G.band_m[1], 800, 1);
}

EQ_TEST(kb, rules_canter_gallop_and_ramp) {
  KbRuleConfig c;
  std::vector<KbDay> h;
  // 60 días: 30 anteriores con 1,5 km de canter y 200 m rápidos cada 3 días; 30 últimos con 1,6 km diarios y 600 m rápidos cada 3 días
  for (long d = 0; d < 60; d++) {
    if (d < 30) h.push_back(day_with(d, d % 3 == 0 ? 1500 : 0, d % 3 == 0 ? 200 : 0, 1.0));
    else h.push_back(day_with(d, 1600, d % 3 == 0 ? 600 : 0, 1.0));
  }
  KbStatus s = kb_evaluate(h, 59, 0, c);
  REPORT("canter 30 d %.1f km, galope 30 d %.1f km (antes %.1f km), reglas %zu\n", s.w30.canter_m / 1000, s.w30.gallop_m / 1000, s.prev30.gallop_m / 1000, s.flags.size());
  CHECK(s.available);
  CHECK_NEAR(s.w30.canter_m, 48000, 1);
  const KbFlag* a1 = flag(s, "A1_CANTER_30D");
  CHECK(a1 && a1->action == "LIMITAR" && a1->level == "VIGILAR");
  const KbFlag* a3 = flag(s, "A3_RAMPA");
  CHECK(a3 != nullptr);   // 6.000 m frente a 2.000 m: ratio 3
  CHECK(flag(s, "A2_GALOPE_30D") == nullptr);   // 6,0 km: no supera 6 km
  // con un poco más de galope sí se supera A2
  h.back().gallop_m = 800;
  CHECK(flag(kb_evaluate(h, 59, 0, c), "A2_GALOPE_30D") != nullptr);
  // aviso de canter entre 40 y 44 km
  std::vector<KbDay> h2;
  for (long d = 0; d < 30; d++) h2.push_back(day_with(d, 1400, 0, 0.5));   // 42 km
  KbStatus s2 = kb_evaluate(h2, 29, 0, c);
  const KbFlag* w = flag(s2, "A1_CANTER_30D");
  CHECK(w && w->action == "AVISO");
  // sin 60 días de historia no se juzga la rampa
  CHECK(flag(kb_evaluate(h, 59, 10, c), "A3_RAMPA") == nullptr);
}

EQ_TEST(kb, rules_return_after_rest) {
  KbRuleConfig c;
  std::vector<KbDay> h;
  for (long d = 0; d <= 20; d += 2) h.push_back(day_with(d, 1500, 400, 2.0));    // trabajo rápido hasta el día 20
  for (long d = 22; d < 90; d += 2) h.push_back(day_with(d, 1500, 0, 0.2));      // solo canter 70 días
  h.push_back(day_with(90, 1500, 400, 2.0));                                     // vuelta el día 90 (70 días sin rápido)
  KbStatus s = kb_evaluate(h, 95, 0, c);
  REPORT("vuelta: día %d tras %d días\n", s.return_day, s.return_rest);
  CHECK(s.return_day == 5 && s.return_rest == 70);
  const KbFlag* a5 = flag(s, "A5_VUELTA_DESCANSO");
  CHECK(a5 && a5->action == "LIMITAR");
  CHECK(flag(kb_evaluate(h, 112, 0, c), "A5_VUELTA_DESCANSO") == nullptr);   // pasada la ventana de 21 días
  CHECK(s.days_since_gallop == 5);
  // antes de la vuelta: 30 días sin rápido con canter → informativo
  CHECK(flag(kb_evaluate(h, 85, 0, c), "KB_SIN_RAPIDO_30D") != nullptr);
  // ≥ 90 días: regla tendinosa
  std::vector<KbDay> t;
  t.push_back(day_with(0, 1500, 400, 2.0));
  for (long d = 5; d < 100; d += 5) t.push_back(day_with(d, 1000, 0, 0.1));
  t.push_back(day_with(100, 1500, 400, 2.0));
  KbStatus st = kb_evaluate(t, 101, 0, c);
  const KbFlag* a6 = flag(st, "A6_VUELTA_TENDON");
  CHECK(a6 && a6->text.find("ecografía") != std::string::npos);
}

EQ_TEST(kb, weekly_bone_fatigue_ratio) {
  KbRuleConfig c;
  std::vector<KbDay> h;
  for (long w = 0; w < 8; w++) { h.push_back(day_with(w * 7 + 1, 2000, 300, 1.0)); h.push_back(day_with(w * 7 + 4, 2000, 300, 1.0)); }
  h.push_back(day_with(57, 2000, 600, 2.0)); h.push_back(day_with(60, 2000, 600, 2.0));   // semana actual: 4 % frente a 2 %
  KbStatus s = kb_evaluate(h, 62, 0, c);
  REPORT("fatiga ósea 7 d %.2f %%, mediana semanal %.2f %%, ratio %.2f\n", s.w7.bone_pct, s.bone_weekly_median, s.bone_ratio);
  CHECK_NEAR(s.bone_weekly_median, 2.0, 1e-9);
  CHECK_NEAR(s.bone_ratio, 2.0, 1e-9);
  CHECK(flag(s, "KB_FATIGA_OSEA_7D") != nullptr);
  // sin historia suficiente no hay línea base
  CHECK(std::isnan(kb_evaluate(h, 62, 40, c).bone_weekly_median));
  // desactivada: solo ventanas, sin reglas
  KbRuleConfig off; off.enabled = false;
  CHECK(kb_evaluate(h, 62, 0, off).flags.empty());
  // historia sin bloque KB (análisis anteriores): no disponible
  std::vector<KbDay> old(3); old[0].day = 1; old[1].day = 2; old[2].day = 3;
  CHECK(!kb_evaluate(old, 3, 1, c).available);
}

EQ_TEST(kb, training_history_and_json) {
  // 35 días de canter alto (1,6 km diarios) con resumen de sesión que trae el bloque KB
  std::vector<SessionSummary> ss;
  for (int d = 0; d < 35; d++) {
    SessionSummary s; s.id = "S" + std::to_string(d); s.horse = "LUNA"; s.date_utc = training_day_text(20500 + d);
    s.gait[2].duration_s = 300; s.moving_s = 1800;
    s.race.present = true; s.race.breed = "PSI";
    s.race.kb_race_pace = 16.7; s.race.kb_band_m[0] = 1600; s.race.kb_band_m[1] = 0; s.race.kb_band_m[2] = 0;
    s.race.kb_canter_m = 1600; s.race.kb_gallop_m = 0; s.race.kb_bone_pct = 0.0; s.race.kb_bone_low_pct = 1.5; s.race.kb_strides = 0;
    ss.push_back(s);
  }
  // ida y vuelta por JSON del resumen
  json::Value v; std::string err;
  CHECK(json::parse(training_summary_to_json(ss[0]), &v, &err));
  SessionSummary back; CHECK(training_summary_from_json(v, &back, &err));
  CHECK_NEAR(back.race.kb_canter_m, 1600, 1e-9);
  CHECK_NEAR(back.race.kb_bone_low_pct, 1.5, 1e-9);
  TrainingConfig c;
  TrainingResult r = analyse_training(ss, "", c);
  CHECK(r.kb.available);
  CHECK(flag(r.kb, "A1_CANTER_30D") != nullptr);
  CHECK(r.level != "NORMAL");
  bool reason = false;
  for (const auto& m : r.reasons) if (m.find("A1_CANTER_30D") != std::string::npos) reason = true;
  CHECK(reason);
  json::Value out;
  CHECK(json::parse(training_to_json(r, c), &out, &err));
  CHECK(out["estado"]["base_cientifica"]["disponible"].boolean(false));
  CHECK(out["sesiones"][34]["base_cientifica"]["reglas"].a.size() >= 1);
  // opciones: desactivar la base científica
  json::Value opt; CHECK(json::parse("{\"base_cientifica\":{\"activa\":false}}", &opt, &err));
  TrainingConfig c2; CHECK(training_config_from_json(opt, &c2, &err));
  CHECK(!c2.kb.enabled);
  CHECK(analyse_training(ss, "", c2).kb.flags.empty());
  json::Value bad; CHECK(json::parse("{\"base_cientifica\":{\"canter_30d_aviso_km\":50}}", &bad, &err));
  TrainingConfig c3; CHECK(!training_config_from_json(bad, &c3, &err));
}
