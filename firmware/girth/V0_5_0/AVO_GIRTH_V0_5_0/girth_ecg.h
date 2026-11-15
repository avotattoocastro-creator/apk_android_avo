// AVO GIRTH 0.5.0 — ECG (MAX30003, one channel) · hardware-independent part, tested on the host.
//
// ECG batch = fmt 2 of the IMU_SAMPLE family (avo_payloads.h). The back and the chest already forward and store unknown
// formats unchanged ("header valid, samples opaque"), so the ECG travels girth -> back -> chest -> .avr with NO change
// in the back or chest firmware. Only the girth (this file) and the receivers (apps / engine) know fmt 2.
//
// Header (24 bytes, ImuBatchHeader):
//   girth_id 0 · imu_id 3 (= ECG channel) · count (≤ ECG_BATCH_MAX) · fmt 2 · batch (own counter) ·
//   girth_t0_us (girth clock of the FIRST sample) · period_us (rounded; exact rate in the README: 512 sps → 1953,125 µs) ·
//   sync_state 0 · units byte (offset 15) = 2 (UNITS_ECG_DUV) · back_rx_ms / girth_to_back_us filled by the back.
// Samples: int24 little endian, ECG voltage at the electrodes in units of 0,1 µV (range ±838 mV).
//   ECG_INVALID (-8388608, 0x800000) = no valid sample (electrode off / FIFO overflow): never interpolated.
// Body size at 512 sps every ~100 ms: 24 + 51 × 3 = 177 bytes ≤ the back's limit (24 + 10 × 18 = 204).
// Range: ±50 mV at gain 20, ±25 mV at gain 40 (default; the equine ECG at the girth is ~1–3 mV + motion).
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

// MAX30003 registers / bits used (datasheet MAX30003, rev. 2)
namespace max30003 {
static const uint8_t STATUS = 0x01, EN_INT = 0x02, MNGR_INT = 0x04, MNGR_DYN = 0x05, SW_RST = 0x08, SYNCH = 0x09,
                     FIFO_RST = 0x0A, INFO = 0x0F, CNFG_GEN = 0x10, CNFG_CAL = 0x12, CNFG_EMUX = 0x14, CNFG_ECG = 0x15,
                     CNFG_RTOR1 = 0x1D, ECG_FIFO_BURST = 0x20, ECG_FIFO = 0x21;
// STATUS bits
static const uint32_t ST_EINT = 1u << 23, ST_EOVF = 1u << 22, ST_DCLOFFINT = 1u << 20;
// ETAG of an ECG FIFO word
enum Etag : uint8_t { VALID = 0, FAST = 1, VALID_EOF = 2, FAST_EOF = 3, EMPTY = 6, OVERFLOW = 7 };
// gain code (CNFG_ECG GAIN[17:16]) -> V/V
inline int gain_vv(uint8_t code) { static const int g[4] = {20, 40, 80, 160}; return g[code & 3]; }
// Register values used by the firmware (one place, tested):
//  CNFG_GEN: EN_ECG, DC lead-off on ECGP/N (5 nA, VMID ± 300 mV), RBIAS 100 MΩ on both inputs, FMSTR 00 (32 768 Hz)
uint32_t cnfg_gen();
//  CNFG_ECG: 512 sps (RATE 00 with FMSTR 00), gain code, digital HPF 0,5 Hz, digital LPF 40 Hz
uint32_t cnfg_ecg(uint8_t gain_code);
//  MNGR_INT: interrupt when the FIFO holds `threshold` samples (1..32)
uint32_t mngr_int(uint8_t threshold);
//  EN_INT: FIFO threshold, FIFO overflow, DC lead-off; INTB open drain with internal pull-up
uint32_t en_int();
// SPI command byte: (reg << 1) | read
inline uint8_t cmd(uint8_t reg, bool read) { return (uint8_t)((reg << 1) | (read ? 1 : 0)); }
}  // namespace max30003

// One ECG FIFO word (24 bits): data = bits 23..6 (18-bit two's complement), ETAG = bits 5..3.
struct EcgWord { int32_t counts; uint8_t etag; };
EcgWord decode_fifo_word(uint32_t w24);

// counts -> 0,1 µV: V = counts × VREF / (2^17 × gain), VREF = 1000 mV. Rounded to nearest; clamped to int24.
int32_t counts_to_duv(int32_t counts, uint8_t gain_code);

// Uniform time stamps for a sample stream produced by an independent clock (MAX30003 crystal) and read in bursts:
// sample k is at t0 + k × period. Each burst gives a noisy time for its LAST sample (the interrupt); the period and the
// origin are corrected slowly (phase-locked), so the time stamps stay uniform AND follow the girth clock without drift.
class EcgClock {
 public:
  void reset(double nominal_period_us) {
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
  uint16_t period_us = 1953;
};
// Encodes an ECG batch (24-byte header + count × int24). Returns the length, 0 when it does not fit / count invalid.
size_t encode_ecg_batch(const EcgMeta& m, const int32_t* duv, uint8_t count, uint8_t* out, size_t cap);

}  // namespace girth
