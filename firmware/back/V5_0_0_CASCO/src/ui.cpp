// AVO CASCO — «pantalla» del casco: anillo de SK6812SIDE-A (8 en el PROTOTIPO A, 7 en la REV B) tras el TPS61023.
// Misma interfaz ui:: que la pantalla del pecho. Brillo máximo 30 % (revisión de la placa: F1 y calor).
//
//   Prioridad (de arriba abajo, gana la primera que se cumple)
//   apagándose ............ rojo que se va apagando
//   manteniendo el táctil . blanco que se llena (aviso de apagado a los 3 s)
//   OTA ................... azul girando
//   solo carga (USB/DOCK) . naranja: tantos LED como % de batería; verde fijo al terminar
//   conectar un móvil ..... morado girando (3 toques) · morado parpadeando: el móvil espera confirmación (1 toque)
//   batería baja .......... un LED rojo parpadeando encima del estado GNSS
//   estado GNSS ........... rojo sin ZED · ámbar sin fix · amarillo 3D · cian RTK float · verde RTK FIX
//   grabando .............. el color del GNSS «respira» · móvil conectado: un LED azul en la posición 0
#include <Arduino.h>
#include <math.h>
#include "app_state.h"
#include "board_pins.h"
#include "services.h"
#include "sys_util.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "esp_task_wdt.h"

extern TaskHandle_t g_task_handles[];

