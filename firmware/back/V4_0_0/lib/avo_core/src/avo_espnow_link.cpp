#include "avo_espnow_link.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include <stdio.h>

namespace avo {

size_t now_build(const NowHeader& h, const uint8_t* body, size_t body_len, uint8_t* out, size_t cap) {
  if (body_len > NOW_MAX_BODY || cap < NOW_HDR + body_len) return 0;
  out[0] = NOW_MAGIC0;
  out[1] = NOW_MAGIC1;
  out[2] = NOW_LINK_VERSION;
  out[3] = (uint8_t)h.kind;
  put_u32(out + 4, h.pair_id);
  put_u32(out + 8, h.boot_id);
  put_u16(out + 12, (uint16_t)body_len);
  if (body_len) memcpy(out + NOW_HDR, body, body_len);
  uint16_t c = crc16_ccitt(out, 14);
  c = crc16_ccitt(out + NOW_HDR, body_len, c);
  put_u16(out + 14, c);
  return NOW_HDR + body_len;
}

bool now_parse(const uint8_t* p, size_t n, NowHeader* h, const uint8_t** body) {
  if (n < NOW_HDR || n > NOW_MAX_PACKET) return false;
  if (p[0] != NOW_MAGIC0 || p[1] != NOW_MAGIC1 || p[2] != NOW_LINK_VERSION) return false;
  uint16_t bl = get_u16(p + 12);
  if (NOW_HDR + bl != n) return false;
  uint16_t c = crc16_ccitt(p, 14);
  c = crc16_ccitt(p + NOW_HDR, bl, c);
  if (c != get_u16(p + 14)) return false;
  uint8_t k = p[3];
  if (k < 1 || k > 3) return false;
  h->kind = (NowKind)k;
  h->pair_id = get_u32(p + 4);
  h->boot_id = get_u32(p + 8);
  h->body_len = bl;
  *body = p + NOW_HDR;
  return true;
}

size_t now_pair_encode(const NowPairMsg& m, uint8_t* out, size_t cap) {
  ByteWriter w(out, cap);
  w.u8((uint8_t)m.role);
  w.u32(m.nonce);
  w.str(m.dev_id, 16);
  w.str(m.fw, 16);
  return w.ok() ? w.size() : 0;
}

bool now_pair_decode(const uint8_t* p, size_t n, NowPairMsg* m) {
  if (n < NOW_PAIR_BODY) return false;
  ByteReader r(p, n);
  uint8_t role = r.u8();
  if (role != 1 && role != 2) return false;
  m->role = (NowRole)role;
  m->nonce = r.u32();
  r.str(m->dev_id, 16);
  r.str(m->fw, 16);
  return r.ok();
}

size_t now_peer_serialize(const NowPeerRecord& r, uint8_t* out, size_t cap) {
  if (cap < NOW_PEER_RECORD_LEN) return 0;
  memcpy(out, "ANP1", 4);
  memcpy(out + 4, r.mac, 6);
  put_u32(out + 10, r.pair_id);
  put_u16(out + 14, crc16_ccitt(out, 14));
  return NOW_PEER_RECORD_LEN;
}

bool now_peer_deserialize(const uint8_t* p, size_t n, NowPeerRecord* r) {
  *r = NowPeerRecord();
  if (n < NOW_PEER_RECORD_LEN || memcmp(p, "ANP1", 4) != 0) return false;
  if (crc16_ccitt(p, 14) != get_u16(p + 14)) return false;
  memcpy(r->mac, p + 4, 6);
  r->pair_id = get_u32(p + 10);
  static const uint8_t zero[6] = {0}, bc[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  if (r->pair_id == 0 || memcmp(r->mac, zero, 6) == 0 || memcmp(r->mac, bc, 6) == 0) return false;
  r->valid = true;
  return true;
}

void now_mac_str(const uint8_t m[6], char out[18]) {
  snprintf(out, 18, "%02X:%02X:%02X:%02X:%02X:%02X", m[0], m[1], m[2], m[3], m[4], m[5]);
}

// ------------------------------------------------------------------ chest
void NowPairing::open(uint32_t now_ms, uint32_t duration_ms, uint32_t new_nonce, uint32_t new_pair_id) {
  open_ = true;
  open_until_ = duration_ms ? now_ms + duration_ms : 0;
  nonce_ = new_nonce ? new_nonce : 1;
  proposed_pair_id_ = new_pair_id ? new_pair_id : 1;
  sent_once_ = false;
}

bool NowPairing::open_now(uint32_t now_ms) const {
  if (!open_) return false;
  if (open_until_ == 0) return true;
  return (int32_t)(open_until_ - now_ms) > 0;
}

size_t NowPairing::chest_poll(uint32_t now_ms, const char* dev_id, const char* fw, uint8_t* body, size_t cap) {
  if (role_ != NowRole::CHEST || !open_now(now_ms)) return 0;
  if (sent_once_ && now_ms - last_req_ms_ < 1000) return 0;
  sent_once_ = true;
  last_req_ms_ = now_ms;
  NowPairMsg m;
  m.role = NowRole::CHEST;
  m.nonce = nonce_;
  strncpy(m.dev_id, dev_id ? dev_id : "", sizeof(m.dev_id) - 1);
  strncpy(m.fw, fw ? fw : "", sizeof(m.fw) - 1);
  return now_pair_encode(m, body, cap);
}

bool NowPairing::chest_on_ack(const uint8_t mac[6], const NowHeader& h, const NowPairMsg& m, uint32_t now_ms) {
  if (role_ != NowRole::CHEST || !open_now(now_ms)) return false;
  if (h.kind != NowKind::PAIR_ACK || m.role != NowRole::BACK) return false;
  if (m.nonce != nonce_ || h.pair_id != proposed_pair_id_) return false;
  peer_.valid = true;
  memcpy(peer_.mac, mac, 6);
  peer_.pair_id = proposed_pair_id_;
  open_ = false;
  return true;
}

// ------------------------------------------------------------------ back
bool NowPairing::back_on_req(const uint8_t mac[6], const NowHeader& h, const NowPairMsg& m, uint32_t now_ms, uint32_t last_peer_rx_ms) {
  if (role_ != NowRole::BACK || h.kind != NowKind::PAIR_REQ || m.role != NowRole::CHEST || h.pair_id == 0) return false;
  uint32_t why = 0;
  if (!peer_.valid) why = 1;
  else if (back_open_now(now_ms)) why = 2;
  else if (memcmp(mac, peer_.mac, 6) == 0) why = 3;
  else if (now_ms - last_peer_rx_ms >= 60000) why = 4;   // last_peer_rx_ms = 0 means "since boot"
  if (!why) return false;
  reason_ = why;
  peer_.valid = true;
  memcpy(peer_.mac, mac, 6);
  peer_.pair_id = h.pair_id;
  back_open_flag_ = false;
  return true;
}

}  // namespace avo
