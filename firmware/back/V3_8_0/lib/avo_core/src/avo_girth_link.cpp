#include "avo_girth_link.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include "avo_payloads.h"

namespace avo {

size_t girth_build(const GirthHeader& h, const uint8_t* body, size_t body_len, uint8_t* out, size_t cap) {
  if (body_len > GIRTH_MAX_BODY || cap < GIRTH_HDR + body_len) return 0;
  out[0] = GIRTH_MAGIC0; out[1] = GIRTH_MAGIC1; out[2] = GIRTH_LINK_VERSION; out[3] = (uint8_t)h.kind;
  put_u32(out + 4, h.boot_id); put_u32(out + 8, h.seq); put_u16(out + 12, (uint16_t)body_len);
  if (body_len) memcpy(out + GIRTH_HDR, body, body_len);
  uint16_t c = crc16_ccitt(out, 14);
  if (body_len) c = crc16_ccitt(out + GIRTH_HDR, body_len, c);
  put_u16(out + 14, c);
  return GIRTH_HDR + body_len;
}

bool girth_parse(const uint8_t* p, size_t n, GirthHeader* h, const uint8_t** body) {
  if (n < GIRTH_HDR || p[0] != GIRTH_MAGIC0 || p[1] != GIRTH_MAGIC1 || p[2] != GIRTH_LINK_VERSION) return false;
  uint16_t len = get_u16(p + 12);
  if ((size_t)len + GIRTH_HDR != n) return false;
  uint16_t c = crc16_ccitt(p, 14);
  if (len) c = crc16_ccitt(p + GIRTH_HDR, len, c);
  if (c != get_u16(p + 14)) return false;
  h->kind = (GirthKind)p[3]; h->boot_id = get_u32(p + 4); h->seq = get_u32(p + 8); h->body_len = len;
  *body = p + GIRTH_HDR;
  return true;
}

size_t girth_hello_encode(const GirthHello& m, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.str(m.dev_id, 16); w.str(m.fw, 16); w.u8(m.hw); w.u8(m.imu_count);
  return w.ok() ? w.size() : 0;
}

bool girth_hello_decode(const uint8_t* p, size_t n, GirthHello* m) {
  if (n < GIRTH_HELLO_LEN) return false;
  memcpy(m->dev_id, p, 16); m->dev_id[15] = 0;
  memcpy(m->fw, p + 16, 16); m->fw[15] = 0;
  m->hw = p[32]; m->imu_count = p[33];
  return true;
}

size_t girth_status_encode(const GirthStatus& s, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u32(s.uptime_ms); w.u16(s.batt_mv); w.u8(s.imu_mask); w.u8(s.imu_count); w.i8(s.rssi_back);
  w.u32(s.tx_ok); w.u32(s.tx_fail); w.u32(s.imu_batches); w.u32(s.pings_rx);
  return w.ok() ? w.size() : 0;
}

bool girth_status_decode(const uint8_t* p, size_t n, GirthStatus* s) {
  if (n < GIRTH_STATUS_LEN) return false;
  ByteReader r(p, n);
  s->uptime_ms = r.u32(); s->batt_mv = r.u16(); s->imu_mask = r.u8(); s->imu_count = r.u8(); s->rssi_back = r.i8();
  s->tx_ok = r.u32(); s->tx_fail = r.u32(); s->imu_batches = r.u32(); s->pings_rx = r.u32();
  return r.ok();
}

size_t girth_ping_encode(const GirthPing& g, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u8(g.flags); w.i8(g.rssi_girth); w.u32(g.rx_packets); w.u32(g.lost);
  return w.ok() ? w.size() : 0;
}

bool girth_ping_decode(const uint8_t* p, size_t n, GirthPing* g) {
  if (n < GIRTH_PING_LEN) return false;
  ByteReader r(p, n);
  g->flags = r.u8(); g->rssi_girth = r.i8(); g->rx_packets = r.u32(); g->lost = r.u32();
  return r.ok();
}

// ------------------------------------------------------------------ GirthHub (back)
GirthHub::GirthHub(Io* io, const char* dev_id, const char* fw, uint32_t boot_id) : io_(io), boot_id_(boot_id) {
  strncpy(dev_, dev_id, sizeof(dev_) - 1);
  strncpy(fw_, fw, sizeof(fw_) - 1);
}

void GirthHub::begin(const uint8_t* stored) {
  static const uint8_t zero[6] = {0, 0, 0, 0, 0, 0}, ff[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  if (stored && memcmp(stored, zero, 6) && memcmp(stored, ff, 6)) {
    memcpy(mac_, stored, 6);
    have_ = true;
    io_->add_peer(mac_);
  }
}

void GirthHub::welcome(const uint8_t mac[6], uint32_t now_ms) {
  GirthHello w;
  strncpy(w.dev_id, dev_, sizeof(w.dev_id) - 1);
  strncpy(w.fw, fw_, sizeof(w.fw) - 1);
  uint8_t b[GIRTH_HELLO_LEN], pkt[GIRTH_MAX_PACKET];
  size_t bl = girth_hello_encode(w, b, sizeof(b));
  GirthHeader h; h.kind = GirthKind::WELCOME; h.boot_id = boot_id_; h.seq = ++seq_;
  size_t n = girth_build(h, b, bl, pkt, sizeof(pkt));
  for (int i = 0; i < 3; i++) if (io_->send(mac, pkt, n)) break;
  last_ping_ms_ = now_ms;
}

void GirthHub::count_seq(const GirthHeader& h) {
  if (!have_seq_ || h.boot_id != peer_boot_) { peer_boot_ = h.boot_id; last_seq_ = h.seq; have_seq_ = true; return; }
  uint32_t d = h.seq - last_seq_;
  if (d == 0 || d > 0x80000000u) return;          // duplicate (MAC retry) or old
  if (d > 1) lost_ += d - 1;
  last_seq_ = h.seq;
}

bool GirthHub::on_radio(const uint8_t mac[6], const uint8_t* d, size_t n, int8_t rssi, uint32_t now_ms, bool pairing_open) {
  GirthHeader h;
  const uint8_t* body;
  if (n < 2 || d[0] != GIRTH_MAGIC0 || d[1] != GIRTH_MAGIC1) return false;
  if (!girth_parse(d, n, &h, &body)) { rejected_++; return true; }
  bool mine = have_ && memcmp(mac, mac_, 6) == 0;
  if (h.kind == GirthKind::HELLO) {
    GirthHello m;
    if (!girth_hello_decode(body, h.body_len, &m)) { rejected_++; return true; }
    if (!mine) {
      if (have_ && !pairing_open) { rejected_++; return true; }   // another girth: only inside the pairing window
      memcpy(mac_, mac, 6);
      have_ = true;
      have_seq_ = false;
      io_->add_peer(mac_);
      io_->store_girth(mac_);
    }
    hello_ = m;
    last_rx_ms_ = now_ms; rssi_ = rssi; rx_++;
    welcome(mac_, now_ms);
    return true;
  }
  if (!mine) { rejected_++; return true; }
  last_rx_ms_ = now_ms; rssi_ = rssi; rx_++;
  count_seq(h);
  if (h.kind == GirthKind::STATUS) {
    girth_status_decode(body, h.body_len, &st_);
  } else if (h.kind == GirthKind::IMU) {
    ImuBatchHeader ih;
    if (h.body_len <= IMU_HDR_LEN + (size_t)GIRTH_IMU_MAX_SAMPLES * IMU_SAMPLE_LEN_9AXIS && decode_imu_header(body, h.body_len, &ih)) {
      uint8_t f[IMU_HDR_LEN + GIRTH_IMU_MAX_SAMPLES * IMU_SAMPLE_LEN_9AXIS];
      ih.back_rx_ms = now_ms;                       // the chest maps girth time through the back clock
      if (encode_imu_header(ih, f, sizeof(f)) == IMU_HDR_LEN) {
        memcpy(f + IMU_HDR_LEN, body + IMU_HDR_LEN, h.body_len - IMU_HDR_LEN);
        io_->forward_imu(f, h.body_len);
        imu_fwd_++;
      }
    } else rejected_++;
  }
  return true;
}

void GirthHub::tick(uint32_t now_ms, bool chest_online) {
  if (!have_ || now_ms - last_ping_ms_ < 1000) return;
  last_ping_ms_ = now_ms;
  if (!connected(now_ms)) return;                  // nobody listening: the girth says HELLO again when it wakes
  GirthPing g;
  g.flags = chest_online ? 1 : 0; g.rssi_girth = rssi_; g.rx_packets = rx_; g.lost = lost_;
  uint8_t b[GIRTH_PING_LEN], pkt[GIRTH_MAX_PACKET];
  size_t bl = girth_ping_encode(g, b, sizeof(b));
  GirthHeader h; h.kind = GirthKind::PING; h.boot_id = boot_id_; h.seq = ++seq_;
  size_t n = girth_build(h, b, bl, pkt, sizeof(pkt));
  io_->send(mac_, pkt, n);
}

}  // namespace avo
