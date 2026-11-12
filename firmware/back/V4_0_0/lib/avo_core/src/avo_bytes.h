// AVO Chest V3.3 — explicit little-endian serialization helpers.
// All on-wire / on-disk structures are encoded field by field: no packed
// structs, no dependence on compiler padding or host endianness.
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <string.h>

namespace avo {

inline void put_u8(uint8_t* p, uint8_t v) { p[0] = v; }
inline void put_u16(uint8_t* p, uint16_t v) { p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); }
inline void put_u32(uint8_t* p, uint32_t v) {
  p[0] = (uint8_t)v; p[1] = (uint8_t)(v >> 8); p[2] = (uint8_t)(v >> 16); p[3] = (uint8_t)(v >> 24);
}
inline void put_u64(uint8_t* p, uint64_t v) { put_u32(p, (uint32_t)v); put_u32(p + 4, (uint32_t)(v >> 32)); }
inline uint8_t get_u8(const uint8_t* p) { return p[0]; }
inline uint16_t get_u16(const uint8_t* p) { return (uint16_t)(p[0] | ((uint16_t)p[1] << 8)); }
inline uint32_t get_u32(const uint8_t* p) {
  return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}
inline uint64_t get_u64(const uint8_t* p) { return (uint64_t)get_u32(p) | ((uint64_t)get_u32(p + 4) << 32); }

// Bounded writer. Once an overflow happens, ok() stays false and nothing
// else is written (callers check ok() once at the end).
class ByteWriter {
 public:
  ByteWriter(uint8_t* buf, size_t cap) : b_(buf), cap_(cap) {}
  void u8(uint8_t v) { if (room(1)) { put_u8(b_ + n_, v); n_ += 1; } }
  void u16(uint16_t v) { if (room(2)) { put_u16(b_ + n_, v); n_ += 2; } }
  void u32(uint32_t v) { if (room(4)) { put_u32(b_ + n_, v); n_ += 4; } }
  void u64(uint64_t v) { if (room(8)) { put_u64(b_ + n_, v); n_ += 8; } }
  void i8(int8_t v) { u8((uint8_t)v); }
  void i16(int16_t v) { u16((uint16_t)v); }
  void i32(int32_t v) { u32((uint32_t)v); }
  void bytes(const void* d, size_t len) { if (room(len)) { if (len) memcpy(b_ + n_, d, len); n_ += len; } }
  // Fixed-width, zero-padded string field (always NUL-terminated inside).
  void str(const char* s, size_t width) {
    if (!room(width)) return;
    memset(b_ + n_, 0, width);
    if (s) { size_t l = strnlen(s, width); if (l > width - 1) l = width - 1; memcpy(b_ + n_, s, l); }
    n_ += width;
  }
  size_t size() const { return n_; }
  bool ok() const { return ok_; }
  uint8_t* data() { return b_; }

 private:
  bool room(size_t k) { if (!ok_ || n_ + k > cap_) { ok_ = false; return false; } return true; }
  uint8_t* b_;
  size_t cap_;
  size_t n_ = 0;
  bool ok_ = true;
};

class ByteReader {
 public:
  ByteReader(const uint8_t* buf, size_t len) : b_(buf), len_(len) {}
  uint8_t u8() { return room(1) ? get_u8(b_ + (n_ += 1) - 1) : 0; }
  uint16_t u16() { if (!room(2)) return 0; uint16_t v = get_u16(b_ + n_); n_ += 2; return v; }
  uint32_t u32() { if (!room(4)) return 0; uint32_t v = get_u32(b_ + n_); n_ += 4; return v; }
  uint64_t u64() { if (!room(8)) return 0; uint64_t v = get_u64(b_ + n_); n_ += 8; return v; }
  int8_t i8() { return (int8_t)u8(); }
  int16_t i16() { return (int16_t)u16(); }
  int32_t i32() { return (int32_t)u32(); }
  void bytes(void* d, size_t len) { if (room(len)) { if (len) memcpy(d, b_ + n_, len); n_ += len; } else if (d) memset(d, 0, len); }
  void str(char* out, size_t width) {
    if (!room(width)) { if (width) out[0] = 0; return; }
    memcpy(out, b_ + n_, width);
    out[width - 1] = 0;
    n_ += width;
  }
  void skip(size_t k) { if (room(k)) n_ += k; }
  size_t pos() const { return n_; }
  size_t remaining() const { return ok_ ? len_ - n_ : 0; }
  const uint8_t* cur() const { return b_ + n_; }
  bool ok() const { return ok_; }

 private:
  bool room(size_t k) { if (!ok_ || n_ + k > len_) { ok_ = false; return false; } return true; }
  const uint8_t* b_;
  size_t len_;
  size_t n_ = 0;
  bool ok_ = true;
};

}  // namespace avo
