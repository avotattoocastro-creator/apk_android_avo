// AVO PPK 1.0.0: Hatanaka, RTKLIB driver, .avr extraction (GNSS_UBX_FRAG and whole GNSS_UBX) and C API.
#include <memory>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <sstream>
#include <string>
#include <vector>
#include "avo_core.h"
#include "avo_ubx_frag.h"
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/json.h"
#include "avo_eq/ppk.h"
#include "eq_test.h"
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX   // rtklib.h includes <windows.h>: keep std::min/std::max
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#endif
#include "../src/ppk/rtklib/rtklib.h"

namespace {

std::string data_dir() {
  std::string f = __FILE__;
  size_t s = f.find_last_of("/\\");
  return (s == std::string::npos ? std::string(".") : f.substr(0, s)) + "/data/ppk/";
}
std::string tmp_dir() {
  for (const char* k : {"TMPDIR", "TEMP", "TMP"}) {
    const char* t = std::getenv(k);
    if (t && *t) return t;
  }
  return "/tmp";
}
std::string slurp(const std::string& p) {
  std::ifstream f(p, std::ios::binary);
  std::ostringstream ss;
  ss << f.rdbuf();
  return ss.str();
}

// ENU offset (m) of llh (deg, deg, m) from an ECEF reference.
void enu_of(double lat, double lon, double h, const double ref[3], double enu[3]) {
  double p[3] = {lat * D2R, lon * D2R, h}, x[3], pr[3], d[3];
  pos2ecef(p, x);
  ecef2pos(ref, pr);
  for (int i = 0; i < 3; i++) d[i] = x[i] - ref[i];
  ecef2enu(pr, d, enu);
}

// ------------------------------------------------------------------ RXM-RAWX built from RINEX observations
void put_r8(uint8_t* p, double v) { std::memcpy(p, &v, 8); }
void put_r4(uint8_t* p, float v) { std::memcpy(p, &v, 4); }

// One RXM-RAWX frame (GPS only, L1 C/A sigId 0 and L2 sigId 3) per epoch, as the ZED-F9P sends it.
std::vector<std::vector<uint8_t>> rawx_from_obs(const obs_t& o) {
  std::vector<std::vector<uint8_t>> out;
  std::map<int, int> lock_ms;
  for (int i = 0; i < o.n;) {
    int j = i;
    while (j < o.n && timediff(o.data[j].time, o.data[i].time) == 0.0) j++;
    int week;
    double tow = time2gpst(o.data[i].time, &week);
    std::vector<uint8_t> pl(16);
    put_r8(&pl[0], tow);
    pl[8] = (uint8_t)week; pl[9] = (uint8_t)(week >> 8);
    pl[10] = 13;      // leap seconds (2005)
    pl[12] = 1;       // recStat: leapSec valid
    pl[13] = 1;       // version
    int nm = 0;
    for (int k = i; k < j; k++) {
      int prn;
      if (satsys(o.data[k].sat, &prn) != SYS_GPS) continue;
      for (int f = 0; f < 2; f++) {
        const obsd_t& d = o.data[k];
        if (d.P[f] == 0.0) continue;
        int key = d.sat * 4 + f;
        if (d.L[f] == 0.0 || (d.LLI[f] & 1)) lock_ms[key] = 0; else lock_ms[key] = std::min(64500, lock_ms[key] + 30000);
        uint8_t m[32] = {0};
        put_r8(m, d.P[f]);
        put_r8(m + 8, d.L[f]);
        put_r4(m + 16, d.D[f]);
        m[20] = 0; m[21] = (uint8_t)prn; m[22] = f == 0 ? 0 : 3;
        m[24] = (uint8_t)lock_ms[key]; m[25] = (uint8_t)(lock_ms[key] >> 8);
        m[26] = (uint8_t)(d.SNR[f] > 0 ? d.SNR[f] : 45);
        m[27] = 5; m[28] = 1; m[29] = 2;
        m[30] = (uint8_t)(0x01 | (d.L[f] != 0.0 ? 0x02 | 0x04 : 0));
        pl.insert(pl.end(), m, m + 32);
        nm++;
      }
    }
    pl[11] = (uint8_t)nm;
    std::vector<uint8_t> fr(pl.size() + 8);
    size_t n = avo::ubx_build(0x02, 0x15, pl.data(), (uint16_t)pl.size(), fr.data(), fr.size());
    fr.resize(n);
    out.push_back(fr);
    i = j;
  }
  return out;
}

// Writes the UBX frames into an .avr exactly as the chest does with the back 3.16.0 (GNSS_UBX_FRAG pieces) or as the
// BETA casco does (whole GNSS_UBX frames). drop_every: one piece in N is lost (radio), 0 = none.
bool write_avr(const std::string& path, const std::vector<std::vector<uint8_t>>& frames, bool fragments, int drop_every) {
  static uint8_t blockbuf[avo::RAW_BLOCK_HDR + 16384];
  avo::RawWriter w;
  w.attach_buffer(blockbuf, 16384);
  std::remove(path.c_str());   // the RAW writer never overwrites a file
  avo::RawFileMeta meta;
  std::strcpy(meta.session_id, "PPKTEST");
  if (!w.open(path.c_str(), meta, 1)) return false;
  uint16_t seq = 0, msg = 0;
  uint64_t t = 1000;
  int piece_no = 0;
  for (const auto& f : frames) {
    std::vector<std::vector<uint8_t>> payloads;
    avo::FrameType ft = fragments ? avo::GNSS_UBX_FRAG : avo::FrameType::GNSS_UBX;
    if (fragments) {
      size_t cnt = avo::ubx_frag_count(f.size());
      for (size_t i = 0; i < cnt; i++) {
        uint8_t p[avo::UBX_FRAG_HDR + avo::UBX_FRAG_CHUNK];
        size_t n = avo::ubx_frag_encode(f.data(), f.size(), msg, (uint8_t)i, p, sizeof p);
        payloads.emplace_back(p, p + n);
      }
      msg++;
    } else payloads.push_back(f);
    for (auto& pl : payloads) {
      piece_no++;
      if (drop_every && piece_no % drop_every == 0) continue;
      std::vector<uint8_t> fr(pl.size() + 32);
      size_t fn = avo::uart_encode(ft, 0, 1, seq++, 0, pl.data(), pl.size(), fr.data(), fr.size());
      avo::RecHdr h;
      h.type = (uint8_t)avo::RecType::UART_FRAME;
      h.len = (uint16_t)fn;
      h.chest_us = t += 1000;
      if (!w.append(h, fr.data(), 0, 0)) return false;
    }
  }
  return w.close(true, 0, 0);
}

struct Ref {
  double base_xyz[3] = {-3976219.5082, 3382372.5671, 3652512.9849};   // 0759, header APPROX POSITION XYZ
  double rover_xyz[3] = {-3978242.4348, 3382841.1715, 3649902.7667};  // 3040
};

}  // namespace

