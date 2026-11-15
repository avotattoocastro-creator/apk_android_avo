#include "girth_lsm6dsv.h"
#include <Wire.h>

namespace girth {

using namespace imu6;

bool Lsm6dsv::wr(uint8_t addr, uint8_t reg, uint8_t v) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(v);
  if (Wire.endTransmission() != 0) { st_.i2c_errors++; return false; }
  return true;
}

bool Lsm6dsv::rd(uint8_t addr, uint8_t reg, uint8_t* d, size_t n) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) { st_.i2c_errors++; return false; }
  if (Wire.requestFrom((int)addr, (int)n) != (int)n) { st_.i2c_errors++; return false; }
  for (size_t i = 0; i < n; i++) d[i] = Wire.read();
  return true;
}

// read-modify-write of a register of the embedded-functions bank
bool Lsm6dsv::emb_rmw(uint8_t reg, uint8_t mask, uint8_t bits) {
  uint8_t v = 0;
  bool ok = wr(LSM_ADDR, FUNC_CFG_ACCESS, 0x80) && rd(LSM_ADDR, reg, &v, 1) &&
            wr(LSM_ADDR, reg, (uint8_t)((v & ~mask) | (bits & mask)));
  ok = wr(LSM_ADDR, FUNC_CFG_ACCESS, 0x00) && ok;
  return ok;
}

void Lsm6dsv::fail(const char* why) {
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.last_error = why; st_.state = ImuState::ERROR; st_.start_failures++;
  xSemaphoreGive(mtx_);
}

void Lsm6dsv::begin(const ImuPins& pins, uint32_t, QueueHandle_t out_queue) {
  pins_ = pins; q_ = out_queue;
  mtx_ = xSemaphoreCreateMutex();
  pinMode(pins_.int1, INPUT);
  pinMode(pins_.int2, INPUT);
  pinMode(pins_.mag_int, INPUT);
  Wire.begin(pins_.sda, pins_.scl, 400000);
  Wire.setTimeOut(20);
  xTaskCreate(task_entry, "imu", 4096, this, 6, &th_);
}

void Lsm6dsv::hold_in_reset() {
  wr(LSM_ADDR, CTRL1, 0x00);        // accelerometer power-down
  wr(LSM_ADDR, CTRL2, 0x00);        // gyroscope power-down
  wr(MMC_ADDR, MMC_CTRL2, 0x00);    // magnetometer: no continuous mode (≈ 1 µA)
}

ImuStatus Lsm6dsv::status() {
  ImuStatus s;
  xSemaphoreTake(mtx_, portMAX_DELAY);
  s = st_;
  xSemaphoreGive(mtx_);
  return s;
}

bool Lsm6dsv::start() {
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.state = ImuState::STARTING; st_.starts++;
  xSemaphoreGive(mtx_);
  uint8_t id = 0;
  if (!rd(LSM_ADDR, WHO_AM_I, &id, 1)) { fail("LSM6DSV16X sin ACK en 0x6A"); return false; }
  if (id != LSM_ID) { fail("LSM6DSV16X: WHO_AM_I distinto de 0x70"); return false; }
  wr(LSM_ADDR, CTRL3, 0x01);                         // software reset
  delay(20);
  bool ok = wr(LSM_ADDR, CTRL3, 0x40 | 0x04);        // BDU + IF_INC
  ok = ok && wr(LSM_ADDR, CTRL8, FS_XL_16G);
  ok = ok && wr(LSM_ADDR, CTRL6, FS_G_2000DPS);
  ok = ok && wr(LSM_ADDR, FIFO_CTRL3, (uint8_t)((ODR_120HZ << 4) | ODR_120HZ));   // batch gyro and accel at 120 Hz
  ok = ok && wr(LSM_ADDR, FIFO_CTRL4, FIFO_STREAM);
  // SFLP: game rotation vector at 120 Hz into the FIFO, then (re)initialise the filter
  ok = ok && emb_rmw(SFLP_ODR, 0x38, (uint8_t)(SFLP_120HZ << 3));
  ok = ok && emb_rmw(EMB_FUNC_FIFO_EN_A, 0x32, 0x02);                 // game RV only (no gravity / gyro bias words)
  ok = ok && emb_rmw(EMB_FUNC_EN_A, 0x02, 0x02);
  ok = ok && emb_rmw(EMB_FUNC_INIT_A, 0x02, 0x02);
  ok = ok && wr(LSM_ADDR, CTRL1, ODR_120HZ);                           // high-performance mode
  ok = ok && wr(LSM_ADDR, CTRL2, ODR_120HZ);
  if (!ok) { fail("LSM6DSV16X: error I2C al configurar"); return false; }
  // magnetometer (optional: without it the samples carry mag = 0 and have bit 2 cleared)
  uint8_t pid = 0;
  bool mag = rd(MMC_ADDR, MMC_PRODUCT_ID, &pid, 1) && pid == MMC_PID;
  if (mag) {
    wr(MMC_ADDR, MMC_CTRL1, 0x80); delay(15);        // software reset
    mag = wr(MMC_ADDR, MMC_CTRL1, MMC_CTRL1_BW100) && wr(MMC_ADDR, MMC_CTRL0, MMC_CTRL0_AUTO_SR) &&
          wr(MMC_ADDR, MMC_CTRL2, MMC_CTRL2_CM100);
  }
  clock_.reset(ODR_PERIOD_US);
  xSemaphoreTake(mtx_, portMAX_DELAY);
  st_.state = ImuState::RUNNING; st_.mag_ok = mag; st_.last_error = mag ? "-" : "MMC5983MA no responde (sin magnetometro)";
  xSemaphoreGive(mtx_);
  return true;
}

