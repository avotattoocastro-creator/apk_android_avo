/* AVO PERFORMANCE HORSE — BACK V3.10.0 (ESP-NOW) · V3.10.0: girth unit (ESP32-C6) hub · V3.9.0: GNSS quality (NAV-SAT/SIG), RTK FIX tracking · V3.8.2: charge mode · V3.8.1: battery voltage sent to the chest
 * BACK V3.8.0 (ESP-NOW) · máxima precisión RTK
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

// Identity marker read by the AVO USB updater ("3.8.0" followed by "AVO-BACK"): the app shows
// "AVO-BACK 3.8.0" and refuses to install a back firmware on the chest or a chest firmware on the back.
extern "C" const char AVO_BACK_IMAGE_ID[] __attribute__((used, aligned(4))) = "\0" AVO_FW_VERSION "\0AVO-BACK";

// ------------------------------------------------------------------ hardware
static const int ZED_RX_PIN = 33;      // Heltec RX  <- ZED TX
static const int ZED_TX_PIN = 35;      // Heltec TX  -> ZED RX
static const int PRG_PIN = 0;          // PRG / USER button (active LOW)
static const int VEXT_PIN = 36;        // Heltec Vext switch (LOW = 3.3 V on Vext)
// V3.8.1: battery voltage. VBAT through a divider on GPIO1, divider enabled by GPIO37 (ADC_Ctrl).
// V3/V3.1 boards: pull-up on GPIO37, active LOW. V3.2 (this back, HTIT-WSL_V3 rev 3.2): transistor, active HIGH.
// The polarity is detected at boot by reading GPIO37 as input (pull-up present → reads HIGH → active LOW).
static const int VBAT_PIN = 1;
static const int VBAT_CTRL_PIN = 37;
static const float VBAT_DIVIDER = 4.9f;  // 390k + 100k (Heltec reference design)
static uint8_t s_vbat_active = HIGH;
static uint16_t s_vbat_mv = 0;
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
  void save_girth(const uint8_t mac[6]) override { prefs.putBytes("girth", mac, 6); }   // V3.10.0
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
  Serial.printf("  BATERIA: %u mV\n", (unsigned)s_vbat_mv);   // V3.8.1
  {  // V3.10.0 girth unit
    const GirthHub& g = core->girth();
    if (!g.paired()) Serial.println("  CINCHA: sin emparejar (se acepta la primera que salude)");
    else {
      char m[18]; now_mac_str(g.mac(), m);
      Serial.printf("  CINCHA: %s %s fw=%s rssi=%d dBm | paquetes=%lu perdidos=%lu IMU reenviados=%lu | uptime %lu s, IMUs=%u, envios ok=%lu fallo=%lu\n",
                    m, g.connected(millis()) ? "CONECTADA" : "sin senal", g.hello().fw, g.rssi(), (unsigned long)g.rx_packets(),
                    (unsigned long)g.lost(), (unsigned long)g.imu_forwarded(), (unsigned long)(g.status().uptime_ms / 1000),
                    g.status().imu_count, (unsigned long)g.status().tx_ok, (unsigned long)g.status().tx_fail);
    }
  }
  {  // V3.9.0: GNSS quality (NAV-SAT/NAV-SIG) and RTK FIX tracking
    const GnssQuality& q = core->quality();
    BackStatus bs = core->status();
    static const char* mon[] = {"pendiente", "OK", "RECHAZADO", "UART lenta"};
    Serial.printf("  CALIDAD: sat %u/%u usados | senales %u (usadas %u, fase %u, corregidas %u) | 2a banda L2/E5b/B2 %u%s | C/N0 media %u min %u max %u | debiles %u | NAV-SIG %s hace %u s\n",
                  q.sv_used, q.sv_tracked, q.sig_tracked, q.sig_used, q.sig_cr_used, q.sig_corr, q.sig_l2,
                  (q.have_sig && q.sig_l2 == 0) ? " (ANTENA SOLO L1: sin RTK FIX)" : "", q.cno_mean, q.cno_min, q.cno_max,
                  q.sig_weak, mon[bs.quality_mon & 3], (unsigned)bs.quality_age_s);
    Serial.printf("  RTK: FIX %lu s, FLOAT %lu s, perdidas de FIX %u, primer FIX %s%u s\n", (unsigned long)(bs.fixed_ms / 1000),
                  (unsigned long)(bs.float_ms / 1000), bs.fix_lost, bs.ttff_fix_s == 0xFFFF ? "aun no " : "a los ",
                  bs.ttff_fix_s == 0xFFFF ? 0u : (unsigned)bs.ttff_fix_s);
  }
  if (z.state() == ZedManager::NO_RESPONSE)
    Serial.println("  AVISO: el ZED no contesta a UBX. Revisa el cableado TX/RX y que el puerto del ZED tenga UBX activado (u-center).");
}

// V3.8.1: average of 16 readings with the divider enabled only while measuring (no constant drain).
static uint16_t read_battery_mv() {
  digitalWrite(VBAT_CTRL_PIN, s_vbat_active);
  delayMicroseconds(200);
  uint32_t acc = 0;
  for (int i = 0; i < 16; i++) acc += analogReadMilliVolts(VBAT_PIN);
  digitalWrite(VBAT_CTRL_PIN, !s_vbat_active);
  uint32_t mv = (uint32_t)((acc / 16) * VBAT_DIVIDER);
  // Outside 2.5–4.6 V it is not a 1-cell Li-ion reading (no battery, wrong polarity): report unknown.
  return (mv < 2500 || mv > 4600) ? 0 : (uint16_t)mv;
}

// V3.8.2: CHARGE MODE. With a wall charger the board cannot charge and run (ZED + radio) at the same time, and it
// has no pin that says "USB powered". Entered with the USER button held 8 s, or automatically when the battery
// voltage keeps rising while running (charger plugged). Everything is switched off except the USB serial port, so
// AVO Update can still install firmware (it resets the board into the ROM bootloader as always).
// Leaves with a short press of USER (restart), or when the voltage drops (charger unplugged).
static void charge_mode(const char* why) {
  Serial.printf("\n[AVO ESPALDA] MODO CARGA (%s): GPS, radio y enlace apagados. Pulsa USER para volver a funcionar.\n", why);
  esp_now_deinit();
  WiFi.mode(WIFI_OFF);
  ZED.end();
  digitalWrite(VEXT_PIN, HIGH);          // Vext off → ZED-F9P without power
  setCpuFrequencyMhz(80);
  uint16_t peak = 0;
  uint32_t last = 0, since = millis();
  while (digitalRead(PRG_PIN) == LOW) delay(10);   // wait for the button that brought us here
  for (;;) {
    if (digitalRead(PRG_PIN) == LOW) { delay(30); if (digitalRead(PRG_PIN) == LOW) { Serial.println("[AVO ESPALDA] fin del modo carga (USER)"); delay(50); ESP.restart(); } }
    if (millis() - last >= 10000) {
      last = millis();
      uint16_t mv = read_battery_mv();
      if (mv > peak) peak = mv;
      Serial.printf("[AVO ESPALDA] MODO CARGA bateria %u mV (max %u)\n", (unsigned)mv, (unsigned)peak);
      // charger unplugged: without load the voltage stays put while charging; a clear drop means no charger
      if (mv && peak && millis() - since > 120000 && mv + 120 < peak) {
        Serial.println("[AVO ESPALDA] la tension baja: cargador desconectado, vuelvo a funcionar");
        delay(50); ESP.restart();
      }
    }
    delay(20);
  }
}

// ------------------------------------------------------------------ setup / loop
void setup() {
  Serial.setTxBufferSize(4096);          // status printing must never block the GNSS/RTCM loop
  Serial.begin(115200);
  delay(300);
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);           // Vext on (harmless if the ZED has its own supply)
  pinMode(PRG_PIN, INPUT_PULLUP);
  pinMode(VBAT_CTRL_PIN, INPUT);
  delay(2);
  s_vbat_active = digitalRead(VBAT_CTRL_PIN) == HIGH ? LOW : HIGH;   // V3.8.1: board revision detection
  pinMode(VBAT_CTRL_PIN, OUTPUT);
  digitalWrite(VBAT_CTRL_PIN, !s_vbat_active);
  analogSetPinAttenuation(VBAT_PIN, ADC_11db);
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
  uint8_t girth_mac[6];   // V3.10.0: girth unit paired before (none: the first one that says HELLO is accepted)
  bool have_girth = prefs.getBytes("girth", girth_mac, 6) == 6;
  core->begin(stored, have_girth ? girth_mac : nullptr);
  s_vbat_mv = read_battery_mv();
  core->set_battery_mv(s_vbat_mv);
  Serial.printf("[AVO ESPALDA] bateria %u mV (ADC_Ctrl activo %s → placa %s)\n", (unsigned)s_vbat_mv,
                s_vbat_active == HIGH ? "HIGH" : "LOW", s_vbat_active == HIGH ? "V3.2" : "V3/V3.1");
  char pm[18] = "-";
  if (stored.valid) now_mac_str(stored.mac, pm);
  // the version is printed from the AVO-BACK marker itself, so the linker can never drop it
  const char* volatile id = AVO_BACK_IMAGE_ID;
  Serial.printf("\nAVO BACK %s — Heltec %s, ESP-NOW canal %u, pecho emparejado: %s\n", id + 1, s_dev_id,
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
  static bool prg_paired = false;
  if (digitalRead(PRG_PIN) == LOW) {
    if (!prg_t) prg_t = millis() | 1;
    uint32_t held = millis() - prg_t;
    if (held > 3000 && !prg_paired) {
      core->open_pairing();
      Serial.println("[AVO ESPALDA] emparejamiento abierto 120 s: pide 'Emparejar espalda' desde la app o reinicia el pecho sin pareja");
      Serial.println("[AVO ESPALDA] (sigue pulsando hasta 8 s para el MODO CARGA)");
      prg_paired = true;
    }
    if (held > 8000) charge_mode("boton USER 8 s");   // V3.8.2
  } else {
    prg_t = 0;
    prg_paired = false;
  }

  static uint32_t last_batt = 0;   // V3.8.1: battery every 5 s, smoothed
  if (millis() - last_batt >= 5000) {
    last_batt = millis();
    uint16_t mv = read_battery_mv();
    s_vbat_mv = (mv == 0 || s_vbat_mv == 0) ? mv : (uint16_t)((s_vbat_mv * 3u + mv) / 4u);
    core->set_battery_mv(s_vbat_mv);
    // V3.8.2: charger plugged while running → the voltage keeps rising under load. Window of 3 min: rise >= 60 mV
    // with every step non-decreasing (a load drop gives one jump, not a steady climb) → charge mode.
    static uint16_t hist[36];
    static uint8_t nh = 0;
    if (s_vbat_mv) {
      if (nh < 36) hist[nh++] = s_vbat_mv; else { memmove(hist, hist + 1, sizeof(hist) - sizeof(hist[0])); hist[35] = s_vbat_mv; }
      if (nh == 36 && hist[35] >= hist[0] + 60 && millis() > 300000) {
        int ups = 0, downs = 0;
        for (int i = 1; i < 36; i++) { if (hist[i] > hist[i - 1]) ups++; else if (hist[i] + 5 < hist[i - 1]) downs++; }
        if (ups >= 18 && downs == 0) charge_mode("tension subiendo: cargador conectado");
      }
    } else nh = 0;
  }
  static uint32_t last_print = 0;
  if (millis() - last_print >= 2000) { last_print = millis(); print_status(); }
  if (!worked) delay(1);                 // only sleep when there was nothing to do
}
