// Host tests for V3.5.0: ESP-NOW link framing + pairing, ZED-F9P manager, and an
// end-to-end simulation chest <-> lossy radio <-> back <-> simulated ZED-F9P.
// The simulated ZED is a model written from the u-blox interface description; it is
// NOT the real receiver (see PRUEBAS: the real test is pending on hardware).
#include "tiny_test.h"
#include "avo_core.h"
#include <deque>
#include <map>
#include <random>
#include <set>

using namespace avo;

static std::vector<uint8_t> hex(const char* h) {
  std::vector<uint8_t> v;
  for (size_t i = 0; h[i] && h[i + 1]; i += 2) { unsigned x; sscanf(h + i, "%2x", &x); v.push_back((uint8_t)x); }
  return v;
}

// ======================================================================= framing
TEST(now, packet_roundtrip_and_rejections) {
  uint8_t body[200];
  for (int i = 0; i < 200; i++) body[i] = (uint8_t)(i * 13 + 1);
  NowHeader h; h.kind = NowKind::DATA; h.pair_id = 0x12345678; h.boot_id = 0xCAFEBABE;
  uint8_t p[NOW_MAX_PACKET];
  size_t n = now_build(h, body, 200, p, sizeof(p));
  CHECK_EQ(n, (size_t)216);
  NowHeader g; const uint8_t* b;
  CHECK(now_parse(p, n, &g, &b));
  CHECK_EQ(g.pair_id, 0x12345678u); CHECK_EQ(g.boot_id, 0xCAFEBABEu); CHECK_EQ(g.body_len, 200);
  CHECK(memcmp(b, body, 200) == 0);
  CHECK(now_build(h, body, NOW_MAX_BODY + 1, p, sizeof(p)) == 0);       // too big
  uint8_t q[NOW_MAX_PACKET]; memcpy(q, p, n); q[100] ^= 1;
  CHECK(!now_parse(q, n, &g, &b));                                       // CRC
  memcpy(q, p, n); q[0] = 0xA5; q[1] = 0x0C;
  CHECK(!now_parse(q, n, &g, &b));                                       // V3.4.5 test magic is not ours
  CHECK(!now_parse(p, n - 1, &g, &b));                                   // truncated
  // max size packet
  CHECK_EQ(now_build(h, body, 0, p, sizeof(p)), NOW_HDR);
}

TEST(now, rtcm_frame_fits_one_packet) {
  uint8_t pl[RTCM_DATA_HDR + NOW_RTCM_CHUNK] = {0};
  uint8_t f[AVO_UART_MAX_FRAME];
  size_t n = uart_encode(FrameType::RTCM_DATA, FF_PRIO_HIGH, 2, 1, 0, pl, sizeof(pl), f, sizeof(f));
  CHECK(n <= NOW_MAX_BODY);
  BackStatus s; s.v2 = true;
  uint8_t b[BACK_STATUS_V2_LEN + 4];
  size_t sn = encode_status(s, b, sizeof(b));
  CHECK_EQ(sn, BACK_STATUS_V2_LEN);
  CHECK(sn + AVO_UART_HDR + AVO_UART_TRAILER <= NOW_MAX_BODY);
}

TEST(now, back_status_v2_roundtrip_and_v1_compat) {
  BackStatus s;
  s.uptime_ms = 1; s.zed_state = 2; s.rtcm_rx_bytes = 1000; s.rtcm_to_zed_bytes = 990; s.rxm_rtcm_used = 7;
  s.gnss_rate_hz_x10 = 100; s.v2 = true; s.zed_baud = 230400; s.zed_port = 2; s.zed_cfg = 3; s.nav_rate_cfg_hz = 10;
  s.zed_detail = 3; s.rtcm_gaps_bytes = 5; s.rtcm_not_written = 6; s.link_tx_fail = 7; s.link_rssi = -61; s.ubx_frames = 99; s.nmea_sentences = 4;
  uint8_t b[128];
  size_t n = encode_status(s, b, sizeof(b));
  BackStatus d;
  CHECK(decode_status(b, n, &d));
  CHECK(d.v2); CHECK_EQ(d.zed_baud, 230400u); CHECK_EQ(d.zed_port, 2); CHECK_EQ(d.link_rssi, -61); CHECK_EQ(d.nmea_sentences, 4u);
  CHECK_EQ(d.rtcm_to_zed_bytes, 990u); CHECK_EQ(d.rxm_rtcm_used, 7u);
  BackStatus d1;
  CHECK(decode_status(b, BACK_STATUS_V1_LEN, &d1));   // a v1 payload still decodes
  CHECK(!d1.v2);
  CHECK_EQ(d1.rtcm_to_zed_bytes, 990u);
}

TEST(now, peer_record) {
  NowPeerRecord r; r.valid = true; uint8_t m[6] = {1, 2, 3, 4, 5, 6}; memcpy(r.mac, m, 6); r.pair_id = 77;
  uint8_t b[NOW_PEER_RECORD_LEN];
  CHECK_EQ(now_peer_serialize(r, b, sizeof(b)), NOW_PEER_RECORD_LEN);
  NowPeerRecord q;
  CHECK(now_peer_deserialize(b, sizeof(b), &q));
  CHECK(q.valid && q.pair_id == 77 && memcmp(q.mac, m, 6) == 0);
  uint8_t z[NOW_PEER_RECORD_LEN] = {0};
  CHECK(!now_peer_deserialize(z, sizeof(z), &q));   // "forget" writes zeros
  b[5] ^= 1;
  CHECK(!now_peer_deserialize(b, sizeof(b), &q));
}

// ======================================================================= pairing
static const uint8_t MAC_CA[6] = {0xC0, 0, 0, 0, 0, 0xA1}, MAC_CB[6] = {0xC0, 0, 0, 0, 0, 0xB2};
static const uint8_t MAC_BA[6] = {0xBA, 0, 0, 0, 0, 0xA1}, MAC_BB[6] = {0xBA, 0, 0, 0, 0, 0xB2};

static bool req(NowPairing& chest, uint32_t now, NowHeader* h, NowPairMsg* m) {
  uint8_t body[64];
  size_t n = chest.chest_poll(now, "CHEST", "3.5.0", body, sizeof(body));
  if (!n) return false;
  h->kind = NowKind::PAIR_REQ; h->pair_id = chest.proposed_pair_id(); h->boot_id = 1;
  return now_pair_decode(body, n, m);
}

TEST(pairing, first_boot_pairs_and_neighbours_do_not_mix) {
  NowPairing ca(NowRole::CHEST), ba(NowRole::BACK), bb(NowRole::BACK);
  ca.open(0, 0, 111, 222);                              // unpaired chest: open until success
  NowHeader h; NowPairMsg m;
  CHECK(req(ca, 0, &h, &m));
  CHECK(!req(ca, 500, &h, &m));                         // 1 Hz
  CHECK(req(ca, 1000, &h, &m));
  CHECK(ba.back_on_req(MAC_CA, h, m, 1000, 0));         // unpaired back accepts
  CHECK_EQ(ba.last_accept_reason(), 1u);
  NowHeader ah; ah.kind = NowKind::PAIR_ACK; ah.pair_id = h.pair_id;
  NowPairMsg am; am.role = NowRole::BACK; am.nonce = m.nonce;
  NowPairMsg wrong = am; wrong.nonce = 999;
  CHECK(!ca.chest_on_ack(MAC_BA, ah, wrong, 1001));     // stale / foreign ACK
  CHECK(ca.chest_on_ack(MAC_BA, ah, am, 1001));
  CHECK(ca.paired() && !ca.open_now(1002));
  CHECK(ca.accept_data(MAC_BA, 222));
  CHECK(!ca.accept_data(MAC_BB, 222));
  CHECK(!ca.accept_data(MAC_BA, 223));
  CHECK(ba.accept_data(MAC_CA, 222));
  // A second chest asks to pair (user pressed "Emparejar espalda" on it) while back A
  // is linked to chest A and hears it: back A must refuse.
  NowPairing cb(NowRole::CHEST);
  cb.open(5000, 60000, 333, 444);
  CHECK(req(cb, 5000, &h, &m));
  CHECK(!ba.back_on_req(MAC_CB, h, m, 5000, 4990));
  // ...but back B, unpaired, takes it
  CHECK(bb.back_on_req(MAC_CB, h, m, 5000, 0));
  // back A orphaned (chest A silent for 60 s) -> accepts the new chest
  CHECK(ba.back_on_req(MAC_CB, h, m, 70000, 5000));
  CHECK_EQ(ba.last_accept_reason(), 4u);
}

