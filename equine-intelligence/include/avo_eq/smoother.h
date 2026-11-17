// AVO PERFORMANCE EQUINE 2.0 — single kinematic truth (F1).
// Kalman filter + Rauch–Tung–Striebel smoother of the receiver ground speed, the same model and defaults the apps used
// on their own until 2.0 (Android Kotlin, Windows C# and iPad Swift SpeedSmoother): state [v, a], constant acceleration
// with white jerk (spectral density jerk_density, m²/s⁵); measurement z = gSpeed with variance max(sAcc, min_sigma)²
// (fallback_sigma when sAcc is unknown). The filter restarts after every break, so it never bridges missing data.
// From 2.0 every speed figure of the engine (maximum, thresholds, best distances, splits, gaits) comes from this series,
// so the apps, the reports and the engine show the same numbers. The raw gSpeed is always kept beside it.
#pragma once
#include <vector>

namespace avoeq {

struct SpeedSmootherConfig {
  double jerk_density = 1.0;        // m²/s⁵
  double min_speed_sigma = 0.05;    // m/s floor of the measurement sigma
  double fallback_speed_sigma = 0.15;  // m/s when sAcc is unknown (<= 0 or NaN)
  double initial_accel_sigma = 2.0; // m/s² prior on the acceleration at each restart
};

struct SpeedSmootherResult {
  std::vector<double> speed, speed_sigma, accel, accel_sigma;
};

// t: s (increasing inside each piece) · z: m/s (NaN = no measurement, prediction only) · sacc: m/s ·
// break_before[i]: a new piece starts at i.
SpeedSmootherResult smooth_speed(const std::vector<double>& t, const std::vector<double>& z, const std::vector<double>& sacc,
                                 const std::vector<bool>& break_before, const SpeedSmootherConfig& c = SpeedSmootherConfig());

}  // namespace avoeq
