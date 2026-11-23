// AVO CASCO BACK V5 — placa: I2C, batería (MAX17048 + BQ24072), encendido (PWR_HOLD + táctil), sin RTC ni pantalla.
// Misma interfaz que el hal_board del pecho (hal_board.h no cambia): el resto del firmware del pecho la usa igual.
#include "hal_board.h"
#include "board_pins.h"
#include <Arduino.h>
#include <Wire.h>
#include <atomic>
#include <driver/gpio.h>
#include <esp_sleep.h>
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "casco_back.h"

// ---------------------------------------------------------------- lo primero del arranque
// Regla 1 de la revisión de la placa: PWR_HOLD (GPIO46) a 1 lo antes posible y retenido en los reinicios y en el sueño.
// C28 + R14 mantienen EN ≈ 1 s mientras el micro arranca. initVariant() lo llama el núcleo de Arduino antes de setup().
extern "C" void initVariant() {
  gpio_hold_dis((gpio_num_t)PIN_PWR_HOLD);
  gpio_set_direction((gpio_num_t)PIN_PWR_HOLD, GPIO_MODE_OUTPUT);
  gpio_set_level((gpio_num_t)PIN_PWR_HOLD, 1);
  gpio_hold_en((gpio_num_t)PIN_PWR_HOLD);
  gpio_deep_sleep_hold_en();
  // Lo demás apagado hasta que cada módulo lo encienda en orden (ESP32 → microSD → ZED → anillo).
  gpio_set_direction((gpio_num_t)PIN_LED_PWR, GPIO_MODE_OUTPUT);
  gpio_set_level((gpio_num_t)PIN_LED_PWR, 0);
  gpio_set_direction((gpio_num_t)PIN_LED_DIN, GPIO_MODE_OUTPUT);
  gpio_set_level((gpio_num_t)PIN_LED_DIN, 0);
  gpio_set_direction((gpio_num_t)PIN_ZED_EN, GPIO_MODE_OUTPUT);
  gpio_set_level((gpio_num_t)PIN_ZED_EN, 0);
  gpio_set_direction((gpio_num_t)PIN_ZED_TX, GPIO_MODE_OUTPUT);
  gpio_set_level((gpio_num_t)PIN_ZED_TX, 0);
  gpio_set_direction((gpio_num_t)PIN_ZED_TX2, GPIO_MODE_OUTPUT);
  gpio_set_level((gpio_num_t)PIN_ZED_TX2, 0);
  gpio_set_direction((gpio_num_t)PIN_ZED_RX2, GPIO_MODE_INPUT);
  gpio_set_direction((gpio_num_t)PIN_ZED_RST, GPIO_MODE_INPUT);   // colector abierto: suelto = sin reset
  gpio_set_direction((gpio_num_t)PIN_SD_PWR_N, GPIO_MODE_OUTPUT);
  gpio_set_level((gpio_num_t)PIN_SD_PWR_N, 1);
}

namespace board {

static SemaphoreHandle_t s_i2c = nullptr;
static std::atomic<uint32_t> s_i2c_err{0};

bool i2c_init() {
  if (!s_i2c) s_i2c = xSemaphoreCreateRecursiveMutex();
  return Wire.begin(PIN_I2C_SDA, PIN_I2C_SCL, I2C_FREQ_HZ);
}
bool i2c_lock(uint32_t t) { return s_i2c && xSemaphoreTakeRecursive(s_i2c, pdMS_TO_TICKS(t)) == pdTRUE; }
void i2c_unlock() { if (s_i2c) xSemaphoreGiveRecursive(s_i2c); }
uint32_t i2c_errors() { return s_i2c_err; }

static int reg_read16(uint8_t dev, uint8_t reg, uint16_t* v) {
  Wire.beginTransmission(dev);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) { s_i2c_err++; return -1; }
  if (Wire.requestFrom((uint16_t)dev, (size_t)2, true) != 2) { s_i2c_err++; return -1; }
  uint8_t hi = (uint8_t)Wire.read(), lo = (uint8_t)Wire.read();
  *v = (uint16_t)((hi << 8) | lo);   // MAX17048: registros de 16 bits, MSB primero
  return 0;
}

// ---------------------------------------------------------------- táctil (TTP223): pulsaciones para pmu_read
// El pecho recibía las pulsaciones de la tecla PWR por interrupción del AXP2101. Aquí controller.cpp lee el táctil
// directamente (PIN_PWR_SENSE = PIN_TOUCH); pkey_* quedan a false.

// ---------------------------------------------------------------- PMU (MAX17048 + BQ24072 + VBUS_DET)
static bool s_gauge = false;
static uint32_t s_boot_ms = 0;
static uint8_t s_pon = 0xFF;
static bool s_by_usb = false;

uint8_t pmu_poweron_status() { return s_pon; }
// Encendido por el USB/pogo (VBUS_DET alto) sin tocar el táctil: modo «solo carga», como el pecho 3.7.10.
bool pmu_powered_on_by_usb() { return s_by_usb; }

