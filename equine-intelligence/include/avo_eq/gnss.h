// GNSS engine: speed, robust acceleration, trajectory geometry and RTK diagnostics.
// The GNSS antenna is on the RIDER: these are rider-trunk kinematics, which follow the horse closely for
// speed and path but NOT for vertical oscillation or short accelerations.
#pragma once
#include <vector>
#include "avo_eq/types.h"
#include "avo_eq/validation.h"

namespace avoeq {

struct GnssConfig {
  double deriv_half_window_s = 0.5;   // local linear fit of speed over ±0.5 s
  double min_speed_heading_ms = 2.0;  // below this, heading / curvature are not computed
  double straight_radius_m = 500.0;   // radius above this = straight line
  double curve_radius_m = 30.0;       // "in a curve" when radius below this
  double accel_good_sigma = 0.3;      // m/s² uncertainty limit for GOOD
  double accel_usable_sigma = 0.8;
  double split_m = 200.0;             // distance splits
};

struct RtkStats {
  double total_s = 0, fixed_s = 0, float_s = 0, dgnss_s = 0, gnss_s = 0, none_s = 0;
  double time_to_first_fix_s = -1;    // -1: never fixed
  uint32_t fix_losses = 0;            // FIXED -> anything else after the first fix
  double longest_outage_s = 0, mean_outage_s = 0;
  double corr_age_max_s = -1;         // from NAV-PVT flags3 (upper bound of the code), -1 unknown
  double hacc_median_fixed_m = -1;    // receiver ESTIMATE (precision), not proven accuracy
};

struct GnssResult {
  std::vector<double> t;              // s from first epoch (GNSS time)
  std::vector<double> speed;          // m/s (receiver gSpeed), NaN where unusable
  std::vector<double> accel;          // m/s² longitudinal (slope of speed), NaN where not computable
  std::vector<double> accel_sigma;    // m/s² 1-sigma propagated from sAcc
  std::vector<double> heading_rate;   // deg/s (from the velocity vector), NaN at low speed
  std::vector<double> heading_rate_sigma;  // deg/s 1-sigma (propagated from the slopes of vN, vE)
  std::vector<double> radius;         // m, NaN at low speed / straight
  std::vector<double> curvature;      // 1/m signed (+ right turn), NaN at low speed
  std::vector<double> curvature_sigma;// 1/m 1-sigma (propagates speed and turn-rate uncertainty)
  std::vector<double> lat_accel;      // m/s² ESTIMATED lateral acceleration of the trajectory = v·ω (+ right)
  std::vector<double> lat_accel_sigma;// m/s² 1-sigma
  std::vector<double> x_e, y_n;       // local east / north (m) from the first usable epoch (NaN when unusable)
  std::vector<double> lat, lon;       // receiver position, deg (copied, NaN when unusable)
  std::vector<uint8_t> usable;        // 1 = epoch passed the hard validation checks
  std::vector<double> dist;           // cumulative m (haversine between usable epochs)
  std::vector<uint8_t> quality;       // Quality per epoch
  std::vector<Metric> metrics;
  RtkStats rtk;
  struct Split { double from_m, to_m, t0, t1, mean_speed; };
  std::vector<Split> splits;
  std::vector<double> speed_hist_edges, speed_hist_s;   // time spent per speed band
};

GnssResult analyse_gnss(const Session& s, const ValidationReport& v, const GnssConfig& c = GnssConfig());

// Local linear regression slope of y(t) around t[i] using points within ±h with valid[] true.
// Returns false when fewer than 3 points. sigma = slope 1-sigma from per-point sigmas.
bool local_slope(const std::vector<double>& t, const std::vector<double>& y, const std::vector<double>& sy,
                 const std::vector<bool>& valid, size_t i, double h, double* slope, double* sigma);

// Upper bound (s) of the correction age code in NAV-PVT flags3 (u-blox interface description). -1 unknown.
double corr_age_code_s(uint8_t code);

}  // namespace avoeq
