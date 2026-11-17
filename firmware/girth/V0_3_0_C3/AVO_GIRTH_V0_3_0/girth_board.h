// AVO GIRTH · placa REV B (ESP32-C3-MINI-1U-N4) — asignación de pines.
// Fuente única del hardware: hardware/girth/PCB/fuente/avo_girth_pcb.py (U4). Si cambia allí, cambia aquí.
#pragma once

namespace gb {

// GPIO0–5 pueden despertar del sueño profundo; ADC1 solo en GPIO0–4 (ESP32-C3).
static const int PIN_IMU_INT  = 0;   // INT1 del LSM6 (activo alto)
static const int PIN_REED     = 1;   // LOW = reed cerrado (cápsula en el soporte), vía Q16
static const int PIN_SCL      = 2;   // I²C SCL · strapping: la hoja del módulo pide 1 al arrancar → 4,7 k a 3,3 V
static const int PIN_BAT_ADC  = 3;   // ADC1_CH3, divisor 1 MΩ / 1 MΩ → V_bat / 2
static const int PIN_CHG_PG   = 4;   // LOW = hay 5 V (Qi o USB) (BQ24072 PGOOD)
static const int PIN_PWR_HOLD = 5;   // 1 = mantener el corte de batería cerrado (Q11/Q10)
static const int PIN_SDA      = 6;   // I²C SDA (LSM6DS3TR-C 0x6A, MMC5983MA 0x30), 4,7 k a 3,3 V
static const int PIN_CHG_STAT = 7;   // LOW = cargando (BQ24072 CHG), pull-up 100 k
static const int PIN_LED      = 8;   // LED rojo, activo a nivel BAJO (strapping: 1 en el arranque)
static const int PIN_BOOT     = 9;   // BOOT (pad TP2), activo a nivel bajo (strapping)
static const int PIN_QI_CHG   = 10;  // LOW = el receptor Qi entrega potencia (BQ51013B CHG)
// GPIO18/19: USB (USB-Serial-JTAG, programación y consola) · GPIO20/21: UART0 (pads TP5/TP4)

static const uint8_t I2C_LSM6 = 0x6A;     // SA0 a GND
static const uint8_t I2C_MMC  = 0x30;

}  // namespace gb
