#include "avo_blackbox.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include <string.h>

namespace avo {

static const uint16_t BB_MAGIC = 0xB1B0;

bool Blackbox::decode(const uint8_t* b, BbRecord* r) const {
  if (get_u16(b) != BB_MAGIC) return false;
  if (crc16_ccitt(b, 30) != get_u16(b + 30)) return false;
  r->seq = get_u32(b + 2); r->uptime_ms = get_u32(b + 6); r->rtc_s = get_u32(b + 10); r->boot = get_u32(b + 14);
  r->code = get_u16(b + 18); r->severity = b[20]; r->arg0 = get_u32(b + 22); r->arg1 = get_u32(b + 26);
  return true;
}

bool Blackbox::init(FlashIo* io) {
  io_ = io;
  if (!io_ || io_->sector_size() % REC || io_->size() < 2 * io_->sector_size()) return false;
  slots_ = io_->size() / REC;
  // Find the record with the highest seq (scan every slot; 256 KB = 8192 slots).
  uint32_t best = 0;
  size_t best_slot = 0;
  bool any = false;
  uint8_t b[REC];
  for (size_t i = 0; i < slots_; i++) {
    if (!io_->read(i * REC, b, REC)) continue;
    BbRecord r;
    if (decode(b, &r) && (!any || (int32_t)(r.seq - best) > 0)) { best = r.seq; best_slot = i; any = true; }
  }
  if (!any) { next_ = 0; seq_ = 1; return true; }
  seq_ = best + 1;
  next_ = (best_slot + 1) % slots_;
  // If the next slot is not erased (stale data from the previous lap), its
  // sector is erased on the next write when next_ is at a sector boundary;
  // otherwise move to the next sector boundary to guarantee erased space.
  size_t per = io_->sector_size() / REC;
  if (next_ % per != 0) {
    io_->read(next_ * REC, b, REC);
    bool erased = true;
    for (size_t k = 0; k < REC; k++) if (b[k] != 0xFF) { erased = false; break; }
    if (!erased) next_ = ((next_ / per) + 1) * per % slots_;
  }
  return true;
}

bool Blackbox::append(const BbRecord& in) {
  if (!io_) return false;
  size_t per = io_->sector_size() / REC;
  if (next_ % per == 0) {
    if (!io_->erase_sector(next_ * REC)) { werr_++; return false; }
  }
  uint8_t b[REC];
  memset(b, 0xFF, REC);
  put_u16(b, BB_MAGIC); put_u32(b + 2, seq_); put_u32(b + 6, in.uptime_ms); put_u32(b + 10, in.rtc_s);
  put_u32(b + 14, in.boot); put_u16(b + 18, in.code); b[20] = in.severity; b[21] = 0;
  put_u32(b + 22, in.arg0); put_u32(b + 26, in.arg1);
  put_u16(b + 30, crc16_ccitt(b, 30));
  bool ok = io_->write(next_ * REC, b, REC);
  if (!ok) werr_++;
  seq_++;
  next_ = (next_ + 1) % slots_;
  return ok;
}

int Blackbox::read_recent(int n, Visitor v, void* ctx) {
  if (!io_ || n <= 0) return 0;
  int got = 0;
  size_t i = next_;
  uint32_t expect = seq_ - 1;
  uint8_t b[REC];
  for (size_t k = 0; k < slots_ && got < n; k++) {
    i = (i + slots_ - 1) % slots_;
    if (!io_->read(i * REC, b, REC)) break;
    BbRecord r;
    if (!decode(b, &r)) { expect--; continue; }  // erased or torn slot
    if (r.seq != expect) break;    // older lap / discontinuity
    v(r, ctx);
    got++;
    expect--;
  }
  return got;
}

}  // namespace avo
