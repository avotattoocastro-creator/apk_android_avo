// AVO GIRTH 0.4.0 — BNO085 over I²C (SHTP) on the XIAO ESP32-C6, in its own FreeRTOS task.
//
// Wiring (unchanged, see hardware/girth/REV5): PS0+PS1–D0 (GPIO0) · RST–D1 (GPIO1) · INT–D2 (GPIO2) ·
// CS–D3 (GPIO21) · ADD–D4 (GPIO22) · SDA–D5 (GPIO23) · SCL–D6 (GPIO16).
// I²C mode needs PS0 = PS1 = 0 when RST is released; ADD (SA0) = 0 selects address 0x4A (0x4B is tried too).
// CS is held high (unused in I²C mode). Same levels as the 0.2.4-diag boot test that found INT low at
// ~94 ms and an ACK at 0x4A.
//
// Start-up (every attempt is bounded in time, nothing waits forever):
//   1. RST low 10 ms, release, wait for INT low (≤ 600 ms)          -> "INT no baja tras el reset"
//   2. I²C ACK at 0x4A / 0x4B                                        -> "sin ACK"
//   3. read the start-up packets (advertisement, "reset complete")
//   4. Product ID request → response 0xF8 (proves SH-2 works, not only the I²C ACK) -> "SH-2 no responde"
//   5. enable accelerometer, gyroscope, magnetometer, linear acceleration and game rotation vector
//   6. at least 20 accelerometer reports in 1 s                     -> "sin muestras"
// Running: reads on every INT; if the BNO resets itself it is configured again; if no sample arrives for
// 1 s, or there are repeated I²C errors, it starts again with a growing pause (1 → 10 s). After 3 failed
// attempts at 400 kHz it alternates with 100 kHz.
#pragma once
#include <Arduino.h>
#include "girth_sh2.h"

namespace girth {

struct BnoPins { int ps, rst, intn, cs, add, sda, scl; };

enum class BnoState : uint8_t { OFF = 0, STARTING, RUNNING, ERROR };

struct BnoStatus {
  BnoState state = BnoState::OFF;
  const char* last_error = "-";   // text of the last failure (static string)
  uint8_t addr = 0;
  uint32_t i2c_hz = 0;
  int int_ms = -1;                // ms from RST release to INT low (last start)
  uint32_t starts = 0, start_failures = 0, i2c_errors = 0, restarts_running = 0;
  uint32_t samples = 0, lost = 0, dropped_queue = 0, unknown = 0, resets_seen = 0;
  float rate_hz = 0;              // measured accelerometer rate over the last second
  ProductId product;
  uint32_t interval_us[16] = {0}; // confirmed by the BNO (Get Feature Response), by report id
  Sample last;                    // last sample (for the serial monitor)
};

class Bno085 {
 public:
  // interval_us: sample period requested for all reports (10000 = 100 Hz)
  void begin(const BnoPins& pins, uint32_t interval_us, QueueHandle_t out_queue);
  void request_restart() { restart_req_ = true; }
  void hold_in_reset();           // before deep sleep
  BnoStatus status();             // copy, thread-safe
  uint32_t interval_us() const { return interval_us_; }

 private:
  static void task_entry(void* arg);
  void task();
  bool start();
  void run();
  bool read_packet(uint8_t* ch, size_t* len);
  bool write_packet(uint8_t ch, const uint8_t* d, size_t n);
  int service(int max_packets);
  bool wait_int_low(uint32_t ms);
  void fail(const char* why);
  static void on_sample(const Sample& s, void* ctx);
  static void IRAM_ATTR isr(void* arg);

  BnoPins pins_{};
  uint32_t interval_us_ = 10000;
  QueueHandle_t q_ = nullptr;
  TaskHandle_t th_ = nullptr;
  SemaphoreHandle_t mtx_ = nullptr;
  volatile uint32_t int_us_ = 0;
  volatile bool restart_req_ = false;
  bool attached_ = false;
  void detach_int();
  uint8_t addr_ = 0x4A;
  uint32_t hz_ = 400000;
  uint8_t seq_[6] = {0};
  uint8_t buf_[1024];
  Assembler asm_;
  BnoStatus st_;
  uint32_t rate_count_ = 0, rate_t0_ = 0, last_sample_ms_ = 0;
};

}  // namespace girth
