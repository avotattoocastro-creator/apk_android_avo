#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>
#include <numeric>

namespace avoeq {
namespace dsp {

static const double PI = 3.14159265358979323846;

static Biquad rbj(double fc, double fs, bool high) {
  const double Q = 1.0 / std::sqrt(2.0);
  double w0 = 2 * PI * fc / fs;
  double cw = std::cos(w0), sw = std::sin(w0), alpha = sw / (2 * Q);
  double a0 = 1 + alpha;
  Biquad b;
  if (high) { b.b0 = (1 + cw) / 2; b.b1 = -(1 + cw); b.b2 = (1 + cw) / 2; }
  else { b.b0 = (1 - cw) / 2; b.b1 = 1 - cw; b.b2 = (1 - cw) / 2; }
  b.a1 = -2 * cw; b.a2 = 1 - alpha;
  b.b0 /= a0; b.b1 /= a0; b.b2 /= a0; b.a1 /= a0; b.a2 /= a0;
  return b;
}
Biquad butter_lowpass(double fc, double fs) { return rbj(fc, fs, false); }
Biquad butter_highpass(double fc, double fs) { return rbj(fc, fs, true); }

std::vector<double> filtfilt(const Biquad& proto, const std::vector<double>& x) {
  size_t n = x.size();
  if (n < 4) return x;
  size_t pad = std::min<size_t>(n - 1, 3 * 6);
  // odd reflection padding keeps the edges continuous
  std::vector<double> e;
  e.reserve(n + 2 * pad);
  for (size_t i = pad; i >= 1; i--) e.push_back(2 * x[0] - x[i]);
  e.insert(e.end(), x.begin(), x.end());
  for (size_t i = 1; i <= pad; i++) e.push_back(2 * x[n - 1] - x[n - 1 - i]);
  Biquad f = proto; f.reset();
  // initialise the state with the first value (steady state for a constant input)
  for (int k = 0; k < 50; k++) f.step(e.front());
  for (auto& v : e) v = f.step(v);
  Biquad r = proto; r.reset();
  for (int k = 0; k < 50; k++) r.step(e.back());
  for (size_t i = e.size(); i-- > 0;) e[i] = r.step(e[i]);
  return std::vector<double>(e.begin() + pad, e.begin() + pad + n);
}

std::vector<double> bandpass_zero_phase(const std::vector<double>& x, double f_lo, double f_hi, double fs) {
  std::vector<double> y = x;
  if (f_lo > 0) y = filtfilt(butter_highpass(f_lo, fs), y);
  if (f_hi > 0 && f_hi < fs / 2) y = filtfilt(butter_lowpass(f_hi, fs), y);
  return y;
}

std::vector<double> detrend_mean(const std::vector<double>& x) {
  double m = mean(x);
  std::vector<double> y(x.size());
  for (size_t i = 0; i < x.size(); i++) y[i] = x[i] - m;
  return y;
}

size_t next_pow2(size_t n) { size_t p = 1; while (p < n) p <<= 1; return p; }

void fft(std::vector<std::complex<double>>& a, bool inverse) {
  size_t n = a.size();
  for (size_t i = 1, j = 0; i < n; i++) {
    size_t bit = n >> 1;
    for (; j & bit; bit >>= 1) j ^= bit;
    j ^= bit;
    if (i < j) std::swap(a[i], a[j]);
  }
  for (size_t len = 2; len <= n; len <<= 1) {
    double ang = 2 * PI / (double)len * (inverse ? 1 : -1);
    std::complex<double> wl(std::cos(ang), std::sin(ang));
    for (size_t i = 0; i < n; i += len) {
      std::complex<double> w(1);
      for (size_t j = 0; j < len / 2; j++) {
        auto u = a[i + j], v = a[i + j + len / 2] * w;
        a[i + j] = u + v; a[i + j + len / 2] = u - v;
        w *= wl;
      }
    }
  }
  if (inverse) for (auto& v : a) v /= (double)n;
}

std::vector<double> autocorr(const std::vector<double>& x, size_t max_lag) {
  size_t n = x.size();
  std::vector<double> r(max_lag + 1, 0.0);
  if (n == 0) return r;
  size_t m = next_pow2(2 * n);
  std::vector<std::complex<double>> a(m);
  for (size_t i = 0; i < n; i++) a[i] = x[i];
  fft(a);
  for (auto& v : a) v = std::complex<double>(std::norm(v), 0);
  fft(a, true);
  double r0 = a[0].real();
  if (r0 <= 0) return r;
  for (size_t k = 0; k <= max_lag && k < n; k++) r[k] = a[k].real() / r0;
  return r;
}

std::vector<double> power_spectrum(const std::vector<double>& x, double fs, double* df) {
  size_t n = x.size();
  size_t m = next_pow2(std::max<size_t>(n, 2));
  std::vector<std::complex<double>> a(m);
  for (size_t i = 0; i < n; i++) {
    double w = 0.5 - 0.5 * std::cos(2 * PI * (double)i / (double)(n > 1 ? n - 1 : 1));
    a[i] = x[i] * w;
  }
  fft(a);
  std::vector<double> p(m / 2 + 1);
  for (size_t k = 0; k < p.size(); k++) p[k] = std::norm(a[k]);
  if (df) *df = fs / (double)m;
  return p;
}

std::vector<size_t> find_peaks(const std::vector<double>& x, double min_height, size_t min_dist) {
  std::vector<size_t> c;
  for (size_t i = 1; i + 1 < x.size(); i++)
    if (x[i] >= min_height && x[i] > x[i - 1] && x[i] >= x[i + 1]) c.push_back(i);
  std::sort(c.begin(), c.end(), [&](size_t a, size_t b) { return x[a] > x[b]; });
  std::vector<size_t> kept;
  for (size_t i : c) {
    bool ok = true;
    for (size_t k : kept) if ((i > k ? i - k : k - i) < min_dist) { ok = false; break; }
    if (ok) kept.push_back(i);
  }
  std::sort(kept.begin(), kept.end());
  return kept;
}

double parabolic_offset(double ym1, double y0, double yp1) {
  double d = ym1 - 2 * y0 + yp1;
  if (std::fabs(d) < 1e-12) return 0;
  double o = 0.5 * (ym1 - yp1) / d;
  return std::max(-0.5, std::min(0.5, o));
}

Fundamental fundamental(const std::vector<double>& x, double fs, double f_min, double f_max, double min_strength) {
  Fundamental out;
  if (x.size() < 8 || fs <= 0 || f_min <= 0 || f_max <= f_min) return out;
  size_t lag_min = (size_t)std::floor(fs / f_max);
  size_t lag_max = (size_t)std::ceil(fs / f_min);
  if (lag_min < 1) lag_min = 1;
  if (lag_max >= x.size() / 2) lag_max = x.size() / 2;
  if (lag_max <= lag_min + 1) return out;
  std::vector<double> y = detrend_mean(x);
  std::vector<double> r = autocorr(y, std::min(x.size() - 1, 3 * lag_max + 2));
  // Broadband noise puts small ripples on the autocorrelation: look for maxima on a smoothed copy
  // (moving average over a quarter of the shortest allowed period), then refine on the raw curve.
  size_t hw = std::max<size_t>(1, lag_min / 8);
  std::vector<double> rs(r.size(), 0.0);
  for (size_t k = 0; k < r.size(); k++) {
    double sum = 0; size_t cnt = 0;
    for (size_t j = (k > hw ? k - hw : 0); j <= k + hw && j < r.size(); j++) { sum += r[j]; cnt++; }
    rs[k] = sum / cnt;
  }
  std::vector<size_t> maxima;
  double bv = -1;
  for (size_t k = lag_min + 1; k < lag_max && k + 1 < rs.size(); k++)
    if (rs[k] > rs[k - 1] && rs[k] >= rs[k + 1]) {
      size_t best = k;   // refine on the raw autocorrelation within ±hw
      for (size_t j = (k > hw ? k - hw : 1); j <= k + hw && j + 1 < r.size(); j++) if (r[j] > r[best]) best = j;
      maxima.push_back(best); bv = std::max(bv, r[best]);
    }
  if (maxima.empty() || bv < min_strength) return out;
  // 1) multiples of the period (2T, 3T) are also maxima, slightly weaker: take the SHORTEST lag that is
  //    almost as strong as the best one.
  size_t chosen = 0;
  for (size_t k : maxima) if (r[k] >= 0.9 * bv) { chosen = k; break; }
  // 2) the opposite error: a cycle made of two similar beats looks periodic at half the cycle. If the lag
  //    twice as long is clearly more coherent, the real cycle is that one.
  size_t L = chosen * 2;
  if (L + 2 < r.size() && L < lag_max) {
    size_t lk = L; double lv = r[L];
    for (size_t k = L - 2; k <= L + 2; k++) if (r[k] > lv) { lv = r[k]; lk = k; }
    if (lv - r[chosen] > 0.05) { chosen = lk; out.subharmonic_chosen = true; }
  }
  double off = (chosen > 0 && chosen + 1 < r.size()) ? parabolic_offset(r[chosen - 1], r[chosen], r[chosen + 1]) : 0;
  double lag = (double)chosen + off;
  out.period_s = lag / fs;
  out.freq_hz = 1.0 / out.period_s;
  out.strength = r[chosen];
  return out;
}

double mean(const std::vector<double>& x) { return x.empty() ? 0 : std::accumulate(x.begin(), x.end(), 0.0) / (double)x.size(); }
double stddev(const std::vector<double>& x) {
  if (x.size() < 2) return 0;
  double m = mean(x), s = 0;
  for (double v : x) s += (v - m) * (v - m);
  return std::sqrt(s / (double)(x.size() - 1));
}
double median(std::vector<double> x) {
  if (x.empty()) return 0;
  size_t n = x.size();
  std::nth_element(x.begin(), x.begin() + n / 2, x.end());
  double m = x[n / 2];
  if (n % 2 == 0) { std::nth_element(x.begin(), x.begin() + n / 2 - 1, x.end()); m = 0.5 * (m + x[n / 2 - 1]); }
  return m;
}
double mad(const std::vector<double>& x) {
  double m = median(x);
  std::vector<double> d(x.size());
  for (size_t i = 0; i < x.size(); i++) d[i] = std::fabs(x[i] - m);
  return median(d);
}
double rms(const std::vector<double>& x) {
  if (x.empty()) return 0;
  double s = 0; for (double v : x) s += v * v;
  return std::sqrt(s / (double)x.size());
}

}  // namespace dsp
}  // namespace avoeq
