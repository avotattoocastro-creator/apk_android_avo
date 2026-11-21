// AVO Base científica KB-1: modelo de fatiga ósea (valores de referencia del estudio ampliado del 17/11/2026), bandas,
// contadores de Verheyen, reglas A1–A6, A6B y fatiga ósea semanal, e integración con Track Work y Training Analytics.
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

// A6B (Choi & Parkin 2025, EVJ 58:31, tabla 2): ≤ 2 días de galope en los 60 días previos, OR 1,842 (1,073–3,162) [E].
EQ_TEST(kb, rule_low_gallop_days_60d) {
  KbRuleConfig c;
  CHECK(c.low_gallop_60d_max_days == 2);
  std::vector<KbDay> h;
  // 70 días con canter cada 2 días; galope rápido (400 m) solo los días 20 y 40
  for (long d = 0; d < 70; d += 2) h.push_back(day_with(d, 1500, (d == 20 || d == 40) ? 400 : 0, 0.5));
  KbStatus s = kb_evaluate(h, 68, 0, c);
  REPORT("días de galope en 60 d: %d\n", s.gallop_days_60d);
  CHECK(s.gallop_days_60d == 2);
  const KbFlag* f = flag(s, "A6B_POCO_GALOPE_60D");
  CHECK(f && f->level == "INFO" && f->action == "AVISO");
  CHECK(f && f->evidence.find("1,84") != std::string::npos);
  CHECK(kb_status_json(s).find("\"dias_galope_60d\":2") != std::string::npos);
  // con un tercer día de galope ya no salta (categoría de referencia 3–24 días)
  h[30].gallop_m = 400;   // día 60
  KbStatus s3 = kb_evaluate(h, 68, 0, c);
  CHECK(s3.gallop_days_60d == 3);
  CHECK(flag(s3, "A6B_POCO_GALOPE_60D") == nullptr);
  // dos sesiones rápidas el mismo día cuentan como un solo día
  std::vector<KbDay> dup = h; dup[30].gallop_m = 0; dup.insert(dup.begin() + 21, day_with(40, 0, 300, 0.2));
  CHECK(kb_evaluate(dup, 68, 0, c).gallop_days_60d == 2);
  // sin 60 días de historia o sin sesiones en la última semana no se juzga
  CHECK(flag(kb_evaluate(h, 68, 20, c), "A6B_POCO_GALOPE_60D") == nullptr);
  h[30].gallop_m = 0;
  CHECK(flag(kb_evaluate(h, 78, 0, c), "A6B_POCO_GALOPE_60D") == nullptr);   // última sesión el día 68
  // umbral configurable
  KbRuleConfig c0; c0.low_gallop_60d_max_days = 1;
  CHECK(flag(kb_evaluate(h, 68, 0, c0), "A6B_POCO_GALOPE_60D") == nullptr);
}

