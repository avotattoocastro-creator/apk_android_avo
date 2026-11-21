// AVO Cardio 1.0.0: ECG de la cincha 0.5.x (MAX30003) → latidos, RR, FC, fases, V200, VHRmax, recuperación y
// candidatos a ectopia. Señales sintéticas con verdad analítica (independiente del detector): QRS rS con S dominante,
// onda T grande, ruido, deriva de línea base y artefacto de movimiento; el lote se codifica con el codificador REAL
// de la cincha (firmware/girth/V0_5_0, girth::encode_ecg_batch) y pasa por avo_core → RAW → ingestión → motor.
#include <cmath>
#include <random>
#include <string>
#include <vector>
#include "avo_eq/cardio.h"
#include "avo_eq/engine.h"
#include "avo_eq/ingestion.h"
#include "avo_eq/json.h"
#include "avo_eq/training.h"
#include "eq_test.h"
#include "raw_writer.h"
#include "synth.h"
// El codificador del lote fmt 2 es el del firmware de la cincha (fuente única del formato).
// MSVC define OVERFLOW (math.h) como macro y choca con girth::max30003::OVERFLOW: se aparta solo aquí.
#ifdef OVERFLOW
#pragma push_macro("OVERFLOW")
#undef OVERFLOW
#define AVO_TEST_RESTORE_OVERFLOW
#endif
#include "../../firmware/girth/V0_5_0/AVO_GIRTH_V0_5_0/girth_ecg.cpp"
#ifdef AVO_TEST_RESTORE_OVERFLOW
#pragma pop_macro("OVERFLOW")
#endif

using namespace avoeq;

