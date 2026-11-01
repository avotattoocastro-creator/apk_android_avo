// AVO Track Work: entrenamiento sintético de un caballo de carreras con verdad analítica (velocidad, curvas, mano, zancada, montaje girado).
#include <cmath>
#include <random>
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/engine.h"
#include "avo_eq/json.h"
#include "eq_test.h"
#include "synth.h"

using namespace avoeq;

namespace {

const double PI = 3.14159265358979323846, G0 = 9.80665;

// Speed profile: trot, canter, acceleration, fast work, fade (fatigue), pull up, walk.
double race_v(double t) {
  if (t < 10) return 3.5;
  if (t < 30) return 9.0;
  if (t < 40) return 9.0 + 0.8 * (t - 30);
  if (t < 70) return 17.0;
  if (t < 85) return 17.0 - (2.5 / 15) * (t - 70);
  if (t < 95) return 14.5 - 0.85 * (t - 85);
  return 1.6;
}
double race_dv(double t) {
  if (t >= 30 && t < 40) return 0.8;
  if (t >= 70 && t < 85) return -2.5 / 15;
  if (t >= 85 && t < 95) return -0.85;
  return 0;
}
// Turn rate (rad/s, + right): right curve 15–25 s (r = 60 m at 9 m/s), left curve 45–60 s (r = 200 m at 17 m/s).
double race_w(double t) {
  if (t >= 15 && t < 25) return 9.0 / 60.0;
  if (t >= 45 && t < 60) return -17.0 / 200.0;
  return 0;
}
// True lead: +1 left, -1 right. Right lead until 30 s, left 30–62 s, right again after 62 s.
int race_lead(double t) { return t < 30 ? -1 : t < 62 ? 1 : -1; }
double stride_f(double v) { return v > 4.6 ? 1.75 + 0.04 * v : v > 2.2 ? 1.45 : 0.9; }

struct Mount { double m[3][3]; };
Mount mount() {   // sensor axes rotated: 170° about x, then 35° about z (girth not aligned with the horse)
  double a = 170 * PI / 180, b = 35 * PI / 180;
  double rx[3][3] = {{1, 0, 0}, {0, std::cos(a), -std::sin(a)}, {0, std::sin(a), std::cos(a)}};
  double rz[3][3] = {{std::cos(b), -std::sin(b), 0}, {std::sin(b), std::cos(b), 0}, {0, 0, 1}};
  Mount M;
  for (int i = 0; i < 3; i++) for (int j = 0; j < 3; j++) { M.m[i][j] = 0; for (int k = 0; k < 3; k++) M.m[i][j] += rz[i][k] * rx[k][j]; }
  return M;
}
// horse frame (forward, left, up) -> sensor frame: s = Mᵀ h
void to_sensor(const Mount& M, const double h[3], double s[3]) {
  for (int i = 0; i < 3; i++) s[i] = M.m[0][i] * h[0] + M.m[1][i] * h[1] + M.m[2][i] * h[2];
}

Session race_session(double secs, uint8_t units, double spike_t = -1, int lead_flip = 1) {
  Session s;
  s.session_id = "ENTRENO_SINT"; s.horse = "FLECHA";
  s.gnss = synth::track_fn(secs, 10, race_v, race_w, 0.05, 0.0, 5);
  s.imu_units = units;
  const double fs = 125, offset = -3.2, drift = 40e-6;
  Mount M = mount();
  std::mt19937 rng(11); std::normal_distribution<double> nz(0, 1); std::exponential_distribution<double> lat(1 / 0.012);
  size_t n = (size_t)((secs - 4) * fs);
  double phase = 0;
  uint32_t bseq = 0;
  const double acc_lsb = units == 1 ? 256.0 : 2048.0 / G0, gyr_lsb = units == 1 ? 512.0 : 1.0 / (0.07 * PI / 180);
  const double sat = units == 1 ? 8 * G0 * 256.0 : 32767;
  for (size_t b0 = 0; b0 < n; b0 += 20, bseq++) {
    double t_last = (std::min(n - 1, b0 + 19)) / fs;
    double rx = t_last + 1000.0 + 0.003 + lat(rng);
    for (size_t i = b0; i < std::min(n, b0 + 20); i++) {
      double t = i / fs, v = race_v(t), f = stride_f(v), w = race_w(t);
      phase += 2 * PI * f / fs;
      int L = race_lead(t) * lead_flip;
      double h[3], om[3];
      if (v > 4.6) {
        double Av = 6 + 0.25 * v;
        h[0] = race_dv(t) + 0.5 * Av * std::sin(phase + 1.3);
        h[1] = L * (0.35 * Av * std::sin(phase + 0.6) + 0.1 * Av * std::sin(2 * phase)) + v * (-w);
        h[2] = G0 + Av * std::sin(phase) + 0.35 * Av * std::sin(2 * phase + 0.4);
        om[0] = L * 0.3 * std::sin(phase + 0.9); om[1] = 0.4 * std::sin(phase + 0.2); om[2] = -w + 0.05 * std::sin(phase);
      } else if (v > 2.2) {
        h[0] = 1.0 * std::sin(2 * phase + 0.5); h[1] = 0.8 * std::sin(phase); h[2] = G0 + 4.0 * std::sin(2 * phase);
        om[0] = 0.2 * std::sin(phase); om[1] = 0.2 * std::sin(2 * phase); om[2] = -w;
      } else {
        h[0] = 0.5 * std::sin(phase); h[1] = 0.3 * std::sin(phase + 1); h[2] = G0 + 0.8 * std::sin(2 * phase);
        om[0] = 0.05 * std::sin(phase); om[1] = 0.05 * std::sin(phase); om[2] = -w;
      }
      if (spike_t > 0 && std::fabs(t - spike_t) < 0.012) h[2] += 5 * G0;
      for (int k = 0; k < 3; k++) { h[k] += 0.15 * nz(rng); om[k] += 0.01 * nz(rng); }
      double sa[3], sg[3];
      to_sensor(M, h, sa); to_sensor(M, om, sg);
      ImuSample x;
      x.imu_id = 0; x.batch_seq = bseq; x.index = (uint16_t)(i - b0);
      x.girth_us = (int64_t)std::llround(((t + offset) * (1 + drift)) * 1e6);
      x.chest_us = (uint64_t)std::llround(rx * 1e6);
      auto clamp = [&](double vv) { return (int16_t)std::lround(std::max(-sat, std::min(sat, vv))); };
      x.ax = clamp(sa[0] * acc_lsb); x.ay = clamp(sa[1] * acc_lsb); x.az = clamp(sa[2] * acc_lsb);
      x.gx = clamp(sg[0] * gyr_lsb); x.gy = clamp(sg[1] * gyr_lsb); x.gz = clamp(sg[2] * gyr_lsb);
      x.sync_state = 1;
      s.imu.push_back(x);
    }
  }
  return s;
}

const Stride* stride_at(const RacingResult& r, double t) {
  for (const auto& s : r.strides) if (s.t0 <= t && t < s.t1 + 1e-9) return &s;
  return nullptr;
}

EngineConfig psi() { EngineConfig c; breed_profile("PSI", &c.racing.breed); return c; }

}  // namespace

