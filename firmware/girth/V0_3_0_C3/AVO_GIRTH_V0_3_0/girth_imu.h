// AVO GIRTH REV B — IMU por I²C: LSM6DS3TR-C (o LSM6DSV16X, misma huella) + MMC5983MA.
// Entrega muestras de 9 ejes en LSB brutos, el formato IMU_FMT_9AXIS_I16 del protocolo de la cincha:
//   ax ay az: ±8 g     (LSM6DS3TR-C 0,244 mg/LSB; LSM6DSV16X 0,244 mg/LSB)
//   gx gy gz: ±2000 dps (70 mdps/LSB en los dos)
//   mx my mz: ±8 G      (MMC5983MA en 16 bits: 4096 LSB/G, cero en 0; 0,244 mG/LSB)
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace gimu {

enum class Accel : uint8_t { NONE = 0, LSM6DS3TRC = 1, LSM6DSV16X = 2 };

struct Sample { int16_t v[9]; };   // ax ay az gx gy gz mx my mz

struct Info {
  Accel accel = Accel::NONE;
  uint8_t accel_whoami = 0;
  bool mag = false;
  uint8_t mag_id = 0;
  uint32_t i2c_errors = 0;
  uint32_t samples = 0;
};

bool begin();                 // Wire en GPIO6/7 a 400 kHz, detecta y configura (104/120 Hz, 100 Hz el magnetómetro)
bool read(Sample* s);         // una muestra (acel+giro del LSM6, último valor del magnetómetro)
void sleep();                 // LSM6 y MMC en reposo (antes de apagar o dormir)
const Info& info();
Sample last();                // última muestra leída (copia protegida)
int scan(uint8_t* found, int cap);   // direcciones I²C que responden (diagnóstico)
const char* accel_name();

}  // namespace gimu
