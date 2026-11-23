#include "avo_ubx_frag.h"
#include <string.h>
#include "avo_gnss_codecs.h"

namespace avo {

static inline void put16(uint8_t* p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
static inline uint16_t get16(const uint8_t* p) { return (uint16_t)(p[0] | (p[1] << 8)); }

size_t ubx_frag_count(size_t len) {
  if (len == 0 || len > UBX_FRAG_MAX_FRAME) return 0;
  return (len + UBX_FRAG_CHUNK - 1) / UBX_FRAG_CHUNK;
}

size_t ubx_frag_encode(const uint8_t* ubx, size_t len, uint16_t msg_seq, uint8_t index, uint8_t* out, size_t cap) {
  size_t count = ubx_frag_count(len);
  if (!ubx || !out || count == 0 || index >= count) return 0;
  size_t off = (size_t)index * UBX_FRAG_CHUNK;
  size_t n = len - off < UBX_FRAG_CHUNK ? len - off : UBX_FRAG_CHUNK;
  if (cap < UBX_FRAG_HDR + n) return 0;
  out[0] = UBX_FRAG_VERSION;
  out[1] = index;
  out[2] = (uint8_t)count;
  out[3] = 0;
  put16(out + 4, msg_seq);
  put16(out + 6, (uint16_t)len);
  memcpy(out + UBX_FRAG_HDR, ubx + off, n);
  return UBX_FRAG_HDR + n;
}

bool ubx_frag_decode(const uint8_t* pl, size_t len, UbxFragPiece* p) {
  if (!pl || !p || len <= UBX_FRAG_HDR || pl[0] != UBX_FRAG_VERSION) return false;
  UbxFragPiece q;
  q.index = pl[1];
  q.count = pl[2];
  q.msg_seq = get16(pl + 4);
  q.total = get16(pl + 6);
  q.data = pl + UBX_FRAG_HDR;
  q.n = len - UBX_FRAG_HDR;
  if (q.count == 0 || q.index >= q.count || ubx_frag_count(q.total) != q.count) return false;
  size_t off = (size_t)q.index * UBX_FRAG_CHUNK;
  size_t want = q.total - off < UBX_FRAG_CHUNK ? q.total - off : UBX_FRAG_CHUNK;
  if (q.n != want) return false;
  *p = q;
  return true;
}

bool UbxDefrag::feed(const uint8_t* pl, size_t len, const uint8_t** frame, size_t* frame_len) {
  UbxFragPiece p;
  if (!ubx_frag_decode(pl, len, &p)) { bad_++; return false; }
  if (!active_ && done_ && p.msg_seq == done_seq_) return false;   // late duplicate of a message already delivered
  if (!active_ || p.msg_seq != seq_ || p.total != total_ || p.count != count_) {
    if (active_) incomplete_++;
    active_ = true;
    seq_ = p.msg_seq;
    total_ = p.total;
    count_ = p.count;
    got_ = 0;
  }
  memcpy(buf_ + (size_t)p.index * UBX_FRAG_CHUNK, p.data, p.n);
  got_ |= 1u << p.index;
  uint32_t all = count_ >= 32 ? 0xFFFFFFFFu : ((1u << count_) - 1u);
  if (got_ != all) return false;
  active_ = false;
  done_ = true;
  done_seq_ = seq_;
  uint8_t cls, id;
  const uint8_t* q;
  uint16_t qn;
  if (!ubx_check_frame(buf_, total_, &cls, &id, &q, &qn)) { bad_++; return false; }
  complete_++;
  if (frame) *frame = buf_;
  if (frame_len) *frame_len = total_;
  return true;
}

}  // namespace avo
