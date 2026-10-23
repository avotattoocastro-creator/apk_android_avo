// Digital signal processing used by every module. Pure functions, deterministic, no allocation surprises.
#pragma once
#include <complex>
#include <cstddef>
#include <vector>

namespace avoeq {
namespace dsp {

// Second-order section (biquad), direct form II transposed.
struct Biquad {
  double b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
  double z1 = 0, z2 = 0;
  double step(double x) { double y = b0 * x + z1; z1 = b1 * x - a1 * y + z2; z2 = b2 * x - a2 * y; return y; }
  void reset() { z1 = z2 = 0; }
};
// Butterworth 2nd-order sections via the bilinear transform with pre-warping (RBJ cookbook, Q = 1/sqrt(2)).
Biquad butter_lowpass(double fc_hz, double fs_hz);
Biquad butter_highpass(double fc_hz, double fs_hz);
// Zero-phase filtering (forward + backward, Gustafsson-free simple reflection padding). Order doubles.
std::vector<double> filtfilt(const Biquad& proto, const std::vector<double>& x);
std::vector<double> bandpass_zero_phase(const std::vector<double>& x, double f_lo, double f_hi, double fs);

std::vector<double> detrend_mean(const std::vector<double>& x);

// In-place radix-2 FFT (n must be a power of two).
void fft(std::vector<std::complex<double>>& a, bool inverse = false);
size_t next_pow2(size_t n);

// Normalised autocorrelation r[k] = sum x[i]x[i+k] / sum x[i]^2 (biased estimator), k = 0..max_lag, via FFT.
std::vector<double> autocorr(const std::vector<double>& x, size_t max_lag);

// One-sided power spectrum with a Hann window. Returns power per bin; df = fs / nfft.
std::vector<double> power_spectrum(const std::vector<double>& x, double fs, double* df);

// Local maxima above a threshold, separated by at least min_dist samples (highest kept).
std::vector<size_t> find_peaks(const std::vector<double>& x, double min_height, size_t min_dist);

// Parabolic interpolation of a peak at index i: returns fractional offset in [-0.5, 0.5].
double parabolic_offset(double ym1, double y0, double yp1);

// Fundamental (cycle) frequency of a periodic signal in [f_min, f_max].
// Autocorrelation picks the period; the sub-harmonic check (period x2, x3) prevents reporting a harmonic
// as the cycle frequency when the true cycle contains several similar beats.
struct Fundamental {
  double freq_hz = 0;        // 0 = no periodicity found
  double strength = 0;       // normalised autocorrelation at the chosen lag (0..1)
  double period_s = 0;
  bool subharmonic_chosen = false;
};
Fundamental fundamental(const std::vector<double>& x, double fs, double f_min, double f_max, double min_strength = 0.3);

// Statistics
double mean(const std::vector<double>& x);
double stddev(const std::vector<double>& x);           // sample standard deviation
double median(std::vector<double> x);
double mad(const std::vector<double>& x);              // median absolute deviation (raw, not scaled)
double rms(const std::vector<double>& x);

}  // namespace dsp
}  // namespace avoeq
