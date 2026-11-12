#include "avo_eq/performance.h"
#include "avo_eq/dsp.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <map>

namespace avoeq {

static double dt_nominal(const GnssResult& g) {
  std::vector<double> d; for (size_t i = 1; i < g.t.size(); i++) if (g.t[i] > g.t[i - 1]) d.push_back(g.t[i] - g.t[i - 1]);
  return d.empty() ? 0.125 : dsp::median(d);
}

PerformanceResult analyse_performance(const GaitResult& gait, const GnssResult& g, const FusionResult* fusion, bool has_imu, const PerfConfig& c) {
  PerformanceResult r; r.classifier = gait.classifier;
  double dtn = dt_nominal(g);
  uint8_t imu_pref = 255;
  if (fusion) for (auto& w : fusion->windows) imu_pref = std::min(imu_pref, w.imu_id);
  int id = 0;
  for (const auto& s : gait.segments) {
    SegmentPerformance p; p.id = ++id; p.gait = s.gait; p.classifier = gait.classifier; p.t0 = s.t0; p.t1 = s.t1; p.duration_s = s.t1 - s.t0;
    p.class_quality = s.quality; p.class_confidence = s.confidence >= 0 ? s.confidence : NAN;
    // ---- GNSS
    std::vector<double> v; double vmax = NAN, amax = NAN, dmin = NAN; size_t first = SIZE_MAX, last = 0, fix = 0, usable = 0;
    double vsum = 0, tsum = 0;
    for (size_t i = 0; i < g.t.size(); i++) {
      if (g.t[i] < s.t0 || g.t[i] >= s.t1) continue;
      if (!g.usable[i]) continue;
      usable++;
      if (g.quality[i] == (uint8_t)Quality::GOOD) fix++;
      if (first == SIZE_MAX) first = i;
      last = i;
      if (!std::isnan(g.speed[i]) && g.quality[i] <= (uint8_t)Quality::USABLE) {
        double dt = (i + 1 < g.t.size()) ? std::min(std::max(g.t[i + 1] - g.t[i], 0.0), 2 * dtn) : dtn;
        vsum += g.speed[i] * dt; tsum += dt;
        if (std::isnan(vmax) || g.speed[i] > vmax) vmax = g.speed[i];
      }
      if (!std::isnan(g.accel[i]) && g.accel_sigma[i] <= c.accel_max_sigma && g.quality[i] <= (uint8_t)Quality::USABLE) {
        if (std::isnan(amax) || g.accel[i] > amax) amax = g.accel[i];
        if (std::isnan(dmin) || g.accel[i] < dmin) dmin = g.accel[i];
      }
    }
    double expected = std::max(1.0, p.duration_s / dtn);
    p.gnss_usable_fraction = std::min(1.0, usable / expected);
    p.gnss_fix_fraction = std::min(1.0, fix / expected);
    if (first != SIZE_MAX && last > first) p.distance_m = g.dist[last] - g.dist[first];
    if (tsum > 0) p.speed_mean = vsum / tsum;
    p.speed_max = vmax; p.accel_max = amax; p.decel_max = dmin;
    p.gnss_quality = usable == 0 ? Quality::UNUSABLE : p.gnss_fix_fraction > 0.9 ? Quality::GOOD : p.gnss_usable_fraction > 0.5 ? Quality::USABLE : Quality::POOR;
    // ---- girth (fused windows of one IMU, preferably the central one)
    if (has_imu && fusion) {
      std::vector<double> f, fsig, icv, acv, cc, ss, L; int in = 0;
      for (auto& w : fusion->windows) {
        if (w.imu_id != imu_pref || std::isnan(w.t_gnss) || w.t_gnss < s.t0 || w.t_gnss >= s.t1) continue;
        in++;
        if (std::isnan(w.cadence_hz) || w.status == "SIN_SINCRONIA") continue;
        f.push_back(w.cadence_hz); fsig.push_back(w.cadence_sigma);
        if (!std::isnan(w.interval_cv)) icv.push_back(w.interval_cv);
        if (!std::isnan(w.amplitude_cv)) acv.push_back(w.amplitude_cv);
        if (!std::isnan(w.cycle_corr)) cc.push_back(w.cycle_corr);
        if (!std::isnan(w.spectral_stability)) ss.push_back(w.spectral_stability);
        if (!std::isnan(w.stride_length_m)) L.push_back(w.stride_length_m);
      }
      p.imu_valid_fraction = in ? (double)f.size() / in : 0;
      if (!f.empty()) {
        p.cadence_mean_hz = dsp::mean(f);
        p.cadence_cv = f.size() > 1 ? dsp::stddev(f) / p.cadence_mean_hz : NAN;
        double between = f.size() > 1 ? dsp::stddev(f) / std::sqrt((double)f.size()) : 0, within = dsp::mean(fsig) / std::sqrt((double)f.size());
        p.cadence_sigma_hz = std::sqrt(between * between + within * within);
      }
      if (!icv.empty()) p.interval_cv = dsp::median(icv);
      if (!acv.empty()) p.amplitude_cv = dsp::median(acv);
      if (!cc.empty()) p.cycle_corr = dsp::median(cc);
      if (!ss.empty()) p.spectral_stability = dsp::median(ss);
      if (!L.empty()) p.stride_length_m = dsp::median(L);
      p.imu_quality = in == 0 ? Quality::UNKNOWN : p.imu_valid_fraction > 0.8 ? Quality::GOOD : p.imu_valid_fraction > 0.5 ? Quality::USABLE : Quality::POOR;
      if (in == 0) p.warnings.push_back("sin ventanas de la cincha en este tramo");
    } else {
      p.imu_quality = Quality::UNKNOWN;
      p.warnings.push_back("SIN DATOS DE CINCHA");
    }
    // ---- insufficient data is a state, not a forced gait
    bool imu_ok = !std::isnan(p.imu_valid_fraction) && p.imu_valid_fraction >= 0.5;
    if (p.gnss_usable_fraction < c.min_gnss_fraction && !imu_ok && p.gait != Gait::INSUFFICIENT_DATA) {
      p.warnings.push_back(std::string("clasificado como ") + gait_name(p.gait) + " pero sin datos suficientes: se marca DATOS_INSUFICIENTES");
      p.gait = Gait::INSUFFICIENT_DATA;
    }
    if (p.gait == Gait::UNKNOWN) p.warnings.push_back("aire no determinado: se conserva como DESCONOCIDO");
    r.segments.push_back(p);
  }
  // ---- aggregations
  double total = 0; for (auto& p : r.segments) total += p.duration_s;
  std::map<int, std::vector<const SegmentPerformance*>> by;
  for (auto& p : r.segments) by[(int)p.gait].push_back(&p);
  auto agg = [&](const std::vector<const SegmentPerformance*>& v, Gait gg) {
    GaitAggregate a; a.gait = gg; a.segments = (uint32_t)v.size();
    double ws = 0, vs = 0, cw = 0, cs = 0; std::vector<double> L;
    for (auto* p : v) {
      a.duration_s += p->duration_s;
      if (!std::isnan(p->distance_m)) a.distance_m += p->distance_m;
      if (!std::isnan(p->speed_mean)) { vs += p->speed_mean * p->duration_s; ws += p->duration_s; }
      if (!std::isnan(p->speed_max) && (std::isnan(a.speed_max) || p->speed_max > a.speed_max)) a.speed_max = p->speed_max;
      if (!std::isnan(p->cadence_mean_hz)) { cs += p->cadence_mean_hz * p->duration_s; cw += p->duration_s; }
      if (!std::isnan(p->stride_length_m)) L.push_back(p->stride_length_m);
    }
    if (ws > 0) a.speed_mean = vs / ws;
    if (cw > 0) a.cadence_mean_hz = cs / cw;
    if (!L.empty()) a.stride_length_m = dsp::median(L);
    a.time_fraction = total > 0 ? a.duration_s / total : 0;
    return a;
  };
  std::vector<const SegmentPerformance*> all;
  for (auto& kv : by) { r.per_gait.push_back(agg(kv.second, (Gait)kv.first)); all.insert(all.end(), kv.second.begin(), kv.second.end()); }
  r.session = agg(all, Gait::UNKNOWN);
  for (auto& a : r.per_gait) {
    Metric m; m.name = std::string("fraccion_tiempo_") + gait_name(a.gait); m.unit = "1"; m.value = a.time_fraction;
    m.algorithm = "rendimiento por aire (" + r.classifier + ")"; m.version = PERFORMANCE_VERSION; m.quality = Quality::USABLE;
    r.metrics.push_back(m);
  }
  return r;
}

// ------------------------------------------------------------------ events
std::vector<Event> detect_events(const EventInputs& in, const EventConfig& c) {
  std::vector<Event> ev;
  auto add = [&](const char* type, double t0, double t1, std::vector<std::string> data, Quality q, std::string why, const std::string& alg,
                 std::vector<std::pair<std::string, double>> vals = {}) {
    Event e; e.type = type; e.t0 = t0; e.t1 = t1; e.data = data; e.quality = q; e.reason = why; e.algorithm = alg; e.version = EVENTS_VERSION; e.values = vals;
    ev.push_back(e);
  };
  const GnssResult* g = in.gnss;
  // ---- movement start / stop: speed hysteresis with hold time
  if (g && !g->t.empty()) {
    int state = -1;   // -1 unknown, 0 stopped, 1 moving
    double cand_t = NAN; int cand = -1;
    for (size_t i = 0; i < g->t.size(); i++) {
      if (std::isnan(g->speed[i]) || g->quality[i] > (uint8_t)Quality::USABLE) continue;
      double v = g->speed[i];
      int want = v > c.move_start_speed ? 1 : v < c.move_stop_speed ? 0 : state;
      if (want < 0) continue;
      if (state < 0) { state = want; continue; }
      if (want == state) { cand = -1; continue; }
      if (cand != want) { cand = want; cand_t = g->t[i]; continue; }
      if (g->t[i] - cand_t >= c.move_hold_s) {
        add(want ? "INICIO_MOVIMIENTO" : "PARADA", cand_t, g->t[i], {"velocidad GNSS"}, Quality::USABLE,
            want ? "velocidad > " + std::to_string(c.move_start_speed).substr(0, 4) + " m/s durante " + std::to_string((int)c.move_hold_s) + " s"
                 : "velocidad < " + std::to_string(c.move_stop_speed).substr(0, 4) + " m/s durante " + std::to_string((int)c.move_hold_s) + " s",
            "histéresis de velocidad con tiempo de confirmación", {{"velocidad_m_s", v}});
        state = want; cand = -1;
      }
    }
  }
  // ---- sustained acceleration / deceleration (Advanced Acceleration Engine)
  if (in.kin) for (auto& k : in.kin->events) {
    if (k.type != "ACELERACION_SOSTENIDA" && k.type != "DESACELERACION_SOSTENIDA") continue;
    add(k.type.c_str(), k.t0, k.t1, {"velocidad GNSS", "aceleración de la trayectoria"}, k.quality,
        "aceleración longitudinal sostenida (núcleo a media altura del pico)", std::string("motor de aceleración ") + KINEMATICS_VERSION,
        {{"aceleracion_media_m_s2", k.mean}, {"pico_m_s2", k.peak}, {"delta_v_m_s", k.dv}});
  }
  // ---- curves
  if (in.curves) for (auto& cv : in.curves->curves) {
    std::vector<std::pair<std::string, double>> vals{{"curva", (double)cv.id}, {"radio_m", cv.radius_m}, {"giro_deg", cv.heading_change_deg}};
    add("INICIO_CURVA", cv.t0, cv.t0, {"trayectoria GNSS"}, cv.quality, "curva " + cv.direction + " de radio < 40 m (histéresis 40/60 m)", std::string("motor de curvas ") + CURVES_VERSION, vals);
    add("FIN_CURVA", cv.t1, cv.t1, {"trayectoria GNSS"}, cv.quality, "radio > 60 m o fin de giro significativo", std::string("motor de curvas ") + CURVES_VERSION, vals);
  }
  // ---- gait transitions (A -> [TRANSITION] -> B among real gaits)
  if (in.gait) {
    const auto& sg = in.gait->segments;
    int last = -1; double tr0 = NAN;
    for (size_t i = 0; i < sg.size(); i++) {
      int gg = (int)sg[i].gait;
      if (gg == (int)Gait::TRANSITION) { if (std::isnan(tr0)) tr0 = sg[i].t0; continue; }
      if (gg > 3) { tr0 = NAN; last = -1; continue; }   // unknown / insufficient interrupts the chain
      if (last >= 0 && last != gg) {
        double t0 = std::isnan(tr0) ? sg[i].t0 : tr0;
        add("TRANSICION_AIRE", t0, sg[i].t0, {"clasificador " + in.gait->classifier}, sg[i].quality,
            std::string(gait_name((Gait)last)) + " -> " + gait_name((Gait)gg), in.gait->classifier + " " + in.gait->version,
            {{"desde", (double)last}, {"hasta", (double)gg}});
      }
      last = gg; tr0 = NAN;
    }
  }
  // ---- cadence jumps and regularity loss (fused girth windows)
  if (in.fusion) {
    std::map<int, const FusedWindow*> prev;
    std::map<int, std::vector<double>> cc;
    for (auto& w : in.fusion->windows) if (!std::isnan(w.cycle_corr) && !std::isnan(w.t_gnss)) cc[w.imu_id].push_back(w.cycle_corr);
    std::map<int, std::pair<double, double>> stat;
    for (auto& kv : cc) if (kv.second.size() >= 10) stat[kv.first] = {dsp::median(kv.second), std::max(0.02, 1.4826 * dsp::mad(kv.second))};
    for (auto& w : in.fusion->windows) {
      if (std::isnan(w.t_gnss)) continue;
      if (!std::isnan(w.cadence_hz)) {
        auto it = prev.find(w.imu_id);
        if (it != prev.end()) {
          const FusedWindow* p = it->second;
          double d = w.cadence_hz - p->cadence_hz, s = std::sqrt(w.cadence_sigma * w.cadence_sigma + p->cadence_sigma * p->cadence_sigma);
          if (std::fabs(d) > std::max(c.cadence_jump_hz, 3 * s) && w.t_gnss - p->t_gnss < 5)
            add("CAMBIO_BRUSCO_CADENCIA", p->t_gnss, w.t_gnss, {"cadencia IMU " + std::to_string(w.imu_id)}, Quality::USABLE,
                "cambio de cadencia mayor que max(0,15 Hz, 3σ) entre ventanas consecutivas", std::string("cadencia ") + CADENCE_VERSION,
                {{"de_hz", p->cadence_hz}, {"a_hz", w.cadence_hz}, {"sigma_hz", s}});
        }
        prev[w.imu_id] = &w;
      }
      auto st = stat.find(w.imu_id);
      if (st != stat.end() && !std::isnan(w.cycle_corr) && (st->second.first - w.cycle_corr) / st->second.second > 3)
        add("PERDIDA_REGULARIDAD", w.t_gnss - 3, w.t_gnss + 3, {"correlación entre ciclos IMU " + std::to_string(w.imu_id)}, Quality::USABLE,
            "correlación entre ciclos más de 3 desviaciones robustas por debajo de la mediana de la sesión", std::string("cadencia ") + CADENCE_VERSION,
            {{"correlacion_ciclos", w.cycle_corr}, {"mediana_sesion", st->second.first}});
    }
  }
  // ---- GNSS quality loss: FIX (quality GOOD) lost for a while, or epochs missing
  if (g && !g->t.empty()) {
    bool seen_good = false; double lost = NAN;
    for (size_t i = 0; i < g->t.size(); i++) {
      bool good = g->quality[i] == (uint8_t)Quality::GOOD;
      if (i > 0 && g->t[i] - g->t[i - 1] > c.fix_loss_min_s)
        add("PERDIDA_CALIDAD_GNSS", g->t[i - 1], g->t[i], {"épocas GNSS"}, Quality::POOR, "sin épocas GNSS durante " + std::to_string(g->t[i] - g->t[i - 1]).substr(0, 4) + " s",
            "huecos de la serie GNSS", {{"duracion_s", g->t[i] - g->t[i - 1]}});
      if (good) {
        if (!std::isnan(lost) && g->t[i] - lost >= c.fix_loss_min_s)
          add("PERDIDA_CALIDAD_GNSS", lost, g->t[i], {"estado RTK", "precisión estimada"}, Quality::POOR, "RTK FIX con precisión suficiente perdido", "estado RTK por época",
              {{"duracion_s", g->t[i] - lost}});
        lost = NAN; seen_good = true;
      } else if (seen_good && std::isnan(lost)) lost = g->t[i];
    }
    if (!std::isnan(lost) && g->t.back() - lost >= c.fix_loss_min_s)
      add("PERDIDA_CALIDAD_GNSS", lost, g->t.back(), {"estado RTK"}, Quality::POOR, "RTK FIX perdido hasta el final de la sesión", "estado RTK por época", {{"duracion_s", g->t.back() - lost}});
  }
  // ---- synchronisation loss: girth data missing while GNSS continues
  if (in.imu && in.girth_to_gnss) for (auto& ser : *in.imu) {
    const ClockMap& m = in.girth_to_gnss[std::min<uint8_t>(ser.imu_id, 2)];
    for (size_t k = 1; k < ser.pieces.size(); k++) {
      double end = ser.pieces[k - 1].t0 + (ser.pieces[k - 1].amag.size() - 1) / ser.fs, start = ser.pieces[k].t0;
      if (start - end < c.sync_gap_s) continue;
      double a, b;
      if (m.map(end, &a) && m.map(start, &b))
        add("PERDIDA_SINCRONIZACION", a, b, {"IMU " + std::to_string(ser.imu_id)}, Quality::POOR, "sin datos de la cincha durante " + std::to_string(start - end).substr(0, 4) + " s",
            "huecos de las series IMU", {{"duracion_s", start - end}});
    }
    if (m.pieces.size() > 1)
      for (size_t k = 1; k < m.pieces.size(); k++) {
        double a; if (m.map(m.pieces[k].x0, &a))
          add("PERDIDA_SINCRONIZACION", a, a, {"mapa de reloj IMU " + std::to_string(ser.imu_id)}, Quality::POOR, "reinicio del reloj de la cincha (nuevo tramo del mapa)", "mapa de relojes", {});
      }
  }
  // ---- order, merge duplicates of the same type, assign ids
  std::sort(ev.begin(), ev.end(), [](const Event& a, const Event& b) { return a.t0 < b.t0 || (a.t0 == b.t0 && a.type < b.type); });
  std::vector<Event> out;
  for (auto& e : ev) {
    Event* dup = nullptr;
    for (auto it = out.rbegin(); it != out.rend() && e.t0 - it->t1 <= c.merge_s; ++it)
      if (it->type == e.type && e.type != "INICIO_CURVA" && e.type != "FIN_CURVA" && e.type != "TRANSICION_AIRE") { dup = &*it; break; }
    if (dup) { dup->t1 = std::max(dup->t1, e.t1); continue; }
    out.push_back(e);
  }
  for (size_t i = 0; i < out.size(); i++) { char b[16]; snprintf(b, sizeof(b), "EV%04zu", i + 1); out[i].id = b; }
  return out;
}

}  // namespace avoeq
