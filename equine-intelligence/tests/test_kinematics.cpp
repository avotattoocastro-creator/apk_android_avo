// Acceleration engine and curve engine against analytic trajectories (simulation, not physical validation).
#include "eq_test.h"
#include "avo_eq/engine.h"
#include "avo_eq/kinematics.h"
#include "synth.h"

using namespace avoeq;

static double v_ramp(double t) { return t < 10 ? 2.0 : t < 14 ? 2.0 + (t - 10) : t < 24 ? 6.0 : t < 26 ? 6.0 - 1.5 * (t - 24) : 3.0; }
static double v_const4(double) { return 4.0; }
static double v_const1(double) { return 1.0; }
static double w_zero(double) { return 0.0; }
// straight 10 s, right turn R=20 m at 4 m/s for 180°, straight 8 s, left turn R=30 m for 90°, straight 8 s
static double w_course(double t) {
  const double T1 = synth::PI * 20 / 4, T2 = (synth::PI / 2) * 30 / 4;
  if (t < 10) return 0;
  if (t < 10 + T1) return 4.0 / 20;
  if (t < 18 + T1) return 0;
  if (t < 18 + T1 + T2) return -4.0 / 30;
  return 0;
}
static double w_tight_slow(double) { return 1.0 / 5.0; }

static GnssResult gnss_of(const std::vector<GnssEpoch>& e) { Session s; s.gnss = e; auto v = validate(s); return analyse_gnss(s, v); }

EQ_TEST(kinematics, sustained_acceleration_and_deceleration) {
  auto g = gnss_of(synth::track_fn(32, 8, v_ramp, w_zero, 0.05));
  auto k = analyse_kinematics(g);
  int na = 0, nd = 0;
  for (auto& e : k.events) {
    if (e.type == "ACELERACION_SOSTENIDA") { na++; CHECK_NEAR(e.mean, 1.0, 0.15); CHECK_NEAR(e.dv, 4.0, 0.8); CHECK_NEAR(e.t0, 10.0, 0.8); REPORT("aceleración %.2f m/s² (%.1f-%.1f s), Δv %.2f\n", e.mean, e.t0, e.t1, e.dv); }
    if (e.type == "DESACELERACION_SOSTENIDA") { nd++; CHECK_NEAR(e.mean, -1.5, 0.25); REPORT("desaceleración %.2f m/s² (%.1f-%.1f s)\n", e.mean, e.t0, e.t1); }
    CHECK(e.source.find("TRAYECTORIA_GNSS") == 0);
  }
  CHECK(na == 1); CHECK(nd == 1);
}

EQ_TEST(kinematics, noise_does_not_create_events) {
  int false_events = 0;
  for (unsigned seed = 1; seed <= 10; seed++) {
    auto g = gnss_of(synth::track_fn(60, 8, v_const4, w_zero, 0.10, 0.0, seed));
    auto k = analyse_kinematics(g);
    false_events += (int)k.events.size();
  }
  REPORT("eventos falsos en 10 sesiones de 60 s con ruido de velocidad 0,10 m/s: %d\n", false_events);
  CHECK(false_events == 0);
}

EQ_TEST(kinematics, irregular_timestamps_keep_events_and_no_false_peaks) {
  auto g = gnss_of(synth::track_fn(32, 8, v_ramp, w_zero, 0.05, 0.25, 7));   // 25 % of epochs missing
  auto k = analyse_kinematics(g);
  int na = 0, peaks_false = 0;
  for (auto& e : k.events) {
    if (e.type == "ACELERACION_SOSTENIDA") { na++; CHECK_NEAR(e.mean, 1.0, 0.25); }
    if (e.type == "PICO_LATERAL") peaks_false++;
  }
  CHECK(na == 1);
  CHECK(peaks_false == 0);
}

