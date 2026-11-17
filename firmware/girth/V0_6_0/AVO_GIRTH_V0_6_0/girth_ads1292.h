// AVO GIRTH 0.6.0 — TI ADS1292 driver (PCB REV D, SPI mode 1) for the ESP32-C6.
// Own task: waits for DRDY (every 2 ms at 500 sps), reads the 72-bit frame, converts channel 2 (ECG) to 0,1 µV,
// marks samples with the electrodes off as ECG_INVALID, time-stamps bursts of 16 samples with EcgClock and hands them
// to the main loop through a queue (same EcgBurst as the 0.5.0, so the fmt 2 batches do not change).
// Nothing waits forever: a chip that does not answer (wrong ID) is retried with a growing pause; no DRDY for 200 ms
// restarts it.
#pragma once
#include <Arduino.h>
#include "girth_ecg.h"

namespace girth {

struct EcgPins { int cs, sck, miso, mosi, drdy, reset, start; };

enum class EcgState : uint8_t { OFF, STARTING, RUNNING, ERROR };

static const uint8_t ECG_BURST_MAX = 32;
static const uint8_t ECG_BURST_AT = 16;   // samples per burst handed to the main loop (32 ms)
struct EcgBurst {
  uint32_t t0_us;              // girth clock of the first sample
  float period_us;             // current estimate of the sample period
  uint8_t count;
  bool leads_off;
  int32_t duv[ECG_BURST_MAX];  // 0,1 µV, ECG_INVALID when not valid
};

struct EcgStatus {
  EcgState state = EcgState::OFF;
  uint8_t id = 0;              // ID register (0x53 ADS1292, 0x73 ADS1292R)
  uint8_t gain_code = 0;
  bool leads_off = true;
  uint8_t loff_stat = 0;
  float rate_hz = 0;
  uint32_t samples = 0, invalid = 0, bad_frames = 0, starts = 0, start_failures = 0, dropped_queue = 0, stalls = 0;
  int32_t last_duv = 0;
  int32_t p2p_duv = 0;         // peak-to-peak of the last second (signal check while mounting)
  char last_error[48] = "";
};

class Ads1292 {
 public:
  void begin(const EcgPins& pins, QueueHandle_t out, uint8_t gain_code);
  EcgStatus status();
  void request_restart() { restart_ = true; }
  void set_gain(uint8_t code) { gain_ = code & 7; restart_ = true; }
  void power_down();           // before deep sleep (PWDN low)

 private:
  static void task_entry(void* self);
  void task();
  bool start();
  void cmd(uint8_t op);
  void wreg(uint8_t reg, uint8_t v);
  uint8_t rreg(uint8_t reg);

  EcgPins p_{};
  QueueHandle_t out_ = nullptr;
  TaskHandle_t task_ = nullptr;
  SemaphoreHandle_t mtx_ = nullptr;
  EcgStatus st_;
  EcgClock clock_;
  volatile bool restart_ = false;
  uint8_t gain_ = 0;
};

}  // namespace girth
