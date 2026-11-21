#!/usr/bin/env python3
"""Static checks of CHEST 3.7.11 DIAG FIX (run from the patched tree root). Not a compilation."""
from pathlib import Path
ble = Path('AVO_CHEST_V3_5_0/src/ble_service.cpp').read_text()
pl = Path('lib/avo_core/src/avo_payloads.h').read_text()
n = 0
def check(c, what):
    global n
    n += 1
    if not c: raise SystemExit(f'test_diag_fix_v3711: FAIL {what}')
check('static char t[2048];' in ble and 'char t[1500];' not in ble, 'DIAG text buffer static, 2048 bytes')
for k in ('rf_ant=', 'rf_jam1=', 'rf_agc1=', 'rtcm_types=', 'rtcm_used=', 'base_id=', 'base_dam=', 'dyn=', 'gnss_set=', 'sig_cr=', 'cno='):
    check(k in ble, f'DIAG key {k}')
check('if (b.v4 && len < (int)sizeof(t))' in ble, 'v4 block only with a v4 back')
check('BACK_STATUS_V4_LEN = BACK_STATUS_V3_LEN + 22' in pl and 'bool v4 = false;' in pl, 'shared decoder knows v4 (130 B)')
print(f'test_diag_fix_v3711: OK ({n} checks)')
