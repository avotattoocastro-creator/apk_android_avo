#include "avo_ring.h"
#include "avo_bytes.h"
#include <string.h>

namespace avo {

static const uint32_t WRAP = 0xFFFFFFFFu;

void rec_hdr_put(const RecHdr& h, uint8_t* o) {
  o[0] = h.type; o[1] = h.flags; put_u16(o + 2, h.len); put_u64(o + 4, h.chest_us);
}
void rec_hdr_get(const uint8_t* p, RecHdr* h) {
  h->type = p[0]; h->flags = p[1]; h->len = get_u16(p + 2); h->chest_us = get_u64(p + 4);
}

static inline size_t align4(size_t v) { return (v + 3) & ~(size_t)3; }

void RecordRing::init(uint8_t* buf, size_t cap) {
  b_ = buf;
  cap_ = cap & ~(size_t)3;
  clear();
}

void RecordRing::clear() { head_ = tail_ = used_ = 0; count_ = 0; }

bool RecordRing::try_place(size_t need, size_t* at) {
  if (used_ == 0) { head_ = tail_ = 0; }
  if (need > cap_) return false;
  if (tail_ >= head_ && !(used_ && tail_ == head_)) {
    if (cap_ - tail_ >= need) { *at = tail_; return true; }
    if (head_ >= need) {  // wrap
      size_t gap = cap_ - tail_;
      if (gap >= 4) put_u32(b_ + tail_, WRAP);
      used_ += gap;
      tail_ = 0;
      *at = 0;
      return true;
    }
    return false;
  }
  if (head_ - tail_ >= need) { *at = tail_; return true; }
  return false;
}

bool RecordRing::push(const RecHdr& h, const uint8_t* data) {
  size_t need = align4(4 + REC_HDR + h.len);
  size_t at;
  if (!b_ || !try_place(need, &at)) return false;
  put_u32(b_ + at, (uint32_t)need);
  rec_hdr_put(h, b_ + at + 4);
  if (h.len) memcpy(b_ + at + 4 + REC_HDR, data, h.len);
  tail_ = at + need;
  if (tail_ == cap_) tail_ = 0;
  used_ += need;
  count_++;
  newest_us_ = h.chest_us;
  return true;
}

bool RecordRing::push_evict(const RecHdr& h, const uint8_t* data, uint64_t min_us, uint32_t* evicted) {
  size_t need = align4(4 + REC_HDR + h.len);
  if (need > cap_) return false;
  uint64_t t;
  while (oldest_time(&t) && t < min_us) { pop(); if (evicted) (*evicted)++; }
  while (!push(h, data)) {
    if (count_ == 0) return false;
    pop();
    if (evicted) (*evicted)++;
  }
  return true;
}

bool RecordRing::peek(RecView* v) {
  if (count_ == 0) return false;
  for (;;) {
    if (cap_ - head_ < 4) { used_ -= cap_ - head_; head_ = 0; continue; }
    uint32_t l = get_u32(b_ + head_);
    if (l == WRAP) { used_ -= cap_ - head_; head_ = 0; continue; }
    rec_hdr_get(b_ + head_ + 4, &v->hdr);
    v->data = b_ + head_ + 4 + REC_HDR;
    return true;
  }
}

void RecordRing::pop() {
  RecView v;
  if (!peek(&v)) return;
  uint32_t l = get_u32(b_ + head_);
  head_ += l;
  if (head_ == cap_) head_ = 0;
  used_ -= l;
  count_--;
  if (count_ == 0) { head_ = tail_ = used_ = 0; }
}

bool RecordRing::oldest_time(uint64_t* t) {
  RecView v;
  if (!peek(&v)) return false;
  *t = v.hdr.chest_us;
  return true;
}

}  // namespace avo
