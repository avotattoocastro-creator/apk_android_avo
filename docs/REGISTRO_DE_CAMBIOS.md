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

## 2026-10-31 — Cincha GIRTH 0.4.3 — las muestras de IMU declaran sus unidades
**Autor:** Claude · Rama `feature/girth-fw-0-4-0-bno085`
**Qué cambia:**
- el byte 15 de la cabecera IMU_SAMPLE («reserved» en avo_payloads.h, que la espalda conserva al reenviar) vale 1, que significa «unidades del BNO085»: acc y aceleración lineal Q8 m/s², giro Q9 rad/s, mag Q4 µT y cuaternión Q14;
- con 0 (cinchas anteriores o REV B), las apps siguen usando su escala nominal.
**Por qué:** la app de Windows dibujaba la IMU con la escala nominal del LSM6 (±8 g): 1 g del BNO085 (2511 LSB) salía como 0,61 g.
**No se ha tocado:** espalda, pecho y formato de la trama (mismo tamaño y mismos campos).
**Validación:** host 40/40 (la prueba comprueba que la espalda conserva el byte). CI pendiente. NO VERIFICADO en el hardware.

---

## 2026-10-31 — Cincha GIRTH 0.4.2 — PRUEBA FÍSICA de extremo a extremo: datos de la cincha en la sesión
**Autor:** Claude · Evidencia: foto de Windows Advanced Analysis V2 PRO, «Entrenamiento 31/10/2026 16:52», HORSE_001
- **PROBADO FÍSICAMENTE:** la gráfica «IMU cincha – aceleración vertical z» muestra la traza «Central» (imu_id 0) durante toda la sesión, con picos al mover la cincha (00:39–00:42). Cadena completa: BNO085 → cincha 0.4.2 → espalda 3.13.11 → pecho 3.7.6 → archivo → app de Windows.
- **Escala:** la app dibuja la IMU en LSB «sin calibrar» con una escala nominal. Con GIRTH 0.4.x, acc = Q8 m/s² (256 LSB = 1 m/s², 1 g ≈ 2511 LSB), giro = Q9 rad/s y mag = Q4 µT. Falta pasar estas unidades a la app y al motor de análisis.
- **Pendiente:**
  - cadencia con el caballo en marcha (en esta prueba la cincha se movió a mano);
  - lectura de fmt 1 (aceleración lineal y cuaternión) en la app y en el motor de análisis;
  - batería y reposo.

---

## 2026-10-31 — Cincha GIRTH 0.4.2 — PRUEBA FÍSICA: IMU y enlace con la espalda funcionando
**Autor:** Claude · Evidencia: monitor serie de la cincha (captura del usuario, 16:51)
- **Enlace PROBADO FÍSICAMENTE:**
  - la cincha se re-emparejó sola con la espalda AC:A7:04:06:C0:B4 (BACK 3.13.11);
  - estado CONFIRMADA con 40 PING recibidos;
  - la espalda confirma 1352 paquetes y **0 perdidos**;
  - RSSI −65/−66 dBm en la cincha y −60/−61 dBm en la espalda; antena interna.
- **IMU PROBADA FÍSICAMENTE:**
  - BNO085 en 0x4A, 124,8–125,9 Hz, 7656 muestras;
  - 0 perdidas en el sensor, 0 en la cola y 0 errores I²C;
  - periodo de 7977–7979 µs, estable;
  - 1376 lotes enviados, sin ninguno sin confirmar;
  - en reposo, |acc| ≈ 9,77 m/s² y aceleración lineal ≈ 0.
- **Pendiente:**
  - comprobar en una sesión del pecho que se guardan los IMU_SAMPLE (fmt 0 y fmt 1) y que la app los dibuja;
  - la precisión del giroscopio sale 0 en reposo (ver si sube al moverlo);
  - batería (divisor no montado) y reposo (contacto del pogo).

---

## 2026-10-31 — Cincha GIRTH 0.4.2 (XIAO ESP32-C6) — re-emparejamiento automático, monitor sin bloqueo, periodo estable
**Autor:** Claude · Rama `feature/girth-fw-0-4-0-bno085`
**Prueba física de 0.4.1 (monitor del usuario):**
- IMU estable a ~125 Hz, sin pérdidas del sensor.
- La cincha seguía emparejada con la espalda antigua CD:24 (0 ACK), así que la sesión del pecho del 31/10 16:37 salió sin datos de cincha.
- Se perdieron 12 046 muestras de una vez en la cola, porque el monitor serie bloqueaba el bucle.
- El periodo estimado era inestable.
**Qué cambia:**
- el monitor serie no bloquea;
- el periodo de los lotes es la media desde el arranque;
- si la espalda guardada no da ACK en 30 s y otra espalda acepta a la cincha (WELCOME), la cincha pasa a esa espalda.
**No se ha tocado:** espalda, pecho, app, particiones, actualización.
**CI:** run 41215973513 (éxito). Enlace y datos en la sesión: NO VERIFICADO.

