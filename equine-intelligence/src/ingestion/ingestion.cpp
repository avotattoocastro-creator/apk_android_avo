// Reads AVO RAW v1 session segments with the SAME C++ code the chest uses to write them (avo_core),
// so there is a single definition of the format. Original values are copied unchanged.
#include "avo_eq/ingestion.h"
#include "avo_core.h"
#include <cstring>
#include <memory>

namespace avoeq {

namespace {
struct Ctx {
  Session* s;
  avo::UartDecoder* dec = nullptr;
  uint64_t cur_chest_us = 0;
  uint32_t cur_block = 0;
};

void on_frame(const avo::FrameView& f, void* vctx) {
  Ctx* c = (Ctx*)vctx;
  Session& s = *c->s;
  if (f.type == avo::FrameType::GNSS_SAMPLE) {
    avo::GnssSample g;
    if (!avo::decode_gnss(f.payload, f.len, &g)) { s.bad_records++; return; }
    GnssEpoch e;
    e.block_seq = c->cur_block; e.chest_us = c->cur_chest_us;
    e.itow_ms = g.itow_ms; e.year = g.year; e.month = g.month; e.day = g.day; e.hour = g.hour; e.minute = g.min; e.second = g.sec;
    e.nano = g.nano; e.valid = g.valid; e.fix_type = g.fix_type; e.flags = g.flags; e.flags3 = g.flags3; e.num_sv = g.num_sv;
    e.lat_deg = g.lat_e7 * 1e-7; e.lon_deg = g.lon_e7 * 1e-7;
    e.height_m = g.height_mm * 1e-3; e.hmsl_m = g.hmsl_mm * 1e-3;
    e.hacc_m = g.hacc_mm * 1e-3; e.vacc_m = g.vacc_mm * 1e-3;
    e.veln_ms = g.veln_mm_s * 1e-3; e.vele_ms = g.vele_mm_s * 1e-3; e.veld_ms = g.veld_mm_s * 1e-3;
    e.gspeed_ms = g.gspeed_mm_s * 1e-3; e.sacc_ms = g.sacc_mm_s * 1e-3;
    e.head_mot_deg = g.head_mot_e5 * 1e-5; e.head_acc_deg = g.head_acc_e5 * 1e-5;
    e.pdop = g.pdop_e2 * 1e-2; e.nav_rate_hz = g.nav_rate_hz;
    s.gnss.push_back(e);
  } else if (f.type == avo::FrameType::IMU_SAMPLE) {
    avo::ImuBatchHeader h;
    if (!avo::decode_imu_header(f.payload, f.len, &h) || h.fmt != avo::IMU_FMT_9AXIS_I16) { s.bad_records++; return; }
    size_t need = avo::IMU_HDR_LEN + (size_t)h.count * avo::IMU_SAMPLE_LEN_9AXIS;
    if (need > f.len) { s.bad_records++; return; }
    const uint8_t* p = f.payload + avo::IMU_HDR_LEN;
    for (uint16_t i = 0; i < h.count; i++, p += avo::IMU_SAMPLE_LEN_9AXIS) {
      ImuSample x;
      x.imu_id = h.imu_id; x.batch_seq = h.girth_seq; x.index = i;
      x.girth_us = (int64_t)h.girth_t0_us + (int64_t)i * h.period_us;   // acquisition time on the girth clock
      x.chest_us = c->cur_chest_us;
      int16_t v[9];
      for (int k = 0; k < 9; k++) v[k] = (int16_t)(p[2 * k] | (p[2 * k + 1] << 8));
      x.ax = v[0]; x.ay = v[1]; x.az = v[2]; x.gx = v[3]; x.gy = v[4]; x.gz = v[5]; x.mx = v[6]; x.my = v[7]; x.mz = v[8];
      x.sync_state = h.sync_state; x.girth_to_back_us = h.girth_to_back_us;
      s.imu.push_back(x);
    }
  } else {
    s.unknown_frames++;
  }
}

void on_record(const avo::RecHdr& h, const uint8_t* data, uint32_t block_seq, uint16_t, void* vctx) {
  Ctx* c = (Ctx*)vctx;
  c->s->records++;
  c->cur_chest_us = h.chest_us;
  c->cur_block = block_seq;
  switch ((avo::RecType)h.type) {
    case avo::RecType::UART_FRAME: c->dec->feed(data, h.len); break;
    case avo::RecType::MARKER: { MarkerEvent m; m.chest_us = h.chest_us; m.text.assign((const char*)data, strnlen((const char*)data, h.len)); c->s->markers.push_back(m); break; }
    default: break;
  }
}
}  // namespace

bool ingest_raw(const std::vector<std::string>& segments, Session* out, std::string* error) {
  *out = Session();
  std::unique_ptr<uint8_t[]> buf(new uint8_t[avo::RAW_BLOCK_HDR + avo::RAW_MAX_BLOCK_PAYLOAD]);
  Ctx c; c.s = out;
  for (const auto& path : segments) {
    avo::UartDecoder dec(on_frame, &c);   // one decoder per segment (sequence numbers restart)
    c.dec = &dec;
    avo::RawScanResult r;
    bool ok = avo::raw_scan(path.c_str(), buf.get(), avo::RAW_BLOCK_HDR + avo::RAW_MAX_BLOCK_PAYLOAD, on_record, &c, &r);
    if (!ok && !r.header_ok) { if (error) *error = "no es un fichero AVO RAW válido: " + path; return false; }
    out->segments++;
    out->bad_records += r.bad_records + dec.stats().crc_err + dec.stats().hdr_crc_err;
    out->clean_close = r.clean_close;
    out->tail_garbage = out->tail_garbage || r.tail_garbage;
    if (out->segments == 1) {
      out->session_id = r.meta.session_id; out->horse = r.meta.horse_name; out->rider = r.meta.rider_name;
      out->chest_fw = r.meta.chest_fw; out->back_fw = r.meta.back_fw;
      out->imu_rate_hz_cfg = r.meta.imu_rate_hz; out->gnss_rate_hz_cfg = r.meta.gnss_rate_hz;
    }
  }
  return true;
}

}  // namespace avoeq
