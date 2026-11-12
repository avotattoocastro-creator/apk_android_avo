// AVO GIRTH — política de alimentación (sin dependencias de Arduino: se prueba en el PC).
// El firmware llama a step() cada 200 ms con las entradas leídas; la acción decide si apagar o dormir.
#pragma once
#include <stdint.h>

namespace gpol {

enum class Action : uint8_t { NONE = 0, SHUTDOWN_OUT_OF_HOLDER, SHUTDOWN_LOW_BATTERY, SLEEP_ON_CHARGER, SHUTDOWN_REMOTE };

struct Inputs {
  bool reed_closed;     // cápsula en el soporte
  bool power_in;        // 5 V presentes (Qi o USB)
  bool qi;              // los 5 V vienen del Qi
  uint16_t batt_mv;
  bool remote_off;      // orden de apagado (espalda o USB)
};

static const uint32_t OUT_OF_HOLDER_MS = 3000, LOW_BATT_MS = 10000, LOW_BATT_MV = 3300, BOOT_GRACE_MS = 10000;

struct Policy {
  uint32_t out_since = 0, low_since = 0;
  Action step(const Inputs& in, uint32_t now) {
    // «now ? now : 1» y no «now | 1»: con now par, «now | 1» da out_since = now + 1, la resta sin signo se
    // desborda y el apagado es inmediato (lo encontró la prueba alimentacion.fuera_del_soporte_apaga_a_los_3s)
    if (!in.reed_closed && !in.power_in) { if (!out_since) out_since = now ? now : 1; } else out_since = 0;
    if (out_since && now - out_since > OUT_OF_HOLDER_MS) return Action::SHUTDOWN_OUT_OF_HOLDER;
    if (!in.power_in && in.batt_mv > 1000 && in.batt_mv < LOW_BATT_MV) { if (!low_since) low_since = now ? now : 1; } else low_since = 0;
    if (low_since && now - low_since > LOW_BATT_MS) return Action::SHUTDOWN_LOW_BATTERY;
    // en la base Qi y fuera del soporte: no hace falta radio; con USB se queda despierta (consola, programación)
    if (in.power_in && in.qi && !in.reed_closed && now > BOOT_GRACE_MS) return Action::SLEEP_ON_CHARGER;
    if (in.remote_off) return Action::SHUTDOWN_REMOTE;
    return Action::NONE;
  }
};

// El despertar del ESP32-C3 desde el sueño profundo es por nivel: solo se arma el del reed si está abierto
// (si está cerrado despertaría al instante; volver a cerrarlo da un impulso nuevo del hardware).
inline bool arm_reed_wake(bool reed_closed) { return !reed_closed; }

}  // namespace gpol
