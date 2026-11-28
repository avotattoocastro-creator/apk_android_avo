// Comparables por condiciones (TRAINING 1.7.0, KB 1.34.0): TC1–TC4, PC1–PC3 y GO1.
#include <cmath>
#include <cstdio>
#include <string>
#include "avo_eq/json.h"
#include "avo_eq/training.h"
#include "eq_test.h"

using namespace avoeq;

namespace {

SessionSummary base_session(const std::string& id, long day) {
  SessionSummary s;
  s.id = id; s.horse = "LUNA"; s.date_utc = training_day_text(day);
  s.gait[0].duration_s = 900; s.gait[1].duration_s = 600; s.gait[2].duration_s = 480;
  s.moving_s = 1980; s.distance_m = 8000;
  return s;
}
SessionSummary ecg_session(int i, double v200, double temp) {
  SessionSummary s = base_session("E" + std::to_string(i), 20500 + i);
  s.surface = "arena"; s.temperature_c = temp;
  s.cardio.present = true; s.cardio.quality = "BUENA"; s.cardio.v200 = v200; s.cardio.v200_method = "CRUCE_200_10S";
  return s;
}
SessionSummary race_session(int i, double sl) {
  SessionSummary s = base_session("R" + std::to_string(i), 20500 + 2 * i);
  s.surface = "ARENA"; s.race.present = true; s.race.breed = "PSI"; s.race.vedba_load_gmin = 20; s.race.sl_ref[0] = sl;
  return s;
}
bool has_flag(const TrainingResult& r, const char* rule) {
  for (const auto& f : r.sessions.back().kb.flags) if (f.rule == rule) return true;
  return false;
}

}  // namespace

// TC1: aproximación del WBGT del Bureau of Meteorology, valores calculados a mano; GO1: estratos; TC3 y PC3.
EQ_TEST(condiciones, wbgt_going_and_heat_class) {
  // T 30 °C, HR 50 %: e = 0,5 · 6,105 · exp(17,27·30/267,7) = 21,143 hPa → 0,567·30 + 0,393·21,143 + 3,94 = 29,26 °C
  CHECK_NEAR(training_wbgt_estimate(30, 50), 29.259, 0.01);
  // T 20 °C, HR 50 %: e = 11,662 hPa → 11,34 + 4,583 + 3,94 = 19,86 °C
  CHECK_NEAR(training_wbgt_estimate(20, 50), 19.863, 0.01);
  CHECK(std::isnan(training_wbgt_estimate(NAN, 50)));
  CHECK(std::isnan(training_wbgt_estimate(25, NAN)));
  CHECK(std::isnan(training_wbgt_estimate(25, 120)));
  CHECK(training_going_stratum("BUENO_FIRME") == "FIRME" && training_going_stratum("FIRME") == "FIRME");
  CHECK(training_going_stratum("BUENO_BLANDO") == "BLANDO" && training_going_stratum("BUENO") == "BUENO");
  CHECK(training_going_stratum("PESADO") == "PESADO" && training_going_stratum("").empty() && training_going_stratum("RARO").empty());
  TrainingConfig c;
  SessionSummary s = base_session("X", 20500);
  CHECK(training_condition_info(s, c).heat.empty());   // sin dato
  s.temperature_c = 30; s.humidity_pct = 50;
  CondInfo a = training_condition_info(s, c);
  CHECK(a.heat == "CALOR" && a.wbgt_origin == "ESTIMADO_T_HR");   // WBGT 29,3 ≥ 28
  s.temperature_c = 25; s.humidity_pct = 60;                       // WBGT ≈ 25,6
  CHECK(training_condition_info(s, c).heat == "NORMAL");
  s.humidity_pct = NAN; s.temperature_c = 31;                      // ≥ 30 °C sin humedad: prudente, calor
  CHECK(training_condition_info(s, c).heat == "CALOR");
  s.temperature_c = 22;
  CHECK(training_condition_info(s, c).heat == "NORMAL");
  s.temperature_c = 29; s.humidity_pct = 90; s.wbgt_c = 27;        // el WBGT medido manda sobre el estimado
  CondInfo m = training_condition_info(s, c);
  CHECK(m.heat == "NORMAL" && m.wbgt_origin == "MEDIDO");
  CHECK_NEAR(m.wbgt, 27, 1e-12);
  s.rider_kg = 58; s.horse_kg = 460;
  CHECK_NEAR(training_condition_info(s, c).cwbw_pct, 12.609, 0.001);
}

