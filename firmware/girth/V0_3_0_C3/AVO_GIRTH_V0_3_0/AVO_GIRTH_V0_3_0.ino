/* AVO PERFORMANCE HORSE — GIRTH (cincha) V0.3.0 · placa REV B · ESP32-C3-MINI-1U-N4
 *
 * Firmware de la placa propia de la cincha (hardware/girth/PCB, REV B). Sustituye a la V0.1.0 (XIAO ESP32-C6).
 *  - Radio: el mismo enlace ESP-NOW con la espalda (lib/avo_core/src/avo_girth_link.h): HELLO / WELCOME,
 *    STATUS cada segundo (ahora con la batería medida y la IMU), PING de la espalda, IMU en lotes de 10 muestras.
 *  - IMU: LSM6DS3TR-C (o LSM6DSV16X) + MMC5983MA por I²C, 104 (o 120) muestras/s de 9 ejes brutos, al ritmo del
 *    dato listo del LSM6 (INT1 → GPIO0); formato IMU_FMT_9AXIS_I16.
 *  - Alimentación (girth_power.h): mantiene el corte de batería con PWR_HOLD; apaga al salir del soporte (3 s),
 *    con batería baja, por orden remota de la espalda (PING bit 1) o por la orden «APAGAR» del monitor USB.
 *  - BOOT 5 s olvida la espalda. LED (activo bajo): rápido = buscando, destello cada 2 s = conectada,
 *    fijo = cargando sin radio.
 *  - Monitor USB: línea «[AVO CINCHA …]» cada 2 s; órdenes DIAG, APAGAR, OLVIDAR.
 * Nada de esto está probado en la placa: compila en el CI, el funcionamiento físico está pendiente.
 */
#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_idf_version.h>
#include <esp_random.h>
#include <esp_timer.h>
#include <Preferences.h>
#include "avo_girth_link.h"
#include "avo_espnow_link.h"
#include "avo_payloads.h"
#include "girth_board.h"
#include "girth_pack.h"
#include "girth_policy.h"
#include "girth_imu.h"
#include "girth_power.h"

using namespace avo;

#define AVO_GIRTH_VERSION "0.3.0"
// Marca de identidad ("0.3.0" seguido de "AVO-GIRTH"): solo se instala en la cincha.
extern "C" const char AVO_GIRTH_IMAGE_ID[] __attribute__((used, aligned(4))) = "\0" AVO_GIRTH_VERSION "\0AVO-GIRTH";

static const uint8_t kBroadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

Preferences prefs;
struct RxPkt { uint8_t mac[6]; int8_t rssi; uint8_t len; uint8_t d[GIRTH_MAX_PACKET]; };
struct ImuBatch { uint32_t t0_us; uint8_t count; gimu::Sample s[GIRTH_IMU_MAX_SAMPLES]; };
static QueueHandle_t s_rxq = nullptr, s_imuq = nullptr;
static SemaphoreHandle_t s_sent = nullptr;
static volatile bool s_sent_ok = false;

static char s_dev_id[16];
static uint32_t s_boot_id = 0, s_seq = 0, s_imu_seq = 0;
static bool s_paired = false, s_imu_ok = false;
static uint8_t s_back[6] = {0};
static uint32_t s_last_ping_ms = 0, s_last_hello_ms = 0, s_last_status_ms = 0;
static GirthStatus s_st;
static GirthPing s_ping;
static char s_back_fw[16] = "?";
static gpow::State s_pw;
static volatile bool s_remote_off = false;