---

## 2026-10-31 — Cincha GIRTH 0.4.1 (XIAO ESP32-C6) — periodo real en los lotes; primera prueba física de la IMU
**Autor:** Claude · Rama `feature/girth-fw-0-4-0-bno085`
**Prueba física de 0.4.0 (monitor serie del usuario):**
- BNO085 en 0x4A, SH-2 3.2.13; ~125 Hz sin pérdidas ni errores I²C; |acc| ≈ 9,84 m/s² en reposo. **IMU PROBADA FÍSICAMENTE.**
- Enlace: la espalda guardada AC:A7:04:06:CD:24 no da ACK; responde otra espalda, AC:A7:04:06:C0:B4, que la cincha ignora porque no es la guardada. Hay que emparejar de nuevo (BOOT 5 s en la cincha). Enlace NO VERIFICADO todavía.
**Qué cambia:** los lotes usan el periodo real sacado de las marcas de tiempo (0.4.0 escribía 10 000 µs, pero el BNO da ~8 ms); se muestran los periodos que confirma el BNO; sin aviso de ISR al arrancar.
**No se ha tocado:** espalda, pecho, app, particiones, actualización.
**CI:** run 41215234946 (éxito). Enlace y datos en la sesión del pecho: NO VERIFICADO.

---

## 2026-10-31 — Cincha GIRTH 0.4.0 (XIAO ESP32-C6) — BNO085 por SH-2, antena interna, enlace confirmado
**Autor:** Claude · Rama `feature/girth-fw-0-4-0-bno085` (desde `feature/avo-wifi-sync`) · **Commits:** `066ac4c`, `efc9d31` · **CI:** run 41212893621 (éxito)
**Qué cambia:** firmware nuevo de la cincha sobre GIRTH 0.1.0 (el código de 0.2.0 no está en el repositorio):
- controlador SHTP/SH-2 propio para el BNO085 por I²C, en una tarea propia guiada por INT. A 100 Hz da
  acelerómetro, giroscopio, magnetómetro, aceleración lineal y game rotation vector. Solo da el arranque por bueno
  si el BNO responde a la petición de identificación y entrega muestras, y si falla reintenta solo;
- antena interna (0.2.0 seleccionaba la externa sin antena);
- lotes fmt 0 (los que ya existen) y fmt 1 (nuevo: aceleración lineal y cuaternión);
- enlace confirmado por el PING de la espalda;
- batería: «no medida» fuera de 3,0–4,5 V;
- reposo por GPIO6, desactivado por defecto.
**Por qué:** 0.2.0 daba «IMU NO RESPONDE», «muestras=0», «envios ok=37 fallo=74» (la espalda nunca dio ACK de radio) y la batería a 0 o 512 mV (divisor no montado). Causas en `firmware/girth/V0_4_0/README.md`.
**Archivos:** `firmware/girth/V0_4_0/**`, `.github/workflows/build-girth-v040.yml`.
**No se ha tocado:** espalda, pecho, app, particiones, firma ni actualización, `main`, `develop/avo-performance-horse`.
**Validación:** CI (compilación ESP32-C6, imagen y 40/40 pruebas de host, simulación). **NO VERIFICADO** en el hardware.
**Pendiente:** prueba en el hardware (BNO085, enlace con BACK ≥ 3.10.0, batería con divisor), lectura de fmt 1 en la app y en el motor de análisis, consumo y reposo con el contacto del pogo.

---

## 2026-10-30 — Cincha (CAD) REV 5.9 — conector pogo en lugar del reed, sin Qi, cápsula 70 × 51 × 13,8
**Autor:** Claude · Rama de propuesta `feature/girth-rev5-9-pogo`, fusionada en `feature/avo-wifi-sync` con el visto bueno del usuario
**Qué cambia:**
- El reed y sus 3 imanes se sustituyen por un conector magnético pogo de 3 pines: la hembra plana en la base (sellada con epoxi en una copa) y el macho con muelles en el soporte (atornillado por debajo, placa de 6,0 mm).
- Contactos: 1 = 5 V (solo base de carga), 2 = GND, 3 = detección. En el soporte un puente 2–3 sustituye al reed.
- Se quita la carga Qi (bobina, placa y alojamientos); la batería va a los pads BAT del XIAO.
- Cápsula 73 × 51 × 15,5 → 70 × 51 × 13,8: fondo 1,4, techo de la tapa 1,8, C6 y BNO 2 mm a −X, imanes en (±27,3, ±17,9). Tornillos M3 × 8.
- Bandeja: un solo paso para los hilos del pogo (+X) y salida de los cables de la batería en +X/−Y.
**Por qué:** petición del usuario (cambiar reed + imán por el conector pogo; carga por contactos; ajustar la cápsula a la batería).
**Archivos:** `hardware/girth/REV5/avo_girth_rev5.py`, `hardware/girth/REV5/README.md`, `hardware/girth/REV5/out/*` (CI).
**No se ha tocado:** firmware, app, comunicaciones del pecho.
**CI:** run 41048766609 (éxito, SHA `9af8785`).
**Validación:** CAD por CI sin interferencias y 1 sólido por pieza; voladizos revisados. **NO VERIFICADO** físicamente. Medidas del conector **estimadas** (foto del vendedor): confirmar con calibre antes de imprimir.
**Pendiente:** medir el conector real; prueba impresa; sellado con epoxi y prueba de inmersión; diseñar la base de carga si se pide.

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
- **REV 5, ajuste:**
  - BNO085 centrado, a petición del usuario, para alejar su magnetómetro de los imanes; la placa Qi pasa al extremo −X;
  - el imán del reed en el soporte pasa a 1 × Ø5 × 1: en el BNO da ~180 µT, frente a ~1000 µT con los 2 × Ø6 × 2 (estimación de dipolo);
  - se recomienda alternar la polaridad de los imanes de las esquinas en diagonal: ~40 µT en el BNO en lugar de ~250 µT;
  - CI sin interferencias.
