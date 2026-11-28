// AVO Base científica de la cuadra (KB-1): conocimiento publicado sobre PSI y árabe de carreras convertido en métricas
// y reglas del motor. Ficha: docs/algoritmos/14_BASE_CIENTIFICA.md. Fuentes y nivel de evidencia ([E] publicado,
// [I] inferencia, [NV] sin verificar) de cada parámetro: knowledge/base_cientifica.json. Se amplía cada semana con
// los estudios nuevos y con los datos de campo del PROTOTIPO; cada cambio sube KNOWLEDGE_VERSION.
//
// 1. Fatiga del hueso subcondral por zancada (SBFL_MORRICE_WEST_2022, regla de Miner sin reparación) [E]:
//      F(v) = 2,778 + 2,1376·v − 0,0535·v²   (N/kg), saturada en 24,13 por encima del máximo (19,98 m/s) [I]
//      σ = σ_max · F / 24,13 ;  Nf = 10^((σ0 − σ) / 14,1) ;  %SBFL = 100 · Σ 1/Nf
//    σ_max = 90 MPa y σ0 = 134,2 MPa por defecto (configurables). Zancadas por época GNSS = f(v)·dt con
//    f(v) = 1,7052 + 0,0305·v + 0,0004·v² Hz. Rango validado 12,57–21 m/s; por debajo se acumula aparte como
//    «extrapolado» (sobrestima el trabajo lento frente a Hong Kong). En árabes: extrapolación sin calibrar.
// 2. Distancias por banda, relativas al ritmo de carrera v_carrera (PSI 16,7 m/s; árabe 14,5 m/s) [I]:
//      B1 trabajo [v_trabajo, 0,80·v_carrera) · B2 intermedia [0,80, 0,93) · B3 alta ≥ 0,93·v_carrera
//    y contadores de Verheyen 2006 [E]: canter 0,40–0,838·v_carrera (PSI 6,7–14 m/s) y galope > 0,838·v_carrera.
// 3. Reglas sobre la historia (7, 30 y 60 días). Orientativas; nunca un diagnóstico.
#pragma once
#include <cmath>
#include <string>
#include <vector>

