// AVO EQUINE INTELLIGENCE ENGINE — common data types.
// Original measurements are kept untouched; everything derived lives in separate structures
// and carries the algorithm name, version, quality and the reasons behind that quality.
#pragma once
#include <cstdint>
#include <string>
#include <vector>

namespace avoeq {

static const char* const ENGINE_VERSION = "1.0.0-dev1";

// ------------------------------------------------------------------ original data
struct GnssEpoch {
  // provenance
  uint32_t block_seq = 0;       // RAW block that carried it
  uint64_t chest_us = 0;        // chest monotonic clock at reception (NOT acquisition time)
  // receiver data (UBX NAV-PVT, unchanged)
  uint32_t itow_ms = 0;         // GPS time of week of the measurement
  uint16_t year = 0; uint8_t month = 0, day = 0, hour = 0, minute = 0, second = 0;
  int32_t nano = 0;
  uint8_t valid = 0;            // b0 date, b1 time, b2 fully resolved
  uint8_t fix_type = 0;         // 0 none 1 DR 2 2D 3 3D 4 GNSS+DR 5 time
  uint8_t flags = 0;            // b0 gnssFixOK, b1 diffSoln, b6..7 carrSoln (1 float, 2 fixed)
  uint16_t flags3 = 0;          // b1..4 lastCorrectionAge code
  uint8_t num_sv = 0;
  double lat_deg = 0, lon_deg = 0;
  double height_m = 0, hmsl_m = 0;
  double hacc_m = 0, vacc_m = 0;
  double veln_ms = 0, vele_ms = 0, veld_ms = 0;
  double gspeed_ms = 0, sacc_ms = 0;
  double head_mot_deg = 0, head_acc_deg = 0;
  double pdop = 0;
  uint8_t nav_rate_hz = 0;

  bool fix_ok() const { return flags & 0x01; }
  uint8_t carr_soln() const { return (flags >> 6) & 0x03; }
  bool diff() const { return flags & 0x02; }
};

enum class RtkState : uint8_t { NONE = 0, GNSS = 1, DGNSS = 2, FLOAT = 3, FIXED = 4 };
RtkState rtk_state(const GnssEpoch& e);
const char* rtk_name(RtkState s);

struct ImuSample {
  uint8_t imu_id = 0;           // 0 central, 1 left, 2 right (as sent by the girth)
  uint32_t batch_seq = 0;       // girth packet sequence (from the batch header)
  uint16_t index = 0;           // position inside the batch
  int64_t girth_us = 0;         // girth clock: t0 + index * period (acquisition time on the girth)
  uint64_t chest_us = 0;        // chest reception time of the batch
  int16_t ax = 0, ay = 0, az = 0, gx = 0, gy = 0, gz = 0, mx = 0, my = 0, mz = 0;   // raw LSB
  uint8_t sync_state = 0;       // from the batch header: 0 none, 1 coarse, 2 PPS
  int32_t girth_to_back_us = 0; // offset estimated by the back (if any)
};

struct MarkerEvent { uint64_t chest_us = 0; std::string text; };

struct Session {
  std::string session_id, horse, rider, chest_fw, back_fw;
  uint16_t imu_rate_hz_cfg = 0;
  uint8_t gnss_rate_hz_cfg = 0;
  std::vector<GnssEpoch> gnss;
  std::vector<ImuSample> imu;
  std::vector<MarkerEvent> markers;
  // ingestion bookkeeping
  uint32_t records = 0, bad_records = 0, unknown_frames = 0, segments = 0;
  bool clean_close = false, tail_garbage = false;
};

// ------------------------------------------------------------------ derived results
enum class Quality : uint8_t { GOOD = 0, USABLE = 1, POOR = 2, UNUSABLE = 3, UNKNOWN = 4 };
const char* quality_name(Quality q);

struct Metric {
  std::string name, unit, algorithm, version;
  double value = 0;
  double uncertainty = -1;      // < 0: not estimated
  Quality quality = Quality::UNKNOWN;
  std::vector<std::string> warnings;
  uint32_t samples_used = 0, samples_excluded = 0;
};

struct TimeSeries {             // derived series on the GNSS time base (seconds from session start)
  std::string name, unit, algorithm, version;
  std::vector<double> t, v;
  std::vector<uint8_t> q;       // Quality per point
};

}  // namespace avoeq
