#!/usr/bin/env python3
"""AVO CHEST V3.7.5-usb1 — training download to the PC over USB (on top of 3.7.5-rc5).

Run from the prepared source tree (same order as build-chest-v375.yml, then this script). The workflow copies
firmware/chest/V3_7_5_USB/src/usb_sync.{h,cpp} into AVO_CHEST_V3_5_0/src/ before running it.

Changes (RAW format, recording, BLE, ESP-NOW, NTRIP/RTCM, GNSS, OTA, Wi-Fi and partitions are NOT touched):
  1. app_main.cpp: usbsync::init() after wifisync::init() (three PSRAM buffers, ~10 KB; no internal RAM).
  2. app_main.cpp: the Arduino loop task, which only slept 1 s, now polls the USB serial port every 10 ms and
     answers the AVO1 commands of the Windows app. No new task: the loop task stack already exists.
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

for f in ("usb_sync.h", "usb_sync.cpp"):
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

print("apply_v375_usb: OK")
