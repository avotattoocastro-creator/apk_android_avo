# Estado del desarrollo unificado — 22/10/2026

**Rama:** `develop/avo-performance-horse`  
**Repositorio:** `avotattoocastro-creator/apk_android_avo`

## Matriz de versiones

| Módulo | Versión fuente | Listo para probar | Validación pendiente |
|---|---|---|---|
| Android | V1.9 / versionCode 11 | APK debug de la rama Android original compilada | CI post-fusión, teléfono y reloj |
| Mareas | V1.9 | UI y consulta de modelo | Parser oficial, datos actuales y comparación visual |
| Contexto marítimo de sesiones | V1.9 | Entidad y captura para sesiones recientes | Prueba real y sincronización servidor |
| CHEST | V3.5.6 | Fuentes base y parches disponibles | Hardware, persistencia, firma |
| CHEST OTA firmado | V3.5.7 propuesto | **No** | Receptor ES256, OTA_AUTH, anti-rollback, recuperación |
| AVO Signer | V0.1 | Código y vector de firma | Respaldo/recuperación de clave y pruebas Android reales |
| ESPALDA | Sin versión integrada | **No** | Importar fuentes y validar GNSS/ESP-NOW |
| CINCHA | Sin versión integrada | **No** | Importar fuentes y validar tres IMU |

## OTA: contrato que falta implementar en receptor

El paquete firmado consta de `firmware.bin`, `manifest.json` y `manifest.sig`. El algoritmo es ES256 (SHA256withECDSA, firma DER), con `schema=avo-ota-manifest-v1`, `target=AVO_CHEST_WAVESHARE_ESP32S3` y clave pública previamente fijada. El reloj **debe** comprobar la firma sobre los bytes originales del manifiesto, SHA-256 y tamaño del firmware, hardware de destino, versión/anti-rollback y persistencia tras reinicio antes de permitir una actualización. Un hash por sí solo no autentica al fabricante. No utilizar la verificación del móvil como sustituto de la del reloj.

**Estado de seguridad:** la transferencia OTA en la app permanece deshabilitada hasta demostrar estas condiciones en hardware. La compilación correcta de Android no certifica la OTA firmada.

## Reglas de desarrollo entre conversaciones

1. Utilizar siempre `develop/avo-performance-horse` como rama de integración.
2. Trabajar con cambios pequeños, indicando SHA, módulo y pruebas realizadas.
3. Mantener las versiones del firmware y de Android **independientes**: Android 1.9 no implica CHEST 3.5.7.
4. No mezclar en una sola afirmación código incorporado, CI correcto y validación física: son estados distintos.
5. Conservar las ramas históricas como respaldo hasta validar una versión conjunta.
6. Actualizar README y este documento al introducir una nueva versión o cambiar el contrato OTA.