- **REV 5, sujeción del C6:**
  - el usuario preguntó cómo se sujetaba el C6 sin paredes en los 4 costados;
  - ahora lleva un marco en los 4 lados a ras del PCB (holgura 0,15) y un tope de la tapa que aprieta el USB-C desde arriba;
  - CI sin interferencias.

## 2026-10-26 — Cincha REV 5.1 (ajustes tras imprimir base y bandeja)
- **Prueba física del usuario** con los componentes reales sobre la base y la bandeja impresas.
- **Placa Qi:**
  - la placa real mide 18 en X y 15 en Y (el modelo la tenía girada);
  - el marco queda solo en los lados Y, con topes en las esquinas;
  - los lados X quedan abiertos: hilos de la bobina en −X y salidas WOUT/BAT en +X;
  - pasa a x = −18 y el paso de los hilos de la bobina va a (−29, −3).
- **BNO085:**
  - largo 25,2 mm y taladros a 3,0 mm de los bordes, medidos sobre la foto (pendiente de calibre);
  - topes de los extremos a 0,15 mm y pared nueva en el lado −X.
- **ESP32-C6:** 17,8 × 21; el marco queda a 0,1 mm por lado.
- **Reed:** el canal es 1 mm más largo por cada extremo.
- **Tapa:** los postes de la placa Qi se reubican (fuera del hueco de la antena y separados de la pared del BNO).
- **CI:** sin interferencias, 1 sólido por pieza.
- **REV 5.1, paso de los hilos de la bobina:** hueco de 6 mm a toda altura en la pared −X de la cuna de la batería (y −6,5…−0,5), donde el usuario lo marcó. Queda sobre el canal del fondo y bajo el paso de la bandeja. CI sin interferencias.

## 2026-10-27 — Cincha REV 5.2 (tapa de una pieza)
- **Petición del usuario:** tapa de una sola pieza, imprimible boca abajo sin soportes, sin la lámina ni las letras.
- Se elimina el panel rojo y su alojamiento; la tapa queda con la cara superior lisa. Quedan 7 piezas (aro y tirador en rojo).
- CI: un sólido por pieza, sin interferencias. Se borran los STEP/STL antiguos del panel.

## 2026-10-27 — Cincha REV 5.3 (nuevo receptor Qi)
- El usuario cambia el receptor Qi: misma placa de 15 × 18 mm, pero con bobina **redonda Ø25 mm**. La anterior era rectangular de 23 × 30.
- En la base, el alojamiento de la bobina pasa a ser circular, de Ø25,4 y 1,4 mm de profundidad, con 1,2 mm de fondo bajo la bobina. El canal de los hilos sale de su borde hacia −X.
- El espesor de la bobina es estimado (1,0 mm): pendiente de calibre.
- CI sin interferencias.

## 2026-10-28 — Cincha REV 5.8.1 (curvas y agujero en D)
- **Petición del usuario** (bocetos sobre su CAD): curvas en el cierre y en la zona de anclaje, por estética; orejas del soporte con la misma forma interior que el pasador.
- **Cambios:**
  - redondeos en el cierre (esquina superior, tirador, rincones y labio) y en los extremos del nervio de la tapa;
  - agujero en D en las orejas (Ø2,25 con plano a juego con el del pasador).
- **CI:** 1 sólido por pieza, sin interferencias; clic y barrido iguales que en la 5.8.

## 2026-10-28 — Cincha REV 5.8 (cierres de palanca con clic)
- **Petición del usuario** (con fotos de una caja de referencia de Printables):
  - un cierre en cada extremo, con bisagra y pasador impreso;
  - clic fuerte que no se suelte;
  - anclaje a ras de la cara superior de la tapa, sin soportes;
  - tirador para soltar;
  - llaves de distinto ancho para que la cápsula entre siempre en la misma posición;
  - quitar el labio y la pestaña, manteniendo los imanes.
