#!/usr/bin/env python3
"""AVO CHEST 3.7.7 DESPERTAR — applied on top of the 3.7.6 GNSS QUALITY tree (run from the tree root).

1. Back sleep (BACK >= 3.14.0):
   - controlled_shutdown(): after the SD is closed and just before the PMIC cuts the power, the chest sends the
     back command BACK_SLEEP (8) twice, 150 ms apart (the back ACKs and goes to deep sleep at once).
   - tx_task(): while the chest is paired but the back link is down, a short DATA packet (one HEARTBEAT frame) is sent
     to the paired back every 100 ms, so a sleeping back that listens 160 ms every 10 s hears it and starts.
2. Wi-Fi download:
   - The "Wi-Fi disabled after a reboot while starting the AP" flag (NVS wifi_off) now remembers the firmware that set
     it (NVS wifi_off_fw). With another firmware it is cleared at boot: a block left by an older firmware (field case
     3.7.4-wifi-rc1, reboot loop when starting the AP) no longer disables Wi-Fi forever. The breadcrumb still blocks
     again if this firmware reboots while starting the AP.
   - Distinct refusal reasons over BLE: 6 = disabled after a reboot, 7 = not enough internal RAM (was 4 for both).
3. Bluetooth with several phones (build flags in build_chest.sh, see INFORME.md):
   - NimBLE kept 3 bonds and 8 CCCDs. Each phone subscribes to 3 notifications (CTRL_TX, TELEM, FILE): the third
     phone overflowed the CCCD store and NimBLE deleted the OLDEST phone's bond. That phone still had its key and
     its next connection failed encryption (quick disconnects). Now 6 bonds and 20 CCCDs.
Nothing else changes: RAW/SD, sessions, ESP-NOW frames, NTRIP/RTCM, GNSS, OTA, partitions, screens and USB.
"""
from pathlib import Path
import sys

ROOT = Path('.')
SRC = ROOT / 'AVO_CHEST_V3_5_0' / 'src'


def patch(path: Path, old: str, new: str, count: int = 1):
    s = path.read_text()
    n = s.count(old)
    if n != count:
        sys.exit(f'apply_v377: {path}: expected {count} match(es), found {n}:\n{old}')
    path.write_text(s.replace(old, new))


# ---------------------------------------------------------------- 1. back sleep
patch(SRC / 'services.h',
      'bool pair_forget();\n}  // namespace uartlink',
      'bool pair_forget();\n'
      '// V3.7.7: asks the back (BACK >= 3.14.0) to go to deep sleep now (the chest is switching off).\n'
      'bool sleep_back();\n'
      '}  // namespace uartlink')

UL = SRC / 'uart_link.cpp'
patch(UL,
      'bool pair_start(uint32_t window_ms) {',
      '// V3.7.7: BackCmd::BACK_SLEEP (8) of BACK 3.14.0. Older backs answer NACK (unknown command) and keep running.\n'
      'static const uint16_t AVO_BACKCMD_BACK_SLEEP = 8;\n'
      'bool sleep_back() { return send_command((BackCmd)AVO_BACKCMD_BACK_SLEEP, nullptr, 0); }\n\n'
      'bool pair_start(uint32_t window_ms) {')
patch(UL,
      '    bool link_up;\n'
      '    appstate::lock(); link_up = appstate::raw().link.connected; appstate::unlock();\n',
      '    bool link_up;\n'
      '    appstate::lock(); link_up = appstate::raw().link.connected; appstate::unlock();\n'
      '    {  // V3.7.7: wake beacon for a sleeping back (BACK >= 3.14.0 listens 160 ms every 10 s)\n'
      '      static uint32_t last_wake = 0;\n'
      '      static uint32_t wake_sent = 0;\n'
      '      if (s_pair.paired() && !link_up && now - last_wake >= 100) {\n'
      '        last_wake = now;\n'
      '        Heartbeat hb;\n'
      '        hb.uptime_ms = now;\n'
      '        uint8_t hp[HEARTBEAT_V1_LEN], fr[64], pkt[NOW_MAX_PACKET];\n'
      '        size_t fn = encode_heartbeat(hb, hp, sizeof(hp))\n'
      '                    ? uart_encode(FrameType::HEARTBEAT, 0, (uint8_t)NodeId::CHEST, s_seq++, now, hp, HEARTBEAT_V1_LEN, fr, sizeof(fr)) : 0;\n'
      '        NowHeader wh; wh.kind = NowKind::DATA; wh.pair_id = s_pair.peer().pair_id; wh.boot_id = s_boot_id;\n'
      '        size_t pn = fn ? now_build(wh, fr, fn, pkt, sizeof(pkt)) : 0;\n'
      '        if (pn) { radio_send(s_pair.peer().mac, pkt, pn); wake_sent++; }   // single shot: no retries\n'
      '        if (wake_sent % 600 == 1) Serial.printf("[AVO NOW] espalda sin enlace: baliza de despertar cada 100 ms (%u enviadas)\\n", (unsigned)wake_sent);\n'
      '      }\n'
      '    }\n')

