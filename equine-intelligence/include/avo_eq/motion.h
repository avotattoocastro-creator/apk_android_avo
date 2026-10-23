// Motion engine: IMU series, cadence, regularity, exploratory signal symmetry and gait classification.
// IMU sensor model and range are NOT known yet: every amplitude is in raw LSB ("sin calibrar"); the algorithms
// rely on scale-free properties (periodicity, correlation, ratios) wherever possible.
#pragma once
#include <string>
#include <vector>
#include "avo_eq/gnss.h"
#include "avo_eq/sync.h"
#include "avo_eq/types.h"
#include "avo_eq/validation.h"

namespace avoeq {

struct ImuSeries {               // one sensor, uniformly sampled pieces without gaps
  uint8_t imu_id = 0;
  double fs = 0;                 // measured rate (Hz)
  struct Piece { double t0 = 0; std::vector<double> ax, ay, az, gx, gy, gz, amag; };
  std::vector<Piece> pieces;     // t0 in girth seconds
  uint32_t saturated = 0, missing = 0;
};
std::vector<ImuSeries> build_imu_series(const Session& s, const ValidationReport& v);

struct CadenceConfig {
  double window_s = 6, hop_s = 2;
  double f_min = 0.6, f_max = 3.5;       // Hz: stride frequencies of walk..gallop, plus beat harmonics
  double band_lo = 0.4, band_hi = 10.0;  // band-pass before analysis
  double min_strength = 0.35;
};

struct CadenceWindow {
  double t_mid = 0;              // seconds (source clock of the series)
  double freq_hz = 0, cpm = 0, period_s = 0, strength = 0;
  bool subharmonic = false;
  // regularity inside the window
  double interval_cv = -1;       // CV of peak-to-peak intervals
  double amplitude_cv = -1;      // CV of peak heights
  double cycle_corr = -1;        // mean correlation of each cycle with the window template
  double half_cycle_ratio = -1;  // r(T/2)/r(T): 1 = both halves alike (signal symmetry), lower = different
  double rms = 0;                // band-passed |a| RMS in LSB (uncalibrated)
};

struct CadenceResult {
  uint8_t imu_id = 0;
  std::vector<CadenceWindow> windows;
  std::vector<Metric> metrics;
};
CadenceResult analyse_cadence(const ImuSeries& s, const CadenceConfig& c = CadenceConfig());

// ---- gait
enum class Gait : uint8_t { STOPPED = 0, WALK = 1, TROT = 2, CANTER_GALLOP = 3, TRANSITION = 4, UNKNOWN = 5 };
const char* gait_name(Gait g);

struct GaitConfig {
  // initial, NOT universal thresholds (GNSS speed of the rider, m/s); to be tuned per horse with labelled data
  double stop_max = 0.4, walk_max = 2.2, trot_max = 4.6;
  // stride frequency bands from the IMU (Hz), overlapping on purpose
  double walk_f_max = 1.2, trot_f_min = 1.1, trot_f_max = 1.8, canter_f_min = 1.5;
  int confirm_windows = 2;       // hysteresis: windows needed to accept a change
  double min_segment_s = 4.0;    // shorter segments become TRANSITION
  double window_s = 2.0;         // classification step when only GNSS is available
};

struct GaitSegment { Gait gait = Gait::UNKNOWN; double t0 = 0, t1 = 0; Quality quality = Quality::UNKNOWN; std::string basis; };
struct GaitResult {
  std::vector<GaitSegment> segments;
  std::string algorithm = "reglas deterministas velocidad GNSS + frecuencia IMU con histéresis";
  std::string version = "1.0.0";
  std::vector<Metric> metrics;   // time and mean speed per gait
};
// cadence may be null (no IMU). Times are GNSS seconds (cadence windows mapped through imu_to_gnss).
GaitResult classify_gait(const GnssResult& g, const CadenceResult* cad, const ClockMap* imu_to_gnss, const GaitConfig& c = GaitConfig());

}  // namespace avoeq
