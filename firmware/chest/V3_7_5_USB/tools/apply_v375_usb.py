#!/usr/bin/env python3
"""AVO CHEST V3.7.5-usb1 — training download to the PC over USB (on top of 3.7.5-rc5).

Run from the prepared source tree (same order as build-chest-v375.yml, then this script). The workflow copies
firmware/chest/V3_7_5_USB/src/usb_sync.{h,cpp} into AVO_CHEST_V3_5_0/src/ before running it.

Changes (RAW format, recording, BLE, ESP-NOW, NTRIP/RTCM, GNSS, OTA, Wi-Fi and partitions are NOT touched):
  1. app_main.cpp: usbsync::init() after wifisync::init() (three PSRAM buffers, ~10 KB; no internal RAM).
  2. app_main.cpp: the Arduino loop task, which only slept 1 s, now polls the USB serial port every 10 ms and
     answers the AVO1 commands of the Windows app. No new task: the loop task stack already exists.
  3. ui.cpp / ui_dash.cpp: "CONECTADO AL PC" screen instead of the charging screen ONLY while a USB host (PC) is on
     the cable (USB start-of-frame seen, or AVO1 commands). With a charger or power bank the charging screen is
     drawn exactly as before. Same rules as the charging screen: a recording shows the cards, a short tap shows the
     cards for 30 s, OTA/shutdown screens keep priority, same brightness handling.
"""
from pathlib import Path
import sys


def patch(path, old, new, count=1):
    p = Path(path)
    s = p.read_text()
    if s.count(old) != count:
        sys.exit(f"apply_v375_usb: anchor not found ({s.count(old)}x) in {path}: {old[:70]!r}")
    p.write_text(s.replace(old, new))


SRC = "AVO_CHEST_V3_5_0/src"

for f in ("usb_sync.h", "usb_sync.cpp", "ui_pc.h", "ui_pc.inc"):
    if not Path(f"{SRC}/{f}").is_file():
        sys.exit(f"apply_v375_usb: {SRC}/{f} missing (copy firmware/chest/V3_7_5_USB/src first)")

patch(f"{SRC}/app_main.cpp", '#include "wifi_sync.h"\n', '#include "wifi_sync.h"\n#include "usb_sync.h"\n')

patch(f"{SRC}/app_main.cpp",
      '  boot_log("wifisync", wifi_ok);\n',
      '  boot_log("wifisync", wifi_ok);\n'
      '  bool usb_ok = usbsync::init();      // V3.7.5-usb1: download to the PC over USB (buffers in PSRAM)\n'
      '  boot_log("usbsync", usb_ok);\n')

patch(f"{SRC}/app_main.cpp",
      "void app_loop() {\n"
      "  // Every function runs in its own FreeRTOS task; the Arduino loop task is idle.\n"
      "  vTaskDelay(pdMS_TO_TICKS(1000));\n"
      "}",
      "void app_loop() {\n"
      "  // Every function runs in its own FreeRTOS task. V3.7.5-usb1: the loop task (idle until now) answers the\n"
      "  // AVO1 commands of the Windows app on the USB serial port. Read-only, never during a recording.\n"
      "  usbsync::poll();\n"
      "  vTaskDelay(pdMS_TO_TICKS(10));\n"
      "}")

# 3. PC screen
Path(f"{SRC}/ui_dash.cpp").write_text(Path(f"{SRC}/ui_dash.cpp").read_text() +
                                      '\n// V3.7.5-usb1: "CONECTADO AL PC" screen (same fonts/icons/colours)\n#include "ui_pc.inc"\n')
patch(f"{SRC}/ui.cpp", '#include "ui_model.h"\n', '#include "ui_model.h"\n#include "ui_pc.h"\n#include "usb_sync.h"\n')
patch(f"{SRC}/ui.cpp",
      "static bool pair_latched = false;\n",
      """// V3.7.5-usb1: PC on the cable → "CONECTADO AL PC" instead of the charging screen (a charger keeps the old one).
static void render_pc(const AppSnapshot& s, uint32_t now) {
  static uint32_t last_sig = 0, last_draw = 0;
  usbsync::PcStatus st;
  usbsync::pc_status(&st);
  dash::PcModel pc;
  pc.phase = (dash::PcPhase)st.phase; pc.index = st.index; pc.count = st.count; pc.pct = st.pct; pc.new_count = st.new_count;
  ui_model::build(s, now, &model);
  const uint32_t sig = dash::pc_hash(pc, model.batt);
  if (shown == Shown::OTHER && charge_screen && sig == last_sig && (uint32_t)(now - last_draw) < 10000) return;
  last_sig = sig;
  last_draw = now;
  charge_screen = true;      // leaving it invalidates the cards exactly like the charging screen
  shown = Shown::OTHER;      // so the charging screen redraws fully if the PC goes away
  dash::draw_pc(fb, pc, model.batt);
  fb.flush(panel);
}
static bool pair_latched = false;
""")
patch(f"{SRC}/ui.cpp",
      "          if (charging_usb && !recording && !tap_cards) {\n            render_charging(*snap, now);\n",
      "          if (charging_usb && !recording && !tap_cards) {\n"
      "            if (usbsync::host_present()) render_pc(*snap, now);   // V3.7.5-usb1\n"
      "            else render_charging(*snap, now);\n")

print("apply_v375_usb: OK")
