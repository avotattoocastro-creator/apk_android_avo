#!/usr/bin/env python3
"""Static checks of CHEST 3.7.9 CARGA (run from the patched tree root). Not a compilation."""
from pathlib import Path
ul = Path('AVO_CHEST_V3_5_0/src/uart_link.cpp').read_text()
n = 0
def check(c, what):
    global n
    n += 1
    if not c: raise SystemExit(f'test_carga_v379: FAIL {what}')
check('if (s_charge_quiet) { s_pk.clear();' in ul, 'no DATA packet to the back while charging')
check('!link_up && !s_charge_quiet && now - last_wake >= 100' in ul, 'no wake beacon while charging')
check('usb && !rec' in ul and 'storage::session_active()' in ul, 'only on USB and not recording')
h = ul.index('charge hold'); b = ul.index('wake beacon for a sleeping back')
check(h < b, 'hold decided before the beacon')
check('if (link_up) { sleep_back(); sleep_back(); hold_t0 = now; }' in ul and 'now - hold_t0 >= 1500' in ul, 'BACK_SLEEP goes out before going quiet')
check('s_charge_quiet = false;' in ul, 'unplugging ends the quiet')
print(f'test_carga_v379: OK ({n} checks)')
