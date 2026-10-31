// u-blox ZED-F9P helpers for the back module (portable, host-testable):
//  - UbxStream: extracts complete UBX frames from a mixed UBX/NMEA/RTCM byte stream.
//  - ubx_valset_*: UBX-CFG-VALSET builder (RAM layer only: a power cycle restores
//    the receiver's own configuration; nothing is written to its flash/BBR).
//  - ZedManager: finds the UART baud rate, finds which ZED port (UART1/UART2) is
//    wired to the back, enables UBX + RTCM3 input and NAV-PVT + RXM-RTCM output,
//    sets the navigation rate and keeps watching the receiver.
// Key IDs: u-blox ZED-F9P HPG Interface Description (CFG-UARTx, CFG-MSGOUT, CFG-RATE).
#pragma once
#include <stdint.h>
#include <stddef.h>
#include "avo_payloads.h"

namespace avo {

// ---- configuration keys (value size is encoded in bits 28..30 of the key)
namespace zedkey {
static const uint32_t RATE_MEAS = 0x30210001;          // U2 ms
static const uint32_t UART1_BAUDRATE = 0x40520001;     // U4
static const uint32_t UART2_BAUDRATE = 0x40530001;     // U4
static const uint32_t UART1INPROT_UBX = 0x10730001, UART1INPROT_NMEA = 0x10730002, UART1INPROT_RTCM3X = 0x10730004;
static const uint32_t UART1OUTPROT_UBX = 0x10740001, UART1OUTPROT_NMEA = 0x10740002, UART1OUTPROT_RTCM3X = 0x10740004;
static const uint32_t UART2INPROT_UBX = 0x10750001, UART2INPROT_NMEA = 0x10750002, UART2INPROT_RTCM3X = 0x10750004;
static const uint32_t UART2OUTPROT_UBX = 0x10760001, UART2OUTPROT_NMEA = 0x10760002, UART2OUTPROT_RTCM3X = 0x10760004;
static const uint32_t MSGOUT_NAV_PVT_UART1 = 0x20910007, MSGOUT_NAV_PVT_UART2 = 0x20910008;
static const uint32_t MSGOUT_RXM_RTCM_UART1 = 0x20910269, MSGOUT_RXM_RTCM_UART2 = 0x2091026A;
// V3.9.0 quality monitoring (output rate = once every N navigation epochs)
static const uint32_t MSGOUT_NAV_SAT_UART1 = 0x20910016, MSGOUT_NAV_SAT_UART2 = 0x20910017;
static const uint32_t MSGOUT_NAV_SIG_UART1 = 0x20910346, MSGOUT_NAV_SIG_UART2 = 0x20910347;
// ---- V3.8.0 precision profile (u-blox F9 HPG Interface Description)
static const uint32_t NAVSPG_DYNMODEL = 0x20110021;      // E1
static const uint32_t NAVSPG_INFIL_MINELEV = 0x201100A4; // I1 degrees
static const uint32_t NAVSPG_INFIL_MINCNO = 0x201100A3;  // U1 dBHz
static const uint32_t NAVHPG_DGNSSMODE = 0x20140011;     // E1: 2 RTK float, 3 RTK fixed
static const uint32_t SIGNAL_GPS_ENA = 0x1031001F, SIGNAL_GAL_ENA = 0x10310021, SIGNAL_BDS_ENA = 0x10310022, SIGNAL_GLO_ENA = 0x10310025;
}  // namespace zedkey

// Dynamic platform models (CFG-NAVSPG-DYNMODEL)
enum class ZedDynModel : uint8_t { PORTABLE = 0, STATIONARY = 2, PEDESTRIAN = 3, AUTOMOTIVE = 4, SEA = 5, AIRBORNE_1G = 6, AIRBORNE_2G = 7, AIRBORNE_4G = 8 };

// Constellation set used for a navigation rate. ZED-F9P data sheet, table 1 (max RTK rate):
// GPS+GLO+GAL+BDS 8 Hz · GPS+GLO+GAL 10 Hz · GPS+GAL 12 Hz. Above that RTK quality is not specified.
struct ZedGnssSet { bool gps, glo, gal, bds; uint8_t max_rtk_hz; };
// Most satellites that still allow RTK at [hz]; *effective_hz receives the rate actually applied.
ZedGnssSet zed_gnss_for_rate(uint8_t hz, uint8_t* effective_hz);
const char* zed_gnss_name(const ZedGnssSet& s);

static const uint8_t UBX_CLS_ACK = 0x05, UBX_ID_ACK_ACK = 0x01, UBX_ID_ACK_NAK = 0x00;
static const uint8_t UBX_CLS_CFG = 0x06, UBX_ID_CFG_VALSET = 0x8A;
static const uint8_t UBX_CLS_MON = 0x0A, UBX_ID_MON_VER = 0x04;
static const uint8_t UBX_CLS_RXM = 0x02, UBX_ID_RXM_RTCM = 0x32;

// Size in bytes of a key's value (from the key's size bits). 0 = unknown.
size_t zed_key_value_size(uint32_t key);

struct ZedKV { uint32_t key; uint32_t value; };
// Builds a complete UBX-CFG-VALSET frame (version 0, layers = RAM). Returns length or 0.
size_t ubx_valset_ram(const ZedKV* kv, size_t n, uint8_t* out, size_t cap);
// Builds a poll frame (empty payload).
size_t ubx_poll(uint8_t cls, uint8_t id, uint8_t* out, size_t cap);

// RXM-RTCM report
struct RxmRtcm { bool crc_failed = false; uint8_t msg_used = 0; uint16_t msg_type = 0; uint16_t ref_station = 0; };
bool ubx_decode_rxm_rtcm(const uint8_t* pl, size_t n, RxmRtcm* r);

// ------------------------------------------------------------------ UbxStream
class UbxStream {
 public:
  typedef void (*FrameCb)(const uint8_t* frame, size_t len, void* ctx);
  UbxStream(FrameCb cb, void* ctx) : cb_(cb), ctx_(ctx) {}
  void feed(const uint8_t* d, size_t n);
  uint32_t frames() const { return frames_; }
  uint32_t bad_checksum() const { return bad_; }
  uint32_t nmea_sentences() const { return nmea_; }   // valid "$..*hh" sentences seen
 private:
  void byte(uint8_t b);
  void nmea_byte(uint8_t b);
  FrameCb cb_;
  void* ctx_;
  uint8_t buf_[2100];   // V3.9.0: NAV-SIG with ~120 signals is ~1.9 KB
  size_t have_ = 0, need_ = 0;
  uint32_t frames_ = 0, bad_ = 0, nmea_ = 0;
  char nm_[96];
  size_t nm_len_ = 0;
  bool nm_on_ = false;
};

// ------------------------------------------------------------------ ZedManager
class ZedIo {
 public:
  virtual ~ZedIo() {}
  virtual void zed_set_baud(uint32_t baud) = 0;
  virtual void zed_write(const uint8_t* d, size_t n) = 0;
};

class ZedManager {
 public:
  // TUNE (V3.8.0) is reported to the chest as CONFIGURE (2): the BackStatus format is unchanged.
  enum State : uint8_t { DETECT = 0, PROBE_PORT = 1, CONFIGURE = 2, RUNNING = 3, NO_RESPONSE = 4, TUNE = 5 };
  ZedManager(ZedIo* io, uint8_t nav_rate_hz, uint32_t target_baud = 230400);
  void begin(uint32_t now_ms);
  void tick(uint32_t now_ms);
  // Feed every byte read from the ZED UART. Complete UBX frames are reported to on_ubx.
  void feed(const uint8_t* d, size_t n, uint32_t now_ms);
  // Callback for every valid UBX frame (NAV-PVT, RXM-RTCM, ...).
  typedef void (*UbxCb)(uint8_t cls, uint8_t id, const uint8_t* pl, uint16_t plen, void* ctx);
  void set_ubx_cb(UbxCb cb, void* ctx) { ucb_ = cb; uctx_ = ctx; }
  // RTCM may be written only when the baud rate is known (or in the default fallback).
  bool rtcm_write_ok() const { return st_ == RUNNING || st_ == NO_RESPONSE || st_ == TUNE || st_ == CONFIGURE; }   // baud known
  void set_nav_rate(uint8_t hz, uint32_t now_ms);
  State state() const { return st_; }
  uint32_t baud() const { return baud_; }
  uint8_t port() const { return port_; }      // 1 UART1, 2 UART2, 0 unknown
  bool config_acked() const { return cfg_ok_; }
  bool rate_applied() const { return rate_ok_; }
  // Precision profile: 0 not sent, 1 full (model + RTK fixed + constellations + masks), 2 reduced (model + RTK fixed), 3 rejected
  uint8_t tune_state() const { return tune_; }
  // V3.9.0: NAV-SAT/NAV-SIG output (1 Hz): 0 not requested yet, 1 both enabled, 2 rejected, 3 skipped (UART too slow),
  // 4 only NAV-SAT accepted, 5 only NAV-SIG accepted (V3.10.1: each one is retried on its own after a NAK)
  uint8_t monitor_state() const { return mon_; }
  const char* receiver_fw() const { return fwver_; }   // "HPG 1.32" etc. (empty until MON-VER arrives)
  const ZedGnssSet& gnss_set() const { return set_; }
  void set_dyn_model(ZedDynModel m) { dyn_ = m; }
  ZedDynModel dyn_model() const { return dyn_; }
  uint8_t nav_rate() const { return rate_; }
  uint32_t detect_cycles() const { return cycles_; }
  const UbxStream& stream() const { return ubx_; }
  // 0 not detected, 1 configuring, 2 running, 3 error (BackStatus.zed_state)
  uint8_t status_code() const;
  static const char* state_name(State s);

