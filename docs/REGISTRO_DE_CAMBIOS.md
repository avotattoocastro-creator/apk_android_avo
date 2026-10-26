# Registro de cambios — AVO Performance Horse

Registro **único y compartido** entre todos los asistentes (Claude, ChatGPT/Codex) y personas que trabajen en el
proyecto. Rama de integración: **`develop/avo-performance-horse`**.

## Cómo añadir una entrada (obligatorio en cada cambio)

- Añadir la entrada **arriba** (orden cronológico inverso), en el **mismo commit** que el cambio o en el siguiente.
- Usar los niveles de `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`: **IMPLEMENTADO**, **COMPILADO / CI** (con número de
  ejecución y SHA) y **PROBADO FÍSICAMENTE** (con dispositivo, versión y evidencia). Si no hay prueba física, escribir
  **NO VERIFICADO**.
- No borrar ni reescribir entradas de otros autores; si algo era incorrecto, añadir una entrada nueva que lo corrija.

```
## AAAA-MM-DD — Módulo vX.Y.Z — título corto
**Autor:** Claude | ChatGPT | persona · **Commits:** `abc1234`, … · **CI:** run NNNN (éxito/fallo)
**Qué cambia:** …
**Por qué:** …
**Archivos:** …
**No se ha tocado:** … (si aplica)
**Validación:** IMPLEMENTADO / CI / PROBADO FÍSICAMENTE / NO VERIFICADO
**Pendiente:** …
```

---

## 2026-10-24 — Android 2.1-motor — inicio automático en segundo plano
**Autor:** Claude · Rama `feature/avo-equine-intelligence-engine`
**Qué cambia:** el servicio de enlace (BLE con el chaleco, NTRIP, descarga automática) arranca sin abrir la app: al encender el móvil,
al actualizar la app, al activar Bluetooth, cuando el reloj autorizado se enlaza (ACL_CONNECTED), al abrir la app y en la comprobación
periódica de WorkManager. Ajuste «Iniciar automáticamente sin abrir la app» (activado por defecto) y botón para quitar la optimización de
batería (necesario para que Android permita iniciar el servicio en segundo plano). «Desconectar» pausa el inicio automático hasta «Conectar».
**Archivos:** `service/AutoStartReceiver.kt`, `service/AvoLinkService.kt`, `data/Settings.kt`, `SettingsScreens.kt`, `MainActivity.kt`, `WatchSyncManager.kt`, `AndroidManifest.xml`.
**Validación:** CI. **NO VERIFICADO** en el teléfono (depende del fabricante: en Xiaomi hay que activar también «Inicio automático»).

## 2026-10-24 — Android 2.1-motor — modo descarga automático
**Autor:** Claude · Rama `feature/avo-equine-intelligence-engine`
**Qué cambia:** al empezar una descarga del reloj la app entra sola en «modo descarga»: deja de enviar correcciones NTRIP por BLE
(la conexión con el caster sigue abierta y las correcciones acumuladas se descartan por obsoletas), mantiene la pantalla encendida en
Historial y muestra «Modo descarga · NTRIP en pausa». Al terminar o fallar se restablece todo automáticamente.
**No se ha tocado:** firmware, protocolo, ni el comportamiento de NTRIP fuera de la descarga (las descargas no se hacen durante una grabación).
**Validación:** CI. **NO VERIFICADO** con el reloj.

## 2026-10-24 — Android 2.1-motor — descarga robusta ante «Sin respuesta del reloj (READ_FILE)»
**Autor:** Claude · Rama `feature/avo-equine-intelligence-engine`
**Qué cambia:** la descarga ya no se interrumpe al primer READ_FILE sin respuesta (un fragmento BLE perdido anula toda la respuesta):
reintenta el mismo bloque hasta 8 veces con pausas crecientes (1–8 s), espera a la reconexión automática si se cae el enlace, pide 2048 B
(el máximo que el reloj responde por READ_FILE); también reintenta los errores de escritura GATT (p. ej. «Escritura BLE fallida (estado 133)»,
visto en S1E8C_000008_001 a 22 kB) en la escritura y en el bloque; y, si al final falla, el mensaje indica kB, intentos, timeouts, fragmentos perdidos y errores CRC.
**No se ha tocado:** firmware ni protocolo BLE/NTRIP (solo la política de reintentos de la app).
**Validación:** CI. **NO VERIFICADO** con el reloj (caso del usuario: sesión S1E8C_000035_001 parada en 288 kB de 724,9 kB).

## 2026-10-24 — Equine Intelligence Engine 1.1.0-dev1 + integración Android y Windows (rama `feature/avo-equine-intelligence-engine`)
**Autor:** Claude · **Commits:** `657c0eb` … (ver `git log`) · **CI de `74ce82b`:** motor [40041495035](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40041495035) (Linux ASan/UBSan 61 casos / 938 comprobaciones, MSVC, NDK ×3, JNI en JVM, fixtures) · Android [40041494960](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40041494960) (APK con el motor para 3 ABI + pruebas instrumentadas en emulador) · Windows [40041494972](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40041494972) (28 autopruebas, incluido el motor por P/Invoke) — **todo en verde**. Repetida con `788de5a`: motor [40042126332](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40042126332), Android [40042126221](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40042126221) (core 49 pruebas incl. `EquineResultTest`; emulador 2 pruebas RAW→JNI→motor→Kotlin, 0 fallos), Windows [40042126383](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40042126383) (28 autopruebas). ZIP: `AVO_EQUINE_INTELLIGENCE_ENGINE_V1_1_0_DEV1_FUENTES.zip`
**Qué cambia:**
- Auditoría de continuidad con 11 correcciones (cadencia doble con 2.º armónico dominante, JNI con «modified UTF-8», distancias distintas app/motor, sin cadencia con 8 % de pérdidas, sesgo de aceleración sostenida, API sin cancelación…): `equine-intelligence/docs/AUDITORIA_CONTINUIDAD_1_1_0.md`.
- Motor 1.1.0-dev1: aceleración avanzada (longitudinal, lateral estimada con incertidumbre, picos, eventos), curvas (radio cinemático y geométrico, centro, entrada/salida, cadencia), cadencia con incertidumbre y estado, regularidad en 4 métricas independientes, rasgos espectrales, GAIT_CLASSIFIER_V2 (V1 conservado), fusión temporal GNSS+cincha OFFLINE/REALTIME (causalidad comprobada), rendimiento por aire con DESCONOCIDO/TRANSICION/DATOS_INSUFICIENTES, eventos trazables, simetría exploratoria con controles de bloqueo, comparación de sesiones (proyección sobre recorrido, DTW de patrón, curvas equivalentes), persistencia de resultados derivados.
- API C v2 (opciones, cancelación, comparación, caché, códigos de error) y JSON v2 compatible con v1 (`docs/FORMATO_RESULTADOS.md`).
- **Android** (versión `2.1-motor-1.1.0-dev1`, versionCode 13): motor compilado con NDK dentro de la APK; al abrir un entrenamiento descargado se analiza en segundo plano (cancelable, reprocesable, guardado en `files/equine/<sesión>`); nueva pestaña **Motor** y gráficas del motor sincronizadas con mapa y gráficas existentes; «SIN DATOS DE CINCHA» cuando no hay IMU; comparación avanzada en la pantalla de comparar. No se ha tocado BLE, NTRIP, geocercas, sincronización ni la pantalla de inicio.
- **Windows**: la app WPF de `feature/windows-advanced-analysis` traída a esta rama e integrada (pestaña **Motor AVO**, DLL por P/Invoke, intervalos, comparación, exportación JSON/CSV, reprocesado); el importador guarda copias RAW verificadas para el motor.
- ML: etiquetado con historial de correcciones, intervalos desde tramos del motor, caballo y sesión, exportación CSV, evaluación por caballo o por sesión, rechazo de modelos definitivos con datos sintéticos.
**Validación:** IMPLEMENTADO + CI + simulación. **NO VERIFICADO físicamente**: sin cincha ni IMU reales, sin teléfono ni PC reales con esta versión.
**Pendiente:** hardware de la cincha (modelo de IMU, calibración, orientación), PPS, sesiones reales etiquetadas, prueba en teléfono y en Windows.

## 2026-10-23 — Equine Intelligence Engine 1.0.0-dev1 (rama `feature/avo-equine-intelligence-engine`)
**Autor:** Claude · **Commits:** `29c60c5`…`2dbbca3` · **CI:** run 40027191410 (**éxito**), `build-equine-engine.yml` (Linux ASan/UBSan, DLL Windows MSVC, NDK Android ×3 ABI, banco, demo ML)
**Qué cambia:** nueva carpeta `equine-intelligence/`: motor C++17 único (ingesta AVO RAW v1 reutilizando `avo_core`,
validación con banderas, mapa de relojes por envolvente inferior, GNSS/RTK, DSP de fase cero, cadencia y regularidad,
clasificación de aires con histéresis, calidad con motivos, anomalías exploratorias, JSON/CSV), API C, puente JNI+Kotlin,
P/Invoke C#, banco científico Python (ctypes sobre la librería real), infraestructura ML (sin modelo entrenado),
fichas de algoritmos y `docs/VALIDACION_Y_LIMITACIONES.md`.
**No se ha tocado:** firmware, app Android, updater, comunicaciones NTRIP.
**Validación:** IMPLEMENTADO + simulación (23 casos / 671 comprobaciones, 0 fallos; cadencia error máx 0,088 Hz con SNR ≥ 5 dB;
deriva de reloj 49,9/50 ppm). **NO VERIFICADO físicamente**: no hay datos reales de IMU (cincha inexistente en el hardware actual).
**Pendiente:** fusión GNSS+IMU, rendimiento por aire, comparación de sesiones, integración en las apps, PPS (sesgo ≈5 ms sin él).

