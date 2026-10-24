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
  3. ble_tx and ui_lite stacks in PSRAM (xTaskCreatePinnedToCoreWithCaps). Checked: these tasks do not write to
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

# 3. task stacks without flash access in PSRAM
patch(f"{SRC}/ble_service.cpp",
      'BaseType_t tx_created = xTaskCreatePinnedToCore(tx_task, "ble_tx", 6144, nullptr, 6, &g_task_handles[TID_BLE_TX], 0);',
      '// V3.7.5: ble_tx only builds and notifies (no NVS/OTA/flash) → stack in PSRAM\n'
      '  BaseType_t tx_created = xTaskCreatePinnedToCoreWithCaps(tx_task, "ble_tx", 6144, nullptr, 6, &g_task_handles[TID_BLE_TX], 0, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);')
patch(f"{SRC}/ble_service.cpp", '#include "services.h"\n', '#include "services.h"\n#include "freertos/idf_additions.h"\n')
patch(f"{SRC}/ui.cpp",
      'BaseType_t ok = xTaskCreatePinnedToCore(task,"ui_lite",4096,nullptr,2,&g_task_handles[TID_UI],0);',
      '// V3.7.5: the UI draws from PSRAM and only notifies other tasks (no flash) → stack in PSRAM\n'
      '  BaseType_t ok = xTaskCreatePinnedToCoreWithCaps(task,"ui_lite",4096,nullptr,2,&g_task_handles[TID_UI],0,MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);')
patch(f"{SRC}/ui.cpp", '#include <esp_heap_caps.h>\n', '#include <esp_heap_caps.h>\n#include "freertos/idf_additions.h"\n')

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
