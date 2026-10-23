// Symmetry Analysis Engine — EXPLORATORY_MOTION_SYMMETRY.
// Describes reproducible differences between the two halves of the stride signal and between girth sensors.
// It is NOT a lameness or clinical assessment, and no such term is produced. Conclusions are withheld when
// calibration, sensor orientation, saturation, regularity of the movement or timing quality do not allow them.
#pragma once
#include <cmath>
#include <string>
#include <vector>
#include "avo_eq/motion.h"
#include "avo_eq/sync.h"

namespace avoeq {

static const char* const SYMMETRY_LABEL = "EXPLORATORY_MOTION_SYMMETRY";
static const char* const SYMMETRY_VERSION = "1.1.0";

struct SymmetryConfig {
  double min_cycle_corr = 0.8;       // irregular windows are excluded
  double max_saturated_frac = 0.005; // windows with more saturated samples are excluded
  double max_sync_sigma_s = 0.010;   // inter-sensor timing needs this synchronisation
  int min_windows = 5;               // per gait, for any statement
  double min_sign_consistency = 0.8; // fraction of windows with the same sign to call a difference reproducible
  bool sensors_calibrated = false;   // inter-sensor amplitude comparison only when true
};

struct SymmetryControl { std::string control, state, reason; };   // state: OK | AVISO | BLOQUEA

struct Spread { double median = NAN, iqr = NAN; uint32_t n = 0; double sign_consistency = NAN; bool reproducible = false; };

struct SymmetryGroup {
  uint8_t imu_id = 0;
  std::string gait;                  // gait name or "TODOS"
  uint32_t windows = 0, strides = 0;
  Spread amp_log_ratio;              // ln(A first beat / A second beat), intra-sensor (scale-free)
  Spread timing_asym;                // (d1 - d2) / (d1 + d2) of the two beat intervals
  Spread half_similarity;            // correlation between both halves of the stride
  Spread vertical_energy;            // fraction of band energy on the axis aligned with gravity (ESTIMATED)
  Spread horizontal_ratio;           // energy ratio of the two remaining axes (orientation unknown)
};

struct InterSensor {
  uint8_t a = 1, b = 2;
  std::string gait;
  Spread lag_s;                      // cross-correlation lag of |a| (b relative to a), seconds
  Spread lag_cycle_fraction;         // lag / stride period
  Spread rms_ratio;                  // only when calibrated, otherwise blocked
  std::string state;                 // OK | BLOQUEA
  std::string reason;
};

struct SymmetryResult {
  std::string label = SYMMETRY_LABEL;
  std::string version = SYMMETRY_VERSION;
  std::vector<SymmetryControl> controls;
  std::vector<SymmetryGroup> groups;
  std::vector<InterSensor> inter;
  uint32_t windows_used = 0, excluded_irregular = 0, excluded_saturated = 0, excluded_status = 0;
  bool conclusions_allowed = false;
  std::vector<std::string> notes;
};

SymmetryResult analyse_symmetry(const std::vector<ImuSeries>& imu, const std::vector<CadenceResult>& cad, const ClockMap girth_to_gnss[3],
                                const GaitResult* gait, const CadenceConfig& cc = CadenceConfig(), const SymmetryConfig& c = SymmetryConfig());

}  // namespace avoeq
