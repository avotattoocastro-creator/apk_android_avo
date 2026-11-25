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

// Ficha de campo (TRAINING 1.1.0): tipo de sesión, franja, marea, going, condiciones, pesos e incidencia.
EQ_TEST(entreno, field_sheet_extra) {
  const char* an = R"({"formato":"avo-equine-analysis","sesion":{"id":"F1","caballo":"LUNA","inicio_utc":"2026-11-21T08:00:00Z"},"rendimiento":{"segmentos":[]}})";
  const char* extra = R"({"tipo_sesion":"trabajo_referencia_1000","pista":{"superficie":"PLAYA","franja":"ORILLA_FIRME","going":"BUENO",
    "marea":{"hora":"07:42","tipo":"BAJAMAR"}},"condiciones":{"temperatura_c":14.5,"humedad_pct":82},
    "pesos":{"jinete_kg":56,"caballo_kg":478},"incidencia":{"tipo":"TROPIEZO","texto":"tropieza en la transición"}})";
  char* out = nullptr;
  CHECK(avo_eq_training_summary(an, extra, &out) == 0 && out);
  json::Value v; std::string err;
  CHECK(out && json::parse(out, &v, &err));
  CHECK(v["tipo_sesion"].str() == "TRABAJO_REFERENCIA_1000");
  CHECK(v["pista"]["superficie"].str() == "PLAYA" && v["pista"]["franja"].str() == "ORILLA_FIRME" && v["pista"]["going"].str() == "BUENO");
  CHECK(v["pista"]["marea"]["hora"].str() == "07:42" && v["pista"]["marea"]["tipo"].str() == "BAJAMAR");
  CHECK_NEAR(v["condiciones"]["temperatura_c"].num(), 14.5, 1e-9);
  CHECK_NEAR(v["condiciones"]["humedad_pct"].num(), 82, 1e-9);
  CHECK_NEAR(v["pesos"]["jinete_kg"].num(), 56, 1e-9);
  CHECK_NEAR(v["pesos"]["caballo_kg"].num(), 478, 1e-9);
  CHECK(v["incidencia"]["tipo"].str() == "TROPIEZO" && v["incidencia"]["texto"].str() == "tropieza en la transición");
  // ida y vuelta: el resumen leído y escrito de nuevo es idéntico
  SessionSummary back;
  CHECK(training_summary_from_json(v, &back, &err) && back.session_type == "TRABAJO_REFERENCIA_1000" && back.beach_band == "ORILLA_FIRME");
  CHECK(training_summary_to_json(back) == std::string(out));
  avo_eq_free(out);
  // valores no válidos: se descartan con aviso, el resto se conserva
  const char* bad = R"({"tipo_sesion":"PASEO","pista":{"franja":"ARENA","marea":{"hora":"25:10"}},"condiciones":{"temperatura_c":80,"humedad_pct":50},
    "pesos":{"caballo_kg":40}})";
  CHECK(avo_eq_training_summary(an, bad, &out) == 0 && out && json::parse(out, &v, &err));
  CHECK(v["tipo_sesion"].str().empty() && v["pista"]["franja"].str().empty() && v["pista"]["marea"]["hora"].str().empty());
  CHECK(v["condiciones"]["temperatura_c"].is_null() && v["condiciones"]["humedad_pct"].num() == 50 && v["pesos"]["caballo_kg"].is_null());
  avo_eq_free(out);
  // incidencias: COJERA sube a REVISAR, CAIDA a VIGILAR, el resto solo se anota
  std::vector<SessionSummary> h;
  for (int i = 0; i < 3; i++) h.push_back(make("I" + std::to_string(i), D0 + i, 15, 20, 5));
  h[0].incident_type = "TROPIEZO"; h[1].incident_type = "CAIDA"; h[2].incident_type = "COJERA"; h[2].incident_text = "mano izquierda";
  TrainingResult r = analyse_training(h, "", TrainingConfig());
  CHECK(find(r, "I0")->level == "NORMAL" && contains(find(r, "I0")->reasons, "incidencia anotada: TROPIEZO"));
  CHECK(find(r, "I1")->level == "VIGILAR");
  CHECK(find(r, "I2")->level == "REVISAR" && contains(find(r, "I2")->reasons, "COJERA (mano izquierda)"));
}

