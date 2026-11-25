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
#include "avo_eq/knowledge.h"

namespace avoeq {

static const char* const TRAINING_VERSION = "1.4.0";   // 1.4.0: planificador en semana natural (lunes–domingo) con lo realizado; 1.1.0: ficha de campo, A4 y base del planificador; 1.2.0: carga CG1–CG3;
                                                       // 1.3.0: planificador semanal, capa 2 (semana siguiente)
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
  KbRuleConfig kb;                     // base científica KB-1 (knowledge.h)
  // CG1–CG3 (KB 1.30.0): carga interna (TRIMP) y externa (bandas GNSS) solo descriptivas, nivel INFO.
  struct LoadCg {
    bool enabled = true;
    KbTrimpConfig trimp;               // FC de reposo 33 y máxima 213 por defecto («no propias»)
    int ewma_acute_days = 7, ewma_chronic_days = 28;   // Williams 2017 [E-r]
    int window_short_days = 7, window_long_days = 30;  // totales de CG2
    double max_missing_fraction = 0.20;                // más sesiones sin dato en la ventana crónica: sin cociente [I]
    int hr_max_min_sessions = 3;                       // FM1: FC máxima propia = pico de ≥ 3 trabajos rápidos [I]
  } cg;
  // Planificador semanal, capa 2 (TRAINING 1.3.0, KB 1.31.0): propuesta orientativa de la semana siguiente con P1, P2,
  // P4–P7, RT1–RT3 y DM1–DM4. Todo SIN CALIBRAR: sale como pautas informativas y nunca cambia el estado del caballo.
  struct Planner {
    bool enabled = true;
    int horizon_days = 7;                 // solo con calendar_week = false (7 días desde el día siguiente a la referencia)
    bool calendar_week = true;            // semana natural de lunes a domingo que contiene la fecha de referencia (25/11/2026)
    int fast_per_week_mature = 2;      // P1: 2,0 rápidos/semana en maduros (Morrice-West 2020) [E]; objetivo 2 [I]
    int fast_per_week_2y = 2;          // P1/DM1: 1,7 rápidos/semana en 2 años (Morrice-West 2020) [E]; tope 2 [I]
    int min_days_between_fast = 3;     // RT1/P2: ≥ 72 h y ≥ 2 días lentos entre rápidos [I] (sin evidencia directa)
    int free_days = 1;                 // P2: un día libre por semana (práctica) [E]
    int prerace_no_fast_days = 3;      // sin rápido en los 3 días previos a una carrera [I]
    int postrace_no_fast_days = 5;     // sin rápido en los 5 días siguientes a una carrera; el siguiente, libre [I]
    int p4_slow_days = 28;             // P4: ~4 semanas de trabajo lento tras > 60 d sin rápido (Morrice-West 2020: 4,0) [E]
    int p4_block_gap_days = 14;        // hueco sin sesiones que abre un bloque nuevo de trabajo [I]
    int p7_window_days = 21;           // P7: 21 d (prudente 30) con 1 rápido/semana tras volver (Carrier 1998 [E-r]) [I]
    double p7_distance_fraction = 0.75;// P4/P7: «distancia reducida» = 75 % de la mediana propia anterior [I]
    int p5_window_days = 60;           // P5: media diaria de distancia rápida en 60 d (Estberg 1998 [E-r])
    double p5_percentile = 75;         // P5: frente al P75 propio [I]
    int p5_min_history_days = 180;     // P5: historia mínima para el P75 propio [I]
    int p6_break_min_days = 40;        // P6: descanso ≥ 40 d sin sesiones (6,3 semanas, IC 5,7–6,8; Morrice-West 2020) [E/I]
    int p6_interval_days = 183;        // P6: ~2 descansos al año (1,9–2,1; Morrice-West 2020) [E]; corte [I]
    double dm1_fast_max_m = 400;       // DM1: rápidos cortos de 200–400 m en 2 años (Oliveira 2006 [E], Boston 2000 [E-r]) [I]
    int dm4_weeks = 12;                // DM4: escalones antes de 12–16 semanas de preparación (Oliveira 2006, n = 42) [E/I]
    double dm4_from_m = 500, dm4_to_m = 700;   // DM4: aviso al pasar de ≈ 500 a ≥ 700 m [E/I]
    double dm2_ratio = 1.5;            // DM2: subida brusca frente a la media acumulada propia [I]
    double dm2_min_fast_m = 200, dm2_min_canter_m = 2000;   // DM2: volumen mínimo de la ventana para avisar [I]
    int dm2_min_history_days = 28;     // DM2: historia propia mínima antes de la ventana [I]
    int age_years = -1;                // edad de carreras (opción «edad_anos»); -1: sin dato
    long birth_day = -1000000;         // fecha de nacimiento (opción «fecha_nacimiento»); edad = año de referencia − año
    bool has_birth = false;            //   de nacimiento (convenio del 1 de enero, hemisferio norte) [OFICIAL]
  } planner;
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
  double v_last_600 = NAN;                      // últimos 600 m del trabajo rápido más veloz (A8, KB 1.5.0)
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
  // base científica KB-1 (bloque "base_cientifica" de trabajo_pista; NaN en análisis anteriores)
  double kb_race_pace = NAN, kb_band_m[KB_BANDS] = {NAN, NAN, NAN}, kb_canter_m = NAN, kb_gallop_m = NAN;
  double kb_bone_pct = NAN, kb_bone_low_pct = NAN, kb_strides = NAN;
  // CG2 (KB 1.30.0): bandas de velocidad de Morrice-West 2020; NaN en análisis anteriores
  double kb_cg_band_m[KB_CG_BANDS] = {NAN, NAN, NAN, NAN, NAN, NAN};
  double kb_hs_m = NAN;                         // metros de trabajo rápido (≥ 13,3 m/s en PSI)
  std::string kb_cg_scale;                      // ABSOLUTAS_PSI | RELATIVAS_V_CARRERA
};

