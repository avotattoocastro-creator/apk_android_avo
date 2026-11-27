// AVO Cardio (motor 2.0.0-dev29, KB-1 1.27.0): ECG de la cincha PROTOTIPO 0.5.x (MAX30003, 512 muestras/s) en el
// análisis. Ficha: docs/algoritmos/15_ECG_V200.md. Nada de esto es un diagnóstico: la ectopia sale siempre como
// «candidato a revisar» y la V200 no está validada hasta tener el error típico (TE) propio de cada caballo.
//
// 1. Detector de latidos anclado en S (Van Steenkiste 2020 [E]: en el caballo la deflexión dominante del QRS es la S):
//    paso banda 8–35 Hz de fase cero, energía de pendiente en 50 ms, umbral adaptativo (0,3 × mediana de los 8 últimos
//    picos) que se reinicia tras un artefacto o 2 s sin latidos (sin ceguera), periodo refractario de 200 ms, rechazo de
//    la onda T (candidato en el primer 60 % del RR con < 40 % de la energía del latido anterior o con la polaridad
//    contraria) y posición final en el extremo de la S con interpolación parabólica (resolución < 2 ms).
// 2. RR y calidad: RR válido entre 0,2 y 3 s, sin muestras no válidas ni huecos dentro, y entre 0,5 y 1,8 veces la
//    mediana local; lo demás es artefacto. FC en épocas de 5 s en tiempo GNSS (reloj de la cincha → pecho → GNSS con el
//    mismo mapa de envolvente inferior que la IMU) con la velocidad GNSS media de la época.
// 3. Fases (Navas de Solis 2026 [E], cortes de van Erck-Westergren 2026 [E]): CALENTAMIENTO, MAXIMA (épocas > 185 lpm),
//    RECUPERACION_0_2MIN y RECUPERACION_TARDIA desde el fin del esfuerzo (velocidad < 50 % del pico tras el máximo, WU4
//    [I]; sin GNSS, fin de la última época > 185 lpm). Puerta de calidad por fase: > 10 % de artefacto = NO_INTERPRETABLE
//    (Ter Woort 2023 [E]). Se informa además cuándo baja la FC de 120 lpm.
// 4. V200 (velocidad a 200 lpm) por dos métodos, guardando el método como atributo:
//    · CRUCE_200_10S (Poinsard 2026 [E-r]): primer instante en que la FC (mediana de 5 latidos) llega a 200 lpm y se
//      mantiene ≥ 10 s; V200 = velocidad GNSS media de esos 10 s [I]. Es el método principal (el que usa A9).
//    · REGRESION_FC_VELOCIDAD (Vermeulen & Evans 2006 [E]; mesetas [I]): mesetas de velocidad ≥ 30 s con CV < 5 %, se
//      descartan 20 s y se promedian los 15 s finales; recta FC = a + b·v con ≥ 3 mesetas, b > 0 y R² ≥ 0,90; sin
//      extrapolar (200 lpm dentro del rango de las mesetas).
//    VHRmax: velocidad a la FC pico (media de los 5 RR más cortos sin candidatos, Navas de Solis 2026 [E]) por la
//    regresión si la FC pico está en su rango (±2 lpm); si no, velocidad de la época de 5 s con la FC más alta [I].
//    Recuperación: FC media (±5 s) a 1, 2, 4, 5, 10 y 15 min del fin del esfuerzo (solo tendencia del propio caballo).
// 5. Ectopia (A11, candidatos a revisar): RR ≥ 6 % (configurable 5–6 %) más corto que la mediana de los 8 RR previos con
//    FC > 100 lpm (10 % con 60–100 y 20 % con < 60 lpm, solo INFO; Flethøj 2016 [E]), acortamiento < 50 % (más es
//    artefacto) y vuelta del RR a ≥ (1 − umbral/2) de la referencia en ≤ 4 latidos (si no vuelve es aceleración sinusal).
//    Rachas: aislado, pareja, triplete, racha ≥ 4. Recuento por fase con su puerta de calidad.
#pragma once
#include <cmath>
#include <string>
#include <vector>
#include "avo_eq/knowledge.h"
#include "avo_eq/sync.h"
#include "avo_eq/types.h"