EQ_TEST(ppk, hatanaka_crinex3_sample) {
  std::string crx = slurp(data_dir() + "P43300USA_R_20190012056_17M_15S_MO.crx"), rnx, err;
  CHECK(avoeq::is_crinex(crx));
  CHECK(avoeq::crx_to_rnx(crx, &rnx, &err));
  std::istringstream in(rnx);
  std::string l, first;
  int epochs = 0, sat_lines = 0;
  bool hdr = true;
  std::map<std::string, double> d0;
  double worst = 0;
  std::vector<std::string> sats_first;
  while (std::getline(in, l)) {
    if (hdr) { if (l.find("END OF HEADER") != std::string::npos) hdr = false; continue; }
    if (l[0] == '>') { if (!epochs) first = l; epochs++; continue; }
    sat_lines++;
    if (epochs == 1) sats_first.push_back(l.substr(0, 3));
    if (l[0] == 'G' && l.size() >= 35) {   // C1C - λ1·L1C: only ionosphere and multipath change it (metres, not km)
      double C = std::atof(l.substr(3, 14).c_str()), L = std::atof(l.substr(19, 14).c_str());
      if (C > 0 && L > 0) {
        double d = C - L * CLIGHT / FREQL1;
        std::string id = l.substr(0, 3);
        if (!d0.count(id)) d0[id] = d; else worst = std::max(worst, std::fabs(d - d0[id]));
        CHECK(C > 1.9e7 && C < 2.7e7);
      }
    }
  }
  CHECK(epochs == 70);
  CHECK(first.compare(0, 35, "> 2019 01 01 20 56 45.0000000  0 27") == 0);
  CHECK(sats_first.size() == 27 && sats_first.front() == "C08" && sats_first.back() == "S38");
  CHECK(worst > 0 && worst < 10.0);
  REPORT("CRINEX: %d épocas, %d líneas de satélite, C1C−λL1C varía como máximo %.2f m\n", epochs, sat_lines, worst);
  // RTKLIB reads the expanded file
  std::string p = tmp_dir() + "/avo_ppk_p433.rnx";
  { std::ofstream f(p, std::ios::binary); f << rnx; }
  obs_t o{};
  std::unique_ptr<nav_t> nvp(new nav_t());   // ~520 KB: en el montón (pila de 1 MB en Windows)
  nav_t& nv = *nvp;
  sta_t st{};
  CHECK(readrnxt(p.c_str(), 1, gtime_t{}, gtime_t{}, 0.0, "", &o, &nv, &st) > 0);
  CHECK(o.n > 1500);
  std::free(o.data); std::free(nv.eph); std::free(nv.geph); std::free(nv.seph);
}

