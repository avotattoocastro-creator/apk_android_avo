# AVO CASCO BACK V5 — firmware 5.0.0 (pecho + espalda en un solo ESP32-S3)

**Estado:** IMPLEMENTADO · compilado en local (arduino-esp32 3.3.12, 1 391 296 B) · pruebas de ordenador correctas ·
CI: workflow `build-casco-v500-fw.yml` pendiente del permiso del usuario · **NO VERIFICADO en la placa** (las PCB del PROTOTIPO A están en fabricación, pedido
W2026112308485306).

## Qué es
El casco hace lo que hoy hacen el pecho (Waveshare) y la espalda (Heltec + ZED-F9P) juntos, con un solo ESP32-S3:

| Viene de | Qué hace en el casco | Cambios |
|---|---|---|
| **Pecho 3.7.11** (entero) | BLE con el móvil (TELEMETRY v3, 116 B), RTCM del NTRIP, grabación `.avr` en la microSD, USB AVO1 con el PC, Wi-Fi, OTA firmada, geocercas y sesiones, caja negra | Sin pantalla: anillo LED. Sin AXP2101: MAX17048 + BQ24072. Táctil en lugar de BOOT/PWR |
| **Espalda 3.15.0** (`BackCore` de `lib/avo_core`) | ZED-F9P a 8 Hz con 4 constelaciones y RTK fijo, calidad GNSS, BackStatus v4, `GirthHub` con las cinchas por ESP-NOW | Ninguno en el núcleo: solo una plataforma del casco (`src/casco_back.cpp`) |

**El enlace pecho ↔ espalda es interno:** las mismas tramas AVO UART v1 en paquetes ESP-NOW, pero en memoria
(`uart_link.cpp` → `casco_back::to_back` y `BackCore::radio_send` → `uartlink::loopback_rx`). La pareja es fija
(MAC virtuales, `pair_id` derivado de la MAC del chip). **Ningún contrato binario cambia:** el móvil, el PC y el iPad
ven un pecho con su espalda conectada. La radio ESP-NOW queda solo para las cinchas (canal 1, como la espalda).

## Cómo se monta (sin copiar el pecho)
1. `tools/prepare_chest_tree.py` ejecuta los pasos de `.github/workflows/build-chest-v377-despertar.yml` y monta el
   pecho 3.7.11 (falla si el pecho cambia de versión: hay que revisar el casco).
2. `tools/apply_v500.py` aplica el casco (cada cambio comprueba el texto original; si no está, falla):
   - `lib/avo_core`: ficheros de la espalda 3.15.0 (BackCore, ZED, GirthHub, calidad GNSS, RTCM 1005/1006) sobre los
     del pecho, salvo `avo_input` (triple toque) y `avo_ble_proto` (TELEMETRY v3), que son los del pecho. Comprueba que
     `avo_payloads`, `avo_espnow_link` y `avo_uart_proto` son idénticos en los dos (contratos).
   - `src`: `board_pins.h`, `hal_board.cpp`, `casco_back.*` y `ui.cpp` (anillo) del casco; se quitan la pantalla y el AXP2101.
   - Parches en `uart_link.cpp`, `controller.cpp`, `app_main.cpp`, `storage.cpp`, `ota.cpp`, `ble_service.cpp`, `usb_sync.cpp`.
3. `build_chest.sh` del pecho compila (misma placa: ESP32-S3, 16 MB, PSRAM octal, USB CDC).

## Hardware (GPIO de `hardware/back/V5_CASCO_PROTOTIPO/PCB/fuente/avo_back_v5_pcb.py`)
| Función | GPIO |
|---|---|
| PWR_HOLD (enclavamiento) | 46 — a 1 en `initVariant()` (antes de `setup`) y retenido |
| Táctil TTP223 (activo alto) | 11 — despierta del sueño profundo |
| VBUS_DET · CHG PGOOD · CHG STAT | 18 · 38 · 39 |
| I²C (MAX17048 0x36, LSM6DSV16X 0x6A) | SDA 42 · SCL 41 |
| microSD 4 bits · alimentación | CLK 12 · CMD 13 · D0–D3 14–17 · PWR_N 21 |
| ZED-F9P UART1 · PPS · RESET_N · EN | RX 5 · TX 6 · 7 · 9 (no se usa) · 10 |
| Anillo: DIN · EN del elevador | 47 · 48 |
| Batería (divisor 1:2, reserva) · Hall · IMU INT1 | 2 · 1 · 4 |

