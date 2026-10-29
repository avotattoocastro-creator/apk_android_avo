# AVO BACK 4.0.0-dev1 · firmware de la placa AVO BACK V4

Placa: `hardware/back/V4/PCB` (ESP32-S3-MINI-1U-N8 + URTK1.2/ZED-F9P). **NO VERIFICADO EN HARDWARE** (placa sin fabricar).

## Qué es
Port de **BACK 3.11.0** (Heltec Wireless Stick Lite V3) a la placa V4. El núcleo `lib/avo_core` es el mismo: enlace
ESP-NOW con el pecho (v1), emparejamiento, ZED/UBX a 8 Hz con 4 constelaciones y RTK fijo, RTCM sin duplicados,
calidad GNSS, concentrador de la cincha y potencia de radio adaptativa. El pecho y la cincha ven la espalda igual.

## Qué cambia respecto a la 3.11.0
| | 3.11.0 (Heltec) | 4.0.0-dev1 (placa V4) |
|---|---|---|
| ZED | UART en GPIO33/35 · regulador Pololu externo (SHDN GPIO6) | UART2 del ZED en GPIO7/8 · UART1 cableada a GPIO5/6 · **RT9080 en placa (EN GPIO10)** |
| Encendido | reed a GND en GPIO7 | **Hall DRV5032 en GPIO1** (misma regla: 3 s fuera del soporte → sueño profundo; despierta al volver) |
| Emparejar | botón PRG 3 s | **3 veces en el soporte en < 8 s**, u orden `PAIR` por USB |
| Modo carga | botón 8 s o tensión subiendo | **PGOOD del BQ24072** (alimentación externa real) |
| Registro | — | **microSD**: flujo UBX completo en `/AVO_nnnnnn.ubx`, tarea propia, búfer de 32 KB |
| Tiempo | — | **PPS** en GPIO4 por interrupción (periodo y desviación en el monitor) |
| Batería | divisor ×4,9 con ADC_Ctrl | divisor 1:2 en GPIO2 |
| LoRa / Vext | dormir el SX1262, Vext | ya no existen |

## Órdenes por USB (115200)
`PAIR` (emparejamiento 120 s) · `TALLER` (no se duerme) · `DORMIR` · `SD` · `ESTADO`.
Al arrancar fuera del soporte hay 3 s para escribir `TALLER`; con alimentación externa entra en modo carga.

## Compilar
`./build_back_v4.sh` (arduino-cli, núcleo esp32 3.3.12, `esp32s3`, 8 MB, `default_8MB`, USB CDC al arrancar).
CI: `.github/workflows/build-back-v4-fw.yml` (pruebas en el ordenador + compilación + comprobación de la imagen); el
ZIP queda en `out/AVO_BACK_V4_FIRMWARE.zip` y la puerta de la PCB lo copia a `PCB/out/FINAL/`.

## Pruebas en el ordenador
`g++ -std=c++17 -Ilib/avo_core/src test/test_espnow.cpp test/test_v4.cpp lib/avo_core/src/*.cpp && ./a.out`
→ 44 casos (37 heredados + 7 de la placa V4: gesto de emparejamiento, PPS, búfer de la microSD, batería, pines).

## Pendiente (no hecho en esta versión)
- RAWX/SFRBX por UART1 a 921600 para posproceso (hoy se graba todo lo que sale por UART2).
- BLE directo con Android (NTRIP sin pasar por el pecho), Wi-Fi para descargar la microSD y OTA firmada: el brief los
  pide para el ESP32 principal; la arquitectura (un ESP32-S3) los admite, pero el código no está escrito.
