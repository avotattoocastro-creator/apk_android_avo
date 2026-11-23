// AVO CASCO — espalda interna: BackCore (lib/avo_core, igual que la espalda 3.15.0) con una plataforma del casco.
#include "casco_back.h"
#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_random.h>
#include <esp_mac.h>
#include <Preferences.h>
#include <driver/gpio.h>
#include <esp_rom_gpio.h>
#include <soc/gpio_sig_map.h>
#include <atomic>
#include <esp_timer.h>
#include "freertos/FreeRTOS.h"
#include "freertos/message_buffer.h"
#include "freertos/semphr.h"
#include "freertos/task.h"
#include "esp_task_wdt.h"
#include "avo_core.h"
#include "board_pins.h"
#include "services.h"
#include "casco_imu.h"

using namespace avo;

namespace ui { void casco_ring_off(); }   // ui.cpp del casco

namespace casco_back {

const uint8_t kVirtualChest[6] = {0x02, 0xA5, 0x0C, 0x45, 0x00, 0x01};
const uint8_t kVirtualBack[6] = {0x02, 0xA5, 0x0C, 0x45, 0x00, 0x02};
static const uint8_t kBroadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
static const uint8_t NAV_RATE_HZ = 8;          // límite RTK del ZED-F9P con 4 constelaciones (como la espalda 3.15.0)
static const uint32_t ZED_ON_DELAY_MS = 1500;  // regla 4: encendido escalonado (ESP32 → microSD → ZED → anillo)

static HardwareSerial ZED(1);
static Preferences s_prefs;
static MessageBufferHandle_t s_from_chest = nullptr, s_from_air = nullptr;
static SemaphoreHandle_t s_air_sent = nullptr;
static volatile bool s_air_ok = false;
static std::atomic<uint16_t> s_batt_mv{0};
static std::atomic<uint32_t> s_drop_chest{0}, s_drop_air{0};
static volatile bool s_zed_on = false, s_parked = false, s_park_req = false, s_unpark_req = false;
static uint32_t s_pair_id = 0;
static char s_dev_id[16] = {0};
static BackCore* s_core = nullptr;
static MessageBufferHandle_t s_head_imu = nullptr;

// ---------------------------------------------------------------- PPS (GPIO7) y TIME_SYNC
static volatile int64_t s_pps_us = 0;          // esp_timer del último flanco
static volatile uint32_t s_pps_count = 0;
static volatile uint32_t s_pps_jitter_ns = 0;  // |intervalo − 1 s| del último par de flancos
static volatile bool s_pps_paired = false;     // el último flanco ya tiene su NAV-PVT
static uint32_t s_sync_ms = 0;                 // última TIME_SYNC válida (millis)
static bool s_ts_pending = false;
static TimeSync s_ts;

static void IRAM_ATTR pps_isr() {
  const int64_t t = esp_timer_get_time();
  if (s_pps_us) {
    int64_t d = t - s_pps_us - 1000000;
    if (d < 0) d = -d;
    s_pps_jitter_ns = d > 4000000 ? 0xFFFFFFFFu : (uint32_t)(d * 1000);
  }
  s_pps_us = t;
  s_pps_count = s_pps_count + 1;
  s_pps_paired = false;
}

uint8_t pps_state() {
  const int64_t last = s_pps_us;
  if (!last || esp_timer_get_time() - last > 2500000) return 0;   // sin pulso en 2,5 s
  return millis() - s_sync_ms < 3000 ? 2 : 1;
}
bool pps_locked() { return pps_state() == 2; }

// NAV-PVT recibido por BackCore (gancho del casco): el del segundo entero (iTOW múltiplo de 1000) se empareja con el
// flanco que lo precede. Por defecto el ZED-F9P alinea el pulso al segundo (TP1 a 1 Hz). Se descarta si el flanco
// tiene más de 900 ms o si el intervalo entre flancos se aleja más de 50 µs de 1 s.
static void on_pvt(const GnssSample& g, void*) {
  const int64_t now = esp_timer_get_time(), edge = s_pps_us;
  if (g.itow_ms % 1000 != 0 || !g.gnss_fix_ok() || g.fix_type < 2 || !edge || s_pps_paired) return;
  const int64_t age = now - edge;
  if (age < 0 || age > 900000) return;
  s_pps_paired = true;
  s_ts = TimeSync();
  s_ts.back_us_at_pps = (uint64_t)edge;
  s_ts.tow_ms_at_pps = g.itow_ms;
  s_ts.pps_jitter_ns = s_pps_jitter_ns;
  s_ts.pps_count = s_pps_count;
  const bool tol = s_pps_jitter_ns <= 50000;
  s_ts.flags = (uint8_t)(1 | (tol ? 4 : 0));   // b0 válida, b2 pulso en tolerancia (semana GPS y UTC: no se envían)
  if (tol) s_sync_ms = millis();
  s_ts_pending = true;
}

bool push_head_imu(const uint8_t* payload, size_t n) {
  return s_head_imu && xMessageBufferSend(s_head_imu, payload, n, 0) != 0;
}

// La pareja interna pecho ↔ espalda es fija: pair_id derivado de la MAC del chip (≠ 0), igual en los dos lados.
uint32_t pair_id() {
  if (!s_pair_id) {
    uint8_t mac[6] = {0};
    esp_read_mac(mac, ESP_MAC_WIFI_STA);
    uint32_t h = 2166136261u;   // FNV-1a
    for (uint8_t b : mac) { h ^= b; h *= 16777619u; }
    s_pair_id = h | 1u;
  }
  return s_pair_id;
}

static void ensure_air_peer(const uint8_t mac[6]) {
  if (esp_now_is_peer_exist(mac)) return;
  esp_now_peer_info_t p = {};
  memcpy(p.peer_addr, mac, 6);
  p.channel = NOW_CHANNEL_DEFAULT;
  p.ifidx = WIFI_IF_STA;
  p.encrypt = false;
  esp_now_add_peer(&p);
}

static bool is_virtual_chest(const uint8_t* mac) { return mac && memcmp(mac, kVirtualChest, 6) == 0; }

class CascoPlatform : public BackPlatform {
 public:
  uint32_t now_ms() override { return millis(); }
  void zed_set_baud(uint32_t b) override {
    if (!s_zed_on) return;
    ZED.flush();
    ZED.updateBaudRate(b);
    while (ZED.available()) ZED.read();   // bytes recibidos a la velocidad anterior
  }
  void zed_write(const uint8_t* d, size_t n) override { if (s_zed_on) ZED.write(d, n); }
  bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) override {
    if (is_virtual_chest(mac)) {   // al pecho: por memoria, entregado siempre
      uartlink::loopback_rx(kVirtualBack, -20, d, (int)n);
      return true;
    }
    const uint8_t* to = mac ? mac : kBroadcast;   // a las cinchas: radio real
    xSemaphoreTake(s_air_sent, 0);
    if (esp_now_send(to, d, n) != ESP_OK) return false;
    if (xSemaphoreTake(s_air_sent, pdMS_TO_TICKS(25)) != pdTRUE) return false;
    return s_air_ok;
  }
  void radio_set_peer(const uint8_t mac[6]) override { if (!is_virtual_chest(mac)) ensure_air_peer(mac); }
  void save_peer(const NowPeerRecord&) override {}   // pareja fija con el pecho interno
  void save_girth(const uint8_t mac[6]) override { s_prefs.putBytes("girth", mac, 6); }
  uint32_t random32() override { return esp_random(); }
  void reboot() override { delay(50); ESP.restart(); }
  // BACK_SLEEP del pecho: carga por USB sin grabar o apagado. La espalda de verdad se dormía; aquí se apaga solo el ZED.
  void request_sleep() override { s_park_req = true; }
};
static CascoPlatform s_plat;