TEST(pairing, button_window_and_same_chest) {
  NowPairing b(NowRole::BACK);
  NowPeerRecord r; r.valid = true; memcpy(r.mac, MAC_CA, 6); r.pair_id = 5; b.load(r);
  NowHeader h; h.kind = NowKind::PAIR_REQ; h.pair_id = 9; NowPairMsg m; m.role = NowRole::CHEST; m.nonce = 1;
  CHECK(!b.back_on_req(MAC_CB, h, m, 1000, 900));                 // other chest, ours alive
  b.back_open(1000, 120000);
  CHECK(b.back_on_req(MAC_CB, h, m, 2000, 1900));                  // PRG window
  CHECK_EQ(b.last_accept_reason(), 2u);
  CHECK(b.back_on_req(MAC_CB, h, m, 3000, 2900));                  // same chest re-pairs (lost its memory)
  CHECK_EQ(b.last_accept_reason(), 3u);
  CHECK(!b.back_on_req(MAC_CA, h, m, 4000, 3900));                 // old chest is now foreign
  // the back must not grab a chest in its first minute after boot (orphan rule)
  NowPairing c(NowRole::BACK); c.load(r);
  CHECK(!c.back_on_req(MAC_CB, h, m, 30000, 0));
  CHECK(c.back_on_req(MAC_CB, h, m, 61000, 0));
}

// ======================================================================= UBX / ZED
TEST(ubx, valset_bytes_match_reference) {
  ZedKV kv = {zedkey::RATE_MEAS, 100};
  uint8_t b[64];
  size_t n = ubx_valset_ram(&kv, 1, b, sizeof(b));
  auto ref = hex("b562068a0a000001000001002130640051b9");   // computed independently (Python)
  CHECK_EQ(n, ref.size());
  CHECK(memcmp(b, ref.data(), n) == 0);
  ZedKV kv3[3] = {{zedkey::MSGOUT_NAV_PVT_UART2, 1}, {zedkey::UART2_BAUDRATE, 230400}, {zedkey::UART2OUTPROT_NMEA, 0}};
  n = ubx_valset_ram(kv3, 3, b, sizeof(b));
  auto ref3 = hex("b562068a16000001000008009120010100534000840300020076100004a8");
  CHECK_EQ(n, ref3.size());
  CHECK(memcmp(b, ref3.data(), n) == 0);
  n = ubx_poll(UBX_CLS_MON, UBX_ID_MON_VER, b, sizeof(b));
  auto ver = hex("b5620a0400000e34");                        // well-known MON-VER poll
  CHECK(n == 8 && memcmp(b, ver.data(), 8) == 0);
  CHECK_EQ(zed_key_value_size(zedkey::UART1_BAUDRATE), (size_t)4);
  CHECK_EQ(zed_key_value_size(zedkey::RATE_MEAS), (size_t)2);
  CHECK_EQ(zed_key_value_size(zedkey::UART1INPROT_UBX), (size_t)1);
}

struct Got { std::vector<std::vector<uint8_t>> f; };
static void got_cb(const uint8_t* f, size_t n, void* ctx) { ((Got*)ctx)->f.emplace_back(f, f + n); }

TEST(ubx, stream_extracts_frames_from_mixed_traffic) {
  Got g;
  UbxStream s(got_cb, &g);
  std::vector<uint8_t> all;
  const char* nmea = "$GNGGA,120000.00,4000.0000000,N,00300.0000000,W,4,25,0.5,650.0,M,0.0,M,1.0,0000*";
  uint8_t cs = 0; for (const char* p = nmea + 1; *p != '*'; p++) cs ^= (uint8_t)*p;
  char line[160]; snprintf(line, sizeof(line), "%s%02X\r\n", nmea, cs);
  uint8_t f1[200], f2[200], r[64], rtcmpl[20] = {0x43, 0x50};
  size_t n1 = ubx_poll(UBX_CLS_MON, UBX_ID_MON_VER, f1, sizeof(f1));
  uint8_t pvt[92] = {0};
  size_t n2 = ubx_build(UBX_CLS_NAV, UBX_ID_NAV_PVT, pvt, 92, f2, sizeof(f2));
  size_t nr = rtcm_build(rtcmpl, 20, r, sizeof(r));
  all.insert(all.end(), line, line + strlen(line));
  all.insert(all.end(), f1, f1 + n1);
  all.insert(all.end(), r, r + nr);
  all.push_back(0xB5);                                     // false sync
  all.insert(all.end(), f2, f2 + n2);
  std::vector<uint8_t> bad(f2, f2 + n2); bad[20] ^= 0xFF;   // corrupted NAV-PVT
  all.insert(all.end(), bad.begin(), bad.end());
  all.insert(all.end(), line, line + strlen(line));
  for (size_t i = 0; i < all.size(); i += 7) s.feed(all.data() + i, std::min<size_t>(7, all.size() - i));
  CHECK_EQ(g.f.size(), (size_t)2);
  CHECK_EQ(s.bad_checksum(), 1u);
  CHECK_EQ(s.nmea_sentences(), 2u);
}

// ---------------------------------------------------------------- simulated ZED-F9P
struct SimZed {
  int port = 2;                                  // which ZED UART is wired to the back
  uint32_t baud[3] = {0, 38400, 38400};
  bool in_ubx[3] = {false, true, true}, in_rtcm[3] = {false, true, true};
  bool out_ubx[3] = {false, true, false}, out_nmea[3] = {false, true, false};
  bool pvt[3] = {false, false, false}, rxm[3] = {false, false, false};
  uint16_t meas_ms = 1000;
  bool nak_rate = false;
  bool old_fw = false;                           // V3.8.0: firmware that does not know the precision keys
  uint8_t dyn = 0, dgnss = 3; int8_t min_elev = 10;
  bool gnss[4] = {true, true, true, true};       // GPS, GLO, GAL, BDS
  uint32_t signal_restarts = 0;
  uint32_t sat_every[3] = {0, 0, 0}, sig_every[3] = {0, 0, 0};   // V3.9.0 NAV-SAT/SIG output rate
  bool l2_antenna = true;
  bool no_sig_key = false;   // older receiver firmware: NAV-SIG key unknown
  uint8_t carr = 2;                                           // carrSoln reported in NAV-PVT
  bool alive = true;
  std::deque<std::pair<uint32_t, uint8_t>> out;   // (baud it was sent at, byte)
  std::vector<uint8_t> rtcm_bytes;                // RTCM frames accepted (valid CRC)
  uint32_t rtcm_frames = 0, garbage_from_back = 0, epochs = 0, valsets = 0;
  uint32_t next_epoch = 0;
  // incoming parsers
  std::vector<uint8_t> in;

