#include "eq_test.h"
#include "avo_eq/engine.h"
#include "synth.h"
#include <set>

using namespace avoeq;

static double f_walk(double) { return 0.95; }
static double f_trot_after_30(double t) { return t < 30 ? 0.95 : 1.45; }

static avoeq::Session session_with_imu(double secs, double (*f)(double), const synth::ImuSpec& sp, std::vector<synth::Leg> legs) {
  avoeq::Session s;
  s.gnss = synth::track(legs, 8, nullptr);
  s.imu = synth::imu(secs, f, sp);
  return s;
}

EQ_TEST(motion, cadence_of_a_known_stride_frequency) {
  synth::ImuSpec sp;
  auto s = session_with_imu(60, f_walk, sp, {{60, 1.5, 0}});
  auto a = analyse(s);
  CHECK(a.cadence.size() == 1);
  double cpm = -1;
  for (auto& m : a.cadence[0].metrics) if (m.name == "cadencia_media") cpm = m.value;
  CHECK_NEAR(cpm, 0.95 * 60, 1.0);           // 57 cycles/min ± 1 (stride, not the 2x beat)
  // a perfectly regular synthetic stride: cycles correlate strongly
  for (auto& m : a.cadence[0].metrics) if (m.name == "correlacion_entre_ciclos") CHECK(m.value > 0.9);
}

EQ_TEST(motion, imu_clock_mapped_to_gnss_with_offset_drift_latency) {
  synth::ImuSpec sp; sp.loss = 0.05;
  auto s = session_with_imu(120, f_walk, sp, {{120, 1.5, 0}});
  auto a = analyse(s);
  CHECK(!a.girth_to_gnss[0].pieces.empty());
  // truth: girth = (t - 3.2)(1 + 50e-6)  ->  t = girth / (1 + 50e-6) + 3.2
  double worst = 0;
  for (double g = 0; g < 110; g += 3.7) {
    double t; if (!a.girth_to_gnss[0].map(g, &t)) continue;
    // the composed map includes the 3 ms minimum radio latency and the 8 ms GNSS latency in the model
    worst = std::max(worst, std::fabs(t - (g / (1 + 50e-6) + 3.2)));
  }
  REPORT("error del mapa cincha->GNSS: %.2f ms (sin PPS, latencias simuladas)\n", worst * 1e3);
  CHECK(worst < 0.015);
}

EQ_TEST(motion, missing_samples_and_saturation_are_counted) {
  synth::ImuSpec sp; sp.loss = 0.1;
  auto s = session_with_imu(30, f_walk, sp, {{30, 1.5, 0}});
  s.imu[100].az = 32767;
  auto a = analyse(s);
  CHECK(a.validation.imu_saturated >= 1);
  CHECK(a.validation.imu_missing[0] > 0);
  CHECK(a.imu[0].pieces.size() > 1);           // gaps split the series: nothing is interpolated
}

EQ_TEST(gait, speed_and_frequency_segments_with_hysteresis) {
  synth::ImuSpec sp;
  // walk 1.5 m/s with 0.95 Hz, then trot 3.5 m/s with 1.45 Hz
  auto s = session_with_imu(70, f_trot_after_30, sp, {{33.2, 1.5, 0}, {40, 3.5, 0}});
  auto a = analyse(s);
  std::vector<Gait> seq;
  for (auto& g : a.gait.segments) if (g.gait != Gait::TRANSITION && g.gait != Gait::UNKNOWN) seq.push_back(g.gait);
  CHECK(seq.size() == 2 && seq[0] == Gait::WALK && seq[1] == Gait::TROT);
  // speed and frequency agree: classified with GOOD quality
  bool good = false; for (auto& g : a.gait.segments) if (g.gait == Gait::TROT && g.quality == Quality::GOOD) good = true;
  CHECK(good);
  for (auto& g : a.gait.segments) REPORT("%s %.1f-%.1f s %s (%s)\n", gait_name(g.gait), g.t0, g.t1, quality_name(g.quality), g.basis.c_str());
}

EQ_TEST(gait, gnss_only_session_still_classifies) {
  avoeq::Session s;
  s.gnss = synth::track({{20, 0.0, 0}, {30, 1.6, 0}, {30, 3.4, 0}, {30, 7.0, 0}}, 8, nullptr);
  auto a = analyse(s);
  std::vector<Gait> seq;
  for (auto& g : a.gait.segments) if (g.gait != Gait::TRANSITION) seq.push_back(g.gait);
  CHECK(seq.size() == 4);
  if (seq.size() == 4) CHECK(seq[0] == Gait::STOPPED && seq[1] == Gait::WALK && seq[2] == Gait::TROT && seq[3] == Gait::CANTER_GALLOP);
}

EQ_TEST(engine, deterministic_output_and_quality_reasons) {
  synth::ImuSpec sp;
  auto s = session_with_imu(40, f_walk, sp, {{40, 1.5, 0}});
  EngineConfig c;
  auto a1 = analyse(s, c, "2026-10-23T00:00:00Z"), a2 = analyse(s, c, "2026-10-23T00:00:00Z");
  CHECK(to_json(a1, s, c) == to_json(a2, s, c));
  std::set<std::string> domains;
  for (auto& q : a1.quality) { domains.insert(q.domain); CHECK(!q.reasons.empty()); }
  CHECK(domains.count("GNSS") && domains.count("IMU") && domains.count("TIEMPO") && domains.count("CALIBRACION"));
}
