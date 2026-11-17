// AVO ESP-NOW LINK v1 — chest (Waveshare) <-> back (Heltec) radio link.
//
// The link carries the SAME frames as AVO UART PROTOCOL v1 (avo_uart_proto.h):
// GNSS_SAMPLE, STATUS, CAPS, HEARTBEAT, RTCM_DATA, COMMAND, ACK... Only the
// transport changes: instead of a UART byte stream, whole frames are packed
// into ESP-NOW packets (unicast to the paired peer, MAC-level ACK + retries).
//
// ESP-NOW packet (<= 250 bytes, works with ESP-NOW v1 and v2):
//   off size
//   0   2    magic 0xA5 0x4E
//   2   1    link version (1)
//   3   1    kind: 1 PAIR_REQ (chest, broadcast) · 2 PAIR_ACK (back, unicast) · 3 DATA
//   4   4    pair_id   (random, chosen by the chest when pairing; identifies the couple)
//   8   4    boot_id   (random per boot of the sender; a change resets duplicate tracking)
//   12  2    body length
//   14  2    CRC-16/CCITT-FALSE over bytes 0..13 and the body
//   16  ...  body (<= 234 bytes)
// DATA body: one or more complete AVO UART frames back to back.
// PAIR_REQ / PAIR_ACK body: u8 role (2 chest, 1 back) · u32 nonce · char dev_id[16] · char fw[16]
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

namespace avo {

static const uint8_t NOW_MAGIC0 = 0xA5, NOW_MAGIC1 = 0x4E;
static const uint8_t NOW_LINK_VERSION = 1;
static const size_t NOW_HDR = 16;
static const size_t NOW_MAX_PACKET = 250;
static const size_t NOW_MAX_BODY = NOW_MAX_PACKET - NOW_HDR;   // 234
static const uint8_t NOW_CHANNEL_DEFAULT = 1;
// RTCM bytes per RTCM_DATA frame so that one frame fits one packet:
// 15 (frame hdr) + 4 (stream offset) + 200 + 4 (CRC) = 223 <= 234
static const size_t NOW_RTCM_CHUNK = 200;

enum class NowKind : uint8_t { PAIR_REQ = 1, PAIR_ACK = 2, DATA = 3 };
enum class NowRole : uint8_t { BACK = 1, CHEST = 2 };

struct NowHeader {
  NowKind kind = NowKind::DATA;
  uint32_t pair_id = 0;
  uint32_t boot_id = 0;
  uint16_t body_len = 0;
};

// Builds a packet. Returns total length or 0 if the body does not fit.
size_t now_build(const NowHeader& h, const uint8_t* body, size_t body_len, uint8_t* out, size_t cap);
// Validates magic, version, length and CRC. On success fills h and *body.
bool now_parse(const uint8_t* p, size_t n, NowHeader* h, const uint8_t** body);

struct NowPairMsg {
  NowRole role = NowRole::CHEST;
  uint32_t nonce = 0;
  char dev_id[16] = {0};
  char fw[16] = {0};
};
static const size_t NOW_PAIR_BODY = 37;
size_t now_pair_encode(const NowPairMsg& m, uint8_t* out, size_t cap);
bool now_pair_decode(const uint8_t* p, size_t n, NowPairMsg* m);

// Persistent pairing record (stored in NVS by each side).
struct NowPeerRecord {
  bool valid = false;
  uint8_t mac[6] = {0};
  uint32_t pair_id = 0;
};
static const size_t NOW_PEER_RECORD_LEN = 16;   // "ANP1" + mac + pair_id + crc16
size_t now_peer_serialize(const NowPeerRecord& r, uint8_t* out, size_t cap);
bool now_peer_deserialize(const uint8_t* p, size_t n, NowPeerRecord* r);
void now_mac_str(const uint8_t mac[6], char out[18]);

// ------------------------------------------------------------------ packer
// Accumulates complete frames into one packet body. Frames never span packets.
class NowPacker {
 public:
  // Returns false if the frame alone can never fit (> NOW_MAX_BODY).
  bool fits(size_t frame_len) const { return len_ + frame_len <= NOW_MAX_BODY; }
  bool add(const uint8_t* f, size_t n) {
    if (!fits(n)) return false;
    memcpy(buf_ + len_, f, n);
    len_ += n;
    frames_++;
    return true;
  }
  const uint8_t* data() const { return buf_; }
  size_t size() const { return len_; }
  uint16_t frames() const { return frames_; }
  bool empty() const { return len_ == 0; }
  void clear() { len_ = 0; frames_ = 0; }
 private:
  uint8_t buf_[NOW_MAX_BODY];
  size_t len_ = 0;
  uint16_t frames_ = 0;
};

// ------------------------------------------------------------------ pairing
// Pure state machine; the platform layer does the radio and NVS work.
//  Chest: sends PAIR_REQ (broadcast, 1 Hz) while pairing is open:
//         automatically when it has no paired back, or for 60 s when the app asks.
//         Accepts the PAIR_ACK that echoes its current nonce and pair_id.
//  Back:  answers a PAIR_REQ when (a) it has no paired chest, (b) the user opened
//         pairing with the PRG button, (c) the request comes from its own paired
//         chest (chest lost its memory), or (d) its paired chest has been silent
//         for >= 60 s (chest replaced). Two couples near each other never mix:
//         a linked chest never sends PAIR_REQ unless the user asks for it.
class NowPairing {
 public:
  explicit NowPairing(NowRole role) : role_(role) {}
  NowRole role() const { return role_; }
  const NowPeerRecord& peer() const { return peer_; }
  void load(const NowPeerRecord& r) { peer_ = r; }
  bool paired() const { return peer_.valid; }

