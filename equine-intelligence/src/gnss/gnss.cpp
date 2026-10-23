#include "avo_eq/gnss.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>
#include <limits>

namespace avoeq {

static const double NaN = std::numeric_limits<double>::quiet_NaN();
static const char* ALG_VER = "1.0.0";

double corr_age_code_s(uint8_t code) {
  static const double up[] = {-1, 1, 2, 5, 10, 15, 20, 30, 45, 60, 90, 120, 1e9};
  return code < 13 ? up[code] : -1;
}

bool local_slope(const std::vector<double>& t, const std::vector<double>& y, const std::vector<double>& sy,
                 const std::vector<bool>& valid, size_t i, double h, double* slope, double* sigma) {
  // weighted least squares y = a + b (t - ti), weights 1/sy²
  double sw = 0, st = 0, sy_ = 0, stt = 0, sty = 0;
  int n = 0;
  size_t lo = i, hi = i;
  while (lo > 0 && t[i] - t[lo - 1] <= h) lo--;
  while (hi + 1 < t.size() && t[hi + 1] - t[i] <= h) hi++;
  double tmin = 1e300, tmax = -1e300;
  for (size_t k = lo; k <= hi; k++) {
    if (!valid[k] || std::isnan(y[k])) continue;
    double s = std::max(sy[k], 0.02);
    double w = 1.0 / (s * s), dt = t[k] - t[i];
    sw += w; st += w * dt; sy_ += w * y[k]; stt += w * dt * dt; sty += w * dt * y[k];
    tmin = std::min(tmin, dt); tmax = std::max(tmax, dt);
    n++;
  }
  // at least 3 points and both sides of the window represented (no one-sided extrapolation)
  if (n < 3 || tmin > -0.25 * h || tmax < 0.25 * h) return false;
  double den = sw * stt - st * st;
  if (den <= 0) return false;
  *slope = (sw * sty - st * sy_) / den;
  *sigma = std::sqrt(sw / den);
  return true;
}

static double hav(double la1, double lo1, double la2, double lo2) {
  const double R = 6371008.8, r = 3.14159265358979323846 / 180.0;
  double a = std::sin((la2 - la1) * r / 2), b = std::sin((lo2 - lo1) * r / 2);
  double h = a * a + std::cos(la1 * r) * std::cos(la2 * r) * b * b;
  return 2 * R * std::asin(std::sqrt(std::min(1.0, h)));
}

static Metric metric(const char* name, const char* unit, double v, Quality q, const char* alg) {
  Metric m; m.name = name; m.unit = unit; m.value = v; m.quality = q; m.algorithm = alg; m.version = ALG_VER;
  return m;
}

GnssResult analyse_gnss(const Session& s, const ValidationReport& v, const GnssConfig& c) {
  GnssResult r;
  const auto& g = s.gnss;
  size_t n = g.size();
  r.t = gnss_time_s(g);
  r.speed.assign(n, NaN); r.accel.assign(n, NaN); r.accel_sigma.assign(n, NaN);
  r.heading_rate.assign(n, NaN); r.radius.assign(n, NaN); r.dist.assign(n, 0); r.quality.assign(n, (uint8_t)Quality::UNUSABLE);
  if (n == 0) return r;
  const uint32_t HARD = GF_NO_FIX | GF_IMPOSSIBLE | GF_DUPLICATE | GF_TIME_BACKWARDS | GF_INVALID_LLH | GF_POS_JUMP;
  std::vector<bool> ok(n);
  std::vector<double> sp(n), sps(n), vn(n), ve(n);
  for (size_t i = 0; i < n; i++) {
    uint32_t f = i < v.gnss_flags.size() ? v.gnss_flags[i] : 0;
    ok[i] = !(f & HARD);
    Quality q = Quality::UNUSABLE;
    if (ok[i]) {
      RtkState st = rtk_state(g[i]);
      q = (st == RtkState::FIXED && !(f & (GF_HACC_HIGH | GF_SACC_HIGH))) ? Quality::GOOD
        : (st == RtkState::FLOAT || st == RtkState::DGNSS || st == RtkState::FIXED) ? Quality::USABLE : Quality::POOR;
      if (f & GF_SACC_HIGH) q = Quality::POOR;
    }
    r.quality[i] = (uint8_t)q;
    sp[i] = g[i].gspeed_ms; sps[i] = g[i].sacc_ms; vn[i] = g[i].veln_ms; ve[i] = g[i].vele_ms;
    if (ok[i]) r.speed[i] = sp[i];
  }
  // ---- acceleration and heading rate: local weighted slopes (no plain differences)
  for (size_t i = 0; i < n; i++) {
    if (!ok[i]) continue;
    double a, sa;
    if (local_slope(r.t, sp, sps, ok, i, c.deriv_half_window_s, &a, &sa)) { r.accel[i] = a; r.accel_sigma[i] = sa; }
    if (sp[i] >= c.min_speed_heading_ms) {
      double an, sn, ae, se;
      if (local_slope(r.t, vn, sps, ok, i, c.deriv_half_window_s, &an, &sn) && local_slope(r.t, ve, sps, ok, i, c.deriv_half_window_s, &ae, &se)) {
        double v2 = vn[i] * vn[i] + ve[i] * ve[i];
        double w = (vn[i] * ae - ve[i] * an) / v2;                // rad/s, positive = turning right (N→E)
        r.heading_rate[i] = w * 180.0 / 3.14159265358979323846;
        double rad = std::sqrt(v2) / std::max(std::fabs(w), 1e-9);
        r.radius[i] = rad > c.straight_radius_m ? NaN : rad;
      }
    }
  }
  // ---- distance between consecutive usable epochs; gaps are not bridged
  double d = 0, excluded_gap_s = 0;
  for (size_t i = 1; i < n; i++) {
    bool both = ok[i] && ok[i - 1] && !(v.gnss_flags.size() > i && (v.gnss_flags[i] & GF_GAP_BEFORE));
    if (both) d += hav(g[i - 1].lat_deg, g[i - 1].lon_deg, g[i].lat_deg, g[i].lon_deg);
    else if (r.t[i] > r.t[i - 1]) excluded_gap_s += r.t[i] - r.t[i - 1];
    r.dist[i] = d;
  }
  // speed integration as an independent distance estimate
  double d_int = 0;
  for (size_t i = 1; i < n; i++) if (ok[i] && ok[i - 1] && r.t[i] > r.t[i - 1] && r.t[i] - r.t[i - 1] < 1.0)
    d_int += 0.5 * (sp[i] + sp[i - 1]) * (r.t[i] - r.t[i - 1]);

  // ---- RTK statistics (time-weighted, each epoch owns the interval to the next one, capped at 2 periods)
  double dt_nom = v.gnss_nominal_hz > 0 ? 1.0 / v.gnss_nominal_hz : 0.125;
  RtkStats& k = r.rtk;
  bool fixed_seen = false, in_outage = false;
  double outage_start = 0, outage_sum = 0; uint32_t outages = 0;
  std::vector<double> hacc_fixed;
  for (size_t i = 0; i < n; i++) {
    double dt = (i + 1 < n) ? std::min(std::max(r.t[i + 1] - r.t[i], 0.0), 2 * dt_nom) : dt_nom;
    RtkState st = ok[i] ? rtk_state(g[i]) : RtkState::NONE;
    k.total_s += dt;
    switch (st) { case RtkState::FIXED: k.fixed_s += dt; break; case RtkState::FLOAT: k.float_s += dt; break;
      case RtkState::DGNSS: k.dgnss_s += dt; break; case RtkState::GNSS: k.gnss_s += dt; break; default: k.none_s += dt; }
    if (st == RtkState::FIXED) {
      hacc_fixed.push_back(g[i].hacc_m);
      if (!fixed_seen) { fixed_seen = true; k.time_to_first_fix_s = r.t[i]; }
      if (in_outage) { double dur = r.t[i] - outage_start; outage_sum += dur; outages++; k.longest_outage_s = std::max(k.longest_outage_s, dur); in_outage = false; }
    } else if (fixed_seen && !in_outage) { in_outage = true; outage_start = r.t[i]; k.fix_losses++; }
    double age = corr_age_code_s((uint8_t)((g[i].flags3 >> 1) & 0x0F));
    if (age >= 0) k.corr_age_max_s = std::max(k.corr_age_max_s, age);
  }
  if (in_outage) { double dur = r.t[n - 1] - outage_start; outage_sum += dur; outages++; k.longest_outage_s = std::max(k.longest_outage_s, dur); }
  k.mean_outage_s = outages ? outage_sum / outages : 0;
  if (!hacc_fixed.empty()) k.hacc_median_fixed_m = dsp::median(hacc_fixed);

  // ---- metrics
  double duration = r.t[n - 1] - r.t[0];
  std::vector<double> good_speed;
  double vmax = -1; size_t imax = 0;
  for (size_t i = 0; i < n; i++) if (ok[i] && r.quality[i] <= (uint8_t)Quality::USABLE) {
    good_speed.push_back(sp[i]);
    if (sp[i] > vmax) { vmax = sp[i]; imax = i; }
  }
  double fix_frac = k.total_s > 0 ? k.fixed_s / k.total_s : 0;
  Quality global = fix_frac > 0.9 ? Quality::GOOD : fix_frac > 0.5 ? Quality::USABLE : Quality::POOR;
  Metric m = metric("distancia", "m", d, global, "haversine entre épocas válidas consecutivas, sin puentear huecos");
  m.samples_excluded = (uint32_t)std::count(ok.begin(), ok.end(), false);
  if (excluded_gap_s > 0) m.warnings.push_back("tiempo excluido por huecos o datos no válidos: " + std::to_string(excluded_gap_s) + " s");
  double rel = d > 0 ? std::fabs(d - d_int) / d : 0;
  if (rel > 0.05) m.warnings.push_back("la distancia por posiciones y por integración de velocidad difieren más de un 5 %");
  m.uncertainty = std::fabs(d - d_int);
  r.metrics.push_back(m);
  r.metrics.push_back(metric("duracion", "s", duration, Quality::GOOD, "tiempo GNSS (iTOW) primera-última época"));
  if (vmax >= 0) {
    Metric mv = metric("velocidad_maxima", "m/s", vmax, (Quality)r.quality[imax], "máximo de gSpeed del receptor en épocas utilizables");
    mv.uncertainty = g[imax].sacc_ms;
    r.metrics.push_back(mv);
  }
  r.metrics.push_back(metric("velocidad_media", "m/s", duration > 0 ? d / duration : 0, global, "distancia / duración"));
  // accelerations: only where the slope uncertainty is acceptable
  double amax = NaN, amin = NaN, samax = 0, samin = 0;
  for (size_t i = 0; i < n; i++) {
    if (std::isnan(r.accel[i]) || r.accel_sigma[i] > c.accel_usable_sigma) continue;
    if (std::isnan(amax) || r.accel[i] > amax) { amax = r.accel[i]; samax = r.accel_sigma[i]; }
    if (std::isnan(amin) || r.accel[i] < amin) { amin = r.accel[i]; samin = r.accel_sigma[i]; }
  }
  if (!std::isnan(amax)) {
    Metric a1 = metric("aceleracion_maxima", "m/s2", amax, samax <= c.accel_good_sigma ? Quality::GOOD : Quality::USABLE,
                       "pendiente por mínimos cuadrados ponderados (1/sAcc²) en ±0,5 s");
    a1.uncertainty = samax; a1.warnings.push_back("cinemática del jinete (antena en el chaleco), no del centro de masas del caballo");
    r.metrics.push_back(a1);
    Metric a2 = metric("desaceleracion_maxima", "m/s2", amin, samin <= c.accel_good_sigma ? Quality::GOOD : Quality::USABLE, a1.algorithm.c_str());
    a2.uncertainty = samin; a2.warnings = a1.warnings;
    r.metrics.push_back(a2);
  }
  // curves
  double turn_abs = 0, curve_t = 0, curve_v = 0;
  for (size_t i = 0; i + 1 < n; i++) {
    double dt = std::min(std::max(r.t[i + 1] - r.t[i], 0.0), 2 * dt_nom);
    if (!std::isnan(r.heading_rate[i])) turn_abs += std::fabs(r.heading_rate[i]) * dt;
    if (!std::isnan(r.radius[i]) && r.radius[i] < c.curve_radius_m) { curve_t += dt; curve_v += sp[i] * dt; }
  }
  r.metrics.push_back(metric("giro_total", "deg", turn_abs, global, "integral de |velocidad angular del vector velocidad|"));
  r.metrics.push_back(metric("tiempo_en_curva", "s", curve_t, global, "radio < 30 m (radio = v / |ω|)"));
  if (curve_t > 0) r.metrics.push_back(metric("velocidad_media_en_curva", "m/s", curve_v / curve_t, global, "media temporal de gSpeed con radio < 30 m"));
  // splits
  if (d > 0) {
    double next = c.split_m; size_t i0 = 0;
    for (size_t i = 1; i < n; i++) if (r.dist[i] >= next) {
      GnssResult::Split sp_; sp_.from_m = r.dist[i0]; sp_.to_m = r.dist[i]; sp_.t0 = r.t[i0]; sp_.t1 = r.t[i];
      sp_.mean_speed = (sp_.to_m - sp_.from_m) / std::max(1e-6, sp_.t1 - sp_.t0);
      r.splits.push_back(sp_); i0 = i; next += c.split_m;
    }
  }
  // speed distribution (time per band)
  r.speed_hist_edges = {0, 0.4, 2.2, 4.4, 6.0, 8.0, 10.0, 12.0, 15.0, 25.0};
  r.speed_hist_s.assign(r.speed_hist_edges.size() - 1, 0);
  for (size_t i = 0; i + 1 < n; i++) {
    if (!ok[i]) continue;
    double dt = std::min(std::max(r.t[i + 1] - r.t[i], 0.0), 2 * dt_nom);
    for (size_t b = 0; b + 1 < r.speed_hist_edges.size(); b++)
      if (sp[i] >= r.speed_hist_edges[b] && sp[i] < r.speed_hist_edges[b + 1]) { r.speed_hist_s[b] += dt; break; }
  }
  return r;
}

}  // namespace avoeq
