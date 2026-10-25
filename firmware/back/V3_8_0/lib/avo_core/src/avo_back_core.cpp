#include "avo_back_core.h"
#include "avo_bytes.h"
#include "avo_version.h"
#include <string.h>

namespace avo {

// 8 Hz: maximum RTK rate of the ZED-F9P with all four constellations (data sheet, table 1).
static const uint8_t BACK_NAV_RATE_DEFAULT = 8;

BackCore::BackCore(BackPlatform* p, const char* dev_id, uint8_t nav_rate_hz)
    : p_(p), pair_(NowRole::BACK), dec_(on_chest_frame, this), zed_(this, nav_rate_hz ? nav_rate_hz : BACK_NAV_RATE_DEFAULT) {
  memset(dev_, 0, sizeof(dev_));
  strncpy(dev_, dev_id ? dev_id : "", sizeof(dev_) - 1);
  boot_id_ = 0;
}

void BackCore::begin(const NowPeerRecord& stored) {
  boot_id_ = p_->random32() | 1u;
  pair_.load(stored);
  if (stored.valid) p_->radio_set_peer(stored.mac);
  zed_.set_ubx_cb(on_ubx, this);
  zed_.begin(p_->now_ms());
}

bool BackCore::chest_online() const {
  return st_.last_chest_rx_ms && (uint32_t)(p_->now_ms() - st_.last_chest_rx_ms) < 3000;
}

// ------------------------------------------------------------------ radio in
void BackCore::on_radio(const uint8_t mac[6], const uint8_t* d, size_t n, int8_t rssi) {
  NowHeader h;
  const uint8_t* body;
  if (!now_parse(d, n, &h, &body)) { st_.rx_bad++; return; }
  uint32_t now = p_->now_ms();
  if (h.kind == NowKind::PAIR_REQ) {
    NowPairMsg m;
    if (!now_pair_decode(body, h.body_len, &m)) { st_.rx_bad++; return; }
    if (!pair_.back_on_req(mac, h, m, now, st_.last_chest_rx_ms)) { st_.rx_foreign++; return; }
    p_->save_peer(pair_.peer());
    p_->radio_set_peer(mac);
    st_.pairings++;
    st_.last_chest_rx_ms = now;
    have_off_ = false;
    // Answer with the chest's nonce so it knows this ACK is for its request.
    NowPairMsg a;
    a.role = NowRole::BACK;
    a.nonce = m.nonce;
    strncpy(a.dev_id, dev_, sizeof(a.dev_id) - 1);
    strncpy(a.fw, AVO_FW_VERSION, sizeof(a.fw) - 1);
    uint8_t b[NOW_PAIR_BODY], pkt[NOW_MAX_PACKET];
    size_t bl = now_pair_encode(a, b, sizeof(b));
    NowHeader ah; ah.kind = NowKind::PAIR_ACK; ah.pair_id = h.pair_id; ah.boot_id = boot_id_;
    size_t pl = now_build(ah, b, bl, pkt, sizeof(pkt));
    for (int i = 0; i < 3; i++) if (p_->radio_send(pair_.peer().mac, pkt, pl)) break;
    caps_sent_ = false;
    return;
  }
  if (h.kind != NowKind::DATA) return;
  if (!pair_.accept_data(mac, h.pair_id)) { st_.rx_foreign++; return; }
  st_.rx_packets++;
  st_.rssi = rssi;
  st_.last_chest_rx_ms = now;
  if (guard_.changed(h.boot_id)) {   // chest rebooted: new frame sequence and RTCM stream offsets
    dec_ = UartDecoder(on_chest_frame, this);
    have_off_ = false;
    caps_sent_ = false;
  }
  dec_.feed(body, h.body_len);
}

void BackCore::on_chest_frame(const FrameView& f, void* ctx) { ((BackCore*)ctx)->chest_frame(f); }

void BackCore::chest_frame(const FrameView& f) {
  switch (f.type) {
    case FrameType::RTCM_DATA:
      rtcm_data(f.payload, f.len);
      break;
    case FrameType::COMMAND: {
      Command c;
      if (!decode_command(f.payload, f.len, &c)) break;
      bool done = false;
      for (uint8_t i = 0; i < done_n_; i++) if (done_cmd_[i] == c.cmd_id) done = true;
      bool ok = true;
      if (!done) {
        switch ((BackCmd)c.cmd) {
          case BackCmd::REQ_CAPS: caps_sent_ = false; break;
          case BackCmd::REQ_STATUS: last_status_ = 0; break;
          case BackCmd::SET_GNSS_RATE: if (c.arg_len >= 1 && c.args[0] >= 1 && c.args[0] <= 25) zed_.set_nav_rate(c.args[0], p_->now_ms()); else ok = false; break;
          case BackCmd::REBOOT: break;
          default: ok = false; break;   // girth commands: no girth on this back
        }
        done_cmd_[done_n_ % 8] = c.cmd_id;
        if (done_n_ < 8) done_n_++;
      }
      send_ack(f.type, f, c.cmd_id, ok ? 0 : 1, !ok);
      if (!done && ok && (BackCmd)c.cmd == BackCmd::REBOOT) { flush(); p_->reboot(); }
      break;
    }
    case FrameType::CAPS:
      if (!caps_sent_) send_caps();
      break;
    default:   // HEARTBEAT and others only keep the link alive
      break;
  }
}

void BackCore::rtcm_data(const uint8_t* pl, size_t len) {
  if (len < RTCM_DATA_HDR) return;
  uint32_t off = get_u32(pl);
  const uint8_t* d = pl + RTCM_DATA_HDR;
  size_t n = len - RTCM_DATA_HDR;
  st_.rtcm_rx_bytes += (uint32_t)n;
  if (have_off_) {
    int32_t delta = (int32_t)(off - exp_off_);
    if (delta > 0) st_.rtcm_gaps += (uint32_t)delta;          // bytes the chest could not deliver
    else if (delta < 0) {                                         // already written: skip the overlap
      uint32_t over = (uint32_t)(-delta);
      if (over >= n) { st_.rtcm_dup_bytes += (uint32_t)n; return; }
      d += over; n -= over; off += over; st_.rtcm_dup_bytes += over;
    }
  }
  have_off_ = true;
  exp_off_ = off + (uint32_t)n;
  if (!zed_.rtcm_write_ok()) { st_.rtcm_not_written += (uint32_t)n; return; }
  p_->zed_write(d, n);
  obs_.feed(d, n);
  st_.rtcm_to_zed += (uint32_t)n;
}

// ------------------------------------------------------------------ ZED in
void BackCore::on_zed(const uint8_t* d, size_t n) { zed_.feed(d, n, p_->now_ms()); }

void BackCore::on_ubx(uint8_t cls, uint8_t id, const uint8_t* pl, uint16_t plen, void* ctx) { ((BackCore*)ctx)->ubx(cls, id, pl, plen); }

void BackCore::ubx(uint8_t cls, uint8_t id, const uint8_t* pl, uint16_t plen) {
  uint32_t now = p_->now_ms();
  if (cls == UBX_CLS_NAV && id == UBX_ID_NAV_PVT) {
    GnssSample g;
    if (!ubx_decode_nav_pvt(pl, plen, &g)) return;
    st_.nav_pvt++;
    rate_n_++;
    g.back_rx_ms = now;
    {  // V3.9.0: RTK FIX tracking (time in FIX/FLOAT, FIX losses, time to first FIX)
      uint8_t carr = g.carr_soln();
      if (last_pvt_ms_ && now - last_pvt_ms_ < 2000) {
        if (last_carr_ == 2) fixed_ms_ += now - last_pvt_ms_;
        else if (last_carr_ == 1) float_ms_ += now - last_pvt_ms_;
      }
      if (last_carr_ == 2 && carr != 2 && fix_lost_ < 0xFFFF) fix_lost_++;
      if (carr == 2 && ttff_fix_s_ == 0xFFFF) ttff_fix_s_ = (uint16_t)(now / 1000 > 0xFFFE ? 0xFFFE : now / 1000);
      last_carr_ = carr;
      last_pvt_ms_ = now;
    }
    g.pps_locked = 0;
    g.nav_rate_hz = zed_.rate_applied() ? zed_.nav_rate() : (uint8_t)((rate_x10_ + 5) / 10);
    uint8_t b[GNSS_SAMPLE_V1_LEN + 8];
    size_t n = encode_gnss(g, b, sizeof(b));
    if (n && pair_.paired() && chest_online()) { queue_frame(FrameType::GNSS_SAMPLE, 0, b, n, true); st_.gnss_sent++; }   // position: send at once
  } else if (cls == UBX_CLS_NAV && id == UBX_ID_NAV_SAT) {
    ubx_quality_nav_sat(pl, plen, &q_);
  } else if (cls == UBX_CLS_NAV && id == UBX_ID_NAV_SIG) {
    if (ubx_quality_nav_sig(pl, plen, &q_)) q_ms_ = now | 1;
  } else if (cls == UBX_CLS_RXM && id == UBX_ID_RXM_RTCM) {
    RxmRtcm r;
    if (ubx_decode_rxm_rtcm(pl, plen, &r)) {
      if (r.msg_used == 2 && !r.crc_failed) st_.rxm_used++;
      else if (r.crc_failed || r.msg_used == 1) st_.rxm_failed++;
    }
  }
}

// ------------------------------------------------------------------ radio out
void BackCore::queue_frame(FrameType t, uint8_t flags, const uint8_t* pl, size_t len, bool flush_now) {
  uint8_t f[NOW_MAX_BODY];
  size_t n = uart_encode(t, flags, (uint8_t)NodeId::BACK, seq_++, p_->now_ms(), pl, len, f, sizeof(f));
  if (!n) return;
  if (!pk_.fits(n)) flush();
  pk_.add(f, n);
  if (flush_now) flush();
}

void BackCore::flush() {
  if (pk_.empty()) return;
  if (!pair_.paired()) { pk_.clear(); return; }
  NowHeader h;
  h.kind = NowKind::DATA;
  h.pair_id = pair_.peer().pair_id;
  h.boot_id = boot_id_;
  uint8_t pkt[NOW_MAX_PACKET];
  size_t n = now_build(h, pk_.data(), pk_.size(), pkt, sizeof(pkt));
  pk_.clear();
  if (!n) return;
  // While the chest is not heard, one attempt only (keeps the loop responsive).
  int attempts = chest_online() ? 3 : 1;
  bool ok = false;
  for (int i = 0; i < attempts && !ok; i++) {
    if (i) st_.tx_retries++;
    ok = p_->radio_send(pair_.peer().mac, pkt, n);
  }
  if (ok) st_.tx_packets++;
  else st_.tx_fail++;
}

void BackCore::send_ack(FrameType t, const FrameView& f, uint16_t cmd_id, uint8_t status, bool nack) {
  Ack a;
  a.acked_type = (uint8_t)t;
  a.acked_seq = f.seq;
  a.cmd_id = cmd_id;
  a.status = status;
  uint8_t b[ACK_V1_LEN];
  if (encode_ack(a, b, sizeof(b))) queue_frame(nack ? FrameType::NACK : FrameType::ACK, 0, b, ACK_V1_LEN, true);
}

BackStatus BackCore::status() const {
  BackStatus s;
  s.uptime_ms = p_->now_ms();
  s.zed_state = zed_.status_code();
  s.pps_state = 0;          // PPS not wired on this back
  s.girth_connected = 0;    // no girth IMU on this back
  s.rtcm_rx_bytes = st_.rtcm_rx_bytes;
  s.rtcm_to_zed_bytes = st_.rtcm_to_zed;
  s.rtcm_frames_ok = obs_.stats().frames_ok;
  s.rtcm_frames_bad = obs_.stats().frames_bad_crc;
  s.rxm_rtcm_used = st_.rxm_used;
  s.rxm_rtcm_failed = st_.rxm_failed;
  s.uart_crc_err = dec_.stats().crc_err + dec_.stats().hdr_crc_err;
  s.back_batt_mv = batt_mv_;   // V3.8.1: measured by the platform (0 = unknown)
  s.gnss_rate_hz_x10 = rate_x10_;
  s.v2 = true;
  s.zed_baud = zed_.baud();
  s.zed_port = zed_.port();
  s.zed_cfg = (uint8_t)((zed_.config_acked() ? 1 : 0) | (zed_.rate_applied() ? 2 : 0));
  s.nav_rate_cfg_hz = zed_.nav_rate();
  s.zed_detail = (uint8_t)(zed_.state() == ZedManager::TUNE ? ZedManager::CONFIGURE : zed_.state());   // chest knows states 0..4
  s.rtcm_gaps_bytes = st_.rtcm_gaps;
  s.rtcm_not_written = st_.rtcm_not_written;
  s.link_tx_fail = st_.tx_fail;
  s.link_rssi = st_.rssi;
  s.ubx_frames = zed_.stream().frames();
  s.nmea_sentences = zed_.stream().nmea_sentences();
  s.v3 = true;
  s.sv_tracked = q_.sv_tracked; s.sv_used = q_.sv_used;
  s.sig_tracked = q_.sig_tracked; s.sig_used = q_.sig_used; s.sig_cr_used = q_.sig_cr_used; s.sig_corr = q_.sig_corr;
  s.sig_l2 = q_.sig_l2; s.sig_l2_used = q_.sig_l2_used; s.sig_weak = q_.sig_weak;
  s.cno_mean = q_.cno_mean; s.cno_min = q_.cno_min; s.cno_max = q_.cno_max;
  uint32_t qa = q_ms_ ? (p_->now_ms() - q_ms_) / 1000 : 255;
  s.quality_age_s = (uint8_t)(qa > 254 ? 255 : qa);
  s.quality_mon = zed_.monitor_state();
  s.fix_lost = fix_lost_; s.ttff_fix_s = ttff_fix_s_; s.fixed_ms = fixed_ms_; s.float_ms = float_ms_;
  return s;
}

void BackCore::send_status() {
  BackStatus s = status();
  uint8_t b[BACK_STATUS_V3_LEN + 8];
  size_t n = encode_status(s, b, sizeof(b));
  if (n) queue_frame(FrameType::STATUS, 0, b, n, false);
}

void BackCore::send_caps() {
  Caps c;
  c.node_type = (uint8_t)NodeId::BACK;
  strncpy(c.fw_version, AVO_FW_VERSION, sizeof(c.fw_version) - 1);
  c.caps = CAP_GNSS_SAMPLE | CAP_RTCM_IN | CAP_RXM_RTCM | CAP_ACK;
  c.max_payload = (uint16_t)(NOW_MAX_BODY - AVO_UART_HDR - AVO_UART_TRAILER);
  c.uart_baud = zed_.baud();
  c.gnss_rate_hz = zed_.nav_rate();
  uint8_t b[CAPS_V1_LEN + 8];
  size_t n = encode_caps(c, b, sizeof(b));
  if (n) { queue_frame(FrameType::CAPS, 0, b, n, false); caps_sent_ = true; }
}

void BackCore::tick() {
  uint32_t now = p_->now_ms();
  zed_.tick(now);
  if (rate_t0_ == 0) rate_t0_ = now;
  if (now - rate_t0_ >= 2000) {
    rate_x10_ = (uint16_t)((rate_n_ * 10000u) / (now - rate_t0_));
    rate_n_ = 0;
    rate_t0_ = now;
  }
  if (!pair_.paired()) return;
  if (now - last_hb_ >= 1000) {
    last_hb_ = now;
    Heartbeat hb;
    hb.uptime_ms = now;
    hb.state = zed_.status_code();
    uint8_t b[HEARTBEAT_V1_LEN];
    if (encode_heartbeat(hb, b, sizeof(b))) queue_frame(FrameType::HEARTBEAT, 0, b, HEARTBEAT_V1_LEN, false);
  }
  if (now - last_status_ >= 1000) { last_status_ = now; send_status(); }
  if (!caps_sent_ || now - last_caps_ >= 30000) { last_caps_ = now; send_caps(); }
  flush();
}

}  // namespace avo
