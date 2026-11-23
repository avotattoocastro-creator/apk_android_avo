// C API of AVO PPK (see avo_eq_c.h).
#include <cstdlib>
#include <cstring>
#include <sstream>
#include <string>
#include <vector>
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/json.h"
#include "avo_eq/ppk.h"

namespace {
char* pdup(const std::string& s) {
  char* p = (char*)std::malloc(s.size() + 1);
  if (p) std::memcpy(p, s.c_str(), s.size() + 1);
  return p;
}
int pfail(char** out, int code, const std::string& m) {
  *out = pdup("{\"error\":\"" + avoeq::json::escape(m) + "\",\"codigo\":" + std::to_string(code) + (code == 4 ? ",\"cancelado\":true}" : "}"));
  return code;
}
bool list(const char* const* p, int n, std::vector<std::string>* v) {
  if (n < 0 || (n > 0 && !p)) return false;
  for (int i = 0; i < n; i++) { if (!p[i]) return false; v->push_back(p[i]); }
  return true;
}
std::string rover_json(const avoeq::PpkRoverStats& r) {
  std::ostringstream o;
  o << "{\"tramas_troceadas\":" << r.frag_frames << ",\"mensajes_perdidos\":" << r.frag_incomplete << ",\"tramas_enteras\":" << r.whole_frames
    << ",\"rawx\":" << r.rawx << ",\"sfrbx\":" << r.sfrbx << ",\"bytes\":" << r.bytes << "}";
  return o.str();
}
}  // namespace

extern "C" {

AVO_EQ_API int avo_eq_ppk_need(const char* const* paths, int n, char** out) {
  if (!out) return 2;
  *out = nullptr;
  std::vector<std::string> seg;
  if (!list(paths, n, &seg) || seg.empty()) return pfail(out, 2, "faltan los segmentos de la sesión");
  try {
    std::vector<uint8_t> ubx;
    avoeq::PpkRoverStats st;
    std::string err;
    if (!avoeq::ppk_extract_ubx(seg, &ubx, &st, &err)) return pfail(out, 1, err);
    avoeq::PpkNeed need;
    bool ok = !ubx.empty() && avoeq::ppk_need(ubx, &need);
    std::ostringstream o;
    o.setf(std::ios::fixed);
    o.precision(7);
    o << "{\"formato\":\"avo-ppk-necesita\",\"version\":\"1.0.0\",\"tiene_rawx\":" << (ok && need.has_raw ? "true" : "false")
      << ",\"rawx\":" << need.rawx << ",\"inicio_utc\":\"" << need.start_utc << "\",\"fin_utc\":\"" << need.end_utc
      << "\",\"lat\":" << need.lat_deg << ",\"lon\":" << need.lon_deg << ",\"rover\":" << rover_json(st) << "}";
    *out = pdup(o.str());
    return 0;
  } catch (...) {
    return pfail(out, 3, "error interno");
  }
}

AVO_EQ_API int avo_eq_ppk(const char* const* paths, int n, const char* const* base_paths, int nb, const char* options_json,
                          const volatile int* cancel, char** out) {
  if (!out) return 2;
  *out = nullptr;
  std::vector<std::string> seg, base;
  if (!list(paths, n, &seg) || seg.empty()) return pfail(out, 2, "faltan los segmentos de la sesión");
  if (!list(base_paths, nb, &base) || base.empty()) return pfail(out, 2, "faltan los ficheros RINEX de la base");
  try {
    avoeq::PpkOptions o;
    bool epochs = true;
    if (options_json && *options_json) {
      avoeq::json::Value v;
      std::string err;
      if (!avoeq::json::parse(options_json, &v, &err)) return pfail(out, 5, "opciones no válidas: " + err);
      using V = avoeq::json::Value;
      if (v["elev_min"].type == V::NUM) o.elev_min_deg = v["elev_min"].n;
      if (v["frecuencias"].type == V::NUM) o.freqs = (int)v["frecuencias"].n;
      if (v["glonass_ar"].type == V::BOOL) o.glonass_ar = v["glonass_ar"].b;
      if (v["fix_and_hold"].type == V::BOOL) o.fix_and_hold = v["fix_and_hold"].b;
      if (v["ratio"].type == V::NUM) o.ar_ratio = v["ratio"].n;
      if (v["edad_max_s"].type == V::NUM) o.max_age_s = v["edad_max_s"].n;
      if (v["combinar"].type == V::BOOL) o.combine = v["combinar"].b;
      if (v["epocas"].type == V::BOOL) epochs = v["epocas"].b;
      if (!v["dir_trabajo"].str().empty()) o.work_dir = v["dir_trabajo"].str();
      const V& xyz = v["base_xyz"];
      if (xyz.type == V::ARR && xyz.a.size() == 3) { o.have_base_xyz = true; for (int i = 0; i < 3; i++) o.base_xyz[i] = xyz.a[(size_t)i].num(); }
      if (o.elev_min_deg < 0 || o.elev_min_deg > 60 || o.freqs < 1 || o.freqs > 3 || o.ar_ratio < 1 || o.max_age_s <= 0)
        return pfail(out, 5, "opciones fuera de rango");
    }
    avoeq::PpkResult r;
    std::vector<uint8_t> ubx;
    std::string err;
    if (!avoeq::ppk_extract_ubx(seg, &ubx, &r.rover, &err)) return pfail(out, 1, err);
    if (ubx.empty()) return pfail(out, 1, "la sesión no tiene datos RAWX: hace falta la espalda 3.16.0 o posterior");
    if (!avoeq::ppk_solve(ubx, base, o, &r, &err, cancel)) return pfail(out, (cancel && *cancel) ? 4 : 1, err);
    *out = pdup(avoeq::ppk_result_json(r, epochs));
    return 0;
  } catch (...) {
    return pfail(out, 3, "error interno");
  }
}

}  // extern "C"
