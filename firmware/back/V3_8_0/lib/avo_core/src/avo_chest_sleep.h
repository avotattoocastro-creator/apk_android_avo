// AVO BACK V3.14.0 — sleep while the chest is off, wake up when it comes back.
//
// The ESP32 cannot hear ESP-NOW in deep sleep (the radio is off), so the back:
//   * goes to deep sleep (GPS at 0 V, radio off) when the chest says it is switching off (BACK_SLEEP command,
//     chest >= 3.7.7) or when its paired chest has not been heard for CHEST_SILENT_SLEEP_MS (90 s);
//   * wakes every LISTEN_PERIOD_S (10 s) by timer, listens LISTEN_WINDOW_MS on the ESP-NOW channel and starts
//     normally only when a packet from ITS paired chest is heard (chest >= 3.7.7 sends a short packet every
//     100 ms while it has no back). Otherwise it goes straight back to sleep.
// Pure logic, host-tested (test/test_espnow.cpp); the sketch does the radio, the GPIOs and the sleep.
#pragma once
#include <stdint.h>
#include <string.h>
#include "avo_espnow_link.h"

namespace avo {

static const uint32_t CHEST_SILENT_SLEEP_MS = 90000;   // user request 09/11/2026: 90 s without the chest
static const uint32_t LISTEN_PERIOD_S = 10;            // user request 09/11/2026: listen every 10 s
static const uint32_t LISTEN_WINDOW_MS = 160;          // > 1.5 x the 100 ms wake beacon of the chest

// Decides when the awake back must go to sleep because the chest is gone.
class ChestSleepPolicy {
 public:
  // boot_ms: when the back finished starting (the 90 s also count from there if the chest was never heard).
  void begin(uint32_t boot_ms) { boot_ms_ = boot_ms; }
  // last_chest_rx_ms: 0 = never heard since boot.
  // blocked: something must keep the back awake (pairing window open, workshop mode, USB charging loop...).
  bool should_sleep(uint32_t now, bool paired, uint32_t last_chest_rx_ms, bool blocked) const {
    if (!paired || blocked) return false;   // an unpaired back must stay awake to be paired
    const uint32_t ref = last_chest_rx_ms ? last_chest_rx_ms : boot_ms_;
    return (uint32_t)(now - ref) >= CHEST_SILENT_SLEEP_MS;
  }
  // Milliseconds left before sleeping (for the serial monitor); 0 = due now.
  uint32_t left_ms(uint32_t now, uint32_t last_chest_rx_ms) const {
    const uint32_t ref = last_chest_rx_ms ? last_chest_rx_ms : boot_ms_;
    const uint32_t el = now - ref;
    return el >= CHEST_SILENT_SLEEP_MS ? 0 : CHEST_SILENT_SLEEP_MS - el;
  }
 private:
  uint32_t boot_ms_ = 0;
};

// During a listening window: is this radio packet a sign that OUR chest is on?
// Accepted: a valid DATA packet of our couple (mac + pair_id), or a PAIR_REQ from our chest's MAC (a chest that
// lost its memory asks to pair again). Girth packets, other couples and broken packets do not wake the back.
inline bool now_is_wake_packet(const uint8_t mac[6], const uint8_t* d, size_t n, const NowPeerRecord& peer) {
  if (!peer.valid || memcmp(mac, peer.mac, 6) != 0) return false;
  NowHeader h;
  const uint8_t* body;
  if (!now_parse(d, n, &h, &body)) return false;
  if (h.kind == NowKind::DATA) return h.pair_id == peer.pair_id;
  return h.kind == NowKind::PAIR_REQ;
}

}  // namespace avo
