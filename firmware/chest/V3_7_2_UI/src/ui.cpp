// AVO CHEST V3.7.2 — seven anti-aliased status cards on the CO5300 AMOLED, no LVGL.
// Rendering: ui_fb (RGB565 framebuffer in PSRAM, 402 KB of 8 MB) + ui_dash (layout) +
// ui_model (live snapshot -> cards). Internal RAM: one 13 KB transfer buffer only.
// Only changed cards (and the blinking SD dot) are sent to the panel, always even-aligned.
// Task logic (touch, pairing, developer mode, brightness, USB, OTA, shutdown) unchanged from 3.7.1-rc2.
#include <Arduino.h>
#include <Arduino_GFX_Library.h>
#include <esp_heap_caps.h>
#include <new>
#include <cstring>
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "app_state.h"
#include "board_pins.h"
#include "services.h"
#include "sys_util.h"
#include "ui_fb.h"
#include "ui_dash.h"
#include "ui_model.h"

using namespace avo;
extern TaskHandle_t g_task_handles[TID_COUNT];
namespace ui {
static Arduino_DataBus* bus = nullptr;
static Arduino_CO5300* gfx = nullptr;
static volatile bool request_wake = false;
static volatile bool passkey_active = false;
static bool display_on = true;
static uint8_t brightness = 180;
static void invalidate_cards();
static uint32_t old_state[7] = {UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX,UINT32_MAX};

static uint32_t last_touch_ms = 0;
static uint32_t touch_start_ms = 0;
static bool dev_latched = false;
static bool developer_mode = false;
static Config config_cache;  // Avoid large config on UI task stack.

// AVO_UI_ROTATE_180_V361: the panel is mounted upside down in the AVO case. The 180° turn is
// done in software when pixels are sent (ui_fb flush), so the CO5300 column offset (22) and
// MADCTL stay exactly as in the working rotation-0 setup. Set to false only if the image
// appears upside down on a differently assembled unit.
static constexpr bool UI_ROTATE_180 = true;

static UiFb fb;
struct GfxPanel : UiPanel {
  void push(int16_t x, int16_t y, const uint16_t* p, int16_t w, int16_t h) override {
    gfx->draw16bitRGBBitmap(x, y, const_cast<uint16_t*>(p), w, h);
  }
};
static GfxPanel panel;
static dash::Model model;        // static: keeps the 4 KB UI task stack small
static uint32_t card_cache[7] = {0,0,0,0,0,0,0};
static bool cards_invalid = true;
static void invalidate_cards() { cards_invalid = true; }

void show_passkey(uint32_t, bool on) {
  // No numeric passkey can be displayed in seven-card mode.
  // Pairing method must be checked in BLE service / Android app.
  passkey_active = on;
  request_wake = true;
}
void wake() { request_wake = true; }
void next_screen() { request_wake = true; } // No extra screens.
void home_screen() { request_wake = true; }

static void screen_power(bool on) {
  if (on == display_on) return;
  display_on = on;
  if (on) {
    gfx->displayOn();
    gfx->setBrightness(brightness);
    for (auto &p : old_state) p = UINT32_MAX;
    invalidate_cards();
  } else gfx->displayOff();
  appstate::update([on](AppSnapshot& a) { a.sys.display_on = on; });
}
static bool shutdown_drawn = false;
// AVO_UI_SEVEN_BANDS_V361: real snapshot data; stale samples never show OK (see ui_model.cpp,
// e.g. the girth needs last_batch_ms[0], last_batch_ms[1] and last_batch_ms[2] fresh).
static uint32_t last_dashboard_refresh = 0;
// SD recording: only the red dot blinks, 500 ms on / 500 ms off; the yellow card is not redrawn.
static uint32_t last_blink_ms = 0;
static bool blink_on = true;

static void render(const AppSnapshot& s, uint32_t now) {
  // Cards: rebuilt once per second from real-time state, no invented readings.
  if (cards_invalid || !last_dashboard_refresh || now - last_dashboard_refresh >= 1000 || old_state[0] == UINT32_MAX) {
    old_state[0] = 0;
    last_dashboard_refresh = now;
    ui_model::build(s, now, &model);
    if (cards_invalid) fb.clear(dash::INK);
    for (int i = 0; i < dash::CARD_COUNT; ++i) {
      const uint32_t sig = dash::card_hash(i, model);
      if (!cards_invalid && card_cache[i] == sig) continue;
      card_cache[i] = sig;
      dash::draw_card(fb, i, model);
      if (i == dash::SD) { blink_on = true; last_blink_ms = now; }
    }
    cards_invalid = false;
  }
  if (dash::rec_dot_active(model) && now - last_blink_ms >= 500) {
    last_blink_ms = now;
    blink_on = !blink_on;
    dash::draw_rec_dot(fb, model, blink_on);
  }
  fb.flush(panel);
}
// Charging UI: PMIC VBUS detection; no guessed battery percentages.
// Radios remain available for OTA and data safety; see release notes.
static bool charge_screen = false;
static uint32_t charge_last_draw = 0;
// Snapshot the display state at the USB insertion edge, not during charging.
static bool usb_was_connected = false;
static bool display_before_usb = true;
static bool display_preference_during_usb = true;
static bool charging_forced_screen = false;
// Full-screen charging ring (kept from 3.7.1-rc2, which shows the dashboard while on USB).
[[maybe_unused]] static void render_charging(const AppSnapshot& s, uint32_t now) {
  static int last_charge_pct = -999;
  const int current_pct = s.power.pmu.batt_pct;
  if (charge_screen && current_pct == last_charge_pct &&
      (uint32_t)(now - charge_last_draw) < 10000) return;
  last_charge_pct = current_pct;
  charge_last_draw = now;
  dash::draw_charging(fb, current_pct);
  fb.flush(panel);
}
static bool pair_latched = false;
static void task(void*) {
  auto* snap = static_cast<AppSnapshot*>(heap_caps_malloc(sizeof(AppSnapshot), MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  if (!snap) {
    Serial.println("[AVO LITE] ERROR: no PSRAM for UI snapshot");
    vTaskDelete(nullptr);
    return;
  }
  new (snap) AppSnapshot();
  uint32_t last_update = 0;
  bool special_screen = false;
  for (;;) {
    const uint32_t now = sys::ms();
    if (request_wake) { request_wake = false; screen_power(true); }
    if (now - last_touch_ms >= 60) {
      last_touch_ms = now;
      bool pressed = false;
      int16_t x=0,y=0;
      if (board::touch_read(&pressed,&x,&y) && pressed) {
        if (!touch_start_ms) { touch_start_ms = now; pair_latched = false; }
        // V3.5.0: touch held 5 s anywhere = look for a back for 60 s (harmless if the own back is
        // alive: it simply answers again). Developer mode stays at 20 s.
        if (!pair_latched && now - touch_start_ms >= 5000) {
          pair_latched = true;
          uartlink::pair_start(60000);
          Serial.println("[AVO LITE] ESP-NOW pairing requested from the touch screen (60 s)");
        }
        if (!dev_latched && now - touch_start_ms >= 20000) {
          dev_latched = true;
          developer_mode = !developer_mode;
          appstate::update([](AppSnapshot& a) { a.sys.dev_mode = developer_mode; });
          Serial.printf("[AVO LITE] developer flag=%d (configuration via Android)\n", developer_mode);
        }
      } else { touch_start_ms = 0; dev_latched = false; }
    }
    if (now - last_update >= 250) {
      last_update = now;
      appstate::get(snap);
      cfgstore::get(&config_cache);
      uint8_t wanted = config_cache.brightness;
      if (config_cache.dim_on_low_batt && snap->power.level == PowerLevel::LOWBAT && wanted > 60) wanted = 60;
      const bool charging_usb = snap->power.pmu.online && snap->power.pmu.vbus;
      if (charging_usb && wanted > 25) wanted = 25;
      if (wanted != brightness) { brightness = wanted; if (display_on) gfx->setBrightness(brightness); }
      // USB insertion: remember whether the user was in normal or power-save
      // display mode. Wake for the charging screen without overwriting that
      // preference. Avoid treating the forced wake as a new user preference.
      if (charging_usb && !usb_was_connected) {
        display_before_usb = snap->sys.display_on;
        display_preference_during_usb = display_before_usb;
        charging_forced_screen = !display_before_usb;
        usb_was_connected = true;
        charge_last_draw = 0;
        screen_power(true);
        Serial.printf("[AVO UI] USB connected; previous display=%s\n",
                      display_before_usb ? "ON" : "SLEEP");
      } else if (!charging_usb && usb_was_connected) {
        usb_was_connected = false;
        // Restore only the display preference. Do not touch BLE, SD or recording.
        const bool restore_on = display_preference_during_usb;
        charging_forced_screen = false;
        charge_screen = false;
        screen_power(restore_on);
        Serial.printf("[AVO UI] USB removed; restored display=%s\n",
                      restore_on ? "ON" : "SLEEP");
      }
      if (!charging_usb) {
        if (!snap->sys.display_on && display_on && !snap->power.shutdown_requested && !passkey_active) screen_power(false);
        if (snap->sys.display_on && !display_on) screen_power(true);
      } else if (!display_on) {
        screen_power(true);
      }
      if (display_on) {
        const bool ota_notice = snap->ble.ota_display_status>=2 && snap->ble.ota_display_since_ms && (uint32_t)(now-snap->ble.ota_display_since_ms)<6000;
        const bool special_now = snap->ble.ota_active || ota_notice || snap->power.shutdown_requested;
        if(special_screen && !special_now) {
          for(auto &v:old_state)v=UINT32_MAX;
          invalidate_cards();
          shutdown_drawn = false; // reset after a failed/cancelled shutdown
          charge_screen = false;
        }
        special_screen=special_now;
        // AVO_UI_OTA_PROGRESS_V361: OTA overrides USB display; real confirmed bytes.
        if (snap->ble.ota_active) {
          static uint32_t last_ota_draw=0;
          static uint32_t last_ota_pct=UINT32_MAX;
          uint32_t pct=snap->ble.ota_total ?
            (uint32_t)((uint64_t)snap->ble.ota_bytes*99/snap->ble.ota_total):0;
          if(pct>99)pct=99;
          if(pct!=last_ota_pct || now-last_ota_draw>=2000 || !last_ota_draw){
            last_ota_draw=now;
            last_ota_pct=pct;
            char ota_percent[8];
            snprintf(ota_percent,sizeof(ota_percent),"%lu%%",(unsigned long)pct);
            dash::draw_ota_progress(fb,pct,ota_percent);
            fb.flush(panel);
          }
          charge_screen=false;
          for(auto &v:old_state)v=UINT32_MAX;
          invalidate_cards();
        } else if (ota_notice && !snap->power.shutdown_requested) {
          // "VERIFICADA" means OTA image validated, not that new firmware has booted.
          // Redraw the notification when entering from the OTA progress screen.
          static uint32_t notice_last_draw = 0;
          static uint8_t last_notice_status = 0;
          if (!notice_last_draw || last_notice_status != snap->ble.ota_display_status ||
              (uint32_t)(now-notice_last_draw)>=1000) {
            last_notice_status = snap->ble.ota_display_status;
            notice_last_draw=now;
            const bool ok = snap->ble.ota_display_status==2;
            dash::draw_ota_notice(fb, ok, ok?"OTA VERIFICADA":"ERROR OTA", ok?"ESPERA REINICIO":"REVISA APP");
            fb.flush(panel);
          }
          for(auto &v:old_state)v=UINT32_MAX;
          invalidate_cards();
        } else if (snap->power.shutdown_requested) {
          // AVO_UI_SAFE_SHUTDOWN_V361: one redraw per shutdown edge.
          if (!shutdown_drawn) {
            shutdown_drawn=true;
            dash::draw_shutdown(fb);
            fb.flush(panel);
          }
        } else {
          if (charge_screen) { for (auto &p : old_state) p = UINT32_MAX; invalidate_cards(); }
          charge_screen = false;
          render(*snap,now);
        }
      }
    }
    vTaskDelay(pdMS_TO_TICKS(25));
  }
}
bool init() {
  bus = new Arduino_ESP32QSPI(PIN_LCD_CS,PIN_LCD_SCLK,PIN_LCD_SDIO0,PIN_LCD_SDIO1,PIN_LCD_SDIO2,PIN_LCD_SDIO3);
  gfx = new Arduino_CO5300(bus,PIN_LCD_RESET,0,LCD_WIDTH,LCD_HEIGHT,LCD_COL_OFFSET,0,0,0);
  if (!gfx || !gfx->begin()) return false;
  gfx->setRotation(0);  // native orientation; the 180° turn is applied in software (UI_ROTATE_180)
  gfx->fillScreen(0x0000);
  static_assert(LCD_WIDTH == UiFb::W && LCD_HEIGHT == UiFb::H, "UI layout is designed for 410x502");
  // Framebuffer in PSRAM; transfer buffer in internal DMA-capable RAM (16 rows, 13 KB).
  auto* pixels = static_cast<uint16_t*>(heap_caps_malloc((size_t)UiFb::W * UiFb::H * 2, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT));
  size_t line_px = (size_t)UiFb::W * 16;
  auto* line = static_cast<uint16_t*>(heap_caps_malloc(line_px * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_DMA | MALLOC_CAP_8BIT));
  if (!line) { line_px = (size_t)UiFb::W * 2; line = static_cast<uint16_t*>(heap_caps_malloc(line_px * 2, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT)); }
  if (!pixels || !line) {
    Serial.printf("[AVO UI] ERROR: framebuffer allocation failed (psram=%p line=%p)\n", pixels, line);
    gfx->setTextColor(0xFFFF, 0x0000); gfx->setTextSize(3); gfx->setCursor(20, LCD_HEIGHT / 2);
    gfx->print("ERROR PANTALLA");
    return false;
  }
  fb.attach(pixels, line, line_px, UI_ROTATE_180);
  cfgstore::get(&config_cache);
  brightness = config_cache.brightness;
  gfx->setBrightness(brightness);
  board::touch_init();
  BaseType_t ok = xTaskCreatePinnedToCore(task,"ui_lite",4096,nullptr,2,&g_task_handles[TID_UI],0);
  Serial.printf("[AVO MEM] UI V3.7.2 task=%s internal=%u largest=%u psram=%u\n",ok==pdPASS?"OK":"FAIL",
    (unsigned)heap_caps_get_free_size(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
    (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT),
    (unsigned)ESP.getFreePsram());
  return ok == pdPASS;
}
} // namespace ui
