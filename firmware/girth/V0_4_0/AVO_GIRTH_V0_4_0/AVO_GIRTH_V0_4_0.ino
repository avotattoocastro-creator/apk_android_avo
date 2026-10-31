/* AVO PERFORMANCE HORSE — GIRTH (cincha) V0.4.3 · XIAO ESP32-C6 + BNO085 (GY-BNO08X, I²C)
 * 0.4.3: the IMU batches declare their units (header byte 15 = 1: BNO085 Q8/Q9/Q4/Q14) so the apps can show m/s² and °/s.
 * 0.4.2: steady batch period (long-run average), serial monitor never blocks (0.4.1 lost samples), and if the
 *   stored back gives no radio ACK for 30 s while another back WELCOMEs us (it has accepted this girth), follow it.
 * 0.4.1 (first hardware test of 0.4.0: BNO085 OK, SH-2 3.2.13, ~125 Hz): the batch period comes from the real
 *   timestamps (the BNO runs at its nearest supported rate, ~125 Hz when 100 Hz is asked), the confirmed
 *   periods are printed at start, and no "GPIO isr service is not installed" message on the first start.
 *
 *
 * Built on GIRTH 0.1.0 (ESP-NOW link with the back, protocol avo_girth_link.h shared with BACK ≥ 3.10.0).
 * The 0.2.0 binary has no source in the repository, so it is not the base.
 *
 *  - IMU: own SHTP/SH-2 driver (girth_bno085.cpp + girth_sh2.cpp), task of its own driven by INT, 100 Hz:
 *    accelerometer, gyroscope, magnetometer, linear acceleration and game rotation vector (quaternion).
 *    A start only counts when the BNO answers the Product ID request and delivers samples: an I²C ACK is
 *    not enough. Failures are retried with a growing pause; nothing waits forever.
 *  - Radio (fix of the 0.2.0 behaviour): the XIAO's INTERNAL antenna is selected (GPIO3 LOW, GPIO14 LOW).
 *    0.2.0 selected the external U.FL connector (GPIO14 HIGH) with no antenna fitted.
 *  - To the back, every 100 ms: one batch fmt 0 (acc, gyro, mag; already understood by back, chest and app)
 *    and one batch fmt 1 (linear acceleration + quaternion) with the same batch number and timestamps.
 *  - Link confirmed only by the back's PING (application level, carries how many girth packets the back
 *    accepted and how many it detected as lost); a MAC ACK alone is shown as "la espalda oye pero no
 *    responde".
 *  - Battery: GPIO5 (MTDI) through a divider (planned 220 k / 220 k, ratio 2,00 — NOT verified on the
 *    board). Values outside 3,0–4,5 V are reported as "no medida" (0), never invented.
 *  - Idle mode ("reposo", OFF by default): with it ON, if GPIO6 (contact 3 of the pogo connector, pull-up)
 *    stays high 30 s (capsule out of the mount) the girth sleeps and wakes when GPIO6 goes low.
 *  - LED (GPIO15, active low): fast blink = looking for the back · 2 flashes/2 s = linked, IMU failing ·
 *    1 flash/2 s = linked and IMU running.
 *  - BOOT held 5 s: forget the back. Serial monitor (115200): status every 2 s; commands: ayuda, estado,
 *    olvidar, imu, antena int|ext, reposo on|off, bateria <ratio>.
 * Installed with AVO Update (full image: bootloader + partitions + app; partitions unchanged).
 */
#include <Arduino.h>
#include <WiFi.h>
#include <esp_now.h>
#include <esp_wifi.h>
#include <esp_idf_version.h>
#include <esp_random.h>
#include <esp_sleep.h>
#include <driver/rtc_io.h>
#include <Preferences.h>
#include "avo_girth_link.h"
#include "avo_espnow_link.h"
#include "girth_sh2.h"
#include "girth_bno085.h"

using namespace avo;