  void send_ubx(uint8_t cls, uint8_t id, const uint8_t* pl, uint16_t n) {
    if (!out_ubx[port]) return;
    uint8_t b[2100];
    size_t len = ubx_build(cls, id, pl, n, b, sizeof(b));
    for (size_t i = 0; i < len; i++) out.push_back({baud[port], b[i]});
  }
  void send_text(const char* s) { for (; *s; s++) out.push_back({baud[port], (uint8_t)*s}); }

  bool known(uint32_t k) {
    if (no_sig_key && (k == zedkey::MSGOUT_NAV_SIG_UART1 || k == zedkey::MSGOUT_NAV_SIG_UART2)) return false;
    static const uint32_t ks[] = {zedkey::RATE_MEAS, zedkey::UART1_BAUDRATE, zedkey::UART2_BAUDRATE,
      zedkey::UART1INPROT_UBX, zedkey::UART1INPROT_NMEA, zedkey::UART1INPROT_RTCM3X, zedkey::UART1OUTPROT_UBX, zedkey::UART1OUTPROT_NMEA,
      zedkey::UART1OUTPROT_RTCM3X, zedkey::UART2INPROT_UBX, zedkey::UART2INPROT_NMEA, zedkey::UART2INPROT_RTCM3X, zedkey::UART2OUTPROT_UBX,
      zedkey::UART2OUTPROT_NMEA, zedkey::UART2OUTPROT_RTCM3X, zedkey::MSGOUT_NAV_PVT_UART1, zedkey::MSGOUT_NAV_PVT_UART2,
      zedkey::MSGOUT_RXM_RTCM_UART1, zedkey::MSGOUT_RXM_RTCM_UART2,
      zedkey::MSGOUT_NAV_SAT_UART1, zedkey::MSGOUT_NAV_SAT_UART2, zedkey::MSGOUT_NAV_SIG_UART1, zedkey::MSGOUT_NAV_SIG_UART2};
    for (uint32_t x : ks) if (x == k) return true;
    static const uint32_t tune[] = {zedkey::NAVSPG_DYNMODEL, zedkey::NAVHPG_DGNSSMODE, zedkey::NAVSPG_INFIL_MINELEV,
      zedkey::NAVSPG_INFIL_MINCNO, zedkey::SIGNAL_GPS_ENA, zedkey::SIGNAL_GLO_ENA, zedkey::SIGNAL_GAL_ENA, zedkey::SIGNAL_BDS_ENA};
    if (!old_fw) for (uint32_t x : tune) if (x == k) return true;
    return false;
  }
  void valset(const uint8_t* pl, uint16_t n) {
    valsets++;
    // parse all keys first: the real receiver applies a VALSET atomically
    std::vector<std::pair<uint32_t, uint32_t>> kv;
    size_t i = 4;
    bool ok = n >= 4 && pl[1] == 0x01;
    while (ok && i + 4 <= n) {
      uint32_t k = get_u32(pl + i); i += 4;
      size_t vs = zed_key_value_size(k);
      if (!known(k) || (k == zedkey::RATE_MEAS && nak_rate) || i + vs > n) { ok = false; break; }
      uint32_t v = vs == 1 ? pl[i] : vs == 2 ? get_u16(pl + i) : get_u32(pl + i);
      i += vs;
      kv.push_back({k, v});
    }
    uint8_t ack[2] = {UBX_CLS_CFG, UBX_ID_CFG_VALSET};
    send_ubx(UBX_CLS_ACK, ok ? UBX_ID_ACK_ACK : UBX_ID_ACK_NAK, ack, 2);   // answered at the current baud
    if (!ok) return;
    bool sig = false;
    for (auto& p : kv) {
      uint32_t k = p.first, v = p.second;
      if (k == zedkey::NAVSPG_DYNMODEL) dyn = (uint8_t)v;
      else if (k == zedkey::NAVHPG_DGNSSMODE) dgnss = (uint8_t)v;
      else if (k == zedkey::NAVSPG_INFIL_MINELEV) min_elev = (int8_t)v;
      else if (k == zedkey::SIGNAL_GPS_ENA) { gnss[0] = v; sig = true; } else if (k == zedkey::SIGNAL_GLO_ENA) { gnss[1] = v; sig = true; }
      else if (k == zedkey::SIGNAL_GAL_ENA) { gnss[2] = v; sig = true; } else if (k == zedkey::SIGNAL_BDS_ENA) { gnss[3] = v; sig = true; }
      if (k == zedkey::RATE_MEAS) meas_ms = (uint16_t)v;
      else if (k == zedkey::UART1_BAUDRATE) baud[1] = v; else if (k == zedkey::UART2_BAUDRATE) baud[2] = v;
      else if (k == zedkey::UART1INPROT_UBX) in_ubx[1] = v; else if (k == zedkey::UART2INPROT_UBX) in_ubx[2] = v;
      else if (k == zedkey::UART1INPROT_RTCM3X) in_rtcm[1] = v; else if (k == zedkey::UART2INPROT_RTCM3X) in_rtcm[2] = v;
      else if (k == zedkey::UART1OUTPROT_UBX) out_ubx[1] = v; else if (k == zedkey::UART2OUTPROT_UBX) out_ubx[2] = v;
      else if (k == zedkey::UART1OUTPROT_NMEA) out_nmea[1] = v; else if (k == zedkey::UART2OUTPROT_NMEA) out_nmea[2] = v;
      else if (k == zedkey::MSGOUT_NAV_PVT_UART1) pvt[1] = v; else if (k == zedkey::MSGOUT_NAV_PVT_UART2) pvt[2] = v;
      else if (k == zedkey::MSGOUT_RXM_RTCM_UART1) rxm[1] = v; else if (k == zedkey::MSGOUT_RXM_RTCM_UART2) rxm[2] = v;
      else if (k == zedkey::MSGOUT_NAV_SAT_UART1) sat_every[1] = v; else if (k == zedkey::MSGOUT_NAV_SAT_UART2) sat_every[2] = v;
      else if (k == zedkey::MSGOUT_NAV_SIG_UART1) sig_every[1] = v; else if (k == zedkey::MSGOUT_NAV_SIG_UART2) sig_every[2] = v;
    }
    if (sig) signal_restarts++;
  }
  // bytes written by the back at back_baud
  void from_back(const uint8_t* d, size_t n, uint32_t back_baud) {
    if (!alive) return;
    if (back_baud != baud[port]) { garbage_from_back += (uint32_t)n; return; }
    in.insert(in.end(), d, d + n);
    // consume complete UBX / RTCM frames
    for (;;) {
      size_t i = 0;
      while (i < in.size() && in[i] != 0xB5 && in[i] != 0xD3) i++;
      in.erase(in.begin(), in.begin() + i);
      if (in.size() < 6) return;
      if (in[0] == 0xB5) {
        if (in[1] != 0x62) { in.erase(in.begin()); continue; }
        size_t len = 8 + in[4] + (in[5] << 8);
        if (in.size() < len) return;
        uint8_t cls, id; const uint8_t* pl; uint16_t plen;
        if (in_ubx[port] && ubx_check_frame(in.data(), len, &cls, &id, &pl, &plen)) {
          if (cls == UBX_CLS_CFG && id == UBX_ID_CFG_VALSET) valset(pl, plen);
          else if (cls == UBX_CLS_MON && id == UBX_ID_MON_VER && plen == 0) { uint8_t v[40] = {'R', 'O', 'M'}; send_ubx(UBX_CLS_MON, UBX_ID_MON_VER, v, 40); }
        }
        in.erase(in.begin(), in.begin() + len);
      } else {
        if (in[1] & 0xFC) { in.erase(in.begin()); continue; }
        size_t len = 6 + (((in[1] & 3) << 8) | in[2]);
        if (in.size() < len) return;
        uint32_t c = crc24q(in.data(), len - 3);
        bool ok = ((uint32_t)in[len - 3] << 16 | (uint32_t)in[len - 2] << 8 | in[len - 1]) == c;
        if (ok && in_rtcm[port]) {
          rtcm_frames++;
          rtcm_bytes.insert(rtcm_bytes.end(), in.begin(), in.begin() + len);
          if (rxm[port]) {
            uint8_t r[8] = {2, 2 << 1, 0, 0, 0, 0, 0, 0};
            uint16_t type = (uint16_t)((in[3] << 4) | (in[4] >> 4));
            put_u16(r + 6, type);
            send_ubx(UBX_CLS_RXM, UBX_ID_RXM_RTCM, r, 8);
          }
          in.erase(in.begin(), in.begin() + len);
        } else in.erase(in.begin());
      }
    }
  }
  void tick(uint32_t now) {
    if (!alive) return;
    if (now < next_epoch) return;
    next_epoch = now + meas_ms;
    epochs++;
    if (pvt[port]) {
      GnssSample g; g.itow_ms = now; g.fix_type = 3; g.flags = (uint8_t)(0x01 | 0x02 | (carr << 6)); g.num_sv = 28;
      g.lat_e7 = 433800000; g.lon_e7 = -32170000; g.hacc_mm = 14; g.year = 2026;
      uint8_t pl[92]; ubx_encode_nav_pvt(g, pl, sizeof(pl));
      send_ubx(UBX_CLS_NAV, UBX_ID_NAV_PVT, pl, 92);
    }
    if (sat_every[port] && epochs % sat_every[port] == 0) {   // 20 satellites, 18 used
      std::vector<uint8_t> b(8 + 20 * 12, 0); b[5] = 20;
      for (int i = 0; i < 20; i++) { uint8_t* q = &b[8 + i * 12]; q[0] = (uint8_t)(i % 4 == 3 ? 6 : i % 4); q[1] = (uint8_t)(i + 1); q[2] = 40; if (i < 18) q[8] = 1 << 3; }
      send_ubx(UBX_CLS_NAV, UBX_ID_NAV_SAT, b.data(), (uint16_t)b.size());
    }
    if (sig_every[port] && epochs % sig_every[port] == 0) {   // 20 L1 + 20 second-band signals (if the antenna has L2)
      int nsig = l2_antenna ? 40 : 20;
      std::vector<uint8_t> b(8 + nsig * 16, 0); b[5] = (uint8_t)nsig;
      for (int i = 0; i < nsig; i++) {
        uint8_t* q = &b[8 + i * 16];
        q[0] = 0; q[1] = (uint8_t)(i % 20 + 1); q[2] = i < 20 ? 0 : 3;   // GPS L1C/A, then L2CL
        q[6] = (uint8_t)(i % 10 == 9 ? 25 : 44);                          // two weak signals per band
        uint16_t f = (1u << 3) | (carr ? (1u << 4) : 0) | (1u << 6);
        if (q[6] < 30) f = 0;
        q[10] = (uint8_t)f; q[11] = (uint8_t)(f >> 8);
      }
      send_ubx(UBX_CLS_NAV, UBX_ID_NAV_SIG, b.data(), (uint16_t)b.size());
    }
    if (out_nmea[port]) send_text("$GNGSA,A,3,,,,,,,,,,,,,1.0,0.5,0.8,1*00\r\n$GPTXT,01,01,02,u-blox*00\r\n");   // bad checksums: noise only
  }
  void power_cycle() {            // RAM configuration lost
    SimZed fresh; fresh.port = port;
    *this = fresh;
  }
};

