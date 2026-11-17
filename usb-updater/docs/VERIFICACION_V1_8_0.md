# Informe de verificación — AVO PERFORMANCE HORSE UPDATE 1.8.0-beta1

Fecha: 2026-10-23. Distingue cuatro niveles: **compilación**, **pruebas automatizadas (simuladas)**,
**programación de flash con hardware** y **recuperación física**.

## 1. Compilación — HECHO (local)
- Todo el código Kotlin (incluida la parte Android) compila con Kotlin 2.0.21 contra la API Android 35.
- La compilación con Gradle/AGP y la APK se generan en GitHub Actions (el entorno de desarrollo no tiene acceso a Google Maven).

## 2. Pruebas automatizadas — 58/58 correctas (SIMULACIÓN)
Ejecutadas con JUnit 4.13.2. **Son resultados de simulación, no de hardware.**
Se comprobó además que las pruebas detectan fallos reales: con `FLASH_BEGIN` en formato ESP32 (4 palabras)
fallan 11 pruebas; si el planificador eligiera el slot activo fallan 8.

| Área | Pruebas |
|---|---|
| SLIP | codificación, decodificación, escapes, tramas fragmentadas byte a byte, ruido de arranque, resincronización tras escape corrupto |
| ROM | SYNC, READ_REG, GET_SECURITY_INFO (formato S3), códigos de error, respuestas perdidas con reintento, timeouts, ROM mudo |
| Flash | formato FLASH_BEGIN/DATA/MD5/SPI_ATTACH/SET_PARAMS, tamaños de bloque, alineación, secuencias, checksum, JEDEC → tamaño, lectura por SPI verificada con MD5 y repliegue a lecturas de 4 bytes |
| BIN | segmentos, checksum, SHA-256 adjunto, truncado, datos sobrantes, chip incorrecto, byte alterado |
| Particiones | tabla válida, MD5 correcto/incorrecto, solapes, tabla corrupta en el reloj |
| OTA | CRC32 con valores de referencia de ESP-IDF `otatool.py`, copia activa, cálculo de secuencia, escritura de la copia inactiva, interpretación tras arranque |
| Instalación completa (ESP32-S3 simulado) | actualización normal app0→app1 y app1→app0; recuperación con slot dañado y con otadata vacío; entrada automática en bootloader; desconexión a mitad (otadata intacto, reintento correcto); fallo de verificación (no se activa); firmware que no arranca (rollback detectado, no se da por completado); firmware sin confirmar; Secure Boot/Flash Encryption (sin ninguna escritura); firmware demasiado grande; BIN inválido; cancelación |

En cada instalación simulada se comprueba que **solo** se escriben el slot destino y un sector de otadata,
y que bootloader, tabla, NVS, blackbox y coredump quedan idénticos.

Constantes y formatos contrastados con el código fuente oficial de **esptool** (v4.8.1 y actual) y **ESP-IDF**
(`esp_flash_partitions.h`, `bootloader_common_loader.c`, `bootloader_utility.c`, `esp_ota_ops.c`).

## 3. Programación de flash con el reloj real — PENDIENTE
Ya demostrado antes: SYNC ROM y READ_REG desde Android. **No probado todavía** con el reloj:
1. *LEER RELOJ*: que muestre ESP32-S3, JEDEC, 16/32 MB, seguridad desactivada, tabla real y slot activo.
   Es solo lectura y es la primera prueba a realizar. Copiar el REGISTRO si falla.
2. Lectura de flash por registros SPI con bloques de 64 bytes (si el chip no lo admite, la app pasa sola a 4 bytes;
   en ambos casos el MD5 del chip valida los datos o la operación se detiene).
3. Reinicio a bootloader por DTR/RTS desde Android y nuevo permiso USB tras la re-enumeración.
4. Instalación de `firmware.bin` 3.7.1-rc2 (1.364.544 bytes): tiempo de borrado/escritura y verificación MD5.
5. Comprobación de arranque: que el firmware AVO confirme la imagen (rollback) o imprima su versión por USB.

## 4. Recuperación física — PENDIENTE
Con un slot dañado a propósito y entrada manual BOOT+RESET.

## Riesgos conocidos
- Si el bootloader del reloj tiene rollback activado y el firmware AVO no llama a
  `esp_ota_mark_app_valid_cancel_rollback()` (Arduino lo hace por defecto), el bootloader volverá a la versión
  anterior en el segundo reinicio. La app lo detecta y lo informa como «no confirmado».
- Android puede pedir permiso USB tras cada reinicio del reloj (el reloj re-enumera).
