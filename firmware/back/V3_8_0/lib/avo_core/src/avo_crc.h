// AVO Chest V3.3 — CRC functions shared by every protocol and file format.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

// CRC-8, poly 0x07, init 0x00, no reflection (CRC-8/SMBUS). Check("123456789") = 0xF4
uint8_t crc8(const uint8_t* d, size_t n, uint8_t crc = 0x00);
// CRC-16/CCITT-FALSE, poly 0x1021, init 0xFFFF. Check("123456789") = 0x29B1
uint16_t crc16_ccitt(const uint8_t* d, size_t n, uint16_t crc = 0xFFFF);
// CRC-32/ISO-HDLC (zlib), poly 0xEDB88320 reflected. Check("123456789") = 0xCBF43926
// Incremental use: crc = crc32_update(crc32_init(), ...); result = crc32_final(crc)
uint32_t crc32_init();
uint32_t crc32_update(uint32_t state, const uint8_t* d, size_t n);
uint32_t crc32_final(uint32_t state);
uint32_t crc32(const uint8_t* d, size_t n);
// CRC-24Q used by RTCM 3. Check("123456789") = 0xCDE703
uint32_t crc24q(const uint8_t* d, size_t n);

}  // namespace avo