// ---------------------------------------------------------------- lossy radio + chest model
struct Radio {
  std::mt19937 rng{1234};
  double loss = 0.0;          // packet lost before the receiver
  double ack_loss = 0.0;      // received, but the sender is told "failed" (MAC ACK lost)
  uint32_t sent = 0, lost = 0, dup_risk = 0;
  // returns {delivered, sender_sees_success}
  std::pair<bool, bool> attempt() {
    sent++;
    std::uniform_real_distribution<double> u(0, 1);
    if (u(rng) < loss) { lost++; return {false, false}; }
    if (u(rng) < ack_loss) { dup_risk++; return {true, false}; }
    return {true, true};
  }
};

struct Pkt { uint8_t mac[6]; std::vector<uint8_t> d; };

struct ChestModel {
  NowPairing pair{NowRole::CHEST};
  NowBootGuard guard;
  UartDecoder* dec = nullptr;
  uint32_t boot_id = 0x11110001;
  uint16_t seq = 0;
  uint32_t rtcm_off = 0;
  std::vector<GnssSample> gnss;
  BackStatus last_status; bool have_status = false;
  Caps caps; bool have_caps = false;
  uint32_t last_rx_ms = 0, tx_fail = 0, rtcm_lost_bytes = 0;
  ChestModel() { dec = new UartDecoder(on_frame, this); pair.open(0, 0, 0xA0A0, 0xB0B0); }
  ~ChestModel() { delete dec; }
  static void on_frame(const FrameView& f, void* ctx) {
    ChestModel* c = (ChestModel*)ctx;
    if (f.type == FrameType::GNSS_SAMPLE) { GnssSample g; if (decode_gnss(f.payload, f.len, &g)) c->gnss.push_back(g); }
    if (f.type == FrameType::STATUS) c->have_status = decode_status(f.payload, f.len, &c->last_status);
    if (f.type == FrameType::CAPS) c->have_caps = decode_caps(f.payload, f.len, &c->caps);
  }
  void reboot() { boot_id++; seq = 0; rtcm_off = 0; delete dec; dec = new UartDecoder(on_frame, this); guard = NowBootGuard(); }
};

struct World;
struct TestPlatform : public BackPlatform {
  World* w;
  uint32_t baud = 38400;
  NowPeerRecord saved;
  uint32_t reboots = 0;
  std::mt19937 rng{99};
  uint32_t now_ms() override;
  void zed_set_baud(uint32_t b) override { baud = b; }
  void zed_write(const uint8_t* d, size_t n) override;
  bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) override;
  void radio_set_peer(const uint8_t*) override {}
  void save_peer(const NowPeerRecord& r) override { saved = r; }
  uint32_t random32() override { return rng(); }
  void reboot() override { reboots++; }
};

