// Variable-length record FIFO over a caller-provided byte buffer (PSRAM on the
// device). Not thread-safe: the device wraps it with a mutex.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

// Common record header (identical in memory and in RAW files).
static const size_t REC_HDR = 12;
struct RecHdr {
  uint8_t type = 0;
  uint8_t flags = 0;
  uint16_t len = 0;
  uint64_t chest_us = 0;   // chest monotonic µs at reception / creation
};
enum RecFlag : uint8_t { RF_PREBUFFER = 0x01, RF_AFTER_GAP = 0x02, RF_PRIO_LOW = 0x80 };
enum class RecType : uint8_t {
  UART_FRAME = 0x01, CHEST_EVENT = 0x02, CHEST_STATUS = 0x03, RTCM_STATS = 0x04, MARKER = 0x05,
  LOSS = 0x06, SESSION_START = 0x07, SESSION_CLOSE = 0x08, RECOVERY = 0x09, CONFIG_SNAPSHOT = 0x0A,
  TIME_REF = 0x0B, PREBUFFER_INFO = 0x0C, DECODER_STATS = 0x0D, RTCM_BYTES = 0x0E, PAUSE = 0x0F, RESUME = 0x10,
};
void rec_hdr_put(const RecHdr& h, uint8_t* out);
void rec_hdr_get(const uint8_t* p, RecHdr* h);

struct RecView {
  RecHdr hdr;
  const uint8_t* data;
};

class RecordRing {
 public:
  void init(uint8_t* buf, size_t cap);
  bool push(const RecHdr& h, const uint8_t* data);
  // Push evicting oldest records (pre-buffer). Records older than min_us are
  // dropped first. Returns false only if the record is larger than the ring.
  bool push_evict(const RecHdr& h, const uint8_t* data, uint64_t min_us, uint32_t* evicted);
  bool peek(RecView* v);
  void pop();
  void clear();
  size_t used() const { return used_; }
  size_t capacity() const { return cap_; }
  uint32_t count() const { return count_; }
  uint32_t fill_permille() const { return cap_ ? (uint32_t)((used_ * 1000) / cap_) : 1000; }
  bool oldest_time(uint64_t* t);
  bool newest_time(uint64_t* t) const { if (!count_) return false; *t = newest_us_; return true; }

 private:
  bool try_place(size_t need, size_t* at);
  uint8_t* b_ = nullptr;
  size_t cap_ = 0, head_ = 0, tail_ = 0, used_ = 0;
  uint32_t count_ = 0;
  uint64_t newest_us_ = 0;
};

}  // namespace avo
