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

static const char* const KNOWLEDGE_VERSION = "1.0.0";
static const char* const KNOWLEDGE_ID = "AVO_KB_1";
static const char* const BONE_MODEL_ALGORITHM = "SBFL_MORRICE_WEST_2022";

struct BoneModelConfig {
  double sigma_max_mpa = 90.0;   // escenario de 90 MPa (9,34 % de media por carrera en Morrice-West 2022); rango 54–90
  double f_max_n_kg = 24.13;
  double sn_a_mpa = 134.2;       // σ0 de Martig 2013 (Anwar 2026 da 139,0 en una tabla truncada: [NV])
  double sn_b_mpa = 14.1;
  double valid_min_speed = 12.57;// filtro de zancadas de Morrice-West 2022
  double low_min_speed = 4.0;    // por debajo no se cuenta nada (paso y trote)
  double max_speed = 25.0;       // por encima: dato GNSS no plausible
};

double bone_vertical_force_n_kg(double v);           // saturada en 24,13 N/kg
// Fracción de vida a fatiga consumida por una zancada a v m/s (0 con v NaN, ≤ 0 o > max_speed).
double bone_stride_damage(double v, const BoneModelConfig& c);
double model_stride_frequency_hz(double v);          // Hz

static const int KB_BANDS = 3;
const char* kb_band_name(int b);                     // B1_TRABAJO, B2_INTERMEDIA, B3_ALTA
struct SpeedBandConfig {
  double work_speed = 9.0;       // inicio de B1 (v_trabajo de la raza)
  double race_pace = NAN;        // ritmo de carrera de referencia (m/s); NaN: todo en B1 y sin contadores de Verheyen
  double b2_fraction = 0.80, b3_fraction = 0.93;
  double canter_lo_fraction = 0.40, gallop_fraction = 14.0 / 16.7;
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
  double gallop_session_min_m = 100.0; // metros de galope (> 14 m/s en PSI) para contar como sesión rápida
  double bone_week_ratio = 1.5;        // KB-B: fatiga ósea de 7 días frente a la mediana semanal propia [I]
  int bone_min_weeks = 4;
};

struct KbDay {
  long day = 0;
  double band_m[KB_BANDS] = {NAN, NAN, NAN};
  double canter_m = NAN, gallop_m = NAN, bone_pct = NAN;
};

struct KbFlag { std::string rule, level, action, text, evidence; };   // level INFO | VIGILAR; action AVISO | LIMITAR
struct KbWindow {
  double band_m[KB_BANDS] = {0, 0, 0};
  double canter_m = 0, gallop_m = 0, bone_pct = 0;
  int sessions = 0, missing = 0;
};
struct KbStatus {
  bool available = false;
  KbWindow w7, w30, prev30, w60;
  double bone_weekly_median = NAN, bone_ratio = NAN;
  int days_since_gallop = -1;          // días desde la última sesión rápida (-1: ninguna)
  int return_day = -1;                 // día de la vuelta tras descanso largo (-1: no hay vuelta en curso)
  int return_rest = 0;                 // días sin trabajo rápido antes de esa vuelta
  std::vector<KbFlag> flags;
};

// Evalúa las reglas al día at_day con las sesiones ordenadas por día (se ignoran las posteriores a at_day).
// first_day: primer día de la historia del caballo (para saber si las ventanas están cubiertas).
KbStatus kb_evaluate(const std::vector<KbDay>& sessions, long at_day, long first_day, const KbRuleConfig& c);
std::string kb_status_json(const KbStatus& s);

}  // namespace avoeq