// ---------------------------------------------------------------- ZED: encender y apagar (reglas 2 y 6 de la revisión)
static void zed_power_on() {
  gpio_hold_dis((gpio_num_t)PIN_ZED_TX);
  digitalWrite(PIN_ZED_EN, HIGH);   // RT9080: 3,3 V del ZED y de la antena activa
  delay(50);
  ZED.setRxBufferSize(8192);
  ZED.setTxBufferSize(4096);
  ZED.begin(38400, SERIAL_8N1, PIN_ZED_RX, PIN_ZED_TX);   // ZedManager busca la velocidad real y el puerto
  ZED.setRxTimeout(1);
  s_zed_on = true;
  s_parked = false;
  Serial.println("[AVO CASCO] ZED encendido (ZED_EN = 1, UART1 RX 5 / TX 6)");
}

static void zed_power_off(const char* why) {
  if (s_zed_on) ZED.flush();
  s_zed_on = false;
  // Regla 2: antes de bajar ZED_EN, las líneas hacia el ZED a 0 (si no, el ZED apagado se alimenta por su RX).
  // Directo a 0 por la matriz de GPIO, sin soltar la línea (ZED.end() podría dejarla flotando en alto un instante).
  gpio_set_level((gpio_num_t)PIN_ZED_TX, 0);
  gpio_set_direction((gpio_num_t)PIN_ZED_TX, GPIO_MODE_OUTPUT);
  esp_rom_gpio_connect_out_signal(PIN_ZED_TX, SIG_GPIO_OUT_IDX, false, false);
  gpio_set_level((gpio_num_t)PIN_ZED_TX2, 0);
  digitalWrite(PIN_ZED_EN, LOW);
  s_parked = true;
  Serial.printf("[AVO CASCO] ZED apagado: %s\n", why);
}