EQ_TEST(ppk, hatanaka_rejects_damaged_input) {
  std::string rnx, err;
  CHECK(!avoeq::crx_to_rnx("hola\n", &rnx, &err) && !err.empty());
  std::string crx = slurp(data_dir() + "P43300USA_R_20190012056_17M_15S_MO.crx");
  size_t eh = crx.find("END OF HEADER");
  size_t e1 = crx.find('\n', crx.find('>', eh));
  std::string cut = crx.substr(0, e1 + 1) + "\n" + "12345 67 89\n";   // a difference before any initialisation
  CHECK(!avoeq::crx_to_rnx(cut, &rnx, &err));
  CHECK(!avoeq::crx_to_rnx("1.0                 COMPACT RINEX FORMAT                    CRINEX VERS   / TYPE\n", &rnx, &err));
}

EQ_TEST(ppk, rtklib_kinematic_3km_baseline_fixes) {
  Ref ref;
  avoeq::PpkOptions o;
  o.work_dir = tmp_dir();
  avoeq::PpkResult r;
  std::string err;
  std::string d = data_dir();
  bool ok = avoeq::ppk_solve_rinex_rover({d + "30400920.05o"}, {d + "07590920.05o", d + "07590920.05n"}, o, &r, &err);
  CHECK(ok);
  if (!ok) { REPORT("error: %s\n", err.c_str()); return; }
  CHECK(r.rover_epochs == 120 && r.base_epochs == 120);
  CHECK_NEAR(r.baseline_km, 3.33, 0.1);
  double pct = r.epochs.empty() ? 0 : 100.0 * r.fix / r.epochs.size();
  CHECK(pct >= 90);
  // Static antenna processed as kinematic. The header coordinates (APPROX POSITION XYZ) are approximate, so the test
  // checks the scatter of the fixed epochs around their mean (what matters for speed, distance and stride) and only
  // a loose bound for the offset from the header.
  double m[3] = {0, 0, 0}, sum_v = 0;
  std::vector<std::array<double, 3>> pts;
  for (auto& e : r.epochs) {
    if (e.q != SOLQ_FIX) continue;
    double enu[3];
    enu_of(e.lat_deg, e.lon_deg, e.h_m, ref.rover_xyz, enu);
    pts.push_back({enu[0], enu[1], enu[2]});
    for (int i = 0; i < 3; i++) m[i] += enu[i];
    sum_v += std::hypot(e.vn, e.ve);
  }
  CHECK(!pts.empty());
  if (pts.empty()) return;
  for (int i = 0; i < 3; i++) m[i] /= pts.size();
  double worst_h = 0, worst_u = 0;
  for (auto& q : pts) { worst_h = std::max(worst_h, std::hypot(q[0] - m[0], q[1] - m[1])); worst_u = std::max(worst_u, std::fabs(q[2] - m[2])); }
  CHECK(worst_h < 0.06);                     // GPS L1/L2 of 2005, 30 s: every fixed epoch within 6 cm (horizontal) of the mean
  CHECK(worst_u < 0.12);
  CHECK(std::hypot(m[0], m[1]) < 0.30);      // and the mean near the published coordinates
  CHECK(sum_v / pts.size() < 0.005);         // speed of a static antenna: < 5 mm/s
  REPORT("PPK RINEX: %u épocas, FIX %.0f %%, dispersión horizontal máx. %.1f cm, vertical %.1f cm, media a %.1f cm de la cabecera\n",
         r.rover_epochs, pct, worst_h * 100, worst_u * 100, std::hypot(m[0], m[1]) * 100);
}