EQ_TEST(pista, profiles) {
  BreedProfile p;
  CHECK(breed_profile("PSI", &p) && p.name == "PSI" && p.fast_speed > 14);
  CHECK(breed_profile("ARABE", &p) && p.name == "ARABE" && p.work_speed < 11);
  CHECK(breed_profile("GENERICO", &p) && p.name == "GENERICO");
  CHECK(!breed_profile("PONI", &p));
}

EQ_TEST(pista, race_session_psi) {
  Session s = race_session(140, 1);
  Analysis a = analyse(s, psi());
  const RacingResult& r = a.racing;
  CHECK(r.has_imu && r.scale == "BNO085");
  CHECK(r.forward_sign_known);
  REPORT("calidad vertical %.3f, zancadas %zu, trabajos %zu\n", r.frame_quality, r.strides.size(), r.efforts.size());
  CHECK(r.frame_quality > 0.9);
  // efforts
  CHECK(r.efforts.size() == 1);
  if (!r.efforts.empty()) {
    const Effort& e = r.efforts[0];
    REPORT("trabajo %s %.0f m, vmax %.2f, últimos 200 m %.2f s, caída %.1f %%, f@vmax %.3f Hz, l@vmax %.2f m, b_f %.4f\n", e.type.c_str(), e.distance_m,
           e.vmax, e.last_200_s, e.fatigue_pct, e.sf_at_vmax, e.sl_at_vmax, e.sf_slope);
    CHECK(e.type == "TRABAJO_RAPIDO");
    CHECK_NEAR(e.vmax, 17.0, 0.2);
    CHECK(e.fatigue_pct > 12 && e.fatigue_pct < 35);
    CHECK_NEAR(e.sf_at_vmax, stride_f(17), 0.05);
    CHECK_NEAR(e.sl_at_vmax, 17 / stride_f(17), 0.3);
    CHECK_NEAR(e.sf_slope, 0.04, 0.015);
    CHECK_NEAR(e.sf_ref[0], stride_f(14), 0.06);
    CHECK_NEAR(e.sf_ref[1], stride_f(16), 0.06);
    CHECK(!e.sectionals.empty() && std::fabs(e.sectionals[0].to_m - 200) < 1e-9);
    CHECK(e.dist_above_90_m > 400);
  }
  CHECK_NEAR(r.best_200_s, 200 / 17.0, 0.2);
  CHECK(r.dist_fast_m > 500);
  // lead
  REPORT("mano: calibración %s, acuerdo %.2f, izq %d, dcha %d, cambios %d\n", r.lead_calibration.c_str(), r.lead_agreement, r.lead_left, r.lead_right, r.lead_changes);
  CHECK(r.lead_calibration == "CURVAS");
  CHECK(r.lead_agreement > 0.9);
  const Stride* s20 = stride_at(r, 20), *s50 = stride_at(r, 50), *s75 = stride_at(r, 75);
  CHECK(s20 && s20->lead == -1);
  CHECK(s50 && s50->lead == 1);
  CHECK(s75 && s75->lead == -1);
  for (const auto& e : r.events) if (e.type == "CAMBIO_DE_MANO") REPORT("cambio %.2f %s\n", e.t, e.detail.c_str());
  CHECK(r.lead_changes == 2);
  // turns: right curve 10 s at 0.15 rad/s, left curve 15 s at 0.085 rad/s
  REPORT("giros: izquierda %.0f°, derecha %.0f°\n", r.turns_total.left_deg, r.turns_total.right_deg);
  CHECK_NEAR(r.turns_total.right_deg, 10 * 0.15 * 180 / PI, 15);
  CHECK_NEAR(r.turns_total.left_deg, 15 * 0.085 * 180 / PI, 15);
  // intensity and trunk motion
  REPORT("VeDBA paso %.3f trote %.3f galope %.3f g; desplazamiento vertical a 17 m/s %.3f m\n", r.vedba_gait[0], r.vedba_gait[1], r.vedba_gait[2],
         s50 ? s50->vert_disp_m : NAN);
  CHECK(r.vedba_gait[2] > r.vedba_gait[1] && r.vedba_gait[1] > r.vedba_gait[0]);
  CHECK(s50 && s50->vert_disp_m > 0.05 && s50->vert_disp_m < 0.2);
  CHECK(r.vedba_load_gmin > 0);
  CHECK(r.saturated_samples == 0);
}