struct World {
  uint32_t now = 0;
  SimZed zed;
  Radio radio;
  TestPlatform plat;
  BackCore* back = nullptr;
  ChestModel chest;
  std::deque<Pkt> to_back, to_chest;
  std::vector<uint8_t> phone_rtcm;      // what the phone sent (= what must reach the ZED)
  std::mt19937 rng{7};
  World(int zport = 2) {
    zed.port = zport;
    plat.w = this;
    back = new BackCore(&plat, "BACKTEST", 10);
    back->begin(NowPeerRecord());
  }
  ~World() { delete back; }
  // chest -> radio with up to 4 attempts (like flush_packet in the chest firmware)
  bool chest_send(const uint8_t* mac, const uint8_t* d, size_t n, bool broadcast = false) {
    for (int i = 0; i < 4; i++) {
      auto r = radio.attempt();
      if (r.first) { Pkt p; memcpy(p.mac, MAC_CA, 6); p.d.assign(d, d + n); to_back.push_back(p); }
      if (broadcast) return true;           // broadcast: no ACK, single shot
      if (r.second) return true;
    }
    (void)mac;
    return false;
  }
  void chest_frames(FrameType t, const uint8_t* pl, size_t len, uint32_t rtcm_n = 0) {
    uint8_t f[256];
    size_t fn = uart_encode(t, t == FrameType::RTCM_DATA ? FF_PRIO_HIGH : 0, 2, chest.seq++, now, pl, len, f, sizeof(f));
    NowHeader h; h.kind = NowKind::DATA; h.pair_id = chest.pair.peer().pair_id; h.boot_id = chest.boot_id;
    uint8_t pkt[NOW_MAX_PACKET];
    size_t n = now_build(h, f, fn, pkt, sizeof(pkt));
    if (!chest_send(chest.pair.peer().mac, pkt, n)) { chest.tx_fail++; chest.rtcm_lost_bytes += rtcm_n; }
  }
  void phone_rtcm_frame() {
    uint8_t pl[300];
    std::uniform_int_distribution<int> L(20, 280);
    int n = L(rng);
    for (int i = 0; i < n; i++) pl[i] = (uint8_t)rng();
    pl[0] = 0x43; pl[1] = 0x50;
    uint8_t f[320];
    size_t fn = rtcm_build(pl, (uint16_t)n, f, sizeof(f));
    phone_rtcm.insert(phone_rtcm.end(), f, f + fn);
  }
  size_t rtcm_sent = 0;
  void chest_step() {
    // pairing
    uint8_t body[64];
    size_t bl = chest.pair.chest_poll(now, "CHEST", "3.5.0", body, sizeof(body));
    if (bl) {
      NowHeader h; h.kind = NowKind::PAIR_REQ; h.pair_id = chest.pair.proposed_pair_id(); h.boot_id = chest.boot_id;
      uint8_t pkt[NOW_MAX_PACKET];
      size_t n = now_build(h, body, bl, pkt, sizeof(pkt));
      chest_send(nullptr, pkt, n, true);
    }
    // inbound
    while (!to_chest.empty()) {
      Pkt p = to_chest.front(); to_chest.pop_front();
      NowHeader h; const uint8_t* b;
      if (!now_parse(p.d.data(), p.d.size(), &h, &b)) continue;
      if (h.kind == NowKind::PAIR_ACK) { NowPairMsg m; if (now_pair_decode(b, h.body_len, &m)) chest.pair.chest_on_ack(p.mac, h, m, now); continue; }
      if (h.kind != NowKind::DATA || !chest.pair.accept_data(p.mac, h.pair_id)) continue;
      if (chest.guard.changed(h.boot_id)) { delete chest.dec; chest.dec = new UartDecoder(ChestModel::on_frame, &chest); }
      chest.last_rx_ms = now;
      chest.dec->feed(b, h.body_len);
    }
    if (!chest.pair.paired()) return;
    // heartbeat 1 Hz
    if (now % 1000 == 0) { Heartbeat hb; hb.uptime_ms = now; uint8_t b[HEARTBEAT_V1_LEN]; encode_heartbeat(hb, b, sizeof(b)); chest_frames(FrameType::HEARTBEAT, b, sizeof(b)); }
    // RTCM: ~1.5 kB/s from the phone, sent in <= 200-byte chunks with the stream offset
    bool link_up = chest.last_rx_ms && now - chest.last_rx_ms < 2000;
    while (rtcm_sent < phone_rtcm.size()) {
      size_t n = std::min<size_t>(NOW_RTCM_CHUNK, phone_rtcm.size() - rtcm_sent);
      if (!link_up) { chest.rtcm_lost_bytes += (uint32_t)n; rtcm_sent += n; chest.rtcm_off += (uint32_t)n; continue; }
      uint8_t pl[RTCM_DATA_HDR + NOW_RTCM_CHUNK];
      put_u32(pl, chest.rtcm_off);
      memcpy(pl + 4, phone_rtcm.data() + rtcm_sent, n);
      chest_frames(FrameType::RTCM_DATA, pl, n + 4, (uint32_t)n);
      chest.rtcm_off += (uint32_t)n;
      rtcm_sent += n;
    }
  }
  void step() {
    now++;
    zed.tick(now);
    // ZED -> back UART: deliver bytes sent at the baud the back is listening to
    std::vector<uint8_t> chunk;
    while (!zed.out.empty() && chunk.size() < 64) {   // ~64 B/ms: fast enough for these rates
      auto b = zed.out.front(); zed.out.pop_front();
      if (b.first == plat.baud) chunk.push_back(b.second);
    }
    if (!chunk.empty()) back->on_zed(chunk.data(), chunk.size());
    while (!to_back.empty()) { Pkt p = to_back.front(); to_back.pop_front(); back->on_radio(p.mac, p.d.data(), p.d.size(), -55); }
    back->tick();
    chest_step();
  }
  void run_ms(uint32_t ms, int rtcm_per_s = 0) {
    for (uint32_t i = 0; i < ms; i++) {
      if (rtcm_per_s && now % (1000 / rtcm_per_s) == 0) phone_rtcm_frame();
      step();
    }
  }
};

uint32_t TestPlatform::now_ms() { return w->now; }
void TestPlatform::zed_write(const uint8_t* d, size_t n) { w->zed.from_back(d, n, baud); }
bool TestPlatform::radio_send(const uint8_t* mac, const uint8_t* d, size_t n) {
  auto r = w->radio.attempt();
  if (r.first) { Pkt p; memcpy(p.mac, MAC_BA, 6); p.d.assign(d, d + n); w->to_chest.push_back(p); }
  (void)mac;
  return r.second;
}

// ---------------------------------------------------------------- ZED manager scenarios
TEST(zed, uart2_factory_default_gets_configured) {
  World w(2);                     // UART2 at 38400, UBX in, no output (u-blox default-like)
  w.run_ms(15000);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  CHECK_EQ(w.back->zed().port(), 2);
  CHECK_EQ(w.back->zed().baud(), 230400u);
  CHECK_EQ(w.zed.baud[2], 230400u);
  CHECK(w.zed.pvt[2] && w.zed.rxm[2] && w.zed.out_ubx[2]);
  CHECK_EQ(w.zed.meas_ms, 100);
  CHECK(w.back->zed().config_acked());
  CHECK_EQ(w.zed.baud[1], 38400u);                // the other port was not touched
  CHECK(w.back->stats().nav_pvt > 50);
}

TEST(zed, uart1_with_nmea_gets_configured) {
  World w(1);
  w.zed.baud[1] = 115200;          // previously set by the user
  w.run_ms(15000);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  CHECK_EQ(w.back->zed().port(), 1);
  CHECK_EQ(w.zed.baud[1], 230400u);
  CHECK(!w.zed.out_nmea[1]);       // NMEA off on the back's port only
  CHECK(w.zed.pvt[1]);
}

TEST(zed, no_ubx_input_falls_back_to_38400_and_rtcm_still_reaches_the_zed) {
  World w(2);
  w.zed.in_ubx[2] = false;         // port accepts only RTCM3 (cannot be configured from the back)
  w.run_ms(20000, 2);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::NO_RESPONSE);
  CHECK_EQ(w.back->zed().status_code(), 3);
  CHECK(w.zed.rtcm_frames > 0);    // corrections are injected anyway
  CHECK(w.chest.gnss.empty());     // no position available: reported, not invented
  CHECK(w.chest.have_status && w.chest.last_status.zed_state == 3);
}

