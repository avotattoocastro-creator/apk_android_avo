// AVO GIRTH REV B — controladores mínimos (registros de los datasheets):
//  · LSM6DS3TR-C (ST DS12093): WHO_AM_I 0Fh = 6Ah; CTRL1_XL 10h, CTRL2_G 11h, CTRL3_C 12h; OUTX_L_G 22h…OUTZ_H_XL 2Dh.
//  · LSM6DSV16X  (ST DS13510): WHO_AM_I 0Fh = 70h; CTRL1 10h, CTRL2 11h, CTRL3 12h, CTRL6 15h (FS_G), CTRL8 17h (FS_XL).
//  · MMC5983MA   (MEMSIC Rev A): Product ID 2Fh = 30h; Internal Control 0/1/2 = 09h/0Ah/0Bh; Xout0…Zout1 00h…05h.
#include "girth_imu.h"
#include "girth_board.h"
#include <Arduino.h>
#include <Wire.h>

namespace gimu {

static Info s_info;
static int16_t s_mag[3] = {0, 0, 0};
static Sample s_last = {};
// una sola tarea a la vez en el I²C (la tarea de la IMU y el diagnóstico del monitor USB)
static SemaphoreHandle_t s_mx = nullptr;
struct Lock {
  Lock() { if (s_mx) xSemaphoreTake(s_mx, portMAX_DELAY); }
  ~Lock() { if (s_mx) xSemaphoreGive(s_mx); }
};

static bool wr(uint8_t addr, uint8_t reg, uint8_t v) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  Wire.write(v);
  bool ok = Wire.endTransmission() == 0;
  if (!ok) s_info.i2c_errors++;
  return ok;
}

static bool rd(uint8_t addr, uint8_t reg, uint8_t* buf, size_t n) {
  Wire.beginTransmission(addr);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) { s_info.i2c_errors++; return false; }
  if (Wire.requestFrom((int)addr, (int)n) != (int)n) { s_info.i2c_errors++; return false; }
  for (size_t i = 0; i < n; i++) buf[i] = (uint8_t)Wire.read();
  return true;
}

static bool probe(uint8_t addr) {
  Wire.beginTransmission(addr);
  return Wire.endTransmission() == 0;
}

int scan(uint8_t* found, int cap) {
  Lock l;
  int n = 0;
  for (uint8_t a = 0x08; a < 0x78; a++)
    if (probe(a) && n < cap) found[n++] = a;
  return n;
}

const Info& info() { return s_info; }

const char* accel_name() {
  switch (s_info.accel) {
    case Accel::LSM6DS3TRC: return "LSM6DS3TR-C";
    case Accel::LSM6DSV16X: return "LSM6DSV16X";
    default: return "ninguno";
  }
}

static bool lsm6_begin() {
  uint8_t who = 0;
  if (!rd(gb::I2C_LSM6, 0x0F, &who, 1)) return false;
  s_info.accel_whoami = who;
  if (who == 0x6A) {                                   // LSM6DS3TR-C
    wr(gb::I2C_LSM6, 0x12, 0x01);                      // CTRL3_C: SW_RESET
    delay(20);
    bool ok = wr(gb::I2C_LSM6, 0x12, 0x44)             // CTRL3_C: BDU, IF_INC
           && wr(gb::I2C_LSM6, 0x10, 0x4C)             // CTRL1_XL: 104 Hz, ±8 g
           && wr(gb::I2C_LSM6, 0x11, 0x4C)             // CTRL2_G: 104 Hz, ±2000 dps
           && wr(gb::I2C_LSM6, 0x0D, 0x01);            // INT1_CTRL: dato de acelerómetro listo → INT1 (GPIO0)
    if (ok) s_info.accel = Accel::LSM6DS3TRC;
    return ok;
  }
  if (who == 0x70) {                                   // LSM6DSV16X
    wr(gb::I2C_LSM6, 0x12, 0x01);                      // CTRL3: SW_RESET
    delay(20);
    bool ok = wr(gb::I2C_LSM6, 0x12, 0x44)             // CTRL3: BDU, IF_INC
           && wr(gb::I2C_LSM6, 0x17, 0x02)             // CTRL8: FS_XL ±8 g
           && wr(gb::I2C_LSM6, 0x15, 0x04)             // CTRL6: FS_G ±2000 dps
           && wr(gb::I2C_LSM6, 0x10, 0x06)             // CTRL1: alto rendimiento, 120 Hz
           && wr(gb::I2C_LSM6, 0x11, 0x06)             // CTRL2: alto rendimiento, 120 Hz
           && wr(gb::I2C_LSM6, 0x0D, 0x01);            // INT1_CTRL: dato de acelerómetro listo → INT1
    if (ok) s_info.accel = Accel::LSM6DSV16X;
    return ok;
  }
  return false;
}

