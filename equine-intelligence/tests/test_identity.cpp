// AVO-ASSIGN-1 (docs/ASIGNACION_CABALLO.md): the horse and rider assigned in an app after recording.
// The assignment changes only the identity of the analysis; the RAW is never modified and the numbers do not change.
#include "eq_test.h"
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/engine.h"
#include "avo_eq/json.h"
#include "avo_eq/store.h"
#include "synth.h"
#include <filesystem>
#include <string>

using namespace avoeq;

#include "raw_writer.h"

namespace {
std::string analyse(const char* raw, const char* options, int* rc) {
  const char* paths[] = {raw};
  char* out = nullptr;
  *rc = avo_eq_analyse_ex(paths, 1, options, nullptr, &out);
  std::string s = out ? out : "";
  avo_eq_free(out);
  return s;
}
json::Value parsed(const std::string& s) { json::Value v; std::string err; json::parse(s, &v, &err); return v; }
// everything from "metricas" on: the numbers of the analysis
std::string numbers(const std::string& s) { size_t p = s.find("\"metricas\""); size_t q = s.find("\"procedencia\""); return s.substr(p, q - p); }
Session session() { Session s; s.session_id = "S_ASIGNACION"; s.gnss = synth::track({{60, 4.0, 0}}, 8, nullptr, nullptr, 0.03); return s; }
}  // namespace

EQ_TEST(asignacion, manifest_block_wins_over_raw_and_numbers_do_not_change) {
  const char* raw = "eq_asignacion.avo";
  remove(raw);
  CHECK(eqfix::write_raw(raw, session()));   // the RAW header says horse "PRUEBA"
  std::string err, fp0 = fingerprint_files({raw}, &err);
  int rc = -1;
  std::string plain = analyse(raw, "{\"procesado_utc\":\"2026-11-12T00:00:00Z\"}", &rc);
  CHECK(rc == 0);
  json::Value p = parsed(plain);
  CHECK(p["sesion"]["caballo"].str() == "PRUEBA");
  CHECK(p["sesion"]["caballo_raw"].str() == "PRUEBA");
  CHECK(p["sesion"]["identidad"].str() == "RAW");
  CHECK(p["sesion"]["caballo_nombre"].is_null());

  std::string asg = analyse(raw, "{\"procesado_utc\":\"2026-11-12T00:00:00Z\",\"asignacion\":{\"horseCode\":\"H_7cfe46c1\","
                                 "\"horseName\":\"Malwina\",\"riderCode\":\"AVO-A66T-F2E9\",\"riderName\":\"Andoni Lezama\"}}", &rc);
  CHECK(rc == 0);
  json::Value a = parsed(asg);
  CHECK(a["sesion"]["caballo"].str() == "H_7cfe46c1");
  CHECK(a["sesion"]["caballo_nombre"].str() == "Malwina");
  CHECK(a["sesion"]["jinete"].str() == "AVO-A66T-F2E9");
  CHECK(a["sesion"]["jinete_nombre"].str() == "Andoni Lezama");
  CHECK(a["sesion"]["caballo_raw"].str() == "PRUEBA");     // the RAW value is kept, never lost
  CHECK(a["sesion"]["identidad"].str() == "ASIGNACION");
  CHECK(numbers(asg) == numbers(plain));                     // identity only: same metrics, gaits, series…
  CHECK(fingerprint_files({raw}, &err) == fp0);              // RAW untouched
  remove(raw);
}

EQ_TEST(asignacion, name_only_cache_and_errors) {
  namespace fs = std::filesystem;
  const char* raw = "eq_asignacion_cache.avo";
  std::string dir = "eq_asignacion_dir";
  fs::remove_all(dir); remove(raw);
  CHECK(eqfix::write_raw(raw, session()));
  int rc = -1;
  // a manifest with only names (older iPad packages) still assigns the horse
  json::Value n = parsed(analyse(raw, "{\"asignacion\":{\"horseName\":\"Zakina\"}}", &rc));
  CHECK(rc == 0 && n["sesion"]["caballo"].str() == "Zakina" && n["sesion"]["caballo_nombre"].str() == "Zakina");
  // an empty block is the same as no assignment
  json::Value e = parsed(analyse(raw, "{\"asignacion\":{}}", &rc));
  CHECK(rc == 0 && e["sesion"]["identidad"].str() == "RAW");
  // a malformed block is rejected (code 5, invalid options), not silently ignored
  analyse(raw, "{\"asignacion\":\"Zakina\"}", &rc);
  CHECK(rc == 5);
  // the stored analysis is not reused after a reassignment
  EngineConfig c, c2; c2.identity.horse_code = "H_ZAKINA";
  CacheResult r1, r2, r3;
  std::string err;
  CHECK(analyse_cached({raw}, dir, c, "t", false, &r1, &err) && r1.state == "CALCULADO");
  CHECK(analyse_cached({raw}, dir, c2, "t", false, &r2, &err) && r2.state == "CALCULADO" && r2.path != r1.path);
  CHECK(parsed(r2.json)["sesion"]["caballo"].str() == "H_ZAKINA");
  CHECK(analyse_cached({raw}, dir, c2, "t2", false, &r3, &err) && r3.state == "ACIERTO");
  fs::remove_all(dir); remove(raw);
}