// A4 y base del planificador en la historia: opción «carreras_previstas» y sesiones CARRERA/TRIAL.
EQ_TEST(entreno, planned_races_a4_and_planner) {
  // PSI con bloque de base científica: canter cada 2 días durante 60 días, galope rápido de 400 m solo el día 50
  std::vector<SessionSummary> h;
  for (int d = 0; d <= 58; d += 2) {
    SessionSummary s = make("P" + std::to_string(d), D0 + d, 15, 10, 8);
    s.race.present = true; s.race.breed = "PSI";
    s.race.kb_band_m[0] = 1500; s.race.kb_band_m[1] = 0; s.race.kb_band_m[2] = d == 50 ? 400 : 0;
    s.race.kb_canter_m = 1500; s.race.kb_gallop_m = d == 50 ? 400 : 0; s.race.kb_bone_pct = 0.3;
    h.push_back(s);
  }
  TrainingConfig c;
  json::Value opt; std::string err;
  CHECK(json::parse("{\"carreras_previstas\":[\"" + training_day_text(D0 + 66) + "\",\"" + training_day_text(D0 + 75) + "\"]}", &opt, &err));
  CHECK(training_config_from_json(opt, &c, &err) && c.kb.planned_race_days.size() == 2);
  TrainingResult r = analyse_training(h, training_day_text(D0 + 58), c);
  // carrera del día 66 vista el 58: faltan 8 días, 1 día rápido en [38, 58] → AVISO (INFO, no sube el estado)
  bool a4 = false;
  for (const auto& f : r.kb.flags) if (f.rule == "A4_CARGA_BAJA_PRECARRERA") a4 = f.level == "INFO";
  CHECK(a4);
  CHECK(r.planner.available && r.planner.next_race_day == D0 + 66 && r.planner.days_to_next_race == 8);
  CHECK(r.planner.fast_days_before_race == 1 && r.planner.fast_needed == 1 && r.planner.days_since_fast == 8);
  bool p1 = false, p3 = false;
  for (const auto& n : r.planner.notes) { if (n.rule == "PLANIFICADOR_P1") p1 = true; if (n.rule == "PLANIFICADOR_P3") p3 = true; }
  CHECK(p1);   // ningún rápido en los últimos 7 días con el caballo trabajando
  CHECK(p3);   // 9 días entre las dos carreras previstas (< 14)
  std::string js = training_to_json(r, c);
  CHECK(js.find("\"planificador\":{\"disponible\":true,\"dias_rapidos_7d\":0") != std::string::npos);
  CHECK(js.find("\"proxima_carrera\":{\"fecha\":\"" + training_day_text(D0 + 66) + "\",\"dias_hasta\":8,\"dias_rapidos_28d\":1,\"faltan_para_minimo\":1}") != std::string::npos);
  // una sesión de tipo TRIAL el día 58 cuenta como carrera: A4 retrospectivo en esa sesión
  std::vector<SessionSummary> h2 = h; h2.back().session_type = "TRIAL"; h2.back().race.kb_gallop_m = 1200; h2.back().race.kb_band_m[2] = 1200;
  TrainingResult r2 = analyse_training(h2, "", TrainingConfig());
  bool a4s = false;
  for (const auto& f : r2.sessions.back().kb.flags) if (f.rule == "A4_CARGA_BAJA_PRECARRERA") a4s = true;
  CHECK(a4s && r2.planner.days_since_last_race == 0);
  // fecha prevista no válida: error de opciones
  TrainingConfig c3;
  CHECK(json::parse("{\"carreras_previstas\":[\"mañana\"]}", &opt, &err) && !training_config_from_json(opt, &c3, &err));
  char* out = nullptr;
  CHECK(avo_eq_training_analyse("{\"sesiones\":[]}", "{\"carreras_previstas\":\"2026-12-01\"}", nullptr, &out) == 5); avo_eq_free(out);
}

// PL1: con la franja anotada, A7/A8 solo comparan sesiones de la misma superficie y franja.
EQ_TEST(entreno, beach_band_comparables) {
  std::vector<SessionSummary> h;
  for (int i = 0; i < 12; i++) {
    SessionSummary s = make("B" + std::to_string(i), D0 + 2 * i, 15, 10, 8);
    s.surface = "PLAYA"; s.race.present = true; s.race.breed = "PSI"; s.race.vedba_load_gmin = 20;
    s.race.sl_ref[0] = 6.40; s.beach_band = i < 9 ? "ORILLA_FIRME" : "SECA_PROFUNDA";
    if (i >= 9) s.race.sl_ref[0] = 6.20;   // arena seca profunda: zancada más corta, no es fatiga
    h.push_back(s);
  }
  TrainingResult r = analyse_training(h, "", TrainingConfig());
  bool a7 = false;
  for (const auto& f : r.sessions.back().kb.flags) if (f.rule == "A7_CAIDA_ZANCADA") a7 = true;
  CHECK(!a7);   // solo 3 sesiones en SECA_PROFUNDA: sin línea base comparable
  // la misma caída sin franja anotada sí salta (se comparan con las de orilla)
  for (auto& s : h) s.beach_band.clear();
  TrainingResult r2 = analyse_training(h, "", TrainingConfig());
  bool a7b = false;
  for (const auto& f : r2.sessions.back().kb.flags) if (f.rule == "A7_CAIDA_ZANCADA") a7b = true;
  CHECK(a7b);
}

