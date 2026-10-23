/* AVO PERFORMANCE HORSE — BACK V3.8.0 (ESP-NOW) · máxima precisión RTK
 *
 * V3.8.0 sobre V3.5.0 (instalada hasta ahora en la espalda, copia del 23-10-2026):
 *   - ZED-F9P a 8 Hz con GPS+GLONASS+Galileo+BeiDou (límite RTK del data sheet; V3.5.0 pedía 10 Hz con 4
 *     constelaciones, por encima de lo que el F9P resuelve en RTK). Si el pecho pide 10/12 Hz se quitan
 *     BeiDou / GLONASS para no pasar el límite; cambiar de constelación solo cuando hace falta.
 *   - Perfil de precisión: RTK fijo (DGNSSMODE=3), modelo dinámico Airborne <2g (galope, saltos, sin
 *     restricciones de suelo), máscara de elevación 10°. VALSET aparte: si el receptor lo rechaza, todo sigue igual que en V3.5.0.
 *   - El RTCM sigue llegando al ZED mientras se reconfigura.
 *   - Radio: sin ahorro de energía Wi-Fi, potencia máxima, espera de ACK 25 ms, cola de 48 paquetes.
 *   - Monitor serie con búfer: imprimir el estado ya no frena el bucle.
 *   El protocolo con el pecho (ESP-NOW + tramas AVO UART v1) NO cambia.
 * Board: Heltec Wireless Stick Lite V3 (ESP32-S3FN8) + u-blox ZED-F9P.
 * Arduino board: "Heltec Wireless Stick Lite(V3)" (arduino-esp32 3.x). Build: ../build_back.sh
 *
 * Wiring (same as the V3.4.5 test firmware the user already has):
 *   Heltec GPIO33 (RX)  <- ZED TX (UART1 or UART2: detected automatically)
 *   Heltec GPIO35 (TX)  -> ZED RX   (GPIO35 is also the white LED: it flickers with RTCM, that is normal)
 *   GND common. ZED powered as per its module (if it is fed from the Heltec Vext pin, Vext is switched on).
 *
 * What it does (all logic in lib/avo_core/src/avo_back_core.* and avo_ubx_zed.*, host-tested):
 *   - finds the ZED baud rate and port, enables UBX + RTCM3 input and NAV-PVT + RXM-RTCM output,
 *     sets the navigation rate (RAM only: a power cycle of the ZED restores its own configuration);
 *   - NAV-PVT -> GNSS_SAMPLE -> chest; RTCM from the chest -> ZED, in order, without duplicates;
 *   - counts what the ZED really applied (UBX-RXM-RTCM) and reports it to the chest every second;
 *   - pairs with ONE chest (stored in flash). PRG button held 3 s: accept a new chest for 120 s.
 * Serial monitor 115200 baud: status every 2 s.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_idf_version.h>
#include <esp_random.h>
#include <Preferences.h>
#include "avo_core.h"

using namespace avo;

// ------------------------------------------------------------------ hardware
static const int ZED_RX_PIN = 33;      // Heltec RX  <- ZED TX
static const int ZED_TX_PIN = 35;      // Heltec TX  -> ZED RX
static const int PRG_PIN = 0;          // PRG / USER button (active LOW)
static const int VEXT_PIN = 36;        // Heltec Vext switch (LOW = 3.3 V on Vext)
static const uint8_t NAV_RATE_HZ = 8;  // RTK limit of the ZED-F9P with 4 constellations

HardwareSerial ZED(1);
Preferences prefs;

// ------------------------------------------------------------------ radio plumbing
struct RxPkt { uint8_t mac[6]; int8_t rssi; uint8_t len; uint8_t d[NOW_MAX_PACKET]; };
static QueueHandle_t s_rxq = nullptr;
static SemaphoreHandle_t s_sent = nullptr;
static volatile bool s_sent_ok = false;
static volatile uint32_t s_rxq_drop = 0;
static const uint8_t kBroadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

#if ESP_IDF_VERSION_MAJOR >= 5
static void on_recv(const esp_now_recv_info_t* info, const uint8_t* d, int n) {
  const uint8_t* mac = info->src_addr;
  int8_t rssi = info->rx_ctrl ? (int8_t)info->rx_ctrl->rssi : 0;
#else
static void on_recv(const uint8_t* mac, const uint8_t* d, int n) {
  int8_t rssi = 0;
#endif
  if (n <= 0 || n > (int)NOW_MAX_PACKET || !s_rxq) return;
  RxPkt p;
  memcpy(p.mac, mac, 6);
  p.rssi = rssi;
  p.len = (uint8_t)n;
  memcpy(p.d, d, (size_t)n);
  if (xQueueSend(s_rxq, &p, 0) != pdTRUE) s_rxq_drop = s_rxq_drop + 1;
}

#if ESP_IDF_VERSION >= ESP_IDF_VERSION_VAL(5, 5, 0)
static void on_sent(const esp_now_send_info_t*, esp_now_send_status_t st) {
#else
static void on_sent(const uint8_t*, esp_now_send_status_t st) {
#endif
  s_sent_ok = (st == ESP_NOW_SEND_SUCCESS);
  xSemaphoreGive(s_sent);
}

static void ensure_peer(const uint8_t mac[6]) {
  if (esp_now_is_peer_exist(mac)) return;
  esp_now_peer_info_t p = {};
  memcpy(p.peer_addr, mac, 6);
  p.channel = NOW_CHANNEL_DEFAULT;
  p.ifidx = WIFI_IF_STA;
  p.encrypt = false;
  esp_now_add_peer(&p);
}

class HeltecPlatform : public BackPlatform {
 public:
  uint32_t now_ms() override { return millis(); }
  void zed_set_baud(uint32_t b) override {
    ZED.flush();
    ZED.updateBaudRate(b);
    while (ZED.available()) ZED.read();   // drop bytes received at the old speed
  }
  void zed_write(const uint8_t* d, size_t n) override { ZED.write(d, n); }
  bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) override {
    const uint8_t* to = mac ? mac : kBroadcast;
    xSemaphoreTake(s_sent, 0);
    if (esp_now_send(to, d, n) != ESP_OK) return false;
    if (xSemaphoreTake(s_sent, pdMS_TO_TICKS(25)) != pdTRUE) return false;   // MAC ACK arrives in ~1-3 ms
    return s_sent_ok;
  }
  void radio_set_peer(const uint8_t mac[6]) override { ensure_peer(mac); }
  void save_peer(const NowPeerRecord& r) override {
    uint8_t b[NOW_PEER_RECORD_LEN];
    size_t n = now_peer_serialize(r, b, sizeof(b));
    if (n) prefs.putBytes("peer", b, n);
  }
  uint32_t random32() override { return esp_random(); }
  void reboot() override { delay(50); ESP.restart(); }
};

static HeltecPlatform platform;
static char s_dev_id[16];
static BackCore* core = nullptr;

// ------------------------------------------------------------------ status print
static void print_status() {
  const BackStats& st = core->stats();
  const ZedManager& z = core->zed();
  const RtcmStats& rs = core->rtcm_stats();
  BackStatus b = core->status();
  char mac[18] = "-";
  if (core->paired()) now_mac_str(core->peer().mac, mac);
  Serial.printf("\n[AVO ESPALDA %s] pecho=%s (%s) %s rssi=%d dBm | tx ok=%lu fallo=%lu reint=%lu | rx=%lu ajenos=%lu malos=%lu colaRX=%lu\n",
                AVO_FW_VERSION, core->chest_online() ? "CONECTADO" : "SIN CONEXION", mac,
                core->pairing_open() ? "EMPAREJAMIENTO ABIERTO" : (core->paired() ? "emparejado" : "SIN EMPAREJAR"),
                (int)st.rssi, (unsigned long)st.tx_packets, (unsigned long)st.tx_fail, (unsigned long)st.tx_retries,
                (unsigned long)st.rx_packets, (unsigned long)st.rx_foreign, (unsigned long)st.rx_bad, (unsigned long)s_rxq_drop);
  Serial.printf("  ZED: %s baudios=%lu puerto=UART%u config=%s ritmo=%u Hz (medido %.1f Hz) UBX=%lu NMEA=%lu NAV-PVT=%lu\n",
                ZedManager::state_name(z.state()), (unsigned long)z.baud(), (unsigned)z.port(),
                z.config_acked() ? "OK" : "NO", (unsigned)z.nav_rate(), b.gnss_rate_hz_x10 / 10.0,
                (unsigned long)z.stream().frames(), (unsigned long)z.stream().nmea_sentences(), (unsigned long)st.nav_pvt);
  Serial.printf("  PRECISION: perfil=%s constelaciones=%s modelo=%u RTK=fijo\n",
                z.tune_state() == 1 ? "COMPLETO" : z.tune_state() == 2 ? "REDUCIDO" : z.tune_state() == 3 ? "RECHAZADO (receptor antiguo)" : "pendiente",
                zed_gnss_name(z.gnss_set()), (unsigned)z.dyn_model());
  Serial.printf("  RTCM: recibido del pecho=%lu B -> escrito al ZED=%lu B (tramas OK=%lu mal=%lu) huecos=%lu B sin escribir=%lu B | ZED aplicadas=%lu rechazadas=%lu\n",
                (unsigned long)st.rtcm_rx_bytes, (unsigned long)st.rtcm_to_zed, (unsigned long)rs.frames_ok,
                (unsigned long)rs.frames_bad_crc, (unsigned long)st.rtcm_gaps, (unsigned long)st.rtcm_not_written,
                (unsigned long)st.rxm_used, (unsigned long)st.rxm_failed);
  if (z.state() == ZedManager::NO_RESPONSE)
    Serial.println("  AVISO: el ZED no contesta a UBX. Revisa el cableado TX/RX y que el puerto del ZED tenga UBX activado (u-center).");
}

// ------------------------------------------------------------------ setup / loop
void setup() {
  Serial.setTxBufferSize(4096);          // status printing must never block the GNSS/RTCM loop
  Serial.begin(115200);
  delay(300);
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);           // Vext on (harmless if the ZED has its own supply)
  pinMode(PRG_PIN, INPUT_PULLUP);
  ZED.setRxBufferSize(8192);
  ZED.setTxBufferSize(4096);
  ZED.begin(38400, SERIAL_8N1, ZED_RX_PIN, ZED_TX_PIN);
  ZED.setRxTimeout(1);                   // hand each NAV-PVT over as soon as the line goes idle

  s_rxq = xQueueCreate(48, sizeof(RxPkt));   // ~1 s of RTCM burst
  s_sent = xSemaphoreCreateBinary();
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  WiFi.setSleep(false);
  esp_wifi_set_ps(WIFI_PS_NONE);         // radio always listening: no added RTCM latency
  esp_wifi_set_channel(NOW_CHANNEL_DEFAULT, WIFI_SECOND_CHAN_NONE);
  esp_wifi_set_max_tx_power(84);         // 21 dBm request (the S3 caps it at its maximum)
  if (esp_now_init() != ESP_OK) Serial.println("[AVO ESPALDA] ERROR esp_now_init");
  esp_now_register_recv_cb(on_recv);
  esp_now_register_send_cb(on_sent);
  ensure_peer(kBroadcast);
  uint8_t mac[6];
  esp_wifi_get_mac(WIFI_IF_STA, mac);
  snprintf(s_dev_id, sizeof(s_dev_id), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

  prefs.begin("avonow", false);
  NowPeerRecord stored;
  uint8_t b[NOW_PEER_RECORD_LEN];
  size_t n = prefs.getBytes("peer", b, sizeof(b));
  if (!now_peer_deserialize(b, n, &stored)) stored = NowPeerRecord();

  core = new BackCore(&platform, s_dev_id, NAV_RATE_HZ);
  core->begin(stored);
  char pm[18] = "-";
  if (stored.valid) now_mac_str(stored.mac, pm);
  Serial.printf("\nAVO BACK %s — Heltec %s, ESP-NOW canal %u, pecho emparejado: %s\n", AVO_FW_VERSION, s_dev_id,
                (unsigned)NOW_CHANNEL_DEFAULT, stored.valid ? pm : "ninguno (se emparejará con el primer pecho que lo pida)");
  Serial.printf("ZED: RX=GPIO%d TX=GPIO%d, buscando baudios...\n", ZED_RX_PIN, ZED_TX_PIN);
}

void loop() {
  bool worked = false;
  RxPkt p;
  while (xQueueReceive(s_rxq, &p, 0) == pdTRUE) { core->on_radio(p.mac, p.d, p.len, p.rssi); worked = true; }

  uint8_t buf[512];
  int avail;
  while ((avail = ZED.available()) > 0) {
    int n = ZED.readBytes(buf, avail > (int)sizeof(buf) ? (int)sizeof(buf) : avail);
    if (n <= 0) break;
    core->on_zed(buf, (size_t)n);
    worked = true;
  }
  core->tick();

  // PRG held 3 s -> accept a new chest for 120 s
  static uint32_t prg_t = 0;
  if (digitalRead(PRG_PIN) == LOW) {
    if (!prg_t) prg_t = millis();
    else if (millis() - prg_t > 3000 && prg_t != 1) {
      core->open_pairing();
      Serial.println("[AVO ESPALDA] emparejamiento abierto 120 s: pide 'Emparejar espalda' desde la app o reinicia el pecho sin pareja");
      prg_t = 1;
    }
  } else {
    prg_t = 0;
  }

  static uint32_t last_print = 0;
  if (millis() - last_print >= 2000) { last_print = millis(); print_status(); }
  if (!worked) delay(1);                 // only sleep when there was nothing to do
}
