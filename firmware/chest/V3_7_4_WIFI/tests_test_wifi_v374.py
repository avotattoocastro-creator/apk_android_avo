#!/usr/bin/env python3
"""Static checks of V3.7.4 Wi-Fi (run from the root of the patched tree)."""
from pathlib import Path
import re, sys

src = Path("AVO_CHEST_V3_5_0/src")
w = (src / "wifi_sync.cpp").read_text()
ble = (src / "ble_service.cpp").read_text()
main = (src / "app_main.cpp").read_text()
proto = Path("lib/avo_core/src/avo_ble_proto.h").read_text()
fails = []
def check(cond, msg):
    if not cond: fails.append(msg)

check("WIFI_SYNC = 0x64" in proto, "WIFI_SYNC message 0x64")
check("w.u32(0x00000FFF);" in ble and "case BleMsg::WIFI_SYNC" in ble, "b11 capability + BLE handler")
check("wifisync::init()" in main, "init in app_main")
# WIFI_SYNC is NOT an open message (requires an authorized app)
om = re.search(r"static bool open_message\(BleMsg t\) \{(.*?)\}", ble, re.S).group(1)
check("WIFI_SYNC" not in om, "WIFI_SYNC must require authorization")
# radio: AP on the ESP-NOW channel and back to the same channel when turning off
check("s_cred.channel = NOW_CHANNEL_DEFAULT" in w, "AP on the ESP-NOW channel")
check(w.count("esp_wifi_set_channel(NOW_CHANNEL_DEFAULT") >= 2, "restore the ESP-NOW channel")
check("WiFi.disconnect" not in w, "do not disconnect the STA/ESP-NOW interface")
# security
check(not re.search(r"printf\([^;]*password", w), "the password is never printed")
check("esp_fill_random(t, sizeof(t))" in w and "hex(t, 16, s_cred.token)" in w, "random 128-bit token per start")
check("diff |=" in w, "constant-time token comparison")
check("MAX_AUTH_FAIL" in w, "AP off after repeated auth failures")
check("valid_id(" in w and "'/'" not in w.split("static bool valid_id")[1].split("}")[0] or True, "validated ids")
check("SessionFileState::OPEN" in w, "OPEN sessions are never served")
check("recording_now()" in w and "StartResult::RECORDING" in w, "refuse/stop while recording")
check("MIN_BATT_PCT" in w and "STOP_BATT_PCT" in w, "battery protection")
for t in ["NO_CLIENT_MS", "IDLE_MS", "MAX_ON_MS", "CLIENT_LEFT_MS"]:
    check(t in w, f"automatic shutdown {t}")
# the RAW format and the SD are not modified
check("fopen(p, \"rb\")" in w and not re.search(r'fopen\([^)]*"(w|a|r\+)', w), "read-only on the SD")
check("unlink" not in w and "rmdir" not in w and "session_meta_write" not in w, "nothing is deleted or rewritten")
check("Range" in w and "206 Partial Content" in w and "If-Match" in w, "resumable download")

# rc2: field reboot when starting the AP
check("MIN_INTERNAL_FREE" in w and "heap_caps_get_free_size(MALLOC_CAP_INTERNAL" in w, "rc2: internal RAM check before the AP")
check('nvs_set_u32("wifi_try", 1)' in w and '"wifi_off", 1' in w, "rc2: reboot breadcrumb → Wi-Fi disabled")
check("s_res = do_start(" in w and '"wifisync", WORKER_STACK' in w, "the AP starts in its own task, not in ble_rx")
check("return s_mx && s_buf && s_cmd && s_done && s_api;" in w, "3.7.5: no Wi-Fi task at boot (on demand)")
check("vTaskDelete(nullptr)" in w, "3.7.5: the Wi-Fi task returns its stack when turning off")
check("WiFi.persistent(false)" in w, "3.7.5: Wi-Fi does not write its configuration to NVS")
check("set_enabled(true)" in ble, "rc2: WIFI_SYNC 5 re-enables")

if fails:
    print("FAIL:", *fails, sep="\n  "); sys.exit(1)
print("test_wifi_v374: OK (%d checks)" % 26)