void Lsm6dsv::task_entry(void* arg) { static_cast<Lsm6dsv*>(arg)->task(); }

void Lsm6dsv::task() {
  uint32_t pause = 1000;
  for (;;) {
    restart_req_ = false;
    if (!start()) { delay(pause); pause = pause < 10000 ? pause * 2 : 10000; continue; }
    pause = 1000;
    run();
    xSemaphoreTake(mtx_, portMAX_DELAY); st_.restarts_running++; xSemaphoreGive(mtx_);
    delay(200);
  }
}

void Lsm6dsv::run() {
  int16_t acc[3] = {0, 0, 0}, gyr[3] = {0, 0, 0}, mag_q4[3] = {0, 0, 0};
  float quat[4] = {0, 0, 0, 1};
  bool new_xl = false, new_gy = false, have_q = false;
  uint32_t last_data_ms = millis(), mag_ms = 0, sec_ms = millis(), sec_n = 0;
  Sample pend[32];
  while (!restart_req_) {
    vTaskDelay(pdMS_TO_TICKS(10));
    uint32_t now = millis();
    if (st_.mag_ok && now - mag_ms >= 10) {
      mag_ms = now;
      uint8_t b[7];
      if (rd(MMC_ADDR, MMC_XOUT0, b, 7)) { mmc_to_q4(b, mag_q4); st_.mag_reads++; }
    }
    uint8_t fs[2];
    if (!rd(LSM_ADDR, FIFO_STATUS1, fs, 2)) { if (st_.i2c_errors > 50) { fail("LSM6DSV16X: errores I2C"); return; } continue; }
    uint16_t words = (uint16_t)(fs[0] | ((fs[1] & 0x01) << 8));
    if (fs[1] & 0x40) { xSemaphoreTake(mtx_, portMAX_DELAY); st_.lost++; xSemaphoreGive(mtx_); clock_.gap(); }   // FIFO overrun
    if (!words) {
      if (now - last_data_ms > 500) { fail("LSM6DSV16X: FIFO sin datos"); return; }
      continue;
    }
    last_data_ms = now;
    int n = 0;
    for (uint16_t w = 0; w < words; w++) {
      uint8_t d[7];
      if (!rd(LSM_ADDR, FIFO_DATA_OUT_TAG, d, 7)) break;
      st_.fifo_words++;
      uint8_t tag = d[0] >> 3;
      int16_t v[3] = {(int16_t)(d[1] | (d[2] << 8)), (int16_t)(d[3] | (d[4] << 8)), (int16_t)(d[5] | (d[6] << 8))};
      if (tag == TAG_XL) { memcpy(acc, v, sizeof(acc)); new_xl = true; }
      else if (tag == TAG_GY) { memcpy(gyr, v, sizeof(gyr)); new_gy = true; }
      else if (tag == TAG_GAME_RV) {
        uint16_t h[3] = {(uint16_t)v[0], (uint16_t)v[1], (uint16_t)v[2]};
        sflp_to_quat(h, quat); have_q = true;
      }
      if (new_xl && new_gy && n < 32) {
        Sample& s = pend[n++];
        s = Sample();
        float ms2[3], g[3];
        acc_raw_to_q8(acc, s.acc, ms2);
        gyro_raw_to_q9(gyr, s.gyro);
        memcpy(s.mag, mag_q4, sizeof(s.mag));
        gravity_in_sensor(quat, g);
        for (int i = 0; i < 3; i++) s.lin[i] = to_q(ms2[i] - g[i], 256.0f);
        quat_to_q14(quat, s.quat);
        s.acc_status = s.gyro_status = 3;
        s.mag_status = st_.mag_ok ? 3 : 0;
        s.rv_status = have_q ? 3 : 0;
        s.have = 1 | (st_.mag_ok ? 2 : 0) | (have_q ? 4 | 8 : 0);
        new_xl = new_gy = false;
      }
    }
    if (n) {
      uint32_t t0 = clock_.burst(micros(), n);
      float per = (float)clock_.period_us();
      for (int k = 0; k < n; k++) {
        pend[k].t_us = t0 + (uint32_t)(k * per + 0.5f);
        if (xQueueSend(q_, &pend[k], 0) != pdTRUE) { xSemaphoreTake(mtx_, portMAX_DELAY); st_.dropped_queue++; xSemaphoreGive(mtx_); }
      }
      sec_n += n;
      xSemaphoreTake(mtx_, portMAX_DELAY);
      st_.samples += n; st_.last = pend[n - 1]; st_.period_us = per;
      xSemaphoreGive(mtx_);
    }
    if (now - sec_ms >= 1000) {
      xSemaphoreTake(mtx_, portMAX_DELAY); st_.rate_hz = sec_n * 1000.0f / (now - sec_ms); xSemaphoreGive(mtx_);
      sec_ms = now; sec_n = 0;
    }
  }
}

}  // namespace girth
