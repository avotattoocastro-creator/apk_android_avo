#!/usr/bin/env python3
"""AVO CHEST V3.7.5 — internal RAM freed (on top of 3.7.4 Wi-Fi).

Measured in the field (USB serial monitor, 3.7.3-rc1): at the end of boot only 11 772 B of internal RAM were free
(largest block 7 156 B). BLE takes ~78 KB, control ~20 KB, UI ~12 KB. With that margin the Wi-Fi AP rebooted the
watch (3.7.4-rc1) and the 8 KB task of rc2 left no room for the UI (automatic rollback to 3.7.3).

Changes (no changes to RAW, recording, ESP-NOW, OTA or partitions):
  1. NimBLE host with memory in PSRAM (CONFIG_BT_NIMBLE_MEM_ALLOC_MODE_EXTERNAL) and without the central/observer
     roles (the watch is peripheral only: no scanning or client).
  2. heap_caps_malloc_extmem_enable(1024): malloc/new >= 1 KB go to PSRAM (AppSnapshot every 500 ms,
     control objects…). Allocations with explicit INTERNAL/DMA caps do not change.
  3. (rc1, removed in rc2) ble_tx and ui_lite stacks in PSRAM (xTaskCreatePinnedToCoreWithCaps). Checked: these tasks do not write to
     flash (NVS/OTA/partitions); ble_rx, storage, link and bb keep their stacks in internal RAM.
  4. Line "ready" with the free internal RAM at the end of boot (target >= 60 KB, block >= 32 KB).
"""
from pathlib import Path
import sys


def patch(path, old, new, count=1):
    p = Path(path)
    s = p.read_text()
    if s.count(old) != count:
        sys.exit(f"apply_v375: anchor not found ({s.count(old)}x) in {path}: {old[:70]!r}")
    p.write_text(s.replace(old, new))


SRC = "AVO_CHEST_V3_5_0/src"

# 1. NimBLE: host in PSRAM, peripheral/broadcaster only
patch("build_chest.sh",
      'PMAP="-ffile-prefix-map=$HERE=AVO -ffile-prefix-map=$BP=AVOBUILD"',
      'PMAP="-ffile-prefix-map=$HERE=AVO -ffile-prefix-map=$BP=AVOBUILD'
      ' -DCONFIG_BT_NIMBLE_MEM_ALLOC_MODE_EXTERNAL=1 -DCONFIG_BT_NIMBLE_ROLE_CENTRAL_DISABLED=1 -DCONFIG_BT_NIMBLE_ROLE_OBSERVER_DISABLED=1"')

# 2. general allocations >= 1 KB to PSRAM, before any other subsystem
patch(f"{SRC}/app_main.cpp",
      "  Serial.begin(115200);  // USB CDC (GPIO19/20), never the link UART\n  appstate::init();",
      "  Serial.begin(115200);  // USB CDC (GPIO19/20), never the link UART\n"
      "  heap_caps_malloc_extmem_enable(1024);   // V3.7.5: malloc/new >= 1 KB in PSRAM (internal RAM for DMA/stacks/radio)\n"
      "  appstate::init();")

# 3. (rc1 only) ble_tx/ui_lite stacks in PSRAM — REMOVED in rc2: rc1 panicked right after "ready"
#    (RTC_SW_CPU_RST, reset PANIC) and kept rebooting. Most likely cause: buffers on the UI/BLE stack used for
#    SPI DMA or during flash-cache-disabled windows. All task stacks stay in internal RAM.

# 3b. rc3: UI DMA transfer buffer 16 → 4 rows (13 120 → 3 280 B internal). Same pixels, more (shorter) transfers.
patch(f"{SRC}/ui.cpp", "size_t line_px = (size_t)UiFb::W * 16;",
      "size_t line_px = (size_t)UiFb::W * 4;   // V3.7.5-rc3: 4 rows (frees ~9.8 KB of internal RAM for Wi-Fi)")

# 3c. rc4: stacks sized to their real use. link_rx/link_tx keep their big buffers static (not on the stack) and
#     ctl builds snapshots in PSRAM. High-water marks are printed when Wi-Fi starts ([AVO STACK]) to verify.
patch(f"{SRC}/uart_link.cpp",
      'xTaskCreatePinnedToCore(rx_task, "link_rx", 8192, nullptr, 18, nullptr, 1);\n  xTaskCreatePinnedToCore(tx_task, "link_tx", 8192, nullptr, 17, &s_tx_task, 1);',
      'xTaskCreatePinnedToCore(rx_task, "link_rx", 5120, nullptr, 18, nullptr, 1);   // V3.7.5-rc4: 8192 → 5120\n'
      '  xTaskCreatePinnedToCore(tx_task, "link_tx", 5120, nullptr, 17, &s_tx_task, 1);  // V3.7.5-rc4: 8192 → 5120')
patch(f"{SRC}/controller.cpp",
      'xTaskCreatePinnedToCore(task, "ctl", 8192, nullptr, 8, &g_task_handles[TID_CTRL], 1);',
      'xTaskCreatePinnedToCore(task, "ctl", 6144, nullptr, 8, &g_task_handles[TID_CTRL], 1);   // V3.7.5-rc4: 8192 → 6144')

# 4. memory at the end of boot (monitor)
patch(f"{SRC}/app_main.cpp",
      '  Serial.printf("[AVO] build fingerprint %s\\n", AVO_BUILD_FINGERPRINT);',
      '  Serial.printf("[AVO] build fingerprint %s\\n", AVO_BUILD_FINGERPRINT);\n'
      '  Serial.printf("[AVO MEM] ready internal=%u largest=%u min=%u psram=%u\\n",\n'
      '                (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),\n'
      '                (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),\n'
      '                (unsigned)heap_caps_get_minimum_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),\n'
      '                (unsigned)ESP.getFreePsram());')

print("apply_v375: OK")
