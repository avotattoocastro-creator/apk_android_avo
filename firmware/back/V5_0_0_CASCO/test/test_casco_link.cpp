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

int main(int argc, char** argv) { return tt_run_all(argc > 1 ? argv[1] : "casco"); }
