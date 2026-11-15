// Host tests for AVO GIRTH 0.5.0 (no hardware): ECG (MAX30003 word decode, units, clock, fmt 2 batch),: SH-2 parsing, sample assembly, batch packing and the
// round trip through the back's real GirthHub (lib/avo_core of the back, the same code the Heltec runs).
// These are simulations: they prove the byte formats and the logic, not the BNO085 or the radio.
#include <cstdio>
#include <cstring>
#include <vector>
#include "../AVO_GIRTH_V0_5_0/girth_sh2.h"
#include "../AVO_GIRTH_V0_5_0/girth_ecg.h"
#include <cmath>
#include "avo_girth_link.h"
#include "avo_payloads.h"

using namespace girth;

static int fails = 0, checks = 0;
#define CHECK(c, msg) do { checks++; if (!(c)) { fails++; printf("FAIL: %s (line %d)\n", msg, __LINE__); } } while (0)

static void p16(std::vector<uint8_t>& v, int v16) { v.push_back((uint8_t)(v16 & 0xFF)); v.push_back((uint8_t)((v16 >> 8) & 0xFF)); }
static void p32(std::vector<uint8_t>& v, uint32_t x) { for (int i = 0; i < 4; i++) v.push_back((uint8_t)(x >> (8 * i))); }
static void rep3(std::vector<uint8_t>& v, uint8_t id, uint8_t seq, uint8_t status, uint8_t delay, int x, int y, int z) {
  v.push_back(id); v.push_back(seq); v.push_back(status); v.push_back(delay); p16(v, x); p16(v, y); p16(v, z);
}

static std::vector<Sample> got;
static void sink(const Sample& s, void*) { got.push_back(s); }

static void test_assembler() {
  Assembler a;
  a.set_sink(sink, nullptr);
  got.clear();
  // packet: base timestamp 2 (=200 µs), accel FIRST, then gyro, mag, linear acc and game RV of the same instant
  std::vector<uint8_t> pk;
  pk.push_back(R_BASE_TIMESTAMP); p32(pk, 2);
  rep3(pk, R_ACCEL, 10, 0x03, 1, 256, -512, 2511);        // 1, -2, 9.81 m/s² (Q8); accuracy 3; delay 100 µs
  rep3(pk, R_GYRO, 10, 0x02, 0, 512, 0, -256);           // 1, 0, -0.5 rad/s (Q9)
  rep3(pk, R_MAG, 10, 0x01, 0, 16, 32, -48);              // 1, 2, -3 µT (Q4)
  rep3(pk, R_LINACC, 10, 0x03, 0, 128, 0, 0);            // 0.5 m/s²
  pk.push_back(R_GAME_RV); pk.push_back(10); pk.push_back(0x03); pk.push_back(0);
  p16(pk, 0); p16(pk, 0); p16(pk, 0); p16(pk, 16384);    // identity quaternion
  a.on_packet(CH_REPORTS, pk.data(), pk.size(), 1000000);
  CHECK(got.size() == 1, "one sample per accelerometer report");
  if (got.size() == 1) {
    const Sample& s = got[0];
    CHECK(s.acc[0] == 256 && s.acc[1] == -512 && s.acc[2] == 2511, "acc values");
    CHECK(s.gyro[0] == 512 && s.gyro[2] == -256, "gyro of the same packet is included (emitted after parsing)");
    CHECK(s.mag[1] == 32, "mag");
    CHECK(s.lin[0] == 128, "linear acceleration");
    CHECK(s.quat[3] == 16384, "quaternion real part");
    CHECK(s.t_us == 1000000 - 200 - 100, "timestamp = INT - base - delay");
    CHECK(s.acc_status == 3 && s.gyro_status == 2 && s.mag_status == 1, "accuracy bits");
    CHECK(s.have == 15, "all values present");
  }
  CHECK(a.reports == 5, "5 reports parsed");

  // sequence gap: 10 -> 13 means 2 accelerometer reports lost
  pk.clear();
  rep3(pk, R_ACCEL, 13, 0x03, 0, 0, 0, 2511);
  a.on_packet(CH_REPORTS, pk.data(), pk.size(), 1030000);
  CHECK(a.lost == 2, "sequence gap counted as lost samples");
  CHECK(got.size() == 2, "second sample");

  // two accelerometer reports in one packet (batched by the sensor)
  pk.clear();
  rep3(pk, R_ACCEL, 14, 0x03, 100, 1, 1, 1);
  rep3(pk, R_ACCEL, 15, 0x03, 0, 2, 2, 2);
  a.on_packet(CH_REPORTS, pk.data(), pk.size(), 2000000);
  CHECK(got.size() == 4, "two samples from one packet");
  CHECK(got.size() == 4 && got[2].t_us < got[3].t_us, "older report first");

  // unknown report id: parsing stops, no crash, counted
  pk.clear();
  pk.push_back(0x77); pk.push_back(0); pk.push_back(0);
  a.on_packet(CH_REPORTS, pk.data(), pk.size(), 2010000);
  CHECK(a.unknown == 1, "unknown report counted");
  // truncated report
  pk.clear();
  rep3(pk, R_ACCEL, 16, 0, 0, 0, 0, 0);
  pk.resize(7);
  a.on_packet(CH_REPORTS, pk.data(), pk.size(), 2020000);
  CHECK(got.size() == 4 && a.unknown == 2, "truncated report ignored");

  // reset complete (channel 1)
  uint8_t rc = 1;
  a.on_packet(CH_EXECUTABLE, &rc, 1, 0);
  CHECK(a.reset_flag && a.resets_seen == 1, "reset complete detected");

  // product id response (two records: only the first is kept)
  std::vector<uint8_t> pid;
  for (int r = 0; r < 2; r++) {
    pid.push_back(R_PRODUCT_ID_RESP); pid.push_back(1); pid.push_back(3); pid.push_back(2);
    p32(pid, 10003608u + r); p32(pid, 324); p16(pid, 7); p16(pid, 0);
  }
  a.on_packet(CH_CONTROL, pid.data(), pid.size(), 0);
  CHECK(a.product.valid && a.product.sw_major == 3 && a.product.sw_minor == 2 && a.product.part == 10003608u &&
        a.product.build == 324 && a.product.patch == 7, "product id");

  // get feature response: confirmed interval
  std::vector<uint8_t> gf;
  gf.push_back(R_GET_FEATURE_RESP); gf.push_back(R_GAME_RV); gf.push_back(0); p16(gf, 0); p32(gf, 10000); p32(gf, 0); p32(gf, 0);
  a.on_packet(CH_CONTROL, gf.data(), gf.size(), 0);
  CHECK(a.feature_interval_us[R_GAME_RV] == 10000 && a.feature_responses == 1, "feature interval confirmed");
}