namespace avoeq {

static const char* const CARDIO_VERSION = "1.2.0";   // 1.2.0: cinética de la FC CF1, CF2, WU2, FW1 y RC1 (KB 1.33.0); 1.1.0: carga interna CG1 (TRIMP, KB 1.30.0)
static const char* const CARDIO_DETECTOR_ID = "AVO_ECG_S_ANCHOR_V1";
static const char* const V200_METHOD_CROSSING = "CRUCE_200_10S";
static const char* const V200_METHOD_REGRESSION = "REGRESION_FC_VELOCIDAD";

struct CardioConfig {
  bool enabled = true;
  // detector
  double band_lo_hz = 8.0, band_hi_hz = 35.0;
  double energy_window_s = 0.05;
  double threshold_fraction = 0.30;
  double refractory_s = 0.20;            // 300 lpm
  double t_wave_rr_fraction = 0.60, t_wave_energy_fraction = 0.40;
  double search_s = 0.06;                // ventana de búsqueda de la S alrededor del pico de energía
  double no_beat_reset_s = 2.0;
  // RR
  double rr_min_s = 0.20, rr_max_s = 3.0, rr_local_lo = 0.5, rr_local_hi = 1.8;
  // épocas y fases
  double epoch_s = 5.0;
  double epoch_max_artifact = 0.20;
  double max_phase_bpm = 185.0, recovery_bpm = 120.0;
  double effort_end_fraction = 0.50;     // fin del esfuerzo: velocidad < 50 % del pico (WU4) [I]
  double early_recovery_s = 120.0;
  double phase_artifact_gate = 0.10;     // Ter Woort 2023 [E]
  // V200 / VHRmax
  double v200_bpm = 200.0, v200_hold_s = 10.0;
  int hr_smooth_beats = 5;
  double plateau_min_s = 30.0, plateau_discard_s = 20.0, plateau_avg_s = 15.0, plateau_cv = 0.05, plateau_min_speed = 2.0;
  double regression_r2_min = 0.90;
  int regression_min_points = 3;
  double warmup_min_m = 1000.0, warmup_min_s = 600.0;   // WU1 (De Mare 2017 [E]; uso [I]): solo atributo
  // ectopia
  double premature_pct = 6.0;            // 5–6 % (Navas de Solis 2026, Frick 2019 [E]); 6 % por sobredetección (Flethøj 2016)
  double premature_pct_60_100 = 10.0, premature_pct_below_60 = 20.0;
  int premature_ref_beats = 8, premature_min_ref = 4, premature_return_beats = 4;
  int ectopy_tolerated = 10;             // P90 de 5–10 en PSI sanos en el máximo (van Erck 2026 [E]); más = VIGILAR [I]
  // CG1 carga interna (KB 1.30.0): TRIMP con las épocas de 5 s válidas; FC de reposo y máxima por defecto «no propias»
  KbTrimpConfig trimp;
  // Cinética de la FC (cardio 1.2.0, KB 1.33.0). Todo SIN CALIBRAR: atributos y tendencia propia, nunca un estado.
  // CF1 [I] (τ del VO2 10 → 21 s sobre el umbral, Langsetmo 1997 [E-r]): en las mesetas rápidas (≥ 70 % de la velocidad
  // máxima de la sesión) o tras un salto ≥ 3 m/s respecto a los 10 s previos se descartan 30 s y se exigen ≥ 45 s.
  bool cf1_enabled = true;
  double cf1_fast_fraction = 0.70, cf1_jump_m_s = 3.0, cf1_discard_s = 30.0, cf1_min_s = 45.0;
  // WU2 [I]: calentamiento = desde el inicio hasta la primera época ≥ 60 % de la velocidad máxima; «FC alta sin
  // velocidad» = épocas válidas con FC ≥ 120 lpm y velocidad < 1,7 m/s (paso o parado); marca si suman ≥ 60 s.
  double wu_fast_fraction = 0.60, wu_high_hr_bpm = 120.0, wu_low_speed_m_s = 1.7, wu_high_hr_mark_s = 60.0;
  // FW1 [I] (Yamanobe 1993 [E-r]): tramo fijo del calentamiento = últimos 60 s seguidos de épocas válidas entre 3 y
  // 6 m/s con CV de la velocidad ≤ 10 %; su FC media es la tendencia diaria sustituta de la V200.
  double fw_window_s = 60.0, fw_v_lo = 3.0, fw_v_hi = 6.0, fw_cv = 0.10;
  // CF2 [I]: τ de recuperación de la FC por ajuste monoexponencial FC(t) = A + B·e^(−t/τ) sobre las épocas válidas de
  // 60 s a 600 s tras el fin del esfuerzo (sin el primer minuto: fase rápida de Rugh 1992 [E-r, ponis]); cobertura ≥ 60 %,
  // R² ≥ 0,80, τ entre 5 y 900 s. Solo tendencia del propio caballo, sin valores de referencia.
  double tau_from_s = 60.0, tau_to_s = 600.0, tau_min_coverage = 0.60, tau_r2_min = 0.80, tau_min_s = 5.0, tau_max_s = 900.0;
  // RC1: THR100 = tiempo desde el fin del esfuerzo hasta FC (mediana de 5 latidos) < 100 lpm; el corte de 200 s de la
  // JRA es solo una referencia institucional, nunca una alerta.
  double thr100_bpm = 100.0, thr100_jra_ref_s = 200.0;
};

struct EcgBeat {
  double t_girth = NAN;        // s, reloj de la cincha (extremo de la S)
  double t = NAN;              // s, tiempo GNSS desde la primera época (o reloj de la cincha si no hay GNSS)
  double rr = NAN;             // s, desde el latido anterior (NaN si no es válido)
  double amp_mv = NAN;         // amplitud de la S en la señal filtrada
  bool rr_valid = false;
  double ref_rr = NAN;         // s, mediana de los 8 RR previos (referencia del prematuro)
  bool candidate = false;      // ectópico candidato (a revisar)
  bool after_run = false;      // primer latido tras una racha de candidatos (pausa compensadora): fuera de la FC
  int run = 0;                 // longitud de la racha a la que pertenece (1 aislado, 2 pareja, 3 triplete, ≥ 4)
  int phase = -1;
};

struct HrEpoch { double t0 = 0, hr = NAN, speed = NAN, artifact = 1.0; int rr = 0; };

enum CardioPhase { PH_WARMUP = 0, PH_MAX = 1, PH_REC_EARLY = 2, PH_REC_LATE = 3, PH_COUNT = 4 };
const char* cardio_phase_name(int p);

struct CardioPhaseStats {
  double t0 = NAN, t1 = NAN, duration_s = 0, artifact = NAN;
  bool interpretable = false;
  int beats = 0, candidates = 0, candidates_hr100 = 0;
};

struct V200Result {
  double value = NAN;          // m/s
  std::string method;          // V200_METHOD_*
  double t_cross = NAN;        // CRUCE: instante del cruce (s)
  double slope = NAN, intercept = NAN, r2 = NAN;   // REGRESION: FC = intercept + slope·v
  int points = 0;
  bool warmup_ok = false;      // WU1: ≥ 1000 m o ≥ 10 min antes del cruce / de la primera meseta rápida
  std::string reason;          // por qué falta
};

struct CardioResult {
  bool present = false, aligned_gnss = false;
  std::string algorithm = CARDIO_DETECTOR_ID, version = CARDIO_VERSION;
  uint32_t batches = 0, samples = 0, invalid_samples = 0, duplicates = 0;
  double fs_hz = NAN, duration_s = 0, artifact = NAN;
  int polarity = 0;            // +1 / −1: signo de la S en la señal filtrada
  std::vector<EcgBeat> beats;
  std::vector<HrEpoch> epochs;
  double hr_peak = NAN, hr_epoch_max = NAN, hr_mean = NAN;
  double effort_end_t = NAN, below_120_after_s = NAN;
  CardioPhaseStats phases[PH_COUNT];
  V200Result v200, v200_regression, vhrmax;
  struct Recovery { double minute = 0, hr = NAN, drop = NAN; };
  std::vector<Recovery> recovery;
  std::string cooldown_class;  // PARADO | PASO | TROTE (WU4, 10 primeros minutos) o vacío
  // ectopia
  int candidates = 0, isolated = 0, pairs = 0, triplets = 0, runs = 0;
  std::string ectopy_level = "INFO", ectopy_text;
  std::string quality = "NO_UTILIZABLE";   // BUENA | UTILIZABLE | POBRE | NO_UTILIZABLE
  KbTrimp trimp;                           // CG1 (épocas válidas)
  std::vector<double> hr_hist;             // segundos por intervalo de 5 lpm (épocas válidas)
  double trimp_coverage = NAN;             // fracción de la sesión con FC válida
  // Cinética de la FC (cardio 1.2.0, KB 1.33.0)
  struct Warmup {           // WU2
    double t0 = NAN, t1 = NAN, duration_s = NAN, distance_m = NAN, hr_mean = NAN, speed_mean = NAN, high_hr_still_s = NAN;
    bool sufficient = false;  // WU1: ≥ 1000 m o ≥ 10 min
    std::string origin;       // VELOCIDAD | FC (sin GNSS: hasta la primera época > 185 lpm) | "" (sin calentamiento)
  } warmup;
  struct FixedSegment { double t0 = NAN, duration_s = NAN, hr = NAN, speed = NAN, cv = NAN; } fixed_warmup;   // FW1
  struct TauFit { double tau_s = NAN, asymptote = NAN, amplitude = NAN, r2 = NAN, coverage = NAN; int points = 0; std::string reason; } tau;   // CF2
  double thr100_s = NAN;    // RC1
  int cf1_plateaus = 0;     // mesetas a las que se aplicó CF1
  std::vector<std::string> warnings;
};

// Ajuste FC(t) = A + B·e^(−t/τ) por mínimos cuadrados (búsqueda de τ en [tau_min, tau_max] con A y B lineales).
// t en segundos desde el fin del esfuerzo. Expuesto para las pruebas.
CardioResult::TauFit fit_hr_recovery(const std::vector<double>& t, const std::vector<double>& hr, double tau_min, double tau_max);

// Detector puro sobre una serie uniforme (mV, NaN = muestra no válida) a fs Hz. Devuelve las posiciones de los latidos
// en segundos desde la primera muestra y la amplitud; polarity_out recibe el signo de la S. Expuesto para las pruebas.
std::vector<EcgBeat> detect_beats(const std::vector<double>& mv, double fs, const CardioConfig& c, int* polarity_out = nullptr);

// Análisis cardiaco sobre una serie RR ya detectada (tiempo GNSS) y la velocidad GNSS: RR válidos, épocas, fases,
// V200, VHRmax, recuperación y ectopia. Es la parte que no depende del formato de la cincha.
// gnss_t / gnss_v: tiempo (s) y velocidad (m/s, NaN si no es utilizable); pueden estar vacíos.
// gap_t0 / gap_t1: intervalos sin señal (artefacto) en la misma escala de tiempo.
void analyse_rr(std::vector<EcgBeat> beats, const std::vector<double>& gnss_t, const std::vector<double>& gnss_v,
                const std::vector<std::pair<double, double>>& gaps, double t_begin, double t_end, const CardioConfig& c, CardioResult* r);

// Análisis completo de la sesión (ECG de Session::ecg). chest_to_gnss: mapa del pecho al GNSS (puede estar vacío).
CardioResult analyse_cardio(const Session& s, const ClockMap& chest_to_gnss, const std::vector<double>& gnss_t,
                            const std::vector<double>& gnss_v, const SyncConfig& sync, const CardioConfig& c);

// Bloque "cardio" del JSON avo-equine-analysis (series = épocas y latidos incluidos).
std::string cardio_json(const CardioResult& r, const CardioConfig& c, bool series);

}  // namespace avoeq
