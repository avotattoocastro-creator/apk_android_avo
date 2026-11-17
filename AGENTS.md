# Instrucciones para asistentes (Claude, ChatGPT/Codex y otros)

Este repositorio se desarrolla con varios asistentes en conversaciones distintas. GitHub es la **única fuente
compartida**: lo que no esté en la rama no existe para el siguiente asistente. Responde y documenta en **español**.

## Reglas
1. Rama de integración: **`develop/avo-performance-horse`**. No trabajar sobre `main` ni sobre ramas históricas.
2. **Cada cambio se documenta en `docs/REGISTRO_DE_CAMBIOS.md`** (entrada arriba, con plantilla), en el mismo
   commit o en el siguiente. Incluir commits, ejecución de CI y nivel de validación.
3. Niveles de validación separados: IMPLEMENTADO · COMPILADO / CI (número de ejecución y SHA) · PROBADO FÍSICAMENTE
   (dispositivo, versión, evidencia). Sin prueba física: **NO VERIFICADO**. Ver `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`.
   «Compila en CI» o «pasa las pruebas simuladas» **nunca** se presenta como «funciona en el hardware».
4. Antes de empezar, leer este archivo, `README.md`, `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` y las últimas entradas de
   `docs/REGISTRO_DE_CAMBIOS.md`, y comprobar `git log` de la rama.
5. Al cambiar una versión, actualizar también la matriz de `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` y la tabla de `README.md`.
6. No guardar credenciales NTRIP, tokens, contraseñas ni claves privadas en el repositorio (ver «Secretos»).

## Ramas (desde la integración del 12/11/2026, PR #7–#17)
- **Una sola rama de integración:** `develop/avo-performance-horse`. Todo el código vigente está en ella.
- **Ramas cortas por tarea**, que salen de `develop` y vuelven a `develop` en días, no en semanas:
  `feat/<módulo>-<tema>`, `fix/<módulo>-<tema>`, `cad/<pieza>-<rev>`, `ci/<tema>` (o `claude/<tema>` para Claude).
  No abrir líneas paralelas de una misma app o firmware: una sola versión de Android, del pecho, de la espalda, etc.
- Se integra **siempre por PR** con *merge commit* (no *squash* ni *rebase*, para no perder historial) y con el CI
  en verde en `develop` antes de abrir el siguiente.
- **Prohibido borrar ramas antiguas** mientras no existan en GitHub las **53 etiquetas `backup/2026-11-12/<rama>`**
  (script `crear_tags_backup.sh`, en `docs/`). Comprobar con
  `git ls-remote --tags origin 'backup/2026-11-12/*' | grep -vc '\^{}'` → debe dar 53.
- Fuera de `develop` a propósito: `main` (histórica), `feature/avo-measurement-engine-v4`, `fix/chest-v373-readfile`,
  `fix/back-3-13-8-gps-uart` y las ramas de evidencias `ci/*` (las escriben los workflows; no se fusionan).

## Secretos (repositorio público)
- **Prohibido subir:** `*.jks`, `*.keystore`, `*.p12`, `*.pfx`, `*.p8`, `*.mobileprovision`, `*.pem` con clave
  privada, `google-services.json` con claves restringidas, ficheros `.env` y credenciales NTRIP (usuario, contraseña,
  caster de pago).
- La **clave privada ECDSA P-256 de licencias vive solo en AVO Tarjetas** (y en su copia completa cifrada fuera del
  móvil). **No** va en GitHub Secrets. En GitHub solo está la clave **pública**, en la variable
  `AVO_LICENSE_PUBLIC_KEYS`.
- Firma de APK (`AVO_UPDATER_KEYSTORE_*`, clave estable de la app) y App Store Connect (`ASC_*`, `APPLE_TEAM_ID`):
  solo como GitHub Secrets. No cambiarlos ni moverlos sin avisar al usuario.

## Hardware actual (no mezclar con prototipos en papel)
- **Pecho:** Waveshare ESP32-S3-Touch-AMOLED-2.06" (AXP2101, microSD SDMMC 1 bit). Los pads IO14/IO15 son el **bus
  I²C**: no son GPIO libres. Caja vigente REV D.
- **Espalda:** Heltec Wireless Stick Lite V3 + u-blox ZED-F9P (URTK1.2) + Pololu S7V8F3 (SHDN = GPIO34, VIN al 3V3 de
  la Heltec). UART del ZED: RX = GPIO35, TX = GPIO33. Firmware en `firmware/back/V3_8_0` (línea 3.13.x / 3.14.x).
  Carcasa V2.2H Rev E.5.
- **Cincha:** Seeed XIAO ESP32-C6 + BNO085 (I²C 0x4A) + pogo magnético de 3 pines. Cápsula REV 5.9.1 (REV 5.10 añade
  el ECG MAX30003).
