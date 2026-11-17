// AVO GIRTH 0.6.0 — ECG (TI ADS1292, channel 2, PCB REV D) · hardware-independent part, tested on the host.
// (0.5.0 used the MAX30003; the batch format below is unchanged, so back, chest and apps see the same data.)
//
// ECG batch = fmt 2 of the IMU_SAMPLE family (avo_payloads.h). The back and the chest already forward and store unknown
// formats unchanged ("header valid, samples opaque"), so the ECG travels girth -> back -> chest -> .avr with NO change
// in the back or chest firmware. Only the girth (this file) and the receivers (apps / engine) know fmt 2.
//
// Header (24 bytes, ImuBatchHeader):
//   girth_id 0 · imu_id 3 (= ECG channel) · count (≤ ECG_BATCH_MAX) · fmt 2 · batch (own counter) ·
//   girth_t0_us (girth clock of the FIRST sample) · period_us (ADS1292 at 500 sps → 2000 µs, corrected by EcgClock) ·
//   sync_state 0 · units byte (offset 15) = 2 (UNITS_ECG_DUV) · back_rx_ms / girth_to_back_us filled by the back.
// Samples: int24 little endian, ECG voltage at the electrodes in units of 0,1 µV (range ±838 mV).
//   ECG_INVALID (-8388608, 0x800000) = no valid sample (electrode off / FIFO overflow): never interpolated.
// Body size at 500 sps every ~100 ms: 24 + 50 × 3 = 174 bytes ≤ the back's limit (24 + 10 × 18 = 204).
// Range: ±403 mV at gain 6 (default; the equine ECG at the girth is ~1–3 mV + electrode offsets of tens of mV).
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace girth {

static const uint8_t FMT_ECG = 2;
static const uint8_t ECG_CHANNEL_ID = 3;      // imu_id of the ECG batches (0..2 are IMUs)
static const uint8_t UNITS_ECG_DUV = 2;       // samples int24 in 0,1 µV
static const size_t ECG_SAMPLE_LEN = 3;
static const uint8_t ECG_BATCH_MAX = 60;      // 24 + 60 × 3 = 204 = back limit
static const int32_t ECG_INVALID = -8388608;

// ADS1292 (datasheet SBAS502C): SPI mode 1, opcodes, registers and values used by the firmware (one place, tested)
namespace ads1292 {
// opcodes
static const uint8_t WAKEUP = 0x02, STANDBY = 0x04, RESET = 0x06, START = 0x08, STOP = 0x0A, RDATAC = 0x10,
                     SDATAC = 0x11, RDATA = 0x12, RREG = 0x20, WREG = 0x40;
// registers
static const uint8_t ID = 0x00, CONFIG1 = 0x01, CONFIG2 = 0x02, LOFF = 0x03, CH1SET = 0x04, CH2SET = 0x05,
                     RLD_SENS = 0x06, LOFF_SENS = 0x07, LOFF_STAT = 0x08, RESP1 = 0x09, RESP2 = 0x0A, GPIO = 0x0B;
// ID register: ADS1291 0x52, ADS1292 0x53, ADS1292R 0x73 (low nibble = channels / revision)
inline bool id_ok(uint8_t id) { return id == 0x52 || id == 0x53 || id == 0x73; }
inline const char* id_name(uint8_t id) { return id == 0x73 ? "ADS1292R" : id == 0x53 ? "ADS1292" : id == 0x52 ? "ADS1291" : "?"; }
// gain code (CHnSET GAIN[6:4]) -> V/V
inline int gain_vv(uint8_t code) { static const int g[8] = {6, 1, 2, 3, 4, 8, 12, 6}; return g[code & 7]; }
// codes accepted by the "ganancia" command; -1 if not a valid gain
int gain_code(int vv);
// register values (500 sps, internal 2,42 V reference, DC lead-off on channel 2, RLD from channel 2, RLDREF internal)
uint8_t config1();             // 0x02: 500 sps, continuous
uint8_t config2();             // 0xE0: lead-off comparators + reference buffer on, VREF 2,42 V. CLK_EN (bit 3) MUST stay 0: PCB REV D ties CLK to DGND
uint8_t loff();                // 0x10: 95 % threshold, 6 nA, DC
uint8_t ch1set();              // 0x81: channel 1 powered down, input shorted
uint8_t ch2set(uint8_t gain_code);   // channel 2 normal electrode input
uint8_t rld_sens();            // 0x2C: RLD buffer on, from IN2P and IN2N
uint8_t loff_sens();           // 0x0C: lead-off on IN2P and IN2N
uint8_t resp1();               // 0x02: respiration off (bit 1 must be 1)
uint8_t resp2();               // 0x03: RLDREF internal ((AVDD + AVSS)/2), bit 0 must be 1
// 72-bit frame: status (1100 + LOFF_STAT[4:0] + GPIO[1:0] + 13 × 0), CH1, CH2 (24-bit two's complement, MSB first)
struct Frame { bool header_ok; uint8_t loff_stat; int32_t ch1, ch2; };
Frame decode_frame(const uint8_t f[9]);
inline bool leads_off(uint8_t loff_stat) { return (loff_stat & 0x0C) != 0; }   // IN2N_OFF (bit 3) or IN2P_OFF (bit 2)
}  // namespace ads1292

// 24-bit code -> 0,1 µV: V = code × 2 × VREF / (gain × 2^24), VREF = 2,42 V. Rounded; clamped to int24 (never 0x800000).
int32_t ads_code_to_duv(int32_t code, uint8_t gain_code);

// Uniform time stamps for a sample stream produced by an independent clock (MAX30003 crystal) and read in bursts:
// sample k is at t0 + k × period. Each burst gives a noisy time for its LAST sample (the interrupt); the period and the
// origin are corrected slowly (phase-locked), so the time stamps stay uniform AND follow the girth clock without drift.
class EcgClock {
 public:
  void reset(double nominal_period_us) {   // 0.6.0: ADS1292 at 500 sps → 2000 µs
    per_ = nominal_period_us; nom_ = nominal_period_us; started_ = false; clock_init_ = false; n_ = 0; run_n_ = 0; unwrap_ = 0;
  }
  // A burst of `count` samples whose last one was read at `t_last_us` (girth clock). Returns the time of the first
  // sample of the burst.
  uint32_t burst(uint32_t t_last_us, uint32_t count);
  double period_us() const { return per_; }
  uint64_t samples() const { return n_; }
  // a gap (FIFO overflow, restart): the next burst starts a new origin
  void gap() { started_ = false; }

 private:
  double per_ = 1953.125, nom_ = 1953.125, t0_ = 0;   // t0_: time of sample index 0 of the current run (µs, unwrapped)
  uint32_t last_raw_ = 0;
  double unwrap_ = 0;
  uint64_t n_ = 0, run_n_ = 0;
  bool started_ = false, clock_init_ = false;
};

// Batch meta of an ECG batch
struct EcgMeta {
  uint8_t girth_id = 0;
  uint32_t batch = 0;
  uint32_t t0_us = 0;
  uint16_t period_us = 2000;
};
// Encodes an ECG batch (24-byte header + count × int24). Returns the length, 0 when it does not fit / count invalid.
size_t encode_ecg_batch(const EcgMeta& m, const int32_t* duv, uint8_t count, uint8_t* out, size_t cap);

}  // namespace girth
