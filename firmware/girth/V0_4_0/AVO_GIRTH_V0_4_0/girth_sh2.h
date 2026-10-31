// AVO GIRTH 0.4.0 — SH-2 (CEVA/Hillcrest) report parsing for the BNO085, independent of Arduino.
//
// The I²C transport (girth_bno085.cpp) hands every SHTP packet here: channel + cargo without the 4-byte
// SHTP header. This file only parses bytes, so the same code is compiled and tested on the host
// (test/test_girth.cpp) and on the ESP32-C6.
//
// Reports enabled by the girth (all at the same interval, 10 ms by default):
//   0x01 accelerometer (calibrated, includes gravity)   Q8  m/s²
//   0x02 gyroscope (calibrated)                          Q9  rad/s
//   0x03 magnetic field (calibrated)                     Q4  µT
//   0x04 linear acceleration (gravity removed)           Q8  m/s²
//   0x08 game rotation vector (no magnetometer)          Q14 unit quaternion (i, j, k, real)
// The game rotation vector does not use the magnetometer, so the corner magnets of the capsule and the
// mount cannot bend the orientation.
//
// One output sample per accelerometer report: the accelerometer is the master clock; the other values
// are the latest received (same interval, usually in the same SHTP packet).
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace girth {

// SHTP channels
enum : uint8_t { CH_COMMAND = 0, CH_EXECUTABLE = 1, CH_CONTROL = 2, CH_REPORTS = 3, CH_WAKE = 4, CH_GYRO_RV = 5 };

// SH-2 report ids used here
enum : uint8_t {
  R_ACCEL = 0x01, R_GYRO = 0x02, R_MAG = 0x03, R_LINACC = 0x04, R_ROTVEC = 0x05, R_GRAVITY = 0x06,
  R_GAME_RV = 0x08, R_GEO_RV = 0x09,
  R_TIMESTAMP_REBASE = 0xFA, R_BASE_TIMESTAMP = 0xFB, R_GET_FEATURE_RESP = 0xFC, R_SET_FEATURE = 0xFD,
  R_PRODUCT_ID_RESP = 0xF8, R_PRODUCT_ID_REQ = 0xF9, R_COMMAND_RESP = 0xF1,
};

// Length of an input report inside a channel-3/4/5 packet (0 = unknown: stop parsing that packet).
size_t report_len(uint8_t id);

// Set Feature command (channel 2): 17 bytes.
size_t build_set_feature(uint8_t report_id, uint32_t interval_us, uint8_t* out, size_t cap);
// Product ID request (channel 2): 2 bytes.
size_t build_product_id_request(uint8_t* out, size_t cap);

struct ProductId {
  bool valid = false;
  uint8_t reset_cause = 0, sw_major = 0, sw_minor = 0;
  uint32_t part = 0, build = 0;
  uint16_t patch = 0;
};

// One synchronized output sample (fixed point exactly as the BNO085 reports it).
struct Sample {
  uint32_t t_us = 0;          // girth clock (esp_timer, low 32 bits) at acquisition
  int16_t acc[3] = {0, 0, 0};   // Q8 m/s²
  int16_t gyro[3] = {0, 0, 0};  // Q9 rad/s
  int16_t mag[3] = {0, 0, 0};   // Q4 µT
  int16_t lin[3] = {0, 0, 0};   // Q8 m/s²
  int16_t quat[4] = {0, 0, 0, 0};  // Q14: i, j, k, real
  uint8_t acc_status = 0, gyro_status = 0, mag_status = 0, rv_status = 0;   // SH-2 accuracy 0..3
  uint8_t have = 0;           // bits: 1 gyro, 2 mag, 4 lin, 8 quat (received at least once)
};

class Assembler {
 public:
  typedef void (*SampleFn)(const Sample& s, void* ctx);
  void set_sink(SampleFn fn, void* ctx) { fn_ = fn; ctx_ = ctx; }
  void reset_state();   // after a BNO reset: forget sequence numbers and the last values

  // One SHTP packet (cargo without the 4-byte header). int_us = host time when INT went low.
  void on_packet(uint8_t channel, const uint8_t* p, size_t n, uint32_t int_us);

  // Counters (monotonic since boot)
  uint32_t samples = 0;         // samples emitted
  uint32_t lost = 0;            // accelerometer reports skipped by the sensor (sequence gaps)
  uint32_t reports = 0;         // input reports parsed
  uint32_t unknown = 0;         // packets cut short by an unknown report id
  uint32_t resets_seen = 0;     // "reset complete" messages (channel 1)
  bool reset_flag = false;      // set on "reset complete": the transport must enable the reports again
  ProductId product;
  uint32_t feature_interval_us[16] = {0};   // from Get Feature Response, index = report id (< 16)
  uint32_t feature_responses = 0;

 private:
  void parse_reports(const uint8_t* p, size_t n, uint32_t int_us);
  void parse_control(const uint8_t* p, size_t n);
  SampleFn fn_ = nullptr;
  void* ctx_ = nullptr;
  Sample cur_;
  bool have_acc_seq_ = false;
  uint8_t acc_seq_ = 0;
};

// ---------------------------------------------------------------- batches for the back (ESP-NOW)
// fmt 0 (existing, understood by the back, the chest, the app and the analysis engine):
//   ax ay az gx gy gz mx my mz, int16 LE, 18 bytes/sample. Units for this girth: acc Q8 m/s², gyro Q9 rad/s,
//   mag Q4 µT (BNO085 native fixed point).
// fmt 1 (new in GIRTH 0.4.0, same timestamps as the fmt 0 batch with the same batch number):
//   lx ly lz (linear acceleration, Q8 m/s²) qi qj qk qr (game rotation vector, Q14), int16 LE, 14 bytes/sample.
static const uint8_t FMT_9AXIS = 0;
static const uint8_t FMT_FUSED = 1;
static const size_t FMT0_LEN = 18, FMT1_LEN = 14;
static const uint8_t BATCH_MAX = 10;   // the back accepts up to 24 + 10 × 18 = 204 bytes of IMU body

struct BatchMeta {
  uint8_t girth_id = 0, imu_id = 0;
  uint32_t batch = 0;        // batch number, shared by the fmt 0 and fmt 1 batches of the same samples
  uint16_t period_us = 10000;
};
// Encodes one IMU body (24-byte header + samples). Returns 0 if it does not fit.
size_t encode_batch(uint8_t fmt, const BatchMeta& m, const Sample* s, uint8_t count, uint8_t* out, size_t cap);

}  // namespace girth