- **Espalda V4 (`firmware/back/V4_0_0`, 4.0.0-dev2) y PCB de la cincha REV B (ESP32-C3):** diseñadas, **no fabricadas**.
  Nunca instalar la 4.0.0-dev en el hardware actual (no tiene batería, modo carga, calidad GNSS ni `GirthHub`).
  Antes de generar o pedir placas de la cincha, confirmar con el usuario la arquitectura: pogo + BNO085 + ECG
  (prototipo actual) o Qi + LSM6/MMC (PCB REV B).

## Contratos binarios (cambiar a la vez en firmware y en todas las apps)
`BackStatus` v3 (108 B) · lotes de la cincha por ESP-NOW (220 B) · `TELEMETRY` v3 por BLE (116 B) · USB `AVO1`
(bloques de 4 KB con CRC-32 y SHA-256) · RTCM3 con CRC-24Q · RAW `.avr` · configuración TLV `AVOC` · licencias
`.avolic`. **OTA firmada del pecho:** la versión instalada debe ser `X.Y.Z` sin sufijo (`-rc`, `-usb`…), o el reloj
rechaza el paquete.

## CI (GitHub Actions)
- Los workflows se disparan con **push a `develop`** filtrados por carpeta (`paths:`). No se ejecutan en los PR.
- **TestFlight** sale de `develop` (`build-avo-ipad.yml`), solo cuando cambian `ipad/**`, `equine-intelligence/**`, la
  biblioteca de protocolo `firmware/back/V3_8_0/lib/avo_core/**`, `windows/tools/demo-fixtures/**` o el propio
  workflow. También se puede lanzar a mano. El número de build lo pone el CI (`run_number`): no tocarlo.
- **Pecho 3.7.10** (`build-chest-v377-despertar.yml`): se compila en `develop` cuando cambian sus carpetas
  `firmware/chest/V3_7_*`.
- No modificar workflows, firmas, `Info.plist` ni el número de build de TestFlight sin avisar al usuario.

## Restricciones técnicas del reloj de pecho (CHEST, Waveshare ESP32-S3 AMOLED 2.06")
- **No usar LVGL**: satura la RAM interna y rompe BLE con el móvil y el enlace con la espalda. La pantalla usa
  Arduino_GFX + el renderizador propio de `firmware/chest/V3_7_2_UI` (framebuffer en PSRAM).
- No modificar comunicaciones (BLE, ESP-NOW, UART, NTRIP/RTCM, GNSS), OTA ni almacenamiento cuando la tarea sea de
  pantalla u otra cosa; si es imprescindible, justificarlo y documentarlo en el registro.
- Arduino_GFX define `BLACK`, `RED`, `GREEN`, `BLUE`, `YELLOW`, `WHITE`… como macros: no usar esos nombres para constantes.
- El panel va montado girado 180°: el giro se hace por software (`UI_ROTATE_180` en `ui.cpp`), no con `setRotation(2)`.
- Mostrar solo datos reales del estado del sistema; nunca valores de demostración de los diseños de referencia.

## Componentes
| Carpeta | Qué es | Workflow |
|---|---|---|
| `app/`, `core/` | App Android AVO Performance Horse (2.9-integrada) | `build-android.yml` |
| `cards/` | AVO Tarjetas (licencias NFC) | `build-android.yml` |
| `usb-updater/` | AVO Update: programa pecho, espalda y cincha por USB | `build-usb-updater.yml` |
| `avo-signer/` | Firma de paquetes OTA | `build-avo-signer.yml` |
| `equine-intelligence/` | Motor C++17 compartido (Equine, Training Analytics, Track Work) | `build-equine-engine.yml` |
| `windows/` | AVO Windows V2 PRO | `build-avo-windows.yml` |
| `ipad/` | App de iPad (SwiftUI) | `build-avo-ipad.yml` |
| `firebase/` | Reglas de Realtime Database (se publican a mano) | `firebase-rules.yml` |
| `firmware/chest/V3_*` | Firmware del reloj de pecho por versiones (ZIP base + parches) | `build-chest-v*.yml` |
| `firmware/back/V3_8_0` | Firmware de la espalda (Heltec), línea 3.14.x | `build-back-v380.yml` |
| `firmware/girth/` | Firmware de la cincha (C6; y C3 de la PCB) | `build-girth*.yml` |
| `firmware/back/V4_0_0`, `hardware/back/V4` | Espalda V4 (sin fabricar) | `build-back-v4-*.yml` |
| `hardware/` | CAD (FreeCAD 1.0.2) y PCB (KiCad 9) | varios |

## Estado actual
Versiones en `develop` y estado de verificación: `README.md`, `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` y la entrada
«Integración en develop» de `docs/REGISTRO_DE_CAMBIOS.md` (12/11/2026). El traspaso antiguo
`docs/TRASPASO_ASISTENTES_2026-10-23.md` se conserva como historia: sus versiones están superadas.
