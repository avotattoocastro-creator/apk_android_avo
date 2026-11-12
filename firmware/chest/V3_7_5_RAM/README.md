# CHEST V3.7.5-rc1 — Internal RAM freed (+ on-demand Wi-Fi)

**BIN UNVERIFIED.** Install only over USB with AVO Update; it is not suitable for OTA until it has been validated. If it fails, the watch automatically goes back to the previous version (otadata NEW → rollback).

## Measured data (USB serial monitor, 3.7.3-rc1, boot #254)

| Point | Free internal | Largest block |
|---|---|---|
| Before BLE | 122 972 | 81 908 |
| After BLE | 44 320 | 31 732 |
| After control | 23 916 | 14 324 |
| After UI (end) | **11 772** | **7 156** |

With that margin:
- 3.7.4-rc1 rebooted when bringing up the Wi-Fi AP;
- the 8 KB task of 3.7.4-rc2 left no room for the UI, so the watch rolled back to 3.7.3.
- The occasional `new AppSnapshot()` every 500 ms (ble_tx/ctl) could also fail. This is a likely cause of BLE drops, **not confirmed**.

## Changes (base 3.7.3-rc1 + 3.7.4 Wi-Fi)

1. **NimBLE host in PSRAM** (`CONFIG_BT_NIMBLE_MEM_ALLOC_MODE_EXTERNAL`). Peripheral role only: the central and observer roles are removed, since the firmware neither scans nor acts as a client.
2. **`heap_caps_malloc_extmem_enable(1024)`** at the start of `setup`: malloc/new ≥ 1 KB go to PSRAM. Allocations with explicit `INTERNAL`/`DMA` caps (radio, display, SD) do not change.
3. **`ble_tx` and `ui_lite` stacks in PSRAM.** Checked: neither of these tasks writes to flash. `ble_rx` (NVS/OTA), `storage`, `link_rx/tx` and `bb` keep their stacks in internal RAM.
4. **On-demand Wi-Fi:**
   - the task is created only when the app asks for the AP and is deleted when it turns off, so nothing is reserved at boot;
   - `WiFi.persistent(false)`;
   - minimum to turn on: 40 KB free and a 16 KB block;
   - it prints `[AVO WIFI] AP up … (cost N B)` to measure the real cost;
   - the rc2 reboot breadcrumb is kept: if the watch reboots while turning on Wi-Fi, Wi-Fi is disabled.
5. Line `[AVO MEM] ready internal=… largest=… min=…` at the end of boot.

**Target: ready internal ≥ 60 KB and largest ≥ 32 KB.** Not measured yet: it requires the physical test.

## Physical test (in order; stop at the first failure)

1. Install with AVO Update over USB → **«Reiniciar reloj y capturar»** (AVO Update 2.2.1 monitor) → save the .txt.
   - It must reach `AVO-CHEST 3.7.5-rc1 ready`.
   - Note the values of `[AVO MEM] ready`.
2. With the app: connect, read the list and download one training over Bluetooth. Check that there are no reboots and that the monitor shows nothing abnormal.
3. 10 minutes connected with telemetry and NTRIP (RTK FIX) without reboots.
4. Short recording (2 min): the RAW file closes normally.
5. Only if 1–4 pass: download over Wi-Fi from the app. Note `[AVO WIFI] AP up … cost`. Telemetry from the back must keep arriving during the download.

If at step 1 the watch goes back to 3.7.3 by itself, send the monitor .txt: it will show the last line before the failure.
