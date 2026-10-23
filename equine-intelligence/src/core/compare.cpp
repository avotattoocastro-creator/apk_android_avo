#include "avo_eq/compare.h"
#include "avo_eq/dsp.h"
#include "avo_eq/json.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>

namespace avoeq {

static const double R_EARTH = 6371008.8, D2R = 3.14159265358979323846 / 180.0;

const char* selection_name(Selection::Kind k) {
  switch (k) { case Selection::ALL: return "SESION"; case Selection::TIME: return "TIEMPO"; case Selection::DISTANCE: return "DISTANCIA";
    case Selection::GAIT: return "AIRE"; case Selection::EVENT: return "EVENTO"; case Selection::POSITION: return "POSICION"; }
  return "?";
}

static double hav(double la1, double lo1, double la2, double lo2) {
  double a = std::sin((la2 - la1) * D2R / 2), b = std::sin((lo2 - lo1) * D2R / 2);
  double h = a * a + std::cos(la1 * D2R) * std::cos(la2 * D2R) * b * b;
  return 2 * R_EARTH * std::asin(std::sqrt(std::min(1.0, h)));
}

static const GaitResult& chosen_gait(const Analysis& an) { return an.performance.classifier == GAIT_V2_ID ? an.gait_v2 : an.gait; }

static std::vector<bool> mask_of(const Analysis& an, const Selection& sel) {
  const GnssResult& g = an.gnss;
  std::vector<bool> m(g.t.size(), false);
  double t0 = -1e300, t1 = 1e300;
  if (sel.kind == Selection::EVENT) {
    for (auto& e : an.events) if (e.id == sel.event_id) { t0 = e.t0; t1 = e.t1; if (t1 - t0 < 4) { t0 -= 2; t1 += 2; } }
    if (t0 == -1e300) return m;
  }
  for (size_t i = 0; i < g.t.size(); i++) {
    switch (sel.kind) {
      case Selection::ALL: m[i] = true; break;
      case Selection::TIME: m[i] = g.t[i] >= sel.a && g.t[i] <= sel.b; break;
      case Selection::DISTANCE: m[i] = g.dist[i] >= sel.a && g.dist[i] <= sel.b; break;
      case Selection::EVENT: m[i] = g.t[i] >= t0 && g.t[i] <= t1; break;
      case Selection::POSITION: m[i] = !std::isnan(g.lat[i]) && hav(g.lat[i], g.lon[i], sel.lat, sel.lon) <= sel.radius_m; break;
      case Selection::GAIT: {
        for (auto& p : an.performance.segments) if (p.gait == sel.gait && g.t[i] >= p.t0 && g.t[i] < p.t1) { m[i] = true; break; }
        break;
      }
    }
  }
  return m;
}

SectionStats section_stats(const Analysis& an, const Selection& sel) {
  SectionStats st;
  const GnssResult& g = an.gnss;
  std::vector<bool> m = mask_of(an, sel);
  std::vector<double> dts; for (size_t i = 1; i < g.t.size(); i++) if (g.t[i] > g.t[i - 1]) dts.push_back(g.t[i] - g.t[i - 1]);
  double dtn = dts.empty() ? 0.125 : dsp::median(dts);
  double vsum = 0, tsum = 0, good = 0;
  for (size_t i = 0; i < g.t.size(); i++) {
    if (!m[i]) continue;
    st.epochs++;
    if (st.intervals.empty() || i == 0 || !m[i - 1] || g.t[i] - g.t[i - 1] > 2 * dtn) st.intervals.push_back({g.t[i], g.t[i]});
    else st.intervals.back().second = g.t[i];
    if (g.quality[i] == (uint8_t)Quality::GOOD) good++;
    if (i > 0 && m[i - 1] && g.usable[i] && g.usable[i - 1]) st.distance_m += g.dist[i] - g.dist[i - 1];
    if (!std::isnan(g.speed[i]) && g.quality[i] <= (uint8_t)Quality::USABLE) {
      double dt = (i + 1 < g.t.size()) ? std::min(std::max(g.t[i + 1] - g.t[i], 0.0), 2 * dtn) : dtn;
      vsum += g.speed[i] * dt; tsum += dt;
      if (std::isnan(st.speed_max) || g.speed[i] > st.speed_max) st.speed_max = g.speed[i];
    }
  }
  for (auto& iv : st.intervals) st.duration_s += iv.second - iv.first + dtn;
  if (tsum > 0) st.speed_mean = vsum / tsum;
  st.fix_fraction = st.epochs ? good / st.epochs : 0;
  auto inside = [&](double t) { for (auto& iv : st.intervals) if (t >= iv.first && t <= iv.second + dtn) return true; return false; };
  const GaitResult& gr = chosen_gait(an);
  for (auto& s : gr.segments) for (auto& iv : st.intervals) {
    double a = std::max(s.t0, iv.first), b = std::min(s.t1, iv.second + dtn);
    if (b > a) st.gait_time[(int)s.gait] += b - a;
  }
  double best = 0;
  for (int k = 0; k < 4; k++) if (st.gait_time[k] > best) { best = st.gait_time[k]; st.dominant_gait = (Gait)k; }
  uint8_t pref = 255; for (auto& w : an.fusion.windows) pref = std::min(pref, w.imu_id);
  std::vector<double> f, cc, cv;
  for (auto& w : an.fusion.windows) if (w.imu_id == pref && w.status == "OK" && inside(w.t_gnss)) {
    f.push_back(w.cadence_hz); if (!std::isnan(w.cycle_corr)) cc.push_back(w.cycle_corr); if (!std::isnan(w.interval_cv)) cv.push_back(w.interval_cv);
  }
  if (!f.empty()) st.cadence_hz = dsp::mean(f);
  if (!cc.empty()) st.cycle_corr = dsp::median(cc);
  if (!cv.empty()) st.interval_cv = dsp::median(cv);
  for (auto& e : an.events) if (inside(e.t0)) st.events++;
  return st;
}

bool project_on_polyline(const std::vector<double>& px, const std::vector<double>& py, double x, double y, size_t hint, size_t search,
                         double* along, double* cross, size_t* seg) {
  if (px.size() < 2) return false;
  size_t lo = hint > search ? hint - search : 0, hi = std::min(px.size() - 1, hint + search);
  double best = 1e300; size_t bk = lo; double bt = 0;
  for (size_t k = lo; k < hi; k++) {
    double dx = px[k + 1] - px[k], dy = py[k + 1] - py[k], L2 = dx * dx + dy * dy;
    double t = L2 > 0 ? ((x - px[k]) * dx + (y - py[k]) * dy) / L2 : 0;
    t = std::max(0.0, std::min(1.0, t));
    double ex = px[k] + t * dx - x, ey = py[k] + t * dy - y, d2 = ex * ex + ey * ey;
    if (d2 < best) { best = d2; bk = k; bt = t; }
  }
  double s = 0; for (size_t k = 0; k < bk; k++) s += std::hypot(px[k + 1] - px[k], py[k + 1] - py[k]);
  double dx = px[bk + 1] - px[bk], dy = py[bk + 1] - py[bk];
  s += bt * std::hypot(dx, dy);
  // sign: + when the point lies to the right of the direction of travel
  double cr = dx * (y - py[bk]) - dy * (x - px[bk]);
  *along = s; *cross = (cr > 0 ? -1 : 1) * std::sqrt(best); *seg = bk;
  return true;
}

static double interp(const std::vector<double>& xs, const std::vector<double>& ys, double x) {
  if (xs.empty()) return NAN;
  if (x <= xs.front()) return ys.front();
  if (x >= xs.back()) return ys.back();
  size_t k = (size_t)(std::upper_bound(xs.begin(), xs.end(), x) - xs.begin());
  double f = (x - xs[k - 1]) / std::max(1e-12, xs[k] - xs[k - 1]);
  return ys[k - 1] + f * (ys[k] - ys[k - 1]);
}

static void align_route(const Analysis& A, const Analysis& B, const Selection& sa, const Selection& sb, RouteAlignment* r) {
  r->attempted = true;
  std::vector<bool> ma = mask_of(A, sa), mb = mask_of(B, sb);
  const GnssResult& ga = A.gnss; const GnssResult& gb = B.gnss;
  size_t i0 = ga.t.size();
  for (size_t i = 0; i < ga.t.size(); i++) if (!std::isnan(ga.lat[i])) { i0 = i; break; }
  if (i0 == ga.t.size()) { r->reason = "sesión de referencia sin posiciones"; return; }
  double c0 = std::cos(ga.lat[i0] * D2R);
  auto enu = [&](double lat, double lon, double* x, double* y) { *x = (lon - ga.lon[i0]) * D2R * R_EARTH * c0; *y = (lat - ga.lat[i0]) * D2R * R_EARTH; };
  // reference polyline: usable epochs of A, thinned to ≥ 0.5 m spacing
  std::vector<double> px, py, pt, pv, ps;
  for (size_t i = 0; i < ga.t.size(); i++) {
    if (!ma[i] || std::isnan(ga.lat[i]) || ga.quality[i] > (uint8_t)Quality::USABLE) continue;
    double x, y; enu(ga.lat[i], ga.lon[i], &x, &y);
    if (!px.empty() && std::hypot(x - px.back(), y - py.back()) < 0.5) continue;
    ps.push_back(px.empty() ? 0 : ps.back() + std::hypot(x - px.back(), y - py.back()));
    px.push_back(x); py.push_back(y); pt.push_back(ga.t[i]); pv.push_back(ga.speed[i]);
  }
  if (px.size() < 5) { r->reason = "recorrido de referencia demasiado corto o sin calidad suficiente"; return; }
  double La = ps.back();
  std::vector<double> sb_, tb, vb, xt;
  size_t hint = 0; bool first = true; int back = 0, steps = 0;
  for (size_t i = 0; i < gb.t.size(); i++) {
    if (!mb[i] || std::isnan(gb.lat[i]) || gb.quality[i] > (uint8_t)Quality::USABLE) continue;
    double x, y, s, d; size_t seg; enu(gb.lat[i], gb.lon[i], &x, &y);
    // first point: global search; then local search around the previous match (keeps the progression)
    if (!project_on_polyline(px, py, x, y, first ? 0 : hint, first ? px.size() : 60, &s, &d, &seg)) continue;
    if (!first) { steps++; if (s < sb_.back() - 0.5) back++; }
    first = false; hint = seg;
    sb_.push_back(s); tb.push_back(gb.t[i]); vb.push_back(gb.speed[i]); xt.push_back(std::fabs(d));
  }
  if (sb_.size() < 5) { r->reason = "la sesión comparada no tiene posiciones suficientes en la selección"; return; }
  double hacc_tol = 3.0;
  if (A.gnss.rtk.hacc_median_fixed_m < 0 || B.gnss.rtk.hacc_median_fixed_m < 0) hacc_tol = 5.0;
  r->tolerance_m = hacc_tol;
  std::vector<double> xs = xt; std::sort(xs.begin(), xs.end());
  r->median_xtrack_m = dsp::median(xt);
  r->p90_xtrack_m = xs[(size_t)(0.9 * (xs.size() - 1))];
  double smin = *std::min_element(sb_.begin(), sb_.end()), smax = *std::max_element(sb_.begin(), sb_.end());
  r->coverage = La > 0 ? (smax - smin) / La : 0;
  r->monotonic = steps ? 1.0 - (double)back / steps : 0;
  std::vector<std::string> why;
  if (r->median_xtrack_m > hacc_tol) why.push_back("separación lateral mediana mayor que la tolerancia");
  if (r->p90_xtrack_m > 2 * hacc_tol) why.push_back("separación lateral p90 mayor que el doble de la tolerancia");
  if (r->coverage < 0.8) why.push_back("cubre menos del 80 % del recorrido de referencia");
  if (r->monotonic < 0.9) why.push_back("el avance sobre el recorrido no es monótono (sentido o trazado distinto)");
  r->comparable = why.empty();
  for (auto& w : why) r->reason += (r->reason.empty() ? "" : "; ") + w;
  if (!r->comparable) return;
  r->reason = "mismo recorrido: alineación por proyección sobre la referencia y distancia acumulada";
  // B: monotone envelope (first time each distance is reached)
  std::vector<double> ms, mt, mv; double run = -1e300;
  for (size_t i = 0; i < sb_.size(); i++) if (sb_[i] > run + 0.05) { run = sb_[i]; ms.push_back(sb_[i]); mt.push_back(tb[i]); mv.push_back(vb[i]); }
  double s0 = std::max(ms.front(), 0.0), s1 = std::min(ms.back(), La);
  double ta0 = interp(ps, pt, s0), tb0 = interp(ms, mt, s0);
  std::vector<double> dvs;
  for (double s = s0; s <= s1; s += 2.0) {
    r->s.push_back(s);
    double va = interp(ps, pv, s), v2 = interp(ms, mv, s);
    r->speed_a.push_back(va); r->speed_b.push_back(v2);
    r->time_diff_s.push_back((interp(ms, mt, s) - tb0) - (interp(ps, pt, s) - ta0));
    if (!std::isnan(va) && !std::isnan(v2)) dvs.push_back(v2 - va);
  }
  if (!dvs.empty()) r->mean_speed_diff = dsp::mean(dvs);
  if (!r->time_diff_s.empty()) r->total_time_diff_s = r->time_diff_s.back();
}

static std::vector<double> profile(const Analysis& an, const Selection& sel, size_t n) {
  std::vector<bool> m = mask_of(an, sel);
  std::vector<double> d, v;
  for (size_t i = 0; i < an.gnss.t.size(); i++) if (m[i] && !std::isnan(an.gnss.speed[i])) { d.push_back(an.gnss.dist[i]); v.push_back(an.gnss.speed[i]); }
  std::vector<double> out;
  if (d.size() < 4 || d.back() - d.front() <= 0) return out;
  for (size_t k = 0; k < n; k++) out.push_back(interp(d, v, d.front() + (d.back() - d.front()) * k / (n - 1)));
  return out;
}

Comparison compare_sessions(const Analysis& A, const Analysis& B, const Selection& sa, const Selection& sb, bool same_route) {
  Comparison c; c.session_a = A.session_id; c.session_b = B.session_id; c.sel_a = sa; c.sel_b = sb;
  c.a = section_stats(A, sa); c.b = section_stats(B, sb);
  if (!c.a.epochs || !c.b.epochs) c.reasons.push_back("una de las selecciones está vacía");
  if (c.a.fix_fraction < 0.5 || c.b.fix_fraction < 0.5) c.reasons.push_back("calidad GNSS insuficiente en alguna selección (RTK FIX < 50 %)");
  bool same_gait = c.a.dominant_gait == c.b.dominant_gait && (int)c.a.dominant_gait <= 3;
  if (!same_gait) c.reasons.push_back(std::string("aire dominante distinto: ") + gait_name(c.a.dominant_gait) + " / " + gait_name(c.b.dominant_gait));
  double vref = std::max(0.5, 0.5 * ((std::isnan(c.a.speed_mean) ? 0 : c.a.speed_mean) + (std::isnan(c.b.speed_mean) ? 0 : c.b.speed_mean)));
  bool same_speed = !std::isnan(c.a.speed_mean) && !std::isnan(c.b.speed_mean) && std::fabs(c.a.speed_mean - c.b.speed_mean) / vref < 0.15;
  bool quality_ok = c.a.epochs && c.b.epochs && c.a.fix_fraction >= 0.5 && c.b.fix_fraction >= 0.5;
  c.comparable = quality_ok;
  auto diff = [&](const char* name, const char* unit, double a, double b, bool comparable, std::string ctx) {
    MetricDiff d; d.name = name; d.unit = unit; d.a = a; d.b = b; d.diff = b - a; d.comparable = comparable && !std::isnan(a) && !std::isnan(b); d.context = ctx;
    if (std::isnan(a) || std::isnan(b)) d.context = "dato no disponible en alguna selección";
    c.diffs.push_back(d);
  };
  std::string qctx = quality_ok ? "calidad GNSS suficiente en ambas" : "calidad GNSS insuficiente";
  diff("duracion", "s", c.a.duration_s, c.b.duration_s, c.a.epochs && c.b.epochs, "selecciones de " + std::string(selection_name(sa.kind)) + " / " + selection_name(sb.kind));
  diff("distancia", "m", c.a.distance_m, c.b.distance_m, quality_ok, qctx);
  diff("velocidad_media", "m/s", c.a.speed_mean, c.b.speed_mean, quality_ok, qctx);
  diff("velocidad_maxima", "m/s", c.a.speed_max, c.b.speed_max, quality_ok, qctx);
  std::string ictx = !same_gait ? "aires distintos: la cadencia y la regularidad no son comparables" : !same_speed ? "velocidades distintas (>15 %): la cadencia depende de la velocidad" : "mismo aire y velocidad similar";
  diff("cadencia", "Hz", c.a.cadence_hz, c.b.cadence_hz, same_gait && same_speed, ictx);
  diff("correlacion_ciclos", "r", c.a.cycle_corr, c.b.cycle_corr, same_gait && same_speed, ictx);
  diff("cv_intervalos", "CV", c.a.interval_cv, c.b.interval_cv, same_gait && same_speed, ictx);
  diff("fraccion_fix", "1", c.a.fix_fraction, c.b.fix_fraction, true, "calidad de adquisición");
  diff("eventos", "n", c.a.events, c.b.events, quality_ok, "número de eventos detectados en la selección");
  for (int k = 0; k <= 6; k++) {
    double ta = c.a.duration_s > 0 ? c.a.gait_time[k] / c.a.duration_s : 0, tb = c.b.duration_s > 0 ? c.b.gait_time[k] / c.b.duration_s : 0;
    if (ta > 0 || tb > 0) diff((std::string("fraccion_") + gait_name((Gait)k)).c_str(), "1", ta, tb, quality_ok, "distribución de aires (" + chosen_gait(A).classifier + ")");
  }
  if (same_route) {
    align_route(A, B, sa, sb, &c.route);
    if (!c.route.comparable) c.reasons.push_back("recorrido no comparable: " + c.route.reason);
  }
  // pattern (shape of the speed profile over the section's own distance), always labelled as non-spatial
  std::vector<double> pa = profile(A, sa, 100), pb = profile(B, sb, 100);
  if (!pa.empty() && !pb.empty()) {
    std::vector<std::pair<size_t, size_t>> path;
    double d = dsp::dtw(pa, pb, 0.1, &path);
    if (std::isfinite(d) && !path.empty()) { c.pattern.computed = true; c.pattern.dtw_distance = d / path.size(); c.pattern.warp_ratio = (double)path.size() / pa.size(); }
  }
  // equivalent curves (same direction, centres close relative to the radius)
  for (auto& ca : A.curves.curves) for (auto& cb : B.curves.curves) {
    if (ca.direction != cb.direction) continue;
    double dc = hav(ca.center_lat, ca.center_lon, cb.center_lat, cb.center_lon);
    if (dc > 0.5 * std::max(ca.radius_m, cb.radius_m)) continue;
    CurveMatch m; m.curve_a = ca.id; m.curve_b = cb.id; m.center_dist_m = dc; m.d_radius_m = cb.radius_m - ca.radius_m;
    m.d_entry_speed = cb.v_entry - ca.v_entry; m.d_lat_acc = cb.lat_acc_mean - ca.lat_acc_mean;
    c.curves.push_back(m);
  }
  if (!c.comparable && c.reasons.empty()) c.reasons.push_back("selecciones no comparables");
  return c;
}

static std::string n(double v) { if (std::isnan(v) || std::isinf(v)) return "null"; char b[40]; snprintf(b, sizeof(b), "%.10g", v); return b; }

static void sel_json(std::ostringstream& o, const Selection& s) {
  o << "{\"tipo\":\"" << selection_name(s.kind) << "\",\"a\":" << n(s.a) << ",\"b\":" << n(s.b) << ",\"aire\":\"" << gait_code(s.gait) << "\",\"evento\":\"" << json::escape(s.event_id)
    << "\",\"lat\":" << n(s.lat) << ",\"lon\":" << n(s.lon) << ",\"radio_m\":" << n(s.radius_m) << "}";
}
static void stats_json(std::ostringstream& o, const SectionStats& s) {
  o << "{\"duracion_s\":" << n(s.duration_s) << ",\"distancia_m\":" << n(s.distance_m) << ",\"velocidad_media\":" << n(s.speed_mean) << ",\"velocidad_max\":" << n(s.speed_max)
    << ",\"cadencia_hz\":" << n(s.cadence_hz) << ",\"correlacion_ciclos\":" << n(s.cycle_corr) << ",\"cv_intervalos\":" << n(s.interval_cv) << ",\"fraccion_fix\":" << n(s.fix_fraction)
    << ",\"eventos\":" << s.events << ",\"epocas\":" << s.epochs << ",\"aire_dominante\":\"" << gait_code(s.dominant_gait) << "\",\"intervalos\":[";
  for (size_t i = 0; i < s.intervals.size(); i++) o << (i ? "," : "") << "[" << n(s.intervals[i].first) << "," << n(s.intervals[i].second) << "]";
  o << "]}";
}

std::string comparison_json(const Comparison& c) {
  std::ostringstream o;
  o << "{\"formato\":\"avo-equine-comparison\",\"version\":\"" << c.version << "\",\"sesion_a\":\"" << json::escape(c.session_a) << "\",\"sesion_b\":\"" << json::escape(c.session_b)
    << "\",\"seleccion_a\":"; sel_json(o, c.sel_a); o << ",\"seleccion_b\":"; sel_json(o, c.sel_b);
  o << ",\"comparable\":" << (c.comparable ? "true" : "false") << ",\"motivos\":[";
  for (size_t i = 0; i < c.reasons.size(); i++) o << (i ? "," : "") << "\"" << json::escape(c.reasons[i]) << "\"";
  o << "],\"a\":"; stats_json(o, c.a); o << ",\"b\":"; stats_json(o, c.b);
  o << ",\"diferencias\":[";
  for (size_t i = 0; i < c.diffs.size(); i++) {
    auto& d = c.diffs[i];
    o << (i ? "," : "") << "{\"metrica\":\"" << d.name << "\",\"unidad\":\"" << d.unit << "\",\"a\":" << n(d.a) << ",\"b\":" << n(d.b) << ",\"diferencia\":" << n(d.diff)
      << ",\"comparable\":" << (d.comparable ? "true" : "false") << ",\"contexto\":\"" << json::escape(d.context) << "\"}";
  }
  const RouteAlignment& r = c.route;
  o << "],\"recorrido\":{\"intentado\":" << (r.attempted ? "true" : "false") << ",\"comparable\":" << (r.comparable ? "true" : "false") << ",\"motivo\":\"" << json::escape(r.reason)
    << "\",\"separacion_mediana_m\":" << n(r.median_xtrack_m) << ",\"separacion_p90_m\":" << n(r.p90_xtrack_m) << ",\"tolerancia_m\":" << n(r.tolerance_m)
    << ",\"cobertura\":" << n(r.coverage) << ",\"monotonia\":" << n(r.monotonic) << ",\"diferencia_velocidad_media\":" << n(r.mean_speed_diff)
    << ",\"diferencia_tiempo_total_s\":" << n(r.total_time_diff_s) << ",\"perfil\":{\"s\":[";
  for (size_t i = 0; i < r.s.size(); i++) o << (i ? "," : "") << n(r.s[i]);
  o << "],\"velocidad_a\":["; for (size_t i = 0; i < r.speed_a.size(); i++) o << (i ? "," : "") << n(r.speed_a[i]);
  o << "],\"velocidad_b\":["; for (size_t i = 0; i < r.speed_b.size(); i++) o << (i ? "," : "") << n(r.speed_b[i]);
  o << "],\"diferencia_tiempo_s\":["; for (size_t i = 0; i < r.time_diff_s.size(); i++) o << (i ? "," : "") << n(r.time_diff_s[i]);
  o << "]}},\"patron\":{\"calculado\":" << (c.pattern.computed ? "true" : "false") << ",\"distancia_dtw_m_s\":" << n(c.pattern.dtw_distance)
    << ",\"deformacion\":" << n(c.pattern.warp_ratio) << ",\"nota\":\"" << json::escape(c.pattern.note) << "\"},\"curvas_equivalentes\":[";
  for (size_t i = 0; i < c.curves.size(); i++) {
    auto& m = c.curves[i];
    o << (i ? "," : "") << "{\"curva_a\":" << m.curve_a << ",\"curva_b\":" << m.curve_b << ",\"distancia_centros_m\":" << n(m.center_dist_m) << ",\"diferencia_radio_m\":" << n(m.d_radius_m)
      << ",\"diferencia_v_entrada\":" << n(m.d_entry_speed) << ",\"diferencia_a_lateral\":" << n(m.d_lat_acc) << "}";
  }
  o << "]}";
  return o.str();
}

}  // namespace avoeq
