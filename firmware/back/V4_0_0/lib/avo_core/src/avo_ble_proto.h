// AVO BLE PROTOCOL v1 — application framing over GATT. Spec: PROTOCOL_BLE.md
//
// Fragment layout (little-endian), one per ATT write/notification:
//   0 ver(1) | 1 type | 2 msg_id u16 | 4 frag_idx u16 | 6 frag_cnt u16 | 8 flags | 9 status
//   10.. payload fragment | last 2 bytes CRC-16/CCITT-FALSE over bytes 0..n-3
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

static const uint8_t BLE_PROTO_VERSION = 1;
static const size_t BLE_FRAG_HDR = 10;
static const size_t BLE_FRAG_OVERHEAD = BLE_FRAG_HDR + 2;
static const size_t BLE_MAX_MSG = 4096;

enum class BleMsg : uint8_t {
  GET_INFO = 0x01, GET_STATUS = 0x02,
  // V3.4.4 application-level authorization (see PROTOCOL_BLE.md §Autorización)
  AUTH_HELLO = 0x08, AUTH_PROOF = 0x09, CLAIM_BEGIN = 0x0A, CLAIM_RESULT = 0x0B, AUTH_REVOKE = 0x0C,
  SESSION_CMD = 0x10,
  GET_CONFIG = 0x20, SET_CONFIG = 0x21, SET_FENCE = 0x22, GET_FENCE = 0x23, SET_ACTIVE_FENCES = 0x24,
  RTCM = 0x30, RTCM_ACK = 0x31,
  LIST_SESSIONS = 0x40, READ_FILE = 0x41, FILE_SHA256 = 0x42, MARK_UPLOADED = 0x43,
  DELETE_PREPARE = 0x44, DELETE_COMMIT = 0x45, FILE_DATA = 0x46,
  OTA_BEGIN = 0x50, OTA_DATA = 0x51, OTA_END = 0x52, OTA_ABORT = 0x53,
  OTA_AUTH = 0x54, // V3.5.7: u16 manifest_len, u16 signature_len, raw manifest, DER signature
  DIAG_GET = 0x60, BLACKBOX_READ = 0x61, REBOOT = 0x62,
  BACK_LINK = 0x63,   // V3.5.0: u8 action (1 open ESP-NOW pairing 60 s, 2 forget the paired back)
  TIME_SET = 0x70, CREDITS = 0x71,
  NACK = 0x7E, ACK = 0x7F,
  TELEMETRY = 0x80, EVENT = 0x81,
};

enum BleFlag : uint8_t { BF_ACK_REQ = 0x01, BF_RESPONSE = 0x02, BF_ERROR = 0x04 };

enum class BleStatus : uint8_t {
  OK = 0, BAD_CRC = 1, BAD_FORMAT = 2, UNKNOWN_TYPE = 3, BUSY = 4, NOT_ALLOWED = 5, NOT_FOUND = 6,
  TOO_LARGE = 7, AUTH_REQUIRED = 8, IO_ERROR = 9, STATE_CONFLICT = 10, DUPLICATE = 11, TIMEOUT = 12,
  VERIFY_FAILED = 13,
};

enum class SessionCmd : uint8_t { START = 1, STOP = 2, PAUSE = 3, RESUME = 4, MARKER = 5, REARM = 6 };

struct BleFragView {
  uint8_t ver, flags, status;
  BleMsg type;
  uint16_t msg_id, frag_idx, frag_cnt;
  const uint8_t* payload;
  size_t len;
};

bool ble_frag_parse(const uint8_t* p, size_t n, BleFragView* v);
// Encodes one fragment. Returns bytes written (0 on error).
size_t ble_frag_build(BleMsg type, uint16_t msg_id, uint16_t idx, uint16_t cnt, uint8_t flags, uint8_t status,
                      const uint8_t* pl, size_t len, uint8_t* out, size_t cap);
// Number of fragments needed for a message of len bytes with a given ATT payload size (MTU-3).
uint16_t ble_frag_count(size_t len, size_t att_payload);

// Reassembles fragmented messages; rejects duplicates of completed messages.
class BleReassembler {
 public:
  enum Result { NEED_MORE, COMPLETE, DUPLICATE, ERROR };
  // On COMPLETE, *msg/*len point to an internal buffer valid until the next call.
  Result feed(const BleFragView& f, uint32_t now_ms, const uint8_t** msg, size_t* len, BleStatus* err);
  void expire(uint32_t now_ms, uint32_t timeout_ms = 5000);
  void reset();
  uint32_t duplicates() const { return dups_; }
  uint32_t errors() const { return errs_; }
 private:
  bool seen(uint16_t id) const;
  void remember(uint16_t id);
  struct Slot { bool used; uint16_t id; uint16_t cnt, next; size_t len; uint32_t t; BleMsg type; uint8_t buf[BLE_MAX_MSG]; };
  Slot s_[2];
  uint16_t done_[32];
  uint8_t done_n_ = 0, done_i_ = 0;
  uint32_t dups_ = 0, errs_ = 0;
};

}  // namespace avo

namespace avo {
// TELEMETRY notification payload (v1 = first 45 bytes, v2 = V3.4.4, 83 bytes).
// Single encoder shared by the firmware and the cross-language test vectors.
struct Telemetry {
  uint8_t session_state = 0, gf_state = 0, rec_status = 0, fix_type = 0, carr_soln = 0, num_sv = 0;
  uint32_t hacc_mm = 0;
  int32_t lat_e7 = 0, lon_e7 = 0, gspeed_mm_s = 0;
  uint32_t distance_cm = 0, active_ms = 0;
  int8_t batt_pct = -1;
  uint8_t link_connected = 0, girth_connected = 0, rtcm_flowing = 0;
  uint16_t ring_fill_permille = 0;
  uint32_t dropped_records = 0, pending_ms = 0;
  uint8_t inhibited = 0;
  // v2
  uint8_t gnss_flags = 0;        // b0 gnssFixOK b1 diffSoln b2 invalidLlh b3 have_gnss b4 quality_ok
  uint8_t corr_age_code = 0, sd_mounted = 0, pps_state = 0xFF;
  uint16_t back_batt_mv = 0;
  uint8_t time_source = 0, back_status_valid = 0;
  uint32_t rtcm_to_back_bytes = 0, rxm_rtcm_used = 0;
  uint8_t power_level = 3, vbus = 0;
  uint16_t batt_mv = 0;
  uint32_t gnss_age_ms = 0xFFFFFFFFu, vacc_mm = 0, link_age_ms = 0xFFFFFFFFu;
  uint8_t manual = 0, girth_present = 0;
  uint32_t girth_lost = 0;
};
static const size_t TELEMETRY_V1_LEN = 45;
static const size_t TELEMETRY_V2_LEN = 83;
size_t encode_telemetry(const Telemetry& t, uint8_t* out, size_t cap);
}  // namespace avo
