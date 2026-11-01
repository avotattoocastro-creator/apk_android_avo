// AVO Training Analytics (fase 1): análisis de la HISTORIA de entrenamientos de un caballo.
// Trabaja sobre resúmenes de sesión extraídos de los JSON "avo-equine-analysis" (no vuelve a leer los RAW).
//   1. Resumen por sesión: tiempo y distancia por aire, velocidad, tranco, cadencia, regularidad, aceleraciones.
//   2. Carga de entrenamiento: carga externa por aires (heurística configurable, NO validada) y, si el entrenador
//      la anota, carga sRPE (RPE x minutos, Foster). Carga aguda 7 d, crónica 28 d, ACWR, monotonía y tensión.
//   3. Línea base del propio caballo (mediana y MAD de sus sesiones anteriores) y desvíos robustos (z).
//   4. Tendencias de forma (pendiente Theil-Sen por semana) y descanso.
//   5. Estado orientativo NORMAL | VIGILAR | REVISAR con los motivos. Sin términos clínicos ni diagnósticos.
// Determinista: misma entrada y versión dan la misma salida.
#pragma once
#include <cmath>
#include <string>
#include <vector>
#include "avo_eq/json.h"

namespace avoeq {

static const char* const TRAINING_VERSION = "1.0.0";
static const char* const TRAINING_LOAD_ALGORITHM = "AVO_TRAINING_LOAD_V1";

// Aires que cuentan para la historia (los demás —transición, desconocido— solo suman tiempo).
enum class TGait { WALK = 0, TROT = 1, CANTER = 2, COUNT = 3 };
const char* tgait_name(TGait g);   // PASO, TROTE, GALOPE

struct TrainingConfig {
  // Carga externa: minutos en cada aire x factor + metros por encima de high_speed_m_s x factor_hs / 100.
  double factor_walk = 1.0, factor_trot = 3.0, factor_canter = 6.0;
  double high_speed_m_s = 11.0;        // ~40 km/h
  double factor_high_speed = 1.0;      // por cada 100 m a alta velocidad
  int acute_days = 7, chronic_days = 28;
  double acwr_high = 1.5, acwr_low = 0.8;
  double monotony_high = 2.0;
  int baseline_days = 60;              // ventana de sesiones anteriores para la línea base
  int baseline_min_sessions = 4;       // menos sesiones: sin línea base (no se juzga)
  double z_watch = 2.0, z_review = 3.0;
  double min_gait_seconds = 60;        // tiempo mínimo en un aire para que sus métricas cuenten en la sesión
  int trend_days = 56;                 // 8 semanas
  int trend_min_sessions = 5;
  int rest_watch_days = 10;            // más días sin entrenar: aviso de vuelta al trabajo
};

// Métricas de un aire dentro de una sesión. NaN = no disponible.
struct GaitSummary {
  double duration_s = 0, distance_m = 0;
  double speed_mean = NAN, speed_max = NAN, stride_length_m = NAN, cadence_hz = NAN;
  double cycle_corr = NAN, interval_cv = NAN;   // regularidad (mediana ponderada por duración de segmentos)
};

// Trabajo en pista de la sesión (bloque "trabajo_pista" del análisis): entrenamiento de caballos de carreras.
struct RaceSummary {
  bool present = false;
  std::string breed;                            // GENERICO | PSI | ARABE
  double vedba_load_gmin = NAN, vedba_gallop_g = NAN;
  double gallop_left_s = 0, gallop_right_s = 0; // tiempo girando a cada mano en galope
  int lead_left = 0, lead_right = 0, lead_changes = 0;
  double wrong_lead_curve_pct = NAN;
  std::string lead_calibration;
  int efforts = 0, fast_efforts = 0;
  double vmax = NAN, best_200_s = NAN, dist_fast_m = 0, dist_work_m = 0;
  double fatigue_pct = NAN;                     // del trabajo con mayor velocidad
  double ref_speed[2] = {NAN, NAN}, sf_ref[2] = {NAN, NAN}, sl_ref[2] = {NAN, NAN};
  double sf_at_vmax = NAN, sl_at_vmax = NAN, vert_disp_m = NAN;
  int impacts = 0, lateral_jolts = 0, saturations = 0;
  // estructura del entrenamiento
  double warmup_s = NAN, cooldown_s = NAN;
  int reps = 0, fast_reps = 0;
  double vmax_drop_pct = NAN, stride_drop_pct = NAN, recovery_mean_s = NAN;
  bool warmup_short = false;
  // recorrido (líneas de salida y meta)
  std::string course_name;
  int passes = 0;
  double best_pass_s = NAN, best_pass_speed = NAN, best_pass_fatigue_pct = NAN;
};

struct SessionSummary {
  std::string id, horse, rider, date_utc;       // date_utc ISO-8601 (AAAA-MM-DD[THH:MM:SSZ])
  long day = 0;                                 // días desde 1970-01-01 (calculado)
  double moving_s = 0, distance_m = 0, speed_max = NAN;
  double high_speed_m = 0;                      // metros por encima de high_speed_m_s (segmentos)
  GaitSummary gait[3];
  int accel_events = 0, decel_events = 0, lateral_peaks = 0;
  double accel_peak = NAN, decel_peak = NAN;    // m/s² (trayectoria GNSS)
  std::string gnss_quality, imu_quality;        // del bloque "calidad" del análisis
  bool has_imu = false;
  // Valoración del entrenador (opcional)
  double rpe = NAN;                             // 1..10
  std::string state, note;                      // BIEN | CANSADO | RARO | COJERA | … texto libre
  std::string surface, track_state;             // pista
  RaceSummary race;
  std::vector<std::string> warnings;
};

// Extrae el resumen de un JSON "avo-equine-analysis" (v1 o v2). false + *err si no es un análisis válido.
bool training_summary_from_analysis(const json::Value& analysis, const TrainingConfig& c, SessionSummary* out, std::string* err);
std::string training_summary_to_json(const SessionSummary& s);
bool training_summary_from_json(const json::Value& v, SessionSummary* out, std::string* err);

struct Deviation {
  std::string metric;          // p. ej. "TROTE.longitud_tranco_m"
  double value = NAN, baseline = NAN, mad = NAN, z = NAN;
  int n = 0;                   // sesiones de la línea base
  std::string level;           // NORMAL | VIGILAR | REVISAR
  std::string direction;       // MAYOR | MENOR
};

struct SessionLoad {
  double external = 0, srpe = NAN;
  double acute = 0, chronic_weekly = 0, acwr = NAN;      // sobre la carga externa
  double acute_srpe = NAN, chronic_weekly_srpe = NAN, acwr_srpe = NAN;
  double imu = NAN, acute_imu = NAN, chronic_weekly_imu = NAN, acwr_imu = NAN;   // carga VeDBA de la cincha (g·min)
  double monotony = NAN, strain = NAN;
  int rest_days_before = -1;   // días desde la sesión anterior (-1: primera)
};

struct SessionResult {
  SessionSummary s;
  SessionLoad load;
  std::vector<Deviation> deviations;
  std::string level = "NORMAL";
  std::vector<std::string> reasons;
};

struct Trend {
  std::string metric;          // p. ej. "GALOPE.velocidad_media"
  double slope_per_week = NAN, slope_low = NAN, slope_high = NAN;   // Theil-Sen + intervalo aproximado (percentiles 10–90 de pendientes)
  double relative_per_week = NAN;   // pendiente / mediana
  int n = 0;
  std::string direction;       // SUBE | BAJA | ESTABLE | SIN_DATOS
};

struct TrainingResult {
  std::string horse, reference_date;
  long reference_day = 0;
  std::vector<SessionResult> sessions;            // en orden cronológico
  std::vector<std::pair<long, double>> daily_load; // día, carga externa (días sin sesión = 0) en la ventana crónica
  SessionLoad current;                              // a la fecha de referencia
  int days_since_last = -1;
  std::vector<Deviation> baselines;                 // línea base actual por métrica (value = NaN)
  std::vector<Trend> trends;
  std::string level = "NORMAL";
  std::vector<std::string> reasons, warnings;
};

// Fecha ISO-8601 -> días desde 1970-01-01. false si no se reconoce.
bool training_parse_day(const std::string& iso, long* day);
std::string training_day_text(long day);

TrainingResult analyse_training(std::vector<SessionSummary> sessions, const std::string& reference_date, const TrainingConfig& c);
std::string training_to_json(const TrainingResult& r, const TrainingConfig& c);

// Opciones JSON (todas opcionales): factores, ventanas y umbrales de TrainingConfig con nombres en español.
bool training_config_from_json(const json::Value& v, TrainingConfig* c, std::string* err);

}  // namespace avoeq
