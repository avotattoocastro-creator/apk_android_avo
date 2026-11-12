#include "avo_payloads.h"
#include "avo_bytes.h"
#include <string.h>

namespace avo {

size_t encode_gnss(const GnssSample& s, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u32(s.itow_ms); w.u16(s.year); w.u8(s.month); w.u8(s.day); w.u8(s.hour); w.u8(s.min); w.u8(s.sec);
  w.u8(s.valid); w.i32(s.nano); w.u32(s.tacc_ns); w.u8(s.fix_type); w.u8(s.flags); w.u16(s.flags3);
  w.u8(s.num_sv); w.i32(s.lon_e7); w.i32(s.lat_e7); w.i32(s.height_mm); w.i32(s.hmsl_mm);
  w.u32(s.hacc_mm); w.u32(s.vacc_mm); w.i32(s.veln_mm_s); w.i32(s.vele_mm_s); w.i32(s.veld_mm_s);
  w.i32(s.gspeed_mm_s); w.i32(s.head_mot_e5); w.u32(s.sacc_mm_s); w.u32(s.head_acc_e5); w.u16(s.pdop_e2);
  w.u32(s.back_rx_ms); w.u8(s.pps_locked); w.u8(s.nav_rate_hz);
  return w.ok() ? w.size() : 0;
}

bool decode_gnss(const uint8_t* p, size_t n, GnssSample* s) {
  if (n < GNSS_SAMPLE_V1_LEN) return false;
  ByteReader r(p, n);
  s->itow_ms = r.u32(); s->year = r.u16(); s->month = r.u8(); s->day = r.u8(); s->hour = r.u8();
  s->min = r.u8(); s->sec = r.u8(); s->valid = r.u8(); s->nano = r.i32(); s->tacc_ns = r.u32();
  s->fix_type = r.u8(); s->flags = r.u8(); s->flags3 = r.u16(); s->num_sv = r.u8();
  s->lon_e7 = r.i32(); s->lat_e7 = r.i32(); s->height_mm = r.i32(); s->hmsl_mm = r.i32();
  s->hacc_mm = r.u32(); s->vacc_mm = r.u32(); s->veln_mm_s = r.i32(); s->vele_mm_s = r.i32();
  s->veld_mm_s = r.i32(); s->gspeed_mm_s = r.i32(); s->head_mot_e5 = r.i32(); s->sacc_mm_s = r.u32();
  s->head_acc_e5 = r.u32(); s->pdop_e2 = r.u16(); s->back_rx_ms = r.u32(); s->pps_locked = r.u8();
  s->nav_rate_hz = r.u8();
  return r.ok();
}

uint32_t corr_age_code_to_max_ms(uint8_t code) {
  // UBX-NAV-PVT flags3.lastCorrectionAge (u-blox interface description, F9 HPG)
  static const uint32_t t[16] = {0, 1000, 2000, 5000, 10000, 15000, 20000, 30000, 45000, 60000,
                                 90000, 120000, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu, 0xFFFFFFFFu};
  return t[code & 0x0F];
}

size_t encode_imu_header(const ImuBatchHeader& h, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u8(h.girth_id); w.u8(h.imu_id); w.u8(h.count); w.u8(h.fmt); w.u32(h.girth_seq);
  w.u32(h.girth_t0_us); w.u16(h.period_us); w.u8(h.sync_state); w.u8(h.reserved);
  w.u32(h.back_rx_ms); w.i32(h.girth_to_back_us);
  return w.ok() ? w.size() : 0;
}

bool decode_imu_header(const uint8_t* p, size_t n, ImuBatchHeader* h) {
  if (n < IMU_HDR_LEN) return false;
  ByteReader r(p, n);
  h->girth_id = r.u8(); h->imu_id = r.u8(); h->count = r.u8(); h->fmt = r.u8(); h->girth_seq = r.u32();
  h->girth_t0_us = r.u32(); h->period_us = r.u16(); h->sync_state = r.u8(); h->reserved = r.u8();
  h->back_rx_ms = r.u32(); h->girth_to_back_us = r.i32();
  if (!r.ok()) return false;
  if (h->fmt != IMU_FMT_9AXIS_I16) return true;  // unknown format: header valid, samples opaque
  if (h->count > IMU_MAX_SAMPLES) return false;
  return n >= IMU_HDR_LEN + (size_t)h->count * IMU_SAMPLE_LEN_9AXIS;
}

size_t encode_timesync(const TimeSync& t, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u64(t.back_us_at_pps); w.u32(t.tow_ms_at_pps); w.u16(t.gps_week); w.u8(t.flags); w.i8(t.leap_s);
  w.u32(t.pps_jitter_ns); w.u32(t.pps_count);
  return w.ok() ? w.size() : 0;
}

bool decode_timesync(const uint8_t* p, size_t n, TimeSync* t) {
  if (n < TIME_SYNC_V1_LEN) return false;
  ByteReader r(p, n);
  t->back_us_at_pps = r.u64(); t->tow_ms_at_pps = r.u32(); t->gps_week = r.u16(); t->flags = r.u8();
  t->leap_s = r.i8(); t->pps_jitter_ns = r.u32(); t->pps_count = r.u32();
  return r.ok();
}

size_t encode_status(const BackStatus& s, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u32(s.uptime_ms); w.u8(s.zed_state); w.u8(s.pps_state); w.u8(s.girth_connected); w.i8(s.girth_rssi);
  w.u32(s.pps_count); w.u32(s.rtcm_rx_bytes); w.u32(s.rtcm_to_zed_bytes); w.u32(s.rtcm_frames_ok);
  w.u32(s.rtcm_frames_bad); w.u32(s.rxm_rtcm_used); w.u32(s.rxm_rtcm_failed); w.u32(s.girth_pkts);
  w.u32(s.girth_lost); w.u32(s.uart_crc_err); w.u16(s.back_batt_mv); w.u16(s.gnss_rate_hz_x10);
  if (s.v2) {
    w.u32(s.zed_baud); w.u8(s.zed_port); w.u8(s.zed_cfg); w.u8(s.nav_rate_cfg_hz); w.u8(s.zed_detail);
    w.u32(s.rtcm_gaps_bytes); w.u32(s.rtcm_not_written); w.u32(s.link_tx_fail); w.i8(s.link_rssi); w.u8(0);
    w.u32(s.ubx_frames); w.u32(s.nmea_sentences);
    if (s.v3) {
      w.u8(s.sv_tracked); w.u8(s.sv_used); w.u8(s.sig_tracked); w.u8(s.sig_used); w.u8(s.sig_cr_used); w.u8(s.sig_corr);
      w.u8(s.sig_l2); w.u8(s.sig_l2_used); w.u8(s.sig_weak); w.u8(s.cno_mean); w.u8(s.cno_min); w.u8(s.cno_max);
      w.u8(s.quality_age_s); w.u8(s.quality_mon); w.u16(s.fix_lost); w.u16(s.ttff_fix_s); w.u32(s.fixed_ms); w.u32(s.float_ms);
    }
  }
  return w.ok() ? w.size() : 0;
}

bool decode_status(const uint8_t* p, size_t n, BackStatus* s) {
  if (n < BACK_STATUS_V1_LEN) return false;
  ByteReader r(p, n);
  s->uptime_ms = r.u32(); s->zed_state = r.u8(); s->pps_state = r.u8(); s->girth_connected = r.u8();
  s->girth_rssi = r.i8(); s->pps_count = r.u32(); s->rtcm_rx_bytes = r.u32(); s->rtcm_to_zed_bytes = r.u32();
  s->rtcm_frames_ok = r.u32(); s->rtcm_frames_bad = r.u32(); s->rxm_rtcm_used = r.u32();
  s->rxm_rtcm_failed = r.u32(); s->girth_pkts = r.u32(); s->girth_lost = r.u32(); s->uart_crc_err = r.u32();
  s->back_batt_mv = r.u16(); s->gnss_rate_hz_x10 = r.u16();
  if (!r.ok()) return false;
  s->v2 = false;
  if (r.remaining() >= BACK_STATUS_V2_LEN - BACK_STATUS_V1_LEN) {
    s->zed_baud = r.u32(); s->zed_port = r.u8(); s->zed_cfg = r.u8(); s->nav_rate_cfg_hz = r.u8(); s->zed_detail = r.u8();
    s->rtcm_gaps_bytes = r.u32(); s->rtcm_not_written = r.u32(); s->link_tx_fail = r.u32(); s->link_rssi = r.i8(); r.u8();
    s->ubx_frames = r.u32(); s->nmea_sentences = r.u32();
    s->v2 = r.ok();
  }
  s->v3 = false;
  if (s->v2 && r.remaining() >= BACK_STATUS_V3_LEN - BACK_STATUS_V2_LEN) {
    s->sv_tracked = r.u8(); s->sv_used = r.u8(); s->sig_tracked = r.u8(); s->sig_used = r.u8(); s->sig_cr_used = r.u8();
    s->sig_corr = r.u8(); s->sig_l2 = r.u8(); s->sig_l2_used = r.u8(); s->sig_weak = r.u8(); s->cno_mean = r.u8();
    s->cno_min = r.u8(); s->cno_max = r.u8(); s->quality_age_s = r.u8(); s->quality_mon = r.u8();
    s->fix_lost = r.u16(); s->ttff_fix_s = r.u16(); s->fixed_ms = r.u32(); s->float_ms = r.u32();
    s->v3 = r.ok();
  }
  return true;
}

size_t encode_caps(const Caps& c, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u8(c.proto_min); w.u8(c.proto_max); w.u8(c.node_type); w.u8(c.hw_rev); w.str(c.fw_version, 16);
  w.u32(c.caps); w.u16(c.max_payload); w.u32(c.uart_baud); w.u8(c.gnss_rate_hz);
  w.u8(c.gnss_constellations); w.u16(c.imu_rate_hz);
  return w.ok() ? w.size() : 0;
}

bool decode_caps(const uint8_t* p, size_t n, Caps* c) {
  if (n < CAPS_V1_LEN) return false;
  ByteReader r(p, n);
  c->proto_min = r.u8(); c->proto_max = r.u8(); c->node_type = r.u8(); c->hw_rev = r.u8();
  r.str(c->fw_version, 16); c->caps = r.u32(); c->max_payload = r.u16(); c->uart_baud = r.u32();
  c->gnss_rate_hz = r.u8(); c->gnss_constellations = r.u8(); c->imu_rate_hz = r.u16();
  return r.ok() && c->proto_min <= c->proto_max;
}

uint8_t negotiate_version(const Caps& a, const Caps& b) {
  uint8_t lo = a.proto_min > b.proto_min ? a.proto_min : b.proto_min;
  uint8_t hi = a.proto_max < b.proto_max ? a.proto_max : b.proto_max;
  return lo <= hi ? hi : 0;
}

size_t encode_event(const EventMsg& e, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u16(e.code); w.u8(e.severity); w.u8(0); w.u32(e.arg0); w.u32(e.arg1); w.str(e.text, 24);
  return w.ok() ? w.size() : 0;
}

bool decode_event(const uint8_t* p, size_t n, EventMsg* e) {
  if (n < EVENT_V1_LEN) return false;
  ByteReader r(p, n);
  e->code = r.u16(); e->severity = r.u8(); r.u8(); e->arg0 = r.u32(); e->arg1 = r.u32(); r.str(e->text, 24);
  return r.ok();
}

size_t encode_command(const Command& c, uint8_t* out, size_t cap) {
  if (c.arg_len > sizeof(c.args)) return 0;
  ByteWriter w(out, cap);
  w.u16(c.cmd); w.u16(c.cmd_id); w.u8(c.arg_len); w.bytes(c.args, c.arg_len);
  return w.ok() ? w.size() : 0;
}

bool decode_command(const uint8_t* p, size_t n, Command* c) {
  if (n < 5) return false;
  ByteReader r(p, n);
  c->cmd = r.u16(); c->cmd_id = r.u16(); c->arg_len = r.u8();
  if (c->arg_len > sizeof(c->args)) return false;
  r.bytes(c->args, c->arg_len);
  return r.ok();
}

size_t encode_ack(const Ack& a, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u8(a.acked_type); w.u16(a.acked_seq); w.u16(a.cmd_id); w.u8(a.status); w.u16(a.detail);
  return w.ok() ? w.size() : 0;
}

bool decode_ack(const uint8_t* p, size_t n, Ack* a) {
  if (n < ACK_V1_LEN) return false;
  ByteReader r(p, n);
  a->acked_type = r.u8(); a->acked_seq = r.u16(); a->cmd_id = r.u16(); a->status = r.u8(); a->detail = r.u16();
  return r.ok();
}

size_t encode_heartbeat(const Heartbeat& h, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u32(h.uptime_ms); w.u8(h.state); w.u8(h.cpu_load_pct); w.u16(h.queue_fill_pct_x10);
  return w.ok() ? w.size() : 0;
}

bool decode_heartbeat(const uint8_t* p, size_t n, Heartbeat* h) {
  if (n < HEARTBEAT_V1_LEN) return false;
  ByteReader r(p, n);
  h->uptime_ms = r.u32(); h->state = r.u8(); h->cpu_load_pct = r.u8(); h->queue_fill_pct_x10 = r.u16();
  return r.ok();
}

}  // namespace avo