#define AVO_GIRTH_VERSION "0.4.3"
// Identity marker read by AVO Update ("0.4.3" followed by "AVO-GIRTH"): never installed on chest or back.
extern "C" const char AVO_GIRTH_IMAGE_ID[] __attribute__((used, aligned(4))) = "\0" AVO_GIRTH_VERSION "\0AVO-GIRTH";

// ---------------------------------------------------------------- pins (XIAO ESP32-C6)
static const int PIN_LED = 15;        // user LED, active low
static const int PIN_BOOT = 9;        // BOOT button, active low
static const int PIN_RF_SW = 3;       // RF switch power: LOW = on
static const int PIN_ANT_SEL = 14;    // LOW = internal ceramic antenna, HIGH = external U.FL
static const int PIN_BAT = 5;         // MTDI / A? : battery divider
static const int PIN_DET = 6;         // MTCK (LP GPIO): mount detection (pogo contact 3, bridged to GND on the mount)
static const girth::BnoPins BNO_PINS = {0, 1, 2, 21, 22, 23, 16};   // ps, rst, int, cs, add, sda, scl

static const uint32_t IMU_INTERVAL_US = 10000;   // 100 Hz
static const uint8_t kBroadcast[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};

Preferences prefs;
static girth::Bno085 bno;
static QueueHandle_t s_imuq = nullptr;

struct RxPkt { uint8_t mac[6]; int8_t rssi; uint8_t len; uint8_t d[GIRTH_MAX_PACKET]; };
static QueueHandle_t s_rxq = nullptr;
static SemaphoreHandle_t s_sent = nullptr;
static volatile bool s_sent_ok = false;

static char s_dev_id[16];
static uint32_t s_boot_id = 0, s_seq = 0;
static bool s_paired = false;
static uint8_t s_back[6] = {0};
static uint32_t s_last_ping_ms = 0, s_last_hello_ms = 0, s_last_status_ms = 0, s_last_welcome_ms = 0;
static GirthStatus s_st;
static GirthPing s_ping;
static char s_back_fw[16] = "?";
static char s_back_id[16] = "";
static uint32_t s_uni_ack = 0, s_uni_noack = 0;      // unicast to the back: MAC ACK yes / no
static uint32_t s_imu_sent_ok = 0, s_imu_unconfirmed = 0, s_imu_discard_nolink = 0;
static uint32_t s_rx_at_first_ping = 0, s_sent_at_first_ping = 0;
static bool s_have_ping_base = false;
static uint8_t s_other_back[6] = {0};
static uint32_t s_other_back_ms = 0;
static uint32_t s_stored_ack_ms = 0;          // 0.4.2: last MAC ACK from the stored back

// settings (NVS)
static bool s_ant_ext = false, s_sleep_enabled = false;
static float s_bat_ratio = 2.0f;

// ---------------------------------------------------------------- radio
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

