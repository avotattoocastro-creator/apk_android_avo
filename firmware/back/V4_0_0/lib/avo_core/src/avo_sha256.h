// Portable SHA-256 and HMAC-SHA256 (FIPS 180-4 / RFC 2104).
// Used by the BLE application-level authorization; identical results on the
// device and in the host tests (and against javax.crypto on Android).
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

struct Sha256 {
  uint32_t h[8];
  uint64_t len;
  uint8_t buf[64];
  size_t n;
  void init();
  void update(const uint8_t* d, size_t k);
  void final(uint8_t out[32]);
};
void sha256(const uint8_t* d, size_t n, uint8_t out[32]);
void hmac_sha256(const uint8_t* key, size_t key_len, const uint8_t* msg, size_t msg_len, uint8_t out[32]);
// Constant-time comparison.
bool ct_equal(const uint8_t* a, const uint8_t* b, size_t n);

}  // namespace avo
