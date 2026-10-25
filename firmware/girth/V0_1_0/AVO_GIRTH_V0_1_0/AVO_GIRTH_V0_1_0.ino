/* AVO PERFORMANCE HORSE — GIRTH (cincha) V0.1.0 · ESP32-C6 (XIAO ESP32-C6 format board)
 *
 * First version: radio link only. The girth unit talks ESP-NOW to the back (Heltec, BACK 3.10.0+),
 * which forwards its data to the chest. No IMU is wired yet: the unit reports "0 IMUs" and sends no
 * IMU samples (nothing is simulated). Protocol: lib/avo_core/src/avo_girth_link.h (shared with the back).
 *
 *  - Pairing: broadcasts HELLO every second until a back answers WELCOME, then stores the back MAC
 *    (NVS) and talks unicast. The back accepts the first girth it sees; to replace a girth, hold
 *    USER/PRG 3 s on the back. BOOT held 5 s here forgets the back.
 *  - STATUS every second (uptime, IMUs, radio counters); the back answers PING every second.
 *  - Link lost (no PING for 5 s): HELLO again (unicast first, broadcast if that fails).
 *  - LED (GPIO15, active low): fast blink = looking for the back, short flash every 2 s = linked.
 *  - USB serial monitor (AVO Update): "[AVO CINCHA]" lines every 2 s.
 * Installed with AVO Update (full image the first time: bootloader + partitions + app).
 */
#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_idf_version.h>
#include <esp_random.h>
#include <Preferences.h>
#include "avo_girth_link.h"
#include "avo_espnow_link.h"

using namespace avo;

#define AVO_GIRTH_VERSION "0.1.0"
// Identity marker read by AVO Update ("0.1.0" followed by "AVO-GIRTH"): never installed on chest or back.
extern "C" const char AVO_GIRTH_IMAGE_ID[] __attribute__((used, aligned(4))) = "\0" AVO_GIRTH_VERSION "\0AVO-GIRTH";

static const int AVO_LED_PIN = 15;     // XIAO ESP32-C6 user LED (active low)
static const int AVO_BOOT_PIN = 9;     // BOOT button (active low)
static const uint8_t kBroadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

Preferences prefs;
struct RxPkt { uint8_t mac[6]; int8_t rssi; uint8_t len; uint8_t d[GIRTH_MAX_PACKET]; };
static QueueHandle_t s_rxq = nullptr;
static SemaphoreHandle_t s_sent = nullptr;
static volatile bool s_sent_ok = false;

static char s_dev_id[16];
static uint32_t s_boot_id = 0, s_seq = 0;
static bool s_paired = false;
static uint8_t s_back[6] = {0};
static uint32_t s_last_ping_ms = 0, s_last_hello_ms = 0, s_last_status_ms = 0;
static GirthStatus s_st;
static GirthPing s_ping;
static char s_back_fw[16] = "?";

