// Data validation: flags problems, never changes or interpolates original data.
#pragma once
#include <cstdint>
#include <string>
#include <vector>
#include "avo_eq/types.h"

namespace avoeq {

enum GnssFlag : uint32_t {
  GF_NO_FIX = 1u << 0,          // gnssFixOK not set or fix type < 3
  GF_INVALID_LLH = 1u << 1,     // flags3 invalidLlh
  GF_IMPOSSIBLE = 1u << 2,      // coordinates/speeds outside physical limits
  GF_DUPLICATE = 1u << 3,       // same iTOW as the previous epoch
  GF_TIME_BACKWARDS = 1u << 4,  // iTOW goes back (not a week rollover)
  GF_GAP_BEFORE = 1u << 5,      // gap larger than 2.5 nominal periods before this epoch
  GF_POS_JUMP = 1u << 6,        // displacement inconsistent with the reported velocity
  GF_HACC_HIGH = 1u << 7,       // horizontal accuracy worse than the configured limit
  GF_SACC_HIGH = 1u << 8,       // speed accuracy worse than the configured limit
  GF_FEW_SATS = 1u << 9,
};

enum ImuFlag : uint32_t {
  IF_SATURATED = 1u << 0,       // any axis at the int16 limit (true saturation needs the sensor range)
  IF_DUPLICATE = 1u << 1,       // same (imu, batch, index) seen before
  IF_TIME_BACKWARDS = 1u << 2,
  IF_GAP_BEFORE = 1u << 3,      // missing samples before this one (period-based)
  IF_STUCK = 1u << 4,           // all axes identical to the previous sample (frozen sensor)
};

struct ValidationConfig {
  double max_speed_ms = 25.0;   // 90 km/h: above any horse (racing gallop ~ 18-19 m/s)
  double max_hacc_m = 0.5;      // "usable for training analysis"
  double max_sacc_ms = 0.5;
  int min_sats = 6;
  double pos_jump_factor = 5.0; // displacement > factor * (v*dt + 3*hacc) is a jump
  int16_t sat_limit = 32760;
};

struct Issue {
  std::string code, detail;
  double t_s = 0;               // seconds from session start (GNSS base when known)
  uint32_t count = 1;
};

struct ValidationReport {
  std::vector<uint32_t> gnss_flags;    // one per Session::gnss
  std::vector<uint32_t> imu_flags;     // one per Session::imu
  std::vector<Issue> issues;           // aggregated, human readable
  double gnss_nominal_hz = 0;          // measured median rate
  double imu_nominal_hz[3] = {0, 0, 0};
  uint32_t gnss_gaps = 0, gnss_missing_epochs = 0, imu_missing[3] = {0, 0, 0}, imu_saturated = 0;
};

// Seconds of each GNSS epoch from the first one, unwrapping GPS week rollovers.
std::vector<double> gnss_time_s(const std::vector<GnssEpoch>& g);

ValidationReport validate(const Session& s, const ValidationConfig& cfg = ValidationConfig());

}  // namespace avoeq
