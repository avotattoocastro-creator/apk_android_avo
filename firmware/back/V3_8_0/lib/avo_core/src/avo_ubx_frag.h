// AVO UBX FRAGMENTS v1 (BACK V3.16.0, 23/11/2026) — long UBX frames (RXM-RAWX, RXM-SFRBX) from the ZED-F9P to the
// chest, split so that every AVO frame fits one ESP-NOW packet. Used for PPK (post-processed kinematic): the chest
// stores every frame verbatim in the .avr (RecType::UART_FRAME), the engine joins the pieces and gets the original
// UBX frame back, byte for byte.
//
// AVO frame type GNSS_UBX_FRAG (0x12). Payload (little-endian):
//   off size
//   0   1    version (1)
//   1   1    index of this piece (0 .. count-1)
//   2   1    count of pieces of the UBX frame (1 .. UBX_FRAG_MAX_PIECES)
//   3   1    reserved (0)
//   4   2    message sequence (per back boot, wraps at 65536): all pieces of one UBX frame share it
//   6   2    total length of the complete UBX frame (sync .. checksum)
//   8   n    bytes [index * UBX_FRAG_CHUNK, ...) of the UBX frame (n = UBX_FRAG_CHUNK except in the last piece)
// AVO frame: 15 header + 8 + 192 + 4 CRC = 219 bytes <= 234 (NOW_MAX_BODY).
// A chest that does not know 0x12 stores it like any other frame and ignores it (no change in the chest firmware).
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

static const uint8_t UBX_FRAG_VERSION = 1;
static const size_t UBX_FRAG_HDR = 8;
static const size_t UBX_FRAG_CHUNK = 192;
static const size_t UBX_FRAG_MAX_FRAME = 4096;   // RXM-RAWX with 127 measurements = 4088 bytes
static const size_t UBX_FRAG_MAX_PIECES = (UBX_FRAG_MAX_FRAME + UBX_FRAG_CHUNK - 1) / UBX_FRAG_CHUNK;   // 22

// Number of pieces for a UBX frame of len bytes (0 if empty or too long).
size_t ubx_frag_count(size_t len);
// Builds the payload of piece `index`. Returns its length, or 0 if the arguments are invalid / out does not fit.
size_t ubx_frag_encode(const uint8_t* ubx, size_t len, uint16_t msg_seq, uint8_t index, uint8_t* out, size_t cap);

struct UbxFragPiece {
  uint8_t index = 0, count = 0;
  uint16_t msg_seq = 0, total = 0;
  const uint8_t* data = nullptr;
  size_t n = 0;
};
bool ubx_frag_decode(const uint8_t* pl, size_t len, UbxFragPiece* p);

// Joins pieces in arrival order. A UBX frame is delivered only when every piece arrived and its UBX checksum is
// right; a piece of a new message drops an unfinished one (counted in `incomplete`).
class UbxDefrag {
 public:
  // Returns true when `frame` / `frame_len` hold a complete, verified UBX frame (valid until the next call).
  bool feed(const uint8_t* pl, size_t len, const uint8_t** frame, size_t* frame_len);
  uint32_t complete() const { return complete_; }
  uint32_t incomplete() const { return incomplete_; }   // messages with at least one piece lost
  uint32_t bad() const { return bad_; }                 // undecodable pieces or wrong checksum after joining
  void reset() { active_ = false; done_ = false; }
 private:
  uint8_t buf_[UBX_FRAG_MAX_FRAME];
  bool active_ = false;
  uint16_t seq_ = 0, total_ = 0;
  uint8_t count_ = 0;
  bool done_ = false;
  uint16_t done_seq_ = 0;
  uint32_t got_ = 0;           // bit i = piece i received (count <= 22)
  uint32_t complete_ = 0, incomplete_ = 0, bad_ = 0;
};

}  // namespace avo