## 2026-10-23 — Copias de código fuente y traspaso para asistentes
**Autor:** Claude · Zips en la raíz: `AVO_ANDROID_V2_0_REDISENO_MAREAS_ANALISIS_FUENTES.zip` (actualizado),
`AVO_UPDATER_V2_1_0_FUENTES.zip`, `AVO_BACK_V3_8_0_FUENTES.zip`. Documento `docs/TRASPASO_ASISTENTES_2026-10-23.md`
con versiones, carpetas, CI, arquitectura y reglas. `AGENTS.md` apunta a él. Sin cambios de código.

---

## 2026-10-23 — ESPALDA V3.8.0 (máxima precisión RTK) + USB Updater 2.1.0 (instala en la espalda)
**Autor:** Claude · **CI:** espalda [40015971416](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40015971416) (éxito, artefacto `AVO-BACK-V3-8-0-HELTEC`) · updater [40015367842](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40015367842) (éxito)
**Origen:** copia de la espalda leída con la app (AVO BACK **3.5.0**, Arduino-ESP32 3.3.12). Fuente: `AVO_BACK_V3_5_0.ino`
del paquete `firmware/chest/V3_5_4` + `avo_core` de 3.7.0-rc2. Nuevo paquete independiente `firmware/back/V3_8_0`
(el pecho conserva su propia copia de `avo_core`; **no se toca el firmware del pecho**).
**Qué cambia en la espalda:** 8 Hz con 4 constelaciones (límite RTK del ZED-F9P; la 3.5.0 pedía 10 Hz), constelaciones
según el ritmo pedido por el pecho (10 Hz sin BDS, 12 Hz GPS+GAL), RTK fijo explícito, modelo Airborne <2g, máscara 10°,
perfil en VALSET aparte con degradación segura, RTCM al ZED también durante la reconfiguración, Wi-Fi sin ahorro de
energía y a potencia máxima, ACK de ESP-NOW 25 ms, cola de 48, monitor serie con búfer, marcador `AVO-BACK`.
**Protocolo con el pecho:** sin cambios.
**USB Updater 2.1.0:** instalación también en la espalda por CP2102 (reinicio ClassicReset, comprobación de arranque por
el mismo enlace y relectura de otadata); bloquea firmware del pecho en la espalda y viceversa; identifica «AVO-BACK x.y.z».
**Validación:** espalda: 23 casos / 159 comprobaciones en ordenador (ZED simulado) y compilación CI (868 KB, 25 % de app0);
updater: 65 pruebas JVM. **NO VERIFICADO** en hardware.
**Pendiente:** instalar en la espalda, comprobar en el monitor serie `perfil=COMPLETO` y `ritmo=8 Hz (medido 8.0 Hz)`, y
comparar tiempo hasta RTK FIX y % de FIX en un entrenamiento frente a la 3.5.0.

---

## 2026-10-23 — USB Updater 2.0.1 — lectura fiable con la espalda Heltec (CP2102)
**Autor:** Claude · **CI:** [40011606283](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40011606283) (**éxito**)
**Prueba física (capturas del usuario, 21:14–21:15):** espalda Heltec por CP2102: «Información del dispositivo» **correcta**
(ESP32-S3 v0.2, MAC AC:A7:04:06:CD:24, flash GD 8 MB, sin Secure Boot ni cifrado, particiones Arduino por defecto
app0/app1 3264 KB + spiffs 1536 KB + coredump; arranca app0: Arduino (ESP-IDF v5.5.5), compilado el 16-09-2026 21:14:44).
**Fallo:** «Leer firmware» y «Copia completa» se detuvieron con «bloque de 3302 bytes en 0x11000» / «4030 bytes en 0x47000»:
se perdían bytes a 921 600 baudios con 64 bloques en vuelo (el CP2102 tiene un búfer muy pequeño). La verificación lo detectó y no guardó nada.
**Corrección:** en puentes USB-UART 460 800 baudios, 2 bloques en vuelo, piezas de 64 KB que solo se escriben si su MD5
coincide, y hasta 4 reintentos por pieza reiniciando el chip y recargando el stub. USB nativo sin cambios.
**Validación:** 64 pruebas JVM en local · **NO VERIFICADO** de nuevo con la Heltec.

---

## 2026-10-23 — USB Updater 2.0.0 — lectura, identificación y copia de seguridad (pecho y espalda) + diseño AVO 2.0
**Autor:** Claude · **Commits:** `7327094` · **CI:** [40009097029](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40009097029) (**éxito**)
**Qué cambia:**
- Nueva sección **Lectura y copia de seguridad** (solo lectura): información del dispositivo (chip, MAC, flash, seguridad,
  particiones, otadata, descriptor de cada app), **leer firmware** (app que arranca, recortada, SHA-256 y textos
  identificativos), **leer partición**, **copia completa de la flash** e informe `.txt`. Archivos guardados con el selector de Android.
- Soporte del módulo de **espalda Heltec Wireless Stick Lite V3**: puente **CP2102** (`Cp210xLink`, protocolo AN571) y
  CDC genéricos (CH9102/CH343); reinicio `ClassicReset` por DTR/RTS; filtro USB ampliado.
- Lectura rápida con el **stub oficial de Espressif** esp-flasher-stub v1.4.1 (Apache-2.0/MIT, `assets/stub/` con licencias)
  y 921 600 baudios; cada bloque comprobado con el MD5 del chip.
- Diseño de la app 2.0: colores AVO, tarjetas y botones como la app de entrenamiento, **pantalla de inicio** con la imagen
  AVO y el estado del programador (USB OTG, dispositivo, permiso, instalador, lectura rápida, almacenamiento). Su botón
  «ENTRAR AHORA» queda por encima de la barra de navegación. Icono AVO.
- versionCode 20 / versionName 2.0.0; artefacto `AVO-Performance-Horse-Update-V2-0-0-DEBUG`.
- Comprobaciones de seguridad del CI: la carga en RAM solo puede estar en `StubFlasher.kt` y el código de lectura no puede usar comandos de escritura ni borrado.
**No se ha tocado:** el flujo de instalación del pecho (planificador, escritura, otadata, verificación).
**Validación:** IMPLEMENTADO · 64 pruebas JVM en local (incluida la lectura completa con stub simulado y la garantía de que la flash no cambia) · **NO VERIFICADO** con la Heltec ni con el pecho.
**Pendiente:** probar con la espalda real; si el reinicio automático no entra en modo descarga, usar PRG + RST.

---

## 2026-10-23 — Android V2.0 — rediseño AVO, mareas IHM estilo Tu Marea Pro, análisis de entrenamientos, sin OTA
**Autor:** Claude · **Commits:** `049abc7` (+ documentación y zip) · **CI:** [39998714393](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39998714393) (**éxito**: pruebas core, pruebas JVM app y APK debug `AVO_Performance_Horse_V2_0_debug.apk`)
**Qué cambia:**
- Tema con los colores de la pantalla de arranque (negro, rojo AVO, plata, azul). Nuevos componentes: `MetricTile`, `MetricGrid`, `Segmented`, `ScreenHeader`; `AvoCard` con degradado y `trailing`.
- Navegación: Inicio · Entrenar · Historial · Mareas · Cuadra + engranaje de Ajustes. Inicio, Entrenar, Historial y Cuadra rediseñados; textos explicativos eliminados.
- Mareas (`tide/TideRepository.kt`, `core/tide/Tides.kt`): predicción oficial IHM (`ideihm.covam.es/api-ihm/getmarea`), puerto más cercano o elegido, curva coseno entre extremos, coeficiente 70 × carrera / carrera media (3 meses), sol y luna locales, Open-Meteo por horas, caché en disco. Pantalla estilo Tu Marea Pro con curva deslizable.
- Análisis (`core/raw/TrainingInsights.kt`): aceleración/frenada en g, altitud, desnivel y pendiente, aires por velocidad, tramos rápidos, parciales, eventos, cadencia de la IMU de la cincha (autocorrelación, sin escala). Pantalla Resumen / Mapa y gráficas / Datos con mapa Mapa/Satélite/Híbrido y gráficas sincronizadas con zoom común.
- Condiciones de la sesión para cualquier fecha (IHM + Open-Meteo, archivo histórico).
- Foto del caballo; Room 3 → 4 (`horses.photoPath`).
- Ajustes: lugar de entrenamiento (nombre y coordenadas, o posición del chaleco).
- OTA retirada por completo: `ota/`, `ChestOtaProtocol`, `MsgType.OTA_*`, `supportsOta`, tarjeta de Inicio, sección de Dispositivos y workflow `diagnose-android-ota.yml`.
- versionCode 12 / versionName 2.0; el workflow publica `AVO-Performance-Horse-V2-0-APK` y convierte los errores `e:` de Kotlin en anotaciones.
- `AVO_ANDROID_V2_0_REDISENO_MAREAS_ANALISIS_FUENTES.zip` en la raíz con app/, core/, gradle/ y `RELEASE_NOTES_V2_0.md`.
**No se ha tocado:** pantalla de arranque, BLE, NTRIP/RTCM, sincronización, NFC, geocercas, No molestar, compartir.
**Validación:** IMPLEMENTADO · CI correcto · pruebas core 48/48 en local · **NO VERIFICADO** en móvil.
**Pendiente:** comprobar en el móvil la lectura del IHM y Open-Meteo, comparar horas y coeficientes con Tu Marea, mapa híbrido y migración con datos reales. Aviso: el botón «ENTRAR AHORA» de la pantalla de arranque queda bajo la barra de navegación de Android (no se ha modificado por petición del usuario).

---