static void test_commands() {
  uint8_t b[32];
  CHECK(build_set_feature(R_ACCEL, 10000, b, sizeof b) == 17, "set feature length");
  CHECK(b[0] == 0xFD && b[1] == R_ACCEL && b[5] == 0x10 && b[6] == 0x27 && b[7] == 0 && b[8] == 0, "set feature interval LE");
  CHECK(build_product_id_request(b, sizeof b) == 2 && b[0] == 0xF9 && b[1] == 0, "product id request");
  CHECK(report_len(R_ACCEL) == 10 && report_len(R_GAME_RV) == 12 && report_len(R_ROTVEC) == 14 && report_len(R_BASE_TIMESTAMP) == 5,
        "report lengths");
}

// ---------------------------------------------------------------- GirthHub round trip
struct FakeIo : avo::GirthHub::Io {
  std::vector<std::vector<uint8_t>> sent, fwd;
  int peers = 0, stored = 0;
  bool send(const uint8_t*, const uint8_t* d, size_t n) override { sent.emplace_back(d, d + n); return true; }
  void add_peer(const uint8_t*) override { peers++; }
  void store_girth(const uint8_t*) override { stored++; }
  void forward_imu(const uint8_t* p, size_t n) override { fwd.emplace_back(p, p + n); }
};

static size_t pkt(avo::GirthKind k, uint32_t seq, const uint8_t* body, size_t bl, uint8_t* out) {
  avo::GirthHeader h; h.kind = k; h.boot_id = 0x1234; h.seq = seq;
  return avo::girth_build(h, body, bl, out, avo::GIRTH_MAX_PACKET);
}