  // ---- chest side
  // Opens pairing until now+duration (duration 0 = until success).
  void open(uint32_t now_ms, uint32_t duration_ms, uint32_t new_nonce, uint32_t new_pair_id);
  bool open_now(uint32_t now_ms) const;
  // Builds the PAIR_REQ body when one is due (every 1000 ms). Returns body length or 0.
  size_t chest_poll(uint32_t now_ms, const char* dev_id, const char* fw, uint8_t* body, size_t cap);
  uint32_t proposed_pair_id() const { return proposed_pair_id_; }
  // Returns true (and stores the peer) when the PAIR_ACK completes pairing.
  bool chest_on_ack(const uint8_t mac[6], const NowHeader& h, const NowPairMsg& m, uint32_t now_ms);

  // ---- back side
  void back_open(uint32_t now_ms, uint32_t duration_ms) { back_open_until_ = now_ms + duration_ms; back_open_flag_ = true; }
  bool back_open_now(uint32_t now_ms) const { return back_open_flag_ && (int32_t)(back_open_until_ - now_ms) > 0; }
  // Decides whether to accept a PAIR_REQ; on acceptance stores the peer and returns true.
  bool back_on_req(const uint8_t mac[6], const NowHeader& h, const NowPairMsg& m, uint32_t now_ms, uint32_t last_peer_rx_ms);

  // ---- both
  // True when a DATA packet from mac/pair_id belongs to our couple.
  bool accept_data(const uint8_t mac[6], uint32_t pair_id) const {
    return peer_.valid && pair_id == peer_.pair_id && memcmp(mac, peer_.mac, 6) == 0;
  }
  void forget() { peer_ = NowPeerRecord(); }
  uint32_t last_accept_reason() const { return reason_; }  // back: 1 unpaired, 2 button, 3 same chest, 4 orphan

 private:
  NowRole role_;
  NowPeerRecord peer_;
  // chest
  bool open_ = false;
  uint32_t open_until_ = 0;   // 0 = no deadline
  uint32_t nonce_ = 0, proposed_pair_id_ = 0, last_req_ms_ = 0;
  bool sent_once_ = false;
  // back
  bool back_open_flag_ = false;
  uint32_t back_open_until_ = 0;
  uint32_t reason_ = 0;
};

// ------------------------------------------------------------------ duplicate guard
// Tracks the boot_id of the peer; when it changes the frame decoder must be reset
// (the peer restarted its frame sequence numbers).
class NowBootGuard {
 public:
  // Returns true when the boot_id changed (first packet included).
  bool changed(uint32_t boot_id) {
    if (have_ && boot_id == boot_) return false;
    have_ = true;
    boot_ = boot_id;
    return true;
  }
 private:
  bool have_ = false;
  uint32_t boot_ = 0;
};

}  // namespace avo