EQ_TEST(ppk, avr_fragments_whole_frames_and_c_api_give_the_same_solution) {
  Ref ref;
  std::string d = data_dir();
  obs_t o{};
  std::unique_ptr<nav_t> nvp(new nav_t());   // ~520 KB: en el montón (pila de 1 MB en Windows)
  nav_t& nv = *nvp;
  sta_t st{};
  CHECK(readrnxt((d + "30400920.05o").c_str(), 1, gtime_t{}, gtime_t{}, 0.0, "", &o, &nv, &st) > 0);
  sortobs(&o);
  auto frames = rawx_from_obs(o);
  std::free(o.data); std::free(nv.eph); std::free(nv.geph); std::free(nv.seph);
  CHECK(frames.size() == 120);
  std::string frag = tmp_dir() + "/avo_ppk_frag.avr", whole = tmp_dir() + "/avo_ppk_whole.avr", lossy = tmp_dir() + "/avo_ppk_lossy.avr";
  CHECK(write_avr(frag, frames, true, 0));
  CHECK(write_avr(whole, frames, false, 0));
  CHECK(write_avr(lossy, frames, true, 37));
  // extraction
  std::vector<uint8_t> u1, u2, u3;
  avoeq::PpkRoverStats s1, s2, s3;
  std::string err;
  CHECK(avoeq::ppk_extract_ubx({frag}, &u1, &s1, &err));
  CHECK(avoeq::ppk_extract_ubx({whole}, &u2, &s2, &err));
  CHECK(avoeq::ppk_extract_ubx({lossy}, &u3, &s3, &err));
  CHECK(u1 == u2);
  CHECK(s1.frag_frames == 120 && s1.rawx == 120 && s1.frag_incomplete == 0);
  CHECK(s2.whole_frames == 120 && s2.rawx == 120);
  CHECK(s3.frag_incomplete > 0 && s3.rawx + s3.frag_incomplete >= 119 && s3.rawx < 120);
  // solution from the .avr (RAWX without SFRBX: ephemerides from the navigation RINEX given with the base)
  avoeq::PpkOptions opt;
  opt.work_dir = tmp_dir();
  avoeq::PpkResult ra, rb;
  CHECK(avoeq::ppk_solve_rinex_rover({d + "30400920.05o"}, {d + "07590920.05o", d + "07590920.05n"}, opt, &ra, &err));
  ra.rover = s1;
  CHECK(avoeq::ppk_solve(u1, {d + "07590920.05o", d + "07590920.05n"}, opt, &rb, &err));
  if (!err.empty()) REPORT("error: %s\n", err.c_str());
  CHECK(rb.rover_epochs == 120);
  CHECK(rb.fix + 3 >= ra.fix);
  // same epochs, same answer as the RINEX rover (the RAWX path only changes how the observations arrive)
  double worst = 0;
  size_t same = 0;
  for (auto& e : rb.epochs) {
    for (auto& f : ra.epochs) {
      if (f.utc_ms != e.utc_ms || f.q != SOLQ_FIX || e.q != SOLQ_FIX) continue;
      double a[3], b[3];
      enu_of(e.lat_deg, e.lon_deg, e.h_m, ref.rover_xyz, a);
      enu_of(f.lat_deg, f.lon_deg, f.h_m, ref.rover_xyz, b);
      worst = std::max(worst, std::hypot(a[0] - b[0], a[1] - b[1]));
      same++;
    }
  }
  CHECK(rb.fix > 100 && same > 100 && worst < 0.01);
  REPORT("PPK desde .avr: FIX %u de %zu (RINEX: %u), diferencia máx. con el rover RINEX %.2f cm\n", rb.fix, rb.epochs.size(), ra.fix, worst * 100);
  // C API
  const char* segs[] = {frag.c_str()};
  std::string bo = d + "07590920.05o", bn = d + "07590920.05n";
  const char* base[] = {bo.c_str(), bn.c_str()};
  char* out = nullptr;
  CHECK(avo_eq_ppk_need(segs, 1, &out) == 0);
  avoeq::json::Value v;
  CHECK(avoeq::json::parse(out ? out : "", &v));
  CHECK(v["tiene_rawx"].boolean() && v["rawx"].num() == 120);
  CHECK(v["inicio_utc"].str().compare(0, 16, "2005-04-01T23:59") == 0);   // 00:00:00 GPST = 23:59:47 UTC
  avo_eq_free(out);
  std::string opts = "{\"dir_trabajo\":\"" + avoeq::json::escape(tmp_dir()) + "\",\"epocas\":false}";
  CHECK(avo_eq_ppk(segs, 1, base, 2, opts.c_str(), nullptr, &out) == 0);
  CHECK(avoeq::json::parse(out ? out : "", &v));
  CHECK(v["formato"].str() == "avo-ppk" && v["resultado"]["fix"].num() > 100 && v["epocas"].is_null());
  avo_eq_free(out);
  CHECK(avo_eq_ppk(segs, 1, base, 0, nullptr, nullptr, &out) == 2);
  avo_eq_free(out);
  CHECK(avo_eq_ppk(segs, 1, base, 2, "{\"frecuencias\":7}", nullptr, &out) == 5);
  avo_eq_free(out);
}

