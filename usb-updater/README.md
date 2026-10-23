# AVO PERFORMANCE HORSE UPDATE

App Android **independiente** de AVO Performance Horse para instalar `firmware.bin` en el reloj de pecho
(Waveshare ESP32-S3 Touch AMOLED 2.06") por USB-C, sin ordenador.

- applicationId permanente: `org.avoperformance.horse.update`
- Versión actual: **1.8.0-beta1** (versionCode 10) — beta: falta la prueba física con el reloj.
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

## Qué hace (y qué no)

| Fase | Mecanismo |
|---|---|
| Comunicación | Protocolo serie del ROM de Espressif (SLIP, estado de 4 bytes), sin stub en RAM. |
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
