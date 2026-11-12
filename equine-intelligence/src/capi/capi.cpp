#include "avo_eq/avo_eq_c.h"
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "avo_eq/dsp.h"
#include "avo_eq/engine.h"
#include "avo_eq/ingestion.h"
#include "avo_eq/compare.h"
#include "avo_eq/json.h"
#include "avo_eq/store.h"
#include <fstream>
#include <memory>
#include <sstream>

static char* dup(const std::string& s) {
  char* p = (char*)std::malloc(s.size() + 1);
  if (p) std::memcpy(p, s.c_str(), s.size() + 1);
  return p;
}
static std::string err_json(const std::string& m) {
  std::string e = "{\"error\":\"";
  for (char c : m) { if (c == '"' || c == '\\') e += '\\'; e += c; }
  return e + "\"}";
}

extern "C" {

AVO_EQ_API const char* avo_eq_version(void) { return avoeq::ENGINE_VERSION; }

static bool load(const char* const* paths, int n, avoeq::Session* s, std::string* err) {
  if (!paths || n <= 0) { *err = "sin ficheros"; return false; }
  std::vector<std::string> v;
  for (int i = 0; i < n; i++) v.push_back(paths[i] ? paths[i] : "");
  return avoeq::ingest_raw(v, s, err);
}

AVO_EQ_API int avo_eq_analyse_files(const char* const* paths, int n, const char* when, int series, char** out) {
  if (!out) return 2;
  try {
    avoeq::Session s; std::string err;
    if (!load(paths, n, &s, &err)) { *out = dup(err_json(err)); return 1; }
    avoeq::EngineConfig c;
    avoeq::Analysis a = avoeq::analyse(s, c, when ? when : "");
    *out = dup(avoeq::to_json(a, s, c, series != 0));
    return 0;
  } catch (const std::exception& e) { *out = dup(err_json(e.what())); return 3; }
}

AVO_EQ_API int avo_eq_export_csv(const char* const* paths, int n, int which, char** out) {
  if (!out) return 2;
  try {
    avoeq::Session s; std::string err;
    if (!load(paths, n, &s, &err)) { *out = dup(err); return 1; }
    avoeq::Analysis a = avoeq::analyse(s);
    *out = dup(which == 0 ? avoeq::gnss_csv(a) : which == 1 ? avoeq::gait_csv(a) : avoeq::cadence_csv(a));
    return 0;
  } catch (const std::exception& e) { *out = dup(e.what()); return 3; }
}

AVO_EQ_API double avo_eq_fundamental(const double* x, int n, double fs, double f_min, double f_max, double* strength) {
  if (!x || n <= 0) return 0;
  std::vector<double> v(x, x + n);
  avoeq::dsp::Fundamental f = avoeq::dsp::fundamental(v, fs, f_min, f_max);
  if (strength) *strength = f.strength;
  return f.freq_hz;
}

AVO_EQ_API void avo_eq_free(char* p) { std::free(p); }

AVO_EQ_API int avo_eq_api_version(void) { return 2; }

}  // extern "C"

namespace {
int fail(char** out, int code, const std::string& m) {
  std::string e = "{\"error\":\"" + avoeq::json::escape(m) + "\",\"codigo\":" + std::to_string(code) + (code == 4 ? ",\"cancelado\":true}" : "}");
  *out = dup(e); return code;
}
struct Opts {
  avoeq::EngineConfig cfg;
  std::unique_ptr<avoeq::GaitModel> model;
  bool series = false, force = false;
  std::string when, cache_dir;
  avoeq::json::Value raw;
};
bool parse_opts(const char* text, Opts* o, std::string* err) {
  if (text && *text) { if (!avoeq::json::parse(text, &o->raw, err)) return false; if (o->raw.type != avoeq::json::Value::OBJ) { *err = "las opciones deben ser un objeto JSON"; return false; } }
  const auto& v = o->raw;
  std::string mode = v["modo"].str("OFFLINE");
  if (mode == "TIEMPO_REAL" || mode == "REALTIME_ANALYSIS") o->cfg.fusion.mode = avoeq::AnalysisMode::REALTIME_ANALYSIS;
  else if (mode != "OFFLINE" && mode != "OFFLINE_ANALYSIS") { *err = "modo desconocido: " + mode; return false; }
  o->series = v["series"].boolean(false);
  o->force = v["forzar"].boolean(false);
  o->when = v["procesado_utc"].str("");
  o->cache_dir = v["cache_dir"].str("");
  std::string cl = v["clasificador_rendimiento"].str("V1");
  if (cl == "V2") o->cfg.performance_uses_v2 = true; else if (cl != "V1") { *err = "clasificador desconocido: " + cl; return false; }
  o->cfg.symmetry.sensors_calibrated = v["sensores_calibrados"].boolean(false);
  std::string mp = v["modelo_aires"].str("");
  if (!mp.empty()) {
    std::ifstream f(mp, std::ios::binary); if (!f) { *err = "no se puede leer el modelo " + mp; return false; }
    std::ostringstream ss; ss << f.rdbuf();
    o->model = avoeq::load_centroid_model(ss.str(), err);
    if (!o->model) return false;
    o->cfg.gait_model = o->model.get();
  }
  return true;
}
std::vector<std::string> paths_of(const char* const* p, int n) { std::vector<std::string> v; for (int i = 0; i < n; i++) v.push_back(p[i] ? p[i] : ""); return v; }
bool selection(const avoeq::json::Value& v, avoeq::Selection* s, std::string* err) {
  if (v.is_null()) return true;
  std::string t = v["tipo"].str("SESION");
  using K = avoeq::Selection;
  if (t == "SESION") s->kind = K::ALL; else if (t == "TIEMPO") s->kind = K::TIME; else if (t == "DISTANCIA") s->kind = K::DISTANCE;
  else if (t == "AIRE") s->kind = K::GAIT; else if (t == "EVENTO") s->kind = K::EVENT; else if (t == "POSICION") s->kind = K::POSITION;
  else { *err = "tipo de selección desconocido: " + t; return false; }
  s->a = v["a"].num(0); s->b = v["b"].num(0); s->event_id = v["evento"].str(""); s->lat = v["lat"].num(0); s->lon = v["lon"].num(0); s->radius_m = v["radio_m"].num(0);
  std::string g = v["aire"].str("");
  for (int k = 0; k <= 6; k++) if (g == avoeq::gait_code((avoeq::Gait)k) || g == avoeq::gait_name((avoeq::Gait)k)) s->gait = (avoeq::Gait)k;
  if (s->kind == K::GAIT && g.empty()) { *err = "selección por aire sin aire"; return false; }
  return true;
}
}  // namespace

