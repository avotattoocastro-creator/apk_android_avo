#include "girth_imu6.h"
#include <math.h>
#include <string.h>

namespace girth {
namespace imu6 {

float half_to_float(uint16_t h) {
  uint32_t sign = (uint32_t)(h >> 15) << 31, exp = (h >> 10) & 0x1F, man = h & 0x3FF, f;
  if (exp == 0) {
    if (man == 0) f = sign;
    else {                                            // subnormal
      int e = -1;
      do { e++; man <<= 1; } while (!(man & 0x400));
      man &= 0x3FF;
      f = sign | ((uint32_t)(127 - 15 - e) << 23) | (man << 13);
    }
  } else if (exp == 31) f = sign | 0x7F800000u | (man << 13);
  else f = sign | ((exp + 127 - 15) << 23) | (man << 13);
  float out;
  memcpy(&out, &f, 4);
  return out;
}

void sflp_to_quat(const uint16_t h[3], float q[4]) {
  float s = 0;
  for (int i = 0; i < 3; i++) { q[i] = half_to_float(h[i]); s += q[i] * q[i]; }
  if (s > 1.0f) { float n = sqrtf(s); for (int i = 0; i < 3; i++) q[i] /= n; s = 1.0f; }
  q[3] = sqrtf(1.0f - s);
}

void gravity_in_sensor(const float q[4], float g[3]) {
  const float x = q[0], y = q[1], z = q[2], w = q[3], G = 9.80665f;
  g[0] = 2.0f * (x * z - w * y) * G;
  g[1] = 2.0f * (y * z + w * x) * G;
  g[2] = (w * w - x * x - y * y + z * z) * G;
}

int16_t to_q(float v, float scale) {
  float r = v * scale;
  r = r >= 0 ? r + 0.5f : r - 0.5f;
  if (r > 32767.0f) return 32767;
  if (r < -32768.0f) return -32768;
  return (int16_t)r;
}

void acc_raw_to_q8(const int16_t raw[3], int16_t out[3], float ms2[3]) {
  for (int i = 0; i < 3; i++) { ms2[i] = raw[i] * XL_MG_PER_LSB * 9.80665e-3f; out[i] = to_q(ms2[i], 256.0f); }
}

void gyro_raw_to_q9(const int16_t raw[3], int16_t out[3]) {
  for (int i = 0; i < 3; i++) out[i] = to_q(raw[i] * G_MDPS_PER_LSB * 1e-3f * 0.017453293f, 512.0f);
}

void quat_to_q14(const float q[4], int16_t out[4]) {
  for (int i = 0; i < 4; i++) out[i] = to_q(q[i], 16384.0f);
}

void mmc_to_q4(const uint8_t b[7], int16_t out[3]) {
  for (int a = 0; a < 3; a++) {
    uint32_t raw = ((uint32_t)b[2 * a] << 10) | ((uint32_t)b[2 * a + 1] << 2) | ((b[6] >> (6 - 2 * a)) & 0x3);
    float ut = ((int32_t)raw - 131072) / 163.84f;     // 16384 counts/G, 1 G = 100 µT
    out[a] = to_q(ut, 16.0f);
  }
}

}  // namespace imu6
}  // namespace girth
