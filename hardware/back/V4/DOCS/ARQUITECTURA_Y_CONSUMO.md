# AVO BACK V4 · arquitectura electrónica y consumo

## 1. ¿Uno o dos ESP32? (el brief pide documentarlo antes de cerrar la arquitectura)

| Criterio | 1 × ESP32-S3 (elegida) | ESP32-S3 + ESP32-C3/C6 |
|---|---|---|
| Funciones (BLE, Wi-Fi, ESP-NOW con pecho y cinchas, UART del ZED, microSD, PPS) | Todas en un chip. **La Heltec actual (un ESP32-S3) ya hace ESP-NOW con pecho y cincha, Wi-Fi y el UART del ZED** (BACK 3.8.0–3.11.0, probado en parte en campo) | Repartidas en dos chips |
| Radio | Una radio de 2,4 GHz: Wi-Fi, BLE y ESP-NOW coordinados por el árbitro de coexistencia del chip | **Dos radios en la misma banda a < 3 cm**, sin coordinación: cuando una emite, la otra queda cegada. No da más tiempo de aire, porque la banda es la misma |
| Consumo medio | ≈ 230 mA (ver §3) | ≈ 300 mA (+ ~75 mA de la segunda radio en recepción continua, necesaria para ESP-NOW) |
| Autonomía con la 654060 | ≈ 7,8 h | ≈ 6 h |
| Superficie de PCB | módulo 15,4 × 15,4 | + 13,2 × 16,6 (C3/C6-MINI) + desacoplos + enlace |
| Firmware | 1 imagen; el núcleo `avo_core` (37 pruebas) se reutiliza | 2 imágenes, 2 OTA, protocolo entre chips nuevo, sincronización del PPS entre chips |
| Fiabilidad | un watchdog; menos piezas y soldaduras | aislamiento de fallos entre radios, a cambio de más piezas y un enlace más que puede fallar |

**Decisión: un solo ESP32-S3** (ESP32-S3-MINI-1U-N8, LCSC C2980299, 2475 uds. el 29/10/2026). Cumple todas las funciones
con igual fiabilidad, consume menos, ocupa menos (que es lo que acorta la carcasa) y coincide con la respuesta del
usuario («ESP32-S3 propio + ZED módulo»).

### UART frente a SPI (enlace entre chips, si algún día se añade el segundo)
Se recomendaría **UART a 2–3 Mbaud con tramas COBS + CRC** (el mismo formato AVO UART v1 que ya usa el proyecto): es
asíncrono, no necesita que un lado sea esclavo con un pin de «datos listos», el ESP-IDF lo maneja por DMA y con RTS/CTS
no pierde bytes. SPI daría más caudal (10–40 MHz), pero exige el C3/C6 como esclavo con transacciones preparadas de
antemano y una línea de petición, y la telemetría (≈ 10–30 kB/s) no lo necesita. Con un solo chip la pregunta desaparece.

### Interfaz con el ZED-F9P
UART2 del ZED (la que usa hoy la espalda) a GPIO7/8; UART1 cableada a GPIO5/6 para el registro RAW a alta velocidad.
SPI del ZED no se usa: la URTK1.2 lo comparte con UART1 (pads RX/MOSI, TX/MISO) y 921 600 bps bastan para RAWX a 8 Hz
(≈ 25 kB/s).

