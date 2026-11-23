// AVO CASCO 5.0.0 — prueba de ordenador del enlace interno pecho ↔ espalda.
// Reutiliza el mundo simulado de la espalda (test/test_espnow.cpp: ZED-F9P simulado, decodificador del pecho) y
// comprueba lo que cambia en el casco: la pareja es FIJA desde el arranque (sin PAIR_REQ/PAIR_ACK), el «radio» entre
// los dos no pierde nada (es memoria) y el BackCore de la espalda funciona igual (8 Hz, RTK fijo, RTCM íntegro al ZED,
// BackStatus, CAPS, BACK_SLEEP). El ZED simulado es un modelo, NO el receptor real.
#define main back_tests_main
#include "../../V3_8_0/test/test_espnow.cpp"
#undef main

static const uint32_t kPairId = 0x5A17C0DEu;

// Mundo del casco: la misma estructura, con las dos parejas cargadas como hace el firmware (casco_back::init y
// uart_link now_init) y sin pérdidas de radio.
struct CascoWorld : World {
  explicit CascoWorld(int zport = 1) : World(zport) {
    radio.loss = 0; radio.ack_loss = 0;
    delete back;
    back = new BackCore(&plat, "CASCOTEST", 8);
    NowPeerRecord chest_rec; chest_rec.valid = true; memcpy(chest_rec.mac, MAC_CA, 6); chest_rec.pair_id = kPairId;
    back->begin(chest_rec);
    NowPeerRecord back_rec; back_rec.valid = true; memcpy(back_rec.mac, MAC_BA, 6); back_rec.pair_id = kPairId;
    chest.pair = NowPairing(NowRole::CHEST);   // como uart_link en el casco: pareja cargada y SIN ventana abierta
    chest.pair.load(back_rec);
  }
};

TEST(casco, fixed_internal_pair_links_without_handshake) {
  CascoWorld w(1);                 // casco: el ZED va por su UART1 (GPIO5/6)
  w.run_ms(3000);
  CHECK(w.back->paired());
  CHECK_EQ(w.back->stats().pairings, 0u);    // nunca hubo emparejamiento
  CHECK(w.chest.have_caps);                  // CAPS de la espalda interna
  CHECK(w.chest.have_status);                // BackStatus decodificado por el pecho
  CHECK_EQ(w.back->stats().rx_foreign, 0u);
}

TEST(casco, zed_runs_8hz_rtk_fixed_and_gnss_reaches_the_chest) {
  CascoWorld w(1);
  w.run_ms(15000);
  CHECK_EQ((int)w.back->zed().state(), (int)ZedManager::RUNNING);
  CHECK_EQ(w.back->zed().port(), 1);
  CHECK_EQ(w.zed.meas_ms, 125);              // 8 Hz con 4 constelaciones
  CHECK_EQ(w.zed.dgnss, 3);                  // RTK fijo
  CHECK(w.chest.gnss.size() > 50);
  CHECK_EQ(w.chest.gnss.back().nav_rate_hz, 8);
  CHECK(w.chest.last_status.v2);
}

TEST(casco, phone_rtcm_reaches_the_zed_intact) {
  CascoWorld w(1);
  w.run_ms(15000);
  w.run_ms(20000, 4);                        // 4 tramas RTCM por segundo desde el «móvil»
  w.run_ms(2000);
  size_t matched = 0, skipped = 0;
  CHECK(walk(w.zed.rtcm_bytes, w.phone_rtcm, &matched, &skipped));
  CHECK_EQ(skipped, 0u);                     // sin pérdidas: el enlace interno es memoria
  CHECK(matched > 50);
  CHECK(w.zed.rtcm_bytes == w.phone_rtcm);   // byte a byte, en orden y sin duplicados
  CHECK_EQ(w.chest.rtcm_lost_bytes, 0u);
}

TEST(casco, back_sleep_parks_only_the_zed) {
  CascoWorld w(1);
  w.run_ms(5000);
  chest_cmd(w, (BackCmd)8, 0, 900);          // BACK_SLEEP: el pecho carga por USB sin grabar
  w.run_ms(500);
  CHECK_EQ(w.plat.sleeps, 1u);               // el casco solo apaga el ZED (casco_back.cpp: request_sleep)
  CHECK(w.back->paired());
}

// ---------------------------------------------------------------- PPS, TIME_SYNC e IMU de la cabeza (ganchos del casco)
// Recoge las tramas que el ChestModel de la espalda no guarda (TIME_SYNC, IMU_SAMPLE) y deja pasar el resto.
struct Extra { std::vector<TimeSync> ts; std::vector<ImuBatchHeader> imu; std::vector<size_t> imu_len; ChestModel* c; };
static void extra_frame(const FrameView& f, void* ctx) {
  Extra* e = (Extra*)ctx;
  ChestModel::on_frame(f, e->c);
  if (f.type == FrameType::TIME_SYNC) { TimeSync t; if (decode_timesync(f.payload, f.len, &t)) e->ts.push_back(t); }
  if (f.type == FrameType::IMU_SAMPLE) {
    ImuBatchHeader h;
    if (decode_imu_header(f.payload, f.len, &h)) { e->imu.push_back(h); e->imu_len.push_back(f.len); }
  }
}
static void hook_chest(CascoWorld& w, Extra& e) { e.c = &w.chest; delete w.chest.dec; w.chest.dec = new UartDecoder(extra_frame, &e); }