// CG1–CG3 (KB 1.30.0): carga interna (TRIMP) y externa (trabajo rápido) descriptivas, nunca suben el estado.
EQ_TEST(entreno, load_cg_trimp_bands_ewma) {
  std::vector<SessionSummary> h;
  const double peaks[3] = {220, 225, 218};
  int fast = 0;
  for (int d = 0; d <= 38; d += 2) {
    SessionSummary s = make("G" + std::to_string(d), D0 + d, 15, 10, 8);
    s.race.present = true; s.race.breed = "PSI";
    s.race.kb_hs_m = 400; s.race.kb_cg_scale = "ABSOLUTAS_PSI";
    double bands[KB_CG_BANDS] = {3000, 1500, 300, 100, 0, 0};
    for (int k = 0; k < KB_CG_BANDS; k++) s.race.kb_cg_band_m[k] = bands[k];
    s.race.kb_gallop_m = d % 10 == 0 ? 400 : 0;   // días 0, 10, 20, 30: trabajo rápido
    s.cardio.present = true; s.cardio.quality = "BUENA"; s.cardio.trimp_coverage_pct = 95;
    s.cardio.hr_hist = {{120, 600}, {200, 60}};    // 10 min a 120–125 y 1 min a 200–205 lpm
    s.cardio.hr_peak = s.race.kb_gallop_m > 0 && fast < 3 ? peaks[fast++] : 190;
    h.push_back(s);
  }
  TrainingConfig c;
  TrainingResult r = analyse_training(h, training_day_text(D0 + 39), c);
  const CgStatus& g = r.cg;
  CHECK(g.available);
  // FM1: FC máxima propia = 225 (máximo de los trabajos rápidos con FC, ≥ 3); reposo por defecto 33
  CHECK(g.hr_max_origin == "PROPIA_HISTORIA" && g.hr_max_sessions == 4);   // días 0, 10, 20 y 30
  CHECK_NEAR(g.hr_max, 225, 1e-9);
  CHECK(g.hr_rest_origin == "POR_DEFECTO");
  // TRIMP por sesión con 33/225 (a mano): 10·w(0,466146) + 1·w(0,882813) = 10,378573
  CHECK_NEAR(r.sessions.back().cg_trimp, 10.378573, 1e-5);
  CHECK_NEAR(g.internal.sum_short, 3 * 10.378573, 1e-4);   // días 34, 36 y 38
  // CG2: 400 m de trabajo rápido cada 2 días → 7 d: 1.200 m; 30 d: 6.000 m
  CHECK_NEAR(g.external.sum_short, 1200, 1e-9);
  CHECK_NEAR(g.external.sum_long, 6000, 1e-9);
  CHECK_NEAR(g.band_long_m[0], 15 * 3000, 1e-9);
  CHECK(g.scale == "ABSOLUTAS_PSI");
  // CG3: EWMA 7/28 d desde el día 0 (a mano): aguda 171,4268, crónica 181,7943, cociente 0,942971
  CHECK_NEAR(g.external.ewma_acute, 171.4268, 1e-3);
  CHECK_NEAR(g.external.ewma_chronic, 181.7943, 1e-3);
  CHECK_NEAR(g.external.ratio, 0.942971, 1e-5);
  CHECK(g.external.reason.empty() && g.external.sessions_long == 14 && g.external.missing_long == 0);
  CHECK(std::isfinite(g.internal.ratio));
  CHECK(std::isfinite(g.external.monotony) && std::isfinite(g.external.strain));
  CHECK(g.daily.size() == 28);
  // nunca sube el estado: el mismo resultado con CG apagada
  TrainingConfig off; off.cg.enabled = false;
  TrainingResult r0 = analyse_training(h, training_day_text(D0 + 39), off);
  CHECK(r0.level == r.level && r0.reasons.size() == r.reasons.size());
  // JSON
  json::Value v; std::string err;
  CHECK(json::parse(training_to_json(r, c), &v, &err));
  const json::Value& cg = v["estado"]["carga_cg"];
  CHECK(cg["nivel"].str() == "INFO" && !cg["validado"].boolean(true));
  CHECK(cg["fc_referencia"]["fc_max_origen"].str() == "PROPIA_HISTORIA");
  CHECK_NEAR(cg["externa"]["cociente"].num(0), 0.942971, 1e-5);
  CHECK(cg["diaria"].a.size() == 28 && cg["bandas"]["bandas"].a.size() == (size_t)KB_CG_BANDS);
  CHECK_NEAR(v["sesiones"][0]["carga_cg"]["rapido_m"].num(0), 400, 1e-9);
  // resumen ida y vuelta: histograma y bandas
  json::Value sj; CHECK(json::parse(training_summary_to_json(h.back()), &sj, &err));
  SessionSummary back; CHECK(training_summary_from_json(sj, &back, &err));
  CHECK(back.cardio.hr_hist.size() == 2 && back.cardio.hr_hist[1].first == 200 && back.cardio.hr_hist[1].second == 60);
  CHECK_NEAR(back.race.kb_hs_m, 400, 1e-9); CHECK_NEAR(back.race.kb_cg_band_m[1], 1500, 1e-9); CHECK(back.race.kb_cg_scale == "ABSOLUTAS_PSI");
  CHECK_NEAR(back.cardio.trimp_coverage_pct, 95, 1e-9);
  // sin ECG en 4 de las 14 sesiones de la ventana crónica (29 % > 20 %): sin cociente interno, con motivo; el externo sigue
  std::vector<SessionSummary> h2 = h;
  for (size_t i = h2.size() - 4; i < h2.size(); i++) h2[i].cardio = CardioSummary();
  TrainingResult r2 = analyse_training(h2, training_day_text(D0 + 39), c);
  CHECK(std::isnan(r2.cg.internal.ratio) && r2.cg.internal.missing_long == 4);
  CHECK(r2.cg.internal.reason.find("faltan datos en 4 de 14") != std::string::npos);
  CHECK(std::isfinite(r2.cg.external.ratio));
  // cobertura de FC baja (< 80 %): la sesión no aporta TRIMP
  std::vector<SessionSummary> h3 = h; h3.back().cardio.trimp_coverage_pct = 50;
  TrainingResult r3 = analyse_training(h3, training_day_text(D0 + 39), c);
  CHECK(std::isnan(r3.sessions.back().cg_trimp));
  // historia corta (< 28 d): totales sí, cociente no
  std::vector<SessionSummary> h4(h.begin(), h.begin() + 5);
  TrainingResult r4 = analyse_training(h4, training_day_text(D0 + 9), c);
  CHECK(std::isnan(r4.cg.external.ratio) && r4.cg.external.reason.find("historia menor de 28") != std::string::npos);
  CHECK_NEAR(r4.cg.external.sum_long, 2000, 1e-9);
  CHECK(r4.cg.hr_max_origin == "POR_DEFECTO" && r4.cg.hr_max == 213);   // 1 trabajo rápido: FC máxima por defecto
  // historia sin bloques nuevos (análisis anteriores): sin datos, todo null
  std::vector<SessionSummary> h5;
  for (int d = 0; d <= 30; d += 3) h5.push_back(make("O" + std::to_string(d), D0 + d, 15, 10, 8));
  TrainingResult r5 = analyse_training(h5, "", c);
  CHECK(!r5.cg.available && std::isnan(r5.cg.external.sum_short) && r5.cg.external.reason == "sin datos");
  // opciones: FC máxima del caballo y valores fuera de rango
  TrainingConfig c6; json::Value opt;
  CHECK(json::parse("{\"carga_cg\":{\"fc_max_lpm\":230,\"fc_reposo_lpm\":30}}", &opt, &err) && training_config_from_json(opt, &c6, &err));
  CHECK(c6.cg.trimp.hr_max_own && c6.cg.trimp.hr_rest_own);
  TrainingResult r6 = analyse_training(h, training_day_text(D0 + 39), c6);
  CHECK(r6.cg.hr_max_origin == "CABALLO" && r6.cg.hr_rest_origin == "CABALLO" && r6.cg.hr_max == 230);
  TrainingConfig c7;
  CHECK(json::parse("{\"carga_cg\":{\"fc_max_lpm\":300}}", &opt, &err) && !training_config_from_json(opt, &c7, &err));
  CHECK(json::parse("{\"carga_cg\":{\"dias_ewma_aguda\":28,\"dias_ewma_cronica\":7}}", &opt, &err) && !training_config_from_json(opt, &c7, &err));
  CHECK(json::parse("{\"carga_cg\":false}", &opt, &err) && training_config_from_json(opt, &c7, &err) && !c7.cg.enabled);
}

