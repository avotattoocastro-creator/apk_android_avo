#include "avo_geo.h"
#include <math.h>
#include <string.h>

namespace avo {

static const double kEarthR = 6371008.8;  // mean Earth radius (m)
static const double kDeg = M_PI / 180.0;

void LocalFrame::init(int32_t lat_e7, int32_t lon_e7) {
  lat0_deg = lat_e7 * 1e-7;
  lon0_deg = lon_e7 * 1e-7;
  ky = kEarthR * kDeg;
  kx = kEarthR * kDeg * cos(lat0_deg * kDeg);
}

void LocalFrame::to_xy(int32_t lat_e7, int32_t lon_e7, double* x, double* y) const {
  double dlon = lon_e7 * 1e-7 - lon0_deg;
  if (dlon > 180) dlon -= 360;
  if (dlon < -180) dlon += 360;
  *x = dlon * kx;
  *y = (lat_e7 * 1e-7 - lat0_deg) * ky;
}

static bool coord_ok(int32_t lat, int32_t lon) {
  return lat >= -900000000 && lat <= 900000000 && lon >= -1800000000 && lon <= 1800000000 &&
         !(lat == 0 && lon == 0);
}

bool segments_intersect(double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy) {
  auto orient = [](double px, double py, double qx, double qy, double rx, double ry) {
    double v = (qx - px) * (ry - py) - (qy - py) * (rx - px);
    if (fabs(v) < 1e-12) return 0;
    return v > 0 ? 1 : -1;
  };
  auto on_seg = [](double px, double py, double qx, double qy, double rx, double ry) {
    return fmin(px, qx) - 1e-9 <= rx && rx <= fmax(px, qx) + 1e-9 && fmin(py, qy) - 1e-9 <= ry && ry <= fmax(py, qy) + 1e-9;
  };
  int o1 = orient(ax, ay, bx, by, cx, cy), o2 = orient(ax, ay, bx, by, dx, dy);
  int o3 = orient(cx, cy, dx, dy, ax, ay), o4 = orient(cx, cy, dx, dy, bx, by);
  if (o1 != o2 && o3 != o4) return true;
  if (o1 == 0 && on_seg(ax, ay, bx, by, cx, cy)) return true;
  if (o2 == 0 && on_seg(ax, ay, bx, by, dx, dy)) return true;
  if (o3 == 0 && on_seg(cx, cy, dx, dy, ax, ay)) return true;
  if (o4 == 0 && on_seg(cx, cy, dx, dy, bx, by)) return true;
  return false;
}

FenceError validate_fence(const FenceDef& f) {
  if (f.type == FenceType::CIRCLE) {
    if (!coord_ok(f.center_lat_e7, f.center_lon_e7)) return FenceError::BAD_COORD;
    if (f.radius_cm < 500 || f.radius_cm > 500000) return FenceError::BAD_RADIUS;  // 5 m .. 5 km
    return FenceError::OK;
  }
  if (f.type != FenceType::POLYGON) return FenceError::NO_TYPE;
  if (f.n < 3) return FenceError::TOO_FEW_VERTICES;
  if (f.n > AVO_MAX_VERTICES) return FenceError::TOO_MANY_VERTICES;
  for (uint8_t i = 0; i < f.n; i++)
    if (!coord_ok(f.lat_e7[i], f.lon_e7[i])) return FenceError::BAD_COORD;
  LocalFrame fr;
  fr.init(f.lat_e7[0], f.lon_e7[0]);
  double x[AVO_MAX_VERTICES], y[AVO_MAX_VERTICES];
  double area2 = 0;
  for (uint8_t i = 0; i < f.n; i++) {
    fr.to_xy(f.lat_e7[i], f.lon_e7[i], &x[i], &y[i]);
    if (fabs(x[i]) > 10000 || fabs(y[i]) > 10000) return FenceError::TOO_LARGE;
  }
  for (uint8_t i = 0; i < f.n; i++) {
    uint8_t i2 = (uint8_t)((i + 1) % f.n);
    for (uint8_t j = (uint8_t)(i + 1); j < f.n; j++) {
      uint8_t j2 = (uint8_t)((j + 1) % f.n);
      if (j == i2 || j2 == i) continue;  // adjacent edges share a vertex
      if (segments_intersect(x[i], y[i], x[i2], y[i2], x[j], y[j], x[j2], y[j2])) return FenceError::SELF_INTERSECTING;
    }
  }
  for (uint8_t i = 0; i < f.n; i++) {
    uint8_t j = (uint8_t)((i + 1) % f.n);
    area2 += x[i] * y[j] - x[j] * y[i];
  }
  if (fabs(area2) / 2 < 25.0) return FenceError::ZERO_AREA;  // < 25 m²
  return FenceError::OK;
}

const char* fence_error_str(FenceError e) {
  switch (e) {
    case FenceError::OK: return "OK";
    case FenceError::NO_TYPE: return "NO_TYPE";
    case FenceError::BAD_RADIUS: return "BAD_RADIUS";
    case FenceError::TOO_FEW_VERTICES: return "TOO_FEW_VERTICES";
    case FenceError::TOO_MANY_VERTICES: return "TOO_MANY_VERTICES";
    case FenceError::BAD_COORD: return "BAD_COORD";
    case FenceError::ZERO_AREA: return "ZERO_AREA";
    case FenceError::SELF_INTERSECTING: return "SELF_INTERSECTING";
    case FenceError::TOO_LARGE: return "TOO_LARGE";
  }
  return "?";
}

bool CompiledFence::compile(const FenceDef& f) {
  valid = false;
  if (validate_fence(f) != FenceError::OK) return false;
  type = f.type;
  id = f.id;
  if (f.type == FenceType::CIRCLE) {
    frame.init(f.center_lat_e7, f.center_lon_e7);
    r = f.radius_cm / 100.0;
    n = 0;
  } else {
    frame.init(f.lat_e7[0], f.lon_e7[0]);
    n = f.n;
    for (uint8_t i = 0; i < n; i++) frame.to_xy(f.lat_e7[i], f.lon_e7[i], &x[i], &y[i]);
  }
  valid = true;
  return true;
}

static double seg_dist(double px, double py, double ax, double ay, double bx, double by) {
  double vx = bx - ax, vy = by - ay;
  double l2 = vx * vx + vy * vy;
  double t = l2 > 0 ? ((px - ax) * vx + (py - ay) * vy) / l2 : 0;
  if (t < 0) t = 0;
  if (t > 1) t = 1;
  double dx = px - (ax + t * vx), dy = py - (ay + t * vy);
  return sqrt(dx * dx + dy * dy);
}

double CompiledFence::signed_distance(int32_t lat_e7, int32_t lon_e7) const {
  double px, py;
  frame.to_xy(lat_e7, lon_e7, &px, &py);
  if (type == FenceType::CIRCLE) return sqrt(px * px + py * py) - r;
  bool inside = false;
  double dmin = 1e18;
  for (uint8_t i = 0, j = (uint8_t)(n - 1); i < n; j = i++) {
    if (((y[i] > py) != (y[j] > py)) && (px < (x[j] - x[i]) * (py - y[i]) / (y[j] - y[i]) + x[i])) inside = !inside;
    double d = seg_dist(px, py, x[j], y[j], x[i], y[i]);
    if (d < dmin) dmin = d;
  }
  return inside ? -dmin : dmin;
}

int FenceSet::build(const FenceDef* defs, uint8_t count, uint8_t active_mask) {
  n_ = 0;
  for (uint8_t i = 0; i < count && i < AVO_MAX_FENCES; i++) {
    if (!(active_mask & (1u << i))) continue;
    if (f_[n_].compile(defs[i])) { f_[n_].id = i; n_++; }  // id = slot index
  }
  return n_;
}

bool FenceSet::signed_distance(int32_t lat_e7, int32_t lon_e7, double* sd, uint8_t* fence_id) const {
  if (n_ == 0) return false;
  double best = 1e18;
  uint8_t bid = 0;
  for (int i = 0; i < n_; i++) {
    double d = f_[i].signed_distance(lat_e7, lon_e7);
    if (d < best) { best = d; bid = f_[i].id; }
  }
  *sd = best;
  if (fence_id) *fence_id = bid;
  return true;
}

double haversine_m(int32_t lat1_e7, int32_t lon1_e7, int32_t lat2_e7, int32_t lon2_e7) {
  double la1 = lat1_e7 * 1e-7 * kDeg, la2 = lat2_e7 * 1e-7 * kDeg;
  double dla = la2 - la1, dlo = (lon2_e7 - lon1_e7) * 1e-7 * kDeg;
  double a = sin(dla / 2) * sin(dla / 2) + cos(la1) * cos(la2) * sin(dlo / 2) * sin(dlo / 2);
  return 2 * kEarthR * atan2(sqrt(a), sqrt(1 - a));
}

}  // namespace avo
