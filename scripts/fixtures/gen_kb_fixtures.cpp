// Generador de las fixtures SINTÉTICAS de la pantalla «Base científica» (KB-1) de las apps:
//   core/src/test/resources/equine/kb_psi_analysis.json        (análisis completo, sin series, de race_session(140 s) con perfil PSI)
//   core/src/test/resources/equine/kb_training_history_psi.json (avo-training-analysis de 34 sesiones en 100 días con A1, A2, A3 y FO 7 d)
// Copias para el iPad en ipad/AVOiPadTests/Fixtures/. Generadas con el motor 2.0.0-dev26 (KB-1 1.24.0) el 21/11/2026.
// La primera parte es copia literal de equine-intelligence/tests/test_racing.cpp (líneas 1–114, sin eq_test.h).
// Uso (desde la raíz del repositorio):
//   cmake -S equine-intelligence -B /tmp/eqb -DCMAKE_BUILD_TYPE=Release && make -C /tmp/eqb avo_eq
//   g++ -std=c++17 -O1 -Iequine-intelligence/include -Iequine-intelligence/tests scripts/fixtures/gen_kb_fixtures.cpp \
//       -L/tmp/eqb -lavo_eq -o /tmp/gen_kb && /tmp/gen_kb core/src/test/resources/equine
// No son datos de caballos reales: solo prueban la cadena JSON del motor → modelos de las apps.
// AVO Track Work: entrenamiento sintético de un caballo de carreras con verdad analítica (velocidad, curvas, mano, zancada, montaje girado).
#include <cmath>
#include <random>
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/engine.h"
#include "avo_eq/json.h"
#include "avo_eq/training.h"
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
#include <cstdio>
#include <fstream>
int main(int argc, char** argv) {
  std::string dir = argv[1];
  Session s = race_session(140, 1);
  EngineConfig c = psi();
  Analysis a = analyse(s, c);
  std::string js = to_json(a, s, c, false);
  { std::ofstream f(dir + "/kb_psi_analysis.json", std::ios::binary); f << js; }
  json::Value v; std::string err;
  if (!json::parse(js, &v, &err)) { fprintf(stderr, "parse %s\n", err.c_str()); return 1; }
  TrainingConfig tc;
  SessionSummary base;
  if (!training_summary_from_analysis(v, tc, &base, &err)) { fprintf(stderr, "summary %s\n", err.c_str()); return 1; }
  std::vector<SessionSummary> ss;
  for (int d = 0; d < 100; d += 3) {
    SessionSummary x = base;
    x.id = "KB_PSI_" + std::to_string(d); x.horse = "FLECHA"; x.date_utc = training_day_text(20500 + d) + "T09:00:00Z";
    bool late = d >= 70;
    x.race.kb_race_pace = 16.7;
    x.race.kb_band_m[0] = late ? 3200 : 1500; x.race.kb_band_m[1] = late ? 500 : 150; x.race.kb_band_m[2] = (late && d % 2 == 0) ? 900 : 0;
    x.race.kb_canter_m = late ? 4800 : 1500; x.race.kb_gallop_m = (d % 9 == 0 || (late && d % 2 == 0)) ? (late ? 900 : 300) : 0;
    x.race.kb_bone_pct = late ? 2.4 : 0.6; x.race.kb_bone_low_pct = late ? 3.0 : 1.4; x.race.kb_strides = late ? 900 : 300;
    ss.push_back(x);
  }
  TrainingResult r = analyse_training(ss, "", tc);
  { std::ofstream f(dir + "/kb_training_history_psi.json", std::ios::binary); f << training_to_json(r, tc); }
  printf("ok %zu sesiones, %zu reglas\n", ss.size(), r.kb.flags.size());
  for (auto& f : r.kb.flags) printf("  %s %s %s\n", f.rule.c_str(), f.level.c_str(), f.action.c_str());
  return 0;
}
