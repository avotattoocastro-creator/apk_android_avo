// AVO GIRTH 0.6.0 — LSM6DSV16X (SFLP) + MMC5983MA, hardware-independent part, tested on the host.
// Converts the sensors' raw words into the same girth::Sample as the BNO085 (girth_sh2.h), so the fmt 0 / fmt 1
// batches (units byte 1: Q8 m/s², Q9 rad/s, Q4 µT, Q14 quaternion) do not change for the back, chest and apps.
#pragma once
#include <stdint.h>
#include <stddef.h>

namespace girth {
namespace imu6 {

// LSM6DSV16X (register addresses from ST's lsm6dsv16x_reg.h)
static const uint8_t LSM_ADDR = 0x6A, LSM_ID = 0x70;
static const uint8_t FUNC_CFG_ACCESS = 0x01, FIFO_CTRL1 = 0x07, FIFO_CTRL2 = 0x08, FIFO_CTRL3 = 0x09, FIFO_CTRL4 = 0x0A,
                     INT1_CTRL = 0x0D, WHO_AM_I = 0x0F, CTRL1 = 0x10, CTRL2 = 0x11, CTRL3 = 0x12, CTRL6 = 0x15,
                     CTRL8 = 0x17, FIFO_STATUS1 = 0x1B, FIFO_STATUS2 = 0x1C, FIFO_DATA_OUT_TAG = 0x78;
// embedded-functions bank (FUNC_CFG_ACCESS bit 7)
static const uint8_t EMB_FUNC_EN_A = 0x04, EMB_FUNC_FIFO_EN_A = 0x44, SFLP_ODR = 0x5E, EMB_FUNC_INIT_A = 0x66;
// FIFO tags
static const uint8_t TAG_GY = 0x01, TAG_XL = 0x02, TAG_TS = 0x04, TAG_GAME_RV = 0x13, TAG_GBIAS = 0x16, TAG_GRAVITY = 0x17;
// configuration: 120 Hz, ±16 g, ±2000 dps, SFLP game rotation vector at 120 Hz, FIFO in continuous mode
static const uint8_t ODR_120HZ = 0x06, FS_XL_16G = 0x03, FS_G_2000DPS = 0x04, SFLP_120HZ = 0x03, FIFO_STREAM = 0x06;
static const float XL_MG_PER_LSB = 0.488f;        // ±16 g
static const float G_MDPS_PER_LSB = 70.0f;        // ±2000 dps
static const uint32_t ODR_PERIOD_US = 8333;       // nominal (120 Hz); real period measured by EcgClock-style PLL

// MMC5983MA (MEMSIC datasheet): I²C 0x30, product ID 0x30 at 0x2F
static const uint8_t MMC_ADDR = 0x30, MMC_PID = 0x30;
static const uint8_t MMC_XOUT0 = 0x00, MMC_STATUS = 0x08, MMC_CTRL0 = 0x09, MMC_CTRL1 = 0x0A, MMC_CTRL2 = 0x0B,
                     MMC_PRODUCT_ID = 0x2F;
// continuous 100 Hz (BW 01), automatic SET/RESET, periodic SET every 100 measurements
static const uint8_t MMC_CTRL0_AUTO_SR = 0x20, MMC_CTRL1_BW100 = 0x01, MMC_CTRL2_CM100 = 0x80 | 0x30 | 0x08 | 0x05;

float half_to_float(uint16_t h);
// SFLP game rotation vector (x, y, z as half floats) -> unit quaternion (x, y, z, w), w ≥ 0
void sflp_to_quat(const uint16_t h[3], float q[4]);
// unit quaternion (sensor -> world) -> gravity seen in the sensor frame (m/s²)
void gravity_in_sensor(const float q[4], float g[3]);
// helpers to the BNO085 fixed point used by the batches
int16_t to_q(float v, float scale);               // round + saturate to int16
void acc_raw_to_q8(const int16_t raw[3], int16_t out[3], float ms2[3]);
void gyro_raw_to_q9(const int16_t raw[3], int16_t out[3]);
void quat_to_q14(const float q[4], int16_t out[4]);   // order i, j, k, real (as the BNO085)
// MMC5983MA 18-bit output (7 bytes from XOUT0) -> µT in Q4
void mmc_to_q4(const uint8_t b[7], int16_t out[3]);

}  // namespace imu6
}  // namespace girth
