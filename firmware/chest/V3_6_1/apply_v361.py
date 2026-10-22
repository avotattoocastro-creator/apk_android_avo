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
# Make the charging display fit the real AMOLED bounds, not the mockup.
# The old V3.5.9 layout put the label below a near-full-height circle.
ui_file=p/"ui.cpp"
ui_source=ui_file.read_text()
old='const int cy = LCD_HEIGHT / 2 - 12;'
new='const int cy = LCD_HEIGHT / 2 - 22;'
assert ui_source.count(old)==1, "Charging UI base changed"
ui_source=ui_source.replace(old,new)
old='const int radius = ((LCD_WIDTH < LCD_HEIGHT ? LCD_WIDTH : LCD_HEIGHT) / 2) - 48;'
new='const int radius = ((LCD_WIDTH < LCD_HEIGHT ? LCD_WIDTH : LCD_HEIGHT) / 2) - 58;'
assert ui_source.count(old)==1, "Charging circle radius base changed"
ui_source=ui_source.replace(old,new)
old='gfx->setTextSize(2);\n  const char* label = pct == 100 ? "CARGA COMPLETA" : "CARGANDO...";'
new='gfx->setTextSize(3);\n  const char* label = pct == 100 ? "COMPLETA" : "CARGANDO...";'
assert ui_source.count(old)==1, "Charging label base changed"
ui_source=ui_source.replace(old,new)
old='gfx->setCursor(cx - (int)strlen(label)*6, cy + radius + 19);'
new='gfx->setCursor(cx - (int)strlen(label)*9, cy + radius + 12);'
assert ui_source.count(old)==1, "Charging label placement base changed"
ui_source=ui_source.replace(old,new)
ui_file.write_text(ui_source)
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
