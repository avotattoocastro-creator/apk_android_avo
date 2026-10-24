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