// ECG de la cincha 0.5.x (bloque "cardio" del análisis, motor 2.0.0-dev29). NaN / vacío = no disponible.
struct CardioSummary {
  bool present = false;
  std::string quality;                          // BUENA | UTILIZABLE | POBRE | NO_UTILIZABLE
  double v200 = NAN;                            // método principal (CRUCE_200_10S, Poinsard 2026), NO VALIDADA
  std::string v200_method;
  bool v200_warmup_ok = false;                  // WU1 (atributo)
  double v200_regression = NAN;                 // REGRESION_FC_VELOCIDAD (aparte)
  double vhrmax = NAN;
  std::string vhrmax_method;
  double hr_peak = NAN;
  double recovery_hr[6] = {NAN, NAN, NAN, NAN, NAN, NAN};   // 1, 2, 4, 5, 10 y 15 min
  int ectopy_candidates = 0;
  std::string ectopy_level, ectopy_text;        // candidatos a revisar; nunca un diagnóstico
  // CG1 (KB 1.30.0, cardio 1.1.0): TRIMP de la sesión y su histograma de FC (para recalcular con la FC propia)
  double trimp = NAN, trimp_coverage_pct = NAN;
  std::vector<std::pair<double, double>> hr_hist;   // [límite inferior lpm, segundos]
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
  // Ficha de campo (TRAINING 1.1.0, todo opcional; la app la pasa en «extra»). Vacío / NaN = sin anotar.
  std::string session_type;   // TRABAJO | TRABAJO_REFERENCIA_1000 | CARRERA | TRIAL | DESCANSO_ACTIVO
  std::string beach_band;     // franja de playa: ORILLA_FIRME | HUMEDA_PROFUNDA | SECA_PROFUNDA | TRANSICION
  std::string going;          // FIRME | BUENO_FIRME | BUENO | BUENO_BLANDO | BLANDO | PESADO
  std::string tide_time;      // HH:MM (hora local) de la bajamar o pleamar de referencia
  std::string tide_type;      // BAJAMAR | PLEAMAR
  // AVO BEACH 1.0.0 (motor dev36): franja AUTOMÁTICA (GPS + líneas de playa + marea) y marea del trabajo (predicción).
  bool beach_band_auto = false;   // true = beach_band viene del análisis; la ficha de campo la sustituye
  std::string tide_level;         // BAJA | MEDIA | ALTA en el inicio del trabajo
  std::string tide_trend;         // SUBE | BAJA
  double tide_height_m = NAN;
  double temperature_c = NAN, humidity_pct = NAN;
  double rider_kg = NAN, horse_kg = NAN;        // peso del jinete (con equipo) y peso corporal del caballo
  std::string incident_type, incident_text;     // NINGUNA | TROPIEZO | CAIDA | ESPANTADA | COJERA | HERRAJE | EQUIPO | OTRA
  bool counts_as_race() const { return session_type == "CARRERA" || session_type == "TRIAL"; }
  RaceSummary race;
  CardioSummary cardio;
  std::vector<std::string> warnings;
};

