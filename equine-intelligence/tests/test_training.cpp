// AVO Training Analytics: fechas, resumen de sesión, carga, ACWR, monotonía, líneas base, desvíos, tendencias y API C.
#include <cstdlib>
#include <cstring>
#include <string>
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/json.h"
#include "avo_eq/training.h"
#include "eq_test.h"

using namespace avoeq;

namespace {

// Session with fixed minutes per gait and per-gait metrics.
SessionSummary make(const std::string& id, long day, double walk_min, double trot_min, double canter_min,
                    double trot_stride = 2.4, double trot_corr = 0.90, double canter_speed = 9.0) {
  SessionSummary s;
  s.id = id; s.horse = "LUNA"; s.date_utc = training_day_text(day);
  s.gait[0].duration_s = walk_min * 60; s.gait[1].duration_s = trot_min * 60; s.gait[2].duration_s = canter_min * 60;
  s.moving_s = (walk_min + trot_min + canter_min) * 60;
  s.gait[0].speed_mean = 1.6; s.gait[0].stride_length_m = 1.6; s.gait[0].cadence_hz = 0.95; s.gait[0].cycle_corr = 0.88; s.gait[0].interval_cv = 0.05;
  s.gait[1].speed_mean = 3.6; s.gait[1].stride_length_m = trot_stride; s.gait[1].cadence_hz = 1.45; s.gait[1].cycle_corr = trot_corr; s.gait[1].interval_cv = 0.04;
  if (canter_min > 0) { s.gait[2].speed_mean = canter_speed; s.gait[2].stride_length_m = 4.5; s.gait[2].cadence_hz = 1.9; s.gait[2].cycle_corr = 0.85; s.gait[2].interval_cv = 0.05; }
  s.has_imu = true;
  return s;
}
const long D0 = 20500;   // 2026-02-16

const SessionResult* find(const TrainingResult& r, const std::string& id) {
  for (auto& s : r.sessions) if (s.s.id == id) return &s;
  return nullptr;
}
const Deviation* dev(const SessionResult* s, const std::string& m) {
  if (!s) return nullptr;
  for (auto& d : s->deviations) if (d.metric == m) return &d;
  return nullptr;
}
const Trend* trend(const TrainingResult& r, const std::string& m) {
  for (auto& t : r.trends) if (t.metric == m) return &t;
  return nullptr;
}
bool contains(const std::vector<std::string>& v, const char* needle) {
  for (auto& s : v) if (s.find(needle) != std::string::npos) return true;
  return false;
}

}  // namespace

EQ_TEST(entreno, dates) {
  long d = 0;
  CHECK(training_parse_day("1970-01-01", &d) && d == 0);
  CHECK(training_parse_day("2026-11-01T14:48:00Z", &d) && training_day_text(d) == "2026-11-01");
  CHECK(training_parse_day("2024-02-29", &d));
  CHECK(!training_parse_day("2026-02-29", &d));
  CHECK(!training_parse_day("2026-13-01", &d));
  CHECK(!training_parse_day("ayer", &d));
  long a, b;
  training_parse_day("2026-03-01", &a); training_parse_day("2026-02-28", &b);
  CHECK(a - b == 1);
}

