// Gait Performance Engine (per-gait segments, aggregations per gait and per session) and
// Event Detection Engine (typed, traceable, de-duplicated events with temporal hysteresis).
#pragma once
#include <string>
#include <vector>
#include "avo_eq/fusion.h"
#include "avo_eq/gnss.h"
#include "avo_eq/kinematics.h"
#include "avo_eq/motion.h"
#include "avo_eq/sync.h"
#include "avo_eq/validation.h"

namespace avoeq {

static const char* const PERFORMANCE_VERSION = "1.1.0";
static const char* const EVENTS_VERSION = "1.1.0";

struct PerfConfig {
  double min_gnss_fraction = 0.5;    // below this (and no IMU) a segment becomes INSUFFICIENT_DATA
  double accel_max_sigma = 0.8;
};

struct SegmentPerformance {
  int id = 0;
  Gait gait = Gait::UNKNOWN;
  std::string classifier;            // GAIT_CLASSIFIER_V1 | GAIT_CLASSIFIER_V2
  double t0 = 0, t1 = 0, duration_s = 0;
  double distance_m = NAN, speed_mean = NAN, speed_max = NAN, accel_max = NAN, decel_max = NAN;
  double cadence_mean_hz = NAN, cadence_cv = NAN, cadence_sigma_hz = NAN;
  double interval_cv = NAN, amplitude_cv = NAN, cycle_corr = NAN, spectral_stability = NAN;   // independent, medians
  double stride_length_m = NAN;
  double gnss_fix_fraction = 0, gnss_usable_fraction = 0;
  double imu_valid_fraction = NAN;   // NaN: no girth data
  Quality gnss_quality = Quality::UNKNOWN, imu_quality = Quality::UNKNOWN, class_quality = Quality::UNKNOWN;
  double class_confidence = NAN;
  std::vector<std::string> warnings;
};

struct GaitAggregate {
  Gait gait = Gait::UNKNOWN;
  uint32_t segments = 0;
  double duration_s = 0, distance_m = 0, speed_mean = NAN, speed_max = NAN, cadence_mean_hz = NAN, stride_length_m = NAN;
  double time_fraction = 0;
};

struct PerformanceResult {
  std::string classifier;
  std::vector<SegmentPerformance> segments;
  std::vector<GaitAggregate> per_gait;
  GaitAggregate session;             // gait = UNKNOWN used as "whole session"
  std::vector<Metric> metrics;
};

PerformanceResult analyse_performance(const GaitResult& gait, const GnssResult& g, const FusionResult* fusion,
                                      bool session_has_imu, const PerfConfig& c = PerfConfig());

// ------------------------------------------------------------------ events
struct EventConfig {
  double move_start_speed = 0.6, move_stop_speed = 0.3, move_hold_s = 2.0;   // hysteresis on speed
  double cadence_jump_hz = 0.15;     // abrupt cadence change between consecutive valid windows (and > 3σ)
  double fix_loss_min_s = 1.0;       // FIXED lost for at least this long
  double sync_gap_s = 1.0;           // girth data missing for at least this long while GNSS continues
  double merge_s = 1.0;              // same-type events closer than this are merged (no duplicates)
};

struct Event {
  std::string id;                    // EV0001…
  std::string type;                  // INICIO_MOVIMIENTO | PARADA | ACELERACION_SOSTENIDA | DESACELERACION_SOSTENIDA |
                                     // INICIO_CURVA | FIN_CURVA | TRANSICION_AIRE | CAMBIO_BRUSCO_CADENCIA |
                                     // PERDIDA_REGULARIDAD | PERDIDA_CALIDAD_GNSS | PERDIDA_SINCRONIZACION
  double t0 = 0, t1 = 0;             // GNSS seconds
  std::vector<std::string> data;     // data sources used
  Quality quality = Quality::UNKNOWN;
  std::string reason;                // why it was detected
  std::string algorithm, version;
  std::vector<std::pair<std::string, double>> values;
};

struct EventInputs {
  const GnssResult* gnss = nullptr;
  const KinematicsResult* kin = nullptr;
  const CurveResult* curves = nullptr;
  const GaitResult* gait = nullptr;
  const FusionResult* fusion = nullptr;
  const ValidationReport* validation = nullptr;
  const std::vector<ImuSeries>* imu = nullptr;
  const ClockMap* girth_to_gnss = nullptr;   // array of 3
};

std::vector<Event> detect_events(const EventInputs& in, const EventConfig& c = EventConfig());

}  // namespace avoeq
