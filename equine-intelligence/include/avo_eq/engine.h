// Full analysis of one session: validation -> synchronisation -> GNSS -> IMU -> cadence/regularity ->
// gait -> anomalies -> quality -> report. Deterministic: the same input and version give the same output.
#pragma once
#include <string>
#include <vector>
#include "avo_eq/gnss.h"
#include "avo_eq/motion.h"
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

struct EngineConfig {
  ValidationConfig validation;
  GnssConfig gnss;
  CadenceConfig cadence;
  GaitConfig gait;
  SyncConfig sync;
};

struct Analysis {
  std::string engine_version, processed_at_utc, session_id;
  ValidationReport validation;
  GnssResult gnss;
  ClockMap chest_to_gnss;        // chest reception clock -> GNSS time (from GNSS epochs)
  ClockMap girth_to_gnss[3];     // per IMU: girth acquisition clock -> GNSS time
  std::vector<ImuSeries> imu;
  std::vector<CadenceResult> cadence;
  GaitResult gait;
  std::vector<Anomaly> anomalies;
  std::vector<QualityIndicator> quality;
};

Analysis analyse(const Session& s, const EngineConfig& c = EngineConfig(), const std::string& processed_at_utc = "");

std::string to_json(const Analysis& a, const Session& s, const EngineConfig& c, bool include_series = false);
std::string gnss_csv(const Analysis& a);
std::string gait_csv(const Analysis& a);
std::string cadence_csv(const Analysis& a);

}  // namespace avoeq
