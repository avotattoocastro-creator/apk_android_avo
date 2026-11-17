// AVO GIRTH 0.5.0 — MAX30003 driver (CJMCU-30003 module, SPI) for the XIAO ESP32-C6.
// Own task: waits for INTB (FIFO threshold / overflow / lead-off), reads the FIFO, converts to 0,1 µV, time-stamps the
// samples with EcgClock and hands bursts to the main loop through a queue. Nothing waits forever: a module that does
// not answer is retried with a growing pause; without 32 768 Hz on FCLK (module without crystal) the clock is
// generated on the FCLK pin automatically and the choice is remembered.
#pragma once
#include <Arduino.h>
#include "girth_ecg.h"

namespace girth {

struct EcgPins { int cs, sck, miso, mosi, intb, fclk; };

enum class EcgState : uint8_t { OFF, STARTING, RUNNING, ERROR };

static const uint8_t ECG_BURST_MAX = 32;
struct EcgBurst {
  uint32_t t0_us;              // girth clock of the first sample
  float period_us;             // current estimate of the sample period
  uint8_t count;
  bool leads_off;
  int32_t duv[ECG_BURST_MAX];  // 0,1 µV, ECG_INVALID when not valid
};

struct EcgStatus {
  EcgState state = EcgState::OFF;
  uint32_t info = 0;           // INFO register (identity)
  uint8_t gain_code = 1;
  bool fclk_generated = false;
  bool leads_off = true;
  float rate_hz = 0;           // measured sample rate (girth clock)
  uint32_t samples = 0, invalid = 0, overflows = 0, starts = 0, start_failures = 0, dropped_queue = 0;
  int32_t last_duv = 0;
  int32_t p2p_duv = 0;         // peak-to-peak of the last second (signal check while mounting)
  char last_error[48] = "";
};

class Max30003 {
 public:
  void begin(const EcgPins& pins, QueueHandle_t out, uint8_t gain_code, int fclk_mode /* -1 auto, 0 off, 1 on */);
  EcgStatus status();
  void request_restart() { restart_ = true; }
  void set_gain(uint8_t code) { gain_ = code & 3; restart_ = true; }
  bool fclk_generated() const { return fclk_on_; }

 private:
  static void task_entry(void* self);
  void task();
  bool start();
  void stop_clock();
  void start_clock();
  uint32_t rd(uint8_t reg);
  void wr(uint8_t reg, uint32_t v);

  EcgPins p_{};
  QueueHandle_t out_ = nullptr;
  TaskHandle_t task_ = nullptr;
  SemaphoreHandle_t mtx_ = nullptr;
  EcgStatus st_;
  EcgClock clock_;
  volatile bool restart_ = false;
  uint8_t gain_ = 1;
  int fclk_mode_ = -1;
  bool fclk_on_ = false;
};

}  // namespace girth