TEST(zed, rate_nak_retries_without_rate) {
  World w(2);
  w.zed.nak_rate = true;
  w.run_ms(15000);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  CHECK(w.back->zed().config_acked());
  CHECK(!w.back->zed().rate_applied());
  CHECK(w.zed.pvt[2]);
  CHECK_EQ(w.zed.meas_ms, 1000);
}

TEST(zed, receiver_power_cycle_is_detected_and_reconfigured) {
  World w(2);
  w.run_ms(15000);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  w.zed.power_cycle();             // back to 38400, outputs off
  w.zed.port = 2;
  w.run_ms(25000);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  CHECK_EQ(w.zed.baud[2], 230400u);
  CHECK(w.zed.pvt[2]);
}

// ---------------------------------------------------------------- end to end
// Walks the ZED stream and the phone stream frame by frame. Returns false if the ZED
// received anything that is not the next phone frame (unknown, duplicated, reordered).
static bool walk(const std::vector<uint8_t>& got, const std::vector<uint8_t>& ph, size_t* matched, size_t* skipped) {
  size_t i = 0, j = 0;
  *matched = *skipped = 0;
  while (i < got.size() && j < ph.size()) {
    size_t lg = 6 + (((got[i + 1] & 3) << 8) | got[i + 2]);
    size_t lp = 6 + (((ph[j + 1] & 3) << 8) | ph[j + 2]);
    if (lg == lp && memcmp(&got[i], &ph[j], lg) == 0) { (*matched)++; i += lg; j += lp; }
    else { (*skipped)++; j += lp; }
  }
  return i == got.size();
}

TEST(e2e, clean_radio_rtcm_byte_exact_and_gnss_to_chest) {
  World w(2);
  w.run_ms(60000, 2);              // 2 RTCM frames/s for 60 s
  CHECK(w.chest.pair.paired());
  CHECK(w.plat.saved.valid);
  CHECK(w.chest.have_caps && w.chest.caps.node_type == (uint8_t)NodeId::BACK);
  size_t matched, skipped;
  CHECK(walk(w.zed.rtcm_bytes, w.phone_rtcm, &matched, &skipped));
  // only the frames sent before the link and the ZED were ready (first seconds) are missing
  CHECK(matched >= 100);
  CHECK(skipped <= 30);
  // after the first matched frame nothing is missing
  CHECK_EQ(w.back->stats().rtcm_gaps, 0u);
  CHECK_EQ(w.back->stats().rxm_used, w.zed.rtcm_frames);
  CHECK(w.chest.have_status);
  CHECK(w.chest.last_status.rxm_rtcm_used + 4 >= w.zed.rtcm_frames);   // reported each second
  CHECK(w.chest.last_status.v2 && w.chest.last_status.zed_port == 2 && w.chest.last_status.zed_baud == 230400);
  // GNSS at ~10 Hz reaches the chest
  CHECK(w.chest.gnss.size() > 400);
  CHECK(!w.chest.gnss.empty() && w.chest.gnss.back().carr_soln() == 2);
  CHECK(!w.chest.gnss.empty() && w.chest.gnss.back().nav_rate_hz == 10);
}

TEST(e2e, lossy_radio_with_lost_acks_no_duplicates_no_reordering) {
  World w(2);
  w.radio.loss = 0.15;             // 15 % of attempts lost
  w.radio.ack_loss = 0.10;         // 10 % delivered but the sender retries (duplicate risk)
  w.run_ms(60000, 3);
  CHECK(w.radio.dup_risk > 50);
  CHECK(w.zed.rtcm_bytes.size() > 10000);
  size_t matched, skipped;
  CHECK(walk(w.zed.rtcm_bytes, w.phone_rtcm, &matched, &skipped));   // nothing unknown, duplicated or reordered

  CHECK(matched > 100);
  printf("    lossy: matched=%zu skipped=%zu chest_tx_fail=%u chest_rtcm_lost=%u radio sent=%u lost=%u dup_risk=%u back gaps=%u notwritten=%u dup_bytes=%u\n", matched, skipped, w.chest.tx_fail, w.chest.rtcm_lost_bytes, w.radio.sent, w.radio.lost, w.radio.dup_risk, w.back->stats().rtcm_gaps, w.back->stats().rtcm_not_written, w.back->stats().rtcm_dup_bytes);
  // the only frames missing are the ones sent while the back was still detecting the ZED
  // baud (first ~2 s, counted as rtcm_not_written); afterwards nothing is lost
  CHECK(skipped <= 6);
  CHECK_EQ(w.back->stats().rtcm_gaps, 0u);
  CHECK_EQ(w.chest.tx_fail, 0u);
  CHECK(w.chest.gnss.size() > 300);
}

TEST(e2e, chest_reboot_and_second_couple_nearby) {
  World w(2);
  w.run_ms(20000, 2);
  size_t before = w.zed.rtcm_bytes.size();
  w.chest.reboot();                // new boot_id, seq and stream offsets restart at 0
  w.run_ms(20000, 2);
  CHECK(w.zed.rtcm_bytes.size() > before + 1000);   // corrections continue after the chest restart
  CHECK_EQ(w.back->stats().pairings, 1u);           // no re-pairing needed
  // a foreign chest asking to pair while ours is alive is refused
  NowPairing other(NowRole::CHEST);
  other.open(w.now, 60000, 5, 6);
  uint8_t body[64];
  size_t bl = other.chest_poll(w.now, "OTHER", "3.5.0", body, sizeof(body));
  NowHeader h; h.kind = NowKind::PAIR_REQ; h.pair_id = 6; h.boot_id = 9;
  uint8_t pkt[NOW_MAX_PACKET];
  size_t n = now_build(h, body, bl, pkt, sizeof(pkt));
  w.back->on_radio(MAC_CB, pkt, n, -70);
  CHECK(memcmp(w.back->peer().mac, MAC_CA, 6) == 0);
  CHECK_EQ(w.back->stats().pairings, 1u);
}

TEST(e2e, radio_outage_is_counted_and_link_recovers) {
  World w(2);
  w.run_ms(20000, 2);
  size_t before = w.zed.rtcm_bytes.size();
  w.radio.loss = 1.0;              // horse out of range / antenna blocked for 10 s
  w.run_ms(10000, 2);
  CHECK_EQ(w.zed.rtcm_bytes.size(), before);
  CHECK(w.chest.rtcm_lost_bytes > 0);   // the chest counts what it could not deliver
  w.radio.loss = 0.0;
  w.run_ms(20000, 2);
  CHECK(w.zed.rtcm_bytes.size() > before + 3000);
  size_t matched, skipped;
  CHECK(walk(w.zed.rtcm_bytes, w.phone_rtcm, &matched, &skipped));   // still no duplicates or reordering
  CHECK(w.back->stats().rtcm_gaps > 0);  // the back saw the hole in the stream offsets and reports it
  CHECK_EQ(w.back->stats().pairings, 1u);
}

TEST(e2e, back_reboot_keeps_pairing) {
  World w(2);
  w.run_ms(20000, 2);
  NowPeerRecord saved = w.plat.saved;
  CHECK(saved.valid);
  delete w.back;                   // power cycle of the Heltec (the ZED keeps its RAM config)
  w.plat.baud = 38400;
  w.back = new BackCore(&w.plat, "BACKTEST", 10);
  w.back->begin(saved);
  size_t before = w.zed.rtcm_bytes.size();
  size_t gnss_before = w.chest.gnss.size();
  w.run_ms(20000, 2);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);   // finds the ZED at 230400 again
  CHECK(w.zed.rtcm_bytes.size() > before + 3000);
  CHECK(w.chest.gnss.size() > gnss_before + 100);
  CHECK_EQ(w.back->stats().pairings, 0u);   // no new pairing needed
}

