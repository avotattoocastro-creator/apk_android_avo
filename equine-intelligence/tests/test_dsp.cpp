#include "eq_test.h"
#include "avo_eq/dsp.h"
#include <random>

using namespace avoeq;
static const double PI = 3.14159265358979323846;

static std::vector<double> sine(double f, double fs, double secs, double noise, unsigned seed, double amp = 1.0) {
  std::mt19937 rng(seed); std::normal_distribution<double> n(0, noise);
  std::vector<double> x((size_t)(fs * secs));
  for (size_t i = 0; i < x.size(); i++) x[i] = amp * std::sin(2 * PI * f * i / fs) + (noise > 0 ? n(rng) : 0);
  return x;
}

EQ_TEST(dsp, fundamental_of_1hz_and_2hz_sines) {
  for (double f : {1.0, 2.0}) {
    auto x = sine(f, 100, 8, 0.0, 1);
    auto r = dsp::fundamental(x, 100, 0.6, 3.5);
    CHECK_NEAR(r.freq_hz, f, 0.01 * f);   // exact signal: < 1 %
    CHECK(r.strength > 0.8);
  }
}

EQ_TEST(dsp, fundamental_with_noise_snr_0db) {
  auto x = sine(1.4, 200, 6, 0.7071, 7);  // signal power 0.5 = noise power 0.5
  auto r = dsp::fundamental(x, 200, 0.6, 3.5);
  CHECK_NEAR(r.freq_hz, 1.4, 0.05);
}

EQ_TEST(dsp, two_unequal_beats_per_cycle_report_the_cycle_not_the_beat) {
  // stride at 1.5 Hz made of two beats (3 Hz) of different shape: the true cycle is 1.5 Hz
  double fs = 200, fc = 1.5;
  std::vector<double> x((size_t)(fs * 8));
  for (size_t i = 0; i < x.size(); i++) {
    double t = i / fs;
    x[i] = std::sin(2 * PI * 2 * fc * t) + 0.45 * std::sin(2 * PI * fc * t + 0.6);
  }
  auto r = dsp::fundamental(x, fs, 0.6, 3.5);
  CHECK_NEAR(r.freq_hz, fc, 0.03);
  // two identical beats: the signal really repeats at 3 Hz, and that is what must be reported
  for (size_t i = 0; i < x.size(); i++) x[i] = std::sin(2 * PI * 2 * fc * i / fs);
  r = dsp::fundamental(x, fs, 0.6, 3.5);
  CHECK_NEAR(r.freq_hz, 2 * fc, 0.05);
}

EQ_TEST(dsp, no_periodicity_in_white_noise) {
  std::mt19937 rng(3); std::normal_distribution<double> n(0, 1);
  std::vector<double> x(1200); for (auto& v : x) v = n(rng);
  auto r = dsp::fundamental(x, 200, 0.6, 3.5, 0.35);
  CHECK(r.freq_hz == 0);
}

EQ_TEST(dsp, butterworth_lowpass_response) {
  double fs = 200;
  auto lp = dsp::butter_lowpass(5, fs);
  auto pass = dsp::filtfilt(lp, sine(1, fs, 10, 0, 1));
  auto stop = dsp::filtfilt(lp, sine(40, fs, 10, 0, 1));
  double rp = dsp::rms(std::vector<double>(pass.begin() + 400, pass.end() - 400));
  double rs = dsp::rms(std::vector<double>(stop.begin() + 400, stop.end() - 400));
  // analytic: 2nd-order Butterworth applied twice: |H(1Hz)|^2 = 1/(1+(1/5)^4) -> 0.9984 ; |H(40Hz)|^2 ≈ (5/40)^4 = 2.4e-4
  CHECK_NEAR(rp / (1 / std::sqrt(2.0)), 1.0 / (1 + std::pow(1.0 / 5, 4)), 0.01);
  CHECK(20 * std::log10(rs / (1 / std::sqrt(2.0))) < -60);
}

EQ_TEST(dsp, fft_roundtrip_and_parseval) {
  std::mt19937 rng(9); std::normal_distribution<double> n(0, 1);
  std::vector<std::complex<double>> a(256); double e = 0;
  for (auto& v : a) { v = n(rng); e += std::norm(v); }
  auto b = a; dsp::fft(b);
  double eb = 0; for (auto& v : b) eb += std::norm(v);
  CHECK_NEAR(eb / 256, e, 1e-9 * e);
  dsp::fft(b, true);
  double err = 0; for (size_t i = 0; i < a.size(); i++) err = std::max(err, std::abs(a[i] - b[i]));
  CHECK(err < 1e-12);
}

EQ_TEST(dsp, robust_statistics) {
  CHECK_NEAR(dsp::median({5, 1, 3}), 3, 0);
  CHECK_NEAR(dsp::median({4, 1, 3, 2}), 2.5, 0);
  CHECK_NEAR(dsp::mad({1, 2, 3, 4, 100}), 1, 0);
  CHECK_NEAR(dsp::stddev({2, 4, 4, 4, 5, 5, 7, 9}), 2.138089935, 1e-8);
}
