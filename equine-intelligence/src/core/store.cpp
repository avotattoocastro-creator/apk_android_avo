#include "avo_eq/store.h"
#include "avo_eq/ingestion.h"
#include "avo_eq/json.h"
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <sstream>

namespace fs = std::filesystem;

namespace avoeq {

std::string fingerprint_files(const std::vector<std::string>& paths, std::string* err) {
  uint64_t h = 1469598103934665603ull;
  auto mix = [&](const uint8_t* p, size_t n) { for (size_t i = 0; i < n; i++) { h ^= p[i]; h *= 1099511628211ull; } };
  std::vector<uint8_t> buf(1 << 16);
  for (auto& p : paths) {
    FILE* f = fopen(p.c_str(), "rb");
    if (!f) { if (err) *err = "no se puede leer " + p; return ""; }
    uint64_t size = 0; size_t n;
    while ((n = fread(buf.data(), 1, buf.size(), f)) > 0) { mix(buf.data(), n); size += n; }
    fclose(f);
    mix((const uint8_t*)&size, sizeof(size));
  }
  char out[20]; snprintf(out, sizeof(out), "%016llx", (unsigned long long)h);
  return out;
}

static bool read_file(const std::string& p, std::string* s) {
  std::ifstream f(p, std::ios::binary); if (!f) return false;
  std::ostringstream o; o << f.rdbuf(); *s = o.str(); return true;
}

static bool versions_match(const json::Value& v) {
  if (v["motor"].str() != ENGINE_VERSION) return false;
  const json::Value& al = v["procedencia"]["algoritmos"];
  auto cur = algorithm_versions();
  if (al.type != json::Value::OBJ || al.o.size() != cur.size()) return false;
  for (auto& kv : cur) if (al[kv.first].str() != kv.second) return false;
  return true;
}

bool analyse_cached(const std::vector<std::string>& segments, const std::string& dir, const EngineConfig& c,
                    const std::string& when, bool force, CacheResult* out, std::string* err) {
  std::string fp = fingerprint_files(segments, err);
  if (fp.empty()) return false;
  std::string ph = params_hash(c);
  std::error_code ec;
  fs::create_directories(dir, ec);
  if (ec) { if (err) *err = "no se puede crear el directorio de análisis: " + dir; return false; }
  std::string file = (fs::path(dir) / ("analisis_" + fp + "_" + ph + ".json")).string();
  bool existed = fs::exists(file, ec);
  if (existed && !force) {
    std::string text; json::Value v;
    if (read_file(file, &text) && json::parse(text, &v) && versions_match(v) && v["procedencia"]["huella_entrada"].str() == fp &&
        v["procedencia"]["hash_parametros"].str() == ph) {
      out->json = text; out->state = "ACIERTO"; out->path = file; return true;
    }
  }
  Session s;
  if (!ingest_raw(segments, &s, err)) return false;
  Analysis a = analyse(s, c, when);
  a.input_fingerprint = fp;
  std::string js = to_json(a, s, c, true);
  std::string tmp = file + ".tmp";
  { std::ofstream f(tmp, std::ios::binary); if (!f) { if (err) *err = "no se puede escribir " + tmp; return false; } f << js; }
  fs::rename(tmp, file, ec);
  if (ec) { if (err) *err = "no se puede guardar " + file; return false; }
  out->json = js; out->state = existed ? "RECALCULADO" : "CALCULADO"; out->path = file;
  return true;
}

std::vector<CacheEntry> cache_list(const std::string& dir) {
  std::vector<CacheEntry> out;
  std::error_code ec;
  if (!fs::is_directory(dir, ec)) return out;
  for (auto& e : fs::directory_iterator(dir, ec)) {
    std::string name = e.path().filename().string();
    if (name.rfind("analisis_", 0) != 0 || e.path().extension() != ".json") continue;
    CacheEntry c; c.file = e.path().string();
    std::string text; json::Value v;
    if (read_file(c.file, &text) && json::parse(text, &v)) {
      c.session = v["sesion"]["id"].str(); c.engine = v["motor"].str(); c.processed_at = v["procesado_utc"].str();
      c.fingerprint = v["procedencia"]["huella_entrada"].str(); c.params = v["procedencia"]["hash_parametros"].str();
      c.valid = versions_match(v);
    }
    out.push_back(c);
  }
  return out;
}

int cache_invalidate(const std::string& dir) {
  int n = 0; std::error_code ec;
  for (auto& c : cache_list(dir)) if (!c.valid && fs::remove(c.file, ec)) n++;
  return n;
}

}  // namespace avoeq