#if ESP_IDF_VERSION_MAJOR >= 5
static void on_recv(const esp_now_recv_info_t* info, const uint8_t* d, int n) {
  const uint8_t* mac = info->src_addr;
  int8_t rssi = info->rx_ctrl ? (int8_t)info->rx_ctrl->rssi : 0;
#else
static void on_recv(const uint8_t* mac, const uint8_t* d, int n) {
  int8_t rssi = 0;
#endif
  if (n < (int)GIRTH_HDR || n > (int)GIRTH_MAX_PACKET || !s_rxq) return;
  if (d[0] != GIRTH_MAGIC0 || d[1] != GIRTH_MAGIC1) return;   // chest<->back traffic on the same channel
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
  m.hw = 1;               // ESP32-C6
  m.imu_count = 0;        // V0.1.0: no IMU wired yet
  uint8_t b[GIRTH_HELLO_LEN];
  size_t bl = girth_hello_encode(m, b, sizeof(b));
  send_kind(GirthKind::HELLO, broadcast ? kBroadcast : s_back, b, bl, broadcast ? 1 : 2);
}

static void send_status() {
  s_st.uptime_ms = millis();
  s_st.batt_mv = 0;       // battery not measured on this board yet
  s_st.imu_mask = 0;
  s_st.imu_count = 0;
  uint8_t b[GIRTH_STATUS_LEN];
  size_t bl = girth_status_encode(s_st, b, sizeof(b));
  send_kind(GirthKind::STATUS, s_back, b, bl, 3);
}

static bool linked() { return s_paired && s_last_ping_ms && millis() - s_last_ping_ms < 5000; }

static void handle(const RxPkt& p) {
  GirthHeader h;
  const uint8_t* body;
  if (!girth_parse(p.d, p.len, &h, &body)) return;
  bool from_back = s_paired && memcmp(p.mac, s_back, 6) == 0;
  if (h.kind == GirthKind::WELCOME) {
    GirthHello w;
    if (!girth_hello_decode(body, h.body_len, &w)) return;
    if (s_paired && !from_back) return;           // only the stored back (BOOT 5 s forgets it)
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
  }
}

static void forget_back() {
  prefs.remove("back");
  s_paired = false;
  memset(s_back, 0, sizeof(s_back));
  s_last_ping_ms = 0;
  Serial.println("[AVO CINCHA] espalda olvidada: buscando una nueva (HELLO por difusion)");
}

void setup() {
  Serial.begin(115200);
  delay(300);
  pinMode(AVO_LED_PIN, OUTPUT);
  digitalWrite(AVO_LED_PIN, HIGH);
  pinMode(AVO_BOOT_PIN, INPUT_PULLUP);
  s_rxq = xQueueCreate(16, sizeof(RxPkt));
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
  const char* volatile id = AVO_GIRTH_IMAGE_ID;   // keeps the marker in the image
  char bm[18] = "-";
  if (s_paired) now_mac_str(s_back, bm);
  Serial.printf("\n[AVO] AVO-GIRTH %s ready — ESP32-C6 %s, ESP-NOW canal %u, espalda: %s, IMUs: 0 (sin conectar)\n",
                id + 1, s_dev_id, (unsigned)NOW_CHANNEL_DEFAULT, s_paired ? bm : "ninguna (buscando)");
}

void loop() {
  RxPkt p;
  while (xQueueReceive(s_rxq, &p, 0) == pdTRUE) handle(p);
  uint32_t now = millis();

  if (!linked() && now - s_last_hello_ms >= 1000) {
    s_last_hello_ms = now;
    // stored back: try unicast first (MAC ACK proves it is there), broadcast every other time
    static bool alt = false;
    alt = !alt;
    send_hello(!s_paired || alt);
  }
  if (linked() && now - s_last_status_ms >= 1000) { s_last_status_ms = now; send_status(); }

  // BOOT held 5 s -> forget the back
  static uint32_t boot_t = 0;
  if (digitalRead(AVO_BOOT_PIN) == LOW) {
    if (!boot_t) boot_t = now | 1;
    else if (boot_t != 2 && now - boot_t > 5000) { forget_back(); boot_t = 2; }
  } else boot_t = 0;

  // LED: fast blink while searching, short flash every 2 s when linked
  bool on = linked() ? (now % 2000) < 60 : (now % 300) < 150;
  digitalWrite(AVO_LED_PIN, on ? LOW : HIGH);

  static uint32_t last_print = 0;
  if (now - last_print >= 2000) {
    last_print = now;
    char bm[18] = "-";
    if (s_paired) now_mac_str(s_back, bm);
    Serial.printf("[AVO CINCHA %s] espalda=%s %s fw=%s | rssi espalda=%d dBm | envios ok=%lu fallo=%lu | pings=%lu | la espalda ve: rssi=%d perdidos=%lu | IMUs=0\n",
                  AVO_GIRTH_VERSION, bm, linked() ? "CONECTADA" : (s_paired ? "sin senal" : "buscando"), s_back_fw,
                  s_st.rssi_back, (unsigned long)s_st.tx_ok, (unsigned long)s_st.tx_fail, (unsigned long)s_st.pings_rx,
                  s_ping.rssi_girth, (unsigned long)s_ping.lost);
  }
  delay(2);
}
