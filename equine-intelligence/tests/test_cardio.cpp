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
  // CG1 (KB 1.30.0): 60 s a 205 lpm (60–120 s) por encima de 200 y de 180; cobertura completa
  CHECK_NEAR(r.trimp.s_above_z2, 60, 6);
  CHECK(r.trimp.s_above_z1 >= r.trimp.s_above_z2);
  CHECK_NEAR(r.trimp_coverage, 1.0, 0.05);
  CHECK(std::isfinite(r.trimp.trimp) && r.trimp.trimp > r.trimp.trimp_unweighted);
  double hs = 0; for (double x : r.hr_hist) hs += x;
  CHECK_NEAR(hs / 60.0, r.trimp.minutes, 1e-9);
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
  // cinética (cardio 1.2.0): el modelo baja la FC con τ 60 s hacia 60 + 9·1,5 = 73,5 lpm; el calentamiento acaba en la
  // primera época ≥ 60 % de 17 m/s (la meseta de 12 m/s, t = 480 s) e incluye la de 8 m/s: desde el inicio del ECG (t0)
  // son 1,5·(120 − t0) + 4·300 + 8·60 m (WU1 suficiente); tramo fijo al trote a 4 m/s; CF1 en las mesetas de 8–17 m/s
  CHECK_NEAR(r.tau.tau_s, 60.0, 6.0);
  CHECK_NEAR(r.tau.asymptote, 73.5, 3.0);
  CHECK(std::isfinite(r.thr100_s) && r.thr100_s > r.below_120_after_s);
  CHECK_NEAR(r.warmup.t0 + r.warmup.duration_s, 480, 5.1);
  CHECK_NEAR(r.warmup.distance_m, 1.5 * (120 - r.warmup.t0) + 1200 + 480, 30);
  CHECK(r.warmup.sufficient);
  CHECK_NEAR(r.fixed_warmup.speed, 4.0, 0.05);
  CHECK(r.cf1_plateaus >= 3);
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
  const json::Value& ci = v["cardio"]["carga_interna"];   // CG1 (KB 1.30.0)
  CHECK(ci["regla"].str() == "CG1" && !ci["validado"].boolean(true));
  CHECK(ci["trimp"].type == json::Value::NUM && ci["trimp"].n > 0);
  CHECK(ci["fc_max_origen"].str() == "POR_DEFECTO" && ci["etiquetas"]["coeficientes"].str() == "NV");
  CHECK(!ci["histograma_fc"]["s"].a.empty());
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
  CHECK(!ss.cardio.hr_hist.empty() && s2.cardio.hr_hist.size() == ss.cardio.hr_hist.size());
  CHECK_NEAR(s2.cardio.trimp, ss.cardio.trimp, 1e-4 * ss.cardio.trimp);
  CHECK_NEAR(s2.cardio.trimp_coverage_pct, ss.cardio.trimp_coverage_pct, 1e-3);
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