namespace {
const double FS = 512.0;

// ---- modelo sintético: velocidad por tramos y FC con retraso de primer orden
double speed_profile(double t) {
  if (t < 120) return 1.5;
  if (t < 420) return 4.0;
  if (t < 480) return 8.0;
  if (t < 540) return 12.0;
  if (t < 600) return 15.0;
  if (t < 660) return 17.0;
  if (t < 700) return 17.0 - 14.0 * (t - 660) / 40.0;
  return 1.5;
}
double no_turn(double) { return 0.0; }
double hr_target(double v) { return 60.0 + 9.0 * v; }   // V200 real = 140/9 = 15,556 m/s; VHRmax a 213 lpm = 17,0 m/s

struct Truth { std::vector<double> beats; std::vector<int> ectopic; double t_cross = NAN; double hr_max = 0; };

// FC integrada a 100 Hz: sube con τ 10 s, baja con τ 60 s.
std::vector<double> hr_series(double secs, std::vector<double>* tt) {
  std::vector<double> h; double hr = hr_target(speed_profile(0));
  for (double t = 0; t <= secs; t += 0.01) {
    double tg = hr_target(speed_profile(t));
    double tau = tg > hr ? 10.0 : 60.0;
    hr += (tg - hr) * 0.01 / tau;
    h.push_back(hr); tt->push_back(t);
  }
  return h;
}

// Latidos sinusales con prematuros insertados (RR × factor; pausa compensadora completa).
Truth make_beats(double secs) {
  Truth tr;
  std::vector<double> tt; std::vector<double> hh = hr_series(secs, &tt);
  auto hr_at = [&](double t) { size_t i = std::min(hh.size() - 1, (size_t)std::max(0.0, t / 0.01)); return hh[i]; };
  struct Ins { double t; double f; int n; };
  const std::vector<Ins> ins = {{300, 0.80, 1}, {450, 0.85, 2}, {630, 0.85, 1}, {900, 0.80, 1}};
  size_t next = 0;
  double t = 2.0;
  while (t < secs - 2) {
    double rr = 60.0 / hr_at(t);
    if (next < ins.size() && t >= ins[next].t) {
      for (int k = 0; k < ins[next].n; k++) { t += rr * ins[next].f; tr.beats.push_back(t); tr.ectopic.push_back(1); }
      t += rr * (1.0 + ins[next].n * (1.0 - ins[next].f));   // pausa compensadora
      tr.beats.push_back(t); tr.ectopic.push_back(0);
      next++;
      continue;
    }
    t += rr; tr.beats.push_back(t); tr.ectopic.push_back(0);
    tr.hr_max = std::max(tr.hr_max, 60.0 / rr);
    if (std::isnan(tr.t_cross) && hr_at(t) >= 200) tr.t_cross = t;
  }
  return tr;
}

// ECG equino de la cincha (mV) en el tiempo t (GNSS): r pequeña, S dominante negativa, T grande positiva.
double ecg_mv(double t, const std::vector<double>& beats, size_t* hint, double motion) {
  double y = 0;
  while (*hint + 1 < beats.size() && beats[*hint + 1] < t - 1.0) (*hint)++;
  for (size_t k = *hint; k < beats.size() && beats[k] < t + 0.5; k++) {
    double b = beats[k];
    double rr = k ? std::min(1.5, b - beats[k - 1]) : 1.0;
    double dr = t - (b - 0.02), ds = t - b;
    double tc = b + 0.08 + 0.30 * rr, ts = 0.025 + 0.02 * rr, dt = t - tc;
    y += 0.25 * std::exp(-dr * dr / (2 * 0.008 * 0.008)) - 1.5 * std::exp(-ds * ds / (2 * 0.010 * 0.010)) + 0.9 * std::exp(-dt * dt / (2 * ts * ts));
  }
  y += 0.3 * std::sin(2 * synth::PI * 0.3 * t) + motion * std::sin(2 * synth::PI * 2.1 * t + 0.4);
  return y;
}

struct EcgSpec { double drift_ppm = 50, offset_s = -3.2, noise_mv = 0.03; double gap_t0 = 200, gap_t1 = 203; unsigned seed = 7; };

// Lotes de 51 muestras con el codificador de la cincha; reloj de la cincha = (t_gnss + offset)(1 + deriva).
std::vector<eqfix::ExtraFrame> ecg_frames(double secs, const Truth& tr, const EcgSpec& sp) {
  std::mt19937 rng(sp.seed); std::normal_distribution<double> nz(0, 1); std::exponential_distribution<double> lat(1.0 / 0.012);
  std::vector<eqfix::ExtraFrame> out;
  const double per_g = 1.0 / FS;   // periodo en el reloj de la cincha
  const double g0 = (0.0 + sp.offset_s + 10.0) * (1 + sp.drift_ppm * 1e-6);
  size_t total = (size_t)((secs - 11.0) * FS), hint = 0;
  uint32_t batch = 0;
  for (size_t k0 = 0; k0 + 51 <= total; k0 += 51) {
    int32_t duv[51];
    double t_last = 0;
    for (int i = 0; i < 51; i++) {
      double g = g0 + (k0 + i) * per_g;
      double t = g / (1 + sp.drift_ppm * 1e-6) - sp.offset_s;
      t_last = t;
      double v = speed_profile(t);
      double mv = ecg_mv(t, tr.beats, &hint, v > 10 ? 0.25 : 0.05) + sp.noise_mv * nz(rng);
      duv[i] = (t >= sp.gap_t0 && t < sp.gap_t1) ? girth::ECG_INVALID : (int32_t)std::lround(mv * 1e4);
    }
    girth::EcgMeta m; m.batch = ++batch;
    m.t0_us = (uint32_t)std::llround((g0 + k0 * per_g) * 1e6); m.period_us = 1953;
    uint8_t body[256];
    size_t n = girth::encode_ecg_batch(m, duv, 51, body, sizeof(body));
    eqfix::ExtraFrame f; f.chest_us = (uint64_t)std::llround((t_last + 1000.0 + 0.003 + lat(rng)) * 1e6);
    f.payload.assign(body, body + n);
    out.push_back(f);
    if (batch == 40) out.push_back(f);   // reintento de radio: el lote llega dos veces
  }
  return out;
}

Session session_with_ecg(const char* path, double secs, const Truth& tr, const EcgSpec& sp, std::string* err) {
  Session s; s.session_id = "S_ECG";
  s.gnss = synth::track_fn(secs, 10.0, speed_profile, no_turn);
  std::vector<eqfix::ExtraFrame> fr = ecg_frames(secs, tr, sp);
  remove(path);
  eqfix::write_raw(path, s, true, &fr);
  Session in;
  ingest_raw({path}, &in, err);
  remove(path);
  return in;
}
}  // namespace

