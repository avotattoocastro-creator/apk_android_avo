#!/usr/bin/env python3
"""AVO CHEST V3.7.6 — GNSS quality from the back (BACK 3.9.0) to the app.

Applied after 3.7.5 (RAM + Wi-Fi). Run from the root of the tree. The workflow first copies
lib/avo_core/src/avo_payloads.{h,cpp} from firmware/back/V3_8_0 (same file as the chest had, plus BackStatus v3:
NAV-SAT/NAV-SIG summary and RTK FIX tracking; v1/v2 frames decode as before).
Changes:
  * avo_ble_proto: TELEMETRY v3 (appended; v2 apps ignore it): quality summary, FIX losses, time in FIX/FLOAT,
    time to first FIX, sAcc and PDOP of the current NAV-PVT.
  * ble_service.cpp: fills the v3 fields.
No change to RAW, recording, ESP-NOW framing, OTA or partitions.
"""
from pathlib import Path
import sys


def patch(path, old, new, count=1):
    p = Path(path)
    s = p.read_text()
    if s.count(old) != count:
        sys.exit(f"apply_v376: anchor not found ({s.count(old)}x) in {path}: {old[:70]!r}")
    p.write_text(s.replace(old, new))


SRC = "AVO_CHEST_V3_5_0/src"
LIB = "lib/avo_core/src"

if "BACK_STATUS_V3_LEN" not in Path(f"{LIB}/avo_payloads.h").read_text():
    sys.exit("apply_v376: copy avo_payloads.{h,cpp} from firmware/back/V3_8_0 first")

patch(f"{LIB}/avo_ble_proto.h", "  uint32_t girth_lost = 0;\n};\nstatic const size_t TELEMETRY_V1_LEN = 45;\nstatic const size_t TELEMETRY_V2_LEN = 83;",
      """  uint32_t girth_lost = 0;
  // v3 (CHEST 3.7.6 + BACK 3.9.0): GNSS quality and RTK FIX tracking
  uint8_t q_flags = 0;           // b0 back status v3 valid, b1 NAV-SIG summary present
  uint8_t sv_tracked = 0, sv_used = 0, sig_tracked = 0, sig_used = 0, sig_cr_used = 0, sig_corr = 0;
  uint8_t sig_l2 = 0, sig_l2_used = 0, sig_weak = 0, cno_mean = 0, cno_min = 0, cno_max = 0;
  uint8_t quality_age_s = 255, quality_mon = 0;
  uint16_t fix_lost = 0, ttff_fix_s = 0xFFFF;
  uint32_t fixed_ms = 0, float_ms = 0;
  uint32_t sacc_mm_s = 0;
  uint16_t pdop_e2 = 0;
};
static const size_t TELEMETRY_V1_LEN = 45;
static const size_t TELEMETRY_V2_LEN = 83;
static const size_t TELEMETRY_V3_LEN = 83 + 1 + 14 + 4 + 8 + 4 + 2;""")

patch(f"{LIB}/avo_ble_proto.cpp", "  w.u8(t.manual); w.u8(t.girth_present); w.u32(t.girth_lost);\n  return w.ok() ? w.size() : 0;",
      """  w.u8(t.manual); w.u8(t.girth_present); w.u32(t.girth_lost);
  w.u8(t.q_flags); w.u8(t.sv_tracked); w.u8(t.sv_used); w.u8(t.sig_tracked); w.u8(t.sig_used); w.u8(t.sig_cr_used);
  w.u8(t.sig_corr); w.u8(t.sig_l2); w.u8(t.sig_l2_used); w.u8(t.sig_weak); w.u8(t.cno_mean); w.u8(t.cno_min); w.u8(t.cno_max);
  w.u8(t.quality_age_s); w.u8(t.quality_mon); w.u16(t.fix_lost); w.u16(t.ttff_fix_s); w.u32(t.fixed_ms); w.u32(t.float_ms);
  w.u32(t.sacc_mm_s); w.u16(t.pdop_e2);
  return w.ok() ? w.size() : 0;""")

patch(f"{SRC}/ble_service.cpp",
      "      t.manual = s->session.manual; t.girth_present = s->girth.connected ? 1 : 0; t.girth_lost = s->girth.seq_lost;\n",
      """      t.manual = s->session.manual; t.girth_present = s->girth.connected ? 1 : 0; t.girth_lost = s->girth.seq_lost;
      // ---- v3 (V3.7.6): GNSS quality from BACK 3.9.0 (zeros with an older back: q_flags = 0)
      if (s->link.status_valid && s->link.back.v3) {
        const BackStatus& q = s->link.back;
        t.q_flags = (uint8_t)(1 | (q.quality_age_s != 255 ? 2 : 0));
        t.sv_tracked = q.sv_tracked; t.sv_used = q.sv_used; t.sig_tracked = q.sig_tracked; t.sig_used = q.sig_used;
        t.sig_cr_used = q.sig_cr_used; t.sig_corr = q.sig_corr; t.sig_l2 = q.sig_l2; t.sig_l2_used = q.sig_l2_used;
        t.sig_weak = q.sig_weak; t.cno_mean = q.cno_mean; t.cno_min = q.cno_min; t.cno_max = q.cno_max;
        t.quality_age_s = q.quality_age_s; t.quality_mon = q.quality_mon; t.fix_lost = q.fix_lost; t.ttff_fix_s = q.ttff_fix_s;
        t.fixed_ms = q.fixed_ms; t.float_ms = q.float_ms;
      }
      t.sacc_mm_s = g.sacc_mm_s; t.pdop_e2 = g.pdop_e2;
""")
patch(f"{SRC}/ble_service.cpp", "      uint8_t b[TELEMETRY_V2_LEN + 8];\n      size_t tl = encode_telemetry(t, b, sizeof(b));",
      "      uint8_t b[TELEMETRY_V3_LEN + 8];\n      size_t tl = encode_telemetry(t, b, sizeof(b));")
print("apply_v376: OK")