## 2. Bloques de la placa (esquema: `PCB/out/AVO_BACK_V4_PCB_esquema.pdf`)
| Bloque | Pieza | Por qué |
|---|---|---|
| Carga Qi | BQ51013B + bobina 30 × 23 bajo la placa | igual que la cincha REV B (ya pasó ERC/DRC); sin módulo Qi suelto ni hilos |
| Cargador | BQ24072 (camino de potencia), 445 mA (ISET 2 k), entrada 760 mA (ILIM 2 k), NTC | termina bien la carga con la espalda encendida; USB-C también carga |
| Protección | PTC 1,5 A (SMD1206P150TF) + PMOS de polaridad (AO3401A) + el PCM de la celda + NTC y temporizador del cargador | |
| 3,3 V principal | TLV75733P (1 A) | picos de radio del S3 (355 mA a 20,5 dBm) + microSD |
| 3,3 V del ZED | RT9080 (600 mA) con **EN en GPIO10** | **corta físicamente el receptor y la antena** (0 V al dormir) y su arranque no hunde el 3,3 V del ESP32: es exactamente el fallo `rst:0x1 POWERON` de la BACK 3.10.4 |
| MCU | ESP32-S3-MINI-1U-N8 + antena FPC 2,4 GHz en el techo del cuello | antena a ~75 mm de la GNSS (como ahora) |
| microSD | Hirose DM3AT (C114218), SDMMC 4 bits, alimentación por PMOS (GPIO21) | la tarjeta se apaga al dormir |
| Soporte | Hall DRV5032FA (C140921) | sustituye al reed de vidrio: sin hilos, sin alojamiento en la base, la PCB baja 2 mm |
| ZED | 8 pads (J4) + resistencias serie | ver INTEGRACION_GNSS.md |

## 3. Consumo y autonomía (estimación; nada medido en la placa V4)
| Carga | Medio (mA) | Pico (mA) | Fuente |
|---|---|---|---|
| ESP32-S3, radio siempre escuchando (Wi-Fi sin ahorro, ESP-NOW) | 95 | — | hoja ESP32-S3-MINI: RX 802.11b/g/n HT20 95 mA |
| ESP32-S3, transmisión (8 Hz al pecho + cincha, potencia adaptativa) | 5 | 355 | ídem: TX 802.11b 20,5 dBm 355 mA |
| CPU 160 MHz, bucle GNSS/RTCM, tarea de la microSD | 10 | — | estimado |
| ZED-F9P siguiendo satélites (4 constelaciones) | 93 | 130 | tabla de SparkFun (tracking 93 mA, pico 130 mA) |
| Antena activa Q39 (LNA por el ZED) | 15 | 20 | estimado (sin dato del anuncio) |
| microSD escribiendo ≈ 25 kB/s a ráfagas | 8 | 100 | estimado |
| LEDs de la URTK1.2, cargador, Hall, divisor | 4 | — | estimado |
| **Total desde la batería** (reguladores lineales: corriente de batería ≈ corriente de carga) | **≈ 230** | **≈ 600** | |

- Batería 654060, 2000 mAh; útil ≈ 1800 mAh hasta 3,5 V (el TLV75733P aún da 3,3 V con 600 mA).
- **Autonomía ≈ 7,8 h** (6,5–9 h según antena y radio). Objetivo del brief: ≥ 4 h → **se cumple con la batería actual;
  no hace falta cambiarla.** Con dos ESP32 serían ≈ 6 h.
- Picos: 600 mA < 1 A del regulador principal, < 600 mA del RT9080 por separado (el ZED solo pide 130 mA), < 1,5 A del PTC.
- **Dormida** (fuera del soporte): ESP32-S3 en sueño profundo 8 µA + TLV75733P ≈ 25 µA + BQ24072 (batería) ≈ 6 µA +
  divisor 2 µA + Hall ≈ 2 µA → **≈ 45 µA**; ZED, antena y microSD a 0 V. Domina la autodescarga de la celda.
- Referencia actual (Heltec + ZED, BACK 3.10.2): 190–230 mA estimados, ~8 h. **La V4 consume lo mismo** (el ZED y la
  radio son el grueso); lo que mejora es el reposo: hoy el ZED se queda a ~70–85 mA si no se corta (3.10.6).

Fuentes: [hoja ESP32-S3-MINI (Arduino/Espressif)](https://docs.arduino.cc/resources/datasheets/esp32-s3-mini.pdf),
[SparkFun: ZED-F9P frente a ZED-X20P](https://learn.sparkfun.com/tutorials/whats-the-difference-between-the-zed-f9p-and-the-zed-x20p/comparison-of-features),
[TI DRV5032 (SLVSDC7H, tipo de salida)](https://www.ti.com/document-viewer/lit/html/SLVSDC7H/GUID-300338FB-1883-4EE2-AF63-124BA7856476).