static void test_hub() {
  FakeIo io;
  avo::GirthHub hub(&io, "BACKID", "3.11.0", 99);
  hub.begin(nullptr);
  const uint8_t gm[6] = {0x58, 0x8C, 0x81, 1, 2, 3};
  uint8_t out[avo::GIRTH_MAX_PACKET];

  avo::GirthHello h;
  strcpy(h.dev_id, "588C81010203"); strcpy(h.fw, "0.4.0"); h.hw = 1; h.imu_count = 1;
  uint8_t hb[avo::GIRTH_HELLO_LEN];
  size_t hl = avo::girth_hello_encode(h, hb, sizeof hb);
  size_t n = pkt(avo::GirthKind::HELLO, 1, hb, hl, out);
  CHECK(hub.on_radio(gm, out, n, -60, 1000, false), "hello accepted");
  CHECK(hub.paired() && io.stored == 1 && io.sent.size() == 1, "first girth paired and welcomed");
  CHECK(hub.hello().imu_count == 1 && !strcmp(hub.hello().fw, "0.4.0"), "hello content");

  // 10 samples -> fmt 0 and fmt 1 batches
  Sample s[BATCH_MAX];
  for (int i = 0; i < BATCH_MAX; i++) {
    s[i].t_us = 5000000 + i * 10000;
    s[i].acc[2] = 2511; s[i].gyro[0] = (int16_t)i; s[i].mag[1] = -5; s[i].lin[0] = (int16_t)(100 + i); s[i].quat[3] = 16384;
  }
  BatchMeta m; m.batch = 7;
  uint8_t body0[avo::GIRTH_MAX_BODY], body1[avo::GIRTH_MAX_BODY];
  size_t b0 = encode_batch(FMT_9AXIS, m, s, BATCH_MAX, body0, sizeof body0);
  size_t b1 = encode_batch(FMT_FUSED, m, s, BATCH_MAX, body1, sizeof body1);
  CHECK(b0 == 24 + 10 * 18 && b0 <= avo::IMU_HDR_LEN + avo::GIRTH_IMU_MAX_SAMPLES * avo::IMU_SAMPLE_LEN_9AXIS, "fmt 0 batch fits the back");
  CHECK(b1 == 24 + 10 * 14, "fmt 1 batch size");
  CHECK(encode_batch(FMT_9AXIS, m, s, 11, body0, sizeof body0) == 0, "more than 10 samples refused");

  n = pkt(avo::GirthKind::IMU, 2, body0, b0, out);
  hub.on_radio(gm, out, n, -61, 1010, false);
  n = pkt(avo::GirthKind::IMU, 3, body1, b1, out);
  hub.on_radio(gm, out, n, -61, 1012, false);
  CHECK(io.fwd.size() == 2, "both batches forwarded to the chest");
  if (io.fwd.size() == 2) {
    avo::ImuBatchHeader ih;
    CHECK(avo::decode_imu_header(io.fwd[0].data(), io.fwd[0].size(), &ih) && ih.fmt == 0 && ih.count == 10 && ih.girth_seq == 7 &&
          ih.girth_t0_us == 5000000 && ih.period_us == 10000 && ih.back_rx_ms == 1010 && ih.reserved == UNITS_BNO085_Q, "fmt 0 header after the back (units byte kept by the back)");
    CHECK(io.fwd[0].size() == b0 && !memcmp(io.fwd[0].data() + 24, body0 + 24, b0 - 24), "fmt 0 samples untouched");
    const uint8_t* p = io.fwd[0].data() + 24 + 9 * 18;   // last sample: gyro x = 9 at offset 6
    CHECK(p[4] == (2511 & 0xFF) && p[6] == 9, "fmt 0 sample layout ax ay az gx ...");
    CHECK(avo::decode_imu_header(io.fwd[1].data(), io.fwd[1].size(), &ih) && ih.fmt == 1 && ih.girth_seq == 7, "fmt 1 forwarded, same batch");
    const uint8_t* q = io.fwd[1].data() + 24;
    CHECK(q[0] == 100 && q[12] == 0x00 && q[13] == 0x40, "fmt 1 layout lx .. qr (Q14 1.0 = 0x4000)");
  }
  // a lost packet (seq 4 missing) is counted by the back and reported back in PING
  n = pkt(avo::GirthKind::IMU, 5, body0, b0, out);
  hub.on_radio(gm, out, n, -61, 1100, false);
  CHECK(hub.lost() == 1, "back detects the missing packet");
  size_t before = io.sent.size();
  hub.tick(2200, true);
  CHECK(io.sent.size() == before + 1, "back sends PING while the girth is connected");
  if (io.sent.size() == before + 1) {
    avo::GirthHeader ph; const uint8_t* body;
    CHECK(avo::girth_parse(io.sent.back().data(), io.sent.back().size(), &ph, &body) && ph.kind == avo::GirthKind::PING, "ping parses");
    avo::GirthPing g;
    CHECK(avo::girth_ping_decode(body, ph.body_len, &g) && g.rx_packets == 4 && g.lost == 1 && g.flags == 1,
          "ping confirms packets received and lost (application-level confirmation)");
  }
  // another girth is rejected outside the pairing window
  const uint8_t other[6] = {9, 9, 9, 9, 9, 9};
  n = pkt(avo::GirthKind::HELLO, 1, hb, hl, out);
  before = io.sent.size();
  hub.on_radio(other, out, n, -50, 3000, false);
  CHECK(io.sent.size() == before && hub.rejected() >= 1, "second girth ignored (no WELCOME) unless pairing is open");
}