// A6C (Choi & Parkin 2025, EVJ 58:31, sección 2.3 y tabla 2): (g60/g90) + 1 ≤ 1,6, OR 2,190 (1,227–3,910) [E];
// ventanas anidadas de 60 y 90 días que acaban en el último trabajo rápido [E].
EQ_TEST(kb, rule_gallop_ratio_60_90) {
  KbRuleConfig c;
  CHECK_NEAR(c.gallop_ratio_max, 1.6, 1e-12);
  std::vector<KbDay> h;
  // 120 días con canter cada 2 días; galope (400 m) los días 34, 40, 46, 52, 58 y después solo 80, 100 y 118
  for (long d = 0; d <= 118; d += 2) {
    bool g = d == 34 || d == 40 || d == 46 || d == 52 || d == 58 || d == 80 || d == 100 || d == 118;
    h.push_back(day_with(d, 1500, g ? 400 : 0, 0.5));
  }
  // último trabajo rápido el día 118: ventana de 90 d = días 29–118 (8 galopes), de 60 d = días 59–118 (3 galopes)
  KbStatus s = kb_evaluate(h, 119, 0, c);
  REPORT("cociente de galope %.3f (g60 %d, g90 %d)\n", s.gallop_ratio, s.gallop_days_60_last, s.gallop_days_90_last);
  CHECK(s.gallop_days_60_last == 3 && s.gallop_days_90_last == 8);
  CHECK_NEAR(s.gallop_ratio, 3.0 / 8.0 + 1.0, 1e-12);   // 1,375
  const KbFlag* f = flag(s, "A6C_COCIENTE_GALOPE");
  CHECK(f && f->level == "INFO" && f->action == "AVISO");
  CHECK(f && f->evidence.find("2,19") != std::string::npos);
  CHECK(kb_status_json(s).find("\"cociente_galope\":{\"valor\":1.375") != std::string::npos);
  // reparto regular (galope cada 6 días): g60 = 10, g90 = 15 → 1,667 > 1,6: no salta
  std::vector<KbDay> r;
  for (long d = 0; d <= 118; d += 2) r.push_back(day_with(d, 1500, (d % 6 == 4) ? 400 : 0, 0.5));
  KbStatus sr = kb_evaluate(r, 119, 0, c);
  REPORT("reparto regular: cociente %.3f (g60 %d, g90 %d)\n", sr.gallop_ratio, sr.gallop_days_60_last, sr.gallop_days_90_last);
  CHECK(sr.gallop_days_60_last == 10 && sr.gallop_days_90_last == 15);
  CHECK(flag(sr, "A6C_COCIENTE_GALOPE") == nullptr);
  // umbral exacto: con 1,7 el reparto regular sí avisa
  KbRuleConfig c17; c17.gallop_ratio_max = 1.7;
  CHECK(flag(kb_evaluate(r, 119, 0, c17), "A6C_COCIENTE_GALOPE") != nullptr);
  // sin 90 días de historia antes del último trabajo rápido no se calcula
  KbStatus sn = kb_evaluate(h, 119, 40, c);
  CHECK(std::isnan(sn.gallop_ratio));
  CHECK(flag(sn, "A6C_COCIENTE_GALOPE") == nullptr);
  CHECK(kb_status_json(sn).find("\"cociente_galope\":null") != std::string::npos);
  // último trabajo rápido de hace más de 30 días: no se juzga (A5/A6 cubren la vuelta)
  std::vector<KbDay> o = h;
  for (long d = 120; d <= 154; d += 2) o.push_back(day_with(d, 1500, 0, 0.5));
  CHECK(flag(kb_evaluate(o, 140, 0, c), "A6C_COCIENTE_GALOPE") != nullptr);   // 22 días desde el último galope
  CHECK(flag(kb_evaluate(o, 154, 0, c), "A6C_COCIENTE_GALOPE") == nullptr);   // 36 días
  // umbral de vigencia configurable
  KbRuleConfig c40; c40.gallop_ratio_max_age_days = 40;
  CHECK(flag(kb_evaluate(o, 154, 0, c40), "A6C_COCIENTE_GALOPE") != nullptr);
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

// KB-1 1.1.0: velocidad de los últimos 600 m (Schrurs 2024, «average speed over the last 600 m»), pendiente A8.
EQ_TEST(kb, final_speed_last_600m) {
  // épocas de 0,1 s con la última muestra exacta al final del tramo
  auto build = [](const std::vector<std::pair<double, double>>& segs, std::vector<double>* t, std::vector<double>* d) {
    double tt = 0, dd = 0; t->push_back(0); d->push_back(0);
    for (const auto& s : segs) {
      double dur = s.first / s.second, end = tt + dur;
      for (double x = tt + 0.1; x < end - 1e-9; x += 0.1) { t->push_back(x); d->push_back(dd + (x - tt) * s.second); }
      tt = end; dd += s.first; t->push_back(tt); d->push_back(dd);
    }
  };
  // R1: 1.000 m a 16 m/s → 37,5 s y 16 m/s
  std::vector<double> t, d; build({{1000, 16}}, &t, &d);
  double ts = 0, v = 0;
  CHECK(kb_final_speed(t, d, KB_FINAL_DISTANCE_M, &ts, &v));
  CHECK_NEAR(ts, 37.5, 1e-6); CHECK_NEAR(v, 16.0, 1e-6);
  // R2: 1.000 m a 14 m/s + 400 m a 17 m/s → últimos 600 m = 200/14 + 400/17 = 37,8151 s → 15,8667 m/s
  t.clear(); d.clear(); build({{1000, 14}, {400, 17}}, &t, &d);
  CHECK(kb_final_speed(t, d, 600, &ts, &v));
  REPORT("últimos 600 m: %.4f s, %.4f m/s (referencia 37,8151 s, 15,8667 m/s)\n", ts, v);
  CHECK_NEAR(ts, 200.0 / 14 + 400.0 / 17, 1e-3); CHECK_NEAR(v, 600.0 / (200.0 / 14 + 400.0 / 17), 1e-3);
  // R3: la velocidad final es D/tiempo, no la media de las muestras (con desaceleración final 17 → 15 m/s)
  t.clear(); d.clear(); build({{800, 15}, {300, 17}, {300, 15}}, &t, &d);
  CHECK(kb_final_speed(t, d, 600, &ts, &v));
  CHECK_NEAR(ts, 300.0 / 17 + 300.0 / 15, 1e-3); CHECK_NEAR(v, 600.0 / (300.0 / 17 + 20.0), 1e-3);
  // R4: un hueco GNSS (NaN) fuera del tramo final no cambia el resultado
  std::vector<double> d2 = d; d2[50] = std::nan(""); d2[51] = std::nan("");
  double ts2 = 0, v2 = 0;
  CHECK(kb_final_speed(t, d2, 600, &ts2, &v2)); CHECK_NEAR(ts2, ts, 1e-9);
  // R5: esfuerzo más corto que 600 m o datos vacíos → false y salida intacta
  t.clear(); d.clear(); build({{500, 16}}, &t, &d);
  double keep = -1;
  CHECK(!kb_final_speed(t, d, 600, &keep, nullptr)); CHECK_NEAR(keep, -1, 0);
  CHECK(!kb_final_speed({}, {}, 600, &keep, nullptr));
  CHECK(std::string(KNOWLEDGE_VERSION) == "1.25.0");
}

// Líneas base (KB 1.3.0, estudio extra 2026-11-19): valores de referencia del estudio ampliado del 18/11 y de la cadena
// de Markov de Brook-Evans (ARL), recalculados a mano en el estudio extra.
EQ_TEST(kb, baseline_robust_median_mad) {
  // L1: {6,9; 7,0; 7,1; 7,05; 6,95; 7,2; 6,85; 7,0} → mediana 7,0; MAD 0,075; MAD_s 0,1112
  std::vector<double> x = {6.9, 7.0, 7.1, 7.05, 6.95, 7.2, 6.85, 7.0};
  KbRobustBaseline b = kb_robust_baseline(x);
  CHECK(b.n == 8);
  CHECK_NEAR(b.median, 7.0, 1e-12);
  CHECK_NEAR(b.mad_s, 1.4826 * 0.075, 1e-9);
  REPORT("línea base: mediana %.4f, MAD_s %.4f (referencia 7,0 y 0,1112)\n", b.median, b.mad_s);
  CHECK_NEAR(b.mad_s, 0.1112, 1e-4);
  // L2: z robusto de 7,4 = 0,4/0,111195 = 3,597 → atípico (> 3,5); 7,3 → 2,698, no
  CHECK_NEAR(kb_robust_z(7.4, b), 0.4 / (1.4826 * 0.075), 1e-9);
  CHECK(kb_robust_z(7.4, b) > KB_ROBUST_Z_OUTLIER);
  CHECK(kb_robust_z(7.3, b) < KB_ROBUST_Z_OUTLIER);
  // L3: NaN se saltan y last_n toma las últimas válidas: {.., 1, 2, NaN, 3} con last_n 3 → {1,2,3}, mediana 2, MAD_s 1,4826
  KbRobustBaseline b2 = kb_robust_baseline({100, 1, 2, std::nan(""), 3}, 3);
  CHECK(b2.n == 3); CHECK_NEAR(b2.median, 2.0, 0); CHECK_NEAR(b2.mad_s, 1.4826, 1e-12);
  // L4: menos de 3 datos o escala nula → NaN; min_scale evita la escala nula
  CHECK(std::isnan(kb_robust_z(1.0, kb_robust_baseline({1, 2}))));
  KbRobustBaseline flat = kb_robust_baseline({5, 5, 5, 5});
  CHECK_NEAR(flat.mad_s, 0, 0);
  CHECK(std::isnan(kb_robust_z(5.5, flat)));
  CHECK_NEAR(kb_robust_z(5.5, flat, 0.25), 2.0, 1e-12);
  CHECK(kb_robust_baseline({}).n == 0);
}

EQ_TEST(kb, baseline_shrinkage_and_threshold) {
  // S1: n = 3, x̄ = 10,0, σ² = 0,04, μ_pop = 9,6, τ² = 0,09 → μ* = 9,9484
  double m = kb_shrink_mean(3, 10.0, 0.04, 9.6, 0.09);
  REPORT("shrinkage: %.4f (referencia 9,9484)\n", m);
  CHECK_NEAR(m, (3 * 10.0 / 0.04 + 9.6 / 0.09) / (3 / 0.04 + 1 / 0.09), 1e-12);
  CHECK_NEAR(m, 9.9484, 1e-4);
  // S2: peso propio = n·ICC/(1 + (n−1)·ICC) con ICC = τ²/(τ² + σ²); ICC 0,6 y n = 8 → 0,923
  double s2 = 0.4, t2 = 0.6, w = 8 * 0.6 / (1 + 7 * 0.6);
  CHECK_NEAR(kb_shrink_mean(8, 1.0, s2, 0.0, t2), w, 1e-12);
  // S3: casos límite: n = 0 → μ_pop; sin prior → x̄
  CHECK_NEAR(kb_shrink_mean(0, 10.0, 0.04, 9.6, 0.09), 9.6, 0);
  CHECK_NEAR(kb_shrink_mean(3, 10.0, 0.04, std::nan(""), 0.09), 10.0, 0);
  CHECK_NEAR(kb_shrink_mean(3, 10.0, 0.04, 9.6, 0), 10.0, 0);
  // T1: TE 0,15 y n = 8 → 2·0,15·√1,125 = 0,3182; con SWC 0,4 manda el SWC; n ≤ 0 → 2·TE·√2 = 0,4243
  CHECK_NEAR(kb_change_threshold(0.15, 8, 0.1), 0.3 * std::sqrt(1.125), 1e-12);
  CHECK_NEAR(kb_change_threshold(0.15, 8, 0.4), 0.4, 0);
  CHECK_NEAR(kb_change_threshold(0.15, 0, 0.0), 0.3 * std::sqrt(2.0), 1e-12);
  CHECK_NEAR(kb_change_threshold(std::nan(""), 8, 0.4), 0.4, 0);
}

EQ_TEST(kb, baseline_cusum_upper) {
  // C1: z = {0,2; 1,2; 1,5; 0,8; 1,6; 1,4; 1,1}, k 0,5, h 4 → S = {0; 0,7; 1,7; 2,0; 3,1; 4,0; 4,6}, alarma en la 7.ª
  KbCusumConfig c;
  KbCusumResult r = kb_cusum_upper({0.2, 1.2, 1.5, 0.8, 1.6, 1.4, 1.1}, c);
  const double ref[] = {0, 0.7, 1.7, 2.0, 3.1, 4.0, 4.6};
  CHECK(r.s.size() == 7);
  for (int i = 0; i < 7; i++) CHECK_NEAR(r.s[i], ref[i], 1e-9);
  CHECK(r.alarm_index == 6);
  // C2: con h = 5 no salta; con FIR (S0 = 2) salta antes, en la 5.ª (1,7 → 2,4 → 3,4 → 3,7 → 4,8)
  KbCusumConfig c5; c5.h = 5;
  CHECK(kb_cusum_upper({0.2, 1.2, 1.5, 0.8, 1.6, 1.4, 1.1}, c5).alarm_index == -1);
  KbCusumConfig cf; cf.fir = true;
  KbCusumResult rf = kb_cusum_upper({0.2, 1.2, 1.5, 0.8, 1.6, 1.4, 1.1}, cf);
  CHECK_NEAR(rf.s[0], 1.7, 1e-12); CHECK_NEAR(rf.s[3], 3.7, 1e-9); CHECK_NEAR(rf.s[4], 4.8, 1e-9);
  CHECK(rf.alarm_index == 4);
  // C3: NaN no cambia S; min_samples retrasa la alarma; una deriva a la baja se vigila con −z
  KbCusumResult rn = kb_cusum_upper({3.0, std::nan(""), 3.0}, c);
  CHECK_NEAR(rn.s[1], 2.5, 1e-12); CHECK_NEAR(rn.s[2], 5.0, 1e-12); CHECK(rn.alarm_index == 2);
  KbCusumConfig cm; cm.min_samples = 5;
  CHECK(kb_cusum_upper({9, 9, 9, 9, 9}, cm).alarm_index == 4);
  CHECK(kb_cusum_upper({-1.5, -1.5, -1.5, -1.5}, c).alarm_index == -1);
  CHECK(kb_cusum_upper({1.5, 1.5, 1.5, 1.5, 1.5}, c).alarm_index == 4);   // 1, 2, 3, 4, 5 → > 4 en la 5.ª
  CHECK(kb_cusum_upper({}, c).s.empty());
}

EQ_TEST(kb, baseline_self_starting_cusum) {
  // H1: auxiliares frente a scipy 1.18 (t.cdf y norm.ppf)
  CHECK_NEAR(kb_student_t_cdf(2.0, 3), 0.9303370157205785, 1e-10);
  CHECK_NEAR(kb_student_t_cdf(-1.5, 7), 0.088649243494985, 1e-10);
  CHECK_NEAR(kb_student_t_cdf(0.7, 1), 0.6944001122142147, 1e-10);
  CHECK_NEAR(kb_normal_quantile(0.975), 1.959963984540054, 1e-9);
  CHECK_NEAR(kb_normal_quantile(1e-10), -6.361340902404056, 1e-8);
  CHECK(std::isnan(kb_normal_quantile(1.5)));
  // H2: Hawkins 1987 sobre x = {10,0; 10,4; 9,8; 10,9; 10,1; 12,0} (referencia calculada con scipy)
  std::vector<double> xi = kb_self_starting_z({10.0, 10.4, 9.8, 10.9, 10.1, 12.0});
  CHECK(xi.size() == 6);
  CHECK(std::isnan(xi[0]) && std::isnan(xi[1]));
  const double ref[] = {-0.7481477355715538, 1.4683756165434736, -0.2945083832748484, 2.3292112693312133};
  for (int i = 0; i < 4; i++) CHECK_NEAR(xi[i + 2], ref[i], 1e-8);
  REPORT("autoiniciado: xi_6 = %.4f (referencia 2,3292)\n", xi[5]);
  // H3: NaN se salta y no cuenta; s = 0 da NaN; vacío
  std::vector<double> xn = kb_self_starting_z({10.0, std::nan(""), 10.4, 9.8, 10.9});
  CHECK(std::isnan(xn[1]) && std::isnan(xn[2]));
  CHECK_NEAR(xn[3], ref[0], 1e-8); CHECK_NEAR(xn[4], ref[1], 1e-8);
  CHECK(std::isnan(kb_self_starting_z({5, 5, 5})[2]));
  CHECK(kb_self_starting_z({}).empty());
  // H4: encadenado con el CUSUM: una subida sostenida tras 8 sesiones estables acaba en alarma; sin subida, no
  std::vector<double> base = {10.0, 10.2, 9.9, 10.1, 9.8, 10.3, 10.0, 9.9};
  std::vector<double> up = base;
  for (int i = 0; i < 6; i++) up.push_back(10.6 + 0.05 * i);
  KbCusumConfig c; c.min_samples = 8;
  CHECK(kb_cusum_upper(kb_self_starting_z(up), c).alarm_index >= 8);
  CHECK(kb_cusum_upper(kb_self_starting_z(base), c).alarm_index == -1);
}

// KB-1 1.5.0: reglas A7 (zancada) y A8 (velocidad final) sobre la línea base propia, con CUSUM autoiniciado.
EQ_TEST(kb, drift_down_rule) {
  const std::vector<double> base = {6.40, 6.42, 6.38, 6.41, 6.39, 6.43, 6.40, 6.37, 6.42, 6.41};
  KbDriftConfig c; c.delta = 0.10;
  // D1: serie estable → sin alarma
  KbDriftResult r0 = kb_drift_down(base, c);
  CHECK(!r0.delta_alarm && !r0.cusum_alarm);
  CHECK(r0.n == 10 && r0.baseline_n == 7);
  // D2: tres sesiones 0,2 m más cortas → umbral (3 de 3) y CUSUM
  std::vector<double> x = base; x.push_back(6.20); x.push_back(6.18); x.push_back(6.19);
  KbDriftResult r1 = kb_drift_down(x, c);
  REPORT("deriva: caída %.3f m frente a %.3f (n %d), aciertos %d, S %.2f\n", r1.drop, r1.baseline, r1.baseline_n, r1.hits, r1.s);
  CHECK(r1.delta_alarm && r1.hits == 3);
  CHECK_NEAR(r1.baseline, 6.405, 1e-9);   // mediana de las 10 anteriores
  CHECK_NEAR(r1.drop, 0.215, 1e-9);
  CHECK(r1.cusum_alarm);
  // D3: una sola sesión corta entre normales → no basta (1 de 3)
  std::vector<double> y = base; y.push_back(6.40); y.push_back(6.41); y.push_back(6.20);
  CHECK(!kb_drift_down(y, c).delta_alarm);
  // D4: pocas sesiones → ni umbral (base < 5) ni CUSUM (calentamiento de 8)
  KbDriftResult r3 = kb_drift_down({6.40, 6.41, 6.39, 6.40, 6.20, 6.18, 6.19}, c);
  CHECK(!r3.delta_alarm && !r3.cusum_alarm && r3.baseline_n == 4);
  // D5: NaN se saltan; una subida no es caída
  std::vector<double> z = base; z.push_back(std::nan("")); z.push_back(6.70); z.push_back(6.72); z.push_back(6.71);
  KbDriftResult r4 = kb_drift_down(z, c);
  CHECK(r4.n == 13 && !r4.delta_alarm && !r4.cusum_alarm);
  CHECK(kb_drift_down({}, c).n == 0);
}

EQ_TEST(kb, drift_rules_in_training) {
  auto mk = [](int d, const std::string& surf, double sl, double v600) {
    SessionSummary s; s.id = "D" + std::to_string(d); s.horse = "LUNA"; s.date_utc = training_day_text(20500 + 3 * d);
    s.gait[2].duration_s = 300; s.moving_s = 1800; s.surface = surf;
    s.race.present = true; s.race.breed = "PSI"; s.race.ref_speed[0] = 14; s.race.sl_ref[0] = sl; s.race.v_last_600 = v600;
    return s;
  };
  const double sl[] = {6.40, 6.42, 6.38, 6.41, 6.39, 6.43, 6.40, 6.37, 6.42, 6.41};
  const double v6[] = {15.80, 15.85, 15.78, 15.82, 15.79, 15.84, 15.81, 15.77, 15.83, 15.80};
  std::vector<SessionSummary> ss;
  for (int i = 0; i < 10; i++) ss.push_back(mk(i, "ARENA", sl[i], v6[i]));
  for (int i = 10; i < 13; i++) ss.push_back(mk(i, "ARENA", 6.22, 15.50));
  TrainingConfig c;
  TrainingResult r = analyse_training(ss, "", c);
  const SessionResult& last = r.sessions.back();
  const KbFlag* a7 = flag(last.kb, "A7_CAIDA_ZANCADA");
  const KbFlag* a8 = flag(last.kb, "A8_CAIDA_VELOCIDAD_FINAL");
  CHECK(a7 && a7->level == "VIGILAR");
  CHECK(a8 != nullptr);
  CHECK(last.level != "NORMAL");
  CHECK(flag(r.kb, "A7_CAIDA_ZANCADA") != nullptr);   // la última sesión está dentro de los 7 días
  CHECK(flag(r.sessions[9].kb, "A7_CAIDA_ZANCADA") == nullptr);
  bool reason = false;
  for (const auto& m : r.reasons) if (m.find("A7_CAIDA_ZANCADA") != std::string::npos) reason = true;
  CHECK(reason);
  // otra superficie: no es comparable con la arena → sin línea base, sin regla
  std::vector<SessionSummary> s2 = ss;
  for (int i = 10; i < 13; i++) s2[i].surface = "PLAYA";
  CHECK(flag(analyse_training(s2, "", c).sessions.back().kb, "A7_CAIDA_ZANCADA") == nullptr);
  // ida y vuelta del resumen con v_ultimos_600m
  json::Value v; std::string err; SessionSummary back;
  CHECK(json::parse(training_summary_to_json(ss[12]), &v, &err) && training_summary_from_json(v, &back, &err));
  CHECK_NEAR(back.race.v_last_600, 15.50, 1e-9);
  // opciones: umbrales y desactivar
  json::Value opt; CHECK(json::parse("{\"base_cientifica\":{\"caida_zancada_m\":0.3,\"cusum_h\":40}}", &opt, &err));
  TrainingConfig c2; CHECK(!training_config_from_json(opt, &c2, &err));   // h fuera de rango
  json::Value opt2; CHECK(json::parse("{\"base_cientifica\":{\"caida_zancada_m\":0.3,\"cusum_h\":8}}", &opt2, &err));
  TrainingConfig c3; CHECK(training_config_from_json(opt2, &c3, &err));
  CHECK_NEAR(c3.kb.stride_drop_m, 0.3, 1e-12); CHECK_NEAR(c3.kb.drift_h, 8, 1e-12);
  const KbFlag* a7b = flag(analyse_training(ss, "", c3).sessions.back().kb, "A7_CAIDA_ZANCADA");
  CHECK(a7b == nullptr || a7b->text.find("CUSUM") != std::string::npos);   // 0,22 m < 0,3 m: solo puede saltar el CUSUM
}

// A4 (KB 1.25.0): Morrice-West 2025, carga muy baja antes de correr, HR 2,89 [E]; corte < 2 días rápidos en 28 d [I].
EQ_TEST(kb, rule_low_load_before_race) {
  KbRuleConfig c;
  CHECK(c.prerace_days == 28 && c.prerace_min_fast_days == 2 && c.prerace_warn_days == 14);
  std::vector<KbDay> h;
  // canter cada 2 días desde el día 0 hasta el 98; galope rápido (400 m) solo el día 80
  for (long d = 0; d <= 98; d += 2) h.push_back(day_with(d, 1500, d == 80 ? 400 : 0, 0.3));
  // 1) carrera prevista el día 100, evaluada el 90 (faltan 10 ≤ 14): 1 día rápido en [72, 90] → AVISO
  c.planned_race_days = {100};
  KbStatus s = kb_evaluate(h, 90, 0, c);
  const KbFlag* f = flag(s, "A4_CARGA_BAJA_PRECARRERA");
  CHECK(f && f->level == "INFO" && f->action == "AVISO");
  CHECK(f && f->evidence.find("2,89") != std::string::npos && f->evidence.find("[I]") != std::string::npos);
  CHECK(s.races.size() == 1 && s.races[0].planned && s.races[0].days_to == 10 && s.races[0].fast_days == 1 && s.races[0].covered);
  std::string js = kb_status_json(s);
  CHECK(js.find("\"carreras\":[{\"fecha\":\"1970-04-11\",\"origen\":\"PREVISTA\",\"dias_hasta\":10,\"dias_rapidos_28d\":1") != std::string::npos);
  // 2) misma carrera vista el día 80 (faltan 20 > 14): se informa en «carreras», sin aviso todavía
  KbStatus early = kb_evaluate(h, 80, 0, c);
  CHECK(flag(early, "A4_CARGA_BAJA_PRECARRERA") == nullptr && early.races.size() == 1 && !early.races[0].flagged);
  // 3) con un segundo día rápido (día 90) ya se llega al mínimo
  std::vector<KbDay> h2 = h; h2[45].gallop_m = 400;   // día 90
  CHECK(flag(kb_evaluate(h2, 90, 0, c), "A4_CARGA_BAJA_PRECARRERA") == nullptr);
  // 4) carrera fuera del horizonte (día 130) o ya pasada (día 85): no se evalúa
  c.planned_race_days = {130};
  CHECK(kb_evaluate(h, 90, 0, c).races.empty());
  c.planned_race_days = {85};
  CHECK(kb_evaluate(h, 90, 0, c).races.empty());
  // 5) historia que no cubre la ventana (empieza el día 80): no se juzga
  c.planned_race_days = {100};
  KbStatus nc = kb_evaluate(h, 90, 80, c);
  CHECK(nc.races.size() == 1 && !nc.races[0].covered && flag(nc, "A4_CARGA_BAJA_PRECARRERA") == nullptr);
  // 6) sesión de tipo CARRERA el día 98 sin fecha prevista: se juzga ese día con [70, 97] → 1 día rápido → AVISO
  KbRuleConfig c2;
  std::vector<KbDay> h3 = h; h3.back().race = true; h3.back().gallop_m = 1600;   // la carrera no cuenta para su propia ventana
  KbStatus sr = kb_evaluate(h3, 98, 0, c2);
  CHECK(sr.races.size() == 1 && !sr.races[0].planned && sr.races[0].days_to == 0 && sr.races[0].fast_days == 1);
  const KbFlag* fr = flag(sr, "A4_CARGA_BAJA_PRECARRERA");
  CHECK(fr && fr->text.find("carrera de hoy") != std::string::npos);
  // prevista y corrida el mismo día: una sola comprobación, origen SESION
  c2.planned_race_days = {98};
  KbStatus both = kb_evaluate(h3, 98, 0, c2);
  CHECK(both.races.size() == 1 && !both.races[0].planned);
  CHECK(kb_day_text(0) == "1970-01-01" && kb_day_text(20500) == "2026-02-16" && kb_day_text(19782) == "2024-02-29");
}