EQ_TEST(entreno, summary_from_analysis) {
  // Two trot segments (stride 2.3 for 100 s, 2.5 for 300 s: weighted median 2.5), one unusable, a short canter.
  const char* js = R"({"formato":"avo-equine-analysis","version_formato":2,
    "sesion":{"id":"S1","caballo":"LUNA","jinete":"ANA","inicio_utc":"2026-10-30T08:00:00Z"},
    "procedencia":{"tiene_cincha":true},
    "rendimiento":{"segmentos":[
      {"codigo":"TROT","duracion_s":100,"distancia_m":350,"velocidad_media":3.5,"velocidad_max":4.0,"longitud_tranco_m":2.3,"cadencia_media_hz":1.5,
       "correlacion_ciclos":0.9,"cv_intervalos":0.04,"calidad_gnss":"BUENA","calidad_imu":"BUENA"},
      {"codigo":"TROT","duracion_s":300,"distancia_m":1110,"velocidad_media":3.7,"velocidad_max":4.2,"longitud_tranco_m":2.5,"cadencia_media_hz":1.48,
       "correlacion_ciclos":0.8,"cv_intervalos":0.05,"calidad_gnss":"BUENA","calidad_imu":"BUENA"},
      {"codigo":"TROT","duracion_s":50,"distancia_m":null,"velocidad_media":9.9,"velocidad_max":20,"longitud_tranco_m":9,"cadencia_media_hz":9,
       "correlacion_ciclos":0.1,"cv_intervalos":0.9,"calidad_gnss":"NO_UTILIZABLE","calidad_imu":"NO_UTILIZABLE"},
      {"codigo":"CANTER_GALLOP","duracion_s":30,"distancia_m":330,"velocidad_media":11.5,"velocidad_max":12.5,"longitud_tranco_m":5,"cadencia_media_hz":2,
       "correlacion_ciclos":0.8,"cv_intervalos":0.05,"calidad_gnss":"BUENA","calidad_imu":"BUENA"},
      {"codigo":"TRANSITION","duracion_s":10},
      {"codigo":"STOPPED","duracion_s":100}],
     "sesion":{"distancia_m":1790}},
    "cinematica":{"eventos":[{"tipo":"ACELERACION_SOSTENIDA","pico_m_s2":1.8,"calidad":"BUENA"},
      {"tipo":"DESACELERACION_SOSTENIDA","pico_m_s2":-2.2,"calidad":"UTILIZABLE"},
      {"tipo":"PICO_ACELERACION","pico_m_s2":7,"calidad":"BAJA"}]},
    "calidad":[{"dominio":"GNSS","nivel":"BUENA"},{"dominio":"IMU","nivel":"UTILIZABLE"}]})";
  json::Value v; std::string err;
  CHECK(json::parse(js, &v, &err));
  TrainingConfig c;
  SessionSummary s;
  CHECK(training_summary_from_analysis(v, c, &s, &err));
  CHECK(s.id == "S1" && s.horse == "LUNA" && s.rider == "ANA" && s.date_utc == "2026-10-30T08:00:00Z");
  CHECK_NEAR(s.gait[1].duration_s, 450, 1e-9);
  CHECK_NEAR(s.gait[1].speed_mean, (3.5 * 100 + 3.7 * 300) / 400.0, 1e-9);   // unusable GNSS excluded
  CHECK_NEAR(s.gait[1].speed_max, 4.2, 1e-9);
  CHECK_NEAR(s.gait[1].stride_length_m, 2.5, 1e-9);
  CHECK_NEAR(s.gait[1].cycle_corr, 0.8, 1e-9);
  CHECK(std::isnan(s.gait[2].stride_length_m));            // 30 s of canter: too short to judge
  CHECK_NEAR(s.gait[2].speed_max, 12.5, 1e-9);             // …but its maximum speed counts
  CHECK_NEAR(s.high_speed_m, 330, 1e-9);                   // canter segment above 11 m/s
  CHECK_NEAR(s.moving_s, 100 + 300 + 50 + 30 + 10, 1e-9);
  CHECK_NEAR(s.distance_m, 1790, 1e-9);
  CHECK(s.accel_events == 1 && s.decel_events == 1);
  CHECK_NEAR(s.accel_peak, 1.8, 1e-9);                     // the BAJA peak is ignored
  CHECK_NEAR(s.decel_peak, 2.2, 1e-9);
  CHECK(s.gnss_quality == "BUENA" && s.imu_quality == "UTILIZABLE");

  // Round trip through the stored summary.
  SessionSummary t;
  json::Value sv;
  CHECK(json::parse(training_summary_to_json(s), &sv, &err));
  CHECK(training_summary_from_json(sv, &t, &err));
  CHECK(training_summary_to_json(t) == training_summary_to_json(s));

  json::Value bad; json::parse("{\"formato\":\"otra\"}", &bad);
  CHECK(!training_summary_from_analysis(bad, c, &s, &err));
}

