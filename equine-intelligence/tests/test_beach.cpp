// AVO BEACH 1.0.0: marea del trabajo y franja de playa automática (GPS + líneas de playa + curva de marea).
// Playa SINTÉTICA recta (norte-sur): línea seca 100 m al oeste del recorrido, línea de bajamar 300 m al este
// (L = 400 m), alturas 4,6 / 0,4 m; marea sinusoidal de 12,42 h entre 0,6 y 4,4 m. Comprueba la geometría y la regla,
// no la exactitud en una playa real (pendiente de validar en Laredo).
#include <cmath>
#include <string>
#include <vector>
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/beach.h"
#include "avo_eq/engine.h"
#include "avo_eq/json.h"
#include "avo_eq/training.h"
#include "eq_test.h"
#include "synth.h"

using namespace avoeq;

namespace {
const double LAT0 = 43.4, LON0 = -3.43;
double lon_at(double x) { return LON0 + x / (synth::M_PER_DEG_LAT * std::cos(LAT0 * synth::PI / 180)); }
const double T0 = 1795424400.0;   // 2026-11-23 09:00:00 UTC

// session at 12 m/s northwards, `x_off` m east of the synthetic origin line, with valid date/time in the first epoch
Session beach_session(double x_off) {
  Session s;
  s.gnss = synth::track({{20, 2.0, 0}, {120, 12.0, 0}, {20, 2.0, 0}}, 8, nullptr);
  for (auto& e : s.gnss) e.lon_deg += lon_at(x_off) - LON0;
  auto& e = s.gnss[0];
  e.valid = 3; e.year = 2026; e.month = 11; e.day = 23; e.hour = 9; e.minute = 0; e.second = 0; e.nano = 0;
  return s;
}

// tide with phase chosen so that at T0 + 20 s (start of the fast work) h = h_now and the trend is `rising`
BeachConfig beach_cfg(double h_now, bool rising) {
  BeachConfig c;
  const double mean = 2.5, amp = 1.9, P = 12.42 * 3600;
  double ph = std::asin((h_now - mean) / amp);
  if (!rising) ph = synth::PI - ph;
  for (double t = -16 * 3600; t <= 4 * 3600; t += 600)
    c.tide.push_back({T0 + 20 + t, mean + amp * std::sin(ph + 2 * synth::PI * t / P)});
  c.tide_source = "SINTETICA";
  c.dry.set = true; c.dry.a_lat = LAT0 - 0.01; c.dry.a_lon = lon_at(-100); c.dry.b_lat = LAT0 + 0.03; c.dry.b_lon = lon_at(-100);
  c.low.set = true; c.low.a_lat = LAT0 - 0.01; c.low.a_lon = lon_at(300); c.low.b_lat = LAT0 + 0.03; c.low.b_lon = lon_at(300);
  return c;
}

BeachResult run(double x_off, double h_now, bool rising) {
  EngineConfig c;
  c.beach = beach_cfg(h_now, rising);
  Session s = beach_session(x_off);
  Analysis a = analyse(s, c);
  return a.beach;
}
}  // namespace

EQ_TEST(playa, high_rising_tide_puts_the_track_on_the_firm_shore) {
  BeachResult r = run(0, 3.5, true);   // water 104,8 m from the dry line; track at 100 m → within 40 m of the water
  CHECK(r.present && r.tide && r.bands);
  CHECK(r.work_band == "ORILLA_FIRME");
  CHECK(r.tide_trend == 1);
  CHECK(r.tide_level == "ALTA");
  CHECK_NEAR(r.tide_work_m, 3.5, 0.05);
  CHECK(r.last_high_m > 4.3);
  CHECK(!r.mixed);
}

EQ_TEST(playa, low_tide_same_track_is_wet_transition_and_close_to_the_dunes_is_dry) {
  BeachResult r = run(0, 0.8, false);   // water 362 m away; last high water 4,4 m wet the sand from 19 m
  CHECK(r.bands && r.work_band == "TRANSICION");
  CHECK(r.tide_trend == -1 && r.tide_level == "BAJA");
  BeachResult d = run(-90, 0.8, false);  // 10 m from the dry line: above the last high water
  CHECK(d.bands && d.work_band == "SECA_PROFUNDA");
}

EQ_TEST(playa, without_lines_only_tide_and_without_options_nothing) {
  EngineConfig c;
  c.beach = beach_cfg(2.0, true);
  c.beach.dry.set = false; c.beach.low.set = false;
  Analysis a = analyse(beach_session(0), c);
  CHECK(a.beach.present && a.beach.tide && !a.beach.bands);
  Analysis b = analyse(beach_session(0), EngineConfig());
  CHECK(!b.beach.present);
  std::string js = to_json(b, beach_session(0), EngineConfig());
  CHECK(js.find("\"entorno\"") == std::string::npos);   // old analyses unchanged
}

EQ_TEST(playa, analysis_json_and_training_summary_use_the_auto_band_and_the_field_sheet_wins) {
  EngineConfig c;
  c.beach = beach_cfg(3.5, true);
  Session s = beach_session(0);
  Analysis a = analyse(s, c);
  std::string js = to_json(a, s, c);
  json::Value v;
  CHECK(json::parse(js, &v));
  CHECK(v["entorno"]["franjas"]["trabajo"].str() == "ORILLA_FIRME");
  CHECK(v["entorno"]["marea"]["nivel"].str() == "ALTA");
  char* out = nullptr;
  CHECK(avo_eq_training_summary(js.c_str(), nullptr, &out) == 0);
  json::Value sm;
  CHECK(json::parse(out ? out : "", &sm));
  CHECK(sm["pista"]["franja"].str() == "ORILLA_FIRME" && sm["pista"]["franja_origen"].str() == "AUTO");
  CHECK(sm["pista"]["marea"]["nivel"].str() == "ALTA" && sm["pista"]["marea"]["tendencia"].str() == "SUBE");
  avo_eq_free(out);
  CHECK(avo_eq_training_summary(js.c_str(), "{\"pista\":{\"franja\":\"HUMEDA_PROFUNDA\"}}", &out) == 0);
  CHECK(json::parse(out ? out : "", &sm));
  CHECK(sm["pista"]["franja"].str() == "HUMEDA_PROFUNDA" && sm["pista"]["franja_origen"].str() == "MANUAL");
  // the saved summary reads back with its origin
  SessionSummary back;
  std::string err;
  CHECK(training_summary_from_json(sm, &back, &err) && back.beach_band == "HUMEDA_PROFUNDA" && !back.beach_band_auto);
  avo_eq_free(out);
}

EQ_TEST(playa, options_through_the_c_api_are_validated) {
  const char* bad[] = {"{\"marea\":{\"curva\":[[1,99]]}}", "{\"playa\":{\"linea_seca\":{\"a\":[43.4,-3.4]}}}",
                       "{\"playa\":{\"altura_seca_m\":1,\"altura_bajamar_m\":1}}"};
  const char* paths[] = {"/no/existe.avr"};
  for (const char* o : bad) {
    char* out = nullptr;
    CHECK(avo_eq_analyse_ex(paths, 1, o, nullptr, &out) == 5);
    avo_eq_free(out);
  }
}