EQ_TEST(cardio, girth_fmt2_batch_reaches_the_session) {
  Truth tr; for (int k = 0; k < 40; k++) tr.beats.push_back(2.0 + k * 1.5);
  EcgSpec sp; sp.gap_t0 = 20; sp.gap_t1 = 21;
  std::string err;
  Session s = session_with_ecg("eq_ecg_ing.avo", 60, tr, sp, &err);
  CHECK(!s.ecg.empty());
  CHECK(s.ecg_duplicates == 1);
  CHECK(s.bad_records == 0);
  if (!s.ecg.empty()) {
    CHECK(s.ecg[0].duv.size() == 51);
    CHECK_NEAR(s.ecg[0].period_us, 1953.125, 1e-9);   // cabecera 1953 → periodo exacto de 512 muestras/s
    size_t inv = 0; for (const auto& b : s.ecg) for (int32_t v : b.duv) inv += v == ECG_INVALID_DUV;
    CHECK(inv >= 500 && inv <= 520);                   // 1 s sin electrodos = 512 muestras
  }
}

EQ_TEST(cardio, detector_anchored_in_s_rejects_t_waves) {
  // 20 s a 40 lpm y 20 s a 220 lpm, T grande: el detector no debe contar la T ni perder latidos.
  std::vector<double> beats;
  for (double t = 0.5; t < 20; t += 1.5) beats.push_back(t);
  for (double t = 20.2; t < 40; t += 60.0 / 220) beats.push_back(t);
  std::mt19937 rng(3); std::normal_distribution<double> nz(0, 1);
  std::vector<double> x; size_t hint = 0;
  for (size_t i = 0; i < (size_t)(40 * FS); i++) x.push_back(ecg_mv(i / FS, beats, &hint, 0.2) + 0.03 * nz(rng));
  CardioConfig c; int pol = 0;
  std::vector<EcgBeat> d = detect_beats(x, FS, c, &pol);
  CHECK(pol == -1);   // S negativa
  int tp = 0; double err_sum = 0;
  for (double b : beats) {
    if (b < 0.3 || b > 39.7) continue;
    for (const auto& e : d) if (std::fabs(e.t_girth - b) < 0.01) { tp++; err_sum += std::fabs(e.t_girth - b); break; }
  }
  int truth_n = 0; for (double b : beats) if (b >= 0.3 && b <= 39.7) truth_n++;
  CHECK(tp == truth_n);
  CHECK((int)d.size() <= truth_n + 1);
  CHECK(tp > 0 && err_sum / tp < 0.002);   // < 2 ms (resolución de 1,95 ms con interpolación)
}

EQ_TEST(cardio, sinus_acceleration_is_not_ectopy) {
  // FC de 100 a 220 lpm en 30 s y vuelta a 120 en 60 s: ningún candidato.
  std::vector<EcgBeat> b; double t = 0;
  while (t < 120) {
    double hr = t < 10 ? 100 : t < 40 ? 100 + 4 * (t - 10) : t < 60 ? 220 : std::max(120.0, 220 - (t - 60) * 100.0 / 60);
    t += 60.0 / hr; EcgBeat e; e.t = t; b.push_back(e);
  }
  CardioConfig c; CardioResult r;
  analyse_rr(b, {}, {}, {}, 0, 120, c, &r);
  CHECK(r.candidates == 0);
  CHECK_NEAR(r.hr_peak, 220, 1.0);
  CHECK(r.quality == "BUENA");
  CHECK(std::isnan(r.v200.value));   // sin GNSS no hay velocidad
  CHECK(!std::isnan(r.v200.t_cross));
}

