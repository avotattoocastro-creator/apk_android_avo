// Generates the test vectors of AVO.Windows.SelfTest/watch_vectors.json from the REAL chest firmware sources
// (lib/avo_core/src of the 3.7.x chest tree: avo_config.cpp, avo_geo.cpp, avo_ble_proto.cpp, avo_ble_auth.cpp, avo_crc.cpp,
// avo_sha256.cpp) and the crosses() test of avo_session.cpp. Build (from a prepared chest tree, see README.md):
//   g++ -std=c++17 -I <tree>/lib/avo_core/src gen_watch_vectors.cpp <tree>/lib/avo_core/src/{avo_config,avo_geo,avo_ble_proto,
//       avo_ble_auth,avo_crc,avo_sha256}.cpp -o gen && ./gen > watch_vectors.json
#include <cstdio>
#include <cstring>
#include <string>
#include "avo_config.h"
#include "avo_geo.h"
#include "avo_ble_proto.h"
#include "avo_ble_auth.h"
using namespace avo;

// copied verbatim from avo_session.cpp (anonymous namespace there)
static bool crosses(double ax, double ay, double bx, double by, double px, double py, double qx, double qy) {
  double sp = (bx - ax) * (py - ay) - (by - ay) * (px - ax);
  double sq = (bx - ax) * (qy - ay) - (by - ay) * (qx - ax);
  bool p_pos = sp >= 0, q_pos = sq >= 0;
  if (p_pos == q_pos) return false;
  double sa = (qx - px) * (ay - py) - (qy - py) * (ax - px);
  double sb = (qx - px) * (by - py) - (qy - py) * (bx - px);
  return (sa >= 0) != (sb >= 0) || sa == 0 || sb == 0;
}

static std::string hex(const uint8_t* b, size_t n) {
  std::string s; char t[3];
  for (size_t i = 0; i < n; i++) { snprintf(t, 3, "%02x", b[i]); s += t; }
  return s;
}

static FenceDef poly(const char* name, std::initializer_list<std::pair<int32_t, int32_t>> v) {
  FenceDef f; f.type = FenceType::POLYGON; strncpy(f.name, name, 15);
  for (auto& p : v) { f.lat_e7[f.n] = p.first; f.lon_e7[f.n] = p.second; f.n++; }
  return f;
}

int main() {
  printf("{\n");
  // 1. configuration with two fences and two lines (as the watch would answer GET_CONFIG)
  Config c; config_defaults(&c);
  strcpy(c.horse_name, "HORSE_001"); c.horse_id = 1; strcpy(c.rider_name, "RIDER_007"); c.rider_id = 7;
  c.fences[0].type = FenceType::CIRCLE; strcpy(c.fences[0].name, "Regaton");
  c.fences[0].center_lat_e7 = 434247000; c.fences[0].center_lon_e7 = -34519000; c.fences[0].radius_cm = 15000;
  c.fences[2] = poly("Pista", {{434250000, -34530000}, {434260000, -34530000}, {434260000, -34510000}, {434250000, -34510000}});
  c.fences[2].id = 2;
  c.fence_count = 3; c.active_mask = 0x05; c.auto_enabled = 1;
  c.lines[0] = {1, 434240000, -34525000, 434240500, -34520000};
  c.lines[2] = {1, 434255000, -34525000, 434255000, -34515000};
  uint8_t buf[4096];
  size_t n = config_serialize(c, buf, sizeof(buf));
  printf("  \"config\": \"%s\",\n", hex(buf, n).c_str());
  Config d; ConfigLoad lr = config_deserialize(buf, n, &d);
  printf("  \"config_roundtrip_ok\": %s,\n", lr == ConfigLoad::OK ? "true" : "false");
  // 2. fence body as SET_FENCE sends it
  n = fence_serialize(c.fences[2], buf, sizeof(buf));
  printf("  \"fence_polygon\": \"%s\",\n", hex(buf, n).c_str());
  // 3. validate_fence() verdicts
  FenceDef bow = poly("Lazo", {{434250000, -34530000}, {434260000, -34510000}, {434260000, -34530000}, {434250000, -34510000}});
  FenceDef tiny = poly("Mini", {{434250000, -34530000}, {434250200, -34530000}, {434250200, -34529800}});
  FenceDef smallc; smallc.type = FenceType::CIRCLE; smallc.center_lat_e7 = 434247000; smallc.center_lon_e7 = -34519000; smallc.radius_cm = 400;
  printf("  \"validate\": {\"ok_polygon\": %d, \"bowtie\": %d, \"tiny\": %d, \"small_circle\": %d},\n",
         (int)validate_fence(c.fences[2]), (int)validate_fence(bow), (int)validate_fence(tiny), (int)validate_fence(smallc));
  // 4. one BLE fragment (SET_ACTIVE_FENCES, msg id 0x1234, ACK_REQ)
  uint8_t pl[2] = {0x05, 0x01};
  n = ble_frag_build(BleMsg::SET_ACTIVE_FENCES, 0x1234, 0, 1, 0x01, 0, pl, 2, buf, sizeof(buf));
  printf("  \"frag_set_active\": \"%s\",\n", hex(buf, n).c_str());
  // 5. authorization proofs
  uint8_t key[32], pn[16], wn[16], out[32];
  for (int i = 0; i < 32; i++) key[i] = (uint8_t)i;
  for (int i = 0; i < 16; i++) { pn[i] = (uint8_t)(0xA0 + i); wn[i] = (uint8_t)(0x50 + i); }
  auth_watch_proof(key, pn, wn, "a0b1c2d3e4f5", out);
  printf("  \"watch_proof\": \"%s\",\n", hex(out, 32).c_str());
  auth_phone_proof(key, wn, pn, "a0b1c2d3e4f5", out);
  printf("  \"phone_proof\": \"%s\",\n", hex(out, 32).c_str());
  // 6. crosses(): A(0,0) B(10,0); left→right, right→left, parallel, beyond the end
  printf("  \"crosses\": [%d, %d, %d, %d]\n", crosses(0, 0, 10, 0, 5, 3, 5, -3), crosses(0, 0, 10, 0, 5, -3, 5, 3),
         crosses(0, 0, 10, 0, 1, 1, 9, 1), crosses(0, 0, 10, 0, 15, 3, 15, -3));
  printf("}\n");
  return 0;
}
