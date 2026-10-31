// AVO BACK 3.10.3 — on/off with the reed of the support (pure logic, host-tested in test/test_espnow.cpp).
//
// The reed no longer switches the battery (a 14 mm reed welded on the inrush current of the board). It only tells the
// Heltec whether the capsule sits in its support: one leg to GND, the other to GPIO7 with the internal pull-up.
//   closed (LOW, magnet of the support)  → running
//   open   (HIGH, capsule out / charging) → after kOpenToSleepMs the firmware cuts Vext (ZED-F9P + antenna at 0 V),
//                                           switches the radio off and enters deep sleep; closing the reed wakes it.
// Workshop mode: pressing USER in the first 3 s after power-up (reed open) ignores the reed until the next restart,
// so the back can be used on the bench without the support.
#pragma once
#include <stdint.h>

namespace avo {

class ReedGate {
 public:
  static const uint32_t kOpenToSleepMs = 3000;   // a short open (bump, reed chatter) never switches off
  static const uint32_t kBootWindowMs = 3000;    // at power-up with the reed open: time to press USER (workshop)

  void set_workshop(bool on) { workshop_ = on; }
  bool workshop() const { return workshop_; }
  // Call often (every loop). Returns true when the back must go to sleep now.
  bool update(uint32_t now_ms, bool reed_closed) {
    closed_ = reed_closed;
    if (workshop_ || reed_closed) { open_ = false; return false; }
    if (!open_) { open_ = true; open_since_ = now_ms; return false; }
    return now_ms - open_since_ >= kOpenToSleepMs;
  }
  bool closed() const { return closed_; }
  // Milliseconds left before sleeping (0 when closed or in workshop mode).
  uint32_t ms_to_sleep(uint32_t now_ms) const {
    if (workshop_ || closed_ || !open_) return 0;
    uint32_t e = now_ms - open_since_;
    return e >= kOpenToSleepMs ? 0 : kOpenToSleepMs - e;
  }

 private:
  bool workshop_ = false;
  bool open_ = false;
  bool closed_ = true;
  uint32_t open_since_ = 0;
};

}  // namespace avo