struct PvtLog { uint32_t n = 0; };
static void pvt_log(const GnssSample& g, void* ctx) {
  PvtLog* l = (PvtLog*)ctx;
  (void)g;
  l->n++;
}

TEST(casco, pps_state_reaches_status_caps_and_gnss_samples) {
  CascoWorld w(1);
  PvtLog log;
  w.back->set_pvt_observer(pvt_log, &log);
  w.run_ms(8000);
  CHECK(w.chest.have_caps);
  CHECK(w.chest.caps.caps & CAP_PPS);
  CHECK(w.chest.caps.caps & CAP_TIME_SYNC);
  CHECK(w.chest.caps.caps & CAP_IMU);
  CHECK(w.chest.have_status && w.chest.last_status.pps_state == 0);   // sin pulsos todavía
  w.back->set_pps(2, 41);
  w.chest.gnss.clear();
  w.run_ms(3000);
  CHECK_EQ(w.chest.last_status.pps_state, 2);
  CHECK_EQ(w.chest.last_status.pps_count, 41u);
  CHECK(!w.chest.gnss.empty() && w.chest.gnss.back().pps_locked == 1);
  CHECK(log.n > 50);        // el observador ve todos los NAV-PVT (8 Hz)
}

TEST(casco, time_sync_and_head_imu_travel_unchanged_to_the_chest) {
  CascoWorld w(1);
  Extra e;
  w.run_ms(5000);
  hook_chest(w, e);   // después del primer paquete (NowBootGuard rehace el decodificador)
  TimeSync t; t.back_us_at_pps = 123456789012ull; t.tow_ms_at_pps = 345000; t.flags = 1 | 4; t.pps_jitter_ns = 800; t.pps_count = 7;
  uint8_t tb[TIME_SYNC_V1_LEN];
  CHECK_EQ(encode_timesync(t, tb, sizeof(tb)), TIME_SYNC_V1_LEN);
  CHECK(w.back->send_extra(FrameType::TIME_SYNC, tb, TIME_SYNC_V1_LEN));
  // lote de la cabeza como casco_imu.cpp: 24 B + 15 × 12 B, fmt 3, imu_id 4, unidades 3 en el byte 15
  ImuBatchHeader h; h.girth_id = 0xCA; h.imu_id = 4; h.count = 15; h.fmt = 3; h.girth_seq = 9; h.girth_t0_us = 5000000;
  h.period_us = 8333; h.sync_state = 2; h.reserved = 3;
  std::vector<uint8_t> ib(IMU_HDR_LEN + 15 * 12, 0x5A);
  CHECK_EQ(encode_imu_header(h, ib.data(), IMU_HDR_LEN), IMU_HDR_LEN);
  CHECK_EQ(ib[15], 3);
  for (int k = 0; k < 20; k++) { h.girth_seq = 9 + k; encode_imu_header(h, ib.data(), IMU_HDR_LEN); CHECK(w.back->send_extra(FrameType::IMU_SAMPLE, ib.data(), ib.size())); }
  w.run_ms(1000);
  CHECK_EQ(e.ts.size(), 1u);
  CHECK(!e.ts.empty() && e.ts[0].back_us_at_pps == 123456789012ull && e.ts[0].tow_ms_at_pps == 345000u && e.ts[0].pps_count == 7u);
  CHECK_EQ(e.imu.size(), 20u);
  bool all = e.imu.size() == 20;
  for (size_t i = 0; i < e.imu.size(); i++)
    all = all && e.imu[i].fmt == 3 && e.imu[i].imu_id == 4 && e.imu[i].reserved == 3 && e.imu[i].girth_seq == 9 + i &&
          e.imu_len[i] == IMU_HDR_LEN + 15 * 12;
  CHECK(all);               // en orden, sin pérdidas ni duplicados (el enlace interno es memoria)
}

TEST(casco, a_16_sample_head_batch_would_not_fit_one_frame) {
  // límite real del enlace: carga ≤ NOW_MAX_BODY − cabecera y cola UART (15 + 4) = 215 B
  CHECK(IMU_HDR_LEN + 15 * 12 <= NOW_MAX_BODY - AVO_UART_HDR - AVO_UART_TRAILER);
  CHECK(IMU_HDR_LEN + 16 * 12 > NOW_MAX_BODY - AVO_UART_HDR - AVO_UART_TRAILER);
}

TEST(casco, send_extra_waits_for_the_chest) {
  CascoWorld w(1);
  uint8_t tb[TIME_SYNC_V1_LEN] = {0};
  CHECK(!w.back->send_extra(FrameType::TIME_SYNC, tb, sizeof(tb)));   // el pecho aún no ha hablado
}

int main(int argc, char** argv) { return tt_run_all(argc > 1 ? argv[1] : "casco"); }
