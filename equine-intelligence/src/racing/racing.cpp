// AVO Track Work 1.0.0 (entrenamiento de caballos de carreras). Ver include/avo_eq/racing.h y docs/algoritmos/13_TRABAJO_PISTA.md.
#include "avo_eq/racing.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>
#include "avo_eq/dsp.h"
#include "avo_eq/json.h"

namespace avoeq {

bool breed_profile(const std::string& name, BreedProfile* p) {
  BreedProfile b;
  if (name == "PSI" || name == "PURA_SANGRE_INGLES" || name == "THOROUGHBRED") {
    b.name = "PSI"; b.work_speed = 11.0; b.fast_speed = 14.5; b.high_speed = 15.0;
    b.ref_speed[0] = 14.0; b.ref_speed[1] = 16.0; b.sf_min = 1.6; b.sf_max = 2.9; b.sl_min = 3.0; b.sl_max = 9.0;
  } else if (name == "ARABE" || name == "PURA_SANGRE_ARABE" || name == "ARABIAN") {
    b.name = "ARABE"; b.work_speed = 10.0; b.fast_speed = 13.0; b.high_speed = 13.5;
    b.ref_speed[0] = 13.0; b.ref_speed[1] = 15.0; b.sf_min = 1.6; b.sf_max = 3.0; b.sl_min = 3.0; b.sl_max = 8.5;
  } else if (name != "GENERICO" && !name.empty()) {
    return false;
  }
  *p = b;
  return true;
}

namespace {

const double kNaN = std::nan("");
const double G = 9.80665;

double median_of(std::vector<double> v) { v.erase(std::remove_if(v.begin(), v.end(), [](double x) { return std::isnan(x); }), v.end()); return v.empty() ? kNaN : dsp::median(v); }
double pct(std::vector<double> v, double p) {
  v.erase(std::remove_if(v.begin(), v.end(), [](double x) { return std::isnan(x); }), v.end());
  if (v.empty()) return kNaN;
  std::sort(v.begin(), v.end());
  double x = p * (v.size() - 1); size_t i = (size_t)x;
  return i + 1 < v.size() ? v[i] + (x - i) * (v[i + 1] - v[i]) : v.back();
}

// Linear interpolation of y(t) (t increasing); NaN outside or across NaN neighbours.
double interp(const std::vector<double>& t, const std::vector<double>& y, double x) {
  if (t.size() < 2 || std::isnan(x) || x < t.front() || x > t.back()) return kNaN;
  size_t i = std::upper_bound(t.begin(), t.end(), x) - t.begin();
  if (i == 0) return y[0];
  if (i >= t.size()) return y.back();
  double t0 = t[i - 1], t1 = t[i];
  if (std::isnan(y[i - 1]) || std::isnan(y[i])) return std::isnan(y[i - 1]) ? y[i] : y[i - 1];
  return t1 > t0 ? y[i - 1] + (x - t0) / (t1 - t0) * (y[i] - y[i - 1]) : y[i];
}

// Time at which cumulative distance reaches d (between usable epochs).
double time_at_dist(const std::vector<double>& t, const std::vector<double>& dist, size_t i0, size_t i1, double d) {
  for (size_t i = i0 + 1; i <= i1; i++) {
    if (std::isnan(dist[i]) || std::isnan(dist[i - 1])) continue;
    if (dist[i] >= d && dist[i - 1] <= d) {
      double dd = dist[i] - dist[i - 1];
      return dd > 0 ? t[i - 1] + (d - dist[i - 1]) / dd * (t[i] - t[i - 1]) : t[i];
    }
  }
  return kNaN;
}

int gait_slot(Gait g) { return g == Gait::WALK ? 0 : g == Gait::TROT ? 1 : g == Gait::CANTER_GALLOP ? 2 : -1; }

struct GaitLookup {
  const GaitResult& g;
  explicit GaitLookup(const GaitResult& r) : g(r) {}
  Gait at(double t) const {   // segments are in time order and do not overlap
    if (std::isnan(t) || g.segments.empty()) return Gait::UNKNOWN;
    auto it = std::upper_bound(g.segments.begin(), g.segments.end(), t, [](double x, const GaitSegment& s) { return x < s.t0; });
    if (it == g.segments.begin()) return Gait::UNKNOWN;
    --it;
    return t < it->t1 ? it->gait : Gait::UNKNOWN;
  }
};

struct V3 { double x = 0, y = 0, z = 0; };
inline V3 sub(V3 a, V3 b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
inline V3 mul(V3 a, double k) { return {a.x * k, a.y * k, a.z * k}; }
inline double dot(V3 a, V3 b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(V3 a, V3 b) { return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}; }
inline double norm(V3 a) { return std::sqrt(dot(a, a)); }
inline V3 unit(V3 a) { double n = norm(a); return n > 0 ? mul(a, 1.0 / n) : V3{0, 0, 1}; }

// Signals of one uniform piece in the horse frame.
struct Piece {
  double fs = 0, t0 = 0;             // girth seconds
  std::vector<double> tg;            // GNSS seconds per sample (NaN when unmapped)
  std::vector<V3> dyn, up, grav;     // dynamic acceleration (g), unit vertical, low-passed specific force (g) (sensor frame)
  std::vector<double> av, vedba, wv; // vertical dynamic (g, + up), |dyn| (g), turn rate about the vertical (deg/s, + left)
  std::vector<double> along, lat;    // horizontal dynamic along / across the forward axis (g)
  std::vector<double> amax_lsb;      // max |raw axis| per sample (saturation)
  std::vector<Gait> gait;
};

double corr(const double* a, const double* b, size_t n) {
  double ma = 0, mb = 0; for (size_t i = 0; i < n; i++) { ma += a[i]; mb += b[i]; } ma /= n; mb /= n;
  double sab = 0, saa = 0, sbb = 0;
  for (size_t i = 0; i < n; i++) { double x = a[i] - ma, y = b[i] - mb; sab += x * y; saa += x * x; sbb += y * y; }
  return saa > 0 && sbb > 0 ? sab / std::sqrt(saa * sbb) : kNaN;
}

void fit_line(const std::vector<double>& x, const std::vector<double>& y, double* a, double* b, double* r) {
  size_t n = x.size();
  double mx = 0, my = 0; for (size_t i = 0; i < n; i++) { mx += x[i]; my += y[i]; } mx /= n; my /= n;
  double sxy = 0, sxx = 0, syy = 0;
  for (size_t i = 0; i < n; i++) { sxy += (x[i] - mx) * (y[i] - my); sxx += (x[i] - mx) * (x[i] - mx); syy += (y[i] - my) * (y[i] - my); }
  if (sxx <= 0) { *a = *b = *r = kNaN; return; }
  *b = sxy / sxx; *a = my - *b * mx; *r = syy > 0 ? sxy / std::sqrt(sxx * syy) : kNaN;
}

// Track slice of one effort or pass: first and last points are its exact limits (possibly interpolated).
struct Track { std::vector<double> t, d, v, a; };

void fill_effort(Effort* E, const Track& T, const RacingResult& r, const RacingConfig& c) {
  Effort& e = *E;
  size_t n = T.t.size(), i0 = 0, i1 = n - 1;
  e.t0 = T.t[i0]; e.t1 = T.t[i1]; e.duration_s = e.t1 - e.t0;
  double d0 = T.d[i0], d1 = T.d[i1];
  e.distance_m = d1 - d0; e.speed_mean = e.duration_s > 0 ? e.distance_m / e.duration_s : kNaN;
  // vmax over a 1 s moving mean (no single-epoch spikes)
  double best = -1, tbest = e.t0;
  for (size_t k = i0; k <= i1; k++) {
    double s = 0; int m = 0;
    for (size_t q = k; q <= i1 && T.t[q] - T.t[k] < 1.0 + 1e-9; q++) if (!std::isnan(T.v[q])) { s += T.v[q]; m++; }
    if (m && s / m > best) { best = s / m; tbest = T.t[k]; }
  }
  e.vmax = best > 0 ? best : kNaN; e.t_to_vmax_s = tbest - e.t0;
  e.dist_above_90_m = 0;
  for (size_t k = i0 + 1; k <= i1; k++)
    if (!std::isnan(T.v[k]) && !std::isnan(T.v[k - 1]) && !std::isnan(T.d[k]) && !std::isnan(T.d[k - 1]) && 0.5 * (T.v[k] + T.v[k - 1]) >= 0.9 * e.vmax)
      e.dist_above_90_m += T.d[k] - T.d[k - 1];
  for (size_t k = i0; k <= i1; k++) if (!std::isnan(T.a[k]) && (std::isnan(e.accel_max) || T.a[k] > e.accel_max)) e.accel_max = T.a[k];
  for (double d = d0 + c.split_m; d <= d1 + 1e-6; d += c.split_m) {
    Sectional s; s.from_m = d - c.split_m - d0; s.to_m = d - d0;
    double ta = s.from_m == 0 ? e.t0 : time_at_dist(T.t, T.d, i0, i1, d - c.split_m), tb = time_at_dist(T.t, T.d, i0, i1, std::min(d, d1));
    if (!std::isnan(ta) && !std::isnan(tb) && tb > ta) { s.time_s = tb - ta; s.speed = c.split_m / s.time_s; }
    e.sectionals.push_back(s);
  }
  // last piece up to the end (the finish line of a course) when it is at least a quarter of a split
  {
    double done = c.split_m * std::floor((d1 - d0) / c.split_m + 1e-9), rest = (d1 - d0) - done;
    if (rest >= 0.25 * c.split_m) {
      Sectional s; s.from_m = done; s.to_m = d1 - d0;
      double ta = done == 0 ? e.t0 : time_at_dist(T.t, T.d, i0, i1, d0 + done);
      if (!std::isnan(ta) && e.t1 > ta) { s.time_s = e.t1 - ta; s.speed = rest / s.time_s; }
      e.sectionals.push_back(s);
    }
  }
  auto tail = [&](double D, double* tt, double* vv) {
    if (e.distance_m < D) return;
    double ta = time_at_dist(T.t, T.d, i0, i1, d1 - D);
    if (!std::isnan(ta) && e.t1 > ta) { *tt = e.t1 - ta; *vv = D / *tt; }
  };
  tail(200, &e.last_200_s, &e.v_last_200);
  tail(400, &e.last_400_s, &e.v_last_400);
  if (e.distance_m >= 400 && !std::isnan(e.v_last_200) && e.vmax > 0) e.fatigue_pct = 100.0 * (e.vmax - e.v_last_200) / e.vmax;
  const double Ds[] = {200, 400, 600, 800, 1000, 1200, 1600};
  for (double D : Ds) {
    if (D > e.distance_m + 1e-6) break;
    BestSplit b; b.distance_m = D;
    for (size_t k = i0; k <= i1; k++) {
      if (std::isnan(T.d[k]) || T.d[k] + D > d1 + 1e-6) continue;
      double tb = time_at_dist(T.t, T.d, k, i1, T.d[k] + D);
      if (!std::isnan(tb) && (std::isnan(b.time_s) || tb - T.t[k] < b.time_s)) { b.time_s = tb - T.t[k]; b.t0 = T.t[k]; }
    }
    e.best.push_back(b);
  }
  // strides of this effort
  std::vector<double> sv, sf, sl, sfx, slx, sft, slt;
  int last = 0; double last_t = -1e9;
  for (const auto& s : r.strides) {
    double tm = 0.5 * (s.t0 + s.t1);
    if (tm < e.t0 || tm > e.t1) continue;
    e.strides++;
    if (s.lead > 0) e.lead_left++; else if (s.lead < 0) e.lead_right++;
    if (s.lead != 0) { if (last != 0 && s.lead != last && s.t0 - last_t < 2.0) e.lead_changes++; last = s.lead; last_t = s.t1; }
    sft.push_back(s.freq_hz);
    if (!std::isnan(s.length_m)) slt.push_back(s.length_m);
    if (std::isnan(s.speed) || std::isnan(s.length_m)) continue;
    if (s.speed >= 0.95 * e.vmax) { sfx.push_back(s.freq_hz); slx.push_back(s.length_m); }
    if (s.speed >= c.breed.work_speed) { sv.push_back(s.speed); sf.push_back(s.freq_hz); sl.push_back(s.length_m); }
  }
  e.sf_at_vmax = median_of(sfx); e.sl_at_vmax = median_of(slx);
  e.sf_max = pct(sft, 0.95); e.sl_max = pct(slt, 0.95);
  if (sv.size() >= 8) {
    double vmin = *std::min_element(sv.begin(), sv.end()), vmx = *std::max_element(sv.begin(), sv.end());
    if (vmx - vmin >= 1.5) {
      double rl;
      fit_line(sv, sf, &e.sf_icpt, &e.sf_slope, &e.fit_r_sf);
      fit_line(sv, sl, &e.sl_icpt, &e.sl_slope, &rl);
      for (int k = 0; k < 2; k++) {
        double vr = c.breed.ref_speed[k];
        if (vr >= vmin - 0.25 && vr <= vmx + 0.25) { e.sf_ref[k] = e.sf_icpt + e.sf_slope * vr; e.sl_ref[k] = e.sl_icpt + e.sl_slope * vr; }
      }
    }
  }
}

}  // namespace

RacingResult analyse_racing(const GnssResult& g, const std::vector<ImuSeries>& imu, const ClockMap girth_to_gnss[3],
                            const GaitResult& gait, uint8_t imu_units, const RacingConfig& c, double itow0_ms) {
  RacingResult r;
  // iTOW (ms) -> session seconds (same base as g.t), across a week rollover
  auto t_of_itow = [&](double itow) {
    if (std::isnan(itow) || std::isnan(itow0_ms)) return kNaN;
    const double WEEK = 604800000.0;
    double d = itow - itow0_ms;
    if (d < -WEEK / 2) d += WEEK; else if (d > WEEK / 2) d -= WEEK;
    return d / 1000.0;
  };
  // slice of the track between two times with interpolated ends
  auto make_track = [&](double a, double b, Track* T) {
    size_t n = g.t.size();
    T->t.push_back(a); T->d.push_back(interp(g.t, g.dist, a)); T->v.push_back(interp(g.t, g.speed, a)); T->a.push_back(interp(g.t, g.accel, a));
    for (size_t k = 0; k < n; k++)
      if (g.t[k] > a && g.t[k] < b) { T->t.push_back(g.t[k]); T->d.push_back(g.dist[k]); T->v.push_back(g.speed[k]); T->a.push_back(g.accel[k]); }
    T->t.push_back(b); T->d.push_back(interp(g.t, g.dist, b)); T->v.push_back(interp(g.t, g.speed, b)); T->a.push_back(interp(g.t, g.accel, b));
    return !std::isnan(T->d.front()) && !std::isnan(T->d.back());
  };
  r.profile = c.breed.name;
  GaitLookup gl(gait);

  // ================================================================ A. girth in the horse frame
  const ImuSeries* ser = nullptr;
  for (const auto& s : imu) if (s.imu_id == 0) ser = &s;
  if (!ser) for (const auto& s : imu) if (!ser || s.samples > ser->samples) ser = &s;
  std::vector<Piece> pieces;
  if (!ser || ser->samples < 100 || ser->fs <= 0) {
    r.scale = "SIN_CINCHA";
    r.warnings.push_back("sin datos de cincha: solo análisis GNSS de los trabajos");
  } else {
    r.has_imu = true;
    const ClockMap& map = girth_to_gnss[std::min<uint8_t>(ser->imu_id, 2)];
    double deg_per_lsb;
    if (imu_units == 1) {
      r.scale = "BNO085"; r.g_lsb = G * 256.0; deg_per_lsb = 57.29577951308232 / 512.0;
    } else {
      std::vector<double> m;
      for (const auto& p : ser->pieces) for (size_t i = 0; i < p.amag.size(); i += 5) m.push_back(p.amag[i]);
      r.scale = "GRAVEDAD_ESTIMADA"; r.g_lsb = dsp::median(m); deg_per_lsb = 0.07;
      r.warnings.push_back("unidades de la cincha no declaradas: escala por la gravedad (mediana de |a|) y giro con la escala nominal del LSM6 (70 mdps/LSB)");
    }
    if (!(r.g_lsb > 0)) { r.has_imu = false; r.scale = "SIN_CINCHA"; r.warnings.push_back("escala de la cincha no válida"); }
    const double fs = ser->fs;
    size_t good_frame = 0, total = 0;
    for (const auto& sp : ser->pieces) {
      if (!r.has_imu) break;
      size_t n = sp.amag.size();
      if (n < (size_t)(4 * fs)) continue;
      Piece P; P.fs = fs; P.t0 = sp.t0;
      std::vector<double> ax(n), ay(n), az(n);
      for (size_t i = 0; i < n; i++) { ax[i] = sp.ax[i] / r.g_lsb; ay[i] = sp.ay[i] / r.g_lsb; az[i] = sp.az[i] / r.g_lsb; }
      dsp::Biquad lp = dsp::butter_lowpass(c.gravity_lp_hz, fs);
      std::vector<double> gx = dsp::filtfilt(lp, ax), gy = dsp::filtfilt(lp, ay), gz = dsp::filtfilt(lp, az);
      P.tg.resize(n); P.dyn.resize(n); P.up.resize(n); P.grav.resize(n); P.av.resize(n); P.vedba.resize(n); P.wv.resize(n); P.amax_lsb.resize(n); P.gait.resize(n);
      for (size_t i = 0; i < n; i++) {
        V3 gv{gx[i], gy[i], gz[i]}, a{ax[i], ay[i], az[i]};
        double gn = norm(gv);
        total++; if (std::fabs(gn - 1) < 0.15) good_frame++;
        V3 u = unit(gv);
        V3 d = sub(a, gv);
        P.up[i] = u; P.dyn[i] = d; P.grav[i] = gv;
        P.av[i] = dot(d, u); P.vedba[i] = norm(d);
        V3 w{sp.gx[i] * deg_per_lsb, sp.gy[i] * deg_per_lsb, sp.gz[i] * deg_per_lsb};
        P.wv[i] = dot(w, u);
        P.amax_lsb[i] = std::max({std::fabs((double)sp.ax[i]), std::fabs((double)sp.ay[i]), std::fabs((double)sp.az[i])});
        double tgi;
        P.tg[i] = map.map(sp.t0 + i / fs, &tgi) ? tgi : kNaN;
        P.gait[i] = gl.at(P.tg[i]);
      }
      // the turn rate is smoothed: oscillation of the trunk inside the stride is not a turn
      P.wv = dsp::filtfilt(dsp::butter_lowpass(1.0, fs), P.wv);
      pieces.push_back(std::move(P));
    }
    r.frame_quality = total ? (double)good_frame / total : kNaN;
    if (r.has_imu && pieces.empty()) { r.has_imu = false; r.scale = "SIN_CINCHA"; r.warnings.push_back("tramos de cincha demasiado cortos (< 4 s)"); }
  }

  if (r.has_imu) {
    // moving: gait known and not stopped, or (no GNSS map) VeDBA above 0.08 g over 1 s
    auto moving = [&](const Piece& P, size_t i, const std::vector<double>& vlp) {
      Gait gg = P.gait[i];
      if (gg != Gait::UNKNOWN && gg != Gait::INSUFFICIENT_DATA) return gg != Gait::STOPPED;
      return vlp[i] > 0.08;
    };
    // forward axis: principal horizontal direction of the dynamic acceleration while moving (session plane)
    V3 upm{0, 0, 0};
    for (const auto& P : pieces) for (size_t i = 0; i < P.up.size(); i += 4) upm = {upm.x + P.up[i].x, upm.y + P.up[i].y, upm.z + P.up[i].z};
    upm = unit(upm);
    V3 ref = std::fabs(upm.x) < 0.9 ? V3{1, 0, 0} : V3{0, 1, 0};
    V3 e1 = unit(cross(upm, ref)), e2 = cross(upm, e1);
    double s11 = 0, s12 = 0, s22 = 0;
    std::vector<std::vector<double>> vlps;
    for (const auto& P : pieces) {
      vlps.push_back(dsp::filtfilt(dsp::butter_lowpass(0.5, P.fs), P.vedba));
      const auto& vlp = vlps.back();
      for (size_t i = 0; i < P.dyn.size(); i += 2) {
        if (!moving(P, i, vlp)) continue;
        V3 h = sub(P.dyn[i], mul(P.up[i], P.av[i]));
        double p = dot(h, e1), q = dot(h, e2);
        s11 += p * p; s12 += p * q; s22 += q * q;
      }
    }
    double tr = s11 + s22, det = s11 * s22 - s12 * s12, l1 = tr / 2 + std::sqrt(std::max(0.0, tr * tr / 4 - det));
    double fx = s12, fy = l1 - s11;
    if (std::fabs(fx) + std::fabs(fy) < 1e-12) { fx = 1; fy = 0; }
    V3 fwd = unit({e1.x * fx + e2.x * fy, e1.y * fx + e2.y * fy, e1.z * fx + e2.z * fy});
    double l2 = tr - l1;
    if (l1 > 0 && l2 / l1 > 0.7) r.warnings.push_back("eje de avance poco definido (aceleración horizontal casi isótropa)");
    for (auto& P : pieces) {
      P.along.resize(P.dyn.size()); P.lat.resize(P.dyn.size());
      for (size_t i = 0; i < P.dyn.size(); i++) {
        V3 h = sub(P.dyn[i], mul(P.up[i], P.av[i]));
        V3 lat = cross(P.up[i], fwd);
        P.along[i] = dot(h, fwd); P.lat[i] = dot(h, lat);
      }
    }
    // sign of the forward axis: a sustained acceleration a tilts the low-passed specific force by a/g toward the
    // motion, so its component along the axis follows the GNSS longitudinal acceleration (or its opposite)
    {
      std::vector<double> xa, xg;
      for (auto& P : pieces) {
        for (size_t i = 0; i < P.grav.size(); i += (size_t)std::max(1.0, P.fs / 5)) {
          double ga = interp(g.t, g.accel, P.tg[i]);
          if (!std::isnan(ga)) { xa.push_back(dot(P.grav[i], fwd)); xg.push_back(ga / G); }
        }
      }
      double rr = xa.size() > 50 ? corr(xa.data(), xg.data(), xa.size()) : kNaN;
      if (!std::isnan(rr) && std::fabs(rr) > 0.3) {
        r.forward_sign_known = true;
        if (rr < 0) for (auto& P : pieces) for (size_t i = 0; i < P.along.size(); i++) { P.along[i] = -P.along[i]; P.lat[i] = -P.lat[i]; }
      } else {
        r.warnings.push_back("sentido del eje de avance sin confirmar con el GNSS (aceleraciones longitudinales insuficientes)");
      }
    }

    // VeDBA and turns
    double vsum = 0, vdt = 0, gsum[3] = {0, 0, 0}, gdt[3] = {0, 0, 0};
    for (size_t k = 0; k < pieces.size(); k++) {
      const Piece& P = pieces[k];
      const auto& vlp = vlps[k];
      double dt = 1.0 / P.fs;
      r.imu_seconds += P.dyn.size() * dt;
      for (size_t i = 0; i < P.dyn.size(); i++) {
        if (P.amax_lsb[i] >= (r.scale == "BNO085" ? 0.98 * 8 * r.g_lsb : 32700)) r.saturated_samples++;
        if (!moving(P, i, vlp)) continue;
        vsum += P.vedba[i] * dt; vdt += dt;
        int gs = gait_slot(P.gait[i]);
        if (gs >= 0) { gsum[gs] += P.vedba[i] * dt; gdt[gs] += dt; }
        double w = P.wv[i];
        if (std::fabs(w) >= c.turn_min_deg_s) {
          TurnStats* ts[2] = {&r.turns_total, gs >= 0 ? &r.turns_gait[gs] : nullptr};
          for (TurnStats* x : ts) {
            if (!x) continue;
            if (w > 0) { x->left_s += dt; x->left_deg += w * dt; } else { x->right_s += dt; x->right_deg += -w * dt; }
          }
        }
      }
    }
    if (vdt > 0) { r.vedba_mean_g = vsum / vdt; r.vedba_load_gmin = vsum / 60.0; }
    for (int k = 0; k < 3; k++) if (gdt[k] > 5) r.vedba_gait[k] = gsum[k] / gdt[k];
    if (r.saturated_samples) {
      char b[160]; snprintf(b, sizeof(b), "%u muestras de la cincha en el límite del rango (±8 g): picos recortados", r.saturated_samples);
      r.warnings.push_back(b);
    }

    // ================================================================ B. strides in canter / gallop
    for (auto& P : pieces) {
      size_t n = P.av.size();
      size_t i = 0;
      while (i < n) {
        if (P.gait[i] != Gait::CANTER_GALLOP) { i++; continue; }
        size_t j = i; while (j < n && P.gait[j] == Gait::CANTER_GALLOP) j++;
        if (j - i >= (size_t)(3 * P.fs)) {
          std::vector<double> seg(P.av.begin() + i, P.av.begin() + j);
          dsp::Fundamental f0 = dsp::fundamental(seg, P.fs, c.breed.sf_min * 0.8, c.breed.sf_max * 1.1, 0.25);
          if (f0.freq_hz > 0) {
            std::vector<double> sm = dsp::filtfilt(dsp::butter_lowpass(std::min(1.6 * f0.freq_hz, 0.45 * P.fs), P.fs), seg);
            std::vector<double> lat_bp = dsp::bandpass_zero_phase(std::vector<double>(P.lat.begin() + i, P.lat.begin() + j), 0.5, 8.0, P.fs);
            std::vector<double> av_bp = dsp::bandpass_zero_phase(seg, 0.5, 8.0, P.fs);
            auto pk = dsp::find_peaks(sm, 0.0, (size_t)std::max(2.0, 0.6 * P.fs / f0.freq_hz));
            for (size_t k = 1; k < pk.size(); k++) {
              size_t a0 = pk[k - 1], a1 = pk[k];
              double dur = (a1 - a0) / P.fs;
              if (dur < 0.6 / f0.freq_hz || dur > 1.5 / f0.freq_hz) continue;
              double fr = 1.0 / dur;
              if (fr < c.breed.sf_min || fr > c.breed.sf_max) continue;
              Stride s;
              s.t0 = P.tg[i + a0]; s.t1 = P.tg[i + a1];
              if (std::isnan(s.t0) || std::isnan(s.t1)) continue;
              s.duration_s = dur; s.freq_hz = fr;
              double vp = -1e9, vs = 0, ys = 0;
              std::vector<double> acc;
              for (size_t q = a0; q < a1; q++) {
                vp = std::max(vp, seg[q]); vs += P.vedba[i + q]; ys += P.wv[i + q];
                acc.push_back(seg[q] * G);
              }
              size_t m = a1 - a0;
              s.vert_peak_g = vp; s.vedba_g = vs / m; s.yaw_deg_s = ys / m;
              // vertical displacement: double integration inside the stride, removing mean velocity and position
              {
                double dt = 1.0 / P.fs, vel = 0, pos = 0;
                std::vector<double> v(m), x(m);
                double ma = 0; for (double a : acc) ma += a; ma /= m;
                for (size_t q = 0; q < m; q++) { vel += (acc[q] - ma) * dt; v[q] = vel; }
                double mv = 0; for (double a : v) mv += a; mv /= m;
                for (size_t q = 0; q < m; q++) { pos += (v[q] - mv) * dt; x[q] = pos; }
                // remove the linear trend left by the integration
                double slope = m > 1 ? (x[m - 1] - x[0]) / (m - 1) : 0;
                double lo = 1e9, hi = -1e9;
                for (size_t q = 0; q < m; q++) { double y = x[q] - slope * q; lo = std::min(lo, y); hi = std::max(hi, y); }
                s.vert_disp_m = hi - lo;
              }
              s.lat_feature = corr(lat_bp.data() + a0, av_bp.data() + a0, m);
              double v0 = interp(g.t, g.speed, s.t0), v1 = interp(g.t, g.speed, s.t1);
              if (!std::isnan(v0) && !std::isnan(v1)) {
                s.speed = 0.5 * (v0 + v1); s.length_m = s.speed * dur;
                if (s.length_m < c.breed.sl_min || s.length_m > c.breed.sl_max) s.length_m = kNaN;
              }
              s.in_curve = std::fabs(s.yaw_deg_s) >= c.turn_min_deg_s;
              r.strides.push_back(s);
            }
          }
        }
        i = j;
      }
    }
    std::sort(r.strides.begin(), r.strides.end(), [](const Stride& a, const Stride& b) { return a.t0 < b.t0; });

    // ================================================================ C. lead (experimental)
    double sign = 0;
    int nc = 0, agree = 0;
    for (const auto& s : r.strides)
      if (s.in_curve && !std::isnan(s.lat_feature) && std::fabs(s.lat_feature) >= c.lead_min_corr) {
        nc++; if ((s.lat_feature > 0) == (s.yaw_deg_s > 0)) agree++;
      }
    if (c.lead_sign != 0) {
      sign = c.lead_sign > 0 ? 1 : -1; r.lead_calibration = "OPCION";
      if (!r.forward_sign_known) r.warnings.push_back("mano con signo fijado pero sin confirmar el sentido de avance: puede estar invertida");
    } else if (nc >= c.lead_min_curve_strides) {
      double a = (double)agree / nc;
      r.lead_agreement = std::max(a, 1 - a);
      if (r.lead_agreement >= c.lead_min_agreement) { sign = a >= 0.5 ? 1 : -1; r.lead_calibration = "CURVAS"; }
      else { r.lead_calibration = "SIN_CALIBRAR"; r.warnings.push_back("mano sin calibrar: en las curvas no predomina una mano"); }
    } else {
      r.lead_calibration = "SIN_CALIBRAR";
      if (!r.strides.empty()) r.warnings.push_back("mano sin calibrar: pocas zancadas de galope en curva");
    }
    r.lead_sign_used = sign;
    if (sign != 0) {
      std::vector<int> raw(r.strides.size(), 0);
      for (size_t k = 0; k < r.strides.size(); k++) {
        double f = r.strides[k].lat_feature;
        if (!std::isnan(f) && std::fabs(f) >= c.lead_min_corr) raw[k] = (f * sign > 0) ? 1 : -1;
      }
      // majority over 5 strides of the same run (gap < 2 strides)
      for (size_t k = 0; k < r.strides.size(); k++) {
        int sum = 0;
        for (size_t q = (k >= 2 ? k - 2 : 0); q <= std::min(r.strides.size() - 1, k + 2); q++) {
          if (std::fabs(r.strides[q].t0 - r.strides[k].t0) > 3.0) continue;
          sum += raw[q];
        }
        r.strides[k].lead = sum > 0 ? 1 : sum < 0 ? -1 : 0;
      }
      // a lead must hold for at least 3 consecutive strides (no flicker at transitions)
      for (size_t k = 0; k < r.strides.size();) {
        size_t j = k + 1;
        while (j < r.strides.size() && r.strides[j].lead == r.strides[k].lead && r.strides[j].t0 - r.strides[j - 1].t1 < 1.0) j++;
        if (r.strides[k].lead != 0 && j - k < 3) for (size_t q = k; q < j; q++) r.strides[q].lead = 0;
        k = j;
      }
      int wrong = 0, curve_known = 0, last = 0;
      double last_t = -1e9;
      for (const auto& s : r.strides) {
        if (s.lead > 0) r.lead_left++; else if (s.lead < 0) r.lead_right++;
        if (s.in_curve && s.lead != 0) { curve_known++; if ((s.lead > 0) != (s.yaw_deg_s > 0)) wrong++; }
        if (s.lead != 0) {
          if (last != 0 && s.lead != last && s.t0 - last_t < 2.0) {
            r.lead_changes++;
            RacingEvent e; e.type = "CAMBIO_DE_MANO"; e.t = s.t0; e.value = s.lead;
            e.detail = s.lead > 0 ? "a mano izquierda" : "a mano derecha";
            r.events.push_back(e);
          }
          last = s.lead; last_t = s.t1;
        }
      }
      if (curve_known) r.wrong_lead_curve_pct = 100.0 * wrong / curve_known;
    }

    // ================================================================ E. girth events (experimental)
    {
      std::vector<double> peaks;
      for (const auto& s : r.strides) if (!std::isnan(s.vert_peak_g)) peaks.push_back(s.vert_peak_g);
      if (peaks.size() >= 20) {
        double med = dsp::median(peaks), mad = dsp::mad(peaks);
        double thr = std::max(c.event_min_g, med + c.event_k * 1.4826 * std::max(mad, 0.02));
        for (const auto& s : r.strides)
          if (s.vert_peak_g > thr) {
            RacingEvent e; e.type = "IMPACTO_ATIPICO"; e.t = s.t0; e.value = s.vert_peak_g;
            char b[120]; snprintf(b, sizeof(b), "pico vertical %.2f g (habitual %.2f g)", s.vert_peak_g, med); e.detail = b;
            r.events.push_back(e);
          }
      }
      // lateral jolts: 1 s windows while moving, lateral peak far above the session's usual and a sharp turn
      for (size_t k = 0; k < pieces.size(); k++) {
        const Piece& P = pieces[k];
        size_t w = (size_t)P.fs;
        std::vector<double> lp, wp, tt;
        for (size_t i = 0; i + w <= P.lat.size(); i += w) {
          double m = 0, ww = 0;
          for (size_t q = i; q < i + w; q++) { m = std::max(m, std::fabs(P.lat[q])); ww = std::max(ww, std::fabs(P.wv[q])); }
          lp.push_back(m); wp.push_back(ww); tt.push_back(P.tg[i + w / 2]);
        }
        if (lp.size() < 30) continue;
        double med = dsp::median(lp), mad = dsp::mad(lp);
        double thr = std::max(1.0, med + c.event_k * 1.4826 * std::max(mad, 0.02));
        double last = -1e9;
        for (size_t q = 0; q < lp.size(); q++)
          if (lp[q] > thr && wp[q] > 30 && !std::isnan(tt[q]) && tt[q] - last > 2) {
            RacingEvent e; e.type = "MOVIMIENTO_LATERAL_BRUSCO"; e.t = tt[q]; e.value = lp[q];
            char b[140]; snprintf(b, sizeof(b), "lateral %.2f g con giro de %.0f °/s (posible espantada o quiebro)", lp[q], wp[q]); e.detail = b;
            r.events.push_back(e); last = tt[q];
          }
      }
      // saturation episodes
      for (const auto& P : pieces) {
        double sat = r.scale == "BNO085" ? 0.98 * 8 * r.g_lsb : 32700, last = -1e9;
        for (size_t i = 0; i < P.amax_lsb.size(); i++)
          if (P.amax_lsb[i] >= sat && !std::isnan(P.tg[i]) && P.tg[i] - last > 0.5) {
            RacingEvent e; e.type = "SATURACION"; e.t = P.tg[i]; e.value = P.amax_lsb[i] / r.g_lsb; e.detail = "aceleración fuera de rango (±8 g)";
            r.events.push_back(e); last = P.tg[i];
          }
      }
    }
  }

  // ================================================================ D. efforts (GNSS)
  size_t n = g.t.size();
  if (n > 2) {
    for (size_t i = 1; i < n; i++) {
      double v0 = g.speed[i - 1], v1 = g.speed[i];
      if (std::isnan(v0) || std::isnan(v1) || std::isnan(g.dist[i]) || std::isnan(g.dist[i - 1])) continue;
      double dd = g.dist[i] - g.dist[i - 1], vm = 0.5 * (v0 + v1);
      if (vm >= c.breed.work_speed) r.dist_work_m += dd;
      if (vm >= c.breed.fast_speed) r.dist_fast_m += dd;
    }
    size_t i = c.manual_efforts_set ? n : 0;   // manual list: no automatic detection
    int id = 0;
    if (c.manual_efforts_set) {
      r.manual_corrections = true;
      for (const auto& sp : c.manual_efforts_itow) {
        double a = std::max(t_of_itow(sp.first), g.t.front()), b = std::min(t_of_itow(sp.second), g.t.back());
        if (std::isnan(a) || std::isnan(b) || b - a < 2.0) { r.warnings.push_back("trabajo manual fuera de la sesión o demasiado corto: no se usa"); continue; }
        Track T;
        if (!make_track(a, b, &T)) continue;
        Effort e; e.id = ++id; e.manual = true;
        fill_effort(&e, T, r, c);
        e.type = e.vmax >= c.breed.fast_speed ? "TRABAJO_RAPIDO" : "GALOPE_TRABAJO";
        if (std::isnan(r.vmax) || e.vmax > r.vmax) r.vmax = e.vmax;
        for (const auto& bs : e.best) if (bs.distance_m == 200 && !std::isnan(bs.time_s) && (std::isnan(r.best_200_s) || bs.time_s < r.best_200_s)) r.best_200_s = bs.time_s;
        r.efforts.push_back(e);
      }
      std::sort(r.efforts.begin(), r.efforts.end(), [](const Effort& x, const Effort& y) { return x.t0 < y.t0; });
      for (size_t k = 0; k < r.efforts.size(); k++) r.efforts[k].id = (int)k + 1;
    }
    while (i < n) {
      if (std::isnan(g.speed[i]) || g.speed[i] < c.breed.work_speed) { i++; continue; }
      size_t j = i, end = i;
      while (j < n) {
        if (!std::isnan(g.speed[j]) && g.speed[j] >= c.breed.work_speed) { end = j; j++; continue; }
        if (g.t[j] - g.t[end] > c.effort_gap_s) break;
        j++;
      }
      size_t i0 = i, i1 = end;
      i = end + 1;
      if (g.t[i1] - g.t[i0] < c.effort_min_s) continue;
      Track T;
      for (size_t k = i0; k <= i1; k++) { T.t.push_back(g.t[k]); T.d.push_back(g.dist[k]); T.v.push_back(g.speed[k]); T.a.push_back(g.accel[k]); }
      if (std::isnan(T.d.front()) || std::isnan(T.d.back())) continue;
      Effort e; e.id = ++id;
      fill_effort(&e, T, r, c);
      e.type = e.vmax >= c.breed.fast_speed ? "TRABAJO_RAPIDO" : "GALOPE_TRABAJO";
      if (std::isnan(r.vmax) || e.vmax > r.vmax) r.vmax = e.vmax;
      for (const auto& bs : e.best) if (bs.distance_m == 200 && !std::isnan(bs.time_s) && (std::isnan(r.best_200_s) || bs.time_s < r.best_200_s)) r.best_200_s = bs.time_s;
      r.efforts.push_back(e);
    }
  }
  // ================================================================ G. course: start / finish lines
  if (c.course.defined() && n > 2) {
    r.course_defined = true; r.course_name = c.course.name;
    const Gate* ref = c.course.start.enabled ? &c.course.start : &c.course.start_finish;
    const double lat0 = ref->a.lat, lon0 = ref->a.lon, M = 111320.0, kx = M * std::cos(lat0 * 0.017453292519943295);
    auto X = [&](double lon) { return (lon - lon0) * kx; };
    auto Y = [&](double lat) { return (lat - lat0) * M; };
    if (c.course.start.enabled && c.course.finish.enabled) {
      double sx = 0.5 * (X(c.course.start.a.lon) + X(c.course.start.b.lon)), sy = 0.5 * (Y(c.course.start.a.lat) + Y(c.course.start.b.lat));
      double fx = 0.5 * (X(c.course.finish.a.lon) + X(c.course.finish.b.lon)), fy = 0.5 * (Y(c.course.finish.a.lat) + Y(c.course.finish.b.lat));
      r.gate_distance_m = std::hypot(fx - sx, fy - sy);
    }
    // same geometry as the watch (avo_session.cpp crosses()) and AVO Windows (LineAnalysis.Crosses)
    auto detect = [&](const Gate& G, const char* role) {
      if (!G.enabled) return;
      double ax = X(G.a.lon), ay = Y(G.a.lat), bx = X(G.b.lon), by = Y(G.b.lat);
      size_t prev = SIZE_MAX;
      for (size_t k = 0; k < n; k++) {
        if (std::isnan(g.lat[k]) || std::isnan(g.lon[k])) continue;
        if (prev != SIZE_MAX && g.t[k] - g.t[prev] <= 2.0) {
          double px = X(g.lon[prev]), py = Y(g.lat[prev]), qx = X(g.lon[k]), qy = Y(g.lat[k]);
          double sp = (bx - ax) * (py - ay) - (by - ay) * (px - ax), sq = (bx - ax) * (qy - ay) - (by - ay) * (qx - ax);
          bool pp = sp >= 0, qp = sq >= 0;
          if (pp != qp) {
            double sa = (qx - px) * (ay - py) - (qy - py) * (ax - px), sb = (qx - px) * (by - py) - (qy - py) * (bx - px);
            if ((sa >= 0) != (sb >= 0) || sa == 0 || sb == 0) {
              double dx = qx - px, dy = qy - py, ex = bx - ax, ey = by - ay, den = dx * ey - dy * ex;
              double f = std::fabs(den) > 1e-12 ? std::max(0.0, std::min(1.0, ((ax - px) * ey - (ay - py) * ex) / den)) : 0.5;
              GateCrossing x; x.gate = role; x.t = g.t[prev] + f * (g.t[k] - g.t[prev]); x.left_to_right = pp && !qp;
              x.counts = G.direction == 0 || (G.direction > 0) == x.left_to_right;
              r.crossings.push_back(x);
            }
          }
        }
        prev = k;
      }
    };
    detect(c.course.start, "SALIDA"); detect(c.course.finish, "META"); detect(c.course.start_finish, "SALIDA_META");
    std::sort(r.crossings.begin(), r.crossings.end(), [](const GateCrossing& a, const GateCrossing& b) { return a.t < b.t; });
    // passes: last SALIDA crossing (in the right direction) before the next counting META, as AVO Windows, except
    // that a SALIDA crossing in the wrong direction cancels the pending start; laps between SALIDA_META crossings
    std::vector<std::pair<double, double>> spans;
    double start = kNaN, lap = kNaN;
    for (const auto& x : r.crossings) {
      // crossing the start line the wrong way cancels a pending start (warm-up passing the line backwards)
      if (x.gate == "SALIDA") { start = x.counts ? x.t : kNaN; continue; }
      if (!x.counts) continue;
      else if (x.gate == "META" && !std::isnan(start)) { spans.push_back({start, x.t}); start = kNaN; }
      else if (x.gate == "SALIDA_META") { if (!std::isnan(lap)) spans.push_back({lap, x.t}); lap = x.t; }
    }
    int id = 0;
    for (const auto& sp : spans) {
      if (sp.second - sp.first < 5.0) continue;
      Track T;
      if (!make_track(sp.first, sp.second, &T)) continue;
      Effort e; e.id = ++id;
      fill_effort(&e, T, r, c);
      e.type = "PASADA";
      if (!std::isnan(r.gate_distance_m) && e.distance_m < 0.5 * r.gate_distance_m) continue;   // not a real pass
      if (std::isnan(r.best_pass_s) || e.duration_s < r.best_pass_s) r.best_pass_s = e.duration_s;
      r.passes.push_back(e);
    }
    if (r.passes.empty()) r.warnings.push_back("recorrido definido pero sin pasadas completas de la salida a la meta (revisar el sentido de las líneas)");
    // recording geofence
    if (c.course.fence.size() >= 3) {
      size_t in = 0, tot = 0;
      for (size_t k = 0; k < n; k++) {
        if (std::isnan(g.lat[k])) continue;
        double px = X(g.lon[k]), py = Y(g.lat[k]);
        bool inside = false;
        for (size_t i = 0, j = c.course.fence.size() - 1; i < c.course.fence.size(); j = i++) {
          double xi = X(c.course.fence[i].lon), yi = Y(c.course.fence[i].lat), xj = X(c.course.fence[j].lon), yj = Y(c.course.fence[j].lat);
          if ((yi > py) != (yj > py) && px < (xj - xi) * (py - yi) / (yj - yi) + xi) inside = !inside;
        }
        tot++; if (inside) in++;
      }
      if (tot) r.fence_inside_pct = 100.0 * in / tot;
      if (tot && r.fence_inside_pct < 95) {
        char b[140]; snprintf(b, sizeof(b), "%.0f %% de la sesión fuera de la geocerca de grabación", 100 - r.fence_inside_pct);
        r.warnings.push_back(b);
      }
    }
  }

  // ================================================================ F. session structure
  if (n > 2) {
    double ts = kNaN, te = kNaN;
    for (size_t k = 0; k < n; k++) if (!std::isnan(g.speed[k])) { if (std::isnan(ts)) ts = g.t[k]; te = g.t[k]; }
    auto dist_at = [&](double t) { return interp(g.t, g.dist, t); };
    auto fill = [&](PhaseStats* P, double a, double b) {
      if (std::isnan(a) || std::isnan(b) || b <= a) return;
      P->present = true; P->t0 = a; P->t1 = b; P->duration_s = b - a;
      double d0 = dist_at(a), d1 = dist_at(b);
      P->distance_m = !std::isnan(d0) && !std::isnan(d1) ? d1 - d0 : 0;
      for (const auto& s : gait.segments) {
        double o = std::min(b, s.t1) - std::max(a, s.t0);
        if (o <= 0) continue;
        if (s.gait == Gait::WALK) P->walk_s += o; else if (s.gait == Gait::TROT) P->trot_s += o;
        else if (s.gait == Gait::CANTER_GALLOP) P->canter_s += o; else if (s.gait == Gait::STOPPED) P->stopped_s += o;
      }
    };
    double mw0 = t_of_itow(c.manual_work_start_itow), mw1 = t_of_itow(c.manual_work_end_itow);
    if ((!std::isnan(mw0) || !std::isnan(mw1)) && !std::isnan(ts)) {
      // work phase limits set by hand; a missing one comes from the passes / efforts (or the session end)
      double a = mw0, b = mw1;
      if (std::isnan(a)) a = !r.passes.empty() ? r.passes.front().t0 : !r.efforts.empty() ? r.efforts.front().t0 : ts;
      if (std::isnan(b)) b = !r.passes.empty() ? r.passes.back().t1 : !r.efforts.empty() ? r.efforts.back().t1 : te;
      a = std::max(ts, std::min(a, te)); b = std::max(a, std::min(b, te));
      r.phase_basis = "MANUAL"; r.manual_corrections = true;
      fill(&r.warmup, ts, a); fill(&r.work, a, b); fill(&r.cooldown, b, te);
    } else if (!r.passes.empty() && !std::isnan(ts)) {
      r.phase_basis = "LINEAS";
      fill(&r.warmup, ts, r.passes.front().t0);
      fill(&r.work, r.passes.front().t0, r.passes.back().t1);
      fill(&r.cooldown, r.passes.back().t1, te);
    } else if (!r.efforts.empty() && !std::isnan(ts)) {
      fill(&r.warmup, ts, r.efforts.front().t0);
      fill(&r.work, r.efforts.front().t0, r.efforts.back().t1);
      fill(&r.cooldown, r.efforts.back().t1, te);
    }
    // recovery to walk and pauses between repetitions (efforts and course passes)
    std::vector<double> rec;
    auto recovery = [&](std::vector<Effort>& list, bool collect) {
    for (size_t k = 0; k < list.size(); k++) {
      Effort& e = list[k];
      size_t q = std::lower_bound(g.t.begin(), g.t.end(), e.t1) - g.t.begin();
      for (; q < n; q++) {
        if (std::isnan(g.speed[q]) || g.speed[q] > c.walk_speed) continue;
        size_t m = q; bool held = true;
        while (m < n && g.t[m] - g.t[q] < c.recovery_hold_s) { if (!std::isnan(g.speed[m]) && g.speed[m] > 1.2 * c.walk_speed) { held = false; break; } m++; }
        if (held && m < n) { e.recovery_to_walk_s = g.t[q] - e.t1; break; }
        if (k + 1 < list.size() && g.t[q] >= list[k + 1].t0) break;
      }
      if (k + 1 < list.size()) {
        const Effort& nx = list[k + 1];
        e.pause_to_next_s = nx.t0 - e.t1;
        double d0 = dist_at(e.t1), d1 = dist_at(nx.t0);
        if (e.pause_to_next_s > 0 && !std::isnan(d0) && !std::isnan(d1)) e.pause_speed_mean = (d1 - d0) / e.pause_to_next_s;
      }
      if (collect && e.type == "TRABAJO_RAPIDO" && !std::isnan(e.recovery_to_walk_s)) rec.push_back(e.recovery_to_walk_s);
    }
    };
    recovery(r.efforts, true);
    recovery(r.passes, false);
    if (!rec.empty()) { double s = 0; for (double x : rec) s += x; r.recovery_mean_s = s / rec.size(); }
    r.reps = (int)r.efforts.size();
    const Effort* first = nullptr; const Effort* lastf = nullptr;
    for (const auto& e : r.efforts) if (e.type == "TRABAJO_RAPIDO") { r.fast_reps++; if (!first) first = &e; lastf = &e; }
    if (r.fast_reps >= 2 && first->vmax > 0) {
      r.vmax_drop_pct = 100.0 * (first->vmax - lastf->vmax) / first->vmax;
      if (first->sl_at_vmax > 0 && !std::isnan(lastf->sl_at_vmax)) r.stride_drop_pct = 100.0 * (first->sl_at_vmax - lastf->sl_at_vmax) / first->sl_at_vmax;
    }
    if (first && !std::isnan(ts) && first->t0 - ts < c.warmup_min_s) {
      r.warmup_short = true;
      char b[160]; snprintf(b, sizeof(b), "calentamiento de %.0f min antes del primer trabajo rápido (referencia %.0f min)", (first->t0 - ts) / 60, c.warmup_min_s / 60);
      r.warnings.push_back(b);
    }
  }
  std::sort(r.events.begin(), r.events.end(), [](const RacingEvent& a, const RacingEvent& b) { return a.t < b.t; });
  return r;
}

// ------------------------------------------------------------------ JSON
namespace {
std::string num(double v) { if (std::isnan(v) || std::isinf(v)) return "null"; char b[40]; snprintf(b, sizeof(b), "%.6g", v); return b; }
std::string q(const std::string& s) { return "\"" + json::escape(s) + "\""; }
void turns(std::ostringstream& o, const TurnStats& t) {
  double tot = t.left_s + t.right_s;
  o << "{\"izquierda_s\":" << num(t.left_s) << ",\"derecha_s\":" << num(t.right_s) << ",\"izquierda_grados\":" << num(t.left_deg)
    << ",\"derecha_grados\":" << num(t.right_deg) << ",\"equilibrio\":" << (tot > 0 ? num((t.left_s - t.right_s) / tot) : "null") << "}";
}
}  // namespace

std::string racing_json(const RacingResult& r, const RacingConfig& c) {
  std::ostringstream o;
  const BreedProfile& b = c.breed;
  o << "{\"modulo\":\"AVO_TRACK_WORK\",\"version\":\"" << RACING_VERSION << "\",\"perfil\":{\"raza\":" << q(b.name) << ",\"v_trabajo\":" << num(b.work_speed) << ",\"v_rapido\":" << num(b.fast_speed)
    << ",\"v_alta\":" << num(b.high_speed) << ",\"v_referencia\":[" << num(b.ref_speed[0]) << "," << num(b.ref_speed[1]) << "],\"frecuencia_zancada_hz\":["
    << num(b.sf_min) << "," << num(b.sf_max) << "],\"longitud_zancada_m\":[" << num(b.sl_min) << "," << num(b.sl_max) << "],\"parcial_m\":" << num(c.split_m) << "}";
  o << ",\"cincha\":{\"disponible\":" << (r.has_imu ? "true" : "false") << ",\"escala\":" << q(r.scale) << ",\"lsb_por_g\":" << num(r.g_lsb)
    << ",\"calidad_vertical\":" << num(r.frame_quality) << ",\"sentido_avance_confirmado\":" << (r.forward_sign_known ? "true" : "false")
    << ",\"segundos\":" << num(r.imu_seconds) << ",\"vedba_media_g\":" << num(r.vedba_mean_g) << ",\"carga_vedba_g_min\":" << num(r.vedba_load_gmin)
    << ",\"vedba_por_aire_g\":{\"PASO\":" << num(r.vedba_gait[0]) << ",\"TROTE\":" << num(r.vedba_gait[1]) << ",\"GALOPE\":" << num(r.vedba_gait[2]) << "}"
    << ",\"giros\":"; turns(o, r.turns_total);
  o << ",\"giros_por_aire\":{\"PASO\":"; turns(o, r.turns_gait[0]); o << ",\"TROTE\":"; turns(o, r.turns_gait[1]); o << ",\"GALOPE\":"; turns(o, r.turns_gait[2]);
  o << "},\"muestras_saturadas\":" << r.saturated_samples << ",\"fuente\":\"IMU_HORSE_FRAME_V1\"}";
  // strides summary + list
  std::vector<double> f, l, vd, vp;
  for (const auto& s : r.strides) { f.push_back(s.freq_hz); l.push_back(s.length_m); vd.push_back(s.vert_disp_m); vp.push_back(s.vert_peak_g); }
  o << ",\"zancadas\":{\"algoritmo\":\"STRIDE_V1\",\"n\":" << r.strides.size() << ",\"frecuencia_mediana_hz\":" << num(median_of(f))
    << ",\"longitud_mediana_m\":" << num(median_of(l)) << ",\"desplazamiento_vertical_mediano_m\":" << num(median_of(vd))
    << ",\"pico_vertical_mediano_g\":" << num(median_of(vp)) << ",\"lista\":[";
  for (size_t i = 0; i < r.strides.size(); i++) {
    const Stride& s = r.strides[i];
    o << (i ? "," : "") << "{\"t0\":" << num(s.t0) << ",\"t1\":" << num(s.t1) << ",\"f_hz\":" << num(s.freq_hz) << ",\"v\":" << num(s.speed) << ",\"l_m\":" << num(s.length_m)
      << ",\"pico_v_g\":" << num(s.vert_peak_g) << ",\"desp_v_m\":" << num(s.vert_disp_m) << ",\"vedba_g\":" << num(s.vedba_g) << ",\"rasgo_lateral\":" << num(s.lat_feature)
      << ",\"giro_deg_s\":" << num(s.yaw_deg_s) << ",\"mano\":\"" << (s.lead > 0 ? "IZQUIERDA" : s.lead < 0 ? "DERECHA" : "INDETERMINADA") << "\",\"curva\":" << (s.in_curve ? "true" : "false") << "}";
  }
  o << "]}";
  o << ",\"mano\":{\"algoritmo\":\"LEAD_V1\",\"experimental\":true,\"calibracion\":" << q(r.lead_calibration) << ",\"signo\":" << num(r.lead_sign_used) << ",\"acuerdo_curvas\":" << num(r.lead_agreement)
    << ",\"zancadas_izquierda\":" << r.lead_left << ",\"zancadas_derecha\":" << r.lead_right << ",\"cambios\":" << r.lead_changes
    << ",\"mano_de_fuera_en_curva_pct\":" << num(r.wrong_lead_curve_pct) << "}";
  auto effort_json = [&](const std::vector<Effort>& list) {
  for (size_t i = 0; i < list.size(); i++) {
    const Effort& e = list[i];
    o << (i ? "," : "") << "{\"id\":" << e.id << ",\"tipo\":" << q(e.type) << ",\"t0\":" << num(e.t0) << ",\"t1\":" << num(e.t1) << ",\"duracion_s\":" << num(e.duration_s)
      << ",\"distancia_m\":" << num(e.distance_m) << ",\"v_media\":" << num(e.speed_mean) << ",\"v_max\":" << num(e.vmax) << ",\"t_hasta_v_max_s\":" << num(e.t_to_vmax_s)
      << ",\"distancia_90_pct_m\":" << num(e.dist_above_90_m) << ",\"aceleracion_max\":" << num(e.accel_max) << ",\"ultimos_200m_s\":" << num(e.last_200_s)
      << ",\"ultimos_400m_s\":" << num(e.last_400_s) << ",\"v_ultimos_200m\":" << num(e.v_last_200) << ",\"v_ultimos_400m\":" << num(e.v_last_400)
      << ",\"indice_caida_pct\":" << num(e.fatigue_pct) << ",\"parciales\":[";
    for (size_t k = 0; k < e.sectionals.size(); k++)
      o << (k ? "," : "") << "{\"desde_m\":" << num(e.sectionals[k].from_m) << ",\"hasta_m\":" << num(e.sectionals[k].to_m) << ",\"tiempo_s\":" << num(e.sectionals[k].time_s) << ",\"v\":" << num(e.sectionals[k].speed) << "}";
    o << "],\"mejores\":[";
    for (size_t k = 0; k < e.best.size(); k++) o << (k ? "," : "") << "{\"distancia_m\":" << num(e.best[k].distance_m) << ",\"tiempo_s\":" << num(e.best[k].time_s) << ",\"t0\":" << num(e.best[k].t0) << "}";
    o << "],\"zancadas\":" << e.strides << ",\"f_en_v_max_hz\":" << num(e.sf_at_vmax) << ",\"l_en_v_max_m\":" << num(e.sl_at_vmax) << ",\"f_max_hz\":" << num(e.sf_max)
      << ",\"l_max_m\":" << num(e.sl_max) << ",\"ajuste_f\":{\"a\":" << num(e.sf_icpt) << ",\"b\":" << num(e.sf_slope) << ",\"r\":" << num(e.fit_r_sf) << "},\"ajuste_l\":{\"a\":"
      << num(e.sl_icpt) << ",\"b\":" << num(e.sl_slope) << "},\"referencia\":[";
    for (int k = 0; k < 2; k++) o << (k ? "," : "") << "{\"v\":" << num(c.breed.ref_speed[k]) << ",\"f_hz\":" << num(e.sf_ref[k]) << ",\"l_m\":" << num(e.sl_ref[k]) << "}";
    o << "],\"mano\":{\"izquierda\":" << e.lead_left << ",\"derecha\":" << e.lead_right << ",\"cambios\":" << e.lead_changes << "}"
      << ",\"recuperacion_hasta_paso_s\":" << num(e.recovery_to_walk_s) << ",\"pausa_hasta_siguiente_s\":" << num(e.pause_to_next_s)
      << ",\"v_media_pausa\":" << num(e.pause_speed_mean) << ",\"manual\":" << (e.manual ? "true" : "false") << "}";
  }
  };
  o << ",\"trabajos\":{\"algoritmo\":\"EFFORT_V1\",\"distancia_galope_trabajo_m\":" << num(r.dist_work_m) << ",\"distancia_rapida_m\":" << num(r.dist_fast_m)
    << ",\"v_max\":" << num(r.vmax) << ",\"mejor_200m_s\":" << num(r.best_200_s) << ",\"lista\":[";
  effort_json(r.efforts);
  o << "]},\"recorrido\":";
  if (!r.course_defined) o << "null";
  else {
    o << "{\"nombre\":" << q(r.course_name) << ",\"distancia_salida_meta_m\":" << num(r.gate_distance_m) << ",\"dentro_geocerca_pct\":" << num(r.fence_inside_pct)
      << ",\"mejor_pasada_s\":" << num(r.best_pass_s) << ",\"cruces\":[";
    for (size_t i = 0; i < r.crossings.size(); i++)
      o << (i ? "," : "") << "{\"linea\":" << q(r.crossings[i].gate) << ",\"t\":" << num(r.crossings[i].t) << ",\"sentido\":\""
        << (r.crossings[i].left_to_right ? "IZQ_A_DCHA" : "DCHA_A_IZQ") << "\",\"cuenta\":" << (r.crossings[i].counts ? "true" : "false") << "}";
    o << "],\"pasadas\":[";
    effort_json(r.passes);
    o << "]}";
  }
  o << ",\"correcciones_manuales\":" << (r.manual_corrections ? "true" : "false");
  o << ",\"fases\":{\"base\":" << q(r.phase_basis) << ",";
  auto ph = [&](const char* name, const PhaseStats& P, bool comma) {
    o << (comma ? "," : "") << "\"" << name << "\":";
    if (!P.present) { o << "null"; return; }
    o << "{\"t0\":" << num(P.t0) << ",\"t1\":" << num(P.t1) << ",\"duracion_s\":" << num(P.duration_s) << ",\"distancia_m\":" << num(P.distance_m)
      << ",\"parado_s\":" << num(P.stopped_s) << ",\"paso_s\":" << num(P.walk_s) << ",\"trote_s\":" << num(P.trot_s) << ",\"galope_s\":" << num(P.canter_s) << "}";
  };
  ph("calentamiento", r.warmup, false); ph("trabajo", r.work, true); ph("vuelta_a_la_calma", r.cooldown, true);
  o << ",\"algoritmo\":\"SESSION_PHASES_V1\"},\"series\":{\"repeticiones\":" << r.reps << ",\"rapidas\":" << r.fast_reps
    << ",\"caida_v_max_pct\":" << num(r.vmax_drop_pct) << ",\"caida_zancada_pct\":" << num(r.stride_drop_pct)
    << ",\"recuperacion_media_s\":" << num(r.recovery_mean_s) << ",\"calentamiento_corto\":" << (r.warmup_short ? "true" : "false") << "}";
  o << ",\"eventos\":[";
  for (size_t i = 0; i < r.events.size(); i++)
    o << (i ? "," : "") << "{\"tipo\":" << q(r.events[i].type) << ",\"t\":" << num(r.events[i].t) << ",\"valor\":" << num(r.events[i].value) << ",\"detalle\":" << q(r.events[i].detail) << "}";
  o << "],\"avisos\":[";
  for (size_t i = 0; i < r.warnings.size(); i++) o << (i ? "," : "") << q(r.warnings[i]);
  o << "],\"nota\":\"entrenamiento de caballos de carreras; exploratorio, sin validar con caballos reales; perfiles de raza = valores de partida\"}";
  return o.str();
}

}  // namespace avoeq