// Cinética de la FC (cardio 1.2.0, KB 1.33.0): WU2, FW1, CF2 y RC1 con verdad analítica.
// Calentamiento: 0–100 s parado a 110 lpm (FC alta sin velocidad solo si ≥ 120: aquí no), 100–700 s al trote a 4 m/s y
// 100 lpm; 700–760 s a 16 m/s y 205 lpm; desde 760 s al paso (1,5 m/s) con FC = 70 + 135·e^(−(t−760)/90).
// THR100 = 90·ln(135/30) = 135,4 s; τ = 90 s y asíntota 70 lpm; calentamiento 700 s y 100·0 + 600·4 = 2400 m.
EQ_TEST(cardio, kinetics_warmup_fixed_segment_tau_thr100) {
  std::vector<EcgBeat> b; std::vector<double> gt, gv; double t = 0;
  auto hr_at = [](double x) { return x < 100 ? 110.0 : x < 700 ? 100.0 : x < 760 ? 205.0 : 70.0 + 135.0 * std::exp(-(x - 760) / 90.0); };
  auto v_at = [](double x) { return x < 100 ? 0.0 : x < 700 ? 4.0 : x < 760 ? 16.0 : 1.5; };
  for (double x = 0; x <= 1500; x += 0.1) { gt.push_back(x); gv.push_back(v_at(x)); }
  while (t < 1500) { t += 60.0 / hr_at(t); EcgBeat e; e.t = t; b.push_back(e); }
  CardioConfig c; CardioResult r;
  analyse_rr(b, gt, gv, {}, 0, 1500, c, &r);
  CHECK_NEAR(r.effort_end_t, 760, 0.1);
  // RC1
  CHECK_NEAR(r.thr100_s, 90.0 * std::log(135.0 / 30.0), 3.0);
  // CF2
  CHECK(std::isfinite(r.tau.tau_s));
  CHECK_NEAR(r.tau.tau_s, 90.0, 3.0);
  CHECK_NEAR(r.tau.asymptote, 70.0, 1.0);
  CHECK(r.tau.r2 > 0.99);
  CHECK(r.tau.points >= 100);
  CHECK(r.cooldown_class == "PASO");
  // WU2
  CHECK(r.warmup.origin == "VELOCIDAD");
  CHECK_NEAR(r.warmup.duration_s, 700, 0.1);
  CHECK_NEAR(r.warmup.distance_m, 2400, 5);
  CHECK(r.warmup.sufficient);
  CHECK_NEAR(r.warmup.high_hr_still_s, 0, 1e-9);
  // FW1: últimos 60 s al trote (640–700 s) a 4 m/s y 100 lpm
  CHECK_NEAR(r.fixed_warmup.t0, 640, 0.1);
  CHECK_NEAR(r.fixed_warmup.hr, 100, 0.5);
  CHECK_NEAR(r.fixed_warmup.speed, 4.0, 0.01);
  // con el umbral de FC alta a 105 lpm, los 100 s parados a 110 lpm cuentan y salen como aviso
  CardioConfig c2 = c; c2.wu_high_hr_bpm = 105; CardioResult r2;
  analyse_rr(b, gt, gv, {}, 0, 1500, c2, &r2);
  CHECK_NEAR(r2.warmup.high_hr_still_s, 100, 5.1);
  bool warn = false; for (const auto& w : r2.warnings) if (w.find("WU2") != std::string::npos) warn = true;
  CHECK(warn);
  // JSON: bloque «cinetica» con etiquetas y nulls coherentes
  r.present = true;   // analyse_rr no marca el bloque como presente (lo hace analyse_cardio)
  std::string js = cardio_json(r, c, false);
  json::Value v; std::string je;
  CHECK(json::parse(js, &v, &je));
  const json::Value& k = v["cinetica"];
  CHECK(!k["validado"].boolean(true));
  CHECK(k["calentamiento"]["regla"].str() == "WU2" && k["calentamiento"]["suficiente"].boolean(false));
  CHECK(k["tramo_fijo"]["regla"].str() == "FW1" && k["tramo_fijo"]["fuente"].str() == "YAMANOBE_1993_JRA");
  CHECK_NEAR(k["recuperacion_tau"]["tau_s"].num(0), 90.0, 3.0);
  CHECK(k["recuperacion_tau"]["motivo"].type == json::Value::NUL);
  CHECK(k["thr100"]["etiqueta"].str() == "OFICIAL");
  CHECK_NEAR(k["thr100"]["referencia_jra_s"].num(0), 200, 1e-9);
}

// CF2 sin datos: grabación que termina 3 min después del esfuerzo → sin τ y con motivo; sin GNSS, calentamiento por FC.
EQ_TEST(cardio, kinetics_no_data_cases) {
  std::vector<EcgBeat> b; double t = 0;
  auto hr_at = [](double x) { return x < 300 ? 110.0 : x < 360 ? 205.0 : 80.0 + 125.0 * std::exp(-(x - 360) / 60.0); };
  while (t < 540) { t += 60.0 / hr_at(t); EcgBeat e; e.t = t; b.push_back(e); }
  CardioConfig c; CardioResult r;
  analyse_rr(b, {}, {}, {}, 0, 540, c, &r);
  CHECK(std::isnan(r.tau.tau_s));
  CHECK(!r.tau.reason.empty());
  CHECK(r.warmup.origin == "FC");
  CHECK_NEAR(r.warmup.duration_s, 300, 5.1);
  CHECK(std::isnan(r.warmup.distance_m));
  CHECK(std::isnan(r.fixed_warmup.hr));
  json::Value v; std::string je;
  r.present = true;
  CHECK(json::parse(cardio_json(r, c, false), &v, &je));
  CHECK(v["cinetica"]["tramo_fijo"]["fc_media_lpm"].type == json::Value::NUL);
  CHECK(v["cinetica"]["recuperacion_tau"]["tau_s"].type == json::Value::NUL);
  // ajuste puro: exponencial exacta y FC plana
  std::vector<double> tt, hh, flat;
  for (double x = 60; x <= 600; x += 5) { tt.push_back(x); hh.push_back(65 + 100 * std::exp(-x / 120.0)); flat.push_back(90); }
  CardioResult::TauFit f = fit_hr_recovery(tt, hh, 5, 900);
  CHECK_NEAR(f.tau_s, 120.0, 0.5);
  CHECK_NEAR(f.asymptote, 65.0, 0.2);
  CHECK_NEAR(f.amplitude, 100.0, 0.5);
  CHECK(std::isnan(fit_hr_recovery(tt, flat, 5, 900).tau_s));
  CHECK(std::isnan(fit_hr_recovery({1, 2, 3}, {3, 2, 1}, 5, 900).tau_s));
}

