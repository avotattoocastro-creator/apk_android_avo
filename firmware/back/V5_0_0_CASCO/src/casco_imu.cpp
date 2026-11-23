// AVO CASCO — LSM6DSV16X de la cabeza: acelerómetro + giróscopo a 120 Hz por FIFO, en lotes IMU_SAMPLE fmt 3.
// Registros y configuración: los mismos que la cincha REV D (firmware/girth/V0_6_0/girth_imu6.h), sin SFLP ni magnetómetro.
#include "casco_imu.h"
#include <Arduino.h>
#include <Wire.h>
#include <esp_timer.h>
#include <atomic>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_task_wdt.h"
#include "avo_core.h"
#include "board_pins.h"
#include "hal_board.h"
#include "casco_back.h"

using namespace avo;

namespace casco_imu {

static const uint8_t ADDR = I2C_ADDR_LSM6DSV16X;
static const uint8_t WHO_AM_I = 0x0F, LSM_ID = 0x70, CTRL1 = 0x10, CTRL2 = 0x11, CTRL3 = 0x12, CTRL6 = 0x15, CTRL8 = 0x17,
                     FIFO_CTRL3 = 0x09, FIFO_CTRL4 = 0x0A, FIFO_STATUS1 = 0x1B, FIFO_DATA_OUT_TAG = 0x78;
static const uint8_t TAG_GY = 0x01, TAG_XL = 0x02;
static const uint8_t ODR_120HZ = 0x06, FS_XL_16G = 0x03, FS_G_2000DPS = 0x04, FIFO_STREAM = 0x06;

static std::atomic<bool> s_present{false};
static std::atomic<uint32_t> s_batches{0}, s_overruns{0};

bool present() { return s_present; }
uint32_t batches() { return s_batches; }
uint32_t overruns() { return s_overruns; }

static bool wr(uint8_t reg, uint8_t v) {
  if (!board::i2c_lock(50)) return false;
  Wire.beginTransmission(ADDR);
  Wire.write(reg);
  Wire.write(v);
  bool ok = Wire.endTransmission(true) == 0;
  board::i2c_unlock();
  return ok;
}

static bool rd(uint8_t reg, uint8_t* d, size_t n) {
  if (!board::i2c_lock(50)) return false;
  Wire.beginTransmission(ADDR);
  Wire.write(reg);
  bool ok = Wire.endTransmission(false) == 0 && Wire.requestFrom((uint16_t)ADDR, n, true) == n;
  if (ok) for (size_t i = 0; i < n; i++) d[i] = (uint8_t)Wire.read();
  board::i2c_unlock();
  return ok;
}

static bool start() {
  uint8_t id = 0;
  if (!rd(WHO_AM_I, &id, 1) || id != LSM_ID) {
    Serial.printf("[AVO CASCO] IMU LSM6DSV16X no responde (WHO_AM_I 0x%02X, se esperaba 0x70)\n", id);
    return false;
  }
  wr(CTRL3, 0x01);   // reinicio por software
  delay(20);
  bool ok = wr(CTRL3, 0x40 | 0x04);                                   // BDU + IF_INC
  ok = ok && wr(CTRL8, FS_XL_16G) && wr(CTRL6, FS_G_2000DPS);
  ok = ok && wr(FIFO_CTRL3, (uint8_t)((ODR_120HZ << 4) | ODR_120HZ)); // giróscopo y acelerómetro a la FIFO a 120 Hz
  ok = ok && wr(FIFO_CTRL4, FIFO_STREAM);
  ok = ok && wr(CTRL1, ODR_120HZ) && wr(CTRL2, ODR_120HZ);            // alto rendimiento
  Serial.printf("[AVO CASCO] IMU LSM6DSV16X %s: 120 Hz, ±16 g, ±2000 dps (lotes IMU_SAMPLE fmt 3, imu_id 4)\n",
                ok ? "OK" : "FALLO al configurar");
  return ok;
}

static void task(void*) {
  static uint8_t batch[IMU_HDR_LEN + HEAD_BATCH * HEAD_SAMPLE_LEN];
  uint32_t seq = 0, pause = 1000;
  for (;;) {
    if (!start()) { s_present = false; vTaskDelay(pdMS_TO_TICKS(pause)); pause = pause < 30000 ? pause * 2 : 30000; continue; }
    s_present = true;
    pause = 1000;
    int16_t acc[3] = {0, 0, 0}, gyr[3] = {0, 0, 0};
    bool new_xl = false, new_gy = false;
    uint8_t n = 0;
    uint32_t t0 = 0, last_data = millis();
    uint16_t i2c_err = 0;
    for (;;) {
      vTaskDelay(pdMS_TO_TICKS(10));
      uint8_t fs[2];
      if (!rd(FIFO_STATUS1, fs, 2)) { if (++i2c_err > 50) break; continue; }
      i2c_err = 0;
      uint16_t words = (uint16_t)(fs[0] | ((fs[1] & 0x01) << 8));
      if (fs[1] & 0x40) s_overruns++;                       // FIFO desbordada: la tarea no llegó a tiempo
      const uint32_t now_us = (uint32_t)esp_timer_get_time();
      if (!words) { if (millis() - last_data > 500) break; continue; }
      last_data = millis();
      const uint16_t samples_now = words / 2;
      for (uint16_t w = 0; w < words; w++) {
        uint8_t d[7];
        if (!rd(FIFO_DATA_OUT_TAG, d, 7)) break;
        const uint8_t tag = d[0] >> 3;
        int16_t v[3] = {(int16_t)(d[1] | (d[2] << 8)), (int16_t)(d[3] | (d[4] << 8)), (int16_t)(d[5] | (d[6] << 8))};
        if (tag == TAG_XL) { memcpy(acc, v, sizeof(acc)); new_xl = true; }
        else if (tag == TAG_GY) { memcpy(gyr, v, sizeof(gyr)); new_gy = true; }
        if (!(new_xl && new_gy)) continue;
        new_xl = new_gy = false;
        if (n == 0) {   // hora de la primera muestra del lote: la última de la ráfaga es «ahora»
          const uint16_t k = w / 2;
          t0 = now_us - (uint32_t)(samples_now > k ? (samples_now - 1 - k) : 0) * HEAD_PERIOD_US;
        }
        uint8_t* p = batch + IMU_HDR_LEN + n * HEAD_SAMPLE_LEN;
        const int16_t s6[6] = {acc[0], acc[1], acc[2], gyr[0], gyr[1], gyr[2]};
        for (int i = 0; i < 6; i++) { p[2 * i] = (uint8_t)s6[i]; p[2 * i + 1] = (uint8_t)((uint16_t)s6[i] >> 8); }
        if (++n == HEAD_BATCH) {
          ImuBatchHeader h;
          h.girth_id = HEAD_GIRTH_ID;
          h.imu_id = HEAD_IMU_ID;
          h.count = n;
          h.fmt = HEAD_FMT;
          h.girth_seq = seq++;
          h.girth_t0_us = t0;
          h.period_us = HEAD_PERIOD_US;
          h.sync_state = casco_back::pps_locked() ? 2 : 1;
          h.reserved = HEAD_UNITS;
          h.back_rx_ms = millis();
          h.girth_to_back_us = 0;   // el mismo reloj que la espalda interna
          encode_imu_header(h, batch, IMU_HDR_LEN);
          if (casco_back::push_head_imu(batch, IMU_HDR_LEN + n * HEAD_SAMPLE_LEN)) s_batches++;
          else s_overruns += n;
          n = 0;
        }
      }
    }
    Serial.println("[AVO CASCO] IMU: sin datos o errores I2C, se reinicia");
    s_present = false;
  }
}

bool init() {
  return xTaskCreatePinnedToCore(task, "casco_imu", 4096, nullptr, 6, nullptr, 0) == pdPASS;
}

}  // namespace casco_imu
