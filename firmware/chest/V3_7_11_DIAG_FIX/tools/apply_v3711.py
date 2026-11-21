#!/usr/bin/env python3
"""AVO CHEST 3.7.11 DIAG FIX — applied on top of 3.7.10 CARGA APAGADO (run from the tree root).

User request (21/11/2026 00:47): "add every reading needed, also in the app, until we find out why the RTK FIX does not
come; once it is solved we simplify the data in the app".
  * The back (>= 3.15.0) appends BackStatus v4 (130 B): antenna and RF (UBX-MON-RF), RTCM families in the corrections and
    the ones the receiver uses, reference station and its distance, dynamic model and constellations. The decoder is the
    shared avo_payloads.{h,cpp} that the workflow copies from the back (v3 backs keep working: v4 = false).
  * DIAG_GET (text read by the app every 5 s in «Calidad GNSS») gets those fields as key=value when the back sends them.
    The text buffer moves from the stack (1500) to a static 2048-byte buffer (DIAG_GET is answered from the BLE task only;
    the answer is copied by queue_msg).
TELEMETRY, the RAW format and everything else are unchanged.
"""
from pathlib import Path
import sys

SRC = Path('AVO_CHEST_V3_5_0') / 'src'


def patch(path: Path, old: str, new: str, count: int = 1):
    s = path.read_text()
    n = s.count(old)
    if n != count:
        sys.exit(f'apply_v3711: {path}: expected {count} match(es), found {n}:\n{old}')
    path.write_text(s.replace(old, new))


BLE = SRC / 'ble_service.cpp'
patch(BLE, '''    case BleMsg::DIAG_GET: {
      AppSnapshot* s = new AppSnapshot();
      appstate::get(s);
      char t[1500];''', '''    case BleMsg::DIAG_GET: {
      AppSnapshot* s = new AppSnapshot();
      appstate::get(s);
      static char t[2048];   // V3.7.11: 1500 on the stack was too small for the back v4 block''')
patch(BLE, '''              (unsigned long)b.nmea_sentences, (unsigned long)b.link_tx_fail, (int)b.link_rssi);
          if (l2 > 0) len += l2;
        }''', '''              (unsigned long)b.nmea_sentences, (unsigned long)b.link_tx_fail, (int)b.link_rssi);
          if (l2 > 0) len += l2;
          // V3.7.11: diagnosis of "no RTK FIX" (BackStatus v4, back >= 3.15.0)
          if (b.v4 && len < (int)sizeof(t)) {
            l2 = snprintf(t + len, sizeof(t) - len,
                " rf_ant=%u rf_pwr=%u rf_jam=%u rf_jam1=%u rf_jam2=%u rf_agc1=%u rf_agc2=%u rf_noise1=%u rf_noise2=%u rf_age=%u"
                " rtcm_types=%u rtcm_used=%u base_id=%u base_dam=%u dyn=%u gnss_set=%u"
                " sv=%u sv_used=%u sig=%u sig_used=%u sig_cr=%u sig_corr=%u sig_l2=%u sig_l2_used=%u cno=%u cno_min=%u cno_max=%u"
                " fix_lost=%u ttff_fix=%u fixed_s=%lu float_s=%lu",
                (unsigned)b.rf_ant_status, (unsigned)b.rf_ant_power, (unsigned)b.rf_jam_state, (unsigned)b.rf_jam_l1,
                (unsigned)b.rf_jam_l2, (unsigned)b.rf_agc_l1, (unsigned)b.rf_agc_l2, (unsigned)b.rf_noise_l1,
                (unsigned)b.rf_noise_l2, (unsigned)b.rf_age_s, (unsigned)b.rtcm_types, (unsigned)b.rtcm_used_types,
                (unsigned)b.base_id, (unsigned)b.base_dist_dam, (unsigned)b.dyn_model, (unsigned)b.gnss_set,
                (unsigned)b.sv_tracked, (unsigned)b.sv_used, (unsigned)b.sig_tracked, (unsigned)b.sig_used,
                (unsigned)b.sig_cr_used, (unsigned)b.sig_corr, (unsigned)b.sig_l2, (unsigned)b.sig_l2_used,
                (unsigned)b.cno_mean, (unsigned)b.cno_min, (unsigned)b.cno_max, (unsigned)b.fix_lost, (unsigned)b.ttff_fix_s,
                (unsigned long)(b.fixed_ms / 1000), (unsigned long)(b.float_ms / 1000));
            if (l2 > 0) len += l2;
          }
        }''')
print('apply_v3711: OK')