- **Desarrollo:** en la rama `feature/girth-rev5-8-cierres`, con 4 rondas de imágenes. El usuario la aprobó y se fusionó a mano.
- **Piezas:**
  - **soporte:** orejas de bisagra en ±X, cerco completo con muescas de 10/5 mm, pasos de cinta separados (ledge 5,6), 105,7 mm de largo;
  - **base:** tacos de posición; sin las ranuras antiguas;
  - **tapa:** nervios del clic a ras de la cara superior;
  - **nuevas:** `cierre_x2` y `pasador_x2`.
- **Comprobaciones en el CI:**
  - 1 sólido por pieza y sin interferencias en posición cerrada;
  - barrido de apertura del cierre: libre de 6° a 60°; clic entre 1° y 5° (choque intencionado, informativo en `informe.json`).
- **Pendiente:** fuerza real del clic y del roce del pasador, en la prueba impresa.

## 2026-10-28 — Cincha REV 5.7.6 (imanes del soporte)
- A petición del usuario, los alojamientos de los imanes de sujeción del soporte pasan a 2 imanes apilados (2,05 mm de fondo; antes 1,05).
- Motivo: con 4 imanes por esquina en total, el reparto 2 + 2 sujeta más que 1 + 3 (estimación con un modelo de discos cargados a 0,35 mm de separación: 2 + 2 ≈ 2,0×, 1 + 3 ≈ 1,6×, respecto a 1 + 1). No se ha medido en físico.
- Solo cambia el soporte. CI sin interferencias.

## 2026-10-28 — Cincha REV 5.7.5 (imanes de la base)
- **Petición del usuario:** poder meter 2 o 3 imanes apilados en las esquinas de la base para tener más sujeción.
- **Cambio:**
  - alojamientos de 3,1 mm de fondo (antes 2,3, que ya admitían 2 imanes), con 0,3 mm de piel abajo;
  - recrecido de Ø7,6 en la zona marcada, desde el suelo interior (2,6) hasta z 3,4.
- **Alcance:** solo cambia la base. El soporte sigue con alojamientos de 1 imán (1,05 mm): en él los imanes entran por arriba, y un alojamiento más hondo los alejaría de la cápsula.

## 2026-10-28 — Cincha REV 5.7.4 (pestaña del C6)
- Petición del usuario tras la prueba impresa (el C6 no entraba): la pestaña superior del C6 sube 0,1 mm, con la cara inferior a 0,15 sobre el PCB (antes 0,05). El borde superior de la pestaña no cambia. Solo cambia la bandeja.

## 2026-10-28 — Cincha REV 5.7.3 (insertos de la tapa)
- Petición del usuario: el alojamiento de los insertos M3 de la tapa, 0,1 mm más grande. Pasa de Ø4,0 a Ø4,1 (5 mm de fondo, sin cambios). Solo cambia la tapa. CI sin interferencias.

## 2026-10-28 — Cincha REV 5.7.2 (soporte)
- **Origen:** el usuario modificó el soporte en su CAD (Shapr3D) y pasó los STL solo como referencia. Por comparación de secciones, la única diferencia eran 2 alojamientos más para imanes del reed. En la base solo había un bloque suelto (12 × 5,5 × 3) fuera de la pieza, que no se incorpora.
- **Soporte:**
  - 3 imanes del reed en fila a −5,1 / 0 / +5,1 mm (los laterales con 1,2 mm de fondo);
  - **tirador integrado** en un solo sólido con el soporte, a petición del usuario. Nervio de la pestaña a todo el largo del tirador y chaflán de 45° en el vuelo exterior, sin voladizo.
  - Se deja de exportar `tirador_rojo`.
- **CI:** 1 sólido por pieza, sin interferencias. Voladizos del soporte: solo las caras de bloqueo del labio/diente, como antes.
- **Pendiente:** comprobar en físico que los 3 imanes activan el reed y el campo que dejan en el BNO (fijo; calibrar con la cápsula montada).

## 2026-10-28 — Cincha: diagnóstico 0.2.2 → 0.2.4-diag y resultado con el BNO085 real
- **0.2.2:** cortos medidos con el BNO en reset; sonda I²C por software tolerante al estiramiento de reloj; SPI sin depender de INT.
- **0.2.3:** etiqueta correcta del resultado de la sonda (−1/0/1).
- **0.2.4:** INT excluido de la detección de cortos (en reset el BNO lo mantiene a 0 y aparecía unido a todo).
- **Resultado en el módulo del usuario (puentes resoldados uno a uno):** con VCC, GND, RST e INT conectados, las resistencias de la placa a VCC se ven en RST e INT, pero INT no baja nunca tras soltar RST: el BNO no arranca. Diagnóstico: placa BNO defectuosa o dañada; se sustituye. Pendiente de confirmar con un módulo nuevo.
- Los falsos «cortos» de 0.2.1 (SDA↔SCL) se explican por el nodo VCC del BNO sin chip operativo y por la reacción del bus; no había puentes de estaño.

