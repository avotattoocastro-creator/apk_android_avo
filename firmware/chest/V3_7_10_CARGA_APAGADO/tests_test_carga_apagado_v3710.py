#!/usr/bin/env python3
"""Static checks of CHEST 3.7.10 CARGA APAGADO (run from the patched tree root). Not a compilation."""
from pathlib import Path
src = Path('AVO_CHEST_V3_5_0/src')
hb = (src / 'hal_board.cpp').read_text(); ctl = (src / 'controller.cpp').read_text(); ul = (src / 'uart_link.cpp').read_text()
n = 0
def check(c, what):
    global n
    n += 1
    if not c: raise SystemExit(f'test_carga_apagado_v3710: FAIL {what}')
check('reg_read(I2C_ADDR_AXP2101, 0x20, &v, 1)' in hb, 'AXP2101 power-on source read at init')
check('(s_pon & 0x04) && !(s_pon & 0x01)' in hb, 'charge boot = VBUS and not the PWR key')
check('s_charge_boot = board::pmu_powered_on_by_usb();' in ctl, 'flag set in ctl::init')
check('controlled_shutdown("charge boot: USB unplugged")' in ctl and 'now - s_unplug_t >= 2000' in ctl, 'off 2 s after unplugging')
check('if (s_charge_boot && s_life.active()) end_charge_boot("sesion");' in ctl, 'a session makes it a normal "on"')
check('end_charge_boot("boton BOOT")' in ctl and 'end_charge_boot("boton PWR")' in ctl, 'buttons make it a normal "on"')
check('(usb || cboot || !pmu_known) && !rec' in ul, 'quiet during the charge boot and before the PMU is read')
print(f'test_carga_apagado_v3710: OK ({n} checks)')
