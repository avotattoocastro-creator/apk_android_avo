# AVO Performance Horse — Android V1.8 (desarrollo)

Aplicación Android para el reloj de pecho Waveshare ESP32-S3 y el chaleco AVO.

## Rama activa de desarrollo

- **Código Kotlin editable** en `app/` y `core/` de `feature/android-v1-4-ota-pecho`.
- **Rama `main`**: versión anterior V1.3; no es la versión más reciente de Android.
- Los ZIP V1.0–V1.8 permanecen únicamente como copias históricas; se compila el código editable de la raíz del proyecto.
- El fichero de GitHub Actions es `.github/workflows/build-android.yml`.

## Funciones incorporadas

- Enlace BLE permanente al reloj, reconexión tras apagar y encender Bluetooth, transferencia RTCM/NTRIP.
- Inicio/parada de grabación, geocercas, sesiones de microSD y sincronización.
- Análisis GNSS con resumen, reproducción, gráficos sincronizados, selección por punto, zoom y pan.
- Recorrido sobre mapa real OpenStreetMap con colores por velocidad y RTK; plano local sin conexión como alternativa.
- Nueva selección Calles/Satélite con teselas Esri World Imagery, atribución de fuentes visible y conservación del punto elegido y zoom al cambiar la base; disponibilidad sujeta a condiciones del proveedor.
- Importación y exportación de entrenamientos `.avo` por el menú Compartir (WhatsApp compatible): ID de sesión, metadatos de caballo y jinete y resolución de duplicados.
- Favoritos de destinatarios y copia portátil de configuración, excluyendo contraseñas NTRIP y claves de autorización BLE.
- No molestar automático opcional: permiso especial Android, solo grabación confirmada por geocerca, sin afectar sesiones manuales, recuperación al finalizar o perder BLE; Android 15 usa una regla propia.

## Compilar y probar

GitHub Actions ejecuta:
1. `./gradlew --no-daemon :core:test`
2. `./gradlew --no-daemon :app:testDebugUnitTest --tests 'org.avoperformance.horse.dnd.GeofenceDndGateTest'`
3. `./gradlew --no-daemon :app:assembleDebug`

Tras éxito se entrega el artefacto **AVO-Performance-Horse-V1-8-Integrada-APK** (APK debug y SHA-256).

[Compilaciones de GitHub Actions](https://github.com/avotattoocastro-creator/apk_android_avo/actions)

## Lo que todavía no se debe dar por validado

La compilación automatizada **no equivale** a prueba integral en un teléfono Android y hardware AVO reales. Faltan verificaciones BLE/NTRIP con el reloj, detección de sesión y geocerca, permiso DND por modelo de Android, importación WhatsApp y mapa sin/con conexión.

La capa de servidor en `AppContainer` sigue siendo `NotConfiguredServer`: no se han inventado endpoints para la subida automática. Hace falta integrar el contrato HTTP real antes de dar por completada esa función.

## Seguridad

Este repositorio es público. No incorporar credenciales NTRIP, secretos del servidor, tokens de acceso, claves de firma ni datos reales de usuarios. El artefacto generado es **debug**, no una publicación firmada de producción.
