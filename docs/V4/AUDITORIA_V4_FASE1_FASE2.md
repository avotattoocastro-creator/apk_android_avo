# Auditoría técnica V4 — Fases 1 y 2 (Measurement Engine)

**Rama:** `feature/avo-measurement-engine-v4` (desde `develop` `18a9823`) · **Fecha:** 23-10-2026 · **Autor:** Claude
**Código auditado:** espalda 3.8.0 (`firmware/back/V3_8_0`, `avo_core` compartido con el pecho 3.7.0-rc2), AVO Update 2.1.0, app Android 2.0.
**Trabajo nuevo:** `firmware/back/V4_0_0_DEV` (4.0.0-dev1). **La 3.8.0 estable no se ha modificado** (idéntica a `develop`).

Clasificación: **DEMOSTRADO** (reproducido con una prueba que fallaba) · **RIESGO** (posible, no reproducido) · **MEJORA**.

## 1. Inventario de hardware y capacidades

| Elemento | Verificado | Fuente | Pendiente físico |
|---|---|---|---|
| Espalda: Heltec Wireless Stick Lite V3, ESP32-S3 v0.2, flash GD 8 MB, MAC AC:A7:04:06:CD:24 | **Sí** | Lectura con AVO Update 2.0.1 (23-10-2026) | — |
| Espalda: firmware instalado AVO BACK 3.5.0 (Arduino 3.3.12, IDF 5.5.5), particiones app0/app1 3264 KB, spiffs, coredump | **Sí** | Copia del firmware | — |
| ZED-F9P por UART (GPIO33 RX / GPIO35 TX), puerto del ZED detectado en marcha | Código | `AVO_BACK_*.ino` | Versión de firmware del ZED (HPG), puerto real, baudios |
| PPS del ZED cableado a la espalda | **No** (código: «PPS not wired») | `avo_back_core.cpp` | Confirmar; sin PPS no se declara sincronía PPS |
| Pecho: Waveshare ESP32-S3 AMOLED 2.06, BLE + ESP-NOW + SD | Sí (pruebas del usuario con 3.7.2-rc1) | Registro | — |
| **Cincha: ESP32 + 3 IMU** | **NO** | No hay firmware de cincha en el repositorio; modelos de IMU y rangos desconocidos | Modelo de ESP32, modelo y rango de cada IMU, frecuencia, alimentación |

## 2. Hallazgos

| # | Tipo | Gravedad | Zona | Evidencia | Impacto | Solución (estado) |
|---|---|---|---|---|---|---|
| 1 | **DEMOSTRADO** | Alta | Historial de comandos (`BackCore`) | `done_cmd_[done_n_ % 8]` con `done_n_` limitado a 8: a partir del 9.º comando siempre se sobrescribe la posición 0. Prueba `audit.duplicate_command_after_eight_others_is_not_executed_twice` fallaba (el comando 700 repetido volvió a poner el ZED a 12 Hz) | Un comando repetido por el pecho (ACK perdido) se ejecuta dos veces; la respuesta a un duplicado era siempre «OK» aunque el original fallara | `CmdHistory` de 16 entradas en anillo con resultado guardado; duplicado → mismo resultado, sin ejecutar; historial borrado si el pecho reinicia. **Corregido** en 4.0.0-dev1 |
| 2 | **DEMOSTRADO** (diseño) | Media | Envío ESP-NOW | `radio_send()` esperaba el callback hasta 25 ms (3.8.0) u 80 ms (3.5.0) por intento, 3 intentos, dentro del callback de NAV-PVT | Hasta 75–240 ms de bloqueo del bucle con mala radio: retrasa RTCM al ZED y lectura UART | Envío asíncrono: `radio_start()` + `on_sent()`; colas alta (posiciones, ACK, emparejamiento) y normal (estado, latido, CAPS) de 12 paquetes, descarte del más antiguo por clase, contadores y latencia máxima. **Corregido** en 4.0.0-dev1 |
| 3 | RIESGO (no reproducido) | Baja | `UartDecoder::feed()` | Con búfer = 2 × trama máxima, un búfer lleno siempre contiene una trama completa o descartable: `process()` siempre avanza. Fuzzing (300 000 entradas, ASan/UBSan) sin fallos | Ninguno observado | Guarda defensiva: si no hubiera sitio, descarta 1 byte y cuenta `stalls` (debe ser 0). Prueba con entradas malformadas y 100 000 bytes de sincronía. **Hecho** |
| 4 | MEJORA | Media | Configuración del ZED | Solo se comprobaba el ACK del VALSET, no lo que el receptor aplica | Un ajuste aceptado pero no aplicado pasaría inadvertido | Lectura de vuelta con **UBX-CFG-VALGET** (ritmo, NAV-PVT, modelo, RTK, constelaciones, máscara): `verify_state` OK / DESAJUSTE / sin respuesta; ritmo leído y ritmo medido. **Hecho** (simulado; falta receptor real) |
| 5 | MEJORA | Media | Cambio de constelaciones | 3.8.0 cambia constelaciones si el pecho pide otro ritmo, aunque haya una sesión activa | Pérdida de FIX ~10–30 s tras el cambio | **Pendiente (fase 4):** política «no cambiar constelaciones con sesión activa» — requiere que la espalda conozca el estado de sesión (dato del pecho) |
| 6 | RIESGO | Alta para el objetivo V4 | Cincha / IMU | No hay firmware de cincha; la espalda 3.5/3.8 no recibe ESP-NOW de la cincha; `CadenceEstimator` de Android usa lotes IMU que hoy no existen en la cadena Heltec | Sin IMU no hay Motion Engine ni análisis biomecánico real | **Bloqueado por hardware:** inventario físico de la cincha (§1). Se puede diseñar la interfaz abstracta y el protocolo versionado sin inventar sensores |
| 7 | RIESGO | Media | Sincronización temporal | Las muestras GNSS llevan `itow` del receptor (bueno) y `back_rx_ms`; sin PPS ni protocolo con la cincha | No se puede alinear IMU-GNSS con error conocido | Fase 6 (TimeSync): protocolo de intercambio de marcas de tiempo espalda↔cincha con estimación de desfase/deriva; requiere la cincha |
| 8 | MEJORA | Baja | Decodificadores ESP-NOW / payloads / UBX | Revisados `now_parse`, `now_pair_decode`, `decode_*`, `UbxStream`: comprueban longitudes; fuzzing sin fallos | — | Fuzzer integrado en CI (1 000 000 entradas con ASan/UBSan) |
| 9 | RIESGO | Baja | Persistencia | Única escritura en NVS de la espalda: el registro de emparejamiento (al emparejar). No hay escrituras periódicas en flash | — | Correcto; mantener |
| 10 | MEJORA | Baja | Herramientas | libFuzzer (`-fsanitize=fuzzer`) no disponible en este entorno; se usa un motor de mutación propio con semilla fija | — | Añadir libFuzzer en CI con clang cuando esté disponible |