## 2026-10-23 — CHEST V3.7.2-rc1 — correcciones tras la primera prueba física (brillo en carga, cambio de pantalla, esquinas)
**Autor:** Claude · **Commits:** `6477310` · **CI:** [39968163291](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39968163291) (**éxito**; RAM estática sin cambios, 71.048 B)
**Prueba física (fotos del usuario, 16:12):** CHEST con 3.7.2-rc1 instalado. **Correcto:** orientación (BLUETOOTH arriba),
legibilidad, «V3.7.2-RC1», BLE conectado, espalda conectada (RSSI −64/−70 dBm), GPS DGNSS con 25 satélites, SD disponible,
cincha mostrada en rojo «Desconectada» (no estaba conectada), pantalla de carga «59 % CARGANDO USB».
**Fallos observados:** (1) brillo de carga demasiado bajo; (2) al desconectar el cargador quedaban restos del anillo de
carga entre las franjas; (3) la franja superior e inferior se cortaban en las esquinas curvas (icono BT, círculo de estado,
icono de batería y «%»).
**Causas y correcciones:**
1. El brillo con USB estaba fijado a 25. Ahora: 255 durante 15 s al conectar, al tocar o al pulsar BOOT/POWER; luego 25.
2. Al quitar el USB se borraba `charge_screen` antes de comprobarlo, así que solo se repintaban las franjas cambiadas.
   Ahora `ui.cpp` registra qué pantalla hay realmente en el panel (`Shown`) y cualquier vuelta a las franjas las repinta todas.
3. El área visible tiene esquinas de ~120 px (estimado con las fotos). Franjas de 62 px con 19 px de margen arriba/abajo;
   la 1 y la 7 siguen la curva y su contenido entra 24 px. Nueva comprobación en ordenador: ningún píxel de contenido
   fuera del área visible.
**No se ha tocado:** comunicaciones, NTRIP, GNSS, OTA ni almacenamiento.
**Validación:** comprobaciones en ordenador correctas; **pendiente de ver en el reloj** las tres correcciones.

## 2026-10-23 — Documentación — registro común y reglas para asistentes
**Autor:** Claude · **Commits:** ver el commit que añade este archivo
**Qué cambia:** se crean este registro, `AGENTS.md` (reglas para cualquier asistente) y `CLAUDE.md` (remite a
`AGENTS.md`). Se actualizan `README.md` y `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` con el programador USB y CHEST 3.7.x.
**Por qué:** petición del usuario: que todos los cambios queden documentados en la rama de GitHub, centralizados
entre Claude y ChatGPT.
**Validación:** documentación; no aplica CI de firmware ni de Android.

## 2026-10-23 — CHEST V3.7.2-rc1 — pantallas de carga USB y apagado seguro por fases reales
**Autor:** Claude · **Commits:** `b2a8fb3`, `3e85c41` · **CI:** [39964200690](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39964200690) (fallo: colisión con macros de color de Arduino_GFX), [39965639870](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39965639870) (**éxito**)
**Qué cambia:**
- Pantalla de carga según referencia del usuario: anillo con extremos redondeados, batería con nivel real y rayo,
  porcentaje grande, «CARGANDO USB» / «CARGA COMPLETA» / «USB CONECTADO». En 3.7.1 la función existía pero **no se
  llamaba** (aviso `render_charging defined but not used`). Ahora se muestra con USB salvo si se está grabando;
  un toque corto (< 0,8 s) alterna 30 s con las siete franjas.
- Pantalla de apagado: icono, «APAGANDO...», «Guardando entrenamiento» y barra de **4 fases reales**
  (1 detener sesión, 2 cerrar archivos SD, 3 guardar caja negra, 4 apagar). Si la SD no se cierra, el firmware
  ya cancelaba el apagado; ahora se muestra «NO SE PUDO GUARDAR — El reloj sigue encendido» durante 6 s.
- Constantes de color renombradas a `C_*` porque Arduino_GFX define `GREEN`, `RED`, `BLUE`, `YELLOW`, `WHITE` como macros.
- El workflow publica errores de compilación y uso de memoria como anotaciones.
**Archivos:** `firmware/chest/V3_7_2_UI/` (`src/ui*.{h,cpp}`, `tools/apply_v372.py`, `tools/gen_ui_assets.py`), `.github/workflows/build-chest-v372-ui.yml`.
**Cambios fuera de la pantalla:** `tools/apply_v372.py` añade `shutdown_phase` y `shutdown_fail_ms` a `PowerState` y
6 líneas en `controlled_shutdown()` (controller.cpp) que publican la fase, más 300 ms antes de `pmu_power_off()`.
**No se ha tocado (petición expresa del usuario):** BLE, ESP-NOW, UART, NTRIP/RTCM, GNSS, OTA ni almacenamiento.
El orden del apagado es el mismo.
**Validación:** COMPILADO / CI (39965639870). Comprobaciones en ordenador con el mismo código de dibujo (panel simulado):
correctas. **NO VERIFICADO en el reloj.**

## 2026-10-23 — CHEST V3.7.2-rc1 — pantalla de siete franjas legible, sin LVGL
**Autor:** Claude · **Commits:** `f60c125` · **CI:** [39963751268](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39963751268) (fallo: la prueba nueva detectaba «LVGL» dentro de un comentario; corregido en `b2a8fb3`)
**Problema observado (foto del usuario, 3.7.1-rc2):** imagen girada 180°, texto ilegible y bordes en escalera.
**Causas:** `setRotation(0)` con el panel montado al revés; fuente interna 5×7 a escala 1–2 (6–14 px);
el CO5300 exige columnas/filas pares y Arduino_GFX dibujaba anchos impares.
**Qué cambia:**
- Nuevo motor `ui_fb`: framebuffer RGB565 410×502 en **PSRAM** (402 KB de 8 MB), primitivas suavizadas, texto UTF-8,
  envío alineado a pares y **giro 180° por software** (el controlador sigue en rotación 0 y conserva su
  desplazamiento de columna de 22 px; `setRotation(2)` lo pondría a 0).
- `ui_dash` (diseño), `ui_model` (estado real → franjas según `V3_5_9/UI_7_FRANJAS_ESPECIFICACION.md`),
  `ui_assets.h` generado: fuentes Barlow Condensed (SIL OFL) e iconos Font Awesome Free 7 (OFL / CC BY 4.0), 148 KB en flash.
- Solo se redibujan las franjas que cambian. Con la SD grabando **solo parpadea el punto rojo** (500 ms), a petición del usuario.
- GPS: rojo sin GNSS, azul autónomo, verde con correcciones NTRIP aplicadas. Batería: verde >50 %, amarillo 21–50 %, rojo ≤20 %.
- **Sin LVGL** (el usuario indica que LVGL satura la RAM interna y rompe BLE y el enlace con la espalda).
**Memoria (CI 39965639870):** RAM estática 71.048 B frente a 70.328 B en 3.7.1-rc2 (+720 B); más un búfer de envío
dinámico de 13 KB en RAM interna. Flash del programa: 1.528.319 B.
**Validación:** COMPILADO / CI. **NO VERIFICADO en el reloj.**
**Pendiente en el reloj:** orientación (BLUETOOTH arriba) sin desplazamiento lateral; esquinas de la primera y la
última franja; parpadeo del punto; línea serie `[AVO MEM] UI V3.7.2`; BLE y espalda estables; margen de pila de la
tarea UI (4 KB, sin cambios). Con USB el brillo sigue limitado a 25 (como 3.7.1).

## 2026-10-23 — Programador USB 1.8.0-beta2 — versión AVO real en los BIN de Arduino
**Autor:** Claude · **Commits:** `a0d2d32` · **CI:** [39963751136](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39963751136) (**éxito**, SHA `f60c125` que incluye `a0d2d32`)
**Qué cambia:** Arduino escribe `arduino-lib-builder <hash>` en `esp_app_desc_t`; la app lo mostraba como versión.
Ahora se lee `AVO_FW_VERSION` junto a `AVO-CHEST` en el primer segmento y la marca `AVOCHEST-IMG-V1:WS-AMOLED-2.06`.
Se usa para la etiqueta, la descripción de los slots (lectura de 1 KB) y la confirmación de arranque por USB.
**Comprobado con archivos reales del usuario:** `AVO_CHEST_V3_7_1_RC2_OTA_UNVERIFIED.bin` (1.364.544 B, SHA-256
`6ca9c695…cbee`) válido: 7 segmentos, checksum y SHA-256 adjunto correctos, versión «AVO-CHEST 3.7.1-rc2».
Tabla `AVO_CHEST_V3_5_0.ino.partitions.bin` = nvs 0x9000, otadata 0xE000, app0 0x10000, app1 0x610000 (6 MB),
blackbox 0xC10000, coredump 0xC50000, con registro MD5. Bootloader: flash 16 MB.
**Validación:** CI, 59 pruebas unitarias. **NO VERIFICADO con el reloj.**

## 2026-10-23 — Programador USB 1.8.0-beta1 — programador completo (bloques A–E)
**Autor:** Claude · **Commits:** `14fdeac` (A), `8a954fd` (B), `346e459` (C), `652344e` (D), `620844c` (E) · **CI:** [39959974774](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/39959974774) (**éxito**)
**Qué cambia:**
- A: cliente ROM ESP32-S3 (estado de 4 bytes, SYNC, READ/WRITE_REG, GET_SECURITY_INFO, SPI_ATTACH/SET_PARAMS,
  watchdogs), lectura de flash por registros SPI1 **verificada con el MD5 del propio chip**, tabla de particiones, otadata, slots.
- B: validación completa del BIN (segmentos, checksum, SHA-256 adjunto, descriptor, revisión de chip). Sustituye
  `FlashWriter` (usaba el formato FLASH_BEGIN de ESP32 y leía mal el estado).