// Extrae el resumen de un JSON "avo-equine-analysis" (v1 o v2). false + *err si no es un análisis válido.
bool training_summary_from_analysis(const json::Value& analysis, const TrainingConfig& c, SessionSummary* out, std::string* err);
std::string training_summary_to_json(const SessionSummary& s);
// Lee la ficha de campo de un objeto con la forma del resumen o de «extra» (tipo_sesion, pista.franja, pista.going,
// pista.marea, condiciones, pesos, incidencia). Solo sobrescribe los campos presentes y válidos; los no válidos se
// descartan con un aviso en s->warnings.
void training_read_field_sheet(const json::Value& x, SessionSummary* s);
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

// CG1–CG3 (KB 1.30.0): carga descriptiva. NaN = sin dato.
struct CgSeries {
  double session = NAN;                // valor de la sesión (o del día de referencia)
  double sum_short = NAN, sum_long = NAN;   // totales de 7 y 30 días
  double ewma_acute = NAN, ewma_chronic = NAN, ratio = NAN;
  double monotony = NAN, strain = NAN;
  int sessions_long = 0, missing_long = 0;  // sesiones con y sin dato en la ventana crónica
  std::string reason;                  // por qué falta el cociente
};
struct CgStatus {
  bool available = false;
  double hr_rest = NAN, hr_max = NAN;
  std::string hr_rest_origin, hr_max_origin;   // POR_DEFECTO | CABALLO | PROPIA_HISTORIA
  int hr_max_sessions = 0;             // trabajos rápidos con FC pico usados para la FC máxima propia
  CgSeries internal, external;         // TRIMP y metros de trabajo rápido
  double band_short_m[KB_CG_BANDS] = {NAN, NAN, NAN, NAN, NAN, NAN}, band_long_m[KB_CG_BANDS] = {NAN, NAN, NAN, NAN, NAN, NAN};
  std::string scale;
  std::vector<std::pair<long, std::pair<double, double>>> daily;   // día, (metros rápidos, TRIMP) en la ventana crónica
  std::vector<std::string> notes;
};

struct SessionResult {
  SessionSummary s;
  SessionLoad load;
  double cg_trimp = NAN;       // CG1 recalculado con la FC de referencia de la historia
  std::vector<Deviation> deviations;
  std::string level = "NORMAL";
  std::vector<std::string> reasons;
  KbStatus kb;                 // base científica a la fecha de la sesión
};

struct Trend {
  std::string metric;          // p. ej. "GALOPE.velocidad_media"
  double slope_per_week = NAN, slope_low = NAN, slope_high = NAN;   // Theil-Sen + intervalo aproximado (percentiles 10–90 de pendientes)
  double relative_per_week = NAN;   // pendiente / mediana
  int n = 0;
  std::string direction;       // SUBE | BAJA | ESTABLE | SIN_DATOS
};

// Base del planificador semanal (TRAINING 1.1.0): pautas informativas P1, P3, RT1 y RT3 de la base científica y el
// margen hasta la próxima carrera prevista (A4). Nunca sube el estado; no es un plan automático.
struct PlannerNote { std::string rule, text, evidence; };
struct PlannerStatus {
  bool available = false;              // hay sesiones con el bloque de carga de la base científica
  int fast_days_7d = 0;                // días con sesión rápida en los últimos 7 días
  int days_since_fast = -1;            // -1: ninguna
  int days_between_last_fast = -1;     // separación entre los dos últimos días rápidos (-1: menos de dos)
  long next_race_day = -1;             // próxima carrera prevista (≥ referencia), -1 si no hay
  int days_to_next_race = -1;
  int fast_days_before_race = 0;       // días rápidos ya hechos en los 28 d previos a esa carrera
  int fast_needed = 0;                 // los que faltan para el mínimo de A4
  int days_since_last_race = -1;       // última sesión CARRERA o TRIAL
  std::vector<PlannerNote> notes;
};

