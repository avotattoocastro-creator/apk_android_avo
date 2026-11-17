// AVO BACK 3.10.2 — adaptive ESP-NOW transmit power (pure logic, host-tested in test/test_espnow.cpp).
//
// The back used to transmit always at the maximum (~20 dBm) although the chest is ~1 m away and arrives at
// -45..-55 dBm. This policy lowers the power only while the link has a large margin and goes back to the
// maximum at once when it is needed:
//   - the level needed is estimated from the WORST RSSI received in the last second from the linked peers
//     (chest and, if paired, girth), assuming the peer transmits at ~20 dBm and aiming at -62 dBm at the peer
//     (about 25-30 dB above the ESP-NOW sensitivity at 1 Mbit/s);
//   - going UP is immediate; any transmit failure or a second without packets from the chest = maximum,
//     held for 15 s;
//   - going DOWN is one step at a time and only after 10 s in which every second allowed the lower level.
// Levels: 11 dBm, 15 dBm and the maximum (84 = 21 dBm request, the ESP32-S3 caps it at its own maximum,
// exactly what the firmware did before).
#pragma once
#include <stdint.h>

namespace avo {

class TxPowerPolicy {
 public:
  static const int kLevels = 3;
  static const uint8_t kLevelQdbm[kLevels];        // units of 0.25 dBm, as esp_wifi_set_max_tx_power() takes
  static const int8_t kLevelDbm[kLevels];          // same levels in dBm (the maximum counted as 20 dBm)
  static const int8_t kTargetAtPeerDbm = -62;
  static const int8_t kAssumedPeerTxDbm = 20;
  static const uint32_t kHoldMaxMs = 15000;
  static const uint32_t kStepDownMs = 10000;

  // Call once per second.
  //   linked:          the chest link is up (paired and heard recently)
  //   worst_rssi_dbm:  lowest RSSI of the packets received from the chest/girth in the last second (0 = none)
  //   new_tx_fail:     transmit failures since the previous call
  // Returns true when the level changed (the caller then applies qdbm()).
  bool update(uint32_t now_ms, bool linked, int worst_rssi_dbm, uint32_t new_tx_fail);

  int level() const { return level_; }
  uint8_t qdbm() const { return kLevelQdbm[level_]; }
  int8_t dbm() const { return kLevelDbm[level_]; }
  // Level needed for a given worst RSSI (exposed for the tests).
  static int needed_level(int worst_rssi_dbm);

 private:
  int level_ = kLevels - 1;          // start at the maximum (pairing, first contact)
  uint32_t hold_until_ = kHoldMaxMs;   // maximum for the first 15 s after boot
  bool hold_ = true;
  uint32_t win_start_ = 0;
  bool win_open_ = false;
  int win_need_ = 0;
  void go(int lvl, uint32_t now_ms) { level_ = lvl; win_open_ = false; (void)now_ms; }
};

}  // namespace avo