// TC2: A9 compara solo sesiones con |ΔT| ≤ 5 °C; sin temperatura (análisis anteriores) se mantiene la comparación.
EQ_TEST(condiciones, a9_temperature_filter) {
  std::vector<SessionSummary> h;
  const double base[] = {15.0, 15.1, 14.95, 15.05, 15.0, 15.1, 14.9, 15.0};
  for (int i = 0; i < 8; i++) h.push_back(ecg_session(i, base[i], 12));
  for (int i = 8; i < 11; i++) h.push_back(ecg_session(i, 13.8, 24));   // 12 °C más: sin comparables propias
  TrainingConfig c;
  TrainingResult r = analyse_training(h, "", c);
  CHECK(!has_flag(r, "A9_PERDIDA_FORMA"));
  CHECK(!has_flag(r, "A9_NO_COMPARABLE_CALOR"));   // 24 °C sin humedad no es calor
  bool cnt = false;
  for (const auto& x : r.cond.rules)
    if (x.rule == "A9") { cnt = true; CHECK(x.count.base == 11 && x.count.kept == 3 && x.count.temperature == 8); }
  CHECK(cnt);
  // con la misma diferencia pero sin temperatura anotada, la caída sí se ve
  std::vector<SessionSummary> h2 = h; for (auto& s : h2) s.temperature_c = NAN;
  CHECK(has_flag(analyse_training(h2, "", c), "A9_PERDIDA_FORMA"));
  // con la opción «condiciones»: false, también
  json::Value opt; std::string err;
  CHECK(json::parse("{\"condiciones\":false}", &opt, &err));
  TrainingConfig off; CHECK(training_config_from_json(opt, &off, &err));
  CHECK(has_flag(analyse_training(h, "", off), "A9_PERDIDA_FORMA"));
  // con |ΔT| ≤ 5 °C se comparan y la caída se ve
  std::vector<SessionSummary> h3 = h; for (int i = 8; i < 11; i++) h3[i].temperature_c = 16;
  CHECK(has_flag(analyse_training(h3, "", c), "A9_PERDIDA_FORMA"));
}

// TC3 y TC4: con calor, A9 no juzga la sesión, sale INFO y nunca sube el estado.
EQ_TEST(condiciones, heat_not_comparable_and_acclimation) {
  std::vector<SessionSummary> h;
  const double base[] = {15.0, 15.1, 14.95, 15.05, 15.0, 15.1, 14.9, 15.0};
  for (int i = 0; i < 8; i++) { h.push_back(ecg_session(i, base[i], 28)); h.back().humidity_pct = 30; }   // WBGT ≈ 24,6
  for (int i = 8; i < 11; i++) { h.push_back(ecg_session(i, 13.8, 31)); h.back().humidity_pct = 75; }   // calor húmedo
  TrainingResult r = analyse_training(h, "", TrainingConfig());
  CHECK(has_flag(r, "A9_NO_COMPARABLE_CALOR"));
  CHECK(!has_flag(r, "A9_PERDIDA_FORMA") && !has_flag(r, "A9_V200_SALTO"));
  CHECK(r.level == "NORMAL");
  CHECK(r.cond.info.heat == "CALOR" && r.cond.acclim_day == 3);   // días 20508, 20509 y 20510
  int tc3 = 0, tc4 = 0;
  for (const auto& m : r.cond.marks) { if (m.rule == "TC3") tc3++; if (m.rule == "TC4") tc4++; }
  CHECK(tc3 == 3 && tc4 == 3);
  // sin humedad, 31 °C también cuenta como calor; con aclimatación de 2 días, el tercero ya no es transición
  json::Value opt; std::string err;
  CHECK(json::parse("{\"condiciones\":{\"dias_aclimatacion\":2}}", &opt, &err));
  TrainingConfig c2; CHECK(training_config_from_json(opt, &c2, &err));
  TrainingResult r2 = analyse_training(h, "", c2);
  int tc4b = 0; for (const auto& m : r2.cond.marks) if (m.rule == "TC4") tc4b++;
  CHECK(tc4b == 2);
}

