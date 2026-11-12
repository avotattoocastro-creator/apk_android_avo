// Full analysis of one session: validation -> synchronisation -> GNSS -> IMU -> cadence/regularity ->
// gait -> anomalies -> quality -> report. Deterministic: the same input and version give the same output.
#pragma once
#include <string>
#include <vector>
#include <exception>
#include <memory>
#include "avo_eq/fusion.h"
#include "avo_eq/gnss.h"
#include "avo_eq/kinematics.h"
#include "avo_eq/motion.h"
#include "avo_eq/performance.h"
#include "avo_eq/racing.h"
#include "avo_eq/symmetry.h"
#include "avo_eq/sync.h"
#include "avo_eq/types.h"
#include "avo_eq/validation.h"

namespace avoeq {

struct QualityIndicator {
  std::string domain;            // GNSS, IMU, TIEMPO, INTEGRIDAD, CALIBRACION, DISPONIBILIDAD, ALGORITMO
  Quality level = Quality::UNKNOWN;
  std::vector<std::string> reasons;   // why (always filled)
};

struct Anomaly {
  std::string kind;              // ADQUISICION | MOVIMIENTO | CAMBIO_DE_AIRE | SIN_CLASIFICAR
  std::string code, explanation;
  double t0 = 0, t1 = 0;         // GNSS seconds (or source seconds for IMU-only when unmapped)
  std::vector<std::pair<std::string, double>> evidence;
};

// AVO-ASSIGN-1: horse and rider assigned in an app after recording (docs/ASIGNACION_CABALLO.md).
// Empty = use what the RAW header says. The RAW itself is never modified.
struct IdentityConfig {
  std::string horse_code, horse_name, rider_code, rider_name;
  bool any() const { return !horse_code.empty() || !horse_name.empty() || !rider_code.empty() || !rider_name.empty(); }
};

struct EngineConfig {
  IdentityConfig identity;         // AVO-ASSIGN-1 (changes only the identity in the output, never the numbers)
  ValidationConfig validation;
  GnssConfig gnss;
  CadenceConfig cadence;
  GaitConfig gait;                 // GAIT_CLASSIFIER_V1
  GaitV2Config gait_v2;            // GAIT_CLASSIFIER_V2
  SyncConfig sync;
  AccelConfig accel;
  CurveConfig curves;
  FusionConfig fusion;             // fusion.mode selects OFFLINE_ANALYSIS / REALTIME_ANALYSIS
  PerfConfig perf;
  EventConfig events;
  SymmetryConfig symmetry;
  RacingConfig racing;             // AVO Racing: breed profile (GENERICO | PSI | ARABE) and options
  bool performance_uses_v2 = false;   // V1 stays the reference until V2 is shown better on labelled data
  const GaitModel* gait_model = nullptr;   // optional trained model for V2 (not owned)
  const volatile int* cancel = nullptr;    // non-zero = stop as soon as possible (throws Cancelled)
};

struct Cancelled : std::exception { const char* what() const noexcept override { return "análisis cancelado"; } };

// Versions of every algorithm, stored with each result (persistence invalidates on any change).
std::vector<std::pair<std::string, std::string>> algorithm_versions();
// Stable hash (hex) of the parameters that change results.
std::string params_hash(const EngineConfig& c);

struct Analysis {
  std::string engine_version, processed_at_utc, session_id;
  ValidationReport validation;
  GnssResult gnss;
  ClockMap chest_to_gnss;        // chest reception clock -> GNSS time (from GNSS epochs)
  ClockMap girth_to_gnss[3];     // per IMU: girth acquisition clock -> GNSS time
  std::vector<ImuSeries> imu;
  std::vector<CadenceResult> cadence;
  GaitResult gait;                // GAIT_CLASSIFIER_V1 (reference)
  GaitResult gait_v2;             // GAIT_CLASSIFIER_V2
  KinematicsResult kinematics;
  CurveResult curves;
  FusionResult fusion;
  PerformanceResult performance;
  SymmetryResult symmetry;
  std::vector<Event> events;
  RacingResult racing;
  AnalysisMode mode = AnalysisMode::OFFLINE_ANALYSIS;
  std::string input_fingerprint, parameters_hash;
  bool has_imu = false, has_gnss = false;
  std::vector<std::string> warnings;
  std::vector<Anomaly> anomalies;
  std::vector<QualityIndicator> quality;
};

Analysis analyse(const Session& s, const EngineConfig& c = EngineConfig(), const std::string& processed_at_utc = "");

// JSON format "avo-equine-analysis" version 2 (all keys of version 1 are kept; see docs/FORMATO_RESULTADOS.md).
std::string to_json(const Analysis& a, const Session& s, const EngineConfig& c, bool include_series = false);
std::string gnss_csv(const Analysis& a);
std::string gait_csv(const Analysis& a);
std::string cadence_csv(const Analysis& a);

}  // namespace avoeq
