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
// V3.16.0 PPK: raw carrier-phase/pseudorange/Doppler measurements and broadcast navigation subframes
static const uint32_t MSGOUT_RXM_RAWX_UART1 = 0x209102A5, MSGOUT_RXM_RAWX_UART2 = 0x209102A6;
static const uint32_t MSGOUT_RXM_SFRBX_UART1 = 0x20910232, MSGOUT_RXM_SFRBX_UART2 = 0x20910233;
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
static const uint8_t UBX_ID_RXM_RAWX = 0x15, UBX_ID_RXM_SFRBX = 0x13;   // V3.16.0 PPK
static const uint8_t UBX_ID_MON_COMMS = 0x36;   // V3.14.4: receiver port usage (HPG 1.12+)
static const uint8_t UBX_ID_MON_RF = 0x38;      // V3.15.0: antenna and RF front end (HPG 1.10+)

// V3.15.0: UBX-MON-RF, one block per RF band (block 0 = L1, block 1 = L2/L5). Diagnosis of "no RTK FIX": antenna
// open/short, jamming (CW interference indicator) and AGC (a front end saturated or starved shows here).
struct ZedRf {
  bool valid = false;
  uint8_t ant_status = 0xFF, ant_power = 0xFF, jam_state = 0xFF;
  uint8_t jam_l1 = 0xFF, jam_l2 = 0xFF;
  uint8_t agc_l1 = 0xFF, agc_l2 = 0xFF;        // % of 8191
  uint16_t noise_l1 = 0xFFFF, noise_l2 = 0xFFFF;
};
bool ubx_decode_mon_rf(const uint8_t* pl, size_t n, ZedRf* r);

// V3.14.4: UART budget of the ZED -> back link, computed before enabling NAV-SAT/NAV-SIG.
// 8N1 = 10 bits per byte. Sizes are UBX frames (8 bytes of header + checksum included):
// NAV-PVT 100 B, NAV-SAT 16 + 12 x satellites, NAV-SIG 16 + 16 x signals, RXM-RTCM 16 B per RTCM message,
// MON-COMMS 16 + 40 x ports (one poll every 5 s). The quality pair goes out once per second, in the same epoch as a
// NAV-PVT, so that burst must fit in one navigation period or it delays the next position.
struct ZedUartBudget {
  uint32_t line_bytes_s = 0;     // what the UART can carry
  uint32_t avg_bytes_s = 0;      // what the receiver sends on average
  uint16_t load_permille = 0;    // avg / line
  uint32_t burst_bytes = 0;      // NAV-PVT + NAV-SAT + NAV-SIG + RXM-RTCM of one epoch
  uint32_t burst_us = 0;         // time on the line for that burst
  uint32_t epoch_us = 0;         // navigation period
  bool ok = false;               // load <= 50 % and the burst fits in one epoch
};
// Worst case used by the firmware: 60 satellites in NAV-SAT, 120 signals in NAV-SIG, 12 RTCM messages per second.
ZedUartBudget zed_uart_budget(uint32_t baud, uint8_t nav_hz, bool quality, uint8_t n_sat = 60, uint8_t n_sig = 120,
                              uint16_t rtcm_msgs_s = 12);
// V3.16.0 PPK: the same budget (NAV-SIG on, NAV-SAT off) plus RXM-RAWX at raw_hz (16 + 32 x measurements + 8 bytes,
// worst case 80 measurements) and RXM-SFRBX (~1 KB/s worst case with four constellations on two bands). The raw
// epoch is assumed to fall in the same navigation epoch as NAV-PVT + NAV-SIG (worst burst).
ZedUartBudget zed_uart_budget_raw(uint32_t baud, uint8_t nav_hz, uint8_t raw_hz, uint8_t n_meas = 80);
// Raw output rate chosen by the back: 2 Hz when the line runs at >= 460800 baud and the budget allows it, otherwise
// 1 Hz when the budget allows it, otherwise 0 (raw output not requested).
uint8_t zed_raw_rate_for(uint32_t baud, uint8_t nav_hz);
// V3.16.1: "HPG 1.32" -> 1, 32 (first "d.dd" in the text); 0, 0 if there is none.
void zed_fw_numbers(const char* fw, uint8_t* major, uint8_t* minor);

