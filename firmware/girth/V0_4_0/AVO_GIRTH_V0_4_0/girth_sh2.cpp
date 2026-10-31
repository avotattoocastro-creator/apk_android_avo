#include "girth_sh2.h"
#include <string.h>

namespace girth {

static inline uint16_t u16le(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }
static inline int16_t i16le(const uint8_t* p) { return (int16_t)u16le(p); }
static inline uint32_t u32le(const uint8_t* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
static inline void put16(uint8_t* p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static inline void put32(uint8_t* p, uint32_t v) { put16(p, (uint16_t)v); put16(p + 2, (uint16_t)(v >> 16)); }

size_t report_len(uint8_t id) {
  switch (id) {
    case R_BASE_TIMESTAMP: case R_TIMESTAMP_REBASE: return 5;
    case R_ACCEL: case R_GYRO: case R_MAG: case R_LINACC: case R_GRAVITY: return 10;
    case R_GAME_RV: return 12;
    case R_ROTVEC: case R_GEO_RV: return 14;
    case 0x07: case 0x0F: case 0x14: case 0x15: case 0x16: return 16;   // uncalibrated / raw (not enabled)
    case 0x2A: return 14;                                             // ARVR-stabilized game RV (not enabled)
    default: return 0;
  }
}

size_t build_set_feature(uint8_t report_id, uint32_t interval_us, uint8_t* out, size_t cap) {
  if (cap < 17) return 0;
  memset(out, 0, 17);
  out[0] = R_SET_FEATURE;
  out[1] = report_id;
  out[2] = 0;                 // feature flags
  put16(out + 3, 0);          // change sensitivity
  put32(out + 5, interval_us);
  put32(out + 9, 0);          // batch interval: 0 = report as soon as available
  put32(out + 13, 0);         // sensor-specific configuration
  return 17;
}

size_t build_product_id_request(uint8_t* out, size_t cap) {
  if (cap < 2) return 0;
  out[0] = R_PRODUCT_ID_REQ;
  out[1] = 0;
  return 2;
}

void Assembler::reset_state() {
  cur_ = Sample();
  have_acc_seq_ = false;
}

void Assembler::on_packet(uint8_t channel, const uint8_t* p, size_t n, uint32_t int_us) {
  if (!p || !n) return;
  switch (channel) {
    case CH_EXECUTABLE:
      if (p[0] == 1) { resets_seen++; reset_flag = true; reset_state(); }   // "reset complete"
      break;
    case CH_CONTROL:
      parse_control(p, n);
      break;
    case CH_REPORTS: case CH_WAKE: case CH_GYRO_RV:
      parse_reports(p, n, int_us);
      break;
    default:
      break;   // channel 0: advertisement / command channel, nothing needed
  }
}

void Assembler::parse_control(const uint8_t* p, size_t n) {
  size_t i = 0;
  while (i < n) {
    uint8_t id = p[i];
    if (id == R_PRODUCT_ID_RESP && i + 16 <= n) {
      // Several 16-byte records (one per firmware component): keep the first (the SH-2 application).
      if (!product.valid) {
        product.valid = true;
        product.reset_cause = p[i + 1]; product.sw_major = p[i + 2]; product.sw_minor = p[i + 3];
        product.part = u32le(p + i + 4); product.build = u32le(p + i + 8); product.patch = u16le(p + i + 12);
      }
      i += 16;
    } else if (id == R_GET_FEATURE_RESP && i + 17 <= n) {
      uint8_t rid = p[i + 1];
      if (rid < 16) feature_interval_us[rid] = u32le(p + i + 5);
      feature_responses++;
      i += 17;
    } else {
      break;   // command responses (0xF1) and others are not needed
    }
  }
}

void Assembler::parse_reports(const uint8_t* p, size_t n, uint32_t int_us) {
  // Accelerometer reports of this packet: emitted after the whole packet is parsed, so that the gyro,
  // linear acceleration and quaternion of the same instant (later in the packet) are included.
  struct Pending { uint32_t t; int16_t a[3]; uint8_t st; };
  Pending pend[8];
  int np = 0;
  uint32_t base_us = 0;   // base timestamp: time between the reports and the INT edge
  size_t i = 0;
  while (i < n) {
    uint8_t id = p[i];
    size_t len = report_len(id);
    if (!len || i + len > n) { unknown++; break; }
    const uint8_t* r = p + i;
    if (id == R_BASE_TIMESTAMP) {
      base_us = u32le(r + 1) * 100u;
    } else if (id == R_TIMESTAMP_REBASE) {
      base_us += (uint32_t)(int32_t)u32le(r + 1) * 100u;   // rebase is relative to the base timestamp
    } else {
      reports++;
      uint8_t status = r[2];
      uint32_t delay_us = ((((uint32_t)status >> 2) << 8) | r[3]) * 100u;
      uint8_t acc = status & 3;
      const uint8_t* d = r + 4;
      switch (id) {
        case R_ACCEL: {
          uint8_t seq = r[1];
          if (have_acc_seq_) {
            uint8_t gap = (uint8_t)(seq - acc_seq_ - 1);
            if (gap && gap < 128) lost += gap;    // a large jump means a restart of the sequence, not losses
          }
          acc_seq_ = seq; have_acc_seq_ = true;
          if (np < 8) {
            Pending& q = pend[np++];
            q.t = int_us - base_us - delay_us;
            for (int k = 0; k < 3; k++) q.a[k] = i16le(d + 2 * k);
            q.st = acc;
          }
          break;
        }
        case R_GYRO: for (int k = 0; k < 3; k++) cur_.gyro[k] = i16le(d + 2 * k); cur_.gyro_status = acc; cur_.have |= 1; break;
        case R_MAG: for (int k = 0; k < 3; k++) cur_.mag[k] = i16le(d + 2 * k); cur_.mag_status = acc; cur_.have |= 2; break;
        case R_LINACC: for (int k = 0; k < 3; k++) cur_.lin[k] = i16le(d + 2 * k); cur_.have |= 4; break;
        case R_GAME_RV: for (int k = 0; k < 4; k++) cur_.quat[k] = i16le(d + 2 * k); cur_.rv_status = acc; cur_.have |= 8; break;
        default: break;
      }
    }
    i += len;
  }
  for (int k = 0; k < np; k++) {
    Sample s = cur_;
    s.t_us = pend[k].t;
    for (int a = 0; a < 3; a++) s.acc[a] = pend[k].a[a];
    s.acc_status = pend[k].st;
    samples++;
    if (fn_) fn_(s, ctx_);
  }
}

size_t encode_batch(uint8_t fmt, const BatchMeta& m, const Sample* s, uint8_t count, uint8_t* out, size_t cap) {
  const size_t per = fmt == FMT_9AXIS ? FMT0_LEN : FMT1_LEN;
  if (!count || count > BATCH_MAX || (fmt != FMT_9AXIS && fmt != FMT_FUSED)) return 0;
  size_t need = 24 + per * count;
  if (cap < need) return 0;
  // ImuBatchHeader (avo_payloads.h), 24 bytes
  out[0] = m.girth_id; out[1] = m.imu_id; out[2] = count; out[3] = fmt;
  put32(out + 4, m.batch);
  put32(out + 8, s[0].t_us);
  put16(out + 12, m.period_us);
  out[14] = 0;                  // sync_state: none (the back stamps its own receive time)
  out[15] = UNITS_BNO085_Q;     // 0.4.3: units declared (was "reserved" = 0)
  put32(out + 16, 0);           // back_rx_ms (filled by the back)
  put32(out + 20, 0);           // girth_to_back_us (not estimated on the girth)
  uint8_t* p = out + 24;
  for (uint8_t i = 0; i < count; i++) {
    const Sample& x = s[i];
    if (fmt == FMT_9AXIS) {
      const int16_t v[9] = {x.acc[0], x.acc[1], x.acc[2], x.gyro[0], x.gyro[1], x.gyro[2], x.mag[0], x.mag[1], x.mag[2]};
      for (int k = 0; k < 9; k++, p += 2) put16(p, (uint16_t)v[k]);
    } else {
      const int16_t v[7] = {x.lin[0], x.lin[1], x.lin[2], x.quat[0], x.quat[1], x.quat[2], x.quat[3]};
      for (int k = 0; k < 7; k++, p += 2) put16(p, (uint16_t)v[k]);
    }
  }
  return need;
}

}  // namespace girth
