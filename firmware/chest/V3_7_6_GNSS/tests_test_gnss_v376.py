#!/usr/bin/env python3
"""Static checks of V3.7.6 (GNSS quality telemetry). Run from the root of the patched tree."""
from pathlib import Path
import sys
lib = Path("lib/avo_core/src"); src = Path("AVO_CHEST_V3_5_0/src")
pay_h, proto_h, proto_c, ble = (lib / "avo_payloads.h").read_text(), (lib / "avo_ble_proto.h").read_text(), (lib / "avo_ble_proto.cpp").read_text(), (src / "ble_service.cpp").read_text()
fails = []
def check(c, m):
    if not c: fails.append(m)
check("BACK_STATUS_V3_LEN" in pay_h and "uint8_t sig_l2 = 0" in pay_h, "BackStatus v3 present")
check("TELEMETRY_V3_LEN = 83 + 1 + 14 + 4 + 8 + 4 + 2" in proto_h, "telemetry v3 length")
check("w.u32(t.sacc_mm_s); w.u16(t.pdop_e2);" in proto_c, "telemetry v3 encoding")
check("s->link.back.v3" in ble and "TELEMETRY_V3_LEN + 8" in ble, "ble_service fills v3")
if fails:
    print("test_gnss_v376: FAIL", fails); sys.exit(1)
print("test_gnss_v376: OK")
