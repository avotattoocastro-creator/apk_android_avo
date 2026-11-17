#include "avo_tx_power.h"

namespace avo {

const uint8_t TxPowerPolicy::kLevelQdbm[TxPowerPolicy::kLevels] = {44, 60, 84};   // 11 dBm, 15 dBm, maximum
const int8_t TxPowerPolicy::kLevelDbm[TxPowerPolicy::kLevels] = {11, 15, 20};

int TxPowerPolicy::needed_level(int worst_rssi_dbm) {
  // Level at the peer ≈ worst_rssi - (peer_tx - our_tx). Needed our_tx = peer_tx + target - worst_rssi.
  const int need_dbm = kAssumedPeerTxDbm + kTargetAtPeerDbm - worst_rssi_dbm;
  for (int i = 0; i < kLevels; i++)
    if (kLevelDbm[i] >= need_dbm) return i;
  return kLevels - 1;
}

bool TxPowerPolicy::update(uint32_t now_ms, bool linked, int worst_rssi_dbm, uint32_t new_tx_fail) {
  const int before = level_;
  const int top = kLevels - 1;
  if (!linked || worst_rssi_dbm >= 0 || new_tx_fail > 0) {
    // no link, no packet in the last second or a lost packet: maximum and keep it for a while
    level_ = top;
    hold_ = true;
    hold_until_ = now_ms + kHoldMaxMs;
    win_open_ = false;
    return level_ != before;
  }
  const int need = needed_level(worst_rssi_dbm);
  if (need > level_) {                       // up: immediately
    go(need, now_ms);
    return true;
  }
  if (hold_ && (int32_t)(now_ms - hold_until_) < 0) return false;
  hold_ = false;
  if (!win_open_) { win_open_ = true; win_start_ = now_ms; win_need_ = need; return false; }
  if (need > win_need_) win_need_ = need;
  if (now_ms - win_start_ >= kStepDownMs) {
    if (win_need_ < level_) { go(level_ - 1, now_ms); return true; }   // down: one step after a calm window
    win_open_ = false;
  }
  return false;
}

}  // namespace avo