// Planificador semanal, capa 2 (TRAINING 1.3.0): propuesta de la semana siguiente. Orientativa y sin calibrar.
struct PlanDay {
  long day = 0;
  std::string type;                    // RAPIDO | LENTO | SUAVE | LIBRE | CARRERA
  std::string reason;
  std::vector<std::string> rules;
  double fast_max_m = NAN;             // distancia rápida máxima propuesta (solo días RAPIDO; NaN: sin tope propio)
  bool done = false;                   // día ya pasado de la semana: lo realizado según las sesiones (no es propuesta)
};
struct WeekPlan {
  bool available = false;
  std::string reason;                  // por qué no hay propuesta
  long from_day = 0, to_day = 0;
  std::string phase;                   // NORMAL | POTRO_2_ANOS | REINCORPORACION_LENTA | REINCORPORACION_RAPIDO
  bool limited = false;                // A1/A2 en LIMITAR: un solo rápido
  int age_years = -1;
  std::string age_origin;              // FECHA_NACIMIENTO | EDAD_ANOS | "" (sin dato)
  std::string breed;
  int fast_target = 0, fast_planned = 0;
  int fast_done = 0;                   // rápidos ya hechos en los días pasados de la semana
  long plan_from_day = 0;              // primer día que se planifica (hoy si aún no hay sesión, si no mañana)
  bool calendar_week = false;
  int slow_days_done = -1;             // P4: días del bloque lento actual (-1: no aplica)
  long return_fast_day = -1;           // P7: primer rápido tras > 60 d sin rápido (-1: no aplica)
  int prep_weeks = -1;                 // semanas del bloque de preparación actual (DM4)
  double fast_ref_m = NAN;             // mediana propia de metros rápidos por día rápido (60 d)
  double fast_max_m = NAN;             // tope propuesto (DM1 o P7); NaN: sin tope
  double p5_mean_m = NAN, p5_p75_m = NAN;   // P5: media diaria de 60 d y su P75 propio
  int days_since_break = -1;           // P6: días desde el final del último descanso ≥ p6_break_min_days (-1: ninguno)
  std::vector<PlanDay> days;
  std::vector<PlannerNote> notes;
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
  KbStatus kb;                                      // base científica a la fecha de referencia
  PlannerStatus planner;                            // base del planificador semanal a la fecha de referencia
  WeekPlan week;                                    // capa 2: propuesta de la semana siguiente (TRAINING 1.3.0)
  CgStatus cg;                                      // CG1–CG3 a la fecha de referencia (solo descriptiva)
  std::string level = "NORMAL";
  std::vector<std::string> reasons, warnings;
};

// Fecha ISO-8601 -> días desde 1970-01-01. false si no se reconoce.
bool training_parse_day(const std::string& iso, long* day);
std::string training_day_text(long day);

TrainingResult analyse_training(std::vector<SessionSummary> sessions, const std::string& reference_date, const TrainingConfig& c);
std::string training_to_json(const TrainingResult& r, const TrainingConfig& c);

// Capa 2 del planificador (src/training/planner.cpp). ok: sesiones en orden cronológico hasta «at»; kbdays: una
// entrada por sesión; kb: base científica a la fecha «at» (para A1/A2 LIMITAR y A3).
WeekPlan training_plan_week(const std::vector<SessionSummary>& ok, const std::vector<KbDay>& kbdays, long at, long first_day,
                            const KbStatus& kb, const TrainingConfig& c);
std::string training_week_plan_json(const WeekPlan& w, const TrainingConfig& c);

// Opciones JSON (todas opcionales): factores, ventanas y umbrales de TrainingConfig con nombres en español.
bool training_config_from_json(const json::Value& v, TrainingConfig* c, std::string* err);

}  // namespace avoeq
