# AVO GIRTH 0.5.0 — cincha con IMU + ECG (MAX30003)

Arquitectura confirmada (2026-11-15): **pogo + BNO085 + MAX30003**, cápsula REV 5.10, **dos placas de electrodo
separadas** en la cincha (una a cada lado del pecho) unidas a la cápsula por cable plano.

Estado: **compilado en CI · NO VERIFICADO en hardware real**. Las pruebas de host demuestran los formatos de bytes,
la conversión de unidades, el reloj de muestras y el paso por el `GirthHub` real de la espalda; no prueban el chip,
los electrodos ni la radio.

## Cableado (REV 5.10)

| MAX30003 (CJMCU-30003) | XIAO ESP32-C6 | GPIO |
|---|---|---|
| CSB | D7 | 17 |
| SCLK | D8 | 19 |
| SDO (MISO) | D9 | 20 |
| SDI (MOSI) | D10 | 18 |
| INTB | MTDO | 7 |
| FCLK | MTMS | 4 (solo si el módulo no lleva cristal de 32 768 Hz) |
| VCC / GND | 3V3 / GND | — |

Pogo de electrodos (3 pines): 1 = ECGP (placa izquierda), 2 = VCM / referencia, 3 = ECGN (placa derecha).

## Señal

- 512 muestras/s, 18 bits, ganancia 40 V/V (orden `ganancia 20|40|80|160`), paso alto digital 0,5 Hz, paso bajo 40 Hz.
- Detección de electrodo despegado (DC lead-off 5 nA): esas muestras se envían como `0x800000` (no válidas).
- Reloj FCLK automático: si en 1,5 s no hay muestras, la cincha genera 32 768 Hz en GPIO4 y lo recuerda (NVS).
  Orden `fclk auto|modulo|generado` para forzarlo.
- Los picos R y la frecuencia cardiaca los calcula el motor AVO sobre el ECG crudo (resolución 2 ms).

## Formato por radio (sin cambios en espalda ni pecho)

Lote `IMU_SAMPLE` **fmt 2**, `imu_id` 3, byte de unidades (offset 15) = 2:
cabecera de 24 B + N × int24 LE en 0,1 µV. N = 51 por lote (~100 ms) → 177 B; máximo 60 → 204 B = límite de la espalda.
`girth_t0_us` = reloj de la cincha de la primera muestra; `period_us` = periodo redondeado (exacto: 1953,125 µs).
La espalda 3.14.x y el pecho 3.7.x reenvían y guardan formatos desconocidos tal cual, así que el ECG llega al `.avr`
sin firmware nuevo en ellos. **Pendiente:** que las apps (Android, Windows, iPad) y el motor decodifiquen fmt 2.

## Montaje en el caballo

LED con enlace: 1 destello = IMU + ECG correctos · **3 destellos rápidos = electrodos sin contacto** (mojar las placas
o poner gel, apretar la cincha). La orden `estado` muestra la amplitud pico a pico del último segundo: un ECG equino
bien colocado da ~1–3 mV.
