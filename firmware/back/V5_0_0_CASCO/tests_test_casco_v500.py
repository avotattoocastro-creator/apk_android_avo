#!/usr/bin/env python3
"""AVO CASCO 5.0.0 — comprobaciones estáticas sobre el árbol ya parcheado (se ejecuta dentro de él).
Reglas de firmware de la revisión previa a fabricación del casco (claude/AVO_BACK_V5_REVISION_PRE_FABRICACION) y
contratos que no pueden cambiar. No sustituye a la prueba en la placa."""
import pathlib
import re

S = pathlib.Path("AVO_CHEST_V3_5_0/src")
L = pathlib.Path("lib/avo_core/src")
src = {p.name: p.read_text() for p in S.iterdir() if p.suffix in (".cpp", ".h")}
pins, hal, back, ui = src["board_pins.h"], src["hal_board.cpp"], src["casco_back.cpp"], src["ui.cpp"]


def pin(name):
    return int(re.search(rf"#define {name} (\d+)", pins).group(1))


# Mapa de pines del casco (avo_back_v5_pcb.py, diccionario GPIO de U4)
expected = {"PIN_I2C_SDA": 42, "PIN_I2C_SCL": 41, "PIN_SD_CLK": 12, "PIN_SD_CMD": 13, "PIN_SD_D0": 14, "PIN_SD_D1": 15,
            "PIN_SD_D2": 16, "PIN_SD_D3": 17, "PIN_SD_PWR_N": 21, "PIN_PWR_HOLD": 46, "PIN_TOUCH": 11, "PIN_VBUS_DET": 18,
            "PIN_CHG_PG": 38, "PIN_CHG_STAT": 39, "PIN_BAT_ADC": 2, "PIN_HALL": 1, "PIN_IMU_INT1": 4, "PIN_ZED_RX": 5,
            "PIN_ZED_TX": 6, "PIN_ZED_RX2": 3, "PIN_ZED_TX2": 8, "PIN_ZED_PPS": 7, "PIN_ZED_RST": 9, "PIN_ZED_EN": 10,
            "PIN_LED_DIN": 47, "PIN_LED_PWR": 48}
for k, v in expected.items():
    assert pin(k) == v, f"{k} = {pin(k)}, la placa dice {v}"
for psram in (35, 36, 37):   # PSRAM octal del N16R8
    assert not re.search(rf"#define PIN_\w+ {psram}\b", pins), f"GPIO{psram} es de la PSRAM"
assert "#define PIN_BOOT_BTN PIN_TOUCH" in pins and "#define PIN_PWR_SENSE PIN_TOUCH" in pins

# Regla 1: PWR_HOLD a 1 en initVariant (antes de setup) y retenido
iv = hal[hal.index('extern "C" void initVariant()'):hal.index("namespace board {")]
assert "gpio_set_level((gpio_num_t)PIN_PWR_HOLD, 1)" in iv and "gpio_hold_en((gpio_num_t)PIN_PWR_HOLD)" in iv
assert iv.index("PIN_PWR_HOLD, 1") < iv.index("PIN_LED_PWR"), "PWR_HOLD tiene que ser lo primero"
# Regla 2: antes de bajar ZED_EN, TX hacia el ZED a 0
off = back[back.index("static void zed_power_off"):back.index("void power_off_peripherals")]
assert off.index("gpio_set_level((gpio_num_t)PIN_ZED_TX, 0)") < off.index("digitalWrite(PIN_ZED_EN, LOW)")
assert off.index("gpio_set_level((gpio_num_t)PIN_ZED_TX2, 0)") < off.index("digitalWrite(PIN_ZED_EN, LOW)")
# Regla 3: líneas de la microSD en entrada antes de cortar su alimentación
pof = back[back.index("void power_off_peripherals"):back.index("void set_battery_mv")]
assert pof.index("pinMode(p, INPUT)") < pof.index("digitalWrite(PIN_SD_PWR_N, HIGH)")
# Regla 4: encendido escalonado (ZED a 1,5 s, anillo a 2,5 s) y corte por batería (PowerPolicy del pecho, 3,45 V)
assert "ZED_ON_DELAY_MS = 1500" in back and "now - t0 < 2500" in ui
# Regla 5: anillo con DIN a 0 apagado y brillo máximo 30 %
assert "#define LED_MAX_BRIGHT 77" in pins and "digitalWrite(PIN_LED_DIN, LOW)" in ui and "LED_MAX_BRIGHT / 255.0f" in ui
# Regla 6: RESET_N del ZED nunca se mueve (solo en entrada)
assert "PIN_ZED_RST" not in back and "gpio_set_direction((gpio_num_t)PIN_ZED_RST, GPIO_MODE_INPUT)" in hal
# Regla 7: el MAX17048 se lee a partir de 3 s
assert "millis() - s_boot_ms >= 3000" in hal

# Enlace interno: el pecho nunca transmite por radio, la espalda solo a las cinchas
u = src["uart_link.cpp"]
assert "return casco_back::to_back(d, n);" in u and "esp_now_send" not in u.split("static bool radio_send")[1].split("}")[0]
assert "casco_back::on_air(" in u and "void loopback_rx(" in u
assert "r.pair_id = casco_back::pair_id();" in u
# Táctil: 3 s apaga; 2 toques sesión; el despertar del sueño es en ALTO
c = src["controller.cpp"]
assert "AVO_BTN_PRESSED(digitalRead(PIN_BOOT_BTN))" in c and "esp_sleep_enable_ext0_wakeup((gpio_num_t)PIN_BOOT_BTN, 1)" in c
assert "static PowerKey s_pwr(3000);" in c

# Identidad y contratos
v = (L / "avo_version.h").read_text()
assert '"AVO-CASCO"' in v and '"5.0.0"' in v and "0x050000" in v
assert re.fullmatch(r"\d+\.\d+\.\d+", re.search(r'AVO_FW_VERSION "([^"]+)"', v).group(1)), "versión X.Y.Z sin sufijos"
o = src["ota.cpp"]
assert '"AVO_CASCO_V5_ESP32S3"' in o and "AVOCHEST-IMG" not in o
bp = (L / "avo_ble_proto.h").read_text()
assert "TELEMETRY_V3_LEN = 83 + 1 + 14 + 4 + 8 + 4 + 2" in bp   # 116 B, como el pecho
assert '\\"name\\":\\"AVO-CHEST\\"' in src["usb_sync.cpp"]          # USB AVO1: el nombre que buscan las apps no cambia
for gone in ("ui_fb.cpp", "ui_model.cpp", "ui_dash.cpp"):
    assert gone not in src
print("PASS: casco 5.0.0 — reglas de la placa y contratos (estático; no sustituye a la prueba en la placa)")