## 2026-10-28 — Cincha: firmware de diagnóstico 0.2.1-diag (BNO085 «NO RESPONDE»)
- **Contexto:** con el firmware 0.2.0 (solo hay binario, sin fuente en el repositorio) el BNO085 no responde en 0x4A.
- **Revisión del binario 0.2.0 (desensamblado):** los pines coinciden con el esquema:
  - RST en GPIO1, PS0/PS1 en GPIO0 a LOW, INT en GPIO2, CS en GPIO21 a HIGH, ADD en GPIO22 a LOW;
  - `Wire.begin(23, 16)` a 400 kHz.
- **Otros hallazgos en el binario:**
  - pone GPIO14 en HIGH, es decir, selecciona la antena externa; sin antena en el U.FL da −96 dBm;
  - lee la batería en GPIO5 ×2; sin divisor marca 0 mV.
- **Nuevo firmware de diagnóstico:** `firmware/girth/DIAG_0_2_1` (workflow `build-girth-diag.yml`). Sin radio y sin tocar la NVS. Comprueba:
  - niveles de cada línea con pull-up/pull-down;
  - cortos entre líneas (INT no se fuerza);
  - que INT baje tras el reset;
  - búsqueda I²C a 100/400 kHz y con SDA/SCL intercambiados;
  - SPI si el I²C falla;
  - tensión en GPIO5.
  - Termina con un resumen de la causa probable.
- No se ha probado en hardware; lo instala el usuario con AVO Update y después vuelve a instalar su firmware normal.

## 2026-10-27 — Cincha REV 5.7.1 (corrección con la prueba impresa)
- **Origen:** en la foto del usuario, con el BNO y el C6 montados en la bandeja REV 5.7, los pines del BNO quedaban ~1,1 mm desplazados hacia el USB respecto a los pads D0–D6.
  - En la foto la fila de pines está centrada en la placa, con ~1,2 mm a cada extremo.
- **Bandeja y BNO:**
  - BNO_PIN_OFF pasa de 1,0 (estimado) a 0,0; el BNO y su hueco bajan 1,0 mm hacia la antena;
  - taladros reales: a 1,95 del borde −X y a 2,45 de los extremos.
- **Tapa:** se quitan los 2 tubos que apretaban el BNO, porque con los taladros reales chocarían con la pestaña −X.
- **CI:** sin interferencias.
- **Pendiente:** comprobar la alineación en una nueva impresión.

## 2026-10-27 — Cincha REV 5.7 (cama de la electrónica)
- **Petición del usuario:**
  - ajustar la cama a la unión BNO–C6;
  - pasar el paso de los cables de la batería al lado opuesto;
  - engrosar la cama y crear canales para los cables;
  - pines del C6 y del BNO al mismo nivel por arriba;
  - pestaña superior en el C6 y sujeción del BNO;
  - ranura abierta para los hilos de la bobina.
- **Cómo se hizo:** la propuesta se desarrolló en la rama `feature/girth-rev5-7-cama`, con imágenes previas. El usuario la aprobó («Perfecto») y se fusionó a mano en `feature/avo-wifi-sync`.
- **Bandeja:**
  - cama maciza a ras de los PCB;
  - BNO hundido (BNO_Z0 = 7,6) a ras del C6, con una ventana debajo;
  - pestañas superiores en el C6 (+X) y en el BNO (−X);
  - canales de 2,4 × 1,2;
  - paso de la batería en −X/+Y;
  - ranura de la bobina abierta hasta el borde;
  - Qi desplazada 1 mm hacia −X.
- **Base:** el hueco de la cuna para los cables de la batería pasa a −X/+Y (la batería se gira 180°).
- **Tapa:**
  - 2 tubos que aprietan el BNO;
  - postes apoyados en la cama;
  - un poste movido a (−3; −18,9).
- **Esquema de conexiones actualizado:**
  - puentes planos por arriba;
  - VCC/GND del BNO a los pads 3V3/GND de la cara inferior del XIAO (la columna derecha queda bajo la pestaña).
- **Comprobaciones:**
  - CI: 1 sólido por pieza y ninguna interferencia;
  - voladizos: solo las caras inferiores de las pestañas (0,45–0,6 mm).
- **Pendiente:** confirmar con calibre el largo del BNO y la posición de su fila de pines. No se ha probado en físico.

