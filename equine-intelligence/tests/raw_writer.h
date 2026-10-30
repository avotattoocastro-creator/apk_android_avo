// Writes a synthetic avoeq::Session to an AVO RAW v1 file with the chest's own writer (avo_core).
#pragma once
#include <algorithm>
#include <cmath>
#include <cstring>
#include <vector>
#include "avo_core.h"
#include "avo_eq/types.h"

namespace eqfix {
using namespace avoeq;
// Writes a Session to an AVO RAW v1 file with the chest's own writer (avo_core), so the whole chain
// RAW -> ingestion -> engine -> JSON is exercised exactly as on the phone.
inline bool write_raw(const char* path, const Session& s, bool close_clean = true) {
  static uint8_t blockbuf[avo::RAW_BLOCK_HDR + 8192];
  avo::RawWriter w; w.attach_buffer(blockbuf, 8192);
  avo::RawFileMeta meta; strcpy(meta.session_id, s.session_id.c_str()); strcpy(meta.horse_name, "PRUEBA"); meta.gnss_rate_hz = 8; meta.imu_rate_hz = 200;
  if (!w.open(path, meta, 1)) return false;
  // interleave GNSS epochs and IMU batches by chest reception time
  struct Rec { uint64_t t; bool gnss; size_t i; };
  std::vector<Rec> recs;
  for (size_t i = 0; i < s.gnss.size(); i++) recs.push_back({s.gnss[i].chest_us, true, i});
  for (size_t i = 0; i < s.imu.size(); i++) if (i + 1 == s.imu.size() || s.imu[i + 1].batch_seq != s.imu[i].batch_seq || s.imu[i + 1].imu_id != s.imu[i].imu_id) recs.push_back({s.imu[i].chest_us, false, i});
  std::stable_sort(recs.begin(), recs.end(), [](const Rec& a, const Rec& b) { return a.t < b.t; });
  uint16_t seq = 0;
  for (auto& r : recs) {
    uint8_t pl[1600], fr[1800]; size_t n; avo::FrameType ft;
    if (r.gnss) {
      const GnssEpoch& e = s.gnss[r.i];
      avo::GnssSample g; g.itow_ms = e.itow_ms; g.fix_type = e.fix_type; g.flags = e.flags; g.num_sv = e.num_sv;
      g.lat_e7 = (int32_t)std::llround(e.lat_deg * 1e7); g.lon_e7 = (int32_t)std::llround(e.lon_deg * 1e7);
      g.gspeed_mm_s = (int32_t)std::lround(e.gspeed_ms * 1000); g.sacc_mm_s = (uint32_t)std::lround(e.sacc_ms * 1000);
      g.veln_mm_s = (int32_t)std::lround(e.veln_ms * 1000); g.vele_mm_s = (int32_t)std::lround(e.vele_ms * 1000); g.hacc_mm = (uint32_t)std::lround(e.hacc_m * 1000);
      n = avo::encode_gnss(g, pl, sizeof(pl)); ft = avo::FrameType::GNSS_SAMPLE;
    } else {
      size_t last = r.i, first = r.i;
      while (first > 0 && s.imu[first - 1].batch_seq == s.imu[last].batch_seq && s.imu[first - 1].imu_id == s.imu[last].imu_id) first--;
      avo::ImuBatchHeader ih; ih.imu_id = s.imu[first].imu_id; ih.count = (uint16_t)(last - first + 1); ih.girth_seq = s.imu[first].batch_seq;
      ih.girth_t0_us = (uint64_t)s.imu[first].girth_us; ih.period_us = (uint32_t)(ih.count > 1 ? (s.imu[first + 1].girth_us - s.imu[first].girth_us) : 5000);
      avo::encode_imu_header(ih, pl, sizeof(pl));
      for (size_t k = first; k <= last; k++) {
        int16_t v[9] = {s.imu[k].ax, s.imu[k].ay, s.imu[k].az, s.imu[k].gx, s.imu[k].gy, s.imu[k].gz, 0, 0, 0};
        for (int a = 0; a < 9; a++) { pl[avo::IMU_HDR_LEN + (k - first) * 18 + 2 * a] = (uint8_t)v[a]; pl[avo::IMU_HDR_LEN + (k - first) * 18 + 2 * a + 1] = (uint8_t)(v[a] >> 8); }
      }
      n = avo::IMU_HDR_LEN + (last - first + 1) * 18; ft = avo::FrameType::IMU_SAMPLE;
    }
    size_t fn = avo::uart_encode(ft, 0, 1, seq++, 0, pl, n, fr, sizeof(fr));
    avo::RecHdr h; h.type = (uint8_t)avo::RecType::UART_FRAME; h.len = (uint16_t)fn; h.chest_us = r.t;
    if (!w.append(h, fr, 0, 0)) return false;
  }
  return close_clean ? w.close(true, 0, 0) : true;
}

}  // namespace eqfix
