#include "avo_eq/avo_eq_c.h"
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>
#include "avo_eq/dsp.h"
#include "avo_eq/engine.h"
#include "avo_eq/ingestion.h"

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

}  // extern "C"