EQ_TEST(kinematics, lateral_acceleration_and_curvature_on_a_circle) {
  auto g = gnss_of(synth::track_fn(40, 8, v_const4, w_course, 0.03));
  // inside the right turn (t in 12..23 s): κ = 1/20, a_lat = v²/R = 0.8 m/s²
  int n = 0; double worst_k = 0, worst_a = 0, max_ratio = 0;
  for (size_t i = 0; i < g.t.size(); i++) if (g.t[i] > 11.5 && g.t[i] < 24.0 && !std::isnan(g.curvature[i])) {
    n++;
    worst_k = std::max(worst_k, std::fabs(g.curvature[i] - 0.05));
    worst_a = std::max(worst_a, std::fabs(g.lat_accel[i] - 0.8));
    max_ratio = std::max(max_ratio, std::fabs(g.lat_accel[i] - 0.8) / g.lat_accel_sigma[i]);
  }
  REPORT("curvatura: error máx %.4f 1/m; aceleración lateral: error máx %.3f m/s² (%.1f σ)\n", worst_k, worst_a, max_ratio);
  CHECK(n > 50);
  CHECK(worst_k < 0.01);
  CHECK(worst_a < 0.2);
  CHECK(max_ratio < 5);     // the propagated uncertainty is of the right order
}

EQ_TEST(curves, course_with_two_turns) {
  auto g = gnss_of(synth::track_fn(55, 8, v_const4, w_course, 0.03));
  auto cr = analyse_curves(g);
  for (auto& c : cr.curves) REPORT("curva %d %s %.0f° R=%.1f±%.1f m (geom %.1f) v=%.2f a_lat=%.2f %s\n", c.id, c.direction.c_str(), c.heading_change_deg, c.radius_m, c.radius_sigma_m, c.radius_geom_m, c.v_mean, c.lat_acc_mean, quality_name(c.quality));
  CHECK(cr.curves.size() == 2);
  if (cr.curves.size() == 2) {
    CHECK(cr.curves[0].direction == "DERECHA");
    CHECK_NEAR(cr.curves[0].heading_change_deg, 180, 20);
    CHECK_NEAR(cr.curves[0].radius_m, 20, 1.5);
    CHECK_NEAR(cr.curves[0].radius_geom_m, 20, 1.0);
    CHECK_NEAR(cr.curves[0].lat_acc_mean, 0.8, 0.1);
    CHECK_NEAR(cr.curves[0].v_entry, 4, 0.2);
    CHECK(cr.curves[1].direction == "IZQUIERDA");
    CHECK_NEAR(cr.curves[1].heading_change_deg, -90, 15);
    CHECK_NEAR(cr.curves[1].radius_m, 30, 2.5);
  }
}

EQ_TEST(curves, no_radius_from_slow_motion_or_straight_noise) {
  auto g1 = gnss_of(synth::track_fn(40, 8, v_const1, w_tight_slow, 0.05));
  CHECK(analyse_curves(g1).curves.empty());                 // 1 m/s: below the minimum speed
  int spurious = 0;
  for (unsigned seed = 1; seed <= 10; seed++) spurious += (int)analyse_curves(gnss_of(synth::track_fn(60, 8, v_const4, w_zero, 0.15, 0.1, seed))).curves.size();
  CHECK(spurious == 0);
}

EQ_TEST(curves, circle_fit_recovers_centre_and_radius) {
  std::vector<double> x, y;
  for (int k = 0; k < 40; k++) { double a = k * 0.05; x.push_back(10 + 25 * std::cos(a)); y.push_back(-4 + 25 * std::sin(a)); }
  double cx, cy, r, rms;
  CHECK(fit_circle(x, y, &cx, &cy, &r, &rms));
  CHECK_NEAR(cx, 10, 1e-6); CHECK_NEAR(cy, -4, 1e-6); CHECK_NEAR(r, 25, 1e-6);
  std::vector<double> lx{0, 1, 2, 3, 4, 5}, ly{0, 0, 0, 0, 0, 0};
  CHECK(!fit_circle(lx, ly, &cx, &cy, &r, &rms));           // collinear: no circle
}
