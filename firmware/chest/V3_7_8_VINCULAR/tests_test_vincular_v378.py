#!/usr/bin/env python3
"""Static checks of CHEST 3.7.8 VINCULAR (run from the patched tree root). Not a compilation."""
from pathlib import Path
src = Path('AVO_CHEST_V3_5_0/src'); lib = Path('lib/avo_core/src')
ble = (src / 'ble_service.cpp').read_text(); ctl = (src / 'controller.cpp').read_text()
inp = (lib / 'avo_input.cpp').read_text(); ui = (src / 'ui_model.cpp').read_text()
n = 0
def check(c, what):
    global n
    n += 1
    if not c: raise SystemExit(f'test_vincular_v378: FAIL {what}')
check('TRIPLE' in (lib / 'avo_input.h').read_text() and 'ev = TRIPLE' in inp, 'TRIPLE event')
check('ev = clicks_ == 1 ? SHORT : DOUBLE' in inp, 'DOUBLE still reported after the click window')
check('case BootButton::TRIPLE' in ctl and 'ble::pair_mode(!ble::pair_mode_active())' in ctl, 'triple click toggles the pair mode')
check('s_srv->disconnect(s_conn)' in ble and 'NimBLEDevice::startAdvertising();\n  pm_publish();' in ble, 'drops the current phone and advertises')
i_begin = ble.index('s_auth->claim_begin(sys::ms()'); i_auto = ble.index('pair_mode_active() && claim_confirm()')
check(i_begin < i_auto, 'CLAIM auto-confirmed only after claim_begin, inside the window')
check('if (s_pm_until) pair_mode(false);' in ble, 'window closes when the key is delivered')
check('info.getIdAddress() == s_pm_block' in ble, 'the dropped phone cannot take the watch back during the window')
check('"MODO VINCULAR"' in ui, 'screen shows the mode')
check('120000' in (src / 'services.h').read_text(), '120 s window')
print(f'test_vincular_v378: OK ({n} checks)')
