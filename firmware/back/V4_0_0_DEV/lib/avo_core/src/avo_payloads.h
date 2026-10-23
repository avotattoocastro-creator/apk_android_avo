// AVO UART PROTOCOL v1 — payload schemas.
// Rule of compatibility: a payload schema may only grow by appending fields.
// Decoders accept payloads longer than they know (extra bytes ignored) and
// reject payloads shorter than the v1 minimum.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

// ---------------------------------------------------------------- GNSS_SAMPLE
// Compact form of UBX-NAV-PVT produced by the back, plus back-side timestamps.
struct GnssSample {
  uint32_t itow_ms = 0;          // GPS time of week of the navigation epoch (measurement time)
  uint16_t year = 0;
  uint8_t month = 0, day = 0, hour = 0, min = 0, sec = 0;
  uint8_t valid = 0;             // UBX valid: b0 validDate, b1 validTime, b2 fullyResolved
  int32_t nano = 0;
  uint32_t tacc_ns = 0;
  uint8_t fix_type = 0;          // 0 none,1 DR,2 2D,3 3D,4 GNSS+DR,5 time only
  uint8_t flags = 0;             // UBX flags: b0 gnssFixOK, b1 diffSoln, b6..7 carrSoln
  uint16_t flags3 = 0;           // UBX flags3: b0 invalidLlh, b1..4 lastCorrectionAge code
  uint8_t num_sv = 0;
  int32_t lon_e7 = 0, lat_e7 = 0;
  int32_t height_mm = 0, hmsl_mm = 0;
  uint32_t hacc_mm = 0, vacc_mm = 0;
  int32_t veln_mm_s = 0, vele_mm_s = 0, veld_mm_s = 0;
  int32_t gspeed_mm_s = 0;
  int32_t head_mot_e5 = 0;
  uint32_t sacc_mm_s = 0;
  uint32_t head_acc_e5 = 0;
  uint16_t pdop_e2 = 0;
  // Back-side timing (not part of NAV-PVT)
  uint32_t back_rx_ms = 0;       // back clock when the NAV-PVT was fully received
  uint8_t pps_locked = 0;        // back had a valid PPS<->GNSS mapping at that moment
  uint8_t nav_rate_hz = 0;       // configured navigation rate on the ZED-F9P

  bool gnss_fix_ok() const { return flags & 0x01; }
  bool diff_soln() const { return flags & 0x02; }
  uint8_t carr_soln() const { return (flags >> 6) & 0x03; }  // 0 none, 1 float, 2 fixed
  bool invalid_llh() const { return flags3 & 0x01; }
  uint8_t corr_age_code() const { return (flags3 >> 1) & 0x0F; }
};
static const size_t GNSS_SAMPLE_V1_LEN = 85;
size_t encode_gnss(const GnssSample& s, uint8_t* out, size_t cap);
bool decode_gnss(const uint8_t* p, size_t n, GnssSample* s);
// Upper bound (ms) of correction age for UBX flags3 lastCorrectionAge code; 0 = not available.
uint32_t corr_age_code_to_max_ms(uint8_t code);

// ---------------------------------------------------------------- IMU_SAMPLE
static const uint8_t IMU_FMT_9AXIS_I16 = 0;  // ax ay az gx gy gz mx my mz (int16, raw sensor LSB)
static const size_t IMU_HDR_LEN = 24;
static const size_t IMU_SAMPLE_LEN_9AXIS = 18;
static const uint8_t IMU_MAX_SAMPLES = 55;   // (1024-24)/18
struct ImuBatchHeader {
  uint8_t girth_id = 0;      // girth device id (original)
  uint8_t imu_id = 0;        // 0 central, 1 left, 2 right
  uint8_t count = 0;         // samples in this batch
  uint8_t fmt = IMU_FMT_9AXIS_I16;
  uint32_t girth_seq = 0;    // original girth packet sequence number
  uint32_t girth_t0_us = 0;  // girth clock at first sample (original)
  uint16_t period_us = 0;    // nominal sample period
  uint8_t sync_state = 0;    // 0 none, 1 coarse (rx-time), 2 PPS-disciplined
  uint8_t reserved = 0;
  uint32_t back_rx_ms = 0;   // back clock when the ESP-NOW packet arrived
  int32_t girth_to_back_us = 0;  // estimated offset: back_us = girth_us + offset
};
size_t encode_imu_header(const ImuBatchHeader& h, uint8_t* out, size_t cap);
bool decode_imu_header(const uint8_t* p, size_t n, ImuBatchHeader* h);

