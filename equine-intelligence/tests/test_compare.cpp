// Session Comparison Engine (simulation).
#include "eq_test.h"
#include "avo_eq/compare.h"
#include "avo_eq/dsp.h"
#include "avo_eq/json.h"
#include "synth.h"

using namespace avoeq;

static double v30(double) { return 3.0; }
static double v33(double) { return 3.3; }
static double v70(double) { return 7.0; }
static double w_course(double t) {    // straight 15 s, right turn R = 20 m (at 3 m/s: ω = 0.15) for 180°, straight
  const double T1 = synth::PI / 0.15;
  return (t >= 15 && t < 15 + T1) ? 0.15 : 0.0;
}
static double w_course33(double t) {  // same geometry at 3.3 m/s: same radius, turn earlier in time
  const double T1 = synth::PI * 20 / 3.3, t0 = 15 * 3.0 / 3.3;
  return (t >= t0 && t < t0 + T1) ? 3.3 / 20 : 0.0;
}

static Analysis an(const std::vector<GnssEpoch>& g, const char* id) { Session s; s.session_id = id; s.gnss = g; return analyse(s); }

EQ_TEST(compare, same_route_aligned_by_distance) {
  auto A = an(synth::track_fn(55, 8, v30, w_course, 0.03), "A");
  auto B = an(synth::track_fn(50, 8, v33, w_course33, 0.03, 0, 5), "B");
  Selection all;
  auto c = compare_sessions(A, B, all, all, true);
  REPORT("recorrido: comparable %d, separación mediana %.2f m, cobertura %.2f, Δv %.3f m/s, Δt %.2f s\n", c.route.comparable, c.route.median_xtrack_m, c.route.coverage, c.route.mean_speed_diff, c.route.total_time_diff_s);
  CHECK(c.route.comparable);
  CHECK_NEAR(c.route.mean_speed_diff, 0.3, 0.05);
  CHECK(c.route.total_time_diff_s < -2);          // B is faster: less time over the same distance
  CHECK(!c.route.s.empty() && c.route.s.size() == c.route.time_diff_s.size());
  CHECK(c.curves.size() == 1);                    // the same 180° turn is recognised in both sessions
  CHECK(c.pattern.computed);
}

EQ_TEST(compare, different_route_is_not_comparable_by_position) {
  auto A = an(synth::track_fn(55, 8, v30, w_course, 0.03), "A");
  auto g = synth::track_fn(55, 8, v30, w_course, 0.03);
  for (auto& e : g) e.lat_deg += 40.0 / synth::M_PER_DEG_LAT;      // 40 m to the north
  auto B = an(g, "B");
  auto c = compare_sessions(A, B, Selection(), Selection(), true);
  CHECK(!c.route.comparable);
  CHECK(c.route.reason.find("separación") != std::string::npos);
  CHECK(c.curves.empty());
}

EQ_TEST(compare, different_gait_limits_cadence_comparison) {
  auto A = an(synth::track_fn(40, 8, v30, w_course, 0.03), "A");
  auto B = an(synth::track_fn(40, 8, v70, w_course, 0.03), "B");
  auto c = compare_sessions(A, B, Selection(), Selection(), false);
  bool reason = false; for (auto& r : c.reasons) reason |= r.find("aire dominante distinto") != std::string::npos;
  CHECK(reason);
  for (auto& d : c.diffs) if (d.name == "cadencia") CHECK(!d.comparable);
}

EQ_TEST(compare, section_selections) {
  auto A = an(synth::track_fn(55, 8, v30, w_course, 0.03), "A");
  Selection t; t.kind = Selection::TIME; t.a = 5; t.b = 15;
  auto st = section_stats(A, t);
  CHECK_NEAR(st.duration_s, 10, 0.3); CHECK_NEAR(st.distance_m, 30, 1.0);
  Selection d; d.kind = Selection::DISTANCE; d.a = 10; d.b = 40;
  CHECK_NEAR(section_stats(A, d).distance_m, 30, 1.0);
  Selection p; p.kind = Selection::POSITION; p.lat = A.gnss.lat[0]; p.lon = A.gnss.lon[0]; p.radius_m = 9;
  auto sp = section_stats(A, p);
  CHECK_NEAR(sp.distance_m, 9, 0.6);
  Selection g; g.kind = Selection::GAIT; g.gait = Gait::TROT;
  CHECK(section_stats(A, g).duration_s > 30);
  if (!A.events.empty()) { Selection e; e.kind = Selection::EVENT; e.event_id = A.events[0].id; CHECK(section_stats(A, e).epochs > 0); }
  Selection none; none.kind = Selection::EVENT; none.event_id = "EV9999";
  CHECK(section_stats(A, none).epochs == 0);
  auto c = compare_sessions(A, A, t, d, false);
  std::string js = comparison_json(c);
  json::Value v; CHECK(json::parse(js, &v));
  CHECK(v["formato"].str() == "avo-equine-comparison");
}

EQ_TEST(compare, dtw_basic_properties) {
  std::vector<double> a{0, 1, 2, 3, 2, 1, 0}, b{0, 0, 1, 2, 3, 2, 1, 0};
  std::vector<std::pair<size_t, size_t>> path;
  CHECK_NEAR(dsp::dtw(a, a, 0.2), 0, 1e-12);
  CHECK_NEAR(dsp::dtw(a, b, 0.3, &path), 0, 1e-12);   // b is a time-shifted copy: zero cost after warping
  CHECK(path.front().first == 0 && path.back().first == a.size() - 1 && path.back().second == b.size() - 1);
}
