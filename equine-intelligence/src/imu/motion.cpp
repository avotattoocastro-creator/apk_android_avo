#include "avo_eq/motion.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>
#include <map>

namespace avoeq {

static const char* VER = "1.0.0";

const char* gait_name(Gait g) {
  switch (g) { case Gait::STOPPED: return "PARADO"; case Gait::WALK: return "PASO"; case Gait::TROT: return "TROTE";
    case Gait::CANTER_GALLOP: return "GALOPE"; case Gait::TRANSITION: return "TRANSICION"; case Gait::UNKNOWN: return "DESCONOCIDO"; }
  return "?";
}

std::vector<ImuSeries> build_imu_series(const Session& s, const ValidationReport& v) {
  std::map<uint8_t, std::vector<size_t>> by;
  for (size_t i = 0; i < s.imu.size(); i++) {
    uint32_t f = i < v.imu_flags.size() ? v.imu_flags[i] : 0;
    if (f & (IF_DUPLICATE | IF_TIME_BACKWARDS)) continue;     // never used, still kept in the session
    by[s.imu[i].imu_id].push_back(i);
  }
  std::vector<ImuSeries> out;
  for (auto& kv : by) {
    ImuSeries ser; ser.imu_id = kv.first;
    auto& idx = kv.second;
    std::stable_sort(idx.begin(), idx.end(), [&](size_t a, size_t b) { return s.imu[a].girth_us < s.imu[b].girth_us; });
    double hz = v.imu_nominal_hz[std::min<uint8_t>(kv.first, 2)];
    if (hz <= 0) continue;
    ser.fs = hz;
    double per_us = 1e6 / hz;
    ImuSeries::Piece cur;
    int64_t last = 0;
    for (size_t k = 0; k < idx.size(); k++) {
      const ImuSample& x = s.imu[idx[k]];
      uint32_t f = v.imu_flags[idx[k]];
      if (f & IF_SATURATED) ser.saturated++;
      bool gap = k && (double)(x.girth_us - last) > 1.5 * per_us;
      if (gap) {
        ser.missing += (uint32_t)std::lround((double)(x.girth_us - last) / per_us) - 1;
        if (cur.amag.size() > 1) ser.pieces.push_back(cur);
        cur = ImuSeries::Piece();
      }
      if (cur.amag.empty()) cur.t0 = (double)x.girth_us * 1e-6;
      cur.ax.push_back(x.ax); cur.ay.push_back(x.ay); cur.az.push_back(x.az);
      cur.gx.push_back(x.gx); cur.gy.push_back(x.gy); cur.gz.push_back(x.gz);
      cur.amag.push_back(std::sqrt((double)x.ax * x.ax + (double)x.ay * x.ay + (double)x.az * x.az));
      last = x.girth_us;
    }
    if (cur.amag.size() > 1) ser.pieces.push_back(cur);
    out.push_back(ser);
  }
  return out;
}

// cycles of a band-passed window, delimited by peaks spaced about one period
static void window_regularity(const std::vector<double>& y, double fs, double period_s, CadenceWindow* w) {
  size_t per = (size_t)std::lround(period_s * fs);
  if (per < 4 || y.size() < 3 * per) return;
  double sd = dsp::stddev(y);
  std::vector<size_t> pk = dsp::find_peaks(y, 0.0 * sd, (size_t)(0.7 * per));
  // keep one peak per cycle: the highest inside each period-long stretch was already enforced by min_dist
  if (pk.size() < 3) return;
  std::vector<double> iv, amp;
  for (size_t i = 1; i < pk.size(); i++) iv.push_back((double)(pk[i] - pk[i - 1]) / fs);
  for (size_t p : pk) amp.push_back(y[p]);
  double mi = dsp::mean(iv), ma = dsp::mean(amp);
  w->interval_cv = mi > 0 ? dsp::stddev(iv) / mi : -1;
  w->amplitude_cv = ma != 0 ? std::fabs(dsp::stddev(amp) / ma) : -1;
  // template of one cycle (resampled to 64 points) and correlation of each cycle with it
  const size_t L = 64;
  std::vector<std::vector<double>> cyc;
  for (size_t i = 1; i < pk.size(); i++) {
    std::vector<double> c(L);
    size_t a = pk[i - 1], b = pk[i];
    for (size_t k = 0; k < L; k++) {
      double pos = a + (double)(b - a) * k / (L - 1);
      size_t i0 = (size_t)pos; double fr = pos - i0;
      c[k] = (i0 + 1 < y.size()) ? y[i0] * (1 - fr) + y[i0 + 1] * fr : y[i0];
    }
    cyc.push_back(c);
  }
  std::vector<double> tmpl(L, 0);
  for (auto& c : cyc) for (size_t k = 0; k < L; k++) tmpl[k] += c[k] / cyc.size();
  double cs = 0;
  for (auto& c : cyc) {
    double mc = dsp::mean(c), mt = dsp::mean(tmpl), num = 0, d1 = 0, d2 = 0;
    for (size_t k = 0; k < L; k++) { num += (c[k] - mc) * (tmpl[k] - mt); d1 += (c[k] - mc) * (c[k] - mc); d2 += (tmpl[k] - mt) * (tmpl[k] - mt); }
    cs += (d1 > 0 && d2 > 0) ? num / std::sqrt(d1 * d2) : 0;
  }
  w->cycle_corr = cs / cyc.size();
}

CadenceResult analyse_cadence(const ImuSeries& s, const CadenceConfig& c) {
  CadenceResult r; r.imu_id = s.imu_id;
  if (s.fs <= 0) return r;
  size_t W = (size_t)std::lround(c.window_s * s.fs), H = (size_t)std::max<long>(1, std::lround(c.hop_s * s.fs));
  for (const auto& p : s.pieces) {
    if (p.amag.size() < W) continue;
    std::vector<double> bp = dsp::bandpass_zero_phase(p.amag, c.band_lo, std::min(c.band_hi, s.fs * 0.45), s.fs);
    for (size_t st = 0; st + W <= bp.size(); st += H) {
      std::vector<double> w(bp.begin() + st, bp.begin() + st + W);
      CadenceWindow cw;
      cw.t_mid = p.t0 + (st + W / 2.0) / s.fs;
      cw.rms = dsp::rms(w);
      dsp::Fundamental f = dsp::fundamental(w, s.fs, c.f_min, c.f_max, c.min_strength);
      if (f.freq_hz > 0) {
        cw.freq_hz = f.freq_hz; cw.cpm = f.freq_hz * 60; cw.period_s = f.period_s; cw.strength = f.strength; cw.subharmonic = f.subharmonic_chosen;
        window_regularity(w, s.fs, f.period_s, &cw);
        std::vector<double> ac = dsp::autocorr(dsp::detrend_mean(w), (size_t)(f.period_s * s.fs) + 2);
        size_t full = (size_t)std::lround(f.period_s * s.fs), half = (size_t)std::lround(f.period_s * s.fs / 2);
        if (full < ac.size() && ac[full] > 0.05 && half > 0) cw.half_cycle_ratio = std::max(-1.0, std::min(1.0, ac[half] / ac[full]));
      }
      r.windows.push_back(cw);
    }
  }
  std::vector<double> f, cv, cc;
  for (auto& w : r.windows) if (w.freq_hz > 0) { f.push_back(w.freq_hz); if (w.interval_cv >= 0) cv.push_back(w.interval_cv); if (w.cycle_corr >= 0) cc.push_back(w.cycle_corr); }
  auto mk = [&](const char* n, const char* u, double v, const char* alg) {
    Metric m; m.name = n; m.unit = u; m.value = v; m.algorithm = alg; m.version = VER;
    m.samples_used = (uint32_t)f.size(); m.samples_excluded = (uint32_t)(r.windows.size() - f.size());
    m.quality = r.windows.empty() ? Quality::UNKNOWN : (f.size() * 2 >= r.windows.size() ? Quality::USABLE : Quality::POOR);
    m.warnings.push_back("frecuencia del ciclo de la señal de la cincha; no identifica apoyos de extremidades");
    return m;
  };
  if (!f.empty()) {
    Metric m = mk("cadencia_media", "ciclos/min", dsp::mean(f) * 60, "autocorrelación en ventanas de 6 s, comprobación de subarmónico");
    m.uncertainty = dsp::stddev(f) * 60;
    r.metrics.push_back(m);
    r.metrics.push_back(mk("duracion_media_ciclo", "s", 1.0 / dsp::mean(f), "1 / frecuencia media"));
    r.metrics.push_back(mk("variabilidad_cadencia", "CV", dsp::mean(f) > 0 ? dsp::stddev(f) / dsp::mean(f) : 0, "desviación típica / media de la frecuencia por ventana"));
  }
  if (!cv.empty()) r.metrics.push_back(mk("variabilidad_intervalos", "CV", dsp::median(cv), "mediana del CV de intervalos pico-pico por ventana"));
  if (!cc.empty()) r.metrics.push_back(mk("correlacion_entre_ciclos", "r", dsp::median(cc), "mediana de la correlación de cada ciclo con la plantilla de su ventana"));
  return r;
}

// ------------------------------------------------------------------ gait
static Gait speed_gait(double v, const GaitConfig& c) {
  if (std::isnan(v)) return Gait::UNKNOWN;
  if (v < c.stop_max) return Gait::STOPPED;
  if (v < c.walk_max) return Gait::WALK;
  if (v < c.trot_max) return Gait::TROT;
  return Gait::CANTER_GALLOP;
}

static bool freq_compatible(Gait g, double f, const GaitConfig& c) {
  switch (g) {
    case Gait::WALK: return f <= c.walk_f_max;
    case Gait::TROT: return f >= c.trot_f_min && f <= c.trot_f_max;
    case Gait::CANTER_GALLOP: return f >= c.canter_f_min;
    default: return true;
  }
}

GaitResult classify_gait(const GnssResult& g, const CadenceResult* cad, const ClockMap* imu_to_gnss, const GaitConfig& c) {
  GaitResult r;
  if (g.t.empty()) return r;
  // decision points: cadence windows (mapped to GNSS time) when available, otherwise a fixed step
  struct Pt { double t; Gait raw; Quality q; std::string basis; };
  std::vector<Pt> pts;
  auto speed_at = [&](double t) {
    std::vector<double> v;
    for (size_t i = 0; i < g.t.size(); i++) if (std::fabs(g.t[i] - t) <= c.window_s / 2 && !std::isnan(g.speed[i])) v.push_back(g.speed[i]);
    return v.empty() ? std::nan("") : dsp::median(v);
  };
  bool have_imu = cad && imu_to_gnss && !cad->windows.empty() && !imu_to_gnss->pieces.empty();
  if (have_imu) {
    for (const auto& w : cad->windows) {
      double tg;
      if (!imu_to_gnss->map(w.t_mid, &tg)) continue;
      double v = speed_at(tg);
      Gait gs = speed_gait(v, c);
      Pt p{tg, gs, Quality::USABLE, "velocidad GNSS"};
      if (w.freq_hz > 0 && gs != Gait::STOPPED && gs != Gait::UNKNOWN) {
        if (freq_compatible(gs, w.freq_hz, c)) { p.q = Quality::GOOD; p.basis = "velocidad GNSS + frecuencia IMU coherentes"; }
        else { p.q = Quality::POOR; p.basis = "velocidad GNSS y frecuencia IMU no coinciden"; }
      } else if (gs == Gait::UNKNOWN && w.freq_hz > 0) {
        p.raw = w.freq_hz <= c.walk_f_max ? Gait::WALK : w.freq_hz >= c.canter_f_min ? Gait::CANTER_GALLOP : Gait::TROT;
        p.q = Quality::POOR; p.basis = "solo frecuencia IMU";
      }
      pts.push_back(p);
    }
  }
  if (pts.empty()) {
    r.algorithm = "reglas deterministas solo con velocidad GNSS, con histéresis";
    for (double t = g.t.front(); t <= g.t.back(); t += c.window_s) {
      double v = speed_at(t);
      pts.push_back({t, speed_gait(v, c), std::isnan(v) ? Quality::UNKNOWN : Quality::USABLE, "velocidad GNSS"});
    }
  }
  std::sort(pts.begin(), pts.end(), [](const Pt& a, const Pt& b) { return a.t < b.t; });
  // hysteresis: a new state is accepted after confirm_windows consecutive points
  Gait cur = pts.empty() ? Gait::UNKNOWN : pts[0].raw;
  Gait cand = cur; int cnt = 0;
  std::vector<Pt> acc;
  for (auto p : pts) {
    if (p.raw == cur) { cnt = 0; }
    else if (p.raw == cand) { if (++cnt >= c.confirm_windows) { cur = cand; cnt = 0; } }
    else { cand = p.raw; cnt = 1; if (c.confirm_windows <= 1) { cur = cand; cnt = 0; } }
    p.raw = cur;
    acc.push_back(p);
  }
  // segments; quality = best level that covers at least 80 % of the segment's decision points
  std::vector<std::vector<int>> qcount;
  for (size_t i = 0; i < acc.size(); i++) {
    if (r.segments.empty() || r.segments.back().gait != acc[i].raw) {
      GaitSegment s; s.gait = acc[i].raw; s.t0 = acc[i].t; s.t1 = acc[i].t; s.basis = acc[i].basis;
      if (!r.segments.empty()) r.segments.back().t1 = acc[i].t;
      r.segments.push_back(s);
      qcount.push_back(std::vector<int>(5, 0));
    } else {
      r.segments.back().t1 = acc[i].t;
    }
    qcount.back()[std::min<int>((int)acc[i].q, 4)]++;
    if (acc[i].q == Quality::GOOD) r.segments.back().basis = acc[i].basis;
  }
  for (size_t k = 0; k < r.segments.size(); k++) {
    int total = 0; for (int c2 : qcount[k]) total += c2;
    int cum = 0; Quality q = Quality::UNKNOWN;
    for (int lvl = 0; lvl < 5; lvl++) { cum += qcount[k][lvl]; if (cum * 10 >= total * 8) { q = (Quality)lvl; break; } }
    r.segments[k].quality = q;
  }
  for (auto& s : r.segments) if (s.t1 - s.t0 < c.min_segment_s && s.gait != Gait::UNKNOWN) { s.gait = Gait::TRANSITION; s.basis = "segmento más corto que " + std::to_string((int)c.min_segment_s) + " s"; }
  // merge consecutive transitions
  std::vector<GaitSegment> merged;
  for (auto& s : r.segments) {
    if (!merged.empty() && merged.back().gait == s.gait) merged.back().t1 = s.t1;
    else merged.push_back(s);
  }
  r.segments = merged;
  // time and mean speed per gait
  for (int k = 0; k <= 5; k++) {
    double tsum = 0, vsum = 0; int vn = 0;
    for (auto& s : r.segments) if ((int)s.gait == k) {
      tsum += s.t1 - s.t0;
      for (size_t i = 0; i < g.t.size(); i++) if (g.t[i] >= s.t0 && g.t[i] < s.t1 && !std::isnan(g.speed[i])) { vsum += g.speed[i]; vn++; }
    }
    if (tsum <= 0) continue;
    Metric m; m.name = std::string("tiempo_") + gait_name((Gait)k); m.unit = "s"; m.value = tsum; m.algorithm = r.algorithm; m.version = r.version;
    m.quality = Quality::USABLE; m.warnings.push_back("umbrales iniciales, no validados para cada caballo");
    r.metrics.push_back(m);
    if (vn) { Metric v = m; v.name = std::string("velocidad_media_") + gait_name((Gait)k); v.unit = "m/s"; v.value = vsum / vn; r.metrics.push_back(v); }
  }
  return r;
}

}  // namespace avoeq