// ---------------------------------------------------------------- TIME_SYNC
struct TimeSync {
  uint64_t back_us_at_pps = 0;  // back monotonic µs captured at the PPS edge
  uint32_t tow_ms_at_pps = 0;   // GPS time of week of that edge (from UBX-TIM-TP)
  uint16_t gps_week = 0;
  uint8_t flags = 0;            // b0 valid, b1 utc_valid, b2 pps_in_tolerance
  int8_t leap_s = 0;
  uint32_t pps_jitter_ns = 0;   // back's measured edge jitter estimate
  uint32_t pps_count = 0;
};
static const size_t TIME_SYNC_V1_LEN = 24;
size_t encode_timesync(const TimeSync& t, uint8_t* out, size_t cap);
bool decode_timesync(const uint8_t* p, size_t n, TimeSync* t);

// ---------------------------------------------------------------- STATUS (back)
struct BackStatus {
  uint32_t uptime_ms = 0;
  uint8_t zed_state = 0;        // 0 not detected, 1 configuring, 2 running, 3 error
  uint8_t pps_state = 0;        // 0 absent, 1 present, 2 locked
  uint8_t girth_connected = 0;
  int8_t girth_rssi = 0;
  uint32_t pps_count = 0;
  uint32_t rtcm_rx_bytes = 0;      // received from chest
  uint32_t rtcm_to_zed_bytes = 0;  // written to the ZED-F9P UART
  uint32_t rtcm_frames_ok = 0;     // RTCM3 frames with valid CRC24Q seen by back
  uint32_t rtcm_frames_bad = 0;
  uint32_t rxm_rtcm_used = 0;      // UBX-RXM-RTCM reports with msgUsed=2 (applied by ZED)
  uint32_t rxm_rtcm_failed = 0;    // UBX-RXM-RTCM reports with crcFailed / not used
  uint32_t girth_pkts = 0;
  uint32_t girth_lost = 0;
  uint32_t uart_crc_err = 0;       // errors seen by the back decoder
  uint16_t back_batt_mv = 0;       // 0 = unknown
  uint16_t gnss_rate_hz_x10 = 0;   // measured NAV-PVT rate ×10
  // ---- v2 (V3.5.0, ESP-NOW back): appended; v1 decoders ignore it
  bool v2 = false;
  uint32_t zed_baud = 0;           // UART baud the back uses with the ZED
  uint8_t zed_port = 0;            // ZED port wired to the back: 1 UART1, 2 UART2, 0 unknown
  uint8_t zed_cfg = 0;             // b0 VALSET acknowledged, b1 navigation rate applied
  uint8_t nav_rate_cfg_hz = 0;     // navigation rate requested by the back
  uint8_t zed_detail = 0;          // ZedManager state (0 detect, 1 port, 2 configure, 3 running, 4 no UBX)
  uint32_t rtcm_gaps_bytes = 0;    // stream bytes never received from the chest
  uint32_t rtcm_not_written = 0;   // bytes received while the ZED baud was unknown
  uint32_t link_tx_fail = 0;       // ESP-NOW packets the back could not deliver
  int8_t link_rssi = 0;            // RSSI of the last packet from the chest (dBm)
  uint32_t ubx_frames = 0;         // valid UBX frames from the ZED
  uint32_t nmea_sentences = 0;     // valid NMEA sentences from the ZED
};
static const size_t BACK_STATUS_V1_LEN = 52;
static const size_t BACK_STATUS_V2_LEN = 82;
size_t encode_status(const BackStatus& s, uint8_t* out, size_t cap);
bool decode_status(const uint8_t* p, size_t n, BackStatus* s);

