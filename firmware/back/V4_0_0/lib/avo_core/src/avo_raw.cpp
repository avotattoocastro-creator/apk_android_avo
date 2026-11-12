#include "avo_raw.h"
#include "avo_bytes.h"
#include "avo_crc.h"
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

namespace avo {

void raw_meta_encode(const RawFileMeta& m, uint8_t out[RAW_FILE_HDR]) {
  memset(out, 0, RAW_FILE_HDR);
  ByteWriter w(out, RAW_FILE_HDR);
  w.bytes("AVORAW1", 8);
  w.u16(RAW_FORMAT_VERSION); w.u16((uint16_t)RAW_FILE_HDR);
  w.str(m.session_id, 24); w.u16(m.segment); w.u16(m.flags); w.u64(m.created_rtc_ms);
  w.u32(m.created_uptime_ms); w.u32(m.boot_count); w.str(m.chest_fw, 16); w.str(m.back_fw, 16);
  w.str(m.chest_dev, 16); w.str(m.back_dev, 16); w.u32(m.horse_id); w.str(m.horse_name, 24);
  w.u32(m.rider_id); w.str(m.rider_name, 24); w.u8(m.fence_id); w.u8(m.start_reason); w.u8(m.exit_action);
  w.u8(m.pre_s); w.u8(m.post_s); w.bytes("\0\0\0", 3); w.u32(m.config_crc); w.u8(m.gnss_rate_hz);
  w.u8(m.constellations); w.u16(m.imu_rate_hz); w.u32(m.uart_baud);
  put_u32(out + RAW_FILE_HDR - 4, crc32(out, RAW_FILE_HDR - 4));
}

bool raw_meta_decode(const uint8_t in[RAW_FILE_HDR], RawFileMeta* m) {
  if (memcmp(in, "AVORAW1", 8) != 0) return false;
  if (crc32(in, RAW_FILE_HDR - 4) != get_u32(in + RAW_FILE_HDR - 4)) return false;
  ByteReader r(in, RAW_FILE_HDR);
  r.skip(8);
  uint16_t ver = r.u16();
  uint16_t hl = r.u16();
  if (ver < 1 || hl != RAW_FILE_HDR) return false;
  r.str(m->session_id, 24); m->segment = r.u16(); m->flags = r.u16(); m->created_rtc_ms = r.u64();
  m->created_uptime_ms = r.u32(); m->boot_count = r.u32(); r.str(m->chest_fw, 16); r.str(m->back_fw, 16);
  r.str(m->chest_dev, 16); r.str(m->back_dev, 16); m->horse_id = r.u32(); r.str(m->horse_name, 24);
  m->rider_id = r.u32(); r.str(m->rider_name, 24); m->fence_id = r.u8(); m->start_reason = r.u8();
  m->exit_action = r.u8(); m->pre_s = r.u8(); m->post_s = r.u8(); r.skip(3); m->config_crc = r.u32();
  m->gnss_rate_hz = r.u8(); m->constellations = r.u8(); m->imu_rate_hz = r.u16(); m->uart_baud = r.u32();
  return r.ok();
}

void RawWriter::attach_buffer(uint8_t* b, size_t maxp) {
  buf_ = b;
  maxp_ = maxp > RAW_MAX_BLOCK_PAYLOAD ? RAW_MAX_BLOCK_PAYLOAD : maxp;
}

bool RawWriter::open(const char* path, const RawFileMeta& meta, uint32_t first_seq) {
  if (f_ || !buf_) return false;
  struct stat st;
  if (stat(path, &st) == 0) return false;  // never overwrite
  f_ = fopen(path, "wb");
  if (!f_) { err_ = true; return false; }
  // Unbuffered: a failing write is reported by fwrite itself, so the pending
  // block is never lost inside a stdio buffer.
  setvbuf(f_, nullptr, _IONBF, 0);
  uint8_t hdr[RAW_FILE_HDR];
  raw_meta_encode(meta, hdr);
  if (fwrite(hdr, 1, RAW_FILE_HDR, f_) != RAW_FILE_HDR || fflush(f_) != 0) {
    fclose(f_); f_ = nullptr; err_ = true; return false;
  }
  bytes_ = RAW_FILE_HDR;
  seq_ = first_seq;
  blocks_ = 0;
  err_ = false;
  // pending records (from a failed previous segment) are kept and written next
  return true;
}

bool RawWriter::append(const RecHdr& h, const uint8_t* data, uint64_t rtc_ms, uint32_t up_ms) {
  if (!buf_) return false;
  size_t need = REC_HDR + h.len;
  if (need > maxp_) return false;
  if (pend_ + need > maxp_ || nrec_ == 0xFFFF) {
    if (!f_ || !write_block(rtc_ms, up_ms, 0)) return false;
  }
  uint8_t* p = buf_ + RAW_BLOCK_HDR + pend_;
  rec_hdr_put(h, p);
  if (h.len) memcpy(p + REC_HDR, data, h.len);
  pend_ += need;
  nrec_++;
  if (h.flags & RF_PREBUFFER) flags_ |= BF_PREBUFFER;
  return true;
}

bool RawWriter::write_block(uint64_t rtc_ms, uint32_t up_ms, uint16_t extra) {
  if (!f_) return false;
  if (pend_ == 0 && !(extra & BF_CLEAN_CLOSE)) return true;
  uint8_t* h = buf_;
  uint16_t fl = (uint16_t)(flags_ | extra);
  put_u32(h + 0, RAW_BLOCK_MAGIC);
  put_u32(h + 4, seq_);
  put_u32(h + 8, (uint32_t)pend_);
  put_u16(h + 12, nrec_);
  put_u16(h + 14, fl);
  put_u32(h + 16, up_ms);
  put_u64(h + 20, rtc_ms);
  put_u32(h + 28, crc32(buf_ + RAW_BLOCK_HDR, pend_));
  put_u32(h + 32, crc32(h, 32));
  size_t total = RAW_BLOCK_HDR + pend_;
  size_t w = fwrite(buf_, 1, total, f_);
  if (w != total) { err_ = true; return false; }
  bytes_ += total;
  seq_++;
  blocks_++;
  pend_ = 0;
  nrec_ = 0;
  flags_ = 0;
  return true;
}

bool RawWriter::flush(bool sync, uint64_t rtc_ms, uint32_t up_ms, uint16_t extra) {
  if (!f_) return false;
  if (!write_block(rtc_ms, up_ms, extra)) return false;
  if (fflush(f_) != 0) { err_ = true; return false; }
  if (sync && fsync(fileno(f_)) != 0) { err_ = true; return false; }
  return true;
}

bool RawWriter::close(bool clean, uint64_t rtc_ms, uint32_t up_ms) {
  if (!f_) return false;
  bool ok = flush(true, rtc_ms, up_ms, clean ? BF_CLEAN_CLOSE : 0);
  if (fclose(f_) != 0) ok = false;
  f_ = nullptr;
  return ok;
}

void RawWriter::abandon() {
  if (f_) fclose(f_);
  f_ = nullptr;
}

bool raw_scan(const char* path, uint8_t* wb, size_t wcap, RawRecordCb cb, void* ctx, RawScanResult* r) {
  *r = RawScanResult();
  FILE* f = fopen(path, "rb");
  if (!f) return false;
  fseek(f, 0, SEEK_END);
  long sz = ftell(f);
  fseek(f, 0, SEEK_SET);
  r->file_size = sz > 0 ? (uint64_t)sz : 0;
  uint8_t hdr[RAW_FILE_HDR];
  if (fread(hdr, 1, RAW_FILE_HDR, f) != RAW_FILE_HDR || !raw_meta_decode(hdr, &r->meta)) {
    fclose(f);
    return false;
  }
  r->header_ok = true;
  r->valid_end = RAW_FILE_HDR;
  uint64_t off = RAW_FILE_HDR;
  for (;;) {
    if (wcap < RAW_BLOCK_HDR || fread(wb, 1, RAW_BLOCK_HDR, f) != RAW_BLOCK_HDR) break;
    if (get_u32(wb) != RAW_BLOCK_MAGIC || crc32(wb, 32) != get_u32(wb + 32)) break;
    uint32_t seq = get_u32(wb + 4);
    uint32_t plen = get_u32(wb + 8);
    uint16_t nrec = get_u16(wb + 12);
    uint16_t fl = get_u16(wb + 14);
    uint32_t up = get_u32(wb + 16);
    uint64_t rtc = get_u64(wb + 20);
    uint32_t pcrc = get_u32(wb + 28);
    if (plen > RAW_MAX_BLOCK_PAYLOAD || RAW_BLOCK_HDR + plen > wcap) break;
    if (fread(wb + RAW_BLOCK_HDR, 1, plen, f) != plen) break;
    const uint8_t* pl = wb + RAW_BLOCK_HDR;
    if (crc32(pl, plen) != pcrc) break;
    // block is valid: walk records
    size_t p = 0;
    uint16_t seen = 0;
    while (p + REC_HDR <= plen) {
      RecHdr h;
      rec_hdr_get(pl + p, &h);
      if (p + REC_HDR + h.len > plen) { r->bad_records++; break; }
      if (cb) cb(h, pl + p + REC_HDR, seq, fl, ctx);
      p += REC_HDR + h.len;
      seen++;
    }
    if (seen != nrec) r->bad_records++;
    r->records += seen;
    if (r->blocks == 0) r->first_block_seq = seq;
    r->blocks++;
    r->last_block_seq = seq;
    r->last_rtc_ms = rtc;
    r->last_uptime_ms = up;
    if (fl & BF_CLEAN_CLOSE) r->clean_close = true;
    off += RAW_BLOCK_HDR + plen;
    r->valid_end = off;
  }
  r->tail_garbage = r->file_size > r->valid_end;
  fclose(f);
  return true;
}

bool raw_recover(const char* path, uint8_t* wb, size_t wcap, RawScanResult* r, bool* truncated) {
  *truncated = false;
  if (!raw_scan(path, wb, wcap, nullptr, nullptr, r)) return false;
  if (r->tail_garbage) {
    if (truncate(path, (off_t)r->valid_end) != 0) return false;
    *truncated = true;
  }
  return true;
}

// ---------------------------------------------------------------- session meta (A/B)
static void meta_path(const char* dir, int slot, char* out, size_t cap) {
  snprintf(out, cap, "%s/meta_%c.bin", dir, slot ? 'b' : 'a');
}

static size_t meta_encode(const SessionMetaFile& m, uint8_t* o) {
  memset(o, 0, SESSION_META_LEN);
  ByteWriter w(o, SESSION_META_LEN);
  w.bytes("AVOM", 4); w.u16(1); w.u32(m.gen); w.str(m.session_id, 24); w.u8((uint8_t)m.state);
  w.u16(m.segments); w.u8(m.start_reason); w.u8(m.manual); w.u32(m.last_block_seq); w.u64(m.start_rtc_ms);
  w.u64(m.last_rtc_ms); w.u32(m.active_ms); w.u32(m.reboots); w.bytes(m.sha256, 32); w.u64(m.total_bytes);
  put_u32(o + SESSION_META_LEN - 4, crc32(o, SESSION_META_LEN - 4));
  return SESSION_META_LEN;
}

static bool meta_decode(const uint8_t* p, SessionMetaFile* m) {
  if (memcmp(p, "AVOM", 4) != 0) return false;
  if (crc32(p, SESSION_META_LEN - 4) != get_u32(p + SESSION_META_LEN - 4)) return false;
  ByteReader r(p, SESSION_META_LEN);
  r.skip(4); r.u16();
  m->gen = r.u32(); r.str(m->session_id, 24); m->state = (SessionFileState)r.u8(); m->segments = r.u16();
  m->start_reason = r.u8(); m->manual = r.u8(); m->last_block_seq = r.u32(); m->start_rtc_ms = r.u64();
  m->last_rtc_ms = r.u64(); m->active_ms = r.u32(); m->reboots = r.u32(); r.bytes(m->sha256, 32);
  m->total_bytes = r.u64();
  return r.ok();
}

bool session_meta_write(const char* dir, SessionMetaFile* m) {
  m->gen++;
  uint8_t b[SESSION_META_LEN];
  meta_encode(*m, b);
  char path[160];
  meta_path(dir, (int)(m->gen & 1), path, sizeof(path));
  FILE* f = fopen(path, "wb");
  if (!f) return false;
  bool ok = fwrite(b, 1, sizeof(b), f) == sizeof(b);
  ok = ok && fflush(f) == 0;
  ok = ok && fsync(fileno(f)) == 0;
  ok = (fclose(f) == 0) && ok;
  return ok;
}

bool session_meta_read(const char* dir, SessionMetaFile* m) {
  bool have = false;
  for (int s = 0; s < 2; s++) {
    char path[160];
    meta_path(dir, s, path, sizeof(path));
    FILE* f = fopen(path, "rb");
    if (!f) continue;
    uint8_t b[SESSION_META_LEN];
    size_t n = fread(b, 1, sizeof(b), f);
    fclose(f);
    SessionMetaFile t;
    if (n == sizeof(b) && meta_decode(b, &t) && (!have || t.gen > m->gen)) { *m = t; have = true; }
  }
  return have;
}

}  // namespace avo