// ---------------------------------------------------------------- planificador semanal, capa 2 (TRAINING 1.3.0)
namespace {
SessionSummary plan_day(long day, double gallop_m, double canter_m, const char* breed = "PSI") {
  SessionSummary s = make("S" + std::to_string(day), day, 15, 10, 8);
  s.race.present = true; s.race.breed = breed;
  s.race.kb_band_m[0] = canter_m; s.race.kb_band_m[1] = 0; s.race.kb_band_m[2] = gallop_m;
  s.race.kb_canter_m = canter_m; s.race.kb_gallop_m = gallop_m; s.race.kb_bone_pct = 0.2;
  return s;
}
std::string plan_types(const WeekPlan& w) {
  std::string t;
  for (const auto& d : w.days) t += (t.empty() ? "" : ",") + d.type;
  return t;
}
bool has_note(const WeekPlan& w, const char* rule) {
  for (const auto& n : w.notes) if (n.rule == rule) return true;
  return false;
}
// Las pruebas de la capa 2 (1.3.0) usan los 7 días siguientes a la referencia; la semana natural tiene su propia prueba.
TrainingConfig plan_cfg(const std::string& opts, bool calendar = false) {
  TrainingConfig c; json::Value v; std::string err;
  if (!opts.empty()) { CHECK(json::parse(opts, &v, &err)); CHECK(training_config_from_json(v, &c, &err)); }
  c.planner.calendar_week = calendar;
  return c;
}
std::string plan_done(const WeekPlan& w) {
  std::string t;
  for (const auto& d : w.days) t += d.done ? "H" : "P";
  return t;
}
}  // namespace

