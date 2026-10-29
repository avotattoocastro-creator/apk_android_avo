// AVO GIRTH REV B — alimentación: enclavamiento de la batería (PWR_HOLD), reed, cargador, batería.
//
// Hardware (hardware/girth/PCB, bloque «Corte»): el corte de batería está cerrado mientras PWR_G > ~1,45 V.
// PWR_G se carga por: el impulso del reed al cerrarse (≈ 2,5 s), los 5 V de carga (Qi o USB, siempre) y PWR_HOLD.
// Reglas que cumple este módulo:
//   1. PWR_HOLD = 1 lo primero en setup(): el impulso del reed solo dura unos segundos.
//   2. Apagar = PWR_HOLD a 0 y dormir. Con la base puesta el corte sigue cerrado por los 5 V: no se bloquea nunca.
//   3. Fuera del soporte (reed abierto) y sin carga durante 3 s → apagar.
//   4. Batería < 3,30 V durante 10 s sin carga → apagar (protege la celda).
#pragma once
#include <stdint.h>

namespace gpow {

struct State {
  bool reed_closed = false;   // cápsula en el soporte
  bool power_in = false;      // PGOOD: 5 V presentes (Qi o USB)
  bool charging = false;      // CHG del BQ24072
  bool qi = false;            // el receptor Qi entrega potencia
  uint16_t batt_mv = 0;
};

void hold();                  // PWR_HOLD = 1 (llamar lo primero)
void begin();
State read();                 // entradas + batería (media de 8 lecturas)
const char* boot_reason();    // por qué se encendió (reed, 5 V, reinicio…)
// Apaga: PWR_HOLD = 0, IMU en reposo y sueño profundo. Despierta si se cierra el reed (o, con carga Qi, al quitar
// la base). Sin carga, el corte se abre solo en ~3 s y la placa queda a < 1 µA.
[[noreturn]] void shutdown(const char* why);
// Con carga Qi y fuera del soporte: duerme hasta que se cierre el reed o se quite la base.
[[noreturn]] void sleep_on_charger();

}  // namespace gpow
