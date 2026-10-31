# Estado del desarrollo unificado — 22/10/2026

**Rama:** `develop/avo-performance-horse`  
**Repositorio:** `avotattoocastro-creator/apk_android_avo`

## Matriz de versiones

| Módulo | Versión fuente | Listo para probar | Validación pendiente |
|---|---|---|---|
| Android | **V2.0 / versionCode 12** | APK debug CI [39998714393](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39998714393) | Prueba en teléfono y reloj |
| Mareas | V2.0 | IHM oficial, coeficiente, sol/luna, Open-Meteo | Comparar con Tu Marea / tabla del puerto en el móvil |
| Contexto marítimo de sesiones | V1.9 | Entidad y captura para sesiones recientes | Prueba real y sincronización servidor |
| CHEST | V3.5.6 | Fuentes base y parches disponibles | Hardware, persistencia, firma |
| CHEST OTA firmado | V3.5.7 propuesto | **No** | Receptor ES256, OTA_AUTH, anti-rollback, recuperación |
| AVO Signer | V0.1 | Código y vector de firma | Respaldo/recuperación de clave y pruebas Android reales |
| ESPALDA | BACK 3.13.11 apagado del GPS con USB (rama `fix/back-3-13-11-usb-pololu-off`); 3.13.10 diagnóstico USB (rama `fix/back-3-13-10-usb-umbral`); 3.13.9 (rama `fix/back-3-13-9-usb-gps-off`) | **Parcial** (usuario: GNSS recuperado con 3.13.8 a 460800) | Apagado del GPS por USB: falta señal física en GPIO20 y medir VOUT |
| CINCHA | Sin versión integrada | **No** | Importar fuentes y validar tres IMU |
| CHEST pantalla (23/10/2026) | V3.7.2-rc1 | Binario de CI [39965639870](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39965639870) | Orientación, legibilidad, memoria y estabilidad BLE/espalda en el reloj |
| Programador USB (23/10/2026) | 1.8.0-beta2 / versionCode 11 | APK debug de CI [39963751136](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39963751136) | «LEER RELOJ», instalación y recuperación con el reloj real |

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
7. **Registrar cada cambio en `docs/REGISTRO_DE_CAMBIOS.md`** (añadido el 23/10/2026 a petición del usuario para centralizar el trabajo de Claude y ChatGPT en GitHub). Reglas para asistentes en `AGENTS.md`.

## Evidencias verificables y niveles de validación (22/10/2026)

**Definiciones obligatorias para README, versiones y entregas:**

- **IMPLEMENTADO:** existen fuentes o cambios en el repositorio. No implica que compile ni que funcione en un dispositivo.
- **COMPILADO / CI:** GitHub Actions ha terminado correctamente para un SHA concreto. Una ejecución de otra rama no valida la rama actual.
- **PROBADO FÍSICAMENTE:** hay una prueba documentada con dispositivo real, versión, resultado y evidencia. Sin ella, consignar **NO VERIFICADO**.

| Subsistema | Implementado en rama unificada | Compilado / CI | Probado físicamente |
| --- | --- | --- | --- |
| Android V1.9 | Sí | **Sí, solo SHA previo a fusión `3b05022b`** (run `39749862683`); **sin CI confirmada de rama unificada** | **No verificado** con APK integrada |
| Pantalla mareas y Open-Meteo | Sí | Incluido en compilación Android previa | **No verificado** en móvil; tabla oficial y exactitud pendientes |
| Instantáneas marítimas de entrenos | Sí | Incluido en compilación Android previa | **No verificado** con entrenamiento real |
| Verificador de ZIP firmado ES256 Android | Sí | Incluido en compilación Android previa | **No verificado** en dispositivo ni integrado en OTA segura de extremo a extremo |
| Firmware CHEST V3.5.4–V3.5.6 | Fuentes y parches integrados | **No consta CI de la rama unificada** | **No verificado** para esta integración; no confundir con pruebas de versiones históricas |
| CHEST V3.5.7 y `OTA_AUTH` | **No** | **No** | **No** |
| AVO Signer V0.1 | Sí | CI de rama Signer previa a fusión; no de rama unificada | **No verificado** en teléfono para flujo completo y restauración de clave |
| ESPALDA y CINCHA | **No integrados** | **No** | **No** |
| CHEST V3.7.2-rc1 (pantalla sin LVGL, carga, apagado por fases) | Sí (`firmware/chest/V3_7_2_UI`) | **Sí**, SHA `3e85c41`, run `39965639870` | **Parcial (23/10/2026, fotos):** orientación, legibilidad, BLE, espalda, GPS y SD correctos con `3e85c41`; correcciones de brillo, transición y esquinas pendientes de ver en el reloj |
| Programador USB 1.8.0-beta2 | Sí (`usb-updater/`) | **Sí**, SHA `f60c125`, run `39963751136` (59 pruebas en simulación) | **No verificado** |

**Fuente de evidencia CI Android previa:** [run 39749862683](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39749862683). **Integraciones:** [PR #4](https://github.com/avotattoocastro-creator/apk_android_avo/pull/4) y [PR #5](https://github.com/avotattoocastro-creator/apk_android_avo/pull/5). La rama actual incorpora además cambios de documentación; no atribuirle el CI de la rama original.

**Política de publicación:** ningún README debe usar «definitiva», «probada» o «OTA segura» solo por existir código o por una compilación correcta. Una APK debug es un artefacto de pruebas, no una release firmada de producción. Registrar SHA exacto y evidencias antes de cambiar cualquiera de estas celdas.

## Ensayo físico comunicado — CHEST V3.5.7 (22/10/2026)

**Dispositivo observado:** AVO_1E8C (Waveshare CHEST). El usuario realizó apagado mediante pulsación POWER prolongada y encendido mediante POWER durante aproximadamente 3 segundos. La aplicación Android volvió a conectar/autorizó por BLE y mostró **firmware 3.5.7**, batería **80 %** y **microSD montada**. Se dispone de fotografía de la pantalla aportada en la conversación.

**Resultado comprobado:** persistencia de la versión anunciada **3.5.7** tras **un ciclo de apagado y encendido**, y reconexión BLE con lectura de información. No se ha comprobado la partición de arranque internamente ni repetido múltiples ciclos.

**No comprobado:** rechazo de OTA sin firma, `OTA_AUTH` positivo/negativo, firma manipulada, anti-rollback, recuperación ante interrupción, instalación firmada posterior, enlace espalda o cincha. La fotografía indica **espalda sin enlace** y **cincha sin datos**. No declarar el flujo OTA firmado validado.

**Android OTA:** `OTA_AUTH (0x54)`, preservación de bytes firmados y envío de autorización antes de `OTA_BEGIN` implementados en commits `006a1935`, `8c4e467c`, `41445e7d` y `38f51fc7`; CI Android del último commit [39761875218](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39761875218) finalizó correctamente. **Sin ensayo físico de OTA_AUTH.** La instalación sigue bloqueada por `safeInstallationAvailable=false` hasta prueba de seguridad.
