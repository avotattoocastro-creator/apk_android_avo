// AVO GIRTH 0.6.0 — IMU of the PCB REV D: ST LSM6DSV16X (accelerometer + gyroscope + SFLP fusion) and MEMSIC
// MMC5983MA (magnetometer), both on I²C at 400 kHz (SDA GPIO23, SCL GPIO16), in their own FreeRTOS task.
//
// LSM6DSV16X: 120 Hz, ±16 g, ±2000 dps, SFLP game rotation vector at 120 Hz, everything through the FIFO (continuous).
// MMC5983MA: continuous 100 Hz with automatic SET/RESET; the last reading is attached to each sample.
// Output: the same girth::Sample as the BNO085 (girth_sh2.h): acc Q8 m/s², gyro Q9 rad/s, mag Q4 µT,
// lin = acc − gravity (from the SFLP quaternion) Q8 m/s², quaternion Q14 (i, j, k, real).
// Time stamps: uniform t0 + k × period, the period learnt from the FIFO counts (same PLL as the ECG, EcgClock).
// Nothing waits forever: WHO_AM_I wrong / I²C errors / FIFO without data for 500 ms -> restart with a growing pause.
#pragma once
#include <Arduino.h>
#include "girth_sh2.h"
#include "girth_ecg.h"
#include "girth_imu6.h"

namespace girth {

struct ImuPins { int sda, scl, int1, int2, mag_int; };

enum class ImuState : uint8_t { OFF = 0, STARTING, RUNNING, ERROR };

struct ImuStatus {
  ImuState state = ImuState::OFF;
  const char* last_error = "-";
  uint8_t addr = imu6::LSM_ADDR;
  uint32_t i2c_hz = 400000;
  bool mag_ok = false;
  uint32_t starts = 0, start_failures = 0, i2c_errors = 0, restarts_running = 0;
  uint32_t samples = 0, lost = 0, dropped_queue = 0, fifo_words = 0, mag_reads = 0;
  float rate_hz = 0;
  float period_us = 0;
  Sample last;
};

class Lsm6dsv {
 public:
  void begin(const ImuPins& pins, uint32_t interval_us, QueueHandle_t out_queue);
  void request_restart() { restart_req_ = true; }
  void hold_in_reset();           // before deep sleep: power-down of both sensors
  ImuStatus status();
  uint32_t interval_us() const { return imu6::ODR_PERIOD_US; }

 private:
  static void task_entry(void* arg);
  void task();
  bool start();
  void run();
  bool wr(uint8_t addr, uint8_t reg, uint8_t v);
  bool rd(uint8_t addr, uint8_t reg, uint8_t* d, size_t n);
  bool emb_rmw(uint8_t reg, uint8_t mask, uint8_t bits);
  void fail(const char* why);

  ImuPins pins_{};
  QueueHandle_t q_ = nullptr;
  TaskHandle_t th_ = nullptr;
  SemaphoreHandle_t mtx_ = nullptr;
  volatile bool restart_req_ = false;
  ImuStatus st_;
  EcgClock clock_;
};

}  // namespace girth
