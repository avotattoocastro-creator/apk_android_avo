// C API of AVO Training Analytics (see avo_eq_c.h).
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/json.h"
#include "avo_eq/training.h"

namespace {

char* tdup(const std::string& s) {
  char* p = (char*)std::malloc(s.size() + 1);
  if (p) std::memcpy(p, s.c_str(), s.size() + 1);
  return p;
}
int tfail(char** out, int code, const std::string& m) {
  std::string e = "{\"error\":\"" + avoeq::json::escape(m) + "\",\"codigo\":" + std::to_string(code) + (code == 4 ? ",\"cancelado\":true}" : "}");
  *out = tdup(e);
  return code;
}
bool read_file(const std::string& path, std::string* text) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  std::ostringstream ss; ss << f.rdbuf(); *text = ss.str();
  return true;
}
// Fields given by the app take precedence over the ones found in the analysis.
void apply_extra(const avoeq::json::Value& x, avoeq::SessionSummary* s) {
  if (x.type != avoeq::json::Value::OBJ) return;
  if (!x["id"].str().empty()) s->id = x["id"].str();
  if (!x["caballo"].str().empty()) s->horse = x["caballo"].str();
  if (!x["jinete"].str().empty()) s->rider = x["jinete"].str();
  if (!x["fecha_utc"].str().empty()) s->date_utc = x["fecha_utc"].str();
  const avoeq::json::Value& v = x["valoracion"];
  if (v["rpe"].type == avoeq::json::Value::NUM) {
    double r = v["rpe"].n;
    if (r >= 0 && r <= 10) s->rpe = r; else s->warnings.push_back("RPE fuera de 0–10: no se usa");
  }
  if (!v["estado"].str().empty()) s->state = v["estado"].str();
  if (!v["nota"].str().empty()) s->note = v["nota"].str();
  if (!x["pista"]["superficie"].str().empty()) s->surface = x["pista"]["superficie"].str();
  if (!x["pista"]["estado"].str().empty()) s->track_state = x["pista"]["estado"].str();
}

}  // namespace

extern "C" {

AVO_EQ_API int avo_eq_training_summary(const char* analysis_json, const char* extra_json, char** out) {
  if (!out) return 2;
  *out = nullptr;
  if (!analysis_json) return tfail(out, 2, "falta el análisis");
  try {
    avoeq::json::Value a, x;
    std::string err;
    if (!avoeq::json::parse(analysis_json, &a, &err)) return tfail(out, 1, "análisis no válido: " + err);
    if (extra_json && *extra_json && !avoeq::json::parse(extra_json, &x, &err)) return tfail(out, 5, "datos extra no válidos: " + err);
    avoeq::TrainingConfig c;
    avoeq::SessionSummary s;
    if (!avoeq::training_summary_from_analysis(a, c, &s, &err)) return tfail(out, 1, err);
    apply_extra(x, &s);
    *out = tdup(avoeq::training_summary_to_json(s));
    return 0;
  } catch (const std::exception& e) { return tfail(out, 3, e.what()); }
}

AVO_EQ_API int avo_eq_training_analyse(const char* input_json, const char* options_json, const volatile int* cancel, char** out) {
  if (!out) return 2;
  *out = nullptr;
  if (!input_json) return tfail(out, 2, "falta la entrada");
  try {
    avoeq::json::Value in, opt;
    std::string err;
    if (!avoeq::json::parse(input_json, &in, &err)) return tfail(out, 2, "entrada no válida: " + err);
    if (options_json && *options_json && !avoeq::json::parse(options_json, &opt, &err)) return tfail(out, 5, "opciones no válidas: " + err);
    avoeq::TrainingConfig c;
    if (!avoeq::training_config_from_json(opt, &c, &err)) return tfail(out, 5, err);
    const avoeq::json::Value& list = in["sesiones"];
    if (list.type != avoeq::json::Value::ARR) return tfail(out, 2, "falta la lista «sesiones»");
    std::string horse = in["caballo"].str();
    std::vector<avoeq::SessionSummary> sessions;
    std::vector<std::string> warnings;
    int other_horse = 0;
    for (size_t i = 0; i < list.a.size(); i++) {
      if (cancel && *cancel) return tfail(out, 4, "análisis cancelado");
      const avoeq::json::Value& e = list.a[i];
      avoeq::SessionSummary s;
      std::string label = "sesión " + std::to_string(i + 1), text, e2;
      bool ok = false;
      if (e["resumen"].type == avoeq::json::Value::OBJ) ok = avoeq::training_summary_from_json(e["resumen"], &s, &e2);
      else if (e["analisis"].type == avoeq::json::Value::OBJ) ok = avoeq::training_summary_from_analysis(e["analisis"], c, &s, &e2);
      else if (!e["ruta_resumen"].str().empty() || !e["ruta_analisis"].str().empty()) {
        bool is_summary = !e["ruta_resumen"].str().empty();
        std::string path = is_summary ? e["ruta_resumen"].str() : e["ruta_analisis"].str();
        avoeq::json::Value v;
        if (!read_file(path, &text)) e2 = "no se puede leer " + path;
        else if (!avoeq::json::parse(text, &v, &e2)) e2 = path + ": " + e2;
        else ok = is_summary ? avoeq::training_summary_from_json(v, &s, &e2) : avoeq::training_summary_from_analysis(v, c, &s, &e2);
      } else e2 = "sin «resumen», «analisis», «ruta_resumen» ni «ruta_analisis»";
      if (!ok) { warnings.push_back(label + " descartada: " + e2); continue; }
      apply_extra(e, &s);
      if (!horse.empty() && !s.horse.empty() && s.horse != horse) { other_horse++; continue; }
      if (s.horse.empty()) s.horse = horse;
      sessions.push_back(s);
    }
    if (other_horse) warnings.push_back(std::to_string(other_horse) + " sesiones de otro caballo no se usan");
    avoeq::TrainingResult r = avoeq::analyse_training(sessions, in["fecha_referencia"].str(), c);
    if (r.horse.empty()) r.horse = horse;
    r.warnings.insert(r.warnings.begin(), warnings.begin(), warnings.end());
    *out = tdup(avoeq::training_to_json(r, c));
    return 0;
  } catch (const std::exception& e) { return tfail(out, 3, e.what()); }
}

}  // extern "C"
