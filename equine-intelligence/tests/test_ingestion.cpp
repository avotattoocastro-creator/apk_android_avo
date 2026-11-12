#include "eq_test.h"
#include "avo_core.h"
#include "avo_eq/engine.h"
#include "avo_eq/ingestion.h"
#include <cstdio>
#include <cstring>

using namespace avoeq;

// Writes a real AVO RAW v1 file with avo_core (the chest's own writer) and reads it back.
EQ_TEST(ingestion, raw_written_by_avo_core_is_read_back_unchanged) {
  const char* path = "eq_test_session.avo";
  remove(path);
  static uint8_t blockbuf[avo::RAW_BLOCK_HDR + 8192];
  avo::RawWriter w; w.attach_buffer(blockbuf, 8192);
  avo::RawFileMeta meta;
  strcpy(meta.session_id, "S_TEST_001"); strcpy(meta.horse_name, "PRUEBA"); meta.gnss_rate_hz = 8; meta.imu_rate_hz = 200;
  CHECK(w.open(path, meta, 1));
  uint16_t seq = 0;
  for (int i = 0; i < 80; i++) {
    avo::GnssSample g; g.itow_ms = 1000 + i * 125; g.fix_type = 3; g.flags = 0x01 | 0x02 | (2 << 6); g.num_sv = 20;
    g.lat_e7 = 434000000 + i * 10; g.lon_e7 = -34300000; g.gspeed_mm_s = 2500; g.hacc_mm = 14; g.sacc_mm_s = 80; g.veln_mm_s = 2500;
    uint8_t pl[128], fr[256];
    size_t n = avo::encode_gnss(g, pl, sizeof(pl));
    size_t fn = avo::uart_encode(avo::FrameType::GNSS_SAMPLE, 0, 1, seq++, 0, pl, n, fr, sizeof(fr));
    avo::RecHdr h; h.type = (uint8_t)avo::RecType::UART_FRAME; h.len = (uint16_t)fn; h.chest_us = 5000000ull + i * 125000ull + 7000;
    CHECK(w.append(h, fr, 0, 0));
  }
  // one IMU batch of 10 samples
  {
    avo::ImuBatchHeader ih; ih.imu_id = 1; ih.count = 10; ih.girth_seq = 77; ih.girth_t0_us = 123456; ih.period_us = 5000;
    uint8_t pl[avo::IMU_HDR_LEN + 10 * 18], fr[512];
    avo::encode_imu_header(ih, pl, sizeof(pl));
    for (int k = 0; k < 10; k++) for (int a = 0; a < 9; a++) { int16_t v = (int16_t)(k * 10 + a); pl[avo::IMU_HDR_LEN + k * 18 + 2 * a] = (uint8_t)v; pl[avo::IMU_HDR_LEN + k * 18 + 2 * a + 1] = (uint8_t)(v >> 8); }
    size_t fn = avo::uart_encode(avo::FrameType::IMU_SAMPLE, 0, 1, seq++, 0, pl, sizeof(pl), fr, sizeof(fr));
    avo::RecHdr h; h.type = (uint8_t)avo::RecType::UART_FRAME; h.len = (uint16_t)fn; h.chest_us = 6000000;
    CHECK(w.append(h, fr, 0, 0));
  }
  CHECK(w.close(true, 0, 0));
  Session s; std::string err;
  CHECK(ingest_raw({path}, &s, &err));
  CHECK(s.session_id == "S_TEST_001" && s.horse == "PRUEBA");
  CHECK(s.gnss.size() == 80);
  CHECK(s.imu.size() == 10);
  if (s.gnss.size() == 80) {
    CHECK(s.gnss[5].itow_ms == 1000 + 5 * 125);
    CHECK_NEAR(s.gnss[5].lat_deg, 43.4000050, 1e-9);
    CHECK(s.gnss[5].chest_us == 5000000ull + 5 * 125000ull + 7000);
    CHECK(rtk_state(s.gnss[5]) == RtkState::FIXED);
  }
  if (s.imu.size() == 10) {
    CHECK(s.imu[3].imu_id == 1 && s.imu[3].batch_seq == 77);
    CHECK(s.imu[3].girth_us == 123456 + 3 * 5000);
    CHECK(s.imu[3].ax == 30 && s.imu[3].mz == 38);
  }
  CHECK(s.clean_close);
  auto a = analyse(s);
  CHECK(!a.gnss.metrics.empty());
  remove(path);
}

EQ_TEST(ingestion, non_avo_file_is_rejected) {
  const char* path = "eq_not_avo.bin";
  FILE* f = fopen(path, "wb"); fputs("esto no es un fichero AVO", f); fclose(f);
  Session s; std::string err;
  CHECK(!ingest_raw({path}, &s, &err));
  CHECK(!err.empty());
  remove(path);
}
