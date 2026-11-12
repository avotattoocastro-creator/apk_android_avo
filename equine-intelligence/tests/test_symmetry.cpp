// EXPLORATORY_MOTION_SYMMETRY with known synthetic beat patterns (simulation, no physical validation).
#include "eq_test.h"
#include "avo_eq/engine.h"
#include "avo_eq/symmetry.h"
#include "synth.h"

using namespace avoeq;

static SymmetryResult run(const std::vector<std::pair<uint8_t, synth::Beats>>& sensors, double secs = 60, bool poor_sync = false) {
  Session s;
  s.gnss = synth::track({{secs + 4, 3.5, 0}}, 8, nullptr);
  synth::ImuSpec sp;
  for (auto& x : sensors) { auto v = synth::imu_beats(secs, x.second, sp, x.first, 9 + x.first); s.imu.insert(s.imu.end(), v.begin(), v.end()); }
  auto a = analyse(s);
  ClockMap m[3] = {a.girth_to_gnss[0], a.girth_to_gnss[1], a.girth_to_gnss[2]};
  if (poor_sync) for (auto& mm : m) for (auto& p : mm.pieces) p.envelope_sd_s = 0.05;
  return analyse_symmetry(a.imu, a.cadence, m, &a.gait);
}

static const SymmetryGroup* all(const SymmetryResult& r, uint8_t id) {
  for (auto& g : r.groups) if (g.imu_id == id && g.gait == "TODOS") return &g;
  return nullptr;
}

EQ_TEST(symmetry, known_amplitude_and_timing_difference) {
  synth::Beats b; b.A = 1000; b.B = 700; b.frac = 0.45;
  auto r = run({{0, b}});
  auto* g = all(r, 0);
  CHECK(g != nullptr);
  if (!g) return;
  REPORT("ln(A1/A2) %.3f (verdad %.3f), asimetría temporal %.3f (verdad %.3f), similitud mitades %.2f, %u ventanas\n",
         g->amp_log_ratio.median, std::log(1000.0 / 700.0), g->timing_asym.median, 2 * 0.45 - 1, g->half_similarity.median, g->windows);
  CHECK_NEAR(g->amp_log_ratio.median, std::log(1000.0 / 700.0), 0.08);
  CHECK_NEAR(g->timing_asym.median, -0.10, 0.02);
  CHECK(g->amp_log_ratio.reproducible && g->timing_asym.reproducible);
  CHECK(r.label == "EXPLORATORY_MOTION_SYMMETRY");
  CHECK(r.conclusions_allowed);
}

EQ_TEST(symmetry, equal_beats_show_no_reproducible_difference) {
  synth::Beats b; b.A = 1000; b.B = 1000; b.frac = 0.5;
  b.A = 1000; b.B = 960;    // a small marker difference so the stride is identifiable at all
  auto r = run({{0, b}});
  auto* g = all(r, 0);
  // identical beats make the stride itself unidentifiable: either no conclusion or no reproducible difference
  if (!g || g->windows < 5) { CHECK(!r.conclusions_allowed || !g); REPORT("latidos casi iguales: sin conclusión (zancada no identificable)\n"); }
  if (g && g->windows >= 5) { CHECK(std::fabs(g->timing_asym.median) < 0.02); CHECK(!g->timing_asym.reproducible); REPORT("asimetría temporal %.4f (no reproducible)\n", g->timing_asym.median); }
}

EQ_TEST(symmetry, saturation_and_irregular_movement_block_conclusions) {
  synth::Beats sat; sat.A = 40000; sat.B = 30000;            // beyond the int16 range: saturated
  auto r1 = run({{0, sat}});
  CHECK(r1.excluded_saturated > 0);
  CHECK(!r1.conclusions_allowed);
  bool blocked = false; for (auto& c : r1.controls) blocked |= c.control == "SATURACION" && c.state == "BLOQUEA";
  CHECK(blocked);
  synth::Beats irr; irr.jitter = 0.25;                        // strongly irregular strides
  auto r2 = run({{0, irr}});
  CHECK(!r2.conclusions_allowed);
  REPORT("irregular: %u ventanas excluidas por irregularidad, %u por estado\n", r2.excluded_irregular, r2.excluded_status);
}

EQ_TEST(symmetry, inter_sensor_timing_and_blocking) {
  synth::Beats l; l.A = 1000; l.B = 800; synth::Beats rr = l; rr.delay_s = 0.020;
  auto r = run({{1, l}, {2, rr}});
  const InterSensor* is = nullptr;
  for (auto& x : r.inter) if (x.gait == "TODOS") is = &x;
  CHECK(is && is->state == "OK");
  if (is) {
    REPORT("retardo entre sensores %.4f s (verdad 0.020), %u pares\n", is->lag_s.median, is->lag_s.n);
    CHECK_NEAR(is->lag_s.median, 0.020, 0.006);
    CHECK(std::isnan(is->rms_ratio.median));                 // uncalibrated: amplitudes between sensors blocked
    CHECK(is->reason.find("sin calibración") != std::string::npos);
  }
  auto bad = run({{1, l}, {2, rr}}, 60, true);
  bool blocked = false; for (auto& x : bad.inter) blocked |= x.state == "BLOQUEA";
  CHECK(blocked);
}

EQ_TEST(symmetry, no_clinical_vocabulary_and_no_imu) {
  Session s; s.gnss = synth::track({{30, 3.0, 0}}, 8, nullptr);
  auto a = analyse(s);
  auto r = analyse_symmetry(a.imu, a.cadence, a.girth_to_gnss, &a.gait);
  CHECK(!r.conclusions_allowed);
  bool sin = false; for (auto& c : r.controls) sin |= c.reason.find("SIN DATOS DE CINCHA") != std::string::npos;
  CHECK(sin);
  synth::Beats b; b.A = 1000; b.B = 700;
  auto r2 = run({{0, b}});
  std::string all_text;
  for (auto& c : r2.controls) all_text += c.reason + " ";
  for (auto& n : r2.notes) all_text += n + " ";
  for (const char* w : {"cojera", "lameness", "clínic", "diagnóst", "lesión", "patolog"}) CHECK(all_text.find(w) == std::string::npos);
}