EQ_TEST(entreno, high_speed_from_series) {
  const char* js = R"({"formato":"avo-equine-analysis","sesion":{"id":"S"},"rendimiento":{"segmentos":[]},
    "series":{"t":[0,1,2,3,4],"velocidad":[10,12,12,12,10]}})";
  json::Value v; json::parse(js, &v);
  SessionSummary s; TrainingConfig c; std::string err;
  CHECK(training_summary_from_analysis(v, c, &s, &err));
  // intervals with mean speed > 11: [1,2], [2,3] at 12 m/s → 24 m; [0,1] and [3,4] are 11 m/s (not above).
  CHECK_NEAR(s.high_speed_m, 24, 1e-9);
}

EQ_TEST(entreno, steady_load_is_normal) {
  TrainingConfig c;
  std::vector<SessionSummary> v;
  for (int w = 0; w < 6; w++)
    for (int d : {0, 1, 3, 4, 5}) v.push_back(make("S" + std::to_string(w * 7 + d), D0 + w * 7 + d, 15, 20, 5));
  TrainingResult r = analyse_training(v, "", c);
  CHECK(r.sessions.size() == 30);
  // 15·1 + 20·3 + 5·6 = 105 per session
  CHECK_NEAR(r.sessions[0].load.external, 105, 1e-9);
  CHECK_NEAR(r.current.acwr, 1.0, 0.12);
  CHECK(r.level == "NORMAL");
  REPORT("ACWR %.3f monotonía %.3f\n", r.current.acwr, r.current.monotony);
  CHECK(!std::isnan(r.current.monotony) && r.current.monotony < c.monotony_high);
  CHECK(std::isnan(r.sessions[3].load.acwr));             // less than 28 days of history
  CHECK(r.days_since_last == 0);
  CHECK(r.daily_load.size() == (size_t)c.chronic_days);
}

EQ_TEST(entreno, load_spike_is_flagged) {
  TrainingConfig c;
  std::vector<SessionSummary> v;
  for (int w = 0; w < 5; w++)
    for (int d : {0, 2, 4}) v.push_back(make("S" + std::to_string(w * 7 + d), D0 + w * 7 + d, 15, 20, 5));
  // Week 6: every day, double canter and long trot.
  for (int d = 0; d < 7; d++) v.push_back(make("X" + std::to_string(d), D0 + 35 + d, 15, 40, 10));
  TrainingResult r = analyse_training(v, "", c);
  REPORT("ACWR %.3f\n", r.current.acwr);
  CHECK(r.current.acwr > c.acwr_high);
  CHECK(r.level == "VIGILAR");
  CHECK(contains(r.reasons, "subida brusca"));
}

EQ_TEST(entreno, deviation_of_stride_and_regularity) {
  TrainingConfig c;
  std::vector<SessionSummary> v;
  const double strides[] = {2.40, 2.42, 2.38, 2.41, 2.39, 2.40, 2.43, 2.37};
  for (int i = 0; i < 8; i++) v.push_back(make("N" + std::to_string(i), D0 + 2 * i, 15, 20, 5, strides[i], 0.90 + 0.005 * (i % 3)));
  v.push_back(make("BAJO", D0 + 16, 15, 20, 5, 2.10, 0.90));                  // much shorter trot stride
  v.push_back(make("MEJOR", D0 + 18, 15, 20, 5, 2.40, 0.99));                 // more regular: not a warning
  v.push_back(make("RAPIDO", D0 + 20, 15, 20, 5, 2.40, 0.90, 12.0));          // faster canter: informative only
  TrainingResult r = analyse_training(v, "", c);
  const SessionResult* low = find(r, "BAJO");
  const Deviation* d = dev(low, "TROTE.longitud_tranco_m");
  CHECK(d != nullptr);
  if (d) { REPORT("z tranco = %.2f\n", d->z); CHECK(d->level == "REVISAR" && d->direction == "MENOR" && d->n == 8); }
  CHECK(low && low->level == "REVISAR" && contains(low->reasons, "TROTE.longitud_tranco_m"));
  const SessionResult* better = find(r, "MEJOR");
  const Deviation* dc = dev(better, "TROTE.correlacion_ciclos");
  CHECK(dc && dc->z > c.z_watch);
  CHECK(better && better->level == "NORMAL");
  const SessionResult* fast = find(r, "RAPIDO");
  const Deviation* ds = dev(fast, "GALOPE.velocidad_media");
  CHECK(ds && ds->level != "NORMAL");
  CHECK(fast && fast->level == "NORMAL");
  // First sessions have no baseline.
  CHECK(dev(find(r, "N2"), "TROTE.longitud_tranco_m") == nullptr);
}