#if ESP_IDF_VERSION_MAJOR >= 5
static void on_recv(const esp_now_recv_info_t* info, const uint8_t* d, int n) {
  const uint8_t* mac = info->src_addr;
  int8_t rssi = info->rx_ctrl ? (int8_t)info->rx_ctrl->rssi : 0;
#else
static void on_recv(const uint8_t* mac, const uint8_t* d, int n) {
  int8_t rssi = 0;
#endif
  if (n < (int)GIRTH_HDR || n > (int)GIRTH_MAX_PACKET || !s_rxq) return;
  if (d[0] != GIRTH_MAGIC0 || d[1] != GIRTH_MAGIC1) return;
  RxPkt p;
  memcpy(p.mac, mac, 6); p.rssi = rssi; p.len = (uint8_t)n; memcpy(p.d, d, (size_t)n);
  xQueueSend(s_rxq, &p, 0);
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

static bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) {
  xSemaphoreTake(s_sent, 0);
  if (esp_now_send(mac, d, n) != ESP_OK) { s_st.tx_fail++; return false; }
  bool ok = xSemaphoreTake(s_sent, pdMS_TO_TICKS(25)) == pdTRUE && (s_sent_ok || mac == kBroadcast);
  if (ok) s_st.tx_ok++; else s_st.tx_fail++;
  return ok;
}

static bool send_kind(GirthKind k, const uint8_t* to, const uint8_t* body, size_t bl, int tries) {
  GirthHeader h; h.kind = k; h.boot_id = s_boot_id; h.seq = ++s_seq;
  uint8_t pkt[GIRTH_MAX_PACKET];
  size_t n = girth_build(h, body, bl, pkt, sizeof(pkt));
  if (!n) return false;
  for (int i = 0; i < tries; i++) if (radio_send(to, pkt, n)) return true;
  return false;
}

static void send_hello(bool broadcast) {
  GirthHello m;
  strncpy(m.dev_id, s_dev_id, sizeof(m.dev_id) - 1);
  strncpy(m.fw, AVO_GIRTH_VERSION, sizeof(m.fw) - 1);
  m.hw = GIRTH_HW_C3_REVB;
  m.imu_count = 1;
  uint8_t b[GIRTH_HELLO_LEN];
  size_t bl = girth_hello_encode(m, b, sizeof(b));
  send_kind(GirthKind::HELLO, broadcast ? kBroadcast : s_back, b, bl, broadcast ? 1 : 2);
}

static void send_status() {
  s_st.uptime_ms = millis();
  s_st.batt_mv = s_pw.batt_mv;
  s_st.imu_mask = s_imu_ok ? 0x01 : 0x00;
  s_st.imu_count = s_imu_ok ? 1 : 0;
  uint8_t b[GIRTH_STATUS_LEN];
  size_t bl = girth_status_encode(s_st, b, sizeof(b));
  send_kind(GirthKind::STATUS, s_back, b, bl, 3);
}

static bool linked() { return s_paired && s_last_ping_ms && millis() - s_last_ping_ms < 5000; }

static void send_imu(const ImuBatch& bt) {
  uint8_t body[IMU_HDR_LEN + GIRTH_IMU_MAX_SAMPLES * IMU_SAMPLE_LEN_9AXIS];
  size_t n = girth_pack_imu_body(bt.s, bt.count, bt.t0_us, ++s_imu_seq, (uint16_t)gimu::period_us(), body, sizeof(body));
  if (!n) return;
  if (send_kind(GirthKind::IMU, s_back, body, n, 2)) s_st.imu_batches++;
}

// Al ritmo del LSM6 (104 o 120 Hz): su INT1 (dato listo, GPIO0) despierta la tarea; cada muestra se lee una vez.
// Lote de 10 muestras → cola → loop() lo envía si hay enlace. Si un flanco se pierde, el tiempo de espera de 50 ms
// lee igualmente (la lectura borra INT1 y vuelven los flancos).
static SemaphoreHandle_t s_drdy = nullptr;
static void IRAM_ATTR on_drdy() {
  BaseType_t woke = pdFALSE;
  xSemaphoreGiveFromISR(s_drdy, &woke);
  if (woke) portYIELD_FROM_ISR();
}
static void imu_task(void*) {
  ImuBatch bt; bt.count = 0;
  while (true) {
    xSemaphoreTake(s_drdy, pdMS_TO_TICKS(50));
    gimu::Sample s;
    if (!gimu::read(&s)) continue;
    if (bt.count == 0) bt.t0_us = (uint32_t)esp_timer_get_time();
    bt.s[bt.count++] = s;
    if (bt.count == GIRTH_IMU_MAX_SAMPLES) {
      xQueueSend(s_imuq, &bt, 0);   // si la cola está llena (sin enlace), el lote se descarta
      bt.count = 0;
    }
  }
}

static void handle(const RxPkt& p) {
  GirthHeader h;
  const uint8_t* body;
  if (!girth_parse(p.d, p.len, &h, &body)) return;
  bool from_back = s_paired && memcmp(p.mac, s_back, 6) == 0;
  if (h.kind == GirthKind::WELCOME) {
    GirthHello w;
    if (!girth_hello_decode(body, h.body_len, &w)) return;
    if (s_paired && !from_back) return;
    if (!s_paired) {
      memcpy(s_back, p.mac, 6);
      s_paired = true;
      prefs.putBytes("back", s_back, 6);
      ensure_peer(s_back);
      char m[18]; now_mac_str(s_back, m);
      Serial.printf("[AVO CINCHA] emparejada con la espalda %s (%s, fw %s)\n", m, w.dev_id, w.fw);
    }
    strncpy(s_back_fw, w.fw, sizeof(s_back_fw) - 1);
    s_last_ping_ms = millis();
    s_st.rssi_back = p.rssi;
    return;
  }
  if (!from_back) return;
  if (h.kind == GirthKind::PING && girth_ping_decode(body, h.body_len, &s_ping)) {
    s_last_ping_ms = millis();
    s_st.pings_rx++;
    s_st.rssi_back = p.rssi;
    if (s_ping.flags & GIRTH_PING_SHUTDOWN) s_remote_off = true;
  }
}

static void forget_back() {
  prefs.remove("back");
  s_paired = false;
  memset(s_back, 0, sizeof(s_back));
  s_last_ping_ms = 0;
  Serial.println("[AVO CINCHA] espalda olvidada: buscando una nueva (HELLO por difusion)");
}

static void diag() {
  uint8_t f[16];
  int n = gimu::scan(f, 16);
  Serial.printf("[AVO DIAG] I2C (SDA GPIO6, SCL GPIO2): %d dispositivos:", n);
  for (int i = 0; i < n; i++) Serial.printf(" 0x%02X", f[i]);
  Serial.println();
  const gimu::Info& in = gimu::info();
  Serial.printf("[AVO DIAG] acelerometro/giro: %s (WHO_AM_I 0x%02X) · magnetometro: %s (ID 0x%02X) · errores I2C %lu · muestras %lu\n",
                gimu::accel_name(), in.accel_whoami, in.mag ? "MMC5983MA" : "NO", in.mag_id,
                (unsigned long)in.i2c_errors, (unsigned long)in.samples);
  gimu::Sample s = gimu::last();
  Serial.printf("[AVO DIAG] ultima muestra: a=%d,%d,%d g=%d,%d,%d m=%d,%d,%d\n", s.v[0], s.v[1], s.v[2], s.v[3], s.v[4],
                s.v[5], s.v[6], s.v[7], s.v[8]);
  Serial.printf("[AVO DIAG] reed %s · 5V %s · cargando %s · Qi %s · bateria %u mV · PWR_HOLD %d · INT1 %d\n",
                s_pw.reed_closed ? "cerrado" : "abierto", s_pw.power_in ? "si" : "no", s_pw.charging ? "si" : "no",
                s_pw.qi ? "si" : "no", s_pw.batt_mv, digitalRead(gb::PIN_PWR_HOLD), digitalRead(gb::PIN_IMU_INT));
}

void setup() {
  gpow::hold();                         // lo primero: el impulso del reed solo sostiene el corte unos segundos
  pinMode(gb::PIN_LED, OUTPUT);
  digitalWrite(gb::PIN_LED, HIGH);      // apagado (activo bajo)
  pinMode(gb::PIN_BOOT, INPUT_PULLUP);
  Serial.begin(115200);
  gpow::begin();
  delay(200);
  s_pw = gpow::read();
  s_imu_ok = gimu::begin();
  s_rxq = xQueueCreate(16, sizeof(RxPkt));
  s_imuq = xQueueCreate(4, sizeof(ImuBatch));
  s_sent = xSemaphoreCreateBinary();
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  WiFi.setSleep(false);
  esp_wifi_set_ps(WIFI_PS_NONE);
  esp_wifi_set_channel(NOW_CHANNEL_DEFAULT, WIFI_SECOND_CHAN_NONE);
  esp_wifi_set_max_tx_power(84);
  if (esp_now_init() != ESP_OK) Serial.println("[AVO CINCHA] ERROR esp_now_init");
  esp_now_register_recv_cb(on_recv);
  esp_now_register_send_cb(on_sent);
  ensure_peer(kBroadcast);
  uint8_t mac[6];
  esp_wifi_get_mac(WIFI_IF_STA, mac);
  snprintf(s_dev_id, sizeof(s_dev_id), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  s_boot_id = esp_random() | 1u;
  prefs.begin("avogirth", false);
  if (prefs.getBytes("back", s_back, 6) == 6 && memcmp(s_back, kBroadcast, 6) != 0) { s_paired = true; ensure_peer(s_back); }
  if (s_imu_ok) {
    s_drdy = xSemaphoreCreateBinary();
    attachInterrupt(gb::PIN_IMU_INT, on_drdy, RISING);
    xTaskCreate(imu_task, "imu", 4096, nullptr, 5, nullptr);
  }
  const char* volatile id = AVO_GIRTH_IMAGE_ID;
  char bm[18] = "-";
  if (s_paired) now_mac_str(s_back, bm);
  Serial.printf("\n[AVO] AVO-GIRTH %s ready — ESP32-C3 REV B %s, ESP-NOW canal %u, espalda: %s, IMU: %s + %s, "
                "bateria %u mV, arranque: %s\n",
                id + 1, s_dev_id, (unsigned)NOW_CHANNEL_DEFAULT, s_paired ? bm : "ninguna (buscando)",
                gimu::accel_name(), gimu::info().mag ? "MMC5983MA" : "sin magnetometro", s_pw.batt_mv,
                gpow::boot_reason());
}

void loop() {
  RxPkt p;
  while (xQueueReceive(s_rxq, &p, 0) == pdTRUE) handle(p);
  uint32_t now = millis();

  // --- alimentación
  static uint32_t last_pw = 0;
  static gpol::Policy pol;
  if (now - last_pw >= 200 || s_remote_off) {
    last_pw = now;
    s_pw = gpow::read();
    gpol::Inputs in{s_pw.reed_closed, s_pw.power_in, s_pw.qi, s_pw.batt_mv, s_remote_off};
    switch (pol.step(in, now)) {
      case gpol::Action::SHUTDOWN_OUT_OF_HOLDER: gpow::shutdown("fuera del soporte");
      case gpol::Action::SHUTDOWN_LOW_BATTERY: gpow::shutdown("bateria baja");
      case gpol::Action::SLEEP_ON_CHARGER: gpow::sleep_on_charger();
      case gpol::Action::SHUTDOWN_REMOTE: gpow::shutdown("orden remota");
      case gpol::Action::NONE: break;
    }
  }

  // --- radio
  if (!linked() && now - s_last_hello_ms >= 1000) {
    s_last_hello_ms = now;
    static bool alt = false;
    alt = !alt;
    send_hello(!s_paired || alt);
  }
  if (linked() && now - s_last_status_ms >= 1000) { s_last_status_ms = now; send_status(); }
  ImuBatch bt;
  while (xQueueReceive(s_imuq, &bt, 0) == pdTRUE)
    if (linked()) send_imu(bt);

  // --- BOOT 5 s → olvidar la espalda
  static uint32_t boot_t = 0;
  if (digitalRead(gb::PIN_BOOT) == LOW) {
    if (!boot_t) boot_t = now ? now : 1;
    else if (boot_t != 2 && now - boot_t > 5000) { forget_back(); boot_t = 2; }
  } else boot_t = 0;

  // --- LED (activo bajo)
  bool on = s_pw.power_in && !linked() ? true : (linked() ? (now % 2000) < 60 : (now % 300) < 150);
  digitalWrite(gb::PIN_LED, on ? LOW : HIGH);

  // --- monitor USB
  if (Serial.available()) {
    static char line[24]; static uint8_t ln = 0;
    while (Serial.available()) {
      char c = (char)Serial.read();
      if (c == '\n' || c == '\r') {
        line[ln] = 0;
        if (!strcmp(line, "DIAG")) diag();
        else if (!strcmp(line, "APAGAR")) gpow::shutdown("orden APAGAR por USB");
        else if (!strcmp(line, "OLVIDAR")) forget_back();
        ln = 0;
      } else if (ln < sizeof(line) - 1) line[ln++] = c;
    }
  }
  static uint32_t last_print = 0;
  if (now - last_print >= 2000) {
    last_print = now;
    char bm[18] = "-";
    if (s_paired) now_mac_str(s_back, bm);
    Serial.printf("[AVO CINCHA %s] espalda=%s %s fw=%s | rssi=%d dBm | envios ok=%lu fallo=%lu | pings=%lu | IMU %s lotes=%lu"
                  " | bat %u mV%s%s | reed %s\n",
                  AVO_GIRTH_VERSION, bm, linked() ? "CONECTADA" : (s_paired ? "sin senal" : "buscando"), s_back_fw,
                  s_st.rssi_back, (unsigned long)s_st.tx_ok, (unsigned long)s_st.tx_fail, (unsigned long)s_st.pings_rx,
                  s_imu_ok ? gimu::accel_name() : "NO", (unsigned long)s_st.imu_batches, s_pw.batt_mv,
                  s_pw.power_in ? (s_pw.qi ? " · Qi" : " · USB") : "", s_pw.charging ? " cargando" : "",
                  s_pw.reed_closed ? "cerrado" : "abierto");
  }
  delay(2);
}
