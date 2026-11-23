// AVO CASCO BACK V5 (PROTOTIPO A y REV B: mismos GPIO) — mapa de pines.
// Fuente: hardware/back/V5_CASCO_PROTOTIPO/PCB/fuente/avo_back_v5_pcb.py (diccionario GPIO del módulo U4,
// ESP32-S3-WROOM-1U-N16R8) y la revisión previa a fabricación (claude/AVO_BACK_V5_REVISION_PRE_FABRICACION).
// Los nombres que ya usaba el pecho (PIN_I2C_*, PIN_SD_*, PIN_BOOT_BTN, PIN_PWR_SENSE) se conservan para no tocar
// sus módulos; el resto son nuevos del casco.
#pragma once

#define AVO_CASCO 1

// ---------------------------------------------------------------- I2C: MAX17048 (0x36) + LSM6DSV16X (0x6A)
#define PIN_I2C_SDA 42
#define PIN_I2C_SCL 41
#define I2C_FREQ_HZ 400000
#define I2C_ADDR_MAX17048 0x36
#define I2C_ADDR_LSM6DSV16X 0x6A

// ---------------------------------------------------------------- microSD (SDMMC 4 bits) + interruptor de alimentación
#define PIN_SD_CLK 12
#define PIN_SD_CMD 13
#define PIN_SD_D0 14
#define PIN_SD_D1 15
#define PIN_SD_D2 16
#define PIN_SD_D3 17
#define PIN_SD_PWR_N 21          // Q4 (PMOS): 0 = tarjeta alimentada, 1 = cortada (R40 la deja apagada al arrancar)

// ---------------------------------------------------------------- encendido y entradas
#define PIN_PWR_HOLD 46          // enclavamiento del 3,3 V (pin de arranque: R15 100k a GND). 1 = mantener encendido
#define PIN_TOUCH 11             // salida del TTP223 (activa ALTA mientras se toca). RTC: despierta del sueño profundo
#define PIN_VBUS_DET 18          // 1 = cable del pogo o USB-C conectado (divisor 1k/1k5, RTC)
#define PIN_CHG_PG 38            // BQ24072 PGOOD (colector abierto, activo BAJO): entrada válida
#define PIN_CHG_STAT 39          // BQ24072 CHG (colector abierto, activo BAJO): cargando
#define PIN_BAT_ADC 2            // divisor 1:2 de VBAT (ADC1_CH1); reserva si el MAX17048 no responde
#define PIN_HALL 1               // DRV5032: 0 = casco en la base con imán (RTC)
#define PIN_IMU_INT1 4           // LSM6DSV16X INT1 (RTC)
#define PIN_POGO_AUX 40          // contacto libre del pogo (reservado)

// El pecho leía un botón BOOT (activo BAJO) y la tecla PWR (activa ALTA). En el casco las dos son el táctil:
// controller.cpp lee los dos con AVO_BTN_PRESSED / AVO_PWR_PRESSED.
#define PIN_BOOT_BTN PIN_TOUCH
#define PIN_PWR_SENSE PIN_TOUCH
#define AVO_BTN_PRESSED(level) ((level) == HIGH)
#define AVO_PWR_PRESSED(level) ((level) == HIGH)

// ---------------------------------------------------------------- ZED-F9P (URTK1.2 en el PROTOTIPO A, soldado en la REV B)
#define PIN_ZED_RX 5             // ← TX1 del ZED (330 Ω)
#define PIN_ZED_TX 6             // → RX1 del ZED (1 kΩ). A 0 antes de cortar ZED_EN
#define PIN_ZED_RX2 3            // ← TX2 del ZED (sin usar: pin de arranque, se deja en entrada)
#define PIN_ZED_TX2 8            // → RX2 del ZED (sin usar: a 0 para no alimentar el ZED apagado)
#define PIN_ZED_PPS 7
#define PIN_ZED_RST 9            // RESET_N en colector abierto (1 kΩ). No se usa de forma rutinaria
#define PIN_ZED_EN 10            // EN del RT9080 (3,3 V del ZED y de la antena activa). 1 = encendido

// ---------------------------------------------------------------- anillo LED (SK6812SIDE-A tras el TPS61023)
#define PIN_LED_DIN 47           // datos (330 Ω). A 0 con el anillo apagado
#define PIN_LED_PWR 48           // EN del elevador (4,20 V). 0 = anillo sin alimentación
#define LED_COUNT 8              // PROTOTIPO A: 8 (REV B: 7; el octavo dato se pierde sin daño)
#define LED_MAX_BRIGHT 77        // 30 % de 255: límite de la revisión (F1 1,5 A y calor)

// ---------------------------------------------------------------- enlace por cable con la espalda (no existe en el casco)
#define PIN_LINK_TX -1
#define PIN_LINK_RX -1