// GO1: A7 compara solo el mismo estrato de going (la zancada corta en blando no es fatiga, GO2).
EQ_TEST(condiciones, a7_going_strata) {
  std::vector<SessionSummary> h;
  for (int i = 0; i < 12; i++) {
    SessionSummary s = race_session(i, i < 9 ? 6.40 : 6.20);
    s.going = i < 9 ? "BUENO" : "BLANDO";
    h.push_back(s);
  }
  TrainingConfig c;
  CHECK(!has_flag(analyse_training(h, "", c), "A7_CAIDA_ZANCADA"));
  // BUENO_FIRME y FIRME son el mismo estrato
  std::vector<SessionSummary> f = h; for (int i = 0; i < 12; i++) f[i].going = i < 9 ? "FIRME" : "BUENO_FIRME";
  CHECK(has_flag(analyse_training(f, "", c), "A7_CAIDA_ZANCADA"));
  // sin going anotado, la caída se ve
  std::vector<SessionSummary> n = h; for (auto& s : n) s.going.clear();
  TrainingResult rn = analyse_training(n, "", c);
  CHECK(has_flag(rn, "A7_CAIDA_ZANCADA"));
  bool note = false; for (const auto& x : rn.cond.notes) if (x.find("GO1") != std::string::npos) note = true;
  CHECK(note);
  // opción estrato_going false: también
  json::Value opt; std::string err;
  CHECK(json::parse("{\"condiciones\":{\"estrato_going\":false}}", &opt, &err));
  TrainingConfig c2; CHECK(training_config_from_json(opt, &c2, &err));
  CHECK(has_flag(analyse_training(h, "", c2), "A7_CAIDA_ZANCADA"));
}

// PC2: peso del jinete ±3 kg y mismo jinete preferente en A7.
EQ_TEST(condiciones, a7_weight_and_same_rider) {
  std::vector<SessionSummary> h;
  for (int i = 0; i < 12; i++) { h.push_back(race_session(i, i < 9 ? 6.40 : 6.25)); h.back().rider_kg = i < 9 ? 55 : 62; }
  TrainingConfig c;
  CHECK(!has_flag(analyse_training(h, "", c), "A7_CAIDA_ZANCADA"));   // +7 kg: no comparables
  for (int i = 9; i < 12; i++) h[i].rider_kg = 57;                      // +2 kg: sí
  CHECK(has_flag(analyse_training(h, "", c), "A7_CAIDA_ZANCADA"));
  // mismo jinete: 10 sesiones de LUIS (6,60 m) y 8 de ANA (6,45 m); la última es de ANA
  std::vector<SessionSummary> r;
  for (int i = 0; i < 18; i++) {
    SessionSummary s = race_session(i, i < 10 ? 6.60 : 6.45);
    s.rider = i < 10 ? "LUIS" : "ANA";
    r.push_back(s);
  }
  TrainingResult rr = analyse_training(r, "", c);
  CHECK(!has_flag(rr, "A7_CAIDA_ZANCADA"));   // 8 de ANA ≥ 5 + 3: solo su jinete, sin caída
  bool cnt = false;
  for (const auto& x : rr.cond.rules)
    if (x.rule == "A7") { cnt = true; CHECK(x.count.base == 18 && x.count.kept == 8 && x.count.rider == 10 && x.count.same_rider); }
  CHECK(cnt);
  json::Value opt; std::string err;
  CHECK(json::parse("{\"condiciones\":{\"mismo_jinete\":false}}", &opt, &err));
  TrainingConfig c2; CHECK(training_config_from_json(opt, &c2, &err));
  CHECK(has_flag(analyse_training(r, "", c2), "A7_CAIDA_ZANCADA"));   // mezclando jinetes: mediana 6,60, caída aparente de 0,15 m
  // PC3: peso cargado > 13 % del peso corporal = marca INFO
  r.back().rider_kg = 62; r.back().horse_kg = 450;   // 13,8 %
  TrainingResult rp = analyse_training(r, "", c);
  bool pc3 = false; for (const auto& m : rp.cond.marks) if (m.rule == "PC3") pc3 = true;
  CHECK(pc3);
  CHECK_NEAR(rp.cond.info.cwbw_pct, 13.778, 0.001);
}