// V3.14.4: UBX-MON-COMMS, the receiver's own view of the port wired to the back.
struct ZedComms {
  bool valid = false;
  uint8_t tx_errors = 0;         // b0 mem, b1 alloc: the receiver could not queue output (messages dropped)
  uint16_t tx_pending = 0;       // bytes waiting in the receiver to go out on this port
  uint8_t tx_usage = 0, tx_peak = 0;   // % of the TX buffer, now and peak
  uint8_t rx_usage = 0, rx_peak = 0;   // % of the RX buffer (RTCM from the back)
  uint16_t overrun_errs = 0;     // RX overruns on this port (RTCM bytes lost inside the receiver)
  uint32_t skipped = 0;          // RX bytes the receiver could not parse (no protocol matched)
  uint32_t rx_bytes = 0, tx_bytes = 0;
};
// portId for UART1 0x0100, UART2 0x0201. False if the payload is malformed or the port is not listed.
bool ubx_decode_mon_comms(const uint8_t* pl, size_t n, uint16_t port_id, ZedComms* c);

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
  // V3.14.4: frames longer than the buffer, and times the parser searched again for a frame start after a bad
  // frame (instead of throwing away every byte of the bad frame, which also lost the frame that followed it).
  uint32_t oversize() const { return oversize_; }
  uint32_t long_frames() const { return long_; }   // V3.16.1: valid frames of 512 B or more
  uint32_t resyncs() const { return resyncs_; }
 private:
  void byte(uint8_t b);
  void nmea_byte(uint8_t b);
  void process();
  void drop(size_t n);
  FrameCb cb_;
  void* ctx_;
  uint8_t buf_[4200];   // V3.9.0: NAV-SIG with ~120 signals is ~1.9 KB · V3.16.0: RXM-RAWX up to 4088 B (127 measurements)
  size_t have_ = 0, need_ = 0;
  uint32_t frames_ = 0, bad_ = 0, nmea_ = 0, oversize_ = 0, resyncs_ = 0, long_ = 0;
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
  // V3.9.0: NAV-SAT/NAV-SIG output (1 Hz): 0 not requested yet, 1 enabled (V3.14.6: NAV-SIG on, NAV-SAT off), 2 rejected, 3 skipped (UART too slow),
  // 4 only NAV-SAT accepted, 5 only NAV-SIG accepted (V3.10.1: each one is retried on its own after a NAK)
  uint8_t monitor_state() const { return mon_; }
  // V3.16.0 PPK: RXM-RAWX + RXM-SFRBX output: 0 not requested yet, 1 enabled, 2 rejected by the receiver,
  // 3 skipped (UART too slow), 7 waiting for the answer. raw_rate_hz = rate requested (1 or 2 Hz, 0 = none).
  uint8_t raw_state() const { return raw_; }
  uint8_t raw_rate_hz() const { return raw_hz_; }
  uint32_t rawx_count() const { return n_rawx_; }
  uint32_t sfrbx_count() const { return n_sfrbx_; }
  // V3.13.12: times the NAV-SAT/SIG output was asked for again because it stopped arriving for 10 s (field 02/11/2026:
  // the card stayed in "waiting for the signal summary" while NAV-PVT kept flowing), and times the receiver went
  // silent for 5 s and had to be detected again (reset, brown-out or cable).
  uint32_t monitor_rearms() const { return mon_rearms_; }
  uint32_t receiver_resets() const { return zed_resets_; }
  static const uint32_t kMonitorLostMs = 10000;
  // V3.14.4: per-message counters and arrival times (ms, 0 = never) of what the receiver really sends.
  uint32_t nav_pvt_count() const { return n_pvt_; }
  uint32_t nav_sat_count() const { return n_sat_; }
  uint32_t nav_sig_count() const { return n_sig_; }
  uint32_t last_nav_sat_ms() const { return t_sat_; }
  uint32_t last_nav_sig_ms() const { return t_sig_; }
  // V3.14.4: UBX-MON-COMMS of the port wired to the back, polled every 5 s while RUNNING (valid = answered).
  const ZedComms& comms() const { return comms_; }
  uint32_t comms_polls() const { return comms_polls_; }
  uint8_t comms_tx_max_running() const { return comms_tx_max_; }   // V3.14.6: worst TX usage (%) while RUNNING
  // V3.14.7: NAV-SIG recovery: times the periodic output was switched off and on again, whether the back is polling
  // NAV-SIG itself (after a second loss in a row), and polls sent.
  uint32_t sig_toggles() const { return sig_toggles_; }
  bool sig_polling() const { return sig_poll_; }
  uint32_t sig_polls() const { return sig_polls_; }
  static const uint32_t kCommsPollMs = 5000;
  // V3.15.0: UBX-MON-RF polled every 5 s (2.5 s after MON-COMMS); last_rf_ms 0 = never.
  const ZedRf& rf() const { return rf_; }
  uint32_t last_rf_ms() const { return t_rf_; }
  // V3.14.4: budget used to decide whether NAV-SAT/NAV-SIG fit on the UART (state 3 "UART too slow" otherwise).
  ZedUartBudget budget() const { return zed_uart_budget(baud_, rate_, true, 0); }   // V3.14.6: NAV-SIG only (NAV-SAT off)
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
  void send_raw(uint8_t raw_hz);      // V3.16.0
  uint8_t raw_ = 0, raw_hz_ = 0, raw_rounds_ = 0;
  uint32_t raw_t0_ = 0, n_rawx_ = 0, n_sfrbx_ = 0;
  uint8_t mon_ = 0, mon_try_ = 2, mon_ok_ = 0, mon_rounds_ = 0;
  uint32_t mon_t0_ = 0;
  uint32_t mon_last_ms_ = 0, mon_set_ms_ = 0, mon_rearms_ = 0, zed_resets_ = 0;
  uint8_t mon_streak_ = 0;
  uint32_t n_pvt_ = 0, n_sat_ = 0, n_sig_ = 0, t_sat_ = 0, t_sig_ = 0;   // V3.14.4
  ZedComms comms_;
  uint32_t comms_t_ = 0, comms_polls_ = 0;
  ZedRf rf_;
  uint32_t rf_t_ = 0, t_rf_ = 0;
  uint8_t comms_tx_max_ = 0;
  bool sig_poll_ = false;
  uint32_t sig_poll_t_ = 0, sig_polls_ = 0, sig_toggles_ = 0;
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