EQ_TEST(pista, impact_event_and_gravity_scale) {
  Session s = race_session(140, 0, 50.0);
  Analysis a = analyse(s, psi());
  const RacingResult& r = a.racing;
  CHECK(r.scale == "GRAVEDAD_ESTIMADA");
  CHECK_NEAR(r.g_lsb, 2048, 120);
  bool found = false;
  for (const auto& e : r.events) if (e.type == "IMPACTO_ATIPICO" && std::fabs(e.t - 50.0) < 1.0) found = true;
  CHECK(found);
  CHECK(r.efforts.size() == 1 && r.strides.size() > 100);
}

EQ_TEST(pista, lead_sign_option) {
  // Calibration in curves assumes the inside lead. A horse that gallops every curve on the OUTSIDE lead is
  // reported as inside lead (documented limitation); with the sign saved from a normal session it is right.
  Session normal = race_session(140, 1);
  Analysis a = analyse(normal, psi());
  double sign = a.racing.lead_sign_used;
  CHECK(sign == 1 || sign == -1);
  Session mirrored = race_session(140, 1, -1, -1);
  Analysis b = analyse(mirrored, psi());
  const Stride* m50 = stride_at(b.racing, 50);
  CHECK(m50 && m50->lead == 1);                 // inside-lead assumption
  EngineConfig c = psi(); c.racing.lead_sign = sign;
  Analysis d = analyse(mirrored, c);
  CHECK(d.racing.lead_calibration == "OPCION");
  const Stride* d50 = stride_at(d.racing, 50), *d20 = stride_at(d.racing, 20);
  CHECK(d50 && d50->lead == -1);                // the real (outside) lead
  CHECK(d20 && d20->lead == 1);
  CHECK(d.racing.wrong_lead_curve_pct > 80);
}

EQ_TEST(pista, gnss_only_and_json) {
  Session s = race_session(140, 1);
  s.imu.clear();
  EngineConfig c; breed_profile("ARABE", &c.racing.breed);
  Analysis a = analyse(s, c);
  CHECK(!a.racing.has_imu && a.racing.scale == "SIN_CINCHA");
  CHECK(a.racing.efforts.size() == 1);
  CHECK(a.racing.strides.empty());
  std::string js = to_json(a, s, c, false);
  json::Value v; std::string err;
  CHECK(json::parse(js, &v, &err));
  CHECK(v["trabajo_pista"]["perfil"]["raza"].str() == "ARABE");
  CHECK(v["trabajo_pista"]["trabajos"]["lista"][0]["tipo"].str() == "TRABAJO_RAPIDO");
  CHECK(v["procedencia"]["algoritmos"]["trabajo_pista"].str() == RACING_VERSION);
}