EQ_TEST(ppk, session_without_raw_and_base_outside_the_session) {
  std::string d = data_dir();
  std::string p = tmp_dir() + "/avo_ppk_empty.avr";
  CHECK(write_avr(p, {}, true, 0));
  const char* segs[] = {p.c_str()};
  char* out = nullptr;
  CHECK(avo_eq_ppk_need(segs, 1, &out) == 0);
  avoeq::json::Value v;
  CHECK(avoeq::json::parse(out ? out : "", &v) && !v["tiene_rawx"].boolean());
  avo_eq_free(out);
  std::string bo = d + "07590920.05o";
  const char* base[] = {bo.c_str()};
  CHECK(avo_eq_ppk(segs, 1, base, 1, nullptr, nullptr, &out) == 1);
  avo_eq_free(out);
  // base of another hour: clean error, not a wrong solution
  obs_t o{};
  std::unique_ptr<nav_t> nvp(new nav_t());   // ~520 KB: en el montón (pila de 1 MB en Windows)
  nav_t& nv = *nvp;
  sta_t st{};
  readrnxt((d + "30400920.05o").c_str(), 1, gtime_t{}, gtime_t{}, 0.0, "", &o, &nv, &st);
  for (int i = 0; i < o.n; i++) o.data[i].time = timeadd(o.data[i].time, 7200.0);
  auto frames = rawx_from_obs(o);
  std::free(o.data); std::free(nv.eph); std::free(nv.geph); std::free(nv.seph);
  std::vector<uint8_t> ubx;
  for (auto& f : frames) ubx.insert(ubx.end(), f.begin(), f.end());
  avoeq::PpkOptions opt;
  avoeq::PpkResult r;
  std::string err;
  CHECK(!avoeq::ppk_solve(ubx, {bo, d + "07590920.05n"}, opt, &r, &err));
  CHECK(err.find("no cubre") != std::string::npos);
}
