// AVO Racing 1.0.0. Ver include/avo_eq/racing.h y docs/algoritmos/13_CARRERAS.md.
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

}  // namespace

RacingResult analyse_racing(const GnssResult& g, const std::vector<ImuSeries>& imu, const ClockMap girth_to_gnss[3],
                            const GaitResult& gait, uint8_t imu_units, const RacingConfig& c) {
  RacingResult r;
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
    size_t i = 0;
    int id = 0;
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
      Effort e; e.id = ++id;
      e.t0 = g.t[i0]; e.t1 = g.t[i1]; e.duration_s = e.t1 - e.t0;
      double d0 = g.dist[i0], d1 = g.dist[i1];
      if (std::isnan(d0) || std::isnan(d1)) continue;
      e.distance_m = d1 - d0; e.speed_mean = e.duration_s > 0 ? e.distance_m / e.duration_s : kNaN;
      // vmax over a 1 s moving mean (no single-epoch spikes)
      double best = -1, tbest = e.t0;
      for (size_t k = i0; k <= i1; k++) {
        double s = 0; int m = 0;
        for (size_t q = k; q <= i1 && g.t[q] - g.t[k] < 1.0 + 1e-9; q++) if (!std::isnan(g.speed[q])) { s += g.speed[q]; m++; }
        if (m && s / m > best) { best = s / m; tbest = g.t[k]; }
      }
      e.vmax = best > 0 ? best : kNaN; e.t_to_vmax_s = tbest - e.t0;
      e.dist_above_90_m = 0;
      for (size_t k = i0 + 1; k <= i1; k++)
        if (!std::isnan(g.speed[k]) && !std::isnan(g.speed[k - 1]) && 0.5 * (g.speed[k] + g.speed[k - 1]) >= 0.9 * e.vmax) e.dist_above_90_m += g.dist[k] - g.dist[k - 1];
      for (size_t k = i0; k <= i1; k++) if (!std::isnan(g.accel[k]) && (std::isnan(e.accel_max) || g.accel[k] > e.accel_max)) e.accel_max = g.accel[k];
      for (double d = d0 + c.split_m; d <= d1 + 1e-6; d += c.split_m) {
        Sectional s; s.from_m = d - c.split_m - d0; s.to_m = d - d0;
        double ta = time_at_dist(g.t, g.dist, i0, i1, d - c.split_m), tb = time_at_dist(g.t, g.dist, i0, i1, d);
        if (s.from_m == 0) ta = e.t0;
        if (!std::isnan(ta) && !std::isnan(tb) && tb > ta) { s.time_s = tb - ta; s.speed = c.split_m / s.time_s; }
        e.sectionals.push_back(s);
      }
      auto tail = [&](double D, double* tt, double* vv) {
        if (e.distance_m < D) return;
        double ta = time_at_dist(g.t, g.dist, i0, i1, d1 - D);
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
          if (std::isnan(g.dist[k]) || g.dist[k] + D > d1 + 1e-6) continue;
          double tb = time_at_dist(g.t, g.dist, k, i1, g.dist[k] + D);
          if (!std::isnan(tb) && (std::isnan(b.time_s) || tb - g.t[k] < b.time_s)) { b.time_s = tb - g.t[k]; b.t0 = g.t[k]; }
        }
        e.best.push_back(b);
        if (D == 200 && !std::isnan(b.time_s) && (std::isnan(r.best_200_s) || b.time_s < r.best_200_s)) r.best_200_s = b.time_s;
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
      e.type = e.vmax >= c.breed.fast_speed ? "TRABAJO_RAPIDO" : "GALOPE_TRABAJO";
      if (std::isnan(r.vmax) || e.vmax > r.vmax) r.vmax = e.vmax;
      r.efforts.push_back(e);
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
  o << "{\"version\":\"" << RACING_VERSION << "\",\"perfil\":{\"raza\":" << q(b.name) << ",\"v_trabajo\":" << num(b.work_speed) << ",\"v_rapido\":" << num(b.fast_speed)
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
  o << ",\"trabajos\":{\"algoritmo\":\"EFFORT_V1\",\"distancia_galope_trabajo_m\":" << num(r.dist_work_m) << ",\"distancia_rapida_m\":" << num(r.dist_fast_m)
    << ",\"v_max\":" << num(r.vmax) << ",\"mejor_200m_s\":" << num(r.best_200_s) << ",\"lista\":[";
  for (size_t i = 0; i < r.efforts.size(); i++) {
    const Effort& e = r.efforts[i];
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
    o << "],\"mano\":{\"izquierda\":" << e.lead_left << ",\"derecha\":" << e.lead_right << ",\"cambios\":" << e.lead_changes << "}}";
  }
  o << "]},\"eventos\":[";
  for (size_t i = 0; i < r.events.size(); i++)
    o << (i ? "," : "") << "{\"tipo\":" << q(r.events[i].type) << ",\"t\":" << num(r.events[i].t) << ",\"valor\":" << num(r.events[i].value) << ",\"detalle\":" << q(r.events[i].detail) << "}";
  o << "],\"avisos\":[";
  for (size_t i = 0; i < r.warnings.size(); i++) o << (i ? "," : "") << q(r.warnings[i]);
  o << "],\"nota\":\"exploratorio, sin validar con caballos reales; perfiles de raza = valores de partida\"}";
  return o.str();
}

}  // namespace avoeq
