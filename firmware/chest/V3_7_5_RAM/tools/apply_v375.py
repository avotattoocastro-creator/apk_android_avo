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

# 3d. rc4: screen paused while the Wi-Fi AP is on (the watch is never recording then). The UI task draws a fixed
#     "DESCARGA WI-FI" notice, deletes itself and its DMA transfer buffer is freed (~4 KB stack + ~3 KB buffer);
#     when Wi-Fi turns off, the buffer is allocated again and the task recreated with a full repaint.
patch(f"{SRC}/services.h", "void home_screen();\n}  // namespace ui",
      "void home_screen();\nvoid pause_for_wifi();      // V3.7.5-rc4: free UI RAM while the Wi-Fi AP is on\nvoid resume_after_wifi();\n}  // namespace ui")
patch(f"{SRC}/ui.cpp", "  fb.attach(pixels, line, line_px, UI_ROTATE_180);\n",
      "  fb.attach(pixels, line, line_px, UI_ROTATE_180);\n  s_pixels = pixels; s_line = line;   // V3.7.5-rc4: kept for pause/resume around Wi-Fi\n")
patch(f"{SRC}/ui.cpp", "static UiFb fb;\n",
      "static UiFb fb;\nstatic volatile bool s_pause_req = false, s_paused = false;   // V3.7.5-rc4\nstatic uint16_t* s_pixels = nullptr;\nstatic uint16_t* s_line = nullptr;\n")
patch(f"{SRC}/ui.cpp", "  bool special_screen = false;\n  for (;;) {\n",
      """  bool special_screen = false;
  for (;;) {
    if (s_pause_req) {   // V3.7.5-rc4: Wi-Fi download → fixed notice, then the task ends (RAM back to Wi-Fi)
      if (display_on) {
        gfx->fillScreen(0x0000);
        gfx->setRotation(UI_ROTATE_180 ? 2 : 0);
        gfx->setTextColor(0xFFFF, 0x0000); gfx->setTextSize(3);
        gfx->setCursor(80, LCD_HEIGHT / 2 - 12); gfx->print("DESCARGA WI-FI");
        gfx->setRotation(0);
      }
      snap->~AppSnapshot(); heap_caps_free(snap);
      g_task_handles[TID_UI] = nullptr;
      s_paused = true;
      vTaskDelete(nullptr);
      return;
    }
""")
patch(f"{SRC}/ui.cpp", "} // namespace ui", r"""void pause_for_wifi() {
  if (s_paused || !g_task_handles[TID_UI]) return;
  s_pause_req = true;
  for (int i = 0; i < 40 && !s_paused; i++) vTaskDelay(pdMS_TO_TICKS(25));
  if (!s_paused) { s_pause_req = false; return; }
  if (s_line) { heap_caps_free(s_line); s_line = nullptr; }
  Serial.printf("[AVO UI] paused for Wi-Fi: internal=%u largest=%u\n",
    (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
    (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT));
}
void resume_after_wifi() {
  if (!s_paused) return;
  size_t px = (size_t)UiFb::W * 4;
  auto* l = static_cast<uint16_t*>(heap_caps_malloc(px * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA | MALLOC_CAP_8BIT));
  if (!l) { px = (size_t)UiFb::W * 2; l = static_cast<uint16_t*>(heap_caps_malloc(px * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT)); }
  if (!l) { Serial.println("[AVO UI] resume: no RAM for the transfer buffer"); return; }
  s_line = l;
  fb.attach(s_pixels, l, px, UI_ROTATE_180);
  for (auto& v : old_state) v = UINT32_MAX;
  shown = Shown::NONE; charge_screen = false; invalidate_cards();
  s_pause_req = false; s_paused = false;
  BaseType_t ok = xTaskCreatePinnedToCore(task, "ui_lite", 4096, nullptr, 2, &g_task_handles[TID_UI], 0);
  Serial.printf("[AVO UI] resumed after Wi-Fi: task=%s\n", ok == pdPASS ? "OK" : "FAIL");
}
} // namespace ui""")

# 3e. rc5: Wi-Fi download speed. The watch has one radio for Wi-Fi, BLE and ESP-NOW. While the AP is on:
#     BLE telemetry stops and the BLE link asks for a long connection interval (100–150 ms, latency 4) so the
#     radio is free for Wi-Fi most of the time; the normal interval is requested again when Wi-Fi turns off
#     (whatever the reason: app, idle, error). BLE stays connected for control and as fallback.
patch(f"{SRC}/ble_service.cpp",
      "    uint32_t now = sys::ms();\n    // V3.7.3: telemetry paused",
      """    uint32_t now = sys::ms();
    {  // V3.7.5-rc5: radio for Wi-Fi while the AP is on
      static bool slow = false;
      bool wifi_on = wifisync::state() != wifisync::State::OFF;
      if (!s_connected) slow = false;
      else if (wifi_on != slow && s_srv && s_conn != 0xFFFF) {
        bool ok = wifi_on ? s_srv->updateConnParams(s_conn, 80, 120, 4, 600) : s_srv->updateConnParams(s_conn, 12, 24, 0, 400);
        Serial.printf("[AVO BLE] conn params %s (%s)\\n", wifi_on ? "slow for Wi-Fi" : "normal", ok ? "OK" : "FAIL");
        slow = wifi_on;
      }
    }
    // V3.7.3: telemetry paused""")
patch(f"{SRC}/ble_service.cpp",
      "if (s_connected && is_authorized() && now - last_tel >= 500 && (uint32_t)(now - s_last_file_ms) > 1500) {",
      "if (s_connected && is_authorized() && now - last_tel >= 500 && (uint32_t)(now - s_last_file_ms) > 1500 &&\n        wifisync::state() == wifisync::State::OFF) {   // V3.7.5-rc5: no telemetry during Wi-Fi download")

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
