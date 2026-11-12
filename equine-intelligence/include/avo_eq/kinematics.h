// Advanced acceleration engine and curve analysis engine (GNSS trajectory of the RIDER's back antenna).
// Everything here is TRAJECTORY kinematics ("TRAYECTORIA_GNSS"): it is not the acceleration measured by the
// girth IMUs, which are uncalibrated and sit on another body; the two are never mixed or presented as equal.
#pragma once
#include <string>
#include <vector>
#include "avo_eq/gnss.h"
#include "avo_eq/types.h"

namespace avoeq {

static const char* const KINEMATICS_VERSION = "1.1.0";
static const char* const CURVES_VERSION = "1.1.0";

struct AccelConfig {
  double sustained_min = 0.4;      // m/s²: sustained acceleration / deceleration threshold
  double sustained_exit = 0.2;     // m/s²: hysteresis, leaves the event below this
  double sustained_min_s = 1.5;    // s minimum duration
  double gap_tolerance_s = 0.4;    // s of missing estimates tolerated inside an event
  double peak_min = 1.0;           // m/s²: longitudinal peak
  double lateral_peak_min = 2.0;   // m/s²: lateral peak
  double peak_k_sigma = 3.0;       // |a| must exceed k·sigma to be a peak (noise guard)
  double peak_separation_s = 1.0;
  double max_sigma = 0.8;          // m/s²: estimates with larger uncertainty are not used
  double physical_max = 15.0;      // m/s²: larger values are treated as artefacts, never as events
};

struct AccelEvent {
  std::string type;                // ACELERACION_SOSTENIDA | DESACELERACION_SOSTENIDA | PICO_ACELERACION | PICO_DESACELERACION | PICO_LATERAL
  double t0 = 0, t1 = 0, t_peak = 0;
  double peak = 0, peak_sigma = 0, mean = 0;   // m/s²
  double v0 = 0, v1 = 0, dv = 0;               // m/s (speed change across the event)
  Quality quality = Quality::UNKNOWN;
  std::string source = "TRAYECTORIA_GNSS";
};

struct KinematicsResult {
  std::vector<AccelEvent> events;
  std::vector<Metric> metrics;
  uint32_t rejected_physical = 0;  // estimates above physical_max (artefacts)
};

KinematicsResult analyse_kinematics(const GnssResult& g, const AccelConfig& c = AccelConfig());

// ------------------------------------------------------------------ curves
struct CurveConfig {
  double min_speed = 2.0;          // m/s: below this the heading is too noisy for a radius
  double enter_radius = 40.0;      // m: enters a curve below this radius
  double exit_radius = 60.0;       // m: leaves it above this (hysteresis)
  double min_duration_s = 2.0;
  double min_heading_deg = 30.0;   // total heading change of a valid curve
  double kappa_k_sigma = 2.0;      // |κ| must exceed k·σκ (otherwise the turn is not significant)
  double gap_tolerance_s = 0.6;
  double min_radius = 3.0;         // m: smaller radii at these speeds are artefacts
};

struct Curve {
  int id = 0;
  std::string direction;           // DERECHA | IZQUIERDA
  double t0 = 0, t1 = 0;
  size_t i0 = 0, i1 = 0;           // GNSS epoch indices (traceability)
  double heading_change_deg = 0;   // signed (+ right)
  double radius_m = 0, radius_sigma_m = 0;     // kinematic radius v/|ω|: robust median and dispersion
  double radius_geom_m = -1;       // geometric radius from a circle fit of the positions (-1 when not computable)
  double center_e = 0, center_n = 0, center_lat = 0, center_lon = 0;   // circle centre (fit) or arc midpoint
  bool center_from_fit = false;
  double v_entry = 0, v_exit = 0, v_mean = 0, v_min = 0;               // m/s
  double lat_acc_mean = 0, lat_acc_max = 0, lat_acc_sigma = 0;         // m/s² (estimated, trajectory)
  double distance_m = 0;
  // filled by the fusion with the girth (NaN when no IMU / not mappable)
  double cadence_before_hz = -1, cadence_during_hz = -1, cadence_after_hz = -1;
  double cycle_corr_before = -1, cycle_corr_during = -1;
  Quality quality = Quality::UNKNOWN;
  std::vector<std::string> warnings;
};

struct CurveResult {
  std::vector<Curve> curves;
  uint32_t rejected_short = 0, rejected_small_turn = 0, rejected_quality = 0;
  std::vector<Metric> metrics;
};

CurveResult analyse_curves(const GnssResult& g, const CurveConfig& c = CurveConfig());

// Least-squares circle fit (Kåsa). Returns false when ill-conditioned.
bool fit_circle(const std::vector<double>& x, const std::vector<double>& y, double* cx, double* cy, double* r, double* rms);

}  // namespace avoeq
