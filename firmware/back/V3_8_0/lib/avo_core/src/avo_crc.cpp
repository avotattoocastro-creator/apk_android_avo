#include "avo_crc.h"

namespace avo {

uint8_t crc8(const uint8_t* d, size_t n, uint8_t crc) {
  for (size_t i = 0; i < n; i++) {
    crc ^= d[i];
    for (int b = 0; b < 8; b++) crc = (crc & 0x80) ? (uint8_t)((crc << 1) ^ 0x07) : (uint8_t)(crc << 1);
  }
  return crc;
}

uint16_t crc16_ccitt(const uint8_t* d, size_t n, uint16_t crc) {
  for (size_t i = 0; i < n; i++) {
    crc = (uint16_t)(crc ^ (uint16_t)(d[i] << 8));
    for (int b = 0; b < 8; b++) crc = (crc & 0x8000) ? (uint16_t)((crc << 1) ^ 0x1021) : (uint16_t)(crc << 1);
  }
  return crc;
}

static uint32_t g_crc32_table[256];
static bool g_crc32_ready = false;

static void crc32_build() {
  for (uint32_t i = 0; i < 256; i++) {
    uint32_t c = i;
    for (int k = 0; k < 8; k++) c = (c & 1) ? (0xEDB88320u ^ (c >> 1)) : (c >> 1);
    g_crc32_table[i] = c;
  }
  g_crc32_ready = true;  // benign race: every writer stores identical values
}

uint32_t crc32_init() { if (!g_crc32_ready) crc32_build(); return 0xFFFFFFFFu; }
uint32_t crc32_update(uint32_t c, const uint8_t* d, size_t n) {
  if (!g_crc32_ready) crc32_build();
  for (size_t i = 0; i < n; i++) c = g_crc32_table[(c ^ d[i]) & 0xFF] ^ (c >> 8);
  return c;
}
uint32_t crc32_final(uint32_t c) { return c ^ 0xFFFFFFFFu; }
uint32_t crc32(const uint8_t* d, size_t n) { return crc32_final(crc32_update(crc32_init(), d, n)); }

uint32_t crc24q(const uint8_t* d, size_t n) {
  uint32_t crc = 0;
  for (size_t i = 0; i < n; i++) {
    crc ^= (uint32_t)d[i] << 16;
    for (int b = 0; b < 8; b++) {
      crc <<= 1;
      if (crc & 0x1000000u) crc ^= 0x1864CFBu;
    }
  }
  return crc & 0xFFFFFFu;
}

}  // namespace avo
