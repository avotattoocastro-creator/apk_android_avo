#include "avo_eq/smoother.h"
#include <algorithm>
#include <cmath>

namespace avoeq {

static double meas_sigma(double sacc, const SpeedSmootherConfig& c) {
  if (!(sacc > 0) || !std::isfinite(sacc)) return c.fallback_speed_sigma;
  return std::max(sacc, c.min_speed_sigma);
}

static void run_piece(const std::vector<double>& t, const std::vector<double>& z, const std::vector<double>& sacc,
                      const SpeedSmootherConfig& c, size_t i0, size_t i1, SpeedSmootherResult& out) {
  size_t m = i1 - i0;
  if (m == 0) return;
  std::vector<double> xf(m * 2), pf(m * 3), xp(m * 2), pp(m * 3);
  double x0 = std::isfinite(z[i0]) ? z[i0] : 0, x1 = 0;
  double r0 = meas_sigma(sacc[i0], c);
  double p00 = r0 * r0, p01 = 0, p11 = c.initial_accel_sigma * c.initial_accel_sigma;
  for (size_t k = 0; k < m; k++) {
    size_t i = i0 + k;
    if (k > 0) {
      double dt = std::max(t[i] - t[i - 1], 1e-3), q = c.jerk_density;
      double q00 = q * dt * dt * dt / 3, q01 = q * dt * dt / 2, q11 = q * dt;
      double n00 = p00 + 2 * dt * p01 + dt * dt * p11 + q00, n01 = p01 + dt * p11 + q01, n11 = p11 + q11;
      x0 = x0 + dt * x1; p00 = n00; p01 = n01; p11 = n11;
    }
    xp[k * 2] = x0; xp[k * 2 + 1] = x1; pp[k * 3] = p00; pp[k * 3 + 1] = p01; pp[k * 3 + 2] = p11;
    if (std::isfinite(z[i])) {
      double r = meas_sigma(sacc[i], c), s = p00 + r * r, k0 = p00 / s, k1 = p01 / s, y = z[i] - x0;
      x0 += k0 * y; x1 += k1 * y;
      double u00 = (1 - k0) * p00, u01 = (1 - k0) * p01, u11 = p11 - k1 * p01;
      p00 = u00; p01 = u01; p11 = u11;
    }
    xf[k * 2] = x0; xf[k * 2 + 1] = x1; pf[k * 3] = p00; pf[k * 3 + 1] = p01; pf[k * 3 + 2] = p11;
  }
  double sx0 = xf[(m - 1) * 2], sx1 = xf[(m - 1) * 2 + 1];
  double s00 = pf[(m - 1) * 3], s01 = pf[(m - 1) * 3 + 1], s11 = pf[(m - 1) * 3 + 2];
  auto store = [&](size_t k) {
    out.speed[i0 + k] = std::max(0.0, sx0); out.accel[i0 + k] = sx1;
    out.speed_sigma[i0 + k] = std::sqrt(std::max(0.0, s00)); out.accel_sigma[i0 + k] = std::sqrt(std::max(0.0, s11));
  };
  store(m - 1);
  for (long k = (long)m - 2; k >= 0; k--) {
    size_t i = i0 + (size_t)k + 1;
    double dt = std::max(t[i] - t[i - 1], 1e-3);
    double f00 = pf[k * 3], f01 = pf[k * 3 + 1], f11 = pf[k * 3 + 2];
    double a00 = f00 + dt * f01, a01 = f01, a10 = f01 + dt * f11, a11 = f11;
    double q00 = pp[(k + 1) * 3], q01 = pp[(k + 1) * 3 + 1], q11 = pp[(k + 1) * 3 + 2];
    double det = q00 * q11 - q01 * q01;
    if (std::fabs(det) < 1e-18) {
      sx0 = xf[k * 2]; sx1 = xf[k * 2 + 1]; s00 = f00; s01 = f01; s11 = f11;
      store((size_t)k);
      continue;
    }
    double inv00 = q11 / det, inv01 = -q01 / det, inv11 = q00 / det;
    double c00 = a00 * inv00 + a01 * inv01, c01 = a00 * inv01 + a01 * inv11;
    double c10 = a10 * inv00 + a11 * inv01, c11 = a10 * inv01 + a11 * inv11;
    double d0 = sx0 - xp[(k + 1) * 2], d1 = sx1 - xp[(k + 1) * 2 + 1];
    double nx0 = xf[k * 2] + c00 * d0 + c01 * d1, nx1 = xf[k * 2 + 1] + c10 * d0 + c11 * d1;
    double e00 = s00 - q00, e01 = s01 - q01, e11 = s11 - q11;
    double g00 = c00 * e00 + c01 * e01, g01 = c00 * e01 + c01 * e11, g10 = c10 * e00 + c11 * e01, g11 = c10 * e01 + c11 * e11;
    double n00 = f00 + g00 * c00 + g01 * c01, n01 = f01 + g00 * c10 + g01 * c11, n11 = f11 + g10 * c10 + g11 * c11;
    sx0 = nx0; sx1 = nx1; s00 = n00; s01 = n01; s11 = n11;
    store((size_t)k);
  }
}

SpeedSmootherResult smooth_speed(const std::vector<double>& t, const std::vector<double>& z, const std::vector<double>& sacc,
                                 const std::vector<bool>& break_before, const SpeedSmootherConfig& c) {
  SpeedSmootherResult r;
  size_t n = t.size();
  r.speed.assign(n, 0); r.speed_sigma.assign(n, 0); r.accel.assign(n, 0); r.accel_sigma.assign(n, 0);
  if (n == 0) return r;
  size_t start = 0;
  for (size_t i = 1; i <= n; i++) {
    if (i == n || break_before[i]) { run_piece(t, z, sacc, c, start, i, r); start = i; }
  }
  return r;
}

}  // namespace avoeq
