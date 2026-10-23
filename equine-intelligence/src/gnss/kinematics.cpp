#include "avo_eq/kinematics.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>

namespace avoeq {

static const double PI = 3.14159265358979323846;

static bool usable_q(const GnssResult& g, size_t i) { return g.usable[i] && g.quality[i] <= (uint8_t)Quality::USABLE; }

KinematicsResult analyse_kinematics(const GnssResult& g, const AccelConfig& c) {
  KinematicsResult r;
  size_t n = g.t.size();
  if (n < 3) return r;
  // estimates accepted for events: finite, small uncertainty, physically possible, good-enough epoch
  std::vector<bool> ok(n, false);
  for (size_t i = 0; i < n; i++) {
    if (std::isnan(g.accel[i]) || !usable_q(g, i) || g.accel_sigma[i] > c.max_sigma) continue;
    if (std::fabs(g.accel[i]) > c.physical_max) { r.rejected_physical++; continue; }
    ok[i] = true;
  }
  // ---- sustained acceleration / deceleration (hysteresis, tolerates short gaps)
  for (int sign : {+1, -1}) {
    bool in = false; size_t s0 = 0, last = 0; double sum = 0; int cnt = 0;
    auto close = [&](size_t endi) {
      if (cnt >= 3) {
        AccelEvent e; e.type = sign > 0 ? "ACELERACION_SOSTENIDA" : "DESACELERACION_SOSTENIDA";
        e.peak = 0; double best = -1; size_t kp = s0;
        for (size_t k = s0; k <= endi; k++) if (ok[k] && sign * g.accel[k] > best) { best = sign * g.accel[k]; e.peak = g.accel[k]; e.peak_sigma = g.accel_sigma[k]; e.t_peak = g.t[k]; kp = k; }
        // the derivative window smears the edges: the event is its core at half the peak value
        size_t a = kp, b = kp;
        while (a > s0 && (!ok[a - 1] || sign * g.accel[a - 1] >= 0.5 * best)) a--;
        while (b < endi && (!ok[b + 1] || sign * g.accel[b + 1] >= 0.5 * best)) b++;
        // mean acceleration = least-squares slope of the measured speed over the core (not an average of slopes)
        double sw = 0, st = 0, sv = 0, stt = 0, stv = 0; int m = 0;
        for (size_t k = a; k <= b; k++) if (usable_q(g, k) && !std::isnan(g.speed[k])) {
          double dt = g.t[k] - g.t[a]; sw += 1; st += dt; sv += g.speed[k]; stt += dt * dt; stv += dt * g.speed[k]; m++;
        }
        double den = sw * stt - st * st;
        double dur = g.t[b] - g.t[a];
        if (m >= 3 && den > 0 && dur >= c.sustained_min_s) {
          e.t0 = g.t[a]; e.t1 = g.t[b];
          e.mean = (sw * stv - st * sv) / den;
          e.v0 = g.speed[a]; e.v1 = g.speed[b]; e.dv = e.v1 - e.v0;
          double sigv = 0; for (size_t k = a; k <= b; k++) sigv = std::max(sigv, g.accel_sigma[k] > 0 ? g.accel_sigma[k] : 0);
          e.quality = std::fabs(e.mean) > 3 * e.peak_sigma ? Quality::GOOD : Quality::USABLE;
          if (sign * e.mean >= c.sustained_exit) r.events.push_back(e);
        }
      }
      in = false; sum = 0; cnt = 0;
    };
    for (size_t i = 0; i < n; i++) {
      if (!ok[i]) { if (in && g.t[i] - g.t[last] > c.gap_tolerance_s) close(last); continue; }
      double a = sign * g.accel[i];
      if (!in) {
        if (a >= c.sustained_min && a - g.accel_sigma[i] > 0) { in = true; s0 = i; last = i; sum = g.accel[i]; cnt = 1; }
      } else if (a >= c.sustained_exit) { last = i; sum += g.accel[i]; cnt++; }
      else close(last);
    }
    if (in) close(last);
  }
  // ---- peaks: local extremes, significant against their own uncertainty, separated in time
  auto peaks = [&](const std::vector<double>& a, const std::vector<double>& sa, double thr, const char* pos, const char* neg, bool lateral) {
    std::vector<AccelEvent> found;
    for (size_t i = 1; i + 1 < n; i++) {
      if (std::isnan(a[i]) || std::isnan(sa[i]) || !usable_q(g, i) || sa[i] > (lateral ? 2 * c.max_sigma : c.max_sigma)) continue;
      double v = std::fabs(a[i]);
      if (v < thr || v < c.peak_k_sigma * sa[i] || v > c.physical_max) continue;
      double prev = std::isnan(a[i - 1]) ? 0 : std::fabs(a[i - 1]), next = std::isnan(a[i + 1]) ? 0 : std::fabs(a[i + 1]);
      if (v < prev || v < next) continue;
      AccelEvent e; e.type = lateral ? "PICO_LATERAL" : (a[i] > 0 ? pos : neg);
      e.t0 = e.t1 = e.t_peak = g.t[i]; e.peak = a[i]; e.peak_sigma = sa[i]; e.mean = a[i];
      e.v0 = e.v1 = g.speed[i];
      e.quality = v > 2 * c.peak_k_sigma * sa[i] ? Quality::GOOD : Quality::USABLE;
      if (lateral) e.source = "TRAYECTORIA_GNSS_ESTIMADA";
      if (!found.empty() && e.t_peak - found.back().t_peak < c.peak_separation_s && (e.type == found.back().type)) {
        if (std::fabs(e.peak) > std::fabs(found.back().peak)) found.back() = e;
      } else found.push_back(e);
    }
    r.events.insert(r.events.end(), found.begin(), found.end());
  };
  peaks(g.accel, g.accel_sigma, c.peak_min, "PICO_ACELERACION", "PICO_DESACELERACION", false);
  peaks(g.lat_accel, g.lat_accel_sigma, c.lateral_peak_min, "", "", true);
  std::sort(r.events.begin(), r.events.end(), [](const AccelEvent& a, const AccelEvent& b) { return a.t0 < b.t0 || (a.t0 == b.t0 && a.type < b.type); });

  // ---- metrics
  auto mk = [&](const char* name, double v, double sigma, Quality q, const char* alg) {
    Metric m; m.name = name; m.unit = "m/s2"; m.value = v; m.uncertainty = sigma; m.quality = q; m.algorithm = alg; m.version = KINEMATICS_VERSION;
    m.warnings.push_back("cinemática de la trayectoria GNSS (antena del jinete); no es la aceleración medida por las IMU de la cincha");
    return m;
  };
  double latmax = -1, latsig = 0; int nsust_a = 0, nsust_d = 0;
  for (size_t i = 0; i < n; i++) {
    if (std::isnan(g.lat_accel[i]) || !usable_q(g, i) || g.lat_accel_sigma[i] > 2 * c.max_sigma) continue;
    if (std::fabs(g.lat_accel[i]) > latmax && std::fabs(g.lat_accel[i]) <= c.physical_max) { latmax = std::fabs(g.lat_accel[i]); latsig = g.lat_accel_sigma[i]; }
  }
  for (auto& e : r.events) { if (e.type == "ACELERACION_SOSTENIDA") nsust_a++; if (e.type == "DESACELERACION_SOSTENIDA") nsust_d++; }
  if (latmax >= 0) r.metrics.push_back(mk("aceleracion_lateral_maxima_estimada", latmax, latsig, latsig < 0.5 ? Quality::USABLE : Quality::POOR, "v·ω con ω de las pendientes locales de vN y vE; incertidumbre propagada"));
  Metric ms; ms.name = "eventos_aceleracion_sostenida"; ms.unit = "n"; ms.value = nsust_a; ms.algorithm = "histéresis sobre aceleración longitudinal"; ms.version = KINEMATICS_VERSION; ms.quality = Quality::USABLE;
  r.metrics.push_back(ms);
  ms.name = "eventos_desaceleracion_sostenida"; ms.value = nsust_d; r.metrics.push_back(ms);
  if (r.rejected_physical) { Metric m = ms; m.name = "estimaciones_aceleracion_descartadas"; m.value = r.rejected_physical; m.warnings = {"valores por encima del límite físico: artefactos de la medida"}; r.metrics.push_back(m); }
  return r;
}

// ------------------------------------------------------------------ circle fit
bool fit_circle(const std::vector<double>& x, const std::vector<double>& y, double* cx, double* cy, double* r, double* rms) {
  size_t n = x.size();
  if (n < 5) return false;
  double mx = dsp::mean(x), my = dsp::mean(y);
  // Kåsa: minimise sum (u² + v² + D u + E v + F)² with u, v centred
  double suu = 0, svv = 0, suv = 0, suz = 0, svz = 0, sz = 0;
  for (size_t i = 0; i < n; i++) {
    double u = x[i] - mx, v = y[i] - my, z = u * u + v * v;
    suu += u * u; svv += v * v; suv += u * v; suz += u * z; svz += v * z; sz += z;
  }
  double det = suu * svv - suv * suv;
  if (std::fabs(det) < 1e-9 * (suu + svv) * (suu + svv) || det == 0) return false;
  double uc = 0.5 * (suz * svv - svz * suv) / det, vc = 0.5 * (svz * suu - suz * suv) / det;
  double rr = std::sqrt(uc * uc + vc * vc + sz / n);
  double e = 0;
  for (size_t i = 0; i < n; i++) { double d = std::hypot(x[i] - mx - uc, y[i] - my - vc) - rr; e += d * d; }
  *cx = uc + mx; *cy = vc + my; *r = rr; *rms = std::sqrt(e / n);
  return std::isfinite(rr);
}

// ------------------------------------------------------------------ curves
CurveResult analyse_curves(const GnssResult& g, const CurveConfig& c) {
  CurveResult r;
  size_t n = g.t.size();
  if (n < 5) return r;
  auto valid = [&](size_t i) {
    return usable_q(g, i) && !std::isnan(g.curvature[i]) && !std::isnan(g.speed[i]) && g.speed[i] >= c.min_speed &&
           std::fabs(g.curvature[i]) > c.kappa_k_sigma * g.curvature_sigma[i] && std::fabs(g.curvature[i]) < 1.0 / c.min_radius;
  };
  double k_in = 1.0 / c.enter_radius, k_out = 1.0 / c.exit_radius;
  bool in = false; int sign = 0; size_t s0 = 0, last = 0;
  std::vector<std::pair<size_t, size_t>> spans;
  for (size_t i = 0; i < n; i++) {
    bool v = valid(i);
    double k = v ? g.curvature[i] : 0;
    if (!in) {
      if (v && std::fabs(k) >= k_in) { in = true; sign = k > 0 ? 1 : -1; s0 = last = i; }
      continue;
    }
    if (v && sign * k >= k_out) { last = i; continue; }
    // not (or no longer) turning: a short loss of estimate inside the curve is tolerated
    if (!v && g.t[i] - g.t[last] <= c.gap_tolerance_s && i + 1 < n) continue;
    spans.push_back({s0, last}); in = false;
    if (v && std::fabs(k) >= k_in) { in = true; sign = k > 0 ? 1 : -1; s0 = last = i; }   // immediate reverse turn
  }
  if (in) spans.push_back({s0, last});
  for (auto sp : spans) {
    size_t a = sp.first, b = sp.second;
    double dur = g.t[b] - g.t[a];
    double turn = 0;
    std::vector<double> radii, lat, xs, ys, vs;
    int bad = 0, tot = 0;
    for (size_t i = a; i <= b; i++) {
      tot++;
      if (!valid(i)) { bad++; continue; }
      double dt = (i + 1 < n) ? std::min(g.t[i + 1] - g.t[i], 0.5) : 0.125;
      turn += g.heading_rate[i] * dt;
      radii.push_back(1.0 / std::fabs(g.curvature[i]));
      lat.push_back(g.lat_accel[i]);
      vs.push_back(g.speed[i]);
      if (!std::isnan(g.x_e[i])) { xs.push_back(g.x_e[i]); ys.push_back(g.y_n[i]); }
    }
    if (dur < c.min_duration_s) { r.rejected_short++; continue; }
    if (std::fabs(turn) < c.min_heading_deg) { r.rejected_small_turn++; continue; }
    if (radii.size() < 4 || bad * 2 > tot) { r.rejected_quality++; continue; }
    Curve cv; cv.id = (int)r.curves.size() + 1;
    cv.direction = turn > 0 ? "DERECHA" : "IZQUIERDA";
    cv.t0 = g.t[a]; cv.t1 = g.t[b]; cv.i0 = a; cv.i1 = b; cv.heading_change_deg = turn;
    cv.radius_m = dsp::median(radii); cv.radius_sigma_m = 1.4826 * dsp::mad(radii);
    cv.v_entry = g.speed[a]; cv.v_exit = g.speed[b]; cv.v_mean = dsp::mean(vs); cv.v_min = *std::min_element(vs.begin(), vs.end());
    double s2 = 0, amax = 0;
    for (size_t i = a; i <= b; i++) if (valid(i)) { s2 += g.lat_accel_sigma[i] * g.lat_accel_sigma[i]; amax = std::max(amax, std::fabs(g.lat_accel[i])); }
    cv.lat_acc_mean = std::fabs(dsp::mean(lat)); cv.lat_acc_max = amax; cv.lat_acc_sigma = std::sqrt(s2 / radii.size());
    cv.distance_m = g.dist[b] - g.dist[a];
    double cx, cy, rr, rms;
    if (xs.size() >= 6 && std::fabs(turn) >= 45 && fit_circle(xs, ys, &cx, &cy, &rr, &rms) && rms < 0.2 * rr) {
      cv.radius_geom_m = rr; cv.center_e = cx; cv.center_n = cy; cv.center_from_fit = true;
    } else if (!xs.empty()) {
      size_t m = xs.size() / 2; cv.center_e = xs[m]; cv.center_n = ys[m];
      cv.warnings.push_back("arco corto: la referencia de posición es el punto medio del arco, no el centro");
    }
    // centre back to lat/lon (inverse of the tangent plane of analyse_gnss)
    size_t i0 = 0; while (i0 < n && std::isnan(g.x_e[i0])) i0++;
    if (i0 < n) {
      const double R = 6371008.8, d2r = PI / 180.0;
      double c0 = std::cos(g.lat[i0] * d2r);
      cv.center_lat = g.lat[i0] + cv.center_n / R / d2r;
      cv.center_lon = g.lon[i0] + cv.center_e / (R * c0) / d2r;
    }
    double rel = cv.radius_m > 0 ? cv.radius_sigma_m / cv.radius_m : 1;
    cv.quality = (bad == 0 && rel < 0.25) ? Quality::GOOD : (rel < 0.5 ? Quality::USABLE : Quality::POOR);
    if (cv.radius_geom_m > 0 && std::fabs(cv.radius_geom_m - cv.radius_m) > 0.3 * cv.radius_m)
      cv.warnings.push_back("el radio cinemático y el geométrico difieren más de un 30 %: trayectoria no circular");
    r.curves.push_back(cv);
  }
  Metric m; m.name = "curvas_detectadas"; m.unit = "n"; m.value = (double)r.curves.size(); m.algorithm = "curvatura ω/v con histéresis de radio y significancia |κ|>2σ"; m.version = CURVES_VERSION; m.quality = Quality::USABLE;
  r.metrics.push_back(m);
  return r;
}

}  // namespace avoeq
