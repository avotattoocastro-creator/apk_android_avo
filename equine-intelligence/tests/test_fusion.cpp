// Sensor Fusion Engine: temporal association, uncertainty propagation, relations, and strict causality of
// the real-time mode (results must not change when later data is removed). Simulation only.
#include "eq_test.h"
#include "avo_eq/engine.h"
#include "avo_eq/fusion.h"
#include "avo_eq/session_sync.h"
#include "synth.h"

using namespace avoeq;

static int ph(double t) { return t < 40 ? 0 : 1; }
static double ff(double t) { return ph(t) ? 1.45 : 0.95; }
static double fa1(double) { return 250; }
static double fa2(double) { return 600; }

static Session walk_trot(double secs = 80) {
  Session s;
  s.gnss = synth::track({{43.2, 1.5, 0}, {secs - 43.2, 3.5, 0}}, 8, nullptr, nullptr, 0.05);
  synth::ImuSpec sp;
  s.imu = synth::imu_shape(secs - 3.2, ff, fa1, fa2, sp, 0, 4, 30);
  return s;
}

EQ_TEST(fusion, offline_associates_speed_and_cadence) {
  Session s = walk_trot();
  auto a = analyse(s);
  auto fr = fuse_offline(a.gnss, a.cadence, a.girth_to_gnss, &a.gait);
  CHECK(fr.windows_total > 20);
  CHECK(fr.windows_ok * 10 >= fr.windows_total * 7);
  double worst_L = 0; int n = 0;
  for (auto& w : fr.windows) if (w.status == "OK" && w.t_gnss > 8 && w.t_gnss < 36) {
    n++;   // walk: speed 1.5, cadence 0.95 -> stride 1.579 m
    worst_L = std::max(worst_L, std::fabs(w.stride_length_m - 1.5 / 0.95));
    CHECK(w.stride_length_sigma > 0 && w.stride_length_sigma < 0.2);
    CHECK(w.gnss_i1 >= w.gnss_i0);
  }
  REPORT("longitud de tranco al paso: error máx %.3f m en %d ventanas\n", worst_L, n);
  CHECK(n > 5); CHECK(worst_L < 0.06);
  bool rel = false;
  for (auto& r : fr.relations) if (r.gait == "TODOS" && r.y == "cadencia_hz" && r.n >= 8) { rel = true; CHECK(r.slope > 0); REPORT("cadencia = %.3f + %.3f·v (r %.2f, n %u)\n", r.intercept, r.slope, r.r, r.n); }
  CHECK(rel);
}

EQ_TEST(fusion, timing_uncertainty_enters_the_speed_uncertainty) {
  Session s = walk_trot();
  auto a = analyse(s);
  ClockMap m[3] = {a.girth_to_gnss[0], a.girth_to_gnss[1], a.girth_to_gnss[2]};
  for (auto& p : m[0].pieces) p.envelope_sd_s = 0.5;                  // pretend a very poor synchronisation
  auto bad = fuse_offline(a.gnss, a.cadence, m, &a.gait);
  auto good = fuse_offline(a.gnss, a.cadence, a.girth_to_gnss, &a.gait);
  CHECK(bad.windows_ok == 0);                                          // every window flagged SIN_SINCRONIA
  CHECK(bad.no_sync == bad.windows_total);
  CHECK(good.windows_ok > 0);
}

EQ_TEST(fusion, gnss_without_imu_and_imu_without_gnss) {
  Session g; g.gnss = synth::track({{30, 2.0, 0}}, 8, nullptr);
  auto a = analyse(g);
  auto f1 = fuse_offline(a.gnss, a.cadence, a.girth_to_gnss, &a.gait);
  CHECK(f1.windows_total == 0);
  bool warn = false; for (auto& w : f1.warnings) warn |= w.find("SIN DATOS DE CINCHA") != std::string::npos;
  CHECK(warn);
  Session i; synth::ImuSpec sp; i.imu = synth::imu_shape(30, ff, fa1, fa2, sp);
  auto b = analyse(i);
  auto f2 = fuse_offline(b.gnss, b.cadence, b.girth_to_gnss, &b.gait);
  CHECK(f2.windows_ok == 0);
  for (auto& w : f2.windows) CHECK(w.status == "SIN_SINCRONIA");   // without GNSS there is no common time base
}

EQ_TEST(fusion, realtime_is_causal_truncation_invariant) {
  Session s = walk_trot(70);
  auto v = validate(s);
  auto imu = build_imu_series(s, v);
  auto full = fuse_realtime(s, v, imu, CadenceConfig(), SyncConfig());
  double cut = 1000.0 + 45.0;                       // chest clock: everything received after GNSS t = 45 s is removed
  Session t = s;
  t.gnss.erase(std::remove_if(t.gnss.begin(), t.gnss.end(), [&](const GnssEpoch& e) { return e.chest_us * 1e-6 > cut; }), t.gnss.end());
  t.imu.erase(std::remove_if(t.imu.begin(), t.imu.end(), [&](const ImuSample& m) { return m.chest_us * 1e-6 > cut; }), t.imu.end());
  auto vt = validate(t);
  auto it = build_imu_series(t, vt);
  auto part = fuse_realtime(t, vt, it, CadenceConfig(), SyncConfig());
  int compared = 0, differ = 0;
  for (auto& w : full.windows) {
    if (w.t_available > cut) continue;
    const FusedWindow* m = nullptr;
    for (auto& x : part.windows) if (x.imu_id == w.imu_id && std::fabs(x.t_imu - w.t_imu) < 1e-9) m = &x;
    compared++;
    if (!m) { differ++; continue; }
    auto same = [](double a, double b) { return (std::isnan(a) && std::isnan(b)) || a == b; };
    if (!same(m->t_gnss, w.t_gnss) || !same(m->speed, w.speed) || !same(m->accel, w.accel) || !same(m->cadence_hz, w.cadence_hz) || m->status != w.status) differ++;
  }
  REPORT("tiempo real: %d ventanas disponibles antes del corte, %d distintas tras quitar los datos posteriores\n", compared, differ);
  CHECK(compared > 10);
  CHECK(differ == 0);
  CHECK(std::string(mode_name(full.mode)) == "REALTIME_ANALYSIS");
  // and the offline analysis of the same data does use the whole session (two-sided), as documented
  CHECK(full.windows_ok > 0);
}
