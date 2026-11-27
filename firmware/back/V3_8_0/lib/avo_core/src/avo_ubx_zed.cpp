#include "avo_ubx_zed.h"
#include "avo_bytes.h"
#include "avo_gnss_codecs.h"
#include "avo_gnss_quality.h"
#include <string.h>
#include <stdlib.h>

namespace avo {

size_t zed_key_value_size(uint32_t key) {
  switch ((key >> 28) & 0x7) {
    case 1: return 1;  // L (bit stored in one byte)
    case 2: return 1;
    case 3: return 2;
    case 4: return 4;
    case 5: return 8;
    default: return 0;
  }
}

size_t ubx_valset_ram(const ZedKV* kv, size_t n, uint8_t* out, size_t cap) {
  uint8_t pl[4 + 64 * 8];
  if (n > 64) return 0;
  ByteWriter w(pl, sizeof(pl));
  w.u8(0);      // version
  w.u8(0x01);   // layers: RAM only
  w.u16(0);     // reserved
  for (size_t i = 0; i < n; i++) {
    size_t vs = zed_key_value_size(kv[i].key);
    if (vs == 0 || vs > 4) return 0;
    w.u32(kv[i].key);
    if (vs == 1) w.u8((uint8_t)kv[i].value);
    else if (vs == 2) w.u16((uint16_t)kv[i].value);
    else w.u32(kv[i].value);
  }
  if (!w.ok()) return 0;
  return ubx_build(UBX_CLS_CFG, UBX_ID_CFG_VALSET, pl, (uint16_t)w.size(), out, cap);
}

size_t ubx_poll(uint8_t cls, uint8_t id, uint8_t* out, size_t cap) { return ubx_build(cls, id, nullptr, 0, out, cap); }

bool ubx_decode_rxm_rtcm(const uint8_t* pl, size_t n, RxmRtcm* r) {
  if (n < 8) return false;
  uint8_t flags = pl[1];
  r->crc_failed = (flags & 0x01) != 0;
  r->msg_used = (uint8_t)((flags >> 1) & 0x03);
  r->ref_station = get_u16(pl + 4);
  r->msg_type = get_u16(pl + 6);
  return true;
}

ZedUartBudget zed_uart_budget(uint32_t baud, uint8_t nav_hz, bool quality, uint8_t n_sat, uint8_t n_sig, uint16_t rtcm_msgs_s) {
  ZedUartBudget b;
  if (nav_hz == 0) nav_hz = 1;
  b.line_bytes_s = baud / 10;                                    // 8N1
  const uint32_t pvt = 100, rxm = 16, comms = 16 + 40 * 5;       // MON-COMMS with 5 ports, one poll every 5 s
  const uint32_t sat = (quality && n_sat) ? 16 + 12u * n_sat : 0, sig = quality ? 16 + 16u * n_sig : 0;
  b.avg_bytes_s = pvt * nav_hz + sat + sig + rxm * rtcm_msgs_s + comms / 5;
  b.load_permille = b.line_bytes_s ? (uint16_t)(b.avg_bytes_s * 1000ull / b.line_bytes_s > 65535 ? 65535 : b.avg_bytes_s * 1000ull / b.line_bytes_s) : 65535;
  b.burst_bytes = pvt + sat + sig + rxm * ((rtcm_msgs_s + nav_hz - 1) / nav_hz);
  b.burst_us = b.line_bytes_s ? (uint32_t)(b.burst_bytes * 1000000ull / b.line_bytes_s) : 0xFFFFFFFFu;
  b.epoch_us = 1000000u / nav_hz;
  // The burst may delay the next NAV-PVT by at most one epoch, once per second; the average must leave half the line
  // free (RXM-RTCM bursts when the caster sends a full MSM set, MON-VER answers, receiver TX buffer margin).
  b.ok = b.line_bytes_s && b.load_permille <= 500 && b.burst_us <= 2 * b.epoch_us;
  return b;
}

ZedUartBudget zed_uart_budget_raw(uint32_t baud, uint8_t nav_hz, uint8_t raw_hz, uint8_t n_meas) {
  ZedUartBudget b = zed_uart_budget(baud, nav_hz, true, 0);
  if (raw_hz == 0) return b;
  const uint32_t rawx = 16 + 32u * n_meas + 8, sfrbx_s = 1000;
  b.avg_bytes_s += rawx * raw_hz + sfrbx_s;
  b.load_permille = b.line_bytes_s ? (uint16_t)(b.avg_bytes_s * 1000ull / b.line_bytes_s > 65535 ? 65535 : b.avg_bytes_s * 1000ull / b.line_bytes_s) : 65535;
  b.burst_bytes += rawx;
  b.burst_us = b.line_bytes_s ? (uint32_t)(b.burst_bytes * 1000000ull / b.line_bytes_s) : 0xFFFFFFFFu;
  b.ok = b.line_bytes_s && b.load_permille <= 500 && b.burst_us <= 2 * b.epoch_us;
  return b;
}

void zed_fw_numbers(const char* fw, uint8_t* major, uint8_t* minor) {
  *major = 0; *minor = 0;
  if (!fw) return;
  for (const char* p = fw; *p; p++) {
    if (*p < '0' || *p > '9') continue;
    unsigned a = 0, b = 0;
    const char* q = p;
    while (*q >= '0' && *q <= '9' && a < 1000) a = a * 10 + (unsigned)(*q++ - '0');
    if (*q != '.' || q[1] < '0' || q[1] > '9') { p = q - 1; continue; }
    q++;
    while (*q >= '0' && *q <= '9' && b < 1000) b = b * 10 + (unsigned)(*q++ - '0');
    *major = (uint8_t)(a > 255 ? 255 : a); *minor = (uint8_t)(b > 255 ? 255 : b);
    return;
  }
}

uint8_t zed_raw_rate_for(uint32_t baud, uint8_t nav_hz) {
  if (nav_hz == 0) nav_hz = 1;
  if (baud >= 460800 && nav_hz >= 2 && zed_uart_budget_raw(baud, nav_hz, 2).ok) return 2;
  if (zed_uart_budget_raw(baud, nav_hz, 1).ok) return 1;
  return 0;
}

// UBX-MON-RF: version U1, nBlocks U1, reserved 2, then 24 bytes per block: blockId U1, flags X1 (b0-1 jammingState),
// antStatus U1, antPower U1, postStatus U4, reserved 4, noisePerMS U2, agcCnt U2, jamInd U1, ofsI I1, magI U1, ofsQ I1,
// magQ U1, reserved 3.
bool ubx_decode_mon_rf(const uint8_t* p, size_t n, ZedRf* r) {
  if (n < 4) return false;
  const uint8_t blocks = p[1];
  if (blocks == 0 || n < 4 + (size_t)blocks * 24) return false;
  ZedRf o;
  for (uint8_t i = 0; i < blocks; i++) {
    const uint8_t* q = p + 4 + (size_t)i * 24;
    const uint8_t id = q[0];
    const uint16_t noise = get_u16(q + 12), agc = get_u16(q + 14);
    const uint8_t agc_pct = (uint8_t)(agc >= 8191 ? 100 : (agc * 100u + 4095u) / 8191u);
    if (id == 0) {
      o.jam_state = (uint8_t)(q[1] & 0x03); o.ant_status = q[2]; o.ant_power = q[3];
      o.noise_l1 = noise; o.agc_l1 = agc_pct; o.jam_l1 = q[16];
    } else if (id == 1) {
      o.noise_l2 = noise; o.agc_l2 = agc_pct; o.jam_l2 = q[16];
    }
  }
  o.valid = true;
  *r = o;
  return true;
}

bool ubx_decode_mon_comms(const uint8_t* p, size_t n, uint16_t port_id, ZedComms* c) {
  if (n < 8) return false;
  uint8_t ports = p[1];
  if (n < 8 + (size_t)ports * 40) return false;
  for (uint8_t i = 0; i < ports; i++) {
    const uint8_t* q = p + 8 + (size_t)i * 40;
    if (get_u16(q) != port_id) continue;
    c->valid = true;
    c->tx_errors = p[2];
    c->tx_pending = get_u16(q + 2);
    c->tx_bytes = get_u32(q + 4);
    c->tx_usage = q[8]; c->tx_peak = q[9];
    c->rx_bytes = get_u32(q + 12);
    c->rx_usage = q[16]; c->rx_peak = q[17];
    c->overrun_errs = get_u16(q + 18);
    c->skipped = get_u32(q + 36);
    return true;
  }
  return false;
}

ZedGnssSet zed_gnss_for_rate(uint8_t hz, uint8_t* eff) {
  if (hz == 0) hz = 1;
  if (hz > 12) hz = 12;                       // above 12 Hz the F9P only does RTK with GPS alone
  if (eff) *eff = hz;
  if (hz <= 8) return {true, true, true, true, 8};
  if (hz <= 10) return {true, true, true, false, 10};
  return {true, false, true, false, 12};
}

const char* zed_gnss_name(const ZedGnssSet& s) {
  if (s.gps && s.glo && s.gal && s.bds) return "GPS+GLO+GAL+BDS";
  if (s.gps && s.glo && s.gal) return "GPS+GLO+GAL";
  if (s.gps && s.gal) return "GPS+GAL";
  return "GPS";
}

// ------------------------------------------------------------------ UbxStream
void UbxStream::feed(const uint8_t* d, size_t n) {
  for (size_t i = 0; i < n; i++) byte(d[i]);
}

static int hexval(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  return -1;
}

void UbxStream::nmea_byte(uint8_t b) {
  if (b == '$') { nm_on_ = true; nm_len_ = 0; }
  if (!nm_on_) return;
  if (b == '\r' || b == '\n') {
    // "$....*HH"
    if (nm_len_ >= 6 && nm_[nm_len_ - 3] == '*') {
      uint8_t cs = 0;
      for (size_t i = 1; i < nm_len_ - 3; i++) cs ^= (uint8_t)nm_[i];
      int h = hexval(nm_[nm_len_ - 2]), l = hexval(nm_[nm_len_ - 1]);
      if (h >= 0 && l >= 0 && cs == (uint8_t)(h * 16 + l)) nmea_++;
    }
    nm_on_ = false;
    return;
  }
  if (b < 0x20 || b > 0x7E || nm_len_ >= sizeof(nm_)) { nm_on_ = false; return; }
  nm_[nm_len_++] = (char)b;
}

// V3.14.4: the frame is assembled in buf_ and checked by process(). A bad frame (lost UART bytes, false sync inside
// a payload) is no longer thrown away whole: the search for "B5 62" starts again one byte after its start, so a
// good frame that began inside the bad one (the usual case when bytes were lost) is still delivered.
void UbxStream::drop(size_t n) {
  if (n > have_) n = have_;
  size_t k = n;
  while (k < have_ && !(buf_[k] == UBX_SYNC1 && (k + 1 == have_ || buf_[k + 1] == UBX_SYNC2))) k++;
  if (k < have_) { memmove(buf_, buf_ + k, have_ - k); have_ -= k; }
  else have_ = 0;
  need_ = 0;
}

void UbxStream::process() {
  for (;;) {
    if (have_ < 6) { need_ = 0; return; }
    need_ = 8 + (size_t)buf_[4] + ((size_t)buf_[5] << 8);
    if (need_ > sizeof(buf_)) { oversize_++; resyncs_++; drop(1); continue; }   // too long for us (or false sync)
    if (have_ < need_) return;
    uint8_t cls, id;
    const uint8_t* pl;
    uint16_t plen;
    if (ubx_check_frame(buf_, need_, &cls, &id, &pl, &plen)) {
      frames_++;
      if (need_ >= 512) long_++;   // V3.16.1
      if (cb_) cb_(buf_, need_, ctx_);
      drop(need_);
    } else {
      bad_++;
      resyncs_++;
      drop(1);
    }
  }
}

void UbxStream::byte(uint8_t b) {
  nmea_byte(b);
  if (have_ == 0) { if (b == UBX_SYNC1) buf_[have_++] = b; return; }
  if (have_ == 1) {
    if (b == UBX_SYNC2) buf_[have_++] = b;
    else have_ = (b == UBX_SYNC1) ? 1 : 0;
    return;
  }
  if (have_ >= sizeof(buf_)) { drop(1); if (have_ == 0) { if (b == UBX_SYNC1) buf_[have_++] = b; return; } }
  buf_[have_++] = b;
  if (have_ >= 6 && (need_ == 0 || have_ >= need_)) process();
}

// ------------------------------------------------------------------ ZedManager
static const uint32_t kCandidates[] = {38400, 115200, 230400, 460800, 921600, 9600};
static const size_t kNumCand = sizeof(kCandidates) / sizeof(kCandidates[0]);

ZedManager::ZedManager(ZedIo* io, uint8_t nav_rate_hz, uint32_t target_baud)
    : io_(io), ubx_(on_frame, this), rate_(nav_rate_hz ? nav_rate_hz : 1), target_(target_baud) {
  uint8_t eff = rate_;
  set_ = zed_gnss_for_rate(rate_, &eff);
  rate_ = eff;
}

const char* ZedManager::state_name(State s) {
  switch (s) {
    case TUNE: return "AJUSTE_PRECISION";
    case DETECT: return "BUSCANDO_BAUDIOS";
    case PROBE_PORT: return "BUSCANDO_PUERTO";
    case CONFIGURE: return "CONFIGURANDO";
    case RUNNING: return "FUNCIONANDO";
    case NO_RESPONSE: return "SIN_RESPUESTA_UBX";
  }
  return "?";
}

uint8_t ZedManager::status_code() const {
  switch (st_) {
    case RUNNING: return 2;
    case TUNE: return 1;
    case NO_RESPONSE: return 3;
    case DETECT: return cycles_ ? 0 : 1;
    default: return 1;
  }
}

void ZedManager::on_frame(const uint8_t* f, size_t n, void* ctx) { ((ZedManager*)ctx)->handle(f, n); }

void ZedManager::handle(const uint8_t* f, size_t n) {
  uint8_t cls = f[2], id = f[3];
  uint16_t plen = (uint16_t)(n - 8);
  const uint8_t* pl = f + 6;
  // Bytes that were already in flight when the baud rate changed are ignored.
  if (now_ - t0_ >= 25 || st_ == RUNNING) got_ubx_ = true;
  last_ubx_ms_ = now_;
  // V3.13.12: the message that carries the summary is watched (NAV-SIG; NAV-SAT only when NAV-SIG was refused).
  if (cls == UBX_CLS_NAV && ((id == UBX_ID_NAV_SIG && mon_ != 4) || (id == UBX_ID_NAV_SAT && mon_ == 4))) { mon_last_ms_ = now_ | 1; mon_streak_ = 0; }
  // V3.14.4: both quality messages are counted and timed on their own (the watchdog checks each one).
  if (cls == UBX_CLS_NAV && id == UBX_ID_NAV_PVT) n_pvt_++;
  if (cls == UBX_CLS_NAV && id == UBX_ID_NAV_SAT) { n_sat_++; t_sat_ = now_ | 1; }
  if (cls == UBX_CLS_NAV && id == UBX_ID_NAV_SIG) { n_sig_++; t_sig_ = now_ | 1; }
  if (cls == UBX_CLS_RXM && id == UBX_ID_RXM_RAWX) n_rawx_++;     // V3.16.0
  if (cls == UBX_CLS_RXM && id == UBX_ID_RXM_SFRBX) n_sfrbx_++;
  if (cls == UBX_CLS_MON && id == UBX_ID_MON_COMMS) {
    ZedComms c;
    if (ubx_decode_mon_comms(pl, plen, port_ == 2 ? 0x0201 : 0x0100, &c)) {
      comms_ = c;
      // V3.14.6: txPeakUsage is since the receiver started (it includes the boot at 38400 with NMEA saturating the line);
      // this one is the worst 1-s usage seen while the back runs the receiver at its configured speed.
      if (st_ == RUNNING && c.tx_usage > comms_tx_max_) comms_tx_max_ = c.tx_usage;
    }
  }
  if (cls == UBX_CLS_MON && id == UBX_ID_MON_RF) { ZedRf r; if (ubx_decode_mon_rf(pl, plen, &r)) { rf_ = r; t_rf_ = now_ | 1; } }
  if (cls == UBX_CLS_ACK && plen >= 2 && pl[0] == UBX_CLS_CFG && pl[1] == UBX_ID_CFG_VALSET) ack_ = (id == UBX_ID_ACK_ACK) ? 1 : 2;
  if (cls == UBX_CLS_MON && id == UBX_ID_MON_VER && plen >= 40) {   // V3.10.1: receiver firmware (FWVER=HPG x.yy)
    for (size_t off = 40; off + 30 <= plen; off += 30) {
      const char* e = (const char*)pl + off;
      if (strncmp(e, "FWVER=", 6) == 0) { size_t k = 0; while (k < sizeof(fwver_) - 1 && k < 24 && e[6 + k] >= 32 && e[6 + k] < 127) { fwver_[k] = e[6 + k]; k++; } fwver_[k] = 0; }
    }
  }
  if (ucb_) ucb_(cls, id, pl, plen, uctx_);
}

void ZedManager::feed(const uint8_t* d, size_t n, uint32_t now_ms) {
  now_ = now_ms;
  uint32_t before = ubx_.nmea_sentences();
  ubx_.feed(d, n);
  if (ubx_.nmea_sentences() != before && now_ms - t0_ >= 25) got_nmea_ = true;
}

void ZedManager::poll_ver() {
  uint8_t b[8];
  size_t n = ubx_poll(UBX_CLS_MON, UBX_ID_MON_VER, b, sizeof(b));
  io_->zed_write(b, n);
}

void ZedManager::send_baud(uint8_t port, uint32_t baud) {
  ZedKV kv = {port == 1 ? zedkey::UART1_BAUDRATE : zedkey::UART2_BAUDRATE, baud};
  uint8_t b[32];
  size_t n = ubx_valset_ram(&kv, 1, b, sizeof(b));
  io_->zed_write(b, n);
}

// Keys applied in CONFIGURE (also used one by one if the receiver rejects the batch).
static size_t config_keys(uint8_t port, bool with_rate, uint8_t rate, uint32_t baud, ZedKV* kv) {
  size_t n = 0;
  if (port == 1 || port == 0) {
    kv[n++] = {zedkey::UART1INPROT_UBX, 1};
    kv[n++] = {zedkey::UART1INPROT_RTCM3X, 1};
    kv[n++] = {zedkey::UART1OUTPROT_UBX, 1};
    if (port == 1) kv[n++] = {zedkey::UART1OUTPROT_NMEA, 0};   // the back does not use NMEA: frees bandwidth
    if (port == 1) kv[n++] = {zedkey::UART1OUTPROT_RTCM3X, 0}; // V3.14.7: nor RTCM from the receiver (saved base config)
    kv[n++] = {zedkey::MSGOUT_NAV_PVT_UART1, 1};
    kv[n++] = {zedkey::MSGOUT_RXM_RTCM_UART1, 1};
  }
  if (port == 2 || port == 0) {
    kv[n++] = {zedkey::UART2INPROT_UBX, 1};
    kv[n++] = {zedkey::UART2INPROT_RTCM3X, 1};
    kv[n++] = {zedkey::UART2OUTPROT_UBX, 1};
    if (port == 2) kv[n++] = {zedkey::UART2OUTPROT_NMEA, 0};
    if (port == 2) kv[n++] = {zedkey::UART2OUTPROT_RTCM3X, 0};   // V3.14.7
    kv[n++] = {zedkey::MSGOUT_NAV_PVT_UART2, 1};
    kv[n++] = {zedkey::MSGOUT_RXM_RTCM_UART2, 1};
  }
  if (with_rate) {
    uint8_t r = rate;
    zed_gnss_for_rate(rate, &r);                 // never above the RTK limit of the constellations used
    // Unknown port means NMEA stays on: keep the UART below ~80 % load.
    if (port == 0 && baud < 115200 && r > 5) r = 5;
    if (baud < 38400 && r > 1) r = 1;
    kv[n++] = {zedkey::RATE_MEAS, (uint32_t)(1000 / r)};
  }
  return n;
}

void ZedManager::send_config(bool with_rate) {
  ZedKV kv[16];
  size_t n = config_keys(port_, with_rate, rate_, baud_, kv);
  uint8_t b[160];
  size_t len = ubx_valset_ram(kv, n, b, sizeof(b));
  ack_ = 0;
  io_->zed_write(b, len);
}

// Precision profile, sent as its own VALSET after the I/O configuration so a receiver that
// rejects a key never loses UBX/RTCM/NAV-PVT. RAM layer only, like the rest.
void ZedManager::send_tune(bool full) {
  ZedKV kv[12];
  size_t n = 0;
  kv[n++] = {zedkey::NAVSPG_DYNMODEL, (uint32_t)dyn_};
  kv[n++] = {zedkey::NAVHPG_DGNSSMODE, 3};          // RTK fixed: resolve integer ambiguities
  if (full) {
    kv[n++] = {zedkey::NAVSPG_INFIL_MINELEV, 10};   // 10 deg: low satellites carry the most multipath
    kv[n++] = {zedkey::NAVSPG_INFIL_MINCNO, 6};     // receiver default, set explicitly
    uint8_t eff = 0;
    set_ = zed_gnss_for_rate(rate_, &eff);
    bool same = set_applied_ && set_.gps == applied_set_.gps && set_.glo == applied_set_.glo &&
                set_.gal == applied_set_.gal && set_.bds == applied_set_.bds;
    if (!same) {                                    // changing constellations restarts tracking: only when needed
      kv[n++] = {zedkey::SIGNAL_GPS_ENA, set_.gps ? 1u : 0u};
      kv[n++] = {zedkey::SIGNAL_GLO_ENA, set_.glo ? 1u : 0u};
      kv[n++] = {zedkey::SIGNAL_GAL_ENA, set_.gal ? 1u : 0u};
      kv[n++] = {zedkey::SIGNAL_BDS_ENA, set_.bds ? 1u : 0u};
    }
  }
  uint8_t b[128];
  size_t len = ubx_valset_ram(kv, n, b, sizeof(b));
  ack_ = 0;
  io_->zed_write(b, len);
}

// V3.14.6: quality output = NAV-SIG once per second, NAV-SAT switched OFF in the same VALSET (the satellite counts are
// taken from NAV-SIG). Field 20/11/2026 (HPG 1.51, UART2 at 230400): MON-COMMS showed the receiver's TX buffer at a peak
// of 101 %, i.e. output dropped by the receiver; NAV-SAT + NAV-SIG left in the same epoch were the largest burst
// (~1.3 KB). NAV-SAT alone (which = 1) only when the receiver refuses NAV-SIG.
void ZedManager::send_monitor(uint8_t which) {
  // V3.16.2: NAV-SAT/NAV-SIG once every kQualityEveryS seconds, not every second. Field 27/11/2026 (HPG 1.51, UART2,
  // 230400): with NAV-SIG + RXM-RAWX + RXM-SFRBX every second the receiver reported TX buffer errors (MON-COMMS
  // mem/alloc, peak 106 %) and stopped sending every message of 512 B or more after ~5 s: no RAWX for PPK.
  uint32_t every = (rate_ ? rate_ : 1) * kQualityEveryS;
  ZedKV kv[2];
  size_t n = 0;
  const uint32_t sat = port_ == 2 ? zedkey::MSGOUT_NAV_SAT_UART2 : zedkey::MSGOUT_NAV_SAT_UART1;
  const uint32_t sig = port_ == 2 ? zedkey::MSGOUT_NAV_SIG_UART2 : zedkey::MSGOUT_NAV_SIG_UART1;
  if (which == 2) { kv[n++] = {sig, every}; kv[n++] = {sat, 0}; }
  else if (which == 1) kv[n++] = {sat, every};
  else { kv[n++] = {sat, every}; kv[n++] = {sig, every}; }
  uint8_t b[48];
  size_t len = ubx_valset_ram(kv, n, b, sizeof(b));
  ack_ = 0;
  io_->zed_write(b, len);
}

// V3.16.0 PPK: RXM-RAWX every (nav rate / raw rate) epochs and every RXM-SFRBX, in their own VALSET (a receiver that
// rejects them keeps NAV-PVT, RTCM and NAV-SIG exactly as before). RAM layer only, like the rest.
void ZedManager::send_raw(uint8_t raw_hz) {
  uint32_t every = raw_hz ? (rate_ > raw_hz ? rate_ / raw_hz : 1) : 0;
  // V3.16.2: RXM-SFRBX OFF (~19 frames/s, ~1.5 KB/s on HPG 1.51). The ephemerides come from the base navigation
  // RINEX (IGN _MN file), which the PPK already downloads (docs/PPK.md). The key is still sent, with 0, so a receiver
  // left with SFRBX on by 3.16.0/3.16.1 (RAM) stops it.
  ZedKV kv[2] = {{port_ == 2 ? zedkey::MSGOUT_RXM_RAWX_UART2 : zedkey::MSGOUT_RXM_RAWX_UART1, every},
                 {port_ == 2 ? zedkey::MSGOUT_RXM_SFRBX_UART2 : zedkey::MSGOUT_RXM_SFRBX_UART1, 0u}};
  uint8_t b[48];
  size_t len = ubx_valset_ram(kv, 2, b, sizeof(b));
  ack_ = 0;
  io_->zed_write(b, len);
}

void ZedManager::go(State s, uint32_t now_ms) {
  st_ = s;
  step_ = 0;
  tries_ = 0;
  t0_ = now_ms;
  got_ubx_ = false;
  got_nmea_ = false;
}

void ZedManager::begin(uint32_t now_ms) {
  now_ = now_ms;
  cand_ = 0;
  go(DETECT, now_ms);
}

void ZedManager::set_nav_rate(uint8_t hz, uint32_t now_ms) {
  if (!hz) return;
  uint8_t eff = hz;
  zed_gnss_for_rate(hz, &eff);
  rate_ = eff;
  mon_ = 0; mon_t0_ = 0; mon_try_ = 2; mon_ok_ = 0; mon_rounds_ = 0;   // V3.9.0: quality output follows the new rate
  raw_ = 0; raw_t0_ = 0; raw_rounds_ = 0;                               // V3.16.0: raw output too
  if (st_ == RUNNING) { cfg_with_rate_ = true; go(CONFIGURE, now_ms); }
}

void ZedManager::tick(uint32_t now_ms) {
  now_ = now_ms;
  uint32_t dt = now_ms - t0_;
  switch (st_) {
    case DETECT: {
      uint32_t c = (cand_ == 0 && found_) ? found_ : kCandidates[(cand_ - (found_ ? 1 : 0)) % kNumCand];
      if (step_ == 0) { io_->zed_set_baud(c); baud_ = c; t0_ = now_ms; got_ubx_ = got_nmea_ = false; step_ = 1; }
      else if (step_ == 1 && dt >= 30) { poll_ver(); step_ = 2; }
      else if (step_ == 2 && dt >= 150) {
        // Blind (RAM) "UBX output on" for both ports: a port whose UBX output is off
        // (u-blox UART2 factory setting) would never answer the poll otherwise.
        ZedKV kv[2] = {{zedkey::UART1OUTPROT_UBX, 1}, {zedkey::UART2OUTPROT_UBX, 1}};
        uint8_t b[40];
        size_t n = ubx_valset_ram(kv, 2, b, sizeof(b));
        io_->zed_write(b, n);
        step_ = 3;
      }
      else if (step_ == 3 && dt >= 250) { poll_ver(); step_ = 4; }
      else if (step_ == 4 && dt >= 500) {
        if (got_ubx_) { found_ = c; go(PROBE_PORT, now_ms); break; }
        if (got_nmea_) { found_ = c; port_ = 0; cfg_with_rate_ = true; go(CONFIGURE, now_ms); break; }   // UBX output off: blind config
        cand_++;
        step_ = 0;
        if (cand_ >= kNumCand + (found_ ? 1 : 0)) { cand_ = 0; cycles_++; go(NO_RESPONSE, now_ms); }
      }
      break;
    }
    case NO_RESPONSE: {
      // Fallback: stay at the last known (or factory default) baud so RTCM keeps flowing.
      if (step_ == 0) { baud_ = found_ ? found_ : 38400; io_->zed_set_baud(baud_); step_ = 1; t0_ = now_ms; got_ubx_ = false; }
      else if (got_ubx_) { found_ = baud_; go(PROBE_PORT, now_ms); }
      else if (dt >= 10000) { cand_ = 0; go(DETECT, now_ms); }
      break;
    }
    case PROBE_PORT: {
      uint32_t T = (found_ == target_) ? (target_ == 230400 ? 460800 : 230400) : target_;
      switch (step_) {
        case 0: send_baud(2, T); t0_ = now_ms; step_ = 1; break;                                       // try UART2
        case 1: if (dt >= 150) { io_->zed_set_baud(T); baud_ = T; t0_ = now_ms; got_ubx_ = false; step_ = 2; } break;
        case 2: if (dt >= 30) { poll_ver(); step_ = 3; } break;
        case 3: if (dt >= 180) { poll_ver(); step_ = 4; } break;
        case 4:
          if (dt >= 400) {
            if (got_ubx_) { port_ = 2; cfg_with_rate_ = true; go(CONFIGURE, now_ms); break; }
            io_->zed_set_baud(found_); baud_ = found_; t0_ = now_ms; got_ubx_ = false; step_ = 5;      // not UART2: back to the old baud
          }
          break;
        case 5: if (dt >= 30) { poll_ver(); step_ = 6; } break;
        case 6: if (dt >= 180) { poll_ver(); step_ = 7; } break;
        case 7:
          if (dt >= 400) {
            if (!got_ubx_) { cand_ = 0; go(DETECT, now_ms); break; }
            port_ = 1;
            send_baud(1, T); t0_ = now_ms; step_ = 8;                                                  // UART1: raise its baud
          }
          break;
        case 8: if (dt >= 150) { io_->zed_set_baud(T); baud_ = T; t0_ = now_ms; got_ubx_ = false; step_ = 9; } break;
        case 9: if (dt >= 30) { poll_ver(); step_ = 10; } break;
        case 10: if (dt >= 180) { poll_ver(); step_ = 11; } break;
        case 11:
          if (dt >= 400) {
            if (!got_ubx_) { io_->zed_set_baud(found_); baud_ = found_; }   // keep the old baud on UART1
            cfg_with_rate_ = true;
            go(CONFIGURE, now_ms);
          }
          break;
      }
      break;
    }
    case CONFIGURE: {
      if (step_ == 0) { send_config(cfg_with_rate_); t0_ = now_ms; step_ = 1; break; }
      if (ack_ == 1) {
        cfg_ok_ = true; rate_ok_ = cfg_with_rate_;
        found_ = baud_;
        go(TUNE, now_ms); last_ubx_ms_ = now_ms;
        break;
      }
      if (ack_ == 2) {   // rejected: retry once without the rate change
        if (cfg_with_rate_) { cfg_with_rate_ = false; step_ = 0; break; }
        cfg_ok_ = false; rate_ok_ = false; found_ = baud_;
        go(TUNE, now_ms); last_ubx_ms_ = now_ms;
        break;
      }
      if (dt >= 600) {
        if (++tries_ < 3) { step_ = 0; break; }
        cfg_ok_ = false;
        if (port_ == 0) { go(NO_RESPONSE, now_ms); break; }
        found_ = baud_;
        go(RUNNING, now_ms); last_ubx_ms_ = now_ms;
      }
      break;
    }
    case TUNE: {
      // step 0: full profile · step 1 waiting · step 2: reduced profile · step 3 waiting
      if (step_ == 0 || step_ == 2) { send_tune(step_ == 0); t0_ = now_ms; step_++; break; }
      if (ack_ == 1) {
        if (step_ == 1) { tune_ = 1; set_applied_ = true; applied_set_ = set_; } else tune_ = 2;
        go(RUNNING, now_ms); last_ubx_ms_ = now_ms;
        break;
      }
      if (ack_ == 2 || dt >= 800) {
        if (step_ == 1) { step_ = 2; break; }      // retry without masks and constellations
        tune_ = 3;
        go(RUNNING, now_ms); last_ubx_ms_ = now_ms;
      }
      break;
    }
    case RUNNING: {
      // V3.9.0: quality messages, once, after the precision profile. Needs the fast UART (~2 KB/s more).
      // Field (ZED with older firmware): the joint VALSET was NAKed -> each message alone, then a later retry.
      if (mon_ == 0 && port_ != 0) {
        if (!budget().ok) mon_ = 3;                                         // V3.14.4: decided by the UART budget
        else if (!mon_t0_) { send_monitor(mon_try_); mon_t0_ = now_ms | 1; }
        else if (ack_ == 1 || ack_ == 2 || now_ms - mon_t0_ >= 1000) {
          bool ok = ack_ == 1;
          if (mon_try_ == 2 && !ok) { mon_try_ = 1; mon_t0_ = 0; }          // V3.14.6: NAV-SIG refused -> NAV-SAT alone
          else {
            mon_ = mon_try_ == 2 ? 1 : ok ? 4 : 2;                           // 1 NAV-SIG on (NAV-SAT off), 4 only NAV-SAT
            mon_set_ms_ = now_ms;
            if (mon_ == 2 && mon_rounds_ < 2) { mon_rounds_++; mon_try_ = 2; mon_t0_ = now_ms | 1; mon_ = 6; }   // retry in 30 s
          }
        }
      }
      if (mon_ == 6 && now_ms - mon_t0_ >= 30000) { mon_ = 0; mon_t0_ = 0; mon_ok_ = 0; }
      // V3.16.0 PPK: raw measurements, once the quality output is settled (both share the ACK slot).
      if (port_ != 0 && mon_ != 0 && mon_ != 6) {
        if (raw_ == 0) {
          raw_hz_ = zed_raw_rate_for(baud_, rate_);
          if (!raw_hz_) raw_ = 3;
          else { send_raw(raw_hz_); raw_ = 7; raw_t0_ = now_ms | 1; }
        } else if (raw_ == 7 && (ack_ == 1 || ack_ == 2 || now_ms - raw_t0_ >= 1000)) {
          raw_ = ack_ == 1 ? 1 : 2;
          raw_t0_ = now_ms | 1;
        } else if (raw_ == 2 && raw_rounds_ < 2 && now_ms - raw_t0_ >= 30000) { raw_rounds_++; raw_ = 0; }
      }
      // V3.13.12: the output was accepted but nothing arrives any more (receiver lost its RAM setting without going
      // silent for 5 s): ask again, same sequence as at start. NAV-PVT and RTCM are not touched.
      // After 3 requests in a row with nothing back, only once a minute (never floods the UART).
      uint32_t wait = mon_streak_ < 3 ? kMonitorLostMs : 60000;
      // Signed differences: bytes fed after this tick's clock reading can carry a slightly later time.
      // V3.14.4: with both messages accepted, EACH one is watched (field 20/11/2026: the satellite counts in the app were
      // older than the NAV-PVT ones, i.e. NAV-SAT had stopped too). The oldest arrival decides; 0 = not since boot.
      // V3.14.6: NAV-SAT is off when NAV-SIG is accepted, so only the message that should arrive is watched.
      uint32_t last = mon_ == 4 ? t_sat_ : t_sig_;
      if ((mon_ == 1 || mon_ == 4 || mon_ == 5) && (int32_t)(now_ms - mon_set_ms_) >= (int32_t)wait &&
          (last == 0 || (int32_t)(now_ms - last) >= (int32_t)wait)) {
        // V3.14.7: field 20/11/2026 22:56 (3.14.6, HPG 1.51): NAV-SIG arrived after boot, then stopped for 144 s while
        // NAV-PVT kept flowing and every repeated VALSET was ACKed. Re-sending the same value may change nothing in the
        // receiver, so the escalation is: 1st loss -> output OFF then ON again (restarts the periodic message);
        // 2nd loss in a row -> the back POLLS NAV-SIG once per second itself (8-byte request, answered at once,
        // independent of the periodic output).
        if (mon_ == 1 && port_ != 0) {
          if (mon_streak_ == 0) {
            ZedKV kv = {port_ == 2 ? zedkey::MSGOUT_NAV_SIG_UART2 : zedkey::MSGOUT_NAV_SIG_UART1, 0};
            uint8_t b[24];
            size_t n = ubx_valset_ram(&kv, 1, b, sizeof(b));
            io_->zed_write(b, n);
            sig_toggles_++;
          } else if (!sig_poll_) {
            sig_poll_ = true;
          }
        }
        mon_rearms_++; if (mon_streak_ < 255) mon_streak_++;
        mon_ = 0; mon_t0_ = 0; mon_try_ = 2; mon_ok_ = 0; mon_rounds_ = 0; mon_last_ms_ = 0;
      }
      if (sig_poll_ && mon_ == 1 && (sig_poll_t_ == 0 || now_ms - sig_poll_t_ >= kQualityEveryS * 1000u)) {   // V3.14.7 · V3.16.2: every 5 s
        uint8_t b[8];
        size_t n = ubx_poll(UBX_CLS_NAV, UBX_ID_NAV_SIG, b, sizeof(b));
        io_->zed_write(b, n);
        sig_poll_t_ = now_ms | 1;
        sig_polls_++;
      }
      uint32_t quiet = now_ms - last_ubx_ms_;
      if (quiet >= 1500 && dt >= 1000) { poll_ver(); t0_ = now_ms; }
      // V3.14.4: MON-COMMS every 5 s (8-byte poll, ~216-byte answer): the receiver tells whether its own TX buffer
      // overflowed (messages dropped before reaching the back) and whether RTCM bytes were lost on its RX side.
      if (port_ != 0 && quiet < 1500 && (comms_t_ == 0 || now_ms - comms_t_ >= kCommsPollMs)) {
        uint8_t b[8];
        size_t n = ubx_poll(UBX_CLS_MON, UBX_ID_MON_COMMS, b, sizeof(b));
        io_->zed_write(b, n);
        comms_t_ = now_ms | 1;
        comms_polls_++;
      }
      // V3.15.0: MON-RF every 5 s, half a period after MON-COMMS (8-byte poll, ~60-byte answer)
      if (port_ != 0 && quiet < 1500 && comms_t_ && now_ms - comms_t_ >= kCommsPollMs / 2 &&
          (rf_t_ == 0 || now_ms - rf_t_ >= kCommsPollMs)) {
        uint8_t b[8];
        size_t n = ubx_poll(UBX_CLS_MON, UBX_ID_MON_RF, b, sizeof(b));
        io_->zed_write(b, n);
        rf_t_ = now_ms | 1;
      }
      if (quiet >= 5000) { sig_poll_ = false; comms_tx_max_ = 0; rf_ = ZedRf(); t_rf_ = 0; rf_t_ = 0; zed_resets_++; cand_ = 0; set_applied_ = false; tune_ = 0; mon_ = 0; mon_t0_ = 0; mon_try_ = 2; mon_ok_ = 0; mon_rounds_ = 0; raw_ = 0; raw_t0_ = 0; raw_rounds_ = 0; go(DETECT, now_ms); }   // receiver reset or unplugged
      break;
    }
  }
}

}  // namespace avo