static uint16_t adc_batt_mv() {
  uint32_t acc = 0;
  for (int i = 0; i < 8; i++) acc += analogReadMilliVolts(PIN_BAT_ADC);
  return (uint16_t)(acc / 8 * 2);   // divisor 1:2 (R32/R33 1 MΩ)
}

bool pmu_init() {
  s_boot_ms = millis();
  pinMode(PIN_VBUS_DET, INPUT);
  pinMode(PIN_CHG_PG, INPUT);      // R9 100k a +3V3
  pinMode(PIN_CHG_STAT, INPUT);    // R10 100k a +3V3
  pinMode(PIN_TOUCH, INPUT);
  pinMode(PIN_HALL, INPUT);
  analogSetPinAttenuation(PIN_BAT_ADC, ADC_11db);
  const bool vbus = digitalRead(PIN_VBUS_DET) == HIGH;
  const bool touch = digitalRead(PIN_TOUCH) == HIGH;
  s_by_usb = vbus && !touch;
  s_pon = (uint8_t)((touch ? 0x01 : 0) | (vbus ? 0x04 : 0));   // mismos bits que el registro 0x20 del AXP2101
  if (!i2c_lock(200)) return false;
  uint16_t ver = 0;
  s_gauge = reg_read16(I2C_ADDR_MAX17048, 0x08, &ver) == 0 && (ver & 0xFFF0) == 0x0010;   // VERSION 0x001x
  i2c_unlock();
  Serial.printf("[AVO CASCO] medidor MAX17048 %s (VERSION 0x%04X), encendido por %s\n", s_gauge ? "OK" : "NO RESPONDE",
                (unsigned)ver, s_by_usb ? "USB/pogo (solo carga)" : "tactil");
  return true;   // sin medidor se usa el divisor de GPIO2
}

bool pmu_configure_power_key() { return true; }

bool pmu_read(PmuStatus* s) {
  PmuStatus p;
  p.online = true;
  p.vbus = digitalRead(PIN_VBUS_DET) == HIGH;
  p.charging = digitalRead(PIN_CHG_STAT) == LOW;
  p.charger_state = (uint8_t)((digitalRead(PIN_CHG_PG) == LOW ? 1 : 0) | (p.charging ? 2 : 0));
  uint16_t vcell = 0, soc = 0;
  bool ok = false;
  // Regla 7: el MAX17048 recalcula el % por tensión al encender; se lee a partir de 3 s.
  if (s_gauge && millis() - s_boot_ms >= 3000 && i2c_lock(50)) {
    ok = reg_read16(I2C_ADDR_MAX17048, 0x02, &vcell) == 0 && reg_read16(I2C_ADDR_MAX17048, 0x04, &soc) == 0;
    i2c_unlock();
  }
  if (ok) {
    p.batt_mv = (uint16_t)((uint32_t)vcell * 78125u / 1000000u);   // 78,125 µV/LSB
    int pct = soc >> 8;                                             // 1/256 %
    p.batt_pct = pct > 100 ? 100 : pct;
  } else {
    p.batt_mv = adc_batt_mv();
    p.batt_pct = -1;
  }
  p.batt_present = p.batt_mv > 2500 && p.batt_mv < 4600;
  if (!p.batt_present) { p.batt_mv = 0; p.batt_pct = -1; }
  p.vbus_mv = p.vbus ? 5000 : 0;
  p.sys_mv = p.batt_mv;
  p.die_temp_c = temperatureRead();
  casco_back::set_battery_mv(p.batt_mv);
  *s = p;
  return true;
}

// Apagado controlado (el pecho ya cerró la sesión y la microSD): ZED, tarjeta y anillo fuera, y se suelta PWR_HOLD.
// Con el cable conectado el EN se mantiene por VBUS: controller.cpp sigue con el sueño profundo (despierta con el táctil).
void pmu_power_off() {
  casco_back::power_off_peripherals();
  gpio_hold_dis((gpio_num_t)PIN_PWR_HOLD);
  gpio_set_level((gpio_num_t)PIN_PWR_HOLD, 0);
  gpio_hold_en((gpio_num_t)PIN_PWR_HOLD);   // también a 0 durante el sueño profundo si el VBUS mantiene la placa
  Serial.println("[AVO CASCO] PWR_HOLD a 0: apagado");
  Serial.flush();
}

// ---------------------------------------------------------------- RTC y pantalla táctil: no existen en el casco
// La hora sale del GNSS (NAV-PVT) o del móvil, como en el pecho cuando el RTC no es válido.
bool rtc_read_unix(uint64_t*, bool* valid) { if (valid) *valid = false; return false; }
bool rtc_write_unix(uint64_t) { return false; }
bool touch_init() { return false; }
bool touch_read(bool* touched, int16_t*, int16_t*) { if (touched) *touched = false; return false; }
uint32_t touch_errors() { return 0; }

}  // namespace board
