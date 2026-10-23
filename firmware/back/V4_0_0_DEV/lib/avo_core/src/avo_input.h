// Button / touch gesture detectors and power policy (pure logic, host-testable).
#pragma once
#include <stdint.h>

namespace avo {

// BOOT button: debounced; SHORT (delayed by the double-click window), DOUBLE, LONG.
class BootButton {
 public:
  enum Event { NONE = 0, SHORT, DOUBLE, LONG };
  BootButton(uint16_t debounce_ms = 30, uint16_t double_ms = 350, uint16_t long_ms = 2000)
      : deb_(debounce_ms), dbl_(double_ms), long_(long_ms) {}
  Event update(bool pressed_raw, uint32_t now_ms);
  bool pressed() const { return stable_; }
  // 0..1000 progress of the current hold towards LONG (UI feedback)
  uint16_t hold_permille(uint32_t now_ms) const;
 private:
  uint16_t deb_, dbl_, long_;
  bool raw_ = false, stable_ = false;
  uint32_t raw_t_ = 0, press_t_ = 0, release_t_ = 0;
  bool long_fired_ = false;
  uint8_t clicks_ = 0;
};

// PWR key as seen on GPIO10 (high = pressed). Fires once after hold_ms.
class PowerKey {
 public:
  explicit PowerKey(uint16_t hold_ms = 3000) : hold_(hold_ms) {}
  bool update(bool pressed, uint32_t now_ms);  // true once when the hold completes
  bool short_press() { bool r = short_; short_ = false; return r; }
  uint16_t hold_permille(uint32_t now_ms) const;
 private:
  uint16_t hold_;
  bool down_ = false, fired_ = false, short_ = false;
  uint32_t t_ = 0;
};

// Developer-mode access: continuous touch for hold_ms within a small radius.
class TouchHold {
 public:
  TouchHold(uint32_t hold_ms = 20000, uint16_t release_tol_ms = 250, uint16_t max_move_px = 80)
      : hold_(hold_ms), tol_(release_tol_ms), move_(max_move_px) {}
  enum Event { NONE = 0, ACTIVATE };
  Event update(bool touching, int16_t x, int16_t y, uint32_t now_ms);
  bool active() const { return holding_; }
  // Seconds left, only meaningful during the last 5 s (returns 0 otherwise / not holding).
  uint8_t countdown_s(uint32_t now_ms) const;
  uint32_t held_ms(uint32_t now_ms) const { return holding_ ? now_ms - start_ : 0; }
 private:
  uint32_t hold_;
  uint16_t tol_, move_;
  bool holding_ = false, fired_ = false, need_release_ = false;
  uint32_t start_ = 0, last_touch_ = 0;
  int16_t x0_ = 0, y0_ = 0;
};

enum class PowerLevel : uint8_t { NORMAL = 0, LOWBAT = 1, CRITICAL = 2, UNKNOWN = 3 };
class PowerPolicy {
 public:
  void configure(uint8_t low_pct, uint8_t crit_pct, uint16_t crit_mv) { low_ = low_pct; crit_ = crit_pct; crit_mv_ = crit_mv; }
  // pct < 0 or mv == 0 => unknown. Critical needs 10 s of consecutive evidence and no VBUS.
  PowerLevel update(int pct, uint16_t mv, bool vbus, uint32_t now_ms);
  PowerLevel level() const { return lvl_; }
 private:
  uint8_t low_ = 15, crit_ = 5;
  uint16_t crit_mv_ = 3450;
  PowerLevel lvl_ = PowerLevel::UNKNOWN;
  bool crit_pending_ = false;
  uint32_t crit_since_ = 0;
};

}  // namespace avo