CTL = SRC / 'controller.cpp'
patch(CTL,
      '  appstate::update([](AppSnapshot& s) { s.power.shutdown_phase = 4; });\n',
      '  appstate::update([](AppSnapshot& s) { s.power.shutdown_phase = 4; });\n'
      '  // V3.7.7: the back (BACK >= 3.14.0) goes to deep sleep now instead of waiting 90 s without the chest.\n'
      '  // Sent twice (different cmd_id); the back acts on the first one it receives.\n'
      '  uartlink::sleep_back();\n'
      '  vTaskDelay(pdMS_TO_TICKS(150));\n'
      '  uartlink::sleep_back();\n'
      '  bb::log(BbCode::SHUTDOWN, 0, 0x5B, 0, "back sleep sent");\n')

# ---------------------------------------------------------------- 2. Wi-Fi
WH = SRC / 'wifi_sync.h'
patch(WH,
      'enum class StartResult : uint8_t { OK = 0, RECORDING = 1, LOW_BATTERY = 2, NO_SD = 3, RADIO_ERROR = 4, BUSY = 5 };',
      'enum class StartResult : uint8_t { OK = 0, RECORDING = 1, LOW_BATTERY = 2, NO_SD = 3, RADIO_ERROR = 4, BUSY = 5,\n'
      '                                   DISABLED = 6, LOW_RAM = 7 };   // V3.7.7: reasons that were RADIO_ERROR')
WS = SRC / 'wifi_sync.cpp'
patch(WS,
      '  if (sys::nvs_get_u32("wifi_off", &off) && off) { unlock(); return StartResult::RADIO_ERROR; }',
      '  if (sys::nvs_get_u32("wifi_off", &off) && off) { unlock(); Serial.println("[AVO WIFI] refused: disabled after a reboot while starting the AP"); return StartResult::DISABLED; }')
patch(WS,
      '    bb::log(BbCode::SHUTDOWN, 1, 0x57, (uint32_t)freeb, "wifi: low internal RAM");\n'
      '    ui::resume_after_wifi();\n'
      '    unlock();\n'
      '    return StartResult::RADIO_ERROR;',
      '    bb::log(BbCode::SHUTDOWN, 1, 0x57, (uint32_t)freeb, "wifi: low internal RAM");\n'
      '    Serial.printf("[AVO WIFI] refused: low internal RAM (free %u < %u or block %u < %u)\\n", (unsigned)freeb,\n'
      '                  (unsigned)MIN_INTERNAL_FREE, (unsigned)largest, (unsigned)MIN_INTERNAL_BLOCK);\n'
      '    ui::resume_after_wifi();\n'
      '    unlock();\n'
      '    return StartResult::LOW_RAM;')
patch(WS,
      'bool init() {\n'
      '  uint32_t tried = 0;\n'
      '  if (sys::nvs_get_u32("wifi_try", &tried) && tried) {\n'
      '    // the previous boot rebooted while starting the AP: disable Wi-Fi (the app uses BLE) and record it\n'
      '    sys::nvs_set_u32("wifi_off", 1);\n',
      'bool init() {\n'
      '  {  // V3.7.7: a block set by ANOTHER firmware (or by one older than 3.7.7, which did not record it) is cleared\n'
      '    uint32_t off = 0;\n'
      '    char fw[24] = {0};\n'
      '    size_t fn = sizeof(fw) - 1;\n'
      '    const bool have_fw = sys::nvs_get_blob("wifi_off_fw", fw, &fn);\n'
      '    if (have_fw) fw[fn < sizeof(fw) ? fn : sizeof(fw) - 1] = 0;\n'
      '    if (sys::nvs_get_u32("wifi_off", &off) && off && (!have_fw || strcmp(fw, AVO_FW_VERSION) != 0)) {\n'
      '      sys::nvs_set_u32("wifi_off", 0);\n'
      '      bb::log(BbCode::SHUTDOWN, 0, 0x57, 0x0FF0, "wifi: old block cleared (new firmware)");\n'
      '      Serial.printf("[AVO WIFI] Wi-Fi block left by firmware %s cleared: Wi-Fi enabled again\\n", have_fw ? fw : "< 3.7.7");\n'
      '    }\n'
      '  }\n'
      '  uint32_t tried = 0;\n'
      '  if (sys::nvs_get_u32("wifi_try", &tried) && tried) {\n'
      '    // the previous boot rebooted while starting the AP: disable Wi-Fi (the app uses BLE) and record it\n'
      '    sys::nvs_set_u32("wifi_off", 1);\n'
      '    sys::nvs_set_blob("wifi_off_fw", AVO_FW_VERSION, strlen(AVO_FW_VERSION));   // V3.7.7\n')

# ---------------------------------------------------------------- 3. NimBLE bond / CCCD store
patch(ROOT / 'build_chest.sh',
      '-DCONFIG_BT_NIMBLE_ROLE_OBSERVER_DISABLED=1"',
      '-DCONFIG_BT_NIMBLE_ROLE_OBSERVER_DISABLED=1 -DCONFIG_BT_NIMBLE_MAX_BONDS=6 -DCONFIG_BT_NIMBLE_MAX_CCCDS=20"')

print('apply_v377: OK (back sleep + wake beacon, Wi-Fi block per firmware + reasons, NimBLE 6 bonds / 20 CCCDs)')