## IMU de la cabeza y PPS (incluidos desde 5.0.0)
- **IMU** LSM6DSV16X (0x6A): los mismos registros que la cincha REV D. 120 Hz, ±16 g, ±2000 dps, FIFO continua.
  Se envía en lotes `IMU_SAMPLE` **fmt 3**, `imu_id 4`, `girth_id 0xCA`, byte 15 = 3: 15 muestras de 12 B (ax ay az
  gx gy gz, int16 LE en LSB; 0,488 mg/LSB y 70 mdps/LSB). Va al `.avr` y al motor (≥ 2.0.0-dev30: `head_imu_batches`)
  por la misma cola que las cinchas, sin mezclarse con ellas.
- **PPS** (GPIO7): estado en BackStatus y en cada muestra GNSS. Además envía **TIME_SYNC** (µs del casco en el flanco
  e iTOW del segundo entero), que enlaza el reloj del casco con la hora GPS.
- Sin IMU o sin PPS, el casco funciona igual. El registro serie muestra «PPS ENGANCHADO / con pulsos / sin pulsos» e
  «IMU cabeza OK / sin IMU» cada 5 s.

## Uso
| Táctil | Acción |
|---|---|
| 1 toque | Autorizar el móvil que lo pide (anillo morado parpadeando) · confirmar la parada de una sesión · encender/apagar el anillo |
| 2 toques | Empezar una sesión manual · con una sesión en marcha: pedir confirmación para pararla (1 toque en 5 s la para) |
| 3 toques | Modo «conectar un móvil» (2 min) |
| Mantener 3 s | Apagar (el anillo se llena de blanco y luego se apaga en rojo) |

**Encender:** tocar (el TTP223 levanta el EN) o conectar el cable. Con el cable y sin tocar arranca en «solo carga»
(como el pecho 3.7.10): GPS apagado, anillo naranja con el %; al desconectar se apaga.

| Anillo (brillo máximo 30 %) | Significado |
|---|---|
| Rojo | Sin ZED (no responde o apagado) |
| Ámbar | ZED funcionando, sin fix |
| Amarillo | Fix 3D sin RTK |
| Cian | RTK float |
| Verde | **RTK FIX** |
| El color «respira» | Grabando |
| Un LED azul | Móvil conectado |
| Un LED rojo parpadeando | Batería baja |
| Morado girando / parpadeando | Conectar un móvil / el móvil espera confirmación |
| Azul girando | Actualización OTA |
| Naranja (tantos LED como %) / verde fijo | Cargando / cargado (modo solo carga) |

## Reglas de la revisión de la placa que cumple (comprobadas por `tests_test_casco_v500.py`)
1. PWR_HOLD a 1 lo primero y retenido. 2. TX hacia el ZED a 0 antes de bajar ZED_EN. 3. Líneas de la microSD en entrada
antes de cortarla. 4. Encendido escalonado (microSD → ZED a 1,5 s → anillo a 2,5 s); corte por batería del pecho
(3,45 V). 5. DIN del anillo a 0 apagado y brillo ≤ 30 %. 6. RESET_N del ZED nunca se mueve. 7. MAX17048 leído desde 3 s.

## Instalar (primera vez)
Placa fuera de la cápsula, USB-C J16, `esptool.py --chip esp32s3 write_flash 0x0 AVO_CASCO_V5_0_0_merged_0x0.bin`
(artefacto del CI). Después, OTA firmada con `target` `AVO_CASCO_V5_ESP32S3`: una OTA del pecho no entra en el casco ni
al revés (marca de imagen `AVOCASCO-IMG-V1:BACK-V5`). AVO Update todavía no conoce `AVO-CASCO`.

## Lo que falta o queda pendiente
- **Probarlo en la placa** (pruebas M1–M10 de la revisión y la de recepción): encendido y enclavamiento en reinicios y
  OTA, táctil, anillo, microSD a 4 bits, MAX17048, carga, ZED por la URTK1.2, RTK FIX, cinchas.
- IMU de la cabeza: se registra (120 Hz, fmt 3) pero ninguna app la muestra todavía; despertar por movimiento y detección
  de caídas, sin hacer.
- PPS: falta comprobar en la placa la polaridad y el ancho del pulso del ZED (TP1 por defecto) y el emparejamiento con el NAV-PVT.
- AVO Update y las apps: reconocer «AVO-CASCO» (el USB AVO1 sigue diciendo `"name":"AVO-CHEST"` y añade
  `"model":"CASCO-V5"`, para no romper las apps).
- Potencia de radio adaptativa de la espalda (`avo_tx_power`): no se aplica; la radio solo habla con las cinchas.