// ---------------------------------------------------------------- V3.8.0 precision profile
static void chest_cmd(World& w, BackCmd cmd, uint8_t arg, uint16_t id) {
  Command c; c.cmd = (uint8_t)cmd; c.cmd_id = id; c.arg_len = 1; c.args[0] = arg;
  uint8_t b[64]; size_t n = encode_command(c, b, sizeof(b));
  w.chest_frames(FrameType::COMMAND, b, n);
}

TEST(precision, default_8hz_uses_all_four_constellations_and_rtk_fixed) {
  World w(2);
  delete w.back; w.back = new BackCore(&w.plat, "BACKTEST", 0);   // firmware default
  w.back->begin(NowPeerRecord());
  w.run_ms(15000);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  CHECK_EQ(w.zed.meas_ms, 125);                                   // 8 Hz = F9P RTK limit with 4 GNSS
  CHECK(w.zed.gnss[0] && w.zed.gnss[1] && w.zed.gnss[2] && w.zed.gnss[3]);
  CHECK_EQ(w.zed.dgnss, 3);
  CHECK_EQ(w.zed.dyn, (uint8_t)ZedDynModel::AIRBORNE_2G);
  CHECK_EQ(w.zed.min_elev, 10);
  CHECK_EQ(w.back->zed().tune_state(), 1);
  CHECK(w.zed.epochs > 50);
}

TEST(precision, rate_requests_never_exceed_the_rtk_limit) {
  uint8_t e = 0;
  ZedGnssSet s = zed_gnss_for_rate(10, &e); CHECK(e == 10 && s.glo && s.gal && !s.bds);
  s = zed_gnss_for_rate(12, &e);            CHECK(e == 12 && !s.glo && s.gal && !s.bds);
  s = zed_gnss_for_rate(25, &e);            CHECK(e == 12 && !s.glo && s.gal);
  s = zed_gnss_for_rate(5, &e);             CHECK(e == 5 && s.bds && s.glo);
}

TEST(precision, chest_rate_change_switches_constellations_once) {
  World w(2);                                   // World asks for 10 Hz: GPS+GLO+GAL
  w.run_ms(15000);
  CHECK_EQ(w.zed.meas_ms, 100);
  CHECK(!w.zed.gnss[3] && w.zed.gnss[1]);
  uint32_t restarts = w.zed.signal_restarts;
  chest_cmd(w, BackCmd::SET_GNSS_RATE, 8, 501);
  w.run_ms(3000);
  CHECK_EQ(w.zed.meas_ms, 125);
  CHECK(w.zed.gnss[3]);
  CHECK_EQ(w.zed.signal_restarts, restarts + 1);
  chest_cmd(w, BackCmd::SET_GNSS_RATE, 5, 502);    // same constellations: tracking is not restarted
  w.run_ms(3000);
  CHECK_EQ(w.zed.meas_ms, 200);
  CHECK_EQ(w.zed.signal_restarts, restarts + 1);
  chest_cmd(w, BackCmd::SET_GNSS_RATE, 20, 503);   // clamped to 12 Hz GPS+GAL
  w.run_ms(3000);
  CHECK_EQ(w.zed.meas_ms, 83);
  CHECK(!w.zed.gnss[1] && !w.zed.gnss[3] && w.zed.gnss[2]);
}

TEST(precision, old_receiver_firmware_keeps_working_without_profile) {
  World w(2);
  w.zed.old_fw = true;
  w.run_ms(15000);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  CHECK_EQ(w.back->zed().tune_state(), 3);
  CHECK(w.back->zed().config_acked());
  size_t before = w.chest.gnss.size();
  w.run_ms(2000);
  CHECK(w.chest.gnss.size() > before + 10);     // positions keep flowing to the chest
}

TEST(precision, rtcm_keeps_reaching_the_zed_during_rate_change_and_tuning) {
  World w(2);
  w.run_ms(15000, 4);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  uint32_t nw = w.back->stats().rtcm_not_written, frames = w.zed.rtcm_frames;
  chest_cmd(w, BackCmd::SET_GNSS_RATE, 8, 601);
  w.run_ms(5000, 4);
  CHECK_EQ(w.back->stats().rtcm_not_written, nw);   // nothing held back while reconfiguring
  CHECK(w.zed.rtcm_frames > frames + 10);
}

// ---------------------------------------------------------------- V3.9.0 GNSS quality
TEST(quality, nav_sat_sig_enabled_at_1hz_and_summarised) {
  World w(2);
  w.run_ms(15000);
  CHECK_EQ((int)w.back->zed().monitor_state(), 1);
  CHECK_EQ(w.zed.sig_every[w.zed.port], (uint32_t)w.back->zed().nav_rate());   // once per second at any rate
  const GnssQuality& q = w.back->quality();
  CHECK(q.have_sat && q.have_sig);
  CHECK_EQ(q.sv_tracked, 20); CHECK_EQ(q.sv_used, 18);
  CHECK_EQ(q.sig_tracked, 40); CHECK_EQ(q.sig_l2, 20);
  CHECK_EQ(q.sig_used, 36); CHECK_EQ(q.sig_cr_used, 36); CHECK_EQ(q.sig_weak, 4);
  CHECK_EQ(q.cno_mean, 44); CHECK_EQ(q.cno_min, 44); CHECK_EQ(q.cno_max, 44);
  BackStatus st = w.back->status();
  uint8_t b[BACK_STATUS_V3_LEN + 8];
  size_t n = encode_status(st, b, sizeof(b));
  CHECK_EQ(n, BACK_STATUS_V3_LEN);
  BackStatus d;
  CHECK(decode_status(b, n, &d));
  CHECK(d.v2 && d.v3);
  CHECK_EQ(d.sig_l2, 20); CHECK_EQ(d.quality_mon, 1); CHECK(d.quality_age_s <= 2);
  CHECK(d.fixed_ms > 5000); CHECK_EQ(d.fix_lost, 0); CHECK(d.ttff_fix_s < 15);
  // a v2 decoder (old chest) still reads it, a v2 frame still decodes here
  BackStatus v2 = st; v2.v3 = false;
  n = encode_status(v2, b, sizeof(b));
  CHECK_EQ(n, BACK_STATUS_V2_LEN);
  CHECK(decode_status(b, n, &d)); CHECK(d.v2 && !d.v3);
}

TEST(quality, l1_only_antenna_shows_no_second_band) {
  World w(2);
  w.zed.l2_antenna = false;
  w.run_ms(15000);
  CHECK_EQ(w.back->quality().sig_l2, 0);
  CHECK_EQ(w.back->quality().sig_tracked, 20);
}

TEST(quality, fix_losses_and_float_time_are_counted) {
  World w(2);
  w.run_ms(10000);
  w.zed.carr = 1; w.run_ms(3000);
  w.zed.carr = 2; w.run_ms(3000);
  w.zed.carr = 0; w.run_ms(2000);
  CHECK_EQ(w.back->fix_lost(), 2);
  BackStatus st = w.back->status();
  CHECK(st.float_ms >= 2500 && st.float_ms <= 3500);
}

TEST(quality, signal_band_classification) {
  CHECK(gnss_sig_is_l1(0, 0)); CHECK(!gnss_sig_is_l1(0, 3)); CHECK(!gnss_sig_is_l1(0, 4));
  CHECK(gnss_sig_is_l1(2, 1)); CHECK(!gnss_sig_is_l1(2, 5));
  CHECK(gnss_sig_is_l1(3, 0)); CHECK(!gnss_sig_is_l1(3, 2));
  CHECK(gnss_sig_is_l1(6, 0)); CHECK(!gnss_sig_is_l1(6, 2));
  uint8_t bad[8] = {0, 0, 0, 0, 0, 5, 0, 0};   // claims 5 signals, carries none
  GnssQuality q;
  CHECK(!ubx_quality_nav_sig(bad, 8, &q));
  CHECK(!ubx_quality_nav_sat(bad, 8, &q));
}

