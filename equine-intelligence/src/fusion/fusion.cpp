#include "avo_eq/fusion.h"
#include "avo_eq/dsp.h"
#include "avo_eq/session_sync.h"
#include <algorithm>
#include <cmath>
#include <map>

namespace avoeq {

const char* mode_name(AnalysisMode m) { return m == AnalysisMode::REALTIME_ANALYSIS ? "REALTIME_ANALYSIS" : "OFFLINE_ANALYSIS"; }

static Gait gait_at(const GaitResult* g, double t) {
  if (!g || std::isnan(t)) return Gait::UNKNOWN;
  for (auto& s : g->segments) if (t >= s.t0 && t < s.t1) return s.gait;
  return Gait::UNKNOWN;
}

static void fill_girth(const CadenceWindow& w, FusedWindow* f) {
  if (w.status == CadenceStatus::VALID) { f->cadence_hz = w.freq_hz; f->cadence_sigma = w.uncertainty_hz; }
  if (w.interval_cv >= 0) f->interval_cv = w.interval_cv;
  if (w.amplitude_cv >= 0) f->amplitude_cv = w.amplitude_cv;
  if (w.cycle_corr >= 0) f->cycle_corr = w.cycle_corr;
  if (w.spectral_stability >= 0) f->spectral_stability = w.spectral_stability;
}

static void stride(FusedWindow* f) {
  if (std::isnan(f->cadence_hz) || std::isnan(f->speed) || f->speed < 0.5) return;
  f->stride_length_m = f->speed / f->cadence_hz;
  double rv = f->speed_sigma / f->speed, rf = f->cadence_sigma / f->cadence_hz;
  f->stride_length_sigma = f->stride_length_m * std::sqrt(rv * rv + rf * rf);
}

static void set_status(FusedWindow* f, double max_sigma, double min_frac) {
  if (std::isnan(f->t_gnss)) f->status = "SIN_SINCRONIA";
  else if (!std::isnan(f->sigma_t) && f->sigma_t > max_sigma) f->status = "SIN_SINCRONIA";
  else if (f->gnss_fraction < min_frac) f->status = "HUECO_GNSS";
  else if (std::isnan(f->cadence_hz)) f->status = "SIN_CADENCIA";
  else f->status = "OK";
}

// ------------------------------------------------------------------ relations
static double spearman(const std::vector<double>& x, const std::vector<double>& y) {
  size_t n = x.size();
  if (n < 3) return NAN;
  auto rank = [&](const std::vector<double>& v) {
    std::vector<size_t> idx(n); for (size_t i = 0; i < n; i++) idx[i] = i;
    std::sort(idx.begin(), idx.end(), [&](size_t a, size_t b) { return v[a] < v[b]; });
    std::vector<double> r(n);
    for (size_t i = 0; i < n;) { size_t j = i; while (j + 1 < n && v[idx[j + 1]] == v[idx[i]]) j++; for (size_t k = i; k <= j; k++) r[idx[k]] = 0.5 * (i + j); i = j + 1; }
    return r;
  };
  std::vector<double> rx = rank(x), ry = rank(y);
  double mx = dsp::mean(rx), my = dsp::mean(ry), a = 0, b = 0, c = 0;
  for (size_t i = 0; i < n; i++) { a += (rx[i] - mx) * (ry[i] - my); b += (rx[i] - mx) * (rx[i] - mx); c += (ry[i] - my) * (ry[i] - my); }
  return (b > 0 && c > 0) ? a / std::sqrt(b * c) : NAN;
}

static Relation wls(const std::string& xn, const std::string& yn, const std::string& gait,
                    const std::vector<double>& x, const std::vector<double>& y, const std::vector<double>& sy) {
  Relation r; r.x = xn; r.y = yn; r.gait = gait; r.n = (uint32_t)x.size();
  if (x.size() < 3) return r;
  double sw = 0, sx = 0, syy = 0, sxx = 0, sxy = 0;
  for (size_t i = 0; i < x.size(); i++) {
    double s = (i < sy.size() && sy[i] > 0) ? sy[i] : 1, w = 1 / (s * s);
    sw += w; sx += w * x[i]; syy += w * y[i]; sxx += w * x[i] * x[i]; sxy += w * x[i] * y[i];
  }
  double den = sw * sxx - sx * sx;
  if (den > 0) {
    r.slope = (sw * sxy - sx * syy) / den; r.intercept = (syy - r.slope * sx) / sw; r.slope_sigma = std::sqrt(sw / den);
    // scale the formal error by the reduced chi-square when the scatter exceeds the stated uncertainties
    double chi = 0; for (size_t i = 0; i < x.size(); i++) { double s = (i < sy.size() && sy[i] > 0) ? sy[i] : 1, e = (y[i] - r.intercept - r.slope * x[i]) / s; chi += e * e; }
    if (x.size() > 2) r.slope_sigma *= std::sqrt(std::max(1.0, chi / (double)(x.size() - 2)));
  }
  double mx = dsp::mean(x), my = dsp::mean(y), a = 0, b = 0, c = 0;
  for (size_t i = 0; i < x.size(); i++) { a += (x[i] - mx) * (y[i] - my); b += (x[i] - mx) * (x[i] - mx); c += (y[i] - my) * (y[i] - my); }
  r.r = (b > 0 && c > 0) ? a / std::sqrt(b * c) : NAN;
  r.spearman = spearman(x, y);
  return r;
}

static void relations(FusionResult* out, double min_n) {
  std::map<std::string, std::vector<const FusedWindow*>> by;
  for (auto& w : out->windows) if (w.status == "OK") { by["TODOS"].push_back(&w); by[gait_name(w.gait)].push_back(&w); }
  for (auto& kv : by) {
    if (kv.second.size() < min_n) continue;
    std::vector<double> v, f, sf, L, sL, cc, cv, ss, vcc, vcv, vss;
    for (auto* w : kv.second) {
      v.push_back(w->speed); f.push_back(w->cadence_hz); sf.push_back(w->cadence_sigma);
      if (!std::isnan(w->stride_length_m)) { L.push_back(w->stride_length_m); sL.push_back(w->stride_length_sigma); }
      if (!std::isnan(w->cycle_corr)) { cc.push_back(w->cycle_corr); vcc.push_back(w->speed); }
      if (!std::isnan(w->interval_cv)) { cv.push_back(w->interval_cv); vcv.push_back(w->speed); }
      if (!std::isnan(w->spectral_stability)) { ss.push_back(w->spectral_stability); vss.push_back(w->speed); }
    }
    Relation a = wls("velocidad_m_s", "cadencia_hz", kv.first, v, f, sf);
    a.note = "mínimos cuadrados ponderados por la incertidumbre de la cadencia";
    out->relations.push_back(a);
    if (L.size() == v.size()) { Relation b = wls("velocidad_m_s", "longitud_tranco_m", kv.first, v, L, sL); b.note = "longitud = velocidad / cadencia (antena del jinete, cincha del caballo)"; out->relations.push_back(b); }
    auto rank_only = [&](const char* yn, const std::vector<double>& x, const std::vector<double>& y) {
      if (x.size() < min_n) return;
      Relation r; r.x = "velocidad_m_s"; r.y = yn; r.gait = kv.first; r.n = (uint32_t)x.size(); r.spearman = spearman(x, y);
      r.note = "correlación de rangos (relación monótona, sin modelo)";
      out->relations.push_back(r);
    };
    rank_only("correlacion_ciclos", vcc, cc);
    rank_only("cv_intervalos", vcv, cv);
    rank_only("estabilidad_espectral", vss, ss);
  }
}

static void summarise(FusionResult* out) {
  std::vector<double> st;
  for (auto& w : out->windows) {
    out->windows_total++;
    if (w.status == "OK") out->windows_ok++;
    else if (w.status == "SIN_SINCRONIA") out->no_sync++;
    else if (w.status == "HUECO_GNSS") out->gnss_gap++;
    else if (w.status == "SIN_CADENCIA") out->no_cadence++;
    if (!std::isnan(w.sigma_t)) st.push_back(w.sigma_t);
  }
  if (!st.empty()) out->median_sigma_t_ms = dsp::median(st) * 1e3;
  Metric m; m.name = "ventanas_fusionadas"; m.unit = "n"; m.value = out->windows_ok; m.algorithm = std::string("fusión temporal ") + mode_name(out->mode); m.version = FUSION_VERSION;
  m.samples_used = out->windows_ok; m.samples_excluded = out->windows_total - out->windows_ok;
  m.quality = out->windows_total == 0 ? Quality::UNKNOWN : (out->windows_ok * 2 >= out->windows_total ? Quality::USABLE : Quality::POOR);
  m.warnings.push_back("sin PPS: incertidumbre temporal de la envolvente; sesgo sistemático ≈ latencia mínima del enlace no incluido");
  out->metrics.push_back(m);
  if (!std::isnan(out->median_sigma_t_ms)) { Metric s = m; s.name = "incertidumbre_temporal_mediana"; s.unit = "ms"; s.value = out->median_sigma_t_ms; out->metrics.push_back(s); }
}

// ------------------------------------------------------------------ offline
FusionResult fuse_offline(const GnssResult& g, const std::vector<CadenceResult>& cad, const ClockMap girth_to_gnss[3],
                          const GaitResult* gait, const FusionConfig& c) {
  FusionResult out; out.mode = AnalysisMode::OFFLINE_ANALYSIS;
  if (g.t.empty()) out.warnings.push_back("sesión sin GNSS: no hay velocidad que asociar");
  if (cad.empty()) out.warnings.push_back("SIN DATOS DE CINCHA: no hay ventanas IMU que fusionar");
  std::vector<double> dts; for (size_t i = 1; i < g.t.size(); i++) if (g.t[i] > g.t[i - 1]) dts.push_back(g.t[i] - g.t[i - 1]);
  double dt_nom = dts.empty() ? 0.125 : dsp::median(dts);
  bool sorted = std::is_sorted(g.t.begin(), g.t.end());
  for (const auto& cr : cad) {
    double W = 6.0;
    if (cr.windows.size() >= 2) W = 3 * (cr.windows[1].t_mid - cr.windows[0].t_mid);   // window = 3 hops (6 s / 2 s)
    for (uint32_t k = 0; k < cr.windows.size(); k++) {
      const CadenceWindow& w = cr.windows[k];
      FusedWindow f; f.imu_id = cr.imu_id; f.window_index = k; f.t_imu = w.t_mid;
      double tg, sg = 0;
      if (girth_to_gnss[std::min<uint8_t>(cr.imu_id, 2)].map(w.t_mid, &tg, &sg)) { f.t_gnss = tg; f.sigma_t = sg; }
      fill_girth(w, &f);
      if (!std::isnan(f.t_gnss) && sorted && !g.t.empty()) {
        double a = f.t_gnss - W / 2, b = f.t_gnss + W / 2;
        size_t i = (size_t)(std::lower_bound(g.t.begin(), g.t.end(), a) - g.t.begin());
        std::vector<double> v, sv, ac, sa, la;
        size_t i0 = i, i1 = i;
        for (; i < g.t.size() && g.t[i] <= b; i++) {
          if (!g.usable[i] || g.quality[i] > (uint8_t)Quality::USABLE || std::isnan(g.speed[i])) continue;
          if (v.empty()) i0 = i;
          i1 = i;
          v.push_back(g.speed[i]); sv.push_back(g.speed_sigma[i]);
          if (!std::isnan(g.accel[i])) { ac.push_back(g.accel[i]); sa.push_back(g.accel_sigma[i]); }
          if (!std::isnan(g.lat_accel[i])) la.push_back(g.lat_accel[i]);
        }
        f.gnss_fraction = std::min(1.0, v.size() * dt_nom / W);
        f.gnss_i0 = (uint32_t)i0; f.gnss_i1 = (uint32_t)i1;
        if (!v.empty()) {
          f.speed = dsp::mean(v);
          double s_meas = dsp::mean(sv) / std::sqrt((double)v.size());
          double a_abs = ac.empty() ? 0 : std::fabs(dsp::mean(ac));
          double s_time = a_abs * (std::isnan(f.sigma_t) ? 0 : f.sigma_t);
          f.speed_sigma = std::sqrt(s_meas * s_meas + s_time * s_time);
        }
        if (!ac.empty()) { f.accel = dsp::mean(ac); f.accel_sigma = dsp::mean(sa) / std::sqrt((double)ac.size()); }
        if (!la.empty()) f.lat_accel = dsp::mean(la);
        // centre epoch missing but bracketed by close epochs: interpolated reference (flag only)
        size_t j = (size_t)(std::lower_bound(g.t.begin(), g.t.end(), f.t_gnss) - g.t.begin());
        if (j > 0 && j < g.t.size() && std::min(g.t[j] - f.t_gnss, f.t_gnss - g.t[j - 1]) > 0.5 * dt_nom && g.t[j] - g.t[j - 1] <= c.max_interp_gap_s)
          f.gnss_interpolated = true;
      }
      f.gait = gait_at(gait, f.t_gnss);
      stride(&f);
      set_status(&f, c.max_sync_sigma_s, c.min_gnss_fraction);
      out.windows.push_back(f);
    }
  }
  relations(&out, c.min_relation_points);
  summarise(&out);
  return out;
}

// ------------------------------------------------------------------ real time (causal)
FusionResult fuse_realtime(const Session& s, const ValidationReport& v, const std::vector<ImuSeries>& imu,
                           const CadenceConfig& cc, const SyncConfig& sc, const FusionConfig& c) {
  FusionResult out; out.mode = AnalysisMode::REALTIME_ANALYSIS;
  out.warnings.push_back("modo tiempo real: cada resultado usa solo datos recibidos hasta su instante de disponibilidad");
  std::vector<double> tg = gnss_time_s(s.gnss);
  bool tg_sorted = std::is_sorted(tg.begin(), tg.end());
  // reception lookup per IMU: girth time -> chest reception time
  std::map<uint8_t, std::vector<std::pair<int64_t, uint64_t>>> rx;
  for (auto& m : s.imu) rx[m.imu_id].push_back({m.girth_us, m.chest_us});
  for (auto& kv : rx) std::sort(kv.second.begin(), kv.second.end());
  ClockMap c2g, g2g[3];
  double last_fit = -1e18;
  for (const auto& ser : imu) {
    if (ser.fs <= 0) continue;
    size_t W = (size_t)std::lround(cc.window_s * ser.fs), H = (size_t)std::max<long>(1, std::lround(cc.hop_s * ser.fs));
    double hi = std::min(cc.band_hi, ser.fs * 0.45);
    auto& lut = rx[ser.imu_id];
    for (const auto& p : ser.pieces) {
      for (size_t st = 0; st + W <= p.amag.size(); st += H) {
        double t_end_g = p.t0 + (double)(st + W - 1) / ser.fs;
        // instant at which the newest sample of the window had reached the chest
        int64_t key = (int64_t)std::llround(t_end_g * 1e6);
        auto it = std::lower_bound(lut.begin(), lut.end(), std::make_pair(key - 2, (uint64_t)0));
        if (it == lut.end()) continue;
        double now = it->second * 1e-6;
        // causal clock maps: refitted with pairs received before "now" (at most every 1.5 s of chest time)
        if (now - last_fit >= 1.5 || now < last_fit) { build_session_maps(s, v, sc, now, &c2g, g2g); last_fit = now; }
        FusedWindow f; f.imu_id = ser.imu_id; f.window_index = (uint32_t)out.windows.size(); f.t_available = now;
        f.t_imu = p.t0 + (st + W / 2.0) / ser.fs;
        double t, sg = 0;
        if (g2g[std::min<uint8_t>(ser.imu_id, 2)].map(f.t_imu, &t, &sg)) { f.t_gnss = t; f.sigma_t = sg; }
        // per-window filtering only (no samples after the window end)
        std::vector<double> mag(p.amag.begin() + st, p.amag.begin() + st + W);
        std::vector<double> bp = dsp::bandpass_zero_phase(mag, cc.band_lo, hi, ser.fs);
        const std::vector<float>* src[3] = {&p.ax, &p.ay, &p.az};
        std::vector<double> ab[3];
        for (int i = 0; i < 3; i++) { std::vector<double> x(src[i]->begin() + st, src[i]->begin() + st + W); ab[i] = dsp::bandpass_zero_phase(x, cc.band_lo, hi, ser.fs); }
        const std::vector<double>* axes[3] = {&ab[0], &ab[1], &ab[2]};
        CadenceWindow cw; cw.t_mid = f.t_imu;
        analyse_cadence_window(bp, axes, ser.fs, cc, &cw);
        fill_girth(cw, &f);
        // GNSS received by "now", inside the window
        if (!std::isnan(f.t_gnss)) {
          double a = f.t_gnss - cc.window_s / 2, b = f.t_gnss + cc.window_s / 2;
          std::vector<double> vt, vv, vs;
          bool first = true;
          size_t i_start = tg_sorted ? (size_t)(std::lower_bound(tg.begin(), tg.end(), a - c.realtime_slope_s) - tg.begin()) : 0;
          for (size_t i = i_start; i < s.gnss.size(); i++) {
            if (tg_sorted && tg[i] > b) break;
            const GnssEpoch& e = s.gnss[i];
            if (e.chest_us * 1e-6 > now || tg[i] < a - c.realtime_slope_s || tg[i] > b) continue;
            if (!e.fix_ok() || e.fix_type < 3 || (v.gnss_flags[i] & (GF_DUPLICATE | GF_TIME_BACKWARDS))) continue;
            vt.push_back(tg[i]); vv.push_back(e.gspeed_ms); vs.push_back(e.sacc_ms);
            if (tg[i] >= a) { if (first) { f.gnss_i0 = (uint32_t)i; first = false; } f.gnss_i1 = (uint32_t)i; }
          }
          std::vector<double> win, ws;
          for (size_t i = 0; i < vt.size(); i++) if (vt[i] >= a) { win.push_back(vv[i]); ws.push_back(vs[i]); }
          double dt_nom = v.gnss_nominal_hz > 0 ? 1.0 / v.gnss_nominal_hz : 0.125;
          f.gnss_fraction = std::min(1.0, win.size() * dt_nom / cc.window_s);
          if (!win.empty()) { f.speed = dsp::mean(win); f.speed_sigma = dsp::mean(ws) / std::sqrt((double)win.size()); }
          // one-sided slope over the last realtime_slope_s seconds received
          if (vt.size() >= 3) {
            double tl = vt.back(), sw = 0, st_ = 0, sy = 0, stt = 0, sty = 0; int n = 0;
            for (size_t i = 0; i < vt.size(); i++) if (vt[i] >= tl - c.realtime_slope_s) {
              double d = vt[i] - tl, w = 1 / std::max(0.02, vs[i]) / std::max(0.02, vs[i]);
              sw += w; st_ += w * d; sy += w * vv[i]; stt += w * d * d; sty += w * d * vv[i]; n++;
            }
            double den = sw * stt - st_ * st_;
            if (n >= 3 && den > 0) { f.accel = (sw * sty - st_ * sy) / den; f.accel_sigma = std::sqrt(sw / den); }
          }
        }
        stride(&f);
        set_status(&f, c.max_sync_sigma_s, c.min_gnss_fraction);
        out.windows.push_back(f);
      }
    }
  }
  std::sort(out.windows.begin(), out.windows.end(), [](const FusedWindow& a, const FusedWindow& b) { return a.t_available < b.t_available; });
  relations(&out, c.min_relation_points);
  summarise(&out);
  return out;
}

}  // namespace avoeq