## 3. Pruebas (ordenador, simuladas — NO son validación física)

- `firmware/back/V4_0_0_DEV/test/test_espnow.cpp`: **29 casos, 191 comprobaciones, 0 fallos**, con AddressSanitizer + UndefinedBehaviorSanitizer.
- Barrido de pérdidas (modelo de radio, no radio real), 60 s a 8 Hz tras el arranque:

| Pérdida radio | Posiciones entregadas | RTCM al ZED | Latencia GNSS máx. (modelo) | Descartes por congestión |
|---|---|---|---|---|
| 0 % | 100 % | íntegro, sin duplicados ni desorden | 0 ms | 0 |
| 5 % | 100 % | íntegro | 2 ms | 0 |
| 15 % | 99,8 % | íntegro | 3 ms | 0 |
| 30 % | 97,7 % | íntegro | 3 ms | 0 |

- `test/fuzz_decoders.cpp`: 300 000 entradas en local (1 000 000 en CI) sin fallos con ASan/UBSan.

## 4. Estado de fases

| Fase | Estado |
|---|---|
| 1 Auditoría | Hecha (este documento) |
| 2 Correcciones críticas | Hechas: #1, #2, #3, #4 |
| 3 Adquisición no bloqueante | Ruta de envío hecha; la recepción ya era por cola |
| 4 GNSS Engine | Parcial: perfiles 8/10/12 Hz (3.8.0), VALGET. Pendiente: perfiles con nombre, diagnóstico RTK (tiempo a FIX, % FIX/FLOAT, pérdidas), política de sesión activa |
| 5 Motion Engine · 6 TimeSync · 7 Radio con cincha | **Bloqueadas por el inventario físico de la cincha** (§1) |
| 8 Data Integrity · 9 Analysis | Fase 9 se desarrolla como «Equine Intelligence Engine» en su propia rama |
| 10 Android/Windows · 11 Pruebas · 12 Entrega | Pendiente |

## 5. Lo que hay que comprobar físicamente
1. Instalar 4.0.0-dev1 **solo para pruebas** (la 3.8.0 sigue disponible) y revisar en el monitor serie: `VERIFICACION (VALGET): OK`,
   `COLAS: ... descartadas alta/normal=0/0 sin_callback=0`, `latencia_GNSS_max` real.
2. Inventario de la cincha: placa ESP32, IMU (modelo, rango, frecuencia), firmware actual, alimentación.
3. Si el ZED tiene PPS disponible, ¿hay un pin libre de la Heltec para cablearlo?