void power_off_peripherals() {
  ui::casco_ring_off();
  zed_power_off("apagado del casco");
  // Regla 3: líneas de la microSD en entrada antes de cortar su alimentación (la sesión ya está cerrada).
  const int sd[] = {PIN_SD_CLK, PIN_SD_CMD, PIN_SD_D0, PIN_SD_D1, PIN_SD_D2, PIN_SD_D3};
  for (int p : sd) pinMode(p, INPUT);
  digitalWrite(PIN_SD_PWR_N, HIGH);
}

void set_battery_mv(uint16_t mv) { s_batt_mv = mv; }

// ---------------------------------------------------------------- entradas
static bool put(MessageBufferHandle_t mb, const uint8_t* mac, int8_t rssi, const uint8_t* d, size_t n) {
  if (!mb || !n || n > NOW_MAX_PACKET) return false;
  uint8_t b[7 + NOW_MAX_PACKET];
  memcpy(b, mac, 6);
  b[6] = (uint8_t)rssi;
  memcpy(b + 7, d, n);
  return xMessageBufferSend(mb, b, 7 + n, 0) != 0;
}

bool to_back(const uint8_t* d, size_t n) {
  if (s_parked) s_unpark_req = true;   // el pecho vuelve a hablar (fin de la carga o grabación): ZED otra vez
  if (put(s_from_chest, kVirtualChest, -20, d, n)) return true;
  s_drop_chest++;
  return false;
}

void on_air(const uint8_t mac[6], int8_t rssi, const uint8_t* d, int n) {
  if (n > 0 && !put(s_from_air, mac, rssi, d, (size_t)n)) s_drop_air++;
}

void on_air_sent(bool ok) {
  s_air_ok = ok;
  if (s_air_sent) xSemaphoreGive(s_air_sent);
}

// ---------------------------------------------------------------- tarea
static const char* zed_state_str(ZedManager::State s) {
  switch (s) {
    case ZedManager::DETECT: return "BUSCANDO";
    case ZedManager::PROBE_PORT: return "PUERTO";
    case ZedManager::CONFIGURE: return "CONFIGURANDO";
    case ZedManager::RUNNING: return "FUNCIONANDO";
    case ZedManager::NO_RESPONSE: return "SIN RESPUESTA";
    case ZedManager::TUNE: return "AJUSTANDO";
  }
  return "?";
}

static void print_status() {
  const ZedManager& z = s_core->zed();
  const BackStats& st = s_core->stats();
  const BackStatus bs = s_core->status();
  Serial.printf("[AVO CASCO] PPS %s (%lu pulsos, jitter %lu ns) | IMU cabeza %s\n",
                pps_state() == 2 ? "ENGANCHADO" : pps_state() == 1 ? "con pulsos" : "sin pulsos", (unsigned long)s_pps_count,
                (unsigned long)s_pps_jitter_ns, casco_imu::present() ? "OK" : "sin IMU");
  Serial.printf("[AVO CASCO] ZED %s %lu bd puerto UART%u | NAV-PVT %lu | RTCM al ZED %lu B (aplicadas %lu) | "
                "cincha %s%s | bat %u mV | perdidos pecho %lu aire %lu%s\n",
                s_zed_on ? zed_state_str(z.state()) : "APAGADO", (unsigned long)z.baud(), (unsigned)z.port(),
                (unsigned long)st.nav_pvt, (unsigned long)st.rtcm_to_zed, (unsigned long)st.rxm_used,
                s_core->girth().paired() ? "emparejada" : "sin pareja", bs.girth_connected ? " y conectada" : "",
                (unsigned)s_batt_mv.load(), (unsigned long)s_drop_chest.load(), (unsigned long)s_drop_air.load(),
                s_parked ? " | ZED en reposo (carga)" : "");
}

