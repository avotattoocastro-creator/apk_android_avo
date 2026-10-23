#include "avo_eq/engine.h"
#include "avo_eq/dsp.h"
#include "avo_eq/session_sync.h"
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <sstream>

namespace avoeq {

// ------------------------------------------------------------------ anomalies (exploratory)
static void find_anomalies(Analysis& a) {
  // acquisition anomalies straight from validation
  for (const auto& is : a.validation.issues) {
    Anomaly an; an.kind = "ADQUISICION"; an.code = is.code; an.t0 = an.t1 = is.t_s;
    an.explanation = is.detail + " (" + std::to_string(is.count) + " veces)";
    an.evidence.push_back({"veces", (double)is.count});
    a.anomalies.push_back(an);
  }
  // GNSS acceleration events beyond 4 robust deviations of the session (only well-estimated points)
  std::vector<double> acc;
  for (size_t i = 0; i < a.gnss.accel.size(); i++) if (!std::isnan(a.gnss.accel[i]) && a.gnss.accel_sigma[i] < 0.5) acc.push_back(a.gnss.accel[i]);
  if (acc.size() > 20) {
    double med = dsp::median(acc), m = dsp::mad(acc) * 1.4826;
    if (m > 0.05) for (size_t i = 0; i < a.gnss.accel.size(); i++) {
      if (std::isnan(a.gnss.accel[i]) || a.gnss.accel_sigma[i] >= 0.5) continue;
      double z = (a.gnss.accel[i] - med) / m;
      if (std::fabs(z) > 4) {
        Anomaly an; an.kind = "MOVIMIENTO"; an.code = z > 0 ? "ACELERACION_BRUSCA" : "FRENADA_BRUSCA";
        an.t0 = an.t1 = a.gnss.t[i];
        an.explanation = "aceleración longitudinal a más de 4 desviaciones robustas de la mediana de la sesión";
        an.evidence = {{"aceleracion_m_s2", a.gnss.accel[i]}, {"incertidumbre_m_s2", a.gnss.accel_sigma[i]}, {"z_robusto", z}};
        // merge with the previous event when contiguous
        if (!a.anomalies.empty() && a.anomalies.back().code == an.code && an.t0 - a.anomalies.back().t1 < 0.5) a.anomalies.back().t1 = an.t1;
        else a.anomalies.push_back(an);
      }
    }
  }
  // loss of regularity in the IMU cadence windows (relative to the session itself)
  for (const auto& cr : a.cadence) {
    std::vector<double> cc;
    for (auto& w : cr.windows) if (w.cycle_corr >= 0) cc.push_back(w.cycle_corr);
    if (cc.size() < 10) continue;
    double med = dsp::median(cc), m = dsp::mad(cc) * 1.4826;
    if (m < 0.02) m = 0.02;
    for (auto& w : cr.windows) if (w.cycle_corr >= 0 && (med - w.cycle_corr) / m > 3) {
      Anomaly an; an.kind = "SIN_CLASIFICAR"; an.code = "PERDIDA_REGULARIDAD_IMU" + std::to_string(cr.imu_id);
      double tg; an.t0 = an.t1 = a.girth_to_gnss[cr.imu_id].map(w.t_mid, &tg) ? tg : w.t_mid;
      an.explanation = "la correlación entre ciclos cae más de 3 desviaciones robustas por debajo de la mediana de la sesión; puede ser un cambio de aire, terreno o un evento";
      an.evidence = {{"correlacion_ciclos", w.cycle_corr}, {"mediana_sesion", med}};
      a.anomalies.push_back(an);
    }
  }
  // gait changes are reported as such, not as anomalies of movement
  for (size_t i = 1; i < a.gait.segments.size(); i++) {
    Anomaly an; an.kind = "CAMBIO_DE_AIRE"; an.code = std::string(gait_name(a.gait.segments[i - 1].gait)) + "->" + gait_name(a.gait.segments[i].gait);
    an.t0 = an.t1 = a.gait.segments[i].t0; an.explanation = "transición entre aires detectada por el clasificador";
    a.anomalies.push_back(an);
  }
}

// ------------------------------------------------------------------ quality
static void assess_quality(const Session& s, Analysis& a) {
  auto add = [&](const char* d, Quality q, std::vector<std::string> why) { QualityIndicator i; i.domain = d; i.level = q; i.reasons = why; a.quality.push_back(i); };
  const RtkStats& k = a.gnss.rtk;
  if (s.gnss.empty()) add("GNSS", Quality::UNUSABLE, {"la sesión no contiene posiciones GNSS"});
  else {
    double fx = k.total_s > 0 ? k.fixed_s / k.total_s : 0;
    char b[160]; snprintf(b, sizeof(b), "RTK FIX %.0f %% del tiempo, FLOAT %.0f %%, sin solución %.0f %%", 100 * fx, 100 * k.float_s / std::max(1e-9, k.total_s), 100 * k.none_s / std::max(1e-9, k.total_s));
    std::vector<std::string> why{b};
    if (k.hacc_median_fixed_m >= 0) { snprintf(b, sizeof(b), "precisión horizontal estimada por el receptor en FIX: %.3f m (estimación, no exactitud comprobada)", k.hacc_median_fixed_m); why.push_back(b); }
    if (a.validation.gnss_gaps) why.push_back(std::to_string(a.validation.gnss_gaps) + " huecos, " + std::to_string(a.validation.gnss_missing_epochs) + " épocas perdidas");
    add("GNSS", fx > 0.9 ? Quality::GOOD : fx > 0.5 ? Quality::USABLE : Quality::POOR, why);
  }
  if (s.imu.empty()) add("IMU", Quality::UNUSABLE, {"la sesión no contiene datos de la cincha"});
  else {
    std::vector<std::string> why; uint32_t miss = 0, sat = a.validation.imu_saturated;
    for (int i = 0; i < 3; i++) { miss += a.validation.imu_missing[i]; if (a.validation.imu_nominal_hz[i] > 0) why.push_back("IMU " + std::to_string(i) + ": " + std::to_string((int)std::lround(a.validation.imu_nominal_hz[i])) + " Hz medidos, " + std::to_string(a.validation.imu_missing[i]) + " muestras perdidas"); }
    double frac_sat = (double)sat / s.imu.size(), frac_miss = (double)miss / (s.imu.size() + miss);
    if (sat) why.push_back(std::to_string(sat) + " muestras en el límite del conversor (saturación)");
    add("IMU", frac_miss < 0.01 && frac_sat < 0.001 ? Quality::GOOD : frac_miss < 0.05 && frac_sat < 0.01 ? Quality::USABLE : Quality::POOR, why);
  }
  {
    std::vector<std::string> why; Quality q = Quality::GOOD;
    for (auto& p : a.chest_to_gnss.pieces) { char b[200]; snprintf(b, sizeof(b), "pecho->GNSS: incertidumbre %.1f ms, latencia mediana %.1f ms (p95 %.1f), deriva %.0f ppm", p.envelope_sd_s * 1e3, p.latency_median_s * 1e3, p.latency_p95_s * 1e3, p.drift_ppm); why.push_back(b); }
    for (int i = 0; i < 3; i++) for (auto& p : a.girth_to_gnss[i].pieces) {
      char b[200]; snprintf(b, sizeof(b), "IMU %d->GNSS: incertidumbre %.1f ms, deriva %.0f ppm", i, p.envelope_sd_s * 1e3, p.drift_ppm); why.push_back(b);
      if (p.envelope_sd_s > 0.010) q = std::max(q, Quality::USABLE);
      if (p.envelope_sd_s > 0.050) q = Quality::POOR;
    }
    if (a.chest_to_gnss.pieces.empty()) { q = Quality::UNKNOWN; why.push_back("no hay suficientes pares para estimar la relación de relojes"); }
    if (!s.imu.empty() && a.girth_to_gnss[0].pieces.empty() && a.girth_to_gnss[1].pieces.empty() && a.girth_to_gnss[2].pieces.empty()) { q = Quality::POOR; why.push_back("no se pudo relacionar el reloj de la cincha con el tiempo GNSS"); }
    why.push_back("sin PPS: sincronía por marcas de tiempo de recepción (envolvente de mínima latencia)");
    add("TIEMPO", q, why);
  }
  add("INTEGRIDAD", s.bad_records == 0 && !s.tail_garbage ? Quality::GOOD : Quality::USABLE,
      {std::to_string(s.records) + " registros, " + std::to_string(s.bad_records) + " dañados", s.clean_close ? "cierre limpio" : "sin cierre limpio (sesión recuperada)"});
  add("CALIBRACION", s.imu.empty() ? Quality::UNKNOWN : Quality::POOR, {"modelo, rango y sesgos de las IMU desconocidos: amplitudes en LSB sin calibrar; solo métricas independientes de escala son comparables"});
  add("ALGORITMO", Quality::USABLE, {"umbrales iniciales sin validar con datos etiquetados; resultados exploratorios, no diagnósticos veterinarios"});
}

Analysis analyse(const Session& s, const EngineConfig& c, const std::string& when) {
  Analysis a;
  a.engine_version = ENGINE_VERSION; a.processed_at_utc = when; a.session_id = s.session_id;
  a.validation = validate(s, c.validation);
  a.gnss = analyse_gnss(s, a.validation, c.gnss);
  build_session_maps(s, a.validation, c.sync, -1, &a.chest_to_gnss, a.girth_to_gnss);
  a.imu = build_imu_series(s, a.validation);
  for (auto& ser : a.imu) a.cadence.push_back(analyse_cadence(ser, c.cadence));
  const CadenceResult* cad = nullptr; const ClockMap* map = nullptr;
  for (auto& cr : a.cadence) if (cr.imu_id == 0) { cad = &cr; map = &a.girth_to_gnss[0]; }
  if (!cad && !a.cadence.empty()) { cad = &a.cadence[0]; map = &a.girth_to_gnss[std::min<uint8_t>(a.cadence[0].imu_id, 2)]; }
  a.gait = classify_gait(a.gnss, cad, map, c.gait);
  find_anomalies(a);
  assess_quality(s, a);
  return a;
}

// ------------------------------------------------------------------ JSON / CSV
namespace {
std::string esc(const std::string& s) {
  std::string o;
  for (char ch : s) {
    switch (ch) { case '"': o += "\\\""; break; case '\\': o += "\\\\"; break; case '\n': o += "\\n"; break;
      default: if ((unsigned char)ch < 0x20) { char b[8]; snprintf(b, sizeof(b), "\\u%04x", ch); o += b; } else o += ch; }
  }
  return o;
}
std::string num(double v) { if (std::isnan(v) || std::isinf(v)) return "null"; char b[40]; snprintf(b, sizeof(b), "%.10g", v); return b; }
void metric_json(std::ostringstream& o, const Metric& m) {
  o << "{\"nombre\":\"" << esc(m.name) << "\",\"valor\":" << num(m.value) << ",\"unidad\":\"" << esc(m.unit)
    << "\",\"algoritmo\":\"" << esc(m.algorithm) << "\",\"version\":\"" << esc(m.version) << "\",\"calidad\":\"" << quality_name(m.quality)
    << "\",\"incertidumbre\":" << (m.uncertainty < 0 ? "null" : num(m.uncertainty)) << ",\"muestras_usadas\":" << m.samples_used
    << ",\"muestras_excluidas\":" << m.samples_excluded << ",\"avisos\":[";
  for (size_t i = 0; i < m.warnings.size(); i++) o << (i ? "," : "") << "\"" << esc(m.warnings[i]) << "\"";
  o << "]}";
}
}  // namespace

std::string to_json(const Analysis& a, const Session& s, const EngineConfig& c, bool series) {
  std::ostringstream o;
  o << "{\"formato\":\"avo-equine-analysis\",\"version_formato\":1,\"motor\":\"" << a.engine_version << "\",\"procesado_utc\":\"" << esc(a.processed_at_utc)
    << "\",\"sesion\":{\"id\":\"" << esc(s.session_id) << "\",\"caballo\":\"" << esc(s.horse) << "\",\"jinete\":\"" << esc(s.rider)
    << "\",\"fw_pecho\":\"" << esc(s.chest_fw) << "\",\"fw_espalda\":\"" << esc(s.back_fw) << "\",\"segmentos\":" << s.segments
    << ",\"epocas_gnss\":" << s.gnss.size() << ",\"muestras_imu\":" << s.imu.size() << ",\"marcas\":" << s.markers.size() << "}";
  o << ",\"parametros\":{\"gnss_ventana_derivada_s\":" << num(c.gnss.deriv_half_window_s) << ",\"cadencia_ventana_s\":" << num(c.cadence.window_s)
    << ",\"cadencia_f_min\":" << num(c.cadence.f_min) << ",\"cadencia_f_max\":" << num(c.cadence.f_max)
    << ",\"aire_v_parado\":" << num(c.gait.stop_max) << ",\"aire_v_paso\":" << num(c.gait.walk_max) << ",\"aire_v_trote\":" << num(c.gait.trot_max)
    << ",\"aire_confirmacion_ventanas\":" << c.gait.confirm_windows << ",\"hacc_max_m\":" << num(c.validation.max_hacc_m) << "}";
  o << ",\"metricas\":[";
  bool first = true;
  auto put = [&](const Metric& m) { if (!first) o << ","; first = false; metric_json(o, m); };
  for (auto& m : a.gnss.metrics) put(m);
  for (auto& cr : a.cadence) for (auto m : cr.metrics) { m.name += "_imu" + std::to_string(cr.imu_id); put(m); }
  for (auto& m : a.gait.metrics) put(m);
  o << "],\"rtk\":{\"total_s\":" << num(a.gnss.rtk.total_s) << ",\"fix_s\":" << num(a.gnss.rtk.fixed_s) << ",\"float_s\":" << num(a.gnss.rtk.float_s)
    << ",\"dgnss_s\":" << num(a.gnss.rtk.dgnss_s) << ",\"gnss_s\":" << num(a.gnss.rtk.gnss_s) << ",\"sin_solucion_s\":" << num(a.gnss.rtk.none_s)
    << ",\"tiempo_hasta_fix_s\":" << num(a.gnss.rtk.time_to_first_fix_s) << ",\"perdidas_fix\":" << a.gnss.rtk.fix_losses
    << ",\"interrupcion_max_s\":" << num(a.gnss.rtk.longest_outage_s) << ",\"interrupcion_media_s\":" << num(a.gnss.rtk.mean_outage_s)
    << ",\"edad_correccion_max_s\":" << num(a.gnss.rtk.corr_age_max_s) << ",\"hacc_mediana_fix_m\":" << num(a.gnss.rtk.hacc_median_fixed_m) << "}";
  o << ",\"aires\":{\"algoritmo\":\"" << esc(a.gait.algorithm) << "\",\"version\":\"" << a.gait.version << "\",\"segmentos\":[";
  for (size_t i = 0; i < a.gait.segments.size(); i++) {
    auto& g = a.gait.segments[i];
    o << (i ? "," : "") << "{\"aire\":\"" << gait_name(g.gait) << "\",\"t0\":" << num(g.t0) << ",\"t1\":" << num(g.t1) << ",\"calidad\":\"" << quality_name(g.quality) << "\",\"base\":\"" << esc(g.basis) << "\"}";
  }
  o << "]},\"anomalias\":[";
  for (size_t i = 0; i < a.anomalies.size(); i++) {
    auto& an = a.anomalies[i];
    o << (i ? "," : "") << "{\"tipo\":\"" << an.kind << "\",\"codigo\":\"" << esc(an.code) << "\",\"t0\":" << num(an.t0) << ",\"t1\":" << num(an.t1)
      << ",\"explicacion\":\"" << esc(an.explanation) << "\",\"datos\":{";
    for (size_t k = 0; k < an.evidence.size(); k++) o << (k ? "," : "") << "\"" << esc(an.evidence[k].first) << "\":" << num(an.evidence[k].second);
    o << "}}";
  }
  o << "],\"calidad\":[";
  for (size_t i = 0; i < a.quality.size(); i++) {
    auto& q = a.quality[i];
    o << (i ? "," : "") << "{\"dominio\":\"" << q.domain << "\",\"nivel\":\"" << quality_name(q.level) << "\",\"motivos\":[";
    for (size_t k = 0; k < q.reasons.size(); k++) o << (k ? "," : "") << "\"" << esc(q.reasons[k]) << "\"";
    o << "]}";
  }
  o << "]";
  if (series) {
    o << ",\"series\":{\"t\":[";
    for (size_t i = 0; i < a.gnss.t.size(); i++) o << (i ? "," : "") << num(a.gnss.t[i]);
    o << "],\"velocidad\":[";
    for (size_t i = 0; i < a.gnss.speed.size(); i++) o << (i ? "," : "") << num(a.gnss.speed[i]);
    o << "],\"aceleracion\":[";
    for (size_t i = 0; i < a.gnss.accel.size(); i++) o << (i ? "," : "") << num(a.gnss.accel[i]);
    o << "]}";
  }
  o << "}";
  return o.str();
}

std::string gnss_csv(const Analysis& a) {
  std::ostringstream o;
  o << "t_s,velocidad_m_s,aceleracion_m_s2,sigma_aceleracion_m_s2,giro_deg_s,radio_m,distancia_m,calidad\n";
  for (size_t i = 0; i < a.gnss.t.size(); i++)
    o << num(a.gnss.t[i]) << "," << num(a.gnss.speed[i]) << "," << num(a.gnss.accel[i]) << "," << num(a.gnss.accel_sigma[i]) << ","
      << num(a.gnss.heading_rate[i]) << "," << num(a.gnss.radius[i]) << "," << num(a.gnss.dist[i]) << "," << quality_name((Quality)a.gnss.quality[i]) << "\n";
  return o.str();
}
std::string gait_csv(const Analysis& a) {
  std::ostringstream o;
  o << "aire,t0_s,t1_s,calidad,base,algoritmo,version\n";
  for (auto& g : a.gait.segments) o << gait_name(g.gait) << "," << num(g.t0) << "," << num(g.t1) << "," << quality_name(g.quality) << ",\"" << g.basis << "\",\"" << a.gait.algorithm << "\"," << a.gait.version << "\n";
  return o.str();
}
std::string cadence_csv(const Analysis& a) {
  std::ostringstream o;
  o << "imu,t_cincha_s,t_gnss_s,frecuencia_hz,ciclos_min,fuerza,cv_intervalos,cv_amplitud,correlacion_ciclos,relacion_medio_ciclo,rms_lsb\n";
  for (auto& cr : a.cadence) for (auto& w : cr.windows) {
    double tg = std::nan("");
    a.girth_to_gnss[std::min<uint8_t>(cr.imu_id, 2)].map(w.t_mid, &tg);
    o << (int)cr.imu_id << "," << num(w.t_mid) << "," << num(tg) << "," << num(w.freq_hz) << "," << num(w.cpm) << "," << num(w.strength) << "," << num(w.interval_cv) << ","
      << num(w.amplitude_cv) << "," << num(w.cycle_corr) << "," << num(w.half_cycle_ratio) << "," << num(w.rms) << "\n";
  }
  return o.str();
}

}  // namespace avoeq