static bool mmc_begin() {
  uint8_t id = 0;
  if (!rd(gb::I2C_MMC, 0x2F, &id, 1)) return false;
  s_info.mag_id = id;
  if (id != 0x30) return false;
  wr(gb::I2C_MMC, 0x0A, 0x80);                         // Internal Control 1: SW_RST
  delay(15);
  bool ok = wr(gb::I2C_MMC, 0x09, 0x08)                // SET: imanación inicial
         && (delay(1), true)
         && wr(gb::I2C_MMC, 0x0A, 0x01)                // BW = 01 (medida de 4 ms)
         && wr(gb::I2C_MMC, 0x09, 0x20)                // Auto_SR_en: SET/RESET automático
         && wr(gb::I2C_MMC, 0x0B, 0x08 | 0x05);        // Cmm_en + Cm_freq 101 = 100 Hz continuo
  s_info.mag = ok;
  return ok;
}

bool begin() {
  if (!s_mx) s_mx = xSemaphoreCreateMutex();
  Lock l;
  Wire.begin(gb::PIN_SDA, gb::PIN_SCL, 400000);
  Wire.setTimeOut(20);
  bool a = lsm6_begin();
  mmc_begin();                                         // opcional
  return a;
}

uint32_t period_us() { return s_info.accel == Accel::LSM6DSV16X ? 8333 : 9615; }

static void mmc_read() {
  if (!s_info.mag) return;
  uint8_t b[6];
  if (!rd(gb::I2C_MMC, 0x00, b, 6)) return;
  for (int i = 0; i < 3; i++) {
    uint16_t u = ((uint16_t)b[2 * i] << 8) | b[2 * i + 1];   // salida de 16 bits sin signo, cero de campo en 32768
    s_mag[i] = (int16_t)((int32_t)u - 32768);
  }
}

bool read(Sample* s) {
  if (s_info.accel == Accel::NONE) return false;
  Lock l;
  uint8_t b[12];
  if (!rd(gb::I2C_LSM6, 0x22, b, 12)) return false;            // giro X,Y,Z y acelerómetro X,Y,Z (little-endian)
  int16_t g[3], a[3];
  for (int i = 0; i < 3; i++) {
    g[i] = (int16_t)((uint16_t)b[2 * i] | ((uint16_t)b[2 * i + 1] << 8));
    a[i] = (int16_t)((uint16_t)b[6 + 2 * i] | ((uint16_t)b[6 + 2 * i + 1] << 8));
  }
  mmc_read();
  s->v[0] = a[0]; s->v[1] = a[1]; s->v[2] = a[2];
  s->v[3] = g[0]; s->v[4] = g[1]; s->v[5] = g[2];
  s->v[6] = s_mag[0]; s->v[7] = s_mag[1]; s->v[8] = s_mag[2];
  s_info.samples++;
  s_last = *s;
  return true;
}

Sample last() {
  Lock l;
  return s_last;
}

void sleep() {
  Lock l;
  if (s_info.accel == Accel::LSM6DS3TRC) { wr(gb::I2C_LSM6, 0x10, 0x00); wr(gb::I2C_LSM6, 0x11, 0x00); }
  if (s_info.accel == Accel::LSM6DSV16X) { wr(gb::I2C_LSM6, 0x10, 0x00); wr(gb::I2C_LSM6, 0x11, 0x00); }
  if (s_info.mag) wr(gb::I2C_MMC, 0x0B, 0x00);                 // sin medida continua: reposo (~1 µA)
}

}  // namespace gimu