static void test_ecg() {
  using namespace girth::max30003;
  // FIFO word: data bits 23..6 (18-bit signed), ETAG bits 5..3
  EcgWord w = decode_fifo_word((0x1FFFFu << 6) | (VALID << 3));
  CHECK(w.counts == 131071 && w.etag == VALID, "fifo word max positive");
  w = decode_fifo_word((0x20000u << 6) | (OVERFLOW << 3));
  CHECK(w.counts == -131072 && w.etag == OVERFLOW, "fifo word min negative + overflow tag");
  w = decode_fifo_word((0x3FFFFu << 6) | (EMPTY << 3));
  CHECK(w.counts == -1 && w.etag == EMPTY, "fifo word -1 / empty");
  // units: 1 mV at gain 40 -> counts = 1e-3 * 131072 * 40 / 1.0 = 5242.88; back to 0,1 µV ≈ 10000
  CHECK(std::abs(counts_to_duv(5243, 1) - 10000) <= 1, "counts -> 0,1 uV (gain 40, 1 mV)");
  CHECK(counts_to_duv(-5243, 1) == -counts_to_duv(5243, 1), "conversion symmetric");
  CHECK(std::abs(counts_to_duv(131071, 0) - 499996) <= 1, "full scale at gain 20 = ±50 mV (VREF 1 V / 2^17 / 20)");
  CHECK(counts_to_duv(-131072, 0) != ECG_INVALID, "full scale never collides with the invalid marker");
  // register values
  CHECK(cnfg_gen() == 0x081117, "CNFG_GEN value");
  CHECK(cnfg_ecg(1) == 0x015000, "CNFG_ECG 512 sps gain 40 HPF 0.5 LPF 40");
  CHECK(mngr_int(24) == (23u << 19), "MNGR_INT EFIT 24");
  CHECK(en_int() == 0xD00003, "EN_INT");
  CHECK(cmd(INFO, true) == 0x1F && cmd(CNFG_GEN, false) == 0x20, "SPI command byte");

  // clock: bursts of 24 samples at a true period of 1953.0 µs (crystal a bit off), read with ±300 µs jitter
  EcgClock c; c.reset(1953.125);
  double true_per = 1953.0, t = 1000000.0; uint32_t first = 0; int bursts = 0; double worst = 0;
  uint64_t k0 = 0;
  for (int b = 0; b < 2000; b++) {
    double t_last = t + (k0 + 23) * true_per + ((b * 7919) % 601 - 300);
    uint32_t f = c.burst((uint32_t)(uint64_t)t_last, 24);
    double truth = t + k0 * true_per;
    double err = (double)(int32_t)(f - (uint32_t)(uint64_t)truth);
    if (b > 500 && std::fabs(err) > worst) worst = std::fabs(err);
    if (b == 0) first = f;
    k0 += 24; bursts++;
  }
  (void)first;
  CHECK(std::fabs(c.period_us() - true_per) < 0.5, "clock learns the crystal period");
  CHECK(worst < 400, "time stamps within 0.4 ms after convergence despite read jitter");
  CHECK(c.samples() == 2000ull * 24, "sample count");
  // 32-bit wrap of micros() keeps going
  EcgClock w2; w2.reset(1953.125);
  uint32_t a = w2.burst(0xFFFFF000u, 24), b2 = w2.burst(0xFFFFF000u + (uint32_t)(24 * 1953.125), 24);
  CHECK((uint32_t)(b2 - a) > 46000 && (uint32_t)(b2 - a) < 48000, "clock across the 32-bit wrap");

  // fmt 2 batch through the back's real GirthHub (unchanged back firmware)
  int32_t duv[ECG_BATCH_MAX];
  for (int i = 0; i < ECG_BATCH_MAX; i++) duv[i] = (int32_t)(10000 * std::sin(i * 0.3)) ;
  duv[5] = ECG_INVALID; duv[6] = -1234567;
  EcgMeta m; m.batch = 42; m.t0_us = 7000000; m.period_us = 1953;
  uint8_t body[avo::GIRTH_MAX_BODY];
  size_t n60 = encode_ecg_batch(m, duv, ECG_BATCH_MAX, body, sizeof body);
  CHECK(n60 == 204 && n60 <= avo::IMU_HDR_LEN + avo::GIRTH_IMU_MAX_SAMPLES * avo::IMU_SAMPLE_LEN_9AXIS, "60-sample ECG batch = back limit (204 B)");
  CHECK(encode_ecg_batch(m, duv, ECG_BATCH_MAX + 1, body, sizeof body) == 0, "more than 60 samples refused");
  size_t n = encode_ecg_batch(m, duv, 51, body, sizeof body);
  CHECK(n == 24 + 51 * 3, "51-sample batch (100 ms at 512 sps) = 177 B");

  FakeIo io;
  avo::GirthHub hub(&io, "BACKID", "3.14.3", 99);
  hub.begin(nullptr);
  const uint8_t gm[6] = {0x58, 0x8C, 0x81, 1, 2, 3};
  uint8_t out[avo::GIRTH_MAX_PACKET];
  avo::GirthHello h;
  strcpy(h.dev_id, "588C81010203"); strcpy(h.fw, "0.5.0"); h.hw = 2; h.imu_count = 1;
  uint8_t hb[avo::GIRTH_HELLO_LEN];
  size_t hl = avo::girth_hello_encode(h, hb, sizeof hb);
  size_t pn = pkt(avo::GirthKind::HELLO, 1, hb, hl, out);
  hub.on_radio(gm, out, pn, -60, 1000, false);
  pn = pkt(avo::GirthKind::IMU, 2, body, n, out);
  hub.on_radio(gm, out, pn, -60, 1500, false);
  pn = pkt(avo::GirthKind::IMU, 3, body, n60, out);
  hub.on_radio(gm, out, pn, -60, 1600, false);
  CHECK(io.fwd.size() == 2, "both ECG batches forwarded by the back");
  if (io.fwd.size() == 2) {
    avo::ImuBatchHeader ih;
    CHECK(avo::decode_imu_header(io.fwd[0].data(), io.fwd[0].size(), &ih) && ih.fmt == FMT_ECG && ih.imu_id == ECG_CHANNEL_ID &&
          ih.count == 51 && ih.girth_seq == 42 && ih.girth_t0_us == 7000000 && ih.period_us == 1953 && ih.reserved == UNITS_ECG_DUV &&
          ih.back_rx_ms == 1500, "fmt 2 header after the back (units kept, back_rx_ms set)");
    CHECK(io.fwd[0].size() == n && !memcmp(io.fwd[0].data() + 24, body + 24, n - 24), "ECG samples untouched by the back");
    const uint8_t* p = io.fwd[0].data() + 24 + 5 * 3;
    CHECK(p[0] == 0x00 && p[1] == 0x00 && p[2] == 0x80, "invalid marker 0x800000");
    p += 3;
    int32_t v = (int32_t)(p[0] | (p[1] << 8) | (p[2] << 16)); if (v & 0x800000) v -= 0x1000000;
    CHECK(v == -1234567, "int24 little endian sign");
    CHECK(io.fwd[1].size() == 204, "60-sample ECG batch forwarded");
  }
}

int main() {
  test_commands();
  test_assembler();
  test_hub();
  test_ecg();
  printf("%s: %d/%d checks (host simulation, not hardware)\n", fails ? "FAILED" : "OK", checks - fails, checks);
  return fails ? 1 : 0;
}
