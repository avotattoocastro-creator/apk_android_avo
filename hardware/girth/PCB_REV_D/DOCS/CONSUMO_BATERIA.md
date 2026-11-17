# Cincha REV D · balance de consumo y batería (15/11/2026)

**Estimación de cálculo, no medida.** Sale de las hojas de datos y del comportamiento del firmware 0.5.0 (radio siempre
encendida, `WIFI_PS_NONE`, 21 dBm, ESP-NOW a 1 Mbps). Se confirma con la medida descrita al final.

## Consumo por bloque
| Bloque | Base de cálculo | mA medios |
|---|---|---|
| ESP32-C6 escuchando (radio siempre encendida) | RX 802.11 HT20: 78 mA (hoja del C6-MINI-1U) + CPU activa ≈ 10 mA | ≈ 88 |
| Envío de 3 lotes cada 100 ms (IMU fmt 0 + fmt 1 + ECG fmt 2: 220 + 180 + 193 B) | TX 802.11b a 20,5 dBm: 382 mA; a 1 Mbps ocupan ≈ 6,7 % del tiempo | ≈ 20 |
| LSM6DSV16X (acelerómetro + giróscopo + fusión) | 0,65 mA en alto rendimiento | 0,65 |
| MMC5983MA (100 Hz) | ≤ 0,45 mA | 0,45 |
| ADS1292R (ECG + RLD) | ≈ 0,7 mW a 3 V | ≈ 0,3 |
| Reguladores, divisor, LED, cargador | | ≈ 0,5 |
| **Total** | | **≈ 110 mA** |

Con el ESP-NOW a **6 Mbps** (solo cambia el firmware de la cincha; la espalda recibe a cualquier velocidad) el envío
baja al ≈ 1 % del tiempo y el total a **≈ 93 mA**. Entre la cincha y la espalda hay ≈ 1 m: el alcance sobra.

## Autonomía (90 % de la capacidad útil hasta 3,5 V; «envejecida» = 80 % tras unos 300 ciclos)
| Batería | 1 Mbps nueva | 1 Mbps envejecida | 6 Mbps nueva | 6 Mbps envejecida |
|---|---|---|---|---|
| 500 mAh (LP403048, 4,3 × 30,5 × 50,8) | 4,1 h | 3,3 h | 4,8 h | 3,9 h |
| **1000 mAh (603450, ≈ 6,0 × 34 × 50)** | **8,2 h** | **6,5 h** | **9,7 h** | **7,7 h** |

## Decisión
**Sí: subir a 1000 mAh.** Con 500 mAh la cincha no aguanta una mañana de entrenamientos (varios caballos) y, con la batería
envejecida, se queda en ~3,5 h. Con 1000 mAh llega a una jornada (~8 h, como la espalda del casco) y sigue por encima de
6,5 h cuando la celda envejece. La cápsula REV 6 crece ≈ 1,7 mm de alto y ≈ 3,5 mm de ancho (la PCB de 40 × 26 cabe
encima de la celda de 34 × 50).

Cambios en la PCB REV D por la celda de 1000 mAh:
- Carga: R6 = 2 kΩ → **≈ 445 mA** (0,45 C; carga completa en ≈ 2,5 h).
- Entrada: R7 = 2,2 kΩ → **≈ 690 mA** (carga + consumo de la placa). La base de carga debe dar **≥ 1 A a 5 V**.

## Cómo medirlo con el prototipo
1. Batería cargada, cincha enlazada con la espalda y enviando (ECG con electrodos o en abierto, IMU en marcha).
2. Orden `estado` por USB cada 10 min (o la batería de la cincha en la app): tensión de la celda.
3. Medir hasta 3,5 V. Autonomía real = minutos; consumo medio ≈ capacidad × 0,9 / horas.
4. Repetir con `phy 6m` (firmware 0.6.0) para comprobar el ahorro del envío a 6 Mbps.
