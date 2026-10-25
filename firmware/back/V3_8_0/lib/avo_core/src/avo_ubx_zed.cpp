#include "avo_ubx_zed.h"
#include "avo_bytes.h"
#include "avo_gnss_codecs.h"
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

void UbxStream::byte(uint8_t b) {
  nmea_byte(b);
  if (have_ == 0) { if (b == UBX_SYNC1) buf_[have_++] = b; return; }
  if (have_ == 1) {
    if (b == UBX_SYNC2) buf_[have_++] = b;
    else have_ = (b == UBX_SYNC1) ? 1 : 0;
    return;
  }
  buf_[have_++] = b;
  if (have_ == 6) {
    need_ = 8 + (size_t)buf_[4] + ((size_t)buf_[5] << 8);
    if (need_ > sizeof(buf_)) { have_ = 0; need_ = 0; return; }   // too long for us: resync
  }
  if (need_ && have_ == need_) {
    uint8_t cls, id;
    const uint8_t* pl;
    uint16_t plen;
    if (ubx_check_frame(buf_, have_, &cls, &id, &pl, &plen)) {
      frames_++;
      if (cb_) cb_(buf_, have_, ctx_);
    } else {
      bad_++;
    }
    have_ = 0;
    need_ = 0;
  }
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
  if (cls == UBX_CLS_ACK && plen >= 2 && pl[0] == UBX_CLS_CFG && pl[1] == UBX_ID_CFG_VALSET) ack_ = (id == UBX_ID_ACK_ACK) ? 1 : 2;
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
    kv[n++] = {zedkey::MSGOUT_NAV_PVT_UART1, 1};
    kv[n++] = {zedkey::MSGOUT_RXM_RTCM_UART1, 1};
  }
  if (port == 2 || port == 0) {
    kv[n++] = {zedkey::UART2INPROT_UBX, 1};
    kv[n++] = {zedkey::UART2INPROT_RTCM3X, 1};
    kv[n++] = {zedkey::UART2OUTPROT_UBX, 1};
    if (port == 2) kv[n++] = {zedkey::UART2OUTPROT_NMEA, 0};
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

// V3.9.0: UBX-NAV-SAT + NAV-SIG once per second, own VALSET (a rejection never touches the rest).
void ZedManager::send_monitor() {
  uint32_t every = rate_ ? rate_ : 1;
  ZedKV kv[2];
  kv[0] = {port_ == 2 ? zedkey::MSGOUT_NAV_SAT_UART2 : zedkey::MSGOUT_NAV_SAT_UART1, every};
  kv[1] = {port_ == 2 ? zedkey::MSGOUT_NAV_SIG_UART2 : zedkey::MSGOUT_NAV_SIG_UART1, every};
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
  mon_ = 0; mon_t0_ = 0;   // V3.9.0: quality output follows the new rate (stays at 1 Hz)
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
      if (mon_ == 0 && port_ != 0) {
        if (baud_ < 115200) mon_ = 3;
        else if (!mon_t0_) { send_monitor(); mon_t0_ = now_ms | 1; }
        else if (ack_ == 1) mon_ = 1;
        else if (ack_ == 2 || now_ms - mon_t0_ >= 800) mon_ = 2;
      }
      uint32_t quiet = now_ms - last_ubx_ms_;
      if (quiet >= 1500 && dt >= 1000) { poll_ver(); t0_ = now_ms; }
      if (quiet >= 5000) { cand_ = 0; set_applied_ = false; tune_ = 0; mon_ = 0; mon_t0_ = 0; go(DETECT, now_ms); }   // receiver reset or unplugged
      break;
    }
  }
}

}  // namespace avo
