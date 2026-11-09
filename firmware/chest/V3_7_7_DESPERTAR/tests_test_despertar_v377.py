#!/usr/bin/env python3
"""Static checks of CHEST 3.7.7 DESPERTAR (run from the patched tree root). Not a compilation."""
from pathlib import Path
import re
src = Path('AVO_CHEST_V3_5_0/src')
ul = (src / 'uart_link.cpp').read_text()
ctl = (src / 'controller.cpp').read_text()
ws = (src / 'wifi_sync.cpp').read_text()
wh = (src / 'wifi_sync.h').read_text()
sh = Path('build_chest.sh').read_text()
n = 0
def check(c, what):
    global n
    n += 1
    if not c:
        raise SystemExit(f'test_despertar_v377: FAIL {what}')

check('AVO_BACKCMD_BACK_SLEEP = 8' in ul and 'bool sleep_back()' in ul, 'BACK_SLEEP command = 8 (BACK 3.14.0)')
check('bool sleep_back();' in (src / 'services.h').read_text(), 'sleep_back declared')
# shutdown: BACK_SLEEP after the SD is closed (phase 4) and BEFORE the PMIC cut
sd = ctl.index('storage::shutdown(8000)')
ph4 = ctl.index('shutdown_phase = 4')
sl = ctl.index('uartlink::sleep_back()')
off = ctl.index('board::pmu_power_off()')
check(sd < ph4 < sl < off, 'BACK_SLEEP after the SD close and before the power cut')
check(ctl.count('uartlink::sleep_back()') == 2, 'sent twice')
fail = ctl.index('SD close failed; power kept on')
check(fail < sl, 'not sent when the SD close fails (the chest stays on)')
# wake beacon: only while paired and the link is down, every 100 ms, single shot
b = ul[ul.index('wake beacon for a sleeping back'):]
b = b[:b.index('\n    }\n')]
check('s_pair.paired() && !link_up && now - last_wake >= 100' in b, 'beacon only paired + link down, 100 ms')
check('radio_send(s_pair.peer().mac' in b and 'for (' not in b, 'unicast to the paired back, no retries')
check('FrameType::HEARTBEAT' in b and 'NowKind::DATA' in b and 's_pair.peer().pair_id' in b, 'valid DATA packet of the couple')
check(ul.index('wake beacon for a sleeping back') < ul.index('// 1) RTCM first'), 'beacon inside the ESP-NOW tx loop')
# Wi-Fi
check('BLOCKED_AFTER_REBOOT = 6, LOW_INTERNAL_RAM = 7' in wh, 'new refusal reasons')
check('return StartResult::BLOCKED_AFTER_REBOOT;' in ws and 'return StartResult::LOW_INTERNAL_RAM;' in ws, 'reasons returned')
check('"wifi_off_fw"' in ws and 'strcmp(fw, AVO_FW_VERSION) != 0' in ws, 'block remembered per firmware')
i_clear = ws.index('old block cleared'); i_try = ws.index('nvs_get_u32("wifi_try", &tried)')
check(i_clear < i_try, 'old block cleared before the breadcrumb check (a reboot of THIS firmware still blocks)')
check('nvs_set_blob("wifi_off_fw", AVO_FW_VERSION' in ws, 'the block records this firmware')
# NimBLE store
m1 = re.search(r'-DCONFIG_BT_NIMBLE_MAX_BONDS=(\d+)', sh); m2 = re.search(r'-DCONFIG_BT_NIMBLE_MAX_CCCDS=(\d+)', sh)
check(m1 and m2, 'NimBLE store flags')
check(int(m2.group(1)) >= 3 * int(m1.group(1)), '3 notify CCCDs per bonded phone fit (no oldest-bond eviction)')
print(f'test_despertar_v377: OK ({n} checks)')
