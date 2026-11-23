#!/usr/bin/env python3
"""AVO CASCO 5.0.0: convierte el árbol del pecho 3.7.11 (el mismo que monta build-chest-v377-despertar.yml) en el
firmware del casco BACK V5: pecho + espalda en un solo ESP32-S3.

Uso (dentro del árbol del pecho ya montado):  python3 apply_v500.py <raíz del repositorio>

Qué hace, en orden (cada cambio comprueba que el texto original existe: si el pecho cambia, falla en vez de adivinar):
  1. lib/avo_core: los ficheros de la espalda 3.15.0 (BackCore, ZED, GirthHub, calidad GNSS, códecs RTCM) sobre los del
     pecho, salvo avo_input y avo_ble_proto (los del pecho son los más nuevos). Identidad AVO-CASCO 5.0.0.
  1b. Ganchos del casco en la copia de BackCore: PPS, observador de NAV-PVT (TIME_SYNC) y tramas propias (IMU cabeza).
  2. src: placa del casco (board_pins.h, hal_board.cpp), espalda interna (casco_back.*), IMU de la cabeza (casco_imu.*)
     y anillo LED (ui.cpp) en lugar de
     la pantalla AMOLED, el AXP2101, el RTC y el táctil de la pantalla.
  3. Enlace pecho ↔ espalda por memoria (uart_link.cpp), táctil (controller.cpp), arranque (app_main.cpp), microSD de
     4 bits con su interruptor (storage.cpp), OTA y nombres propios del casco (ota.cpp, ble_service.cpp, usb_sync.cpp).
"""
import pathlib
import shutil
import sys

ROOT = pathlib.Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else None
if not ROOT or not (ROOT / "firmware/back/V3_8_0").is_dir():
    sys.exit("uso: apply_v500.py <raíz del repositorio>")
T = pathlib.Path.cwd()
SRC = T / "AVO_CHEST_V3_5_0/src"
LIB = T / "lib/avo_core/src"
BACK_LIB = ROOT / "firmware/back/V3_8_0/lib/avo_core/src"
CASCO = ROOT / "firmware/back/V5_0_0_CASCO/src"
assert SRC.is_dir() and LIB.is_dir(), "no es el árbol del pecho"


def patch(rel, old, new, count=1):
    p = T / rel
    s = p.read_text()
    n = s.count(old)
    assert n == count, f"{rel}: se esperaban {count} apariciones y hay {n}:\n{old}"
    p.write_text(s.replace(old, new))


# ------------------------------------------------------------------ 1. biblioteca común
for name in ("avo_back_core.h", "avo_back_core.cpp", "avo_ubx_zed.h", "avo_ubx_zed.cpp", "avo_gnss_codecs.h",
             "avo_gnss_codecs.cpp", "avo_girth_link.h", "avo_girth_link.cpp", "avo_gnss_quality.h", "avo_gnss_quality.cpp",
             "avo_tx_power.h", "avo_tx_power.cpp", "avo_reed_gate.h", "avo_chest_sleep.h", "avo_core.h"):
    shutil.copy2(BACK_LIB / name, LIB / name)
for name in ("avo_payloads.h", "avo_payloads.cpp", "avo_espnow_link.h", "avo_espnow_link.cpp", "avo_uart_proto.h",
             "avo_uart_proto.cpp"):   # contratos: tienen que ser los mismos bytes en los dos lados
    assert (LIB / name).read_bytes() == (BACK_LIB / name).read_bytes(), f"{name} distinto entre pecho y espalda"
(LIB / "avo_version.h").write_text(
    "// AVO CASCO BACK V5 firmware identity (pecho 3.7.11 + espalda 3.15.0 en un solo ESP32-S3). Bumped for every release.\n"
    "#pragma once\n"
    '#define AVO_FW_NAME "AVO-CASCO"\n'
    '#define AVO_FW_VERSION "5.0.0"\n'
    "#define AVO_FW_VERSION_NUM 0x050000\n"
    '#define AVO_HW_TARGET "AVO CASCO BACK V5 (ESP32-S3-WROOM-1U-N16R8, PROTOTIPO A / REV B)"\n')

