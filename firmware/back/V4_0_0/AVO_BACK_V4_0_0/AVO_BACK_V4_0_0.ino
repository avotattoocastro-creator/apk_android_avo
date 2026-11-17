/* AVO PERFORMANCE HORSE — BACK V4.0.0-dev2 · placa propia AVO BACK V4 REV B (ESP32-S3-MINI-1U-N8) + URTK1.2 (ZED-F9P)
 *
 * Parte de BACK 3.11.0 (Heltec Wireless Stick Lite V3). El núcleo (lib/avo_core: enlace ESP-NOW con el pecho,
 * emparejamiento, ZED/UBX, RTCM, calidad GNSS, cincha) NO cambia: el pecho y la cincha ven la espalda igual.
 * Cambia la capa de hardware:
 *   - ZED en UART2 (GPIO7 RX / GPIO8 TX) con su propio regulador RT9080 (EN = GPIO10): 0 V al dormir.
 *     UART1 del ZED cableada a GPIO5/GPIO6 (reservada para el registro RAW a alta velocidad, sin usar todavía).
 *   - REV B: sin Qi ni sensor de soporte. El soporte del chaleco puentea los contactos SYS y BAT del fondo: la placa
 *     solo tiene alimentación en el chaleco (o por el USB-C del taller). Quitar la cápsula = apagado total (0 µA).
 *   - Emparejamiento sin botón: 3 encendidos seguidos de menos de 4 s cada uno (poner y quitar la cápsula del
 *     soporte 3 veces), o la orden PAIR por USB. El contador vive en la NVS.
 *   - Cargador BQ24072 (solo USB del taller): PGOOD (GPIO38) y CHG (GPIO39) se muestran en el monitor.
 *   - microSD (SDMMC 4 bits, alimentación por GPIO21): registro continuo del flujo UBX del ZED en /AVO_xxxxxx.ubx
 *     desde una tarea propia (el bucle GNSS/RTCM nunca espera a la tarjeta). El fichero se vacía cada segundo: al
 *     quitar la cápsula se corta la corriente sin aviso y se pierde como mucho el último segundo.
 *   - PPS del ZED en GPIO4: marca de tiempo por interrupción (estadística de periodo/jitter en el monitor).
 *   - Batería por ADC (GPIO2, divisor 1:2).
 * Órdenes por el puerto USB (115200): PAIR · DORMIR · SD · ESTADO
 * Build: ../build_back_v4.sh (arduino-cli, núcleo esp32 3.3.12, ESP32S3 Dev Module, 8 MB, USB CDC al arrancar).
 * NO VERIFICADO EN HARDWARE: la placa V4 no se ha fabricado.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_idf_version.h>
#include <esp_random.h>
#include <esp_timer.h>
#include <Preferences.h>
#include <esp_sleep.h>
#include <driver/gpio.h>
#include <soc/soc_caps.h>
#include <FS.h>
#include <SD_MMC.h>
#include "avo_core.h"

using namespace avo;
using namespace avo::v4;

// Identity marker read by the AVO USB updater ("<version>\0AVO-BACK").
extern "C" const char AVO_BACK_IMAGE_ID[] __attribute__((used, aligned(4))) = "\0" AVO_FW_VERSION "\0AVO-BACK";

static const uint8_t NAV_RATE_HZ = 8;    // RTK limit of the ZED-F9P with 4 constellations
static const uint32_t CPU_MHZ = 160;
static const uint32_t ZED_DELAY_MS = 300;    // the ZED has its own regulator: no need to wait for the 3V3 rail
static TxPowerPolicy s_txp;
static int8_t s_rssi_worst = 0;
static bool s_boots_cleared = false;         // power-cycle pairing counter cleared after PowerCycleGesture::kQuickMs
static bool s_radio_on = false, s_zed_on = false, s_zed_pending = false;
static uint32_t s_zed_at = 0;
static uint16_t s_vbat_mv = 0;

HardwareSerial ZED(1);                       // S3 UART1 ↔ ZED UART2
Preferences prefs;

// ------------------------------------------------------------------ PPS
static PpsStats s_pps;
static portMUX_TYPE s_pps_mux = portMUX_INITIALIZER_UNLOCKED;
static void IRAM_ATTR on_pps() {
  uint64_t t = (uint64_t)esp_timer_get_time();
  portENTER_CRITICAL_ISR(&s_pps_mux);
  s_pps.edge(t);
  portEXIT_CRITICAL_ISR(&s_pps_mux);
}

// ------------------------------------------------------------------ microSD logger
static ByteFifo<32768> s_log;
static portMUX_TYPE s_log_mux = portMUX_INITIALIZER_UNLOCKED;
static volatile bool s_sd_ok = false;
static volatile uint32_t s_sd_bytes = 0, s_sd_errors = 0;
static char s_sd_name[24] = "-";
static bool s_sd_present_level = false;

static void log_push(const uint8_t* d, size_t n) {
  if (!s_sd_ok) return;
  portENTER_CRITICAL(&s_log_mux);
  s_log.push(d, n);
  portEXIT_CRITICAL(&s_log_mux);
}

static bool sd_start() {
  pinMode(PIN_SD_PWR_N, OUTPUT);
  digitalWrite(PIN_SD_PWR_N, LOW);           // card powered
  delay(20);
  if (!SD_MMC.setPins(PIN_SD_CLK, PIN_SD_CMD, PIN_SD_D0, PIN_SD_D1, PIN_SD_D2, PIN_SD_D3)) return false;
  if (!SD_MMC.begin("/sdcard", false, false, SDMMC_FREQ_DEFAULT, 2)) {
    digitalWrite(PIN_SD_PWR_N, HIGH);
    return false;
  }
  uint32_t n = prefs.getUInt("logn", 0) + 1;
  prefs.putUInt("logn", n);
  snprintf(s_sd_name, sizeof(s_sd_name), "/AVO_%06lu.ubx", (unsigned long)n);
  return true;
}

static void sd_stop() {
  s_sd_ok = false;
  SD_MMC.end();
  pinMode(PIN_SD_PWR_N, OUTPUT);
  digitalWrite(PIN_SD_PWR_N, HIGH);          // card off
}

static void sd_task(void*) {
  static uint8_t chunk[4096];
  File f;
  uint32_t last_flush = 0;
  for (;;) {
    if (!s_sd_ok) { if (f) f.close(); vTaskDelay(pdMS_TO_TICKS(200)); continue; }
    if (!f) {
      f = SD_MMC.open(s_sd_name, FILE_APPEND);
      if (!f) { s_sd_errors = s_sd_errors + 1; vTaskDelay(pdMS_TO_TICKS(1000)); continue; }
    }
    size_t n;
    portENTER_CRITICAL(&s_log_mux);
    n = s_log.pop(chunk, sizeof(chunk));
    portEXIT_CRITICAL(&s_log_mux);
    if (n) {
      if (f.write(chunk, n) != n) { s_sd_errors = s_sd_errors + 1; f.close(); }
      else s_sd_bytes = s_sd_bytes + n;
    }
    if (millis() - last_flush > 1000) { if (f) f.flush(); last_flush = millis(); }   // power can vanish at any time
    if (n < sizeof(chunk) / 2) vTaskDelay(pdMS_TO_TICKS(20));
  }
}

// ------------------------------------------------------------------ radio plumbing (as 3.11.0)
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

class V4Platform : public BackPlatform {
 public:
  uint32_t now_ms() override { return millis(); }
  void zed_set_baud(uint32_t b) override {
    if (!s_zed_on) return;
    ZED.flush();
    ZED.updateBaudRate(b);
    while (ZED.available()) ZED.read();
  }
  void zed_write(const uint8_t* d, size_t n) override { if (s_zed_on) ZED.write(d, n); }
  bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) override {
    const uint8_t* to = mac ? mac : kBroadcast;
    xSemaphoreTake(s_sent, 0);
    if (esp_now_send(to, d, n) != ESP_OK) return false;
    if (xSemaphoreTake(s_sent, pdMS_TO_TICKS(25)) != pdTRUE) return false;
    return s_sent_ok;
  }
  void radio_set_peer(const uint8_t mac[6]) override { ensure_peer(mac); }
  void save_peer(const NowPeerRecord& r) override {
    uint8_t b[NOW_PEER_RECORD_LEN];
    size_t n = now_peer_serialize(r, b, sizeof(b));
    if (n) prefs.putBytes("peer", b, n);
  }
  void save_girth(const uint8_t mac[6]) override { prefs.putBytes("girth", mac, 6); }
  uint32_t random32() override { return esp_random(); }
  void reboot() override { delay(50); ESP.restart(); }
};

static V4Platform platform;
static char s_dev_id[16];
static BackCore* core = nullptr;

// ------------------------------------------------------------------ helpers
static bool usb_power() { return digitalRead(PIN_CHG_PG) == LOW; }     // workshop USB-C present
static bool charging() { return digitalRead(PIN_CHG_STAT) == LOW; }
static void led(bool on) { digitalWrite(PIN_LED, on ? LOW : HIGH); }

static uint16_t read_battery_mv() {
  uint32_t acc = 0;
  for (int i = 0; i < 16; i++) acc += analogReadMilliVolts(PIN_BAT_ADC);
  return battery_mv_from_adc(acc / 16);
}

static void zed_lines_safe() {               // unpowered ZED must not be fed through its RX lines
  pinMode(PIN_S3_TX1, OUTPUT); digitalWrite(PIN_S3_TX1, LOW);
  pinMode(PIN_S3_TX2, OUTPUT); digitalWrite(PIN_S3_TX2, LOW);
  pinMode(PIN_ZED_TX1, INPUT); pinMode(PIN_ZED_TX2, INPUT);
  pinMode(PIN_ZED_RST, INPUT);
}

static void zed_power_on() {
  gpio_hold_dis((gpio_num_t)PIN_ZED_EN);
  pinMode(PIN_ZED_EN, OUTPUT);
  digitalWrite(PIN_ZED_EN, HIGH);            // RT9080 on (its soft start; the ESP32 3V3 is a separate regulator)
  delay(50);
  ZED.setRxBufferSize(8192);
  ZED.setTxBufferSize(4096);
  ZED.begin(38400, SERIAL_8N1, PIN_ZED_TX2, PIN_S3_TX2);   // RX, TX
  ZED.setRxTimeout(1);
  s_zed_on = true;
  pinMode(PIN_ZED_PPS, INPUT);
  attachInterrupt(digitalPinToInterrupt(PIN_ZED_PPS), on_pps, RISING);
  Serial.println("[AVO ESPALDA V4] ZED alimentado (RT9080, EN = GPIO10)");
}

static void zed_power_off() {
  if (s_zed_on) { detachInterrupt(digitalPinToInterrupt(PIN_ZED_PPS)); ZED.end(); s_zed_on = false; }
  s_zed_pending = false;
  zed_lines_safe();
  pinMode(PIN_ZED_EN, OUTPUT);
  digitalWrite(PIN_ZED_EN, LOW);             // 0 V on the receiver and the active antenna
}

static void radio_on() {
  if (s_radio_on) return;
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  WiFi.setSleep(false);
  esp_wifi_set_ps(WIFI_PS_NONE);
  esp_wifi_set_channel(NOW_CHANNEL_DEFAULT, WIFI_SECOND_CHAN_NONE);
  esp_wifi_set_max_tx_power(84);
  if (esp_now_init() != ESP_OK) Serial.println("[AVO ESPALDA V4] ERROR esp_now_init");
  esp_now_register_recv_cb(on_recv);
  esp_now_register_send_cb(on_sent);
  ensure_peer(kBroadcast);
  s_radio_on = true;
}

static void radio_off() {
  if (!s_radio_on) return;
  esp_now_deinit();
  WiFi.mode(WIFI_OFF);
  s_radio_on = false;
}

static void go_to_sleep(const char* why) {
  Serial.printf("\n[AVO ESPALDA V4] A DORMIR (%s): ZED sin corriente, microSD apagada, radio apagada.\n"
                "[AVO ESPALDA V4] Vuelve a arrancar al quitar y poner la cápsula en el soporte (o con RESET).\n", why);
  Serial.flush();
  radio_off();
  if (s_sd_ok) { delay(300); sd_stop(); }
  zed_power_off();
  gpio_hold_en((gpio_num_t)PIN_ZED_EN);
  gpio_hold_en((gpio_num_t)PIN_S3_TX1);
  gpio_hold_en((gpio_num_t)PIN_S3_TX2);
  pinMode(PIN_SD_PWR_N, OUTPUT); digitalWrite(PIN_SD_PWR_N, HIGH); gpio_hold_en((gpio_num_t)PIN_SD_PWR_N);
  led(false); gpio_hold_en((gpio_num_t)PIN_LED);
#if SOC_GPIO_SUPPORT_HOLD_IO_IN_DSLP && !SOC_GPIO_SUPPORT_HOLD_SINGLE_IO_IN_DSLP
  gpio_deep_sleep_hold_en();
#endif
  esp_deep_sleep_start();                                  // no wake source: a power cycle restarts the board
}

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
  Serial.printf("  RTCM: recibido del pecho=%lu B -> escrito al ZED=%lu B (tramas OK=%lu mal=%lu) | ZED aplicadas=%lu rechazadas=%lu\n",
                (unsigned long)st.rtcm_rx_bytes, (unsigned long)st.rtcm_to_zed, (unsigned long)rs.frames_ok,
                (unsigned long)rs.frames_bad_crc, (unsigned long)st.rxm_used, (unsigned long)st.rxm_failed);
  PpsStats pps;
  portENTER_CRITICAL(&s_pps_mux); pps = s_pps; portEXIT_CRITICAL(&s_pps_mux);
  Serial.printf("  PPS: %s pulsos=%lu periodo=%ld us desviacion max=%ld us\n", pps.alive(esp_timer_get_time()) ? "OK" : "sin pulsos",
                (unsigned long)pps.count, (long)pps.last_period_us, (long)pps.max_dev_us);
  Serial.printf("  ALIMENTACION: %s | bateria %u mV | %s\n", usb_power() ? "USB-C del taller" : "soporte del chaleco (SYS-BAT)",
                (unsigned)s_vbat_mv, usb_power() ? (charging() ? "cargando por USB" : "sin carga (sin bateria puenteada o llena)") : "");
  Serial.printf("  MICROSD: %s %s escritos=%lu B perdidos=%lu B errores=%lu (deteccion=%s)\n", s_sd_ok ? "GRABANDO" : "sin tarjeta",
                s_sd_name, (unsigned long)s_sd_bytes, (unsigned long)s_log.dropped(), (unsigned long)s_sd_errors,
                digitalRead(PIN_SD_CD) == (s_sd_present_level ? HIGH : LOW) ? "tarjeta" : "?");
  Serial.printf("  AHORRO: CPU %lu MHz | potencia radio %d dBm%s\n", (unsigned long)getCpuFrequencyMhz(), (int)s_txp.dbm(),
                s_txp.level() == TxPowerPolicy::kLevels - 1 ? " (maxima)" : "");
  {
    const GirthHub& g = core->girth();
    if (!g.paired()) Serial.println("  CINCHA: sin emparejar (se acepta la primera que salude)");
    else {
      char m[18]; now_mac_str(g.mac(), m);
      Serial.printf("  CINCHA: %s %s fw=%s rssi=%d dBm | paquetes=%lu perdidos=%lu IMU reenviados=%lu\n", m,
                    g.connected(millis()) ? "CONECTADA" : "sin senal", g.hello().fw, g.rssi(), (unsigned long)g.rx_packets(),
                    (unsigned long)g.lost(), (unsigned long)g.imu_forwarded());
    }
  }
  {
    const GnssQuality& q = core->quality();
    Serial.printf("  CALIDAD: sat %u/%u usados | 2a banda %u%s | C/N0 media %u | RTK FIX %lu s FLOAT %lu s\n", q.sv_used, q.sv_tracked,
                  q.sig_l2, (q.have_sig && q.sig_l2 == 0) ? " (ANTENA SOLO L1: sin RTK FIX)" : "", q.cno_mean,
                  (unsigned long)(b.fixed_ms / 1000), (unsigned long)(b.float_ms / 1000));
  }
  if (z.state() == ZedManager::NO_RESPONSE)
    Serial.println("  AVISO: el ZED no contesta a UBX. Revisa el mazo (TX2/RX2 de la URTK1.2 a los pads 5/6 de J4) y 3V3_ZED (TP9).");
}

static void handle_command(const char* c) {
  if (!strcmp(c, "PAIR")) { core->open_pairing(); Serial.println("[AVO ESPALDA V4] emparejamiento abierto 120 s"); }
  else if (!strcmp(c, "DORMIR")) go_to_sleep("orden por USB");
  else if (!strcmp(c, "SD")) Serial.printf("[AVO ESPALDA V4] microSD %s %s %lu B\n", s_sd_ok ? "ok" : "no", s_sd_name, (unsigned long)s_sd_bytes);
  else if (!strcmp(c, "ESTADO")) print_status();
  else Serial.printf("[AVO ESPALDA V4] orden desconocida '%s' (PAIR, DORMIR, SD, ESTADO)\n", c);
}

// ------------------------------------------------------------------ setup / loop
void setup() {
  Serial.setTxBufferSize(4096);
  Serial.begin(115200);
#if SOC_GPIO_SUPPORT_HOLD_IO_IN_DSLP && !SOC_GPIO_SUPPORT_HOLD_SINGLE_IO_IN_DSLP
  gpio_deep_sleep_hold_dis();
#endif
  for (int p : {PIN_ZED_EN, PIN_S3_TX1, PIN_S3_TX2, PIN_SD_PWR_N, PIN_LED}) gpio_hold_dis((gpio_num_t)p);
  zed_power_off();                           // ZED at 0 V until the 3V3 rail and the ESP32 are up
  pinMode(PIN_SD_PWR_N, OUTPUT); digitalWrite(PIN_SD_PWR_N, HIGH);
  pinMode(PIN_LED, OUTPUT); led(true);
  pinMode(PIN_CHG_PG, INPUT); pinMode(PIN_CHG_STAT, INPUT);
  pinMode(PIN_SD_CD, INPUT);
  analogSetPinAttenuation(PIN_BAT_ADC, ADC_11db);
  setCpuFrequencyMhz(CPU_MHZ);
  delay(300);
  // REV B: having power means the capsule is on the vest support (or on the workshop USB): everything starts.
  s_zed_at = millis() + ZED_DELAY_MS;
  s_zed_pending = true;

  s_rxq = xQueueCreate(48, sizeof(RxPkt));
  s_sent = xSemaphoreCreateBinary();
  radio_on();
  uint8_t mac[6];
  esp_wifi_get_mac(WIFI_IF_STA, mac);
  snprintf(s_dev_id, sizeof(s_dev_id), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

  prefs.begin("avonow", false);
  bool pair_gesture = false;
  prefs.putUChar("boots", PowerCycleGesture::on_boot(prefs.getUChar("boots", 0), &pair_gesture));
  NowPeerRecord stored;
  uint8_t b[NOW_PEER_RECORD_LEN];
  size_t n = prefs.getBytes("peer", b, sizeof(b));
  if (!now_peer_deserialize(b, n, &stored)) stored = NowPeerRecord();
  core = new BackCore(&platform, s_dev_id, NAV_RATE_HZ);
  uint8_t girth_mac[6];
  bool have_girth = prefs.getBytes("girth", girth_mac, 6) == 6;
  core->begin(stored, have_girth ? girth_mac : nullptr);
  if (pair_gesture) { core->open_pairing(); Serial.println("[AVO ESPALDA V4] 3 encendidos rápidos: emparejamiento abierto 120 s"); }
  s_vbat_mv = read_battery_mv();
  core->set_battery_mv(s_vbat_mv);

  s_sd_present_level = digitalRead(PIN_SD_CD);   // level seen at boot with a card is taken as "present"
  if (sd_start()) {
    s_sd_ok = true;
    xTaskCreatePinnedToCore(sd_task, "avo_sd", 6144, nullptr, 1, nullptr, 0);
    Serial.printf("[AVO ESPALDA V4] microSD: grabando %s\n", s_sd_name);
  } else {
    Serial.println("[AVO ESPALDA V4] microSD: sin tarjeta o no responde (la espalda funciona igual)");
  }
  char pm[18] = "-";
  if (stored.valid) now_mac_str(stored.mac, pm);
  const char* volatile id = AVO_BACK_IMAGE_ID;
  Serial.printf("\nAVO BACK %s — placa V4 %s, ESP-NOW canal %u, pecho emparejado: %s\n", id + 1, s_dev_id,
                (unsigned)NOW_CHANNEL_DEFAULT, stored.valid ? pm : "ninguno (se emparejará con el primer pecho que lo pida)");
  Serial.println("Emparejar: poner y quitar la cápsula del soporte 3 veces seguidas (menos de 4 s cada vez), u orden PAIR por USB.");
  led(false);
}

void loop() {
  bool worked = false;
  RxPkt p;
  while (xQueueReceive(s_rxq, &p, 0) == pdTRUE) {
    core->on_radio(p.mac, p.d, p.len, p.rssi);
    worked = true;
    const bool from_chest = core->paired() && memcmp(p.mac, core->peer().mac, 6) == 0;
    const bool from_girth = core->girth().paired() && memcmp(p.mac, core->girth().mac(), 6) == 0;
    if ((from_chest || from_girth) && p.rssi < 0 && (s_rssi_worst == 0 || p.rssi < s_rssi_worst)) s_rssi_worst = p.rssi;
  }
  uint8_t buf[512];
  int avail;
  if (s_zed_pending && (int32_t)(millis() - s_zed_at) >= 0) { s_zed_pending = false; zed_power_on(); }
  while (s_zed_on && (avail = ZED.available()) > 0) {
    int n = ZED.readBytes(buf, avail > (int)sizeof(buf) ? (int)sizeof(buf) : avail);
    if (n <= 0) break;
    log_push(buf, (size_t)n);                  // raw UBX stream to the microSD (never blocks)
    core->on_zed(buf, (size_t)n);
    worked = true;
  }
  core->tick();

  static String cmd;
  while (Serial.available()) {
    char ch = (char)Serial.read();
    if (ch == '\n' || ch == '\r') { if (cmd.length()) handle_command(cmd.c_str()); cmd = ""; }
    else if (cmd.length() < 32) cmd += ch;
  }

  static uint32_t last_batt = 0;
  if (millis() - last_batt >= 5000) {
    last_batt = millis();
    uint16_t mv = read_battery_mv();
    s_vbat_mv = (mv == 0 || s_vbat_mv == 0) ? mv : (uint16_t)((s_vbat_mv * 3u + mv) / 4u);
    core->set_battery_mv(s_vbat_mv);
  }
  if (!s_boots_cleared && PowerCycleGesture::should_clear(millis())) {
    s_boots_cleared = true;
    prefs.putUChar("boots", 0);                // this power-up was long: the pairing sequence starts again
  }
  static uint32_t last_txp = 0;
  if (millis() - last_txp >= 1000) {
    last_txp = millis();
    static uint32_t last_fail = 0;
    const uint32_t fail = core->stats().tx_fail;
    if (s_txp.update(millis(), core->chest_online(), s_rssi_worst, fail - last_fail)) esp_wifi_set_max_tx_power(s_txp.qdbm());
    last_fail = fail;
    s_rssi_worst = 0;
    led(core->pairing_open() ? true : (core->chest_online() ? ((millis() / 1000) % 4 == 0) : ((millis() / 1000) & 1)));
  }
  static uint32_t last_print = 0;
  if (millis() - last_print >= 2000) { last_print = millis(); print_status(); }
  if (!worked) delay(1);
}
