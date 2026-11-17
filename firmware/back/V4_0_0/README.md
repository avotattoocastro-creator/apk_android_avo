# AVO BACK 4.0.0-dev2 · firmware de la placa AVO BACK V4 REV B

Placa: `hardware/back/V4/PCB` (ESP32-S3-MINI-1U-N8 + URTK1.2/ZED-F9P). **NO VERIFICADO EN HARDWARE** (placa sin fabricar).

## Qué es
Port de **BACK 3.11.0** (Heltec Wireless Stick Lite V3) a la placa V4. El núcleo `lib/avo_core` es el mismo: enlace
ESP-NOW con el pecho (v1), emparejamiento, ZED/UBX a 8 Hz con 4 constelaciones y RTK fijo, RTCM sin duplicados,
calidad GNSS, concentrador de la cincha y potencia de radio adaptativa. El pecho y la cincha ven la espalda igual.

## Qué cambia respecto a la 3.11.0
| | 3.11.0 (Heltec) | 4.0.0-dev2 (placa V4 REV B) |
|---|---|---|
| ZED | UART en GPIO33/35 · regulador Pololu externo (SHDN GPIO6) | UART2 del ZED en GPIO7/8 · UART1 cableada a GPIO5/6 · **RT9080 en placa (EN GPIO10)** |
| Encendido | reed a GND en GPIO7 | **por hardware**: el soporte del chaleco puentea los contactos SYS–BAT; fuera del soporte no hay alimentación (0 µA) |
| Emparejar | botón PRG 3 s | **3 encendidos seguidos de < 4 s** (poner y quitar la cápsula 3 veces; contador en NVS), u orden `PAIR` por USB |
| Carga | botón 8 s o tensión subiendo | en la **base de carga** (cargador externo en BAT–GND, la placa está apagada); por USB-C en el taller (PGOOD/CHG del BQ24072 en el monitor) |
| Registro | — | **microSD**: flujo UBX completo en `/AVO_nnnnnn.ubx`, tarea propia, búfer de 32 KB, vaciado cada 1 s (corte sin aviso) |
| Tiempo | — | **PPS** en GPIO4 por interrupción (periodo y desviación en el monitor) |
| Batería | divisor ×4,9 con ADC_Ctrl | divisor 1:2 en GPIO2 |
| LoRa / Vext | dormir el SX1262, Vext | ya no existen |

## Órdenes por USB (115200)
`PAIR` (emparejamiento 120 s) · `DORMIR` (sueño profundo hasta el siguiente encendido) · `SD` · `ESTADO`.
Con el USB-C del taller la placa funciona igual que en el chaleco (no hay modo TALLER: no hay sensor que la duerma).

## Compilar
`./build_back_v4.sh` (arduino-cli, núcleo esp32 3.3.12, `esp32s3`, 8 MB, `default_8MB`, USB CDC al arrancar).
CI: `.github/workflows/build-back-v4-fw.yml` (pruebas en el ordenador + compilación + comprobación de la imagen); el
ZIP queda en `out/AVO_BACK_V4_FIRMWARE.zip` y la puerta de la PCB lo copia a `PCB/out/FINAL/`.

## Pruebas en el ordenador
`g++ -std=c++17 -Ilib/avo_core/src test/test_espnow.cpp test/test_v4.cpp lib/avo_core/src/*.cpp && ./a.out`
→ 44 casos (37 heredados + 7 de la placa V4: emparejamiento por encendidos, PPS, búfer de la microSD, batería, pines).

## Pendiente (no hecho en esta versión)
- RAWX/SFRBX por UART1 a 921600 para posproceso (hoy se graba todo lo que sale por UART2).
- BLE directo con Android (NTRIP sin pasar por el pecho), Wi-Fi para descargar la microSD y OTA firmada: el brief los
  pide para el ESP32 principal; la arquitectura (un ESP32-S3) los admite, pero el código no está escrito.
