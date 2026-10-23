// Motion engine: IMU series, cadence (with uncertainty and validity status), independent regularity metrics,
// spectral features and gait classification (GAIT_CLASSIFIER_V1 reference + GAIT_CLASSIFIER_V2).
// IMU sensor model and range are NOT known yet: every amplitude is in raw LSB ("sin calibrar"); the algorithms
// rely on scale-free properties (periodicity, correlation, ratios) wherever possible.
#pragma once
#include <limits>
#include <memory>
#include <string>
#include <vector>
#include "avo_eq/gnss.h"
#include "avo_eq/sync.h"
#include "avo_eq/types.h"
#include "avo_eq/validation.h"

namespace avoeq {

static const char* const CADENCE_VERSION = "1.1.0";
static const char* const GAIT_V1_ID = "GAIT_CLASSIFIER_V1";
static const char* const GAIT_V2_ID = "GAIT_CLASSIFIER_V2";

struct ImuSeries {               // one sensor, uniformly sampled pieces without gaps
  uint8_t imu_id = 0;
  double fs = 0;                 // measured rate (Hz)
  // float storage: raw values are int16, a float holds them exactly and halves the memory of long sessions
  struct Piece { double t0 = 0; std::vector<float> ax, ay, az, gx, gy, gz, amag; };
  std::vector<Piece> pieces;     // t0 in girth seconds
  uint32_t saturated = 0, missing = 0;
  uint64_t samples = 0;
};
std::vector<ImuSeries> build_imu_series(const Session& s, const ValidationReport& v);

struct CadenceConfig {
  double window_s = 6, hop_s = 2;
  double f_min = 0.6, f_max = 3.5;       // Hz: stride frequencies of walk..gallop, plus beat harmonics
  double band_lo = 0.4, band_hi = 10.0;  // band-pass before analysis
  double min_strength = 0.35;
  double max_rel_uncertainty = 0.08;     // σf/f above this: the cadence is not reported (status INCIERTA)
  double max_disagreement = 0.10;        // |f_autocorr - f_intervals| / f above this: AMBIGUA
  // controlled interpolation (derived copy only, RAW untouched): gaps up to max_bridge_s are filled linearly
  // and a window is analysed only when at most max_interp_fraction of its samples are interpolated
  double max_bridge_s = 0.25;
  double max_interp_fraction = 0.10;
};

enum class CadenceStatus : uint8_t { VALID = 0, WEAK_PERIODICITY = 1, AMBIGUOUS = 2, UNCERTAIN = 3, INSUFFICIENT_DATA = 4 };
const char* cadence_status_name(CadenceStatus s);

struct CadenceWindow {
  double t_mid = 0;              // seconds (source clock of the series)
  CadenceStatus status = CadenceStatus::INSUFFICIENT_DATA;
  double freq_hz = 0, cpm = 0, period_s = 0, strength = 0;   // freq_hz > 0 ONLY when status == VALID
  double uncertainty_hz = -1;    // 1-sigma of freq (intervals statistics + lag resolution), -1 = not estimated
  double candidate_hz = 0;       // what the autocorrelation proposed, kept for traceability even when rejected
  double interval_freq_hz = 0;   // independent estimate: 1 / mean peak-to-peak interval
  bool subharmonic = false;
  double subharmonic_snr = -1;   // power at f0/2 over the local noise floor: > 5 means the true cycle may be 2/f0
  // ---- regularity: independent metrics, deliberately NOT combined into a score
  double interval_cv = -1;       // temporal regularity: CV of cycle durations
  double amplitude_cv = -1;      // amplitude regularity: CV of cycle peak heights
  double cycle_corr = -1;        // cycle similarity: mean correlation of each cycle with the window template
  double spectral_stability = -1;// spectral stability: correlation of the spectra of both window halves
  double half_cycle_ratio = -1;  // r(T/2)/r(T): 1 = both halves alike (signal symmetry), lower = different
  // ---- spectral features
  double dominant_hz = 0;        // strongest spectral peak in the band: NOT assumed to be the cadence
  int dominant_harmonic = 0;     // k when dominant ≈ k·f0 (k ≥ 2: a harmonic dominates the spectrum)
  double harmonic_ratio[4] = {-1, -1, -1, -1};   // P(k·f0)/P(f0), k = 1..4 (index 0 is 1 by definition)
  double harmonic_energy = -1;   // fraction of band power at f0 and its harmonics
  double band_energy[4] = {0, 0, 0, 0};          // fractions in 0.4-1.5, 1.5-3, 3-6, 6-10 Hz
  double axis_energy[3] = {-1, -1, -1};          // fractions of band power in ax, ay, az (orientation unknown)
  double rms = 0;                // band-passed |a| RMS in LSB (uncalibrated)
  double p2p = 0;                // median peak-to-peak per cycle, LSB (uncalibrated)
  uint32_t saturated = 0;        // saturated samples inside the window
  double interpolated_fraction = 0;  // samples filled by the controlled interpolation
};

struct CadenceResult {
  uint8_t imu_id = 0;
  double fs = 0;
  std::vector<CadenceWindow> windows;
  std::vector<Metric> metrics;
};
CadenceResult analyse_cadence(const ImuSeries& s, const CadenceConfig& c = CadenceConfig());

// ---- gait
enum class Gait : uint8_t { STOPPED = 0, WALK = 1, TROT = 2, CANTER_GALLOP = 3, TRANSITION = 4, UNKNOWN = 5, INSUFFICIENT_DATA = 6 };
const char* gait_name(Gait g);        // Spanish display name (PARADO, PASO, …, DATOS_INSUFICIENTES)
const char* gait_code(Gait g);        // stable English code (STOPPED, WALK, …, INSUFFICIENT_DATA)

struct GaitConfig {
  // initial, NOT universal thresholds (GNSS speed of the rider, m/s); to be tuned per horse with labelled data
  double stop_max = 0.4, walk_max = 2.2, trot_max = 4.6;
  // stride frequency bands from the IMU (Hz), overlapping on purpose
  double walk_f_max = 1.2, trot_f_min = 1.1, trot_f_max = 1.8, canter_f_min = 1.5;
  int confirm_windows = 2;       // hysteresis: windows needed to accept a change
  double min_segment_s = 4.0;    // shorter segments become TRANSITION
  double window_s = 2.0;         // classification step when only GNSS is available
};

struct GaitSegment { Gait gait = Gait::UNKNOWN; double t0 = 0, t1 = 0; Quality quality = Quality::UNKNOWN; std::string basis; double confidence = -1; };
struct GaitResult {
  std::string classifier = GAIT_V1_ID;
  std::vector<GaitSegment> segments;
  std::string algorithm = "reglas deterministas velocidad GNSS + frecuencia IMU con histéresis";
  std::string version = "1.0.0";
  std::vector<Metric> metrics;   // time and mean speed per gait
};
// GAIT_CLASSIFIER_V1 (reference, unchanged rules). cadence may be null (no IMU). Times are GNSS seconds.
GaitResult classify_gait(const GnssResult& g, const CadenceResult* cad, const ClockMap* imu_to_gnss, const GaitConfig& c = GaitConfig());

// ---- GAIT_CLASSIFIER_V2: configurable feature scoring + optional trained model
struct GaitFeatures {            // one decision point (GNSS time)
  double t = 0;
  double speed = NAN_D(), speed_sigma = NAN_D();
  double f0 = NAN_D(), f0_sigma = NAN_D();       // only VALID cadence
  double strength = NAN_D(), h2h1 = NAN_D(), half_cycle_ratio = NAN_D(), interval_cv = NAN_D(), cycle_corr = NAN_D(), rms = NAN_D();
  static double NAN_D() { return std::numeric_limits<double>::quiet_NaN(); }
};

struct Trapezoid { double a = 0, b = 0, c = 0, d = 0; double at(double x) const; };   // membership 0..1

struct GaitV2Config {
  // memberships per class (STOPPED, WALK, TROT, CANTER_GALLOP): speed m/s, stride frequency Hz, P(2f0)/P(f0)
  Trapezoid speed[4] = {{-1, -1, 0.3, 0.6}, {0.3, 0.6, 1.9, 2.5}, {1.9, 2.5, 4.4, 5.2}, {4.0, 4.8, 20, 25}};
  Trapezoid freq[4] = {{-1, -1, -1, -1}, {0.55, 0.7, 1.05, 1.25}, {1.05, 1.2, 1.75, 1.95}, {1.35, 1.6, 2.6, 3.0}};
  // walk and trot: two vertical trunk oscillations per stride (h2 strong); canter/gallop: one (h1 strong).
  // Hypothesis for girth-mounted sensors, to be confirmed with labelled data.
  Trapezoid harm[4] = {{-1, -1, -1, -1}, {0.6, 1.0, 50, 60}, {0.6, 1.0, 50, 60}, {-1, -1, 0.6, 1.2}};
  double w_speed = 1.0, w_freq = 0.7, w_harm = 0.4;
  double floor = 0.05;           // membership floor (one disagreeing feature penalises, does not veto)
  double min_score = 0.5, min_margin = 0.15;
  int confirm_points = 2;
  double min_segment_s = 4.0;
  double step_s = 2.0;           // decision step when only GNSS is available
  std::string model_path;        // optional trained model (ml/avo_ml.py JSON); empty = rules
};

// Trained-model interface: scores for the four gait classes from one feature vector.
struct GaitModel {
  virtual ~GaitModel() {}
  virtual std::string id() const = 0;
  virtual bool scores(const GaitFeatures& f, double out[4]) const = 0;   // false = cannot score these features
};
// Nearest-centroid model written by ml/avo_ml.py (`train`). Returns null and sets *err when invalid.
std::unique_ptr<GaitModel> load_centroid_model(const std::string& json_text, std::string* err);

std::vector<GaitFeatures> gait_features(const GnssResult& g, const CadenceResult* cad, const ClockMap* imu_to_gnss, double step_s);
GaitResult classify_gait_v2(const GnssResult& g, const CadenceResult* cad, const ClockMap* imu_to_gnss,
                            const GaitV2Config& c = GaitV2Config(), const GaitModel* model = nullptr);

// Time-based comparison of a classification against reference labels (same data for V1 and V2).
struct GaitEvaluation {
  double evaluated_s = 0, agree_s = 0;
  double confusion[7][7] = {};   // [truth][predicted] seconds
  double accuracy() const { return evaluated_s > 0 ? agree_s / evaluated_s : 0; }
  double recall(Gait g) const;
  double precision(Gait g) const;
};
// Times inside truth TRANSITION segments, or within `guard_s` of a truth boundary, are not evaluated.
GaitEvaluation evaluate_gait(const std::vector<GaitSegment>& predicted, const std::vector<GaitSegment>& truth, double guard_s = 1.0, double step_s = 0.1);

}  // namespace avoeq
