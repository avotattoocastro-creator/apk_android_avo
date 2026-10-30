// AVO Windows — generator of DEMONSTRATION sessions (SYNTHETIC DATA, never a measured training).
// Writes AVO RAW v1 (.avr) files with the chest's own writer (avo_core), so the Windows reader, the engine and the UI are
// exercised with the exact on-disk format. Session ids start with "DEMO_" and every screen/report labels them as synthetic.
//
// Content: beach outing near Playa del Regatón (Laredo) — walk, trot, canter, gallop, cool down — with RTK FIX/FLOAT/
// autonomous periods, one 6 s GNSS outage, GNSS date/time, MSL height and (optionally) three girth IMUs at 104 Hz
// (imu_id 0 central, 1 left, 2 right) whose |a| oscillates at a stride frequency consistent with each phase.
//
// usage: make_demo_sessions OUTPUT_DIR
#include <cmath>
#include <cstdio>
#include <cstring>
#include <random>
#include <string>
#include <vector>
#include <algorithm>
#include "avo_core.h"

namespace {
const double PI = 3.14159265358979323846;
const double M_PER_DEG = 111320.0;

struct Phase { double secs, speed, stride_hz, a1, a2; };   // a1: one beat per stride (canter), a2: two beats (walk/trot)

struct Spec {
  const char* id; const char* horse; const char* rider;
  int year, month, day, hour, minute;                      // UTC start
  std::vector<Phase> phases;
  bool girth; unsigned seed; double heading_deg; double lat0, lon0;
};

struct Epoch { avo::GnssSample g; uint64_t chest_us; };
struct Imu { uint8_t id; uint64_t chest_us; uint32_t seq; uint32_t t0_us; std::vector<int16_t> v; };   // v: count*9

uint32_t itow_of(int y, int mo, int d, int h, int mi, double s) {
  // GPS time of week (ms) — day of week from Zeller-like computation (2026 dates only need consistency here).
  auto dow = [](int y_, int m_, int d_) { static int t[] = {0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4}; y_ -= m_ < 3; return (y_ + y_ / 4 - y_ / 100 + y_ / 400 + t[m_ - 1] + d_) % 7; };
  return (uint32_t)std::llround(((dow(y, mo, d) * 24.0 + h) * 3600 + mi * 60 + s + 18) * 1000);   // +18 s GPS-UTC
}

bool write(const std::string& dir, const Spec& sp) {
  std::mt19937 rng(sp.seed);
  std::normal_distribution<double> nz(0, 1);
  const double rate = 8, dt = 1 / rate;
  double total = 0; for (auto& p : sp.phases) total += p.secs;
  // ---------------------------------------------------------------- GNSS track
  std::vector<Epoch> gn;
  double x = 0, y = 0, hdg = sp.heading_deg * PI / 180, v = 0;
  double turn_start = total * 0.55, turn_len = 40;              // U-turn to come back along the beach
  int n = (int)(total * rate);
  for (int k = 0; k < n; k++) {
    double t = k * dt, acc = 0; const Phase* ph = &sp.phases.back();
    for (auto& p : sp.phases) { if (t < acc + p.secs) { ph = &p; break; } acc += p.secs; }
    double target = ph->speed;
    v += (target - v) * std::min(1.0, dt / 6.0);                // smooth transitions (~6 s)
    double w = (t >= turn_start && t < turn_start + turn_len) ? PI / turn_len : 0.004 * std::sin(t / 37.0);
    double vm = std::max(0.0, v + 0.04 * nz(rng));
    bool outage = t > total * 0.32 && t < total * 0.32 + 6;    // 6 s with no epochs
    int carr = 2;
    if (t > total * 0.12 && t < total * 0.12 + 40) carr = 1;    // RTK FLOAT for 40 s
    if (t > total * 0.70 && t < total * 0.70 + 15) carr = 0;    // autonomous / DGNSS for 15 s
    if (!outage) {
      Epoch e{};
      auto& g = e.g;
      double sec = sp.minute * 60.0 + t;
      int hh = sp.hour + (int)(sec / 3600), mm = (int)std::fmod(sec / 60, 60); double ss = std::fmod(sec, 60);
      g.itow_ms = itow_of(sp.year, sp.month, sp.day, sp.hour, sp.minute, t);
      g.year = (uint16_t)sp.year; g.month = (uint8_t)sp.month; g.day = (uint8_t)sp.day; g.hour = (uint8_t)hh; g.min = (uint8_t)mm;
      g.sec = (uint8_t)ss; g.nano = (int32_t)std::lround((ss - std::floor(ss)) * 1e9); g.valid = 0x07; g.tacc_ns = 20;
      g.fix_type = 3; g.num_sv = (uint8_t)(26 + (int)std::lround(3 * std::sin(t / 90.0)));
      g.flags = (uint8_t)(0x01 | (carr ? 0x02 : 0) | (carr << 6));
      double lat = sp.lat0 + y / M_PER_DEG, lon = sp.lon0 + x / (M_PER_DEG * std::cos(sp.lat0 * PI / 180));
      double hn = carr == 2 ? 0.012 : carr == 1 ? 0.25 : 0.9;
      lat += hn * 0.3 * nz(rng) / M_PER_DEG; lon += hn * 0.3 * nz(rng) / (M_PER_DEG * std::cos(sp.lat0 * PI / 180));
      g.lat_e7 = (int32_t)std::llround(lat * 1e7); g.lon_e7 = (int32_t)std::llround(lon * 1e7);
      g.hmsl_mm = (int32_t)std::llround((2.1 + 0.4 * std::sin(t / 300.0) + 0.02 * nz(rng)) * 1000);
      g.height_mm = g.hmsl_mm + 51800;                           // geoid separation ~51.8 m (Cantabria)
      g.hacc_mm = (uint32_t)std::llround(hn * 1000); g.vacc_mm = g.hacc_mm * 2;
      g.gspeed_mm_s = (int32_t)std::llround(vm * 1000); g.sacc_mm_s = carr == 2 ? 40 : 90;
      g.veln_mm_s = (int32_t)std::llround(vm * std::cos(hdg) * 1000); g.vele_mm_s = (int32_t)std::llround(vm * std::sin(hdg) * 1000);
      double hd = std::fmod(hdg * 180 / PI + 360, 360);
      g.head_mot_e5 = (int32_t)std::llround(hd * 1e5); g.pdop_e2 = 120; g.nav_rate_hz = 8;
      e.chest_us = (uint64_t)std::llround((t + 500.0) * 1e6 + 9000 + 2000 * std::abs(nz(rng)));
      gn.push_back(e);
    }
    x += v * std::sin(hdg) * dt; y += v * std::cos(hdg) * dt; hdg += w * dt;
  }
  // ---------------------------------------------------------------- girth IMUs
  std::vector<Imu> im;
  if (sp.girth) {
    const double fs = 1e6 / 9615.0; const int batch = 10;   // period 9615 us = 104 Hz
    for (uint8_t id = 0; id < 3; id++) {
      double phase = 0.3 * id, gain = id == 1 ? 1.06 : id == 2 ? 0.95 : 1.0;   // slight left/right difference (synthetic)
      uint32_t seq = 0; size_t ns = (size_t)(total * fs);
      for (size_t b0 = 0; b0 < ns; b0 += batch, seq++) {
        Imu b; b.id = id; b.seq = seq; b.t0_us = (uint32_t)((b0 / fs + 12.5) * 1e6);
        size_t b1 = std::min(ns, b0 + batch);
        for (size_t i = b0; i < b1; i++) {
          double t = i / fs, acc = 0; const Phase* ph = &sp.phases.back();
          for (auto& p : sp.phases) { if (t < acc + p.secs) { ph = &p; break; } acc += p.secs; }
          phase += 2 * PI * ph->stride_hz / fs;
          double a2 = ph->a2 * gain, a1 = ph->a1 * gain;
          double az = 4096 + a2 * std::sin(2 * phase) + a1 * std::sin(phase + 0.6) + 40 * nz(rng);   // 4096 LSB = 1 g nominal
          double ax = 0.18 * (a1 + a2) * std::sin(phase + 1.3) + 25 * nz(rng);
          double ay = (id == 1 ? 1 : id == 2 ? -1 : 0.2) * 0.12 * (a1 + a2) * std::sin(phase + 0.4) + 25 * nz(rng);
          double gx = 900 * std::sin(phase + 0.2) * (ph->speed > 0.3) + 30 * nz(rng), gy = 600 * std::sin(2 * phase) * (ph->speed > 0.3) + 30 * nz(rng);
          double gz = 300 * std::sin(phase) * (ph->speed > 0.3) + 20 * nz(rng);
          auto c = [](double q) { return (int16_t)std::lround(std::max(-32768.0, std::min(32767.0, q))); };
          int16_t vals[9] = {c(ax), c(ay), c(az), c(gx), c(gy), c(gz), 0, 0, 0};
          b.v.insert(b.v.end(), vals, vals + 9);
        }
        double t_last = (b1 - 1) / fs;
        b.chest_us = (uint64_t)std::llround((t_last + 500.0) * 1e6 + 6000 + 4000 * std::abs(nz(rng)));
        im.push_back(std::move(b));
      }
    }
  }
  // ---------------------------------------------------------------- RAW file
  static uint8_t blockbuf[avo::RAW_BLOCK_HDR + 8192];
  avo::RawWriter w; w.attach_buffer(blockbuf, 8192);
  avo::RawFileMeta meta;
  strncpy(meta.session_id, sp.id, sizeof(meta.session_id) - 1);
  strncpy(meta.horse_name, sp.horse, sizeof(meta.horse_name) - 1);
  strncpy(meta.rider_name, sp.rider, sizeof(meta.rider_name) - 1);
  strncpy(meta.chest_fw, "DEMO", sizeof(meta.chest_fw) - 1);
  // RTC: days since epoch for the UTC start
  auto days = [](int y, int m, int d) { y -= m <= 2; int era = y / 400; int yoe = y - era * 400; int doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1;
    int doe = yoe * 365 + yoe / 4 - yoe / 100 + doy; return (long long)era * 146097 + doe - 719468; };
  meta.created_rtc_ms = (uint64_t)((days(sp.year, sp.month, sp.day) * 86400LL + sp.hour * 3600LL + sp.minute * 60LL) * 1000LL);
  meta.gnss_rate_hz = 8; meta.imu_rate_hz = sp.girth ? 104 : 0;
  std::string path = dir + "/" + sp.id + ".avr";
  std::remove(path.c_str());   // the chest writer refuses to overwrite
  if (!w.open(path.c_str(), meta, 1)) return false;
  struct Rec { uint64_t t; int kind; size_t i; };
  std::vector<Rec> recs;
  for (size_t i = 0; i < gn.size(); i++) recs.push_back({gn[i].chest_us, 0, i});
  for (size_t i = 0; i < im.size(); i++) recs.push_back({im[i].chest_us, 1, i});
  // three markers (button) at the start of canter, gallop and cool down
  { double acc = 0; for (size_t p = 0; p + 1 < sp.phases.size(); p++) { acc += sp.phases[p].secs; if (p >= 1) recs.push_back({(uint64_t)((acc + 500.0) * 1e6), 2, p}); } }
  std::stable_sort(recs.begin(), recs.end(), [](const Rec& a, const Rec& b) { return a.t < b.t; });
  uint16_t seq = 0; uint32_t markers = 0;
  for (auto& r : recs) {
    uint8_t pl[1600], fr[1800]; size_t n2; avo::FrameType ft;
    if (r.kind == 2) {
      uint8_t mk[5] = {0, 0, 0, 0, 0}; markers++;
      mk[1] = (uint8_t)markers; mk[2] = (uint8_t)(markers >> 8);
      avo::RecHdr h; h.type = 0x05; h.len = 5; h.chest_us = r.t;
      if (!w.append(h, mk, 0, 0)) return false;
      continue;
    }
    if (r.kind == 0) { n2 = avo::encode_gnss(gn[r.i].g, pl, sizeof(pl)); ft = avo::FrameType::GNSS_SAMPLE; }
    else {
      const Imu& b = im[r.i];
      avo::ImuBatchHeader ih; ih.imu_id = b.id; ih.count = (uint8_t)(b.v.size() / 9); ih.girth_seq = b.seq; ih.girth_t0_us = b.t0_us; ih.period_us = 9615; ih.sync_state = 1;  // 104 Hz nominal (LSM6DS3TR-C)
      avo::encode_imu_header(ih, pl, sizeof(pl));
      for (size_t k = 0; k < b.v.size(); k++) { pl[avo::IMU_HDR_LEN + 2 * k] = (uint8_t)b.v[k]; pl[avo::IMU_HDR_LEN + 2 * k + 1] = (uint8_t)(b.v[k] >> 8); }
      n2 = avo::IMU_HDR_LEN + b.v.size() * 2; ft = avo::FrameType::IMU_SAMPLE;
    }
    size_t fn = avo::uart_encode(ft, 0, 1, seq++, 0, pl, n2, fr, sizeof(fr));
    avo::RecHdr h; h.type = (uint8_t)avo::RecType::UART_FRAME; h.len = (uint16_t)fn; h.chest_us = r.t;
    if (!w.append(h, fr, 0, 0)) return false;
  }
  if (!w.close(true, 0, 0)) return false;
  printf("%s: %zu épocas GNSS, %zu lotes IMU (DEMOSTRACIÓN — DATOS SINTÉTICOS)\n", path.c_str(), gn.size(), im.size());
  return true;
}
}  // namespace

