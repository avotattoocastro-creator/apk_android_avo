#!/usr/bin/env python3
"""AVO CHEST V3.7.6 GNSS QUALITY — freshness of the back's GNSS quality before it reaches the app.

Applied AFTER, in this order (see .github/workflows/build-chest-v376-gnss-quality.yml):
  3.7.0-rc2 zip → 3.7.2 UI → 3.7.3 READFILE → 3.7.4 Wi-Fi → 3.7.5 RAM → 3.7.5-usb1 (USB to the PC)
  → copy avo_payloads.{h,cpp} from firmware/back/V3_8_0 (BackStatus v3, the same file BACK 3.13.11 is built with)
  → firmware/chest/V3_7_6_GNSS/tools/apply_v376.py (TELEMETRY v3 over BLE, layout already decoded by Android)
  → this script.

Why: the chest keeps the LAST BackStatus forever (s.link.status_valid is never cleared when the back goes quiet).
With apply_v376.py alone, if the back switched off the app would keep receiving the last quality summary with
q_flags = 3 and a frozen quality_age_s, i.e. old values presented as current. This script:
  * sends q_flags = 0 (the app then shows no quality data) when the last BackStatus is older than 5 s
    (the back sends one per second, avo_back_core.cpp: `now - last_status_ >= 1000`);
  * adds the age of that BackStatus to quality_age_s (saturated at 254; 255 keeps meaning "never"), so the age the
    app sees is the real age of the NAV-SIG summary, not the age the back reported a few seconds ago.
No new field, no change of size or order: TELEMETRY v3 stays 116 bytes exactly as in apply_v376.py and Android
(core/.../ble/Messages.kt, Telemetry.V3_LEN = 116).
"""
from pathlib import Path
import sys


def patch(path, old, new, count=1):
    p = Path(path)
    s = p.read_text()
    if s.count(old) != count:
        sys.exit(f"apply_v376_gq: anchor not found ({s.count(old)}x) in {path}: {old[:70]!r}")
    p.write_text(s.replace(old, new))


SRC = "AVO_CHEST_V3_5_0/src"

patch(f"{SRC}/ble_service.cpp",
      "      if (s->link.status_valid && s->link.back.v3) {\n"
      "        const BackStatus& q = s->link.back;\n"
      "        t.q_flags = (uint8_t)(1 | (q.quality_age_s != 255 ? 2 : 0));\n",
      "      // V3.7.6 GNSS QUALITY: only a FRESH BackStatus v3 is forwarded (the back sends one per second).\n"
      "      const int32_t q_link_ms = (int32_t)(now - s->link.back_status_ms);\n"
      "      const uint32_t q_link_age_ms = q_link_ms > 0 ? (uint32_t)q_link_ms : 0;\n"
      "      if (s->link.status_valid && s->link.back.v3 && q_link_age_ms <= 5000) {\n"
      "        const BackStatus& q = s->link.back;\n"
      "        t.q_flags = (uint8_t)(1 | (q.quality_age_s != 255 ? 2 : 0));\n")
patch(f"{SRC}/ble_service.cpp",
      "        t.fixed_ms = q.fixed_ms; t.float_ms = q.float_ms;\n      }\n",
      "        t.fixed_ms = q.fixed_ms; t.float_ms = q.float_ms;\n"
      "        if (q.quality_age_s != 255) {   // real age of the NAV-SIG summary as seen by the app\n"
      "          const uint32_t qa = (uint32_t)q.quality_age_s + q_link_age_ms / 1000;\n"
      "          t.quality_age_s = (uint8_t)(qa > 254 ? 254 : qa);\n"
      "        }\n"
      "      }\n")
print("apply_v376_gq: OK")