- C: planificador (actualización normal / recuperación USB), FLASH_BEGIN S3 de 5 palabras, verificación MD5,
  huellas de zonas protegidas, activación `otadata` como `esp_ota_set_boot_partition()`, reinicio por DTR/RTS y
  comprobación del primer arranque.
- D: interfaz Android en español, hilo de trabajo, cancelación segura, permisos tras re-enumeración, filtro USB 303A:1001.
- E: ESP32-S3 simulado y pruebas; workflow con comprobaciones de seguridad.
**Seguridad:** solo se escribe el slot OTA destino y una copia de otadata; nunca bootloader, tabla, NVS, blackbox
ni coredump. Bloqueo con Secure Boot, Flash Encryption o Secure Download.
**Validación:** CI (58 pruebas en simulación). **NO VERIFICADO con el reloj.** Primera prueba física: solo «LEER RELOJ».
**Detalle:** `usb-updater/README.md`, `usb-updater/docs/VERIFICACION_V1_8_0.md`.

## Historial anterior
Ver `docs/ESTADO_DESARROLLO_Y_VERSIONES.md` (hasta CHEST V3.5.7, 22/10/2026) y los README de `firmware/chest/V3_*`.
Las versiones CHEST 3.6.x, 3.7.0-rc1/rc2 y 3.7.1-rc2 constan en sus carpetas y workflows (`build-chest-v3*.yml`)
pero no tenían entrada en este registro.

## 2026-10-24 — App: borrar del móvil, WhatsApp y borrar, firma estable
- `WatchSyncManager.deleteLocal`: borra solo la copia del teléfono (RAW, resultados del motor, paquete compartido); el entrenamiento vuelve a «Solo en el reloj». La copia del reloj no se toca.
- Historial: botón «Borrar del móvil» (con confirmación) y botón «WhatsApp»: descarga si hace falta, abre WhatsApp / WhatsApp Business con el paquete AVO-TRAINING-1 y, al volver, borra la copia local (ajuste `share.deleteAfterWhatsApp`, activado por defecto).
- Firma estable: el APK debug se firma con la clave AVO cuando existen los secretos `AVO_KEYSTORE_BASE64`, `AVO_KEYSTORE_PASSWORD`, `AVO_KEY_ALIAS` y `AVO_KEY_PASSWORD`. La clave no está en el repositorio. Hace falta una última desinstalación al pasar a la clave estable.
- versionCode 14. Pendiente: validación física en el dispositivo.

## 2026-10-24 — Identidad AVO por tarjeta NFC + app «AVO Tarjetas» (rama `feature/avo-nfc-identity`)
- Primer paso del envío de entrenamientos entre apps. Cada persona tiene una tarjeta NFC personal con código único (`AVO-XXXX-XXXX`), nombre y una clave aleatoria de 128 bits. Si cambias de móvil, la identidad viaja con la tarjeta.
- Formato: `core/identity/AvoUserCard` → URI NDEF `avohorse://identity/user/<código>?v=1&name=…&k=…`, el mismo esquema que las etiquetas de caballo y jinete. Las versiones anteriores de la app ignoran este tipo. Pruebas: `AvoUserCardTest`.
- App principal:
  - `identity/UserIdentity` guarda la tarjeta cifrada (SecureStore).
  - Al acercar una tarjeta personal, se adopta solo si el móvil no tiene identidad. Una tarjeta distinta no reemplaza la identidad: hay que pulsar «Olvidar identidad» en NFC.
  - La pantalla NFC muestra la identidad y no graba caballo o jinete encima de una tarjeta personal.
  - La lectura de etiquetas de caballo y jinete no cambia.
- Nuevo módulo `cards` (`org.avoperformance.cards`, «AVO Tarjetas»):
  - crea y graba tarjetas (URI + AAR que abre la app principal) y las verifica;
  - opción de bloqueo irreversible;
  - no sobrescribe datos AVO sin confirmación;
  - lista de tarjetas emitidas, «Grabar copia» y «Dar de baja». La baja tendrá efecto cuando exista el servicio de envío.
- Tarjetas simples (NTAG213/215/216), uso doméstico: se pueden copiar si alguien las tiene en la mano.
- CI compila los dos APK, que se firman con la misma clave estable cuando existen los secretos.
- Pendiente: el servicio de envío (Firebase, cuando se aporte `google-services.json`) y la validación física con tarjetas reales.

## 2026-10-24 — Envío de entrenamientos entre apps por internet (Firebase, sin servidor propio)
- Proyecto Firebase `avo-performance-horse-7be14`, plan gratuito Spark. Usa Authentication (correo/contraseña) y Realtime Database (europe-west1). No usa Cloud Storage ni Cloud Functions.
- La cuenta es la tarjeta NFC personal: el correo es `<código>@avo-cards.app` (no es una dirección real) y la contraseña es la clave de la tarjeta. Con la misma tarjeta en otro móvil se entra en la misma cuenta.
- Envío (`cloud/AvoCloud`):
  - el paquete `.avo` (AVO-TRAINING-1, `TrainingShare.buildPackage`) se sube en trozos base64 de 256 kB a `blobs/<destino>/<id>`;
  - después se escribe el aviso en `inbox/<destino>/<id>`, con remitente, sesión, tamaño, SHA-256 y número de trozos;
  - máximo 30 MB.
- Recepción (`cloud/CloudInbox`, dentro de `AvoLinkService`):
  - escucha la bandeja mientras el servicio está activo, descarga, comprueba el tamaño y el SHA-256, guarda en `files/received`, borra la entrega de Firebase y avisa con la notificación «Nuevo entrenamiento recibido»;
  - al pulsar el aviso se abre el diálogo de importación de siempre;
  - si se pierde la red, reintenta con espera creciente.
- Interfaz: botón «Internet» en cada entrenamiento (lista de usuarios AVO) y lista de recibidos con Importar/Descartar en «Mis entrenamientos».
- Seguridad:
  - reglas en `firebase/database.rules.json`: solo el titular de la tarjeta lee o borra su bandeja, el remitente debe ser quien dice ser y hay límites de tamaño;
  - la configuración pública de Firebase está en `cloud/FirebaseConfig.kt`. No es un secreto: Google la incluye en cada app, y la protección la dan las reglas.
- Limitaciones:
  - el aviso solo llega mientras el servicio de la app está activo (sin FCM ni Cloud Functions);
  - «Dar de baja» en AVO Tarjetas todavía no bloquea la cuenta en Firebase.
- versionCode 15. Pendiente: pegar las reglas en la consola y hacer la validación física con dos móviles.

## 2026-10-24 — AVO Tarjetas con el estilo visual de la app principal
- Regla: toda app AVO nueva usa el mismo estilo visual que la principal, como AVO Update.
- `cards` compila directamente `app/.../ui/theme` (AvoTheme, AvoColors) y `ui/components` (AvoCard, StatusPill, KV, Note, ConfirmDialog). Hay una sola fuente, así que cualquier cambio de estilo se aplica a las dos apps.
- Recursos copiados de la app: icono AVO adaptativo, imagen de cabecera `avo_brand_hero`, colores y tema de ventana `Theme.Avo` con fondos negros.
- Pantalla con cabecera de marca, encabezado «AVO TARJETAS», tarjetas AVO e indicadores de estado (GRABANDO/LECTURA/BAJA).

## 2026-10-24 — Envío automático de entrenamientos nuevos a otro usuario (Firebase)
- Sincronización → «Envío automático por internet»: se activa y se elige el destinatario de la lista de usuarios AVO.
- `cloud/AutoSender`:
  - envía cada entrenamiento una sola vez en cuanto se descarga y verifica con el reloj (`WatchSyncManager.onVerified`);
  - solo envía los grabados desde que se activó la opción; nunca envía en bloque los antiguos;
  - lleva un registro de los ya enviados (`cloud.autoSendDone`);
  - deja pendientes los que no tienen caballo o jinete;
  - si falla la red, reintenta al iniciar el servicio, en cada descarga nueva o con «Enviar pendientes ahora».
- Usa el mismo transporte y las mismas reglas que el envío manual. Al otro usuario le llega el aviso «Nuevo entrenamiento recibido».

## 2026-10-24 — Compartir y sincronizar entre usuarios AVO (Firebase) · rama `feature/avo-firebase-sync`
- Sustituye al envío por internet anterior (AvoCloud/CloudInbox/AutoSender). Documento: `docs/SHARE_FIREBASE.md`.
- Cuenta = tarjeta NFC, sin correo (decisión del usuario). Sin FCM ni Cloud Storage (plan Spark).
- Tres modalidades simultáneas: global, por caballo y manual (COMPARTIR). Deduplicación por destinatario y por contenido (identificador estable de transferencia).
- Invitaciones con aceptar, rechazar, bloquear y eliminar. No se envía nada sin invitación aceptada.
- Motor en `core/share` (`ShareEngine`): un único contenido por entrenamiento con permiso individual por destinatario, subida reanudable, verificación SHA-256, importación con `TrainingImport`, acuse de recibo y limpieza por confirmación o caducidad (14 días).
- Cola persistente en Room (migración 4→5, solo tablas nuevas), WorkManager periódico cada 15 min y reintentos con backoff. Escucha en vivo desde el servicio y comprobación al abrir la app.
- Pantalla «Compartir y sincronizar» con: estado, cuenta, invitaciones, destinatarios globales y por caballo, transferencias, conflictos, historial, red y consumo. Botones «Compartir AVO» (Historial) y «COMPARTIR» con indicador de estado (Análisis).
- Reglas definitivas en `firebase/database.rules.json`, con pruebas en Firebase Emulator Suite (workflow «Firebase rules (emulator)»). Pendiente de publicar a mano en la consola de Firebase.
- versionName 2.2-share-dev1, versionCode 17. Pendiente: validación física con dos móviles.

