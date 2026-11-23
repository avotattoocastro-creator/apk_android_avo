// AVO PPK 1.0.0 — see include/avo_eq/ppk.h.
#include "avo_eq/ppk.h"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <memory>
#include <sstream>
#include "avo_core.h"
#include "avo_ubx_frag.h"
#include "avo_eq/json.h"
#if defined(_WIN32)
#ifndef NOMINMAX
#define NOMINMAX   // rtklib.h includes <windows.h>: keep std::min/std::max
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#endif
#include "rtklib/rtklib.h"

namespace avoeq {

// ------------------------------------------------------------------ rover UBX from the .avr
namespace {
struct XCtx {
  std::vector<uint8_t>* ubx;
  PpkRoverStats* st;
  avo::UbxDefrag defrag;
};

void count_ubx(const uint8_t* f, size_t n, PpkRoverStats* st) {
  if (n < 8 || f[2] != 0x02) return;
  if (f[3] == 0x15) st->rawx++;
  else if (f[3] == 0x13) st->sfrbx++;
}

void x_frame(const avo::FrameView& f, void* vctx) {
  XCtx* c = (XCtx*)vctx;
  if (f.type == avo::GNSS_UBX_FRAG) {
    const uint8_t* fr;
    size_t fl;
    if (c->defrag.feed(f.payload, f.len, &fr, &fl)) {
      c->st->frag_frames++;
      count_ubx(fr, fl, c->st);
      c->ubx->insert(c->ubx->end(), fr, fr + fl);
    }
  } else if (f.type == avo::FrameType::GNSS_UBX) {   // BETA casco: whole verbatim UBX frames
    uint8_t cls, id;
    const uint8_t* pl;
    uint16_t plen;
    if (avo::ubx_check_frame(f.payload, f.len, &cls, &id, &pl, &plen) && cls == 0x02 && (id == 0x15 || id == 0x13)) {
      c->st->whole_frames++;
      count_ubx(f.payload, f.len, c->st);
      c->ubx->insert(c->ubx->end(), f.payload, f.payload + f.len);
    }
  }
}

struct RCtx {
  avo::UartDecoder* dec;
};
void x_record(const avo::RecHdr& h, const uint8_t* data, uint32_t, uint16_t, void* vctx) {
  if ((avo::RecType)h.type == avo::RecType::UART_FRAME) ((RCtx*)vctx)->dec->feed(data, h.len);
}
}  // namespace

bool ppk_extract_ubx(const std::vector<std::string>& segments, std::vector<uint8_t>* ubx, PpkRoverStats* st, std::string* error) {
  ubx->clear();
  *st = PpkRoverStats();
  std::unique_ptr<uint8_t[]> buf(new uint8_t[avo::RAW_BLOCK_HDR + avo::RAW_MAX_BLOCK_PAYLOAD]);
  XCtx c;
  c.ubx = ubx;
  c.st = st;
  for (const auto& path : segments) {
    avo::UartDecoder dec(x_frame, &c);
    RCtx rc{&dec};
    avo::RawScanResult r;
    bool ok = avo::raw_scan(path.c_str(), buf.get(), avo::RAW_BLOCK_HDR + avo::RAW_MAX_BLOCK_PAYLOAD, x_record, &rc, &r);
    if (!ok && !r.header_ok) { if (error) *error = "no es un fichero AVO RAW válido: " + path; return false; }
  }
  st->frag_incomplete = c.defrag.incomplete();
  st->frag_bad = c.defrag.bad();
  st->bytes = ubx->size();
  return true;
}

// ------------------------------------------------------------------ RTKLIB helpers
namespace {

std::string iso_utc(gtime_t t) {
  double ep[6];
  time2epoch(gpst2utc(t), ep);
  char b[40];
  std::snprintf(b, sizeof b, "%04d-%02d-%02dT%02d:%02d:%06.3fZ", (int)ep[0], (int)ep[1], (int)ep[2], (int)ep[3], (int)ep[4], ep[5]);
  return b;
}

int64_t unix_ms(gtime_t t) {
  gtime_t u = gpst2utc(t);
  return (int64_t)u.time * 1000 + (int64_t)std::llround(u.sec * 1000.0);
}

struct Nav {
  nav_t n{};
  Nav() {}
  ~Nav() { std::free(n.eph); std::free(n.geph); std::free(n.seph); std::free(n.alm); std::free(n.peph); std::free(n.pclk); std::free(n.tec); }
  Nav(const Nav&) = delete;
  Nav& operator=(const Nav&) = delete;
};
struct Obs {
  obs_t o{};
  ~Obs() { std::free(o.data); }
};

bool add_eph(nav_t* nav, const eph_t& e) {
  if (nav->nmax <= nav->n) {
    int nm = nav->nmax <= 0 ? 256 : nav->nmax * 2;
    eph_t* p = (eph_t*)std::realloc(nav->eph, sizeof(eph_t) * (size_t)nm);
    if (!p) return false;
    nav->eph = p;
    nav->nmax = nm;
  }
  nav->eph[nav->n++] = e;
  return true;
}
bool add_geph(nav_t* nav, const geph_t& e) {
  if (nav->ngmax <= nav->ng) {
    int nm = nav->ngmax <= 0 ? 64 : nav->ngmax * 2;
    geph_t* p = (geph_t*)std::realloc(nav->geph, sizeof(geph_t) * (size_t)nm);
    if (!p) return false;
    nav->geph = p;
    nav->ngmax = nm;
  }
  nav->geph[nav->ng++] = e;
  return true;
}
bool add_obs(obs_t* obs, const obsd_t& d) {
  if (obs->nmax <= obs->n) {
    int nm = obs->nmax <= 0 ? 4096 : obs->nmax * 2;
    obsd_t* p = (obsd_t*)std::realloc(obs->data, sizeof(obsd_t) * (size_t)nm);
    if (!p) return false;
    obs->data = p;
    obs->nmax = nm;
  }
  obs->data[obs->n++] = d;
  return true;
}

struct RawFree {
  void operator()(raw_t* r) const { if (r) { free_raw(r); delete r; } }
};

// Decodes the rover UBX stream into observations (rcv 1) and broadcast ephemerides.
bool decode_rover(const std::vector<uint8_t>& ubx, obs_t* obs, nav_t* nav, std::string* error) {
  std::unique_ptr<raw_t, RawFree> raw(new raw_t());
  if (!init_raw(raw.get(), STRFMT_UBX)) { if (error) *error = "sin memoria para el decodificador u-blox"; return false; }
  for (uint8_t b : ubx) {
    int ret = input_ubx(raw.get(), b);
    if (ret == 1) {
      for (int i = 0; i < raw->obs.n; i++) { obsd_t d = raw->obs.data[i]; d.rcv = 1; if (!add_obs(obs, d)) return false; }
    } else if (ret == 2) {
      int sat = raw->ephsat, set = raw->ephset;
      if (sat <= 0) continue;
      int prn;
      if (satsys(sat, &prn) == SYS_GLO) add_geph(nav, raw->nav.geph[prn - 1]);
      else add_eph(nav, raw->nav.eph[sat - 1 + MAXSAT * set]);
    } else if (ret == 9) {   // ionosphere / UTC parameters
      std::memcpy(nav->ion_gps, raw->nav.ion_gps, sizeof(nav->ion_gps));
      std::memcpy(nav->ion_gal, raw->nav.ion_gal, sizeof(nav->ion_gal));
      std::memcpy(nav->ion_cmp, raw->nav.ion_cmp, sizeof(nav->ion_cmp));
      std::memcpy(nav->utc_gps, raw->nav.utc_gps, sizeof(nav->utc_gps));
    }
  }
  for (int i = 0; i < NSATGLO; i++) nav->glo_fcn[i] = raw->nav.glo_fcn[i];
  return true;
}

bool read_text(const std::string& path, std::string* s) {
  std::ifstream f(path, std::ios::binary);
  if (!f) return false;
  std::ostringstream ss;
  ss << f.rdbuf();
  *s = ss.str();
  return true;
}

std::string base_name(const std::string& p) {
  size_t s = p.find_last_of("/\\");
  return s == std::string::npos ? p : p.substr(s + 1);
}

// Plain RINEX path for RTKLIB: Hatanaka files are expanded first (RTKLIB itself would need crx2rnx).
bool prepare_rinex(const std::string& path, const std::string& work_dir, std::string* out, std::string* error) {
  std::string head;
  {
    std::ifstream f(path, std::ios::binary);
    if (!f) { if (error) *error = "no se puede abrir " + path; return false; }
    char b[200] = {0};
    f.read(b, sizeof b - 1);
    head.assign(b, (size_t)f.gcount());
  }
  if (head.size() >= 2 && (uint8_t)head[0] == 0x1F && (uint8_t)head[1] == 0x8B) {
    if (error) *error = base_name(path) + " sigue comprimido con gzip: la app debe descomprimirlo antes";
    return false;
  }
  if (!is_crinex(head)) { *out = path; return true; }
  std::string crx, rnx, e;
  if (!read_text(path, &crx)) { if (error) *error = "no se puede leer " + path; return false; }
  if (!crx_to_rnx(crx, &rnx, &e)) { if (error) *error = base_name(path) + ": " + e; return false; }
  std::string dir = work_dir;
  if (dir.empty()) { size_t s = path.find_last_of("/\\"); dir = s == std::string::npos ? "." : path.substr(0, s); }
  *out = dir + "/" + base_name(path) + ".avo.rnx";
  std::ofstream f(*out, std::ios::binary);
  if (!f) { if (error) *error = "no se puede escribir " + *out; return false; }
  f << rnx;
  return (bool)f;
}

struct Sol {
  gtime_t t{};
  double rr[3] = {0, 0, 0};
  double v[3] = {0, 0, 0};   // variances xx yy zz
  int stat = 0, ns = 0;
  double ratio = 0, age = 0;
};

// One RTKLIB kinematic pass over the rover epochs (forward or backward).
void pass(const std::vector<std::pair<int, int>>& rov, const obs_t& ro, const obs_t& bo, const nav_t& nav, const prcopt_t& opt,
          bool backward, std::vector<Sol>* out, const volatile int* cancel) {
  out->assign(rov.size(), Sol());
  std::unique_ptr<rtk_t> rtk(new rtk_t());
  rtkinit(rtk.get(), &opt);
  std::vector<obsd_t> buf;
  int nr = (int)rov.size();
  for (int k = 0; k < nr; k++) {
    if (cancel && *cancel) break;
    int i = backward ? nr - 1 - k : k;
    const obsd_t* r = ro.data + rov[(size_t)i].first;
    int rn = rov[(size_t)i].second;
    gtime_t t = r[0].time;
    // nearest base epoch (base epochs are sorted and grouped by time)
    int best = -1;
    double bd = 1e9;
    if (bo.n > 0) {
      // binary search on time
      int lo = 0, hi = bo.n - 1;
      while (lo < hi) {
        int mid = (lo + hi) / 2;
        if (timediff(bo.data[mid].time, t) < 0) lo = mid + 1; else hi = mid;
      }
      for (int c : {lo - 1, lo}) {
        if (c < 0 || c >= bo.n) continue;
        // move to the first record of that epoch
        int s = c;
        while (s > 0 && timediff(bo.data[s - 1].time, bo.data[c].time) == 0.0) s--;
        double d = std::fabs(timediff(bo.data[s].time, t));
        if (d < bd) { bd = d; best = s; }
      }
    }
    buf.assign(r, r + rn);
    if (best >= 0 && bd <= opt.maxtdiff) {
      for (int j = best; j < bo.n && timediff(bo.data[j].time, bo.data[best].time) == 0.0; j++) buf.push_back(bo.data[j]);
    }
    rtkpos(rtk.get(), buf.data(), (int)buf.size(), &nav);
    Sol& s = (*out)[(size_t)i];
    s.t = t;
    s.stat = rtk->sol.stat;
    s.ns = rtk->sol.ns;
    s.ratio = rtk->sol.ratio;
    s.age = rtk->sol.age;
    for (int a = 0; a < 3; a++) { s.rr[a] = rtk->sol.rr[a]; s.v[a] = rtk->sol.qr[a]; }
  }
  rtkfree(rtk.get());
}

int rank(int stat) {   // smaller = better
  switch (stat) { case SOLQ_FIX: return 0; case SOLQ_FLOAT: return 1; case SOLQ_DGPS: return 2; case SOLQ_SINGLE: return 3; default: return 9; }
}

Sol combine(const Sol& f, const Sol& b) {
  if (rank(f.stat) != rank(b.stat)) return rank(f.stat) < rank(b.stat) ? f : b;
  if (f.stat == SOLQ_NONE) return f;
  Sol c = f;
  bool disagree = false;
  for (int a = 0; a < 3; a++) {
    double vf = f.v[a] > 0 ? f.v[a] : 1e-8, vb = b.v[a] > 0 ? b.v[a] : 1e-8;
    if (std::fabs(f.rr[a] - b.rr[a]) > 4.0 * std::sqrt(vf + vb)) disagree = true;
    c.rr[a] = (f.rr[a] / vf + b.rr[a] / vb) / (1.0 / vf + 1.0 / vb);
    c.v[a] = 1.0 / (1.0 / vf + 1.0 / vb);
  }
  if (disagree) {   // two fixes (or floats) that do not agree: keep the more reliable one, never present it as FIX
    c = f.ratio >= b.ratio ? f : b;
    if (c.stat == SOLQ_FIX) c.stat = SOLQ_FLOAT;
  }
  c.ns = std::max(f.ns, b.ns);
  c.ratio = std::max(f.ratio, b.ratio);
  return c;
}

}  // namespace

bool ppk_need(const std::vector<uint8_t>& ubx, PpkNeed* need) {
  *need = PpkNeed();
  Obs ro;
  Nav nav;
  std::string e;
  if (!decode_rover(ubx, &ro.o, &nav.n, &e) || ro.o.n == 0) return false;
  need->has_raw = true;
  need->start_utc = iso_utc(ro.o.data[0].time);
  need->end_utc = iso_utc(ro.o.data[ro.o.n - 1].time);
  uniqnav(&nav.n);
  // approximate position: first single-point solution
  prcopt_t opt = prcopt_default;
  opt.navsys = SYS_GPS | SYS_GAL | SYS_GLO | SYS_CMP | SYS_QZS;
  std::vector<double> azel;
  for (int i = 0; i < ro.o.n;) {
    int j = i;
    while (j < ro.o.n && timediff(ro.o.data[j].time, ro.o.data[i].time) == 0.0) j++;
    need->rawx++;
    if (need->lat_deg == 0 && need->lon_deg == 0 && j - i >= 5 && nav.n.n > 0) {
      sol_t sol{};
      azel.assign((size_t)(j - i) * 2, 0.0);
      char msg[128] = {0};
      if (pntpos(ro.o.data + i, j - i, &nav.n, &opt, &sol, azel.data(), nullptr, msg)) {
        double p[3];
        ecef2pos(sol.rr, p);
        need->lat_deg = p[0] * R2D;
        need->lon_deg = p[1] * R2D;
      }
    }
    i = j;
  }
  return true;
}

namespace {
bool solve_core(Obs& ro, Nav& nav, const std::vector<std::string>& base_files, const PpkOptions& o, PpkResult* r,
                std::string* error, const volatile int* cancel);
}

bool ppk_solve(const std::vector<uint8_t>& rover_ubx, const std::vector<std::string>& base_files, const PpkOptions& o,
               PpkResult* r, std::string* error, const volatile int* cancel) {
  PpkRoverStats keep = r->rover;
  *r = PpkResult();
  r->rover = keep;
  Obs ro;
  Nav nav;
  if (!decode_rover(rover_ubx, &ro.o, &nav.n, error)) return false;
  if (ro.o.n == 0) { if (error) *error = "la sesión no tiene observaciones RAWX (espalda < 3.16.0 o salida en bruto no activada)"; return false; }
  return solve_core(ro, nav, base_files, o, r, error, cancel);
}

bool ppk_solve_rinex_rover(const std::vector<std::string>& rover_files, const std::vector<std::string>& base_files,
                           const PpkOptions& o, PpkResult* r, std::string* error, const volatile int* cancel) {
  *r = PpkResult();
  Obs ro;
  Nav nav;
  for (const auto& f : rover_files) {
    std::string path;
    if (!prepare_rinex(f, o.work_dir, &path, error)) return false;
    sta_t s{};
    if (readrnxt(path.c_str(), 1, gtime_t{}, gtime_t{}, 0.0, "", &ro.o, &nav.n, &s) < 0) { if (error) *error = "RINEX no válido: " + base_name(f); return false; }
  }
  for (int i = 0; i < ro.o.n; i++) ro.o.data[i].rcv = 1;
  sortobs(&ro.o);
  if (ro.o.n == 0) { if (error) *error = "el RINEX del rover no tiene observaciones"; return false; }
  return solve_core(ro, nav, base_files, o, r, error, cancel);
}

namespace {
bool solve_core(Obs& ro, Nav& nav, const std::vector<std::string>& base_files, const PpkOptions& o, PpkResult* r,
                std::string* error, const volatile int* cancel) {
  auto fail = [&](const std::string& m) { if (error) *error = m; return false; };
  Obs bo;
  // base: observation files (rcv 2) and navigation files; the station is the first observation file with a position
  sta_t sta{};
  bool have_sta = false;
  for (const auto& f : base_files) {
    std::string path;
    if (!prepare_rinex(f, o.work_dir, &path, error)) return false;
    sta_t s{};
    int before = bo.o.n;
    if (readrnxt(path.c_str(), 2, gtime_t{}, gtime_t{}, 0.0, "", &bo.o, &nav.n, &s) < 0) return fail("RINEX no válido: " + base_name(f));
    if (bo.o.n > before && !have_sta) { sta = s; have_sta = true; r->base_name = s.name[0] ? s.name : base_name(f); }
  }
  if (bo.o.n == 0) return fail("faltan las observaciones de la estación base (RINEX de observación)");
  for (int i = 0; i < bo.o.n; i++) bo.o.data[i].rcv = 2;
  sortobs(&bo.o);
  uniqnav(&nav.n);
  r->nav_eph = (uint32_t)(nav.n.n + nav.n.ng);
  if (nav.n.n + nav.n.ng == 0) return fail("sin efemérides: ni SFRBX en la sesión ni RINEX de navegación");
  double rb[3];
  if (o.have_base_xyz) std::memcpy(rb, o.base_xyz, sizeof rb);
  else std::memcpy(rb, sta.pos, sizeof rb);
  if (std::sqrt(rb[0] * rb[0] + rb[1] * rb[1] + rb[2] * rb[2]) < 6.0e6) return fail("la base no tiene posición (APPROX POSITION XYZ) y no se ha indicado");
  ecef2pos(rb, r->base_llh);
  // rover epochs
  std::vector<std::pair<int, int>> rov;
  for (int i = 0; i < ro.o.n;) {
    int j = i;
    while (j < ro.o.n && timediff(ro.o.data[j].time, ro.o.data[i].time) == 0.0) j++;
    rov.push_back({i, j - i});
    i = j;
  }
  r->rover_epochs = (uint32_t)rov.size();
  {
    uint32_t be = 0;
    for (int i = 0; i < bo.o.n; i++) if (i == 0 || timediff(bo.o.data[i].time, bo.o.data[i - 1].time) != 0.0) be++;
    r->base_epochs = be;
  }
  if (timediff(bo.o.data[0].time, ro.o.data[ro.o.n - 1].time) > o.max_age_s ||
      timediff(ro.o.data[0].time, bo.o.data[bo.o.n - 1].time) > o.max_age_s)
    return fail("la base no cubre la hora de la sesión (" + iso_utc(ro.o.data[0].time) + " – " + iso_utc(ro.o.data[ro.o.n - 1].time) + ")");
  prcopt_t opt = prcopt_default;
  opt.mode = PMODE_KINEMA;
  opt.nf = o.freqs < 1 ? 1 : o.freqs > 3 ? 3 : o.freqs;
  opt.navsys = SYS_GPS | SYS_GAL | SYS_GLO | SYS_CMP | SYS_QZS;
  opt.elmin = o.elev_min_deg * D2R;
  opt.modear = o.fix_and_hold ? ARMODE_FIXHOLD : ARMODE_CONT;
  opt.glomodear = o.glonass_ar ? GLO_ARMODE_ON : GLO_ARMODE_OFF;
  opt.thresar[0] = o.ar_ratio;
  opt.maxtdiff = o.max_age_s;
  opt.ionoopt = IONOOPT_BRDC;
  opt.tropopt = TROPOPT_SAAS;
  opt.dynamics = 1;
  opt.refpos = POSOPT_POS_XYZ;
  for (int i = 0; i < 3; i++) opt.rb[i] = rb[i];
  if (have_sta && sta.deltype == 0) for (int i = 0; i < 3; i++) opt.antdel[1][i] = sta.del[i];
  std::vector<Sol> fw, bw;
  pass(rov, ro.o, bo.o, nav.n, opt, false, &fw, cancel);
  if (cancel && *cancel) return fail("cancelado");
  if (o.combine) {
    pass(rov, ro.o, bo.o, nav.n, opt, true, &bw, cancel);
    if (cancel && *cancel) return fail("cancelado");
  }
  r->epochs.reserve(rov.size());
  std::vector<std::array<double, 3>> enu_pos;
  for (size_t i = 0; i < rov.size(); i++) {
    Sol s = o.combine ? combine(fw[i], bw[i]) : fw[i];
    if (s.stat == SOLQ_NONE) continue;
    PpkEpoch e;
    e.tow_s = time2gpst(s.t, &e.week);
    e.utc_ms = unix_ms(s.t);
    double p[3];
    ecef2pos(s.rr, p);
    e.lat_deg = p[0] * R2D; e.lon_deg = p[1] * R2D; e.h_m = p[2];
    double P[9] = {s.v[0], 0, 0, 0, s.v[1], 0, 0, 0, s.v[2]}, Q[9];
    covenu(p, P, Q);
    e.sde = std::sqrt(std::max(0.0, Q[0])); e.sdn = std::sqrt(std::max(0.0, Q[4])); e.sdu = std::sqrt(std::max(0.0, Q[8]));
    e.q = s.stat; e.ns = s.ns; e.ratio = s.ratio; e.age_s = s.age;
    if (e.q == SOLQ_FIX) r->fix++; else if (e.q == SOLQ_FLOAT) r->flt++; else r->single++;
    r->epochs.push_back(e);
    double d[3] = {s.rr[0] - rb[0], s.rr[1] - rb[1], s.rr[2] - rb[2]}, en[3];
    ecef2enu(r->base_llh, d, en);
    enu_pos.push_back({en[0], en[1], en[2]});
  }
  // velocity by central differences between neighbours of the same quality (≤ 1.5 s apart)
  for (size_t i = 0; i < r->epochs.size(); i++) {
    size_t a = i > 0 ? i - 1 : i, b = i + 1 < r->epochs.size() ? i + 1 : i;
    if (a == b) continue;
    PpkEpoch& e = r->epochs[i];
    if (r->epochs[a].q != e.q || r->epochs[b].q != e.q) continue;
    double dt = (r->epochs[b].utc_ms - r->epochs[a].utc_ms) / 1000.0;
    if (dt <= 0 || dt > 3.0) continue;
    e.ve = (enu_pos[b][0] - enu_pos[a][0]) / dt; e.vn = (enu_pos[b][1] - enu_pos[a][1]) / dt; e.vu = (enu_pos[b][2] - enu_pos[a][2]) / dt;
  }
  if (!r->epochs.empty()) {
    double p0[3] = {r->epochs[0].lat_deg * D2R, r->epochs[0].lon_deg * D2R, r->epochs[0].h_m}, x0[3], d[3];
    pos2ecef(p0, x0);
    for (int i = 0; i < 3; i++) d[i] = x0[i] - rb[i];
    r->baseline_km = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]) / 1000.0;
    r->first_utc = iso_utc(fw.front().t);
    r->last_utc = iso_utc(fw.back().t);
  }
  if (r->baseline_km > 30) r->warnings.push_back("línea base de " + std::to_string((int)r->baseline_km) + " km: por encima de 20–30 km el FIX es poco fiable; usar una estación más cercana");
  if (!o.have_base_xyz) r->warnings.push_back("posición de la base tomada de la cabecera RINEX (APPROX POSITION XYZ): para coordenadas absolutas, indicar las oficiales ETRS89 de la reseña de la estación");
  r->warnings.push_back("sin calibración de antenas (ANTEX): la altura absoluta puede desviarse unos centímetros; velocidades, distancias y parciales no se ven afectados");
  if (r->rover.frag_incomplete) r->warnings.push_back(std::to_string(r->rover.frag_incomplete) + " mensajes RAWX/SFRBX perdidos por radio entre la espalda y el pecho");
  return true;
}
}  // namespace