namespace avoeq {

static const char* const KNOWLEDGE_VERSION = "1.34.0";
static const char* const KNOWLEDGE_ID = "AVO_KB_1";
static const char* const BONE_MODEL_ALGORITHM = "SBFL_MORRICE_WEST_2022";

struct BoneModelConfig {
  double sigma_max_mpa = 90.0;   // escenario de 90 MPa (9,34 % de media por carrera en Morrice-West 2022); 54–90 son los niveles del ensayo de Martig 2013
  double f_max_n_kg = 24.13;
  double sn_a_mpa = 134.2;       // σ0 de Martig 2013 (curva de sensibilidad, R² 0,72), la de Morrice-West 2022; 139,0 es la
                                 // calibración in vivo de Pan 2025 para el modelo B con reparación (estudio 2026-11-18 noche)
  double sn_b_mpa = 14.1;
  double valid_min_speed = 12.57;// filtro de zancadas de Morrice-West 2022
  double low_min_speed = 4.0;    // por debajo no se cuenta nada (paso y trote)
  double max_speed = 25.0;       // por encima: dato GNSS no plausible
};

double bone_vertical_force_n_kg(double v);           // saturada en 24,13 N/kg
// Fracción de vida a fatiga consumida por una zancada a v m/s (0 con v NaN, ≤ 0 o > max_speed).
double bone_stride_damage(double v, const BoneModelConfig& c);
double model_stride_frequency_hz(double v);          // Hz

// Velocidad media de los últimos D metros de un esfuerzo (Schrurs 2024: «average speed over the last 600 m»), como
// D / tiempo, con el tiempo interpolado sobre la distancia acumulada (t en s, d en m, crecientes; NaN se saltan).
// Devuelve false si el esfuerzo es más corto que D o falta el dato; time_s y speed quedan intactos.
static const double KB_FINAL_DISTANCE_M = 600.0;
bool kb_final_speed(const std::vector<double>& t, const std::vector<double>& d, double D, double* time_s, double* speed);

static const int KB_BANDS = 3;
const char* kb_band_name(int b);                     // B1_TRABAJO, B2_INTERMEDIA, B3_ALTA
struct SpeedBandConfig {
  double work_speed = 9.0;       // inicio de B1 (v_trabajo de la raza)
  double race_pace = NAN;        // ritmo de carrera de referencia (m/s); NaN: todo en B1 y sin contadores de Verheyen
  double b2_fraction = 0.80, b3_fraction = 0.93;
  double canter_lo_fraction = 0.40, gallop_fraction = 14.0 / 16.7;
  bool cg_relative = false;      // CG2: bandas relativas a v_carrera (árabes [I-raza]); false = absolutas de PSI [E]
  double b2_lo() const { return b2_fraction * race_pace; }
  double b3_lo() const { return b3_fraction * race_pace; }
  double canter_lo() const { return canter_lo_fraction * race_pace; }
  double gallop_lo() const { return gallop_fraction * race_pace; }
};
int kb_speed_band(double v, const SpeedBandConfig& c);   // -1 por debajo de B1; 0, 1 o 2

// Acumulador de una sesión.
struct KbSessionLoad {
  double band_m[KB_BANDS] = {0, 0, 0}, band_s[KB_BANDS] = {0, 0, 0};
  double canter_m = 0, gallop_m = 0;   // contadores de Verheyen (NaN si no hay v_carrera, ver finish())
  double strides = 0, bone_fl = 0;     // rango validado (fracción; ×100 = %)
  double strides_low = 0, bone_fl_low = 0;   // 4–12,57 m/s: extrapolado
  double cg_band_m[6] = {0, 0, 0, 0, 0, 0}, cg_band_s[6] = {0, 0, 0, 0, 0, 0};   // CG2 (KB 1.30.0)
  double hs_m = 0;                     // CG2: metros ≥ 13,3 m/s (PSI) o ≥ 13,3/16,7·v_carrera (relativas)
  void add(double dt_s, double dd_m, double v, const SpeedBandConfig& b, const BoneModelConfig& m);
};

// ------------------------------------------------------------------ historia
struct KbRuleConfig {
  bool enabled = true;
  double canter_30d_watch_km = 40.0;   // A1 aviso (90 % del umbral) [I]
  double canter_30d_limit_km = 44.0;   // A1 limitar: Verheyen 2006, > 44 km de canter en 30 días [E]
  double gallop_30d_limit_km = 6.0;    // A2: Verheyen 2006, > 6 km de galope (> 14 m/s) en 30 días [E]
  double ramp_ratio = 1.4;             // A3: Estberg 1996, +40 % de trabajo rápido → OR 3,9 [E]; ventana 30/30 d [I]
  double ramp_min_m = 1000.0;
  int return_rest_days = 60;           // A5: Carrier 1998, ≥ 60 días sin trabajo rápido [E]
  int return_window_days = 21;         // RR 71 a 10 días y 45 a 21 días [E]
  int tendon_rest_days = 90;           // A6: Choi & Parkin 2025, ≥ 90 días sin trabajo rápido, OR 3,10 [E]
  int low_gallop_60d_max_days = 2;     // A6B: Choi & Parkin 2025, ≤ 2 días de galope en 60 días, OR 1,84 (1,07–3,16) de
                                       // tendinopatía del TFDS [E]; «día de galope» = día con sesión rápida [I]
  double gallop_ratio_max = 1.6;       // A6C: Choi & Parkin 2025 (sección 2.3 y tabla 2): (g60/g90) + 1 ≤ 1,6, OR 2,190
                                       // (1,227–3,910) [E]; ventanas anidadas que acaban en el último trabajo rápido [E]
  int gallop_ratio_max_age_days = 30;  // A6C solo si el último trabajo rápido es de los últimos 30 días [I]
  double gallop_session_min_m = 100.0; // metros de galope (> 14 m/s en PSI) para contar como sesión rápida
  double bone_week_ratio = 1.5;        // KB-B: fatiga ósea de 7 días frente a la mediana semanal propia [I]
  int bone_min_weeks = 4;
  // A7 y A8 sobre la línea base propia (KB 1.5.0): sesiones comparables = misma superficie anotada [I].
  bool drift_rules = true;
  double stride_drop_m = 0.10;         // A7: Wong 2023, HR 1,11 por cada 10 cm menos de zancada [E]; umbral 10 cm [I]
  double final_speed_drop = 0.20;      // A8: últimos 600 m (Schrurs 2024 [E]); 0,1–0,2 m/s es [I], se usa el alto
  int drift_min_baseline = 5;          // sesiones comparables mínimas antes de las 3 últimas [I]
  int drift_warmup = 8;                // CUSUM autoiniciado: sin alarmas antes de la 9.ª sesión comparable [I]
  double drift_h = 5.0;                // h = 5 (muchas cartas a la vez) [I]
  // A4 carga baja antes de una carrera (KB 1.26.0): Morrice-West 2025 [E], «baja» allí es fatiga ósea acumulada < 0,25
  // en las 4 salidas previas; el corte en sesiones es [I]. Carreras = fechas previstas (opción «carreras_previstas»)
  // y sesiones de tipo CARRERA o TRIAL.
  std::vector<long> planned_race_days;
  int prerace_days = 28;               // ventana previa a la carrera [I]
  int prerace_min_fast_days = 2;       // < 2 días con sesión rápida: AVISO [I]
  int prerace_warn_days = 14;          // aviso anticipado cuando faltan ≤ 14 días y aún no se llega al mínimo [I]
  // A9 (KB 1.27.0, motor 2.0.0-dev29): V200 y VHRmax del ECG de la cincha 0.5.x frente a la línea base propia (misma
  // superficie y mismo método). Umbral max(2·TE·√(1 + 1/n), SWC) (kb_change_threshold) con TE por defecto del 3 % de la
  // línea base, NO VALIDADO hasta tener el TE propio con ≥ 3 pruebas (VT1 [I]); aviso de posible artefacto si la V200
  // cambia > 5 % en ≤ 31 días (VT2 [I]).
  double v200_warmup_match_pct = 20.0; // WU3 (KB 1.33.0) [I]: A9 compara solo calentamientos con distancia ±20 % (si ambos la tienen); 0 = sin filtro
  double v200_te_pct = 3.0;
  double v200_swc_pct = 0.0;
  double v200_jump_pct = 5.0;
  int v200_jump_days = 31;
};

struct KbDay {
  long day = 0;
  bool race = false;                   // sesión de tipo CARRERA o TRIAL (A4)
  double band_m[KB_BANDS] = {NAN, NAN, NAN};
  double canter_m = NAN, gallop_m = NAN, bone_pct = NAN;
};

struct KbFlag { std::string rule, level, action, text, evidence; };   // level INFO | VIGILAR; action AVISO | LIMITAR
struct KbWindow {
  double band_m[KB_BANDS] = {0, 0, 0};
  double canter_m = 0, gallop_m = 0, bone_pct = 0;
  int sessions = 0, missing = 0;
};
// A4: una carrera (prevista o sesión CARRERA/TRIAL) dentro del horizonte de la fecha evaluada.
struct KbRaceCheck {
  long day = 0;
  bool planned = false;                // true: fecha prevista; false: sesión de tipo CARRERA o TRIAL
  int days_to = 0;                     // días desde la fecha evaluada hasta la carrera (0 = ese día)
  int fast_days = 0;                   // días con sesión rápida en [carrera − 28, carrera − 1] hasta la fecha evaluada
  int missing = 0;                     // sesiones de esa ventana sin bloque de carga
  bool covered = false;                // la historia cubre la ventana (si no, no se juzga)
  bool flagged = false;
};
struct KbStatus {
  bool available = false;
  std::vector<KbRaceCheck> races;      // A4
  KbWindow w7, w30, prev30, w60;
  double bone_weekly_median = NAN, bone_ratio = NAN;
  int days_since_gallop = -1;          // días desde la última sesión rápida (-1: ninguna)
  int return_day = -1;                 // día de la vuelta tras descanso largo (-1: no hay vuelta en curso)
  int return_rest = 0;                 // días sin trabajo rápido antes de esa vuelta
  int gallop_days_60d = 0;             // días con sesión rápida en los últimos 60 días (A6B)
  int gallop_days_60_last = -1;        // A6C: días de galope en los 60 d que acaban en el último trabajo rápido (-1: sin datos)
  int gallop_days_90_last = -1;        // A6C: ídem en 90 d
  double gallop_ratio = NAN;           // A6C: (g60/g90) + 1, entre 1 y 2 (NAN si no se puede calcular)
  std::vector<KbFlag> flags;
};

// Evalúa las reglas al día at_day con las sesiones ordenadas por día (se ignoran las posteriores a at_day).
// first_day: primer día de la historia del caballo (para saber si las ventanas están cubiertas).
KbStatus kb_evaluate(const std::vector<KbDay>& sessions, long at_day, long first_day, const KbRuleConfig& c);
std::string kb_status_json(const KbStatus& s);
std::string kb_day_text(long day);   // días desde 1970-01-01 -> AAAA-MM-DD

// ------------------------------------------------------------------ líneas base (KB 1.3.0, estudio extra 2026-11-19)
// Herramientas estadísticas para comparar a cada caballo consigo mismo. Matemática cerrada [E]; su uso en caballos y
// los umbrales por métrica son [I] (no hay CUSUM publicado en caballos de carreras). Todavía no las usa ninguna regla:
// faltan TE propios por métrica (2–3 trabajos repetidos por caballo) y anotar la superficie (playa por franja).
//
// Línea base robusta: mediana m y MAD_s = 1,4826·mediana(|x − m|) (1,4826 = 1/Φ⁻¹(0,75), Rousseeuw & Croux 1993) de las
// últimas `last_n` observaciones válidas (NaN se saltan). z robusto = (x − m)/max(MAD_s, min_scale); con |z| > 3,5 es
// atípico (z modificado de Iglewicz & Hoaglin 1993: 0,6745·(x − m)/MAD > 3,5). min_scale evita escalas nulas con
// pocas sesiones (el MAD de 10 datos rinde como una DE de ~4) [I].
static const double KB_MAD_SCALE = 1.4826;
static const double KB_ROBUST_Z_OUTLIER = 3.5;
struct KbRobustBaseline { int n = 0; double median = NAN, mad_s = NAN; };
KbRobustBaseline kb_robust_baseline(const std::vector<double>& x, int last_n = 12);
double kb_robust_z(double x, const KbRobustBaseline& b, double min_scale = 0.0);   // NaN con n < 3 o escala 0

// Shrinkage normal-normal (Efron & Morris 1975) para el arranque en frío: media propia de n sesiones encogida hacia la
// de la cuadra. sigma2_within = TE² (varianza dentro del caballo); tau2_between = varianza VERDADERA entre caballos
// (la observada menos sigma2/n). μ* = (n·x̄/σ² + μ_pop/τ²)/(n/σ² + 1/τ²); con n = 0 devuelve μ_pop.
double kb_shrink_mean(int n, double xbar, double sigma2_within, double mu_pop, double tau2_between);

// Umbral de cambio real frente a una media de n sesiones: max(2·TE·√(1 + 1/n), SWC). Hopkins 2000 propone 1,5–2·TE
// [E]; √(1 + 1/n) es el ruido de una medida frente a la media de n [cálculo]. Con n ≤ 0 usa √2 (dos medidas sueltas).
double kb_change_threshold(double te, int n, double swc);

// CUSUM unilateral superior sobre z ya tipificados con la DE dentro del caballo: S_t = max(0, S_{t−1} + z_t − k), alarma
// cuando S_t > h. Para derivas a la baja se pasa −z. Con k = 0,5: h = 4 → ARL0 ≈ 335 sesiones y ARL1(δ = 1) ≈ 8,4;
// h = 5 → ARL0 ≈ 931 y ARL1 ≈ 10,4 (cadena de Markov de Brook-Evans; la tabla del NIST/SEMATECH e-Handbook
// §6.3.2.3.1, leída el 23/11/2026, da 336 / 8,38 y 930 / 10,4 para el CUSUM UNILATERAL). Los 168/465 del CUSUM
// bilateral (≈ ARL0/2 de dos cartas unilaterales) son un cálculo nuestro: el NIST no publica ARL bilaterales. Con muchas cartas a la vez (caballos
// × métricas × sentidos) conviene h = 5 [I]. fir: arranque con S0 = h/2 (Lucas & Crosier 1982), ARL1(δ = 1) 5,3 con
// h = 4. min_samples: no se dan alarmas antes de esa muestra válida [I]. NaN: la muestra se salta (S no cambia).
struct KbCusumConfig { double k = 0.5, h = 4.0; bool fir = false; int min_samples = 1; };
struct KbCusumResult { std::vector<double> s; int alarm_index = -1; };   // índice (0-based) de la primera alarma
KbCusumResult kb_cusum_upper(const std::vector<double>& z, const KbCusumConfig& c);

// CUSUM autoiniciado (Hawkins 1987, The Statistician 36:299; descrito en van Zyl & Lombard 2018, S. Afr. Stat. J.
// 52:93, §2.6) [E, original no leído]: con μ y σ estimadas de 5–20 sesiones el CUSUM con h = 4/5 NO tiene el ARL0
// nominal por caballo (simulación propia, estudio extra 2 2026-11-19: con m = 10 y h = 4 el 10 % de los caballos tiene
// ARL0 ≤ 23 sesiones). Esta función tipifica cada sesión frente a las ANTERIORES: para la n-ésima válida (n ≥ 3)
// V = (x_n − x̄_{n−1})/s_{n−1} y ξ = Φ⁻¹(T_{n−2}(√((n−1)/n)·V)), con T la t de Student de n − 2 g.l. Bajo control los ξ son
// N(0, 1) independientes y se pasan a kb_cusum_upper con las mismas k y h (ARL0 incondicional 339/930 en la simulación
// propia, h = 4/5, 20 000 réplicas). NaN en las dos primeras válidas, en las entradas NaN y con s = 0. Uso [I]: no
// alarmar en las primeras 8–10 sesiones (min_samples), no actualizar con sesiones en alarma y reiniciar tras una.
std::vector<double> kb_self_starting_z(const std::vector<double>& x);
double kb_student_t_cdf(double t, double nu);   // auxiliares (expuestas para las pruebas)
double kb_normal_quantile(double p);

// Regla de caída frente a la línea base propia (A7 zancada, A8 velocidad final), KB 1.5.0 [I]. x: valores de sesiones
// comparables en orden cronológico; la última es la sesión que se juzga (NaN se saltan). Dos criterios:
//  · umbral: la última y al menos `recent_hits` de las `recent` últimas están ≥ delta por debajo de la mediana de las
//    (hasta 12) anteriores a esas `recent`, con ≥ min_baseline sesiones de base;
//  · CUSUM autoiniciado (kb_self_starting_z sobre −x, k 0,5, h): alarma mientras S > h; las sesiones con S > 0,8·h no
//    entran en la base (no aprende la deriva); sin alarmas en las primeras `warmup` válidas.
struct KbDriftConfig { double delta = NAN, k = 0.5, h = 5.0; int warmup = 8, recent = 3, recent_hits = 2, min_baseline = 5; };
struct KbDriftResult {
  int n = 0, baseline_n = 0, hits = 0;
  double last = NAN, baseline = NAN, drop = NAN, s = 0;   // drop = baseline − last (positivo = caída)
  bool delta_alarm = false, cusum_alarm = false;
};
KbDriftResult kb_drift_down(const std::vector<double>& x, const KbDriftConfig& c);

// ------------------------------------------------------------------ carga de entrenamiento CG1–CG3 (KB 1.30.0)
// Estudio 2026-11-23 (noche) y 2026-11-24. Solo DESCRIPTIVA: no hay TRIMP ni ACWR validados en PSI ni en árabes de
// carreras (el único equino es de completo, Munsters 2020 [I-raza]); nunca un riesgo ni un semáforo de lesión, nunca
// sube el estado del caballo (nivel INFO).
//
// CG1 carga interna por sesión con la forma del TRIMP de Banister (Morton, Fitz-Clarke y Banister 1990 [E-r]):
//   ΔFC = (FC − FC_reposo)/(FC_máx − FC_reposo), recortado a [0, 1] [I]
//   TRIMP = Σ Δt(min) · ΔFC · b · e^(c·ΔFC)       b = 0,64 y c = 1,92 (humanos varones) [NV en equinos]
//   sin ponderar = Σ Δt(min) · ΔFC ; tiempo por encima de 180 y 200 lpm (Flyrin y Hägglund 2021 [E, trotones]).
//   FC de reposo por defecto 33 lpm (Ohmura y Jones 2017: 32,9 ± 3,5 lpm en PSI de 3–7 años [E-r]) y FC máxima por
//   defecto 213 lpm (FM1: 210–215 lpm [I]) mientras no haya FC propias; ambas marcadas «no propia».
// CG2 carga externa por bandas de velocidad GNSS (Morrice-West 2020, EVJ 10.1111/evj.13156 [E]): < 10 / 10–13,3 /
//   13,3–14,4 / 14,4–15,5 / 15,5–16,8 / ≥ 16,8 m/s en PSI; trabajo rápido («fast work») ≥ 13,3 m/s (también Wong 2023
//   [E]). En árabes las bandas se escalan por v_carrera/16,7 [I-raza].
// CG3 agudo/crónico por EWMA (Williams 2017 [E-r]): EWMA_d = λ·carga_d + (1 − λ)·EWMA_(d−1), λ = 2/(N + 1), N = 7 y 28,
//   EWMA = 0 el día anterior al primero de la historia [I]; cociente solo con la historia cubierta y ≤ 20 % de sesiones
//   sin dato [I]. Monotonía de Foster 1998 [E-r] = media diaria de 7 d / DE (poblacional, días sin sesión = 0 [NV]);
//   strain = carga de 7 d × monotonía. Impellizzeri 2020 [E-r]: el cociente no sirve para gestionar lesiones; se
//   muestran siempre aguda y crónica por separado.
static const char* const KB_TRIMP_ALGORITHM = "TRIMP_BANISTER_EQUINO_CG1";
static const double KB_HR_BIN_BPM = 5.0;   // histograma de FC por sesión (para recalcular con la FC propia)
static const int KB_HR_BINS = 60;          // 0–300 lpm
struct KbTrimpConfig {
  double hr_rest = 33.0;         // lpm [E-r] Ohmura y Jones 2017
  double hr_max = 213.0;         // lpm [I] FM1 (210–215)
  bool hr_rest_own = false, hr_max_own = false;   // true: FC del propio caballo (opción o historia)
  double b = 0.64, c = 1.92;     // plantilla de Banister [NV en equinos]
  double zone1_bpm = 180.0, zone2_bpm = 200.0;
  double min_coverage = 0.80;    // fracción mínima de la sesión con FC válida para usar el TRIMP en la historia [I]
};
struct KbTrimp {
  double trimp = NAN, trimp_unweighted = NAN, minutes = 0;
  double s_above_z1 = 0, s_above_z2 = 0, s_above_max = 0;
};
double kb_trimp_delta(double hr, const KbTrimpConfig& c);    // ΔFC recortado a [0, 1]; NaN si hr no es finito
// Acumula una época de dt_s segundos con FC hr en el acumulador (y en el histograma si hist no es nulo).
void kb_trimp_add(KbTrimp* t, double dt_s, double hr, const KbTrimpConfig& c, std::vector<double>* hist = nullptr);
// Recalcula el TRIMP desde el histograma (segundos por intervalo de 5 lpm, FC = centro del intervalo).
KbTrimp kb_trimp_from_histogram(const std::vector<double>& seconds_per_bin, const KbTrimpConfig& c);

static const int KB_CG_BANDS = 6;
static const double KB_CG_PSI_PACE = 16.7;
static const double KB_CG_EDGES_PSI[KB_CG_BANDS - 1] = {10.0, 13.3, 14.4, 15.5, 16.8};
static const int KB_CG_HS_BAND = 2;        // primera banda de trabajo rápido (≥ 13,3 m/s)
const char* kb_cg_band_name(int k);        // LENTO, MEDIO, RAPIDO_1 … RAPIDO_4
// Bordes de las bandas: absolutos de PSI o escalados por race_pace/16,7 (relative y race_pace finito).
void kb_cg_edges(bool relative, double race_pace, double out[KB_CG_BANDS - 1]);
int kb_cg_band(double v, const double edges[KB_CG_BANDS - 1]);   // 0..5 (-1 con v NaN o < 0)

double kb_ewma_lambda(int n_days);         // 2/(N + 1)
// EWMA aguda y crónica al último día de la serie diaria (días consecutivos; empieza con EWMA = 0).
void kb_ewma(const std::vector<double>& daily, int n_acute, int n_chronic, double* acute, double* chronic);
// Monotonía y strain de Foster sobre los 7 últimos días (días sin sesión = 0). false si la DE es 0 o la media ≤ 0.
bool kb_foster(const std::vector<double>& last7, double* monotony, double* strain);

}  // namespace avoeq
