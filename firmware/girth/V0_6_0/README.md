# AVO GIRTH 0.6.0 — firmware de la cincha para la PCB REV D

Solo para la **PCB REV D** (`hardware/girth/PCB_REV_D`): ESP32-C6-MINI-1U + LSM6DSV16X + MMC5983MA + ADS1292.
La cincha actual (XIAO + GY-BNO08X + CJMCU-30003) sigue con la **0.5.0**.

Estado: **compilado en CI · NO VERIFICADO en hardware real** (la placa no está fabricada).

## Qué cambia frente a la 0.5.0
- **IMU:** LSM6DSV16X a 120 Hz (±16 g, ±2000 °/s) con la fusión SFLP del propio chip (vector de rotación «game») y
  MMC5983MA a 100 Hz. Salen las mismas muestras que daba el BNO085 (`girth::Sample`): aceleración, giro, campo
  magnético, aceleración lineal (aceleración − gravedad del cuaternión) y cuaternión, con las mismas unidades.
- **ECG:** ADS1292 canal 2, 500 muestras/s, 24 bits, ganancia 6 (orden `ganancia 1|2|3|4|6|8|12`), RLD al electrodo de
  referencia, detección de electrodo despegado. Mismo lote fmt 2 (enteros de 24 bits en 0,1 µV), 50 muestras ≈ 100 ms.
- **Radio:** orden `phy 1m|6m` para enviar el ESP-NOW a 6 Mbps (≈ 15 mA menos; ver `DOCS/CONSUMO_BATERIA.md` de la
  REV D). Por defecto 1 Mbps, como antes.

## Sin cambios
Protocolo con la espalda (HELLO/WELCOME/STATUS/PING), lotes fmt 0/1/2 y byte de unidades: la espalda, el pecho y las
apps no necesitan cambios para la REV D.

## Pines (REV D)
| Función | GPIO |
|---|---|
| I²C SDA / SCL (LSM6DSV16X 0x6A, MMC5983MA 0x30) | 23 / 16 |
| LSM6 INT1 / INT2 · MMC INT | 2 / 17 · 22 |
| ADS1292 CS / SCLK / DIN / DOUT / DRDY | 0 / 1 / 14 / 7 / 3 |
| ADS1292 PWDN-RESET / START | 4 / 21 |
| Batería (divisor 1:2) · DET · CHG · BOOT | 5 · 6 · 8 · 9 |
| Aro de luz: datos (4 × SK6812SIDE-A) · alimentación (alto = encendido) | 15 · 18 |

## Aro de luz (PCB REV D, 15/11/2026)
Sustituye al LED verde. Los LED solo reciben alimentación mientras se encienden (GPIO18 → Q2 → Q1), así que entre
destellos consumen 0 mA. La línea de datos queda a nivel bajo mientras el aro está apagado.

| Aro | Significado |
|---|---|
| Destello azul cada 0,6 s | Buscando la espalda |
| 1 destello verde cada 2 s | Todo bien |
| 3 destellos ámbar | Electrodos sin contacto (revisar la cincha o el gel) |
| 2 destellos rojos | IMU sin datos |
| 1 destello rojo | Batería por debajo del 15 % |
| Naranja fijo en el soporte | Cargando |
| Verde fijo en el soporte | Cargada |

Comando serie: `aro on|off` (se guarda). Pruebas de host del patrón: `test/test_girth.cpp`.
**Compilado en CI · NO VERIFICADO en hardware.**