EQ_TEST(cardio, rr_series_v200_crossing_and_ectopy_thresholds) {
  // Serie RR pura (la parte del motor que no depende del contrato): 200 lpm alcanzados a t = 60 s y mantenidos.
  std::vector<EcgBeat> b; double t = 0; std::vector<double> gt, gv;
  for (double x = 0; x <= 200; x += 0.1) { gt.push_back(x); gv.push_back(x < 60 ? 10.0 + x / 20 : x < 120 ? 16.0 : 2.0); }
  int k = 0;
  while (t < 200) {
    double hr = t < 60 ? 150 + 50 * t / 60 : t < 120 ? 205 : 90;
    double rr = 60.0 / hr;
    if (k == 300) rr *= 0.93;          // 7 % más corto con FC > 100: candidato (umbral 6 %)
    if (k == 301) rr *= 1.07;
    if (k == 330) rr *= 0.945;         // 5,5 %: solo con el umbral del 5 %
    if (k == 331) rr *= 1.055;
    if (k == 360) rr *= 0.96;          // 4 %: nunca
    t += rr; EcgBeat e; e.t = t; b.push_back(e); k++;
  }
  CardioConfig c; CardioResult r;
  analyse_rr(b, gt, gv, {}, 0, 200, c, &r);
  CHECK(r.candidates == 1 && r.isolated == 1);
  CHECK_NEAR(r.v200.t_cross, 60, 1.5);
  CHECK_NEAR(r.v200.value, 16.0, 0.05);
  CHECK(r.v200.method == V200_METHOD_CROSSING);
  CHECK(!r.v200.warmup_ok);  // 690 m y 60 s antes del cruce: calentamiento corto (WU1)
  CardioConfig c5 = c; c5.premature_pct = 5.0; CardioResult r5;
  analyse_rr(b, gt, gv, {}, 0, 200, c5, &r5);
  CHECK(r5.candidates == 2);   // con el 5 % entra el de 5,5 %; el de 4 % sigue fuera
}