## 2026-10-24 — Diagnóstico de «Permiso denegado» al compartir (2.2-share-dev2)
- Prueba física: al pulsar «Compartir AVO», Firebase devuelve «Permission denied».
- Los errores de permiso ahora indican la ruta exacta y el usuario con sesión iniciada, para localizar qué regla lo rechaza. No cambia ninguna regla ni ninguna funcionalidad. versionCode 18.

## 2026-10-24 — Corrección: perfil sin publicar ⇒ «Permiso denegado» al invitar (2.2-share-dev3)
- Prueba física: «Permission denied en grants/AVO-URTK-T4A8/AVO-BM2N-9YGG como AVO-BM2N-9YGG».
- Causa probable: el primer registro con la tarjeta se hizo con las reglas aún bloqueadas. La sesión de Firebase quedó abierta, pero el perfil `users/<código>` no se guardó, y `signIn` salía antes de tiempo al ver la sesión abierta, así que nunca lo reintentaba. Las reglas exigen que existan los perfiles de remitente y destinatario.
- Corrección: `signIn` publica o repara el perfil siempre que la sesión ya esté abierta (una vez por proceso). `invite` comprueba antes que el destinatario esté registrado y, si no, da un mensaje claro. versionCode 19.

## 2026-10-24 — Asignar caballo y jinete desde la app; envío al aceptar (2.2-share-dev4)
- Prueba física: el envío falla con «Falta caballo o jinete» y no había forma de asignarlos fuera del flujo «Compartir» de WhatsApp.
- Nuevo diálogo `AssignHorseRiderDialog` («Caballo y jinete»): permite elegir uno guardado o escribir uno nuevo, que se guarda en Cuadra/Jinetes. Solo cambia los metadatos del entrenamiento en el móvil; no toca el RAW ni el reloj. Está disponible en:
  - Análisis: tarjeta «Caballo y jinete» con el botón Asignar/Cambiar;
  - Historial: botón «Caballo y jinete» en cada entrenamiento descargado;
  - «Compartir AVO»: si faltan, los pide antes de elegir destinatarios. Volver a compartir reabre un envío fallido.
- Si hay envíos esperando aceptación, se comprueba cada minuto (mientras el servicio está activo) y salen en cuanto se acepta, sin esperar a la tarea de 15 min.
- Historial de enviados: sin caballo, muestra el identificador de sesión en lugar de «— ·». versionCode 20.

## 2026-10-24 — Confirmación de recepción sin esperar 15 min (2.2-share-dev5)
- Petición del usuario: que, al pasar a «Enviado», la sincronización con Firebase sea automática.
- Con el servicio activo, cada 20 s se consultan los acuses (`receipts`) de los envíos en «Enviado». Si el destinatario ya confirmó (o el contenido ya no existe), se lanza una pasada y el envío pasa a OK.
- Además, tras cada pasada con envíos en «Enviado» de menos de 2 h, se programa otra pasada a los 30 s con WorkManager, también con la app cerrada. Las invitaciones aceptadas se siguen comprobando cada minuto. versionCode 21.

## 2026-10-24 — Sincronización al abrir los entrenamientos (2.2-share-dev6)
- Al abrir Historial se lanza una pasada de Firebase (envío, acuses de recibo y recepción), sin esperar a la tarea periódica. Se suma a la sincronización tras «Enviado» de 2.2-share-dev5. versionCode 22.

## 2026-10-24 — Recepción al momento en móviles sin reloj (opción A, gratis) (2.2-share-dev7)
- Prueba física: el móvil receptor no tenía reloj autorizado, así que `AvoLinkService` nunca arrancaba y no había escucha de Firebase. Solo recibía al abrir la app o con la tarea de 15 min.
- `AvoLinkService` arranca también sin reloj si el móvil tiene tarjeta AVO. En ese caso solo escucha Firebase: no arranca el enlace con el reloj, ni NTRIP, ni la sincronización con el reloj. Usa el tipo de servicio `remoteMessaging` (Android 14+; permiso `FOREGROUND_SERVICE_REMOTE_MESSAGING`) con la notificación fija «Esperando entrenamientos de usuarios AVO». Con reloj autorizado no cambia nada (`connectedDevice`).
- El servicio se arranca: al abrir la app, al acercar la tarjeta AVO, al reiniciar el móvil o actualizar la app, y como red de seguridad en cada `ShareWorker`.
- Sigue sin ser push: si el fabricante cierra la app en segundo plano, hay que quitarla del ahorro de batería. La opción B (FCM con Cloud Functions, plan Blaze) queda pendiente de decisión. versionCode 23.

## 2026-10-24 — Reorganización de la interfaz (2.2-ui-dev8)
Petición del usuario.
- **Cuadra:**
  - al tocar un caballo se abre su ficha: datos, totales y entrenamientos del más reciente al más antiguo, que se abren al análisis;
  - lo mismo con los jinetes;
  - «Seleccionar» pasa a ser un botón propio (`ProfileScreens.kt`).
- **Historial → «Entrenamientos»:**
  - título de la pantalla «ENTRENAMIENTOS»; la pestaña inferior se llama «Entrenos» por espacio;
  - cada entrenamiento tiene un único botón **Compartir**, que abre una ventana con: Usuarios AVO, WhatsApp y borrar del móvil, y Otras aplicaciones.
- **Ajustes:** la pantalla principal solo tiene botones agrupados por proceso:
  - Conexión: reloj y Bluetooth, NTRIP, dispositivos;
  - Entrenamiento: lugar, geocercas, no molestar;
  - Caballos y jinetes: jinetes, tarjetas NFC;
  - Datos y compartir: descarga del reloj, compartir y sincronizar, WhatsApp favoritos, almacenamiento, copias de seguridad;
  - Sistema: diagnósticos, acerca de.
  - Las tarjetas sueltas pasan a páginas propias (`SpotScreen`, `DndScreen`, `WhatsAppFavoritesScreen`, `BackupScreen`, `AboutScreen`).
- **Textos explicativos eliminados** (ayudas de funcionamiento, rutas de sincronización, tarjeta «Servidor»). Se mantienen los estados, los errores, las listas vacías y los avisos de validez del análisis (umbrales sin validar en caballos reales, aceleraciones GNSS frente a cincha), que evitan conclusiones no validadas.
- No cambia ninguna funcionalidad. versionCode 24.