// Maduro, rápido de 600 m cada 4 días: dos rápidos a ≥ 72 h (días +3 y +6), suave al día siguiente y un día libre.
EQ_TEST(entreno, planner_week_mature) {
  std::vector<SessionSummary> h;
  for (int d = 0; d <= 40; d++) h.push_back(plan_day(D0 + d, d % 4 == 0 ? 600 : 0, 1000));
  TrainingConfig c = plan_cfg("");
  TrainingResult r = analyse_training(h, training_day_text(D0 + 40), c);
  const WeekPlan& w = r.week;
  CHECK(w.available && w.phase == "NORMAL" && !w.limited);
  CHECK(w.from_day == D0 + 41 && w.to_day == D0 + 47 && w.days.size() == 7);
  CHECK(w.fast_target == 2 && w.fast_planned == 2);
  CHECK(plan_types(w) == "SUAVE,LENTO,RAPIDO,SUAVE,LENTO,RAPIDO,LIBRE");
  CHECK_NEAR(w.fast_ref_m, 600, 1e-9);
  CHECK(std::isnan(w.fast_max_m) && w.age_years == -1 && has_note(w, "PLANIFICADOR_EDAD"));
  CHECK(r.level == analyse_training(h, training_day_text(D0 + 40), plan_cfg("{\"planificador\":false}")).level);   // nunca cambia el estado
  std::string js = training_to_json(r, c);
  CHECK(js.find("\"semana_siguiente\":{\"disponible\":true,\"desde\":\"" + training_day_text(D0 + 41) + "\"") != std::string::npos);
  CHECK(js.find("\"fase\":\"NORMAL\"") != std::string::npos && js.find("\"validado\":false") != std::string::npos);
  json::Value v; std::string err;
  CHECK(json::parse(js, &v, &err));
  const json::Value& sw = v["estado"]["planificador"]["semana_siguiente"];
  CHECK(sw["dias"].a.size() == 7 && sw["dias"][2]["tipo"].str() == "RAPIDO" && sw["dias"][2]["rapido_max_m"].is_null());
  CHECK(sw["edad_anos"].is_null() && sw["rapido_max_m"].is_null() && sw["parametros"]["dias_min_entre_rapidos"].num() == 3);
  // desactivado: sin propuesta
  TrainingResult off = analyse_training(h, "", plan_cfg("{\"planificador\":false}"));
  CHECK(!off.week.available && off.week.days.empty());
  // sin bloque de carga de la base científica: sin propuesta y motivo
  std::vector<SessionSummary> plain;
  for (int d = 0; d < 10; d++) plain.push_back(make("N" + std::to_string(d), D0 + d, 15, 20, 5));
  TrainingResult rn = analyse_training(plain, "", c);
  CHECK(!rn.week.available && !rn.week.reason.empty());
  CHECK(training_to_json(rn, c).find("\"semana_siguiente\":{\"disponible\":false,\"motivo\":") != std::string::npos);
}

// Potro de 2 años con carrera prevista: sin rápido en los 3 días previos ni el siguiente; DM1 tope de 400 m.
EQ_TEST(entreno, planner_week_colt_race) {
  std::vector<SessionSummary> h;
  for (int d = 0; d <= 20; d++) h.push_back(plan_day(D0 + d, d % 4 == 0 ? 300 : 0, 800));
  TrainingConfig c = plan_cfg("{\"edad_anos\":2,\"carreras_previstas\":[\"" + training_day_text(D0 + 26) + "\"]}");
  TrainingResult r = analyse_training(h, training_day_text(D0 + 20), c);
  const WeekPlan& w = r.week;
  CHECK(w.phase == "POTRO_2_ANOS" && w.age_years == 2 && w.age_origin == "EDAD_ANOS" && w.prep_weeks == 2);
  CHECK_NEAR(w.fast_max_m, 400, 1e-9);
  CHECK(w.fast_target == 2 && w.fast_planned == 0);
  CHECK(plan_types(w) == "SUAVE,LENTO,LENTO,LENTO,LENTO,CARRERA,LIBRE");
  CHECK(has_note(w, "PLANIFICADOR_DM1") && has_note(w, "PLANIFICADOR_P2") && !has_note(w, "PLANIFICADOR_EDAD"));
  // sin carrera: dos rápidos con el tope de DM1
  TrainingResult r2 = analyse_training(h, training_day_text(D0 + 20), plan_cfg("{\"fecha_nacimiento\":\"2024-03-01\"}"));
  CHECK(r2.week.age_years == 2 && r2.week.age_origin == "FECHA_NACIMIENTO" && r2.week.fast_planned == 2);
  CHECK(plan_types(r2.week) == "SUAVE,LENTO,RAPIDO,SUAVE,LENTO,RAPIDO,LIBRE");
  CHECK_NEAR(r2.week.days[2].fast_max_m, 400, 1e-9);
}

