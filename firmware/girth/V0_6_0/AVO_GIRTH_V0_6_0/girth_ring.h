// AVO GIRTH 0.6.x · light ring of the PCB REV D: 4 × SK6812SIDE-A (GRB, 800 kHz) on GPIO15, power switched by GPIO18.
// The LEDs only get power while something is shown: each SK6812 draws ~1 mA even when dark, so between flashes VLED
// is cut (Q1 AO3401A) and DIN stays LOW (no back-powering through the data input).
#pragma once
#include <stdint.h>

namespace girth {

struct Rgb {
  uint8_t r, g, b;
  bool operator==(const Rgb& o) const { return r == o.r && g == o.g && b == o.b; }
  bool operator!=(const Rgb& o) const { return !(*this == o); }
  bool dark() const { return !r && !g && !b; }
};

// What the ring shows. Pure function of the state and the time (host-tested in test/test_girth.cpp).
struct RingState {
  bool linked;          // the back answers
  bool imu_ok;          // IMU delivering samples
  bool ecg_running;     // ADS1292 running
  bool leads_off;       // ECG electrode(s) without contact
  bool on_mount;        // capsule on the charger/mount (DET low)
  bool charging;        // BQ24072 CHG low
  uint8_t bat_pct;      // 0 = not measured
};

// Colours are dim on purpose (the capsule is a few cm from the eye when mounting the girth).
Rgb ring_colour(const RingState& s, uint32_t now_ms);

class Ring {
 public:
  bool begin(int pin_din, int pin_en, int n_leds);
  void show(Rgb c);               // same colour on every LED; dark → power cut
  void set_enabled(bool e);       // "aro off": always dark
  bool enabled() const { return enabled_; }
  bool powered() const { return powered_; }

 private:
  void write_all(Rgb c);
  int din_ = -1, en_ = -1, n_ = 0;
  bool ok_ = false, powered_ = false, enabled_ = true;
  Rgb cur_{0, 0, 0};
};

}  // namespace girth
