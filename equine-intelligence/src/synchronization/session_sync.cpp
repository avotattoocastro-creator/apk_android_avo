// Session clock maps (moved from engine.cpp in 1.1.0 so the real-time analysis can reuse them with a cutoff).
#include "avo_eq/session_sync.h"
#include <cmath>
#include <cstdint>
#include <vector>

namespace avoeq {

// ------------------------------------------------------------------ synchronisation of the session
void build_session_maps(const Session& s, const ValidationReport& v, const SyncConfig& c, double cutoff,
                        ClockMap* chest_to_gnss, ClockMap girth_to_gnss[3]) {
  *chest_to_gnss = ClockMap();
  for (int i = 0; i < 3; i++) girth_to_gnss[i] = ClockMap();
  // chest reception (s) vs GNSS acquisition time (s): NAV-PVT reaches the chest with variable latency
  std::vector<double> gx, cy;
  std::vector<double> tg = gnss_time_s(s.gnss);
  for (size_t i = 0; i < s.gnss.size(); i++) {
    if (v.gnss_flags[i] & (GF_DUPLICATE | GF_TIME_BACKWARDS)) continue;
    if (cutoff >= 0 && s.gnss[i].chest_us * 1e-6 > cutoff) continue;
    gx.push_back(tg[i]); cy.push_back(s.gnss[i].chest_us * 1e-6);
  }
  ClockMap g2c = fit_clock(gx, cy, c);           // gnss -> chest
  // invert each piece: chest -> gnss
  for (auto p : g2c.pieces) {
    ClockPiece q;
    q.slope = 1.0 / p.slope; q.offset = -p.offset / p.slope;
    q.x0 = p.offset + p.slope * p.x0; q.x1 = p.offset + p.slope * p.x1;
    q.envelope_sd_s = p.envelope_sd_s; q.latency_median_s = p.latency_median_s; q.latency_p95_s = p.latency_p95_s;
    q.drift_ppm = (q.slope - 1) * 1e6; q.pairs = p.pairs; q.envelope_pairs = p.envelope_pairs;
    chest_to_gnss->pieces.push_back(q);
  }
  // girth acquisition (s) -> chest reception (s): one pair per batch (its last sample is the newest)
  for (int id = 0; id < 3; id++) {
    std::vector<double> x, y;
    uint32_t last_batch = UINT32_MAX;
    for (size_t i = 0; i < s.imu.size(); i++) {
      const ImuSample& m = s.imu[i];
      if (m.imu_id != id || (v.imu_flags[i] & IF_DUPLICATE)) continue;
      if (cutoff >= 0 && m.chest_us * 1e-6 > cutoff) continue;
      bool last_of_batch = (i + 1 >= s.imu.size()) || s.imu[i + 1].batch_seq != m.batch_seq || s.imu[i + 1].imu_id != m.imu_id;
      if (!last_of_batch || m.batch_seq == last_batch) continue;
      last_batch = m.batch_seq;
      x.push_back(m.girth_us * 1e-6); y.push_back(m.chest_us * 1e-6);
    }
    ClockMap g2ch = fit_clock(x, y, c);
    // compose girth -> chest -> gnss (piecewise, using the chest->gnss piece at the start of each girth piece)
    for (auto p : g2ch.pieces) {
      double ch0 = p.offset + p.slope * p.x0, gn0;
      double sd2 = 0;
      if (!chest_to_gnss->map(ch0, &gn0, &sd2)) continue;
      const ClockPiece* cg = nullptr;
      for (auto& q : chest_to_gnss->pieces) if (ch0 >= q.x0 - 1 && ch0 <= q.x1 + 1) cg = &q;
      if (!cg) continue;
      ClockPiece r = p;
      r.slope = cg->slope * p.slope; r.offset = cg->offset + cg->slope * p.offset;
      r.drift_ppm = (r.slope - 1) * 1e6;
      r.envelope_sd_s = std::sqrt(p.envelope_sd_s * p.envelope_sd_s + cg->envelope_sd_s * cg->envelope_sd_s);
      girth_to_gnss[id].pieces.push_back(r);
    }
  }
}

}  // namespace avoeq
