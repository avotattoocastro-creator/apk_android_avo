#!/usr/bin/env python3
"""Static checks of V3.7.5 (internal RAM). Run from the root of the patched tree."""
from pathlib import Path
import re, sys

src = Path("AVO_CHEST_V3_5_0/src")
read = lambda n: (src / n).read_text()
main, ble, ui, build = read("app_main.cpp"), read("ble_service.cpp"), read("ui.cpp"), Path("build_chest.sh").read_text()
fails = []
def check(c, m):
    if not c: fails.append(m)

check("CONFIG_BT_NIMBLE_MEM_ALLOC_MODE_EXTERNAL=1" in build, "NimBLE host in PSRAM")
check("ROLE_CENTRAL_DISABLED" in build and "ROLE_OBSERVER_DISABLED" in build, "NimBLE peripheral only")
check(not re.search(r"NimBLEScan|getScan\(|createClient|NimBLEClient", ble), "the firmware does not use scanning/client (required to disable roles)")
i = main.index("heap_caps_malloc_extmem_enable(1024)")
check(i < main.index("appstate::init();"), "extmem enabled before any allocation")
# PSRAM stacks only in tasks that do not write flash
def task_body(text, name):
    m = re.search(r"static void " + name + r"\(void\*\) \{(.*?)\n\}", text, re.S)
    return m.group(1) if m else ""
tx = task_body(ble, "tx_task")
check(tx != "", "ble_tx task located")
for bad in ["nvs_set", "nvs_commit", "esp_partition_write", "esp_partition_erase", "ota::", "cfgstore::set", "Update."]:
    check(bad not in tx, f"ble_tx writes flash ({bad}) — it cannot have its stack in PSRAM")
uitask = task_body(ui, "task")
for bad in ["nvs_set", "esp_partition_write", "ota::", "cfgstore::set"]:
    check(bad not in uitask, f"ui_lite writes flash ({bad}) — it cannot have its stack in PSRAM")
check("WithCaps" not in ble, "rc2: ble_tx stack internal")
check("WithCaps" not in ui, "rc2: ui_lite stack internal")
check("UiFb::W * 4;" in ui, "rc3: 4-row DMA buffer")
check('xTaskCreatePinnedToCore(rx_task, "ble_rx", 6144' in ble, "ble_rx keeps an internal stack (it writes NVS/OTA)")
check("[AVO MEM] ready internal=" in main, "memory at the end of boot in the monitor")
if fails:
    print("FAIL:", *fails, sep="\n  "); sys.exit(1)
print("test_ram_v375: OK")