 private:
  static void on_frame(const uint8_t* f, size_t n, void* ctx);
  void handle(const uint8_t* f, size_t n);
  void go(State s, uint32_t now_ms);
  void poll_ver();
  void send_baud(uint8_t port, uint32_t baud);
  void send_config(bool with_rate);
  void send_tune(bool full);
  void send_monitor(uint8_t which);   // 3 both, 1 NAV-SAT, 2 NAV-SIG
  uint8_t mon_ = 0, mon_try_ = 3, mon_ok_ = 0, mon_rounds_ = 0;
  uint32_t mon_t0_ = 0;
  char fwver_[25] = {0};
  ZedIo* io_;
  UbxStream ubx_;
  UbxCb ucb_ = nullptr;
  void* uctx_ = nullptr;
  State st_ = DETECT;
  uint8_t rate_;
  uint32_t target_;
  uint32_t baud_ = 38400, found_ = 0;
  uint8_t port_ = 0;
  uint8_t step_ = 0, cand_ = 0, tries_ = 0;
  uint32_t t0_ = 0, last_ubx_ms_ = 0, last_nmea_count_ = 0;
  bool got_ubx_ = false, got_nmea_ = false;
  bool cfg_ok_ = false, rate_ok_ = false, cfg_with_rate_ = true;
  uint8_t ack_ = 0;          // 0 waiting, 1 ACK, 2 NAK
  uint32_t cycles_ = 0;
  uint32_t now_ = 0;
  // V3.8.0 precision profile
  ZedDynModel dyn_ = ZedDynModel::AIRBORNE_2G;
  ZedGnssSet set_ = {true, true, true, true, 8};
  bool set_applied_ = false;      // constellation keys already in the receiver (changing them restarts tracking)
  ZedGnssSet applied_set_ = {true, true, true, true, 8};
  uint8_t tune_ = 0;
};

}  // namespace avo
