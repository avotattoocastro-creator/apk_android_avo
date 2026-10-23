#include "avo_uart_proto.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include <string.h>

namespace avo {

size_t uart_encode(FrameType type, uint8_t flags, uint8_t src, uint16_t seq, uint32_t t_ms,
                   const uint8_t* payload, size_t len, uint8_t* out, size_t cap) {
  if (len > AVO_UART_MAX_PAYLOAD) return 0;
  size_t total = AVO_UART_HDR + len + AVO_UART_TRAILER;
  if (cap < total || (len && !payload)) return 0;
  out[0] = AVO_UART_SYNC0;
  out[1] = AVO_UART_SYNC1;
  out[2] = AVO_UART_VERSION;
  out[3] = (uint8_t)type;
  out[4] = flags;
  out[5] = src;
  put_u16(out + 6, seq);
  put_u16(out + 8, (uint16_t)len);
  put_u32(out + 10, t_ms);
  out[14] = crc8(out + 2, 12);
  if (len) memcpy(out + AVO_UART_HDR, payload, len);
  put_u32(out + AVO_UART_HDR + len, crc32(out + 2, AVO_UART_HDR - 2 + len));
  return total;
}

SeqTracker::Result SeqTracker::check(uint16_t seq, uint32_t* lost) {
  if (!have_) { have_ = true; last_ = seq; window_ = 1; return NEW; }
  uint16_t ahead = (uint16_t)(seq - last_);
  if (ahead == 0) return DUPLICATE;
  if (ahead < 0x8000) {
    // Newer frame. A very large jump (>1000) is treated as a sender restart:
    // counted as loss is not meaningful, so the tracker is re-based.
    if (ahead > 1000) { last_ = seq; window_ = 1; return NEW; }
    if (lost) *lost += (uint32_t)(ahead - 1);
    window_ = (ahead >= 64) ? 1 : ((window_ << ahead) | 1);
    last_ = seq;
    return NEW;
  }
  uint16_t behind = (uint16_t)(last_ - seq);
  if (behind < 64) {
    uint64_t bit = (uint64_t)1 << behind;
    if (window_ & bit) return DUPLICATE;
    window_ |= bit;
    if (lost && *lost) (*lost)--;  // late arrival fills a gap we already counted
    return OLD;
  }
  // Far in the past: sender most likely rebooted. Re-base.
  last_ = seq; window_ = 1;
  return NEW;
}

void UartDecoder::feed(const uint8_t* d, size_t n) {
  st_.bytes_in += (uint32_t)n;
  while (n) {
    if (head_ > 0 && (tail_ == sizeof(buf_) || head_ > sizeof(buf_) / 2)) {
      memmove(buf_, buf_ + head_, tail_ - head_);
      tail_ -= head_;
      head_ = 0;
    }
    size_t room = sizeof(buf_) - tail_;
    size_t k = n < room ? n : room;
    memcpy(buf_ + tail_, d, k);
    tail_ += k; d += k; n -= k;
    process();
  }
}

void UartDecoder::process() {
  for (;;) {
    size_t avail = tail_ - head_;
    if (avail < 2) return;
    const uint8_t* p = buf_ + head_;
    if (p[0] != AVO_UART_SYNC0 || p[1] != AVO_UART_SYNC1) {
      // Skip to the next candidate sync byte in one step.
      size_t i = 1;
      while (i < avail && buf_[head_ + i] != AVO_UART_SYNC0) i++;
      st_.resync_bytes += (uint32_t)i;
      head_ += i;
      continue;
    }
    if (avail < AVO_UART_HDR) return;
    if (crc8(p + 2, 12) != p[14]) { st_.hdr_crc_err++; st_.resync_bytes++; head_++; continue; }
    uint16_t len = get_u16(p + 8);
    if (len > AVO_UART_MAX_PAYLOAD) { st_.len_err++; st_.resync_bytes++; head_++; continue; }
    size_t total = AVO_UART_HDR + len + AVO_UART_TRAILER;
    if (avail < total) return;
    uint32_t want = get_u32(p + AVO_UART_HDR + len);
    if (crc32(p + 2, AVO_UART_HDR - 2 + len) != want) { st_.crc_err++; st_.resync_bytes++; head_++; continue; }
    FrameView f;
    f.ver = p[2];
    f.type = (FrameType)p[3];
    f.flags = p[4];
    f.src = p[5];
    f.seq = get_u16(p + 6);
    f.len = len;
    f.t_ms = get_u32(p + 10);
    f.payload = p + AVO_UART_HDR;
    f.raw = p;
    f.raw_len = total;
    if (f.ver == 0) st_.unknown_version++;
    SeqTracker::Result r = trk_[f.src & 7].check(f.seq, &st_.seq_lost);
    head_ += total;
    if (r == SeqTracker::DUPLICATE) { st_.duplicates++; continue; }
    if (r == SeqTracker::OLD) st_.out_of_order++;
    st_.frames_ok++;
    if (cb_) cb_(f, ctx_);
  }
}

}  // namespace avo
