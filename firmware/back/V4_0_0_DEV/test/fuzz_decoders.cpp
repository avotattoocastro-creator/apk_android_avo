// Fuzz targets for every decoder that sees bytes from outside (radio, ZED UART).
// Build with libFuzzer:   clang++ -fsanitize=fuzzer,address,undefined ... fuzz_decoders.cpp
// Build standalone:       g++ -DAVO_FUZZ_STANDALONE -fsanitize=address,undefined ... (mutation loop, fixed seed)
#include "avo_core.h"
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include <vector>

using namespace avo;

namespace {
uint32_t g_frames = 0;
void on_frame(const FrameView& f, void*) {
  g_frames++;
  // payload decoders get whatever the frame carries
  GnssSample g; decode_gnss(f.payload, f.len, &g);
  BackStatus s; decode_status(f.payload, f.len, &s);
  Caps c; decode_caps(f.payload, f.len, &c);
  Command cm; decode_command(f.payload, f.len, &cm);
  Ack a; decode_ack(f.payload, f.len, &a);
  Heartbeat h; decode_heartbeat(f.payload, f.len, &h);
  ImuBatchHeader ih; decode_imu_header(f.payload, f.len, &ih);
  TimeSync ts; decode_timesync(f.payload, f.len, &ts);
  EventMsg e; decode_event(f.payload, f.len, &e);
  if (f.raw_len < f.len) __builtin_trap();
}
void on_ubx(const uint8_t*, size_t n, void*) { if (n < 8) __builtin_trap(); }

struct NullPlatform : public BackPlatform {
  uint32_t t = 0;
  uint32_t now_ms() override { return t; }
  void zed_set_baud(uint32_t) override {}
  void zed_write(const uint8_t*, size_t) override {}
  bool radio_start(const uint8_t*, const uint8_t*, size_t n) override { if (n > NOW_MAX_PACKET) __builtin_trap(); return true; }
  void radio_set_peer(const uint8_t*) override {}
  void save_peer(const NowPeerRecord&) override {}
  uint32_t random32() override { return 0x12345679; }
  void reboot() override {}
};
}  // namespace

extern "C" int LLVMFuzzerTestOneInput(const uint8_t* d, size_t n) {
  // 1. UART stream decoder, fed in irregular chunks
  {
    UartDecoder dec(on_frame, nullptr);
    size_t i = 0, step = 1;
    while (i < n) { size_t k = (step % 37) + 1; if (i + k > n) k = n - i; dec.feed(d + i, k); i += k; step = step * 7 + 3; }
  }
  // 2. ESP-NOW packet + pairing body
  {
    NowHeader h; const uint8_t* body = nullptr;
    if (now_parse(d, n, &h, &body)) {
      if (body < d || body + h.body_len > d + n) __builtin_trap();
      NowPairMsg m; now_pair_decode(body, h.body_len, &m);
      UartDecoder dec(on_frame, nullptr); dec.feed(body, h.body_len);
    }
    NowPeerRecord r; now_peer_deserialize(d, n, &r);
  }
  // 3. UBX / NMEA stream
  {
    UbxStream s(on_ubx, nullptr);
    s.feed(d, n);
    RxmRtcm rr; ubx_decode_rxm_rtcm(d, n, &rr);
    GnssSample g; ubx_decode_nav_pvt(d, n, &g);
  }
  // 4. Whole back core: bytes as radio packets (with a valid-looking header) and as ZED output
  {
    NullPlatform p;
    BackCore core(&p, "FUZZ", 8);
    NowPeerRecord peer; peer.valid = true; memset(peer.mac, 0xAB, 6); peer.pair_id = 77;
    core.begin(peer);
    uint8_t pkt[NOW_MAX_PACKET];
    NowHeader h; h.kind = NowKind::DATA; h.pair_id = 77; h.boot_id = 5;
    size_t off = 0;
    while (off < n) {
      size_t k = n - off; if (k > NOW_MAX_BODY) k = NOW_MAX_BODY;
      size_t pl = now_build(h, d + off, k, pkt, sizeof(pkt));
      core.on_radio(peer.mac, pkt, pl, -50);
      core.on_radio(peer.mac, d + off, k, -50);   // raw garbage as a packet too
      core.on_zed(d + off, k);
      p.t += 7; core.on_sent((k & 1) != 0); core.tick();
      off += k;
    }
  }
  return 0;
}

