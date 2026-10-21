#!/usr/bin/env python3
"""Apply reviewed V3.5.5 changes to the V3.5.4 source archive."""
from pathlib import Path
p = Path("AVO_CHEST_V3_5_0/src")
def replace(file, old, new):
    f = p/file
    s = f.read_text()
    assert s.count(old) == 1, f"unexpected source: {file}: {old[:50]}"
    f.write_text(s.replace(old,new))

replace("build_info.h", '"V3.5.4-SD-FIX-ESPNOW-AUTH-TELEM2"', '"V3.5.5-OTA-PERSIST-USB-CHARGE"')
replace("app_main.cpp", '  // SD fsync on a slow card can exceed the default 5 s; 10 s still catches real hangs.', '''  // Confirm pending OTA after essential boot checks, rather than after 60 s.
  if (ota::pending_verify()) {
    const bool healthy = i2c_ok && pmu_ok && sd_ok && ctl_ok && ui_ok && ble_ok;
    Serial.printf("[AVO OTA] first boot health=%s\\n", healthy ? "OK" : "FAILED");
    if (healthy) ota::mark_valid_if_healthy(true);
  }

  // SD fsync on a slow card can exceed the default 5 s; 10 s still catches real hangs.''')
replace("controller.cpp", '  bool ota_checked = false;', '')
replace("controller.cpp", '''    if (!ota_checked && now > 60000) {
      ota_checked = true;
      AppSnapshot* s = new AppSnapshot();
      appstate::get(s);
      ota::mark_valid_if_healthy(s->sys.heap_free > 20000);
      delete s;
    }
''', '')
replace("ota.cpp", '''    esp_ota_mark_app_valid_cancel_rollback();
    bb::log(BbCode::OTA, 0, 2, 0, "new image validated");''', '''    const esp_err_t result = esp_ota_mark_app_valid_cancel_rollback();
    if (result == ESP_OK) {
      bb::log(BbCode::OTA, 0, 2, 0, "new image validated");
      Serial.println("[AVO OTA] validated for persistent boot");
    } else {
      Serial.printf("[AVO OTA] validation error: %s\\n", esp_err_to_name(result));
      bb::log(BbCode::OTA, 2, 4, (uint32_t)result, "validation failed");
    }''')
replace("ui.cpp", 'static bool pair_latched = false;', '''// USB charging display; keep BLE/SD/ESP-NOW running for safe OTA/data handling.
static bool charge_screen = false;
static uint32_t charge_last_draw = 0;
static void render_charging(const AppSnapshot& s, uint32_t now) {
  if (charge_screen && now - charge_last_draw < 10000) return;
  charge_last_draw = now;
  gfx->fillScreen(C_BLACK);
  gfx->setTextColor(0xFFFF, C_BLACK);
  gfx->setTextSize(3);
  const int pct = s.power.pmu.batt_pct;
  char value[16];
  if (pct >= 0 && pct <= 100) snprintf(value, sizeof(value), "%d%%", pct);
  else snprintf(value, sizeof(value), "--%%");
  const int cx = LCD_WIDTH / 2, cy = LCD_HEIGHT / 2;
  gfx->drawCircle(cx, cy, 120, 0x39E7);
  gfx->drawCircle(cx, cy, 119, 0x39E7);
  if (pct >= 0 && pct <= 100) {
    const int steps = pct * 72 / 100;
    for (int i = 0; i < steps; ++i) {
      const float a = (i * 5.0f - 90.0f) * 0.01745329252f;
      const float b = ((i + 1) * 5.0f - 90.0f) * 0.01745329252f;
      gfx->drawLine(cx + (int)(120*cosf(a)), cy + (int)(120*sinf(a)),
                    cx + (int)(120*cosf(b)), cy + (int)(120*sinf(b)), C_GREEN);
    }
  }
  gfx->setCursor(cx - (int)strlen(value)*9, cy - 18);
  gfx->print(value);
  gfx->setTextSize(2);
  gfx->setCursor(cx - 84, cy + 40);
  gfx->print(pct == 100 ? "CARGA COMPLETA" : "CARGANDO USB");
}
static bool pair_latched = false;''')
replace("ui.cpp", '''      if (config_cache.dim_on_low_batt && snap->power.level == PowerLevel::LOWBAT && wanted > 60) wanted = 60;''', '''      if (config_cache.dim_on_low_batt && snap->power.level == PowerLevel::LOWBAT && wanted > 60) wanted = 60;
      const bool charging_usb = snap->power.pmu.online && snap->power.pmu.vbus;
      if (charging_usb && wanted > 25) wanted = 25;''')
replace("ui.cpp", '      if (display_on) render(*snap,now);', '''      if (display_on) {
        if (charging_usb) {
          if (!charge_screen) charge_last_draw = 0;
          render_charging(*snap, now);
          charge_screen = true;
        } else {
          if (charge_screen) { for (auto &v : old_state) v = 255; gfx->fillScreen(C_BLACK); }
          charge_screen = false;
          render(*snap, now);
        }
      }''')
print("V3.5.5 patch applied")
