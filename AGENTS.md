# Instrucciones para asistentes (Claude, ChatGPT/Codex y otros)

Este repositorio se desarrolla con varios asistentes en conversaciones distintas. GitHub es la **única fuente
compartida**: lo que no esté en la rama no existe para el siguiente asistente. Responde y documenta en **español**.

## Empieza aquí (todas las conversaciones)
1. Trabaja desde **`develop/avo-performance-horse`** actualizada (`git pull`); nunca desde `main` ni ramas viejas.
2. Lee **`docs/ESTADO_DESARROLLO_Y_VERSIONES.md`** (tabla única de lo vigente) y las últimas entradas de
   `docs/REGISTRO_DE_CAMBIOS.md`.
3. Haz el cambio en una rama corta (`claude/<tema>`), con PR a `develop` y *merge commit*.
4. Al terminar: entrada en el registro **y** fila actualizada en la tabla del estado. Si no está en GitHub, no existe.
5. Descargas de lo último publicado: release `descargas` (ver «Descargas directas»).

## Nombres: PROTOTIPO y BETA (decisión del usuario, 17/11/2026)
- **PROTOTIPO** = todo lo que funciona sobre **placas de desarrollo, sin PCB propia** (Waveshare del pecho, Heltec de la
  espalda, XIAO de la cincha), y sus cajas, carcasas y firmware.
- **BETA** = todo lo que lleva **PCB propia** (cincha PCB REV D, casco BACK V5, DOCK V1, espalda V4), y sus cajas,
  carcasas y firmware.
- Los nombres nuevos de archivos, artefactos, descargas y documentos llevan `PROTOTIPO` o `BETA`
  (p. ej. `AVO_CINCHA_BETA_FW.zip`, `CAD_PECHO_PROTOTIPO_REV_D.zip`). Las apps no llevan etiqueta.
- **Pruebas de campo (decisión del usuario, 17/11/2026):** hasta que estén construidas **todas** las PCB del sistema,
  las pruebas de campo que corroboran el funcionamiento se hacen **solo con PROTOTIPOS**. Lo validado ahí se porta
  después a las BETA. Con todas las PCB construidas empiezan las pruebas de campo con las BETA. Por eso una función
  nueva se valida primero en el firmware PROTOTIPO, y el firmware BETA la recibe ya probada (mismos contratos binarios).
- Las carpetas y workflows existentes **no se renombran** de golpe (romperían rutas de CI, enlaces e historial): la
  etiqueta se aplica en documentación y descargas, y en cada carpeta nueva.

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
- **Etiquetas de respaldo creadas (17/11/2026):** 52 `backup/2026-11-12/*` y 108 `backup/2026-11-17/*` (una por
  rama). Las ramas respaldadas se borran con `docs/borrar_ramas_2026-11-17.sh` (desde un ordenador: las sesiones de
  Claude en la nube no pueden borrar ramas, crear etiquetas ni cambiar ajustes del repositorio). Antes de borrar una
  rama creada después del 17/11, crear su etiqueta.
