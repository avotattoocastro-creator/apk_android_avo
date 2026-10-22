#!/usr/bin/env python3
"""AVO CHEST V3.5.9: versioned, fail-closed signed OTA receiver."""
from pathlib import Path
p=Path("AVO_CHEST_V3_5_0/src")
core=Path("lib/avo_core/src")
def replace(path,old,new):
    s=path.read_text()
    assert s.count(old)==1, f"Unexpected V3.5.8 base in {path}: {old[:70]}"
    path.write_text(s.replace(old,new))
replace(core/"avo_version.h",'"3.5.8"','"3.5.9"')
replace(core/"avo_version.h","0x030508","0x030509")
replace(p/"build_info.h",'"V3.5.8-OTA-HARDENED"','"V3.5.9-OTA-DIAGNOSTICS"')
ota=p/"ota.cpp"
replace(ota,'if(rc!=0){snprintf(err,el,"signature invalid");return false;}',
            'if(rc!=0){snprintf(err,el,"signature invalid");return false;}')
replace(ota,'if(!ok)snprintf(err,el,"manifest invalid");',
            'if(!ok)snprintf(err,el,"manifest invalid: target/version/hash/size/kid");')

# Charging UI: large circular gauge, centered percentage and CARGANDO...
# Retain the existing USB detection, display-state restoration and all background services.
ui=p/"ui.cpp"
source=ui.read_text()
start=source.index("static void render_charging(const AppSnapshot& s, uint32_t now) {")
end=source.index("static bool pair_latched = false;",start)
replacement=r'''static void render_charging(const AppSnapshot& s, uint32_t now) {
  if (charge_screen && now - charge_last_draw < 10000) return;
  charge_last_draw = now;
  gfx->fillScreen(C_BLACK);
  const int pct = s.power.pmu.batt_pct;
  const int cx = LCD_WIDTH / 2;
  const int cy = LCD_HEIGHT / 2 - 12;
  const int radius = ((LCD_WIDTH < LCD_HEIGHT ? LCD_WIDTH : LCD_HEIGHT) / 2) - 48;
  // Subtle unfilled track, then a thick cyan/green progress ring.
  for (int thickness = 0; thickness < 7; ++thickness) {
    gfx->drawCircle(cx, cy, radius - thickness, 0x3186);
  }
  if (pct >= 0 && pct <= 100) {
    const int segments = (pct * 180 + 50) / 100;
    for (int i = 0; i < segments; ++i) {
      const float a = (i * 2.0f - 90.0f) * 0.01745329252f;
      const float b = ((i + 1) * 2.0f - 90.0f) * 0.01745329252f;
      const uint16_t color = i < 90 ? 0x07FF : 0x07F0;
      for (int thickness = 0; thickness < 8; ++thickness) {
        const int r = radius - thickness;
        gfx->drawLine(cx + (int)(r*cosf(a)), cy + (int)(r*sinf(a)),
                      cx + (int)(r*cosf(b)), cy + (int)(r*sinf(b)), color);
      }
    }
  }
  char value[8];
  if (pct >= 0 && pct <= 100) snprintf(value, sizeof(value), "%d%%", pct);
  else snprintf(value, sizeof(value), "--%%");
  gfx->setTextColor(0xFFFF, C_BLACK);
  gfx->setTextSize(5);
  gfx->setCursor(cx - (int)strlen(value)*15, cy - 22);
  gfx->print(value);
  gfx->setTextSize(2);
  const char* label = pct == 100 ? "CARGA COMPLETA" : "CARGANDO...";
  gfx->setTextColor(0x07F0, C_BLACK);
  gfx->setCursor(cx - (int)strlen(label)*6, cy + radius + 19);
  gfx->print(label);
}
'''
assert source.count("static void render_charging(const AppSnapshot& s, uint32_t now) {")==1
ui.write_text(source[:start]+replacement+source[end:])
print("V3.5.9 circular USB charging UI applied")

print("V3.5.9 patch applied")
