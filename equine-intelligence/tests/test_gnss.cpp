#include "eq_test.h"
#include "avo_eq/gnss.h"
#include "avo_eq/validation.h"
#include "synth.h"

using namespace avoeq;

EQ_TEST(gnss, straight_then_circle_distance_speed_radius) {
  synth::Truth tr;
  avoeq::Session s;
  s.gnss = synth::track({{60, 5.0, 0}, {60, 5.0, 20.0}}, 8, &tr);
  auto v = validate(s);
  auto g = analyse_gnss(s, v);
  double d = -1;
  for (auto& m : g.metrics) if (m.name == "distancia") d = m.value;
  // analytic distance of the path between first and last epoch = v * (n-1) * dt
  CHECK_NEAR(d, 5.0 * (s.gnss.size() - 1) / 8.0, 0.002 * d);
  // inside the circle (away from its edges): radius 20 m, turn rate v/r = 14.3 deg/s
  std::vector<double> rr, ww;
  for (size_t i = 0; i < g.t.size(); i++) if (g.t[i] > 65 && g.t[i] < 115) { rr.push_back(g.radius[i]); ww.push_back(g.heading_rate[i]); }
  CHECK(!rr.empty());
  double rm = 0, wm = 0; for (double x : rr) rm += x / rr.size(); for (double x : ww) wm += x / ww.size();
  CHECK_NEAR(rm, 20.0, 0.2);
  CHECK_NEAR(wm, 5.0 / 20.0 * 180 / synth::PI, 0.15);
  // straight part: no radius
  for (size_t i = 0; i < g.t.size(); i++) if (g.t[i] > 5 && g.t[i] < 55) CHECK(std::isnan(g.radius[i]));
}

EQ_TEST(gnss, acceleration_of_a_known_ramp_with_noise) {
  // speed v(t) = 1 + 2 t for 3 s (2 m/s²), noise σ = 0.1 m/s on every epoch
  avoeq::Session s;
  std::vector<synth::Leg> legs;
  for (int k = 0; k < 24; k++) legs.push_back({0.125, 1 + 2 * (k * 0.125), 0});
  for (int k = 0; k < 40; k++) legs.push_back({0.125, 7, 0});
  s.gnss = synth::track(legs, 8, nullptr, nullptr, 0.1, 5);
  auto g = analyse_gnss(s, validate(s));
  std::vector<double> a, sg;
  for (size_t i = 0; i < g.t.size(); i++) if (g.t[i] > 0.6 && g.t[i] < 2.4) { a.push_back(g.accel[i]); sg.push_back(g.accel_sigma[i]); }
  double am = 0; for (double x : a) am += x / a.size();
  CHECK_NEAR(am, 2.0, 0.1);
  // the reported uncertainty must be of the right order: ±0.5 s window, 9 points, σv 0.1 -> σa ≈ 0.1/sqrt(Σdt²) ≈ 0.15
  CHECK(sg[sg.size() / 2] > 0.08 && sg[sg.size() / 2] < 0.3);
  // constant-speed part: |accel| small
  for (size_t i = 0; i < g.t.size(); i++) if (g.t[i] > 4 && g.t[i] < 7.5) CHECK(std::fabs(g.accel[i]) < 4 * g.accel_sigma[i] + 0.05);
}

static int rtk_plan(double t) { return t < 10 ? 0 : t < 30 ? 2 : t < 35 ? 1 : 2; }

EQ_TEST(gnss, rtk_statistics_follow_the_planned_states) {
  avoeq::Session s;
  s.gnss = synth::track({{60, 3.0, 0}}, 8, nullptr, rtk_plan);
  auto g = analyse_gnss(s, validate(s));
  CHECK_NEAR(g.rtk.time_to_first_fix_s, 10.0, 0.13);
  CHECK(g.rtk.fix_losses == 1);
  CHECK_NEAR(g.rtk.longest_outage_s, 5.0, 0.13);
  CHECK_NEAR(g.rtk.fixed_s, 45.0, 0.25);
  CHECK_NEAR(g.rtk.float_s, 5.0, 0.25);
  CHECK_NEAR(g.rtk.dgnss_s + g.rtk.gnss_s, 10.0, 0.25);
  CHECK_NEAR(g.rtk.hacc_median_fixed_m, 0.014, 1e-9);
}

EQ_TEST(validation, impossible_duplicate_gap_and_jump_are_flagged_not_changed) {
  avoeq::Session s;
  s.gnss = synth::track({{20, 4.0, 0}}, 8, nullptr);
  auto copy = s.gnss;
  s.gnss[40].gspeed_ms = 60;                     // impossible
  s.gnss[60] = s.gnss[59];                       // duplicate epoch
  s.gnss.erase(s.gnss.begin() + 80, s.gnss.begin() + 88);   // 1 s gap
  s.gnss[100].lat_deg += 0.001;                  // ~111 m jump
  auto v = validate(s);
  CHECK(v.gnss_flags[40] & GF_IMPOSSIBLE);
  CHECK(v.gnss_flags[60] & GF_DUPLICATE);
  CHECK(v.gnss_flags[80] & GF_GAP_BEFORE);
  CHECK(v.gnss_missing_epochs == 8);
  CHECK((v.gnss_flags[100] & GF_POS_JUMP) || (v.gnss_flags[101] & GF_POS_JUMP));
  CHECK(s.gnss[40].gspeed_ms == 60);             // original kept
  auto g = analyse_gnss(s, v);
  CHECK(std::isnan(g.speed[40]));                // excluded from derived series
}
