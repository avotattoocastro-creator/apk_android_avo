# AVO Performance Horse — desarrollo unificado (22/10/2026)

Repositorio conjunto para la aplicación Android, el firmware de pecho y la herramienta de firma OTA.

## Rama activa

**`develop/avo-performance-horse`** es la rama de integración compartida entre los chats de Android y firmware. La rama `main` y las ramas históricas no representan el estado más reciente. No modificar una rama histórica esperando que sus cambios aparezcan automáticamente en la rama unificada.

## Versiones de los componentes

| Componente | Versión en código | Estado comprobado |
| --- | --- | --- |
| App Android AVO Performance Horse | **1.9** (`versionCode=11`) | Compilación y pruebas CI correctas para el commit Android `3b05022b`; falta prueba integral en móvil |
| Módulo de mareas | Incluido en Android 1.9 | Interfaz, modelo Open-Meteo y lector de tabla de Santander en código; extracción de datos oficiales actuales no validada |
| Metadatos marítimos de entrenamientos | Android 1.9 | Persistencia y enriquecimiento de sesiones recientes incorporados; falta ensayo con sesión real |
| Firmware CHEST Waveshare ESP32-S3 | **V3.5.6** (última fuente/parche integrada) | Fuentes V3.5.4 y parches V3.5.5/V3.5.6 disponibles; no se afirma prueba de firma en hardware |
| Firmware CHEST V3.5.7 | **No integrado ni validado** | Pendiente de firmware receptor con validación ES256, control de versión y recuperación |
| AVO Signer Android | **V0.1 prototipo** | Código y vectores de prueba ES256 integrados; no es firma de producción |
| Verificador de paquetes OTA Android | Formato `avo-ota-manifest-v1`, ES256 | Código integrado, clave pública fijada; no equivale a autorización del reloj |
| Firmware espalda y cincha | No integrados en esta rama | Pendientes de importar desde fuentes verificadas |
| Firmware CHEST pantalla **V3.7.2-rc1** (23/10/2026) | Siete franjas legibles sin LVGL, pantallas de carga y apagado | CI correcto [39965639870](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39965639870); **no verificado en el reloj** |
| Programador USB **1.8.0-beta2** (`usb-updater/`) | Instalación de `firmware.bin` por USB-C desde Android | CI correcto [39963751136](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39963751136); **no verificado con el reloj** |

## Documentación compartida (Claude y ChatGPT)

- [`AGENTS.md`](AGENTS.md): reglas para cualquier asistente (rama, documentación, restricciones del reloj como **no usar LVGL**).
- [`docs/REGISTRO_DE_CAMBIOS.md`](docs/REGISTRO_DE_CAMBIOS.md): **registro de todos los cambios**, con commits, CI y nivel de validación. Obligatorio en cada cambio.
- [`docs/ESTADO_DESARROLLO_Y_VERSIONES.md`](docs/ESTADO_DESARROLLO_Y_VERSIONES.md): matriz de versiones y niveles de validación.

## Estructura

- `app/`: aplicación Android Kotlin/Jetpack Compose, BLE, GNSS, entrenamientos y mareas.
- `core/`: protocolo compartido y pruebas JVM.
- `firmware/chest/V3_5_4/`: ZIP de fuentes del firmware base.
- `firmware/chest/V3_5_5/` y `V3_5_6/`: scripts de parche sucesivos.
- `firmware/chest/V3_7_2_UI/`: nueva pantalla del reloj (renderizador propio, sin LVGL) y parche mínimo de fases de apagado.
- `usb-updater/`: app Android independiente para programar el reloj por USB (ROM del ESP32-S3).
- `avo-signer/`: aplicación independiente para firmar paquetes OTA y documentación de seguridad.
- `docs/`: requisitos y estado de validación.
- `.github/workflows/`: compilaciones Android, CHEST y Signer.

## Compilación

La app Android usa `./gradlew --no-daemon :core:test :app:assembleDebug`. El flujo de CI Android incluye pruebas adicionales; los artefactos de GitHub Actions son APK de **depuración**, no publicaciones de producción. El último CI Android confirmado antes de fusionar las ramas es el del commit `3b05022b`; **la rama unificada necesita una ejecución de integración propia**.

[Acciones de GitHub](https://github.com/avotattoocastro-creator/apk_android_avo/actions)

## Seguridad OTA: límite actual

La verificación de firma en Android no sustituye la verificación en el dispositivo. **No desbloquear la instalación OTA firmada** hasta demostrar en el reloj la autenticación del manifiesto, integridad del BIN, coincidencia del hardware, anti-rollback, selección de partición y persistencia tras apagado/reinicio. El gestor Android mantiene `safeInstallationAvailable=false`. La herramienta Signer no debe incorporar claves privadas al repositorio.

## Funciones Android existentes

BLE/NTRIP, RTK/GNSS, sesiones SD, geocercas, visualización de entrenamientos, mapas, importación/exportación .avo, selección caballo/jinete, favoritos, DND y módulo de mareas. La presencia de código no implica que todas las funciones hayan pasado pruebas reales. La subida automática al servidor sigue requiriendo verificar el contrato HTTP configurado; no afirmar sincronización real si el servidor está `NotConfiguredServer`.

## Próximos criterios de aceptación

1. CI de integración de la rama unificada sin fallos.
2. Validación de tabla oficial de mareas con datos actuales y origen visible; no confundir referencia Santander con medición en El Regatón.
3. Prueba Android ↔ reloj físico: BLE, NTRIP, SD, entrenamiento, geocerca y reinicio.
4. Firmware V3.5.7 con verificación de firmas en el receptor, pruebas de rechazo y recuperación.
5. APK de distribución firmada con clave de publicación controlada, distinta de la APK debug.

No almacenar credenciales NTRIP, secretos de servidor, tokens ni claves privadas en GitHub.
