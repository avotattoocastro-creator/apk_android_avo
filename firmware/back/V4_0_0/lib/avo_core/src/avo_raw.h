// AVO RAW FORMAT v1 — session files on MicroSD. Normative spec: RAW_FORMAT.md
// Uses only C stdio + POSIX (works on the host and on ESP-IDF FATFS/VFS).
#pragma once
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include "avo_ring.h"

namespace avo {

static const uint16_t RAW_FORMAT_VERSION = 1;
static const size_t RAW_FILE_HDR = 512;
static const size_t RAW_BLOCK_HDR = 36;
static const uint32_t RAW_BLOCK_MAGIC = 0x424F5641;  // "AVOB"
static const size_t RAW_MAX_BLOCK_PAYLOAD = 64 * 1024;

enum RawBlockFlag : uint16_t { BF_PREBUFFER = 0x0001, BF_CLEAN_CLOSE = 0x0002, BF_AFTER_RECOVERY = 0x0004, BF_AFTER_ERROR = 0x0008 };

struct RawFileMeta {
  char session_id[24] = {0};
  uint16_t segment = 1;
  uint16_t flags = 0;               // b0 resumed after reboot
  uint64_t created_rtc_ms = 0;      // 0 = RTC time unknown
  uint32_t created_uptime_ms = 0;
  uint32_t boot_count = 0;
  char chest_fw[16] = {0};
  char back_fw[16] = {0};
  char chest_dev[16] = {0};
  char back_dev[16] = {0};
  uint32_t horse_id = 0;
  char horse_name[24] = {0};
  uint32_t rider_id = 0;
  char rider_name[24] = {0};
  uint8_t fence_id = 0;
  uint8_t start_reason = 0;
  uint8_t exit_action = 0;
  uint8_t pre_s = 0, post_s = 0;
  uint32_t config_crc = 0;
  uint8_t gnss_rate_hz = 0, constellations = 0;
  uint16_t imu_rate_hz = 0;
  uint32_t uart_baud = 0;
};
void raw_meta_encode(const RawFileMeta& m, uint8_t out[RAW_FILE_HDR]);
bool raw_meta_decode(const uint8_t in[RAW_FILE_HDR], RawFileMeta* m);

class RawWriter {
 public:
  // block_buf must hold RAW_BLOCK_HDR + max_payload bytes.
  void attach_buffer(uint8_t* block_buf, size_t max_payload);
  // Creates a new segment file. Never overwrites an existing file.
  bool open(const char* path, const RawFileMeta& meta, uint32_t first_block_seq);
  bool is_open() const { return f_ != nullptr; }
  // Appends a record to the pending block. Writes the block when it is full.
  // Returns false on I/O error (record kept in the pending block).
  bool append(const RecHdr& h, const uint8_t* data, uint64_t rtc_ms, uint32_t uptime_ms);
  bool has_room(size_t len) const { return pend_ + REC_HDR + len <= maxp_; }
  // Writes the pending block (if any) and fflush(); fsync if sync.
  bool flush(bool sync, uint64_t rtc_ms, uint32_t uptime_ms, uint16_t extra_flags = 0);
  bool close(bool clean, uint64_t rtc_ms, uint32_t uptime_ms);
  // Abandon a failed file without further writes (pending data retained).
  void abandon();
  size_t pending_bytes() const { return pend_; }
  uint64_t file_bytes() const { return bytes_; }
  uint32_t next_block_seq() const { return seq_; }
  uint32_t blocks_written() const { return blocks_; }
  bool error() const { return err_; }
  void set_block_flags(uint16_t f) { flags_ |= f; }

 private:
  bool write_block(uint64_t rtc_ms, uint32_t uptime_ms, uint16_t extra);
  FILE* f_ = nullptr;
  uint8_t* buf_ = nullptr;
  size_t maxp_ = 0, pend_ = 0;
  uint16_t nrec_ = 0, flags_ = 0;
  uint32_t seq_ = 0, blocks_ = 0;
  uint64_t bytes_ = 0;
  bool err_ = false;
};

struct RawScanResult {
  bool header_ok = false;
  RawFileMeta meta;
  uint32_t blocks = 0;
  uint32_t records = 0;
  uint64_t file_size = 0;
  uint64_t valid_end = 0;          // offset after the last valid block
  uint32_t first_block_seq = 0, last_block_seq = 0;
  uint64_t last_rtc_ms = 0;
  uint32_t last_uptime_ms = 0;
  bool clean_close = false;
  bool tail_garbage = false;       // bytes after valid_end (torn write)
  uint32_t bad_records = 0;
};
typedef void (*RawRecordCb)(const RecHdr& h, const uint8_t* data, uint32_t block_seq, uint16_t block_flags, void* ctx);
// Scans a segment; stops at the first invalid block. work_buf >= RAW_BLOCK_HDR+RAW_MAX_BLOCK_PAYLOAD.
bool raw_scan(const char* path, uint8_t* work_buf, size_t work_cap, RawRecordCb cb, void* ctx, RawScanResult* r);
// Truncates the segment to the last valid block (crash recovery). Returns true if file is usable.
bool raw_recover(const char* path, uint8_t* work_buf, size_t work_cap, RawScanResult* r, bool* truncated);

// ---- per-session state file, written A/B with a generation counter.
enum class SessionFileState : uint8_t { OPEN = 1, CLOSED = 2, CLOSED_RECOVERED = 3, UPLOADED = 4 };
struct SessionMetaFile {
  uint32_t gen = 0;
  char session_id[24] = {0};
  SessionFileState state = SessionFileState::OPEN;
  uint16_t segments = 1;
  uint8_t start_reason = 0;
  uint8_t manual = 0;
  uint32_t last_block_seq = 0;
  uint64_t start_rtc_ms = 0;
  uint64_t last_rtc_ms = 0;       // updated periodically while recording
  uint32_t active_ms = 0;
  uint32_t reboots = 0;
  uint8_t sha256[32] = {0};       // of the concatenated segments, set when upload confirmed
  uint64_t total_bytes = 0;
};
static const size_t SESSION_META_LEN = 128;
bool session_meta_write(const char* dir, SessionMetaFile* m);  // increments gen, alternates A/B
bool session_meta_read(const char* dir, SessionMetaFile* m);   // newest valid copy

}  // namespace avo
