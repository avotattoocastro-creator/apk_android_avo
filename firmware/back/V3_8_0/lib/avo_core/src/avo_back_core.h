// AVO BACK (Heltec Wireless Stick Lite V3 + ZED-F9P) — portable core logic.
// The Arduino sketch only provides the platform (UART to the ZED, ESP-NOW radio,
// NVS, clock). Everything here is host-testable.
//
//  ZED-F9P ──UART──> UbxStream ──NAV-PVT──> GNSS_SAMPLE ─┐
//                              └─RXM-RTCM─> counters      ├──ESP-NOW──> chest
//  STATUS / HEARTBEAT / CAPS / ACK ──────────────────────┘
//  chest ──ESP-NOW──> RTCM_DATA (u32 stream offset + bytes) ──UART──> ZED-F9P
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "avo_espnow_link.h"
#include "avo_gnss_codecs.h"
#include "avo_payloads.h"
#include "avo_uart_proto.h"
#include "avo_ubx_zed.h"

namespace avo {

class BackPlatform {
 public:
  virtual ~BackPlatform() {}
  virtual uint32_t now_ms() = 0;
  virtual void zed_set_baud(uint32_t baud) = 0;
  virtual void zed_write(const uint8_t* d, size_t n) = 0;
  // Sends one ESP-NOW packet; mac == nullptr means broadcast. Returns true when the
  // radio reports delivery (unicast: MAC-level ACK received).
  virtual bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) = 0;
  virtual void radio_set_peer(const uint8_t mac[6]) = 0;
  virtual void save_peer(const NowPeerRecord& r) = 0;
  virtual uint32_t random32() = 0;
  virtual void reboot() = 0;
};

struct BackStats {
  uint32_t rx_packets = 0, rx_bad = 0, rx_foreign = 0;
  uint32_t tx_packets = 0, tx_fail = 0, tx_retries = 0;
  uint32_t rtcm_rx_bytes = 0, rtcm_to_zed = 0, rtcm_gaps = 0, rtcm_not_written = 0, rtcm_dup_bytes = 0;
  uint32_t rxm_used = 0, rxm_failed = 0;
  uint32_t nav_pvt = 0, gnss_sent = 0, gnss_send_fail = 0;
  uint32_t pairings = 0;
  int8_t rssi = 0;
  uint32_t last_chest_rx_ms = 0;
};

class BackCore : public ZedIo {
 public:
  BackCore(BackPlatform* p, const char* dev_id, uint8_t nav_rate_hz);
  void begin(const NowPeerRecord& stored);
  // Call from the main loop with every packet the radio received (copied out of the WiFi task).
  void on_radio(const uint8_t mac[6], const uint8_t* d, size_t n, int8_t rssi);
  // Call with every byte block read from the ZED UART.
  void on_zed(const uint8_t* d, size_t n);
  void tick();
  // PRG button: accept a new chest for 120 s.
  void open_pairing() { pair_.back_open(p_->now_ms(), 120000); }
  bool pairing_open() const { return pair_.back_open_now(p_->now_ms()); }
  bool paired() const { return pair_.paired(); }
  const NowPeerRecord& peer() const { return pair_.peer(); }
  bool chest_online() const;
  const BackStats& stats() const { return st_; }
  const ZedManager& zed() const { return zed_; }
  const RtcmStats& rtcm_stats() const { return obs_.stats(); }
  BackStatus status() const;

  // ZedIo
  void zed_set_baud(uint32_t b) override { p_->zed_set_baud(b); }
  void zed_write(const uint8_t* d, size_t n) override { p_->zed_write(d, n); }

 private:
  static void on_chest_frame(const FrameView& f, void* ctx);
  void chest_frame(const FrameView& f);
  static void on_ubx(uint8_t cls, uint8_t id, const uint8_t* pl, uint16_t plen, void* ctx);
  void ubx(uint8_t cls, uint8_t id, const uint8_t* pl, uint16_t plen);
  void queue_frame(FrameType t, uint8_t flags, const uint8_t* pl, size_t len, bool flush_now);
  void flush();
  void send_status();
  void send_caps();
  void send_ack(FrameType t, const FrameView& f, uint16_t cmd_id, uint8_t status, bool nack);
  void rtcm_data(const uint8_t* pl, size_t len);

  BackPlatform* p_;
  char dev_[16];
  NowPairing pair_;
  NowBootGuard guard_;
  UartDecoder dec_;
  NowPacker pk_;
  ZedManager zed_;
  RtcmObserver obs_;
  BackStats st_;
  uint32_t boot_id_;
  uint16_t seq_ = 0;
  bool have_off_ = false;
  uint32_t exp_off_ = 0;
  uint16_t done_cmd_[8] = {0};
  uint8_t done_n_ = 0;
  uint32_t last_status_ = 0, last_hb_ = 0, last_caps_ = 0;
  uint32_t rate_t0_ = 0, rate_n_ = 0;
  uint16_t rate_x10_ = 0;
  bool caps_sent_ = false;
};

}  // namespace avo
