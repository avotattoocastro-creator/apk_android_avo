// UBX (u-blox) and RTCM3 helpers. The chest never modifies RTCM bytes: the
// RTCM framer only *observes* the stream to produce statistics.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "avo_payloads.h"

namespace avo {

// ---- UBX
static const uint8_t UBX_SYNC1 = 0xB5, UBX_SYNC2 = 0x62;
static const uint8_t UBX_CLS_NAV = 0x01, UBX_ID_NAV_PVT = 0x07;
static const size_t UBX_NAV_PVT_LEN = 92;
void ubx_checksum(const uint8_t* d, size_t n, uint8_t* cka, uint8_t* ckb);
// Validates one complete UBX frame (sync..checksum). On success returns true and
// fills class/id/payload pointer/len.
bool ubx_check_frame(const uint8_t* f, size_t n, uint8_t* cls, uint8_t* id, const uint8_t** pl, uint16_t* plen);
// Builds a UBX frame (used by tests and the back simulator).
size_t ubx_build(uint8_t cls, uint8_t id, const uint8_t* pl, uint16_t plen, uint8_t* out, size_t cap);
// Decodes NAV-PVT payload (92 bytes) into GnssSample (back timing fields untouched).
bool ubx_decode_nav_pvt(const uint8_t* pl, size_t n, GnssSample* s);
// Encodes a GnssSample as a NAV-PVT payload (simulator/tests).
size_t ubx_encode_nav_pvt(const GnssSample& s, uint8_t* pl, size_t cap);

// ---- RTCM3 stream observer
struct RtcmStats {
  uint32_t bytes = 0;
  uint32_t frames_ok = 0;
  uint32_t frames_bad_crc = 0;
  uint32_t garbage_bytes = 0;   // bytes outside any valid frame
  uint16_t last_msg_type = 0;
  uint32_t msm_frames = 0;      // MSM4..MSM7 observation frames
  uint32_t ref_station_frames = 0;  // 1005/1006
};

class RtcmObserver {
 public:
  void feed(const uint8_t* d, size_t n);
  const RtcmStats& stats() const { return st_; }
  void reset() { st_ = RtcmStats(); have_ = 0; }
 private:
  void scan();
  uint8_t buf_[1029 + 64];
  size_t have_ = 0;
  RtcmStats st_;
};
// Builds an RTCM3 frame around payload (tests/simulator).
size_t rtcm_build(const uint8_t* pl, uint16_t plen, uint8_t* out, size_t cap);

}  // namespace avo