// ---------------------------------------------------------------- CAPS
enum CapBits : uint32_t {
  CAP_GNSS_SAMPLE = 1u << 0, CAP_GNSS_UBX = 1u << 1, CAP_IMU = 1u << 2, CAP_RTCM_IN = 1u << 3,
  CAP_PPS = 1u << 4, CAP_TIME_SYNC = 1u << 5, CAP_RXM_RTCM = 1u << 6, CAP_ACK = 1u << 7,
};
struct Caps {
  uint8_t proto_min = 1, proto_max = 1;
  uint8_t node_type = 0;        // NodeId
  uint8_t hw_rev = 0;
  char fw_version[16] = {0};
  uint32_t caps = 0;
  uint16_t max_payload = 1024;
  uint32_t uart_baud = 0;
  uint8_t gnss_rate_hz = 0;
  uint8_t gnss_constellations = 0;  // b0 GPS b1 GLO b2 GAL b3 BDS
  uint16_t imu_rate_hz = 0;
};
static const size_t CAPS_V1_LEN = 34;
size_t encode_caps(const Caps& c, uint8_t* out, size_t cap);
bool decode_caps(const uint8_t* p, size_t n, Caps* c);
// Highest version both sides support, or 0 if incompatible.
uint8_t negotiate_version(const Caps& a, const Caps& b);

// ---------------------------------------------------------------- EVENT
struct EventMsg {
  uint16_t code = 0;
  uint8_t severity = 0;   // 0 info, 1 warning, 2 error, 3 critical
  uint32_t arg0 = 0, arg1 = 0;
  char text[24] = {0};
};
static const size_t EVENT_V1_LEN = 36;
size_t encode_event(const EventMsg& e, uint8_t* out, size_t cap);
bool decode_event(const uint8_t* p, size_t n, EventMsg* e);

// ---------------------------------------------------------------- COMMAND / ACK / NACK
enum class BackCmd : uint16_t {
  REQ_CAPS = 1, REQ_STATUS = 2, SET_GNSS_RATE = 3, GIRTH_PAIR = 4, GIRTH_UNPAIR = 5,
  TIME_REQUEST = 6, REBOOT = 7,
};
struct Command {
  uint16_t cmd = 0;
  uint16_t cmd_id = 0;      // idempotency key: repeated cmd_id is not executed twice
  uint8_t arg_len = 0;
  uint8_t args[32] = {0};
};
size_t encode_command(const Command& c, uint8_t* out, size_t cap);
bool decode_command(const uint8_t* p, size_t n, Command* c);

struct Ack {
  uint8_t acked_type = 0;
  uint16_t acked_seq = 0;
  uint16_t cmd_id = 0;
  uint8_t status = 0;     // 0 ok; for NACK: reason code
  uint16_t detail = 0;
};
static const size_t ACK_V1_LEN = 8;
size_t encode_ack(const Ack& a, uint8_t* out, size_t cap);
bool decode_ack(const uint8_t* p, size_t n, Ack* a);

// ---------------------------------------------------------------- HEARTBEAT
struct Heartbeat {
  uint32_t uptime_ms = 0;
  uint8_t state = 0;
  uint8_t cpu_load_pct = 0;
  uint16_t queue_fill_pct_x10 = 0;
};
static const size_t HEARTBEAT_V1_LEN = 8;
size_t encode_heartbeat(const Heartbeat& h, uint8_t* out, size_t cap);
bool decode_heartbeat(const uint8_t* p, size_t n, Heartbeat* h);

// ---------------------------------------------------------------- RTCM_DATA
// payload: u32 stream_offset (byte offset of data[0] in the chest's RTCM stream), data[]
static const size_t RTCM_DATA_HDR = 4;

}  // namespace avo