- Rama por defecto del repositorio: debe ser `develop/avo-performance-horse` (se cambia en GitHub → Settings).
- Fuera de `develop` a propósito: `main` (archivo completo: PR #62, con `archivo/binarios/`) y las ramas de evidencias
  `ci/*` (las escriben los workflows; no se fusionan). Archivadas (solo en su etiqueta): `feature/avo-measurement-engine-v4`,
  `fix/chest-v373-readfile`, `fix/back-3-13-8-gps-uart`, `feature/girth-pcb-rev-c`, `cad/girth-rev5-11-cierre-magnetico`.

## Secretos (repositorio público)
- **Prohibido subir:** `*.jks`, `*.keystore`, `*.p12`, `*.pfx`, `*.p8`, `*.mobileprovision`, `*.pem` con clave
  privada, `google-services.json` con claves restringidas, ficheros `.env` y credenciales NTRIP (usuario, contraseña,
  caster de pago).
- La **clave privada ECDSA P-256 de licencias vive solo en AVO Tarjetas** (y en su copia completa cifrada fuera del
  móvil). **No** va en GitHub Secrets. En GitHub solo está la clave **pública**, en la variable
  `AVO_LICENSE_PUBLIC_KEYS`.
- Firma de APK (`AVO_UPDATER_KEYSTORE_*`, clave estable de la app) y App Store Connect (`ASC_*`, `APPLE_TEAM_ID`):
  solo como GitHub Secrets. No cambiarlos ni moverlos sin avisar al usuario.

## Hardware (no mezclar líneas)
### PROTOTIPO (placas de desarrollo; es lo que existe y se prueba hoy)
- **Pecho PROTOTIPO:** Waveshare ESP32-S3-Touch-AMOLED-2.06" (AXP2101, microSD SDMMC 1 bit). Los pads IO14/IO15 son el
  **bus I²C**: no son GPIO libres. Caja REV D. Firmware 3.7.x.
- **Espalda PROTOTIPO:** Heltec Wireless Stick Lite V3 + u-blox ZED-F9P (URTK1.2) + Pololu S7V8F3 (SHDN = GPIO34, VIN
  al 3V3 de la Heltec). UART del ZED: RX = GPIO35, TX = GPIO33. Firmware `firmware/back/V3_8_0` (3.13.x / 3.14.x).
  Carcasa V2.2H Rev E.5.
- **Cincha PROTOTIPO:** Seeed XIAO ESP32-C6 + BNO085 (I²C 0x4A) + pogo magnético de 3 pines. Cápsula REV 5.9.1
  (REV 5.10 añade el ECG MAX30003). Firmware 0.4.x (IMU) y 0.5.x (IMU + ECG).

### BETA (PCB propia; diseñada, **no fabricada** salvo que el registro diga lo contrario)
- **Cincha BETA:** PCB REV D (ESP32-C6-MINI-1U + LSM6DSV16X + MMC5983MA + ADS1292), arquitectura confirmada por el
  usuario el 15/11/2026. Cápsula REV 6.4 con funda y cierre de balancín (`hardware/girth/CINCHA_MONTAJE`). Firmware 0.6.x.
- **Casco BETA (BACK V5):** PCB + CAD en `hardware/back/V5_CASCO`. Sin firmware todavía.
- **DOCK BETA V1** (soporte de pared cargador): PCB REV A + caja en `hardware/dock/V1`. Sin firmware todavía.
- **Espalda BETA V4** (`firmware/back/V4_0_0`, 4.0.0-dev2; `hardware/back/V4`). **Nunca** instalar la 4.0.0-dev en la
  Heltec (no tiene batería, modo carga, calidad GNSS ni `GirthHub`).
- Las PCB REV B (ESP32-C3) y REV C de la cincha quedan como historia. Antes de pedir placas, confirmar con el usuario.

## Contratos binarios (cambiar a la vez en firmware y en todas las apps)
`BackStatus` v3 (108 B) · lotes de la cincha por ESP-NOW (220 B) · `TELEMETRY` v3 por BLE (116 B) · USB `AVO1`
(bloques de 4 KB con CRC-32 y SHA-256) · RTCM3 con CRC-24Q · RAW `.avr` · configuración TLV `AVOC` · licencias
`.avolic`. **OTA firmada del pecho:** la versión instalada debe ser `X.Y.Z` sin sufijo (`-rc`, `-usb`…), o el reloj
rechaza el paquete.

## Descargas directas
Release fija `descargas`: `https://github.com/avotattoocastro-creator/apk_android_avo/releases/download/descargas/<ARCHIVO>`.
La publica `publicar-descargas.yml` en cada push a `develop`; qué entra y con qué nombre, en
`scripts/descargas/descargas.json`. Explicación: `docs/DESCARGAS_DIRECTAS.md`.

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
| `firmware/back/V4_0_0`, `hardware/back/V4` | Espalda BETA V4 (sin fabricar) | `build-back-v4-*.yml` |
| `hardware/` | CAD (FreeCAD 1.0.2) y PCB (KiCad 9) | varios |

## Estado actual
**Fuente única:** la tabla «Vigente» al principio de `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`. Quien cambie una versión
la actualiza en el mismo PR. El traspaso antiguo `docs/TRASPASO_ASISTENTES_2026-10-23.md` es historia.
