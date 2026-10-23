# AVO PERFORMANCE HORSE UPDATE

App Android **independiente** de AVO Performance Horse. Rama `feature/avo-usb-updater`.

## Identidad y actualizaciones
- applicationId permanente: `org.avoperformance.horse.update`.
- `versionCode` estrictamente creciente.
- Para actualizar sin desinstalar, **todas** las APK instaladas en el teléfono deben firmarse con la **misma clave**. Una APK debug de CI no es intercambiable con una APK release firmada con otra clave.
- CI de producción debe utilizar un keystore persistente protegido como secreto. Nunca generar una clave nueva por compilación ni subirla al repositorio.
- Android no instala automáticamente APK sin consentimiento del usuario; futura actualización in-app descargará APK firmada y abrirá el instalador del sistema.

## V1.0
Detección USB Host / VID / PID / interfaces / permisos. **No flashea** ni modifica memoria del reloj.
Pendiente: identificación real del puerto USB Waveshare, modo ROM download, protocolo ESP32-S3, esquema de particiones y backup seguro. Nunca escribir firmware.bin en dirección supuesta.
