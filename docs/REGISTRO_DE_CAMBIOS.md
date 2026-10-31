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

## 2026-10-31 — BACK 3.13.10 (Heltec) — diagnóstico de USB por umbrales en GPIO20
**Autor:** Claude · Rama `fix/back-3-13-10-usb-umbral` (desde `fix/back-3-13-9-usb-gps-off`) · **Commits:** pendiente · **CI:** pendiente
**Qué cambia:** USB por tensión en GPIO20 (ADC, mediana de 9, > 100 mV conectado / < 50 mV desconectado, histéresis,
confirmación de 2 s), GPIO7 (ADC1) medido como alternativa, línea `[USB]` cada segundo y motivo de cada transición.
`AVO_USB_AUTO_OFF 0`: **ningún apagado por USB** (ni en el bucle, ni al arrancar, ni al despertar); las transiciones se
registran como simulación. Se elimina la lectura digital de GPIO20 de la 3.13.9.
**Por qué:** petición del usuario; requisito de seguridad de no apagar el GPS con estos umbrales sin comprobarlos.
**Auditoría:** ADC2 compartido con la Wi-Fi (lecturas rechazadas = 0), GPIO20 = D+ del USB nativo (pad desactivado),
ADC impreciso por debajo de ~100 mV y lectura de ~170 mV con el pin suelto: umbrales de 100/50 mV no fiables. Propuesto
GPIO7 (ADC1) con el mismo divisor alimentado desde un punto con 5 V solo con USB.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**. Apagado por USB no validado (desactivado).

## 2026-10-31 — BACK 3.13.9 (Heltec) — GPS apagado con el USB conectado
**Autor:** Claude · Rama `fix/back-3-13-9-usb-gps-off` (desde `diag/back-3-13-8-pololu-libre`) · **Commits:** `0a48cfa` · **CI:** [41161727290](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41161727290) (éxito: pruebas de ordenador + imagen de 916 224 B)
**Qué cambia:** `zed_shdn()`: GPS encendido = GPIO34 en alta impedancia (pull-up del Pololu a VIN = 3V3), apagado =
GPIO34 OUTPUT LOW; nunca ALTO. USB confirmado con 8 lecturas seguidas en ALTO de GPIO20 → paro de GNSS/RTCM, GPIO34
LOW, TX a LOW, sueño profundo durante la carga; al retirarlo, GPIO34 libre, UART1 RX35/TX33 y recuperación de UBX y
NAV-PVT, con tiempos en el monitor. Modo carga 3.8.2: TX del ZED a LOW.
**Por qué:** petición del usuario; la 3.13.8 ha recuperado la comunicación GNSS (460800). Cableado nuevo: VIN del Pololu al 3V3.
**No se ha tocado:** UART (RX35/TX33), `ZedManager`, NAV-PVT, ESP-NOW, RTCM, brownout, umbrales de batería.
**Validación:** IMPLEMENTADO · COMPILADO / CI · **NO VERIFICADO**. **La detección del USB no es fiable** (GPIO20 0,16–0,17 V con USB):
mientras no se arregle el circuito el GPS no se apaga por USB. El apagado real de VOUT solo se dará por bueno midiéndolo.
**Pendiente:** señal física de USB a GPIO20; medir VOUT ≈ 0 V con USB; pruebas de las tres situaciones en la espalda.

## 2026-10-31 — BACK 3.13.8 DIAGNÓSTICO (Heltec) — Pololu siempre encendido
**Autor:** Claude · Rama `diag/back-3-13-8-pololu-libre` (desde `fix/back-3-13-8-gps-uart`) · **Commits:** `39ce718`, `90c26a0` · **CI:** [41160703337](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41160703337) (éxito: imagen de 915 776 B)
**Qué cambia:** `AVO_POLOLU_FREE 1`: todo el control de GPIO34 pasa por `zed_shdn()`/`zed_shdn_sleep()`; en esta
compilación GPIO34 se libera (`gpio_hold_dis`) y queda `INPUT` sin pulls, sin `digitalWrite` ni `gpio_hold_en`. El
`gpio_deep_sleep_hold_en()` global sigue para los demás pines (TX GPIO33, Vext, ADC, LoRa), no afecta a GPIO34 porque no
tiene hold propio. Binario y artefacto con nombre DIAG_POLOLU.
**Por qué:** prueba pedida por el usuario para descartar que el control de SHDN impida funcionar al ZED-F9P.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**. No es versión de ahorro: el GPS puede quedar encendido dormida o cargando.
La alimentación del GPS no se da por correcta sin medir VOUT del Pololu.

