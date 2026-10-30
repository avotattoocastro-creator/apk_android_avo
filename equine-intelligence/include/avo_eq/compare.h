// Session Comparison Engine: whole session, selected sections (time, distance, position, gait, event),
// same-route comparison by spatial alignment (projection on a reference route + cumulative distance), and a
// pattern comparison by Dynamic Time Warping (explicitly NOT spatial). Every result says whether the two
// sections are really comparable and why; differences are given with their context (speed, gait, quality).
#pragma once
#include <string>
#include <vector>
#include "avo_eq/engine.h"

namespace avoeq {

static const char* const COMPARE_VERSION = "1.1.0";

struct Selection {
  enum Kind { ALL, TIME, DISTANCE, GAIT, EVENT, POSITION } kind = ALL;
  double a = 0, b = 0;               // TIME: seconds; DISTANCE: metres (cumulative)
  Gait gait = Gait::UNKNOWN;         // GAIT
  std::string event_id;              // EVENT
  double lat = 0, lon = 0, radius_m = 0;   // POSITION: circle
};
const char* selection_name(Selection::Kind k);

struct SectionStats {
  double duration_s = 0, distance_m = 0, speed_mean = NAN, speed_max = NAN, cadence_hz = NAN, cycle_corr = NAN, interval_cv = NAN;
  double fix_fraction = 0;
  double gait_time[7] = {0, 0, 0, 0, 0, 0, 0};
  uint32_t events = 0, epochs = 0;
  Gait dominant_gait = Gait::UNKNOWN;
  std::vector<std::pair<double, double>> intervals;   // GNSS time intervals of the section
};

struct MetricDiff {
  std::string name, unit;
  double a = NAN, b = NAN, diff = NAN;
  bool comparable = false;
  std::string context;               // why (not) comparable / what conditions differ
};

struct RouteAlignment {
  bool attempted = false, comparable = false;
  double median_xtrack_m = NAN, p90_xtrack_m = NAN, coverage = 0, monotonic = 0, tolerance_m = 0;
  std::vector<double> s, speed_a, speed_b, time_diff_s;   // profile on the reference route (s = metres along A)
  double mean_speed_diff = NAN, total_time_diff_s = NAN;
  std::string reason;
};

struct PatternComparison {
  bool computed = false;
  double dtw_distance = NAN;         // mean |Δv| along the warping path, m/s
  double warp_ratio = NAN;           // path length / reference length (1 = no warping)
  std::string note = "comparación de forma del perfil de velocidad (DTW); no es una comparación espacial";
};

struct CurveMatch { int curve_a = 0, curve_b = 0; double center_dist_m = 0, d_radius_m = 0, d_entry_speed = 0, d_lat_acc = 0; };

struct Comparison {
  std::string version = COMPARE_VERSION;
  std::string session_a, session_b;
  Selection sel_a, sel_b;
  SectionStats a, b;
  bool comparable = false;
  std::vector<std::string> reasons;  // conditions that limit the comparison
  std::vector<MetricDiff> diffs;
  RouteAlignment route;
  PatternComparison pattern;
  std::vector<CurveMatch> curves;
};

SectionStats section_stats(const Analysis& an, const Selection& sel);
Comparison compare_sessions(const Analysis& A, const Analysis& B, const Selection& sa, const Selection& sb, bool same_route);
std::string comparison_json(const Comparison& c);

// Projection of point (x,y) on polyline (px,py): returns along-track distance and signed cross-track (+ right).
bool project_on_polyline(const std::vector<double>& px, const std::vector<double>& py, double x, double y, size_t hint, size_t search,
                         double* along, double* cross, size_t* seg);

}  // namespace avoeq