#ifdef AVO_FUZZ_STANDALONE
#include <random>
#include <stdio.h>
#include <stdlib.h>
// Seeds: valid frames of every type, then random mutations (bit flips, truncation, splicing, length edits).
static std::vector<std::vector<uint8_t>> seeds() {
  std::vector<std::vector<uint8_t>> s;
  uint8_t f[1100], pl[300];
  GnssSample g; g.lat_e7 = 433800000; g.num_sv = 20; size_t n = encode_gnss(g, pl, sizeof(pl));
  s.push_back(std::vector<uint8_t>(f, f + uart_encode(FrameType::GNSS_SAMPLE, 0, 1, 3, 100, pl, n, f, sizeof(f))));
  Command c; c.cmd = (uint16_t)BackCmd::SET_GNSS_RATE; c.cmd_id = 9; c.arg_len = 1; c.args[0] = 10;
  n = encode_command(c, pl, sizeof(pl));
  s.push_back(std::vector<uint8_t>(f, f + uart_encode(FrameType::COMMAND, 0, 2, 4, 100, pl, n, f, sizeof(f))));
  uint8_t r[220]; put_u32(r, 1000); for (int i = 4; i < 220; i++) r[i] = (uint8_t)i;
  s.push_back(std::vector<uint8_t>(f, f + uart_encode(FrameType::RTCM_DATA, 0, 2, 5, 100, r, sizeof(r), f, sizeof(f))));
  uint8_t ub[100]; uint8_t pvt[92] = {0};
  s.push_back(std::vector<uint8_t>(ub, ub + ubx_build(UBX_CLS_NAV, UBX_ID_NAV_PVT, pvt, 92, ub, sizeof(ub))));
  NowHeader h; h.kind = NowKind::PAIR_REQ; h.pair_id = 3; NowPairMsg m; uint8_t b[64], pk[NOW_MAX_PACKET];
  size_t bl = now_pair_encode(m, b, sizeof(b));
  s.push_back(std::vector<uint8_t>(pk, pk + now_build(h, b, bl, pk, sizeof(pk))));
  return s;
}

int main(int argc, char** argv) {
  long iters = argc > 1 ? atol(argv[1]) : 200000;
  std::mt19937 rng(20261023);
  auto pool = seeds();
  for (long it = 0; it < iters; it++) {
    std::vector<uint8_t> x = pool[rng() % pool.size()];
    if (rng() % 3 == 0) { auto& y = pool[rng() % pool.size()]; x.insert(x.end(), y.begin(), y.end()); }
    int muts = 1 + rng() % 8;
    for (int k = 0; k < muts && !x.empty(); k++) {
      switch (rng() % 6) {
        case 0: x[rng() % x.size()] ^= (uint8_t)(1u << (rng() % 8)); break;
        case 1: x[rng() % x.size()] = (uint8_t)rng(); break;
        case 2: x.resize(rng() % (x.size() + 1)); break;
        case 3: x.insert(x.begin() + rng() % (x.size() + 1), (uint8_t)rng()); break;
        case 4: if (x.size() > 10) { size_t p = 8 + rng() % 2; x[p] = (uint8_t)rng(); } break;   // length fields
        case 5: { size_t l = rng() % 64; for (size_t j = 0; j < l; j++) x.push_back((uint8_t)rng()); } break;
      }
    }
    LLVMFuzzerTestOneInput(x.data(), x.size());
    if (rng() % 50 == 0) pool.push_back(x);
    if (pool.size() > 400) pool.erase(pool.begin() + 5);
  }
  printf("fuzz: %ld entradas sin fallos (%u tramas UART decodificadas)\n", iters, g_frames);
  return 0;
}
#endif