static void task(void*) {
  esp_task_wdt_add(nullptr);
  static uint8_t buf[7 + NOW_MAX_PACKET];
  static uint8_t zb[512];
  const uint32_t t0 = millis();
  uint32_t last_print = 0;
  bool zed_started = false;
  for (;;) {
    bool worked = false;
    const uint32_t now = millis();
    if (!zed_started && now - t0 >= ZED_ON_DELAY_MS) { zed_started = true; zed_power_on(); }
    if (s_park_req) { s_park_req = false; if (s_zed_on) zed_power_off("el pecho interno lo pide (carga por USB sin grabar)"); }
    if (s_unpark_req) { s_unpark_req = false; if (zed_started && !s_zed_on) zed_power_on(); }
    size_t got;
    for (int k = 0; k < 16 && (got = xMessageBufferReceive(s_from_chest, buf, sizeof(buf), 0)) > 7; k++) {
      s_core->on_radio(buf, buf + 7, got - 7, (int8_t)buf[6]);
      worked = true;
    }
    for (int k = 0; k < 16 && (got = xMessageBufferReceive(s_from_air, buf, sizeof(buf), 0)) > 7; k++) {
      s_core->on_radio(buf, buf + 7, got - 7, (int8_t)buf[6]);
      worked = true;
    }
    int avail;
    while (s_zed_on && (avail = ZED.available()) > 0) {
      int n = ZED.readBytes(zb, avail > (int)sizeof(zb) ? (int)sizeof(zb) : avail);
      if (n <= 0) break;
      s_core->on_zed(zb, (size_t)n);
      worked = true;
    }
    s_core->set_battery_mv(s_batt_mv);
    s_core->set_pps(pps_state(), s_pps_count);
    if (s_ts_pending) {   // TIME_SYNC (24 B), fuera del callback del NAV-PVT
      s_ts_pending = false;
      uint8_t b[TIME_SYNC_V1_LEN];
      if (encode_timesync(s_ts, b, sizeof(b))) s_core->send_extra(FrameType::TIME_SYNC, b, TIME_SYNC_V1_LEN);
    }
    for (int k = 0; k < 4 && (got = xMessageBufferReceive(s_head_imu, buf, sizeof(buf), 0)) > 0; k++) {
      s_core->send_extra(FrameType::IMU_SAMPLE, buf, got);   // IMU de la cabeza: misma cola que las cinchas
      worked = true;
    }
    s_core->tick();
    if (now - last_print >= 5000) { last_print = now; print_status(); }
    esp_task_wdt_reset();
    if (!worked) vTaskDelay(1);
  }
}

bool init() {
  s_from_chest = psram_message_buffer(16384);
  s_from_air = psram_message_buffer(8192);
  s_air_sent = xSemaphoreCreateBinary();
  s_head_imu = psram_message_buffer(4096);
  if (!s_from_chest || !s_from_air || !s_air_sent || !s_head_imu) return false;
  uint8_t mac[6];
  esp_wifi_get_mac(WIFI_IF_STA, mac);
  snprintf(s_dev_id, sizeof(s_dev_id), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  s_prefs.begin("casco", false);
  uint8_t girth[6];
  const bool have_girth = s_prefs.getBytes("girth", girth, 6) == 6;
  s_core = new BackCore(&s_plat, s_dev_id, NAV_RATE_HZ);
  if (!s_core) return false;
  NowPeerRecord chest;
  chest.valid = true;
  memcpy(chest.mac, kVirtualChest, 6);
  chest.pair_id = pair_id();
  s_core->begin(chest, have_girth ? girth : nullptr);
  s_core->set_pvt_observer(on_pvt, nullptr);
  pinMode(PIN_ZED_PPS, INPUT);
  attachInterrupt(PIN_ZED_PPS, pps_isr, RISING);
  ensure_air_peer(kBroadcast);
  BaseType_t ok = xTaskCreatePinnedToCore(task, "casco_back", 8192, nullptr, 16, nullptr, 1);
  Serial.printf("[AVO CASCO] espalda interna %s (BackCore de la espalda, %u Hz) cincha %s\n", ok == pdPASS ? "OK" : "FALLO",
                (unsigned)NAV_RATE_HZ, have_girth ? "guardada" : "sin pareja");
  return ok == pdPASS;
}

}  // namespace casco_back
