// AVO Track Work 1.0.0 — análisis de los ENTRENAMIENTOS de caballos de carreras (perfiles PSI y árabe) con la cincha
// y el GNSS. Código interno con nombre «racing»; bloque JSON «trabajo_pista».
//
// A. Cincha sola (IMU_HORSE_FRAME_V1): escala física, vertical por gravedad, ejes de avance y lateral (PCA),
//    VeDBA (aceleración dinámica del cuerpo), giro sobre la vertical (tiempo y grados a cada mano), saturación.
// B. Zancadas en galope (STRIDE_V1): duración, frecuencia, impacto vertical, desplazamiento vertical del tronco,
//    VeDBA, velocidad GNSS y longitud de zancada; relación frecuencia/longitud con la velocidad.
// C. Mano de galope (LEAD_V1, EXPERIMENTAL): el rasgo lateral cambia de signo entre mano izquierda y derecha
//    (simetría especular). El signo se calibra en las curvas (se espera la mano de dentro) o por opción.
// D. Trabajos del entrenamiento (EFFORT_V1, GNSS): galopes de trabajo y trabajos rápidos con parciales cada 200 m
//    (o furlong), mejores distancias, velocidad máxima, índice de caída (fatiga), zancada a velocidad de referencia,
//    recuperación hasta el paso y pausa hasta la siguiente repetición.
// F. Estructura de la sesión (SESSION_PHASES_V1): calentamiento, trabajo y vuelta a la calma (tiempo por aire y
//    distancia), series (repeticiones, caída de velocidad y de zancada entre la primera y la última).
// E. Eventos de la cincha (EXPERIMENTAL): impactos atípicos, movimientos laterales bruscos, saturación.
// Todo es exploratorio y NO VERIFICADO con caballos reales; los perfiles de raza son valores de partida.
#pragma once
#include <cmath>
#include <string>
#include <vector>
#include "avo_eq/gnss.h"
#include "avo_eq/motion.h"
#include "avo_eq/sync.h"
#include "avo_eq/types.h"

