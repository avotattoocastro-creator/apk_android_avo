// Cadence and regularity under difficult signals (simulation). The engine must either be right within its
// stated uncertainty or refuse to report a cadence.
#include "eq_test.h"
#include "avo_eq/engine.h"
#include "synth.h"

using namespace avoeq;

static double f_chirp(double t) { return 0.9 + 0.6 * t / 90.0; }
static double f_095(double) { return 0.95; }
static double f_step(double t) { return t < 30 ? 0.95 : 1.45; }
static double f_160(double) { return 1.6; }
static double a_600(double) { return 600; }
static double a_280(double) { return 280; }
static double a_80(double) { return 80; }
static double a_0(double) { return 0; }

static CadenceResult run(double secs, double (*f)(double), double (*a1)(double), double (*a2)(double), double fs, double noise, double loss = 0, unsigned seed = 2) {
  synth::ImuSpec sp; sp.fs = fs; sp.loss = loss; sp.offset_s = 0; sp.drift_ppm = 0;
  Session s; s.imu = synth::imu_shape(secs, f, a1, a2, sp, 0, seed, noise);
  auto v = validate(s);
  auto ser = build_imu_series(s, v);
  return ser.empty() ? CadenceResult() : analyse_cadence(ser[0]);
}

// for each VALID window: |f - truth| must stay within 3σ + 0.02 Hz (and the stride, not a harmonic, is reported)
static void check_valid(const CadenceResult& r, double (*truth)(double), int* valid, int* bad, double skip_from = -1, double skip_to = -1) {
  for (auto& w : r.windows) {
    if (w.status != CadenceStatus::VALID) { CHECK(w.freq_hz == 0); continue; }
    if (w.t_mid >= skip_from && w.t_mid <= skip_to) continue;
    (*valid)++;
    double err = std::fabs(w.freq_hz - truth(w.t_mid));
    if (err > 3 * w.uncertainty_hz + 0.02) { (*bad)++; REPORT("t=%.1f f=%.3f verdad=%.3f σ=%.3f\n", w.t_mid, w.freq_hz, truth(w.t_mid), w.uncertainty_hz); }
  }
}

EQ_TEST(cadence, variable_frequency_tracked_within_uncertainty) {
  auto r = run(90, f_chirp, a_280, a_600, 200, 30);
  int valid = 0, bad = 0; check_valid(r, f_chirp, &valid, &bad);
  REPORT("frecuencia variable: %d ventanas válidas de %zu, %d fuera de 3σ\n", valid, r.windows.size(), bad);
  CHECK(valid > (int)r.windows.size() / 2); CHECK(bad == 0);
}

EQ_TEST(cadence, heavy_noise_never_gives_a_confident_wrong_value) {
  int valid = 0, bad = 0, total = 0;
  for (unsigned seed = 1; seed <= 5; seed++) {
    auto r = run(60, f_095, a_280, a_600, 200, 900, 0, seed);   // noise RMS above the signal amplitude
    total += (int)r.windows.size();
    check_valid(r, f_095, &valid, &bad);
  }
  REPORT("ruido intenso: %d válidas de %d ventanas, %d erróneas\n", valid, total, bad);
  CHECK(bad == 0);
}

EQ_TEST(cadence, dominant_harmonic_is_not_taken_as_the_cadence) {
  auto r = run(60, f_095, a_80, a_600, 200, 20);           // the 2nd harmonic dominates the spectrum
  int valid = 0, bad = 0, dom2 = 0; check_valid(r, f_095, &valid, &bad);
  for (auto& w : r.windows) if (w.status == CadenceStatus::VALID && w.dominant_harmonic == 2) dom2++;
  REPORT("armónico dominante: %d válidas, %d con el pico espectral en 2·f0, %d erróneas\n", valid, dom2, bad);
  CHECK(valid > 0); CHECK(bad == 0); CHECK(dom2 > 0);
}

EQ_TEST(cadence, lost_samples_split_and_stay_accurate) {
  auto r = run(90, f_095, a_280, a_600, 200, 30, 0.08);
  int valid = 0, bad = 0; check_valid(r, f_095, &valid, &bad);
  REPORT("pérdidas 8 %%: %d válidas, %d erróneas\n", valid, bad);
  CHECK(bad == 0);
}

EQ_TEST(cadence, gait_change_inside_a_window_is_not_reported_as_valid_mixture) {
  auto r = run(60, f_step, a_280, a_600, 200, 30);
  int straddle_valid_wrong = 0;
  for (auto& w : r.windows) if (w.t_mid > 27 && w.t_mid < 33 && w.status == CadenceStatus::VALID) {
    double e = std::min(std::fabs(w.freq_hz - 0.95), std::fabs(w.freq_hz - 1.45));
    if (e > 0.1) straddle_valid_wrong++;
  }
  int valid = 0, bad = 0; check_valid(r, f_step, &valid, &bad, 26.9, 33.1);
  CHECK(straddle_valid_wrong == 0); CHECK(bad == 0);
}

EQ_TEST(cadence, non_periodic_movement_has_no_cadence) {
  int valid = 0;
  for (unsigned seed = 1; seed <= 5; seed++) { auto r = run(60, f_095, a_0, a_0, 200, 300, 0, seed); for (auto& w : r.windows) if (w.status == CadenceStatus::VALID) valid++; }
  REPORT("ruido sin periodicidad: %d ventanas válidas\n", valid);
  CHECK(valid == 0);
}

EQ_TEST(cadence, different_sampling_rates) {
  for (double fs : {50.0, 100.0, 200.0, 400.0}) {
    auto r = run(40, f_160, a_600, a_280, fs, 30);
    int valid = 0, bad = 0; check_valid(r, f_160, &valid, &bad);
    REPORT("fs %.0f Hz: %d válidas, %d erróneas\n", fs, valid, bad);
    CHECK(valid > 0); CHECK(bad == 0);
  }
}

EQ_TEST(cadence, regularity_metrics_are_reported_separately) {
  auto r = run(40, f_095, a_280, a_600, 200, 30);
  bool t = false, a = false, c = false, s = false;
  for (auto& m : r.metrics) { t |= m.name == "variabilidad_intervalos"; a |= m.name == "regularidad_amplitud_cv"; c |= m.name == "correlacion_entre_ciclos"; s |= m.name == "estabilidad_espectral"; }
  CHECK(t && a && c && s);
  for (auto& m : r.metrics) CHECK(m.name.find("puntuacion") == std::string::npos);
}
