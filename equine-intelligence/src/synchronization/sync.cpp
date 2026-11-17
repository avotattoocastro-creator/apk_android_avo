#include "avo_eq/sync.h"
#include <algorithm>
#include <cmath>

namespace avoeq {

static void linfit(const std::vector<double>& x, const std::vector<double>& y, const std::vector<size_t>& idx,
                   double* a, double* b) {
  double n = (double)idx.size(), sx = 0, sy = 0, sxx = 0, sxy = 0;
  double x0 = x[idx[0]];                       // centre for numerical stability
  for (size_t i : idx) { double u = x[i] - x0; sx += u; sy += y[i]; sxx += u * u; sxy += u * y[i]; }
  double den = n * sxx - sx * sx;
  double slope = den > 0 ? (n * sxy - sx * sy) / den : 1.0;
  double inter = (sy - slope * sx) / n;        // at x0
  *b = slope;
  *a = inter - slope * x0;
}

static ClockPiece fit_piece(const std::vector<double>& x, const std::vector<double>& y, size_t from, size_t to, const SyncConfig& c) {
  ClockPiece p;
  std::vector<size_t> idx;
  for (size_t i = from; i < to; i++) idx.push_back(i);
  p.pairs = (uint32_t)idx.size();
  p.x0 = x[from]; p.x1 = x[to - 1];
  double a, b;
  linfit(x, y, idx, &a, &b);
  for (int it = 0; it < c.iterations; it++) {
    std::vector<std::pair<double, size_t>> res;
    for (size_t i = from; i < to; i++) res.push_back({y[i] - (a + b * x[i]), i});
    std::sort(res.begin(), res.end());
    size_t keep = std::max<size_t>(3, (size_t)std::ceil(res.size() * c.envelope_quantile));
    // spread the kept points over time: take the lowest residuals per time bin so the slope is not
    // estimated from a single cluster
    size_t bins = std::min<size_t>(keep, 16);
    std::vector<size_t> sel;
    double span = std::max(1e-9, p.x1 - p.x0);
    for (size_t bn = 0; bn < bins; bn++) {
      double lo = p.x0 + span * bn / bins, hi = p.x0 + span * (bn + 1) / bins;
      std::vector<std::pair<double, size_t>> inbin;
      for (auto& r : res) if (x[r.second] >= lo && (x[r.second] < hi || bn + 1 == bins)) inbin.push_back(r);
      std::sort(inbin.begin(), inbin.end());
      size_t take = std::max<size_t>(1, inbin.size() * keep / std::max<size_t>(1, res.size()));
      for (size_t k = 0; k < take && k < inbin.size(); k++) sel.push_back(inbin[k].second);
    }
    if (sel.size() < 3) break;
    std::sort(sel.begin(), sel.end());
    linfit(x, y, sel, &a, &b);
    p.envelope_pairs = (uint32_t)sel.size();
    double s2 = 0;
    for (size_t i : sel) { double e = y[i] - (a + b * x[i]); s2 += e * e; }
    p.envelope_sd_s = std::sqrt(s2 / std::max<double>(1, (double)sel.size() - 2));
  }
  // the envelope line passes through the middle of the low points: lower it to the minimum so every
  // residual (latency) is >= 0
  double mn = 1e300;
  std::vector<double> lat;
  for (size_t i = from; i < to; i++) mn = std::min(mn, y[i] - (a + b * x[i]));
  a += mn;
  for (size_t i = from; i < to; i++) lat.push_back(y[i] - (a + b * x[i]));
  std::sort(lat.begin(), lat.end());
  p.latency_median_s = lat[lat.size() / 2];
  p.latency_p95_s = lat[std::min(lat.size() - 1, (size_t)(lat.size() * 0.95))];
  p.offset = a; p.slope = b; p.drift_ppm = (b - 1.0) * 1e6;
  return p;
}

ClockMap fit_clock(const std::vector<double>& xs, const std::vector<double>& ys, const SyncConfig& c) {
  ClockMap m;
  size_t n = std::min(xs.size(), ys.size());
  if (n < c.min_pairs) return m;
  // Pieces are cut in ARRIVAL order: a restart of the source clock makes x go back (or y - x jump).
  size_t from = 0;
  auto close_piece = [&](size_t to) {
    if (to - from < c.min_pairs) return;
    std::vector<size_t> o;
    for (size_t i = from; i < to; i++) o.push_back(i);
    std::stable_sort(o.begin(), o.end(), [&](size_t a, size_t b) { return xs[a] < xs[b]; });
    std::vector<double> x, y;
    for (size_t i : o) { x.push_back(xs[i]); y.push_back(ys[i]); }
    m.pieces.push_back(fit_piece(x, y, 0, x.size(), c));
  };
  for (size_t i = 1; i <= n; i++) {
    bool cut = (i == n);
    if (!cut) {
      double d0 = ys[i - 1] - xs[i - 1], d1 = ys[i] - xs[i];
      if (xs[i] < xs[i - 1] - c.reset_jump_s || std::fabs(d1 - d0) > c.reset_jump_s) cut = true;
    }
    if (cut) { close_piece(i); from = i; }
  }
  return m;
}

bool ClockMap::map(double x, double* y, double* sigma) const {
  for (const auto& p : pieces) {
    if (x >= p.x0 - 1.0 && x <= p.x1 + 1.0) {
      *y = p.offset + p.slope * x;
      if (sigma) *sigma = p.envelope_sd_s;
      return true;
    }
  }
  return false;
}

}  // namespace avoeq