// CF1: una meseta rápida de 40 s (tras un salto de 8 m/s) vale con la regla antigua (≥ 30 s) y no con CF1 (≥ 45 s).
EQ_TEST(cardio, cf1_fast_plateau_needs_45s) {
  std::vector<double> gt, gv;
  auto v_at = [](double x) { return x < 100 ? 4.0 : x < 160 ? 8.0 : x < 220 ? 11.0 : x < 260 ? 16.0 : 1.5; };
  for (double x = 0; x <= 600; x += 0.1) { gt.push_back(x); gv.push_back(v_at(x)); }
  std::vector<EcgBeat> b; double t = 0;
  while (t < 600) { t += 60.0 / (60.0 + 9.0 * v_at(t)); EcgBeat e; e.t = t; b.push_back(e); }
  CardioConfig on; CardioResult r1; analyse_rr(b, gt, gv, {}, 0, 600, on, &r1);
  CardioConfig off = on; off.cf1_enabled = false; CardioResult r0; analyse_rr(b, gt, gv, {}, 0, 600, off, &r0);
  CHECK(r0.v200_regression.points == r1.v200_regression.points + 1);
  CHECK(r1.cf1_plateaus >= 1);
  CHECK(r0.cf1_plateaus == 0);
}

// Cinética de la FC en la historia (TRAINING 1.6.0): CF2, RC1 y FW1 frente a la mediana propia; WU3 en A9.
EQ_TEST(cardio, history_kinetics_marks_and_wu3) {
  auto mk = [](int i, double tau, double thr, double fw, double warm_m) {
    SessionSummary s; s.id = "K" + std::to_string(i); s.horse = "H";
    char d[32]; snprintf(d, sizeof(d), "2026-10-%02d", i + 1); s.date_utc = d; s.surface = "arena";
    s.cardio.present = true; s.cardio.cooldown_class = "PASO"; s.cardio.warmup_m = warm_m;
    s.cardio.tau_s = tau; s.cardio.thr100_s = thr; s.cardio.fw_hr = fw; s.cardio.fw_speed = 4.0;
    s.moving_s = 1800; s.distance_m = 8000;
    return s;
  };
  std::vector<SessionSummary> h;
  // cuatro sesiones de base: τ 80, 90, 100, 90 (mediana 90); THR100 150, 160, 140, 150 (mediana 150); FW1 100, 102, 98, 100
  const double tau[] = {80, 90, 100, 90}, thr[] = {150, 160, 140, 150}, fw[] = {100, 102, 98, 100};
  for (int i = 0; i < 4; i++) h.push_back(mk(i, tau[i], thr[i], fw[i], 2000));
  // última: τ 117 (+30 %), THR100 180 (+20 %, sin marca con el 25 %), FW1 109 (+9 lpm)
  h.push_back(mk(4, 117, 180, 109, 2100));
  TrainingConfig c;
  TrainingResult r = analyse_training(h, "2026-10-05", c);
  const HrKinetics& k = r.hrkin;
  CHECK(k.available && k.ecg_sessions == 5 && k.last_id == "K4");
  CHECK(k.metrics.size() == 3);
  if (k.metrics.size() == 3) {
    CHECK(k.metrics[0].rule == "CF2" && k.metrics[0].n == 4);
    CHECK_NEAR(k.metrics[0].baseline, 90, 1e-9);
    CHECK_NEAR(k.metrics[0].change, 30, 1e-9);
    CHECK(k.metrics[0].marked);
    CHECK_NEAR(k.metrics[1].change, 20, 1e-9);
    CHECK(!k.metrics[1].marked);
    CHECK_NEAR(k.metrics[2].baseline, 100, 1e-9);
    CHECK_NEAR(k.metrics[2].change, 9, 1e-9);
    CHECK(k.metrics[2].marked);
  }
  int cf2 = 0, fw1 = 0, rc1 = 0;
  for (const auto& m : k.marks) { if (m.rule == "CF2") cf2++; if (m.rule == "FW1") fw1++; if (m.rule == "RC1") rc1++; }
  CHECK(cf2 == 1 && fw1 == 1 && rc1 == 0);
  CHECK(r.level == "NORMAL");   // nunca sube el estado
  // otra vuelta a la calma (TROTE) o un calentamiento un 50 % más largo: sin comparables para τ y THR100
  std::vector<SessionSummary> h2 = h; h2[4].cardio.cooldown_class = "TROTE";
  TrainingResult r2 = analyse_training(h2, "2026-10-05", c);
  CHECK(r2.hrkin.metrics[0].n == 0 && !r2.hrkin.metrics[0].marked);
  CHECK(r2.hrkin.metrics[2].n == 4);   // FW1 no depende de la vuelta a la calma
  std::vector<SessionSummary> h3 = h; h3[4].cardio.warmup_m = 3000;
  TrainingResult r3 = analyse_training(h3, "2026-10-05", c);
  CHECK(r3.hrkin.metrics[0].n == 0);
  // JSON y opción
  json::Value v; std::string je;
  CHECK(json::parse(training_to_json(r, c), &v, &je));
  const json::Value& kj = v["estado"]["cinetica_fc"];
  CHECK(kj["disponible"].boolean(false) && !kj["validado"].boolean(true));
  CHECK(kj["ultima"]["metricas"][0]["regla"].str() == "CF2");
  CHECK(kj["parametros"]["etiquetas"]["thr100_referencia_200_s"].str() == "OFICIAL");
  CHECK(kj["marcas"].a.size() == 2);
  json::Value opt; CHECK(json::parse("{\"cinetica_fc\":{\"tau_subida_pct\":40,\"calentamiento_dif_pct\":0}}", &opt, &je));
  TrainingConfig c2; CHECK(training_config_from_json(opt, &c2, &je));
  CHECK_NEAR(c2.hrkin.tau_rise_pct, 40, 1e-9);
  CHECK_NEAR(c2.kb.v200_warmup_match_pct, 0, 1e-9);
  json::Value bad; CHECK(json::parse("{\"cinetica_fc\":{\"tau_subida_pct\":0}}", &bad, &je));
  TrainingConfig c3; CHECK(!training_config_from_json(bad, &c3, &je));
  // sin ECG
  std::vector<SessionSummary> none = h; for (auto& s : none) s.cardio = CardioSummary();
  TrainingResult rn = analyse_training(none, "2026-10-05", c);
  CHECK(!rn.hrkin.available && !rn.hrkin.reason.empty());
  // resumen ida y vuelta
  json::Value back; CHECK(json::parse(training_summary_to_json(h[4]), &back, &je));
  SessionSummary s2; CHECK(training_summary_from_json(back, &s2, &je));
  CHECK_NEAR(s2.cardio.tau_s, 117, 1e-9);
  CHECK_NEAR(s2.cardio.fw_speed, 4.0, 1e-9);
  CHECK(s2.cardio.cooldown_class == "PASO");
  // WU3 en A9: 8 V200 de base con calentamiento de 2000 m y 3 caídas con 4000 m → no comparables, sin A9
  auto mv = [](int i, double v200, double wm) {
    SessionSummary s; s.id = "V" + std::to_string(i); s.horse = "H";
    char d[32]; snprintf(d, sizeof(d), "2026-09-%02d", i + 1); s.date_utc = d; s.surface = "arena";
    s.cardio.present = true; s.cardio.v200 = v200; s.cardio.v200_method = V200_METHOD_CROSSING; s.cardio.warmup_m = wm;
    s.moving_s = 1800; s.distance_m = 8000;
    return s;
  };
  std::vector<SessionSummary> hv;
  for (int i = 0; i < 8; i++) hv.push_back(mv(i, 15.0, 2000));
  for (int i = 8; i < 11; i++) hv.push_back(mv(i, 13.8, 4000));
  TrainingResult ra = analyse_training(hv, "2026-09-12", c);
  bool a9 = false; for (const auto& f : ra.sessions.back().kb.flags) if (f.rule == "A9_PERDIDA_FORMA") a9 = true;
  CHECK(!a9);
  TrainingConfig coff = c; coff.kb.v200_warmup_match_pct = 0;
  TrainingResult rb = analyse_training(hv, "2026-09-12", coff);
  bool a9b = false; for (const auto& f : rb.sessions.back().kb.flags) if (f.rule == "A9_PERDIDA_FORMA") a9b = true;
  CHECK(a9b);
}