## 2026-10-31 — BACK 3.13.8 (Heltec) — GPS UART PIN FIX
**Autor:** Claude · Rama `fix/back-3-13-8-gps-uart` (desde `fix/back-3-13-7-gps`) · **Commits:** pendiente · **CI:** pendiente
**Qué cambia:** UART1 del ZED con **RX=GPIO35, TX=GPIO33** según el cableado confirmado (blanco = RX del ZED → GPIO33,
verde = TX del ZED → GPIO35, amarillo = SHDN del Pololu → GPIO34). GPIO35 solo entrada: no se escribe ni se fija al
dormir (se aparca GPIO33). USB solo por GPIO20 digital filtrado (sin ADC2, sin otros pines candidatos). Monitor con
`GNSS UART1`, `POLOLU: SHDN GPIO34`, `GNSS: bytes recibidos / UBX / NMEA / NAV-PVT / estado`.
**Por qué:** con RX=33 no llegaba ningún byte del ZED (UBX=0, NMEA=0). Petición del usuario con el cableado por colores.
**Archivos:** `firmware/back/V3_8_0/AVO_BACK_V3_8_0/AVO_BACK_V3_8_0.ino`, `lib/avo_core/src/avo_version.h`, `README.md`,
`docs/AUDITORIA_GNSS_3_9_0_vs_3_13_6.md` (sección 6), `.github/workflows/build-back-v380.yml`, este registro, `README.md`, `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`.
**No se ha tocado:** detector de brownout, corte por batería baja, sueño por USB, ESP-NOW, RTCM, configuración RTK, `ZedManager`.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**. GPS no recuperado hasta ver NAV-PVT en el dispositivo. USB por GPIO20:
sin resolver (0,16–0,17 V con USB conectado: la señal física no llega).
**Pendiente:** prueba en la espalda; si `UBX malos` alto, quitar el LED blanco de GPIO35.

## 2026-10-31 — BACK 3.13.7 (Heltec) — recuperación del GPS ZED-F9P
**Autor:** Claude · Rama `fix/back-3-13-7-gps` (desde `develop/avo-performance-horse`) · **Commits:** `f6b8ee3` · **CI:** [41157825892](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41157825892) (éxito: pruebas de ordenador + imagen ESP32-S3 de 915 840 B, 27 % de app0)
**Qué cambia:** se trae a esta rama la espalda 3.13.6 de `feature/avo-back-v4` y sobre ella: pines del ZED fijos
RX=GPIO33/TX=GPIO35 (sin intercambio automático), ciclo de corriente del ZED por GPIO34 al arrancar, escucha pasiva en
todos los baudios antes de cualquier orden y antes de la radio, ESP-NOW después del diagnóstico, sin UBX-RXM-PMREQ al
dormir, línea `GNSS:` en el monitor (B/s, UBX, NMEA, NAV-PVT, GPIO34 solicitado frente a tensión no medida).
**Por qué:** el GPS no responde desde las pruebas del 31/10 (UBX=0 NMEA=0, ni un byte). Petición del usuario: recuperar
el funcionamiento de la 3.9.0 sin perder las funciones de la 3.13.6. Auditoría: `firmware/back/V3_8_0/docs/AUDITORIA_GNSS_3_9_0_vs_3_13_6.md`.
**Archivos:** `firmware/back/V3_8_0/**`, `.github/workflows/build-back-v380.yml`, este registro, `README.md`, `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`.
**No se ha tocado:** detector de brownout, cargador, umbrales del corte por batería baja (3,30 / 3,45 V), protocolo con el pecho.
**Validación:** IMPLEMENTADO · COMPILADO / CI · **NO VERIFICADO**. El GPS no se da por recuperado hasta ver NAV-PVT en el monitor.
**Pendiente:** prueba en la espalda; si no hay bytes del ZED en ningún baudio, medir VOUT del Pololu, VIN, GND y TX del ZED → GPIO33.
Recomendado: 100 kΩ de SHDN a GND (GPIO34 queda por debajo de 3,3 V mientras el pin está suelto en el arranque).

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