EQ_TEST(pista, chain_to_training_summary) {
  Session s = race_session(140, 1);
  EngineConfig c = psi();
  Analysis a = analyse(s, c);
  std::string js = to_json(a, s, c, true);
  char* out = nullptr;
  CHECK(avo_eq_training_summary(js.c_str(), "{\"fecha_utc\":\"2026-10-20\"}", &out) == 0);
  json::Value v; std::string err;
  CHECK(out && json::parse(out, &v, &err));
  const json::Value& rc = v["trabajo_pista"];
  CHECK(rc["raza"].str() == "PSI");
  CHECK(rc["trabajos_rapidos"].num() == 1);
  CHECK_NEAR(rc["v_max"].num(), 17, 0.2);
  CHECK_NEAR(rc["referencia"][0]["f_hz"].num(), stride_f(14), 0.06);
  CHECK(rc["mano"]["cambios"].num() == 2);
  // high-speed metres use the PSI threshold (15 m/s): ~30 s at 17 m/s plus part of the fade
  double hs = v["distancia_alta_velocidad_m"].num();
  REPORT("distancia > 15 m/s: %.0f m\n", hs);
  CHECK(hs > 30 * 17 * 0.9 && hs < 30 * 17 + 15 * 16.5);
  avo_eq_free(out);
}

namespace {
// Typical track morning: walk + trot warm-up (4 min), two fast repetitions (16 and 15 m/s) with a walk between, walk cool-down.
double morning_v(double t) {
  if (t < 120) return 1.6;
  if (t < 240) return 3.5;
  if (t < 250) return 3.5 + 1.25 * (t - 240);
  if (t < 280) return 16.0;
  if (t < 290) return 16.0 - 1.44 * (t - 280);
  if (t < 400) return 1.6;
  if (t < 410) return 1.6 + 1.34 * (t - 400);
  if (t < 440) return 15.0;
  if (t < 450) return 15.0 - 1.34 * (t - 440);
  return 1.6;
}
double straight(double) { return 0; }
}  // namespace

EQ_TEST(pista, training_morning_structure) {
  Session s;
  s.session_id = "MANANA"; s.horse = "FLECHA";
  s.gnss = synth::track_fn(600, 10, morning_v, straight, 0.03, 0.0, 8);
  EngineConfig c = psi();
  Analysis a = analyse(s, c);
  const RacingResult& r = a.racing;
  REPORT("repeticiones %d (rápidas %d), caída %.2f %%, recuperación media %.1f s, calentamiento %.0f s (paso %.0f, trote %.0f), calma %.0f s\n",
         r.reps, r.fast_reps, r.vmax_drop_pct, r.recovery_mean_s, r.warmup.duration_s, r.warmup.walk_s, r.warmup.trot_s, r.cooldown.duration_s);
  CHECK(r.reps == 2 && r.fast_reps == 2);
  CHECK_NEAR(r.vmax_drop_pct, 100.0 * (16 - 15) / 16, 1.0);
  CHECK(r.efforts.size() == 2);
  if (r.efforts.size() == 2) {
    // 16 -> 2.2 m/s at 1.44 m/s²: walk at 289.6 s; the effort ends when the speed falls below 11 m/s (~283.5 s)
    CHECK_NEAR(r.efforts[0].recovery_to_walk_s, 289.58 - 283.47, 0.6);
    CHECK_NEAR(r.efforts[0].pause_to_next_s, (400 + 9.4 / 1.34) - 283.47, 1.0);
    CHECK(std::isnan(r.efforts[1].pause_to_next_s));
  }
  CHECK(r.warmup.present && r.work.present && r.cooldown.present);
  CHECK_NEAR(r.warmup.duration_s, 240 + 7.5 / 1.25, 1.0);   // until the first effort starts (11 m/s at 246 s)
  CHECK(r.warmup.walk_s > 90 && r.warmup.trot_s > 90);
  CHECK(r.cooldown.duration_s > 140);
  CHECK(r.warmup_short);                                       // 4 min < 10 min reference
  std::string js = to_json(a, s, c, false);
  json::Value v; std::string err;
  CHECK(json::parse(js, &v, &err));
  CHECK(v["trabajo_pista"]["series"]["rapidas"].num() == 2);
  CHECK(v["trabajo_pista"]["fases"]["calentamiento"]["duracion_s"].num() > 200);
  char* out = nullptr;
  CHECK(avo_eq_training_summary(js.c_str(), "{\"fecha_utc\":\"2026-10-21\"}", &out) == 0);
  CHECK(out && json::parse(out, &v, &err));
  CHECK(v["trabajo_pista"]["sesion"]["rapidas"].num() == 2 && v["trabajo_pista"]["sesion"]["calentamiento_corto"].boolean());
  avo_eq_free(out);
}
