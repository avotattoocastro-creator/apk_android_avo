// AVO CASCO — IMU de la cabeza del jinete: LSM6DSV16X (I²C 0x6A, INT1 en GPIO4).
//
// Contrato (extensión compatible del IMU_SAMPLE de avo_payloads.h; cabecera de 24 B sin cambios):
//   girth_id = 0xCA ("casco") · imu_id = 4 · fmt = 3 · reserved (byte 15) = 3 (unidades LSM6DSV16X)
//   muestras de 12 B: int16 LE ax ay az gx gy gz en LSB del sensor
//     acelerómetro ±16 g → 0,488 mg/LSB · giróscopo ±2000 dps → 70 mdps/LSB · 120 Hz (period_us 8333),
//     igual que la cincha REV D (mismo sensor y registros: firmware/girth/V0_6_0/girth_imu6.h)
//   girth_seq = número de lote · girth_t0_us = reloj del casco (esp_timer, µs, 32 bits) de la primera muestra
//   sync_state = 2 con el PPS enganchado (TIME_SYNC del mismo reloj), 1 sin él · girth_to_back_us = 0 (mismo reloj)
// Las apps y el motor que no conocen fmt 3 lo ignoran (Windows/iPad: lote «opaco»; Android: solo fmt 0;
// motor ≥ 2.0.0-dev32: head_imu_batches). No se mezcla con las cinchas (imu_id 0–3).
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace casco_imu {

static const uint8_t HEAD_GIRTH_ID = 0xCA;
static const uint8_t HEAD_IMU_ID = 4;
static const uint8_t HEAD_FMT = 3;
static const uint8_t HEAD_UNITS = 3;
static const size_t HEAD_SAMPLE_LEN = 12;
static const uint8_t HEAD_BATCH = 15;        // 24 + 15 × 12 = 204 B: cabe en una trama (carga ≤ 234 − 19 = 215 B)
// 8 lotes por segundo a 120 Hz.
static const uint16_t HEAD_PERIOD_US = 8333; // 120 Hz

bool init();          // después de board::i2c_init: arranca la tarea; si la IMU no responde reintenta (el casco sigue)
bool present();
uint32_t batches();   // lotes enviados
uint32_t overruns();  // muestras perdidas (la tarea no llegó a tiempo)

}  // namespace casco_imu
