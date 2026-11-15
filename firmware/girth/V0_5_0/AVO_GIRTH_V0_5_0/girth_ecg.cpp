#include "girth_ecg.h"
#include <math.h>

namespace girth {

namespace max30003 {
uint32_t cnfg_gen() {
  return (1u << 19)       // EN_ECG
       | (1u << 12)       // EN_DCLOFF = 01: DC lead-off on ECGP / ECGN
       | (1u << 8)        // DCLOFF_IMAG = 001: 5 nA
       | (0u << 6)        // DCLOFF_VTH = 00: VMID ± 300 mV
       | (1u << 4)        // EN_RBIAS = 01: bias resistors on the ECG inputs
       | (1u << 2)        // RBIASV = 01: 100 MΩ
       | (1u << 1) | 1u;  // RBIASP, RBIASN
}
uint32_t cnfg_ecg(uint8_t gain_code) {
  return (0u << 22)                         // RATE 00 -> 512 sps with FMSTR 00
       | ((uint32_t)(gain_code & 3) << 16)  // GAIN
       | (1u << 14)                         // DHPF: 0,5 Hz high-pass (baseline wander)
       | (1u << 12);                        // DLPF 01: 40 Hz low-pass
}
uint32_t mngr_int(uint8_t threshold) {
  if (threshold < 1) threshold = 1;
  if (threshold > 32) threshold = 32;
  return (uint32_t)(threshold - 1) << 19;   // EFIT
}
uint32_t en_int() { return (1u << 23) | (1u << 22) | (1u << 20) | 3u; }   // EINT, EOVF, DCLOFFINT, INTB open drain + pull-up
}  // namespace max30003

EcgWord decode_fifo_word(uint32_t w24) {
  EcgWord w;
  w24 &= 0xFFFFFF;
  int32_t v = (int32_t)(w24 >> 6) & 0x3FFFF;          // 18 bits
  if (v & 0x20000) v -= 0x40000;                     // sign
  w.counts = v;
  w.etag = (uint8_t)((w24 >> 3) & 7);
  return w;
}

int32_t counts_to_duv(int32_t counts, uint8_t gain_code) {
  // 0,1 µV = counts × 1e7 / (131072 × gain)
  int64_t num = (int64_t)counts * 10000000LL;
  int64_t den = 131072LL * max30003::gain_vv(gain_code);
  int64_t q = num >= 0 ? (num + den / 2) / den : -((-num + den / 2) / den);
  if (q > 8388607) q = 8388607;
  if (q < -8388607) q = -8388607;                    // -8388608 is reserved for ECG_INVALID
  return (int32_t)q;
}

uint32_t EcgClock::burst(uint32_t t_last_us, uint32_t count) {
  if (!count) return (uint32_t)(int64_t)(t0_ + run_n_ * per_);
  // unwrap the 32-bit µs clock
  if (!clock_init_) { clock_init_ = true; unwrap_ = t_last_us; last_raw_ = t_last_us; }
  else { unwrap_ += (double)(uint32_t)(t_last_us - last_raw_); last_raw_ = t_last_us; }
  const double t_last = unwrap_;
  if (!started_) {
    started_ = true;
    run_n_ = 0;
    t0_ = t_last - (double)(count - 1) * per_;
  } else {
    const double idx = (double)(run_n_ + count - 1);
    const double err = t_last - (t0_ + idx * per_);
    if (fabs(err) > 50000.0) {                       // 50 ms off: lost samples or a stall -> new origin
      run_n_ = 0;
      t0_ = t_last - (double)(count - 1) * per_;
    } else {
      // phase-locked loop: slow origin and period correction (the read latency is jittery, the crystal is not)
      t0_ += 0.02 * err;
      if (idx > 0) per_ += 0.0005 * err / idx * 50.0;
      if (per_ > nom_ * 1.01) per_ = nom_ * 1.01;
      if (per_ < nom_ * 0.99) per_ = nom_ * 0.99;
    }
  }
  const double first = t0_ + (double)run_n_ * per_;
  run_n_ += count;
  n_ += count;
  return (uint32_t)((uint64_t)llround(first) & 0xFFFFFFFFull);
}

static inline void put16(uint8_t* p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static inline void put32(uint8_t* p, uint32_t v) { put16(p, (uint16_t)v); put16(p + 2, (uint16_t)(v >> 16)); }

size_t encode_ecg_batch(const EcgMeta& m, const int32_t* duv, uint8_t count, uint8_t* out, size_t cap) {
  if (!count || count > ECG_BATCH_MAX) return 0;
  const size_t need = 24 + ECG_SAMPLE_LEN * count;
  if (cap < need) return 0;
  out[0] = m.girth_id; out[1] = ECG_CHANNEL_ID; out[2] = count; out[3] = FMT_ECG;
  put32(out + 4, m.batch);
  put32(out + 8, m.t0_us);
  put16(out + 12, m.period_us);
  out[14] = 0;
  out[15] = UNITS_ECG_DUV;
  put32(out + 16, 0);
  put32(out + 20, 0);
  uint8_t* p = out + 24;
  for (uint8_t i = 0; i < count; i++, p += 3) {
    uint32_t v = (uint32_t)duv[i] & 0xFFFFFF;
    p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16);
  }
  return need;
}

}  // namespace girth
