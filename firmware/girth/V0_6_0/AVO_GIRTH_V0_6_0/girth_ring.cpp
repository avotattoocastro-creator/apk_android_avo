#include "girth_ring.h"

namespace girth {

// ---------------------------------------------------------------- pattern (portable, host-tested)
Rgb ring_colour(const RingState& s, uint32_t now_ms) {
  const Rgb off{0, 0, 0}, green{0, 40, 0}, blue{0, 0, 45}, amber{45, 18, 0}, red{50, 0, 0}, orange{40, 10, 0};
  uint32_t ph = now_ms % 2000;
  auto flash = [&](int n, uint32_t on_ms, uint32_t gap_ms) {   // n flashes at the start of each 2 s period
    for (int k = 0; k < n; ++k) {
      uint32_t t0 = (uint32_t)k * (on_ms + gap_ms);
      if (ph >= t0 && ph < t0 + on_ms) return true;
    }
    return false;
  };
  // on the charger: steady orange while charging, steady green when full (the LEDs are on mains power then)
  if (s.on_mount && s.charging) return orange;
  if (s.on_mount && !s.linked) return green;
  // looking for the back: short blue blink every 300 ms
  if (!s.linked) return (now_ms % 600) < 80 ? blue : off;
  // linked: problems first
  if (!s.imu_ok) return flash(2, 80, 120) ? red : off;
  if (s.ecg_running && s.leads_off) return flash(3, 80, 120) ? amber : off;   // electrodes: check contact / gel
  if (s.bat_pct && s.bat_pct < 15) return flash(1, 80, 0) ? red : off;
  return flash(1, 60, 0) ? green : off;                                         // all fine
}

}  // namespace girth

#ifdef ARDUINO
#include <Arduino.h>

namespace girth {

// SK6812 timing with a 10 MHz RMT clock (0,1 µs ticks): 0 = 0,3 µs high + 0,9 µs low · 1 = 0,6 + 0,6 · reset ≥ 80 µs
bool Ring::begin(int pin_din, int pin_en, int n_leds) {
  din_ = pin_din; en_ = pin_en; n_ = n_leds;
  pinMode(en_, OUTPUT);
  digitalWrite(en_, LOW);                    // VLED cut
  ok_ = rmtInit(din_, RMT_TX_MODE, RMT_MEM_NUM_BLOCKS_1, 10000000);
  if (!ok_) { pinMode(din_, OUTPUT); digitalWrite(din_, LOW); }
  powered_ = false; cur_ = {0, 0, 0};
  return ok_;
}

void Ring::write_all(Rgb c) {
  if (!ok_ || n_ <= 0 || n_ > 8) return;
  rmt_data_t sym[8 * 24];
  int k = 0;
  for (int i = 0; i < n_; ++i) {
    uint32_t grb = ((uint32_t)c.g << 16) | ((uint32_t)c.r << 8) | c.b;
    for (int bit = 23; bit >= 0; --bit) {
      bool one = (grb >> bit) & 1;
      sym[k].level0 = 1; sym[k].duration0 = one ? 6 : 3;
      sym[k].level1 = 0; sym[k].duration1 = one ? 6 : 9;
      ++k;
    }
  }
  rmtWrite(din_, sym, k, 10);                // idle level LOW afterwards
  delayMicroseconds(100);                    // latch
}

void Ring::show(Rgb c) {
  if (!enabled_) c = {0, 0, 0};
  if (c == cur_ && (powered_ || c.dark())) return;
  if (c.dark()) {
    if (powered_) { write_all(c); digitalWrite(en_, LOW); powered_ = false; }   // DIN stays LOW (RMT idle)
  } else {
    if (!powered_) { digitalWrite(en_, HIGH); powered_ = true; delayMicroseconds(1500); }  // VLED up, LEDs reset
    write_all(c);
  }
  cur_ = c;
}

void Ring::set_enabled(bool e) {
  enabled_ = e;
  if (!e) show({0, 0, 0});
}

}  // namespace girth
#endif