## 2026-10-27 — Cincha REV 5.6 (BNO085 pegado al ESP32-C6)
- **Petición del usuario:** colocar el ESP32 y el IMU con los puntos de soldadura pegados y las conexiones coincidentes.
- **Bandeja:** la posición del BNO085 se calcula a partir del C6 según la huella oficial de Seeed (paso 2,54, D0 en el extremo del USB, USB-C sobresale 1,5). Los 7 pines PS1…SCL quedan a la misma Y que D0…D6, con un hueco de 0,15 mm.
- **Tapa:** el poste de presión del C6 en el lado −X se separa 0,2 mm del BNO (interferencia de 0,033 mm³ en el CI).
- **Conexiones:**
  - PS0+PS1→D0, RST→D1, INT→D2, CS→D3, AD0→D4, SDA→D5, SCL→D6;
  - GND y VCC, con cable a GND y 3V3.
- **Firmware:** I²C por la matriz de GPIO, `Wire.begin(23, 16)`, dirección 0x4A. Todavía no implementado y no probado en hardware.
- **Medidas estimadas (pendientes de calibre):** desplazamiento de la fila de pines del BNO (1,0) y distancia de los pines al borde (1,3).
- **Esquema ampliado (ronda posterior):**
  - columnas I²C/SPI con los mismos 7 puentes;
  - vista lateral del puente;
  - reed a MTCK (GPIO6), divisor de la batería a MTDI (GPIO5) y antena externa.
- **Comprobaciones:** girar el XIAO 180° es peor (la otra columna solo tiene D7–D10 y la alimentación queda en orden inverso), así que se descarta.
- **CI:** sin interferencias.

## 2026-10-27 — Cincha REV 5.4 y 5.5 (paredes macizas, insertos M3, sin soportes)
- **Petición del usuario:**
  - colocar bien los STL para que desaparezcan los soportes;
  - que todo el perímetro sea macizo, sin voladizos;
  - insertos M3 en la tapa;
  - permiso para ampliar la cápsula si los imanes chocaban.
- **Pieza a pieza:**
  - **Base:** pared maciza de 3,6 mm en toda la altura (antes, reborde volado), chaflán inferior de 45°, capa de sacrificio de 0,3 mm sobre los avellanados y techo de las ranuras de anclaje a 45°.
  - **Tapa:** pared maciza de 4,95 mm hasta el techo, chaflán superior de 45°, 8 columnas Ø7 con alojamiento de inserto M3 (Ø4,0 × 5 mm, 1 mm de techo por encima).
  - **Soporte:** la pestaña baja hasta la cama por una ranura de la placa, se quita el canal inferior de la cinta y la placa se ensancha para que el redondeo del borde no quede bajo el cerco.
  - **Bandeja:** holgura de Ø7,4 alrededor de las columnas de la tapa; paso de los cables de la batería fuera del marco del C6.
  - **C6:** se desplaza 0,4 mm hacia −X.
- **Tamaño:** la cápsula pasa a 73 × 51 mm. Los tornillos, imanes y reed se definen ahora respecto al tamaño exterior. Los imanes de esquina quedan entre la cuna y la pared, sin voladizo.
- **Exportación:** cada STEP y STL sale orientado para imprimir (tapa y tirador boca abajo); `out/montaje/` guarda las piezas en posición de montaje.
- **Comprobaciones:**
  - CI: 1 sólido por pieza y ninguna interferencia;
  - análisis de voladizos sobre los STL: solo quedan los puentes de las capas de sacrificio y las caras de bloqueo del labio y del diente (0,7–0,9 mm).
- **Campo estimado en el BNO** (dipolo, polaridad alterna en diagonal): unos 35 µT de los 8 imanes de esquina; el imán de esquina más cercano al reed queda a 21,9 mm.

## 2026-10-28 — BACK 3.10.2 — ahorro de batería
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `2970e16` · **CI:** [40721458125](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40721458125) (éxito; artefacto `AVO-BACK-V3-10-2-HELTEC`)
**Qué cambia:**
- CPU de 240 a 160 MHz.
- La radio LoRa SX1262 (sin uso) se pone en sueño profundo al arrancar; antes se quedaba en espera (~0,6 mA).
- Potencia de envío ESP-NOW adaptativa (11 / 15 dBm / máximo) según el peor RSSI del pecho y la cincha: sube al instante,
  máximo 15 s tras cualquier fallo de envío o segundo sin paquetes, baja de nivel en nivel tras 10 s estables. Lógica en
  `lib/avo_core/src/avo_tx_power.*` con 4 pruebas nuevas (35 casos en total).