# ------------------------------------------------------------------ 1b. ganchos del casco en BackCore (solo en este árbol)
# La espalda de la Heltec no tiene PPS ni IMU propia: su biblioteca (firmware/back/V3_8_0) NO se toca. En la copia del
# casco se añaden: estado del PPS en BackStatus y en GnssSample.pps_locked, un observador de NAV-PVT (para la
# TIME_SYNC) y el envío de tramas propias (TIME_SYNC, IMU de la cabeza) por la misma cola hacia el pecho.
BH = "lib/avo_core/src/avo_back_core.h"
BC = "lib/avo_core/src/avo_back_core.cpp"
patch(BH, "  void set_battery_mv(uint16_t mv) { batt_mv_ = mv; }\n",
      "  void set_battery_mv(uint16_t mv) { batt_mv_ = mv; }\n"
      "  // AVO CASCO 5.0.0: PPS medido por la placa (0 sin pulsos, 1 pulsos, 2 enganchado), observador de NAV-PVT y\n"
      "  // tramas propias del casco (TIME_SYNC, IMU_SAMPLE de la cabeza) por la cola hacia el pecho.\n"
      "  void set_pps(uint8_t state, uint32_t count) { pps_state_ = state; pps_count_ = count; }\n"
      "  typedef void (*PvtCb)(const GnssSample& g, void* ctx);\n"
      "  void set_pvt_observer(PvtCb cb, void* ctx) { pvt_cb_ = cb; pvt_ctx_ = ctx; }\n"
      "  bool send_extra(FrameType t, const uint8_t* pl, size_t n) {\n"
      "    if (!pair_.paired() || !chest_online()) return false;\n"
      "    queue_frame(t, 0, pl, n, true);\n"
      "    return true;\n"
      "  }\n")
patch(BH, "  uint16_t batt_mv_ = 0;\n",
      "  uint16_t batt_mv_ = 0;\n"
      "  uint8_t pps_state_ = 0;   // AVO CASCO\n"
      "  uint32_t pps_count_ = 0;\n"
      "  PvtCb pvt_cb_ = nullptr;\n"
      "  void* pvt_ctx_ = nullptr;\n")
patch(BC, "    g.pps_locked = 0;\n",
      "    g.pps_locked = pps_state_ == 2 ? 1 : 0;   // AVO CASCO: PPS de la placa\n"
      "    if (pvt_cb_) pvt_cb_(g, pvt_ctx_);        // AVO CASCO: TIME_SYNC\n")
patch(BC, "  s.pps_state = 0;          // PPS not wired on this back\n",
      "  s.pps_state = pps_state_;   // AVO CASCO: PPS de la placa\n"
      "  s.pps_count = pps_count_;\n")
patch(BC, "  c.caps = CAP_GNSS_SAMPLE | CAP_RTCM_IN | CAP_RXM_RTCM | CAP_ACK;",
      "  c.caps = CAP_GNSS_SAMPLE | CAP_RTCM_IN | CAP_RXM_RTCM | CAP_ACK | CAP_PPS | CAP_TIME_SYNC | CAP_IMU;   // AVO CASCO")

# ------------------------------------------------------------------ 2. placa y pantalla
for name in ("ui_dash.cpp", "ui_dash.h", "ui_fb.cpp", "ui_fb.h", "ui_model.cpp", "ui_model.h", "ui_pc.h", "ui_pc_draw.h",
             "ui_assets.h", "ui.cpp", "hal_board.cpp", "board_pins.h"):
    (SRC / name).unlink()
for name in ("board_pins.h", "hal_board.cpp", "casco_back.h", "casco_back.cpp", "casco_imu.h", "casco_imu.cpp", "ui.cpp"):
    shutil.copy2(CASCO / name, SRC / name)

# ------------------------------------------------------------------ 3a. enlace con la espalda: por memoria
U = "AVO_CHEST_V3_5_0/src/uart_link.cpp"
patch(U, '#include "sys_util.h"\n', '#include "sys_util.h"\n#include "casco_back.h"   // AVO CASCO 5.0.0\n')
patch(U, """  s_sent_ok = (st == ESP_NOW_SEND_SUCCESS);
  if (s_sent_sem) xSemaphoreGive(s_sent_sem);
}""", """  casco_back::on_air_sent(st == ESP_NOW_SEND_SUCCESS);   // AVO CASCO: la radio real solo la usa la espalda (cinchas)
}""")
patch(U, "  enqueue_rx(info->src_addr, info->rx_ctrl ? (int8_t)info->rx_ctrl->rssi : 0, d, n);\n",
      "  casco_back::on_air(info->src_addr, info->rx_ctrl ? (int8_t)info->rx_ctrl->rssi : 0, d, n);   // AVO CASCO: cinchas\n")
