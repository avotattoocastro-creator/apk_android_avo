// Blackbox: append-only ring of 32-byte event records in a dedicated flash
// partition. Sectors are erased one at a time as the ring advances, which
// spreads wear evenly; each record carries its own CRC so a torn write only
// loses that record.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace avo {

class FlashIo {
 public:
  virtual ~FlashIo() {}
  virtual size_t size() const = 0;
  virtual size_t sector_size() const = 0;
  virtual bool read(size_t off, void* dst, size_t len) = 0;
  virtual bool write(size_t off, const void* src, size_t len) = 0;
  virtual bool erase_sector(size_t off) = 0;
};

enum class BbCode : uint16_t {
  BOOT = 1, SHUTDOWN = 2, RESET_REASON = 3, WATCHDOG = 4, BROWNOUT = 5, PANIC = 6,
  SD_ERROR = 10, SD_REMOUNT = 11, SD_FULL = 12, BUFFER_SATURATED = 13, RECORDS_DROPPED = 14,
  UART_LOST = 20, UART_RESTORED = 21, UART_CRC = 22,
  BLE_CONNECT = 30, BLE_DISCONNECT = 31, BLE_AUTH_FAIL = 32,
  RTCM_LOST = 40, RTCM_RESTORED = 41, RTCM_OVERFLOW = 42,
  GNSS_LOST = 50, GNSS_RECOVERED = 51, RTK_CHANGE = 52,
  BATT_LOW = 60, BATT_CRITICAL = 61,
  SESSION_START = 70, SESSION_STOP = 71, SESSION_PAUSE = 72, SESSION_RESUME = 73, SESSION_RECOVERED = 74,
  SESSION_RESUMED_AFTER_REBOOT = 75,
  GEOFENCE = 80, CONFIG_CHANGED = 90, CONFIG_CORRUPT = 91, OTA = 100, PREBUFFER_REDUCED = 110,
};

struct BbRecord {
  uint32_t seq = 0;
  uint32_t uptime_ms = 0;
  uint32_t rtc_s = 0;       // 0 if wall time unknown
  uint32_t boot = 0;
  uint16_t code = 0;
  uint8_t severity = 0;
  uint32_t arg0 = 0, arg1 = 0;
};

class Blackbox {
 public:
  static const size_t REC = 32;
  bool init(FlashIo* io);              // scans the partition to find the head
  bool append(const BbRecord& r);      // assigns seq
  uint32_t next_seq() const { return seq_; }
  // Visits up to n most recent records, newest first. Returns count visited.
  typedef void (*Visitor)(const BbRecord& r, void* ctx);
  int read_recent(int n, Visitor v, void* ctx);
  uint32_t write_errors() const { return werr_; }
 private:
  bool decode(const uint8_t* b, BbRecord* r) const;
  FlashIo* io_ = nullptr;
  size_t slots_ = 0, next_ = 0;
  uint32_t seq_ = 1;
  uint32_t werr_ = 0;
};

}  // namespace avo
