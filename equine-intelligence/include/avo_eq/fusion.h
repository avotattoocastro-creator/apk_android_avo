// Sensor Fusion Engine — TEMPORAL fusion of the rider's GNSS (back) and the girth IMUs (horse).
// They are NOT one rigid body: no inertial navigation, no attitude estimation, no mixing of accelerations.
// The fusion associates each girth analysis window with the GNSS state of the same instant (clock maps
// without PPS), propagates the timing uncertainty and builds velocity–cadence / velocity–regularity relations.
//
// Modes:
//   OFFLINE_ANALYSIS  — whole session available: two-sided derivatives, centred windows, maps from every pair.
//   REALTIME_ANALYSIS — every result at instant "now" uses ONLY data received by the chest up to "now"
//                       (clock maps refitted with past pairs, one-sided GNSS slope, per-window filtering).
#pragma once
#include <cmath>
#include <string>
#include <vector>
#include "avo_eq/gnss.h"
#include "avo_eq/motion.h"
#include "avo_eq/sync.h"
#include "avo_eq/types.h"
#include "avo_eq/validation.h"

namespace avoeq {

static const char* const FUSION_VERSION = "1.1.0";

enum class AnalysisMode : uint8_t { OFFLINE_ANALYSIS = 0, REALTIME_ANALYSIS = 1 };
const char* mode_name(AnalysisMode m);

struct FusionConfig {
  AnalysisMode mode = AnalysisMode::OFFLINE_ANALYSIS;
  double max_interp_gap_s = 0.3;    // GNSS: linear interpolation only between epochs closer than this
  double max_sync_sigma_s = 0.020;  // timing uncertainty above this: window marked SIN_SINCRONIA
  double min_gnss_fraction = 0.6;   // fraction of the window covered by usable GNSS epochs
  double realtime_slope_s = 1.0;    // one-sided slope window for the real-time acceleration
  double min_relation_points = 8;   // windows needed for a velocity relation
};

struct FusedWindow {
  uint8_t imu_id = 0;
  uint32_t window_index = 0;        // index in CadenceResult::windows (traceability)
  double t_imu = 0;                 // girth clock (s), window centre
  double t_gnss = NAN, sigma_t = NAN;   // GNSS time of the window centre and its 1-sigma (clock map)
  double t_available = NAN;         // REALTIME: chest reception instant when the result became available
  std::string status;               // OK | SIN_SINCRONIA | HUECO_GNSS | SIN_CADENCIA | DATOS_INSUFICIENTES
  // GNSS state over the same window
  double speed = NAN, speed_sigma = NAN;   // mean speed over the window; σ includes sAcc and timing (a·σt)
  double accel = NAN, accel_sigma = NAN;   // longitudinal, trajectory (NOT the IMU acceleration)
  double lat_accel = NAN;                  // estimated lateral acceleration of the trajectory
  double gnss_fraction = 0;                // window time covered by usable epochs
  bool gnss_interpolated = false;          // centre value obtained by controlled linear interpolation
  uint32_t gnss_i0 = 0, gnss_i1 = 0;       // GNSS epochs used (traceability)
  // girth window (unchanged values, cadence only when VALID)
  double cadence_hz = NAN, cadence_sigma = NAN;
  double stride_length_m = NAN, stride_length_sigma = NAN;   // speed / cadence, propagated uncertainty
  double interval_cv = NAN, amplitude_cv = NAN, cycle_corr = NAN, spectral_stability = NAN;
  Gait gait = Gait::UNKNOWN;
};

struct Relation {
  std::string x, y, gait;           // e.g. velocidad_m_s vs cadencia_hz, gait or "TODOS"
  uint32_t n = 0;
  double slope = NAN, intercept = NAN, slope_sigma = NAN, r = NAN;   // weighted least squares (1/σy²)
  double spearman = NAN;            // rank correlation (robust, for regularity metrics)
  std::string note;
};

struct FusionResult {
  AnalysisMode mode = AnalysisMode::OFFLINE_ANALYSIS;
  std::vector<FusedWindow> windows;
  std::vector<Relation> relations;
  uint32_t windows_total = 0, windows_ok = 0, no_sync = 0, gnss_gap = 0, no_cadence = 0;
  double median_sigma_t_ms = NAN;
  std::vector<Metric> metrics;
  std::vector<std::string> warnings;
};

// OFFLINE: uses the analysis already computed (gnss, cadence windows, maps, gait segments).
FusionResult fuse_offline(const GnssResult& g, const std::vector<CadenceResult>& cad, const ClockMap girth_to_gnss[3],
                          const GaitResult* gait, const FusionConfig& c = FusionConfig());

// REALTIME: recomputes everything causally from the session (results independent of later data).
FusionResult fuse_realtime(const Session& s, const ValidationReport& v, const std::vector<ImuSeries>& imu,
                           const CadenceConfig& cc, const SyncConfig& sc, const FusionConfig& c = FusionConfig());

}  // namespace avoeq
