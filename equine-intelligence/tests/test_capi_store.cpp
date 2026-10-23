// Persistence, C API v2 (the same entry points used by JNI, P/Invoke and ctypes) and robustness:
// incomplete sessions, GNSS without IMU, IMU without GNSS, irregular timestamps, long sessions, cancellation.
#include "eq_test.h"
#include "avo_core.h"
#include "avo_eq/avo_eq_c.h"
#include "avo_eq/engine.h"
#include "avo_eq/ingestion.h"
#include "avo_eq/json.h"
#include "avo_eq/store.h"
#include "synth.h"
#include <chrono>
#include <cstring>
#include <filesystem>
#include <fstream>

using namespace avoeq;

// Writes a Session to an AVO RAW v1 file with the chest's own writer (avo_core), so the whole chain
// RAW -> ingestion -> engine -> JSON is exercised exactly as on the phone.
static bool write_raw(const char* path, const Session& s, bool close_clean = true) {
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

static double f095(double) { return 0.95; }
static double a280(double) { return 280; }
static double a600(double) { return 600; }

static Session full_session(double secs, const char* id) {
  Session s; s.session_id = id;
  s.gnss = synth::track({{secs + 4, 1.5, 0}}, 8, nullptr, nullptr, 0.03);
  synth::ImuSpec sp; sp.offset_s = 5.0;   // girth clock is unsigned in the RAW format
  s.imu = synth::imu_shape(secs, f095, a280, a600, sp, 0, 3, 30);
  return s;
}

EQ_TEST(store, raw_untouched_cache_hit_and_invalidation) {
  namespace fs = std::filesystem;
  const char* raw = "eq_store_session.avo";
  std::string dir = "eq_store_dir";
  fs::remove_all(dir); remove(raw);
  CHECK(write_raw(raw, full_session(40, "S_STORE")));
  std::string err, fp0 = fingerprint_files({raw}, &err);
  CacheResult r1, r2, r3;
  EngineConfig c;
  CHECK(analyse_cached({raw}, dir, c, "2026-10-24T00:00:00Z", false, &r1, &err));
  CHECK(r1.state == "CALCULADO");
  CHECK(analyse_cached({raw}, dir, c, "2026-10-24T01:00:00Z", false, &r2, &err));
  CHECK(r2.state == "ACIERTO" && r2.json == r1.json);             // same stored analysis, no recomputation
  CHECK(fingerprint_files({raw}, &err) == fp0);                     // RAW file never modified
  EngineConfig c2; c2.cadence.window_s = 8;                          // different parameters: another analysis
  CHECK(analyse_cached({raw}, dir, c2, "x", false, &r3, &err));
  CHECK(r3.state == "CALCULADO" && r3.path != r1.path);
  CHECK(analyse_cached({raw}, dir, c, "y", true, &r3, &err) && r3.state == "RECALCULADO" && r3.path == r1.path);   // forced: replaced, not duplicated
  size_t files = 0; for (auto& e : fs::directory_iterator(dir)) { (void)e; files++; }
  CHECK(files == 2);
  // an analysis from another engine version is detected and removed
  { std::string t = r2.json; size_t p = t.find(ENGINE_VERSION); t.replace(p, strlen(ENGINE_VERSION), "0.9.0"); std::ofstream(dir + "/analisis_viejo_x.json") << t; }
  auto list = cache_list(dir);
  int invalid = 0; for (auto& e : list) if (!e.valid) invalid++;
  CHECK(invalid == 1);
  CHECK(cache_invalidate(dir) == 1);
  CHECK(fingerprint_files({raw}, &err) == fp0);
  fs::remove_all(dir); remove(raw);
}

EQ_TEST(capi, analyse_compare_errors_and_cancel) {
  const char* raw = "eq_capi_a.avo"; const char* raw2 = "eq_capi_b.avo";
  CHECK(write_raw(raw, full_session(40, "S_CAPI_A")));
  CHECK(write_raw(raw2, full_session(40, "S_CAPI_B")));
  CHECK(avo_eq_api_version() == 2);
  const char* p[] = {raw};
  char* out = nullptr;
  CHECK(avo_eq_analyse_ex(p, 1, "{\"series\":true,\"modo\":\"OFFLINE\",\"clasificador_rendimiento\":\"V2\"}", nullptr, &out) == 0);
  json::Value v; std::string err;
  CHECK(json::parse(out, &v, &err));
  CHECK(v["version_formato"].num() == 2 && v["motor"].str() == ENGINE_VERSION);
  CHECK(v["rendimiento"]["clasificador"].str() == "GAIT_CLASSIFIER_V2");
  CHECK(v["series"]["t"].a.size() == v["series"]["velocidad"].a.size());
  CHECK(!v["series_cincha"]["cadencia_hz"].a.empty());
  CHECK(v["procedencia"]["huella_entrada"].str().size() == 16);
  CHECK(v["unidades_series"]["velocidad"].str() == "m/s");
  avo_eq_free(out);
  // invalid options and missing files: error code and JSON error, never a crash
  CHECK(avo_eq_analyse_ex(p, 1, "{\"modo\":\"MAGIA\"}", nullptr, &out) == 5); CHECK(json::parse(out, &v) && !v["error"].str().empty()); avo_eq_free(out);
  CHECK(avo_eq_analyse_ex(p, 1, "{no json", nullptr, &out) == 5); avo_eq_free(out);
  const char* missing[] = {"no_existe.avo"};
  CHECK(avo_eq_analyse_ex(missing, 1, nullptr, nullptr, &out) == 1); avo_eq_free(out);
  CHECK(avo_eq_analyse_ex(nullptr, 0, nullptr, nullptr, &out) == 2); avo_eq_free(out);
  // cancellation requested before start: stops at the first stage
  volatile int cancel = 1;
  CHECK(avo_eq_analyse_ex(p, 1, nullptr, &cancel, &out) == 4); CHECK(json::parse(out, &v) && v["cancelado"].boolean()); avo_eq_free(out);
  // comparison through the C API
  const char* q[] = {raw2};
  CHECK(avo_eq_compare_ex(p, 1, q, 1, "{\"mismo_recorrido\":true,\"seleccion_a\":{\"tipo\":\"TIEMPO\",\"a\":5,\"b\":30},\"seleccion_b\":{\"tipo\":\"TIEMPO\",\"a\":5,\"b\":30}}", nullptr, &out) == 0);
  CHECK(json::parse(out, &v) && v["formato"].str() == "avo-equine-comparison");
  CHECK(v["recorrido"]["comparable"].boolean());
  avo_eq_free(out);
  remove(raw); remove(raw2);
}

EQ_TEST(robustness, incomplete_session_without_clean_close) {
  const char* raw = "eq_incomplete.avo";
  CHECK(write_raw(raw, full_session(30, "S_INCOMPLETE"), false));    // recording interrupted: no closing block
  Session s; std::string err;
  CHECK(ingest_raw({raw}, &s, &err));
  CHECK(!s.clean_close);
  auto a = analyse(s);
  bool flagged = false; for (auto& q : a.quality) if (q.domain == "INTEGRIDAD") for (auto& r : q.reasons) flagged |= r.find("sin cierre limpio") != std::string::npos;
  CHECK(flagged);
  CHECK(!a.gnss.t.empty());
  remove(raw);
}

EQ_TEST(robustness, gnss_only_imu_only_and_irregular_timestamps) {
  Session g; g.gnss = synth::track({{60, 3.0, 0}}, 8, nullptr);
  for (size_t i = 0; i < g.gnss.size(); i += 7) g.gnss[i].itow_ms += 37;    // jittered epochs
  g.gnss.erase(g.gnss.begin() + 100, g.gnss.begin() + 130);              // 3.75 s hole
  auto a = analyse(g);
  CHECK(!a.has_imu);
  bool w = false; for (auto& x : a.warnings) w |= x == "SIN DATOS DE CINCHA";
  CHECK(w);
  CHECK(!a.performance.segments.empty());
  for (auto& p : a.performance.segments) CHECK(std::isnan(p.cadence_mean_hz));
  bool gap_event = false; for (auto& e : a.events) gap_event |= e.type == "PERDIDA_CALIDAD_GNSS";
  CHECK(gap_event);
  Session i; synth::ImuSpec sp; i.imu = synth::imu_shape(60, f095, a280, a600, sp);
  auto b = analyse(i);
  CHECK(!b.has_gnss && b.has_imu);
  CHECK(!b.cadence.empty() && !b.cadence[0].metrics.empty());        // cadence still computed on the girth clock
  for (auto& s : b.performance.segments) CHECK(s.gait == Gait::INSUFFICIENT_DATA || s.gait == Gait::UNKNOWN);
}

EQ_TEST(robustness, long_session_three_imus) {
  const double secs = 1800;   // 30 min, 3 IMUs at 100 Hz, GNSS 8 Hz
  Session s;
  s.gnss = synth::track({{secs + 4, 3.0, 0}}, 8, nullptr, nullptr, 0.03);
  synth::ImuSpec sp; sp.fs = 100; sp.batch = 10;
  for (uint8_t id = 0; id < 3; id++) { auto v = synth::imu_shape(secs, f095, a280, a600, sp, id, 10 + id, 30); s.imu.insert(s.imu.end(), v.begin(), v.end()); }
  auto t0 = std::chrono::steady_clock::now();
  auto a = analyse(s);
  double el = std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
  REPORT("sesión de 30 min: %zu épocas GNSS, %zu muestras IMU, análisis en %.1f s (con sanitizadores si están activos)\n", s.gnss.size(), s.imu.size(), el);
  CHECK(a.cadence.size() == 3);
  CHECK(a.fusion.windows_total > 2000);
  std::string js = to_json(a, s, EngineConfig(), true);
  json::Value v; CHECK(json::parse(js, &v));
  CHECK(el < 300);
}