extern "C" {

AVO_EQ_API int avo_eq_analyse_ex(const char* const* paths, int n, const char* options, const volatile int* cancel, char** out) {
  if (!out) return 2;
  *out = nullptr;
  if (!paths || n <= 0) return fail(out, 2, "sin ficheros");
  try {
    Opts o; std::string err;
    if (!parse_opts(options, &o, &err)) return fail(out, 5, err);
    o.cfg.cancel = cancel;
    std::vector<std::string> v = paths_of(paths, n);
    if (!o.cache_dir.empty()) {
      avoeq::CacheResult cr;
      if (!avoeq::analyse_cached(v, o.cache_dir, o.cfg, o.when, o.force, &cr, &err)) return fail(out, 1, err);
      // insert the cache state as the first key
      std::string js = cr.json;
      js.insert(1, "\"cache\":\"" + cr.state + "\",\"fichero_resultado\":\"" + avoeq::json::escape(cr.path) + "\",");
      *out = dup(js);
      return 0;
    }
    avoeq::Session s;
    if (!avoeq::ingest_raw(v, &s, &err)) return fail(out, 1, err);
    std::string fp = avoeq::fingerprint_files(v, &err);
    avoeq::Analysis a = avoeq::analyse(s, o.cfg, o.when);
    a.input_fingerprint = fp;
    *out = dup(avoeq::to_json(a, s, o.cfg, o.series));
    return 0;
  } catch (const avoeq::Cancelled&) { return fail(out, 4, "análisis cancelado");
  } catch (const std::exception& e) { return fail(out, 3, e.what()); }
}

AVO_EQ_API int avo_eq_compare_ex(const char* const* pa, int na, const char* const* pb, int nb, const char* options, const volatile int* cancel, char** out) {
  if (!out) return 2;
  *out = nullptr;
  if (!pa || na <= 0 || !pb || nb <= 0) return fail(out, 2, "faltan ficheros de alguna sesión");
  try {
    Opts o; std::string err;
    if (!parse_opts(options, &o, &err)) return fail(out, 5, err);
    o.cfg.cancel = cancel;
    avoeq::Selection sa, sb;
    if (!selection(o.raw["seleccion_a"], &sa, &err) || !selection(o.raw["seleccion_b"], &sb, &err)) return fail(out, 5, err);
    avoeq::Session A, B;
    if (!avoeq::ingest_raw(paths_of(pa, na), &A, &err)) return fail(out, 1, err);
    if (!avoeq::ingest_raw(paths_of(pb, nb), &B, &err)) return fail(out, 1, err);
    avoeq::Analysis xa = avoeq::analyse(A, o.cfg, o.when), xb = avoeq::analyse(B, o.cfg, o.when);
    *out = dup(avoeq::comparison_json(avoeq::compare_sessions(xa, xb, sa, sb, o.raw["mismo_recorrido"].boolean(false))));
    return 0;
  } catch (const avoeq::Cancelled&) { return fail(out, 4, "comparación cancelada");
  } catch (const std::exception& e) { return fail(out, 3, e.what()); }
}

AVO_EQ_API int avo_eq_cache_invalidate(const char* dir) {
  if (!dir) return -1;
  try { return avoeq::cache_invalidate(dir); } catch (...) { return -1; }
}

}  // extern "C"