// P4 y P7: vuelta tras > 60 d sin rápido (rápidos de 600 m hasta el día 28, parado 31–100, lento desde el 101).
EQ_TEST(entreno, planner_week_return) {
  std::vector<SessionSummary> base;
  for (int d = 0; d <= 30; d++) base.push_back(plan_day(D0 + d, d % 4 == 0 ? 600 : 0, 1000));
  // 10 días de lento: semana sin rápidos, un día libre al final; tope 75 % de 600 = 450 m
  std::vector<SessionSummary> h = base;
  for (int d = 101; d <= 110; d++) h.push_back(plan_day(D0 + d, 0, 1000));
  TrainingConfig c = plan_cfg("");
  TrainingResult r = analyse_training(h, training_day_text(D0 + 110), c);
  CHECK(r.week.phase == "REINCORPORACION_LENTA" && r.week.slow_days_done == 10 && r.week.fast_target == 0 && r.week.fast_planned == 0);
  CHECK(plan_types(r.week) == "LENTO,LENTO,LENTO,LENTO,LENTO,LENTO,LIBRE");
  CHECK_NEAR(r.week.fast_max_m, 450, 1e-9);
  CHECK(has_note(r.week, "PLANIFICADOR_P4") && r.week.days_since_break == 9);
  // 30 días de lento: un solo rápido de 450 m
  h = base;
  for (int d = 101; d <= 130; d++) h.push_back(plan_day(D0 + d, 0, 1000));
  r = analyse_training(h, training_day_text(D0 + 130), c);
  CHECK(r.week.phase == "REINCORPORACION_LENTA" && r.week.slow_days_done == 30 && r.week.fast_target == 1 && r.week.fast_planned == 1);
  CHECK(plan_types(r.week) == "RAPIDO,SUAVE,LENTO,LENTO,LENTO,LENTO,LIBRE");
  CHECK_NEAR(r.week.days[0].fast_max_m, 450, 1e-9);
  // primer rápido de la vuelta el día 131: ventana P7, el siguiente rápido 7 días después
  h.push_back(plan_day(D0 + 131, 600, 1000));
  for (int d = 132; d <= 135; d++) h.push_back(plan_day(D0 + d, 0, 1000));
  r = analyse_training(h, training_day_text(D0 + 135), c);
  CHECK(r.week.phase == "REINCORPORACION_RAPIDO" && r.week.return_fast_day == D0 + 131 && r.week.fast_target == 1);
  CHECK(plan_types(r.week) == "LENTO,LENTO,RAPIDO,SUAVE,LENTO,LENTO,LIBRE");
  CHECK_NEAR(r.week.fast_max_m, 450, 1e-9);
  CHECK(has_note(r.week, "PLANIFICADOR_P7"));
  // pasada la ventana de 21 d: fase normal
  for (int d = 136; d <= 155; d++) h.push_back(plan_day(D0 + d, d % 4 == 0 ? 600 : 0, 1000));
  r = analyse_training(h, training_day_text(D0 + 155), c);
  CHECK(r.week.phase == "NORMAL" && r.week.fast_target == 2);
}

