// GAIT_CLASSIFIER_V1 — reference classifier kept unchanged (rules of engine 1.0.0). Only performance changes:
// speed lookups use binary search on the monotonic GNSS time base.
#include "avo_eq/motion.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>

namespace avoeq {

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
  r.version = "1.0.1";   // rules unchanged; since 1.1.0 the engine only passes VALID cadence windows
  if (g.t.empty()) return r;
  // decision points: cadence windows (mapped to GNSS time) when available, otherwise a fixed step
  struct Pt { double t; Gait raw; Quality q; std::string basis; };
  std::vector<Pt> pts;
  bool sorted = std::is_sorted(g.t.begin(), g.t.end());
  auto speed_at = [&](double t) {
    std::vector<double> v;
    if (sorted) {   // O(log n): the time base is monotonic (backwards epochs are flagged, not reordered)
      size_t i = (size_t)(std::lower_bound(g.t.begin(), g.t.end(), t - c.window_s / 2) - g.t.begin());
      for (; i < g.t.size() && g.t[i] <= t + c.window_s / 2; i++) if (!std::isnan(g.speed[i])) v.push_back(g.speed[i]);
    } else {
      for (size_t i = 0; i < g.t.size(); i++) if (std::fabs(g.t[i] - t) <= c.window_s / 2 && !std::isnan(g.speed[i])) v.push_back(g.speed[i]);
    }
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
  for (int k = 0; k <= 6; k++) {
    double tsum = 0, vsum = 0; int vn = 0;
    for (auto& s : r.segments) if ((int)s.gait == k) {
      tsum += s.t1 - s.t0;
      size_t i = sorted ? (size_t)(std::lower_bound(g.t.begin(), g.t.end(), s.t0) - g.t.begin()) : 0;
      for (; i < g.t.size(); i++) { if (sorted && g.t[i] >= s.t1) break; if (g.t[i] >= s.t0 && g.t[i] < s.t1 && !std::isnan(g.speed[i])) { vsum += g.speed[i]; vn++; } }
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