- Monitor serie: línea `AHORRO`.
**Por qué:** el usuario ve que la batería de la espalda (654060, 2000 mAh) baja rápido. Consumo estimado ~190–230 mA (≈ 8 h);
esta versión recorta ~13–16 mA (≈ +6–8 %). Más ahorro exigiría apagar el GPS o la escucha de radio, que necesita el RTK.
**Archivos:** `firmware/back/V3_8_0/AVO_BACK_V3_8_0/AVO_BACK_V3_8_0.ino`, `lib/avo_core/src/avo_tx_power.{h,cpp}`,
`lib/avo_core/src/avo_core.h`, `lib/avo_core/src/avo_version.h`, `test/test_espnow.cpp`, `README.md`,
`.github/workflows/build-back-v380.yml`.
**No se ha tocado:** protocolo con el pecho y la cincha, emparejamiento, RTK/ritmo GNSS, modo carga, lectura de batería.
**Validación:** IMPLEMENTADO · CI correcto (35 casos, compilación ESP32-S3, imagen con versión 3.10.2 y línea AHORRO) · **NO VERIFICADO** en la espalda.
**Pendiente:** medir la duración real (carga completa → apagado) y la corriente con polímetro; comparar la lectura de la
batería (`BATERIA` del monitor, 3,83 V el 28/10) con un polímetro para validar el divisor ×4,9.

## 2026-10-28 — BACK 3.10.3 — encendido/apagado con el reed del soporte (sueño profundo)
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `0daa8ab` · **CI:** [40766920246](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40766920246) (éxito; artefacto `AVO-BACK-V3-10-3-HELTEC`)
**Qué cambia:** el reed pasa de cortar la batería a ser una señal en GPIO7 (pull-up, a GND). Abierto 3 s → Vext cortado
(el ZED-F9P se alimenta de Vext), pines del ZED en alta impedancia, radio apagada, pines fijados y sueño profundo; se
despierta al cerrar el reed (ext0). Al arrancar con el reed abierto: 3 s para pulsar USER (modo taller) o se duerme.
Lógica en `lib/avo_core/src/avo_reed_gate.h` con 2 pruebas (37 casos en total). Monitor: línea `INTERRUPTOR`.
**Por qué:** el reed de 14 mm en serie con la batería se soldó por el pico de carga de los condensadores al cerrar. Por la
señal pasan microamperios. El usuario no quiere MOSFET y el botón KAN-9A no cabe sin rehacer la tapa.
**Cableado nuevo:** ver `firmware/back/V3_8_0/README.md` (V3.10.3). El ZED debe pasar del 3V3 fijo a Vext.
**No se ha tocado:** protocolo, emparejamiento, RTK, ahorro de la 3.10.2, modo carga, lectura de batería.
**Validación:** IMPLEMENTADO · CI correcto (37 casos, compilación ESP32-S3, imagen con 3.10.3 e INTERRUPTOR) · **NO VERIFICADO** en la espalda.
**Pendiente:** medir el consumo dormida (µA) y comprobar 0 V en el ZED con la cápsula fuera del soporte.

## 2026-10-28 — BACK 3.10.4 — arranque suave de Vext
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `2163073` · **CI:** [40777133489](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40777133489) (éxito; artefacto `AVO-BACK-V3-10-4-HELTEC`)
**Qué cambia:** Vext (alimentación del ZED desde la 3.10.3) se enciende con PWM creciente (~200 ms) en vez de golpe.
**Por qué:** el usuario pasó el VCC del ZED a Vext y la espalda quedó en bucle `rst:0x1 (POWERON)`: al encender Vext de golpe
el ZED cargaba sus condensadores desde el 3V3 en marcha y el ESP32-S3 se quedaba sin tensión. Error de la 3.10.3 (apagaba
Vext al arrancar y lo volvía a encender de golpe).
**Archivos:** `AVO_BACK_V3_8_0.ino`, `avo_version.h`, `README.md`, `build-back-v380.yml`.
**Validación:** IMPLEMENTADO · CI correcto · **NO VERIFICADO** en la espalda.
**Prueba física parcial (28/10/2026 23:29, monitor del usuario):** BACK 3.10.4 en la Heltec ACA70406C0B4 con el ZED en Vext:
arranca una sola vez (`rst:0x1 POWERON`, sin bucle), `INTERRUPTOR: reed CERRADO`, `AHORRO: CPU 160 MHz | LoRa dormida`,
ZED encontrado a los ~16 s (230400, UART2, HPG 1.51, perfil COMPLETO, 8 Hz). Pecho sin respuesta en esa prueba (reloj
apagado o lejos). Batería 3,60 V. Pendiente: dormir/despertar con el reed, 0 V en el ZED dormida, consumo dormida.

## 2026-10-28 — BACK 3.10.5 — prueba: ZED encendido 10 s después del arranque
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `998f5b8` · **CI:** [40780929468](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40780929468) (éxito)
**Qué cambia:** Vext (ZED) se enciende 10 s después de arrancar o despertar, con el arranque suave de la 3.10.4; el UART del
ZED se abre en ese momento y hasta entonces sus pines quedan como entradas.
**Por qué:** petición del usuario. Con el ZED en Ve conectado desde el arranque la espalda no arrancaba; conectando Ve a mano
con la placa en marcha funcionaba (monitor 23:29 con la 3.10.4).
**Validación:** IMPLEMENTADO · CI correcto · **NO VERIFICADO**. Es una prueba: el retardo se ajustará según el resultado.