// P5 (60 d frente al P75 propio, sin penalizar el último mes) y P6 (sin descanso en ≥ 183 d).
EQ_TEST(entreno, planner_week_p5_p6) {
  // rápido cada 4 días: 200 m los 100 primeros días y luego 200 + 6·(d − 100) m (acumulación sostenida)
  std::vector<SessionSummary> h;
  for (int d = 0; d <= 199; d++) h.push_back(plan_day(D0 + d, d % 4 == 0 ? (d < 100 ? 200 : 200 + 6.0 * (d - 100)) : 0, 800));
  TrainingResult r = analyse_training(h, training_day_text(D0 + 199), plan_cfg(""));
  // ventana 140–199: 15 rápidos, Σ = 15·200 + 6·(40 + 44 + … + 96) = 9120 m → 152 m/día
  CHECK_NEAR(r.week.p5_mean_m, 152, 1e-9);
  CHECK(r.week.p5_mean_m > r.week.p5_p75_m && has_note(r.week, "PLANIFICADOR_P5"));
  CHECK(has_note(r.week, "PLANIFICADOR_P6") && r.week.days_since_break == -1);
  // mismo volumen pero solo en el último mes (rápido cada 5 días): no se avisa
  std::vector<SessionSummary> h2;
  for (int d = 0; d <= 199; d++) h2.push_back(plan_day(D0 + d, d % 5 == 0 ? (d < 170 ? 200 : 2000) : 0, 800));
  TrainingResult r2 = analyse_training(h2, training_day_text(D0 + 199), plan_cfg(""));
  CHECK(r2.week.p5_mean_m > r2.week.p5_p75_m && !has_note(r2.week, "PLANIFICADOR_P5"));
  // historia corta: sin P5 ni P6
  TrainingResult r3 = analyse_training(std::vector<SessionSummary>(h.begin(), h.begin() + 100), "", plan_cfg(""));
  CHECK(std::isnan(r3.week.p5_mean_m) && !has_note(r3.week, "PLANIFICADOR_P5") && !has_note(r3.week, "PLANIFICADOR_P6"));
}

// DM2–DM4 en potros de 2 años.
EQ_TEST(entreno, planner_week_dmd) {
  // DM2: canter 1000 m/día hasta el día 34 y 2500 m/día del 35 al 41 → 7 d: ×2,5; 14 d: ×1,75
  std::vector<SessionSummary> h;
  for (int d = 0; d <= 41; d++) h.push_back(plan_day(D0 + d, 0, d < 35 ? 1000 : 2500));
  TrainingResult r = analyse_training(h, training_day_text(D0 + 41), plan_cfg("{\"edad_anos\":2}"));
  int dm2 = 0;
  for (const auto& n : r.week.notes) if (n.rule == "PLANIFICADOR_DM2") dm2++;
  CHECK(dm2 == 2);
  bool x25 = false, x175 = false;
  for (const auto& n : r.week.notes) { if (n.text.find("2.5 veces") != std::string::npos || n.text.find("2,5 veces") != std::string::npos) x25 = true;
                                       if (n.text.find("1.8 veces") != std::string::npos || n.text.find("1,8 veces") != std::string::npos) x175 = true; }
  CHECK(x25 && x175);
  // el mismo caballo sin edad: sin DM
  TrainingResult rm = analyse_training(h, training_day_text(D0 + 41), plan_cfg(""));
  CHECK(!has_note(rm.week, "PLANIFICADOR_DM2"));
  // DM3 y DM4: rápidos de 400 m y salto a 750 m el día 40 con 1500 m de canter (lentos 1000 m)
  std::vector<SessionSummary> h2;
  for (int d = 0; d <= 41; d++) {
    double g = d == 40 ? 750 : (d % 4 == 0 && d <= 36 ? 400 : 0);
    h2.push_back(plan_day(D0 + d, g, d == 40 ? 1500 : 1000));
  }
  TrainingResult r2 = analyse_training(h2, training_day_text(D0 + 41), plan_cfg("{\"edad_anos\":2}"));
  CHECK(has_note(r2.week, "PLANIFICADOR_DM3") && has_note(r2.week, "PLANIFICADOR_DM4"));
  // árabe: aviso de extrapolación [I-raza]
  std::vector<SessionSummary> h3;
  for (int d = 0; d <= 20; d++) h3.push_back(plan_day(D0 + d, d % 4 == 0 ? 600 : 0, 1000, "ARABE"));
  CHECK(has_note(analyse_training(h3, "", plan_cfg("")).week, "PLANIFICADOR_ARABE"));
}

// Opciones del planificador: rangos y errores.
EQ_TEST(entreno, planner_options) {
  TrainingConfig c = plan_cfg("{\"planificador\":{\"rapidos_semana_maduro\":3,\"dias_min_entre_rapidos\":2,\"dias_libres\":0,\"p7_fraccion_distancia\":0.5}}");
  CHECK(c.planner.fast_per_week_mature == 3 && c.planner.min_days_between_fast == 2 && c.planner.free_days == 0);
  CHECK_NEAR(c.planner.p7_distance_fraction, 0.5, 1e-12);
  std::vector<SessionSummary> h;
  for (int d = 0; d <= 40; d++) h.push_back(plan_day(D0 + d, d % 4 == 0 ? 600 : 0, 1000));
  TrainingResult r = analyse_training(h, training_day_text(D0 + 40), c);
  CHECK(r.week.fast_planned == 3 && plan_types(r.week) == "SUAVE,RAPIDO,SUAVE,RAPIDO,SUAVE,RAPIDO,SUAVE");
  const char* bad[] = {"{\"planificador\":{\"dias_min_entre_rapidos\":0}}", "{\"planificador\":{\"p7_fraccion_distancia\":2}}",
                       "{\"planificador\":\"si\"}", "{\"fecha_nacimiento\":\"ayer\"}", "{\"edad_anos\":2.5}",
                       "{\"planificador\":{\"dm4_desde_m\":900,\"dm4_hasta_m\":700}}"};
  for (const char* b : bad) {
    TrainingConfig k; json::Value v; std::string err;
    CHECK(json::parse(b, &v, &err) && !training_config_from_json(v, &k, &err) && !err.empty());
  }
}