namespace avoeq {

static const char* const RACING_VERSION = "1.0.0";

struct BreedProfile {
  std::string name = "GENERICO";     // GENERICO | PSI | ARABE
  double work_speed = 9.0;           // m/s: galope de trabajo a partir de aquí
  double fast_speed = 12.0;          // m/s: un trabajo es RAPIDO si su máxima llega aquí
  double high_speed = 11.0;          // m/s: distancia a alta velocidad (carga)
  double ref_speed[2] = {10.0, 12.0};// m/s: velocidades de referencia para comparar la zancada entre sesiones
  double sf_min = 1.5, sf_max = 3.0; // Hz: frecuencia de zancada plausible en galope
  double sl_min = 2.5, sl_max = 9.0; // m: longitud de zancada plausible
};
// "PSI" (pura sangre inglés), "ARABE" (pura sangre árabe) o "GENERICO". false si no se conoce.
bool breed_profile(const std::string& name, BreedProfile* p);

// Recorrido de entrenamiento (mismo formato que geocercas.json de Windows/iPad: líneas A→B con sentido).
struct GeoPoint { double lat = NAN, lon = NAN; };
struct Gate {
  bool enabled = false;
  std::string name;
  GeoPoint a, b;
  int direction = 0;                 // 0 ambos; +1 de izquierda a derecha (mirando de A a B); −1 de derecha a izquierda
};
struct CourseConfig {
  Gate start, finish;                // SALIDA y META (si solo hay una línea SALIDA_META: vueltas entre cruces)
  Gate start_finish;
  std::vector<GeoPoint> fence;       // geocerca de grabación (polígono), opcional
  std::string name;
  bool defined() const { return (start.enabled && finish.enabled) || start_finish.enabled; }
};

struct RacingConfig {
  BreedProfile breed;
  CourseConfig course;
  double split_m = 200.0;            // parciales (201.168 = furlong)
  double effort_min_s = 10.0;        // duración mínima de un trabajo
  double effort_gap_s = 3.0;         // bajadas cortas por debajo del umbral dentro del mismo trabajo
  double gravity_lp_hz = 0.25;       // paso bajo para estimar la vertical
  double turn_min_deg_s = 4.0;       // |giro| por encima: el caballo está girando
  double lead_sign = 0;              // 0 = autocalibrar en curvas; +1/-1 = signo fijado con una sesión etiquetada
  double lead_min_corr = 0.15;       // |rasgo| mínimo para decidir la mano de una zancada
  double lead_min_agreement = 0.65;  // autocalibración: acuerdo mínimo con la mano de dentro en curvas
  int lead_min_curve_strides = 12;
  double event_k = 6.0;              // eventos: pico por encima de mediana + k·MAD de los picos de zancada
  double event_min_g = 1.5;          // y por encima de este valor absoluto (g)
  double walk_speed = 2.2;           // m/s: recuperación = hasta volver al paso (por debajo de esto)…
  double recovery_hold_s = 5.0;      // …y mantenerlo este tiempo
  double warmup_min_s = 600.0;       // aviso si el calentamiento antes del primer trabajo rápido es más corto
};

struct Stride {
  double t0 = 0, t1 = 0;             // s GNSS
  double duration_s = 0, freq_hz = 0;
  double speed = NAN, length_m = NAN;// GNSS (NaN sin GNSS)
  double vert_peak_g = NAN;          // pico de aceleración vertical dinámica
  double vert_disp_m = NAN;          // desplazamiento vertical pico a pico del tronco (doble integración por zancada)
  double vedba_g = NAN;              // media de |a dinámica|
  double lat_feature = NAN;          // correlación lateral/vertical (cambia de signo con la mano)
  double yaw_deg_s = NAN;            // giro medio sobre la vertical (+ izquierda)
  int lead = 0;                      // +1 izquierda, -1 derecha, 0 indeterminada
  bool in_curve = false;
};

struct TurnStats { double left_s = 0, right_s = 0, left_deg = 0, right_deg = 0; };

struct Sectional { double from_m = 0, to_m = 0, time_s = NAN, speed = NAN; };
struct BestSplit { double distance_m = 0, time_s = NAN, t0 = NAN; };

struct Effort {
  int id = 0;
  std::string type;                  // GALOPE_TRABAJO | TRABAJO_RAPIDO
  double t0 = 0, t1 = 0, duration_s = 0, distance_m = 0, speed_mean = NAN;
  double vmax = NAN, t_to_vmax_s = NAN, dist_above_90_m = NAN, accel_max = NAN;
  double v_last_200 = NAN, v_last_400 = NAN, fatigue_pct = NAN;   // caída: (vmax − media últimos 200 m) / vmax
  double last_200_s = NAN, last_400_s = NAN;
  std::vector<Sectional> sectionals;
  std::vector<BestSplit> best;
  // zancada (si hay cincha)
  int strides = 0;
  double sf_at_vmax = NAN, sl_at_vmax = NAN, sf_max = NAN, sl_max = NAN;
  double sf_slope = NAN, sf_icpt = NAN, sl_slope = NAN, sl_icpt = NAN, fit_r_sf = NAN;   // f = a + b·v ; l = c + d·v
  double sf_ref[2] = {NAN, NAN}, sl_ref[2] = {NAN, NAN};          // a las velocidades de referencia (si están en rango)
  int lead_left = 0, lead_right = 0, lead_changes = 0;
  // entrenamiento
  double recovery_to_walk_s = NAN;   // desde el final del trabajo hasta volver al paso (NaN: no volvió antes del final)
  double pause_to_next_s = NAN, pause_speed_mean = NAN;   // pausa hasta la siguiente repetición
};

struct GateCrossing { std::string gate; double t = 0; bool left_to_right = false; bool counts = false; };

struct PhaseStats {
  bool present = false;
  double t0 = NAN, t1 = NAN, duration_s = 0, distance_m = 0;
  double walk_s = 0, trot_s = 0, canter_s = 0, stopped_s = 0;
};

struct RacingEvent {
  std::string type;                  // IMPACTO_ATIPICO | MOVIMIENTO_LATERAL_BRUSCO | CAMBIO_DE_MANO | SATURACION
  double t = 0;                      // s GNSS (o s de la cincha si no hay mapa)
  double value = NAN;                // g o grados/s según el tipo
  std::string detail;
};

struct RacingResult {
  std::string profile;
  // A. cincha
  bool has_imu = false;
  std::string scale;                 // BNO085 | GRAVEDAD_ESTIMADA | SIN_CINCHA
  double g_lsb = NAN;                // LSB por g usados
  double frame_quality = NAN;        // 0..1: estabilidad de la vertical estimada
  bool forward_sign_known = false;
  double imu_seconds = 0;
  double vedba_mean_g = NAN, vedba_load_gmin = NAN;   // media en movimiento y carga = ∫VeDBA (g·min)
  double vedba_gait[3] = {NAN, NAN, NAN};             // PASO, TROTE, GALOPE
  TurnStats turns_total, turns_gait[3];
  uint32_t saturated_samples = 0;
  // B/C. zancadas y mano
  std::vector<Stride> strides;
  std::string lead_calibration;      // CURVAS | OPCION | SIN_CALIBRAR
  double lead_sign_used = 0;         // signo aplicado (guardarlo y pasarlo como "signo_mano" en sesiones sin curvas)
  double lead_agreement = NAN;       // acuerdo con la mano de dentro en curvas (autocalibración)
  int lead_left = 0, lead_right = 0, lead_changes = 0;
  double wrong_lead_curve_pct = NAN; // zancadas en curva con la mano de fuera
  // D. trabajos
  std::vector<Effort> efforts;
  double best_200_s = NAN, vmax = NAN, dist_fast_m = 0, dist_work_m = 0;
  // G. recorrido (líneas de salida y meta)
  bool course_defined = false;
  std::string course_name;
  double gate_distance_m = NAN;      // distancia en línea recta entre los centros de salida y meta
  std::vector<GateCrossing> crossings;
  std::vector<Effort> passes;        // PASADA: de la salida a la meta (o vueltas)
  double best_pass_s = NAN;
  double fence_inside_pct = NAN;     // épocas GNSS dentro de la geocerca
  // F. estructura de la sesión
  std::string phase_basis = "VELOCIDAD";   // LINEAS cuando hay pasadas por el recorrido
  PhaseStats warmup, work, cooldown;
  int reps = 0, fast_reps = 0;
  double vmax_drop_pct = NAN;        // (máxima de la 1.ª repetición rápida − de la última) / 1.ª
  double stride_drop_pct = NAN;      // igual con la longitud de zancada a la máxima
  double recovery_mean_s = NAN;      // media de la recuperación hasta el paso tras los trabajos rápidos
  bool warmup_short = false;
  // E. eventos
  std::vector<RacingEvent> events;
  std::vector<std::string> warnings;
};

// imu_units: 1 = la cincha declara unidades del BNO085 (acc Q8 m/s², giro Q9 rad/s); 0 = escala por gravedad.
RacingResult analyse_racing(const GnssResult& g, const std::vector<ImuSeries>& imu, const ClockMap girth_to_gnss[3],
                            const GaitResult& gait, uint8_t imu_units, const RacingConfig& c);
std::string racing_json(const RacingResult& r, const RacingConfig& c);

}  // namespace avoeq