std::string ppk_result_json(const PpkResult& r, bool with_epochs) {
  std::ostringstream o;
  o.setf(std::ios::fixed);
  auto num = [&](double v, int d) { std::ostringstream t; t.setf(std::ios::fixed); t.precision(d); t << v; return t.str(); };
  o << "{\"formato\":\"avo-ppk\",\"version\":\"1.0.0\",\"solver\":\"RTKLIB demo5 b34L (BSD-2)\"";
  o << ",\"rover\":{\"tramas_troceadas\":" << r.rover.frag_frames << ",\"mensajes_perdidos\":" << r.rover.frag_incomplete
    << ",\"trozos_malos\":" << r.rover.frag_bad << ",\"tramas_enteras\":" << r.rover.whole_frames << ",\"rawx\":" << r.rover.rawx
    << ",\"sfrbx\":" << r.rover.sfrbx << ",\"bytes\":" << r.rover.bytes << ",\"epocas\":" << r.rover_epochs << "}";
  o << ",\"base\":{\"nombre\":\"" << json::escape(r.base_name) << "\",\"epocas\":" << r.base_epochs
    << ",\"lat\":" << num(r.base_llh[0] * R2D, 8) << ",\"lon\":" << num(r.base_llh[1] * R2D, 8) << ",\"h\":" << num(r.base_llh[2], 3)
    << ",\"linea_base_km\":" << num(r.baseline_km, 2) << "}";
  size_t n = r.epochs.size();
  o << ",\"resultado\":{\"epocas\":" << n << ",\"fix\":" << r.fix << ",\"float\":" << r.flt << ",\"otras\":" << r.single
    << ",\"pct_fix\":" << num(n ? 100.0 * r.fix / n : 0, 1) << ",\"efemerides\":" << r.nav_eph
    << ",\"inicio_utc\":\"" << r.first_utc << "\",\"fin_utc\":\"" << r.last_utc << "\"}";
  o << ",\"avisos\":[";
  for (size_t i = 0; i < r.warnings.size(); i++) o << (i ? "," : "") << "\"" << json::escape(r.warnings[i]) << "\"";
  o << "]";
  if (with_epochs) {
    o << ",\"epocas\":[";
    for (size_t i = 0; i < n; i++) {
      const PpkEpoch& e = r.epochs[i];
      o << (i ? "," : "") << "{\"semana\":" << e.week << ",\"tow_s\":" << num(e.tow_s, 3) << ",\"utc_ms\":" << e.utc_ms
        << ",\"lat\":" << num(e.lat_deg, 9) << ",\"lon\":" << num(e.lon_deg, 9) << ",\"h\":" << num(e.h_m, 3)
        << ",\"q\":" << e.q << ",\"ns\":" << e.ns << ",\"sdn\":" << num(e.sdn, 4) << ",\"sde\":" << num(e.sde, 4) << ",\"sdu\":" << num(e.sdu, 4)
        << ",\"ratio\":" << num(e.ratio, 1) << ",\"edad_s\":" << num(e.age_s, 1)
        << ",\"vn\":" << num(e.vn, 3) << ",\"ve\":" << num(e.ve, 3) << ",\"vu\":" << num(e.vu, 3) << "}";
    }
    o << "]";
  }
  o << "}";
  return o.str();
}

}  // namespace avoeq