int main(int argc, char** argv) {
  std::string out = argc > 1 ? argv[1] : ".";
  // phases: secs, speed m/s, stride Hz, a1 (one beat/stride), a2 (two beats/stride)
  std::vector<Phase> full = {{300, 1.6, 0.95, 250, 650}, {320, 3.6, 1.45, 300, 900}, {220, 6.2, 1.75, 1400, 380}, {110, 11.5, 2.15, 1900, 300}, {280, 1.5, 0.92, 240, 620}};
  std::vector<Phase> med = {{280, 1.5, 0.93, 240, 640}, {300, 3.4, 1.42, 290, 880}, {200, 5.8, 1.70, 1300, 360}, {90, 10.4, 2.05, 1800, 290}, {240, 1.5, 0.92, 240, 620}};
  std::vector<Phase> slow = {{320, 1.5, 0.94, 240, 640}, {360, 3.2, 1.40, 280, 860}, {240, 5.4, 1.66, 1250, 350}, {260, 1.4, 0.90, 230, 600}};
  std::vector<Spec> specs = {
    {"DEMO_REGATON_20261022", "Rayo (demo)", "Antonio (demo)", 2026, 10, 22, 6, 15, full, true, 11, 112, 43.4247, -3.4519},
    {"DEMO_REGATON_20261015", "Rayo (demo)", "Antonio (demo)", 2026, 10, 15, 7, 5, med, true, 12, 110, 43.4246, -3.4517},
    {"DEMO_REGATON_20261008", "Rayo (demo)", "Antonio (demo)", 2026, 10, 8, 6, 40, slow, true, 13, 111, 43.4245, -3.4520},
    {"DEMO_SIN_CINCHA_20261001", "Luna (demo)", "Marta (demo)", 2026, 10, 1, 8, 30, slow, false, 14, 108, 43.4249, -3.4515},
  };
  for (auto& s : specs) if (!write(out, s)) { fprintf(stderr, "no se pudo escribir %s\n", s.id); return 1; }
  return 0;
}