EQ_TEST(cardio, full_session_v200_vhrmax_phases_recovery_ectopy) {
  const double secs = 1620;
  Truth tr = make_beats(secs);
  EcgSpec sp;
  std::string err;
  Session s = session_with_ecg("eq_ecg_full.avo", secs, tr, sp, &err);
  CHECK(s.ecg.size() > 1000);
  Analysis a = analyse(s);
  const CardioResult& r = a.cardio;
  CHECK(r.present && r.aligned_gnss);
  CHECK_NEAR(r.fs_hz, 512.0, 1e-6);
  // detector: sensibilidad y VPP frente a la verdad (fuera del hueco sin electrodos), error de tiempo
  int truth_n = 0, tp = 0; std::vector<double> errs;
  for (double b : tr.beats) {
    if (b < 11 || b > secs - 13 || (b > sp.gap_t0 - 0.5 && b < sp.gap_t1 + 0.5)) continue;
    truth_n++;
    for (const auto& e : r.beats) if (std::fabs(e.t - b) < 0.012) { tp++; errs.push_back(e.t - b); break; }
  }
  int det_n = 0; for (const auto& e : r.beats) if (e.t >= 11 && e.t <= secs - 13 && !(e.t > sp.gap_t0 - 0.5 && e.t < sp.gap_t1 + 0.5)) det_n++;
  CHECK(truth_n > 1500);
  CHECK(tp >= 0.995 * truth_n);
  CHECK(det_n <= tp + truth_n * 0.005);
  // reloj de la cincha → GNSS: deriva de 50 ppm y latencia variable corregidas por la envolvente inferior; queda el sesgo
  // fijo inobservable entre las latencias mínimas de la cincha (3 ms) y del GNSS (8 ms) = −5 ms, igual que en la IMU.
  double bias = 0; for (double e : errs) bias += e; bias /= std::max<size_t>(1, errs.size());
  double spread = 0; for (double e : errs) spread += std::fabs(e - bias); spread /= std::max<size_t>(1, errs.size());
  CHECK_NEAR(bias, -0.005, 0.0015);
  CHECK(spread < 0.0015);
  // el hueco de 3 s no ciega al detector: hay latidos en el primer segundo después
  bool after_gap = false; for (const auto& e : r.beats) if (e.t > sp.gap_t1 + 0.2 && e.t < sp.gap_t1 + 1.5) after_gap = true;
  CHECK(after_gap);
  CHECK(r.quality == "BUENA" || r.quality == "UTILIZABLE");
  // FC pico y fases
  CHECK_NEAR(r.hr_peak, 213.0, 2.0);
  CHECK(r.phases[PH_MAX].duration_s > 60);
  CHECK(r.phases[PH_MAX].interpretable);
  CHECK_NEAR(r.effort_end_t, 685, 5.1);
  CHECK(r.phases[PH_REC_EARLY].duration_s == 120.0);
  CHECK(!std::isnan(r.below_120_after_s));
  CHECK(r.cooldown_class == "PASO");
  // V200: cruce de 200 lpm mantenido 10 s (meseta de 17 m/s) y, aparte, la regresión FC–velocidad (15,56 m/s)
  CHECK(r.v200.method == V200_METHOD_CROSSING);
  CHECK_NEAR(r.v200.t_cross, tr.t_cross, 1.5);
  CHECK_NEAR(r.v200.value, 17.0, 0.1);
  CHECK(r.v200.warmup_ok);
  CHECK(r.v200_regression.method == V200_METHOD_REGRESSION);
  CHECK(r.v200_regression.points >= 4);
  CHECK(r.v200_regression.r2 >= 0.99);
  CHECK_NEAR(r.v200_regression.value, 140.0 / 9.0, 0.15);
  CHECK_NEAR(r.v200_regression.slope, 9.0, 0.3);
  CHECK(r.vhrmax.method == V200_METHOD_REGRESSION);
  CHECK_NEAR(r.vhrmax.value, 17.0, 0.3);
  // recuperación: baja con el tiempo
  CHECK(r.recovery.size() == 6);
  if (r.recovery.size() == 6) {
    CHECK(!std::isnan(r.recovery[0].hr) && !std::isnan(r.recovery[5].hr));
    CHECK(r.recovery[0].hr > r.recovery[1].hr && r.recovery[1].hr > r.recovery[4].hr && r.recovery[4].hr > r.recovery[5].hr);
    CHECK(r.recovery[5].drop > 100);
  }
  // ectopia: 5 prematuros insertados (3 aislados y 1 pareja), todos candidatos a revisar; INFO (≤ 10 con FC > 100)
  CHECK(r.candidates == 5);
  CHECK(r.isolated == 3 && r.pairs == 1 && r.triplets == 0 && r.runs == 0);
  CHECK(r.ectopy_level == "INFO");
  CHECK(r.phases[PH_MAX].candidates == 1);
  // JSON del análisis
  std::string js = to_json(a, s, EngineConfig(), false);
  json::Value v; std::string je;
  CHECK(json::parse(js, &v, &je));
  CHECK(v["cardio"]["presente"].boolean(false));
  CHECK(v["cardio"]["v200"]["metodo"].str() == "CRUCE_200_10S");
  CHECK(!v["cardio"]["v200"]["validada"].boolean(true));
  CHECK(v["cardio"]["ectopia"]["tipo"].str() == "CANDIDATO_A_REVISAR");
  CHECK(!v["cardio"]["ectopia"]["diagnostico"].boolean(true));
  // resumen de entrenamiento: V200 y ectopia pasan al historial
  SessionSummary ss; TrainingConfig tc;
  CHECK(training_summary_from_analysis(v, tc, &ss, &je));
  CHECK_NEAR(ss.cardio.v200, 17.0, 0.1);
  CHECK(ss.cardio.v200_method == "CRUCE_200_10S");
  CHECK(ss.cardio.ectopy_candidates == 5);
  json::Value back; CHECK(json::parse(training_summary_to_json(ss), &back, &je));
  SessionSummary s2; CHECK(training_summary_from_json(back, &s2, &je));
  CHECK_NEAR(s2.cardio.v200, ss.cardio.v200, 1e-9);
  CHECK(s2.cardio.v200_method == ss.cardio.v200_method && s2.cardio.ectopy_level == ss.cardio.ectopy_level);
}

EQ_TEST(cardio, session_without_ecg_has_empty_block) {
  Session s; s.gnss = synth::track_fn(60, 10.0, speed_profile, no_turn);
  Analysis a = analyse(s);
  CHECK(!a.cardio.present);
  CHECK(cardio_json(a.cardio, CardioConfig(), true).find("\"presente\":false") != std::string::npos);
}