EQ_TEST(entreno, trainer_assessment_and_srpe) {
  TrainingConfig c;
  std::vector<SessionSummary> v;
  for (int i = 0; i < 5; i++) { v.push_back(make("S" + std::to_string(i), D0 + i, 10, 20, 0)); v.back().rpe = 5; }
  v.back().state = "cojera";
  TrainingResult r = analyse_training(v, "", c);
  CHECK(r.sessions.back().level == "REVISAR");
  CHECK(r.level == "REVISAR");
  CHECK_NEAR(r.sessions[0].load.srpe, 5 * 30, 1e-9);
  CHECK_NEAR(r.current.acute_srpe, 5 * 150, 1e-9);
}

EQ_TEST(entreno, trend_per_week) {
  TrainingConfig c;
  std::vector<SessionSummary> v;
  for (int w = 0; w < 8; w++)
    for (int d : {0, 3}) v.push_back(make("S" + std::to_string(w * 7 + d), D0 + w * 7 + d, 15, 20, 5, 2.4, 0.9, 9.0 + 0.1 * (w + d / 7.0)));
  TrainingResult r = analyse_training(v, "", c);
  const Trend* t = trend(r, "GALOPE.velocidad_media");
  CHECK(t != nullptr);
  if (t) { CHECK_NEAR(t->slope_per_week, 0.1, 1e-6); CHECK(t->direction == "SUBE"); }
  const Trend* s = trend(r, "TROTE.longitud_tranco_m");
  CHECK(s && s->direction == "ESTABLE");
}

EQ_TEST(entreno, dates_duplicates_and_reference) {
  TrainingConfig c;
  std::vector<SessionSummary> v;
  v.push_back(make("A", D0, 10, 10, 0));
  v.push_back(make("B", D0 + 2, 10, 10, 0));
  v.push_back(make("B", D0 + 3, 10, 10, 0));                 // same id: the last one wins
  SessionSummary nodate = make("C", D0, 10, 10, 0); nodate.date_utc = "";
  v.push_back(nodate);
  v.push_back(make("FUT", D0 + 30, 10, 10, 0));
  TrainingResult r = analyse_training(v, training_day_text(D0 + 20), c);
  CHECK(r.sessions.size() == 2);
  CHECK(r.sessions.back().s.day == D0 + 3);
  CHECK(r.days_since_last == 17);
  CHECK(contains(r.warnings, "sin fecha"));
  CHECK(contains(r.warnings, "posteriores"));
  CHECK(contains(r.reasons, "días sin sesiones"));
  TrainingResult e = analyse_training({}, "", c);
  CHECK(e.sessions.empty() && e.level == "NORMAL");
}

