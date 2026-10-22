#!/usr/bin/env python3
"""Apply V3.5.6 USB display-state restoration on top of V3.5.5."""
from pathlib import Path
p=Path("AVO_CHEST_V3_5_0/src")
ui=p/"ui.cpp"
s=ui.read_text()
def change(old,new):
 global s
 assert s.count(old)==1, "unexpected source layout: "+old[:80]
 s=s.replace(old,new)
change('static bool charge_screen = false;', '''static bool charge_screen = false;
// Preserve pre-USB user display preference across charging.
static bool usb_was_connected = false;
static bool display_before_usb = true;''')
change('      if (display_on) {\n        if (charging_usb) {', '''      if (charging_usb && !usb_was_connected) {
        display_before_usb = snap->sys.display_on;
        usb_was_connected = true;
        charge_last_draw = 0;
        screen_power(true);
      } else if (!charging_usb && usb_was_connected) {
        usb_was_connected = false;
        charge_screen = false;
        screen_power(display_before_usb);
      }
      if (charging_usb && !display_on) screen_power(true);
      if (display_on) {
        if (charging_usb) {''')
change('      if (display_on) {\n        if (charging_usb) {', '      if (display_on) {\n        if (charging_usb) {') if False else None
# Avoid power-management restoring a stale pre-USB state on disconnect.
# screen_power updates appstate::sys.display_on as well as hardware.
ui.write_text(s)
info=p/"build_info.h"
info.write_text(info.read_text().replace("V3.5.5-OTA-PERSIST-USB-CHARGE","V3.5.6-USB-STATE-RESTORE"))
print("V3.5.6 USB state restore patch applied")
