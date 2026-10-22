#!/usr/bin/env python3
"""AVO CHEST V3.6.1 — fail-closed version patch and source audit.

Do not emit a distributable binary until real UI implementation is present.
"""
from pathlib import Path
p=Path("AVO_CHEST_V3_5_0/src")
core=Path("lib/avo_core/src")
def change(file,old,new):
    s=file.read_text()
    assert s.count(old)==1, f"Unexpected source in {file}: {old}"
    file.write_text(s.replace(old,new))
change(core/"avo_version.h",'"3.6.0"','"3.6.1"')
change(core/"avo_version.h","0x030600","0x030601")
change(p/"build_info.h",'"V3.6.0-UI-INTEGRATION"','"V3.6.1-SEVEN-BAND-PENDING"')
ui=(p/"ui.cpp").read_text()
checks={
  "circular charge UI": "static void render_charging(" in ui and "drawCircle(" in ui and "CARGANDO..." in ui,
  "seven-band UI": "AVO_UI_SEVEN_BANDS_V361" in ui,
  "180 degree screen and touch": "AVO_UI_ROTATE_180_V361" in ui,
  "OTA progress screen": "AVO_UI_OTA_PROGRESS_V361" in ui,
  "safe shutdown screen": "AVO_UI_SAFE_SHUTDOWN_V361" in ui,
}
for name,passed in checks.items():
    print(f"{'PASS' if passed else 'FAIL'}: {name}")
if not all(checks.values()):
    raise SystemExit("V3.6.1 release BLOCKED: missing implemented UI components")
print("UI markers present; compile, hardware tests and signed OTA verification STILL REQUIRED")