EQ_TEST(entreno, c_api) {
  std::string in = "{\"caballo\":\"LUNA\",\"sesiones\":[";
  for (int i = 0; i < 6; i++) {
    SessionSummary s = make("S" + std::to_string(i), D0 + i, 15, 20, 5);
    in += (i ? "," : "") + std::string("{\"resumen\":") + training_summary_to_json(s) + ",\"valoracion\":{\"rpe\":6}}";
  }
  in += ",{\"resumen\":" + training_summary_to_json([] { SessionSummary s = make("OTRO", D0 + 1, 1, 1, 1); s.horse = "RAYO"; return s; }()) + "}";
  in += ",{\"nada\":1}]}";
  char* out = nullptr;
  int rc = avo_eq_training_analyse(in.c_str(), "{\"factor_galope\":8}", nullptr, &out);
  CHECK(rc == 0 && out);
  json::Value v; std::string err;
  CHECK(out && json::parse(out, &v, &err));
  CHECK(v["formato"].str() == "avo-training-analysis");
  CHECK(v["sesiones_usadas"].num() == 6);
  CHECK_NEAR(v["sesiones"][0]["carga"]["externa"].num(), 15 + 60 + 40, 1e-9);
  CHECK_NEAR(v["sesiones"][0]["carga"]["srpe"].num(), 6 * 40, 1e-9);
  std::string warn;
  for (auto& w : v["avisos"].a) warn += w.str() + "|";
  CHECK(warn.find("otro caballo") != std::string::npos && warn.find("descartada") != std::string::npos);
  // Deterministic
  char* out2 = nullptr;
  avo_eq_training_analyse(in.c_str(), "{\"factor_galope\":8}", nullptr, &out2);
  CHECK(out && out2 && std::strcmp(out, out2) == 0);
  avo_eq_free(out); avo_eq_free(out2);

  CHECK(avo_eq_training_analyse(in.c_str(), "{\"dias_aguda\":40}", nullptr, &out) == 5); avo_eq_free(out);
  CHECK(avo_eq_training_analyse(in.c_str(), "{\"factor_trote\":-1}", nullptr, &out) == 5); avo_eq_free(out);
  CHECK(avo_eq_training_analyse("{no json", nullptr, nullptr, &out) == 2); avo_eq_free(out);
  CHECK(avo_eq_training_analyse("{}", nullptr, nullptr, &out) == 2); avo_eq_free(out);
  volatile int cancel = 1;
  CHECK(avo_eq_training_analyse(in.c_str(), nullptr, &cancel, &out) == 4); avo_eq_free(out);
  CHECK(avo_eq_training_analyse(in.c_str(), nullptr, nullptr, nullptr) == 2);

  const char* an = R"({"formato":"avo-equine-analysis","sesion":{"id":"Q","caballo":"LUNA","inicio_utc":null},"rendimiento":{"segmentos":[]}})";
  CHECK(avo_eq_training_summary(an, "{\"fecha_utc\":\"2026-10-31\",\"valoracion\":{\"rpe\":12,\"estado\":\"BIEN\"}}", &out) == 0);
  CHECK(out && json::parse(out, &v, &err));
  CHECK(v["fecha_utc"].str() == "2026-10-31" && v["valoracion"]["rpe"].is_null() && v["valoracion"]["estado"].str() == "BIEN");
  avo_eq_free(out);
  CHECK(avo_eq_training_summary("{\"formato\":\"x\"}", nullptr, &out) == 1); avo_eq_free(out);
}

EQ_TEST(entreno, racing_metrics_history) {
  TrainingConfig c;
  std::vector<SessionSummary> v;
  const double l1[] = {6.40, 6.45, 6.38, 6.42, 6.41, 6.39};
  for (int i = 0; i < 6; i++) {
    SessionSummary s = make("R" + std::to_string(i), D0 + 3 * i, 15, 10, 8);
    s.race.present = true; s.race.breed = "PSI"; s.race.vedba_load_gmin = 20; s.race.vedba_gallop_g = 0.75;
    s.race.ref_speed[0] = 14; s.race.sf_ref[0] = 2.31; s.race.sl_ref[0] = l1[i]; s.race.fatigue_pct = 15; s.race.vmax = 16.8;
    v.push_back(s);
  }
  SessionSummary bad = make("CORTA", D0 + 18, 15, 10, 8);
  bad.race = v.back().race; bad.race.sl_ref[0] = 5.90; bad.race.impacts = 2;   // much shorter stride at 14 m/s
  v.push_back(bad);
  TrainingResult r = analyse_training(v, "", c);
  const SessionResult* x = find(r, "CORTA");
  const Deviation* d = dev(x, "TRABAJO.l_v1_m");
  CHECK(d && d->level == "REVISAR" && d->direction == "MENOR");
  CHECK(x && x->level == "REVISAR");
  CHECK(x && contains(x->reasons, "impactos atípicos"));
  CHECK(trend(r, "TRABAJO.l_v1_m") != nullptr);
  CHECK(trend(r, "carga_vedba") != nullptr);
  CHECK_NEAR(r.current.acute_imu, 20 * 3, 1e-9);   // sessions on days 12, 15, 18
  // summary JSON round trip keeps the racing block
  json::Value sv; std::string err; SessionSummary back;
  CHECK(json::parse(training_summary_to_json(bad), &sv, &err) && training_summary_from_json(sv, &back, &err));
  CHECK(back.race.present && back.race.impacts == 2 && std::fabs(back.race.sl_ref[0] - 5.9) < 1e-9 && back.race.breed == "PSI");
  CHECK(training_summary_to_json(back) == training_summary_to_json(bad));
}
