# AVO PERFORMANCE HORSE UPDATE

App Android **independiente** de AVO Performance Horse para instalar `firmware.bin` en el reloj de pecho
(Waveshare ESP32-S3 Touch AMOLED 2.06") por USB-C, sin ordenador, y para **leer y copiar** cualquier módulo AVO
ESP32-S3: pecho (USB nativo) y espalda Heltec Wireless Stick Lite V3 (puente CP2102).

- applicationId permanente: `org.avoperformance.horse.update`
- Versión actual: **2.0.1** (versionCode 21) — falta la prueba física (pecho y espalda).
- Rama: `develop/avo-performance-horse` · CI: `.github/workflows/build-usb-updater.yml`

## Manual breve

1. **Conectar.** Cable USB-C *de datos* (u OTG) entre el teléfono y el reloj. La app muestra
   «USB: conectado (VID 303A · PID 1001)».
2. **Seleccionar el firmware.** *SELECCIONAR FIRMWARE BIN* → elige el `firmware.bin` de aplicación
   (no un archivo combinado con bootloader). La app muestra nombre, tamaño, versión, SHA-256 y si es válido.
3. **Leer el reloj.** *LEER RELOJ*. Con la casilla «Entrar en modo bootloader automáticamente» marcada,
   la app reinicia el reloj en modo bootloader por USB, lee chip, flash, seguridad, particiones y otadata,
   y lo devuelve a su firmware. Acepta el permiso USB cuando Android lo pida (puede pedirlo otra vez tras cada
   reinicio del reloj; marca «usar de forma predeterminada» para evitarlo).
   - **Modo bootloader manual** (si el automático falla o el firmware está dañado): desmarca la casilla,
     mantén **BOOT**, pulsa y suelta **RESET**, suelta **BOOT**, y pulsa *LEER RELOJ*.
4. **Instalar.** El botón *INSTALAR FIRMWARE POR USB* solo se activa si todas las comprobaciones son correctas.
   Confirma el diálogo, no desconectes el reloj. Pasos: preparando conexión → leyendo dispositivo →
   comprobando particiones → validando → borrando destino → escribiendo (%) → verificando → activando →
   reiniciando → comprobando arranque.
5. **Resultado.** «Instalación completada» solo aparece si el arranque se confirma (otadata en estado VALID
   o el firmware anuncia su versión por USB). Si no, la app dice exactamente qué no se pudo confirmar.

## Lectura y copia de seguridad (V2.0) — solo lectura

| Botón | Qué hace |
|---|---|
| Información del dispositivo | Chip, revisión, **MAC**, flash (JEDEC y tamaño), seguridad, tabla de particiones, otadata y, por cada partición de aplicación, proyecto, versión, fecha de compilación, ESP-IDF y SHA-256 del ELF. |
| Leer firmware (.bin) | Lee la aplicación que arranca, la recorta al tamaño real de la imagen, calcula su SHA-256 y extrae los **textos identificativos** (nombre del sketch `.ino`, versiones, fechas `__DATE__`, AVO, ZED/UBX/RTCM, ESP-NOW…). Se guarda como `.bin` que se puede volver a instalar. |
| Leer partición… | Cualquier partición de la tabla (nvs, spiffs, coredump…). |
| Copia completa de la flash | Los 8 MB (espalda) o 16 MB (pecho) desde 0x0, en un único `.bin`. |
| Guardar informe (.txt) | Informe y registro para compararlos o pasarlos a los asistentes. |

- Conexión: USB-Serial/JTAG del ESP32-S3, **Silicon Labs CP210x** (VID 10C4) y CDC (CH9102/CH343). Reinicio en modo
  descarga por DTR/RTS (`ClassicReset` de esptool en puentes USB-UART). Manual en la Heltec: mantener **PRG**, pulsar y soltar **RST**, soltar PRG.
- Velocidad: carga en RAM el **stub oficial de Espressif** (esp-flasher-stub v1.4.1, Apache-2.0 o MIT, `assets/stub/`,
  idéntico al que incluye esptool) y sube a 460 800 baudios en puentes USB-UART, con 2 bloques en vuelo y reintento automático (8 MB en unos 4–5 min).
- Verificación: cada bloque de 256 KB se comprueba con el **MD5 que calcula el chip**; si no coincide no se guarda nada.
- Nunca escribe ni borra: el CI comprueba que el código de lectura no usa comandos de escritura y que la carga en RAM solo existe en `StubFlasher.kt`.
- Al terminar, el módulo se reinicia con su propio firmware.

## Qué hace (y qué no)

| Fase | Mecanismo |
|---|---|
| Comunicación | Protocolo serie del ROM de Espressif (SLIP, estado de 4 bytes). La instalación no usa stub; la lectura rápida sí (ver arriba). |
| Lectura de flash | Registros SPI1 «user command» (método de esptool para `flash_id`), **cada lectura comprobada con el MD5 que calcula el propio chip**. |
| Particiones | Tabla real en `0x8000`, con su registro MD5; nada de tablas históricas. |
| Slot activo | `otadata` real, reglas de `bootloader_common_get_active_otadata` de ESP-IDF. |
| Escritura | `FLASH_BEGIN` (5 palabras, formato S3) borra solo los sectores de la imagen; bloques de 1 KB con checksum y reintento. |
| Verificación | MD5 del chip sobre lo grabado + lectura de cabecera + huellas MD5 de bootloader, tabla, NVS, otadata, blackbox, coredump y el otro slot antes y después. |
| Activación | Reescribe **una** copia de `otadata` como `esp_ota_set_boot_partition()` (seq + CRC32, estado NEW → rollback del bootloader si el firmware no confirma). |
| Arranque | Reinicio por DTR/RTS (USB-Serial-JTAG), vigilancia de reinicios, relectura de otadata tras el primer arranque. |

**Actualización normal**: el slot seleccionado tiene imagen válida → se escribe el otro; el anterior queda como respaldo.
**Recuperación USB**: el slot seleccionado está dañado pero el ROM responde → se reescribe ese slot.

Bloqueos (sin intentar eludirlos): Secure Boot, Flash Encryption, Secure Download, bootloader de 2.ª etapa
inválido, tabla corrupta, firmware que no cabe, revisión de chip o tamaño de flash incompatibles.
Si el bootloader de 2.ª etapa o la tabla de particiones están dañados, hace falta programación completa desde ordenador.

## Firma de la APK

Para actualizar sin desinstalar, todas las APK deben firmarse con la misma clave. La APK de CI es *debug*.
Para producción: keystore persistente como secreto (`AVO_UPDATER_KEYSTORE_*`), nunca en el repositorio.

Detalle de pruebas: [`docs/VERIFICACION_V1_8_0.md`](docs/VERIFICACION_V1_8_0.md).
