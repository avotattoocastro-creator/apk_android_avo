// AVO BACK V4: board map and small hardware-independent helpers (host-tested in test/test_v4.cpp).
// PCB REV B: hardware/back/V4/PCB (ESP32-S3-MINI-1U-N8). Pin numbers = GPIO of the module (see PCB README).
// REV B has no Qi receiver and no Hall sensor: the vest support bridges the SYS and BAT contacts, so the board is
// powered only while it sits on the vest (or from the workshop USB-C).
#pragma once
#include <stdint.h>
#include <string.h>

namespace avo {
namespace v4 {

// ------------------------------------------------------------------ pins (fuente/avo_back_v4_pcb.py, dict GPIO)
static const int PIN_BOOT = 0;          // TP2 (strapping): LOW at reset = ROM download
static const int PIN_BAT_ADC = 2;       // VBAT / 2 (1 MΩ / 1 MΩ + 100 nF)
static const int PIN_ZED_PPS = 4;       // ZED TIMEPULSE (330 Ω)
static const int PIN_ZED_TX1 = 5;       // S3 RX  <- ZED UART1 TX (TX/MISO pad of the URTK1.2)
static const int PIN_S3_TX1 = 6;        // S3 TX  -> ZED UART1 RX (1 kΩ)
static const int PIN_ZED_TX2 = 7;       // S3 RX  <- ZED UART2 TX
static const int PIN_S3_TX2 = 8;        // S3 TX  -> ZED UART2 RX (1 kΩ)
static const int PIN_ZED_RST = 9;       // ZED RESET_N through 1 kΩ: drive LOW only (open-drain use)
static const int PIN_ZED_EN = 10;       // RT9080 EN: HIGH = ZED powered (100 kΩ pull-down: off at boot)
static const int PIN_LED = 11;          // red LED, active LOW
static const int PIN_SD_CLK = 12, PIN_SD_CMD = 13, PIN_SD_D0 = 14, PIN_SD_D1 = 15, PIN_SD_D2 = 16, PIN_SD_D3 = 17;
static const int PIN_SD_CD = 18;        // card-detect switch to GND, 100 kΩ pull-up (polarity checked at run time)
static const int PIN_SD_PWR_N = 21;     // AO3401A gate: LOW = card powered (100 kΩ pull-up: off at boot)
static const int PIN_CHG_PG = 38;       // BQ24072 PGOOD: LOW = workshop USB power present
static const int PIN_CHG_STAT = 39;     // BQ24072 CHG: LOW = charging (USB + capsule on the vest support)
static const float BAT_DIVIDER = 2.0f;

// ------------------------------------------------------------------ pairing gesture (REV B: no button, no sensor)
// The board is powered only while the capsule sits on the vest support, so the gesture is three quick power-ups in a
// row: put the capsule on the support, take it off before kQuickMs, three times. The counter lives in NVS.
class PowerCycleGesture {
 public:
  static const uint32_t kQuickMs = 4000;   // a power-up longer than this breaks the sequence
  static const uint8_t kBoots = 3;
  // stored = counter read from NVS at boot. Returns the counter to write back now; *fire = gesture complete.
  static uint8_t on_boot(uint8_t stored, bool* fire) {
    const uint8_t n = (uint8_t)((stored >= kBoots ? 0 : stored) + 1);
    *fire = n >= kBoots;
    return *fire ? 0 : n;
  }
  // once the board has been up for kQuickMs the sequence is broken and the counter must be cleared
  static bool should_clear(uint32_t uptime_ms) { return uptime_ms >= kQuickMs; }
};

// ------------------------------------------------------------------ PPS statistics (captured in an ISR, read in loop)
struct PpsStats {
  uint32_t count = 0;
  int32_t last_period_us = 0;     // last period (µs) between two PPS edges
  int32_t max_dev_us = 0;         // max |period − 1 s| seen while locked (> 0 = jitter of the S3 timestamp)
  uint64_t last_us = 0;
  // feed an edge timestamp (µs, monotonic). Periods outside 0.5–1.5 s (start-up, lost pulses) are not counted as jitter.
  void edge(uint64_t t_us) {
    if (count) {
      int64_t p = (int64_t)(t_us - last_us);
      last_period_us = (int32_t)p;
      if (p > 500000 && p < 1500000) {
        int32_t d = (int32_t)(p - 1000000); if (d < 0) d = -d;
        if (d > max_dev_us) max_dev_us = d;
      }
    }
    last_us = t_us;
    count++;
  }
  bool alive(uint64_t now_us) const { return count && now_us - last_us < 2000000ull; }
};

// ------------------------------------------------------------------ SD logger buffer (single producer, single consumer)
// The GNSS loop pushes raw ZED bytes; the SD task pops chunks. When the card is slow the oldest data is NOT
// overwritten: new bytes are dropped and counted (a gap in the log is visible, a corrupted frame is not).
template <size_t N>
class ByteFifo {
 public:
  size_t push(const uint8_t* d, size_t n) {
    size_t free_ = N - 1 - used();
    if (n > free_) { dropped_ += (uint32_t)(n - free_); n = free_; }
    for (size_t i = 0; i < n; i++) { buf_[head_] = d[i]; head_ = (head_ + 1) % N; }
    return n;
  }
  size_t pop(uint8_t* out, size_t max) {
    size_t n = 0;
    while (n < max && tail_ != head_) { out[n++] = buf_[tail_]; tail_ = (tail_ + 1) % N; }
    return n;
  }
  size_t used() const { return (head_ + N - tail_) % N; }
  uint32_t dropped() const { return dropped_; }

 private:
  uint8_t buf_[N];
  volatile size_t head_ = 0, tail_ = 0;
  uint32_t dropped_ = 0;
};

// battery: ADC millivolts at the divider → cell millivolts (0 = not a Li-ion reading)
inline uint16_t battery_mv_from_adc(uint32_t adc_mv) {
  uint32_t mv = (uint32_t)(adc_mv * BAT_DIVIDER);
  return (mv < 2500 || mv > 4600) ? 0 : (uint16_t)mv;
}

}  // namespace v4
}  // namespace avo
