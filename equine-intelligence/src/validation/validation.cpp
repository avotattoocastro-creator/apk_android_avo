#include "avo_eq/validation.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <map>
#include <set>
#include <tuple>

namespace avoeq {

static const double WEEK_MS = 604800000.0;

RtkState rtk_state(const GnssEpoch& e) {
  if (!e.fix_ok() || e.fix_type < 2) return RtkState::NONE;
  if (e.carr_soln() == 2) return RtkState::FIXED;
  if (e.carr_soln() == 1) return RtkState::FLOAT;
  if (e.diff()) return RtkState::DGNSS;
  return RtkState::GNSS;
}
const char* rtk_name(RtkState s) {
  switch (s) { case RtkState::NONE: return "SIN_SOLUCION"; case RtkState::GNSS: return "GNSS"; case RtkState::DGNSS: return "DGNSS";
    case RtkState::FLOAT: return "RTK_FLOAT"; case RtkState::FIXED: return "RTK_FIX"; }
  return "?";
}
const char* quality_name(Quality q) {
  switch (q) { case Quality::GOOD: return "BUENA"; case Quality::USABLE: return "UTILIZABLE"; case Quality::POOR: return "BAJA";
    case Quality::UNUSABLE: return "NO_UTILIZABLE"; case Quality::UNKNOWN: return "DESCONOCIDA"; }
  return "?";
}

std::vector<double> gnss_time_s(const std::vector<GnssEpoch>& g) {
  std::vector<double> t(g.size(), 0.0);
  if (g.empty()) return t;
  double base = g[0].itow_ms, wraps = 0, prev = g[0].itow_ms;
  for (size_t i = 0; i < g.size(); i++) {
    double v = g[i].itow_ms;
    if (i && v < prev && prev - v > WEEK_MS / 2) wraps += WEEK_MS;   // week rollover
    prev = v;
    t[i] = (v + wraps - base) / 1000.0;
  }
  return t;
}

static double dist_m(double la1, double lo1, double la2, double lo2) {
  const double R = 6371008.8, r = 3.14159265358979323846 / 180.0;
  double a = std::sin((la2 - la1) * r / 2), b = std::sin((lo2 - lo1) * r / 2);
  double h = a * a + std::cos(la1 * r) * std::cos(la2 * r) * b * b;
  return 2 * R * std::asin(std::sqrt(std::min(1.0, h)));
}

static void add_issue(std::map<std::string, Issue>& m, const std::string& code, double t, const std::string& detail) {
  auto it = m.find(code);
  if (it == m.end()) { Issue i; i.code = code; i.t_s = t; i.detail = detail; m[code] = i; }
  else it->second.count++;
}

ValidationReport validate(const Session& s, const ValidationConfig& c) {
  ValidationReport r;
  std::map<std::string, Issue> agg;
  const auto& g = s.gnss;
  r.gnss_flags.assign(g.size(), 0);
  std::vector<double> t = gnss_time_s(g);
  // nominal rate = median of positive steps
  std::vector<double> dts;
  for (size_t i = 1; i < g.size(); i++) if (t[i] > t[i - 1]) dts.push_back(t[i] - t[i - 1]);
  double dt_nom = dts.empty() ? 0 : dsp::median(dts);
  r.gnss_nominal_hz = dt_nom > 0 ? 1.0 / dt_nom : 0;
  for (size_t i = 0; i < g.size(); i++) {
    const GnssEpoch& e = g[i];
    uint32_t f = 0;
    if (!e.fix_ok() || e.fix_type < 3 || e.fix_type == 5) { f |= GF_NO_FIX; add_issue(agg, "GNSS_SIN_FIX", t[i], "épocas sin solución 3D válida"); }
    if (e.flags3 & 0x01) f |= GF_INVALID_LLH;
    if (std::fabs(e.lat_deg) > 90 || std::fabs(e.lon_deg) > 180 || e.gspeed_ms < 0 || e.gspeed_ms > c.max_speed_ms ||
        std::sqrt(e.veln_ms * e.veln_ms + e.vele_ms * e.vele_ms) > c.max_speed_ms) {
      f |= GF_IMPOSSIBLE; add_issue(agg, "GNSS_VALOR_IMPOSIBLE", t[i], "coordenadas o velocidad fuera de límites físicos");
    }
    if (e.hacc_m > c.max_hacc_m) f |= GF_HACC_HIGH;
    if (e.sacc_ms > c.max_sacc_ms) f |= GF_SACC_HIGH;
    if (e.num_sv < c.min_sats) f |= GF_FEW_SATS;
    if (i) {
      double dt = t[i] - t[i - 1];
      if (dt == 0) { f |= GF_DUPLICATE; add_issue(agg, "GNSS_DUPLICADO", t[i], "misma época repetida"); }
      else if (dt < 0) { f |= GF_TIME_BACKWARDS; add_issue(agg, "GNSS_TIEMPO_ATRAS", t[i], "el tiempo GNSS retrocede"); }
      else if (dt_nom > 0 && dt > 2.5 * dt_nom) {
        f |= GF_GAP_BEFORE; r.gnss_gaps++;
        r.gnss_missing_epochs += (uint32_t)std::lround(dt / dt_nom) - 1;
        char b[96]; snprintf(b, sizeof(b), "hueco de %.2f s", dt);
        add_issue(agg, "GNSS_HUECO", t[i], b);
      }
      if (dt > 0 && !(f & (GF_NO_FIX | GF_IMPOSSIBLE)) && !(r.gnss_flags[i - 1] & (GF_NO_FIX | GF_IMPOSSIBLE))) {
        double d = dist_m(g[i - 1].lat_deg, g[i - 1].lon_deg, e.lat_deg, e.lon_deg);
        double vmax = std::max(e.gspeed_ms, g[i - 1].gspeed_ms) + 3 * std::max(e.sacc_ms, 0.05);
        double allowed = c.pos_jump_factor * (vmax * dt + 3 * (e.hacc_m + g[i - 1].hacc_m) + 0.05);
        if (d > allowed) { f |= GF_POS_JUMP; add_issue(agg, "GNSS_SALTO_POSICION", t[i], "desplazamiento incompatible con la velocidad medida"); }
      }
    }
    r.gnss_flags[i] = f;
  }
  // ---- IMU
  const auto& im = s.imu;
  r.imu_flags.assign(im.size(), 0);
  std::set<std::tuple<uint8_t, uint32_t, uint16_t>> seen;
  int64_t last_t[3] = {INT64_MIN, INT64_MIN, INT64_MIN};
  const ImuSample* prev[3] = {nullptr, nullptr, nullptr};
  std::vector<double> steps[3];
  for (size_t i = 0; i < im.size(); i++) {
    uint8_t id = im[i].imu_id < 3 ? im[i].imu_id : 2;
    if (last_t[id] != INT64_MIN && im[i].girth_us > last_t[id]) steps[id].push_back((double)(im[i].girth_us - last_t[id]));
    last_t[id] = std::max(last_t[id], im[i].girth_us);
  }
  for (int k = 0; k < 3; k++) { double m = steps[k].empty() ? 0 : dsp::median(steps[k]); r.imu_nominal_hz[k] = m > 0 ? 1e6 / m : 0; }
  for (int k = 0; k < 3; k++) last_t[k] = INT64_MIN;
  for (size_t i = 0; i < im.size(); i++) {
    const ImuSample& x = im[i];
    uint8_t id = x.imu_id < 3 ? x.imu_id : 2;
    uint32_t f = 0;
    if (!seen.insert(std::make_tuple(x.imu_id, x.batch_seq, x.index)).second) { f |= IF_DUPLICATE; add_issue(agg, "IMU_DUPLICADO", 0, "muestra IMU repetida"); }
    int16_t v[6] = {x.ax, x.ay, x.az, x.gx, x.gy, x.gz};
    for (int16_t a : v) if (a >= c.sat_limit || a <= -c.sat_limit) { f |= IF_SATURATED; }
    if (f & IF_SATURATED) { r.imu_saturated++; add_issue(agg, "IMU_SATURADA", 0, "valores en el límite de int16 (saturación del conversor)"); }
    if (last_t[id] != INT64_MIN) {
      if (x.girth_us < last_t[id]) { f |= IF_TIME_BACKWARDS; add_issue(agg, "IMU_TIEMPO_ATRAS", 0, "tiempo de la cincha retrocede"); }
      double per = r.imu_nominal_hz[id] > 0 ? 1e6 / r.imu_nominal_hz[id] : 0;
      if (per > 0 && (double)(x.girth_us - last_t[id]) > 1.5 * per) {
        f |= IF_GAP_BEFORE;
        r.imu_missing[id] += (uint32_t)std::lround((double)(x.girth_us - last_t[id]) / per) - 1;
        add_issue(agg, "IMU_MUESTRAS_PERDIDAS", 0, "huecos en la serie IMU");
      }
    }
    if (prev[id] && prev[id]->ax == x.ax && prev[id]->ay == x.ay && prev[id]->az == x.az && prev[id]->gx == x.gx &&
        prev[id]->gy == x.gy && prev[id]->gz == x.gz) f |= IF_STUCK;
    prev[id] = &x;
    last_t[id] = std::max(last_t[id], x.girth_us);
    r.imu_flags[i] = f;
  }
  for (auto& kv : agg) r.issues.push_back(kv.second);
  return r;
}

}  // namespace avoeq
