// Geometry for geofences and virtual lines (local tangent plane, metres).
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

static const uint8_t AVO_MAX_FENCES = 8;
static const uint8_t AVO_MAX_VERTICES = 24;

enum class FenceType : uint8_t { NONE = 0, CIRCLE = 1, POLYGON = 2 };

struct FenceDef {
  uint8_t id = 0;
  FenceType type = FenceType::NONE;
  char name[16] = {0};
  // Circle
  int32_t center_lat_e7 = 0, center_lon_e7 = 0;
  uint32_t radius_cm = 0;
  // Polygon (vertices in order, implicitly closed)
  uint8_t n = 0;
  int32_t lat_e7[AVO_MAX_VERTICES] = {0};
  int32_t lon_e7[AVO_MAX_VERTICES] = {0};
};

enum class FenceError : uint8_t {
  OK = 0, NO_TYPE, BAD_RADIUS, TOO_FEW_VERTICES, TOO_MANY_VERTICES, BAD_COORD, ZERO_AREA,
  SELF_INTERSECTING, TOO_LARGE,
};
FenceError validate_fence(const FenceDef& f);
const char* fence_error_str(FenceError e);

// Local equirectangular projection around a reference point. Adequate for
// fences up to a few km (error < 1 cm per 100 m at mid latitudes).
struct LocalFrame {
  double lat0_deg = 0, lon0_deg = 0, kx = 0, ky = 0;
  void init(int32_t lat_e7, int32_t lon_e7);
  void to_xy(int32_t lat_e7, int32_t lon_e7, double* x, double* y) const;
};

// Pre-computed fence in its own local frame.
struct CompiledFence {
  bool valid = false;
  FenceType type = FenceType::NONE;
  uint8_t id = 0;
  LocalFrame frame;
  double r = 0;                    // circle radius (m)
  uint8_t n = 0;
  double x[AVO_MAX_VERTICES], y[AVO_MAX_VERTICES];
  bool compile(const FenceDef& f);
  // Signed distance (m) to the boundary: negative inside, positive outside.
  double signed_distance(int32_t lat_e7, int32_t lon_e7) const;
};

// Union of the active fences: the position is "inside" if inside any of them.
class FenceSet {
 public:
  // Returns number of valid compiled fences among those enabled in active_mask.
  int build(const FenceDef* defs, uint8_t count, uint8_t active_mask);
  bool empty() const { return n_ == 0; }
  int count() const { return n_; }
  // Minimum signed distance over the union. Returns false when empty.
  bool signed_distance(int32_t lat_e7, int32_t lon_e7, double* sd, uint8_t* fence_id) const;
 private:
  CompiledFence f_[AVO_MAX_FENCES];
  int n_ = 0;
};

// Great-circle distance (haversine), metres.
double haversine_m(int32_t lat1_e7, int32_t lon1_e7, int32_t lat2_e7, int32_t lon2_e7);
// Segment intersection test in a plane (proper or touching).
bool segments_intersect(double ax, double ay, double bx, double by, double cx, double cy, double dx, double dy);

}  // namespace avo