## 2026-10-25 — Icono de la app con caballo, AVO y HORSE EDITION (2.2-ui-dev9)
- Petición del usuario: el icono solo mostraba la cabeza del caballo recortada.
- Nuevo primer plano del icono adaptativo (`avo_launcher_foreground.webp`), recortado de la imagen de marca `avo_brand_hero`: caballo, «AVO» y «HORSE EDITION», sin «PERFORMANCE» porque a ese tamaño no se lee.
- Tamaño ajustado para que entre completo en la máscara circular y en la cuadrada redondeada. Fondo negro de marca (#030406). También en AVO Tarjetas. versionCode 25.

## 2026-10-25 — Iconos diferenciados: AVO Tarjetas (marco azul) y AVO Update (marco verde)
- Petición del usuario: distinguir las apps por el icono.
- AVO Tarjetas: icono adaptativo nuevo (caballo, AVO, HORSE EDITION) con marco azul en el borde de la máscara.
- AVO Update 2.1.1 (versionCode 23): pasa de icono cuadrado (`avo_launcher_brand`) a icono adaptativo con el mismo logo y marco verde. No cambia ninguna funcionalidad del updater.
- El workflow del updater también se ejecuta en `feature/avo-firebase-sync`.

## 2026-10-25 — Descarga de entrenamientos por Wi-Fi reloj ↔ móvil · rama `feature/avo-wifi-sync`
- **Firmware CHEST 3.7.4-wifi-rc1** (`firmware/chest/V3_7_4_WIFI`, sobre 3.7.3-rc1):
  - punto de acceso SoftAP `AVO_CHEST_XXXX` (WPA2) en el canal ESP-NOW, en modo AP_STA, para que la espalda siga conectada;
  - contraseña única por reloj en NVS y token de sesión de 128 bits;
  - servidor HTTP de solo lectura `/api/v1` con Range, If-Match/etag, SHA-256 y fin de sincronización;
  - orden BLE `WIFI_SYNC` 0x64 (solo con app autorizada) y capacidad b11;
  - no se enciende durante una grabación y se apaga si empieza una;
  - apagado automático por inactividad, falta de cliente, tiempo máximo, batería o fin confirmado.
  - BIN `AVO_CHEST_V3_7_4_WIFI_RC1_UNVERIFIED.bin`, compilado en CI y **no validado en hardware ni apto para OTA**. No cambia el formato RAW, la grabación, ESP-NOW, OTA ni las particiones.
  - Documento: `PROTOCOLO_WIFI.md`.
- **Android 2.3-wifi-dev1:**
  - `AvoWifiSyncManager` + `core/wifi` (`WifiSyncCoordinator`, máquina de estados, `WifiDownloader` reanudable);
  - `WifiNetworkSpecifier` con BSSID y HTTP atado a la red del reloj;
  - los segmentos van a los mismos ficheros que BLE, así que cada transporte continúa la descarga del otro;
  - verificación SHA-256 con el reloj;
  - respaldo BLE cuando el firmware no tiene la capacidad o Android no conecta;
  - NTRIP en pausa durante la descarga.
  - Se activa al terminar un entrenamiento, al reconectar, con «Descargar todo» (que ahora funciona aunque la descarga automática esté desactivada) y al abrir Entrenamientos.
  - Estados en pantalla: Conectando con el reloj…, Descargando · %, Verificando…, Entrenamiento guardado ✓ y Pendiente de conexión; botones Pausar/Reanudar y Cancelar.
  - Permisos: `CHANGE_NETWORK_STATE`, `ACCESS_WIFI_STATE`.
- **Corrección:** el pecho sí usa ESP-NOW por defecto (`AVO_LINK_UART`=0); el cable UART es solo una opción de compilación.
- **Pruebas:** `WifiSyncTest` (24 casos, escenarios 1–20 de la directiva) y `test_wifi_v374.py` (19 comprobaciones). Las pruebas físicas están pendientes; la lista está en `PROTOCOLO_WIFI.md`.

## 2026-10-25 — Bucle de reinicios con CHEST 3.7.4-wifi-rc1 (corrección: firmware rc2 + app 2.3-wifi-dev2)
- **Prueba física:** con 3.7.4-wifi-rc1 el reloj se reinicia cada 5–6 s. En cada conexión, la app pedía `WIFI_SYNC(start)`, el reloj se reiniciaba al levantar el AP y, al reconectar, la app volvía a pedirlo. Era un bucle provocado por la app.
- **Causa probable** (sin log serie, no confirmada): falta de RAM interna al levantar AP + httpd junto a BLE + ESP-NOW (ya había avisos de `ESP_ERR_NO_MEM`), o desbordamiento de pila al ejecutarse en la tarea `ble_rx` (6 KB).
- **Firmware 3.7.4-wifi-rc2:**
  - el AP se levanta en su propia tarea (8 KB de pila), fuera de `ble_rx`;
  - comprueba la RAM interna antes de empezar (≥ 72 KB libres y bloque ≥ 24 KB) y, si no la hay, rechaza con `IO_ERROR`/4 sin reiniciarse;
  - deja una marca en NVS (`wifi_try`): si el reloj se reinicia antes de terminar de levantar el AP, en el siguiente arranque desactiva el Wi-Fi (`wifi_off`), lo anota en la caja negra y la app pasa a BLE;
  - `WIFI_SYNC` 5 lo vuelve a activar;
  - pila de httpd de 6 KB.
- **App 2.3-wifi-dev2:**
  - protección contra bucles: antes de cada arranque del AP guarda el contador de arranques del reloj; si al reconectar ha subido, desactiva el Wi-Fi para ese firmware y descarga por Bluetooth. Se reactiva solo con otra versión de firmware;
  - «Pausar» se mantiene tras reiniciar la app.
- Las pruebas físicas siguen pendientes. El rc2 tampoco está probado en el reloj.

## 2026-10-25 — Los botones de un entrenamiento también usan Wi-Fi (2.3-wifi-dev3)
- Registro de campo: con 3.7.4-wifi-rc2 la app no pedía Wi-Fi (no aparece ninguna línea WIFI). «Reanudar descarga», Compartir y WhatsApp llamaban a la descarga BLE directamente; solo «Descargar todo» y la descarga automática pasaban por Wi-Fi.
- `WatchSyncManager.download(id)` intenta Wi-Fi primero (con el mismo coordinador; si ya hay una pasada en marcha, no se lanza otra) y usa BLE solo como respaldo.
- El registro indica siempre por qué no se usa Wi-Fi: firmware sin la capacidad, bloqueo por reinicio o falta de datos del reloj.
- **Observación de campo, pendiente de explicar:** el registro alterna `fw 3.7.4-wifi-rc2` y `fw 3.7.3-rc1` tras cada «enlace perdido». Puede ser una vuelta atrás automática de OTA (rollback) por reinicio del rc2, o una reinstalación manual. Se pide confirmación al usuario y el log serie. versionCode 28.

## 2026-10-25 — AVO Update 2.2.0: monitor serie
- Para diagnosticar el reinicio de CHEST 3.7.4 sin ordenador. El registro de campo muestra que AVO Update instala el rc2 en app1 en estado NEW y el reloj vuelve solo a la 3.7.3 (app0): el rc2 se reinicia por sí solo.
- Nueva tarjeta «Monitor serie»:
  - lee lo que el reloj imprime por su USB (USB-Serial/JTAG o CP210x a 115200);
  - se reconecta solo cuando el reloj se reinicia y el USB desaparece, así captura el arranque siguiente (motivo de reinicio y líneas `[AVO MEM]`);
  - botón «Reiniciar reloj y capturar» (reinicio normal por RTS, como esptool);
  - «Guardar monitor (.txt)».
- No escribe nada en el reloj. versionCode 24.

## 2026-10-25 — CHEST 3.7.5-rc1: liberar RAM interna (+ Wi-Fi bajo demanda) · AVO Update 2.2.1
- **Medido en campo** con el monitor serie (3.7.3-rc1): al final del arranque solo quedan 11 772 B de RAM interna libre, con un bloque máximo de 7 156 B. Es la causa del reinicio de 3.7.4-rc1 y de la vuelta atrás automática del rc2. Detalle en `firmware/chest/V3_7_5_RAM/README.md`.
- **3.7.5:**
  - host NimBLE en PSRAM y solo con rol periférico;
  - `heap_caps_malloc_extmem_enable(1024)`;
  - pilas de `ble_tx` y `ui_lite` en PSRAM (comprobado que no escriben en la flash);
  - Wi-Fi bajo demanda: la tarea solo existe mientras el AP está encendido, con `WiFi.persistent(false)`, umbral de 40/16 KB y medida del coste;
  - línea `[AVO MEM] ready`.
  - No cambia el formato RAW, la grabación, ESP-NOW, OTA ni las particiones. BIN marcado UNVERIFIED.
  - Pruebas estáticas: `test_ram_v375.py`, y `test_wifi_v374.py` actualizado a 26 comprobaciones.
- **AVO Update 2.2.1:** el monitor ya no muestra «USB desconectado» cuando solo no llegan datos.

## 2026-10-25 — AVO Update 2.2.2: monitor automático tras instalar
- Al terminar la instalación por USB, el monitor serie se pone en marcha solo, sin reiniciar el reloj, e incluye la salida USB que se captó durante la verificación. Así queda registrado el primer arranque del firmware nuevo y una posible vuelta atrás, que con la 3.7.5-rc1 no se pudo ver.
- El workflow del updater ponía un nombre fijo (V2_1_0) al APK y al artefacto. Ahora el APK se llama `AVO_Update_V<versión>.apk`, con la versión sacada de build.gradle, y el artefacto `AVO-Update-APK`.

## 2026-10-25 — CHEST 3.7.5-rc2
- **Prueba física de la 3.7.5-rc1:**
  - arranca y queda validada (VALID);
  - RAM interna libre al final del arranque: 26 084 B, con un bloque máximo de 17 396 B (la 3.7.3 dejaba 11 772 B y 7 156 B);
  - justo después de `ready` da un PANIC y entra en reinicios constantes.
- **rc2:** se quitan las pilas de `ble_tx` y `ui_lite` en PSRAM, que eran el cambio con más riesgo. Se mantienen NimBLE en PSRAM y `extmem(1024)`. Sigue sin verificar.

## 2026-10-25 — CHEST 3.7.5-rc3
- **Medido en la rc2:**
  - estable, descarga por BLE sin reinicios;
  - al final del arranque quedan 15 352 B libres, con un bloque máximo de 7 412 B;
  - la UI consume unos 24 KB internos, de los que 13 KB son el búfer DMA de 16 filas.
- **rc3:**
  - búfer DMA de la UI reducido a 4 filas (unos 9,8 KB más libres);
  - umbral del AP Wi-Fi bajado de 40/16 KB a 20/8 KB, porque el Wi-Fi ya está inicializado para ESP-NOW. Se mantienen las protecciones: si el reloj se reinicia al encender el AP, el Wi-Fi queda desactivado y la app pasa a Bluetooth.
- Sin verificar físicamente.

## 2026-10-25 — CHEST 3.7.5-rc3 (medido) y rc4
- **rc3 medida:**
  - estable;
  - 25 572 B libres al terminar el arranque, con un bloque de 17 396 B;
  - con el móvil conectado, al pedir el Wi-Fi quedaban 18 196 B (bloque de 10 228 B): el reloj lo rechazó porque el mínimo era 20 KB, y la descarga se hizo por BLE.
- **rc4:**
  - pilas de `link_rx` y `link_tx` reducidas de 8192 a 5120 B, y la de `ctl` de 8192 a 6144 B: unos 8 KB más libres;
  - mínimo del AP bajado a 16/8 KB;
  - el monitor muestra `[AVO STACK]` con la pila libre de cada tarea al pedir el Wi-Fi.
- Sin verificar físicamente.

## 2026-10-25 — CHEST 3.7.5-rc4: pantalla en pausa durante el Wi-Fi
- Autorizado por el usuario: durante la descarga por Wi-Fi (nunca durante una grabación) se pueden parar la pantalla, la telemetría y el enlace con la espalda.
- **Implementado en la rc4:**
  - Al encender el AP, la pantalla muestra «DESCARGA WI-FI» fija. La tarea de la UI termina y se libera su búfer DMA (unos 7 KB).
  - Al apagar el Wi-Fi, o si el reloj lo rechaza, se recrean el búfer y la tarea y se repinta todo.
  - Monitor: `[AVO UI] paused/resumed`.
- **No se ha parado el enlace con la espalda:** sus tareas solo devuelven RAM si se borran, y borrarlas en marcha es arriesgado. Lo que se ha hecho es reducir sus pilas, que es lo de la entrada anterior.
- Se ha eliminado el workflow de la 3.7.4-rc2: `wifi_sync.cpp` ahora necesita las funciones de la UI de la 3.7.5, y la 3.7.5 sustituye a la 3.7.4.
- Sin verificar físicamente.

## 2026-10-25 — App 2.3-wifi-dev4: HTTP permitido solo hacia el AP del reloj
- **Prueba de campo con la 3.7.5-rc4:** el reloj encendió el AP y Android se conectó, pero la descarga falló con «Cleartext HTTP traffic to 192.168.4.1 not permitted».
- **Cambio:** `network_security_config` permite HTTP sin cifrar únicamente a `192.168.4.1`, que es el AP local del reloj. El acceso va con un token de sesión recibido por BLE autenticado y con verificación SHA-256. El resto del tráfico sigue siendo solo HTTPS.

## 2026-10-25 — CHEST 3.7.5-rc5: velocidad de la descarga por Wi-Fi
- **Medido con rc4 + app dev4:** la descarga por Wi-Fi funciona de extremo a extremo. Un entrenamiento de 1,6 MB tarda unos 15 s (unos 110 KB/s).
- **rc5:** mientras el AP está encendido, el BLE deja de enviar telemetría y pide un intervalo de conexión largo (100–150 ms, latencia 4) para dejarle la radio al Wi-Fi. Al apagarse el Wi-Fi, por cualquier motivo, vuelve al intervalo normal. El BLE sigue conectado para el control y como respaldo.
- ESP-NOW (la espalda) no se ha tocado: para que deje de transmitir habría que cambiar el firmware de la espalda.
- Sin verificar físicamente.
- **Medido en campo con rc5 + app dev4:** 1,6 MB en unos 6 s (unos 270 KB/s), unas 2,5 veces más rápido que la rc4. Sigue sin verificarse: 10 minutos con NTRIP en RTK FIX, una grabación corta y el regreso de la telemetría tras el Wi-Fi.
- **Pruebas físicas de la rc5 (2026-10-25):**
  - Prueba 1, telemetría y pantalla después de la descarga por Wi-Fi: **OK**.
  - Prueba 2, 10 minutos con NTRIP en RTK FIX: **PENDIENTE**. No se puede conseguir FIX hasta que llegue la antena L1/L2; la actual es L1/L5.
  - Prueba 3, grabación en campo y descarga por Wi-Fi: **PENDIENTE**, se hará en la prueba de campo.
  - La rc5 queda como versión de trabajo. El BIN sigue marcado como UNVERIFIED y no se declara apto para OTA.

## 2026-10-25 — App 2.3-wifi-dev5: Inicio con las baterías de las tres unidades
- **Fila 1:**
  - **Pecho:** batería del reloj, en % (o V si no hay %).
  - **Espalda:** tensión de batería de la espalda (`backBatteryMv`) si su estado es válido.
  - **Cincha:** conectada o apagada.
- **Fila 2:** NTRIP · SD · GNSS.
- **Colores:** rojo = apagado o sin enlace; naranja = batería baja (pecho ≤ 20 %, espalda < 3,60 V); verde = bien.
- La cincha **no envía su batería** (no está en la telemetría del pecho), así que no se muestra ninguna cifra: no se inventan datos. Para mostrarla habrá que añadirla al firmware de la cincha y del pecho.
- **dev6:** todas las unidades se muestran en %.
  - **Espalda:** solo envía la tensión, así que el % se **estima** con la curva de descarga típica de una celda Li-ion (interpolada, ±10 %). Naranja si es ≤ 20 %.
  - **Cincha:** muestra «— %» mientras esté conectada, porque su batería no llega al pecho. Para enviarla hace falta un cambio de firmware en la cincha y en la espalda (la cincha → la espalda → el pecho, por ESP-NOW), en el pecho y en la app. El firmware de la cincha no está en el repositorio.

## 2026-10-25 — BACK 3.8.1: la espalda envía la tensión de su batería
- Placa confirmada por foto: Heltec HTIT-WSL_V3, rev. 3.2.
- La 3.8.0 enviaba `back_batt_mv = 0` (desconocido). La 3.8.1 mide la tensión (GPIO1, con ADC_Ctrl en GPIO37 y polaridad detectada) y la envía. El pecho y la app no cambian, y la app muestra el % estimado.
- La placa no tiene señal de estado de carga.
- Pruebas en ordenador: 23 casos y 159 comprobaciones OK. Sin verificar en la espalda real.
- Detalle en `firmware/back/V3_8_0/README.md`.

## 2026-10-25 — BACK 3.8.2: modo carga
- Petición del usuario: al cargar con el cargador de pared, apagar todo para que solo se cargue la batería, manteniendo la opción de actualizar.
- **Entrada:** USER 8 s, o subida continua de la tensión.
- **Qué apaga:** radio, ZED (Vext) y CPU a 80 MHz. El USB serie sigue activo para AVO Update.
- **Salida:** USER, o caída de la tensión.
- Detalle en `firmware/back/V3_8_0/README.md`. Pruebas en ordenador OK. Sin verificar en la placa.
- **Prueba física de BACK 3.8.2 (2026-10-25):**
  - Lectura de batería: **OK**. Marca 3689–3695 mV con todo encendido y el USB conectado, y 3714 mV en modo carga. Está pendiente compararla con un multímetro.
  - Modo carga con USER 8 s: **OK**. Se ha comprobado el mensaje y que se apagan la radio y el enlace.
  - **El ZED sigue encendido:** su 3V3 está cableado al 3V3 de la Heltec, que no se puede cortar. Hay que pasarlo al pin Ve (Vext, GPIO36).
  - Con el cargador puesto y todo funcionando, la tensión se mantiene estable, lo que confirma que no carga mientras funciona.

## 2026-10-25 — App 2.3-wifi-dev7: diagnóstico de bloqueos
- **Problema:** «AVO Performance Horse no responde» al abrir el análisis de un entrenamiento desde el listado. Era un entrenamiento de 5:25, casi sin movimiento.
- **Revisión del código, sin encontrar todavía la causa:**
  - la carga del análisis, los insights y el motor ya van fuera del hilo principal;
  - el mapa ya agrupa el recorrido en unos 150 tramos.
- **Diagnóstico añadido:** un vigilante del hilo principal. Si la interfaz se queda bloqueada más de 2 s, escribe en «Registro de la app» (etiqueta BLOQUEO) las funciones donde estaba parado. No cambia ninguna otra funcionalidad.

## 2026-10-25 — AVO GNSS PRO: BACK 3.9.0 · CHEST 3.7.6-rc1 · App 2.3-wifi-dev8
- Petición del usuario: dejar preparada la máxima precisión con el hardware actual antes de que llegue la antena L1/L2.
- **BACK 3.9.0 (espalda):**
  - activa UBX-NAV-SAT y UBX-NAV-SIG a 1 Hz con su propio VALSET; si el receptor lo rechaza, el resto sigue igual;
  - resume la calidad: satélites usados y seguidos; señales usadas, con fase de portadora y corregidas; señales de 2.ª banda (L2/E5b/B2); C/N₀ media, mínima y máxima; señales débiles;
  - registra el RTK FIX: tiempo en FIX y en FLOAT, pérdidas de FIX y tiempo hasta el primer FIX;
  - todo va al pecho en `BackStatus` v3, añadido al final (un pecho anterior lo sigue leyendo como v2);
  - búfer UBX ampliado a 2,1 KB;
  - monitor: líneas `CALIDAD` y `RTK`, y aviso «ANTENA SOLO L1»;
  - pruebas en ordenador: 27 casos y 199 comprobaciones (ZED simulado con y sin L2, y con pérdidas de FIX).
- **CHEST 3.7.6-rc1 (pecho):**
  - sobre la 3.7.5-rc5 (RAM y Wi-Fi);
  - decodifica `BackStatus` v3 (el mismo `avo_payloads` que la espalda);
  - **telemetría BLE v3** (116 B, añadida al final): calidad, FIX, sAcc y PDOP;
  - no cambian el RAW, la grabación, la trama ESP-NOW ni la OTA. NAV-PVT completo, con sAcc, ya se grababa.
- **App 2.3-wifi-dev8:**
  - **tarjeta «Calidad GNSS»** en Inicio, con el diagnóstico de por qué no hay FIX: antena solo L1, sin correcciones usadas, señal débil o convergiendo;
  - **mountpoints de reserva** en Ajustes → NTRIP, con cambio automático tras 3 fallos seguidos o 30 s sin datos. Nunca se mezclan dos fuentes;
  - Inicio muestra el mountpoint activo;
  - registro de las pérdidas de FIX y de la antena sin L2;
  - prueba con un vector generado por el codificador del firmware.
- Nada de esto mejora la precisión por sí mismo: sirve para diagnosticar y para tener una fuente de reserva. La precisión real depende de la antena L1/L2 y del cielo despejado. Sin verificar físicamente.

## 2026-10-25 — Cincha: GIRTH 0.1.0 (ESP32-C6) · BACK 3.10.0 · AVO Update 2.3.0
- **GIRTH 0.1.0** (`firmware/girth/V0_1_0`, placa ESP32-C6 de formato XIAO). Primera prueba, **solo el enlace, sin IMU conectado**: envía «IMUs: 0» y ninguna muestra. No se simula nada.
  - Usa ESP-NOW por el canal 1 con la espalda, con el protocolo `avo_girth_link` (biblioteca compartida con la espalda y magic propio 0xA5 0x47).
  - Se empareja con HELLO por difusión hasta recibir WELCOME, y guarda la MAC de la espalda en la NVS.
  - Envía STATUS cada segundo; la espalda responde con PING.
  - LED: parpadeo rápido mientras busca, destello cada 2 s cuando está enlazada. BOOT 5 s olvida la espalda.
  - Monitor serie: `[AVO CINCHA]`.
- **BACK 3.10.0:**
  - `GirthHub` acepta la primera cincha que saluda (MAC guardada en la NVS). Para cambiarla hay que abrir la ventana de emparejamiento (USER 3 s);
  - cuenta paquetes, pérdidas (huecos de secuencia) y RSSI;
  - reenvía los lotes de IMU al pecho como `IMU_SAMPLE`, con un máximo de 10 muestras por paquete;
  - rellena `girth_connected`, `girth_rssi`, `girth_pkts` y `girth_lost` en el STATUS que ya existía, así que pecho y app ven «Cincha: Conectada» sin cambiar nada;
  - pruebas en ordenador: 30 casos y 227 comprobaciones.
- **AVO Update 2.3.0:** nueva ruta de instalación **solo para ESP32-C6 con la marca AVO-GIRTH**, a partir de la imagen completa (`*_COMPLETO.bin`):
  - escribe bootloader, tabla, otadata y app, y verifica cada zona con el MD5 del chip;
  - **no escribe la NVS**;
  - el pecho y la espalda (ESP32-S3) siguen por la ruta de solo slot OTA, sin cambios.
  - Constantes del C6 (LP_WDT) tomadas de esptool (`targets/esp32c6.py`).
- Nada de esto está verificado en hardware.
- Imagen completa de la cincha: el core la rellena hasta los 4 MB; el CI la recorta al final de la app (comprobando que el resto es 0xFF), que es lo que espera AVO Update. Resultado: 1 033 344 B, con la app de 967 808 B (73 % de ota_0).
- AVO Update 2.3.1: «Comprobar módulo» con un firmware de la cincha seleccionado solo identifica el chip ESP32-C6 y su seguridad. Antes aplicaba la comprobación del ESP32-S3 y daba el error «no es un ESP32-S3 (chip id 13)».

## 2026-10-25 — BACK 3.10.1 · App 2.3-wifi-dev9
- **Medido en campo con BACK 3.9/3.10:** «Mensajes de calidad: rechazados por el receptor». El ZED respondió NAK al VALSET conjunto de NAV-SAT y NAV-SIG.
- **3.10.1:**
  - tras un NAK, prueba NAV-SAT solo y después NAV-SIG solo; si los dos se rechazan, repite el ciclo a los 30 s, hasta 2 veces;
  - estados nuevos: 4 = solo NAV-SAT, 5 = solo NAV-SIG, 6 = reintento;
  - el monitor muestra la línea `RECEPTOR: firmware …`, sacada del FWVER de MON-VER, para saber si el ZED tiene un firmware HPG antiguo;
  - prueba en ordenador con un receptor sin NAV-SIG: 31 casos y 230 comprobaciones.
- **App dev9:** muestra esos estados y los satélites usados/seguidos aunque falte NAV-SIG.
- **Observado en la misma captura:** la cincha aparece conectada a través de la espalda (casilla «— %» en gris).

## 2026-10-26 — Cincha: concepto de caja REV 0 y placa de probetas
- En `hardware/girth/REV0/`: imágenes del concepto (escena three.js `scene.html`) y `AVO_GIRTH_PROBETAS_REV0.stl`, generada con `probetas.py` en PETG para la Centauri Carbon.
- **Probetas:** cuna de la batería, BNO085 con 2 postes M2, ESP32-C6 con holguras de 0,10, 0,20 y 0,30, bobina y placa Qi, canal del reed e imanes Ø6 (a presión y deslizante).
- Medidas tomadas de los anuncios; la posición de los taladros del BNO085 es provisional.

## 2026-10-26 — Cincha REV 1 (CAD real, STEP + STL)
- `hardware/girth/REV1`: modelo CadQuery generado por CI (`build-girth-cad.yml`, que sube `out/`).
- **Cápsula** de 64 × 46 × 15,5 mm: base, tapa con logo, bandeja y tapón USB de TPU.
- **Soporte** de 84 × 60 mm para cinta de 50 mm, con 2 colas de milano, gancho elástico de seguridad y 2 imanes Ø6.
- Interferencias comprobadas en CAD: ninguna.
- Pendiente de imprimir y probar (antes, la placa de probetas).
- **REV 1.1:** la tapa tenía el labio interior suelto (2 sólidos). Ahora un puente lo une a la pared. El CI exige un único sólido por pieza y las 5 piezas lo cumplen.
- **REV 1.3:** se invierte el sentido del gancho, como pidió el usuario. La cápsula entra por el lado contrario a la pestaña y hace tope al final de las colas de milano. El gancho, con la rampa hacia la entrada y la cara recta hacia la pestaña, impide que vuelva atrás. El rebaje del fondo queda cerrado (y 12…19).
- **REV 1.4:**
  - las colas de milano se recortan con la silueta de la cápsula; ya no sobresalen;
  - holgura de 0,10 por lado y tope a 0,10;
  - costillas aplastables de 0,2 en los flancos (3 por lado) para eliminar el juego de impresión;
  - la cara del gancho queda a 0,10 de la pared del rebaje;
  - el control de interferencias del CI excluye esas costillas, que interfieren a propósito.

## 2026-10-26 — Cincha REV 2 (CAD fiel al concepto REV 0)
- **Petición del usuario:** que el CAD sea «como la imagen de referencia, lo más exacto posible y que encaje todo perfecto». Preguntó también para qué servían los salientes de las colas de milano: eran costillas aplastables (REV 1.4) para quitar el juego de impresión. En REV 2 se eliminan.
- **`hardware/girth/REV2/avo_girth_rev2.py`:**
  - base con fondo liso y una ranura de anclaje en cada extremo X;
  - aro rojo entre base y tapa;
  - tapa negra con alojamiento para un panel rojo con AVO / GIRTH en relieve y ventana del LED;
  - soporte con cerco a 0,12 mm, labio en −X y pestaña elástica con diente en +X;
  - tirador rojo pegado a la pestaña;
  - pasadores para cinta de 50 mm e imanes Ø6.
- **CI:** `build-girth-cad.yml` construye ahora REV 2 (REV 1 se conserva). Resultado: 8 piezas, 1 sólido cada una, sin interferencias.
- **Comprobación:** sección real de los STL por Y = 5 mm (labio y diente dentro de sus ranuras).
- Pendiente de imprimir y probar.

## 2026-10-26 — Cincha REV 3 (componentes reales y soporte de una pieza)
- **Petición del usuario:** ajustar todo a los componentes reales y hacer el soporte «compacto, fuerte, comercial y muy visual». Señaló que un poste del BNO estaba mal y que el soporte estaba mal resuelto.
- **Medidas:** se revisaron las fotos de los anuncios que mandó el usuario (BNO085 HanOaki, C6 diymore, Qi, LP403048, reed e imán).
- **Errores de REV 2 corregidos:**
  - los taladros del BNO estaban en diagonal; los reales están en el lado opuesto a los pines;
  - el USB-C quedaba hundido 3,3 mm y el cable no podía entrar.
- **`hardware/girth/REV3/avo_girth_rev3.py`:**
  - nueva distribución de la bandeja: C6 con tope en la pared y ventana inferior para los cables, BNO, placa Qi y pasos de cables;
  - cuna de batería cerrada;
  - canal para los hilos de la bobina;
  - reed desplazado;
  - soporte de una pieza de 88,4 × 58,4 mm con pasos de cinta cerrados;
  - el informe del CI indica dónde está cada interferencia.
- **CI:** construye ahora REV 3. Resultado: 8 piezas, 1 sólido cada una, sin interferencias.
- Medidas estimadas sobre foto marcadas (E) en el código. Pendiente de imprimir y probar.

## 2026-10-26 — Cincha REV 4 (cápsula estanca, objetivo IP67)
- **Petición del usuario:** caja «estanca completamente», con el USB dentro, sin agujero para el LED, IP67.
- **`hardware/girth/REV4/avo_girth_rev4.py`:**
  - sin ninguna abertura: fuera la ventana USB, la ventana del LED y el tapón;
  - C6 desplazado hacia dentro (tope en x = 26,8);
  - reborde en la base con ranura continua para una junta de TPU 85A (1,2 × 1,4 mm, 29 % de compresión fijada por el apoyo de la tapa);
  - faldón de la tapa sobre el reborde y aro rojo por fuera de la junta;
  - tornillos M2 desde abajo con junta tórica 2 × 1 bajo la cabeza;
  - columnas unidas a la pared;
  - la junta se exporta con su altura libre.
- **CI:** construye REV 4. Resultado: 8 piezas, 1 sólido cada una, sin interferencias.
- **Comprobación:** sección real de los STL por el eje del tornillo y por el lado +Y.
- **Pendiente:**
  - imprimir y hacer la prueba de inmersión; IP67 no está probado;
  - actualizar el firmware de la cincha por radio, porque el USB ya no es accesible sin abrir.

## 2026-10-26 — Cincha REV 5 (8 tornillos M3 y 4 + 4 imanes Ø5 × 1)
- **Petición del usuario:**
  - 4 imanes de neodimio finos y redondos para que la cápsula no se mueva del soporte; luego confirmó Ø5 × 1;
  - tornillos de cierre M3 «de 9 mm», en lugar de los M2 × 4 de su dibujo.
- **`hardware/girth/REV5/avo_girth_rev5.py`:**
  - la cápsula pasa a 70 × 48 × 15,5 mm;
  - 8 columnas M3 con avellanado para una junta tórica 3 × 1 bajo la cabeza, por dentro de la junta TPU;
  - 4 alojamientos para imanes Ø5 × 1 en la cápsula (piel de 0,3 mm) y 4 en el soporte;
  - interior redistribuido: BNO y C6 girados, Qi en el centro, reed en el centro del lado −Y;
  - soporte de 94,4 × 58,4 mm.
- **CI:** construye REV 5. Resultado: 8 piezas, 1 sólido cada una, sin interferencias.
- **Pendiente:**
  - comprobar que los imanes de la cápsula no activan el reed;
  - imprimir y hacer la prueba de inmersión; IP67 no está probado.
