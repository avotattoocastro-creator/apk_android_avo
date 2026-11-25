// AVO BEACH 1.0.0 — see include/avo_eq/beach.h.
#include "avo_eq/beach.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include "avo_eq/engine.h"
#include "avo_eq/json.h"

namespace avoeq {

const char* beach_band_code(BeachBand b) {
  switch (b) {
    case BeachBand::ORILLA_FIRME: return "ORILLA_FIRME";
    case BeachBand::TRANSICION: return "TRANSICION";
    case BeachBand::SECA_PROFUNDA: return "SECA_PROFUNDA";
    default: return "";
  }
}

namespace {
// days from 1970-01-01 (proleptic Gregorian), Howard Hinnant's algorithm
long days_from_civil(long y, unsigned m, unsigned d) {
  y -= m <= 2;
  const long era = (y >= 0 ? y : y - 399) / 400;
  const unsigned yoe = (unsigned)(y - era * 400);
  const unsigned doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
  const unsigned doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
  return era * 146097 + (long)doe - 719468;
}

struct Local { double lat0, lon0, kx, ky; };
Local local_at(double lat, double lon) {
  const double R = 6371008.8, d2r = M_PI / 180;
  return {lat, lon, R * d2r * std::cos(lat * d2r), R * d2r};
}
void xy(const Local& L, double lat, double lon, double* x, double* y) { *x = (lon - L.lon0) * L.kx; *y = (lat - L.lat0) * L.ky; }
}  // namespace

std::vector<double> gnss_unix_s(const Session& s, const std::vector<double>& t) {
  std::vector<double> u(t.size(), NAN);
  for (size_t k = 0; k < s.gnss.size() && k < t.size(); k++) {
    const GnssEpoch& g = s.gnss[k];
    if ((g.valid & 3) != 3 || g.year < 2000 || g.month < 1 || g.month > 12 || g.day < 1 || std::isnan(t[k])) continue;
    double base = (double)days_from_civil(g.year, g.month, g.day) * 86400.0 + g.hour * 3600.0 + g.minute * 60.0 + g.second + g.nano * 1e-9 - t[k];
    for (size_t i = 0; i < t.size(); i++) if (!std::isnan(t[i])) u[i] = base + t[i];
    break;
  }
  return u;
}

double tide_at(const std::vector<std::pair<double, double>>& c, double x) {
  if (c.size() < 2 || std::isnan(x) || x < c.front().first || x > c.back().first) return NAN;
  auto it = std::lower_bound(c.begin(), c.end(), std::make_pair(x, -1e300));
  if (it == c.begin()) return it->second;
  auto p = it - 1;
  if (it == c.end()) return p->second;
  double dt = it->first - p->first;
  return dt <= 0 ? p->second : p->second + (it->second - p->second) * (x - p->first) / dt;
}

BeachResult analyse_beach(const Session& s, const Analysis& a, const BeachConfig& c) {
  BeachResult r;
  if (!c.any()) return r;
  const auto& g = a.gnss;
  const size_t n = g.t.size();
  std::vector<double> ut = gnss_unix_s(s, g.t);
  double u0 = NAN, base = NAN;   // base: ut time of GNSS time 0
  for (size_t i = 0; i < n; i++) if (!std::isnan(ut[i])) { u0 = ut[i]; base = ut[i] - g.t[i]; break; }
  if (std::isnan(u0)) { r.present = true; r.warnings.push_back("sin fecha y hora válidas en el GPS: no se puede situar la marea"); return r; }
  // start of the work: first effort of AVO Racing; otherwise the start of the session
  double w0 = NAN;
  for (const auto& e : a.racing.efforts) if (std::isnan(w0) || e.t0 < w0) w0 = e.t0;
  const double uw = std::isnan(w0) ? u0 : base + w0;
  // ---- marea
  if (c.tide.size() >= 2) {
    r.tide = true;
    r.tide_source = c.tide_source;
    r.tide_start_m = tide_at(c.tide, u0);
    r.tide_work_m = tide_at(c.tide, uw);
    if (std::isnan(r.tide_work_m)) r.warnings.push_back("la curva de marea no cubre la hora del trabajo");
    double h1 = tide_at(c.tide, uw + 600);
    if (!std::isnan(h1) && !std::isnan(r.tide_work_m)) r.tide_trend = h1 > r.tide_work_m + 0.005 ? 1 : h1 < r.tide_work_m - 0.005 ? -1 : 0;
    // extremes of the curve around the work: local max / min
    double prev_t = NAN, prev_h = NAN, next_t = NAN, next_h = NAN;
    for (size_t k = 1; k + 1 < c.tide.size(); k++) {
      double hp = c.tide[k - 1].second, h = c.tide[k].second, hn = c.tide[k + 1].second;
      bool ext = (h >= hp && h > hn) || (h <= hp && h < hn);
      if (!ext) continue;
      if (c.tide[k].first <= uw) { prev_t = c.tide[k].first; prev_h = h; }
      else if (std::isnan(next_t)) { next_t = c.tide[k].first; next_h = h; }
    }
    (void)prev_t; (void)next_t;
    if (!std::isnan(prev_h) && !std::isnan(next_h) && std::fabs(next_h - prev_h) > 0.05 && !std::isnan(r.tide_work_m)) {
      r.tide_phase_pct = std::min(100.0, std::max(0.0, (r.tide_work_m - prev_h) / (next_h - prev_h) * 100));
      double lo = std::min(prev_h, next_h), hi = std::max(prev_h, next_h);
      double rel = (r.tide_work_m - lo) / (hi - lo);
      r.tide_level = rel < 1.0 / 3 ? "BAJA" : rel < 2.0 / 3 ? "MEDIA" : "ALTA";
    }
    // highest water of the 13 h before the work (the sand it covered is still wet)
    for (const auto& p : c.tide) if (p.first >= uw - 13 * 3600 && p.first <= uw && (std::isnan(r.last_high_m) || p.second > r.last_high_m)) r.last_high_m = p.second;
    if (!c.tide.empty() && c.tide.front().first > uw - 12 * 3600) r.warnings.push_back("la curva de marea empieza menos de 12 h antes del trabajo: la última pleamar puede ser aproximada");
    r.present = true;
  }
  // ---- franjas
  if (c.dry.set && c.low.set) {
    r.present = true;
    if (!r.tide) { r.warnings.push_back("hay líneas de playa pero no curva de marea: sin franja automática"); return r; }
    if (!(c.h_dry > c.h_low + 0.5)) { r.warnings.push_back("altura de la línea seca no mayor que la de bajamar: sin franja automática"); return r; }
    Local L = local_at(c.dry.a_lat, c.dry.a_lon);
    double ax, ay, bx, by, l1x, l1y, l2x, l2y;
    xy(L, c.dry.a_lat, c.dry.a_lon, &ax, &ay); xy(L, c.dry.b_lat, c.dry.b_lon, &bx, &by);
    xy(L, c.low.a_lat, c.low.a_lon, &l1x, &l1y); xy(L, c.low.b_lat, c.low.b_lon, &l2x, &l2y);
    double ux = bx - ax, uy = by - ay, len = std::hypot(ux, uy);
    if (len < 20) { r.warnings.push_back("línea seca demasiado corta (< 20 m)"); return r; }
    ux /= len; uy /= len;
    double nx = -uy, ny = ux;                         // normal; oriented towards the low-water line
    double mx = (l1x + l2x) / 2 - ax, my = (l1y + l2y) / 2 - ay;
    double Lw = mx * nx + my * ny;
    if (Lw < 0) { nx = -nx; ny = -ny; Lw = -Lw; }
    if (Lw < 20) { r.warnings.push_back("las líneas seca y de bajamar están a menos de 20 m: sin franja automática"); return r; }
    double span = c.h_dry - c.h_low;
    r.band.assign(n, (uint8_t)BeachBand::NONE);
    std::vector<std::pair<double, double>> work;
    for (const auto& e : a.racing.efforts) work.push_back({e.t0, e.t1});
    bool any_work = !work.empty();
    double far_off = 0;
    for (size_t i = 1; i < n; i++) {
      if (!g.usable[i] || !g.usable[i - 1] || std::isnan(ut[i]) || std::isnan(g.speed[i]) || g.speed[i] < 2.0) continue;
      double h = tide_at(c.tide, ut[i]);
      if (std::isnan(h)) continue;
      double hh = r.last_high_m;
      double x, y;
      xy(L, g.lat[i], g.lon[i], &x, &y);
      double xc = (x - ax) * nx + (y - ay) * ny;      // m seaward of the dry line
      double along = (x - ax) * ux + (y - ay) * uy;
      if (along < -500 || along > len + 500) { far_off += g.dist[i] - g.dist[i - 1]; continue; }   // outside the drawn beach
      double xw = Lw * (c.h_dry - h) / span, xm = std::isnan(hh) ? xw : Lw * (c.h_dry - std::max(hh, h)) / span;
      BeachBand b = xc >= xw - c.shore_m ? BeachBand::ORILLA_FIRME : xc >= xm ? BeachBand::TRANSICION : BeachBand::SECA_PROFUNDA;
      r.band[i] = (uint8_t)b;
      double d = g.dist[i] - g.dist[i - 1];
      if (!(d > 0)) continue;
      r.dist_m[(int)b] += d;
      bool in_work = false;
      for (const auto& w : work) if (g.t[i] >= w.first && g.t[i] <= w.second) { in_work = true; break; }
      if (in_work || !any_work) r.work_m[(int)b] += d;
    }
    if (far_off > 200) r.warnings.push_back(std::to_string((int)far_off) + " m fuera de la playa dibujada: sin franja");
    double tot = r.work_m[0] + r.work_m[1] + r.work_m[2];
    if (tot >= 200) {
      int k = 0;
      for (int j = 1; j < 3; j++) if (r.work_m[j] > r.work_m[k]) k = j;
      r.bands = true;
      r.work_band = beach_band_code((BeachBand)k);
      r.work_band_pct = 100.0 * r.work_m[k] / tot;
      r.mixed = r.work_band_pct < 70;
      if (r.mixed) r.warnings.push_back("trabajo repartido entre franjas (la dominante es el " + std::to_string((int)r.work_band_pct) + " %)");
    } else {
      r.warnings.push_back("menos de 200 m clasificados en la playa: sin franja del trabajo");
    }
  } else if (c.dry.set || c.low.set) {
    r.present = true;
    r.warnings.push_back("falta una de las dos líneas de playa (seca y de bajamar): sin franja automática");
  }
  return r;
}

std::string beach_json(const BeachResult& r) {
  auto num = [](double v, int d) {
    if (std::isnan(v) || std::isinf(v)) return std::string("null");
    char b[40]; snprintf(b, sizeof b, "%.*f", d, v); return std::string(b);
  };
  auto q = [](const std::string& s) { return "\"" + json::escape(s) + "\""; };
  std::string o = "{\"version\":\"" + std::string(BEACH_VERSION) + "\"";
  if (r.tide) {
    o += ",\"marea\":{\"fuente\":" + q(r.tide_source) + ",\"altura_inicio_m\":" + num(r.tide_start_m, 2) +
         ",\"altura_trabajo_m\":" + num(r.tide_work_m, 2) + ",\"tendencia\":" + q(r.tide_trend > 0 ? "SUBE" : r.tide_trend < 0 ? "BAJA" : "") +
         ",\"fase_pct\":" + num(r.tide_phase_pct, 0) + ",\"nivel\":" + q(r.tide_level) + ",\"ultima_pleamar_m\":" + num(r.last_high_m, 2) +
         ",\"tipo_dato\":\"PREDICCION\"}";
  }
  if (r.bands) {
    o += ",\"franjas\":{\"metodo\":\"AUTO_LINEAS_Y_MAREA\",\"trabajo\":" + q(r.work_band) + ",\"trabajo_pct\":" + num(r.work_band_pct, 0) +
         ",\"mixta\":" + std::string(r.mixed ? "true" : "false") + ",\"distancia_m\":{";
    for (int k = 0; k < 3; k++) o += std::string(k ? "," : "") + q(beach_band_code((BeachBand)k)) + ":" + num(r.dist_m[k], 0);
    o += "},\"trabajo_m\":{";
    for (int k = 0; k < 3; k++) o += std::string(k ? "," : "") + q(beach_band_code((BeachBand)k)) + ":" + num(r.work_m[k], 0);
    o += "},\"validado\":false}";
  }
  o += ",\"avisos\":[";
  for (size_t i = 0; i < r.warnings.size(); i++) o += (i ? "," : "") + q(r.warnings[i]);
  return o + "]}";
}

}  // namespace avoeq
