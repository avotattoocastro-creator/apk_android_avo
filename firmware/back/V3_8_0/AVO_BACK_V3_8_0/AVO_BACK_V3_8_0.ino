/* AVO PERFORMANCE HORSE — BACK V3.13.11 (ESP-NOW) · V3.13.11: REAL Pololu shutdown on USB (AVO_USB_AUTO_OFF 1): GPIO20 read with an own ADC2 oneshot unit (failed reads = invalid, never 0 V), USB confirmed with >100 mV for 2 s → ZED UART stopped, GPIO33 high impedance, GPIO34 OUTPUT LOW, radio off, awake low-power charging loop (no deep sleep) that keeps SHDN LOW; <50 mV for 2 s → GPIO34 released, 1.5 s, clean restart (UART1 RX35/TX33, GNSS, ESP-NOW) · V3.13.10: USB DIAGNOSTIC by thresholds on GPIO20 (ADC, >100 mV connected, <50 mV disconnected, hysteresis, 2 s confirmation), GPIO7 (ADC1) measured alongside; automatic GPS shutdown DISABLED (AVO_USB_AUTO_OFF 0): transitions are only logged · V3.13.9: Pololu (VIN on the Heltec 3V3) enabled by leaving GPIO34 in high impedance (its own pull-up), disabled with GPIO34 OUTPUT LOW; never driven HIGH. USB confirmed on GPIO20 (2 s of HIGH readings) → GNSS and RTCM stop, GPIO34 LOW, deep sleep while charging; USB removed → GPIO34 released, UART1 RX35/TX33 restarted, times to first UBX / NAV-PVT logged · V3.13.8: GPS UART PIN FIX: UART1 RX=GPIO35 (green wire, ZED TX) and TX=GPIO33 (white wire, ZED RX) per the confirmed wiring; GPIO35 never driven (no LED use, not held LOW while asleep); USB sensed only by GPIO20 as a filtered digital input (no ADC2); monitor lines GNSS bytes/UBX/NMEA/NAV-PVT/estado · V3.13.7: GNSS recovery: fixed pins RX=GPIO33 TX=GPIO35 (no automatic swap), clean power cycle of the ZED through GPIO34 at start-up, passive listening at every baud rate before any command, ESP-NOW started after that diagnosis, no UBX-RXM-PMREQ before sleeping (the Pololu cuts the power), GNSS bytes/s, UBX, NMEA, NAV-PVT and GPIO34 in the monitor · V3.13.6: ZED UART pins swapped automatically (GPIO33/35) when nothing arrives from the ZED for 10 s; the working order is kept in NVS · V3.13.5: USB divider found on any free pin of the 5V row (GPIO20, 18, 21, 19, 47, 48; GPIO20 read 0.17 V = not wired there on the user's board) and the level of every candidate printed at start-up · V3.13.4: GPIO20 also read with the ADC, USB = more than 1.0 V (the digital input needs ~2.5 V and read LOW on the user's board); a failed ADC read (radio busy) is ignored · V3.13.3: low-battery cut-off (below 3.30 V at rest, before the radio starts: deep sleep, ZED off, retried every 60 s, back above 3.45 V; the user's board was at 2.95 V and reset by brown-out every time Wi-Fi started); USB sensed ONLY on GPIO20 (digital, pull-down); the GPIO7 ADC reading floated when nothing was wired there (analogRead drops the pull-down) and woke / slept the board at random; GPIO20 no longer held during sleep · V3.13.2: USB sense also on GPIO20 (next to the 5V pin; digital, divider 10k/22k), GPIO7 kept · V3.13.1: USB charging sleep checked with the ADC every 3 s (timer wake-up) instead of a GPIO level wake-up (woke after 1 s on the user's board); reset and wake-up reasons printed · V3.13.0: Pololu S7V8F3 SHDN on GPIO34 (between the ZED TX and RX pins of the header); USB charging: with USB 5 V present (divider 5V→GPIO7) everything sleeps and only the battery charges, unplugging wakes it · V3.12.0: pogo contacts (prototype Rev E + Heltec): no Qi, no reed; the vest support bridges the SYS and BAT contacts, so the board only has power on the vest; pairing = 3 quick power-ups (or PRG 3 s) · V3.11.0: ZED powered by a Pololu S7V8F3 from the battery, SHDN on GPIO6 (0 V asleep), reed sleep back on · V3.10.9: reed switch disabled (never sleeps), ZED woken at start-up (UART + EXTINT) · V3.10.8: ZED also woken through its UART RX line (no INT wire needed), line held LOW from the last byte of the backup order · V3.10.7: ZED to software backup (UBX-RXM-PMREQ) while asleep, woken through EXTINT · V3.10.6: white LED (GPIO35) held off while asleep, ZED powered 1 s after start-up · V3.10.5: ZED powered 10 s after start-up (test) · V3.10.4: soft start of Vext (no 3V3 dip when the ZED switches on) · V3.10.3: on/off with the reed of the support (deep sleep, ZED on Vext cut) · V3.10.2: battery saving (CPU 160 MHz, LoRa radio asleep, adaptive ESP-NOW power) · V3.10.0: girth unit (ESP32-C6) hub · V3.9.0: GNSS quality (NAV-SAT/SIG), RTK FIX tracking · V3.8.2: charge mode · V3.8.1: battery voltage sent to the chest
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
 *   V3.13.8 wiring: Heltec GPIO35 (RX) <- ZED TX (green wire) · Heltec GPIO33 (TX) -> ZED RX (white wire) · GPIO34 -> Pololu SHDN (yellow)
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
#include <SPI.h>
#include <esp_sleep.h>
#include <driver/gpio.h>
#include <driver/rtc_io.h>
#include <soc/soc_caps.h>
#include <soc/usb_serial_jtag_reg.h>
#include <soc/gpio_sig_map.h>
#include <esp_rom_gpio.h>
#include <esp_adc/adc_oneshot.h>   // V3.13.11: own ADC2 unit for GPIO20 (error codes)
#include <esp_adc/adc_cali.h>
#include <esp_adc/adc_cali_scheme.h>
#include "avo_core.h"

using namespace avo;

// Identity marker read by the AVO USB updater ("3.8.0" followed by "AVO-BACK"): the app shows
// "AVO-BACK 3.8.0" and refuses to install a back firmware on the chest or a chest firmware on the back.
extern "C" const char AVO_BACK_IMAGE_ID[] __attribute__((used, aligned(4))) = "\0" AVO_FW_VERSION "\0AVO-BACK";

// ------------------------------------------------------------------ hardware
// V3.13.8: physical wiring confirmed by the user (cable colours): white = ZED RX -> GPIO33, green = ZED TX -> GPIO35,
// yellow = Pololu SHDN -> GPIO34. So UART1 is RX=GPIO35, TX=GPIO33 (3.13.7 had them the other way round). GPIO35 is
// also the white LED of the Heltec (LED + resistor to GND): it is now only an input of UART1 — the firmware never sets
// it as OUTPUT, never writes it and never holds it; the LED simply follows the ZED's TX line (lit while it idles HIGH).
// No automatic swap.
static const int ZED_RX_PIN = 35;      // Heltec RX  <- ZED TX (green)
static const int ZED_TX_PIN = 33;      // Heltec TX  -> ZED RX (white)
static uint32_t s_zed_bytes = 0, s_zed_on_at = 0;   // bytes received from the ZED since it was powered
static bool s_zed_pwr_req = false;     // V3.13.7: GPIO34 driven HIGH = power REQUESTED (the voltage is not measured)
static uint32_t s_diag_baud = 0;       // V3.13.7: baud rate where the passive listening heard the ZED (0 = nothing)
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
// V3.13.3: low-battery cut-off (protects the LiPo and avoids the brown-out loop when the radio starts)
static const uint16_t LOW_BATT_MV = 3300, LOW_BATT_RESUME_MV = 3450;
static const uint32_t LOW_BATT_POLL_S = 60;
RTC_DATA_ATTR static bool s_low_batt = false;
static uint32_t s_sleep_s = 3;            // timer of the next deep sleep
static const uint8_t NAV_RATE_HZ = 8;  // RTK limit of the ZED-F9P with 4 constellations
// V3.10.2: battery saving. The SX1262 LoRa radio of the Heltec is not used; after power-up it sits in standby
// (~0.6 mA) until told to sleep. Heltec Wireless Stick Lite V3 pins.
static const int LORA_NSS = 8, LORA_SCK = 9, LORA_MOSI = 10, LORA_MISO = 11, LORA_RST = 12, LORA_BUSY = 13;
static const uint32_t CPU_MHZ = 160;   // was 240: UART, ESP-NOW and the GNSS/RTCM loop have ample headroom at 160
static TxPowerPolicy s_txp;            // adaptive ESP-NOW transmit power (lib/avo_core/src/avo_tx_power.*)
static int8_t s_rssi_worst = 0;        // worst RSSI from the chest/girth in the current second (0 = none)
static bool s_lora_asleep = false;
// V3.10.3: on/off. Reed of the support between GPIO7 and GND (internal pull-up): closed = running, open 3 s = deep
// sleep with Vext cut (the ZED-F9P must be powered from Vext, not from the fixed 3V3). Wakes when the reed closes.
static const int REED_PIN = 7;
// V3.10.9: reed switch OFF (user request: behaves like 3.10.2, never sleeps). 1 = sleep when the reed opens (3.10.3–3.10.8).
#define AVO_REED_SLEEP 0   // V3.12.0: no reed any more (pogo contacts: off the vest support the board has no power)
// V3.12.0: pairing without opening the capsule: three power-ups in a row, each shorter than QUICK_BOOT_MS (put the
// capsule on the vest support and take it off three times). Counter in NVS ("boots"), cleared after QUICK_BOOT_MS.
static const uint32_t QUICK_BOOT_MS = 4000;
static bool s_boots_cleared = false;
static ReedGate s_reed;
static bool s_radio_on = false, s_zed_on = false;
// V3.10.5 (test requested on 28/10): Vext (ZED-F9P) switched on VEXT_DELAY_MS after start-up / wake-up, once the board,
// the radio and the link are running, as when the user connects the Ve wire by hand (that works).
static const uint32_t VEXT_DELAY_MS = 1000;
// V3.10.7: with the ZED on the fixed 3V3 (Vext gives a reset loop at power-up on this board) the ZED is put into
// software backup with UBX-RXM-PMREQ before the Heltec sleeps, and woken with a pulse on its EXTINT pin ("INT" on the
// URTK1.2 board) wired to GPIO6. The line idles HIGH and is held HIGH during deep sleep (no edge → no false wake).
// V3.11.0: GPIO6 = SHDN of the Pololu S7V8F3 that powers the ZED from the battery (HIGH = ZED on, LOW = 0 V).
// It replaces the INT wire of 3.10.7 (the ZED INT pin must NOT be wired to GPIO6 any more).
// V3.13.0: SHDN of the Pololu moved to GPIO34: header pin 7 of the row Ve·GND·12·RX·TX·33·34·35·36…, between the ZED
// wires on GPIO33 and GPIO35 (checked against the Heltec pin list). Not an RTC pin: held LOW in deep sleep with
// gpio_hold_en + gpio_deep_sleep_hold_en (ESP32-S3: SOC_GPIO_SUPPORT_HOLD_IO_IN_DSLP).
static const int ZED_INT_PIN = 34;
// V3.13.9: Pololu S7V8F3 control, wiring confirmed by the user: VIN = Heltec 3V3, SHDN = GPIO34, VOUT = GPS.
//   GPS ON  → GPIO34 INPUT without pulls (high impedance): SHDN goes HIGH through the Pololu's own 100 kΩ pull-up to
//             VIN = 3.3 V (so the pin never sees more than 3.3 V). GPIO34 is NEVER driven HIGH.
//   GPS OFF → GPIO34 OUTPUT LOW (held LOW during deep sleep).
// "OFF" here is only what was ORDERED: the firmware cannot measure VOUT; check it with a meter (≈ 0 V expected).
static void zed_shdn(bool on) {          // the only place that touches GPIO34
  gpio_hold_dis((gpio_num_t)ZED_INT_PIN);
  if (on) {
    pinMode(ZED_INT_PIN, INPUT);         // high impedance, no internal pull-up / pull-down
  } else {
    pinMode(ZED_INT_PIN, OUTPUT);
    digitalWrite(ZED_INT_PIN, LOW);
  }
  s_zed_pwr_req = on;
}
static void zed_shdn_sleep() {           // before deep sleep: Pololu off and held off
  zed_shdn(false);
  gpio_hold_en((gpio_num_t)ZED_INT_PIN);
}
// V3.13.0: USB charging. The Heltec has no "USB powered" pin (CP2102 + TP4054), so the 5V header pin (USB 5 V) goes
// to GPIO7 through a divider: 5V ─ 10 kΩ ─ GPIO7 ─ 15 kΩ ─ GND (≈ 3.0 V with USB, 0 V without). USB present → the
// whole back sleeps (ZED at 0 V, radio off, LEDs off) and only the battery charges; USB unplugged → GPIO7 LOW →
// wakes (ext0) and works as usual. USER pressed within 3 s of USB being seen = WORKSHOP mode (stays awake with USB).
// Without the divider GPIO7 reads 0 V (internal pull-down) and the back never sleeps for USB (the old 3.8.2 charge
// mode by rising voltage is still there).
static const int USB_SENSE_PIN = 7;
static const uint32_t USB_POLL_S = 3;           // V3.13.1: while charging, USB checked every 3 s
static bool s_usb_workshop = false;
// V3.13.10: USB threshold diagnosis state (see usb_threshold_update)
#define AVO_USB_AUTO_OFF 1   // V3.13.11: real shutdown (user request 31/10 04:35)
static const int USB_ADC_PIN = 20, USB_ADC_ALT = 7;
static const uint16_t USB_ON_MV = 100, USB_OFF_MV = 50;
static const uint32_t USB_CONFIRM_MS = 2000;
static uint16_t s_usb20_mv = 0, s_usb7_mv = 0;
static uint8_t s_usb20_zero = 0;
static bool s_usb_on = false;                // confirmed state (starts "disconnected")
static int8_t s_usb_cand = -1;               // candidate state waiting for the 2 s confirmation
static uint32_t s_usb_cand_t = 0;
static char s_usb_why[96] = "arranque (estado inicial: desconectado)";

static bool usb_present();
static uint32_t s_vext_at = 0;
static bool s_vext_pending = false;

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
    if (!s_zed_on) return;               // V3.10.5: UART not started while the ZED has no power
    ZED.flush();
    ZED.updateBaudRate(b);
    while (ZED.available()) ZED.read();   // drop bytes received at the old speed
  }
  void zed_write(const uint8_t* d, size_t n) override { if (s_zed_on) ZED.write(d, n); }
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
  {  // V3.13.8: what really arrives from the ZED (requested monitor format)
    static uint32_t prev_b = 0, prev_t = 0;
    const uint32_t now = millis(), db = s_zed_bytes - prev_b, dt = now - prev_t;
    prev_b = s_zed_bytes; prev_t = now;
    const uint32_t ubx = z.stream().frames(), nmea = z.stream().nmea_sentences(), pvt = st.nav_pvt;
    const char* est = !s_zed_pwr_req ? "GPS_SIN_ALIMENTACION_SOLICITADA" : s_zed_bytes == 0 ? "SIN_BYTES (no llega nada por GPIO35)" :
                      (ubx == 0 && nmea == 0) ? "BYTES_SIN_TRAMAS_VALIDAS (baudios o senal)" : pvt == 0 ? "TRAMAS_OK_SIN_NAV-PVT (GPS NO VERIFICADO)" :
                      "NAV-PVT_RECIBIDOS (comunicacion GNSS correcta)";
    Serial.printf("  GNSS UART1: RX=GPIO%d TX=GPIO%d | POLOLU: GPIO34=%s (orden; VOUT no medida)\n", ZED_RX_PIN, ZED_TX_PIN,
                  s_zed_pwr_req ? "ALTA IMPEDANCIA -> Pololu habilitado por su pull-up" : "OUTPUT LOW -> Pololu deshabilitado");
    Serial.printf("  GNSS: bytes recibidos=%lu (%lu B/s) | UBX validos=%lu malos=%lu | NMEA validos=%lu | NAV-PVT=%lu | estado=%s\n",
                  (unsigned long)s_zed_bytes, (unsigned long)(dt ? db * 1000 / dt : 0), (unsigned long)ubx, (unsigned long)z.stream().bad_checksum(),
                  (unsigned long)nmea, (unsigned long)pvt, est);
  }
  Serial.printf("  ZED: %s baudios=%lu puerto del ZED=%s config=%s ritmo=%u Hz (medido %.1f Hz) UBX=%lu NMEA=%lu NAV-PVT=%lu\n",
                ZedManager::state_name(z.state()), (unsigned long)z.baud(), z.port() == 1 ? "UART1" : z.port() == 2 ? "UART2" : "?",
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
  if (s_vext_pending) Serial.printf("  GPS: sin corriente, se enciende en %ld s\n", (long)((int32_t)(s_vext_at - millis()) / 1000) + 1);   // V3.10.5
#if AVO_REED_SLEEP
  Serial.printf("  INTERRUPTOR: reed %s%s\n", s_reed.closed() ? "CERRADO (en el soporte)" : "ABIERTO",   // V3.10.3
                s_reed.workshop() ? " | MODO TALLER: no se duerme" : (s_reed.closed() ? "" : " → se duerme"));
#else
  Serial.printf("  INTERRUPTOR: reed no usado | USB (umbrales, diagnostico): %s | GPS: Pololu SHDN GPIO34 %s\n",   // V3.13.10
                s_usb_on ? "CONECTADO" : "DESCONECTADO", s_zed_on ? "ENCENDIDO" : "apagado");
#endif
  Serial.printf("  AHORRO: CPU %lu MHz | LoRa %s | potencia radio %d dBm%s\n", (unsigned long)getCpuFrequencyMhz(),   // V3.10.2
                s_lora_asleep ? "dormida" : "NO dormida", (int)s_txp.dbm(), s_txp.level() == TxPowerPolicy::kLevels - 1 ? " (maxima)" : "");
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
    static const char* mon[] = {"pendiente", "OK", "RECHAZADO", "UART lenta", "solo NAV-SAT", "solo NAV-SIG", "reintento", "?"};
    Serial.printf("  CALIDAD: sat %u/%u usados | senales %u (usadas %u, fase %u, corregidas %u) | 2a banda L2/E5b/B2 %u%s | C/N0 media %u min %u max %u | debiles %u | NAV-SIG %s hace %u s\n",
                  q.sv_used, q.sv_tracked, q.sig_tracked, q.sig_used, q.sig_cr_used, q.sig_corr, q.sig_l2,
                  (q.have_sig && q.sig_l2 == 0) ? " (ANTENA SOLO L1: sin RTK FIX)" : "", q.cno_mean, q.cno_min, q.cno_max,
                  q.sig_weak, mon[bs.quality_mon & 7], (unsigned)bs.quality_age_s);
    Serial.printf("  RECEPTOR: firmware %s\n", core->zed().receiver_fw()[0] ? core->zed().receiver_fw() : "(sin leer)");
    Serial.printf("  RTK: FIX %lu s, FLOAT %lu s, perdidas de FIX %u, primer FIX %s%u s\n", (unsigned long)(bs.fixed_ms / 1000),
                  (unsigned long)(bs.float_ms / 1000), bs.fix_lost, bs.ttff_fix_s == 0xFFFF ? "aun no " : "a los ",
                  bs.ttff_fix_s == 0xFFFF ? 0u : (unsigned)bs.ttff_fix_s);
  }
  if (z.state() == ZedManager::NO_RESPONSE)
    Serial.println("  AVISO: el ZED no contesta a UBX. Revisa el cableado TX/RX y que el puerto del ZED tenga UBX activado (u-center).");
}

// V3.10.2: put the unused SX1262 into cold-start sleep (SetSleep 0x84, ~0.2 uA). NSS stays HIGH afterwards
// (a falling NSS edge would wake it up). Returns false if the chip stayed busy (not fitted / other board).
static bool lora_sleep() {
  pinMode(LORA_NSS, OUTPUT);
  digitalWrite(LORA_NSS, HIGH);
  pinMode(LORA_RST, OUTPUT);
  digitalWrite(LORA_RST, LOW);
  delay(2);
  digitalWrite(LORA_RST, HIGH);
  pinMode(LORA_BUSY, INPUT);
  delay(5);                              // BUSY rises right after reset; wait for the chip to finish booting
  uint32_t t0 = millis();
  while (digitalRead(LORA_BUSY) == HIGH) { if (millis() - t0 > 50) return false; delay(1); }
  SPI.begin(LORA_SCK, LORA_MISO, LORA_MOSI, LORA_NSS);
  SPI.beginTransaction(SPISettings(2000000, MSBFIRST, SPI_MODE0));
  digitalWrite(LORA_NSS, LOW);
  SPI.transfer(0x84);                    // SetSleep
  SPI.transfer(0x00);                    // cold start, RTC off
  digitalWrite(LORA_NSS, HIGH);
  SPI.endTransaction();
  SPI.end();
  pinMode(LORA_NSS, OUTPUT);
  digitalWrite(LORA_NSS, HIGH);
  delay(1);
  return digitalRead(LORA_BUSY) == HIGH;   // in sleep BUSY stays high
}

// V3.10.4: SOFT START of Vext. Switching the ZED-F9P (input capacitors + active antenna) onto the live 3V3 rail in one
// go pulls the rail down and the ESP32-S3 restarts (rst:0x1 POWERON, loop seen on 28/10 with the ZED moved to Vext).
// The Vext P-MOSFET (GPIO36, LOW = on) is driven with a 40 kHz PWM whose on-time grows from 0.4 % to 100 % in ~250 ms,
// so the capacitors charge in small steps; then the pin is left LOW as before.
static void vext_on_soft() {
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, HIGH);
  if (ledcAttach(VEXT_PIN, 40000, 8)) {
    for (int on = 1; on <= 255; on++) {  // duty = time HIGH (off); on-time grows step by step
      ledcWrite(VEXT_PIN, 256 - on);
      delayMicroseconds(on < 32 ? 2000 : 600);
    }
    ledcDetach(VEXT_PIN);
  }
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, LOW);           // fully on
}

// V3.11.0: ZED regulator (Pololu S7V8F3, SHDN on GPIO6) on. Its own soft start; fed from the battery, so the ZED
// start-up current never touches the 3V3 of the Heltec (no boot loop as with Ve).
static void zed_wake_pulse() {
  zed_shdn(true);
  delay(50);
}

// V3.10.7: UBX-RXM-PMREQ v0 (16 bytes): duration 0 = until woken, flags backup|force.
// V3.10.8: wake-up sources EXTINT0 AND UART RX (0x28): the ZED also wakes on any edge of its RX line, so the INT
// wire is no longer needed (3.10.7 left the ZED in backup for good when INT was not wired or did not wake it).
// Right after the last byte the line is driven LOW at once (before the ZED has even parsed the message) and held
// LOW all night: no edge after the ZED enters backup, white LED (GPIO35) off. The edge that wakes it is the line
// going HIGH again when the UART starts after the next wake-up.
// If the UART was not running yet (capsule out of the support at power-up) it is started at 38400, the ZED's
// default after a power-up or a backup (its configuration lives only in RAM).
static void zed_backup() {
  // V3.13.7: no UBX-RXM-PMREQ any more. The ZED is fed by the Pololu and GPIO34 cuts its power; a software backup
  // only mattered with the ZED on the fixed 3V3, and if the power is NOT really cut it leaves a ZED that answers
  // nothing until it sees an edge on its RX line. Only the TX line (and the white LED) is parked LOW.
  if (s_zed_on) ZED.flush();
  // straight to LOW through the GPIO matrix (microseconds; ZED.end()/pinMode could let the line float HIGH first)
  gpio_set_level((gpio_num_t)ZED_TX_PIN, 0);
  gpio_set_direction((gpio_num_t)ZED_TX_PIN, GPIO_MODE_OUTPUT);
  esp_rom_gpio_connect_out_signal(ZED_TX_PIN, SIG_GPIO_OUT_IDX, false, false);
  gpio_hold_en((gpio_num_t)ZED_TX_PIN);
  s_zed_on = false;                      // the UART is not stopped: ZED.end() would release the line
}

// V3.10.5: ZED on: Vext with soft start, then the UART.
static void zed_power_on() {
  vext_on_soft();
  zed_wake_pulse();                      // V3.10.7: out of software backup if it was there
  ZED.setRxBufferSize(8192);
  ZED.setTxBufferSize(4096);
  ZED.begin(38400, SERIAL_8N1, ZED_RX_PIN, ZED_TX_PIN);
  s_zed_on_at = millis(); s_zed_bytes = 0;
  s_zed_pwr_req = true;
  ZED.setRxTimeout(1);                   // hand each NAV-PVT over as soon as the line goes idle
  const uint8_t wake[8] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  ZED.write(wake, sizeof(wake));         // V3.10.8: edges on the ZED RX line = out of backup (ignored when awake)
  ZED.flush();
  delay(100);                            // the ZED needs a moment after the wake-up edge
  s_zed_on = true;
  Serial.println("[AVO ESPALDA] Vext encendido: el ZED tiene corriente");
}

// V3.13.0: USB 5 V present? (divider on GPIO7, internal pull-down so an unwired pin reads 0)
// V3.13.2: second sense input, GPIO20 (header pin 8 of the 5V·3V3·GND·47·48·0·26·20 row, close to the 5V pin). On this
// board GPIO20 is the unused USB D+ of the ESP32-S3 (the USB-C goes to the CP2102): its USB pad and D+ pull-up are
// switched off so the pin is a plain input. ADC2 cannot be read while the radio is on, so it is read as a digital
// input with the internal pull-down: divider 5V ─ 10 kΩ ─ GPIO20 ─ 22 kΩ ─ GND ≈ 2.7–3.0 V with USB, 0 V without.
static const int USB_SENSE_PIN2 = 20;
// V3.13.3: GPIO20 only. analogRead() turns GPIO7 into an analog pad without pulls: unwired it floats and read as
// "USB present" at random (user test 31/10 02:04: off for a second and on again).
// V3.13.8: USB = GPIO20 digital input only (filtered). No ADC2: its readings are not used to decide.
// V3.13.10: USB by voltage thresholds — DIAGNOSTIC.
//   GPIO20 = ADC2_CH9 on the ESP32-S3. ADC2 is shared with Wi-Fi: while ESP-NOW is running a read can be refused by
//   the arbiter (Arduino then returns 0), so a 0 is counted as "0 or failed". GPIO20 is also the D+ of the native USB
//   (not routed to the USB-C on this board): the USB-Serial-JTAG pad and its pull-ups are switched off first.
//   The ESP32-S3 ADC is not accurate in the first ~100 mV (offset and non-linearity near 0 V at 12 dB attenuation), and
//   a pin with NOTHING connected already read ~170 mV before (V3.13.4–3.13.5 logs). Thresholds of 100 / 50 mV are inside
//   that zone, so the decision is only LOGGED: AVO_USB_AUTO_OFF 0 never switches the GPS off.
//   GPIO7 (ADC1_CH6, free since the reed is gone, usable with Wi-Fi on) is read and shown as the proposed alternative.
static void usb_pad_off() {
  static bool done = false;
  if (done) return;
  done = true;
  SET_PERI_REG_MASK(USB_SERIAL_JTAG_CONF0_REG, USB_SERIAL_JTAG_PAD_PULL_OVERRIDE);
  CLEAR_PERI_REG_MASK(USB_SERIAL_JTAG_CONF0_REG, USB_SERIAL_JTAG_DP_PULLUP | USB_SERIAL_JTAG_DM_PULLUP | USB_SERIAL_JTAG_USB_PAD_ENABLE);
}
// V3.13.11: GPIO20 = ADC2_CH9 read through an own adc_oneshot unit, so a read refused by the Wi-Fi (ESP_ERR_TIMEOUT) is
// known as INVALID instead of looking like 0 V. GPIO20 is not read through Arduino's analogRead any more.
static adc_oneshot_unit_handle_t s_adc2 = nullptr;
static adc_cali_handle_t s_adc2_cali = nullptr;
static bool adc2_init() {
  if (s_adc2) return true;
  adc_oneshot_unit_init_cfg_t u = {};
  u.unit_id = ADC_UNIT_2;
  u.ulp_mode = ADC_ULP_MODE_DISABLE;
  if (adc_oneshot_new_unit(&u, &s_adc2) != ESP_OK) { s_adc2 = nullptr; return false; }
  adc_oneshot_chan_cfg_t c = {};
  c.atten = ADC_ATTEN_DB_12;
  c.bitwidth = ADC_BITWIDTH_DEFAULT;
  adc_oneshot_config_channel(s_adc2, ADC_CHANNEL_9, &c);   // GPIO20
  adc_cali_curve_fitting_config_t cc = {};
  cc.unit_id = ADC_UNIT_2; cc.chan = ADC_CHANNEL_9; cc.atten = ADC_ATTEN_DB_12; cc.bitwidth = ADC_BITWIDTH_DEFAULT;
  if (adc_cali_create_scheme_curve_fitting(&cc, &s_adc2_cali) != ESP_OK) s_adc2_cali = nullptr;
  return true;
}
static int adc2_read_mv() {               // -1 = invalid read
  if (!adc2_init()) return -1;
  int raw = 0, mv = 0;
  if (adc_oneshot_read(s_adc2, ADC_CHANNEL_9, &raw) != ESP_OK) return -1;
  if (s_adc2_cali && adc_cali_raw_to_voltage(s_adc2_cali, raw, &mv) == ESP_OK) return mv;
  return raw * 3100 / 4095;
}
// Median of the VALID readings out of 9; returns -1 if fewer than 5 were valid (the sample is ignored).
static int usb20_sample(uint8_t* valid) {
  int v[9], n = 0;
  for (int i = 0; i < 9; i++) { const int r = adc2_read_mv(); if (r >= 0) v[n++] = r; }
  if (valid) *valid = (uint8_t)n;
  if (n < 5) return -1;
  for (int i = 1; i < n; i++) { int k = v[i], j = i - 1; while (j >= 0 && v[j] > k) { v[j + 1] = v[j]; j--; } v[j + 1] = k; }
  return v[n / 2];
}
static uint8_t s_usb20_valid = 0;
static uint8_t s_usb_agree = 0;            // valid samples agreeing with the candidate
static const char* gnss_state_str();
static void usb_charge_mode();
// Called every 250 ms: hysteresis + confirmation (≥ 2 s and ≥ 6 agreeing VALID samples, no valid sample against).
// Invalid samples change nothing. Returns the confirmed state.
static bool usb_threshold_update(uint32_t now) {
  usb_pad_off();
  const int mv = usb20_sample(&s_usb20_valid);
  s_usb7_mv = (uint16_t)analogReadMilliVolts(USB_ADC_ALT);
  if (mv < 0) { s_usb20_zero = (uint8_t)(9 - s_usb20_valid); return s_usb_on; }   // invalid: keep everything
  s_usb20_mv = (uint16_t)mv; s_usb20_zero = (uint8_t)(9 - s_usb20_valid);
  const int8_t want = mv > USB_ON_MV ? 1 : (mv < USB_OFF_MV ? 0 : -1);   // -1 = between thresholds: keep
  if (want < 0) return s_usb_on;
  if (want == (int8_t)s_usb_on) { s_usb_cand = -1; s_usb_agree = 0; return s_usb_on; }
  if (s_usb_cand != want) {
    s_usb_cand = want; s_usb_cand_t = now; s_usb_agree = 1;
    Serial.printf("[USB] t=%lu ms: candidato %s (GPIO20=%d mV %s %u mV), confirmando 2 s\n", (unsigned long)now,
                  want ? "CONECTADO" : "DESCONECTADO", mv, want ? ">" : "<", (unsigned)(want ? USB_ON_MV : USB_OFF_MV));
    return s_usb_on;
  }
  s_usb_agree++;
  if (now - s_usb_cand_t < USB_CONFIRM_MS || s_usb_agree < 6) return s_usb_on;
  s_usb_on = want; s_usb_cand = -1; s_usb_agree = 0;
  snprintf(s_usb_why, sizeof(s_usb_why), "GPIO20 %s %u mV durante %lu ms (ultima lectura %d mV)", want ? ">" : "<",
           (unsigned)(want ? USB_ON_MV : USB_OFF_MV), (unsigned long)(now - s_usb_cand_t), mv);
  Serial.printf("[USB] t=%lu ms: TRANSICION -> USB %s | motivo: %s\n", (unsigned long)now, want ? "CONECTADO" : "DESCONECTADO", s_usb_why);
  return s_usb_on;
}
// Sleep paths of older versions (boot / timer wake) no longer use USB: the awake charging loop handles it.
static bool usb_present() { return false; }

// V3.10.3: everything off and deep sleep until the reed closes again (capsule back in its support).
// V3.13.0: used for USB charging: wakes when the USB 5 V disappears (GPIO7 LOW).
static void go_to_sleep(const char* why, uint32_t wake_s = 3) {
  s_sleep_s = wake_s;
  Serial.printf("\n[AVO ESPALDA] A DORMIR (%s): GPS sin corriente (GPIO34 = SHDN del Pololu), radio apagada, LEDs apagados.\n"
                "[AVO ESPALDA] Solo carga la bateria. Despierta cada %lu s para mirar el USB y la bateria.\n", why, (unsigned long)s_sleep_s);
  Serial.flush();
  if (s_radio_on) { esp_now_deinit(); WiFi.mode(WIFI_OFF); s_radio_on = false; }
  // V3.10.8: software backup first (it is what saves if the ZED is still on 3V3); GPIO35 (ZED RX + white LED) ends
  // held LOW inside zed_backup()
  zed_backup();
  zed_shdn_sleep();                      // V3.13.9: GPIO34 OUTPUT LOW + hold → Pololu off while asleep
  pinMode(ZED_RX_PIN, INPUT);
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, HIGH);          // Vext off → ZED-F9P and antenna at 0 V
  gpio_hold_en((gpio_num_t)VEXT_PIN);    // keep it off during deep sleep
  pinMode(VBAT_CTRL_PIN, OUTPUT);
  digitalWrite(VBAT_CTRL_PIN, !s_vbat_active);   // battery divider off
  gpio_hold_en((gpio_num_t)VBAT_CTRL_PIN);
  if (s_lora_asleep) {                   // NSS and RST high, or the SX1262 would wake up / reset into standby
    digitalWrite(LORA_NSS, HIGH); gpio_hold_en((gpio_num_t)LORA_NSS);
    digitalWrite(LORA_RST, HIGH); gpio_hold_en((gpio_num_t)LORA_RST);
  }
#if SOC_GPIO_SUPPORT_HOLD_IO_IN_DSLP && !SOC_GPIO_SUPPORT_HOLD_SINGLE_IO_IN_DSLP
  gpio_deep_sleep_hold_en();
#endif
  // V3.13.1: no level wake-up on GPIO7 any more: with the divider the pin sits close to the RTC input threshold and
  // the board woke up after ~1 s with the USB still plugged in (user test 31/10). Instead it wakes every USB_POLL_S,
  // reads GPIO20 (V3.13.3) at the very start of setup() (a few ms, from the USB power) and goes back to sleep while
  // the USB is still there; with the holds above still on, nothing else switches on in between.
  pinMode(USB_SENSE_PIN, INPUT);
  esp_sleep_enable_timer_wakeup((uint64_t)s_sleep_s * 1000000ULL);
  esp_deep_sleep_start();
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
  if (s_zed_on) { ZED.end(); s_zed_on = false; }
  s_vext_pending = false;
  digitalWrite(VEXT_PIN, HIGH);          // Vext off → ZED-F9P without power
  zed_shdn(false);                       // V3.13.9: Pololu off (GPIO34 OUTPUT LOW)
  pinMode(ZED_TX_PIN, OUTPUT);           // no HIGH level into the RX of an unpowered ZED
  digitalWrite(ZED_TX_PIN, LOW);
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
// V3.13.7: GNSS bring-up and diagnosis, BEFORE the radio starts and before any command is sent to the ZED.
//   1. GPIO34 LOW (Pololu off) 500 ms → clean power cycle of the ZED (factory 38400, NMEA on, no leftover state).
//   2. GPIO34 HIGH (power REQUESTED; nothing on this board measures the Pololu output) and 1.5 s for it to boot.
//   3. UART1 (HardwareSerial ZED(1)) RX=GPIO33 TX=GPIO35, then LISTEN only at every baud rate.
//   4. If nothing at all was heard: 8 bytes 0xFF (edge on the ZED RX: out of a possible software backup — not a
//      configuration command) and one more listening round.
// It never switches the ZED off. The configuration (UBX, RTK, 8 Hz) is done afterwards by ZedManager in loop().
static void gnss_bringup_diag() {
  static const uint32_t bauds[] = {38400, 9600, 115200, 230400, 460800, 921600};
  Serial.printf("AVO BACK V%s\n", AVO_FW_VERSION);
  Serial.println("[GNSS] ---- arranque y diagnostico del GPS (sin enviar ordenes al ZED) ----");
  zed_shdn(false);
  Serial.printf("[GNSS] t=%lu ms: GPIO34 OUTPUT LOW (Pololu deshabilitado) 500 ms: arranque limpio del GPS\n", (unsigned long)millis());
  delay(500);
  zed_shdn(true);
  Serial.printf("[GNSS] t=%lu ms: GPIO34 en ALTA IMPEDANCIA -> Pololu habilitado por su pull-up (VOUT no medida); espero 1500 ms\n", (unsigned long)millis());
  delay(1500);
  ZED.setRxBufferSize(8192);
  ZED.setTxBufferSize(4096);
  ZED.begin(38400, SERIAL_8N1, ZED_RX_PIN, ZED_TX_PIN);
  ZED.setRxTimeout(1);
  s_zed_on = true; s_zed_on_at = millis(); s_zed_bytes = 0; s_vext_pending = false;
  Serial.printf("GNSS UART1: RX=GPIO%d TX=GPIO%d  (RX <- TX del ZED, cable verde; TX -> RX del ZED, cable blanco; GPIO35 solo entrada)\n",
                ZED_RX_PIN, ZED_TX_PIN);
  uint8_t buf[256];
  for (int round = 0; round < 2 && !s_diag_baud; round++) {
    for (size_t k = 0; k < sizeof(bauds) / sizeof(bauds[0]); k++) {
      const uint32_t b = bauds[k];
      ZED.updateBaudRate(b);
      while (ZED.available()) ZED.read();
      UbxStream st(nullptr, nullptr);
      uint32_t bytes = 0;
      const uint32_t win = (b <= 38400) ? 2200 : 1300;   // the factory NMEA comes once per second
      const uint32_t t0 = millis();
      while (millis() - t0 < win) {
        int n = ZED.available();
        if (n > 0) { n = ZED.readBytes(buf, n > (int)sizeof(buf) ? (int)sizeof(buf) : n); if (n > 0) { st.feed(buf, n); bytes += n; } }
        else delay(2);
      }
      s_zed_bytes += bytes;
      Serial.printf("[GNSS] escucha %6lu baudios: %5lu bytes (%lu B/s) | UBX validos=%lu malos=%lu | NMEA validos=%lu\n",
                    (unsigned long)b, (unsigned long)bytes, (unsigned long)(bytes * 1000 / win), (unsigned long)st.frames(),
                    (unsigned long)st.bad_checksum(), (unsigned long)st.nmea_sentences());
      if (st.frames() || st.nmea_sentences()) { s_diag_baud = b; break; }
    }
    if (!s_diag_baud && round == 0) {
      Serial.println("[GNSS] nada en ningun baudio: envio 8 bytes 0xFF (flanco en el RX del ZED, no es configuracion) y escucho otra vez");
      ZED.updateBaudRate(38400);
      const uint8_t wake[8] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
      ZED.write(wake, sizeof(wake));
      ZED.flush();
      delay(300);
    }
  }
  ZED.updateBaudRate(s_diag_baud ? s_diag_baud : 38400);
  while (ZED.available()) ZED.read();
  if (s_diag_baud) {
    Serial.printf("[GNSS] COMUNICACION OK: el ZED habla a %lu baudios. Ahora se configura (UBX, RTK, 8 Hz); el GPS solo se dara por bueno con NAV-PVT.\n",
                  (unsigned long)s_diag_baud);
  } else {
    Serial.println("[GNSS] SIN DATOS DEL ZED en ningun baudio. GPIO34 esta en 1 (orden de encendido), pero eso NO demuestra que el ZED tenga");
    Serial.println("[GNSS]   tension. Medir con polimetro: VOUT del Pololu = 3,3 V, VIN = bateria, GND comun, y continuidad TX del ZED -> GPIO33.");
  }
  Serial.println("[GNSS] ---- fin del diagnostico: ahora se activa ESP-NOW ----");
}

void setup() {
  // V3.13.1: timer wake-up while charging: USB still there → straight back to sleep (holds still on: ZED, LED and
  // radio stay off). Only when the USB is gone does the back start.
  if (esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_TIMER && usb_present()) {
    pinMode(USB_SENSE_PIN, INPUT);
#if SOC_GPIO_SUPPORT_HOLD_IO_IN_DSLP && !SOC_GPIO_SUPPORT_HOLD_SINGLE_IO_IN_DSLP
    gpio_deep_sleep_hold_en();
#endif
    esp_sleep_enable_timer_wakeup((uint64_t)USB_POLL_S * 1000000ULL);
    esp_deep_sleep_start();
  }
  Serial.setTxBufferSize(4096);          // status printing must never block the GNSS/RTCM loop
  Serial.begin(115200);
  delay(300);
  // V3.10.3: coming back from deep sleep: keep the ZED off until the reed is confirmed, then release the holds
  pinMode(VEXT_PIN, OUTPUT);
  digitalWrite(VEXT_PIN, HIGH);
#if SOC_GPIO_SUPPORT_HOLD_IO_IN_DSLP && !SOC_GPIO_SUPPORT_HOLD_SINGLE_IO_IN_DSLP
  gpio_deep_sleep_hold_dis();
#endif
  gpio_hold_dis((gpio_num_t)VEXT_PIN);
  gpio_hold_dis((gpio_num_t)VBAT_CTRL_PIN);
  gpio_hold_dis((gpio_num_t)LORA_NSS);
  gpio_hold_dis((gpio_num_t)LORA_RST);
  gpio_hold_dis((gpio_num_t)33);           // V3.13.6: both ZED UART pins (either may be TX)
  gpio_hold_dis((gpio_num_t)35);
  zed_shdn(false);                           // V3.13.9: Pololu off until the GPS start-up (gnss_bringup_diag)
  const bool woke_by_reed = esp_sleep_get_wakeup_cause() == ESP_SLEEP_WAKEUP_TIMER;   // V3.13.1: USB unplugged while asleep
  Serial.printf("[AVO ESPALDA] arranque: motivo de reinicio %d, despertar %d (1=encendido 3=software 4=panico 8=sueño 9=caida de tension; despertar 4=temporizador)\n",
                (int)esp_reset_reason(), (int)esp_sleep_get_wakeup_cause());
#if AVO_REED_SLEEP
  pinMode(REED_PIN, INPUT_PULLUP);
#endif
  pinMode(PRG_PIN, INPUT_PULLUP);
  setCpuFrequencyMhz(CPU_MHZ);           // V3.10.2 (before Wi-Fi starts)
  s_lora_asleep = lora_sleep();          // V3.10.2
  pinMode(VBAT_CTRL_PIN, INPUT);
  delay(2);
  s_vbat_active = digitalRead(VBAT_CTRL_PIN) == HIGH ? LOW : HIGH;   // V3.8.1: board revision detection
  pinMode(VBAT_CTRL_PIN, OUTPUT);
  digitalWrite(VBAT_CTRL_PIN, !s_vbat_active);
  analogSetPinAttenuation(VBAT_PIN, ADC_11db);
  // V3.13.3: battery at rest, before the radio: too low → sleep (ZED off) and try again every 60 s
  {
    const uint16_t mv0 = read_battery_mv();
    const bool usb0 = usb_present();
    Serial.printf("[AVO ESPALDA] bateria en reposo %u mV | USB GPIO20=%s%s\n", (unsigned)mv0, usb0 ? "HIGH" : "LOW",
                  usb0 ? " (USB detectado)" : " (USB no detectado; con USB conectado y LOW, la senal fisica no llega a GPIO20)");
    const uint16_t lim = s_low_batt ? LOW_BATT_RESUME_MV : LOW_BATT_MV;
    if (mv0 && mv0 < lim && !usb0) {
      s_low_batt = true;
      go_to_sleep("BATERIA AGOTADA: hay que cargarla", LOW_BATT_POLL_S);
    }
    s_low_batt = false;
  }
  gnss_bringup_diag();                   // V3.13.7: GPS first, radio later
  // V3.10.3: capsule out of its support at power-up → sleep, unless USER is pressed within 3 s (workshop mode)
  delay(20);
  if (woke_by_reed) Serial.printf("[USB] t=%lu ms: despierta: USB retirado (GPIO20 LOW) -> Pololu, UART1 RX35/TX33 y UBX se recuperan ahora\n", (unsigned long)millis());
  // V3.13.0: USB connected at power-up / reset → only charging (deep sleep), unless USER within 3 s (workshop)
  if (usb_present()) {
    Serial.println("[AVO ESPALDA] USB conectado (GPIO20 alto): a dormir para cargar. Pulsa USER en 3 s para el MODO TALLER.");
    uint32_t t0 = millis();
    while (millis() - t0 < 3000 && digitalRead(PRG_PIN) == HIGH) delay(10);
    if (digitalRead(PRG_PIN) == LOW) {
      s_usb_workshop = true;
      Serial.println("[AVO ESPALDA] MODO TALLER: no se duerme con el USB hasta reiniciar");
      while (digitalRead(PRG_PIN) == LOW) delay(10);
    } else if (usb_present()) {
      go_to_sleep("USB conectado al arrancar");
    }
  }
#if !AVO_REED_SLEEP
  s_reed.set_workshop(true);             // V3.10.9: reed ignored, the back never sleeps
  Serial.println("[AVO ESPALDA] V3.12: sin reed (contactos pogo): la placa solo tiene corriente en el soporte del chaleco");
#else
  if (digitalRead(REED_PIN) == HIGH) {
    Serial.println("[AVO ESPALDA] reed ABIERTO (capsula fuera del soporte). Pulsa USER en 3 s para el MODO TALLER (no se duerme).");
    uint32_t t0 = millis();
    bool workshop = false;
    while (millis() - t0 < ReedGate::kBootWindowMs) {
      if (digitalRead(PRG_PIN) == LOW) { workshop = true; break; }
      if (digitalRead(REED_PIN) == LOW) break;
      delay(10);
    }
    if (workshop) {
      s_reed.set_workshop(true);
      Serial.println("[AVO ESPALDA] MODO TALLER: el reed se ignora hasta reiniciar");
      while (digitalRead(PRG_PIN) == LOW) delay(10);   // do not count this press as the 3 s / 8 s USER hold
    } else if (digitalRead(REED_PIN) == HIGH) {
      go_to_sleep("capsula fuera del soporte al arrancar");
    }
  }
#endif
  // V3.10.5: the ZED gets power (and its UART starts) VEXT_DELAY_MS later, from loop(); until then its pins stay
  // as inputs so the unpowered ZED is not fed through its RX line.
  // V3.13.7: the ZED is already powered and its UART open (gnss_bringup_diag); no delayed power-on any more.
  s_vext_pending = false;

  s_rxq = xQueueCreate(48, sizeof(RxPkt));   // ~1 s of RTCM burst
  s_sent = xSemaphoreCreateBinary();
  WiFi.mode(WIFI_STA);
  WiFi.disconnect();
  WiFi.setSleep(false);
  esp_wifi_set_ps(WIFI_PS_NONE);         // radio always listening: no added RTCM latency
  esp_wifi_set_channel(NOW_CHANNEL_DEFAULT, WIFI_SECOND_CHAN_NONE);
  esp_wifi_set_max_tx_power(84);         // 21 dBm request (the S3 caps it at its maximum)
  if (esp_now_init() != ESP_OK) Serial.println("[AVO ESPALDA] ERROR esp_now_init");
  s_radio_on = true;
  esp_now_register_recv_cb(on_recv);
  esp_now_register_send_cb(on_sent);
  ensure_peer(kBroadcast);
  uint8_t mac[6];
  esp_wifi_get_mac(WIFI_IF_STA, mac);
  snprintf(s_dev_id, sizeof(s_dev_id), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);

  prefs.begin("avonow", false);
  if (prefs.isKey("zedswap")) prefs.remove("zedswap");   // V3.13.7: the 3.13.6 swap memory is not used any more
  Serial.println("[AVO ESPALDA] ESP-NOW activo (despues del diagnostico GNSS)");
  uint8_t boots = prefs.getUChar("boots", 0);
  // V3.13.0: only real power-ups count (a wake-up after USB charging is not one)
  if (esp_reset_reason() == ESP_RST_POWERON) boots = (uint8_t)((boots >= 3 ? 0 : boots) + 1); else boots = 0;
  const bool pair_gesture = boots >= 3;
  prefs.putUChar("boots", pair_gesture ? 0 : boots);
  NowPeerRecord stored;
  uint8_t b[NOW_PEER_RECORD_LEN];
  size_t n = prefs.getBytes("peer", b, sizeof(b));
  if (!now_peer_deserialize(b, n, &stored)) stored = NowPeerRecord();

  core = new BackCore(&platform, s_dev_id, NAV_RATE_HZ);
  uint8_t girth_mac[6];   // V3.10.0: girth unit paired before (none: the first one that says HELLO is accepted)
  bool have_girth = prefs.getBytes("girth", girth_mac, 6) == 6;
  core->begin(stored, have_girth ? girth_mac : nullptr);
  if (pair_gesture) { core->open_pairing(); Serial.println("[AVO ESPALDA] 3 encendidos rapidos: emparejamiento abierto 120 s"); }
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
  Serial.printf("AHORRO: CPU %lu MHz, LoRa %s, potencia de radio adaptativa (empieza al maximo)\n",
                (unsigned long)getCpuFrequencyMhz(), s_lora_asleep ? "dormida" : "NO dormida (no responde)");
}

// V3.13.11: charging with the USB connected. Stays AWAKE (no deep sleep) so GPIO34 is actively held LOW and the USB
// can be watched every 250 ms with the radio off (ADC2 free, reads valid). When the USB is confirmed gone: GPIO34 is
// released (Pololu enabled by its pull-up), 1.5 s, and the board restarts cleanly: UART1 RX35/TX33, passive listening,
// ZedManager (UBX, RTK, 8 Hz), NAV-PVT, ESP-NOW, telemetry and RTCM all come back exactly as at power-up.
static void usb_charge_mode() {
  const uint32_t t0 = millis();
  Serial.printf("\n[USB] t=%lu ms: USB CONECTADO -> modo carga\n", (unsigned long)t0);
  // 1. nothing more is sent to the ZED (zed_write is guarded by s_zed_on) and its UART is stopped
  if (s_zed_on) { ZED.flush(); s_zed_on = false; ZED.end(); }
  // 2. GPIO33 (TX) and GPIO35 (RX) in high impedance: no level can feed the ZED through its UART pins
  gpio_hold_dis((gpio_num_t)ZED_TX_PIN);
  pinMode(ZED_TX_PIN, INPUT);
  pinMode(ZED_RX_PIN, INPUT);
  // 3. Pololu off and kept off while the USB stays (actively driven: the board does not sleep)
  zed_shdn(false);
  // 4. radio off: no telemetry and no RTCM while charging
  if (s_radio_on) { esp_now_deinit(); WiFi.mode(WIFI_OFF); s_radio_on = false; }
  setCpuFrequencyMhz(80);
  Serial.println("POLOLU APAGADO — USB CONECTADO (GPIO34 OUTPUT LOW; la tension de VOUT NO se mide: comprobar con polimetro)");
  uint32_t last = 0, last_print = 0;
  for (;;) {
    const uint32_t now = millis();
    if (now - last >= 250) {
      last = now;
      if (!usb_threshold_update(now)) {
        Serial.printf("[USB] t=%lu ms: USB RETIRADO tras %lu s de carga -> libero GPIO34 (alta impedancia), espero 1500 ms y reinicio limpio\n",
                      (unsigned long)now, (unsigned long)((now - t0) / 1000));
        zed_shdn(true);
        delay(1500);
        Serial.println("[USB] reinicio: UART1 RX=GPIO35 TX=GPIO33, GNSS, NAV-PVT, ESP-NOW y RTCM se recuperan en el arranque");
        Serial.flush();
        ESP.restart();
      }
    }
    if (now - last_print >= 1000) {
      last_print = now;
      Serial.printf("[USB] carga %lu s | GPIO20=%u mV (%u/9 validas) | USB=%s%s | GPIO34=OUTPUT LOW | POLOLU APAGADO — USB CONECTADO | bateria %u mV\n",
                    (unsigned long)((now - t0) / 1000), (unsigned)s_usb20_mv, (unsigned)s_usb20_valid, s_usb_on ? "CONECTADO" : "DESCONECTADO",
                    s_usb_cand == 0 ? " (confirmando DESCONECTADO)" : "", (unsigned)read_battery_mv());
    }
    delay(10);
  }
}

static const char* gnss_state_str() {   // V3.13.10
  if (!s_zed_pwr_req) return "SIN_ALIMENTACION_SOLICITADA";
  if (!core) return "ARRANCANDO";
  const ZedManager& z = core->zed();
  if (s_zed_bytes == 0) return "SIN_BYTES";
  if (z.stream().frames() == 0 && z.stream().nmea_sentences() == 0) return "BYTES_SIN_TRAMAS";
  if (core->stats().nav_pvt == 0) return "TRAMAS_OK_SIN_NAV-PVT";
  return "NAV-PVT_OK";
}

void loop() {
  bool worked = false;
  RxPkt p;
  while (xQueueReceive(s_rxq, &p, 0) == pdTRUE) {
    core->on_radio(p.mac, p.d, p.len, p.rssi);
    worked = true;
    // V3.10.2: worst RSSI of our own peers (chest, girth) for the adaptive transmit power
    const bool from_chest = core->paired() && memcmp(p.mac, core->peer().mac, 6) == 0;
    const bool from_girth = core->girth().paired() && memcmp(p.mac, core->girth().mac(), 6) == 0;
    if ((from_chest || from_girth) && p.rssi < 0 && (s_rssi_worst == 0 || p.rssi < s_rssi_worst)) s_rssi_worst = p.rssi;
  }

  uint8_t buf[512];
  int avail;
  if (s_vext_pending && (int32_t)(millis() - s_vext_at) >= 0) { s_vext_pending = false; zed_power_on(); }   // V3.10.5
  while (s_zed_on && (avail = ZED.available()) > 0) {
    int n = ZED.readBytes(buf, avail > (int)sizeof(buf) ? (int)sizeof(buf) : avail);
    if (n <= 0) break;
    s_zed_bytes += (uint32_t)n;          // V3.13.7: bytes/s in the monitor
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
  if (!s_boots_cleared && millis() >= QUICK_BOOT_MS) { s_boots_cleared = true; prefs.putUChar("boots", 0); }   // V3.12.0
  // V3.13.10: USB by thresholds every 250 ms + a line every second with everything that decides it
  static uint32_t last_usb = 0, last_usb_print = 0;
  if (millis() - last_usb >= 250) {
    last_usb = millis();
    if (usb_threshold_update(last_usb) && !s_usb_workshop) usb_charge_mode();   // V3.13.11: never returns
  }
  if (millis() - last_usb_print >= 1000) {
    last_usb_print = millis();
    Serial.printf("[USB] GPIO20=%u mV (ADC2, %u/9 lecturas rechazadas por la radio) | GPIO7=%u mV (ADC1, alternativa; sin conectar = ruido) | USB=%s%s | GPIO34=%s | GNSS=%s | ultimo cambio: %s\n",
                  (unsigned)s_usb20_mv, (unsigned)s_usb20_zero, (unsigned)s_usb7_mv, s_usb_on ? "CONECTADO" : "DESCONECTADO",
                  s_usb_cand >= 0 ? (s_usb_cand ? " (confirmando CONECTADO)" : " (confirmando DESCONECTADO)") : "",
                  s_zed_pwr_req ? "ALTA IMPEDANCIA (Pololu habilitado)" : "OUTPUT LOW (Pololu deshabilitado)", gnss_state_str(), s_usb_why);
  }
  // V3.13.9: times from GPS power-on to the first valid UBX frame and the first NAV-PVT
  {
    static bool got_ubx = false, got_pvt = false;
    if (s_zed_on && !got_ubx && core->zed().stream().frames() > 0) {
      got_ubx = true;
      Serial.printf("[GNSS] primer UBX valido %lu ms despues de habilitar el Pololu\n", (unsigned long)(millis() - s_zed_on_at));
    }
    if (s_zed_on && !got_pvt && core->stats().nav_pvt > 0) {
      got_pvt = true;
      Serial.printf("[GNSS] primer NAV-PVT %lu ms despues de habilitar el Pololu (comunicacion GNSS recuperada en este arranque)\n",
                    (unsigned long)(millis() - s_zed_on_at));
    }
  }
  static uint32_t last_reed = 0;   // V3.10.3: capsule out of its support for 3 s → deep sleep
  if (millis() - last_reed >= 100) {
    last_reed = millis();
    if (s_reed.update(millis(), digitalRead(REED_PIN) == LOW)) go_to_sleep("capsula fuera del soporte");
  }
  static uint32_t last_txp = 0;    // V3.10.2: adaptive ESP-NOW transmit power, decided once per second
  if (millis() - last_txp >= 1000) {
    last_txp = millis();
    static uint32_t last_fail = 0;
    const uint32_t fail = core->stats().tx_fail;
    if (s_txp.update(millis(), core->chest_online(), s_rssi_worst, fail - last_fail)) {
      esp_wifi_set_max_tx_power(s_txp.qdbm());
      Serial.printf("[AVO ESPALDA] potencia de radio %d dBm (peor RSSI %d dBm)\n", (int)s_txp.dbm(), (int)s_rssi_worst);
    }
    last_fail = fail;
    s_rssi_worst = 0;
  }
  static uint32_t last_print = 0;
  if (millis() - last_print >= 2000) { last_print = millis(); print_status(); }
  if (!worked) delay(1);                 // only sleep when there was nothing to do
}