// Cinética de la FC: τ solo con |ΔT| ≤ 5 °C (TC2).
EQ_TEST(condiciones, hr_kinetics_temperature) {
  std::vector<SessionSummary> h;
  for (int i = 0; i < 5; i++) {
    SessionSummary s = ecg_session(i, 15, i < 4 ? 10 : 22);
    s.cardio.cooldown_class = "PASO"; s.cardio.tau_s = i < 4 ? 90 : 120;
    h.push_back(s);
  }
  TrainingResult r = analyse_training(h, "", TrainingConfig());
  CHECK(r.hrkin.metrics.size() == 3 && r.hrkin.metrics[0].n == 0);
  for (auto& s : h) s.temperature_c = NAN;
  TrainingResult r2 = analyse_training(h, "", TrainingConfig());
  CHECK(r2.hrkin.metrics[0].n == 4 && r2.hrkin.metrics[0].marked);
}

// JSON: bloque estado.condiciones, condiciones por sesión, ficha de campo con wbgt_c y opciones fuera de rango.
EQ_TEST(condiciones, json_and_options) {
  std::vector<SessionSummary> h;
  for (int i = 0; i < 3; i++) { h.push_back(ecg_session(i, 15, 31)); h.back().humidity_pct = 80; h.back().going = "BUENO_FIRME"; }
  TrainingConfig c;
  TrainingResult r = analyse_training(h, "", c);
  json::Value v; std::string err;
  CHECK(json::parse(training_to_json(r, c), &v, &err));
  const json::Value& k = v["estado"]["condiciones"];
  CHECK(k["disponible"].boolean(false) && !k["validado"].boolean(true) && k["nivel"].str() == "INFO");
  CHECK(k["parametros"]["etiquetas"]["temperatura_dif"].str() == "I");
  CHECK_NEAR(k["parametros"]["wbgt_calor_c"].num(), 28, 1e-12);
  CHECK(k["ultima"]["condiciones"]["calor"].str() == "CALOR");
  CHECK(k["ultima"]["condiciones"]["estrato_going"].str() == "FIRME");
  CHECK(k["ultima"]["condiciones"]["wbgt_origen"].str() == "ESTIMADO_T_HR");
  CHECK(k["ultima"]["peso_jinete_kg"].type == json::Value::NUL);
  CHECK(k["ultima"]["dia_periodo_calor"].num() == 3);
  CHECK(v["sesiones"][0]["condiciones"]["calor"].str() == "CALOR");
  // sin sesiones con datos de condiciones: nulls, nunca inventados
  std::vector<SessionSummary> e; e.push_back(base_session("Z", 20500));
  TrainingResult re = analyse_training(e, "", c);
  json::Value ve; CHECK(json::parse(training_to_json(re, c), &ve, &err));
  CHECK(ve["estado"]["condiciones"]["ultima"]["condiciones"]["wbgt_c"].type == json::Value::NUL);
  CHECK(ve["estado"]["condiciones"]["ultima"]["condiciones"]["calor"].type == json::Value::NUL);
  CHECK(ve["estado"]["condiciones"]["ultima"]["dia_periodo_calor"].type == json::Value::NUL);
  // ficha de campo: condiciones.wbgt_c
  json::Value x; CHECK(json::parse("{\"condiciones\":{\"temperatura_c\":29,\"humedad_pct\":90,\"wbgt_c\":26.5}}", &x, &err));
  SessionSummary s = base_session("F", 20500); training_read_field_sheet(x, &s);
  CHECK_NEAR(s.wbgt_c, 26.5, 1e-12);
  SessionSummary back; CHECK(json::parse(training_summary_to_json(s), &x, &err) && training_summary_from_json(x, &back, &err));
  CHECK_NEAR(back.wbgt_c, 26.5, 1e-12);
  // opciones
  CHECK(json::parse("{\"condiciones\":{\"temperatura_dif_c\":3,\"peso_dif_kg\":2,\"wbgt_estimado\":false}}", &x, &err));
  TrainingConfig c2; CHECK(training_config_from_json(x, &c2, &err));
  CHECK_NEAR(c2.cond.temp_match_c, 3, 1e-12); CHECK_NEAR(c2.cond.weight_match_kg, 2, 1e-12); CHECK(!c2.cond.wbgt_estimate);
  CHECK(json::parse("{\"condiciones\":{\"wbgt_calor_c\":5}}", &x, &err));
  TrainingConfig c3; CHECK(!training_config_from_json(x, &c3, &err));
  CHECK(json::parse("{\"condiciones\":3}", &x, &err));
  TrainingConfig c4; CHECK(!training_config_from_json(x, &c4, &err));
}
