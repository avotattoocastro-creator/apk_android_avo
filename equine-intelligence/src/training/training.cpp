// AVO Training Analytics (fase 1). Ver include/avo_eq/training.h y docs/algoritmos/12_ENTRENAMIENTO.md.
#include "avo_eq/training.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <functional>
#include <map>
#include <set>
#include <sstream>

namespace avoeq {

const char* tgait_name(TGait g) {
  switch (g) { case TGait::WALK: return "PASO"; case TGait::TROT: return "TROTE"; case TGait::CANTER: return "GALOPE"; default: return "?"; }
}

namespace {

const double kNaN = std::nan("");

std::string num(double v) {
  if (std::isnan(v) || std::isinf(v)) return "null";
  char b[40]; snprintf(b, sizeof(b), "%.6g", v); return b;
}
std::string q(const std::string& s) { return "\"" + json::escape(s) + "\""; }

// Numbers that may be null in the analysis JSON.
double nnum(const json::Value& v) { return v.type == json::Value::NUM ? v.n : kNaN; }

int gait_index(const std::string& code) {
  if (code == "WALK" || code == "PASO") return 0;
  if (code == "TROT" || code == "TROTE") return 1;
  if (code == "CANTER_GALLOP" || code == "GALOPE") return 2;
  return -1;
}

double median(std::vector<double> v) {
  if (v.empty()) return kNaN;
  std::sort(v.begin(), v.end());
  size_t n = v.size();
  return n % 2 ? v[n / 2] : 0.5 * (v[n / 2 - 1] + v[n / 2]);
}
double percentile(std::vector<double> v, double p) {   // linear interpolation, p in [0,1]
  if (v.empty()) return kNaN;
  std::sort(v.begin(), v.end());
  double x = p * (v.size() - 1);
  size_t i = (size_t)std::floor(x);
  if (i + 1 >= v.size()) return v.back();
  return v[i] + (x - i) * (v[i + 1] - v[i]);
}
// Median weighted by duration (values with NaN are skipped).
double weighted_median(std::vector<std::pair<double, double>> vw) {
  vw.erase(std::remove_if(vw.begin(), vw.end(), [](const std::pair<double, double>& p) {
             return std::isnan(p.first) || !(p.second > 0); }), vw.end());
  if (vw.empty()) return kNaN;
  std::sort(vw.begin(), vw.end());
  double total = 0; for (auto& p : vw) total += p.second;
  double acc = 0;
  for (size_t i = 0; i < vw.size(); i++) {
    acc += vw[i].second;
    if (acc >= total / 2 - 1e-12) {
      if (std::fabs(acc - total / 2) < 1e-9 && i + 1 < vw.size()) return 0.5 * (vw[i].first + vw[i + 1].first);
      return vw[i].first;
    }
  }
  return vw.back().first;
}

// Civil date <-> days since 1970-01-01 (H. Hinnant's algorithm).
long days_from_civil(long y, unsigned m, unsigned d) {
  y -= m <= 2;
  const long era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (long)doe - 719468;
}
void civil_from_days(long z, long* y, unsigned* m, unsigned* d) {
  z += 719468;
  const long era = (z >= 0 ? z : z - 146096) / 146097;
  const unsigned doe = (unsigned)(z - era * 146097);
  const unsigned yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
  const unsigned doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
  const unsigned mp = (5 * doy + 2) / 153;
  *d = doy - (153 * mp + 2) / 5 + 1;
  *m = mp < 10 ? mp + 3 : mp - 9;
  *y = (long)yoe + era * 400 + (*m <= 2);
}

struct MetricDef { const char* key; double GaitSummary::*field; bool raises_level; int worse; double floor_abs; };
// worse: +1 higher is worse, -1 lower is worse, 0 both directions matter. Speed is the rider's choice: informative only.
const MetricDef kMetrics[] = {
    {"velocidad_media", &GaitSummary::speed_mean, false, 0, 0.05},
    {"longitud_tranco_m", &GaitSummary::stride_length_m, true, 0, 0.03},
    {"cadencia_hz", &GaitSummary::cadence_hz, true, 0, 0.01},
    {"correlacion_ciclos", &GaitSummary::cycle_corr, true, -1, 0.01},
    {"cv_intervalos", &GaitSummary::interval_cv, true, +1, 0.005},
};

int level_rank(const std::string& l) { return l == "REVISAR" ? 2 : l == "VIGILAR" ? 1 : 0; }
void raise(std::string* level, const std::string& to) { if (level_rank(to) > level_rank(*level)) *level = to; }

std::string upper_ascii(std::string s) { for (auto& c : s) if (c >= 'a' && c <= 'z') c = (char)(c - 32); return s; }

}  // namespace

// ------------------------------------------------------------------ dates
bool training_parse_day(const std::string& iso, long* day) {
  int y = 0, m = 0, d = 0;
  if (iso.size() < 10 || sscanf(iso.c_str(), "%4d-%2d-%2d", &y, &m, &d) != 3) return false;
  if (y < 1970 || y > 9999 || m < 1 || m > 12 || d < 1 || d > 31) return false;
  static const int mdays[] = {31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31};
  if (d > mdays[m - 1]) return false;
  bool leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0;
  if (m == 2 && d == 29 && !leap) return false;
  *day = days_from_civil(y, (unsigned)m, (unsigned)d);
  return true;
}
std::string training_day_text(long day) {
  long y; unsigned m, d; civil_from_days(day, &y, &m, &d);
  char b[40]; snprintf(b, sizeof(b), "%04ld-%02u-%02u", y, m, d); return b;
}

// ------------------------------------------------------------------ session summary
bool training_summary_from_analysis(const json::Value& a, const TrainingConfig& c, SessionSummary* out, std::string* err) {
  if (a.type != json::Value::OBJ || a["formato"].str() != "avo-equine-analysis") {
    if (err) *err = "no es un análisis avo-equine-analysis";
    return false;
  }
  SessionSummary s;
  const json::Value& ses = a["sesion"];
  s.id = ses["id"].str(); s.horse = ses["caballo"].str(); s.rider = ses["jinete"].str();
  s.date_utc = ses["inicio_utc"].str();
  s.has_imu = a["procedencia"]["tiene_cincha"].boolean(false);

  // Per-gait segments (rendimiento, format v2). Fallback: gait segments of v1 (durations only).
  std::vector<std::pair<double, double>> wm[3][4];   // stride, cadence, corr, cv : (value, duration)
  double speed_wsum[3] = {0, 0, 0}, speed_w[3] = {0, 0, 0};
  const json::Value& segs = a["rendimiento"]["segmentos"];
  bool have_perf = segs.type == json::Value::ARR;
  if (have_perf) {
    for (const auto& g : segs.a) {
      int gi = gait_index(g["codigo"].str());
      double dur = g["duracion_s"].num(0);
      std::string code = g["codigo"].str();
      if (gi < 0) { if (code == "TRANSITION") s.moving_s += dur; continue; }
      s.moving_s += dur;
      GaitSummary& G = s.gait[gi];
      G.duration_s += dur;
      double dist = nnum(g["distancia_m"]);
      if (!std::isnan(dist)) G.distance_m += dist;
      bool gnss_ok = g["calidad_gnss"].str() != "NO_UTILIZABLE";
      double v = nnum(g["velocidad_media"]), vmax = nnum(g["velocidad_max"]);
      if (gnss_ok && !std::isnan(v) && dur > 0) { speed_wsum[gi] += v * dur; speed_w[gi] += dur; }
      if (gnss_ok && !std::isnan(vmax) && (std::isnan(G.speed_max) || vmax > G.speed_max)) G.speed_max = vmax;
      if (gnss_ok && !std::isnan(v) && v > c.high_speed_m_s && !std::isnan(dist)) s.high_speed_m += dist;
      bool imu_ok = g["calidad_imu"].str() != "NO_UTILIZABLE";
      if (gnss_ok) wm[gi][0].push_back({nnum(g["longitud_tranco_m"]), dur});
      if (imu_ok) {
        wm[gi][1].push_back({nnum(g["cadencia_media_hz"]), dur});
        wm[gi][2].push_back({nnum(g["correlacion_ciclos"]), dur});
        wm[gi][3].push_back({nnum(g["cv_intervalos"]), dur});
      }
    }
    double d = nnum(a["rendimiento"]["sesion"]["distancia_m"]);
    if (!std::isnan(d)) s.distance_m = d;
    else for (auto& G : s.gait) s.distance_m += G.distance_m;
  } else {
    s.warnings.push_back("análisis sin bloque «rendimiento» (formato 1): solo tiempos por aire");
    for (const auto& g : a["aires"]["segmentos"].a) {
      int gi = gait_index(g["codigo"].str().empty() ? g["aire"].str() : g["codigo"].str());
      double dur = g["t1"].num(0) - g["t0"].num(0);
      if (dur <= 0) continue;
      if (gi >= 0) { s.gait[gi].duration_s += dur; s.moving_s += dur; }
    }
  }
  // High-speed distance from the speed series when present (more exact than whole segments).
  const json::Value& st = a["series"]["t"];
  const json::Value& sv = a["series"]["velocidad"];
  if (st.type == json::Value::ARR && sv.type == json::Value::ARR && st.a.size() == sv.a.size() && st.a.size() > 1) {
    double hs = 0;
    for (size_t i = 1; i < st.a.size(); i++) {
      double dt = nnum(st.a[i]) - nnum(st.a[i - 1]), v0 = nnum(sv.a[i - 1]), v1 = nnum(sv.a[i]);
      if (std::isnan(dt) || dt <= 0 || dt > 2 || std::isnan(v0) || std::isnan(v1)) continue;
      double vm = 0.5 * (v0 + v1);
      if (vm > c.high_speed_m_s) hs += vm * dt;
    }
    s.high_speed_m = hs;
  }
  for (int gi = 0; gi < 3; gi++) {
    GaitSummary& G = s.gait[gi];
    if (G.duration_s < c.min_gait_seconds) continue;   // too little time to judge stride, cadence or regularity
    if (speed_w[gi] > 0) G.speed_mean = speed_wsum[gi] / speed_w[gi];
    G.stride_length_m = weighted_median(wm[gi][0]);
    G.cadence_hz = weighted_median(wm[gi][1]);
    G.cycle_corr = weighted_median(wm[gi][2]);
    G.interval_cv = weighted_median(wm[gi][3]);
  }
  for (const auto& G : s.gait) if (!std::isnan(G.speed_max) && (std::isnan(s.speed_max) || G.speed_max > s.speed_max)) s.speed_max = G.speed_max;

  // GNSS trajectory accelerations (only usable quality).
  for (const auto& e : a["cinematica"]["eventos"].a) {
    std::string qq = e["calidad"].str();
    if (qq == "NO_UTILIZABLE" || qq == "BAJA") continue;
    std::string t = e["tipo"].str();
    double pk = std::fabs(e["pico_m_s2"].num(0));
    if (t == "ACELERACION_SOSTENIDA") s.accel_events++;
    else if (t == "DESACELERACION_SOSTENIDA") s.decel_events++;
    else if (t == "PICO_LATERAL") s.lateral_peaks++;
    if (t == "ACELERACION_SOSTENIDA" || t == "PICO_ACELERACION") { if (std::isnan(s.accel_peak) || pk > s.accel_peak) s.accel_peak = pk; }
    if (t == "DESACELERACION_SOSTENIDA" || t == "PICO_DESACELERACION") { if (std::isnan(s.decel_peak) || pk > s.decel_peak) s.decel_peak = pk; }
  }
  for (const auto& qv : a["calidad"].a) {
    if (qv["dominio"].str() == "GNSS") s.gnss_quality = qv["nivel"].str();
    if (qv["dominio"].str() == "IMU") s.imu_quality = qv["nivel"].str();
  }
  if (s.gnss_quality == "NO_UTILIZABLE") s.warnings.push_back("GNSS no utilizable: distancias y velocidades no fiables");
  if (!s.has_imu) s.warnings.push_back("sesión sin cincha: sin cadencia ni regularidad");
  *out = s;
  return true;
}

std::string training_summary_to_json(const SessionSummary& s) {
  std::ostringstream o;
  o << "{\"formato\":\"avo-training-session\",\"version_formato\":1,\"version\":\"" << TRAINING_VERSION << "\",\"id\":" << q(s.id)
    << ",\"caballo\":" << q(s.horse) << ",\"jinete\":" << q(s.rider) << ",\"fecha_utc\":" << (s.date_utc.empty() ? "null" : q(s.date_utc))
    << ",\"tiempo_movimiento_s\":" << num(s.moving_s) << ",\"distancia_m\":" << num(s.distance_m) << ",\"velocidad_max\":" << num(s.speed_max)
    << ",\"distancia_alta_velocidad_m\":" << num(s.high_speed_m) << ",\"tiene_cincha\":" << (s.has_imu ? "true" : "false") << ",\"aires\":{";
  for (int gi = 0; gi < 3; gi++) {
    const GaitSummary& G = s.gait[gi];
    o << (gi ? "," : "") << q(tgait_name((TGait)gi)) << ":{\"duracion_s\":" << num(G.duration_s) << ",\"distancia_m\":" << num(G.distance_m)
      << ",\"velocidad_media\":" << num(G.speed_mean) << ",\"velocidad_max\":" << num(G.speed_max) << ",\"longitud_tranco_m\":" << num(G.stride_length_m)
      << ",\"cadencia_hz\":" << num(G.cadence_hz) << ",\"correlacion_ciclos\":" << num(G.cycle_corr) << ",\"cv_intervalos\":" << num(G.interval_cv) << "}";
  }
  o << "},\"aceleraciones\":{\"sostenidas\":" << s.accel_events << ",\"frenadas_sostenidas\":" << s.decel_events << ",\"picos_laterales\":" << s.lateral_peaks
    << ",\"pico_aceleracion_m_s2\":" << num(s.accel_peak) << ",\"pico_frenada_m_s2\":" << num(s.decel_peak) << ",\"fuente\":\"TRAYECTORIA_GNSS\"}"
    << ",\"calidad\":{\"gnss\":" << q(s.gnss_quality) << ",\"imu\":" << q(s.imu_quality) << "}"
    << ",\"valoracion\":{\"rpe\":" << num(s.rpe) << ",\"estado\":" << q(s.state) << ",\"nota\":" << q(s.note) << "}"
    << ",\"pista\":{\"superficie\":" << q(s.surface) << ",\"estado\":" << q(s.track_state) << "},\"avisos\":[";
  for (size_t i = 0; i < s.warnings.size(); i++) o << (i ? "," : "") << q(s.warnings[i]);
  o << "]}";
  return o.str();
}

bool training_summary_from_json(const json::Value& v, SessionSummary* out, std::string* err) {
  if (v.type != json::Value::OBJ || v["formato"].str() != "avo-training-session") { if (err) *err = "no es un resumen avo-training-session"; return false; }
  SessionSummary s;
  s.id = v["id"].str(); s.horse = v["caballo"].str(); s.rider = v["jinete"].str(); s.date_utc = v["fecha_utc"].str();
  s.moving_s = v["tiempo_movimiento_s"].num(0); s.distance_m = v["distancia_m"].num(0); s.speed_max = nnum(v["velocidad_max"]);
  s.high_speed_m = v["distancia_alta_velocidad_m"].num(0); s.has_imu = v["tiene_cincha"].boolean(false);
  for (int gi = 0; gi < 3; gi++) {
    const json::Value& g = v["aires"][tgait_name((TGait)gi)];
    GaitSummary& G = s.gait[gi];
    G.duration_s = g["duracion_s"].num(0); G.distance_m = g["distancia_m"].num(0);
    G.speed_mean = nnum(g["velocidad_media"]); G.speed_max = nnum(g["velocidad_max"]); G.stride_length_m = nnum(g["longitud_tranco_m"]);
    G.cadence_hz = nnum(g["cadencia_hz"]); G.cycle_corr = nnum(g["correlacion_ciclos"]); G.interval_cv = nnum(g["cv_intervalos"]);
  }
  const json::Value& ac = v["aceleraciones"];
  s.accel_events = (int)ac["sostenidas"].num(0); s.decel_events = (int)ac["frenadas_sostenidas"].num(0); s.lateral_peaks = (int)ac["picos_laterales"].num(0);
  s.accel_peak = nnum(ac["pico_aceleracion_m_s2"]); s.decel_peak = nnum(ac["pico_frenada_m_s2"]);
  s.gnss_quality = v["calidad"]["gnss"].str(); s.imu_quality = v["calidad"]["imu"].str();
  s.rpe = nnum(v["valoracion"]["rpe"]); s.state = v["valoracion"]["estado"].str(); s.note = v["valoracion"]["nota"].str();
  s.surface = v["pista"]["superficie"].str(); s.track_state = v["pista"]["estado"].str();
  for (const auto& w : v["avisos"].a) s.warnings.push_back(w.str());
  *out = s;
  return true;
}

// ------------------------------------------------------------------ configuration
bool training_config_from_json(const json::Value& v, TrainingConfig* c, std::string* err) {
  if (v.is_null()) return true;
  if (v.type != json::Value::OBJ) { if (err) *err = "las opciones deben ser un objeto JSON"; return false; }
  struct D { const char* k; double* p; double lo, hi; };
  const D ds[] = {{"factor_paso", &c->factor_walk, 0, 100}, {"factor_trote", &c->factor_trot, 0, 100}, {"factor_galope", &c->factor_canter, 0, 100},
                  {"alta_velocidad_m_s", &c->high_speed_m_s, 1, 30}, {"factor_alta_velocidad", &c->factor_high_speed, 0, 100},
                  {"acwr_alto", &c->acwr_high, 0.5, 5}, {"acwr_bajo", &c->acwr_low, 0, 2}, {"monotonia_alta", &c->monotony_high, 0.5, 20},
                  {"z_vigilar", &c->z_watch, 0.5, 10}, {"z_revisar", &c->z_review, 0.5, 20}, {"min_segundos_aire", &c->min_gait_seconds, 0, 3600}};
  for (const auto& d : ds) {
    if (!v.has(d.k)) continue;
    const json::Value& x = v[d.k];
    if (x.type != json::Value::NUM || !(x.n >= d.lo && x.n <= d.hi)) { if (err) *err = std::string("opción fuera de rango: ") + d.k; return false; }
    *d.p = x.n;
  }
  struct I { const char* k; int* p; int lo, hi; };
  const I is[] = {{"dias_aguda", &c->acute_days, 1, 60}, {"dias_cronica", &c->chronic_days, 7, 180}, {"dias_linea_base", &c->baseline_days, 7, 730},
                  {"min_sesiones_linea_base", &c->baseline_min_sessions, 3, 100}, {"dias_tendencia", &c->trend_days, 14, 730},
                  {"min_sesiones_tendencia", &c->trend_min_sessions, 3, 100}, {"dias_descanso_aviso", &c->rest_watch_days, 1, 365}};
  for (const auto& d : is) {
    if (!v.has(d.k)) continue;
    const json::Value& x = v[d.k];
    if (x.type != json::Value::NUM || x.n != std::floor(x.n) || x.n < d.lo || x.n > d.hi) { if (err) *err = std::string("opción fuera de rango: ") + d.k; return false; }
    *d.p = (int)x.n;
  }
  if (c->acute_days >= c->chronic_days) { if (err) *err = "dias_aguda debe ser menor que dias_cronica"; return false; }
  if (c->z_watch >= c->z_review) { if (err) *err = "z_vigilar debe ser menor que z_revisar"; return false; }
  if (c->acwr_low >= c->acwr_high) { if (err) *err = "acwr_bajo debe ser menor que acwr_alto"; return false; }
  return true;
}

// ------------------------------------------------------------------ analysis
namespace {

double external_load(const SessionSummary& s, const TrainingConfig& c) {
  return s.gait[0].duration_s / 60.0 * c.factor_walk + s.gait[1].duration_s / 60.0 * c.factor_trot +
         s.gait[2].duration_s / 60.0 * c.factor_canter + s.high_speed_m / 100.0 * c.factor_high_speed;
}

struct Baseline { double med = kNaN, mad = kNaN; int n = 0; };
Baseline baseline_of(const std::vector<double>& vals) {
  Baseline b; b.n = (int)vals.size();
  if (vals.empty()) return b;
  b.med = median(vals);
  std::vector<double> dev; dev.reserve(vals.size());
  for (double x : vals) dev.push_back(std::fabs(x - b.med));
  b.mad = median(dev);
  return b;
}

// Load windows at day d. loads: day -> load; first_day: first day of the history.
void windows_at(long d, const std::map<long, double>& loads, const std::map<long, double>& srpe, const std::map<long, int>& missing_rpe,
                long first_day, const TrainingConfig& c, SessionLoad* L, std::vector<std::string>* notes) {
  double acute = 0, chronic = 0, acute_s = 0, chronic_s = 0;
  int miss_chronic = 0;
  std::vector<double> week;
  for (long k = d - c.chronic_days + 1; k <= d; k++) {
    auto it = loads.find(k);
    double l = it == loads.end() ? 0 : it->second;
    chronic += l;
    auto is = srpe.find(k);
    double ls = is == srpe.end() ? 0 : is->second;
    chronic_s += ls;
    auto im = missing_rpe.find(k);
    if (im != missing_rpe.end()) miss_chronic += im->second;
    if (k > d - c.acute_days) { acute += l; acute_s += ls; week.push_back(l); }
  }
  double weeks = c.chronic_days / 7.0, acute_weeks = c.acute_days / 7.0;
  L->acute = acute;
  L->chronic_weekly = chronic / weeks;
  bool covered = first_day <= d - c.chronic_days + 1;
  if (covered && L->chronic_weekly > 0) L->acwr = (acute / acute_weeks) / L->chronic_weekly;
  else if (notes && !covered) notes->push_back("historia menor de " + std::to_string(c.chronic_days) + " días: sin ACWR");
  if (miss_chronic == 0 && chronic_s > 0) {
    L->acute_srpe = acute_s; L->chronic_weekly_srpe = chronic_s / weeks;
    if (covered && L->chronic_weekly_srpe > 0) L->acwr_srpe = (acute_s / acute_weeks) / L->chronic_weekly_srpe;
  }
  // Foster monotony over the acute window (days without training count as 0).
  double mean = 0; for (double x : week) mean += x; mean /= week.size();
  double var = 0; for (double x : week) var += (x - mean) * (x - mean); var /= week.size();
  double sd = std::sqrt(var);
  if (sd > 1e-9 && mean > 0) { L->monotony = mean / sd; L->strain = acute * L->monotony; }
}

void load_flags(const SessionLoad& L, const TrainingConfig& c, std::string* level, std::vector<std::string>* reasons) {
  char b[200];
  if (!std::isnan(L.acwr) && L.acwr > c.acwr_high) {
    snprintf(b, sizeof(b), "carga de los últimos %d días %.2f veces la habitual (ACWR > %.2f): subida brusca", c.acute_days, L.acwr, c.acwr_high);
    raise(level, "VIGILAR"); reasons->push_back(b);
  }
  if (!std::isnan(L.acwr_srpe) && L.acwr_srpe > c.acwr_high) {
    snprintf(b, sizeof(b), "carga percibida (sRPE) %.2f veces la habitual", L.acwr_srpe);
    raise(level, "VIGILAR"); reasons->push_back(b);
  }
  if (!std::isnan(L.monotony) && L.monotony > c.monotony_high) {
    snprintf(b, sizeof(b), "entrenamientos muy parecidos día tras día (monotonía %.2f > %.2f)", L.monotony, c.monotony_high);
    raise(level, "VIGILAR"); reasons->push_back(b);
  }
}

double theil_sen(const std::vector<std::pair<double, double>>& xy, double* lo, double* hi) {
  std::vector<double> slopes;
  for (size_t i = 0; i < xy.size(); i++)
    for (size_t j = i + 1; j < xy.size(); j++) {
      double dx = xy[j].first - xy[i].first;
      if (std::fabs(dx) > 1e-9) slopes.push_back((xy[j].second - xy[i].second) / dx);
    }
  if (slopes.empty()) { *lo = *hi = kNaN; return kNaN; }
  *lo = percentile(slopes, 0.10); *hi = percentile(slopes, 0.90);
  return median(slopes);
}

}  // namespace

TrainingResult analyse_training(std::vector<SessionSummary> sessions, const std::string& reference_date, const TrainingConfig& c) {
  TrainingResult r;
  // Dates, de-duplication (same id: the last one wins), chronological order.
  std::vector<SessionSummary> ok;
  std::map<std::string, size_t> by_id;
  for (auto& s : sessions) {
    if (!training_parse_day(s.date_utc, &s.day)) { r.warnings.push_back("sesión «" + s.id + "» sin fecha válida: no se usa"); continue; }
    if (!s.id.empty() && by_id.count(s.id)) { ok[by_id[s.id]] = s; r.warnings.push_back("sesión «" + s.id + "» repetida: se usa la última"); continue; }
    if (!s.id.empty()) by_id[s.id] = ok.size();
    ok.push_back(s);
  }
  std::stable_sort(ok.begin(), ok.end(), [](const SessionSummary& a, const SessionSummary& b) {
    return a.day != b.day ? a.day < b.day : a.date_utc != b.date_utc ? a.date_utc < b.date_utc : a.id < b.id; });

  if (!reference_date.empty()) {
    if (!training_parse_day(reference_date, &r.reference_day)) { r.warnings.push_back("fecha de referencia no válida: se usa la última sesión"); r.reference_day = ok.empty() ? 0 : ok.back().day; }
  } else r.reference_day = ok.empty() ? 0 : ok.back().day;
  size_t before = ok.size();
  ok.erase(std::remove_if(ok.begin(), ok.end(), [&](const SessionSummary& s) { return s.day > r.reference_day; }), ok.end());
  if (ok.size() < before) r.warnings.push_back(std::to_string(before - ok.size()) + " sesiones posteriores a la fecha de referencia no se usan");
  r.reference_date = training_day_text(r.reference_day);
  if (ok.empty()) { r.warnings.push_back("sin sesiones con fecha"); r.level = "NORMAL"; return r; }
  for (auto& s : ok) if (!s.horse.empty()) { r.horse = s.horse; break; }

  std::map<long, double> loads, srpe;
  std::map<long, int> missing_rpe;
  for (auto& s : ok) {
    double L = external_load(s, c);
    loads[s.day] += L;
    if (!std::isnan(s.rpe)) srpe[s.day] += s.rpe * s.moving_s / 60.0; else missing_rpe[s.day]++;
  }
  long first_day = ok.front().day;

  for (size_t i = 0; i < ok.size(); i++) {
    SessionResult R; R.s = ok[i];
    const SessionSummary& s = ok[i];
    R.load.external = external_load(s, c);
    if (!std::isnan(s.rpe)) R.load.srpe = s.rpe * s.moving_s / 60.0;
    if (i > 0) R.load.rest_days_before = (int)(s.day - ok[i - 1].day);
    windows_at(s.day, loads, srpe, missing_rpe, first_day, c, &R.load, nullptr);
    load_flags(R.load, c, &R.level, &R.reasons);
    if (R.load.rest_days_before > c.rest_watch_days)
      R.reasons.push_back("vuelta al trabajo tras " + std::to_string(R.load.rest_days_before) + " días sin sesiones");

    // Deviations against the horse's own previous sessions.
    for (int gi = 0; gi < 3; gi++)
      for (const auto& m : kMetrics) {
        double x = s.gait[gi].*(m.field);
        if (std::isnan(x)) continue;
        std::vector<double> hist;
        for (size_t j = 0; j < i; j++)
          if (ok[j].day >= s.day - c.baseline_days) { double y = ok[j].gait[gi].*(m.field); if (!std::isnan(y)) hist.push_back(y); }
        if ((int)hist.size() < c.baseline_min_sessions) continue;
        Baseline b = baseline_of(hist);
        double scale = std::max(1.4826 * b.mad, std::max(m.floor_abs, 0.02 * std::fabs(b.med)));
        Deviation d;
        d.metric = std::string(tgait_name((TGait)gi)) + "." + m.key;
        d.value = x; d.baseline = b.med; d.mad = b.mad; d.n = b.n; d.z = (x - b.med) / scale;
        d.direction = d.z >= 0 ? "MAYOR" : "MENOR";
        bool worse = m.worse == 0 || (m.worse > 0 && d.z > 0) || (m.worse < 0 && d.z < 0);
        double az = std::fabs(d.z);
        d.level = az >= c.z_review ? "REVISAR" : az >= c.z_watch ? "VIGILAR" : "NORMAL";
        if (d.level != "NORMAL" && m.raises_level && worse) {
          raise(&R.level, d.level);
          char b2[240];
          snprintf(b2, sizeof(b2), "%s %s de lo habitual: %.3g frente a %.3g (z = %.1f, %d sesiones)", d.metric.c_str(),
                   d.z > 0 ? "por encima" : "por debajo", x, b.med, d.z, b.n);
          R.reasons.push_back(b2);
        }
        R.deviations.push_back(d);
      }
    // Trainer's assessment.
    std::string st = upper_ascii(s.state);
    if (st == "COJERA" || st == "COJO" || st == "DOLOR") { raise(&R.level, "REVISAR"); R.reasons.push_back("el entrenador anotó: " + s.state); }
    else if (st == "CANSADO" || st == "RARO" || st == "MAL") { raise(&R.level, "VIGILAR"); R.reasons.push_back("el entrenador anotó: " + s.state); }
    if (!std::isnan(s.rpe) && s.rpe >= 9) R.reasons.push_back("esfuerzo percibido muy alto (RPE " + num(s.rpe) + ")");
    r.sessions.push_back(R);
  }

  // Current state at the reference day.
  windows_at(r.reference_day, loads, srpe, missing_rpe, first_day, c, &r.current, &r.warnings);
  r.current.rest_days_before = -1;
  { auto it = loads.find(r.reference_day); r.current.external = it == loads.end() ? 0 : it->second;
    auto is = srpe.find(r.reference_day); if (is != srpe.end() && !missing_rpe.count(r.reference_day)) r.current.srpe = is->second; }
  r.days_since_last = (int)(r.reference_day - ok.back().day);
  for (long k = r.reference_day - c.chronic_days + 1; k <= r.reference_day; k++) {
    auto it = loads.find(k);
    r.daily_load.push_back({k, it == loads.end() ? 0.0 : it->second});
  }
  load_flags(r.current, c, &r.level, &r.reasons);
  const SessionResult& last = r.sessions.back();
  if (r.days_since_last <= c.acute_days) {
    for (const auto& reason : last.reasons) r.reasons.push_back("última sesión (" + training_day_text(last.s.day) + "): " + reason);
    raise(&r.level, last.level);
  }
  if (!std::isnan(r.current.acwr) && r.current.acwr < c.acwr_low)
    r.reasons.push_back("carga reciente baja respecto a la habitual (ACWR " + num(r.current.acwr) + "): descarga o parada");
  if (r.days_since_last > c.rest_watch_days)
    r.reasons.push_back(std::to_string(r.days_since_last) + " días sin sesiones: volver a subir la carga poco a poco");

  // Current baselines.
  for (int gi = 0; gi < 3; gi++)
    for (const auto& m : kMetrics) {
      std::vector<double> hist;
      for (const auto& s : ok) if (s.day >= r.reference_day - c.baseline_days) { double y = s.gait[gi].*(m.field); if (!std::isnan(y)) hist.push_back(y); }
      Baseline b = baseline_of(hist);
      Deviation d; d.metric = std::string(tgait_name((TGait)gi)) + "." + m.key; d.baseline = b.med; d.mad = b.mad; d.n = b.n;
      d.level = b.n >= c.baseline_min_sessions ? "DISPONIBLE" : "INSUFICIENTE";
      r.baselines.push_back(d);
    }

  // Trends (per week) over the trend window.
  auto add_trend = [&](const std::string& name, std::function<double(const SessionSummary&)> f) {
    Trend t; t.metric = name;
    std::vector<std::pair<double, double>> xy;
    std::vector<double> ys;
    for (const auto& s : ok)
      if (s.day > r.reference_day - c.trend_days) { double y = f(s); if (!std::isnan(y)) { xy.push_back({(s.day - r.reference_day) / 7.0, y}); ys.push_back(y); } }
    t.n = (int)xy.size();
    std::set<long> days; for (auto& p : xy) days.insert((long)std::lround(p.first * 7));
    if (t.n < c.trend_min_sessions || days.size() < 3) { t.direction = "SIN_DATOS"; r.trends.push_back(t); return; }
    t.slope_per_week = theil_sen(xy, &t.slope_low, &t.slope_high);
    double med = median(ys);
    if (std::fabs(med) > 1e-9) t.relative_per_week = t.slope_per_week / std::fabs(med);
    t.direction = t.slope_low > 0 ? "SUBE" : t.slope_high < 0 ? "BAJA" : "ESTABLE";
    r.trends.push_back(t);
  };
  for (int gi = 0; gi < 3; gi++)
    for (const auto& m : kMetrics) {
      auto field = m.field;
      add_trend(std::string(tgait_name((TGait)gi)) + "." + m.key, [gi, field](const SessionSummary& s) { return s.gait[gi].*field; });
    }
  add_trend("carga_externa", [&](const SessionSummary& s) { return external_load(s, c); });
  add_trend("distancia_m", [](const SessionSummary& s) { return s.distance_m; });

  r.warnings.push_back("carga externa = heurística por aires (" + std::string(TRAINING_LOAD_ALGORITHM) + "), sin validar con datos fisiológicos");
  return r;
}

// ------------------------------------------------------------------ JSON
namespace {
void load_json(std::ostringstream& o, const SessionLoad& L) {
  o << "{\"externa\":" << num(L.external) << ",\"srpe\":" << num(L.srpe) << ",\"aguda\":" << num(L.acute) << ",\"cronica_semanal\":" << num(L.chronic_weekly)
    << ",\"acwr\":" << num(L.acwr) << ",\"aguda_srpe\":" << num(L.acute_srpe) << ",\"cronica_semanal_srpe\":" << num(L.chronic_weekly_srpe)
    << ",\"acwr_srpe\":" << num(L.acwr_srpe) << ",\"monotonia\":" << num(L.monotony) << ",\"tension\":" << num(L.strain)
    << ",\"dias_desde_anterior\":" << (L.rest_days_before < 0 ? std::string("null") : std::to_string(L.rest_days_before)) << "}";
}
void strs(std::ostringstream& o, const std::vector<std::string>& v) {
  o << "["; for (size_t i = 0; i < v.size(); i++) o << (i ? "," : "") << q(v[i]); o << "]";
}
void dev_json(std::ostringstream& o, const Deviation& d) {
  o << "{\"metrica\":" << q(d.metric) << ",\"valor\":" << num(d.value) << ",\"linea_base\":" << num(d.baseline) << ",\"mad\":" << num(d.mad)
    << ",\"z\":" << num(d.z) << ",\"n\":" << d.n << ",\"nivel\":" << q(d.level);
  if (!d.direction.empty()) o << ",\"direccion\":" << q(d.direction);
  o << "}";
}
}  // namespace

std::string training_to_json(const TrainingResult& r, const TrainingConfig& c) {
  std::ostringstream o;
  o << "{\"formato\":\"avo-training-analysis\",\"version_formato\":1,\"version\":\"" << TRAINING_VERSION << "\",\"algoritmo_carga\":\"" << TRAINING_LOAD_ALGORITHM
    << "\",\"caballo\":" << q(r.horse) << ",\"fecha_referencia\":" << q(r.reference_date) << ",\"sesiones_usadas\":" << r.sessions.size()
    << ",\"parametros\":{\"factor_paso\":" << num(c.factor_walk) << ",\"factor_trote\":" << num(c.factor_trot) << ",\"factor_galope\":" << num(c.factor_canter)
    << ",\"alta_velocidad_m_s\":" << num(c.high_speed_m_s) << ",\"factor_alta_velocidad\":" << num(c.factor_high_speed) << ",\"dias_aguda\":" << c.acute_days
    << ",\"dias_cronica\":" << c.chronic_days << ",\"acwr_alto\":" << num(c.acwr_high) << ",\"acwr_bajo\":" << num(c.acwr_low) << ",\"monotonia_alta\":" << num(c.monotony_high)
    << ",\"dias_linea_base\":" << c.baseline_days << ",\"min_sesiones_linea_base\":" << c.baseline_min_sessions << ",\"z_vigilar\":" << num(c.z_watch)
    << ",\"z_revisar\":" << num(c.z_review) << ",\"min_segundos_aire\":" << num(c.min_gait_seconds) << ",\"dias_tendencia\":" << c.trend_days
    << ",\"min_sesiones_tendencia\":" << c.trend_min_sessions << ",\"dias_descanso_aviso\":" << c.rest_watch_days << "}";
  o << ",\"estado\":{\"nivel\":" << q(r.level) << ",\"motivos\":"; strs(o, r.reasons);
  o << ",\"dias_desde_ultima\":" << (r.days_since_last < 0 ? std::string("null") : std::to_string(r.days_since_last)) << ",\"carga\":"; load_json(o, r.current);
  o << ",\"nota\":\"orientativo; no es un diagnóstico veterinario\"}";
  o << ",\"carga_diaria\":[";
  for (size_t i = 0; i < r.daily_load.size(); i++) o << (i ? "," : "") << "{\"fecha\":" << q(training_day_text(r.daily_load[i].first)) << ",\"carga\":" << num(r.daily_load[i].second) << "}";
  o << "],\"lineas_base\":[";
  for (size_t i = 0; i < r.baselines.size(); i++) { if (i) o << ","; const Deviation& d = r.baselines[i];
    o << "{\"metrica\":" << q(d.metric) << ",\"mediana\":" << num(d.baseline) << ",\"mad\":" << num(d.mad) << ",\"n\":" << d.n << ",\"estado\":" << q(d.level) << "}"; }
  o << "],\"tendencias\":[";
  for (size_t i = 0; i < r.trends.size(); i++) { if (i) o << ","; const Trend& t = r.trends[i];
    o << "{\"metrica\":" << q(t.metric) << ",\"pendiente_semana\":" << num(t.slope_per_week) << ",\"pendiente_p10\":" << num(t.slope_low) << ",\"pendiente_p90\":" << num(t.slope_high)
      << ",\"relativa_semana\":" << num(t.relative_per_week) << ",\"n\":" << t.n << ",\"direccion\":" << q(t.direction) << "}"; }
  o << "],\"sesiones\":[";
  for (size_t i = 0; i < r.sessions.size(); i++) {
    const SessionResult& R = r.sessions[i];
    o << (i ? "," : "") << "{\"id\":" << q(R.s.id) << ",\"fecha\":" << q(training_day_text(R.s.day)) << ",\"nivel\":" << q(R.level) << ",\"motivos\":"; strs(o, R.reasons);
    o << ",\"carga\":"; load_json(o, R.load);
    o << ",\"desvios\":["; for (size_t k = 0; k < R.deviations.size(); k++) { if (k) o << ","; dev_json(o, R.deviations[k]); } o << "]";
    o << ",\"resumen\":" << training_summary_to_json(R.s) << "}";
  }
  o << "],\"avisos\":"; strs(o, r.warnings);
  o << "}";
  return o.str();
}

}  // namespace avoeq
