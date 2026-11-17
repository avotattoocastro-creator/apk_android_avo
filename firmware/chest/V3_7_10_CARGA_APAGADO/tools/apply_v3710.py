#!/usr/bin/env python3
"""AVO CHEST 3.7.10 CARGA APAGADO — applied on top of 3.7.9 CARGA (run from the tree root).

User request (09/11/2026): "if the chest is off and I plug it in to charge, when I unplug it it must switch itself off,
and at no moment in that process wake the back".
  * At boot the AXP2101 power-on source is read (register 0x20, PWRON status: bit0 = PWR key, bit2 = VBUS inserted).
    Switched on by the USB and not by the PWR key → "charge boot".
  * During a charge boot the chest never transmits to the back (no wake beacon, no DATA), also after the USB is
    unplugged, until it switches off. Before the PMU has been read (first seconds after boot) it does not transmit either.
  * USB unplugged for 2 s during a charge boot, without a session → controlled shutdown (same path as PWR long press:
    SD closed, then the AXP2101 cuts the power).
  * The charge boot ends (the chest becomes a normal "on" watch) when the user presses BOOT or PWR, or when a session
    starts: then unplugging leaves it on and the back is called as usual.
Nothing else changes.
"""
from pathlib import Path
import sys

SRC = Path('AVO_CHEST_V3_5_0') / 'src'


def patch(path: Path, old: str, new: str, count: int = 1):
    s = path.read_text()
    n = s.count(old)
    if n != count:
        sys.exit(f'apply_v3710: {path}: expected {count} match(es), found {n}:\n{old}')
    path.write_text(s.replace(old, new))


# ---------------------------------------------------------------- PMU power-on source
patch(SRC / 'hal_board.h', 'void pmu_power_off();',
      'void pmu_power_off();\n'
      '// V3.7.10: AXP2101 power-on source (register 0x20 PWRON status, read once in pmu_init; 0xFF = unknown).\n'
      '// bit0 = PWRON key, bit1 = IRQ pin, bit2 = VBUS inserted, bit3 = battery charge, bit4 = battery inserted, bit5 = EN.\n'
      'uint8_t pmu_poweron_status();\n'
      '// True when the watch was switched on by plugging the USB in (not by the PWR key).\n'
      'bool pmu_powered_on_by_usb();')
HB = SRC / 'hal_board.cpp'
patch(HB, 'bool pmu_init() {\n',
      'static uint8_t s_pon = 0xFF;   // V3.7.10\n'
      'uint8_t pmu_poweron_status() { return s_pon; }\n'
      'bool pmu_powered_on_by_usb() { return s_pon != 0xFF && (s_pon & 0x04) && !(s_pon & 0x01); }\n'
      'bool pmu_init() {\n')
patch(HB, '    s_pmu.enableIRQ(XPOWERS_AXP2101_PKEY_SHORT_IRQ | XPOWERS_AXP2101_PKEY_LONG_IRQ);\n  }\n',
      '    s_pmu.enableIRQ(XPOWERS_AXP2101_PKEY_SHORT_IRQ | XPOWERS_AXP2101_PKEY_LONG_IRQ);\n'
      '    uint8_t v = 0;\n'
      '    if (reg_read(I2C_ADDR_AXP2101, 0x20, &v, 1) == 0) s_pon = v;   // V3.7.10: why the watch switched on\n'
      '  }\n')

# ---------------------------------------------------------------- state
patch(SRC / 'app_state.h', '  uint16_t pwr_hold_permille = 0;\n};',
      '  uint16_t pwr_hold_permille = 0;\n'
      '  bool charge_boot = false;   // V3.7.10: switched on by the USB (charging only): never wakes the back\n'
      '};')

# ---------------------------------------------------------------- controller
CTL = SRC / 'controller.cpp'
patch(CTL, 'static bool s_shutting_down = false;\n',
      'static bool s_shutting_down = false;\n'
      'static bool s_charge_boot = false;        // V3.7.10\n'
      'static uint32_t s_unplug_t = 0;\n'
      'static void end_charge_boot(const char* why) {\n'
      '  if (!s_charge_boot) return;\n'
      '  s_charge_boot = false;\n'
      '  appstate::update([](AppSnapshot& s) { s.power.charge_boot = false; });\n'
      '  Serial.printf("[AVO POWER] encendido normal (%s): al desenchufar sigue encendido\\n", why);\n'
      '}\n')
patch(CTL, '  BootButton::Event e = s_boot.update(boot, now);\n',
      '  BootButton::Event e = s_boot.update(boot, now);\n'
      '  if (e != BootButton::NONE) end_charge_boot("boton BOOT");   // V3.7.10\n')
patch(CTL, '  if (s_pwr.short_press()) {\n',
      '  if (s_pwr.short_press()) {\n'
      '    end_charge_boot("boton PWR");   // V3.7.10\n')
patch(CTL, '  if (lvl == PowerLevel::CRITICAL) controlled_shutdown("battery critical");\n}',
      '  if (lvl == PowerLevel::CRITICAL) controlled_shutdown("battery critical");\n'
      '  // V3.7.10: switched on only to charge → switch off again 2 s after the USB is unplugged (no session)\n'
      '  if (s_charge_boot && s_life.active()) end_charge_boot("sesion");\n'
      '  if (s_charge_boot && ok && !p.vbus) {\n'
      '    if (!s_unplug_t) s_unplug_t = now | 1;\n'
      '    if (now - s_unplug_t >= 2000) controlled_shutdown("charge boot: USB unplugged");\n'
      '  } else s_unplug_t = 0;\n'
      '}')
patch(CTL, '  pinMode(PIN_BOOT_BTN, INPUT);       // external 10k pull-up\n',
      '  pinMode(PIN_BOOT_BTN, INPUT);       // external 10k pull-up\n'
      '  s_charge_boot = board::pmu_powered_on_by_usb();   // V3.7.10\n'
      '  { const bool cb = s_charge_boot; appstate::update([&](AppSnapshot& s) { s.power.charge_boot = cb; }); }\n'
      '  Serial.printf("[AVO POWER] encendido por %s (AXP2101 0x20 = 0x%02X)%s\\n", s_charge_boot ? "USB (solo carga)" : "PWR / normal",\n'
      '                (unsigned)board::pmu_poweron_status(), s_charge_boot ? ": la espalda no se despierta y al desenchufar se apaga" : "");\n')

# ---------------------------------------------------------------- link: quiet during a charge boot and before the PMU is read
UL = SRC / 'uart_link.cpp'
patch(UL,
      '      bool usb, rec;\n'
      '      appstate::lock();\n'
      '      usb = appstate::raw().power.pmu.online && appstate::raw().power.pmu.vbus;\n',
      '      bool usb, rec, cboot, pmu_known;\n'
      '      appstate::lock();\n'
      '      usb = appstate::raw().power.pmu.online && appstate::raw().power.pmu.vbus;\n'
      '      cboot = appstate::raw().power.charge_boot;                                  // V3.7.10\n'
      '      pmu_known = appstate::raw().power.pmu.online || now > 8000;                  // V3.7.10\n')
patch(UL,
      '      const bool want = usb && !rec;\n',
      '      const bool want = (usb || cboot || !pmu_known) && !rec;   // V3.7.10: charge boot stays quiet until it switches off\n')
print('apply_v3710: OK (charge boot from USB: back never woken, switches off 2 s after unplugging)')
