// AVO GIRTH — empaquetado del cuerpo de un paquete IMU (sin dependencias de Arduino: se prueba en el PC,
// firmware/girth/V0_3_0_C3/pruebas). Formato: ImuBatchHeader (24 B, avo_payloads.h) + count × 9 int16 little-endian
// en el orden ax ay az gx gy gz mx my mz (IMU_FMT_9AXIS_I16).
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "avo_payloads.h"
#include "avo_girth_link.h"

namespace avo {

// S: cualquier tipo con int16_t v[9] (gimu::Sample en el firmware).
template <typename S>
size_t girth_pack_imu_body(const S* samples, uint8_t count, uint32_t t0_us, uint32_t girth_seq, uint16_t period_us,
                           uint8_t* out, size_t cap) {
  if (count > GIRTH_IMU_MAX_SAMPLES || cap < IMU_HDR_LEN + (size_t)count * IMU_SAMPLE_LEN_9AXIS) return 0;
  ImuBatchHeader ih;
  ih.girth_id = 0; ih.imu_id = 0; ih.count = count; ih.fmt = IMU_FMT_9AXIS_I16;
  ih.girth_seq = girth_seq; ih.girth_t0_us = t0_us; ih.period_us = period_us;
  ih.sync_state = 0;                                   // sin sincronía con la espalda (la estima la espalda)
  size_t n = encode_imu_header(ih, out, cap);
  if (n != IMU_HDR_LEN) return 0;
  for (uint8_t k = 0; k < count; k++)
    for (int a = 0; a < 9; a++) {
      uint16_t v = (uint16_t)samples[k].v[a];
      out[n++] = (uint8_t)(v & 0xFF); out[n++] = (uint8_t)(v >> 8);   // little-endian, como avo_bytes.h
    }
  return n;
}

}  // namespace avo
