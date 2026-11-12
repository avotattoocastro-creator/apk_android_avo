#include "eq_test.h"
#include "avo_eq/sync.h"
#include <random>

using namespace avoeq;

// x = source acquisition time, y = target reception time = offset + (1+drift) x + latency
static void gen(std::vector<double>& x, std::vector<double>& y, double off, double drift_ppm, double lat_mean, double loss,
                double t0, double t1, double step, unsigned seed) {
  std::mt19937 rng(seed); std::exponential_distribution<double> lat(1.0 / lat_mean); std::uniform_real_distribution<double> u(0, 1);
  for (double t = t0; t < t1; t += step) {
    if (u(rng) < loss) continue;
    x.push_back(t); y.push_back(off + (1 + drift_ppm * 1e-6) * t + 0.003 + lat(rng));
  }
}

EQ_TEST(sync, offset_drift_variable_latency_and_loss) {
  std::vector<double> x, y;
  gen(x, y, 3.2, 50, 0.015, 0.10, 0, 600, 0.1, 11);
  auto m = fit_clock(x, y);
  CHECK(m.pieces.size() == 1);
  // truth line has the 3 ms minimum latency built in: the envelope must find offset + 3 ms
  double worst = 0;
  for (double t = 5; t < 595; t += 7.3) {
    double est; CHECK(m.map(t, &est));
    worst = std::max(worst, std::fabs(est - (3.2 + 0.003 + (1 + 50e-6) * t)));
  }
  REPORT("error máximo del mapa de reloj: %.3f ms, deriva estimada %.1f ppm (real 50), incertidumbre %.3f ms, latencia mediana %.1f ms\n",
         worst * 1e3, m.pieces[0].drift_ppm, m.pieces[0].envelope_sd_s * 1e3, m.pieces[0].latency_median_s * 1e3);
  CHECK(worst < 0.002);                      // < 2 ms with 15 ms mean exponential latency
  CHECK_NEAR(m.pieces[0].drift_ppm, 50, 5);
}

EQ_TEST(sync, source_clock_restart_creates_a_new_piece) {
  std::vector<double> x, y;
  gen(x, y, 3.2, 50, 0.010, 0.0, 0, 300, 0.1, 12);
  // girth reboots: its clock restarts at 0 while the target keeps running (+300 s)
  std::vector<double> x2, y2;
  gen(x2, y2, 3.2 + 310, -20, 0.010, 0.0, 0, 200, 0.1, 13);
  x.insert(x.end(), x2.begin(), x2.end()); y.insert(y.end(), y2.begin(), y2.end());
  auto m = fit_clock(x, y);
  CHECK(m.pieces.size() == 2);
  CHECK(m.resets() == 1);
  CHECK_NEAR(m.pieces[1].drift_ppm, -20, 5);
}

EQ_TEST(sync, reordered_arrivals_do_not_break_the_fit) {
  std::vector<double> x, y;
  gen(x, y, 1.0, 0, 0.02, 0, 0, 120, 0.05, 14);
  std::mt19937 rng(1);
  for (size_t i = 0; i + 1 < x.size(); i += 2) if (rng() % 3 == 0) { std::swap(x[i], x[i + 1]); std::swap(y[i], y[i + 1]); }
  auto m = fit_clock(x, y);
  CHECK(m.pieces.size() == 1);
  double est; m.map(60, &est);
  CHECK_NEAR(est, 1.0 + 0.003 + 60, 0.002);
}

EQ_TEST(sync, too_few_pairs_gives_no_map) {
  auto m = fit_clock({1, 2, 3}, {4, 5, 6});
  CHECK(m.pieces.empty());
  double y; CHECK(!m.map(2, &y));
}
