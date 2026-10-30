# Traspaso para asistentes (Claude / ChatGPT) — estado al 23-10-2026

Rama de trabajo: **`develop/avo-performance-horse`** (no usar `main`). Registro completo de cambios:
`docs/REGISTRO_DE_CAMBIOS.md`. Normas comunes: `AGENTS.md`.

## Código fuente actual (carpetas del repositorio = fuente de verdad; los zip son copias)

| Componente | Versión | Carpeta | Copia zip (raíz) | CI |
|---|---|---|---|---|
| App Android AVO Performance Horse | **2.0** (versionCode 12) | `app/`, `core/` | `AVO_ANDROID_V2_0_REDISENO_MAREAS_ANALISIS_FUENTES.zip` | `build-android.yml` · run 39998714393 ✔ |
| App AVO Update (programador/lector USB) | **2.1.0** (versionCode 22) | `usb-updater/` | `AVO_UPDATER_V2_1_0_FUENTES.zip` | `build-usb-updater.yml` · run 40015367842 ✔ |
| Firmware espalda (Heltec Wireless Stick Lite V3 + ZED-F9P) | **3.8.0** | `firmware/back/V3_8_0/` | `AVO_BACK_V3_8_0_FUENTES.zip` | `build-back-v380.yml` · run 40015971416 ✔ |
| Firmware pecho (Waveshare ESP32-S3 AMOLED 2.06) | 3.7.2-rc1 (pantalla) | `firmware/chest/V3_7_2_UI/` (+ base `V3_7_0_RC2` zip) | — | `build-chest-v372-ui.yml` |

## Arquitectura de comunicaciones (no cambiar sin acuerdo)
Móvil (NTRIP) → **BLE** → pecho → **ESP-NOW** (enlace v1, emparejamiento, tramas AVO UART v1) → espalda → **UART** → ZED-F9P.
La espalda devuelve NAV-PVT como `GNSS_SAMPLE`, `STATUS`, `CAPS`, `ACK`. Definición: `lib/avo_core/src/avo_espnow_link.h`,
`avo_uart_proto.h`, `avo_payloads.h`. **La espalda 3.8.0 no cambia el protocolo.**

## Espalda 3.8.0 (resumen)
- Partió de **AVO BACK 3.5.0** (instalado; copia leída con AVO Update, MAC AC:A7:04:06:CD:24; fuente en `firmware/chest/V3_5_4` zip).
- ZED-F9P a **8 Hz con GPS+GLO+GAL+BDS** (límite RTK del data sheet), 10 Hz sin BDS, 12 Hz GPS+GAL; RTK fijo,
  modelo Airborne <2g, máscara 10°, perfil en VALSET separado con degradación segura; Wi-Fi sin ahorro y a potencia
  máxima; marcador `AVO-BACK 3.8.0`. Pruebas en ordenador: `test/test_espnow.cpp` (23 casos, ZED simulado).
- Instalar: AVO Update 2.1.0 → `AVO_BACK_V3_8_0_firmware.bin` (NO el `_COMPLETO_0x0.bin`, que es para esptool desde 0x0).
- **No verificado en hardware.** Comprobar en el monitor serie: `ritmo=8 Hz`, `perfil=COMPLETO`.

## AVO Update 2.1.0 (resumen)
- Instala en pecho (USB-Serial/JTAG) y espalda (CP2102); bloquea firmware cruzado (marcadores AVO-CHEST / AVO-BACK).
- Lectura solo-lectura: información, leer firmware, leer partición, copia completa (stub oficial esp-flasher-stub
  Apache/MIT en `assets/stub/`; CP2102 a 460800 con 2 bloques en vuelo y reintentos). Probado parcialmente con la espalda real.

## App Android 2.0 (resumen)
Rediseño con colores AVO, mareas oficiales IHM estilo Tu Marea Pro, análisis de entrenamientos (Resumen / Mapa y
gráficas / Datos), foto de caballo (Room 3→4), OTA retirada. Pantalla de arranque sin tocar. **No verificada en móvil.**

## Reglas acordadas con el usuario
- No usar LVGL en el pecho. No modificar comunicaciones/NTRIP del pecho sin petición expresa.
- Nunca guardar credenciales NTRIP, tokens ni claves privadas en el repositorio.
- Documentar cada cambio en `docs/REGISTRO_DE_CAMBIOS.md` y distinguir IMPLEMENTADO / CI / PROBADO FÍSICAMENTE.
