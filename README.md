# AVO Performance Horse — Android V1.0

Repositorio Android de AVO Performance Horse, conectado a GitHub Actions.

## Acceso
La cuenta `avotattoocastro-creator` tiene permisos de administrador y escritura. Se verificaron con commits reales el 19/10/2026.

## Subir la aplicación Android V1.0 (un solo archivo)

1. Descarga el archivo **AVO_ANDROID_V1_0_FUENTES_PARA_GITHUB.zip**, preparado a partir del proyecto Android aportado por el propietario.
2. Abre **Add file > Upload files** en https://github.com/avotattoocastro-creator/apk_android_avo
3. Arrastra el ZIP **sin descomprimir** hasta la raíz de la rama `main` y confirma **Commit changes**.
4. En https://github.com/avotattoocastro-creator/apk_android_avo/actions abre **Build AVO Android APK**.
5. El workflow se inicia automáticamente por la subida del ZIP; también permite **Run workflow**.
6. Si la compilación termina correctamente, descarga el artefacto **AVO-Performance-Horse-V1-0-APK**. Contendrá la APK de pruebas y su SHA-256.

El workflow extrae el proyecto del ZIP, instala Android SDK 35 y Java 17, ejecuta los tests de `:core`, compila con `./gradlew :app:assembleDebug` y publica el artefacto. Si los tests fallan se registrará el resultado y se intentará generar la APK igualmente para facilitar diagnóstico.

También es compatible con fuentes Android descomprimidas en la raíz (`app/`, `core/`, `gradlew`, `gradle/`), que tienen prioridad respecto al ZIP.

## Estado de las pruebas

El ZIP de origen incluye pruebas previas del módulo `:core` y una comprobación de tipos de la interfaz, pero no se ha demostrado todavía una compilación de Android con SDK real ni una prueba con teléfono/reloj reales. La ejecución de GitHub Actions será la primera verificación de compilación Android de esta entrega.

## Seguridad

**Este repositorio es público.** No subir claves NTRIP privadas, contraseñas, credenciales de API, tokens de servidor, datos reales de usuarios ni claves de firma. La APK será **debug**, no firmada para distribución en Play Store. Los parámetros sensibles deben suministrarse mediante ajustes seguros de la app o secretos de Actions para futuras builds de release.

## Hardware previsto

- Pecho: reloj Waveshare ESP32-S3 Touch AMOLED 2.06 con microSD.
- Espalda: Heltec Wireless Stick Lite V3 con ZED-F9P; RTCM por UART desde el pecho.
- Cincha: ESP32 con tres IMU; ESP-NOW directo con espalda.
- Teléfono Android: BLE permanente con pecho, NTRIP, geocercas, sesiones y sincronización.