namespace ui {

struct Rgb { uint8_t r, g, b; };
static const Rgb OFF = {0, 0, 0}, RED = {255, 0, 0}, AMBER = {255, 110, 0}, YELLOW = {200, 200, 0}, CYAN = {0, 200, 200},
                 GREEN = {0, 255, 0}, BLUE = {0, 60, 255}, PURPLE = {170, 0, 255}, ORANGE = {255, 70, 0}, WHITE = {255, 255, 255};

static volatile bool s_off = false;     // casco_ring_off(): apagado definitivo
static volatile bool s_wifi_pause = false;
static bool s_powered = false, s_rmt = false;
static rmt_data_t s_sym[LED_COUNT * 24];

static void ring_power(bool on) {
  if (on == s_powered) return;
  if (on) {
    digitalWrite(PIN_LED_PWR, HIGH);   // TPS61023 a 4,20 V
    delay(2);
    if (!s_rmt) s_rmt = rmtInit(PIN_LED_DIN, RMT_TX_MODE, RMT_MEM_NUM_BLOCKS_1, 10000000);   // 100 ns por tic
  } else {
    if (s_rmt) { rmtDeinit(PIN_LED_DIN); s_rmt = false; }
    pinMode(PIN_LED_DIN, OUTPUT);
    digitalWrite(PIN_LED_DIN, LOW);    // regla 5: DIN a 0 con el anillo apagado (no alimentar los LED por la entrada)
    digitalWrite(PIN_LED_PWR, LOW);
  }
  s_powered = on;
}

// SK6812: orden GRB, 0 = 0,3 µs alto + 0,9 µs bajo, 1 = 0,6 + 0,6 µs.
static void show(const Rgb* px) {
  bool any = false;
  for (int i = 0; i < LED_COUNT; i++) any |= px[i].r || px[i].g || px[i].b;
  if (!any) { ring_power(false); return; }
  ring_power(true);
  if (!s_rmt) return;
  int k = 0;
  for (int i = 0; i < LED_COUNT; i++) {
    const uint8_t c[3] = {px[i].g, px[i].r, px[i].b};
    for (uint8_t byte : c)
      for (int bit = 7; bit >= 0; bit--) {
        const bool one = (byte >> bit) & 1;
        s_sym[k].level0 = 1; s_sym[k].duration0 = one ? 6 : 3;
        s_sym[k].level1 = 0; s_sym[k].duration1 = one ? 6 : 9;
        k++;
      }
  }
  rmtWrite(PIN_LED_DIN, s_sym, k, 20);
}

static Rgb scale(Rgb c, float f) {
  if (f < 0) f = 0;
  if (f > 1) f = 1;
  const float m = f * LED_MAX_BRIGHT / 255.0f;   // nunca por encima del 30 %
  return {(uint8_t)(c.r * m), (uint8_t)(c.g * m), (uint8_t)(c.b * m)};
}

static void fill(Rgb* px, Rgb c) { for (int i = 0; i < LED_COUNT; i++) px[i] = c; }

static void frame(const AppSnapshot& s, uint32_t now, Rgb* px) {
  fill(px, OFF);
  const float breathe = 0.55f + 0.45f * sinf(now * 0.004f);   // ≈ 1,5 s
  const int spin = (int)((now / 120) % LED_COUNT);
  const bool blink = (now / 500) % 2;
  if (s.power.shutdown_requested) {
    const float f = s.power.shutdown_phase >= 4 ? 0.0f : 1.0f - s.power.shutdown_phase * 0.2f;
    fill(px, scale(RED, f));
    return;
  }
  if (s.power.pwr_hold_permille > 150) {   // el táctil se está manteniendo: a los 3 s se apaga
    const int n = (int)((s.power.pwr_hold_permille * LED_COUNT + 999) / 1000);
    for (int i = 0; i < n && i < LED_COUNT; i++) px[i] = scale(WHITE, 0.7f);
    return;
  }
  if (!s.sys.display_on) return;   // un toque corto apaga o enciende el anillo (la tecla PWR del pecho)
  if (s.ble.ota_active) {
    for (int i = 0; i < 3; i++) px[(spin + i) % LED_COUNT] = scale(BLUE, 1.0f - i * 0.3f);
    return;
  }
  if (s.power.charge_boot) {
    const int pct = s.power.pmu.batt_pct;
    if (s.power.pmu.vbus && !s.power.pmu.charging && pct >= 95) { fill(px, scale(GREEN, 0.3f)); return; }
    const int n = pct < 0 ? 1 : 1 + pct * (LED_COUNT - 1) / 100;
    for (int i = 0; i < n; i++) px[i] = scale(ORANGE, i == n - 1 ? breathe : 0.5f);
    return;
  }
  if (s.ble.pair_mode) {
    for (int i = 0; i < 2; i++) px[(spin + i) % LED_COUNT] = scale(PURPLE, 1.0f - i * 0.4f);
    return;
  }
  if (s.ble.claim_pending) { if (blink) fill(px, scale(PURPLE, 0.8f)); return; }
  // Estado GNSS (lo que importa al jinete): del NAV-PVT que llega por la espalda interna.
  Rgb g = RED;
  const bool zed_ok = s.link.status_valid && s.link.back.zed_detail == 3;
  if (zed_ok && s.gnss.have && sys::ms() - s.gnss.rx_ms < 3000) {
    const uint8_t carr = (s.gnss.s.flags >> 6) & 3;
    if (s.gnss.s.fix_type < 3 || !s.gnss.s.gnss_fix_ok()) g = AMBER;
    else if (carr == 2) g = GREEN;
    else if (carr == 1) g = CYAN;
    else g = YELLOW;
  } else if (zed_ok) g = AMBER;
  const bool rec = s.storage.rec == RecStatus::RECORDING;
  fill(px, scale(g, rec ? breathe : 0.6f));
  if (s.ble.connected) px[0] = scale(BLUE, 0.8f);
  if (s.power.level == avo::PowerLevel::LOWBAT || s.power.level == avo::PowerLevel::CRITICAL)
    px[LED_COUNT / 2] = blink ? scale(RED, 1.0f) : OFF;
}

static void task(void*) {
  esp_task_wdt_add(nullptr);
  static Rgb px[LED_COUNT];
  AppSnapshot* snap = new AppSnapshot();
  const uint32_t t0 = sys::ms();
  for (;;) {
    const uint32_t now = sys::ms();
    if (s_off) {
      fill(px, OFF);
      show(px);
    } else if (now - t0 < 2500) {   // regla 4: el anillo es lo último en encenderse (tras el ZED)
      fill(px, OFF);
      show(px);
    } else {
      appstate::get(snap);
      frame(*snap, now, px);
      show(px);
    }
    esp_task_wdt_reset();
    vTaskDelay(pdMS_TO_TICKS(s_wifi_pause ? 250 : 50));
  }
}

bool init() {
  pinMode(PIN_LED_PWR, OUTPUT);
  digitalWrite(PIN_LED_PWR, LOW);
  pinMode(PIN_LED_DIN, OUTPUT);
  digitalWrite(PIN_LED_DIN, LOW);
  return xTaskCreatePinnedToCore(task, "ui", 4096, nullptr, 3, &g_task_handles[TID_UI], 1) == pdPASS;
}

void casco_ring_off() {
  s_off = true;
  vTaskDelay(pdMS_TO_TICKS(120));   // la tarea apaga el elevador y deja DIN a 0
  digitalWrite(PIN_LED_PWR, LOW);   // por si la tarea no llegó a hacerlo
}

void show_passkey(uint32_t, bool) {}   // BLE sin pantalla (NO_INPUT_OUTPUT): la autorización es con el táctil
void wake() { appstate::update([](AppSnapshot& s) { s.sys.display_on = true; }); }
void next_screen() {}
void home_screen() {}
void pause_for_wifi() { s_wifi_pause = true; }
void resume_after_wifi() { s_wifi_pause = false; }

}  // namespace ui