patch(U, "static void now_recv_cb(const uint8_t* mac, const uint8_t* d, int n) { enqueue_rx(mac, 0, d, n); }",
      "static void now_recv_cb(const uint8_t* mac, const uint8_t* d, int n) { casco_back::on_air(mac, 0, d, n); }")
patch(U, """  if (xMessageBufferSend(s_rxmb, b, 7 + (size_t)n, 0) == 0) s_rx_drop = s_rx_drop + 1;
}
""", """  if (xMessageBufferSend(s_rxmb, b, 7 + (size_t)n, 0) == 0) s_rx_drop = s_rx_drop + 1;
}

// AVO CASCO 5.0.0: paquetes de la espalda interna (los mismos bytes que llegaban por ESP-NOW).
void loopback_rx(const uint8_t* mac, int8_t rssi, const uint8_t* d, int n) { enqueue_rx(mac, rssi, d, n); }
""")
patch(U, """static bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) {
  xSemaphoreTake(s_sent_sem, 0);
  if (esp_now_send(mac, d, n) != ESP_OK) return false;
  if (xSemaphoreTake(s_sent_sem, pdMS_TO_TICKS(80)) != pdTRUE) return false;
  return s_sent_ok;
}""", """static bool radio_send(const uint8_t* mac, const uint8_t* d, size_t n) {
  (void)mac;   // AVO CASCO 5.0.0: todo lo que el pecho envía va a la espalda interna, nunca a la radio
  return casco_back::to_back(d, n);
}""")
patch(U, """static void add_peer(const uint8_t mac[6]) {
  if (esp_now_is_peer_exist(mac)) return;""", """static void add_peer(const uint8_t mac[6]) {
  if (memcmp(mac, casco_back::kVirtualBack, 6) == 0) return;   // AVO CASCO: la espalda interna no es un par de radio
  if (esp_now_is_peer_exist(mac)) return;""")
patch(U, """  snprintf(s_dev_id, sizeof(s_dev_id), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  uint8_t rec[NOW_PEER_RECORD_LEN];""", """  snprintf(s_dev_id, sizeof(s_dev_id), "%02X%02X%02X%02X%02X%02X", mac[0], mac[1], mac[2], mac[3], mac[4], mac[5]);
  {  // AVO CASCO 5.0.0: pareja fija con la espalda interna (no se guarda ni se puede olvidar)
    NowPeerRecord r;
    r.valid = true;
    memcpy(r.mac, casco_back::kVirtualBack, 6);
    r.pair_id = casco_back::pair_id();
    s_pair.load(r);
    Serial.printf("[AVO NOW] casco %s canal %u: espalda interna por memoria; la radio queda para las cinchas\\n", s_dev_id,
                  NOW_CHANNEL_DEFAULT);
    publish_pairing();
    return true;
  }
  uint8_t rec[NOW_PEER_RECORD_LEN];""")
patch(U, """bool pair_start(uint32_t window_ms) {
#if AVO_LINK_UART""", """bool pair_start(uint32_t window_ms) {
#if AVO_CASCO
  (void)window_ms;   // la espalda es interna: no hay espalda que emparejar (las cinchas se emparejan con su orden)
  return false;
#endif
#if AVO_LINK_UART""")
patch(U, """bool pair_forget() {
#if AVO_LINK_UART""", """bool pair_forget() {
#if AVO_CASCO
  return false;
#endif
#if AVO_LINK_UART""")

# ------------------------------------------------------------------ 3b. táctil en lugar de BOOT + PWR
C = "AVO_CHEST_V3_5_0/src/controller.cpp"
patch(C, "  bool boot = digitalRead(PIN_BOOT_BTN) == LOW;\n  bool pwr = digitalRead(PIN_PWR_SENSE) == HIGH;\n",
      "  bool boot = AVO_BTN_PRESSED(digitalRead(PIN_BOOT_BTN));   // AVO CASCO: los dos son el táctil (activo ALTO)\n"
      "  bool pwr = AVO_PWR_PRESSED(digitalRead(PIN_PWR_SENSE));\n")