// ---------------------------------------------------------------- V3.10.0 girth unit (GirthHub)
struct FakeGirthIo : GirthHub::Io {
  std::vector<std::vector<uint8_t>> sent, imu;
  std::vector<std::array<uint8_t, 6>> peers, stored;
  bool deliver = true;
  bool send(const uint8_t*, const uint8_t* d, size_t n) override { sent.emplace_back(d, d + n); return deliver; }
  void add_peer(const uint8_t m[6]) override { std::array<uint8_t, 6> a; memcpy(a.data(), m, 6); peers.push_back(a); }
  void store_girth(const uint8_t m[6]) override { std::array<uint8_t, 6> a; memcpy(a.data(), m, 6); stored.push_back(a); }
  void forward_imu(const uint8_t* d, size_t n) override { imu.emplace_back(d, d + n); }
};

static std::vector<uint8_t> girth_pkt(GirthKind k, uint32_t boot, uint32_t seq, const uint8_t* body, size_t bl) {
  GirthHeader h; h.kind = k; h.boot_id = boot; h.seq = seq;
  std::vector<uint8_t> p(GIRTH_MAX_PACKET);
  p.resize(girth_build(h, body, bl, p.data(), p.size()));
  return p;
}
static std::vector<uint8_t> girth_hello(uint32_t boot, uint32_t seq) {
  GirthHello m; strcpy(m.dev_id, "C6TEST"); strcpy(m.fw, "0.1.0"); m.hw = 1;
  uint8_t b[GIRTH_HELLO_LEN]; size_t n = girth_hello_encode(m, b, sizeof(b));
  return girth_pkt(GirthKind::HELLO, boot, seq, b, n);
}

TEST(girth, first_girth_pairs_automatically_and_is_stored) {
  FakeGirthIo io; GirthHub hub(&io, "BACK", "3.10.0", 77); hub.begin(nullptr);
  const uint8_t g1[6] = {1, 2, 3, 4, 5, 6};
  auto p = girth_hello(9, 1);
  CHECK(hub.on_radio(g1, p.data(), p.size(), -40, 1000, false));
  CHECK(hub.paired()); CHECK(hub.connected(1500));
  CHECK_EQ(io.stored.size(), 1u); CHECK(!io.sent.empty());
  GirthHeader h; const uint8_t* body;
  CHECK(girth_parse(io.sent.back().data(), io.sent.back().size(), &h, &body));
  CHECK(h.kind == GirthKind::WELCOME);
  CHECK(!hub.connected(5000));                                   // 3 s without packets -> not connected
  // chest-link packets are not consumed by the hub
  uint8_t other[20] = {0xA5, 0x4E};
  CHECK(!hub.on_radio(g1, other, sizeof(other), -40, 1000, false));
}

TEST(girth, second_girth_only_inside_pairing_window) {
  FakeGirthIo io; GirthHub hub(&io, "BACK", "3.10.0", 77);
  const uint8_t g1[6] = {1, 2, 3, 4, 5, 6}, g2[6] = {9, 9, 9, 9, 9, 9};
  hub.begin(g1);
  auto p = girth_hello(5, 1);
  hub.on_radio(g2, p.data(), p.size(), -40, 1000, false);
  CHECK(memcmp(hub.mac(), g1, 6) == 0); CHECK_EQ(hub.rejected(), 1u);
  hub.on_radio(g2, p.data(), p.size(), -40, 1100, true);
  CHECK(memcmp(hub.mac(), g2, 6) == 0);
}

TEST(girth, status_losses_imu_forwarding_and_ping) {
  FakeGirthIo io; GirthHub hub(&io, "BACK", "3.10.0", 77); hub.begin(nullptr);
  const uint8_t g[6] = {1, 2, 3, 4, 5, 6};
  auto hello = girth_hello(3, 1); hub.on_radio(g, hello.data(), hello.size(), -40, 0, false);
  GirthStatus st; st.uptime_ms = 1234; st.tx_ok = 10;
  uint8_t b[GIRTH_STATUS_LEN]; size_t bl = girth_status_encode(st, b, sizeof(b));
  CHECK_EQ(bl, GIRTH_STATUS_LEN);
  auto s2 = girth_pkt(GirthKind::STATUS, 3, 2, b, bl); hub.on_radio(g, s2.data(), s2.size(), -50, 100, false);
  auto s5 = girth_pkt(GirthKind::STATUS, 3, 5, b, bl); hub.on_radio(g, s5.data(), s5.size(), -50, 200, false);
  hub.on_radio(g, s5.data(), s5.size(), -50, 210, false);          // MAC-level duplicate: not a loss
  CHECK_EQ(hub.lost(), 2u); CHECK_EQ(hub.status().uptime_ms, 1234u); CHECK_EQ(hub.rssi(), -50);
  // IMU batch: forwarded with the back reception time
  ImuBatchHeader ih; ih.count = 2; ih.girth_seq = 44;
  std::vector<uint8_t> ib(IMU_HDR_LEN + 2 * IMU_SAMPLE_LEN_9AXIS, 7);
  encode_imu_header(ih, ib.data(), ib.size());
  auto im = girth_pkt(GirthKind::IMU, 3, 6, ib.data(), ib.size());
  hub.on_radio(g, im.data(), im.size(), -50, 300, false);
  CHECK_EQ(io.imu.size(), 1u);
  ImuBatchHeader out; CHECK(decode_imu_header(io.imu[0].data(), io.imu[0].size(), &out));
  CHECK_EQ(out.back_rx_ms, 300u); CHECK_EQ(out.girth_seq, 44u); CHECK_EQ(io.imu[0].size(), ib.size());
  // too many samples for one chest packet: rejected, not forwarded
  std::vector<uint8_t> big(IMU_HDR_LEN + 11 * IMU_SAMPLE_LEN_9AXIS, 0);
  auto bp = girth_pkt(GirthKind::IMU, 3, 7, big.data(), big.size());
  hub.on_radio(g, bp.data(), bp.size(), -50, 310, false);
  CHECK_EQ(io.imu.size(), 1u);
  // ping once per second while connected
  size_t before = io.sent.size();
  hub.tick(1500, true);
  CHECK_EQ(io.sent.size(), before + 1);
  GirthHeader h; const uint8_t* body; GirthPing gp;
  CHECK(girth_parse(io.sent.back().data(), io.sent.back().size(), &h, &body));
  CHECK(h.kind == GirthKind::PING && girth_ping_decode(body, h.body_len, &gp));
  CHECK_EQ(gp.flags, 1); CHECK_EQ(gp.lost, 2u);
  // corrupted packet
  auto bad = s5; bad[20] ^= 1;
  hub.on_radio(g, bad.data(), bad.size(), -50, 400, false);
  CHECK(hub.rejected() >= 2u);
}

TEST(quality, receiver_without_nav_sig_keeps_nav_sat) {
  World w(2);
  w.zed.no_sig_key = true;
  w.run_ms(20000);
  CHECK_EQ((int)w.back->zed().monitor_state(), 4);
  CHECK(w.back->quality().have_sat);
  CHECK(!w.back->quality().have_sig);
}

int main(int argc, char** argv) { return tt_run_all(argc > 1 ? argv[1] : nullptr); }
