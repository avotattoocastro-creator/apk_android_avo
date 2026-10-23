// AVO UART PROTOCOL v1 — chest (Waveshare) <-> back (Heltec) link.
// See PROTOCOL_UART.md for the normative description and test vectors.
//
// Frame layout (little-endian):
//   off size field
//   0   1    sync0  = 0xA5
//   1   1    sync1  = 0x5A
//   2   1    ver    = protocol version of the sender (1)
//   3   1    type   (FrameType)
//   4   1    flags  (FrameFlag bits)
//   5   1    src    (NodeId of the sender)
//   6   2    seq    (per-sender counter, wraps at 65536)
//   8   2    len    (payload length, 0..AVO_UART_MAX_PAYLOAD)
//   10  4    t_ms   (sender monotonic time in ms at transmission)
//   14  1    hcrc   CRC-8/SMBUS over bytes 2..13
//   15  len  payload
//   15+len 4 crc    CRC-32/ISO-HDLC over bytes 2..(15+len-1)
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

static const uint8_t AVO_UART_SYNC0 = 0xA5;
static const uint8_t AVO_UART_SYNC1 = 0x5A;
static const uint8_t AVO_UART_VERSION = 1;
static const size_t AVO_UART_HDR = 15;
static const size_t AVO_UART_TRAILER = 4;
static const size_t AVO_UART_MAX_PAYLOAD = 1024;
static const size_t AVO_UART_MAX_FRAME = AVO_UART_HDR + AVO_UART_MAX_PAYLOAD + AVO_UART_TRAILER;

enum class FrameType : uint8_t {
  CAPS = 0x01,          // capability negotiation (both directions)
  HEARTBEAT = 0x02,
  TIME_SYNC = 0x03,     // back: mapping back-clock <-> GNSS time via PPS
  GNSS_SAMPLE = 0x10,   // back: compact decoded NAV-PVT + timestamps
  GNSS_UBX = 0x11,      // back: verbatim UBX frame from the ZED-F9P (RAW first)
  IMU_SAMPLE = 0x20,    // back: batch of girth (cincha) IMU samples, original ids/seq/time
  RTCM_DATA = 0x30,     // chest->back: RTCM3 bytes, unmodified
  EVENT = 0x40,
  STATUS = 0x41,        // back: GNSS/PPS/RTCM/girth/link status
  COMMAND = 0x50,
  ACK = 0x51,
  NACK = 0x52,
  DIAGNOSTIC = 0x60,
};

enum FrameFlag : uint8_t {
  FF_ACK_REQ = 0x01,   // receiver must answer ACK/NACK
  FF_RETX = 0x02,      // retransmission of an earlier seq
  FF_PRIO_HIGH = 0x04, // informative: sender queued it on the high-priority lane
};

enum class NodeId : uint8_t { UNKNOWN = 0, BACK = 1, CHEST = 2, GIRTH = 3, PHONE = 4 };

struct FrameView {
  uint8_t ver;
  FrameType type;
  uint8_t flags;
  uint8_t src;
  uint16_t seq;
  uint16_t len;
  uint32_t t_ms;
  const uint8_t* payload;
  const uint8_t* raw;      // complete frame (sync..crc) — stored verbatim in RAW
  size_t raw_len;
};

// Encode a frame. Returns total length or 0 if it does not fit / is invalid.
size_t uart_encode(FrameType type, uint8_t flags, uint8_t src, uint16_t seq, uint32_t t_ms,
                   const uint8_t* payload, size_t len, uint8_t* out, size_t cap);

struct DecoderStats {
  uint32_t frames_ok = 0;
  uint32_t bytes_in = 0;
  uint32_t resync_bytes = 0;  // bytes discarded while hunting for sync
  uint32_t hdr_crc_err = 0;
  uint32_t len_err = 0;
  uint32_t crc_err = 0;
  uint32_t duplicates = 0;
  uint32_t out_of_order = 0;
  uint32_t seq_lost = 0;      // frames missing according to seq gaps
  uint32_t unknown_version = 0;
};

// Per-sender sequence tracker (duplicate + gap detection with a 64-entry window).
class SeqTracker {
 public:
  enum Result { NEW, DUPLICATE, OLD };
  // Returns classification and adds detected gap size to *lost.
  Result check(uint16_t seq, uint32_t* lost);
  void reset() { have_ = false; window_ = 0; }
 private:
  bool have_ = false;
  uint16_t last_ = 0;     // highest seq accepted
  uint64_t window_ = 0;   // bit i => (last_ - i) seen
};

// Streaming decoder with sync recovery. Not thread-safe: one instance per RX task.
class UartDecoder {
 public:
  typedef void (*FrameCb)(const FrameView& f, void* ctx);
  UartDecoder(FrameCb cb, void* ctx) : cb_(cb), ctx_(ctx) {}
  void feed(const uint8_t* d, size_t n);
  const DecoderStats& stats() const { return st_; }
  void reset_stats() { st_ = DecoderStats(); }
  // Max accepted version (frames with higher header version are still decoded:
  // the header layout is frozen; ver only describes payload schemas).
 private:
  void process();
  FrameCb cb_;
  void* ctx_;
  uint8_t buf_[AVO_UART_MAX_FRAME * 2];
  size_t head_ = 0, tail_ = 0;  // valid bytes are buf_[head_..tail_)
  DecoderStats st_;
  SeqTracker trk_[8];
};

}  // namespace avo