// TRAINING 1.4.0: semana natural de lunes a domingo con lo realizado en los días pasados (petición del usuario, 25/11/2026).
EQ_TEST(entreno, planner_calendar_week) {
  // referencia en miércoles: busca el primer miércoles ≥ D0 + 40 (día 0 = 1970-01-01, jueves)
  long at = D0 + 40;
  while (((at % 7) + 7 + 3) % 7 != 2) at++;
  const long mon = at - 2;
  std::vector<SessionSummary> h;
  for (long d = at - 40; d <= at; d++) h.push_back(plan_day(d, (mon - d) % 4 == 0 ? 600 : 0, 1000));   // rápido el lunes y cada 4 días antes
  TrainingConfig c = plan_cfg("", true);
  TrainingResult r = analyse_training(h, training_day_text(at), c);
  const WeekPlan& w = r.week;
  CHECK(w.calendar_week && w.from_day == mon && w.to_day == mon + 6 && w.plan_from_day == at + 1);   // hoy ya entrenado
  CHECK(w.fast_target == 2 && w.fast_done == 1 && w.fast_planned == 1);
  CHECK(plan_types(w) == "RAPIDO,LENTO,LENTO,RAPIDO,SUAVE,LENTO,LIBRE");
  CHECK(plan_done(w) == "HHHPPPP");
  CHECK(w.days[0].reason.find("realizado") != std::string::npos && w.days[0].rules.empty());
  CHECK(has_note(w, "PLANIFICADOR_P1"));
  std::string js = training_to_json(r, c);
  json::Value v; std::string err;
  CHECK(json::parse(js, &v, &err));
  const json::Value& sw = v["estado"]["planificador"]["semana_siguiente"];
  CHECK(sw["desde"].str() == training_day_text(mon) && sw["planifica_desde"].str() == training_day_text(at + 1));
  CHECK(sw["semana_calendario"].boolean(false) && sw["rapidos_hechos"].num() == 1);
  CHECK(sw["dias"][0]["realizado"].boolean(false) && !sw["dias"][3]["realizado"].boolean(true));
  // hoy sin entrenar todavía (última sesión ayer): se planifica desde hoy
  std::vector<SessionSummary> h2(h.begin(), h.end() - 1);
  TrainingResult r2 = analyse_training(h2, training_day_text(at), c);
  CHECK(r2.week.plan_from_day == at && plan_done(r2.week) == "HHPPPPP");
  CHECK(plan_types(r2.week) == "RAPIDO,LENTO,LENTO,RAPIDO,SUAVE,LENTO,LIBRE");
  // última sesión hace semanas (como en el iPad con la última sesión el 08/11 y hoy 25/11): días pasados sin entrenamiento
  std::vector<SessionSummary> h3;
  for (long d = at - 60; d <= at - 17; d++) h3.push_back(plan_day(d, (at - 17 - d) % 4 == 0 ? 600 : 0, 1000));
  TrainingResult r3 = analyse_training(h3, training_day_text(at), c);
  CHECK(r3.week.from_day == mon && r3.week.plan_from_day == at && r3.week.fast_done == 0);
  CHECK(r3.week.days[0].type == "LIBRE" && r3.week.days[0].done && r3.week.days[1].type == "LIBRE");
  CHECK(r3.week.fast_planned == 2 && plan_types(r3.week) == "LIBRE,LIBRE,RAPIDO,SUAVE,LENTO,RAPIDO,SUAVE");
  // domingo ya entrenado: se planifica la semana siguiente entera
  long sun = mon + 6;
  std::vector<SessionSummary> h4;
  for (long d = sun - 40; d <= sun; d++) h4.push_back(plan_day(d, (sun - d) % 4 == 0 ? 600 : 0, 1000));
  TrainingResult r4 = analyse_training(h4, training_day_text(sun), c);
  CHECK(r4.week.from_day == sun + 1 && r4.week.plan_from_day == sun + 1 && plan_done(r4.week) == "PPPPPPP");
  // opción: la semana natural se puede desactivar
  TrainingConfig c5; json::Value o;
  CHECK(json::parse("{\"planificador\":{\"semana_calendario\":false}}", &o, &err) && training_config_from_json(o, &c5, &err) && !c5.planner.calendar_week);
  CHECK(json::parse("{\"planificador\":{\"semana_calendario\":1}}", &o, &err) && !training_config_from_json(o, &c5, &err));
}
