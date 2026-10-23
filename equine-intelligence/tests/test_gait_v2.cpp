// GAIT_CLASSIFIER_V2 vs the reference GAIT_CLASSIFIER_V1 on the same labelled SYNTHETIC sessions.
// The numbers printed here say nothing about real horses; the test only checks behaviour and that both
// classifiers can be evaluated with the same data and the same metric. No superiority is asserted.
#include "eq_test.h"
#include "avo_eq/engine.h"
#include "synth.h"

using namespace avoeq;

// schedule: 0-20 stop, 20-50 walk, 50-80 trot, 80-110 canter, 110-130 walk
static int phase(double t) { return t < 20 ? 0 : t < 50 ? 1 : t < 80 ? 2 : t < 110 ? 3 : 1; }
static double sf(double t) { const double f[4] = {1.0, 0.95, 1.45, 1.75}; return f[phase(t)]; }
static double sa1(double t) { const double a[4] = {0, 250, 250, 700}; return a[phase(t)]; }
static double sa2(double t) { const double a[4] = {0, 600, 650, 200}; return a[phase(t)]; }

static Session labelled(std::vector<GaitSegment>* truth, bool with_imu = true) {
  Session s;
  s.gnss = synth::track({{20, 0.0, 0}, {30, 1.5, 0}, {30, 3.5, 0}, {30, 6.5, 0}, {20, 1.5, 0}}, 8, nullptr, nullptr, 0.05);
  // girth clock aligned with GNSS time apart from the clock model of synth (offset, drift, latency)
  synth::ImuSpec sp; sp.offset_s = -3.2;
  if (with_imu) s.imu = synth::imu_shape(130, sf, sa1, sa2, sp, 0, 5, 30);
  *truth = {{Gait::STOPPED, 0, 20}, {Gait::WALK, 20, 50}, {Gait::TROT, 50, 80}, {Gait::CANTER_GALLOP, 80, 110}, {Gait::WALK, 110, 130}};
  return s;
}

EQ_TEST(gait_v2, v1_and_v2_evaluated_on_the_same_data) {
  std::vector<GaitSegment> truth;
  Session s = labelled(&truth);
  auto a = analyse(s);
  const CadenceResult* cad = a.cadence.empty() ? nullptr : &a.cadence[0];
  auto v1 = classify_gait(a.gnss, cad, &a.girth_to_gnss[0]);
  auto v2 = classify_gait_v2(a.gnss, cad, &a.girth_to_gnss[0]);
  auto e1 = evaluate_gait(v1.segments, truth), e2 = evaluate_gait(v2.segments, truth);
  REPORT("V1 acuerdo %.3f, V2 acuerdo %.3f sobre %.0f s (sintético; no es exactitud real)\n", e1.accuracy(), e2.accuracy(), e2.evaluated_s);
  for (auto& g : v2.segments) REPORT("  V2 %s %.1f-%.1f conf %.2f %s (%s)\n", gait_name(g.gait), g.t0, g.t1, g.confidence, quality_name(g.quality), g.basis.c_str());
  CHECK(e1.evaluated_s == e2.evaluated_s);
  CHECK(e1.evaluated_s > 90);
  CHECK(e2.accuracy() > 0.8);          // behaviour check on clean synthetic data only
  CHECK(e1.accuracy() > 0.8);
  CHECK(v2.classifier == std::string(GAIT_V2_ID) && v1.classifier == std::string(GAIT_V1_ID));
}

EQ_TEST(gait_v2, conflicting_evidence_becomes_unknown_not_forced) {
  // GNSS says trot speed (3.5 m/s) for the whole session but the girth shows a clear canter signal
  Session s;
  s.gnss = synth::track({{60, 3.5, 0}}, 8, nullptr);
  synth::ImuSpec sp;
  static auto f = [](double) { return 2.4; }; static auto a1 = [](double) { return 700.0; }; static auto a2 = [](double) { return 150.0; };
  s.imu = synth::imu_shape(60, f, a1, a2, sp, 0, 3, 30);
  auto a = analyse(s);
  auto v2 = classify_gait_v2(a.gnss, &a.cadence[0], &a.girth_to_gnss[0]);
  double trot = 0, unknown = 0;
  for (auto& g : v2.segments) { if (g.gait == Gait::TROT) trot += g.t1 - g.t0; if (g.gait == Gait::UNKNOWN) unknown += g.t1 - g.t0; }
  REPORT("evidencias contradictorias: TROTE %.0f s, DESCONOCIDO %.0f s\n", trot, unknown);
  CHECK(unknown > trot);
}

EQ_TEST(gait_v2, gnss_gap_without_imu_is_insufficient_data) {
  Session s;
  s.gnss = synth::track({{30, 1.5, 0}, {20, 1.5, 0}, {30, 1.5, 0}}, 8, nullptr);
  for (size_t i = 240; i < 400; i++) s.gnss[i].flags = 0;          // 20 s without fix
  for (size_t i = 240; i < 400; i++) s.gnss[i].fix_type = 0;
  auto a = analyse(s);
  auto v2 = classify_gait_v2(a.gnss, nullptr, nullptr);
  double ins = 0; for (auto& g : v2.segments) if (g.gait == Gait::INSUFFICIENT_DATA) ins += g.t1 - g.t0;
  REPORT("hueco GNSS de 20 s sin IMU: %.0f s como DATOS_INSUFICIENTES\n", ins);
  CHECK(ins > 15);
}

EQ_TEST(gait_v2, trained_model_hook_loads_avo_ml_format) {
  const char* model = R"({"tipo":"centroide_mas_cercano","rasgos":["v_gnss","f_ciclo","fuerza","cv_intervalos","corr_ciclos"],
    "media":[3.0,1.4,0.8,0.05,0.9],"desv":[2.0,0.4,0.1,0.02,0.05],
    "centroides":{"PARADO":[-1.45,0,0,0,0],"PASO":[-0.75,-1.1,0,0,0],"TROTE":[0.2,0.1,0,0,0],"GALOPE":[1.75,1.0,0,0,0]},
    "entrenado_con":{"ventanas":10,"caballos":["X"],"fecha":"2026-10-24T00:00:00Z"}})";
  std::string err;
  auto m = load_centroid_model(model, &err);
  CHECK(m != nullptr);
  if (!m) { REPORT("%s\n", err.c_str()); return; }
  GaitFeatures f; f.speed = 3.4; f.f0 = 1.45;
  double sc[4]; CHECK(m->scores(f, sc));
  CHECK(sc[2] > sc[1] && sc[2] > sc[3] && sc[2] > sc[0]);
  CHECK(load_centroid_model("{\"tipo\":\"otro\"}", &err) == nullptr);
  CHECK(load_centroid_model("no es json", &err) == nullptr);
  std::vector<GaitSegment> truth;
  Session s = labelled(&truth);
  auto a = analyse(s);
  auto v2m = classify_gait_v2(a.gnss, &a.cadence[0], &a.girth_to_gnss[0], GaitV2Config(), m.get());
  CHECK(v2m.algorithm.find("modelo entrenado") == 0);
  CHECK(!v2m.segments.empty());
}
