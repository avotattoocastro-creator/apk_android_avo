#include "girth_ecg.h"
#include <math.h>

namespace girth {

namespace ads1292 {
int gain_code(int vv) {
  switch (vv) { case 6: return 0; case 1: return 1; case 2: return 2; case 3: return 3; case 4: return 4; case 8: return 5;
                case 12: return 6; default: return -1; }
}
uint8_t config1() { return 0x02; }
uint8_t config2() { return 0x80 | 0x40 | 0x20; }
uint8_t loff() { return 0x10; }
uint8_t ch1set() { return 0x80 | 0x01; }
uint8_t ch2set(uint8_t gain_code) { return (uint8_t)((gain_code & 7) << 4); }
uint8_t rld_sens() { return 0x20 | 0x08 | 0x04; }
uint8_t loff_sens() { return 0x08 | 0x04; }
uint8_t resp1() { return 0x02; }
uint8_t resp2() { return 0x02 | 0x01; }
static int32_t s24(const uint8_t* p) {
  int32_t v = ((int32_t)p[0] << 16) | ((int32_t)p[1] << 8) | p[2];
  if (v & 0x800000) v -= 0x1000000;
  return v;
}
Frame decode_frame(const uint8_t f[9]) {
  Frame r;
  uint32_t st = ((uint32_t)f[0] << 16) | ((uint32_t)f[1] << 8) | f[2];
  r.header_ok = (st >> 20) == 0xC;
  r.loff_stat = (uint8_t)((st >> 15) & 0x1F);
  r.ch1 = s24(f + 3);
  r.ch2 = s24(f + 6);
  return r;
}
}  // namespace ads1292

int32_t ads_code_to_duv(int32_t code, uint8_t gain_code) {
  // 0,1 µV = code × 2 × 2,42 V × 1e7 / (gain × 2^24) = code × 48 400 000 / (gain × 16 777 216)
  int64_t num = (int64_t)code * 48400000LL;
  int64_t den = 16777216LL * ads1292::gain_vv(gain_code);
  int64_t q = num >= 0 ? (num + den / 2) / den : -((-num + den / 2) / den);
  if (q > 8388607) q = 8388607;
  if (q < -8388607) q = -8388607;
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
      t0_ += 0.1 * err;
      if (idx > 0) per_ += 0.5 * err / idx;           // frequency error seen over the whole run
      if (per_ > nom_ * 1.03) per_ = nom_ * 1.03;   // 0.6.0: internal oscillator of the ADS1292 (±2 % over temperature)
      if (per_ < nom_ * 0.97) per_ = nom_ * 0.97;
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