## 2026-10-28 — BACK 3.10.6 — LED apagado al dormir, ZED a 1 s
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `381fdf9` · **CI:** [40782841947](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40782841947) (éxito)
**Qué cambia:** GPIO35 (RX del ZED y LED blanco) en LOW fijado durante el sueño; retardo de encendido del ZED 10 s → 1 s.
**Por qué:** con el ZED en 3V3 la espalda se dormía pero el LED quedaba encendido (el RX del ZED alimentado levanta la
línea). La 3.10.5 (ZED a los 10 s) no cambió el bucle `POWERON` con el ZED en Ve: el reinicio ocurre en el cargador de
arranque (`entry 0x403c9880`), antes del firmware → causa de hardware; propuesto condensador de 470–1000 µF entre 3V3 y GND.
**Validación:** IMPLEMENTADO · CI correcto · **NO VERIFICADO**.

## 2026-10-29 — BACK 3.10.7 — ZED en reposo por software (UBX-RXM-PMREQ + EXTINT)
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `248aeeb` · **CI:** [40787062302](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40787062302) (éxito)
**Qué cambia:** antes del sueño profundo, `UBX-RXM-PMREQ` (backup indefinido, force, despertar por EXTINT0); EXTINT del
ZED (pin INT de la URTK1.2) en GPIO6, HIGH fijado al dormir; pulso LOW de 20 ms al encender el ZED.
**Por qué:** el ZED en Vext provoca reinicios en el cargador de arranque (hardware) y el usuario no quiere añadir piezas.
Con el ZED en 3V3 la Heltec dormía pero el ZED seguía encendido (~70–85 mA, LEDs encendidos).
**Validación:** IMPLEMENTADO · CI correcto · **NO VERIFICADO** (consumo del ZED en reposo sin dato en el data sheet).

## 2026-10-29 — BACK 3.10.8 — el ZED despierta también por su RX (sin cable INT)
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `36dd147` · **CI:** [40788606165](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40788606165) (éxito)
**Qué cambia:** `UBX-RXM-PMREQ` con `wakeupSources` = uartrx + extint0 (0x28). Tras el último byte, GPIO35 pasa a LOW por
la matriz GPIO al instante y queda fijado (sin `ZED.end()`, que soltaría la línea); GPIO6 se fija en HIGH antes de la orden.
Al encender el ZED se mandan 8 bytes 0xFF y se esperan 100 ms. Si el UART no estaba abierto (cápsula fuera al arrancar),
se abre a 38400 para mandar la orden.
**Por qué:** prueba del usuario 29/10/2026 00:34 con la 3.10.7: Heltec despierta y enlazada, app «Sin GNSS», último dato
GNSS hace 198827 ms, espalda al 11 %; LED blanco y LEDs del ZED encendidos. El ZED entró en reposo y no volvió a salir.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.

## 2026-10-29 — BACK 3.10.9 — reed desactivado, como la 3.10.2
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `b91fa05` · **CI:** [40790873680](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40790873680) (éxito)
**Qué cambia:** `AVO_REED_SLEEP 0`: el reed se ignora y la espalda no se duerme (modo taller fijo). Sin más cambios
respecto a la 3.10.8 (ZED despertado al arrancar por INT y por RX).
**Por qué:** el usuario pide la 3.9.0 o la última antes del reed, pero que despierte al ZED. Con la 3.9.0 no había GPS: el
ZED seguía en el reposo de la 3.10.7, que solo despierta por EXTINT o quitando toda la corriente.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.

## 2026-10-29 — BACK 3.11.0 — ZED alimentado por un Pololu S7V8F3 con SHDN en GPIO6
**Autor:** Claude · Rama `feature/avo-wifi-sync` · **Commits:** `01f3fcf` · **CI:** [40794217810](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40794217810) (éxito)
**Qué cambia:** GPIO6 pasa de EXTINT del ZED a SHDN del regulador S7V8F3 (batería → 3,3 V del ZED): LOW al arrancar y al
dormir (fijado) y en modo carga, HIGH al encender el ZED. Sin pulso EXTINT. `AVO_REED_SLEEP 1` (vuelve el sueño con el reed).
La orden PMREQ se mantiene antes del corte (compatibilidad con el ZED en 3V3).
**Por qué:** el usuario pide un módulo que corte la corriente por GPIO. Con el ZED en Ve la Heltec entra en bucle de
arranque (pico de corriente en su 3V3) y con el ZED en 3V3 no se puede apagar. El S7V8F3 (Bricogeek PRO-0170) tiene su
propio regulador desde la batería y apagado por pin.
**Validación:** IMPLEMENTADO · **NO VERIFICADO** (módulo aún sin montar).