// A9: V200 por debajo de la línea base propia con el TE por defecto del 3 % (NO VALIDADO) y VT2 (salto > 5 % en ≤ 31 d).
EQ_TEST(cardio, a9_v200_drop_against_own_baseline) {
  auto mk = [](int i, double v200) {
    SessionSummary s; s.id = "S" + std::to_string(i); s.horse = "H";
    char d[32]; snprintf(d, sizeof(d), "2026-09-%02d", i + 1); s.date_utc = d; s.surface = "arena";
    s.cardio.present = true; s.cardio.v200 = v200; s.cardio.v200_method = V200_METHOD_CROSSING;
    s.moving_s = 1800; s.distance_m = 8000;
    return s;
  };
  std::vector<SessionSummary> h;
  const double base[] = {15.0, 15.1, 14.95, 15.05, 15.0, 15.1, 14.9, 15.0};
  for (int i = 0; i < 8; i++) h.push_back(mk(i, base[i]));
  TrainingConfig c;
  TrainingResult ok = analyse_training(h, "2026-09-09", c);
  bool a9 = false; for (const auto& f : ok.sessions.back().kb.flags) if (f.rule == "A9_PERDIDA_FORMA") a9 = true;
  CHECK(!a9);
  // tres sesiones con la V200 un 8 % más baja: umbral 2·TE·√(1 + 1/n) con TE 3 % ≈ 6,3 %
  for (int i = 8; i < 11; i++) h.push_back(mk(i, 13.8));
  TrainingResult bad = analyse_training(h, "2026-09-12", c);
  const KbFlag* f = nullptr; const KbFlag* jump = nullptr;
  for (const auto& x : bad.sessions.back().kb.flags) { if (x.rule == "A9_PERDIDA_FORMA") f = &x; }
  for (const auto& s : bad.sessions) for (const auto& x : s.kb.flags) if (x.rule == "A9_V200_SALTO") jump = &x;
  CHECK(f != nullptr);
  if (f) CHECK(f->text.find("NO VALIDADO") != std::string::npos);
  CHECK(jump != nullptr);   // el primer salto de 15 → 13,8 m/s (−8 %) en 1 día
  // otro método (regresión) no se compara con el cruce
  std::vector<SessionSummary> mix = h;
  for (int i = 8; i < 11; i++) mix[i].cardio.v200_method = V200_METHOD_REGRESSION;
  TrainingResult m = analyse_training(mix, "2026-09-12", c);
  bool a9m = false; for (const auto& x : m.sessions.back().kb.flags) if (x.rule == "A9_PERDIDA_FORMA") a9m = true;
  CHECK(!a9m);
}

// Puerta de calidad por fase (Ter Woort 2023): con > 10 % de artefacto la fase es NO_INTERPRETABLE y sus candidatos
// no suben el nivel aunque sean muchos.
EQ_TEST(cardio, phase_quality_gate_blocks_escalation) {
  std::vector<EcgBeat> b; std::vector<double> gt, gv; double t = 0; int k = 0;
  for (double x = 0; x <= 400; x += 0.1) { gt.push_back(x); gv.push_back(x < 100 ? 5 : x < 200 ? 16 : 1.5); }
  while (t < 400) {
    double hr = t < 100 ? 120 : t < 200 ? 210 : 80;
    double rr = 60.0 / hr;
    if (t > 120 && t < 190 && k % 20 == 0) rr *= 0.85;      // 12+ prematuros en la fase máxima
    else if (t > 120 && t < 190 && k % 20 == 1) rr *= 1.15;
    t += rr; EcgBeat e; e.t = t; b.push_back(e); k++;
  }
  CardioConfig c;
  CardioResult ok; analyse_rr(b, gt, gv, {}, 0, 400, c, &ok);
  CHECK(ok.phases[PH_MAX].interpretable);
  CHECK(ok.phases[PH_MAX].candidates_hr100 > 10);
  CHECK(ok.ectopy_level == "VIGILAR");
  // 15 s sin señal dentro de la fase máxima (~100 s): > 10 % de artefacto
  CardioResult gated; analyse_rr(b, gt, gv, {{150.0, 165.0}}, 0, 400, c, &gated);
  CHECK(!gated.phases[PH_MAX].interpretable);
  CHECK(gated.ectopy_level == "INFO");
  CHECK(gated.candidates > 0);   // se siguen contando como candidatos a revisar
}
