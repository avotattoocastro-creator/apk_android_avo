#!/usr/bin/env python3
"""AVO CHEST 3.7.9 CARGA — applied on top of 3.7.8 VINCULAR (run from the tree root).

User report (09/11/2026): plugging the chest in to charge woke the back up. With USB the AXP2101 powers the watch and
the firmware runs (charging screen), so 3.7.7 sent its wake beacon and the back (BACK >= 3.14.0) started.
Now, while the chest is on USB and NOT recording ("charge hold"):
  * on entering it, if the back is linked, BACK_SLEEP is sent (twice) so the back cuts its GPS and waits;
  * 1.5 s later (at once if the back was not linked) the chest stops transmitting to the back: no wake beacon and no
    DATA packets (heartbeat, CAPS, commands are dropped), so a sleeping back never hears it;
  * unplugging the USB (or starting a recording) ends it: the beacon comes back and the back wakes within 10 s.
Nothing else changes.
"""
from pathlib import Path
import sys

UL = Path('AVO_CHEST_V3_5_0') / 'src' / 'uart_link.cpp'


def patch(path: Path, old: str, new: str, count: int = 1):
    s = path.read_text()
    n = s.count(old)
    if n != count:
        sys.exit(f'apply_v379: {path}: expected {count} match(es), found {n}:\n{old}')
    path.write_text(s.replace(old, new))


patch(UL,
      'static void flush_packet() {\n'
      '  if (s_pk.empty()) return;\n',
      '// V3.7.9: chest charging on USB and not recording → nothing is transmitted to the back (it stays asleep)\n'
      'static volatile bool s_charge_quiet = false;\n'
      'static uint32_t s_charge_quiet_drop = 0;\n'
      'static void flush_packet() {\n'
      '  if (s_pk.empty()) return;\n'
      '  if (s_charge_quiet) { s_pk.clear(); s_pk_rtcm = 0; s_charge_quiet_drop++; return; }   // V3.7.9\n')
patch(UL,
      '    {  // V3.7.7: wake beacon for a sleeping back (BACK >= 3.14.0 listens 160 ms every 10 s)\n',
      '    {  // V3.7.9: charge hold — on USB and not recording the back is sent to sleep and left alone\n'
      '      static bool hold = false;\n'
      '      static uint32_t hold_t0 = 0;\n'
      '      bool usb, rec;\n'
      '      appstate::lock();\n'
      '      usb = appstate::raw().power.pmu.online && appstate::raw().power.pmu.vbus;\n'
      '      rec = appstate::raw().storage.rec == RecStatus::RECORDING;\n'
      '      appstate::unlock();\n'
      '      rec = rec || storage::session_active();\n'
      '      const bool want = usb && !rec;\n'
      '      if (want && !hold) {\n'
      '        hold = true;\n'
      '        if (link_up) { sleep_back(); sleep_back(); hold_t0 = now; }   // let BACK_SLEEP go out first\n'
      '        else hold_t0 = now - 2000;                                  // back not linked: quiet at once\n'
      '        Serial.printf("[AVO NOW] pecho cargando por USB: la espalda %s y no se despierta mientras cargue\\n",\n'
      '                      link_up ? "recibe la orden de dormir" : "no se despierta");\n'
      '      } else if (!want && hold) {\n'
      '        hold = false;\n'
      '        s_charge_quiet = false;\n'
      '        Serial.printf("[AVO NOW] fin de la carga (o grabando): baliza para despertar la espalda (%u paquetes descartados)\\n",\n'
      '                      (unsigned)s_charge_quiet_drop);\n'
      '      }\n'
      '      if (hold && now - hold_t0 >= 1500) s_charge_quiet = true;\n'
      '    }\n'
      '    {  // V3.7.7: wake beacon for a sleeping back (BACK >= 3.14.0 listens 160 ms every 10 s)\n')
patch(UL,
      '      if (s_pair.paired() && !link_up && now - last_wake >= 100) {\n',
      '      if (s_pair.paired() && !link_up && !s_charge_quiet && now - last_wake >= 100) {   // V3.7.9: not while charging\n')
print('apply_v379: OK (chest on USB and not recording: BACK_SLEEP, then no transmission to the back)')
