#include "avo_input.h"
#include <stdlib.h>

namespace avo {

BootButton::Event BootButton::update(bool raw, uint32_t now) {
  if (raw != raw_) { raw_ = raw; raw_t_ = now; }
  Event ev = NONE;
  if (raw_ != stable_ && now - raw_t_ >= deb_) {
    stable_ = raw_;
    if (stable_) {
      press_t_ = now;
      long_fired_ = false;
    } else {
      release_t_ = now;
      if (!long_fired_) {
        clicks_++;
        if (clicks_ >= 2) { clicks_ = 0; ev = DOUBLE; }
      } else {
        clicks_ = 0;
      }
    }
  }
  if (stable_ && !long_fired_ && now - press_t_ >= long_) {
    long_fired_ = true;
    clicks_ = 0;  // a long press cancels a pending single click
    return LONG;
  }
  if (!stable_ && clicks_ == 1 && now - release_t_ >= dbl_) { clicks_ = 0; ev = SHORT; }
  return ev;
}

uint16_t BootButton::hold_permille(uint32_t now) const {
  if (!stable_ || long_fired_) return 0;
  uint32_t h = now - press_t_;
  return (uint16_t)(h >= long_ ? 1000 : (h * 1000) / long_);
}

bool PowerKey::update(bool pressed, uint32_t now) {
  if (pressed && !down_) { down_ = true; fired_ = false; t_ = now; }
  if (!pressed && down_) {
    down_ = false;
    if (!fired_ && now - t_ >= 50 && now - t_ < 1000) short_ = true;
  }
  if (down_ && !fired_ && now - t_ >= hold_) { fired_ = true; return true; }
  return false;
}

uint16_t PowerKey::hold_permille(uint32_t now) const {
  if (!down_ || fired_) return 0;
  uint32_t h = now - t_;
  return (uint16_t)(h >= hold_ ? 1000 : (h * 1000) / hold_);
}

TouchHold::Event TouchHold::update(bool touching, int16_t x, int16_t y, uint32_t now) {
  if (touching) {
    if (need_release_) { last_touch_ = now; return NONE; }
    if (!holding_) {
      holding_ = true; fired_ = false; start_ = now; x0_ = x; y0_ = y;
    } else if (abs(x - x0_) > move_ || abs(y - y0_) > move_) {
      start_ = now; x0_ = x; y0_ = y;  // moved: restart the count (not a deliberate hold)
    }
    last_touch_ = now;
    if (!fired_ && now - start_ >= hold_) { fired_ = true; holding_ = false; need_release_ = true; return ACTIVATE; }
  } else if (now - last_touch_ > tol_) {
    holding_ = false;
    need_release_ = false;
  }
  return NONE;
}

uint8_t TouchHold::countdown_s(uint32_t now) const {
  if (!holding_) return 0;
  uint32_t h = now - start_;
  if (h >= hold_ || hold_ - h > 5000) return 0;
  return (uint8_t)((hold_ - h + 999) / 1000);
}

PowerLevel PowerPolicy::update(int pct, uint16_t mv, bool vbus, uint32_t now) {
  if (pct < 0 || mv == 0) { lvl_ = PowerLevel::UNKNOWN; crit_pending_ = false; return lvl_; }
  bool crit_now = !vbus && (pct <= crit_ || mv <= crit_mv_);
  if (crit_now) {
    if (!crit_pending_) { crit_pending_ = true; crit_since_ = now; }
    if (now - crit_since_ >= 10000) { lvl_ = PowerLevel::CRITICAL; return lvl_; }
  } else {
    crit_pending_ = false;
  }
  if (lvl_ == PowerLevel::CRITICAL && !vbus && !crit_now && pct > crit_ + 3) lvl_ = PowerLevel::LOWBAT;
  if (vbus && lvl_ == PowerLevel::CRITICAL) lvl_ = PowerLevel::LOWBAT;
  if (lvl_ != PowerLevel::CRITICAL) {
    if (pct <= low_) lvl_ = PowerLevel::LOWBAT;
    else if (pct > low_ + 3) lvl_ = PowerLevel::NORMAL;
    else if (lvl_ == PowerLevel::UNKNOWN) lvl_ = PowerLevel::NORMAL;
  }
  return lvl_;
}

}  // namespace avo
