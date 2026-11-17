#!/usr/bin/env python3
"""Static checks of CHEST V3.7.6 GNSS QUALITY (usb1 base + BackStatus v3 + TELEMETRY v3 + freshness).
Run from the root of the patched tree (same place as the other tests/test_*.py)."""
from pathlib import Path
import re
import sys

lib = Path("lib/avo_core/src")
src = Path("AVO_CHEST_V3_5_0/src")
pay_h = (lib / "avo_payloads.h").read_text()
pay_c = (lib / "avo_payloads.cpp").read_text()
proto_h = (lib / "avo_ble_proto.h").read_text()
ble = (src / "ble_service.cpp").read_text()
ver = (lib / "avo_version.h").read_text()
fails = []


def check(c, m):
    print(("  ok   " if c else "  FAIL ") + m)
    if not c:
        fails.append(m)


# BackStatus v3: same decoder as BACK 3.13.11 (bytes appended after the 82-byte v2 block)
check("BACK_STATUS_V3_LEN = 82 + 14 + 4 + 8" in pay_h, "BackStatus v3 length = 108 (same constant as the back)")
check("s->v3 = r.ok();" in pay_c and "r.remaining() >= BACK_STATUS_V3_LEN - BACK_STATUS_V2_LEN" in pay_c,
      "v3 only accepted when the whole tail is present")
# TELEMETRY v3 (unchanged layout from apply_v376.py, decoded by Android Telemetry.V3_LEN = 116)
check("TELEMETRY_V3_LEN = 83 + 1 + 14 + 4 + 8 + 4 + 2" in proto_h, "TELEMETRY v3 length 116")
check("uint8_t b[TELEMETRY_V3_LEN + 8];" in ble and "TELEMETRY_V2_LEN + 8" not in ble, "telemetry buffer sized for v3")
# freshness: no stale back data presented as current
check("q_link_age_ms <= 5000" in ble and "s->link.status_valid && s->link.back.v3" in ble, "only a fresh BackStatus v3 is forwarded")
check("q_link_ms > 0 ? (uint32_t)q_link_ms : 0" in ble, "no unsigned wrap if the status arrives during the snapshot")
check("t.quality_age_s = (uint8_t)(qa > 254 ? 254 : qa);" in ble, "quality age includes the link age, 255 stays 'never'")
i = ble.find("q_link_age_ms <= 5000")
j = ble.find("t.sacc_mm_s = g.sacc_mm_s;", i)
check(0 < i < j and "t.q_flags = (uint8_t)(1 |" in ble[i:j], "q_flags is set only inside the freshness block")
check(ble.count("t.q_flags =") == 1, "q_flags assigned in exactly one place (default 0 = no data)")
# version: plain numeric so a future signed OTA from this version passes ota.cpp version_cmp()
check('#define AVO_FW_VERSION "3.7.6"' in ver and "#define AVO_FW_VERSION_NUM 0x030706" in ver, "version 3.7.6 / 0x030706")
# untouched: USB sync, OTA verification, partitions
check((src / "usb_sync.cpp").is_file() and "usbsync::poll();" in (src / "app_main.cpp").read_text(), "USB sync (3.7.5-usb1) kept")
ota = (src / "ota.cpp").read_text()
check('eq("alg","ES256")' in ota and "mbedtls_pk_verify" in ota and "kPublicSpki" in ota, "OTA ES256 verification kept")
check(re.search(r"version_cmp\(ver,AVO_FW_VERSION\)>0", ota) is not None, "OTA anti-rollback kept")

if fails:
    print("test_gnss_quality_v376: FAIL", fails)
    sys.exit(1)
print("test_gnss_quality_v376: OK")
