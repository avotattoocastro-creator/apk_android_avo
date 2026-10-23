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

std::vector<std::pair<std::string, std::string>> algorithm_versions() {
  return {{"motor", ENGINE_VERSION}, {"gnss", "1.1.0"}, {"aceleracion", KINEMATICS_VERSION}, {"curvas", CURVES_VERSION},
          {"cadencia", CADENCE_VERSION}, {GAIT_V1_ID, "1.0.1"}, {GAIT_V2_ID, "2.0.0"}, {"fusion", FUSION_VERSION},
          {"rendimiento", PERFORMANCE_VERSION}, {"eventos", EVENTS_VERSION}, {"simetria", SYMMETRY_VERSION}};
}

std::string params_hash(const EngineConfig& c) {
  // FNV-1a over the textual values of every parameter that changes results
  char b[1024];
  snprintf(b, sizeof(b), "%g|%g|%g|%d|%g|%g|%g|%g|%g|%g|%g|%g|%g|%g|%d|%g|%g|%g|%g|%g|%d|%g|%g|%g|%g|%d|%g|%g|%d|%s|%d",
           c.validation.max_hacc_m, c.validation.max_sacc_ms, c.validation.max_speed_ms, c.validation.min_sats,
           c.gnss.deriv_half_window_s, c.gnss.min_speed_heading_ms, c.cadence.window_s, c.cadence.hop_s, c.cadence.f_min, c.cadence.f_max,
           c.cadence.min_strength, c.cadence.max_rel_uncertainty, c.cadence.max_bridge_s, c.cadence.max_interp_fraction,
           c.gait.confirm_windows, c.gait.stop_max, c.gait.walk_max, c.gait.trot_max, c.gait.min_segment_s, c.gait_v2.min_score,
           c.gait_v2.confirm_points, c.accel.sustained_min, c.accel.peak_min, c.curves.enter_radius, c.curves.exit_radius,
           (int)c.fusion.mode, c.fusion.max_sync_sigma_s, c.symmetry.min_cycle_corr, (int)c.performance_uses_v2,
           c.gait_model ? c.gait_model->id().c_str() : "-", c.symmetry.sensors_calibrated ? 1 : 0);
  uint64_t h = 1469598103934665603ull;
  for (const char* p = b; *p; p++) { h ^= (uint8_t)*p; h *= 1099511628211ull; }
  char out[20]; snprintf(out, sizeof(out), "%016llx", (unsigned long long)h);
  return out;
}

static void fill_curve_cadence(Analysis& a) {
  for (auto& cv : a.curves.curves) {
    std::vector<double> fb, fd, fa, cb, cd;
    for (auto& w : a.fusion.windows) {
      if (w.status != "OK" || std::isnan(w.t_gnss)) continue;
      if (w.t_gnss >= cv.t0 - 8 && w.t_gnss < cv.t0) { fb.push_back(w.cadence_hz); if (!std::isnan(w.cycle_corr)) cb.push_back(w.cycle_corr); }
      else if (w.t_gnss >= cv.t0 && w.t_gnss <= cv.t1) { fd.push_back(w.cadence_hz); if (!std::isnan(w.cycle_corr)) cd.push_back(w.cycle_corr); }
      else if (w.t_gnss > cv.t1 && w.t_gnss <= cv.t1 + 8) fa.push_back(w.cadence_hz);
    }
    if (!fb.empty()) cv.cadence_before_hz = dsp::mean(fb);
    if (!fd.empty()) cv.cadence_during_hz = dsp::mean(fd);
    if (!fa.empty()) cv.cadence_after_hz = dsp::mean(fa);
    if (!cb.empty()) cv.cycle_corr_before = dsp::median(cb);
    if (!cd.empty()) cv.cycle_corr_during = dsp::median(cd);
    if (fd.empty() && !a.has_imu) cv.warnings.push_back("SIN DATOS DE CINCHA: sin cadencia en la curva");
  }
}

