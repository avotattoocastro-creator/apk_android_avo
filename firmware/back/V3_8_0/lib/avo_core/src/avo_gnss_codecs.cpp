#include "avo_gnss_codecs.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include <string.h>

namespace avo {

void ubx_checksum(const uint8_t* d, size_t n, uint8_t* cka, uint8_t* ckb) {
  uint8_t a = 0, b = 0;
  for (size_t i = 0; i < n; i++) { a = (uint8_t)(a + d[i]); b = (uint8_t)(b + a); }
  *cka = a; *ckb = b;
}

bool ubx_check_frame(const uint8_t* f, size_t n, uint8_t* cls, uint8_t* id, const uint8_t** pl, uint16_t* plen) {
  if (n < 8 || f[0] != UBX_SYNC1 || f[1] != UBX_SYNC2) return false;
  uint16_t len = get_u16(f + 4);
  if ((size_t)len + 8 != n) return false;
  uint8_t a, b;
  ubx_checksum(f + 2, 4 + (size_t)len, &a, &b);
  if (a != f[6 + len] || b != f[7 + len]) return false;
  *cls = f[2]; *id = f[3]; *pl = f + 6; *plen = len;
  return true;
}

size_t ubx_build(uint8_t cls, uint8_t id, const uint8_t* pl, uint16_t plen, uint8_t* out, size_t cap) {
  if (cap < (size_t)plen + 8) return 0;
  out[0] = UBX_SYNC1; out[1] = UBX_SYNC2; out[2] = cls; out[3] = id; put_u16(out + 4, plen);
  if (plen) memcpy(out + 6, pl, plen);
  ubx_checksum(out + 2, 4 + (size_t)plen, out + 6 + plen, out + 7 + plen);
  return (size_t)plen + 8;
}

bool ubx_decode_nav_pvt(const uint8_t* p, size_t n, GnssSample* s) {
  if (n < UBX_NAV_PVT_LEN) return false;
  s->itow_ms = get_u32(p + 0); s->year = get_u16(p + 4); s->month = p[6]; s->day = p[7]; s->hour = p[8];
  s->min = p[9]; s->sec = p[10]; s->valid = p[11]; s->tacc_ns = get_u32(p + 12); s->nano = (int32_t)get_u32(p + 16);
  s->fix_type = p[20]; s->flags = p[21]; s->num_sv = p[23];
  s->lon_e7 = (int32_t)get_u32(p + 24); s->lat_e7 = (int32_t)get_u32(p + 28);
  s->height_mm = (int32_t)get_u32(p + 32); s->hmsl_mm = (int32_t)get_u32(p + 36);
  s->hacc_mm = get_u32(p + 40); s->vacc_mm = get_u32(p + 44);
  s->veln_mm_s = (int32_t)get_u32(p + 48); s->vele_mm_s = (int32_t)get_u32(p + 52); s->veld_mm_s = (int32_t)get_u32(p + 56);
  s->gspeed_mm_s = (int32_t)get_u32(p + 60); s->head_mot_e5 = (int32_t)get_u32(p + 64);
  s->sacc_mm_s = get_u32(p + 68); s->head_acc_e5 = get_u32(p + 72); s->pdop_e2 = get_u16(p + 76);
  s->flags3 = get_u16(p + 78);
  return true;
}

size_t ubx_encode_nav_pvt(const GnssSample& s, uint8_t* p, size_t cap) {
  if (cap < UBX_NAV_PVT_LEN) return 0;
  memset(p, 0, UBX_NAV_PVT_LEN);
  put_u32(p + 0, s.itow_ms); put_u16(p + 4, s.year); p[6] = s.month; p[7] = s.day; p[8] = s.hour; p[9] = s.min;
  p[10] = s.sec; p[11] = s.valid; put_u32(p + 12, s.tacc_ns); put_u32(p + 16, (uint32_t)s.nano);
  p[20] = s.fix_type; p[21] = s.flags; p[23] = s.num_sv; put_u32(p + 24, (uint32_t)s.lon_e7);
  put_u32(p + 28, (uint32_t)s.lat_e7); put_u32(p + 32, (uint32_t)s.height_mm); put_u32(p + 36, (uint32_t)s.hmsl_mm);
  put_u32(p + 40, s.hacc_mm); put_u32(p + 44, s.vacc_mm); put_u32(p + 48, (uint32_t)s.veln_mm_s);
  put_u32(p + 52, (uint32_t)s.vele_mm_s); put_u32(p + 56, (uint32_t)s.veld_mm_s);
  put_u32(p + 60, (uint32_t)s.gspeed_mm_s); put_u32(p + 64, (uint32_t)s.head_mot_e5);
  put_u32(p + 68, s.sacc_mm_s); put_u32(p + 72, s.head_acc_e5); put_u16(p + 76, s.pdop_e2); put_u16(p + 78, s.flags3);
  return UBX_NAV_PVT_LEN;
}

size_t rtcm_build(const uint8_t* pl, uint16_t plen, uint8_t* out, size_t cap) {
  if (plen > 1023 || cap < (size_t)plen + 6) return 0;
  out[0] = 0xD3; out[1] = (uint8_t)((plen >> 8) & 0x03); out[2] = (uint8_t)plen;
  if (plen) memcpy(out + 3, pl, plen);
  uint32_t c = crc24q(out, 3 + (size_t)plen);
  out[3 + plen] = (uint8_t)(c >> 16); out[4 + plen] = (uint8_t)(c >> 8); out[5 + plen] = (uint8_t)c;
  return (size_t)plen + 6;
}

void RtcmObserver::feed(const uint8_t* d, size_t n) {
  st_.bytes += (uint32_t)n;
  while (n) {
    size_t room = sizeof(buf_) - have_;
    size_t k = n < room ? n : room;
    memcpy(buf_ + have_, d, k);
    have_ += k; d += k; n -= k;
    scan();
  }
}

void RtcmObserver::scan() {
  size_t pos = 0;
  for (;;) {
    while (pos < have_ && buf_[pos] != 0xD3) { pos++; st_.garbage_bytes++; }
    if (have_ - pos < 3) break;
    const uint8_t* f = buf_ + pos;
    if (f[1] & 0xFC) { pos++; st_.garbage_bytes++; continue; }  // reserved bits must be 0
    uint16_t len = (uint16_t)(((f[1] & 0x03) << 8) | f[2]);
    size_t total = (size_t)len + 6;
    if (have_ - pos < total) {
      if (total > sizeof(buf_)) { pos++; st_.garbage_bytes++; continue; }
      break;
    }
    uint32_t c = crc24q(f, 3 + (size_t)len);
    uint32_t want = ((uint32_t)f[3 + len] << 16) | ((uint32_t)f[4 + len] << 8) | f[5 + len];
    if (c == want) {
      st_.frames_ok++;
      if (len >= 2) {
        uint16_t t = (uint16_t)((f[3] << 4) | (f[4] >> 4));
        st_.last_msg_type = t;
        if (t == 1005 || t == 1006) st_.ref_station_frames++;
        uint16_t m = t % 10;
        if (t >= 1070 && t <= 1137 && m >= 4 && m <= 7) st_.msm_frames++;
      }
      pos += total;
    } else {
      st_.frames_bad_crc++;
      pos++;
      st_.garbage_bytes++;
    }
  }
  if (pos) { memmove(buf_, buf_ + pos, have_ - pos); have_ -= pos; }
}

}  // namespace avo