// One transmission. Broadcasts have no MAC ACK: they only count as "sent".
static bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) {
  const bool bc = memcmp(mac, kBroadcast, 6) == 0;
  xSemaphoreTake(s_sent, 0);
  if (esp_now_send(mac, d, n) != ESP_OK) { s_st.tx_fail++; if (!bc) s_uni_noack++; return false; }
  bool done = xSemaphoreTake(s_sent, pdMS_TO_TICKS(25)) == pdTRUE;
  bool ok = done && (s_sent_ok || bc);
  if (ok) s_st.tx_ok++; else s_st.tx_fail++;
  if (!bc) { if (done && s_sent_ok) { s_uni_ack++; if (!memcmp(mac, s_back, 6)) s_stored_ack_ms = millis(); } else s_uni_noack++; }
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

static bool imu_running() { return bno.status().state == girth::BnoState::RUNNING; }

static void send_hello(bool broadcast) {
  GirthHello m;
  strncpy(m.dev_id, s_dev_id, sizeof(m.dev_id) - 1);
  strncpy(m.fw, AVO_GIRTH_VERSION, sizeof(m.fw) - 1);
  m.hw = 1;               // ESP32-C6 (XIAO)
  m.imu_count = 1;        // one BNO085
  uint8_t b[GIRTH_HELLO_LEN];
  size_t bl = girth_hello_encode(m, b, sizeof(b));
  send_kind(GirthKind::HELLO, broadcast ? kBroadcast : s_back, b, bl, broadcast ? 1 : 2);
}

// ---------------------------------------------------------------- battery
static uint16_t s_bat_mv = 0, s_bat_pin_mv = 0;
static uint8_t s_bat_pct = 0;

static uint8_t lipo_percent(uint16_t mv) {   // rough LiPo discharge curve at rest (estimate)
  static const uint16_t v[] = {3300, 3500, 3600, 3700, 3750, 3800, 3850, 3900, 4000, 4100, 4200};
  static const uint8_t p[] = {0, 5, 10, 20, 30, 40, 50, 60, 75, 90, 100};
  if (mv <= v[0]) return 0;
  for (int i = 1; i < 11; i++)
    if (mv <= v[i]) return (uint8_t)(p[i - 1] + (p[i] - p[i - 1]) * (mv - v[i - 1]) / (v[i] - v[i - 1]));
  return 100;
}

static void read_battery() {
  uint32_t acc = 0;
  for (int i = 0; i < 16; i++) acc += analogReadMilliVolts(PIN_BAT);
  s_bat_pin_mv = (uint16_t)(acc / 16);
  float mv = s_bat_pin_mv * s_bat_ratio;
  // Outside the range of a LiPo: divider not fitted, battery disconnected or wrong ratio -> not measured.
  if (mv < 3000.0f || mv > 4500.0f) { s_bat_mv = 0; s_bat_pct = 0; return; }
  s_bat_mv = (uint16_t)mv;
  s_bat_pct = lipo_percent(s_bat_mv);
}

// ---------------------------------------------------------------- link
static bool linked() { return s_paired && s_last_ping_ms && millis() - s_last_ping_ms < 5000; }

static void send_status() {
  s_st.uptime_ms = millis();
  s_st.batt_mv = s_bat_mv;
  bool run = imu_running();
  s_st.imu_mask = run ? 1 : 0;
  s_st.imu_count = 1;
  uint8_t b[GIRTH_STATUS_LEN];
  size_t bl = girth_status_encode(s_st, b, sizeof(b));
  send_kind(GirthKind::STATUS, s_back, b, bl, 3);
}

static void handle(const RxPkt& p) {
  GirthHeader h;
  const uint8_t* body;
  if (!girth_parse(p.d, p.len, &h, &body)) return;
  bool from_back = s_paired && memcmp(p.mac, s_back, 6) == 0;
  if (h.kind == GirthKind::WELCOME) {
    GirthHello w;
    if (!girth_hello_decode(body, h.body_len, &w)) return;
    if (s_paired && !from_back) {
      memcpy(s_other_back, p.mac, 6);
      s_other_back_ms = millis();
      // 0.4.2: a back only sends WELCOME to a girth it has accepted (its paired girth, or its pairing window is
      // open). If the stored back has not given a single radio ACK for 30 s, follow the back that accepted us.
      uint32_t now = millis();
      if (now > 20000 && !linked() && (!s_stored_ack_ms || now - s_stored_ack_ms > 30000)) {
        char om[18], nm[18]; now_mac_str(s_back, om); now_mac_str(p.mac, nm);
        Serial.printf("[AVO CINCHA] la espalda guardada %s no responde desde hace 30 s y la espalda %s nos ha aceptado: "
                      "se cambia a ella\n", om, nm);
        if (esp_now_is_peer_exist(s_back)) esp_now_del_peer(s_back);
        s_paired = false;
        s_have_ping_base = false;
      } else {
        return;
      }
    }
    if (!s_paired) {
      memcpy(s_back, p.mac, 6);
      s_paired = true;
      prefs.putBytes("back", s_back, 6);
      ensure_peer(s_back);
      char m[18]; now_mac_str(s_back, m);
      Serial.printf("[AVO CINCHA] emparejada con la espalda %s (%s, fw %s)\n", m, w.dev_id, w.fw);
    }
    strncpy(s_back_fw, w.fw, sizeof(s_back_fw) - 1);
    strncpy(s_back_id, w.dev_id, sizeof(s_back_id) - 1);
    s_last_welcome_ms = millis();
    s_last_ping_ms = millis();
    s_st.rssi_back = p.rssi;
    return;
  }
  if (!from_back) return;
  if (h.kind == GirthKind::PING && girth_ping_decode(body, h.body_len, &s_ping)) {
    s_last_ping_ms = millis();
    s_st.pings_rx++;
    s_st.rssi_back = p.rssi;
    if (!s_have_ping_base) { s_have_ping_base = true; s_rx_at_first_ping = s_ping.rx_packets; s_sent_at_first_ping = s_uni_ack; }
  }
}

static void forget_back() {
  prefs.remove("back");
  s_paired = false;
  memset(s_back, 0, sizeof(s_back));
  s_last_ping_ms = 0;
  s_have_ping_base = false;
  strcpy(s_back_fw, "?");
  Serial.println("[AVO CINCHA] espalda olvidada: buscando una nueva (HELLO por difusion)");
}

// ---------------------------------------------------------------- IMU batches
static girth::Sample s_batch[girth::BATCH_MAX];
static uint8_t s_batch_n = 0;
// 0.4.1: real sample period, from the timestamps (the BNO runs at its own nearest rate: ~125 Hz when 100 Hz is asked)
static float s_period_us = IMU_INTERVAL_US;
static float s_period_ref = 0;   // 0.4.2: long-run period from the IMU task (0 = not known yet)
static uint32_t s_batch_no = 0, s_batch_first_ms = 0;

static void flush_batch() {
  if (!s_batch_n) return;
  if (!linked()) { s_imu_discard_nolink += s_batch_n; s_batch_n = 0; return; }
  girth::BatchMeta m;
  // 0.4.2: the long-run period (steady); before it is known, the slow average of the timestamps
  uint32_t per = (uint32_t)((s_period_ref > 0 ? s_period_ref : s_period_us) + 0.5f);
  if (per < 1000 || per > 60000) per = IMU_INTERVAL_US;
  m.girth_id = 0; m.imu_id = 0; m.batch = ++s_batch_no; m.period_us = (uint16_t)per;
  uint8_t body[GIRTH_MAX_BODY];
  for (uint8_t fmt : {girth::FMT_9AXIS, girth::FMT_FUSED}) {
    size_t n = girth::encode_batch(fmt, m, s_batch, s_batch_n, body, sizeof(body));
    if (n && send_kind(GirthKind::IMU, s_back, body, n, 3)) { s_st.imu_batches++; s_imu_sent_ok++; }
    else s_imu_unconfirmed++;
  }
  s_batch_n = 0;
}

static void pump_imu() {
  girth::Sample s;
  while (xQueueReceive(s_imuq, &s, 0) == pdTRUE) {
    // a gap (> 1,5 periods) closes the batch: t0 + i × period must stay true for every sample
    if (s_batch_n) {
      uint32_t dt = s.t_us - s_batch[s_batch_n - 1].t_us;
      if (dt > 2000 && dt < 50000) s_period_us += 0.02f * ((float)dt - s_period_us);   // slow average of the real period
      if ((float)dt > (s_period_ref > 0 ? s_period_ref : s_period_us) * 1.5f) flush_batch();
    }
    if (!s_batch_n) s_batch_first_ms = millis();
    s_batch[s_batch_n++] = s;
    if (s_batch_n >= girth::BATCH_MAX) flush_batch();
  }
  if (s_batch_n && millis() - s_batch_first_ms > 150) flush_batch();
}

// ---------------------------------------------------------------- settings, antenna, sleep
static void apply_antenna() {
  pinMode(PIN_RF_SW, OUTPUT);
  digitalWrite(PIN_RF_SW, LOW);                     // RF switch on
  pinMode(PIN_ANT_SEL, OUTPUT);
  digitalWrite(PIN_ANT_SEL, s_ant_ext ? HIGH : LOW);
}

static void go_to_sleep() {
  Serial.println("[AVO CINCHA] fuera del soporte 30 s: a dormir (despierta al volver al soporte, GPIO6 a GND)");
  Serial.flush();
  bno.hold_in_reset();
  gpio_hold_en((gpio_num_t)BNO_PINS.rst);
  esp_now_deinit();
  esp_wifi_stop();
  digitalWrite(PIN_LED, HIGH);
  rtc_gpio_pullup_en((gpio_num_t)PIN_DET);
  rtc_gpio_pulldown_dis((gpio_num_t)PIN_DET);
  esp_deep_sleep_enable_gpio_wakeup(1ULL << PIN_DET, ESP_GPIO_WAKEUP_GPIO_LOW);
  esp_deep_sleep_start();
}

static void print_status();

static void print_help() {
  Serial.println("[AVO CINCHA] ordenes: estado | olvidar | imu (reinicia el BNO) | antena int|ext | reposo on|off | bateria <divisor, p. ej. 2.00>");
}

static void command(String c) {
  c.trim();
  c.toLowerCase();
  if (!c.length()) return;
  if (c == "ayuda" || c == "help") print_help();
  else if (c == "estado") print_status();
  else if (c == "olvidar") forget_back();
  else if (c == "imu") bno.request_restart();
  else if (c == "antena ext" || c == "antena int") {
    s_ant_ext = c.endsWith("ext"); prefs.putBool("ant_ext", s_ant_ext); apply_antenna();
    Serial.printf("[AVO CINCHA] antena %s\n", s_ant_ext ? "EXTERNA (U.FL; tiene que estar conectada)" : "INTERNA");
  } else if (c == "reposo on" || c == "reposo off") {
    s_sleep_enabled = c.endsWith("on"); prefs.putBool("sleep", s_sleep_enabled);
    Serial.printf("[AVO CINCHA] reposo %s\n", s_sleep_enabled ? "ACTIVADO (fuera del soporte 30 s -> duerme)" : "DESACTIVADO");
  } else if (c.startsWith("bateria ")) {
    float r = c.substring(8).toFloat();
    if (r >= 1.0f && r <= 5.0f) { s_bat_ratio = r; prefs.putFloat("bat_ratio", r); Serial.printf("[AVO CINCHA] divisor de bateria %.3f\n", r); }
    else Serial.println("[AVO CINCHA] divisor no valido (1.0 a 5.0)");
  } else { Serial.printf("[AVO CINCHA] orden desconocida: %s\n", c.c_str()); print_help(); }
}

static void print_status() {
  uint32_t now = millis();
  char bm[18] = "-";
  if (s_paired) now_mac_str(s_back, bm);
  girth::BnoStatus b = bno.status();
  static const char* st[] = {"APAGADA", "ARRANCANDO", "OK", "ERROR"};
  // link
  const char* link = linked() ? "CONFIRMADA" : (!s_paired ? "buscando" :
                     (s_uni_ack && now - s_last_ping_ms > 5000 ? "la espalda oye (ACK) pero no responde" : "sin senal"));
  uint32_t confirmed = s_have_ping_base ? s_ping.rx_packets - s_rx_at_first_ping : 0;
  Serial.printf("[AVO CINCHA %s] ESPALDA %s %s fw=%s | rssi %d dBm | unicast ACK %lu / sin ACK %lu | pings %lu | "
                "la espalda confirma %lu paquetes, perdidos %lu, nos oye a %d dBm | antena %s\n",
                AVO_GIRTH_VERSION, bm, link, s_back_fw, s_st.rssi_back, (unsigned long)s_uni_ack, (unsigned long)s_uni_noack,
                (unsigned long)s_st.pings_rx, (unsigned long)confirmed, (unsigned long)s_ping.lost, s_ping.rssi_girth,
                s_ant_ext ? "externa" : "interna");
  if (s_other_back_ms && now - s_other_back_ms < 10000) {
    char om[18]; now_mac_str(s_other_back, om);
    Serial.printf("[AVO CINCHA]   otra espalda %s ha respondido: se ignora (BOOT 5 s aqui para emparejar con ella)\n", om);
  }
  if (s_paired && !linked() && s_uni_ack > 0 && s_uni_noack < s_uni_ack)
    Serial.println("[AVO CINCHA]   la espalda recibe (ACK de radio) pero no da la bienvenida: probablemente esta emparejada con otra "
                   "cincha -> en la espalda manten USER/PRG 3 s para abrir el emparejamiento");
  if (s_paired && !linked() && s_uni_ack == 0 && s_uni_noack >= 6)
    Serial.println("[AVO CINCHA]   ningun ACK de la espalda guardada: apagada/dormida, fuera de alcance, otro canal o es otra espalda "
                   "(BOOT 5 s aqui la olvida y vuelve a buscar)");
  // IMU
  const girth::Sample& s = b.last;
  Serial.printf("[AVO CINCHA %s] IMU %s", AVO_GIRTH_VERSION, st[(int)b.state]);
  if (b.state == girth::BnoState::RUNNING || b.samples) {
    Serial.printf(" 0x%02X %lukHz | %.1f Hz | muestras %lu perdidas(sensor) %lu perdidas(cola) %lu | "
                  "acc %.2f %.2f %.2f m/s2 | lin %.2f %.2f %.2f m/s2 | gyro %.3f %.3f %.3f rad/s | quat %.4f %.4f %.4f %.4f | "
                  "precision acc/gyro/mag/rv %u/%u/%u/%u",
                  b.addr, (unsigned long)(b.i2c_hz / 1000), b.rate_hz, (unsigned long)b.samples, (unsigned long)b.lost,
                  (unsigned long)b.dropped_queue, s.acc[0] / 256.0f, s.acc[1] / 256.0f, s.acc[2] / 256.0f, s.lin[0] / 256.0f,
                  s.lin[1] / 256.0f, s.lin[2] / 256.0f, s.gyro[0] / 512.0f, s.gyro[1] / 512.0f, s.gyro[2] / 512.0f,
                  s.quat[0] / 16384.0f, s.quat[1] / 16384.0f, s.quat[2] / 16384.0f, s.quat[3] / 16384.0f, s.acc_status,
                  s.gyro_status, s.mag_status, s.rv_status);
  }
  Serial.printf(" | arranques %lu fallidos %lu reinicios %lu errores I2C %lu | ultimo error: %s\n", (unsigned long)b.starts,
                (unsigned long)b.start_failures, (unsigned long)b.restarts_running, (unsigned long)b.i2c_errors, b.last_error);
  Serial.printf("[AVO CINCHA %s] ENVIO IMU periodo real %.0f us | lotes ok %lu sin confirmar %lu | muestras descartadas sin enlace %lu | BATERIA %s",
                AVO_GIRTH_VERSION, s_period_ref > 0 ? s_period_ref : s_period_us, (unsigned long)s_imu_sent_ok, (unsigned long)s_imu_unconfirmed,
                (unsigned long)s_imu_discard_nolink, s_bat_mv ? "" : "no medida");
  if (s_bat_mv) Serial.printf("%u mV (~%u %%, estimado)", s_bat_mv, s_bat_pct);
  Serial.printf(" [pin GPIO5 %u mV, divisor %.2f sin verificar] | soporte %s | reposo %s\n", s_bat_pin_mv, s_bat_ratio,
                digitalRead(PIN_DET) == LOW ? "PUESTO" : "fuera/sin conectar", s_sleep_enabled ? "on" : "off");
}

// ---------------------------------------------------------------- setup / loop
void setup() {
  Serial.begin(115200);
  Serial.setTxTimeoutMs(0);   // 0.4.2: the monitor never blocks the loop (0.4.1 lost IMU samples while printing)
  delay(300);
  pinMode(PIN_LED, OUTPUT);
  digitalWrite(PIN_LED, HIGH);
  pinMode(PIN_BOOT, INPUT_PULLUP);
  gpio_hold_dis((gpio_num_t)BNO_PINS.rst);           // after deep sleep the BNO reset was held
  if (rtc_gpio_is_valid_gpio((gpio_num_t)PIN_DET)) rtc_gpio_deinit((gpio_num_t)PIN_DET);
  pinMode(PIN_DET, INPUT_PULLUP);
  analogReadResolution(12);
  analogSetPinAttenuation(PIN_BAT, ADC_11db);

  prefs.begin("avogirth", false);                    // same namespace as 0.1.0/0.2.0: the pairing is kept
  s_ant_ext = prefs.getBool("ant_ext", false);
  s_sleep_enabled = prefs.getBool("sleep", false);
  s_bat_ratio = prefs.getFloat("bat_ratio", 2.0f);
  apply_antenna();

  s_rxq = xQueueCreate(16, sizeof(RxPkt));
  s_sent = xSemaphoreCreateBinary();
  s_imuq = xQueueCreate(96, sizeof(girth::Sample));   // ~1 s at 100 Hz
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
  if (prefs.getBytes("back", s_back, 6) == 6 && memcmp(s_back, kBroadcast, 6) != 0) { s_paired = true; ensure_peer(s_back); }
  const char* volatile id = AVO_GIRTH_IMAGE_ID;     // keeps the marker in the image
  char bm[18] = "-";
  if (s_paired) now_mac_str(s_back, bm);
  Serial.printf("\n[AVO] AVO-GIRTH %s ready - XIAO ESP32-C6 %s, ESP-NOW canal %u, antena %s, espalda: %s, IMU: BNO085 I2C (SDA 23, SCL 16)\n",
                id + 1, s_dev_id, (unsigned)NOW_CHANNEL_DEFAULT, s_ant_ext ? "externa" : "interna", s_paired ? bm : "ninguna (buscando)");
  print_help();
  read_battery();
  bno.begin(BNO_PINS, IMU_INTERVAL_US, s_imuq);
}

void loop() {
  RxPkt p;
  while (xQueueReceive(s_rxq, &p, 0) == pdTRUE) handle(p);
  uint32_t now = millis();

  if (!linked() && now - s_last_hello_ms >= 1000) {
    s_last_hello_ms = now;
    // stored back: unicast (its MAC ACK proves it hears us) alternating with broadcast
    static bool alt = false;
    alt = !alt;
    send_hello(!s_paired || alt);
  }
  if (linked() && now - s_last_status_ms >= 1000) { s_last_status_ms = now; send_status(); }
  pump_imu();

  static uint32_t per_ms = 0;
  if (now - per_ms >= 1000) { per_ms = now; girth::BnoStatus bs = bno.status(); if (bs.period_us > 1000 && bs.period_us < 60000) s_period_ref = bs.period_us; }
  static uint32_t bat_ms = 0;
  if (now - bat_ms >= 10000) { bat_ms = now; read_battery(); }

  // BOOT held 5 s -> forget the back
  static uint32_t boot_t = 0;
  if (digitalRead(PIN_BOOT) == LOW) {
    if (!boot_t) boot_t = now | 1;
    else if (boot_t != 2 && now - boot_t > 5000) { forget_back(); boot_t = 2; }
  } else boot_t = 0;

  // idle mode: out of the mount for 30 s -> deep sleep (only if enabled)
  static uint32_t off_mount_since = 0;
  if (s_sleep_enabled && digitalRead(PIN_DET) == HIGH) {
    if (!off_mount_since) off_mount_since = now | 1;
    else if (now - off_mount_since > 30000) go_to_sleep();
  } else off_mount_since = 0;

  // LED
  bool run = imu_running();
  uint32_t ph = now % 2000;
  bool on = !linked() ? (now % 300) < 150 : (run ? ph < 60 : (ph < 60 || (ph > 200 && ph < 260)));
  digitalWrite(PIN_LED, on ? LOW : HIGH);

  // serial commands
  static String line;
  while (Serial.available()) {
    char c = (char)Serial.read();
    if (c == '\n' || c == '\r') { if (line.length()) command(line); line = ""; }
    else if (line.length() < 64) line += c;
  }

  static uint32_t last_print = 0;
  if (now - last_print >= 2000) { last_print = now; print_status(); }
  delay(2);
}
