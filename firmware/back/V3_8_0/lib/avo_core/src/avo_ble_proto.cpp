#include "avo_ble_proto.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include <string.h>

namespace avo {

bool ble_frag_parse(const uint8_t* p, size_t n, BleFragView* v) {
  if (n < BLE_FRAG_OVERHEAD) return false;
  if (crc16_ccitt(p, n - 2) != get_u16(p + n - 2)) return false;
  v->ver = p[0];
  v->type = (BleMsg)p[1];
  v->msg_id = get_u16(p + 2);
  v->frag_idx = get_u16(p + 4);
  v->frag_cnt = get_u16(p + 6);
  v->flags = p[8];
  v->status = p[9];
  v->payload = p + BLE_FRAG_HDR;
  v->len = n - BLE_FRAG_OVERHEAD;
  if (v->ver == 0 || v->frag_cnt == 0 || v->frag_idx >= v->frag_cnt) return false;
  return true;
}

size_t ble_frag_build(BleMsg type, uint16_t id, uint16_t idx, uint16_t cnt, uint8_t flags, uint8_t status,
                      const uint8_t* pl, size_t len, uint8_t* out, size_t cap) {
  size_t total = len + BLE_FRAG_OVERHEAD;
  if (total > cap || cnt == 0 || idx >= cnt) return 0;
  out[0] = BLE_PROTO_VERSION; out[1] = (uint8_t)type; put_u16(out + 2, id); put_u16(out + 4, idx);
  put_u16(out + 6, cnt); out[8] = flags; out[9] = status;
  if (len) memcpy(out + BLE_FRAG_HDR, pl, len);
  put_u16(out + BLE_FRAG_HDR + len, crc16_ccitt(out, BLE_FRAG_HDR + len));
  return total;
}

uint16_t ble_frag_count(size_t len, size_t att) {
  if (att <= BLE_FRAG_OVERHEAD) return 0;
  size_t per = att - BLE_FRAG_OVERHEAD;
  size_t c = (len + per - 1) / per;
  return (uint16_t)(c ? c : 1);
}

bool BleReassembler::seen(uint16_t id) const {
  for (uint8_t i = 0; i < done_n_; i++) if (done_[i] == id) return true;
  return false;
}

void BleReassembler::remember(uint16_t id) {
  done_[done_i_] = id;
  done_i_ = (uint8_t)((done_i_ + 1) % 32);
  if (done_n_ < 32) done_n_++;
}

void BleReassembler::reset() {
  for (auto& s : s_) s.used = false;
  done_n_ = done_i_ = 0;
}

void BleReassembler::expire(uint32_t now, uint32_t timeout) {
  for (auto& s : s_) if (s.used && now - s.t > timeout) { s.used = false; errs_++; }
}

BleReassembler::Result BleReassembler::feed(const BleFragView& f, uint32_t now, const uint8_t** msg, size_t* len, BleStatus* err) {
  *err = BleStatus::OK;
  if (seen(f.msg_id) && f.frag_idx == 0) { dups_++; *err = BleStatus::DUPLICATE; return DUPLICATE; }
  Slot* s = nullptr;
  for (auto& x : s_) if (x.used && x.id == f.msg_id && x.type == f.type) s = &x;
  if (!s) {
    if (f.frag_idx != 0) { errs_++; *err = BleStatus::BAD_FORMAT; return ERROR; }
    for (auto& x : s_) if (!x.used) { s = &x; break; }
    if (!s) {  // evict the oldest incomplete message
      s = &s_[0];
      if (s_[1].t < s_[0].t) s = &s_[1];
      errs_++;
    }
    s->used = true; s->id = f.msg_id; s->cnt = f.frag_cnt; s->next = 0; s->len = 0; s->type = f.type;
  }
  s->t = now;
  if (f.frag_cnt != s->cnt) { s->used = false; errs_++; *err = BleStatus::BAD_FORMAT; return ERROR; }
  if (f.frag_idx < s->next) { dups_++; *err = BleStatus::DUPLICATE; return DUPLICATE; }  // retransmitted fragment
  if (f.frag_idx != s->next) { s->used = false; errs_++; *err = BleStatus::BAD_FORMAT; return ERROR; }  // gap
  if (s->len + f.len > BLE_MAX_MSG) { s->used = false; errs_++; *err = BleStatus::TOO_LARGE; return ERROR; }
  if (f.len) memcpy(s->buf + s->len, f.payload, f.len);
  s->len += f.len;
  s->next++;
  if (s->next < s->cnt) return NEED_MORE;
  s->used = false;
  remember(s->id);
  *msg = s->buf;
  *len = s->len;
  return COMPLETE;
}

}  // namespace avo

namespace avo {
size_t encode_telemetry(const Telemetry& t, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u8(t.session_state); w.u8(t.gf_state); w.u8(t.rec_status); w.u8(t.fix_type); w.u8(t.carr_soln); w.u8(t.num_sv);
  w.u32(t.hacc_mm); w.i32(t.lat_e7); w.i32(t.lon_e7); w.i32(t.gspeed_mm_s); w.u32(t.distance_cm); w.u32(t.active_ms);
  w.i8(t.batt_pct); w.u8(t.link_connected); w.u8(t.girth_connected); w.u8(t.rtcm_flowing); w.u16(t.ring_fill_permille);
  w.u32(t.dropped_records); w.u32(t.pending_ms); w.u8(t.inhibited);
  w.u8(t.gnss_flags); w.u8(t.corr_age_code); w.u8(t.sd_mounted); w.u8(t.pps_state); w.u16(t.back_batt_mv);
  w.u8(t.time_source); w.u8(t.back_status_valid); w.u32(t.rtcm_to_back_bytes); w.u32(t.rxm_rtcm_used);
  w.u8(t.power_level); w.u8(t.vbus); w.u16(t.batt_mv); w.u32(t.gnss_age_ms); w.u32(t.vacc_mm); w.u32(t.link_age_ms);
  w.u8(t.manual); w.u8(t.girth_present); w.u32(t.girth_lost);
  return w.ok() ? w.size() : 0;
}
}  // namespace avo
