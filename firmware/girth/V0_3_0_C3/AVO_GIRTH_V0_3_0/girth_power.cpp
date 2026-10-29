#include "girth_power.h"
#include "girth_board.h"
#include "girth_imu.h"
#include "girth_policy.h"
#include <Arduino.h>
#include <esp_sleep.h>
#include <driver/gpio.h>

namespace gpow {

void hold() {
  gpio_hold_dis((gpio_num_t)gb::PIN_PWR_HOLD);
  pinMode(gb::PIN_PWR_HOLD, OUTPUT);
  digitalWrite(gb::PIN_PWR_HOLD, HIGH);
}

void begin() {
  pinMode(gb::PIN_REED, INPUT);        // pull-up externo R31 (100 k)
  pinMode(gb::PIN_CHG_PG, INPUT);      // pull-up externo R9
  pinMode(gb::PIN_CHG_STAT, INPUT);    // pull-up externo R10
  pinMode(gb::PIN_QI_CHG, INPUT);      // pull-up externo R4
  pinMode(gb::PIN_IMU_INT, INPUT);
  analogReadResolution(12);
  analogSetPinAttenuation(gb::PIN_BAT_ADC, ADC_11db);
}

State read() {
  State s;
  s.reed_closed = digitalRead(gb::PIN_REED) == LOW;
  s.power_in = digitalRead(gb::PIN_CHG_PG) == LOW;
  s.charging = digitalRead(gb::PIN_CHG_STAT) == LOW;
  s.qi = digitalRead(gb::PIN_QI_CHG) == LOW;
  uint32_t mv = 0;
  for (int i = 0; i < 8; i++) mv += analogReadMilliVolts(gb::PIN_BAT_ADC);
  s.batt_mv = (uint16_t)((mv / 8) * 2);   // divisor 1:2
  return s;
}

const char* boot_reason() {
  switch (esp_sleep_get_wakeup_cause()) {
    case ESP_SLEEP_WAKEUP_GPIO: return "despertar por GPIO (reed o base)";
    default: break;
  }
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "encendido (reed o 5 V)";
    case ESP_RST_SW: return "reinicio por software";
    case ESP_RST_PANIC: return "reinicio tras un fallo";
    case ESP_RST_INT_WDT: case ESP_RST_TASK_WDT: case ESP_RST_WDT: return "reinicio por vigilante";
    case ESP_RST_BROWNOUT: return "caída de tensión";
    case ESP_RST_USB: return "reinicio por USB";
    default: return "otro";
  }
}

static void prepare_sleep() {
  gimu::sleep();
  digitalWrite(gb::PIN_LED, HIGH);                                 // LED apagado (activo bajo)
  // El despertar del C3 es por nivel: con el reed ya cerrado despertaría al instante (y volvería a encender).
  // Solo se arma si el reed está abierto; con el reed cerrado no hace falta: volver a cerrarlo da un impulso nuevo
  // del hardware (C40) que enciende la placa desde cero.
  if (gpol::arm_reed_wake(digitalRead(gb::PIN_REED) == LOW))
    esp_deep_sleep_enable_gpio_wakeup(1ULL << gb::PIN_REED, ESP_GPIO_WAKEUP_GPIO_LOW);
}

void shutdown(const char* why) {
  Serial.printf("[AVO CINCHA] APAGADO: %s. PWR_HOLD = 0; sin carga el corte se abre en ~3 s.\n", why);
  Serial.flush();
  delay(20);
  digitalWrite(gb::PIN_PWR_HOLD, LOW);
  gpio_hold_en((gpio_num_t)gb::PIN_PWR_HOLD);                      // sigue a 0 durante el sueño
  prepare_sleep();
  // con la base Qi puesta el corte no se abre: despertar también al quitarla para apagar del todo
  if (digitalRead(gb::PIN_CHG_PG) == LOW)
    esp_deep_sleep_enable_gpio_wakeup(1ULL << gb::PIN_CHG_PG, ESP_GPIO_WAKEUP_GPIO_HIGH);
  esp_deep_sleep_start();
  while (true) {}
}

void sleep_on_charger() {
  Serial.println("[AVO CINCHA] en la base Qi y fuera del soporte: sueño profundo hasta cerrar el reed o quitar la base");
  Serial.flush();
  delay(20);
  digitalWrite(gb::PIN_PWR_HOLD, LOW);       // al quitar la base, el corte se abre solo
  gpio_hold_en((gpio_num_t)gb::PIN_PWR_HOLD);
  prepare_sleep();
  esp_deep_sleep_enable_gpio_wakeup(1ULL << gb::PIN_CHG_PG, ESP_GPIO_WAKEUP_GPIO_HIGH);
  esp_deep_sleep_start();
  while (true) {}
}

}  // namespace gpow
