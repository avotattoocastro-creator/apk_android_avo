#!/usr/bin/env python3
"""V3.7.2 minimal source patch on top of the 3.7.0-rc2 tree (run from the tree root).

ONLY publishes the shutdown phase for the screen. Communications (BLE, ESP-NOW, UART,
NTRIP/RTCM, GNSS), OTA and storage code are NOT touched; the shutdown order is unchanged:
each phase value is written right after the step that already existed.
"""
from pathlib import Path

def patch(path, old, new, count=1):
    p = Path(path)
    s = p.read_text()
    assert s.count(old) == count, f"{path}: expected {count} match(es) for:\n{old}"
    p.write_text(s.replace(old, new))

# 1) Two fields in PowerState (read by the UI only).
patch("AVO_CHEST_V3_5_0/src/app_state.h",
      "  bool shutdown_requested = false;\n",
      "  bool shutdown_requested = false;\n"
      "  // V3.7.2 screen only: 1 stopping session, 2 closing SD files, 3 saving black box,\n"
      "  // 4 power off, 5 failed (SD could not be closed; power kept on).\n"
      "  uint8_t shutdown_phase = 0;\n"
      "  uint32_t shutdown_fail_ms = 0;\n")

C = "AVO_CHEST_V3_5_0/src/controller.cpp"
patch(C,
      "  appstate::update([&](AppSnapshot& s) { s.power.shutdown_requested = true; s.sys.display_on = true; });\n",
      "  appstate::update([&](AppSnapshot& s) { s.power.shutdown_requested = true; s.sys.display_on = true; s.power.shutdown_phase = 1; });\n")
patch(C,
      "  if (s_life.active()) { s_fsm->manual_stop(now); apply_actions(now); }\n  bool ok = storage::shutdown(8000);\n",
      "  if (s_life.active()) { s_fsm->manual_stop(now); apply_actions(now); }\n"
      "  appstate::update([](AppSnapshot& s) { s.power.shutdown_phase = 2; });\n"
      "  bool ok = storage::shutdown(8000);\n"
      "  if (ok) appstate::update([](AppSnapshot& s) { s.power.shutdown_phase = 3; });\n")
patch(C,
      "    appstate::update([](AppSnapshot& s) { s.power.shutdown_requested = false; });\n",
      "    appstate::update([](AppSnapshot& s) { s.power.shutdown_requested = false; s.power.shutdown_phase = 5; s.power.shutdown_fail_ms = sys::ms(); });\n")
patch(C,
      "  board::pmu_power_off();\n",
      "  appstate::update([](AppSnapshot& s) { s.power.shutdown_phase = 4; });\n"
      "  vTaskDelay(pdMS_TO_TICKS(300));  // V3.7.2: let the screen show the final phase\n"
      "  board::pmu_power_off();\n")
print("V3.7.2 patch applied (app_state.h, controller.cpp: shutdown phase only)")