patch(C, """    case BootButton::DOUBLE:
      s_confirm_stop = false;
      ui::home_screen();
      break;
    case BootButton::LONG:
""", """    case BootButton::DOUBLE:
#if AVO_CASCO
      // AVO CASCO: 2 toques = empezar sesión, o pedir confirmación para pararla (1 toque en 5 s la para)
      if (s_life.active()) { s_confirm_stop = true; s_confirm_until = now + 5000; }
      else { s_confirm_stop = false; handle_cmd(SessionCmd::START, CmdSource::BUTTON, now); }
      break;
#endif
      s_confirm_stop = false;
      ui::home_screen();
      break;
    case BootButton::LONG:
#if AVO_CASCO
      break;   // AVO CASCO: mantener el táctil es el apagado (3 s, tecla PWR del pecho)
#endif
""")
patch(C, "  esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_BOOT_BTN, 0);\n",
      "  esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_BOOT_BTN, 1);   // AVO CASCO: el táctil despierta en ALTO\n")

# ------------------------------------------------------------------ 3c. arranque
A = "AVO_CHEST_V3_5_0/src/app_main.cpp"
patch(A, '#include "build_info.h"\n', '#include "build_info.h"\n#include "casco_back.h"   // AVO CASCO 5.0.0\n#include "casco_imu.h"\n')
patch(A, """  bool link_ok = uartlink::init(uart_baud);
  boot_log("uart", rtcm_ok && link_ok);
""", """  bool link_ok = uartlink::init(uart_baud);
  boot_log("uart", rtcm_ok && link_ok);
  bool back_ok = link_ok && casco_back::init();   // AVO CASCO: espalda interna (ZED-F9P + cinchas)
  boot_log("back", back_ok);
  boot_log("imu", casco_imu::init());   // AVO CASCO: LSM6DSV16X de la cabeza (sin ella el casco sigue)
""")
patch(A, "    const bool healthy = i2c_ok && pmu_ok && sd_ok && ctl_ok && ui_ok && ble_ok;\n",
      "    const bool healthy = i2c_ok && pmu_ok && sd_ok && ctl_ok && ui_ok && ble_ok && back_ok;\n")

# ------------------------------------------------------------------ 3d. microSD: 4 bits y alimentación conmutada
S = "AVO_CHEST_V3_5_0/src/storage.cpp"
patch(S, """  if (!SD_MMC.setPins(PIN_SD_CLK, PIN_SD_CMD, PIN_SD_D0)) return false;
  if (!SD_MMC.begin(AVO_SD_MOUNT, true, false, SDMMC_FREQ_DEFAULT, 6)) return false;""", """  {  // AVO CASCO: Q4 enciende la tarjeta (arranque suave R47/C42); la primera vez se espera a que se estabilice
    static bool powered = false;
    if (!powered) { pinMode(PIN_SD_PWR_N, OUTPUT); digitalWrite(PIN_SD_PWR_N, LOW); delay(50); powered = true; }
  }
  if (!SD_MMC.setPins(PIN_SD_CLK, PIN_SD_CMD, PIN_SD_D0, PIN_SD_D1, PIN_SD_D2, PIN_SD_D3)) return false;
  if (!SD_MMC.begin(AVO_SD_MOUNT, false, false, SDMMC_FREQ_DEFAULT, 6)) return false;   // AVO CASCO: 4 bits""")

# ------------------------------------------------------------------ 3e. identidad: una OTA del pecho no entra en el casco ni al revés
O = "AVO_CHEST_V3_5_0/src/ota.cpp"
patch(O, 'eq("target","AVO_CHEST_WAVESHARE_ESP32S3")', 'eq("target","AVO_CASCO_V5_ESP32S3")')
patch(O, '"AVOCHEST-IMG-V1:WS-AMOLED-2.06"', '"AVOCASCO-IMG-V1:BACK-V5"', count=2)
patch("AVO_CHEST_V3_5_0/src/ble_service.cpp", '"AVO-CHEST %s %s"', '"AVO-CASCO %s %s"')
# USB AVO1: el nombre que buscan las apps no cambia (contrato); se añade el modelo
patch("AVO_CHEST_V3_5_0/src/usb_sync.cpp", '\\"name\\":\\"AVO-CHEST\\",', '\\"name\\":\\"AVO-CHEST\\",\\"model\\":\\"CASCO-V5\\",')

print("AVO CASCO 5.0.0 aplicado sobre el pecho 3.7.11")