Analysis analyse(const Session& s, const EngineConfig& c, const std::string& when) {
  auto step = [&]() { if (c.cancel && *c.cancel) throw Cancelled(); };
  Analysis a;
  a.engine_version = ENGINE_VERSION; a.processed_at_utc = when; a.session_id = s.session_id;
  a.mode = c.fusion.mode; a.parameters_hash = params_hash(c);
  a.has_imu = !s.imu.empty(); a.has_gnss = !s.gnss.empty();
  if (!a.has_imu) a.warnings.push_back("SIN DATOS DE CINCHA");
  if (!a.has_gnss) a.warnings.push_back("SIN DATOS GNSS: sin velocidad, distancia ni recorrido");
  a.validation = validate(s, c.validation); step();
  a.gnss = analyse_gnss(s, a.validation, c.gnss); step();
  build_session_maps(s, a.validation, c.sync, -1, &a.chest_to_gnss, a.girth_to_gnss); step();
  a.imu = build_imu_series(s, a.validation); step();
  for (auto& ser : a.imu) { a.cadence.push_back(analyse_cadence(ser, c.cadence)); step(); }
  const CadenceResult* cad = nullptr; const ClockMap* map = nullptr;
  for (auto& cr : a.cadence) if (cr.imu_id == 0) { cad = &cr; map = &a.girth_to_gnss[0]; }
  if (!cad && !a.cadence.empty()) { cad = &a.cadence[0]; map = &a.girth_to_gnss[std::min<uint8_t>(a.cadence[0].imu_id, 2)]; }
  a.gait = classify_gait(a.gnss, cad, map, c.gait); step();
  a.gait_v2 = classify_gait_v2(a.gnss, cad, map, c.gait_v2, c.gait_model); step();
  a.kinematics = analyse_kinematics(a.gnss, c.accel);
  a.curves = analyse_curves(a.gnss, c.curves); step();
  const GaitResult& chosen = c.performance_uses_v2 ? a.gait_v2 : a.gait;
  if (c.fusion.mode == AnalysisMode::REALTIME_ANALYSIS) a.fusion = fuse_realtime(s, a.validation, a.imu, c.cadence, c.sync, c.fusion);
  else a.fusion = fuse_offline(a.gnss, a.cadence, a.girth_to_gnss, &chosen, c.fusion);
  step();
  fill_curve_cadence(a);
  a.performance = analyse_performance(chosen, a.gnss, &a.fusion, a.has_imu, c.perf); step();
  a.symmetry = analyse_symmetry(a.imu, a.cadence, a.girth_to_gnss, &chosen, c.cadence, c.symmetry); step();
  EventInputs in; in.gnss = &a.gnss; in.kin = &a.kinematics; in.curves = &a.curves; in.gait = &chosen; in.fusion = &a.fusion;
  in.validation = &a.validation; in.imu = &a.imu; in.girth_to_gnss = a.girth_to_gnss;
  a.events = detect_events(in, c.events);
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


// ------------------------------------------------------------------ format v2 blocks
namespace {
template <class T, class F> void arr(std::ostringstream& o, const std::vector<T>& v, F f) { o << "["; for (size_t i = 0; i < v.size(); i++) { if (i) o << ","; f(v[i]); } o << "]"; }
void strs(std::ostringstream& o, const std::vector<std::string>& v) { arr(o, v, [&](const std::string& x) { o << "\"" << esc(x) << "\""; }); }
void spread_json(std::ostringstream& o, const Spread& s) {
  o << "{\"mediana\":" << num(s.median) << ",\"iqr\":" << num(s.iqr) << ",\"n\":" << s.n << ",\"consistencia_signo\":" << num(s.sign_consistency)
    << ",\"reproducible\":" << (s.reproducible ? "true" : "false") << "}";
}
}  // namespace

static void write_v2_blocks(std::ostringstream& o, const Analysis& a, const Session& s) {
  o << ",\"procedencia\":{\"sesion\":\"" << esc(s.session_id) << "\",\"huella_entrada\":\"" << esc(a.input_fingerprint) << "\",\"hash_parametros\":\"" << a.parameters_hash
    << "\",\"modo\":\"" << mode_name(a.mode) << "\",\"itow_inicial_ms\":" << (s.gnss.empty() ? std::string("null") : std::to_string(s.gnss[0].itow_ms)) << ",\"algoritmos\":{";
  auto av = algorithm_versions();
  for (size_t i = 0; i < av.size(); i++) o << (i ? "," : "") << "\"" << esc(av[i].first) << "\":\"" << esc(av[i].second) << "\"";
  o << "},\"unidades\":{\"t\":\"s (tiempo GNSS desde la primera época)\",\"velocidad\":\"m/s\",\"aceleracion\":\"m/s2\",\"distancia\":\"m\",\"cadencia\":\"Hz (ciclos de tranco por segundo)\",\"imu\":\"LSB sin calibrar\",\"angulos\":\"grados\"},"
    << "\"tiene_cincha\":" << (a.has_imu ? "true" : "false") << ",\"tiene_gnss\":" << (a.has_gnss ? "true" : "false") << "}";
  o << ",\"advertencias\":"; strs(o, a.warnings);
  // kinematics
  o << ",\"cinematica\":{\"fuente\":\"TRAYECTORIA_GNSS\",\"nota\":\"aceleración de la trayectoria de la antena del jinete; no es la aceleración de las IMU de la cincha\",\"descartadas_fisicas\":"
    << a.kinematics.rejected_physical << ",\"eventos\":";
  arr(o, a.kinematics.events, [&](const AccelEvent& e) {
    o << "{\"tipo\":\"" << e.type << "\",\"t0\":" << num(e.t0) << ",\"t1\":" << num(e.t1) << ",\"t_pico\":" << num(e.t_peak) << ",\"pico_m_s2\":" << num(e.peak)
      << ",\"sigma_pico_m_s2\":" << num(e.peak_sigma) << ",\"media_m_s2\":" << num(e.mean) << ",\"v0\":" << num(e.v0) << ",\"v1\":" << num(e.v1) << ",\"dv\":" << num(e.dv)
      << ",\"calidad\":\"" << quality_name(e.quality) << "\",\"fuente\":\"" << e.source << "\"}"; });
  o << ",\"metricas\":"; arr(o, a.kinematics.metrics, [&](const Metric& m) { metric_json(o, m); });
  o << "}";
  // curves
  o << ",\"curvas\":{\"version\":\"" << CURVES_VERSION << "\",\"descartadas\":{\"cortas\":" << a.curves.rejected_short << ",\"giro_pequeno\":" << a.curves.rejected_small_turn
    << ",\"calidad\":" << a.curves.rejected_quality << "},\"lista\":";
  arr(o, a.curves.curves, [&](const Curve& c) {
    o << "{\"id\":" << c.id << ",\"direccion\":\"" << c.direction << "\",\"t0\":" << num(c.t0) << ",\"t1\":" << num(c.t1) << ",\"epoca0\":" << c.i0 << ",\"epoca1\":" << c.i1
      << ",\"giro_deg\":" << num(c.heading_change_deg) << ",\"radio_m\":" << num(c.radius_m) << ",\"radio_sigma_m\":" << num(c.radius_sigma_m)
      << ",\"radio_geometrico_m\":" << (c.radius_geom_m < 0 ? std::string("null") : num(c.radius_geom_m))
      << ",\"centro_lat\":" << num(c.center_lat) << ",\"centro_lon\":" << num(c.center_lon) << ",\"centro_ajustado\":" << (c.center_from_fit ? "true" : "false")
      << ",\"v_entrada\":" << num(c.v_entry) << ",\"v_salida\":" << num(c.v_exit) << ",\"v_media\":" << num(c.v_mean) << ",\"v_min\":" << num(c.v_min)
      << ",\"a_lateral_media\":" << num(c.lat_acc_mean) << ",\"a_lateral_max\":" << num(c.lat_acc_max) << ",\"a_lateral_sigma\":" << num(c.lat_acc_sigma)
      << ",\"distancia_m\":" << num(c.distance_m)
      << ",\"cadencia_antes_hz\":" << (c.cadence_before_hz < 0 ? std::string("null") : num(c.cadence_before_hz))
      << ",\"cadencia_durante_hz\":" << (c.cadence_during_hz < 0 ? std::string("null") : num(c.cadence_during_hz))
      << ",\"cadencia_despues_hz\":" << (c.cadence_after_hz < 0 ? std::string("null") : num(c.cadence_after_hz))
      << ",\"correlacion_ciclos_antes\":" << (c.cycle_corr_before < 0 ? std::string("null") : num(c.cycle_corr_before))
      << ",\"correlacion_ciclos_durante\":" << (c.cycle_corr_during < 0 ? std::string("null") : num(c.cycle_corr_during))
      << ",\"calidad\":\"" << quality_name(c.quality) << "\",\"avisos\":"; strs(o, c.warnings); o << "}"; });
  o << "}";
  // gait V2
  o << ",\"aires_v2\":{\"clasificador\":\"" << a.gait_v2.classifier << "\",\"algoritmo\":\"" << esc(a.gait_v2.algorithm) << "\",\"version\":\"" << a.gait_v2.version
    << "\",\"nota\":\"evaluable con los mismos datos que GAIT_CLASSIFIER_V1; no se declara superior sin datos etiquetados\",\"segmentos\":";
  arr(o, a.gait_v2.segments, [&](const GaitSegment& g) {
    o << "{\"aire\":\"" << gait_name(g.gait) << "\",\"codigo\":\"" << gait_code(g.gait) << "\",\"t0\":" << num(g.t0) << ",\"t1\":" << num(g.t1) << ",\"calidad\":\""
      << quality_name(g.quality) << "\",\"confianza\":" << num(g.confidence) << ",\"base\":\"" << esc(g.basis) << "\"}"; });
  o << "}";
  // performance per gait
  auto aggj = [&](const GaitAggregate& g) {
    o << "{\"aire\":\"" << gait_name(g.gait) << "\",\"codigo\":\"" << gait_code(g.gait) << "\",\"segmentos\":" << g.segments << ",\"duracion_s\":" << num(g.duration_s)
      << ",\"distancia_m\":" << num(g.distance_m) << ",\"velocidad_media\":" << num(g.speed_mean) << ",\"velocidad_max\":" << num(g.speed_max)
      << ",\"cadencia_media_hz\":" << num(g.cadence_mean_hz) << ",\"longitud_tranco_m\":" << num(g.stride_length_m) << ",\"fraccion_tiempo\":" << num(g.time_fraction) << "}"; };
  o << ",\"rendimiento\":{\"clasificador\":\"" << a.performance.classifier << "\",\"version\":\"" << PERFORMANCE_VERSION << "\",\"segmentos\":";
  arr(o, a.performance.segments, [&](const SegmentPerformance& p) {
    o << "{\"id\":" << p.id << ",\"aire\":\"" << gait_name(p.gait) << "\",\"codigo\":\"" << gait_code(p.gait) << "\",\"t0\":" << num(p.t0) << ",\"t1\":" << num(p.t1)
      << ",\"duracion_s\":" << num(p.duration_s) << ",\"distancia_m\":" << num(p.distance_m) << ",\"velocidad_media\":" << num(p.speed_mean) << ",\"velocidad_max\":" << num(p.speed_max)
      << ",\"aceleracion_max\":" << num(p.accel_max) << ",\"desaceleracion_max\":" << num(p.decel_max) << ",\"cadencia_media_hz\":" << num(p.cadence_mean_hz)
      << ",\"cadencia_cv\":" << num(p.cadence_cv) << ",\"cadencia_sigma_hz\":" << num(p.cadence_sigma_hz) << ",\"cv_intervalos\":" << num(p.interval_cv)
      << ",\"cv_amplitud\":" << num(p.amplitude_cv) << ",\"correlacion_ciclos\":" << num(p.cycle_corr) << ",\"estabilidad_espectral\":" << num(p.spectral_stability)
      << ",\"longitud_tranco_m\":" << num(p.stride_length_m) << ",\"fraccion_fix\":" << num(p.gnss_fix_fraction) << ",\"fraccion_gnss_util\":" << num(p.gnss_usable_fraction)
      << ",\"fraccion_imu_valida\":" << num(p.imu_valid_fraction) << ",\"calidad_gnss\":\"" << quality_name(p.gnss_quality) << "\",\"calidad_imu\":\"" << quality_name(p.imu_quality)
      << "\",\"calidad_clasificacion\":\"" << quality_name(p.class_quality) << "\",\"confianza\":" << num(p.class_confidence) << ",\"avisos\":"; strs(o, p.warnings); o << "}"; });
  o << ",\"por_aire\":"; arr(o, a.performance.per_gait, aggj);
  o << ",\"sesion\":"; aggj(a.performance.session);
  o << "}";
  // fusion
  const FusionResult& f = a.fusion;
  o << ",\"fusion\":{\"modo\":\"" << mode_name(f.mode) << "\",\"version\":\"" << FUSION_VERSION << "\",\"ventanas\":" << f.windows_total << ",\"ventanas_ok\":" << f.windows_ok
    << ",\"sin_sincronia\":" << f.no_sync << ",\"hueco_gnss\":" << f.gnss_gap << ",\"sin_cadencia\":" << f.no_cadence
    << ",\"incertidumbre_temporal_mediana_ms\":" << num(f.median_sigma_t_ms) << ",\"relaciones\":";
  arr(o, f.relations, [&](const Relation& r) {
    o << "{\"x\":\"" << r.x << "\",\"y\":\"" << r.y << "\",\"aire\":\"" << esc(r.gait) << "\",\"n\":" << r.n << ",\"pendiente\":" << num(r.slope) << ",\"ordenada\":" << num(r.intercept)
      << ",\"sigma_pendiente\":" << num(r.slope_sigma) << ",\"r\":" << num(r.r) << ",\"spearman\":" << num(r.spearman) << ",\"nota\":\"" << esc(r.note) << "\"}"; });
  o << ",\"avisos\":"; strs(o, f.warnings); o << "}";
  // symmetry
  const SymmetryResult& y = a.symmetry;
  o << ",\"simetria\":{\"etiqueta\":\"" << y.label << "\",\"version\":\"" << y.version << "\",\"conclusiones_permitidas\":" << (y.conclusions_allowed ? "true" : "false")
    << ",\"ventanas_usadas\":" << y.windows_used << ",\"excluidas\":{\"irregulares\":" << y.excluded_irregular << ",\"saturadas\":" << y.excluded_saturated << ",\"estado\":" << y.excluded_status << "},\"controles\":";
  arr(o, y.controls, [&](const SymmetryControl& c) { o << "{\"control\":\"" << c.control << "\",\"estado\":\"" << c.state << "\",\"motivo\":\"" << esc(c.reason) << "\"}"; });
  o << ",\"grupos\":";
  arr(o, y.groups, [&](const SymmetryGroup& g) {
    o << "{\"imu\":" << (int)g.imu_id << ",\"aire\":\"" << esc(g.gait) << "\",\"ventanas\":" << g.windows << ",\"trancos\":" << g.strides << ",\"log_cociente_amplitud\":";
    spread_json(o, g.amp_log_ratio); o << ",\"asimetria_temporal\":"; spread_json(o, g.timing_asym); o << ",\"similitud_mitades\":"; spread_json(o, g.half_similarity);
    o << ",\"energia_vertical_estimada\":"; spread_json(o, g.vertical_energy); o << ",\"cociente_horizontal\":"; spread_json(o, g.horizontal_ratio); o << "}"; });
  o << ",\"entre_sensores\":";
  arr(o, y.inter, [&](const InterSensor& i) {
    o << "{\"a\":" << (int)i.a << ",\"b\":" << (int)i.b << ",\"aire\":\"" << esc(i.gait) << "\",\"estado\":\"" << i.state << "\",\"motivo\":\"" << esc(i.reason) << "\",\"retardo_s\":";
    spread_json(o, i.lag_s); o << ",\"retardo_fraccion_ciclo\":"; spread_json(o, i.lag_cycle_fraction); o << ",\"cociente_rms\":"; spread_json(o, i.rms_ratio); o << "}"; });
  o << ",\"notas\":"; strs(o, y.notes); o << "}";
  // events
  o << ",\"eventos\":";
  arr(o, a.events, [&](const Event& e) {
    o << "{\"id\":\"" << e.id << "\",\"tipo\":\"" << e.type << "\",\"t0\":" << num(e.t0) << ",\"t1\":" << num(e.t1) << ",\"datos\":"; strs(o, e.data);
    o << ",\"calidad\":\"" << quality_name(e.quality) << "\",\"motivo\":\"" << esc(e.reason) << "\",\"algoritmo\":\"" << esc(e.algorithm) << "\",\"version\":\"" << e.version << "\",\"valores\":{";
    for (size_t k = 0; k < e.values.size(); k++) o << (k ? "," : "") << "\"" << esc(e.values[k].first) << "\":" << num(e.values[k].second);
    o << "}}"; });
  // cadence window status counts
  o << ",\"cadencia_estado_ventanas\":";
  arr(o, a.cadence, [&](const CadenceResult& cr) {
    int n[5] = {0, 0, 0, 0, 0}; for (auto& w : cr.windows) n[std::min<int>((int)w.status, 4)]++;
    o << "{\"imu\":" << (int)cr.imu_id << ",\"fs_hz\":" << num(cr.fs);
    for (int k = 0; k < 5; k++) o << ",\"" << cadence_status_name((CadenceStatus)k) << "\":" << n[k];
    o << "}"; });
}

static void write_series(std::ostringstream& o, const Analysis& a, const EngineConfig& c) {
  const GnssResult& g = a.gnss;
  auto col = [&](const char* name, const std::vector<double>& v) { o << ",\"" << name << "\":["; for (size_t i = 0; i < v.size(); i++) o << (i ? "," : "") << num(v[i]); o << "]"; };
  o << ",\"series\":{\"t\":["; for (size_t i = 0; i < g.t.size(); i++) o << (i ? "," : "") << num(g.t[i]); o << "]";
  col("velocidad", g.speed); col("aceleracion", g.accel); col("sigma_velocidad", g.speed_sigma); col("sigma_aceleracion", g.accel_sigma);
  col("aceleracion_lateral", g.lat_accel); col("curvatura", g.curvature); col("distancia", g.dist); col("lat", g.lat); col("lon", g.lon);
  o << ",\"calidad\":["; for (size_t i = 0; i < g.quality.size(); i++) o << (i ? "," : "") << (int)g.quality[i]; o << "]";
  const GaitResult& chosen = c.performance_uses_v2 ? a.gait_v2 : a.gait;
  o << ",\"aire\":[";
  size_t k = 0;
  for (size_t i = 0; i < g.t.size(); i++) {
    while (k < chosen.segments.size() && g.t[i] >= chosen.segments[k].t1) k++;
    int code = (k < chosen.segments.size() && g.t[i] >= chosen.segments[k].t0) ? (int)chosen.segments[k].gait : (int)Gait::UNKNOWN;
    o << (i ? "," : "") << code;
  }
  o << "]}";
  o << ",\"unidades_series\":{\"t\":\"s\",\"velocidad\":\"m/s\",\"aceleracion\":\"m/s2\",\"aceleracion_lateral\":\"m/s2\",\"curvatura\":\"1/m\",\"distancia\":\"m\",\"lat\":\"grados\",\"lon\":\"grados\","
    << "\"calidad\":\"0 BUENA 1 UTILIZABLE 2 BAJA 3 NO_UTILIZABLE 4 DESCONOCIDA\",\"aire\":\"0 PARADO 1 PASO 2 TROTE 3 GALOPE 4 TRANSICION 5 DESCONOCIDO 6 DATOS_INSUFICIENTES\"}";
  // girth windows on the same time base
  const auto& w = a.fusion.windows;
  auto fcol = [&](const char* name, auto get) { o << ",\"" << name << "\":["; for (size_t i = 0; i < w.size(); i++) o << (i ? "," : "") << num(get(w[i])); o << "]"; };
  o << ",\"series_cincha\":{\"imu\":["; for (size_t i = 0; i < w.size(); i++) o << (i ? "," : "") << (int)w[i].imu_id; o << "]";
  fcol("t", [](const FusedWindow& x) { return x.t_gnss; });
  fcol("sigma_t", [](const FusedWindow& x) { return x.sigma_t; });
  fcol("cadencia_hz", [](const FusedWindow& x) { return x.cadence_hz; });
  fcol("sigma_cadencia_hz", [](const FusedWindow& x) { return x.cadence_sigma; });
  fcol("longitud_tranco_m", [](const FusedWindow& x) { return x.stride_length_m; });
  fcol("cv_intervalos", [](const FusedWindow& x) { return x.interval_cv; });
  fcol("cv_amplitud", [](const FusedWindow& x) { return x.amplitude_cv; });
  fcol("correlacion_ciclos", [](const FusedWindow& x) { return x.cycle_corr; });
  fcol("estabilidad_espectral", [](const FusedWindow& x) { return x.spectral_stability; });
  fcol("velocidad", [](const FusedWindow& x) { return x.speed; });
  o << ",\"estado\":["; for (size_t i = 0; i < w.size(); i++) o << (i ? "," : "") << "\"" << w[i].status << "\""; o << "]}";
}

std::string to_json(const Analysis& a, const Session& s, const EngineConfig& c, bool series) {
  std::ostringstream o;
  o << "{\"formato\":\"avo-equine-analysis\",\"version_formato\":2,\"motor\":\"" << a.engine_version << "\",\"procesado_utc\":\"" << esc(a.processed_at_utc)
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
  o << ",\"aires\":{\"clasificador\":\"" << a.gait.classifier << "\",\"algoritmo\":\"" << esc(a.gait.algorithm) << "\",\"version\":\"" << a.gait.version << "\",\"segmentos\":[";
  for (size_t i = 0; i < a.gait.segments.size(); i++) {
    auto& g = a.gait.segments[i];
    o << (i ? "," : "") << "{\"aire\":\"" << gait_name(g.gait) << "\",\"codigo\":\"" << gait_code(g.gait) << "\",\"t0\":" << num(g.t0) << ",\"t1\":" << num(g.t1) << ",\"calidad\":\"" << quality_name(g.quality) << "\",\"base\":\"" << esc(g.basis) << "\"}";
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
  write_v2_blocks(o, a, s);
  if (series) write_series(o, a, c);
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
