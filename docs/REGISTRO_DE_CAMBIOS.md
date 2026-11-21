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

## 2026-11-21 — Motor 2.0.0-dev27 · KB-1 1.25.0 — ECG de la cincha PROTOTIPO 0.5.0 en el análisis: V200, VHRmax, A9 y A11
**Autor:** Claude (tarea programada, paso 3 del informe «Motor AVO Equine: análisis completo de funciones») · **Rama:**
`claude/motor-ecg-v200` · **CI:** `build-equine-engine.yml` lanzado a mano en la rama (ver PR)
**Diagnóstico:** la cincha 0.5.0 manda **muestras de ECG** (no RR) como `IMU_SAMPLE fmt 2` (`imu_id 3`, unidades 2 = 0,1 µV,
51 muestras int24 por lote, 177 B; máximo 204 B + 16 B de cabecera = lote de 220 B). La espalda (`GirthHub`,
`decode_imu_header` «formato desconocido: cabecera válida») y el pecho (RAW literal antes de decodificar) lo reenvían y
lo guardan tal cual: **el `.avr` ya trae el ECG**. El motor dev26 lo descartaba como registro malo. Ruta con archivos y
líneas en `equine-intelligence/docs/algoritmos/15_ECG_V200.md` §1. **No cambia ningún contrato binario** ni firmware.
**Qué cambia (solo motor):**
- Ingestión del `fmt 2` (`Session::ecg`), desenrollado del reloj de 32 bits, periodo exacto 1953,125 µs y descarte de
  lotes repetidos por reintento de radio.
- `src/cardio/cardio.cpp` (AVO Cardio 1.0.0): detector anclado en S con rechazo de T y sin ceguera tras artefacto; RR con
  calidad; FC en épocas de 5 s en tiempo GNSS (mapa cincha → pecho → GNSS, `compose_girth_map` compartido con la IMU);
  fases CALENTAMIENTO / MAXIMA (> 185 lpm) / RECUPERACION_0_2MIN / TARDIA con puerta > 10 % de artefacto; V200 por
  `CRUCE_200_10S` (Poinsard 2026, método principal) y por `REGRESION_FC_VELOCIDAD` aparte, con el método como atributo;
  VHRmax; recuperación a 1, 2, 4, 5, 10 y 15 min; ectopia como `CANDIDATO_A_REVISAR` (RR ≥ 6 % más corto, rachas,
  recuento por fase). Bloque `cardio` en el JSON del análisis.
- Training Analytics: bloque `cardio` en el resumen de sesión; reglas `A9_PERDIDA_FORMA` (kb_change_threshold +
  kb_drift_down, TE por defecto del 3 % **NO VALIDADO**, mismo método y superficie), `A9_V200_SALTO` (VT2) y `A11_ECG`.
- KB-1 1.25.0: A9 y A11 pasan a IMPLEMENTADO; parámetros y pendientes anotados. Fixtures regeneradas (solo versión,
  hash de parámetros y el bloque `cardio` vacío).
**Archivos:** `equine-intelligence/{include/avo_eq/cardio.h, src/cardio/cardio.cpp, src/ingestion/ingestion.cpp,
src/synchronization/session_sync.cpp, src/core/engine.cpp, src/training/training.cpp, include/avo_eq/{types,engine,
knowledge,training,session_sync}.h, knowledge/base_cientifica.json, tests/test_cardio.cpp, tests/raw_writer.h,
docs/algoritmos/{12,14,15}_*.md, docs/FORMATO_RESULTADOS.md}`, `core/src/test/resources/equine/*_analysis.json`.
**No se ha tocado:** firmware (cincha, espalda, pecho), contratos binarios, apps, workflows, firmas, `Info.plist`, número de build.
**Validación:** pruebas locales 111/111 con ASan/UBSan (8 casos nuevos: el lote se codifica con el codificador real de la
cincha y pasa por avo_core → RAW → ingestión → motor; sensibilidad y VPP ≥ 99,5 % en señal sintética) ·
`check_fixtures.py` OK · CI: ver PR · **NO VERIFICADO** con ECG real ni con caballos.
**Pendiente:** sesión real con el PROTOTIPO (cincha 0.5.0, cápsula REV 5.10) y anotación manual de latidos en galope;
TE propio de V200 (≥ 3 pruebas); dibujar `cardio` en Android, Windows e iPad; CF1, WU3, FA y multiformes.

## 2026-11-21 — Espalda 3.15.0 · Pecho 3.7.11 · Android 2.16-fixdiag-dev1 — Diagnóstico de «no hay RTK FIX» (BackStatus v4)
**Autor:** Claude (petición del usuario, 21/11 00:47: «añade todas las lecturas necesarias hasta en la apk hasta que
consigamos averiguar por qué no llega fix; una vez solucionado simplificamos datos en el apk») · **Rama:**
`claude/gnss-diagnostico-fix` · **CI:** ver PR
**Qué cambia:**
- **Espalda 3.15.0:** UBX-MON-RF cada 5 s (antena, alimentación, interferencias, AGC y ruido por banda); familias RTCM en
  las correcciones y las que usa el receptor (RXM-RTCM); estación base (1005/1006) y su distancia; modelo dinámico y
  constelaciones. Todo en **`BackStatus v4` (130 B, añadido al final de la v3)** y en el monitor serie.
- **Pecho 3.7.11:** los campos v4 en el texto `DIAG_GET` (búfer estático de 2048 B). Nada más cambia.
- **Android 2.16-fixdiag-dev1 (vc 50):** tarjeta «¿Por qué no hay RTK FIX? (diagnóstico)» en Inicio con causas ordenadas
  (bloquea / aviso / info) y todos los datos. Núcleo `GnssFixDiag` con pruebas JVM.
- **Workflows (avisado al usuario):** `build-back-v380.yml` y `build-chest-v377-despertar.yml` cambian versión, nombres de
  archivo y artefactos (`AVO-BACK-V3-15-0-HELTEC`, `AVO-CHEST-V3-7-11-DIAG-FIX-UNVERIFIED`) y añaden el paso 3.7.11.
- iPad y Windows no leen `DIAG_GET`: sin cambios.
- Contrato: `docs/DIAGNOSTICO_FIX_RTK.md` (vector compartido de los 22 bytes).
**Validación:** pruebas de host de la espalda 59/59 y del pecho en local · CI: ver PR · **NO VERIFICADO** en hardware.
**Pendiente:** prueba de campo; cuando se sepa la causa, simplificar la tarjeta de la app.

## 2026-11-20 — Integración (23:38): PR #112, #113, #114 y #115 en `develop`
**Autor:** Claude (chat integrador, petición del usuario 20/11 23:38) · **Orden:** por llegada, de uno en uno, con *merge commit*.
- **#112** motor 2.0.0-dev24 / KB-1 1.22.0 (sin conflictos).
- **#113** espalda PROTOTIPO 3.14.4 → 3.14.7 + Android 2.15-gnss-dev2 (vc 49). Se trajo `develop` y se conservaron las dos partes
  en `README.md` y en este registro. CI en la rama: espalda 3.14.7 44825167399 ✅, Android dev2 44820546249 ✅.
- **#114** motor dev25 / KB-1 1.23.0 y **#115** motor dev26 / KB-1 1.24.0 (encadenados). Mismo tratamiento en `README.md` y registro;
  motor con su CI de la rama ✅ (Linux, Windows y Android ×3 ABI).
**Validación:** COMPILADO / CI · **NO VERIFICADO** en hardware ni con caballos reales.

---

## 2026-11-20 — Espalda PROTOTIPO 3.14.7 — NAV-SIG se reactiva o se sondea si la salida periódica se para
**Autor:** Claude · **Rama:** `claude/gnss-calidad-rtcm-back-3-14-4` (PR #113) · **CI:** ver PR
**Qué se vio (22:56):**
- Cadena RTCM completa a ~1,3 kB/s, con 5,5 msg/s usados.
- NAV-SIG «activados, pero no llegan (último hace 144 s)», con la petición repetida 3 o más veces y todas aceptadas por el receptor.
- Llega al arrancar y se para con las correcciones en marcha, mientras NAV-PVT sigue.
**Lectura:** con 13 tramas UBX/s completas (8 NAV-PVT + RXM-RTCM) y 0 tramas malas, no es pérdida en el cable ni en la espalda. Es el receptor, que deja de generar el mensaje periódico. El pico del 101 % de MON-COMMS puede venir del arranque a 38 400 con la línea saturada de NMEA. Repetir el mismo VALSET no cambia nada en el receptor.
**Qué cambia:**
- Primera pérdida (10 s): NAV-SIG se **apaga y se vuelve a encender**, para reiniciar el mensaje periódico.
- Segunda pérdida seguida: la espalda **sondea NAV-SIG una vez por segundo** (petición de 8 B, respuesta inmediata), sin depender de la salida periódica.
- Salida RTCM3 del receptor apagada en el puerto de la espalda, en RAM: la espalda nunca la usa.
- Monitor: `NAV-SIG apagado/encendido N | sondeo NAV-SIG ACTIVO/no (peticiones)`.
- Pruebas de host: 55 casos y 542 comprobaciones.
  - Un ZED simulado con la salida periódica atascada se recupera, unas veces con apagar y encender y otras con el sondeo.
  - Las posiciones no se interrumpen.
**Validación:** IMPLEMENTADO · CI ver PR · **NO VERIFICADO**.

## 2026-11-20 — Espalda PROTOTIPO 3.14.6 — Solo NAV-SIG (NAV-SAT apagado): el búfer de salida del receptor llegaba al 101 %
**Autor:** Claude · **Rama:** `claude/gnss-calidad-rtcm-back-3-14-4` (PR #113) · **CI:** ver PR
**Qué se vio (monitor de AVO Update, 22:37–22:40, espalda 3.14.5):**
- **Arranque:** el ZED sale a 38 400 (velocidad de fábrica) y tarda más de 2 s en hablar. La primera vuelta de escucha no lo oye. En la segunda vuelta llena la línea: 3 825 B/s de los 3 840 que caben, con ~70 frases NMEA por segundo de su configuración guardada.
  - Corrección al informe: no estaba a 460 800. Los bytes sin tramas a 230 400/460 800 eran su señal de 38 400 leída a otra velocidad.
- **En marcha:**
  - ZED en **UART2**, 230 400 baudios, firmware **HPG 1.51**.
  - NAV-SAT y NAV-SIG llegando en ese momento, con 0 UBX malos y 0 desbordes de la FIFO.
  - Calidad: 25/31 satélites, 50 señales, 0 con fase y C/N₀ media 33 dBHz.
- **MON-COMMS:** búfer TX del receptor con **pico del 101 %**. El receptor llegó a descartar salida.
- **Modo carga por USB:** a los 23 s la espalda detecta el USB (GPIO20 = 175 mV) y entra en modo carga, con el GPS apagado. Con el cable puesto solo se observan unos 20 s.
**Qué cambia:**
- Mensajes de calidad: solo **NAV-SIG** a 1 Hz.
  - NAV-SAT se **apaga** en el mismo VALSET, aunque la configuración guardada del receptor lo tuviera activado.
  - Los satélites seguidos y usados se cuentan con NAV-SIG (satélites distintos entre sus señales).
  - La ráfaga de 1 Hz baja de ~1,3 KB a ~0,9 KB con 50 señales.
  - NAV-SAT solo queda como respaldo si el receptor rechaza NAV-SIG (estado 4).
- La vigilancia mira solo el mensaje que debe llegar.
- Monitor: «max en marcha» de MON-COMMS (peor uso del búfer TX desde que la espalda configura el receptor), separado del pico desde el arranque, que incluye la fase saturada a 38 400.
- `BackStatus` sin cambios de formato. Pruebas de host: 52 casos y 527 comprobaciones.
**Validación:** IMPLEMENTADO · CI ver PR · **NO VERIFICADO**.

## 2026-11-20 — Android 2.15-gnss-dev2 (vc 49) — «No usadas por el receptor» deja de presentarse como pérdida
**Autor:** Claude · **Rama:** `claude/gnss-calidad-rtcm-back-3-14-4` (PR #113)
**Qué se vio (usuario, 22:24, espalda 3.14.5):**
- Pecho y espalda enlazados.
- Cadena RTCM completa: 1,3–1,6 kB/s en todas las etapas, 4,5 msg/s usados y solución DGNSS.
- UBX a 13,1 tramas/s a 230 400.
- NAV-SAT/SIG «activados, pero no llegan», con 3 o más peticiones repetidas.
- «El receptor rechaza mensajes RTCM» en rojo.
**Qué cambia:**
- El contador `zed_fail` de la espalda junta RXM-RTCM con `msgUsed = 1`, es decir, tipos que el receptor no usa, con los CRC erróneos.
- Ahora sale como «No usadas por el receptor», en ámbar y con su caudal, en lugar de error rojo.
- Prueba JVM actualizada. vc 48 → **49**.
**Validación:** IMPLEMENTADO · CI ver PR · NO VERIFICADO.

## 2026-11-20 — Espalda PROTOTIPO 3.14.5 — UART del ZED otra vez como en la 3.14.3 (la 3.14.4 no enlazaba con el pecho)
**Autor:** Claude · **Rama:** `claude/gnss-calidad-rtcm-back-3-14-4` (PR #113) · **CI:** ver PR
**Qué se vio (usuario, 20/11 21:48–22:08, espalda 3.14.4):**
- La espalda no enlaza con el reloj ni entra en el modo sin pecho.
- El monitor de AVO Update mostró el arranque normal (`POWERON`, sin bucle) y el diagnóstico del GPS: 38 400 y 9 600 sin bytes; 115 200 y 230 400 con bytes pero sin tramas válidas, lo propio de un ZED a 460 800 leído a otra velocidad.
- Tras la línea de 230 400 no salió nada más.
**Revisión:** el parser nuevo pasó 2 000 flujos aleatorios con ASan/UBSan, sin bloqueos ni errores. En la placa solo cambiaban dos cosas:
- la tarea de eventos de la UART que crea `onReceiveError`, con prioridad máxima;
- el umbral de la FIFO RX.
Causa **no confirmada**.
**Qué cambia:**
- La UART del ZED vuelve a configurarse exactamente como en la 3.14.3: solo `setRxTimeout(1)`, sin `onReceiveError` y con el umbral FIFO del núcleo.
- El ajuste de la 3.14.4 queda en el código tras `AVO_ZED_UART_TUNE` (0), para probarlo en banco.
- Se conserva el resto de la 3.14.4: parser con resincronización, vigilancia de NAV-SAT/SIG por separado, solo recuentos frescos, presupuesto UART y MON-COMMS.
- Pruebas de host: 52 casos y 519 comprobaciones.
**Validación:** IMPLEMENTADO · CI ver PR · **NO VERIFICADO**. Si la 3.14.5 tampoco enlaza, el fallo no está en la UART: volver a la 3.14.3 y comparar.

## 2026-11-20 — Espalda PROTOTIPO 3.14.4 · Android 2.15-gnss-dev1 — Mensajes de calidad GNSS que no llegan, cadena RTCM por etapas
**Autor:** Claude (encargo del usuario, 20/11 21:07: «Mensajes de calidad activados, pero no llegan», 64,9 cm H, sin RTK
FIX, velocidad ±0,52 km/h) · **Rama:** `claude/gnss-calidad-rtcm-back-3-14-4` · **Commits:** `3ed96d0` (espalda), `d502568` (Android), docs en el último commit del PR
**CI:** espalda `build-back-v380.yml` run 44810109245 ✅ (52 casos / 519 comprobaciones; imagen ESP32-S3 927 984 B, 27 % de app0) · espalda tras traer `develop` run 44811443358 ✅ · Android `build-android.yml` run 44811442078 ✅ (lanzado a mano en la rama; core 181 pruebas, 0 fallos = 174 de `develop` + 7 de `GnssChainTest`; pruebas en emulador ✅; APK firmada con la clave estable). El intento 44810606166 falló solo al descargar `com.google.zxing:core:3.5.3` (dependencia ya existente).
**Informe completo:** `firmware/back/V3_8_0/docs/AUDITORIA_CALIDAD_GNSS_3_14_4.md`.
**Diagnóstico:**
- NAV-PVT llegaba, pero NAV-SAT y NAV-SIG no: los satélites «18 / 26» de la app eran de un NAV-SAT antiguo, porque NAV-PVT daba 24.
- Causa probable, **sin medir**: desbordamiento de la FIFO RX de 128 B del ESP32-S3.
  - Con el umbral por defecto (~120 B) quedaban 0,35 ms de margen a 230 400 y 0,17 ms a 460 800.
  - Al desbordarse se pierde un bloque entero: destruye las tramas largas y casi nunca un NAV-PVT de 100 B.
- Defectos confirmados con pruebas:
  - el parser UBX perdía también la trama siguiente a una mala;
  - la vigilancia de la 3.13.12 solo miraba NAV-SIG;
  - los recuentos caducados se enviaban y se mostraban como actuales;
  - la activación de los mensajes no calculaba la carga de la UART.
- **Pines verificados:** el código usa RX=GPIO35 / TX=GPIO33, cableado confirmado el 31/10. El encargo los daba al revés,
  que es justo el fallo de la 3.9.0. No se tocan.
**Qué cambia:**
- **Espalda 3.14.4:**
  - umbral de la FIFO RX a 32 B;
  - contadores de errores de la UART;
  - el parser resincroniza tras una trama mala;
  - NAV-SAT y NAV-SIG se vigilan por separado;
  - en `STATUS` solo van recuentos con ≤ 5 s (formato de 108 B sin cambios);
  - presupuesto UART antes de activar la calidad;
  - UBX-MON-COMMS cada 5 s (búfer TX del receptor y desbordes de RTCM);
  - líneas nuevas en el monitor serie: `MENSAJES ZED`, `UART ESP32 (ZED)`, `PRESUPUESTO UART`, `MON-COMMS`.
- **Android 2.15-gnss-dev1 (vc 48;** commits del Android con el nombre provisional 2.14-gnss-dev1 / vc 47, renumerada al traer `develop`, donde vc 47 ya es 2.14-presencia-dev1**):**
  - `GnssChain` lee la cadena RTCM (caster → móvil → reloj → espalda → UART → usadas) y la recepción UBX a partir de
    `DIAG_GET` (ya existente), cada 5 s con INICIO abierta. Dice en qué etapa se paran las correcciones.
  - «NTRIP recibiendo» no se presenta como RTK.
  - Calidad GNSS: ya no muestra satélites caducados; la precisión de velocidad se compara con el objetivo de 0,20 km/h.
  - `KV` y `MetricTile` sin solapes.
**No se ha tocado:**
- pecho, ni contratos binarios (`BackStatus` v3, `TELEMETRY` v3, `DIAG_GET`);
- iPad y Windows, que decodifican igual;
- pines, alimentación, sueño, carga USB, RTCM, ESP-NOW, modelo dinámico, frecuencia ni máscaras;
- firmas e `Info.plist`.
- Workflow `build-back-v380.yml`: solo nombre de versión, marcas de la imagen y la rama de esta tarea en `branches`.
- Al fusionar, `build-avo-ipad.yml` se lanzará porque cambia `lib/avo_core` (sin cambios para el iPad).
**Validación:** IMPLEMENTADO · CI ✅ (espalda y Android) · **NO VERIFICADO** en hardware. PR #113.
**Pendiente:** procedimiento del §8 del informe:
- `FIFO desbordada` = 0 y edades de NAV-SAT/SIG ≤ 1,5 s durante 10 min;
- cadena RTCM en verde con NTRIP;
- ensayos de velocidad parado, en recta y en giros, con porcentaje de épocas con `sAcc` < 55 mm/s.

---

## 2026-11-20 — Motor 2.0.0-dev26 / KB-1 1.24.0 — Estudio horario 22:09: lesiones de árabes de llano en Turquía y repetibilidad de campo
**Autor:** Claude (estudio horario programado) · **Rama:** `claude/kb-estudio-2026-11-20-2209` (encadenada desde `claude/kb-estudio-2026-11-20-2108`, PR #114) · **CI:** ver PR
**Qué cambia:** KB-1 1.23.0 → 1.24.0 y motor 2.0.0-dev25 → 2.0.0-dev26 (solo versiones, sin cambios de lógica).
- **Árabes de llano, Turquía:** Yıldırım & Karaarslan 2025 (TJVR) leído en texto completo: tendón 137/216 (63,7 %) en
  árabes frente a fractura 206/337 (61,5 %) en PSI; serie hospitalaria (≈ 20 % de la población), no incidencia. Misma
  serie que el EVJ 2025 (solo resumen; superficie sin OR). Fuente reclasificada de `SIN_AUDITAR` y duplicado marcado.
- **Repetibilidad:** Poinsard 2026: bloque de ≥ 3 sesiones con ≤ 7 d, 18 caballos, ICC ajustado por temperatura [E-r];
  ICC de V200 0,50 no reconfirmado (texto completo sin acceso).
- Propuestas TA1–TA2 y RB1 [I], sin implementar; 2 fuentes nuevas, 4 actualizadas, 2 parámetros de referencia.
**Por qué:** datos de árabes de llano y auditoría de fuentes (prioridades del estudio horario).
**Archivos:** `equine-intelligence/knowledge/base_cientifica.json`, `equine-intelligence/knowledge/estudios/2026-11-20_2209_lesiones_arabes_turquia_repetibilidad_v200.md`, `equine-intelligence/include/avo_eq/{types,knowledge}.h`, `equine-intelligence/tests/test_knowledge.cpp`, `equine-intelligence/docs/algoritmos/14_BASE_CIENTIFICA.md`, fixtures del motor y de `core` (versión), `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`, `README.md`.
**No se ha tocado:** workflows, firmas, `Info.plist`, build de TestFlight, firmware ni contratos binarios.
**Validación:** pruebas del motor en local (Debug con sanitizers y Release + fixtures); CI en el PR. NO VERIFICADO con caballos reales.
**Pendiente:** EVJ 2025 y Poinsard 2026 en texto completo (Wiley, MDPI y PMC sin permiso de red en la sesión desatendida).

## 2026-11-20 — Motor 2.0.0-dev25 / KB-1 1.23.0 — Estudio horario 21:08: estado del terreno (going) y calentamiento / vuelta a la calma
**Autor:** Claude (estudio horario programado) · **Rama:** `claude/kb-estudio-2026-11-20-2108` (encadenada desde `claude/kb-estudio-2026-11-20-2008`, PR #112) · **CI:** ver PR
**Qué cambia:** KB-1 1.22.0 → 1.23.0 y motor 2.0.0-dev24 → 2.0.0-dev25 (solo versiones, sin cambios de lógica).
- **Going:** firme/bueno-firme más riesgo (OR 1,29 muerte, Rosanowski 2018 PLoS ONE [E]; OR 1,27–1,73, Morrice-West 2025
  [E]) y más fatiga ósea por salida (Morrice-West 2022 [E]); blando más zancadas a igual velocidad (Morrice-West [E]); going
  oficial con 51 % de concordancia y CV 14 % del GoingStick (Northrop 2024 [E]); árabes de llano 14,45 frente a 13,52 m/s
  en césped/tierra (Yıldırım 2019 [E]). Propuesta GO1–GO4 [I].
- **Calentamiento / vuelta a la calma:** FC más alta a igual esfuerzo tras calentamiento intenso (Mukai 2010, PSI [E-r]);
  sin dato publicado del efecto en la V200 de campo [NV]; vuelta a la calma activa aclara antes el lactato (trotones y PSI
  en cinta [E-r]). Propuesta WU1–WU4 [I].
- 20 fuentes, 4 parámetros (3 de contexto, 1 propuesto), 2 reglas PROPUESTAS, 1 pendiente, 2 entradas de cola; fixtures solo con versiones.
**Archivos:** `equine-intelligence/knowledge/estudios/2026-11-20_2108_going_terreno_calentamiento_vuelta_calma.md`,
`base_cientifica.json`, `knowledge.h`, `types.h`, `tests/test_knowledge.cpp`, fixtures de `core/src/test/resources/equine/`,
ficha 14, tabla de estado, `README.md`.
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`, TestFlight.
**Validación:** IMPLEMENTADO (solo versiones) · pruebas locales con `-DAVO_EQ_SANITIZE=ON` en verde y fixtures OK · CI: ver PR · NO VERIFICADO con caballos reales.
**Pendiente:** implementar GO1–GO4 y WU1–WU4 (campo going/penetración en `Session`); textos completos de Hobbs 2024, Mukai 2008/2010 y Jansson 2005.

## 2026-11-20 — Motor 2.0.0-dev24 / KB-1 1.22.0 — Estudio horario 20:08: recuperación tras el trabajo rápido y pérdida de peso corporal (umbral del 2 %)
**Autor:** Claude (estudio horario programado) · **Rama:** `claude/kb-estudio-2026-11-20-2008` (encadenada desde `claude/kb-estudio-2026-11-20-1908`, PR #110) · **CI:** ver PR
**Qué cambia:** KB-1 1.21.0 → 1.22.0 y motor 2.0.0-dev23 → 2.0.0-dev24 (solo versiones, sin cambios de lógica).
- **Recuperación:** glucógeno 48–72 h tras un esfuerzo rápido (Jose-Cunilleras & Hinchcliff 2004 [E]; Hyyppä 1997 y
  Lacombe 2004 [E-r]; Minami 2009 discrepa con 24 h [E-r]); CK/AST con pico a 1–6 h y normales en ≤ 24 h, también en
  árabes de llano (Mami 2019 [E-r], Pourmohammad 2019 [E]); días entre carreras/trabajos sin efecto independiente en
  lesión catastrófica (Hitchens 2018 [E]). Propuesta RT1–RT3 [I] (≥ 72 h entre trabajos rápidos).
- **Peso corporal:** −2,7 % agudo tras carrera y −1–1,3 % a 24 h (trotones [I-raza], PSI de carretas [E-r]); el 2 % de
  SO1 no está validado. Propuesta PE1–PE3 [I] (pesaje matinal, persistencia ≥ 3 d, ALTO ≥ 4 %, gracia tras transporte).
- 17 fuentes, 3 parámetros de contexto, 2 reglas PROPUESTAS, 1 pendiente, 2 entradas de cola; fixtures solo con versiones.
**Archivos:** `equine-intelligence/knowledge/estudios/2026-11-20_2008_recuperacion_trabajo_rapido_peso_corporal.md`,
`base_cientifica.json`, `knowledge.h`, `types.h`, `tests/test_knowledge.cpp`, fixtures de `core/src/test/resources/equine/`,
ficha 14, tabla de estado, `README.md`.
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`, TestFlight.
**Validación:** pruebas locales ✅ (ASan/UBSan) y fixtures ✅ · CI: ver PR · NO VERIFICADO con caballos reales.
**Pendiente:** implementar RT1–RT3 y PE1–PE3 cuando haya error típico propio del peso; glucógeno tras breeze en pista.

---

## 2026-11-20 — Integración: motor 2.0.0-dev15 → dev23 (KB-1 1.13.0 → 1.21.0) en `develop`
**Autor:** Claude (chat integrador, petición del usuario 20/11 21:02: «fusióname todos los pasos del motor pendientes»)
**Qué entra:** PR #99, #101, #102, #104, #106, #107, #108, #109 y #110 (apilados: #110 contiene los ocho anteriores),
fusionados con *merge commit* a través de #110. Se trajo `develop` (con el PR #111, LIVE con presencia) a la rama y se
conservaron las dos partes en este registro y en la tabla de estado (fila del iPad de #111, fila del motor de dev23).
**CI previo en la rama:** motor 44802462967 ✅ (Linux con JNI, Windows, Android ×3 ABI), Android 44808102888 ✅ y
Windows 44808108216 ✅. El iPad compila y sube a TestFlight al entrar en `develop`.
**No se ha tocado:** lógica del motor, firmware, workflows, firmas ni contratos binarios (todo es base científica).
**Validación:** COMPILADO / CI · **NO VERIFICADO** con caballos reales.

---

## 2026-11-20 — Android 2.14-presencia-dev1 · iPad · reglas RTDB — Directo desde que se enciende el pecho; varios caballos en el iPad
**Autor:** Claude (petición del usuario, 20/11 20:55, con boceto sobre la build 202: «selector para cuando hay más de 1
caballo a la vez», «lista sistemas conectados» bajo LIVE, «que el pecho mande posición en cuanto se encienda, tiempo
real al servidor cada segundo sin grabar; el raw es solo cuando entra en la geocerca») · **Rama:** `claude/live-presencia`
**Qué cambia:**
- **Android (vc 47):** `LiveRecorder` con presencia (`IDLE` 1 Hz desde la primera `TELEMETRY`; `REC` 2 Hz; fin tras 60 s
  sin `TELEMETRY`); `LiveShare` comprueba cada 5 s.
- **iPad:** estado «EN ESPERA»; selector de caballo (chips) cuando hay más de un directo; sección «EN DIRECTO» en la barra
  lateral con los sistemas conectados (lista en segundo plano cada 20 s).
- **Reglas RTDB:** `state` admite `IDLE` (prueba nueva en el emulador). Hay que publicarlas a mano.
**No se ha tocado:** firmware (el pecho ya manda `TELEMETRY` sin grabar), contratos binarios, workflows, firmas.
**Validación:** IMPLEMENTADO · CI: ver PR · **NO VERIFICADO** en dispositivos.

---

## 2026-11-20 — Motor 2.0.0-dev23 / KB-1 1.21.0 — Estudio horario 19:08: DMD en potros de 2 años y auditoría de sobreentrenamiento (A9/A10)
**Autor:** Claude (tarea programada, estudio horario) · **Rama:** `claude/kb-estudio-2026-11-20-1908` (sale de
`claude/kb-estudio-2026-11-20-1809`, PR #109) · **CI:** ver PR
**Qué cambia:** estudio `equine-intelligence/knowledge/estudios/2026-11-20_1908_dmd_potros_auditoria_sobreentrenamiento.md`.
- DMD: Crawford 2021 [E] (HR 0,89 por km rápido acumulado; inicio tardío y machos con más riesgo), Boston & Nunamaker
  2000 [E-r], Verheyen 2005 [E-ag], Oliveira 2006 [E]; propuesta DM1–DM4 [I] para el planificador, sin implementar.
- Sobreentrenamiento: **cifra corregida** «14–19 %» → 19 % de tiempo hasta la fatiga en trotones (de Graaf-Roelfsema
  2009, Wijnberg 2008 [E]); Tyler-McGowan 1999 (no 1998); umbral de peso del 2 % declarado diseño; Martin 2000
  confirmado; propuesta SO1–SO3 [I].
- 12 fuentes, 2 parámetros de contexto, 2 reglas PROPUESTA, 2 pendientes y 2 temas de cola.

**Por qué:** el planificador de potros no tenía base sobre DMD y A9/A10 se apoyaban en cifras de agregador.
**Archivos:** `base_cientifica.json`, el estudio, `knowledge.h`, `types.h`, `tests/test_knowledge.cpp`, fixtures de
`core/src/test/resources/equine/` (solo versiones), ficha 14, tabla de estado, `README.md` y este registro.
**No se ha tocado:** lógica, reglas implementadas, umbrales, firmware, workflows, firmas ni contratos binarios.
**Validación:** pruebas locales (ASan/UBSan) y fixtures; CI en el PR · NO VERIFICADO con caballos reales.

---

## 2026-11-20 — Motor 2.0.0-dev22 / KB-1 1.20.0 — Estudio horario 18:09: modelo óseo B (tabla 4, signo de b) y auditoría de fuentes
**Autor:** Claude (tarea programada, estudio horario) · **Rama:** `claude/kb-estudio-2026-11-20-1809` (sale de
`claude/kb-estudio-2026-11-20-1709`, PR #108) · **CI:** ver PR
**Qué cambia:** estudio `equine-intelligence/knowledge/estudios/2026-11-20_1809_modeloB_tabla4_auditoria_fuentes.md`.
- Modelo B: dt y solver siguen [NV] (Zenodo, Europe PMC y PMC sin permiso de acceso en la sesión). La tabla 4 exacta
  del preprint de Anwar se guarda como vector de validación (`modelo_b_tabla4_anwar_preprint`); 0,852 frente a 0,911 es
  una incoherencia interna del preprint; el signo de b difiere entre Pan (0,02) y Anwar (−0,02).
- Auditoría de la KB: 15 obras duplicadas (17 entradas con `duplicado_de`, 7 con `acceso` incoherente) y 52 fuentes
  sin campos obligatorios, completadas como `SIN_AUDITAR`/`[NV]` sin releerlas. Pendiente AU1 [I].
- Li 2026 probable revisión de caballos de deporte; Hall 2026: 53 frente a 54 fracturas [I].

**Por qué:** el modelo B es el pendiente que más bloquea código y la base tenía fuentes duplicadas con acceso dispar.
**Archivos:** `base_cientifica.json`, el estudio, `knowledge.h`, `types.h`, `tests/test_knowledge.cpp`, fixtures de
`core/src/test/resources/equine/` (solo versiones), ficha 14, tabla de estado, `README.md` y este registro.
**No se ha tocado:** lógica, reglas, umbrales, firmware, workflows, firmas ni contratos binarios.
**Validación:** pruebas locales (ASan/UBSan) y fixtures; CI en el PR · NO VERIFICADO con caballos reales.

---

## 2026-11-20 — Motor 2.0.0-dev21 / KB-1 1.19.0 — Estudio horario 17:09: exactitud del GNSS/IMU a galope y mano de galope
**Autor:** Claude (tarea programada, estudio horario) · **Rama:** `claude/kb-estudio-2026-11-20-1709` (sale de
`claude/kb-estudio-2026-11-20-1610`, PR #107) · **CI:** ver PR
**Qué cambia:** estudio `equine-intelligence/knowledge/estudios/2026-11-20_1709_exactitud_gnss_mano_de_galope.md`.
- No hay exactitud publicada de RTK a galope. La referencia es ±0,15 m/s en carrera (TurfTrax [E-r]) y France Galop
  exige ≤ 25 cm de posición. Las curvas y las aceleraciones degradan la velocidad GNSS [E].
- Se propone GN1 [I]: menor confianza en tramos con curva o aceleración, A8 solo con la misma geometría y la longitud
  de zancada solo por tramos de ≥ 100–200 m.
- Mano de galope: el 18,6 % de las zancadas en curva va en mano incorrecta (Parkes 2020 [E]) y, en pistas antihorarias,
  la mano izquierda tiene RR 1,14 de fractura (Peterson 2021 [E]). No hay exactitud publicada de detección con un solo
  sensor en el tronco. Se propone ML1 [I] como métrica experimental, nunca como riesgo.
- KB: 14 fuentes, 3 parámetros de contexto, 2 pendientes y 3 entradas de cola.

**Por qué:** temas no cubiertos por ningún estudio anterior que afectan a V200, A8, la velocidad final y la cincha.
**Archivos:** `base_cientifica.json`, el estudio, `knowledge.h`, `types.h`, `tests/test_knowledge.cpp`, ficha 14,
tabla de estado, `README.md` y este registro.
**No se ha tocado:** lógica, reglas, umbrales, firmware, workflows, firmas ni contratos binarios.
**Validación:** pruebas locales (ASan/UBSan) y fixtures; CI en el PR · NO VERIFICADO con caballos reales.

---

## 2026-11-20 — Motor 2.0.0-dev20 / KB-1 1.18.0 — Estudio horario 16:10: aceleración del tronco a galope y cinética de la FC
**Autor:** Claude (tarea programada, estudio horario) · **Rama:** `claude/kb-estudio-2026-11-20-1610` (sale de
`claude/kb-estudio-2026-11-20-1510`, PR #106) · **CI:** ver PR
**Qué cambia:** estudio `equine-intelligence/knowledge/estudios/2026-11-20_1610_aceleracion_tronco_cinetica_fc.md`.
- No hay ningún pico de aceleración del tronco publicado en g a 16–18 m/s. Los sensores de referencia usan ±10–16 g
  (Pfau 2006 y Parsons 2008 [E], StrideSAFE y MTw [E]). Se estima [I] que ±8 g basta para el movimiento del cuerpo.
- Se precisa el pendiente del contador de saturación de la cincha (|a| ≥ 7,9 g, > 0,1 % en galope [I]) y se propone
  ±16 g para la cincha BETA. No se toca el firmware.
- Cinética de la FC: el descarte de 20–30 s en las mesetas de V200 es coherente (Mukai 2007 y Langsetmo 1997 [E-r]).
  Se proponen CF1 (meseta ≥ 45–60 s cerca del galope de trabajo) y CF2 (τ de recuperación solo propia del caballo),
  ambos [I] y sin implementar.
- Fraipont 2011/2012 es de resistencia, no de trotones.
- KB: 9 fuentes, 3 parámetros de contexto, 2 pendientes y 3 entradas de cola.

**Por qué:** temas abiertos de la cola y de `pendiente_motor` no cubiertos por los estudios de hoy.
**Archivos:** `base_cientifica.json`, el estudio, `knowledge.h`, `types.h`, `tests/test_knowledge.cpp`, ficha 14,
tabla de estado, `README.md` y este registro.
**No se ha tocado:** lógica, reglas, umbrales, firmware, workflows, firmas ni contratos binarios.
**Validación:** pruebas locales (ASan/UBSan) y fixtures; CI en el PR · NO VERIFICADO con caballos reales.

---

## 2026-11-20 — Android 2.13-qr-dev1 · iPad — Entrar en el iPad escaneando un QR de la tarjeta
**Autor:** Claude (petición del usuario, 20/11 15:22: «botón para cargar el archivo de licencia» en LIVE; elegida la
opción QR) · **Rama:** `claude/qr-tarjeta` · **CI:** ver PR
**Por qué no el `.avolic`:** el archivo de licencia lleva el token cifrado con la clave de la tarjeta, pero **no** la
clave: no sirve para entrar en Firebase (y así un archivo reenviado no da acceso a la cuenta).
**Qué cambia:**
- **Android:** Compartir › Mi cuenta › «Entrar en el iPad» muestra un **QR** del enlace de la tarjeta
  (`avohorse://identity/user/…`), generado con `com.google.zxing:core:3.5.3` (dependencia nueva). vc 45 → **46**.
- **iPad:** LIVE › **«Escanear QR de la tarjeta»** (cámara trasera, AVFoundation); al leerlo entra y guarda la tarjeta en
  el Llavero, como con el enlace. La Nube AVO usa la misma sesión.
- Windows sigue entrando pegando el enlace o «código clave» (sin escáner de QR).
**No se ha tocado:** firmware, contratos, workflows, firmas, `Info.plist` (ya tenía el permiso de cámara).
**Validación:** IMPLEMENTADO · CI: ver PR · **NO VERIFICADO** en dispositivos.

## 2026-11-20 — Motor 2.0.0-dev19 / KB-1 1.17.0 — Estudio horario 15:10: árabes de llano (lactato, velocidad) y novedades 2026
**Autor:** Claude (tarea programada, sin supervisión) · **Rama:** `claude/kb-estudio-2026-11-20-1510` (encadenada desde `claude/kb-estudio-2026-11-20-1410`, PR #104, sin fusionar) · **CI:** ver PR
**Qué cambia:**
- Estudio nuevo: `equine-intelligence/knowledge/estudios/2026-11-20_1510_arabes_lactato_novedades_2026.md`.
- `base_cientifica.json` 1.17.0: 9 fuentes nuevas (Kędzierski 2007, Paksoy 2025, Thomassian 2005, Prince/KER, Dąbrowska 2026 BMC, Espil 2026, Hall 2026, Legg 2026, Eamon 2026), 2 parámetros de contexto (`lactato_post_galope_arabe_llano`, `velocidad_carrera_arabe_llano_1400m`), pendiente NV1, 4 entradas de cola, estudio e historial.
- `KNOWLEDGE_VERSION` 1.17.0 y `ENGINE_VERSION` 2.0.0-dev19 (y su prueba); ficha 14, README y tabla de estado.
**Por qué:** faltaban datos fisiológicos de árabes de carreras en llano y revisar lo publicado en 2026.
**No se ha tocado:** lógica, reglas, umbrales, firmware, apps, workflows, contratos binarios.
**Validación:** pruebas locales (ASan/UBSan) y fixtures; CI en el PR · NO VERIFICADO con caballos reales.
**Pendiente:** tabla S4 de Dąbrowska 2026, versión RSOS de Anwar, textos completos de Hall y Espil 2026; NV1 sin implementar.

## 2026-11-20 — Motor 2.0.0-dev18 / KB-1 1.16.0 — Estudio horario 14:10: regla combinada de Verheyen y TE por defecto de la V200
**Autor:** Claude (tarea programada, sin supervisión) · **Rama:** `claude/kb-estudio-2026-11-20-1410` (encadenada desde `claude/kb-estudio-2026-11-20-1312`, PR #102, sin fusionar) · **CI:** ver PR
**Qué cambia:**
- Estudio nuevo: `equine-intelligence/knowledge/estudios/2026-11-20_1410_verheyen_combinada_v200_te_japon.md`.
- `base_cientifica.json` 1.15.0 → 1.16.0: 9 fuentes, 2 parámetros (`v200_te_por_defecto` PROPUESTO [I],
  `v200_arabes_referencia` CONTEXTO [E]), regla `A1A2_VERHEYEN_COMBINADO` pasa a PROPUESTO con 3 fuentes secundarias,
  2 pendientes (VC1–VC4, VT1–VT3), 3 entradas de cola, estudio e historial.
- `KNOWLEDGE_VERSION` 1.16.0 y `ENGINE_VERSION` 2.0.0-dev18 (y la línea de `tests/test_knowledge.cpp`).
- Ficha 14, tabla de estado y `README.md`.
**Por qué:** la regla combinada A1+A2 y el TE de la V200 bloquean código. Verheyen 2006 se describe como interacción
canter × galope en tres secundarios en texto completo; sigue sin OR, así que no se cambian severidades.
**No se ha tocado:** lógica, reglas y umbrales del motor; firmware; contratos binarios; workflows; firmas; `Info.plist`.
**Validación:** IMPLEMENTADO (solo versiones) · probado en local con ASan/UBSan y fixtures; CI en el PR · **NO VERIFICADO** con caballos reales.
**Pendiente:** OR de Verheyen 2006; aprobar o no VC1–VC4; TE numérico de V200 (Vermeulen & Evans 2006, Wiley); disciplina de los árabes de Piccione 2004.

## 2026-11-20 — Motor 2.0.0-dev17 / KB-1 1.15.0 — Estudio horario 13:12: temperatura y peso cargado como criterios de comparables
**Autor:** Claude (tarea programada, sin supervisión) · **Rama:** `claude/kb-estudio-2026-11-20-1312` (encadenada desde `claude/kb-estudio-2026-11-20-1210`, PR #101, sin fusionar) · **CI:** ver PR
**Qué cambia:**
- Estudio nuevo: `equine-intelligence/knowledge/estudios/2026-11-20_1312_temperatura_peso_comparables.md`.
- `base_cientifica.json` 1.15.0:
  - 19 fuentes nuevas (temperatura: Hargreaves 1999, Schrurs 2024, Ebisuda 2023, Ohmura 2025, Nomura 2019, Geor
    1995/1996, Marlin 1996, Art 1995, Arfuso 2025; peso: Lee & Park 2011, Bugislaus 2004, Takahashi 2015, Schrurs
    2022, Pfau 2009, Christensen 2020, Stefánsdóttir 2017, Ekiz 2005 y Sobczyńska 2006 en árabes).
  - 2 parámetros PROPUESTOS [I]: `temperatura_comparables` (|ΔT| ≤ 5 °C, «no comparable» con WBGT ≥ 28 °C) y
    `peso_cargado_comparables` (|Δpeso| ≤ 3 kg, aviso informativo con CW/BW > 13 %).
  - 1 pendiente de motor y 3 entradas de cola.
- `KNOWLEDGE_VERSION` 1.14.0 → 1.15.0 y `ENGINE_VERSION` 2.0.0-dev16 → 2.0.0-dev17, también en
  `tests/test_knowledge.cpp`.
- Ficha 14, tabla de estado y README actualizados.

**Por qué:** las líneas base y los comparables de A7, A8 y A9 no tenían en cuenta el calor ni el peso cargado. Ninguna
fuente publica un coeficiente de corrección, así que se proponen como criterios de comparables, sin implementar.
**No se ha tocado:** lógica, reglas, umbrales, firmware, contratos binarios, workflows, firmas, `Info.plist` ni
TestFlight.
**Validación:** probado en local (ASan/UBSan, Release y fixtures) y en CI (ver PR). **NO VERIFICADO** con caballos reales.
**Pendiente:** campos de temperatura, jinete y peso en `Session`; textos completos de Hargreaves 1999, Geor 1995/1996 y
Marlin 1996; ningún dato de árabes de llano.

## 2026-11-20 — Motor 2.0.0-dev16 / KB-1 1.14.0 — Estudio horario 12:10: playa por franjas y parcial final de 200 m (A8)
**Autor:** Claude (tarea programada, sin supervisión) · **Rama:** `claude/kb-estudio-2026-11-20-1210` (encadenada desde `claude/kb-estudio-2026-11-20-1110`, PR #99, sin fusionar) · **CI:** ver PR
**Qué cambia:**
- Estudio nuevo: `equine-intelligence/knowledge/estudios/2026-11-20_1210_playa_franjas_parcial_final_200m.md`.
- `base_cientifica.json` 1.14.0:
  - **Corrección de cifra/atribución** en `playa_franjas`: la humedad del 19 % y el 13,5 % es de Crevier-Denoix 2011
    (se añaden el DOI …00202.x y el PMID 21059058).
  - Las cifras de −59 % y −50 % de Chateau 2011 son deceleraciones del casco. Su DOI …00277.x pasa a provisional, sin
    confirmar.
  - 6 fuentes nuevas: Porzio 2025, Graydon 2023, Crevier-Denoix 2013 (AVF), Morrice-West 2020, Legg 2025 y Takahashi
    2021.
  - 3 fuentes completadas: Chateau 2011, Crevier-Denoix 2011 y Morrice-West 2018; además, una nota en Wong 2023.
  - Parámetro informativo nuevo `ruido_velocidad_final_carrera`: ≈ 0,66 m/s, CV ≈ 4 % [I].
  - Se amplía la nota de A8 y de dos pendientes, y se añaden 3 entradas a la cola de investigación.
- `KNOWLEDGE_VERSION` 1.13.0 → 1.14.0 y `ENGINE_VERSION` 2.0.0-dev15 → 2.0.0-dev16, también en
  `tests/test_knowledge.cpp`.
- Ficha 14, tabla de estado y README actualizados.

**Por qué:** la playa por franja y el parcial final de A8 son pendientes que bloquean código. La atribución de la playa
mezclaba dos artículos.
**No se ha tocado:** lógica, reglas, umbrales, firmware, contratos binarios, workflows, firmas, `Info.plist` ni
TestFlight.
**Validación:** probado en local (ASan/UBSan, Release y fixtures) y en CI (ver PR). **NO VERIFICADO** con caballos reales.
**Pendiente:** texto completo de Chateau/Crevier-Denoix 2011, método de Wong 2023 y DE del último 200 m en trabajo.

## 2026-11-20 — Motor 2.0.0-dev15 / KB-1 1.13.0 — Estudio horario 11:10: regreso tras layup (planificador) y sensores 2025–2026
**Autor:** Claude (tarea programada, sin supervisión) · **Rama:** `claude/kb-estudio-2026-11-20-1110` (desde `develop/avo-performance-horse` 32e2706; no había PR `claude/kb-*` abierto) · **CI:** ver PR
**Qué cambia:**
- Estudio nuevo: `equine-intelligence/knowledge/estudios/2026-11-20_1110_regreso_layup_sensores_2025_2026.md`.
- `base_cientifica.json` 1.13.0:
  - 11 fuentes nuevas: Choi, Rosanowski & Parkin 2026, Morrice-West 2024, aviso de HISA, UC Davis VORL, Li 2026,
    Takahashi/Pfau 2025, van den Broek 2025, Mc Sweeney 2025, Morrice-West 2025 (ANZCVS), Siegers 2025 y Savoini 2025.
  - 4 fuentes completadas: Carrier 1998 (DOI no confirmado, se cita por PMID), Poinsard 2026, Wong 2023 y
    Hitchens 2018.
  - 2 parámetros nuevos: `reincorporacion_tras_layup` (PROPUESTO) y `sesgo_curva_zancada` (INFORMATIVO).
  - Pendiente nuevo P7 del planificador; cola actualizada.
- Motor: `ENGINE_VERSION` 2.0.0-dev15 y `KNOWLEDGE_VERSION` 1.13.0, con su prueba. **Sin cambios de lógica, reglas ni
  umbrales.**
**Por qué:** el planificador (P1–P6) no tenía evidencia sobre las primeras semanas tras un descanso. Carrier 1998 y
Choi 2026 apuntan a los días 0–21 tras ≥ 60 d sin trabajo rápido, en fractura de húmero. Las dos solo se han leído por
resumen, así que P7 queda como diseño [I].
**Archivos:** el estudio, `base_cientifica.json`, `include/avo_eq/types.h`, `include/avo_eq/knowledge.h`,
`tests/test_knowledge.cpp`, la ficha 14, `README.md` y la tabla de estado.
**No se ha tocado:** firmware, contratos binarios, apps, workflows, firmas, `Info.plist`, build de TestFlight.
**Validación:** IMPLEMENTADO (solo documentación y versiones) · pruebas locales con ASan/UBSan · CI: ver PR ·
**NO VERIFICADO** con caballos reales.
## 2026-11-20 — Android 2.12-nube-dev1 · iPad · Windows — Cambiar caballo/jinete en la nube desde las tres apps; confirmar tras descargar; directo por defecto
**Autor:** Claude (petición del usuario, 20/11 14:00–14:10: «opción de modificar caballo y jinete en la nube desde iOS,
Windows y apk», «sí» a la confirmación tras la descarga y al directo activado) · **Rama:** `claude/nube-asignacion` · **CI:** ver PR
**Qué cambia:**
- **Nube AVO:** nuevos metadatos `horseCode`, `riderCode`, `assignedMs`. Gana la asignación más reciente.
  `CloudSync.decide` (núcleo Kotlin) decide subir, aplicar lo de la nube o nada; huella común en las tres apps con vector
  compartido.
- **Android 2.12 (vc 45):** `TrainingAssign` (una sola forma de asignar, guarda la hora); `CloudBackup` aplica cambios de
  la nube y repasa cada hora; diálogo **«Confirma caballo y jinete»** tras cada descarga verificada (Confirmar / Más
  tarde); **«Directo (LIVE en el iPad)» activado por defecto**.
- **iPad:** al guardar una asignación, si el entrenamiento está en la nube, sube el `.avo` reescrito; botón «Cambiar» en
  Servidor › Nube AVO.
- **Windows:** lo mismo (subida multipart, botón «Cambiar»).
- Reglas de Storage sin cambios (ya permiten reemplazar al dueño).
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`.
**Validación:** IMPLEMENTADO · CI: ver PR · **NO VERIFICADO** en dispositivos.
**Pendiente:** prueba cruzada: cambiar en el iPad → el Android lo aplica (≤ 1 h o al abrir Compartir › «Volver a comprobar todo»).

## 2026-11-20 — Android 2.11-nube-dev1 · iPad · Windows · reglas Storage — Nube AVO: entrenamientos en el servidor
**Autor:** Claude (petición del usuario, 20/11 12:32–12:44: «servidor para subir los entrenamientos que muestre también
datos en tiempo real… móntalo todo») · **Rama:** `claude/nube-sesiones` · **CI:** ver PR
**Qué cambia:**
- El tiempo real ya existía (LIVE, `docs/LIVE_SERVIDOR.md`). Se añade la **Nube AVO** en Cloud Storage del mismo proyecto
  de Firebase (el usuario pasó el proyecto a plan Blaze el 20/11).
- **Android:** cada entrenamiento verificado con el reloj (con caballo y jinete) se sube como `.avo` a
  `trainings/<CODIGO>/AVO_<id>.avo`, en la misma pasada que Compartir. Tarjeta «Nube AVO» en Compartir (interruptor,
  contador, pendientes, errores, «Subir ahora»). Dependencia nueva `firebase-storage` (BOM 33.7.0). vc 43 → **44**.
- **iPad y Windows:** página Servidor › «Nube AVO»: listar, descargar con comprobación de SHA-256 e importar.
- **Reglas:** `firebase/storage.rules` (solo el dueño, solo `.avo` ≤ 40 MB con `sha256`) con pruebas en el emulador
  (`firebase/test/storage.test.js`); `firebase.json` y el script de pruebas incluyen el emulador de Storage.
- Contrato y puesta en marcha: `docs/NUBE_SESIONES.md`.
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`.
**Validación:** IMPLEMENTADO · CI: ver PR · **NO VERIFICADO** con el bucket real ni en dispositivos.
**Pendiente:** activar Storage (UE) y publicar `storage.rules` en la consola; comprobar que la clave web acepta iPad y
Windows; prueba real: descarga verificada en el Android → aparece en iPad y Windows.

## 2026-11-20 — iPad 1.0.0 — Los caballos y jinetes borrados ya no vuelven; copia de seguridad diaria y recuperación
**Autor:** Claude (petición del usuario, 20/11 11:17: «cada vez que instalo una build nueva me saltan caballos y jinetes
que había borrado») · **Rama:** `claude/cuadra-borrados-persistentes` · **CI:** ver PR
**Causa:** el problema no era la build. En cada arranque, la app vuelve a cargar los entrenamientos de la biblioteca y
de «AVO Horse», y `registerFromTraining` da de alta el caballo y el jinete que trae cada archivo si no están en la
Cuadra. Un caballo o jinete borrado con entrenamientos volvía a crearse. Una build nueva fuerza un arranque, por eso se
notaba al actualizar.
**Qué cambia:**
- `cuadra.json` guarda los registros borrados (`DeletedHorses` / `DeletedRiders`: código, nombre y fecha). Un código o
  nombre borrado **no se vuelve a crear automáticamente** desde un entrenamiento.
- Solo vuelve si se crea a propósito: alta manual, etiqueta o enlace, o France Galop. Al crearlo así deja de estar
  marcado como borrado.
- Los entrenamientos de un caballo borrado no se tocan: muestran el nombre que trae el archivo, como antes.
- **Copia de seguridad:**
  - cada cambio de la Cuadra o de Jinetes lanza la copia a «AVO Horse › Copia de seguridad» en segundos (antes, como
    mucho cada 2 minutos);
  - nueva carpeta **«Historial/AAAA-MM-DD»** con los datos de cada día, para deshacer un error copiando el archivo
    de vuelta;
  - **al arrancar**, si falta un archivo de datos de la app (por ejemplo `cuadra.json` o `carreras.json`), se
    recupera de «Copia de seguridad/Datos» antes de cargar nada. Los archivos existentes no se tocan nunca.
- Archivos: `Core/Stable.swift`, `App/StableModel.swift`, `App/AppModel.swift`, `App/AppModel+DocumentsSync.swift`;
  prueba `testDeletedRecordsAreNotRecreatedFromTrainings`.
**Límite:** «AVO Horse» está dentro de la app en el iPad. Sobrevive a las actualizaciones de TestFlight y de la App Store,
pero **no a borrar la app**. Para eso hace falta una copia fuera: iCloud Drive o la carpeta Compartir.
**No se ha tocado:** motor, firmware, contratos, Android, Windows, workflows, firmas, `Info.plist`, build de TestFlight.
**Validación:** IMPLEMENTADO · CI: ver PR · **NO VERIFICADO** en el iPad.
## 2026-11-20 — Motor 2.0.0-dev14 / KB-1 1.12.0 — Estudio horario 10:08: OR del TFDS (índice tendinoso) y árabes de carreras en llano
**Autor:** Claude (tarea programada, sin supervisión) · **Rama:** `claude/kb-estudio-2026-11-20-1008` (encadenada desde `claude/kb-estudio-2026-11-20-0909`, PR #96 sin fusionar) · **CI:** ver PR
**Qué cambia:**
- Estudio nuevo: `equine-intelligence/knowledge/estudios/2026-11-20_1008_tendon_or_arabes_llano.md`.
- `base_cientifica.json` 1.12.0:
  - 10 fuentes nuevas (Paksoy 2025, Śniegucka 2026, *Antioxidants* 2024, *Genes* 2025, Dąbrowska 2026, Schurink 2009,
    Nielsen 2006, Takahashi 2004, Lam 2007 *EVJ* y Lam 2007 *AJVR*).
  - Yildirim 2025 e Ikeda 2019 completadas.
  - 2 parámetros informativos de árabes de llano: trabajo rápido a 12,5–13,9 m/s y 2 sesiones intensas por semana.
  - Pendiente del índice tendinoso ampliado y 4 entradas nuevas en la cola.
- Motor: `ENGINE_VERSION` 2.0.0-dev14 y `KNOWLEDGE_VERSION` 1.12.0. Fixtures regenerados, solo con las versiones.
- Ficha 14, tabla de estado y `README.md` actualizados.
**Por qué:** el índice tendinoso sigue sin OR legibles: AVMA, doi.org, Unpaywall y Europe PMC dieron 403 en la sesión.
De los árabes de llano solo se publica la práctica de entrenamiento (Polonia, Turquía), no la zancada, la FC de carrera
ni la V200.
**No se ha tocado:** lógica, reglas, parámetros ni umbrales del motor; firmware, workflows, firmas, `Info.plist` y
contratos binarios.
**Validación:** pruebas locales (ASan/UBSan) y fixtures en verde; CI en el PR. **NO VERIFICADO** con caballos reales.
**Pendiente:** OR de Takahashi y Lam *AJVR* desde AVMA, PDF de Yildirim 2025 y tabla S4 de Dąbrowska 2026.

## 2026-11-20 — Motor 2.0.0-dev13 / KB-1 1.11.0 — Estudio horario 09:09: V200/VHRmax (A9) y umbral de prematuro del ECG (A11)
**Autor:** Claude (tarea programada, sin supervisión) · **Rama:** `claude/kb-estudio-2026-11-20-0909` (encadenada desde `claude/kb-estudio-2026-11-20-0809`, PR #94 sin fusionar) · **CI:** ver PR
**Qué cambia:**
- Estudio `equine-intelligence/knowledge/estudios/2026-11-20_0909_v200_a9_ecg_a11_umbrales.md`.
- **A11 / ECG:** Flethøj 2016 (BMC Vet Res, texto completo): el 20/10/4 % son acortamientos del RR escalonados por FC (< 60, 60–100, > 100 lpm) en árabes de raid, y el 4 % en ejercicio sobredetecta (~3,8 % de latidos marcados frente a ≤ 0,4 % de arritmias reales). Se mantiene ≥ 5–6 % con FC > 100 lpm; se anota en el pendiente 10 %/20 % [I] para FC baja y FC pico sin prematuros (Navas de Solis 2026).
- **A9 / V200:** sin texto completo nuevo; referencias de escala en PSI (Gramkow: VHRmax < 14,5 m/s ↔ ganancias bajas, solo resumen; Kobayashi: +10,9 % de V200 en 5 meses) y ningún dato publicado de V200 en árabes de llano.
- `base_cientifica.json` 1.11.0: 4 fuentes nuevas (Flethøj 2016, Massie 2021, Gücüyener 2024, Wilk 2017), 5 completadas, notas de A9 y A11, 2 pendientes ampliados, cola actualizada. `KNOWLEDGE_VERSION` 1.11.0, `ENGINE_VERSION` 2.0.0-dev13; fixtures regenerados (solo versiones).
**Por qué:** estudio horario de la KB pedido por el usuario para el 20/11.
**No se ha tocado:** lógica, reglas, parámetros ni umbrales del motor; workflows, firmas, firmware ni contratos binarios.
**Validación:** pruebas locales (ASan/UBSan) y fixtures; CI en el PR · NO VERIFICADO con caballos reales.
**Pendiente:** textos completos de Vermeulen/Gramkow y Frick desde un navegador; V200 en árabes de llano.

---

## 2026-11-20 — iPad 1.0.0 — Informe PDF de «Análisis motor» sin «Cómo se calcula»
**Autor:** Claude (captura del PDF marcada por el usuario, 20/11 10:06) · **Rama:** `claude/pdf-sin-como-se-calcula` · **CI:** ver PR
**Qué cambia:** el PDF ya no incluye la sección «Cómo se calcula» ni la línea «Generado el…». La versión del motor
sigue en el pie de cada página. En la pantalla, el método se sigue pudiendo desplegar, y el texto del estado de la pista
dice ya que el dato se obtiene automáticamente.
**Validación:** IMPLEMENTADO · **NO VERIFICADO** en el iPad.

---

## 2026-11-20 — Motor 2.0.0-dev12 / KB-1 1.10.0 — Estudio horario 08:09: modelo óseo B y velocidad final relativa
**Autor:** Claude (tarea programada, sin supervisión) · **Rama:** `claude/kb-estudio-2026-11-20-0809` (desde `develop`, sin PR `kb-*` abiertos) · **CI:** ver PR
**Qué cambia:**
- Estudio `equine-intelligence/knowledge/estudios/2026-11-20_0809_modeloB_dt_velocidad_final_relativa.md`.
- **Modelo óseo B:** el paso de integración y el solver no aparecen en los preprints leídos en texto completo (arXiv de Anwar, bioRxiv de Pan): diario es [I]. Condiciones iniciales f_BM 0,61 y D* 0 [E]. Tablas 4 y 7 anotadas como objetivo de validación; incoherencia del preprint (D* máx. 0,911 en la tabla 7 frente a 0,852 en la Discusión). Zenodo y PMC13641913 siguen bloqueados.
- **A8 / velocidad final:** Wong 2023 reconfirmado (v200 absoluta, longitudinal, riesgo al bajar): A8 ya tiene el sentido correcto. Finishing Speed % de Timeform (v final / v media frente al par) sin umbrales; árabes: Nielsen 2006 (desaceleración final, resumen) y PDF de France Galop.
- `base_cientifica.json` 1.10.0: 6 fuentes nuevas, 3 completadas, notas de A8 y de dos pendientes, 2 entradas de cola. `KNOWLEDGE_VERSION` 1.10.0, `ENGINE_VERSION` 2.0.0-dev12.
**Por qué:** estudio horario de la KB pedido por el usuario para el 20/11.
**No se ha tocado:** lógica, reglas, parámetros ni umbrales del motor; workflows, firmas, firmware ni contratos binarios.
**Validación:** pruebas locales (ASan/UBSan) y fixtures; CI en el PR · NO VERIFICADO con caballos reales.
**Pendiente:** código de Zenodo 19173866 y PMC13641913 desde navegador; v200 en A8.

---

## 2026-11-20 — iPad 1.0.0 — Estado de la pista automático (PDF de tracking + Equidia)
**Autor:** Claude (petición del usuario, 20/11 08:33: «que sea automático») · **Rama:** `claude/estado-pista-france-galop` · **CI:** ver PR
**Qué cambia:**
- **PDF de tracking:** algunos traen el terreno bajo la fecha, por ejemplo Auteuil, 31/03/2024: «Lourd (4,7)». El
  parser lo lee al importar, con el penetrómetro. Los de plat que hemos visto no lo traen.
- **Equidia:** si el PDF no lo trae, la app busca la página de la carrera
  (`www.equidia.fr/courses/AAAA-MM-DD/R<n>/C<n>`) y lee «Terrain Souple 3.5».
  - La reunión sale del hipódromo y la carrera del nombre.
  - Si el nombre del PDF trae el número de carrera (`AAAAMMDDHHHCC_…`), se usa ese número.
  - Las peticiones van de una en una y solo para carreras sin estado de pista. Cada carrera se intenta una vez por
    sesión de la app.
- **Cuándo busca:** al importar una carrera, al abrir su ficha, al entrar en Carreras (todas las que falten) y al abrir
  «Análisis motor». Un valor puesto a mano no se sustituye nunca.
- **Bajo el selector** se ve de dónde sale el dato: «del PDF», «de Equidia (automático)» o «indicado a mano», con el
  penetrómetro.
- `Race.goingPenetrometer` y `Race.goingSource` son opcionales: los `carreras.json` anteriores se siguen leyendo.
- Archivos:
  - `Core/RaceGoingLookup.swift` (nuevo, funciones puras);
  - `Core/RaceTrackingParser.swift`, `Core/RaceModels.swift`, `App/RacesModel.swift`, `Views/RaceEngineAnalysisView.swift`;
  - pruebas `RaceGoingLookupTests` (4).
**No se ha tocado:** motor, firmware, contratos, Android, Windows, workflows, firmas, `Info.plist`, build de TestFlight.
**Validación:** IMPLEMENTADO · CI: ver PR · **NO VERIFICADO** en el iPad. La estructura de Equidia se ha comprobado
leyendo una página real desde aquí, pero desde esta sesión no se puede hacer una petición desde el iPad. Si Equidia
cambia su página o bloquea la petición, el estado queda «No encontrado» y se elige a mano.

## 2026-11-20 — iPad 1.0.0 — «Análisis motor»: el puesto de rapidez («14.º») ya no se parte en dos líneas
**Autor:** Claude (captura de TestFlight del 20/11, 01:23) · **Rama:** `claude/analisis-motor-ajustes` · **CI:** ver PR
**Qué cambia:** la columna del puesto de rapidez en «Cómo fue la carrera» es más ancha y de una sola línea.
**Validación:** IMPLEMENTADO · **NO VERIFICADO** en el iPad.
## 2026-11-20 — Motor 2.0.0-dev11 — KB-1 1.9.0: investigación nocturna (regla A6C del cociente de galope y auditoría de fuentes)
**Autor:** Claude (tarea programada nocturna, sin supervisión) · **Rama:** `claude/kb-noche-2026-11-20` (desde `claude/kb-estudio5-2026-11-19`, PR #89 abierto) · **CI:** motor lanzado a mano en la rama (resultado en el PR)
**Qué cambia:**
- **Estudio** `equine-intelligence/knowledge/estudios/2026-11-20_noche_auditoria_cociente_galope_asia_latam.md`, con
  etiquetas [E]/[E-r]/[I]/[I-raza]/[NV] y tipo de acceso.
  - Auditoría de 11 fuentes: 7 pasan a texto completo (Choi & Parkin 2025, Morrice-West 2020 y 2022, Wong 2023 ×2,
    Witte 2006 y van Erck 2026).
  - Correcciones de atribución y de ámbito, sin cambiar ninguna constante:
    - «Morrice-West 2023» es Wong 2023 (Front Vet Sci), y las fracciones 0,80/0,93 son diseño propio;
    - 12,57–21 m/s son criterios de exclusión;
    - 16,7 m/s es un límite de franja;
    - la fórmula de frecuencia de zancada es de Witte;
    - el umbral de Verheyen es conjunto (canter y galope) y el galope acumulado fue protector en añojos;
    - A8: Wong usó los 200 m finales de carrera.
  - Cobertura de Japón, Corea, Hong Kong, Turquía, Golfo (sin datos), Argentina, Uruguay, Brasil y Chile.
- **Motor:** regla nueva **A6C_COCIENTE_GALOPE**. Choi & Parkin 2025, sección 2.3 y tabla 2, leídas en el texto
  completo:
  - cociente = (días de galope en 60 d / en 90 d) + 1, con las ventanas acabadas en el último trabajo rápido;
  - avisa con cociente ≤ 1,6, que tiene OR 2,19 (1,23–3,91) de TFDS;
  - es INFO · AVISO;
  - opciones `cociente_galope_max` y `dias_vigencia_cociente_galope`;
  - campo `cociente_galope` en el JSON de `base_cientifica`.
- **Versiones:** `KNOWLEDGE_VERSION` 1.8.0 → 1.9.0 y `ENGINE_VERSION` 2.0.0-dev10 → 2.0.0-dev11. Fixtures regenerados
  (solo cambian las versiones).
- **`base_cientifica.json` 1.9.0:**
  - 24 fuentes nuevas;
  - 3 parámetros nuevos;
  - regla A6C;
  - pendientes de A1/A2 y A8;
  - 8 entradas nuevas en la cola.
- Actualizados también la ficha 14, la tabla de estado y el README.
**Por qué:** el cociente de A6 estaba pendiente por ambigüedad. La auditoría nocturna verifica las fuentes que sostienen
reglas implementadas.
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`, número de build de TestFlight, apps.
**Validación:**
- IMPLEMENTADO.
- Pruebas locales con ASan/UBSan: 103 casos y 1.744 comprobaciones sin fallos.
- Release y `check_fixtures.py` en verde tras `--update` (diferencias: solo versiones).
- CI: ver PR.
- **NO VERIFICADO** con caballos reales. A6C es un factor asociado, no una predicción de lesiones.
**Pendiente:**
- texto completo de Verheyen 2006 (regla combinada A1+A2);
- velocidad de los últimos 200 m para A8;
- tabla S1 de Choi;
- PDF de Kusunose 2002 (J-STAGE);
- versión publicada de Anwar 2026 (RSOS).

## 2026-11-20 — iPad 1.0.0 — «Informe PDF» en la pantalla «Análisis motor» de carreras
**Autor:** Claude (a petición del usuario sobre la captura de TestFlight del 20/11, 01:00) · **Rama:** `claude/analisis-motor-informe-pdf` · **CI:** ver PR
**Qué cambia:** botón rojo **«Informe PDF»** en la barra superior de «Análisis motor». Genera el PDF con el mismo
aspecto que los demás informes AVO y el contenido de la pantalla:
- resumen y datos clave, incluido el estado de pista;
- salida, desarrollo y final;
- gráficas de puesto, distancia al primero y velocidad, y tabla por tramo;
- rivales con su cara a cara;
- carreras anteriores (distancia, pista, hipódromo);
- entrenamientos y gráfica del mejor 200 m;
- conclusiones, «para la próxima», notas y método.

Se guarda en `exportaciones/` y se abre en el visor de PDF desde la propia pantalla, porque el visor general no se ve
encima de ella. El visor permite compartirlo.
Archivos: `Core/RaceEnginePdf.swift` (nuevo), `App/RacesModel.swift`, `Views/RaceEngineAnalysisView.swift`.
**No se ha tocado:** motor C++, firmware, contratos, Android, Windows, workflows, firmas, `Info.plist`, build de TestFlight.
**Validación:** IMPLEMENTADO · CI: ver PR · **NO VERIFICADO** en el iPad.

## 2026-11-20 — Proceso — Integración centralizada en un chat integrador
**Autor:** Claude (decisión del usuario, 20/11/2026 00:32) · **Rama:** `claude/regla-chat-integrador`
**Qué cambia:** `AGENTS.md` (sección «Integración centralizada» y paso 3 de «Empieza aquí») y `CLAUDE.md`: cada chat abre
su PR sin fusionarlo; un único chat integrador fusiona los PR en `develop` de uno en uno, resuelve los conflictos
conservando las dos partes y solo fusiona con el CI en verde.
**Por qué:** la build 177 salió sin los PR #84 (LIVE) y #87 (botones de Motor y «Análisis motor»), que seguían abiertos
mientras otros chats fusionaban sus cambios del motor.
**No se ha tocado:** código, workflows, firmas, `Info.plist`, número de build de TestFlight.
**Validación:** solo documentación.

## 2026-11-19 — iPad LIVE + Android 2.10-live-dev1 (vc 43) + reglas Firebase `live/` — directo desde el servidor
**Autor:** Claude (boceto del entrenador sobre la captura de la build 171; decisión del usuario: «El iPad es Live desde el servidor») · **Rama:** `claude/live-servidor` · **CI:** los workflows solo se ejecutan al fusionar en `develop` (Android, iPad/TestFlight y reglas Firebase)
**Qué cambia:**
- **iPad:** nueva página **LIVE** en la barra lateral, debajo de «Carreras».
  - Arriba, datos en tiempo real: tiempo, distancia, velocidad, aceleración, aire, tiempo y distancia del aire, GNSS.
  - El mapa centrado sigue al caballo («Centrar» / «Ver todo»).
  - Sobre la parte baja del mapa, la velocidad en tiempo real.
  - Debajo, las gráficas de pulso y de aceleración.
  - Sin panel derecho y sin barra de pestañas.
  - Entrada con la tarjeta AVO (enlace, o código y clave; se guarda en el Llavero).
  - Firebase por REST, sin SDK: `Core/LiveCodec.swift`, `Core/LiveFirebase.swift`, `App/LiveModel.swift`, `Views/LiveView.swift`.
  - Simulación con el entrenamiento abierto, marcada SIMULACIÓN. Captura nueva «Live» en `ScreenshotTests`.
- **Android 2.10-live-dev1 (vc 43):** `core/.../live/LiveCodec.kt` (formato `LIVE1` + `LiveRecorder`, con pruebas) y
  `app/.../cloud/LiveShare.kt`, que sube la `TELEMETRY` mientras el pecho graba.
  - Interruptor «Directo (LIVE en el iPad)» en Compartir, desactivado por defecto.
  - «Entrar en el iPad (LIVE)» en Mi cuenta, que muestra el código y la clave o comparte el enlace.
- **Firebase:** nodo `live/{owner}/{sid}` (`meta`, `last`, `s/{n}`). Escribe solo el dueño registrado. Leen el dueño y
  quien tenga sus envíos ACCEPTED. Cuatro pruebas nuevas en `rules.test.js`.
- Documento `docs/LIVE_SERVIDOR.md`.
**Por qué:** el entrenador quiere ver el entrenamiento en directo en el iPad. El pecho acepta un solo móvil (el Android,
que manda el RTCM), así que el directo va por el servidor.
**No se ha tocado:** firmware, contratos binarios (`TELEMETRY v3` igual), workflows, firmas, `Info.plist`, número de
build de TestFlight, `google-services.json`. Sin dependencias nuevas en el iPad.
**Validación:** IMPLEMENTADO · CI lanzado a mano en la rama (commit `3b03740`):
- reglas Firebase run 44565056559 ✅, 15/15 (4 nuevas de LIVE);
- Android run 44565050754 ✅ (APK y pruebas core con `LiveCodecTest`);
- iPad run 44565045768 ✅, sin TestFlight: compila y pasan 121 pruebas unitarias, 5 de ellas de `LiveCodecTests`.

Las capturas de UI fallan desde antes en casi todas las páginas («No existe nav.X»: 44 fallos en el último run de
`develop`, 44524012083). La nueva captura «Live» sufre el mismo problema, así que no hay captura de la pantalla.
**NO VERIFICADO** en hardware.
**Pendiente:**
1. Publicar las reglas a mano en la consola de Firebase cuando `firebase-rules.yml` pase.
2. Comprobar que la clave web de Firebase acepta llamadas desde el iPad. Si no, añadir una app iOS (ver `docs/LIVE_SERVIDOR.md`).
3. Prueba en pista: pecho + Android + iPad.
4. Pulso y aceleración de la IMU en directo (`TELEMETRY v4`, otro lote).
5. LIVE en Windows.
## 2026-11-19 — Motor 2.0.0-dev10 — KB-1 1.8.0: estudio extra 5 (modelo óseo B y playa por franja)
**Autor:** Claude (a petición del usuario: «lanza otro estudio ahora») · **Rama:** `claude/kb-estudio5-2026-11-19` (desde `develop` con PR #85–#87 fusionados) · **CI:** motor lanzado a mano en la rama (resultado en el PR)
**Qué cambia:**
- **Estudio** `equine-intelligence/knowledge/estudios/2026-11-19_extra5_modeloB_signo_b_playa_franjas.md`, con cifras
  etiquetadas [E]/[E-r]/[I]/[NV]. (1) **Modelo óseo B:** signo de b cerrado (−0,02 en la tabla 9 de Anwar 2026, arXiv
  HTML, y en Hitchens 2018; convención S_v = a·√(1 − f)·[1 − b(1 − f)]) y f_BM(0) = 0,61 (Pan 2025). El paso de
  integración no se publica y la tabla 4 de Anwar no se reproduce sin el código (Zenodo bloqueado). (2) **Playa por
  franja:** solo hay datos de playa de trotones al trote (Chateau 2011, Crevier-Denoix 2011); en PSI al galope el suelo
  cambia la zancada hasta 0,186 m a igual velocidad (Pfau 2024), más que el umbral de A7. Propuestas PL1–PL6.
- `base_cientifica.json` 1.8.0: **corrección de `modelo_B_constantes.b` de +0,02 a −0,02** (no afecta a ningún
  cálculo: el modelo B sigue PENDIENTE), f_BM inicial, regla `PLAYA_LINEA_BASE_PL1_PL6` (PENDIENTE), 7 fuentes nuevas,
  pendientes y cola actualizados. Ficha 14, tabla de estado y README.
- **Motor sin cambios de lógica:** `KNOWLEDGE_VERSION` 1.7.0 → 1.8.0 y `ENGINE_VERSION` 2.0.0-dev9 → 2.0.0-dev10;
  fixtures regenerados (solo versiones).
**Por qué:** el modelo B y la línea base de la playa son pendientes que bloquean código.
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`, número de build de TestFlight, apps.
**Validación:** IMPLEMENTADO (solo versiones) · pruebas locales con ASan/UBSan: 102 casos y 1.729 comprobaciones sin
fallos; Release y `check_fixtures.py` en verde tras `--update` (diferencias: solo versiones) · CI: ver PR ·
**NO VERIFICADO** con caballos reales. La fatiga ósea del modelo B no es una predicción de lesiones.
**Pendiente:** código de Anwar/Pan para el paso de integración; campo de franja y marea en las apps; textos completos
de Chateau 2011 y Crevier-Denoix 2011.

## 2026-11-19 — iPad 1.0.0 — Botones de la pestaña Motor y «Análisis motor» de carreras
**Autor:** Claude (a petición del usuario, capturas del build 173 marcadas) · **Rama:** `claude/motor-botones-analisis-carreras` (desde `develop` `fb9de38`) · **Commits:** `e73fca3`, `af7541c` · **PR:** #87 · **CI:** iPad run 44611181120 ✅ (sin TestFlight)
**Qué cambia:**
- **Pestaña Motor:** columna de botones arriba a la derecha de «Lectura del entrenamiento»: **Reprocesar** (motor
  actual, forzado), **Reprocesar caballo** (todos los entrenamientos del mismo caballo, con confirmación y progreso),
  **Exportar JSON** (resultado del motor a Documentos › Exportados y hoja de compartir), **Detalle técnico** (abre y
  baja a las tablas) y **Borrar caché** (borra los `analisis_*.json` guardados; no toca entrenamientos, correcciones ni
  valoraciones). También aparece cuando el entrenamiento aún no tiene análisis.
- **Carreras › detalle:** botón **«Análisis motor»** entre «Informe PDF» y «PDF original». Abre una pantalla completa que
  pasa el motor actual por los entrenamientos de los 60 días previos y recalcula informe, forma y tramo a tramo
  («Volver a analizar» fuerza el motor). Contenido en lenguaje llano: resumen en una frase; salida, desarrollo y final
  frente al ganador y al caballo medio; gráficas de puesto, distancia al primero (cuerpos) y velocidad por tramo;
  rivales con su **cara a cara** en carreras anteriores del iPad y sus otras carreras; **carreras anteriores** del
  caballo por **distancia** (±100 m), **estado de pista** e **hipódromo** con gráfica de puesto relativo;
  entrenamientos (mejores 200/400/600 m, tendencia, caída, forma/ACWR) con gráfica; conclusiones, «para la próxima»
  (orientativo), confianza y método.
- **Estado de la pista** (`Race.going`, escala France Galop de *Très léger* a *Très lourd*, grupos firme/bueno/blando/
  pesado): se anota a mano en esa pantalla porque el PDF de tracking no lo trae. Campo opcional: `carreras.json`
  anterior se sigue leyendo.
- Lógica en `ipad/AVOiPad/Core/RaceDeepEngine.swift` (funciones puras) con `RaceDeepEngineTests` (5 pruebas).
  `RaceReport.fastWorkList` (aditivo). Archivos: `App/AppModel+EngineTools.swift`, `App/RacesModel.swift`,
  `Core/RaceAnalysis.swift`, `Core/RaceModels.swift`, `Views/EngineView.swift`, `Views/RaceDetailView.swift`,
  `Views/RaceEngineAnalysisView.swift`.
**Por qué:** el usuario pidió botones en Motor y un análisis en profundidad de cada carrera con entrenamientos,
carreras anteriores, mismos rivales, misma distancia y estado de pista, con gráficas y entendible.
**No se ha tocado:** motor C++, firmware, contratos binarios, Android, Windows, workflows, firmas, `Info.plist`,
número de build de TestFlight. Las carreras siguen siendo solo del iPad (como el resto de Carreras).
**Validación:** IMPLEMENTADO · COMPILADO / CI: run 44611181120 en `e73fca3`, compilación ✅ y 121/121 pruebas unitarias ✅ (5 nuevas); capturas de UI con los 44 fallos que ya había en `develop` · **NO VERIFICADO** en el iPad. Las comparaciones con carreras
anteriores solo usan las carreras importadas en el iPad; con menos de 3 son una pista, no una conclusión.
**Pendiente:** probar en el iPad con carreras reales; leer el estado de pista de France Galop si su ficha lo muestra;
añadir el análisis al Informe PDF si el usuario lo quiere.
## 2026-11-19 — Motor 2.0.0-dev9 — KB-1 1.7.0: estudio extra 4 (auditoría de fuentes, tendón en árabes, V200 con trotones)
**Autor:** Claude (tarea programada, estudio extra 4) · **Rama:** `claude/kb-estudio4-2026-11-19` (desde `claude/kb-estudio3-2026-11-19`, PR #85 abierto) · **CI:** motor lanzado a mano en la rama (resultado en el PR)
**Qué cambia:**
- **Estudio** `equine-intelligence/knowledge/estudios/2026-11-19_extra4_auditoria_fuentes_tendon_arabes_v200_trotones.md`
  (etiquetas [E]/[E-r]/[I]/[I-raza]/[NV] y tipo de acceso). (1) **Auditoría** de 9 fuentes que sostienen reglas del
  motor; 6 mejoradas (Perkins 2005 a texto completo, tesis de Massey). Correcciones de ámbito, sin cambiar constantes:
  Morrice-West 2025 es de Tasmania, da HR y su «carga baja» es fatiga ósea < 0,25 en 4 salidas (el corte de A4 es [I]);
  Carrier 1998 solo húmero; Vermeulen & Evans «diferencia media ≤ 2 %» (no CV; el +8 % es de prensa); Frick 2019 canter
  en cinta (corte 6 %: S 88 %, E 97 %); Martig 2013 confirmada. (2) **Tendón en árabes:** sin OR/IRR publicadas (Golfo,
  Turquía, Polonia); edad 3–4 años con tres fuentes (Çalışkan 2020 texto completo, Pap 2026 Doha); la carga solo se
  asocia a la gravedad; CSA del TFDS árabe 62–94 mm² (Çelimli 2000); trotones solo como dirección [I-raza].
  (3) **V200/VHRmax:** trotones (Leleu, Couroucé, Hamlin, Ringmark) como método [I-raza]; Corea (Lee 2019) y Brasil
  (Alonso 2013, árabes en cinta); no hay TE publicado legible en PSI/árabe → TE propio del caballo.
- `base_cientifica.json` 1.7.0: campos `acceso`, `verificado_fecha`, `pais`, `idioma`, `raza_fuente`; 17 fuentes nuevas;
  notas de A3, A4, A5, A9, índice tendinoso, σ0, VHRmax y ECG; pendientes y cola actualizados; niveles E-r e I-raza.
- Se descartó por legalidad una lectura en una copia no autorizada de un libro comercial (sin usar cifras).
- **Motor sin cambios de lógica:** `KNOWLEDGE_VERSION` 1.6.0 → 1.7.0 y `ENGINE_VERSION` 2.0.0-dev8 → 2.0.0-dev9;
  fixtures regenerados (solo versiones). Ficha 14, tabla de estado y README.
**Por qué:** estudio extra pedido por el usuario (modo meticuloso, mundial y multirraza).
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`, número de build de TestFlight, apps.
**Validación:** IMPLEMENTADO (solo versiones) · pruebas locales con ASan/UBSan (ctest en verde) y Release: 102 casos y
1.729 comprobaciones sin fallos; `check_fixtures.py` en verde tras `--update` (diferencias: solo versiones) · CI: ver PR ·
**NO VERIFICADO** con caballos reales. La fatiga ósea es un índice de carga, no una predicción de lesiones.
**Pendiente:** textos completos bloqueados (Martig 2013, Morrice-West 2025, Estberg 1998, Vermeulen/Gramkow 2006, Frick
2019 en PMC desde un navegador), DOI de Carrier 1998, Çelimli 2004 completo; línea base de la playa.

## 2026-11-19 — Motor 2.0.0-dev8 — KB-1 1.6.0: estudio extra 3 (planificador semanal y ECG / A11)
**Autor:** Claude (tarea programada, estudio extra 3) · **Rama:** `claude/kb-estudio3-2026-11-19` (desde `develop` con PR #80–#83 fusionados) · **CI:** motor lanzado a mano en la rama (resultado en el PR)
**Qué cambia:**
- **Estudio** `equine-intelligence/knowledge/estudios/2026-11-19_extra3_planificador_semanal_ecg_a11.md`, con cifras
  etiquetadas [E]/[E-r]/[I]/[NV]. (1) **Planificador semanal:** práctica publicada (≈ 2 trabajos rápidos/semana en PSI
  maduros y 1,7 en 2 años; ~8 km/mes a ≥ 13,3 m/s; un día libre; ~2 descansos/año de ~6 semanas; carreras cada
  2,3 semanas), carga del último mes protectora frente a la de 60–180 d (Hitchens 2018, Georgopoulos & Parkin 2017) y
  seis restricciones P1–P6 propuestas. No hay evidencia publicada de días entre trabajos rápidos ni de árabes de llano.
  (2) **ECG / A11:** detector anclado en el pico S (Van Steenkiste 2020: VPP 99,1 %, S 98,0 % en reposo; Pan-Tompkins
  81,5/91,5), prematuro ≥ 5–6 % (Navas de Solis 2026, Frick 2019), fases (Marr 2020: 50,6 % en la recuperación), puerta
  de calidad del 10 % y acuerdo entre observadores en ejercicio 0–13 % (Trachsel 2011).
- `base_cientifica.json` 1.6.0: 10 fuentes, regla `PLANIFICADOR_RESTRICCIONES_P1_P6` (PENDIENTE), nota en `A11_ECG`,
  pendientes de ECG y planificador reescritos, 4 temas nuevos en la cola. Ficha 14, tabla de estado y README.
- **Motor sin cambios de lógica:** `KNOWLEDGE_VERSION` 1.5.0 → 1.6.0 y `ENGINE_VERSION` 2.0.0-dev7 → 2.0.0-dev8 para que
  el análisis declare la base vigente; fixtures regenerados (solo las dos versiones).
**Por qué:** estudio extra pedido por el usuario sobre pendientes que bloquean código (planificador y A11).
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`, número de build de TestFlight, apps.
**Validación:** IMPLEMENTADO (solo versiones) · pruebas locales con ASan/UBSan: 102 casos y 1.729 comprobaciones sin
fallos; Release y `check_fixtures.py` en verde tras `--update` (diferencias: solo versiones) · CI: ver PR ·
**NO VERIFICADO** con caballos reales. Las restricciones son de prudencia, no predicciones de lesión.
**Pendiente:** validar un detector de QRS con galope real anotado (cincha PROTOTIPO REV 5.10); implementar P1–P6 cuando
haya semanas reales de la cuadra; leer PMC12699123, Flethøj 2016 y Frick 2019 completos.

## 2026-11-19 — Motor 2.0.0-dev7 — KB-1 1.5.0: reglas A7 y A8 aplicadas (línea base propia + CUSUM autoiniciado)
**Autor:** Claude (a petición del usuario: «fusiona y empieza a aplicar las reglas») · **Rama:** `claude/kb-reglas-lineas-base-2026-11-19` (desde `develop` con PR #82 fusionado) · **CI:** motor lanzado a mano en la rama (resultado en el PR)
**Qué cambia:**
- **Training Analytics aplica A7 y A8** en cada sesión y en el estado actual: `A7_CAIDA_ZANCADA` (zancada a la velocidad
  de referencia ≥ 0,10 m bajo la línea base comparable, VIGILAR) y `A8_CAIDA_VELOCIDAD_FINAL` (últimos 600 m del trabajo
  rápido ≥ 0,20 m/s más lentos, INFO; VIGILAR si también lo confirma el CUSUM). Comparables = misma superficie. Criterio:
  la última y 2 de las 3 últimas bajo el umbral (≥ 5 sesiones de base), o CUSUM autoiniciado de Hawkins (k 0,5, h 5,
  calentamiento 8). Aparecen en `base_cientifica.reglas` y en los motivos, así que las apps las muestran sin cambios.
- `kb_drift_down` en `knowledge.h`; `RaceSummary.v_last_600` (campo `v_ultimos_600m` en el resumen de sesión, aditivo);
  opciones JSON nuevas en `base_cientifica`; `reglas` se escribe aunque falte el bloque de carga si hay avisos A7/A8.
- Exclusión de la base con S > 0,8·h elegida por simulación propia (falsa alarma 11,4 % en 100 sesiones frente a
  23,7 % con h/2; detección de 3 DE en ≤ 6 sesiones 91,5 %).
- `KNOWLEDGE_VERSION` 1.4.0 → 1.5.0; `ENGINE_VERSION` 2.0.0-dev6 → 2.0.0-dev7. `base_cientifica.json` 1.5.0 (A7 y A8
  IMPLEMENTADO), ficha 14, tabla de estado, README y fixtures (solo versiones).
**Por qué:** el usuario pidió que las reglas se apliquen ya; A9 sigue pendiente porque el análisis no trae V200 (ECG).
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`, número de build de TestFlight, apps.
**Validación:** IMPLEMENTADO · pruebas locales con ASan/UBSan: 102 casos y 1.729 comprobaciones sin fallos; Release y
`check_fixtures.py` en verde · CI: ver PR · **NO VERIFICADO** con caballos reales. Los umbrales son de partida [I]; son
avisos para revisar al caballo, no predicciones de lesión.
**Pendiente:** TE propio por métrica con las sesiones del PROTOTIPO; playa por franja como superficie; A9 con el ECG.

## 2026-11-19 — Motor 2.0.0-dev6 — KB-1 1.4.0: estudio extra 2 (CUSUM con pocas sesiones, tendón en árabes, IDF) y CUSUM autoiniciado
**Autor:** Claude (tarea programada, estudio extra 2) · **Rama:** `claude/kb-estudio2-2026-11-19` (desde `develop`, con PR #80 y #81 fusionados) · **CI:** motor lanzado a mano en la rama (resultado en el PR)
**Qué cambia:**
- **Estudio** `equine-intelligence/knowledge/estudios/2026-11-19_extra2_cusum_autoiniciado_tendon_arabes_idf.md`,
  con cifras etiquetadas [E]/[E-r]/[I]/[NV] y decisiones al principio. (1) CUSUM con μ y σ estimadas de 5–20
  sesiones: el ARL0 por caballo no es el nominal (simulación propia: m = 10, h = 4 → P10 = 23 sesiones frente a 335);
  la tipificación autoiniciada de Hawkins 1987 lo recupera (339/930). (2) TFDS: OR univariables de Ikeda 2019 (PSI,
  Japón) y, en árabes, TFDS = 83 % de las tendinopatías (Kalisiak 2012) y pico de lesiones de tendón a los 3 años
  (Yıldırım & Karaarslan 2025). (3) France Galop **no publica ningún IDF**: el pendiente pasa a una métrica propia de
  velocidad final relativa con par por pista (referencia: Finishing Speed % de Timeform).
- **Motor (un pendiente):** `kb_self_starting_z`, `kb_student_t_cdf` y `kb_normal_quantile` en `knowledge.h`, con la
  prueba `kb.baseline_self_starting_cusum`. **No se conectan a ninguna regla**; la salida del análisis solo cambia en
  las versiones. `KNOWLEDGE_VERSION` 1.3.0 → 1.4.0; `ENGINE_VERSION` 2.0.0-dev5 → 2.0.0-dev6.
- **`base_cientifica.json` 1.4.0:** 5 parámetros y 9 fuentes nuevos; `pendiente_motor` (líneas base e IDF) y
  `cola_investigacion` actualizados; historial.
- Ficha `docs/algoritmos/14_BASE_CIENTIFICA.md`, fila del motor en la tabla de estado y `README.md`.
- Fixtures `core/src/test/resources/equine/*.json` regeneradas con `--update` (solo cambian las versiones).
**Por qué:** estudio extra pedido por el usuario (máx. 1 h); conectar las líneas base a Training Analytics con pocas
sesiones exige un CUSUM que no dispare falsas alarmas de más.
**No se ha tocado:** firmware, contratos binarios, workflows, firmas, `Info.plist`, TestFlight, apps.
**Validación:** IMPLEMENTADO · pruebas locales con ASan/UBSan: 100 casos y 1.703 comprobaciones sin fallos; Release y
`check_fixtures.py` en verde · CI: ver PR · **NO VERIFICADO** con caballos reales. La carga tendinosa y la fatiga ósea
son índices de carga, nunca predicciones de lesión.
**Pendiente:** conectar `kb_self_starting_z` + CUSUM a A7–A9 (TE por métrica, superficie); cuantificar el efecto del
shrinkage y de la autocorrelación; textos bloqueados (Jones 2004, Saleh 2016, Hawkins 1987, Takahashi 2004, Lam 2007);
revisar a mano las OR de Ikeda 2019 y los recuentos de *foulées* de France Galop.

## 2026-11-19 — Motor 2.0.0-dev5 — KB-1 1.3.0: estudio extra (tendón, V200, líneas base, playa, France Galop) y herramientas de línea base
**Autor:** Claude (tarea programada, estudio extra) · **Rama:** `claude/kb-estudio-2026-11-19` (sale de `claude/kb-noche-2026-11-19`, PR #80, sin fusionar) · **CI:** motor lanzado a mano en la rama (resultado en el PR)
**Qué cambia:**
- **Estudio** `equine-intelligence/knowledge/estudios/2026-11-19_extra_tendon_v200_lineas_base_playa.md`, con cada
  cifra etiquetada [E]/[E-r]/[I]/[NV] y las decisiones al principio. Temas: índice tendinoso (árabes: vuelven a correr
  el 15 % frente al 41 % de PSI, Kalisiak 2012; no hay curva S-N del tendón, se retira el exponente de carga); V200 y
  recuperación de FC (retraso de FC, ventanas de 4 y 15 min); líneas base (ARL del CUSUM recalculados: 335 unilateral
  con h = 4, los 168 eran bilaterales; z atípico 3,5; umbral de cambio 2·TE·√(1 + 1/n)); playa por franjas (Chateau y
  Crevier-Denoix 2011, trotones); France Galop publica parciales por 200 m y zancadas desde 2025 (árabes ≈ 2,4–2,5 Hz).
- **Motor (un pendiente):** herramientas de línea base en `knowledge.h`: `kb_robust_baseline`, `kb_robust_z`,
  `kb_shrink_mean`, `kb_change_threshold` y `kb_cusum_upper` (k 0,5, h 4, FIR opcional). **No se conectan a ninguna
  regla** y la salida del análisis no cambia (solo versiones). `KNOWLEDGE_VERSION` 1.2.0 → 1.3.0; `ENGINE_VERSION`
  2.0.0-dev4 → 2.0.0-dev5.
- **`base_cientifica.json` 1.3.0:** 13 parámetros nuevos, regla pendiente `TENDON_INDICE_HEURISTICO`, 19 fuentes
  nuevas, nota de Önder 2022 (los 0,9 m/s son una resta), pendientes y cola renovados.
- Ficha 14 (apartado 3 quater), fixtures de Kotlin regeneradas (solo versiones) y fila del motor en la tabla de estado.
**Por qué:** estudio extra pedido por el usuario sobre los temas que bloquean código.
**Archivos:** `equine-intelligence/{include/avo_eq/knowledge.h, include/avo_eq/types.h, src/knowledge/knowledge.cpp,
tests/test_knowledge.cpp, knowledge/base_cientifica.json, knowledge/estudios/…, docs/algoritmos/14_BASE_CIENTIFICA.md}`,
`core/src/test/resources/equine/{sample,synthetic}_analysis.json`, `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`.
**No se ha tocado:** firmware, workflows, firmas, `Info.plist`, TestFlight ni contratos binarios.
**Validación:** IMPLEMENTADO · pruebas locales con ASan/UBSan: 99 casos, 1.684 comprobaciones, 0 fallos · fixtures OK
tras `--update` · CI: ver PR · **NO VERIFICADO** con caballos reales.
**Pendiente:** conectar las líneas base a A7/A8/A9 con TE propios; índice tendinoso; V200 (A9); IDF de France Galop;
línea base de playa por franja.

---

## 2026-11-19 — Motor 2.0.0-dev4 — KB-1 1.2.0: investigación nocturna (modelo B, tendón, árabes, arritmias) y regla A6B
**Autor:** Claude (tarea programada nocturna) · **Rama:** `claude/kb-noche-2026-11-19` (sale de `develop`) · **CI:** motor lanzado a mano en la rama (resultado en el PR)
**Qué cambia:**
- **Estudio** `equine-intelligence/knowledge/estudios/2026-11-19_noche_modeloB_tendon_choi_ecg_prevalencia.md`, con
  cada cifra etiquetada [E]/[E-r]/[I]/[NV] y las decisiones de la noche al principio.
- **Motor (un pendiente):** regla nueva **A6B_POCO_GALOPE_60D** (Choi & Parkin 2025, texto completo, tabla 2: ≤ 2 días
  de galope en 60 d, OR 1,842, IC 95 % 1,073–3,162 de tendinopatía del TFDS). Solo INFO / AVISO, con 60 d de historia y
  sesiones en la última semana; «día de galope» = día con sesión rápida es [I]. Campo nuevo `dias_galope_60d` en el
  estado de la base científica y opción `base_cientifica.dias_galope_60d_max` (0–24, por defecto 2).
  `KNOWLEDGE_VERSION` 1.1.0 → 1.2.0; `ENGINE_VERSION` 2.0.0-dev3 → 2.0.0-dev4.
- **`base_cientifica.json` 1.2.0:** constantes del modelo B completas (A_OBL_min/max, δ_B, γ_B, A_OCL_max; tabla 9 de
  Anwar 2026, extracto [E-r]) pero **sin implementar** (signo de b dudoso, f_BM inicial no publicada); tabla 2 de Choi &
  Parkin; tipos de lesión de árabes (tendón 64 %, Yildirim 2025); prevalencia de arritmias en caballos sanos (A11 sigue
  pendiente: no hay número aceptable publicado); 9 fuentes nuevas; cola y pendientes renovados.
- Fixtures JSON (`core/src/test/resources/equine/*.json`) regeneradas con `check_fixtures.py --update`: solo cambian
  las versiones del motor y de la base (2.0.0-dev3 → dev4, 1.1.0 → 1.2.0).
- Ficha `docs/algoritmos/14_BASE_CIENTIFICA.md` actualizada.
**Por qué:** investigación nocturna programada de la base científica de la cuadra.
**No se ha tocado:** firmware, workflows, firmas, `Info.plist`, TestFlight y contratos binarios. La API C no cambia.
**Validación:** IMPLEMENTADO · pruebas locales con `-DAVO_EQ_SANITIZE=ON` (ASan/UBSan): 96 casos y 1.638 comprobaciones
sin fallos (nueva `kb.rule_low_gallop_days_60d`) · fixtures OK con el CLI en Release. **NO VERIFICADO** con caballos
reales.
**Pendiente:** modelo B (signo de b, f_BM inicial, reproducir la tabla 4 de Anwar); cociente de galope de A6; A8; A9;
A11; regla combinada de Verheyen; pantallas de las apps para A6B.

## 2026-11-18 — Documentación — skills de Claude en `AGENTS.md`
**Autor:** Claude · **Rama:** `claude/skills-agents`
**Qué cambia:** `AGENTS.md` gana la sección «Skills de Claude» (qué skill cargar según la tarea: `avo-cambio-protocolo`,
`avo-release-firmware`, `avo-revision-pcb-cad` y los plugins Engineering, code-review, Data, github y swift-lsp) y el
paso 6 de «Empieza aquí». El mismo contenido está en `CLAUDE.md` del proyecto de claude.ai.
**Por qué:** petición del usuario, para que todos los chats de Claude usen las skills activadas el 18/11/2026.
**Archivos:** `AGENTS.md`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** código, firmware, workflows ni versiones. La tabla «Vigente» no cambia (no hay versiones nuevas).
**Validación:** solo documentación; no aplica CI ni prueba física.

## 2026-11-18 — Cincha CAD REV 6.5 → 7.0 integrada en `develop`
**Autor:** Claude · **Rama:** `claude/integrar-cad-cincha-rev7`
**Qué cambia:** se integra en `develop` la cadena de PR del CAD de la cincha (#67 a #73, REV 6.5 → REV 7.0 con 3 IMU),
cuyos cambios pidió o decidió el usuario. Iban apilados sobre la rama del #60, ya fusionada. El único conflicto era el
registro de cambios: se conservan las entradas de los dos lados. Tabla de estado: fila de la cápsula BETA en REV 7.0.
**Validación:** diseño. Las medidas del pogo de 6 pines y de las PCB del soporte y los satélites son PROVISIONALES. Nada
fabricado.

## 2026-11-18 — Motor 2.0.0-dev3 — CI en verde en `develop`
**Autor:** Claude · **Commits:** `e45c103` (#74), `c3dd769` (#75), `5747dbc` (#76)
**CI:**
- motor 44299049283 ✅ (lanzado a mano: el workflow no se dispara en `develop`);
- iPad y TestFlight 44295513273 ✅;
- Android 44299040682 ✅;
- Windows 44299040506 ✅;
- descargas 44299040623 ✅.
**Validación:** COMPILADO / CI. **NO VERIFICADO** con caballos reales.

## 2026-11-18 — Motor 2.0.0-dev3 — fixtures JSON regeneradas tras KB-1
**Autor:** Claude · **Rama:** `claude/fixtures-motor-dev3`
**Qué cambia:** `core/src/test/resources/equine/synthetic_analysis.json` y `sample_analysis.json` regeneradas con
`check_fixtures.py --update`. Diferencias, todas esperadas: versión del motor (2.0.0-dev1 → 2.0.0-dev3), bloque
`trabajo_pista.base_cientifica`, `perfil.v_carrera` y `procedencia.algoritmos.base_cientifica`.
**Por qué:** tras fusionar los PR #74 y #75, la ejecución manual del workflow del motor (run 44297079489) falló solo en
la comprobación de fixtures. Las pruebas del motor pasaron: 95 casos, 1627 comprobaciones, 0 fallos (ASan/UBSan).
Android, Windows y las 3 ABI de Android compilaron en verde.
**Nota:** `build-equine-engine.yml` no se dispara con push a `develop` (solo en ramas antiguas), así que hay que lanzarlo
a mano. No se ha cambiado el workflow; avisado al usuario.
**Validación:** comprobación local de fixtures OK. **NO VERIFICADO** con caballos reales.

## 2026-11-18 — Motor 2.0.0-dev3 — KB-1 1.1.0: investigación nocturna (σ0, Verheyen, árabes, cincha, ECG, V200) y velocidad de los últimos 600 m
**Autor:** Claude (tarea programada nocturna) · **Rama:** `claude/kb-noche-2026-11-18` (sale de `claude/base-cientifica-cuadra`, PR #74) · **CI:** pendiente del push a `develop`
**Qué cambia:**
- **Estudio** `equine-intelligence/knowledge/estudios/2026-11-18_noche_sigma0_verheyen_arabes_cincha_ecg_v200.md`, con
  cada cifra etiquetada [E]/[E-r]/[I]/[NV] y las decisiones de la noche al principio.
- **σ0 aclarado:** 134,2 MPa es la curva de sensibilidad de Martig 2013 (la de Morrice-West 2022, modelo A); 139,0 MPa
  es la calibración in vivo de Pan 2025 para el modelo B. El modelo A **no cambia**. Corregida la nota de σ_max
  (54–90 MPa eran los niveles del ensayo).
- **Motor (un pendiente):** `kb_final_speed` y campos `v_ultimos_600m` / `ultimos_600m_s` en cada trabajo de ≥ 600 m
  (definición de Schrurs 2024). La regla A8 pasa a PARCIAL (falta umbral). `KNOWLEDGE_VERSION` 1.0.0 → 1.1.0;
  `ENGINE_VERSION` 2.0.0-dev2 → 2.0.0-dev3.
- **`base_cientifica.json` 1.1.0:** 16 fuentes nuevas; parámetros nuevos (velocidad final, constantes del modelo B,
  rango del acelerómetro de la cincha [I], definiciones de ECG, corte de VHRmax del PSI); notas corregidas (σ0, σ_max,
  Verheyen, v_carrera del árabe: los 14,2 m/s polacos eran de 3.000 m); regla pendiente A1A2_VERHEYEN_COMBINADO; cola
  de investigación renovada. El archivo pasa a formato con sangría (mismo contenido de los campos anteriores).
- Ficha `docs/algoritmos/14_BASE_CIENTIFICA.md` actualizada.
**Por qué:** investigación nocturna programada de la base científica de la cuadra.
**No se ha tocado:** firmware, workflows, firmas, `Info.plist`, TestFlight y contratos binarios. La API C no cambia: los
campos nuevos van dentro del JSON. Las reglas A1 y A2 no cambian (evidencia no cerrada).
**Validación:** IMPLEMENTADO · pruebas locales con `-DAVO_EQ_SANITIZE=ON` (ASan/UBSan): 95 casos y 1.627 comprobaciones
sin fallos (nueva `kb.final_speed_last_600m`; `pista.base_cientifica_kb1` ampliada). CI: pendiente. **NO VERIFICADO**
con caballos reales.
**Pendiente:** regla A8 con línea base; modelo B (faltan 5 constantes); A11 con el texto completo de Van Erck 2026;
V200/VHRmax; regla combinada de Verheyen; pantallas de las apps para la velocidad final.

## 2026-11-18 — Motor 2.0.0-dev2 — Base científica de la cuadra KB-1 1.0.0 (PSI y árabe de carreras)
**Autor:** Claude · **Rama:** `claude/base-cientifica-cuadra` · **CI:** pendiente del push a `develop`
**Qué cambia:**
- **Módulo nuevo** `equine-intelligence/src/knowledge` (`knowledge.h`, ficha `docs/algoritmos/14_BASE_CIENTIFICA.md`):
  - fatiga del hueso subcondral por zancada (Morrice-West 2022), con σ_max y σ0 configurables, rango validado
    12,57–21 m/s y el trabajo lento aparte como «extrapolado»;
  - distancias por banda relativas al ritmo de carrera (PSI 16,7 m/s, árabe 14,5 m/s, o el del caballo con
    `v_carrera_m_s`) y contadores de Verheyen (canter ≤ 14 m/s y galope > 14 m/s en PSI);
  - reglas sobre la historia con su evidencia: A1 canter en 30 d, A2 galope rápido en 30 d, A3 rampa, A5 vuelta tras
    ≥ 60 d sin trabajo rápido, A6 vuelta tras ≥ 90 d (tendón) y fatiga ósea de 7 d frente a la semana habitual.
- **Track Work:** bloque `trabajo_pista.base_cientifica`; `perfil.v_carrera`; la zancada del árabe se compara a
  **13 y 14 m/s** (antes 13 y 15).
- **Training Analytics:** el resumen guarda el bloque; la historia añade `estado.base_cientifica` y
  `sesiones[].base_cientifica`, y las reglas VIGILAR suben el estado. Opción `base_cientifica` (`true`/`false` u objeto).
- **Base de conocimiento versionada:** `equine-intelligence/knowledge/base_cientifica.json` (fuentes, parámetros,
  reglas, pendientes y cola de investigación) y los dos estudios en `equine-intelligence/knowledge/estudios/`.
- `ENGINE_VERSION` 2.0.0-dev2; `algorithm_versions` incluye `base_cientifica`.
**Por qué:** el usuario pide integrar el análisis de la literatura como base del modelo de la cuadra y ampliarlo cada
semana durante las pruebas de campo del PROTOTIPO, hasta la primera versión oficial.
**No se ha tocado:** contratos binarios (`BackStatus`, ESP-NOW, `TELEMETRY`, `AVO1`, `.avr`), firmware, workflows,
firmas ni `Info.plist`. La API C no cambia: los campos nuevos van dentro del JSON.
**Validación:** IMPLEMENTADO · pruebas locales con ASan/UBSan: 94 casos y 1607 comprobaciones sin fallos (incluye los
valores de referencia del modelo óseo: 1.200 m a 16,7 m/s = 8,64 %). CI: pendiente. **NO VERIFICADO** con caballos
reales.
**Pendiente:** pantallas en Android, Windows e iPad; frecuencia de zancada medida por la cincha; modelo óseo con
reparación (Pan/Anwar); V200 y ECG; CUSUM y shrinkage; últimos 600 m; IDF de carreras; planificador semanal
(lista completa en `base_cientifica.json`).

## 2026-11-14 — Espalda V5 CASCO: anillo de luz (8 LED laterales) y caja sin juntas
**Autor:** Claude · Rama `feature/back-v5-casco`
**Qué cambia:**
- **PCB:**
  - 8 × SK6812SIDE-A (C5378721), 2 por lado, en los cantos de la cara F, en cadena desde el GPIO47 (33 Ω, C25105) y alimentados de VSYS;
  - pads de la batería movidos a (−17,3 / −14,5; −23);
  - una vía de LED_D4 alejada del canto.
  - Puerta superada: DRC 0, 0 conexiones incompletas, paridad 0, ERC 0/0 y todas las piezas con código LCSC.
- **CAD:**
  - anillo de resina translúcida de **una pieza**, de 3,0 mm, centrado en los LED (z 10,4–13,4);
  - **sin juntas TPU**: las uniones del anillo van pegadas;
  - la tapa baja por fuera del canto de la PCB;
  - el imán del Hall de la base del casco ya no queda cortado por la ventana central.
- **Workflows nuevos** (solo en esta rama): `easyeda-fp-back-v5.yml` (huellas y hojas de LCSC) y `jlc-stock-back-v5.yml`.

**Por qué:** peticiones del usuario del 14/11, de 16:53 a 17:22.
**Validación:** CI de la PCB y del CAD. **Nada impreso ni fabricado.**

---

## 2026-11-14 — Espalda V5 CASCO: CAD REV A de la cápsula estanca y de la base del casco
**Autor:** Claude · Rama `feature/back-v5-casco`
**Qué cambia:**
- `hardware/back/V5_CASCO/CAD/avo_casco_v5.py` (CadQuery) y workflow **nuevo** `build-back-v5-cad.yml`, solo para esta rama.
- **Cápsula** de 56,4 × 56,4 × 24,1:
  - base y tapa de PETG y junta de TPU;
  - 4 × M2,5 a través de la PCB;
  - pogo de 5 contactos estimado e imanes de sujeción.
- **Base del casco:** anillo con alojamiento a 45°, imanes enfrentados, imán del Hall y cara inferior cóncava de R110.

**Por qué:** petición del usuario: «realizar primero los step de la base y la tapa para después ver dónde se colocan led, pogo, etc.».
**Validación:** CI con 1 sólido por pieza y 0 interferencias con la PCB, los componentes, la batería, la antena, el pogo y los imanes. **No impreso.**
**Pendiente:** STEP real del pogo de 5 contactos, batería real y posición del LED.

---

## 2026-11-14 — Espalda V5 CASCO: PCB REV A (un ESP32-S3), puerta de fabricación superada
**Autor:** Claude · Rama `feature/back-v5-casco`
**Qué cambia:**
- `hardware/back/V5_CASCO/PCB/`: cadena de la V4 adaptada (generador, colocación, Freerouting en el CI y reparación).
- Workflow **nuevo** `.github/workflows/build-back-v5-pcb.yml`: copia del de la V4 que solo se ejecuta en esta rama; no toca firmas ni TestFlight.
- **Placa:** 51 × 51, 4 capas, 1,6 mm.
  - Componentes en la cara F; B.Cu es la masa maciza de la antena GNSS.
  - ESP32-S3 + ZED-F9P soldado + antena activa por VCC_RF.
  - Pogo USB de 5 contactos, BQ24072, Hall y microSD.
- Correcciones de una revisión independiente del esquema:
  - ESD en la entrada de RF;
  - 22 Ω en 1206 en la alimentación de la antena (aguanta un corto del coaxial);
  - 0 Ω en RF_IN;
  - 1 µF en VCC del ZED;
  - nota de ILIM corregida.

**Por qué:** petición del usuario («Dale ya a la pcb con 51x51», «Sigue con un solo esp32»).
**Validación:**
- CI run 43597476741: DRC 0, 0 conexiones incompletas, paridad 0 y ERC 0/0. Puerta superada; ficheros en `out/FINAL/`.
- Ruteado: Freerouting 1.9.0 + 1 conexión de VSYS reparada con `repair.py`.
- **NO fabricada ni verificada en hardware.**

---

## 2026-11-14 — Espalda V5 CASCO: dos ESP32 (decisión del usuario)
**Autor:** Claude · Rama `feature/back-v5-casco`
**Qué cambia:** `ARQUITECTURA.md` pasa a dos chips (solo documentación):
- **ESP32-C6**: ESP-NOW con la cincha, el pecho y futuros equipos;
- **ESP32-S3**: ZED, microSD, NTRIP con el móvil y USB por el pogo.

**Enlace entre los dos:** UART COBS + CRC con RTS/CTS, PPS compartido, EN y BOOT del C6 controlados por el S3 (un solo USB para programar los dos) y línea de coordinación de radio.
**Consumo:** ≈ 300–320 mA (E). Con 2000 mAh, unas 6 h; para 8 h hacen falta unos 2700 mAh (+2,5 mm, +12 g).
**Por qué:** petición del usuario.
**Validación:** ninguna (estimaciones).

---

## 2026-11-14 — Espalda V5 CASCO: propuesta de arquitectura (sin PCB ni firmware)
**Autor:** Claude · Rama `feature/back-v5-casco` (desde `develop/avo-performance-horse`)
**Qué cambia:** solo documentación, en `hardware/back/V5_CASCO/DOCS/`:
- `ARQUITECTURA.md`;
- plano de concepto `AVO_BACK_V5_CASCO_concepto.png` y su fuente `concepto_plano.py`.

**Propuesta:**
- cápsula estanca de 55 × 55 × 22,6 mm (E), unos 105 g, y base magnética desprendible de unos 10 g;
- ZED-F9P y ESP32-S3 en una PCB de 51 × 51, con antena plana activa L1/L2 de 25 × 25 encima;
- batería de ≥ 2000 mAh;
- pogo de 5 contactos (VBUS, D−, D+, GND y uno libre) para cargar y para el USB con el PC;
- encendido por sensor Hall.

**Por qué:** petición del usuario: rediseñar la espalda para el casco del jockey (solo entrenamientos), lo más compacta y ligera posible sin perder prestaciones.
**Validación:** ninguna. Todo son estimaciones. No hay nada compilado ni verificado en hardware.

---

## 2026-11-15 — DOCK V1 (nuevo) — soporte de pared cargador: PCB REV A y caja
**Autor:** Claude · **Rama:** `claude/dock-cargador-v1` (sale de `develop/avo-performance-horse`) · **CI:** ver PR
**Qué cambia:** módulo nuevo `hardware/dock/V1`.
- **Para qué:** cargar 2 cascos (BACK V5, pogo de 5 contactos) y 2 cinchas (REV 5.9.1 / 5.10, pogo de 3 contactos).
- **Alimentación:** red de 230 V con un Mean Well IRM-20-5 en la PCB, en una zona aislada con foso de 6,5 mm, o USB-C de 5 V con prioridad a la red.
- **Pantalla** ST7789 de 2" con la batería de las 4 cápsulas.
- **ESP32-S3** con BLE y Wi-Fi, más un **hub USB2514B** y 2 TS3USB221 para dos modos:
  - **modo PC:** el PC ve los cascos y el soporte;
  - **modo autónomo:** el S3 hace de anfitrión, lee los cascos y sirve los entrenamientos por Wi-Fi.
- **Puertos:** 4 TPS2553 con límite de corriente y 4 INA180.
- **PCB:** generador derivado del de la BACK V5 (`PCB/fuente/avo_dock_v1_pcb.py`, `place_dock.py`, `build.py`). Placa de 130 × 76 mm, 4 capas.
- **Caja:** CadQuery (`CAD/avo_dock_v1.py`), 200 × 190 × 55, en 2 piezas de PETG.
- **Workflows nuevos** (no se ha modificado ninguno existente): `build-dock-v1-pcb.yml` y `build-dock-v1-cad.yml`. Solo se lanzan en esta rama o a mano.

**Por qué:** petición del usuario (15/11/2026). Decisiones tomadas: pogo de 3 de la REV 5.9.1, hub USB + ESP32-S3, módulo AC-DC certificado y rama desde develop.
**Archivos:** `hardware/dock/V1/**`, `.github/workflows/build-dock-v1-pcb.yml`, `.github/workflows/build-dock-v1-cad.yml`.
**No se ha tocado:** firmware, apps, contratos binarios, workflows existentes, firmas, `Info.plist`, número de build.
**Iteraciones del ruteado (16/11/2026):**
- se gira el hub 270° y se fijan el cristal y los desacoplos;
- 0,25 mm entre patios;
- In2 pasa a plano +3V3 con vía desde cada pad;
- F.Cu y B.Cu quedan como capas de señal;
- OCS_N del hub a +3V3 (sin R25);
- se unen los pads VBUS superpuestos del USB-C;
- se quita la zona +3V3 duplicada al importar la sesión;
- `jlc.py` ordena referencias como Q1B.

**Validación:**
- IMPLEMENTADO.
- **COMPILADO / CI:**
  - PCB: [43789462892](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/43789462892). DRC 0 errores, 0 conexiones incompletas, paridad 0, ERC 0/0, puerta superada. Ficheros en `out/FINAL/`. Ruteado de la ejecución 43788505774.
  - Caja: CI 43785237645. 1 sólido por pieza, 0 interferencias.
- **NO VERIFICADO** en hardware: nada fabricado.
**Pendiente:**
- códigos LCSC de 6 piezas;
- STEP real del pogo de 5 contactos;
- medidas de la pantalla;
- firmware DOCK 0.1.0 y el contrato `DockStatus v1` en todas las apps a la vez;
- % de batería por USB en la BACK 5.x;
- protocolo por MTCK y divisor de batería en la GIRTH.
## 2026-11-17 — Repositorio — Integración de pendientes, archivo en `main`, limpieza y escaneo de secretos
**Autor:** Claude · Rama `claude/integracion-17-11` · Petición del usuario: «Realiza todo tú».
**Qué se ha hecho:**
- **PR #62 fusionado en `main`** (archivo completo con `archivo/binarios/`). Único conflicto: `README.md` de `main`; se
  conserva el que el usuario editó en `main` (17/11 12:38, «AVO Performance —Horse Edition—»).
- **PR #60 fusionado** (cincha BETA, cápsula REV 6.4 con cierre de balancín). **PR #45 fusionado** (DOCK BETA V1) y
  **PR #64 fusionado** (casco BETA BACK V5, 229 commits por detrás): ambos puestos al día con `develop` por *merge
  commit*; único conflicto, el registro (se conservan ambas entradas). Sus workflows nuevos (`build-dock-v1-*`,
  `build-back-v5-*`, `easyeda-fp-back-v5`, `jlc-stock-back-v5`) solo se disparan en su rama o a mano: no corren en
  `develop`.
- **REV 5.11 no se integra:** el cierre magnético se hizo por error sobre la REV 5 (PR #46 cerrado); el vigente es la
  REV 6.4. La rama queda archivada en su etiqueta.
- **PR #3 cerrado** (signer antiguo contra `main`; AVO Signer ya está en `develop`, PR #5).
- Descargas: CAD del casco V5 y del DOCK V1 salen ya de `develop`.
- **No se pudo (lo bloquea la política de la sesión en la nube):** cambiar la rama por defecto a `develop`, proteger
  `develop`, borrar ramas y crear etiquetas. Para borrar las 99 ramas respaldadas: `docs/borrar_ramas_2026-11-17.sh`
  (comprueba que cada etiqueta apunta al mismo commit antes de borrar). Se conservan `develop`, `main`, `ci/*`,
  `archivo/todo-2026-11-17` y 4 ramas recién fusionadas sin etiqueta (`cad/cincha-rev6-3-balancin-magnetico`,
  `claude/dock-cargador-v1`, `claude/nombres-prototipo-beta`, `feature/back-v5-casco`).
- **Escaneo de secretos** (gitleaks 8.21.2, historial completo de `develop`, 1191 commits): 2919 avisos, de ellos 2913
  en JSON de existencias de JLCPCB/EasyEDA (identificadores de producto, falsos positivos). Los 6 restantes no son
  secretos: plantilla `BEGIN PRIVATE KEY` en `build-avo-ipad.yml` e `ipad/README.md` (instrucciones, sin clave),
  contraseñas de prueba en tests del iPad, vector de prueba `vectors_auth.txt` y la clave web de Firebase
  (`FirebaseConfig.kt`; es pública por diseño, la protección son las reglas). **Sin claves reales.** No se escanearon
  los binarios de `main`/`archivo` ni las ramas `ci/*`.
**Validación:** fusiones con CI de `develop` · nada nuevo verificado en hardware.

## 2026-11-17 — Cincha CAD REV 7.0 — arquitectura de 3 IMU en el CAD completo
**Autor:** Claude · **Rama:** `cad/cincha-rev7-0-tres-imu` (sobre el PR #72)
**Qué cambia (decisiones del usuario):** un solo pogo magnético de 6 pines; PCB de sensores SOP REV A encapsulada en
un alojamiento del soporte; 2 satélites IMU (±355 mm) en la funda con cable fijo de 6 hilos; electrodos ECG+/ECG−
bajo los satélites y REF bajo el soporte; funda 860 mm; portaimanes del balancín (sustituye a las tapas de los imanes,
`mag_c` 3,4); lengüetas de la tapa en media caña sobre el pasador. Medidas de pogo y PCB PROVISIONALES. Archivos
`R6_10` → `R7_0`; renders 20–22.
**Validación:** IMPLEMENTADO · `verificar_step.py` 27/27 · vóxeles: 0 mm³ cápsula/soporte, portaimanes sin
interferencias; cierre 4° / ~10° · **NO VERIFICADO** (nada impreso; PCB sin diseñar).
**Pendiente:** elegir el pogo de 6 pines real y diseñar las PCB (SOP REV A, satélite, cápsula REV E); contrato de
datos de 3 IMU (firmware + apps a la vez); prueba en PROTOTIPO.

---

## 2026-11-17 — Cincha CAD REV 6.10 — sin cordón de seguridad
**Autor:** Claude · **Rama:** `cad/cincha-rev6-10-sin-cordon` (sobre el PR #71)
**Qué cambia (decisión del usuario):** fuera la oreja de la tapa, su agujero, el anclaje del ala del soporte y el
cordón Dyneema; la tapa queda rectangular. La retención depende solo de los balancines y el cerco. Archivos `R6_9` →
`R6_10`. También se guarda en el proyecto la propuesta de arquitectura con 3 IMU y PCB de sensores en el soporte
(`AVO_CINCHA_BETA_3IMU_ARQUITECTURA_PROPUESTA_2026-11-17.md`).
**Validación:** IMPLEMENTADO · `verificar_step.py` 26/26 · vóxeles: cierre y portaimanes sin cambios ·
**NO VERIFICADO** (nada impreso). **Pendiente:** ensayo de tirón y caída (§8.4) sin cordón.

---

## 2026-11-17 — Cincha CAD REV 6.9 — soporte continuo (cuerpo a ras y cerco sin corte)
**Autor:** Claude · **Rama:** `cad/cincha-rev6-9-soporte-continuo` (sobre el PR #70)
**Qué cambia (captura del usuario):** cuerpo del soporte a ras del cerco; el cerco no se corta en ±X (rebaje interior
con piel de 1,15 mm para el balancín); `pock_out` 1,95; canto exterior del cerco R0,5. Archivos `R6_8` → `R6_9`.
**Validación:** IMPLEMENTADO · `verificar_step.py` 26/26 · vóxeles: 0 mm³ cápsula/soporte; suelta a 4°, tope contra
el soporte a ~10° · **NO VERIFICADO** (nada impreso).

---

## 2026-11-17 — Cincha CAD REV 6.8 — cápsula rectangular con aristas redondeadas (acabado comercial)
**Autor:** Claude · **Rama:** `cad/cincha-rev6-8-acabado-comercial` (sobre el PR #69)
**Qué cambia (petición del usuario):** cápsula rectangular (parte baja 69,0 × 60,2 R8 con las columnas de los
tornillos dentro; parte alta y cerco 75,5 × 66,7 R11,25, a ras); redondeos: tapa R1,5, arista del escalón R1,0,
canto del cerco R1,0 (dentro, fuera y paso del balancín), balancines a juego. Archivos `R6_7` → `R6_8`.
**Validación:** IMPLEMENTADO · `verificar_step.py` 26/26 · vóxeles: 0 mm³ cápsula/soporte, cierre 4° / 12°,
portaimanes sin cambios · **NO VERIFICADO** (nada impreso).
**Pendiente:** decidir la oreja del cordón (única pieza que sobresale).

---

## 2026-11-17 — Cincha CAD REV 6.7 — extremos a ras del soporte y tapa redondeada
**Autor:** Claude · **Rama:** `cad/cincha-rev6-7-extremos-redondeo` (sobre el PR #68)
**Qué cambia (capturas del usuario):** los extremos ±X también quedan a ras del cerco (parte alta 75,5 × 66,6 mm,
esquinas iguales a las del cerco); el balancín engorda 3,25 mm por encima del escalón para seguir a ras; borde
superior de la tapa y del balancín redondeado R1,5; oreja del cordón +1 mm. Propuesta documentada: base en una pieza
con franja translúcida (z 8,0–12,0) por cambio de filamento. Archivos `R6_6` → `R6_7`.
**Validación:** IMPLEMENTADO · `verificar_step.py` 26/26 OK · vóxeles: 0 mm³ cápsula/soporte, suelta a 4°, tope a 12°
(+X) / 13° (−X), portaimanes sin cambios · **NO VERIFICADO** (nada impreso).

---

## 2026-11-17 — Cincha CAD REV 6.6 — pared de la cápsula a ras del soporte
**Autor:** Claude · **Rama:** `cad/cincha-rev6-6-pared-a-ras` (sobre el PR #67)
**Qué cambia (capturas del usuario):** por encima del cerco la base engorda hasta la cara exterior del cerco, que pasa
a ser una envolvente convexa común (sin entrantes entre columnas); cápsula y soporte quedan a ras. Parte alta 69,0 ×
66,6 mm; la parte que entra en el cerco no cambia. Escalón a z = 4,25 con rendija de 0,45 mm. Tapa con la misma
envolvente. Extremos ±X sin cambios. Archivos `R6_5` → `R6_6`.
**Archivos:** `hardware/girth/CINCHA_MONTAJE/` (fuente, out, renders 16 y 16b, DOCS).
**Validación:** IMPLEMENTADO · `verificar_step.py` 26/26 OK · vóxeles: 0 mm³ cápsula/soporte (cerrada y empujada
0,25), cierre (4° / 12°) y portaimanes sin cambios · **NO VERIFICADO** (nada impreso).
**Pendiente:** luz del aro a través de ≈ 10 mm de PETG; soportes bajo el escalón al imprimir la base.

---

## 2026-11-17 — Cincha CAD REV 6.5 — portaimanes para los imanes de la pared
**Autor:** Claude · **Rama:** `cad/cincha-rev6-5-portaimanes` (sobre el PR #60)
**Qué cambia (captura del usuario):**
- el pozo justo de los 2 imanes Ø5 × 1 de la pared (con tapón) pasa a ser una abertura de 2,8 × 6,6 × 7,0 mm en la
  cara inferior; dentro entra un **portaimanes** PETG de 2,6 × 6,4 × 6,9 mm con los imanes en su cuna, a ras del fondo
  y con los imanes ocultos;
- cuna abierta solo hacia el balancín: misma piel de 0,65 mm y misma distancia entre imanes que en la REV 6.4;
- planta trapezoidal (chaflanes de 1 mm): una sola posición de montaje; los de +X y −X son la misma pieza;
- fuera los 2 tapones de `tapas_imanes`; nueva pieza `AVO_CINCHA_R6_5_portaimanes_PETG_x2`; todos los archivos pasan
  de `R6_4` a `R6_5`.
**Archivos:** `hardware/girth/CINCHA_MONTAJE/fuente/{avo_cincha_montaje.py, render.py, verificar_cierre.py,
verificar_portaimanes.py}`, `out/STEP`, `out/STL`, `out/informe.json`, `out/verificacion_*.json`, `renders/` (15 y
15b nuevos), `DOCS/MONTAJE_CINCHA.md`.
**Validación:** IMPLEMENTADO · `verificar_step.py` OK (0 aristas mal cosidas) · `verificar_portaimanes.py`: 0 mm³
portaimanes/base e imanes/base/portaimanes · `verificar_cierre.py`: sin cambios (suelta a 4°, tope a 12°) ·
**NO VERIFICADO** (nada impreso).
**Pendiente:** probeta del ajuste (0,1 mm por lado) y de la pared de 0,95 mm; la fila de la tabla «Vigente» se
actualiza a REV 6.5 al integrar el PR #60 en `develop`.

---

## 2026-11-17 — Cincha CAD REV 6.4 — balancín magnético empotrado a ras en la pared
**Autor:** Claude · **Rama:** `cad/cincha-rev6-3-balancin-magnetico` (PR #60)
**Qué cambia (captura del usuario):**
- extremos de la cápsula +5 mm (69,0 mm) con el balancín empotrado a ras en un hueco de la pared, fuera de la línea de la junta;
- eje: pasador de acero Ø2 × 20 / Ø2 × 18 a presión en el balancín, que gira en cojinetes impresos con la base; lo cierran lengüetas de la tapa;
- imanes 2 + 2 Ø5 × 1 entre el balancín y la pared (pozo desde abajo con tapón);
- diente recto en la cama del soporte;
- se quitan las aletas, la barra y el labio de la 6.3.1;
- soporte de 94,5 × 84,6; patrón de la funda regenerado.
**Comprobado (script local):**
- piezas cerradas; conjuntos de 96 sólidos con 0 aristas abiertas; `verificar_step.py` 25/25 OK;
- `verificar_cierre.py`: 0 mm³ cerrado; diente libre a unos 4° (0,5 mm de pulsador); tope a unos 12°; sin choques con el soporte antes del tope.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.
**Pendiente:** rozamiento real (μ ≥ 0,17–0,24 con diente recto), fuerza de los imanes y probeta del extremo.

## 2026-11-17 — Cincha CAD REV 6.3.1 — eje en las columnas y labio sobre la tapa
**Autor:** Claude · **Rama:** `cad/cincha-rev6-3-balancin-magnetico` (PR #60)
**Qué cambia (marcado del usuario, «integrado»):**
- las aletas del eje pasan junto a las columnas de las esquinas (±20,5 en +X, ±19,5 en −X: llave de posición);
- el balancín (14 / 12 mm) lleva una barra de columna a columna con los pasadores Ø2 × 6 en sus extremos;
- labio superior que tapa el hueco y entra en un rebaje del borde de la tapa (fondo a 0,5 mm del interior).
**Comprobado (script local):**
- piezas cerradas; conjuntos de 96 sólidos con 0 aristas abiertas; `verificar_step.py` 25/25 OK;
- `verificar_cierre.py`: 0 mm³ de interferencia cerrado y sin choques con el soporte al abrir;
- diente libre a unos 9,5° (1,4 mm de pulsador); tope del labio a unos 14,5°.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.

## 2026-11-17 — Cincha CAD REV 6.3 (con funda) — cierre magnético de balancín
**Autor:** Claude · **Rama:** `cad/cincha-rev6-3-balancin-magnetico`
**Qué cambia:** en `hardware/girth/CINCHA_MONTAJE` los pestillos elásticos y los seguros TPU de la REV 6.2 se sustituyen por un **balancín magnético en cada lado corto**:
- balancín a ras de la tapa, con 2 pasadores de acero Ø2 × 6 en aletas de la base;
- dientes rectos en ventanas del cerco;
- 2 + 2 imanes Ø5 × 1 en atracción (balancín ↔ cerco), con orificio y tapón;
- cerco de 3,0;
- soporte de 99,6 × 84,6;
- piezas renombradas a `R6_3`;
- `fuente/verificar_cierre.py` nuevo (comprobación por vóxeles);
- renders 13, 13b y 14 nuevos;
- patrón de la funda regenerado (los tornillos de Chicago cambian de sitio).
**Por qué:** decisión del usuario, que aplica a la cincha vigente (con funda) el diseño que se había acordado sobre la REV5 (PR #46, que se cierra sin fusionar). Sin imanes de repulsión arriba: no caben por la ranura de la junta y la tapa de 2,5 mm.
**Comprobado (script local, no hay workflow para esta carpeta):**
- `avo_cincha_montaje.py`: todas las piezas cerradas; conjuntos de 96 sólidos con 0 aristas abiertas;
- `verificar_step.py`: 25/25 OK;
- `verificar_cierre.py`: 0 mm³ de interferencia cerrado, sin choques al abrir, dientes libres a unos 10° (1,5 mm de pulsador), tope a unos 26°.
**Validación:** IMPLEMENTADO · **NO VERIFICADO** (ni impreso ni probado).
**Pendiente:** fuerza real de los imanes apilados y del rozamiento, probeta del cierre, ensayo de tirón (§8.4).








## 2026-11-17 — Docs/CI — Nombres PROTOTIPO / BETA y estado vigente único
**Autor:** Claude · Rama `claude/nombres-prototipo-beta`
**Qué cambia:** regla del usuario: sin PCB propia = **PROTOTIPO** (Waveshare, Heltec, XIAO); con PCB propia = **BETA**
(cincha PCB REV D, casco V5, DOCK V1, espalda V4). Descargas renombradas (`AVO_PECHO_PROTOTIPO_FW.zip`,
`CAD_CINCHA_BETA_REV6_MONTAJE.zip`…), nueva `AVO_CINCHA_BETA_FW.zip` (0.6.x) y entrada para la espalda BETA V4; los
nombres antiguos se retiran de la release. `AGENTS.md`: bloque «Empieza aquí», regla de nombres, hardware por líneas,
etiquetas de respaldo ya creadas, descargas y **plan de pruebas**: campo solo con PROTOTIPOS hasta tener todas las PCB
construidas; después se porta a las BETA y se prueban. `ESTADO_DESARROLLO_Y_VERSIONES.md`: tabla única vigente arriba; lo del
22/10 queda como histórico.
**No se ha tocado:** carpetas, workflows de compilación ni nombres de artefactos existentes (renombrarlos rompería CI e
historial; la etiqueta se aplica en docs, descargas y carpetas nuevas).
**Validación:** publicación simulada en local con los artefactos reales · se publica al fusionar.

## 2026-11-17 — CI — Descargas directas (release fija `descargas`)
**Autor:** Claude · Rama `claude/descargas-directas` · **CI:** se ejecuta por primera vez al integrar en `develop`
**Qué cambia:** workflow nuevo `publicar-descargas.yml` + `scripts/descargas/publicar.py` + `descargas.json`. Publica en
la release `descargas`, con nombres fijos, la última versión de firmware (pecho, espalda, cincha, cincha ECG), apps
(Android, Tarjetas, AVO Update, Windows) y ZIP de CAD (cincha REV5, montaje, casco V5, DOCK V1, espalda V4), más
`VERSIONES.txt` y `manifiesto.json`. Espera a que terminen las compilaciones del commit y solo sube lo que cambia.
**Por qué:** el usuario pide descarga directa de lo último de todo; los artefactos caducan y piden iniciar sesión.
**No se ha tocado:** ningún workflow de compilación, firmas, `Info.plist` ni TestFlight. iOS sigue solo por TestFlight.
**Validación:** IMPLEMENTADO · simulado en local con `gh` falso y los 988 artefactos reales de la API (17 entradas:
12 publicables, 5 pendientes) · **sin ejecutar aún en Actions**. Detalle: `docs/DESCARGAS_DIRECTAS.md`.

## 2026-11-16 — Diseño AVO-LOCK-1 — licencias por QR en la base de carga
**Autor:** Claude · **Commits:** este PR · **CI:** no aplica (solo documentación)
**Qué cambia:** §16 en `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`: la app muestra un QR con la licencia de cuadra (una firma
para todos los cascos) y la elección de caballos; la base de carga lo lee con un lector UART y lo instala en todos los
cascos que cargan.
**Por qué:** idea del usuario (16/11/2026 21:56).
**Archivos:** `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** código, firmware, PCB del DOCK, workflows, firmas, `Info.plist`. Estado: solo diseño, **NO VERIFICADO**.

## 2026-11-16 — Diseño AVO-LOCK-1 — plazas de caballo compartidas por todos los cascos de la cuadra
**Autor:** Claude · **Commits:** este PR · **CI:** no aplica (solo documentación)
**Qué cambia:** §15 de `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`: las plazas son de la cuadra; cualquier casco alquilado por la
cuadra graba con cualquiera de sus caballos activados; el comprobante de activación se reparte entre cascos y, si hay dos,
gana el más antiguo.
**Por qué:** indicación del usuario (16/11/2026 21:52).
**Archivos:** `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** código, firmware, workflows, firmas, `Info.plist`. Estado: solo diseño, **NO VERIFICADO**.

## 2026-11-16 — Diseño AVO-LOCK-1 — renovación con los caballos anteriores marcados
**Autor:** Claude · **Commits:** este PR · **CI:** no aplica (solo documentación)
**Qué cambia:** §15 de `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`: al renovar, la selección aparece con los caballos que ya
tenían plaza marcados; el cliente confirma o cambia.
**Por qué:** indicación del usuario (16/11/2026 21:49).
**Archivos:** `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** código, firmware, workflows, firmas, `Info.plist`. Estado: solo diseño, **NO VERIFICADO**.

## 2026-11-16 — Diseño AVO-LOCK-1 — activación de caballos al recibir la licencia
**Autor:** Claude · **Commits:** este PR · **CI:** no aplica (solo documentación)
**Qué cambia:** §15 de `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`: caballos ilimitados en la app; al recibir la licencia se
eligen los de las plazas contratadas y quedan bloqueados (nombre e id); el casco ata la elección por nº de licencia y emite un
comprobante firmado por su ATECC608B. Resuelta la decisión pendiente de §11.
**Por qué:** flujo definido por el usuario (16/11/2026 21:48).
**Archivos:** `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** código, firmware, workflows, firmas, `Info.plist`. Estado: solo diseño, **NO VERIFICADO**.

## 2026-11-16 — Diseño AVO-LOCK-1 — cupo de caballos por licencia de cuadra
**Autor:** Claude · **Commits:** este PR · **CI:** no aplica (solo documentación)
**Qué cambia:** §15 en `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`: la licencia de cuadra lleva plazas de caballo firmadas; no se
cambia de caballo hasta renovar o contratar otra plaza; el caballo sustituido queda bloqueado para el casco (sus datos se
siguen viendo). Nueva decisión pendiente sobre quién rellena una plaza vacía.
**Por qué:** regla del usuario (16/11/2026 21:43).
**Archivos:** `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** código, firmware, workflows, firmas, `Info.plist`. Estado: solo diseño, **NO VERIFICADO**.

## 2026-11-16 — Diseño AVO-LOCK-1 — licencias hijas sin caducidad propia
**Autor:** Claude · **Commits:** este PR · **CI:** no aplica (solo documentación)
**Qué cambia:** §14 de `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`: las licencias de entrenador, jockeys y caballos no tienen
fecha de fin; dependen solo de la de la cuadra. Con la cuadra caducada las apps permiten ver en solo lectura todo lo
generado durante la licencia activa; nada nuevo. Resuelta la decisión pendiente de §11.
**Por qué:** aclaración del usuario (16/11/2026 21:39).
**Archivos:** `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** código, firmware, workflows, firmas, `Info.plist`. Estado: solo diseño, **NO VERIFICADO**.

## 2026-11-16 — Diseño AVO-LOCK-1 — jerarquía de licencias (la cuadra manda)
**Autor:** Claude · **Commits:** este PR · **CI:** no aplica (solo documentación)
**Qué cambia:** §14 en `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`: con la licencia de cuadra caducada no funcionan las licencias
de entrenador, jockeys, caballos ni cascos de esa cuadra; las licencias hijas nunca duran más que la cuadra; personas con
varias cuadras solo pierden la caducada; se mantiene la descarga de lo grabado (§12). Nueva decisión pendiente: consulta en
solo lectura con la cuadra caducada.
**Por qué:** regla del usuario (16/11/2026 21:35).
**Archivos:** `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** código, firmware, workflows, firmas, `Info.plist`. Estado: solo diseño, **NO VERIFICADO**.

## 2026-11-16 — AVO-LOCK-1: alquiler mensual y cambio de cuadra del casco
**Autor:** Claude · **Rama:** `docs/avo-lock-1-alquiler` · solo documento.
**Qué cambia:** nueva §13 de `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`:
- licencia mensual del casco;
- en la devolución, la app comprueba que todo esté descargado;
- solo AVO lo pasa a otra cuadra, con una licencia y una llave pública nuevas firmadas;
- el casco borra la SD y la configuración, y rechaza el cambio si hay sesiones sin descargar, salvo con la marca `BORRAR_PENDIENTES`;
- el casco y AVO Tarjetas guardan el historial del casco.

**Estado:** DISEÑO.

## 2026-11-16 — AVO-LOCK-1: decisiones confirmadas
**Autor:** Claude · **Rama:** `docs/avo-lock-1-decisiones` · solo documento.
**Qué cambia:** en la §12 de `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md` el usuario confirma:
- aviso desde 7 días antes y bloqueo de la grabación el día de fin;
- con la licencia caducada se pueden descargar los datos ya grabados;
- hacen falta dos licencias, la del casco (cuadra) y la de la persona.

**Estado:** DISEÑO.

## 2026-11-16 — Diseño AVO-LOCK-1: el casco solo funciona dentro del sistema y de su licencia
**Autor:** Claude · **Rama:** `docs/avo-lock-1` · solo documento.
**Qué cambia:** nueva §12 de `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`:
- **Identidad:** ATECC608B con certificado de casco firmado por AVO Tarjetas.
- **Licencia:** licencia propia del casco, comprobada con la hora GNSS.
- **Conexión:** reto y respuesta mutuos entre la app (llave de cuadra) y el casco, con el canal cifrado.
- **Firmware:** arranque seguro y cifrado de flash en serie.
- **Estados:** licencia válida, aviso, caducada (sin grabar, pero se puede descargar) y sin licencia.

**Estado:** DISEÑO · decisiones pendientes en §12.

## 2026-11-16 — AVO-ENC-1: solo el casco cifra; pecho y espalda siguen como banco de pruebas
**Autor:** Claude · **Rama:** `docs/avo-enc-1-casco` · solo documento.
**Qué cambia:** decisión del usuario en `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`:
- el cifrado es solo para el casco (PCB propia);
- el pecho y la espalda actuales son el banco de pruebas y siguen grabando `.avr` sin cifrar;
- en la placa de serie del casco se recomienda arranque seguro y cifrado de flash, y el elemento seguro opcional queda como decisión pendiente.

**Estado:** DISEÑO.

## 2026-11-16 — Diseño AVO-ENC-1: RAW comprimido y cifrado en el casco + llavero de cuadras
**Autor:** Claude · **Rama:** `docs/avo-enc-1` · solo documento.
**Qué cambia:** nuevo `docs/AVO_ENC_1_CIFRADO_Y_LLAVERO.md`, con el diseño aprobado por el usuario:
- **Formato en la SD:** el casco escribe `.avoe` por bloques (deflate + AES-256-GCM, ECDH P-256 para envolver la llave de sesión).
- **Llaves:** una llave por cuadra y una llave personal por persona.
- **Llavero `.avokeys`:** cifrado con la clave secreta de la tarjeta NFC; un propietario o veterinario con varias cuadras usa una sola tarjeta.
- **Copias por destinatario:** al asignar el caballo se añade una para su propietario.
- **Casco:** solo acepta llaves públicas de cuadra firmadas por AVO Tarjetas.

**No se ha tocado:** firmware, apps, workflows ni firmas.
**Estado:** DISEÑO · sin implementar.

## 2026-11-16 — iPad — «Análisis visual» de la carrera a pantalla completa
**Autor:** Claude · **Rama:** `feature/ipad-carrera-analisis-profundo`
**Qué cambia:** en la ficha de la carrera hay un botón nuevo, **«Análisis visual»** (icono de gráficas, a la izquierda de «Informe PDF»). Abre una ventana a pantalla completa.
- **Panel izquierdo:** se elige qué se muestra:
  - cualquier caballo de la carrera, con atajos «Mío + ganador», «Top 3», «Todos» y «Ninguno»;
  - los entrenamientos con parciales de los 60 días anteriores, en línea discontinua y alineados desde la meta;
  - las otras carreras del mismo caballo, en línea punteada y alineadas por la distancia a la meta.
- **8 medidas:** velocidad, % de su mejor tramo, tiempo del tramo, posición, distancia al primero, diferencia con mi caballo, zancada y foulées.
- **Gráfica grande:** al tocar o arrastrar se elige un tramo y aparece un ranking de ese tramo de mejor a peor. Debajo, una tabla con todos los tramos en la que el mejor de cada tramo sale en verde y el peor en rojo.
- **Por defecto** se muestran mi caballo, el ganador y el entrenamiento elegido en la ficha.

**Por qué:** boceto del entrenador sobre la build 165 (16/11/2026 11:25): «ventana a pantalla completa donde hacer un análisis visual profundo de la carrera, poder seleccionar qué caballos mostrar, comparar con mi carrera y mis entrenos».
**Archivos:** `Views/RaceDeepAnalysisView.swift` (nuevo), `Views/RaceDetailView.swift`.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-16 — Logotipo de los informes: «PERFORMANCE» un poco más abajo y sin el trazo rojo bajo «PE»
**Autor:** Claude · **Rama:** `feature/logo-ajuste`
**Qué cambia:** en `report_text.jpg` (iPad y Windows):
- «PERFORMANCE» baja 7 px respecto a la línea roja de «AVO»;
- se borra la cola roja que quedaba bajo «PE», un resto de la línea roja de «AVO» que se había movido con la banda de «HORSE EDITION»;
- se añade un margen inferior a «HORSE EDITION».

El tamaño queda en 670 × 293 px.
**Por qué:** boceto del entrenador sobre un PDF de tramo (16/11/2026 01:05): «un pelín más bajo».
**Estado:** imagen cambiada · NO VERIFICADO en los PDF generados.

## 2026-11-16 — iPad — Flechas de «% carrera» vistas desde la carrera
**Autor:** Claude · **Rama:** `feature/ipad-flechas-carrera`
**Qué cambia:** las flechas de «Entrenamiento vs carrera» (app y PDF) se leen ahora desde la carrera:
- ▲ verde si en ese tramo la carrera fue **más rápida** que el entrenamiento (% carrera < 100 %);
- ▼ roja si la carrera fue igual o más lenta.

Antes era al revés.
**Por qué:** boceto del entrenador sobre la build 159 (16/11/2026 00:47): «está al revés».
**Archivos:** `Views/RaceTrainingSplitsView.swift`, `Core/RaceComparisonPdf.swift`.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-16 — Imagen de marca (`avo_brand_hero`): «PERFORMANCE» arriba y «HORSE EDITION» debajo
**Autor:** Claude · **Rama:** `feature/hero-performance-arriba`
**Qué cambia:** igual que en el logotipo de los informes, en la imagen grande de marca se intercambian las bandas «HORSE EDITION» y «PERFORMANCE». Se hace solo en la zona del texto y con los bordes fundidos, para no cortar las rayas rojas del fondo. Misma resolución (941 × 869). Cambia en todas las apps que usan la imagen:
- iPad: Dashboard e Inicio;
- Windows: `Assets/avo_brand_hero.jpg`;
- Android: `app`, `cards` y `usb-updater` (`drawable-nodpi/avo_brand_hero.webp`).

**Por qué:** boceto del entrenador sobre el Dashboard del iPad (16/11/2026 01:02).
**Estado:** imagen cambiada · NO VERIFICADO en los dispositivos.

## 2026-11-16 — Logotipo de los informes: «PERFORMANCE» arriba y «HORSE EDITION» debajo
**Autor:** Claude · **Rama:** `feature/logo-performance-arriba`
**Qué cambia:** en el logotipo de la cabecera de los informes (`report_text.jpg`) se intercambian las dos bandas: «PERFORMANCE» pasa justo bajo «AVO» y «HORSE EDITION» va debajo. Mismo tamaño (670 × 282 px). Se cambia en el iPad (`Assets.xcassets/report_text.imageset`) y en Windows (`AVO.Windows.Core/Reports`), que comparten el mismo archivo.
**Por qué:** petición del entrenador (16/11/2026).
**Estado:** imagen cambiada · NO VERIFICADO en los PDF generados en el iPad.

## 2026-11-16 — iPad — Cuadra: número de carreras de cada caballo
**Autor:** Claude · **Rama:** `feature/ipad-cuadra-carreras`
**Qué cambia:** en la lista de la Cuadra cada caballo muestra su número de carreras importadas («1 carrera», «0 carreras»), antes del número de entrenamientos.
**Por qué:** boceto del entrenador sobre la build 155 (16/11/2026 00:17).
**Archivos:** `Views/StableView.swift`.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-16 — iPad — Carreras: «mediana del campo» pasa a llamarse «caballo medio»
**Autor:** Claude · **Rama:** `feature/ipad-pdf-carrera-saltos`
**Qué cambia:** en todo lo que tiene que ver con carreras, «mediana del campo» pasa a ser **«caballo medio»** y «mediana de sus trabajos» pasa a ser «valor medio». Afecta a la ficha de la carrera, las gráficas, el análisis, las observaciones, el método y el Informe PDF. El cálculo no cambia: sigue siendo la mediana de los demás participantes, sin contar el nuestro, y la explicación lo dice con palabras sencillas.
**Por qué:** petición del entrenador (16/11/2026): «algo que sea entendible por cualquiera», «en todas partes».
**Archivos:** `Views/RaceDetailView.swift`, `Core/RaceAnalysis.swift`, `Core/RaceComparisonPdf.swift`.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-16 — iPad — Informe PDF de la carrera: ningún título queda solo al final de una página
**Autor:** Claude · **Rama:** `feature/ipad-pdf-carrera-saltos`
**Qué cambia:** cada título y subtítulo del PDF se mantiene en la misma página que su primer bloque. Si no caben juntos, el título pasa a la página siguiente. Antes quedaban sueltos al pie de la página 1 y 2:
- «Entrenamiento vs carrera»: el título va con sus datos, las cifras y la primera gráfica;
- «Análisis según los entrenamientos»: el título va con el primer bloque, y «Lo que dice la carrera» con sus 6 filas;
- lo mismo para entrenamientos, forma, estimación y observaciones.

**Por qué:** bocetos del entrenador sobre la build de TestFlight (15/11/2026 23:58, «siguiente página»).
**Archivos:** `Core/RaceComparisonPdf.swift`.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-15 — iPad — Flechas en «% carrera», «mediana del campo» explicada, visor PDF a pantalla completa y símbolos del PDF
**Autor:** Claude · **Rama:** `feature/ipad-pdf-carrera-fila`
**Qué cambia (bocetos del entrenador 15/11/2026, build 151):**
- **Flechas en «% carrera»** (app y PDF) de «Entrenamiento vs carrera»: ▲ verde si en ese tramo el entrenamiento fue igual o más rápido que la carrera (≥ 100 %) y ▼ roja si fue más lento.
- **«Mediana del campo» explicada** (app y PDF), bajo «Lo que dice la carrera»: es el «caballo típico» de la carrera, es decir, el valor del caballo que queda en medio de los demás participantes, sin el nuestro.
- **Visor de PDF a pantalla completa** (antes era una hoja pequeña centrada).
- **Símbolos del PDF:** ≈, ≥, ≤ y → salían como «?» porque las fuentes estándar del PDF no los tienen. Ahora se escriben ~, >=, <= y ->.

**Archivos:** `Core/PdfDocument.swift` (`safe`, `fillPolygon`, `arrow`), `Core/RaceComparisonPdf.swift`, `Views/RaceTrainingSplitsView.swift`, `Views/RaceDetailView.swift`, `App/RootView.swift`.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-15 — iPad — Informe PDF de la carrera: las 8 cifras del resultado en una sola línea
**Autor:** Claude · **Rama:** `feature/ipad-pdf-carrera-fila`
**Qué cambia:** las 8 cifras del resultado van ahora en una sola línea:
- puesto, tiempo oficial y distancia al ganador;
- velocidad máxima y velocidad media;
- mejor 200 m, últimos 600 m y recorrido vs 1.º.

Todas las cifras de una línea comparten tamaño, que se reduce para que quepa la más ancha, y los nombres y textos pequeños se ajustan al recuadro.
**Por qué:** boceto del entrenador sobre el PDF (15/11/2026, build 151): «Todos en misma línea».
**Archivos:** `Core/RaceComparisonPdf.swift`.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-15 — iPad — Casilla «PDF» en cada grupo de datos de la carrera
**Autor:** Claude · **Rama:** `feature/ipad-pdf-carrera-checks` · **CI:** ver PR
**Qué cambia:** cada recuadro de la ficha de la carrera tiene arriba a la derecha una casilla **«PDF»** que decide si sale en el «Informe PDF». Son 17 grupos:
- datos de la carrera y resultado;
- clasificación y tramos;
- las 4 gráficas por tramo: velocidad, posición, foulées/zancada y distancia al primero;
- entrenamiento vs carrera;
- conclusión, lo que dice la carrera, lo que dicen sus entrenamientos, forma, estimación, observaciones y método;
- notas.

La elección se guarda y se aplica a todas las carreras. El PDF incluye ahora también las 4 gráficas de la carrera. Si no hay nada marcado, avisa y no genera el PDF.
**Por qué:** petición del entrenador (15/11/2026): elegir qué incluir y qué no en el informe.
**Archivos:** `Core/RaceComparisonPdf.swift` (`RacePdfSection`, gráficas), `Views/RacePdfCheck.swift` (nuevo), `App/RacesModel.swift` (`pdfSections`), `Views/RaceDetailView.swift`.
**No se ha tocado:** workflows, firmas, `Info.plist`, número de build.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-15 — iPad — «Informe PDF» de la carrera frente al entrenamiento
**Autor:** Claude · **Rama:** `feature/ipad-pdf-carrera-entreno` · **CI:** ver PR
**Qué cambia:** en la ficha de la carrera aparece el botón **«Informe PDF»**. Genera un PDF para enviar, con el estilo de los informes de entrenamiento, y lo abre en el visor con «Compartir». El PDF incluye:
- la carrera y el resultado;
- los tramos de nuestro caballo;
- la clasificación con nuestro caballo resaltado;
- «Entrenamiento vs carrera, tramo a tramo» con el trabajo elegido en la ficha: cifras, gráfica de velocidad por tramo, perfil de caída y tabla;
- el «Análisis según los entrenamientos» completo: conclusión, carrera, entrenamientos, forma, estimación, observaciones y método;
- las notas.

El botón del PDF del tracker pasa a llamarse «PDF original».
**Por qué:** petición del entrenador (15/11/2026): la comparación solo se veía en la app.
**Archivos:** `Core/RaceComparisonPdf.swift` (nuevo), `App/RacesModel.swift` (`exportComparisonPdf`, `splitChoice`), `Views/RaceDetailView.swift`, `Views/RaceTrainingSplitsView.swift`.
**No se ha tocado:** workflows, firmas, `Info.plist`, número de build.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.

## 2026-11-15 — Cincha REV D: CPL corregido para las huellas de JLCPCB
**Autor:** Claude · **Rama:** `fix/girth-revd-cpl-centros` · **CI:** PCB run 43738514699 (puerta superada)
**Qué cambia:** el CPL ya aplica el giro y el centro de las huellas de JLCPCB/EasyEDA (`fuente/jlc_correcciones.py`, `jlc_correcciones.json`, `jlc.py`).
- U4: desplazado 2,7 mm.
- U6: +270°.
- U3 y U7: +270°.
- Q1 y Q2: +180°.
- U5 y U8: +180°.
- C47: +180°.

**Por qué:** la vista previa de JLCPCB mostraba el módulo C6 desplazado sobre el borde. La placa (cobre) no cambia.
**Aviso:** la REV C tiene el mismo problema de CPL. No pedirla con su CPL sin aplicar esta corrección.
**Estado:** compilado en CI · NO VERIFICADO en hardware.

## 2026-11-15 — Cincha — REV 6.2: sin bolsillo; cápsula sujeta por pestillos con seguro positivo (CAD)
**Autor:** Claude · Rama `feature/cincha-rev6-2-cierre` (desde develop, con la 6.1 integrada) · **CI:** no aplica
**Qué cambia (decisión del usuario 15/11 18:34 y aclaración de 18:35: cápsula expuesta, mucha vibración):**
- **Bolsillo de piel eliminado:** fuera del STEP, del patrón (B1/B2, broche y ventanas) y de la BOM.
- **Soporte** (`AVO_CINCHA_R6_2_soporte_pestillos_PETG`):
  - 2 pestillos elásticos de PETG integrados (viga de 1,2 × 12 × 12,9 mm, ε = 1,19 %), con gancho en una **ranura
    exterior** de la base (1,2 mm; no atraviesa la pared);
  - **seguros deslizantes de TPU 95A con retén de clic** (bloqueo positivo);
  - contrafuertes que protegen los pulsadores, rebajados;
  - cerco de 4,5 mm con 0,25 de holgura;
  - 4 tacos TPU 85A de precarga (sin juego vertical);
  - desagües en los huecos de los pestillos;
  - anclaje del cordón de seguridad.
- **Cápsula:**
  - ranura exterior y chaflán de entrada en la base;
  - **oreja maciza en la tapa** para un cordón Dyneema Ø1,5, fuera de la junta. La estanqueidad no cambia.
- **Retención calculada:**
  - ≈ 165 N con seguros (objetivo ≥ 100 N; choque de 50 g ≈ 32 N);
  - ≈ 65 N sin seguros;
  - lateral y giro, por el cerco.
- `DOCS/MONTAJE_CINCHA.md` §8 «Retención»: cálculo, uso con guantes y ensayos (tirón de 10 kg, vibración 1 h,
  caída de 1,5 m, 2000 ciclos, barro).
- Se actualizan la tabla de estanqueidad (filas 14–16), la BOM, los renders (13 = corte por el pestillo, 14 = pestillo
  y seguro) y el zip.
**No se ha tocado:** PCB, firmware, apps, workflows, firmas, Info.plist ni números de build.
**Validación:** IMPLEMENTADO.
- `verificar_step.py`: 24/24 STEP cerrados y planos.
- **NO VERIFICADO:** nada impreso; retención, fatiga e IP67 sin ensayar.
**Pendiente:** imprimir el soporte y una base; hacer los ensayos de §8.4 y §7.4. La fatiga entre capas de la raíz del
pestillo es el riesgo principal.

## 2026-11-15 — Cincha — cápsula REV 6.1: aro de luz (4 LED SK6812SIDE-A) y todo estanco (objetivo IP67) (CAD)
**Autor:** Claude · Rama `feature/cincha-cad-montaje` (con develop fusionado) · **CI:** no aplica
**Qué cambia (petición del usuario 15/11 15:10):**
- **Aro de luz:**
  - la **base entera** se imprime en PETG translúcido «natural» y su pared de 4 mm rodea la PCB a la altura de los 4 LED
    laterales (centro de la luz a z = 10,9; lentes a y = ±14,66; cotas de `feature/girth-pcb-rev-d-aro`);
  - la tapa pasa a ser plana, de PETG opaco;
  - no hay costuras ni uniones nuevas.
- **Estanqueidad:**
  - una sola junta TPU 85A de 1,2 × 1,6 en ranura de 1,9 × 1,2 (25 % de compresión, tope duro);
  - 6 tornillos M2 × 6 + arandela DIN 433 **fuera** de la línea de la junta, en insertos ciegos;
  - guías ciegas en la tapa;
  - pogos con epoxi de colada;
  - colas del soporte encapsuladas;
  - empalme de los electrodos soldado con termorretráctil con adhesivo (se quita el JST);
  - sin USB ni pasantes.
- **Bolsillo:** 2 + 2 ventanas de 20 × 4,5 frente a la banda de luz (patrón B2 actualizado).
- **Medidas:** cápsula de 62,9 × 60,1 × 15,5 mm (antes 59,4 × 54,5 × 14,7); soporte de 83,5 × 80,7 × 10,5.
- **Documentación:** `DOCS/MONTAJE_CINCHA.md` con la nueva §7 «Estanqueidad»:
  - tabla de los 13 puntos de entrada de agua;
  - impresión estanca;
  - ensayos de vacío, de inmersión a 1 m durante 30 min con papel indicador y de manguera.
  También se actualizan la BOM (≈ 200 €), los renders 12 (corte por los LED) y 13 (ventanas de luz) y el zip.
**No se ha tocado:** firmware, apps, PCB (solo se copia `piezas.json` de develop; los LED se modelan con las cotas indicadas),
workflows, firmas, Info.plist ni números de build.
**Validación:** IMPLEMENTADO.
- `verificar_step.py`: todos los STEP cerrados y planos.
- **NO VERIFICADO:**
  - IP67 sin ensayar;
  - luz sin probar;
  - nada impreso.
**Pendiente:**
- ensayos de §7.4 con una base impresa;
- comprobar la luz a través de la pared y de las ventanas;
- fusionar las cotas finales de los LED cuando se integre `feature/girth-pcb-rev-d-aro`.

## 2026-11-15 — Cincha — montaje del sistema en la cincha: cápsula REV 6, soporte, funda de piel y electrodos ECG (CAD)
**Autor:** Claude · Rama `feature/cincha-cad-montaje` · **CI:** no aplica (no hay workflow para esta carpeta)
**Qué cambia:** nueva carpeta `hardware/girth/CINCHA_MONTAJE/` (petición del usuario: «todo el sistema montado en una cincha,
en STEP, con funda de piel»):
- **STEP del conjunto completo**, curvado sobre un tórax de 188 cm de perímetro y en versión recta (87 sólidos):
  - cincha tipo Decathlon Fouganza de 110 cm, con elásticos, hebillas de rodillo de 25 mm y anilla D;
  - funda de piel con bolsillo;
  - soporte con 2 conectores pogo de pines;
  - cápsula REV 6, con PCB REV D, celda 603450, antena Molex 146153 y tornillería M2 inox;
  - 2 electrodos Vialta PG980/51 (60 × 85) + REF opcional, con espuma EVA, y cables.
- STEP por pieza, incluida una cincha anatómica tipo Horze (recta y curvada).
- **Piezas impresas** (STL):
  - base, tapa y soporte de PETG; junta y separador de TPU 85A;
  - cápsula de 59,4 × 54,5 × 14,7 mm, con la PCB colgada de la tapa sobre la celda;
  - 6 M2 × 8 en insertos térmicos.
- **Patrón plano de la funda** (DXF R12 + SVG 1:1, con capas de corte, pliegue, costura cada 4 mm, rebaje y taladros).
- Renders de comprobación y `DOCS/MONTAJE_CINCHA.md`: fuentes, BOM (≈ 190 €), impresión, montaje paso a paso y notas de la piel.
- Scripts reproducibles en `fuente/`: núcleo CAD propio `avo_cad.py` (numpy + OpenCV; en el entorno no había CadQuery/OCP ni
  FreeCAD), `avo_cincha_montaje.py`, `patron_funda.py`, `render.py` y `verificar_step.py`.
**Por qué:** petición del usuario con fotos de referencia (Decathlon Fouganza 14,50 €, Horze 110 cm 79,95 €). Electrodos
Vialta PG980/51 elegidos por el usuario. La lámina POTUBI con broche de 4 mm queda documentada como alternativa.
**No se ha tocado:** firmware, apps, PCB REV D (solo se copió su `piezas.json`), workflows, firmas, Info.plist ni números de build.
**Validación:** IMPLEMENTADO.
- `verificar_step.py`: 21/21 STEP con referencias completas, sólidos cerrados (0 aristas mal cosidas) y vértices en su plano.
- **NO VERIFICADO:**
  - los STEP no se han abierto en FreeCAD/SolidWorks;
  - no hay cálculo automático de interferencias;
  - nada impreso ni cosido;
  - nada probado en un caballo.
**Pendiente:**
- medir la cincha real (ancho y grueso estimados) y el electrodo Vialta (grosor y salida del cable estimados);
- imprimir una base y un soporte de prueba;
- prueba de inmersión de la cápsula;
- RSSI con la antena dentro;
- ECG en reposo.

## 2026-11-15 — Cincha REV D: aro de luz (4 LED) y firmware 0.6.0 con el aro
**Autor:** Claude · **Rama:** `feature/girth-pcb-rev-d-aro` · **CI:** PCB run 43723857285 (puerta superada: DRC 0, 0 conexiones, paridad 0, ERC 0/0) · firmware run 43723342562 (éxito, host 80/80)
**Qué cambia:**
- **PCB:** 4 × SK6812SIDE-A en los cantos largos en lugar del LED verde, datos por GPIO15 y alimentación conmutada (AO3401A + 2N7002, GPIO18). Ver `hardware/girth/PCB_REV_D/DOCS/INFORME_PCB_REV_D.md`.
- **Firmware:** `girth_ring.cpp` (RMT a 800 kHz). Los LED solo reciben tensión mientras se encienden.
- **Colores:**
  - azul: buscando la espalda;
  - verde: todo bien;
  - ámbar ×3: electrodos sin contacto;
  - rojo ×2: IMU sin datos;
  - rojo ×1: batería < 15 %;
  - en el soporte, naranja fijo cargando y verde fijo cargada (CHG por GPIO8).
- **Comando nuevo:** `aro on|off`.

**Por qué:** petición del usuario, igual que el aro del casco V5. La cápsula estanca con el aro va en `feature/cincha-cad-montaje`.
**Workflows:** sin cambios. Se lanzaron a mano (`workflow_dispatch`) en la rama nueva.
**Estado:** COMPILADO / CI · **NO VERIFICADO en hardware real**.

## 2026-11-15 — Cincha PCB REV D + firmware 0.6.0 + batería 1000 mAh
**Autor:** Claude · **Commits:** rama `feature/girth-pcb-rev-d` (puerta en `b63c741`) · **CI:** PCB run 43721512373 (éxito: DRC 0, 0 conexiones, paridad 0, ERC 0/0) · firmware run 43706692273 (éxito)
**Qué cambia:**
- **PCB REV D (46 × 30 mm, 4 capas):** ESP32-C6-MINI-1U-H4, LSM6DSV16X, MMC5983MA y ECG ADS1292 en TQFP-32 (C2651570), con RT9080 propio para AVDD.
- **Pines:** el CLK del ADS va a DGND (sin R46), y los pads 14 y 51 del módulo quedan sin conectar.
- **Reparación del ruteado:** vías GND de cosido (`stitch_gnd.py`) y `repair.py --src`, con costes configurables.
- **Firmware cincha 0.6.0:** controladores del ADS1292, del LSM6DSV16X (SFLP) y del MMC5983MA, lotes ESP-NOW fmt 0/1/2 y pines de la REV D. Sin conmutador de antena: GPIO3 y GPIO14 son del ADS. 71/71 pruebas de host.
- **Batería:** análisis en `DOCS/CONSUMO_BATERIA.md`, con la decisión de usar la 603450 de 1000 mAh.

**Workflows:** se añaden `build-girth-pcb-revd.yml` (Freerouting con `-mp 80`), `easyeda-fp-girth-revd.yml`, `jlc-stock-girth-revd.yml` y `build-girth-v060.yml`.
**Por qué:** el BNO085 y el MAX30003 no tenían existencias en JLCPCB. Con el VQFN del ADS1292 no se completaba el ruteado.
**Archivos:** `hardware/girth/PCB_REV_D/**`, `firmware/girth/V0_6_0/**`.
**No se ha tocado:** firmas, `Info.plist`, número de build.
**Estado:** COMPILADO / CI · **NO VERIFICADO en hardware real**. La PCB no se ha fabricado y el firmware no se ha cargado en ninguna placa.


## 2026-11-15 — iPad 1.0.0 — «Cámara» se abre con el menú lateral oculto
**Autor:** Claude · **Commits:** ver PR · **CI:** pendiente
**Qué cambia:** al entrar en «Cámara» el menú lateral se oculta (como en Inicio); solo se abre con el botón de menú
flotante de la esquina superior izquierda. Volver a pulsar «Cámara» en el menú también lo cierra. Las demás páginas
siguen abriendo con el menú visible.
**Por qué:** boceto del entrenador 15/11/2026 (build 145): «Al entrar a cámara menú oculto, solo lo abrís botón menú».
**Archivos:** `ipad/AVOiPad/App/RootView.swift` (`RootView.hidesSidebar`).
**No se ha tocado:** workflows, firmas, `Info.plist`, número de build.
**Estado:** IMPLEMENTADO · NO VERIFICADO en iPad real.
## 2026-11-15 — iPad — botón «SALIR» para cerrar la app del todo
**Autor:** Claude · Rama `feature/ipad-salir`
**Qué cambia:** al pie de la barra lateral, sobre los datos de versión, un botón rojo «SALIR» con confirmación. Cierra el Wi-Fi y el
Bluetooth del reloj, detiene la cámara (si graba, espera 2,5 s a que el vídeo se cierre), guarda y cierra la app del todo
(`App/AppModel+Quit.swift`). Boceto del entrenador del 15/11/2026.
**Aviso:** iPadOS no tiene una forma oficial de cerrar una app y Apple lo desaconseja: en TestFlight funciona; en una revisión de la
App Store podrían pedir quitarlo.
**Validación:** pendiente del CI del iPad. **NO VERIFICADO** en el iPad.

## 2026-11-15 — iPad — Vídeo asociado al entrenamiento, datos impresos y recorte
**Autor:** Claude · Rama `claude/ipad-video-datos` · **CI:** run 43698716776 (compila y pruebas unitarias OK, sin TestFlight)
**Qué cambia (peticiones del entrenador 15/11/2026, con referencia tipo «telemetry overlay»):**
- **Caballo al grabar:** se elige en el panel y se guarda en el `.avosync.json`.
- **Asociación al entrenamiento:** automática por la hora, prefiriendo el mismo caballo, o elegida a mano en el
  reproductor. En la lista de vídeos se ve a qué entrenamiento está asociado cada uno.
- **Reproductor con los datos encima:** velocímetro, barra de distancia, recorrido, brújula, coordenadas, aire,
  aceleraciones, tranco, IMU de la cincha, altitud, calidad GNSS, hora GPS y caballo.
  - Todo se puede elegir con el botón «Datos».
  - El pulso aparece «sin datos» hasta que se decodifique el ECG.
- **Recorte por delante y por detrás:** no destructivo, con agarres y botones.
- **Exportar con datos:** vídeo HEVC con los indicadores impresos (`videos/exportados/`), «Guardar en Fotos» y compartir.
- **Nuevos archivos:** `Core/VideoTelemetry.swift` (series del entrenamiento + dibujo), `App/VideoOverlayExporter.swift`.
  - `SessionItem.fullImu` pasa a ser legible.
  - `AvoSyncVideoFile` añade `horse`, `training_id`, `trim_start_s` y `trim_end_s`, opcionales, y lee igual los archivos
    de la build 136.
**No se ha tocado:** protocolo AVO SYNC, motor, Android, Windows, firmware, Info.plist (los permisos de Cámara y Fotos ya
estaban), workflows ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.
- No está comprobado que el vídeo exportado salga bien orientado con el iPad girado al revés.
- La sincronía con el reloj del iPad es de decenas de ms (estimada).

## 2026-11-15 — iPad — «Cámara» a todo el ancho y panel desplegable
**Autor:** Claude · Rama `claude/ipad-camara-ancho`
**Qué cambia (boceto del entrenador 15/11/2026, build 136):**
- **Imagen a todo el ancho:** la imagen de la cámara ocupa toda la página. Se quitan la barra superior, los márgenes y las
  bandas negras: la vista previa rellena el recuadro, y el vídeo grabado conserva el encuadre completo del sensor.
- **Botón de menú:** con el menú oculto, el botón para mostrarlo flota sobre la imagen.
- **Panel desplegable:** AVO SYNC, Grabación y Vídeos pasan a un panel que se despliega por encima de la imagen, a la derecha.
  - Se abre con el botón junto a la hora. El botón lleva un punto con el estado de AVO SYNC.
  - Se cierra con la ✕ o con el mismo botón.
  - La app recuerda si estaba abierto o cerrado.
- **REC:** el contador pasa arriba, al centro, y durante la grabación hay un marco rojo.
- **Reproductor:** se abre a pantalla completa, con fondo negro.
**No se ha tocado:** grabación, AVO SYNC, archivos, Info.plist, workflows ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-15 — Cincha PCB REV C — placa propia compacta con ECG (MAX30003)
**Autor:** Claude · Rama `feature/girth-pcb-rev-c` · **CI:** `build-girth-pcb-revc.yml` run 43672058713 (puerta superada)
**Qué cambia:** nueva PCB de la cincha en `hardware/girth/PCB_REV_C` (generador Python → KiCad 9, mismas herramientas que el
casco V5). 40 × 26 mm, 4 capas, 1,0 mm, componentes en una cara: ESP32-C6-MINI-1U-H4, BNO085 por I²C, MAX30003 con 1,8 V propio
y oscilador MEMS SiT1533, cargador BQ24072, 3,3 V RT9080, pogos de carga y de electrodos y batería por hilos, pads de
programación USB. Mismos GPIO que el XIAO: el firmware 0.5.0 sirve sin cambios. DRC 0, ERC 0/0, paridad 0, 0 conexiones
pendientes; Gerber, BOM, CPL y STEP en `out/FINAL`. El pad de esquina 51 del módulo (GND de anclaje) queda sin conectar.
**Workflows NUEVOS** (no se modifica ninguno existente): `build-girth-pcb-revc.yml`, `easyeda-fp-girth-revc.yml`,
`jlc-stock-girth-revc.yml`.
**Por qué:** el usuario pide una PCB de cincha lo más compacta posible, como la del casco (arquitectura confirmada: pogo +
BNO085 + MAX30003, cápsula nueva más pequeña, dos pogos de 3).
**Validación:** DISEÑO VERIFICADO POR SOFTWARE. **NO VERIFICADO** en hardware (no fabricada).
**Pendiente:** MAX30003 y BNO085 sin existencias en JLCPCB (Global Sourcing); cápsula REV 6 en FreeCAD; comprobar con la hoja
de ADI los valores del filtro de entrada y la huella del SiT1533.

## 2026-11-15 — iPad — Página «Cámara»: vídeo con hora GPS (AVO SYNC v1)
**Autor:** Claude · Rama `claude/ipad-camara-avo-sync` · **Commits:** `7a8ca9e` · **CI:** run 43665157107 (éxito, lanzado a mano sin TestFlight)
**Qué cambia:**
- **Menú del iPad:** nueva página «Cámara» (`Page.camera` = `Camera`) debajo de «Análisis», según el boceto del entrenador.
  Siempre está activa.
- **Grabación:** cámara trasera, HEVC, 1080p o 4K a 30/60/120/240 fps según el iPad, sin audio.
  - Se graba con `AVAssetWriter` para conservar el sello del reloj del iPad de cada fotograma.
  - Cada vídeo se guarda en `videos/` (`.mov`) con su archivo de hora `.avosync.json`.
- **AVO SYNC v1:** protocolo BLE nuevo e independiente, con UUID fijos, tramas `TIME_REQ`, `TIME_RESP`, `MARK` y `STATUS`,
  e intercambio tipo NTP cada segundo.
  - Filtro de menor retardo por ventanas de 10 s y recta de deriva.
  - Gestor Bluetooth propio, separado del de los relojes.
  - Sin gadget, se graba con el reloj del iPad y queda indicado.
- **Página:**
  - hora en directo sobre la vista previa;
  - estado del gadget;
  - marcas «Serie», «Vuelta» y «Fin»;
  - lista de vídeos con reproductor (hora GPS del fotograma y saltos a las marcas), compartir y borrar.
- **Prueba de capturas:** se añade `Camera`. En el simulador sale «sin cámara».
**Por qué:** boceto del entrenador («Cámara» debajo de «Análisis») y propuesta AVO SYNC V0.1: grabar el entrenamiento y
juntarlo con los datos por la hora GPS, aunque el caballo esté lejos (playa).
**Archivos:** `ipad/AVOiPad/Core/AvoSync.swift`, `App/AvoSyncLink.swift`, `App/CameraModel.swift`,
`Views/CameraView.swift`, `App/AppModel.swift`, `App/AppModel+Shell.swift`, `App/RootView.swift`,
`Resources/Info.plist`, `AVOiPadTests/AvoSyncTests.swift`, `AVOiPadUITests/ScreenshotTests.swift`,
`docs/AVO_SYNC.md`, `ipad/UI_CONTRACT.md`.
**Info.plist (avisado al usuario):** se añaden `NSCameraUsageDescription` y `NSPhotoLibraryAddUsageDescription`.
Sin el primero, la app se cierra al abrir la cámara. El segundo hace falta para «Guardar vídeo» desde Compartir.
**No se ha tocado:** contratos existentes (TELEMETRY, BackStatus, cincha, AVO1, `.avr`), enlace BLE con el reloj, motor,
Android, Windows, firmware, workflows, firmas ni el número de build.
**Validación:** IMPLEMENTADO.
- COMPILADO / CI: run 43665157107 sobre `7a8ca9e`. Compila para el simulador.
- `AvoSyncTests`: 4 de 4 pruebas superadas (simuladas).
- La prueba de capturas no saca la página: ya fallaba en `develop` desde la run 43653284779 (`No existe nav.*` en
  todas las páginas tras «Listado»), y no la causa este cambio.
- **NO VERIFICADO** en iPad real ni con gadget, porque el gadget no existe.
**Pendiente:**
- gadget y firmware `firmware/sync/V0_1`;
- medir la precisión real (LED a 240 fps);
- juntar el vídeo con el entrenamiento y superponer los datos;
- audio opcional;
- Android y Windows.

## 2026-11-15 — Cincha v0.5.0 — ECG con MAX30003 (fmt 2) sin tocar espalda ni pecho
**Autor:** Claude · Rama `feature/girth-ecg-0-5-0` · **CI:** `build-girth-v050.yml` (workflow NUEVO; no se modifica ninguno existente)
**Qué cambia:** nuevo firmware `firmware/girth/V0_5_0` (copia de 0.4.3 + ECG). Driver MAX30003 por SPI (CSB 17, SCK 19,
MISO 20, MOSI 18, INTB 7, FCLK 4) en tarea propia: 512 sps, 18 bits, ganancia 40 (configurable), HPF 0,5 Hz, LPF 40 Hz,
detección de electrodo despegado. Reloj FCLK de 32 768 Hz generado automáticamente si el módulo no lleva cristal. Sellos de
tiempo uniformes con corrección de deriva (`EcgClock`). Envío como lote `IMU_SAMPLE` fmt 2 (`imu_id` 3, unidades 2, int24 en
0,1 µV, 51 muestras = 177 B, máx. 60 = 204 B). LED de 3 destellos si los electrodos no hacen contacto. Órdenes serie `ecg`,
`ganancia`, `fclk`; `estado` muestra frecuencia, amplitud pico a pico y contadores.
**Por qué:** frecuencia cardiaca / ECG en la cincha (arquitectura confirmada por el usuario: pogo + BNO085 + MAX30003, dos placas
de electrodo separadas).
**Archivos:** `firmware/girth/V0_5_0/**`, `.github/workflows/build-girth-v050.yml`.
**No se ha tocado:** firmware de espalda y pecho (reenvían fmt desconocidos tal cual, comprobado en prueba de host con el
`GirthHub` real), workflows existentes, firmas, `Info.plist`, build de TestFlight.
**Validación:** pruebas de host 65/65 OK (simulación). Compilación ESP32-C6 en CI. **NO VERIFICADO** en hardware real.
**Pendiente:** decodificar fmt 2 en Android, Windows, iPad y motor (picos R, FC, recuperación); CAD de las placas de electrodo
y adaptación de la cápsula REV 5.10; confirmar si el módulo trae cristal de 32 768 Hz y su pinout ECGP/ECGN/VCM.

## 2026-11-15 — AVO-SHELL-31 — Biblioteca: una copia mala ya no hace rechazar el archivo bueno
**Autor:** Claude · Rama `feature/avo-equine-2-0`
**Qué pasaba:** si en la biblioteca de la app ya había una copia con el mismo nombre (la huella SHA-256 del archivo) pero con
otro contenido, por ejemplo una copia que quedó a medias, no se reemplazaba. El archivo bueno se rechazaba con «La copia de la
biblioteca no coincide con el original» (visto en «MALWINA_BELLA 2.avo» y «BELLA_AL_SHAHANIA 2.avo»).
**Qué cambia (iPad y Windows, por igual):** la copia mala se borra y se vuelve a copiar el original. Si después la copia sigue
sin coincidir, se rechaza como antes. El archivo original nunca se toca.
**No se ha tocado:** el motor, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-14 — AVO-SHELL-30 — El arranque no interrumpe con archivos de AVO Horse que no se pueden leer
**Autor:** Claude · Rama `feature/avo-equine-2-0`
**Qué pasaba:** la búsqueda automática de «AVO Horse» al arrancar intentaba importar en cada arranque los mismos archivos
que no se pueden leer, y sacaba en la portada el aviso «2 archivo(s) rechazados».
**Qué cambia (iPad):**
- La búsqueda del arranque ya no muestra ese aviso. El resumen queda en la barra de estado, con el número de archivos no
  legibles, y el motivo de cada uno sigue en «Estado de importaciones».
- Recuerda los archivos que fallaron (ruta, tamaño y fecha) y no los vuelve a intentar al arrancar. Si el archivo cambia,
  se reintenta.
- La importación manual («Abrir», «Buscar entrenamientos») sigue avisando como antes.
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-ENGINE-2.0-F2a — Trabajo completo bien detectado; selección movible; % de la espalda
**Autor:** Claude · Rama `feature/avo-equine-2-0`
**Por qué (boceto del entrenador):** «No detecta bien el trabajo; es esencial que se detecten bien las zonas». Antes, el
trabajo solo abarcaba lo que iba por encima del umbral de velocidad (11 m/s en PSI) y se dejaba fuera la arrancada y la
frenada.
**Qué cambia:**
- **Motor (EFFORT_V2):**
  - cada trabajo tiene límites completos, de la arrancada (acelerando) a la frenada (desacelerando);
  - la fase de trabajo y el calentamiento se miden con esos límites;
  - nuevo `distancia_trabajo_m` con su ventana `t0_trabajo`–`t1_trabajo`;
  - las métricas de fatiga siguen en el núcleo;
  - prueba del entreno de mañana ampliada: calentamiento 240 s (antes 246 s), arrancada y frenada incluidas.
  - Detalle: `docs/algoritmos/13_TRABAJO_PISTA.md`.
- **iPad y Windows (Parámetros clave / Datos clave):** «Distancia de trabajo» muestra el trabajo completo y al tocarla
  selecciona exactamente esa ventana del motor. Con resultados 1.x se mantiene la regla anterior. Pruebas idénticas en las
  dos apps.
- **iPad · Gráficas:** la selección tiene dos agarres, «Inicio» y «Fin», en la gráfica de velocidad, para moverla a mano;
  la tabla de la selección se recalcula.
- **iPad · Equipo conectado:** el recuadro Espalda muestra el % de batería de la espalda (TELEMETRY v2, `backBatteryMv`,
  misma tabla Li-ion que Android) y los mV.
  - El iPad se suscribe a la telemetría solo si el reloj la ofrece; si no, se ve «Enlazada» como antes.
  - Solo lectura: el protocolo no cambia.
- **iPad · Cuadra:** «France Galop» se mueve al extremo derecho de la barra.
**No se ha tocado:** protocolos, firmware, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** motor local 87 casos / 1524 comprobaciones, 0 fallos. CI pendiente. **NO VERIFICADO** con sesiones reales
ni con el reloj.

## 2026-11-14 — AVO-ENGINE-2.0-F1b — Aceleración del filtro y apps con la velocidad del motor
**Autor:** Claude · Rama `feature/avo-equine-2-0`
**Qué cambia:**
- **Motor:** la aceleración longitudinal (y su σ) sale del mismo filtro Kalman + RTS que la velocidad, en vez de la
  pendiente local ±0,5 s sobre gSpeed. Afecta a los máximos de aceleración y frenada, a los eventos de aceleración y frenada
  sostenida y a los cálculos de Trabajo en pista.
  - Las pruebas de aceleración conocida (rampa de 2 m/s², sostenida de 1,0 / −1,5 m/s² y ningún falso evento con ruido)
    siguen pasando.
  - El modo anterior sigue disponible (`accel_from_smoother = false`).
- **iPad y Windows:** la línea de tiempo adopta la velocidad y la aceleración del motor, con su σ, al recibir el análisis y
  al recortar la ventana útil. Así barra, gráficas, Parámetros clave, Cuadra, Comparar e informes salen de la misma serie
  que el motor.
  - Se interpola solo entre muestras del motor separadas como mucho 0,5 s; fuera de ellas se mantiene el filtro de la app.
  - No se adopta si el usuario ha cambiado la sacudida del filtro en Ajustes.
  - Pruebas nuevas idénticas en iPad (XCTest) y Windows (autoprueba) con la sesión sintética de referencia.
- **Android:** no tenía filtro propio; sus gráficas del motor ya reciben la serie suavizada.
- Fixtures JSON del motor regenerados.
**No se ha tocado:** protocolos, firmware, `.avr`, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** motor local 87 casos / 1521 comprobaciones, 0 fallos. CI pendiente. **NO VERIFICADO** con sesiones reales.

## 2026-11-14 — AVO-SHELL-29 — GPS sin cabecera y marea con % de subida o bajada
**Autor:** Claude · Rama `feature/avo-equine-2-0`
**Qué cambia (iPad):**
- **GPS:** sin el título «Datos GPS» ni el aviso de la antena del chaleco. La barra del entrenamiento ya identifica la sesión.
- **Resumen · marea:** debajo de «Marea 1,70 m · subiendo» aparece «N % de la subida» (o «de la bajada»). Es la altura a la
  hora del entrenamiento entre la bajamar y la pleamar anterior y siguiente, según la predicción del IHM
  (`EnvironmentModel.tidePhasePct`).
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-ENGINE-2.0-F1a — AVO Performance Equine 2.0.0-dev1: una sola velocidad para todo
**Autor:** Claude · Rama `feature/avo-equine-2-0` (desde `develop/avo-performance-horse` tras integrar el PR #20)
**Por qué:** el motor 1.1 calculaba todas sus cifras con la velocidad bruta del receptor (gSpeed), mientras que las apps
mostraban una velocidad filtrada propia. Por eso el mismo entrenamiento daba 60,2 km/h en el motor y 58,3 km/h en la barra.
Plan completo: proyecto, `claude/AVO_PERFORMANCE_EQUINE_2_0_PLAN.md`.
**Qué cambia:**
- **Velocidad del motor:** Kalman v-a + suavizado RTS en C++ (`smoother.h/.cpp`), con el mismo modelo y valores por
  defecto que las apps.
  - `GnssResult.speed` es ahora la velocidad suavizada, con su σ posterior, y de ella salen todas las cifras de velocidad:
    máxima, histograma, curvas, Trabajo en pista (distancias de trabajo y rápida, mejores distancias), aires y fusión.
  - gSpeed se conserva en `speed_raw` y en la nueva serie `velocidad_receptor`.
  - El modo 1.x sigue disponible (`smooth_speed = false`).
- **Versión:** `ENGINE_VERSION` 2.0.0-dev1 y versión de algoritmo GNSS 2.0.0. El nombre visible pasa a «AVO Performance
  Equine» en Android, Windows e iPad. Los identificadores técnicos (`avo_eq`, `avo-equine-*`) no cambian, por compatibilidad.
- **Pruebas del motor:** dos casos nuevos (`gnss2.*`) y fixtures JSON regenerados. Las pruebas de versión de Kotlin,
  Android, Windows e iPad esperan ya «2.0.0».
- **Resultado en simulación:** galope de 14 m/s con ruido σ 0,3 m/s → RMS 0,310 → 0,081 m/s; velocidad máxima 14,91 →
  14,22 m/s.
**No se ha tocado:** protocolos, firmware, formato `.avr`, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** pruebas locales del motor 87 casos / 1520 comprobaciones, 0 fallos (Linux, GCC). CI pendiente.
**NO VERIFICADO** con sesiones reales: es el paso F5.
**Siguiente (F1b):** las apps dejan de filtrar por su cuenta y dibujan la serie `velocidad` del motor; aceleración también
desde el filtro, con su σ.
## 2026-11-15 — iPad: motivo real cuando el reloj rechaza el Wi-Fi y botón «Reactivar Wi-Fi del reloj»
**Autor:** Claude · Rama `fix/ipad-wifi-motivos-rechazo` (desde `develop/avo-performance-horse`)
**Síntoma:** en la build 125 (ya sin el error del permiso de iOS) el iPad mostraba «el reloj no pudo activar su Wi-Fi (radio del reloj)» y descargaba por Bluetooth. El iPad reducía todos los rechazos de `WIFI_SYNC(start)` distintos de «sin microSD» a «radio del reloj».
**Qué cambia:**
- `BleWifiControl.refusal(code:)` traduce los códigos de `StartResult` del pecho: 3 sin microSD, 4 no arrancó su punto de acceso, 6 Wi-Fi bloqueado tras un reinicio (CHEST 3.7.7+), 7 memoria del reloj baja (CHEST 3.7.7+), otros «radio del reloj, código N».
- `WifiSyncAction.reenable = 5` y `BleWifiControl.reenableWatchWifi()`. La orden ya existía en el pecho desde 3.7.4 rc2 (`wifisync::set_enabled(true)`).
- Botón «Reactivar Wi-Fi del reloj» en «Reloj Wi-Fi», solo cuando el reloj respondió con el código 6, siempre con una confirmación previa. El bloqueo protege del bucle de reinicios: si el reloj vuelve a reiniciarse al encender el punto de acceso, se bloquea de nuevo y la descarga sigue por Bluetooth.
- La línea de estado sigue la fase de la descarga por Wi-Fi (uniendo, lista, descargando con velocidad, comprobando SHA-256); antes se quedaba en «Pidiendo al reloj que active su Wi-Fi…».
- Prueba unitaria `testWifiStartRefusalCodes`.
- Nota: el 14/11/2026 23:30 la build 125 sí descargó por Wi-Fi con el pecho 3.7.10 (captura del usuario, 32 % del entrenamiento 2 de 2): el rechazo anterior fue puntual.
**Archivos:** `ipad/AVOiPad/Core/WifiSync.swift`, `ipad/AVOiPad/App/WatchWifiModel.swift`, `ipad/AVOiPad/Views/WatchWifiView.swift`, `ipad/AVOiPadTests/WatchTests.swift`.
**No se ha tocado:** firmware, protocolo BLE, workflows, firmas, `Info.plist`, número de build, Android (Android tiene el mismo mapeo genérico en `AvoWifiSyncManager.kt`, pendiente).
**Validación:** IMPLEMENTADO. CI pendiente. NO VERIFICADO en iPad ni en el reloj.
**Pendiente:** probar en iPad + pecho 3.7.10 y llevar el mismo mapeo a Android.

---

## 2026-11-15 — iPad: el Wi-Fi del reloj fallaba siempre en TestFlight («error interno de iOS»)
**Autor:** Claude · Rama `fix/ipad-wifi-hotspot-entitlement` (desde `develop/avo-performance-horse`)
**Síntoma:** en la página «Reloj Wi-Fi» del iPad (build 123), `NEHotspotConfigurationManager.apply` devolvía `.internal` en los 3 intentos y la descarga pasaba a Bluetooth.
**Causa:**
- `build-avo-ipad.yml` archivaba la app **sin firmar** (`CODE_SIGNING_ALLOWED=NO`), así que el entitlement `com.apple.developer.networking.HotspotConfiguration` de `AVOiPad.entitlements` no llegaba al binario.
- La exportación vuelve a firmar con lo que encuentra en el archivo, de modo que la app de TestFlight salía sin el entitlement.
- Sin ese entitlement, iOS responde con el error interno.

**Cambio (workflow, avisado al usuario):**
- el archivo se firma **ad hoc** (`CODE_SIGN_IDENTITY=-`, sin certificado: no se acumula nada en la cuenta), solo para incrustar los entitlements;
- la exportación sigue usando la firma de distribución gestionada en la nube;
- un paso nuevo comprueba con `codesign` que el archivo lleva HotspotConfiguration y para el job si no.

**Sin cambios:** número de build, `Info.plist`, `ExportOptions` ni firma de distribución.
**Validación:** pendiente del CI de macOS y de probarlo en el iPad con la nueva build de TestFlight.

---

## 2026-11-14 — AVO-SHELL-28 — Cifras que coinciden: velocidad máxima y distancia de trabajo
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad y Windows, por igual):**
- **Velocidad máxima:** Datos clave / Parámetros clave mostraban la máxima propia del motor (p. ej. 60,2 km/h), mientras
  que la barra, Gráficas y Cuadra mostraban la filtrada (58,3 km/h). Ahora el recuadro usa la misma velocidad filtrada en
  todas partes, con el pie «Velocidad filtrada» (`withMaxSpeed` / `WithMaxSpeed`).
- **Distancia de trabajo:** el motor la calcula como la distancia recorrida a la velocidad de «trabajo rápido» o más
  (`trabajo_pista.perfil.v_rapido`, PSI 14,5 m/s), y no como un tramo continuo. Antes, al tocarla, se seleccionaba del
  primer al último esfuerzo, con pausas incluidas (2,11 km frente a 1,11 km).
  - Ahora selecciona desde el primer hasta el último momento por encima de ese umbral, sobre la misma velocidad filtrada de
    Gráficas (`openFastWork` / `OpenFastWork`).
  - Si no hay umbral, abre la ventana de los esfuerzos del motor.
  - Con un solo trabajo rápido la selección coincide; con varios separados incluye la pausa entre ellos.
**No se ha tocado:** el motor C++, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-14 — AVO-SHELL-27 — Comparar: tramo sin «Observaciones» y doble toque para quitar la selección
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- «Tramo seleccionado» ya no tiene la columna «Observaciones»; las cifras ocupan el ancho que deja libre.
- En las gráficas de Comparar, un doble toque quita la selección al momento. Sin selección, el doble toque sigue
  restableciendo el zoom.
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-26 — Recuadros de cifras alineados por arriba
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad y Windows):** los recuadros de cifras (Datos clave / Parámetros clave, `AvoMetric` y `AvoMetricTile`) se
alinean por arriba en lugar de centrarse, así que los iconos y las cifras de una fila quedan en la misma línea aunque el texto
de debajo ocupe una o dos líneas (boceto «línea / línea»). En el iPad, un recuadro sin icono reserva su hueco.
**No se ha tocado:** el motor, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-14 — AVO-SHELL-25 — Distancia de trabajo enlazada a gráficas y mapa de Comparar orientado
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:**
- **Datos clave / Parámetros clave (iPad y Windows, por igual):** «Distancia de trabajo» abre las gráficas sobre el trabajo,
  igual que «Mejor 200 m» y «Mejor 600 m». El tramo va del inicio del primer esfuerzo al final del último, según el motor.
  Hay una prueba idéntica en iPad y Windows.
- **Comparar (iPad):** el mapa de recorridos arranca como «Mapa»: recorrido en horizontal (el mar arriba, misma regla que
  `MapKitRoute`) y encuadrado con margen. «Ajustar recorridos» vuelve a esa vista, y las lupas conservan la orientación.
**No se ha tocado:** el motor C++, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-14 — AVO-SHELL-24 — Resumen: marea subiendo o bajando
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):** el tiempo del Resumen muestra la marea con su tendencia a la hora del entrenamiento: «Marea 1,70 m ·
subiendo», con flecha azul, o «· bajando», con flecha ámbar. Sale de la predicción del IHM (`tideTrend`), igual que en Mareas.
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-23 — Comparar con encuadre manual y automático; Resumen con tarjetas a la misma altura
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- **Comparar · Encuadre** (boceto: «posibilidad de mover los entrenamientos para encuadrar y encuadre automático»):
  - barra «Encuadre» sobre la velocidad comparada, con una fila por entrenamiento y botones −10 / −1 / +1 / +10 s (o
    −100 / −10 / +10 / +100 m al alinear por distancia), más «Encuadre automático» y «Restablecer»;
  - el encuadre automático hace coincidir el inicio del trabajo más rápido de cada entrenamiento. Desde la velocidad
    máxima retrocede mientras la velocidad sigue por encima de la mitad de esa máxima;
  - los desplazamientos solo afectan a la vista: mueven todas las gráficas comparadas. El tramo seleccionado y
    «Guardar como tramo» los tienen en cuenta; las sesiones no se modifican;
  - los desplazamientos se ponen a cero al cambiar los entrenamientos o el modo de alineación.
- **Resumen:** «Motor AVO Equine Intelligence» y «Valoración del entrenador» con la misma altura.
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-22 — Menú lateral reordenado, Calendario como botón y barra de Cuadra en una fila
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- **Menú lateral:** Dashboard, Entrenamientos, Análisis, Biomecánica, Informes, Cuadra, Jinetes, Carreras, y Configuración.
  Calendario sale del menú.
- **Entrenamientos:** botón «Calendario» junto a «Abrir».
- **Cuadra y Jinetes:**
  - sin la línea «N registrados · …»;
  - «Mostrar inactivos» y «France Galop» van en la misma fila que «Nuevo» y la búsqueda.
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-21 — Comparar a todo el ancho, nuevo orden de pestañas y páginas sin cabecera
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- **Comparar:**
  - sin título y sin panel izquierdo;
  - sin la fila de zoom y rango;
  - los entrenamientos a comparar se eligen en la barra superior (`CompareSelector`): lista ancha, una línea por
    entrenamiento con casilla y color, «Alinear por Tiempo / Distancia» y «Ocultar sin recorrido»; cada cambio actualiza
    la comparación;
  - el mapa superpuesto y las gráficas ocupan todo el ancho.
- **Pestañas:**
  - nuevo orden: Resumen, Mapa, Gráficas, Trabajo en pista, Comparar, GPS, Mareas, Motor, Asistente IA (Comparar pasa
    detrás de Trabajo en pista y el Asistente al final);
  - «Tramos» se oculta de momento: el análisis de tramos está en «Análisis tramo».
- **Asistente IA:** sin la cabecera del entrenamiento ni la barra «Archivo completo / Inicio = cursor…».
- **Trabajo en pista:**
  - sin la tarjeta de perfil de raza y base de las fases;
  - Calentamiento, Trabajo y Vuelta a la calma con la misma medida y el contenido centrado.
- **Biomecánica:**
  - sin la cabecera del entrenamiento;
  - sin la fila de lupas / Ver ±2 s / Guardar como tramo / Quitar selección;
  - sin la fila «VER Completo / Calentamiento / Trabajo / Enfriamiento»;
  - se mantiene la barra de vista general.
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-20 — Motor legible para el entrenador y Mareas más limpia
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- **Motor** (entrenador: «algo legible y entendible, que cualquier entrenador pueda sacar provecho»). Se quitan la
  cabecera del entrenamiento, la barra de ventana del archivo y la tarjeta técnica del motor. En su lugar:
  - **Lectura del entrenamiento:** frases cortas con el reparto por aires, los tramos a galope (el más largo, con su
    distancia y su media), las paradas, las frenadas sostenidas y las curvas. Avisa si no hay cincha y recuerda que no es un
    diagnóstico veterinario.
  - **Tiempo en cada aire:** barra de colores con tiempo, % y distancia por aire.
  - **Fases del entrenamiento:** cada fase con su aire, desde → hasta, duración, distancia y media.
  - **Momentos clave:** los eventos en lenguaje llano («Pasa de paso a galope», «Se para», «Arranca», «Frena de forma
    sostenida», «Entra en curva a la izquierda»), con su minuto.
  - **Curvas:** una frase por curva (sentido, giro, radio y fuerza lateral).
  - **¿Cuánto fiarse de estos datos?:** semáforo por dominio, con nombres y explicación claros (cincha, sincronización,
    archivo, calibración de sensores y cálculos del motor).
  - **Detalle técnico** (plegado): las tablas originales del motor y «Reprocesar con el motor».
  - Todo sale de las filas del motor: no se calcula ninguna cifra nueva.
- **Mareas:**
  - sin la cabecera del entrenamiento;
  - «Marea · fuente y valores», «Meteorología y oleaje» y «Origen de los datos» con la misma altura;
  - fuera los textos explicativos de «Origen de los datos». El estado solo aparece mientras carga o si hay un problema.
**No se ha tocado:** el motor C++, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-19 — Gráficas sin la fila de botones
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):** por decisión del entrenador («quitarla entera»), «Gráficas» ya no tiene la fila de botones:
lupas, flechas, Guardar como tramo, Quitar selección, Exportar CSV ni reproducción.
- Se mantienen el zoom con los dedos, la barra de vista general y la selección manteniendo pulsado y arrastrando.
- Guardar tramos sigue disponible en Tramos y en Biomecánica, y la reproducción en Mapa.
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-18 — Gráficas: «Mostrar datos» desplegable y sin «Uso, filtrado y unidades»
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- «Mostrar datos» va plegado por defecto, con Desplegar / Ocultar. Los interruptores y «Ver todo» no cambian.
- Se quita la tarjeta «Uso, filtrado y unidades» (texto de ayuda). Los filtros siguen igual.
**No se ha tocado:** el motor, el filtrado, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-17 — Mapa con la fila de pestañas del entrenamiento
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):** la pestaña «Mapa» muestra la misma fila de pestañas que el resto de páginas del entrenamiento
(Resumen, Mapa, Gráficas…). Antes la ocultaba, porque era la página de mapa a pantalla completa del menú lateral.
Se mantiene «Análisis tramo» en la barra superior.
**No se ha tocado:** el motor, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-16 — Equipo conectado: batería y módulos Chaleco · Espalda · Cincha
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- **Decodificación de GET_STATUS:** `WatchStatusFull` lee la respuesta completa del reloj, con la misma disposición que
  Android (`core/…/ble/Messages.kt`, `WatchStatus`): batería %, mV, carga (VBUS), enlace de la espalda, cincha, flujo RTCM,
  SD y grabación. No cambia el protocolo: solo se lee lo que el reloj ya envía.
- **Consulta:** `WatchWifiModel.readStatus()` pregunta por el enlace abierto; la ventana lo repite cada 5 s mientras está abierta.
- **Ventana «Equipo conectado»:**
  - la tarjeta del reloj muestra «Batería N %» con su icono (en rojo por debajo del 15 %), en lugar de la hora y el identificador;
  - tres recuadros: **Chaleco** (batería, mV, cargando, grabando), **Espalda** (enlazada o no, correcciones RTCM) y
    **Cincha** (conectada o no).
  - Sin estado legible se muestra «—» y «Sin estado del reloj».
**Limitación:** el estado del reloj no informa de la batería de la espalda ni de la de la cincha, solo de si están
enlazadas; por eso no se muestran.
**No se ha tocado:** protocolos, firmware, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** con el reloj real.

## 2026-11-14 — AVO-SHELL-15 — LIVE, tiempo automático en Resumen, lista de entrenamientos en línea y sin Datos clave
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- **LIVE:** el botón «Equipo conectado» pasa a ser la sección «LIVE» del menú lateral. Hay una fila por equipo conectado
  por Bluetooth, hasta 4; cada fila abre la ventana de gestión. El Dashboard añade el contador «Live» (conectados en tiempo
  real, máx. 4).
  - Se muestra el nombre del equipo y la hora de conexión. Caballo y jockey aún no llegan por el enlace (la telemetría en
    vivo no está decodificada en el iPad): no se inventan.
- **Resumen · tiempo:** se consulta solo al entrar, con la hora de inicio y la primera posición GNSS del entrenamiento
  (`EnvironmentModel.load`, con copia local). Desaparece el botón «Consultar». Si la consulta en línea está desactivada,
  se dice.
- **Selector de entrenamiento** de la barra superior: en vez del menú, que partía las líneas, abre una lista ancha con
  toda la información en una línea: Fecha | Caballo | Jinete | Disciplina | V. máx. | Tiempo | Km.
- **Pestañas:** «Datos clave» se oculta de la barra; sus cifras están en Resumen → Parámetros clave.
**No se ha tocado:** protocolos, firmware, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real ni con relojes conectados.

## 2026-11-14 — AVO-SHELL-14 — Botón «Equipo conectado» por Bluetooth
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- **Seguimiento de enlaces:** `IosBleCentral` lleva la lista de enlaces Bluetooth abiertos y avisa cuando uno se abre o se
  cierra (`BleLink`, `.avoBleLinksChanged`). La app no inicia ningún escaneo ni pide permiso por esto.
- **Botón en el menú lateral:** bajo Configuración aparece «Equipo conectado» solo mientras hay un equipo enlazado, con su
  nombre y un punto verde. Abre la ventana de gestión.
- **Ventana de gestión del hardware:**
  - por cada equipo, su nombre, la hora de conexión y su identificador en el iPad, con un botón «Desconectar»;
  - accesos a Reloj Wi-Fi y descargas, Geocercas y líneas, y Configuración;
  - no muestra batería, GNSS ni firmware, porque el enlace actual no los informa: no se inventan.
**Limitación:** el iPad solo abre el enlace mientras trabaja con el reloj (descarga, Wi-Fi, geocercas), así que el botón
aparece durante esas operaciones.
**No se ha tocado:** protocolos, firmware, Windows, workflows, firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** con un reloj real.

## 2026-11-14 — AVO-SHELL-13 — Resumen: columnas del análisis del caballo a la misma altura
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):** en «Análisis del caballo», las tres columnas terminan a la misma altura: Zonas de velocidad, Esfuerzo
y Aceleraciones + Curvas. La tarjeta de Curvas se estira hasta abajo.
**No se ha tocado:** el motor, Windows, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-12 — Resumen al estilo Equimetre, Resumen y Mapa primeros, ficha con «X»
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- **Resumen** (boceto Equimetre del entrenador, «Así quiero resumen»):
  - cabecera con foto y nombre del caballo, «Ver ficha», Editar (asignar) e Informe PDF; fecha y hora grandes;
  - disciplina · jinete; distancia, duración y lugar; comentario del entrenamiento (las notas de siempre);
  - tiempo de la sesión, solo si se ha consultado en Mareas para esa sesión (si no, «Sin datos del tiempo · Consultar»);
  - debajo, «Parámetros clave» (las cifras de Datos clave) y «Análisis del caballo», desplegables;
  - al final, el motor y la valoración.
  - La reproducción, el mapa y los recuadros del cursor salen del Resumen.
- **Barra del entrenamiento:**
  - el orden es Resumen, Mapa, Datos clave, Gráficas…;
  - «Mapa» ocupa el sitio de «Análisis», que queda oculto de momento: pedir Análisis abre Resumen;
  - el menú lateral pierde «Mapa»; «Análisis» abre el entrenamiento por Resumen.
- **Ficha de Cuadra y Jinetes:** sin el botón «‹ Cuadra / ‹ Jinetes» encima (la ficha sube arriba) y con una «X» de salir en
  la esquina superior derecha de la tarjeta.
**No se ha tocado:** el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.
**Pendiente:** Windows aún no tiene el Resumen nuevo ni este orden de pestañas.

## 2026-11-14 — AVO-SHELL-11 — Cuadra y Jinetes: «Mejor 200 m» en los totales
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad y Windows, por igual):**
- Los totales de la ficha pasan de 5 a 6 recuadros: «Mejor 200 m» entre «V. máxima» y «Último». Es el mejor tiempo de
  200 m entre todos los entrenamientos de la ficha que tienen resultado del motor, con la misma regla que el recuadro
  «Mejor 200 m» de Datos clave (si no hay, «—»).
- `KeyData` expone el valor numérico (`best200S` / `Best200S`), con pruebas idénticas en iPad y Windows (11,36 s).
- Informes: la vista previa ocupa el 62 % del ancho (ajuste de AVO-SHELL-10).
**No se ha tocado:** el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-14 — AVO-SHELL-10 — Informes: opciones arriba y Exportar a todo el ancho
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad):**
- La columna derecha de Informes lleva, de arriba abajo, «Opciones del informe» (desplegable), «Exportar» y «Notas», todas
  al ancho completo de la columna. La vista previa ocupa el 62 % del ancho (antes la mitad; boceto 14/11/2026 10:44)
  y la columna derecha el resto.
- En Exportar, los botones van en tres columnas, todos del mismo alto y en una sola línea («Informe PDF» y «Compartir
  último» ya no se cortan).
- «Último:» muestra solo el nombre del archivo, no la ruta interna.
**No se ha tocado:** el motor, Windows, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-9 — Botones de ficha a igual alto, Biomecánica en 4 bloques iguales e informe con cifras estilo Datos clave
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:**
- **Ficha de Cuadra y Jinetes (iPad):** Guardar, Copiar enlace y Eliminar tienen el mismo ancho y alto, en una sola línea
  (el texto pasa de «Copiar enlace avohorse://» a «Copiar enlace»; copia el mismo enlace).
- **Biomecánica (iPad):** cuatro bloques del mismo tamaño en dos columnas iguales: caballo | cifras y, debajo,
  Canales de la cincha | Índices del motor por sensor (sustituye a la disposición de AVO-SHELL-8).
- **Informes PDF y HTML (iPad y Windows, por igual):** los recuadros de cifras (Tramo, Resumen, etc.) usan el estilo de
  Datos clave: sin caja ni barra roja, cifra centrada, nombre en versalitas debajo y líneas finas de separación.
**No se ha tocado:** el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-14 — AVO-SHELL-8 — Arranque sin entrar solo, Biomecánica a medida igual e Informes desplegable
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:**
- **Arranque (iPad):** la búsqueda silenciosa de «AVO Horse» ya no abre el último entrenamiento importado ni cambia de
  página; la app se queda en la portada y solo activa INICIAR. `importFiles(_:restoring:navigate:)` con `navigate: false`
  desde `loadFromAvoHorse()`.
- **Biomecánica (iPad):**
  - la tarjeta del caballo tiene la misma altura que el bloque de cifras;
  - las cuatro cifras miden lo mismo (dos filas iguales de dos);
  - «Canales de la cincha» va debajo, con el mismo ancho, y la columna termina a ras de «Índices del motor por sensor».
  - `AvoCard` admite `fill: true` para estirarse a la altura de la fila.
- **Informes (iPad):**
  - sin título de página: la vista previa empieza arriba;
  - «Opciones del informe» es un desplegable (Ocultar / Desplegar), cerrado por defecto, que indica cuántas secciones van marcadas.
**No se ha tocado:** el motor, Windows, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-7 — Todos los recuadros de cifras con el estilo de Datos clave; Cuadra, Configuración y tramo
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:**
- **Recuadros de cifras (iPad `AvoMetric`, Windows `AvoMetricTile`):** pasan al estilo de Datos clave en toda la app: sin caja,
  icono fino elegido por el nombre de la cifra, cifra y unidad centradas, nombre en versalitas y líneas finas. Todos miden lo
  mismo (alto mínimo de 138). Afecta a Análisis del tramo, Cuadra, Jinetes, Calendario, Resumen, etc.
- **Cuadra y Jinetes (iPad):**
  - sin título de página en la ficha;
  - Guardar, Copiar enlace y Eliminar tienen el mismo ancho;
  - los totales van en una fila de 5.
- **Ficha de Cuadra y Jinetes (iPad):**
  - foto a la izquierda con los datos a su derecha; se elige de Fotos, se guarda en `<app>/fotos/<código>.jpg` (máx. 900 px)
    y también se ve en la fila de la lista;
  - «Entrenamientos» y «Tramos guardados» van primero, como desplegables (Ocultar / Desplegar).
- **Configuración (iPad):** incluye «Reloj Wi-Fi» y «Geocercas y líneas» (salen del menú lateral) junto al Servidor AVO.
  La prueba de capturas llega a ellas desde Configuración.
- **Análisis del tramo (iPad):** la tabla de parciales usa todo el ancho de la tarjeta y los metros («1000–1200») no se parten.
- Se incluyen también el mapa alineado y encuadrado por defecto y la reproducción a 1× (AVO-SHELL-6).
**No se ha tocado:** el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad ni en PC reales.
**Pendiente:** en Windows, la ficha de Cuadra/Jinetes y la página Configuración aún no siguen estos bocetos.

## 2026-11-14 — AVO-SHELL-6 — Datos clave por recuadros, carga de AVO Horse al arrancar y gráficas al arrastrar
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:**
- **Datos clave (iPad y Windows, mismas reglas y pruebas):**
  - «Mejor 1000 m» pasa a ser **Distancia de trabajo**: la distancia del trabajo rápido dentro del entrenamiento
    (`trabajos.distancia_rapida_m` del motor).
  - Recuadros por fila: velocidad 6, pulso 3 (sin «Recuperación a 15 min») y tranco 5 (sin «Frecuencia a 58 km/h»), cada
    fila a todo el ancho.
  - Se quitan el título de la página, la columna de sesiones y la tarjeta «Calidad de la posición». Aires ocupa todo el ancho.
  - En los parciales, el tiempo y la velocidad van en dos columnas de la misma medida.
- **Barra del entrenamiento (iPad):** como en Mapa, solo la sesión con sus datos; sin «Entreno 2».
- **Arranque (iPad):** tras restaurar la biblioteca, la app revisa «Archivos › En mi iPad › AVO Horse» e importa en silencio los
  entrenamientos guardados que falten, sin duplicados. «INICIAR» espera a que termine y mientras tanto muestra «Cargando datos
  de AVO Horse…».
- **Mapa (iPad):** al abrirse, el recorrido sale siempre alineado en horizontal y encuadrado entero (vista predeterminada; ya no
  se recuerda la orientación norte arriba), y la reproducción empieza a 1×.
- **Gráficas (iPad):** al arrastrar la ventana de la barra de resumen (o desplazar y pellizcar) se redibujan cada 120 ms; antes
  solo se redibujaban al soltar.
**No se ha tocado:** el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** IMPLEMENTADO · CI pendiente · **NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-14 — AVO-SHELL-5 — iPad: barras, menú lateral, mapa del análisis y tabla de entrenamientos
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad, bocetos del usuario sobre la build 91):**
- **Entrenamientos:** se corrige el hueco enorme encima de la tabla (un `Color.clear` de la cabecera se estiraba en vertical).
- **Menú lateral:**
  - Mapa, Análisis y Biomecánica quedan atenuados y sin acción hasta que se abre un entrenamiento (desde la lista, el
    calendario o el Dashboard).
  - El pie muestra los datos de la app: versión, build y fecha de compilación.
- **Barra inferior:** a la izquierda, la versión del motor de IA; a la derecha, el copyright.
- **Barra del entrenamiento:** Fecha | Caballo | V. máx. | Tiempo | Km.
- **Análisis/Mapa:**
  - el mapa abre encuadrando el recorrido entero y ya no salta al tramo de trabajo cuando llega el resultado del motor;
  - los paneles y botones sobre el mapa usan siempre los colores oscuros (en modo claro no se veían las cifras ni los iconos);
  - se quitan la fila de botones «Zonas» y su leyenda.
**No se ha tocado:** Windows, el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** COMPILADO / CI: iPad run 43526019186 (TestFlight build 92). **NO VERIFICADO** en iPad real.

## 2026-11-14 — AVO-SHELL-4 — iPad: el menú lateral vuelve a abrirse, imagen entera y gris claro más oscuro
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia (iPad, sobre la build 90):**
- Al ocultar el menú lateral en el Dashboard no se podía volver a abrir: la barra lateral se pedía con `.all`, que en una vista de
  dos columnas puede quedarse oculta. Ahora se pide con `.doubleColumn` en el botón y al cambiar de página.
- El Dashboard muestra el logotipo entero (antes se cortaba «PERFORMANCE» y, sin menú, la página quedaba descompensada): la
  imagen se ajusta dentro del recuadro sobre su fondo negro.
- Modo claro: fondo, superficies secundarias, líneas y cabecera un poco más oscuros.
**No se ha tocado:** Windows, el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** COMPILADO / CI: iPad run 43524630332 (TestFlight build 91). **NO VERIFICADO** en iPad real.

## 2026-11-13 — AVO-SHELL-3 — Entrenamientos, Calendario (Semana), Cuadra e informe con logotipo
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:**
- **Entrenamientos (iPad):** la tabla es propia en lugar de `Table`:
  - filas rectas, sin redondeo, con colores alternos;
  - la fila seleccionada va en un tono neutro con una barra roja a la izquierda, en lugar del rojo/granate;
  - las cabeceras ordenan al tocarlas; se mantienen el menú contextual y el botón de abrir grande.
- **Menú lateral (iPad):** los nombres nunca se cortan (una línea y columna algo más ancha).
- **Calendario (iPad y Windows):** nueva vista **Semana**: 7 columnas a toda la altura con hora, caballo, distancia y
  duración. Las reglas `weekStart`/`weekGrid`/`weekTitle` son las mismas en Swift y C#, con la misma prueba.
- **Cuadra (iPad):** lista a todo el ancho, con una fila por caballo o jinete, colores alternos y desplazamiento; al tocar
  una se abre su ficha a página completa con «‹ volver».
- **Informe (iPad y Windows, HTML y PDF):** la cabecera lleva el logotipo (1 · cabeza de caballo, 2 · «AVO Horse Edition
  Performance», recortados de `avo_brand_hero`). Título, fecha y sesión van en tres líneas a la derecha y ya no se montan.
  El PDF de Windows admite imágenes JPEG, como el del iPad, y guarda una sola copia del logotipo para todas las páginas.
**No se ha tocado:** el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** COMPILADO / CI: Windows run 43520776654 (éxito) · iPad run 43520780825 (tests unitarios en verde; TestFlight build 90).
**NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-13 — AVO-SHELL-2 — Modo claro (iPad), Datos clave estilo Equimetre y ajustes del Dashboard
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:**
- **Paleta doble en iPad (`Views/Theme.swift`):** cada color de `Avo` tiene un valor oscuro (el de siempre) y otro claro.
  Las tarjetas y la cabecera también. «Configuración › Apariencia» permite elegir Oscuro o Claro; la elección se guarda en
  `UserDefaults` («avo.appearance») y se aplica al momento en la app y en las hojas (`.avoColorScheme()`).
  No hay opción «Como el sistema» porque `Info.plist` fija `UIUserInterfaceStyle = Dark` y no se ha tocado.
- **Datos clave (iPad y Windows), estilo «Key parameters» de Equimetre:** sin cajas; icono fino, cifra y unidad centradas,
  nombre en mayúsculas pequeñas y líneas finas entre celdas. Las velocidades y los tiempos usan el icono del caballo.
- **Dashboard:**
  - el panel de cifras se salía de la pantalla porque la imagen pedía más ancho, y por eso no se veían los números
    (build 88); corregido;
  - los 5 huecos de «Últimos entrenamientos» miden lo mismo, con un hueco vacío si hay menos de 5.
**No se ha tocado:** el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** COMPILADO / CI: Windows run 43518612675 (éxito) · iPad run 43518616953 (TestFlight build 89).
**NO VERIFICADO** en iPad ni en PC reales.
**Pendiente:** modo claro en Windows (allí la paleta usa `StaticResource` y aún no hay página de Configuración).

## 2026-11-13 — AVO-SHELL-1 — Dashboard, Entrenamientos, Calendario y Configuración (bocetos del usuario)
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:**
- **Barra superior:** en iPad y Windows solo aparece en las páginas de un entrenamiento; las páginas generales no la tienen.
  En iPad se mantiene el botón del menú cuando la barra lateral está oculta.
- **Inicio:** sale del menú lateral; la portada solo se ve al arrancar.
- **Dashboard (iPad y Windows):**
  - la imagen va sin texto encima;
  - a la derecha, cinco contadores pulsables: Caballos, Jockeys, Entrenamientos, Esta semana (de lunes a domingo, hora
    de Madrid) y Por revisar (sin caballo o sin analizar);
  - abajo, los 5 últimos entrenamientos en lugar de la fila de totales; al tocar uno se abre en Datos clave.
  - Las reglas están en `DashboardSummary` (Core `KeyData.swift`/`.cs`), con la misma prueba en las dos apps.
- **Entrenamientos (iPad):**
  - sin título ni resumen; barra con «Filtros» (panel plegable) y «Abrir»;
  - la tabla queda con favorito, fecha, caballo, jinete, distancia, velocidad máxima y abrir, con el botón de abrir más grande;
  - la selección va en un tono rojo más apagado.
  - En Windows la tabla del Dashboard tiene las mismas columnas, y «Abrir» / «Importar carpeta» van en su cabecera.
- **Configuración (iPad, nueva):** en lugar de «Servidor AVO» en el menú. Contiene:
  - buscar entrenamientos perdidos, buscar en una carpeta, exportar y copiar a AVO Horse;
  - el acceso al servidor.
  - Más adelante tendrá otros ajustes, como el modo claro/oscuro.
- **Calendario (iPad y Windows):** solo la cuadrícula, a página completa, sin acumulados ni filtro de caballos.
**No se ha tocado:** el motor, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** COMPILADO / CI: Windows run 43515844299 (éxito) · iPad run 43515849775 (tests unitarios en verde; TestFlight build 88).
**NO VERIFICADO** en iPad ni en PC reales.
**Pendiente:** página Configuración en Windows (allí no hay recuperación ni copia a AVO Horse); modo claro.

## 2026-11-13 — AVO-START-2 — Pantalla de inicio con botón «INICIAR» (iPad y Windows)
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20)
**Qué cambia:** boceto del usuario sobre la build 86.
- En la pantalla de inicio se quitan el botón «Menú» y el panel lateral de accesos.
- El lema «CIENCIA · TECNOLOGÍA · RENDIMIENTO» queda centrado abajo.
- Encima del lema hay un único botón «INICIAR», con borde blanco fino sobre azul marino translúcido, que abre el Dashboard.
  La barra lateral vuelve en el resto de páginas.
- Archivos: `ipad/AVOiPad/Views/StartView.swift`, `ipad/AVOiPad/App/RootView.swift` y
  `ipad/AVOiPadUITests/ScreenshotTests.swift` (las capturas entran por `start.iniciar`); en Windows,
  `Views/StartView.xaml` y `Views/HeroArt.xaml` (el lema pasa de HeroArt a StartView con los mismos contornos Montserrat).
**No se ha tocado:** los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** COMPILADO / CI: Windows run 43514114679 (éxito; el run 43513678310 falló porque la comprobación de captura
esperaba 5 acciones, corregido) · iPad run 43513683877 (TestFlight build 87 subido). **NO VERIFICADO** en iPad ni en PC reales.

## 2026-11-13 — AVO-PARITY-2 — Datos clave: 6 por fila, tranco a velocidad de referencia, parciales y navegador
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` (PR #20) · Contrato: `docs/PARIDAD_IPAD_PC.md`
**Qué cambia (iPad y Windows, mismas reglas y mismas pruebas):**
- Rejilla de 6 fichas por fila. Tras ver la build 84, el usuario pidió «6 en línea».
- Cuatro fichas nuevas de tranco y frecuencia a las dos velocidades de referencia de la raza (`referencia[]` del motor;
  mediana entre trabajos, como `training.cpp`).
- Al tocar un mejor 200/600/1000 m se abre Gráficas con ese tramo seleccionado y ampliado.
- Tarjeta «Parciales cada 200 m» por trabajo, con el parcial más rápido en rojo; al tocar un parcial o el trabajo se abre en Gráficas.
- Navegador lateral de sesiones por día, con búsqueda por caballo, que se puede ocultar.
- Archivos:
  - iPad: `Core/KeyData.swift`, `App/AppModel+KeyData.swift`, `Views/KeyDataView.swift`, `Views/CalendarView.swift`
    y `AVOiPadTests/KeyDataTests.swift`.
  - Windows: `Core/Analysis/KeyData.cs`, `MainViewModel.Parity.cs`, `Views/KeyDataView.xaml` y `SelfTest/KeyDataTests.cs`.
**Por qué:** ideas del webinar de Equimetre (capítulos Key Data y Graphics) que pidió el usuario.
**No se ha tocado:** el motor C++ (ya daba `parciales` y `referencia`), los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** COMPILADO / CI: Windows run 43387375222 (éxito, 7 self-tests nuevos PASS; el run 43387112395 falló por
`CultureInfo.GetUnicodeCategory`, corregido) · iPad run 43387116210 (tests unitarios en verde; TestFlight build 86 subido).
**NO VERIFICADO** en iPad ni en PC reales.
**Pendiente:** eje de distancia en Gráficas; zonas de pulso cuando llegue el ECG de la cincha.

## 2026-11-13 — AVO-PARITY-1 — iPad y PC: Calendario y Datos clave (paridad)
**Autor:** Claude · Rama `claude/paridad-calendario-datos-clave` · Contrato: `docs/PARIDAD_IPAD_PC.md`
**Qué cambia:**
- **iPad:** nuevas páginas **Calendario** (vista de mes y de año, acumulados y filtro por caballo) y **Datos clave**
  (velocidad, mejores 200/600/1000 m, pulso pendiente del ECG de la cincha, tranco, aires y calidad GNSS).
  `Core/KeyData.swift`, `Views/CalendarView.swift`, `Views/KeyDataView.swift`, pruebas `KeyDataTests`, y las dos páginas
  añadidas a las capturas de la UI.
- **Windows:** las mismas páginas con las mismas reglas: `AVO.Windows.Core/Analysis/KeyData.cs`,
  `MainViewModel.Parity.cs`, `Views/CalendarView.xaml`, `Views/KeyDataView.xaml`, `SelfTest/KeyDataTests.cs` (mismo JSON y
  mismos valores que en iPad), y las dos páginas añadidas a las capturas.
**Por qué:** petición del usuario de que iPad y PC tengan los mismos datos y análisis, con ideas de presentación tomadas de
Equimetre. El pulso solo procederá de la cincha propia (no se usará el Polar H10).
**No se ha tocado:** el motor C++, los contratos binarios, los workflows, las firmas, `Info.plist` ni el número de build.
**Validación:** COMPILADO / CI: Windows run 43333938426 (éxito, 8 self-tests nuevos PASS) · iPad run 43333943702 (TestFlight
build 84 subido; tests fallaron por el nombre del módulo, corregido) · iPad run 43335103721 (éxito: tests + capturas
`04_Calendar`, `09_KeyData`). **NO VERIFICADO** en iPad ni en PC reales.
**Pendiente:** tabla de análisis, Comparar, Historia y Track Work en Windows; sesión de referencia; ficha de sesión.

## 2026-11-13 — AVO-ASSIGN-1 — asignación de caballo y jinete en todas las apps y en el motor
**Autor:** Claude · Rama `claude/asignacion-caballo` · Contrato: `docs/ASIGNACION_CABALLO.md`
**Qué cambia:**
- **Motor:** opción `asignacion` (bloque del manifiesto) en `avo_eq_analyse_ex`/`compare_ex`; `sesion.caballo`/`jinete` con
  la asignación y, nuevos, `caballo_nombre`, `jinete_nombre`, `caballo_raw`, `jinete_raw` e `identidad` (RAW | ASIGNACION).
  La asignación entra en el hash de parámetros. `avo_eq_cli --caballo/--caballo-nombre/--jinete/--jinete-nombre`.
  Pruebas `test_identity.cpp` (2 casos, 23 comprobaciones). Referencias JSON regeneradas: solo esas 5 claves.
- **Android:** el caballo y el jinete elegidos se envían al reloj al elegirlos y antes de INICIAR (aviso si no hay caballo);
  el `.avo` compartido lleva el bloque `asignacion` (con la cabecera RAW en `raw`); al importar manda el bloque y gana la
  asignación más reciente; el motor recibe la asignación; la sincronización ya no pisa un caballo asignado a mano.
  `core/share/AvoAssignment.kt` + `AvoAssignmentTest` (6 pruebas).
- **Windows:** `AvoAssignment.cs`; asignar reescribe el manifiesto de la copia de la biblioteca y de los `.avo` de la
  carpeta del reloj (RAW byte a byte, verificado, sustitución atómica); la biblioteca guarda la huella anterior
  (`PreviousSha256`); la cuadra adopta asignaciones más recientes; el motor recibe la asignación. `AssignmentTests`.
- **iPad:** `AvoAssignment.swift`; mismo flujo que Windows; `AvoPackageWriter` ya no deja el caballo en blanco en los
  paquetes de la descarga (Android los rechazaba) y admite reescribir con `manifestBase`. `AssignmentTests` (4 pruebas).
**Por qué:** petición del usuario: «cuando se asigne caballo en la app iOS, Android o Windows también modifique en el raw para
no tener problemas». Decisión del usuario: **no se modifica el RAW** (su SHA-256 identifica el entrenamiento); la identidad
vive en el manifiesto `.avo` y se elige en origen.
**Probado con datos reales:** sesión del 08/11 11:38 (`HORSE_001` en el RAW) analizada con la asignación «Zakina» /
«Andoni Lezama»: identidad correcta, distancia idéntica, RAW sin cambios.
**Validación:** CI de motor, Android, Windows e iPad sobre la rama (ver PR) · **NO VERIFICADO** en móvil, PC, iPad ni reloj.
**Pendiente:** comparación de dos sesiones con caballos distintos (la opción es común a las dos); que el reloj muestre el
caballo configurado antes de grabar.

---

## 2026-11-12 — Reglas y CI tras la integración — AGENTS.md, CLAUDE.md, TestFlight y pecho desde develop
**Autor:** Claude · Rama `claude/reglas-ci-tras-integracion` · **CI:** al fusionar (ver PR)
**Qué cambia:**
- `AGENTS.md` (reglas comunes) y `CLAUDE.md` (resumen): una sola `develop` con ramas cortas por tarea integradas por PR
  con *merge commit*; prohibido borrar ramas antiguas hasta tener las 53 etiquetas `backup/2026-11-12/*`; lista de
  ficheros secretos prohibidos (la clave privada ECDSA de licencias vive solo en AVO Tarjetas); hardware actual,
  contratos binarios y CI; tabla de componentes actualizada (Windows, iPad, motor, cincha, espalda V4).
- `.github/workflows/build-avo-ipad.yml`: el trabajo `testflight` se ejecuta con push a **`develop`** (antes, a
  `feature/ipad-app`). Los filtros `paths:` y el número de build (`run_number`) no cambian.
- `.github/workflows/build-chest-v377-despertar.yml`: añade `develop` a sus ramas; sus `paths:` ya eran solo las carpetas
  `firmware/chest/V3_7_*` del pecho 3.7.10.
- `docs/crear_tags_backup.sh`: script de las 53 etiquetas de respaldo con los commits auditados.
**Por qué:** petición del usuario tras terminar la integración: reglas permanentes y TestFlight/pecho desde `develop`.
**No se ha tocado:** código de apps ni firmware, secretos, firma, `Info.plist`, `paths:` de los workflows.
**Validación:** IMPLEMENTADO · YAML validado · NO VERIFICADO hasta el primer push a `develop` que cambie esas carpetas.

---

## 2026-11-12 — Integración en develop — 11 fusiones (PR #7 a #17)
**Autor:** Claude · **Plan:** `PLAN_INTEGRACION_DEVELOP.md` (conocimiento del proyecto)
**Qué cambia:** `develop/avo-performance-horse` pasa de `18a9823` (23/10) a reunir todo el trabajo vigente:
`feature/avo-wifi-sync` (#7), cincha REV 5.9.2/5.10 (#8), **pecho 3.7.10** (#9), **espalda 3.14.3** con 3.13.12 (#10),
licencias 2.5 + **AVO Tarjetas 1.4** (#11), Android 2.6 + 2.8 → **2.9-integrada-dev1, vc 42** (#12), **iPad + motor
Equine (Training Analytics, Track Work) + Windows V2 PRO** (#13), registro de `ipad-analisis-entreno` (#14), **espalda V4
+ CAD Rev E.7** sin tocar la 3.14.3 (#15), auditoría de la PCB de la cincha REV B/B.1 (#16) y ODB++ para AISLER (#17).
**Conflictos resueltos:** registro y README (los dos lados); espalda → 3.14.3 (contrato binario solo con añadidos);
Android → vc 42; motor y Windows → lado iPad (descendiente del de develop) y retirada de 5 ficheros de la UI de
Windows V1 (`EngineChart`, `MainWindow.Engine`, `MainWindow.Usb`, `RouteView`, `TelemetryChart`): la descarga USB se
conserva porque `ChestUsb.cs`, `SimWatch.cs` y `usb_transcript.json` son idénticos.
**CI en develop:** Android, Windows, AVO Update, espalda 3.14.3, cincha, Firebase e iPad en verde; pecho 3.7.10
compilado a mano sobre develop (run 43270226647).
**No integradas a propósito:** `main`, `feature/avo-measurement-engine-v4`, `fix/chest-v373-readfile`,
`fix/back-3-13-8-gps-uart` y `ci/*`.
**Validación:** COMPILADO / CI · NO VERIFICADO en hardware como conjunto.
**Pendiente:** etiquetas de respaldo (esta sesión no puede crearlas); tabla única de versiones en `README.md`.

---

## 2026-11-11 — Cincha (CAD) REV 5.10 — módulo de pulso MAX30003 y segundo pogo
**Autor:** Claude · Rama `feature/girth-rev5-10-pulso` (propuesta, sin fusionar), sobre `feature/girth-rev5-9-2-pogo-empotrado`
**Qué cambia:**
- cápsula de W 51 a 53 (70 × 53 × 13,8); batería otra vez centrada (`BAT_Y` = 0);
- módulo CJMCU-30003 (21 × 16 × 8 con el jack, según el usuario; sin el jack, ≤ 4,2 E) en el hueco −X de la bandeja, con ventana debajo;
- los tubos de la tapa del antiguo Qi pasan a ser topes a 0,2 mm sobre el módulo;
- segundo pogo de 3 pines en y = +19,7 (simétrico al de y = −19,7) para los electrodos: ECGP, VCM y ECGN;
- en la bandeja, paso y canales de los hilos (pogo → módulo y módulo → C6);
- en el soporte, segundo alojamiento de pines y canal inferior de 4 × 2 hasta el borde +Y;
- conexión propuesta: CSB D7, SCK D8, SDO D9, SDI D10, INT1 MTDO (GPIO7) y FCLK MTMS (GPIO4) si hace falta.
**Por qué:** petición del usuario: «Necesitamos meter en la caja el módulo de pulso». El usuario eligió la cápsula de la cincha y el segundo pogo.
**Validación:** CI sin interferencias y 1 sólido por pieza. NO VERIFICADO en impresión ni con el módulo.
**Pendiente:** altura real sin el jack; si la placa lleva oscilador de 32 768 Hz; firmware del MAX30003.

---

## 2026-10-31 — Cincha (CAD) REV 5.9.2 — pogo empotrado por completo en el soporte
**Autor:** Claude · Rama `feature/girth-rev5-9-2-pogo-empotrado` (propuesta, sin fusionar)
**Qué cambia:**
- placa del soporte `MT` de 6,0 a 8,5 mm;
- el lado de los pines del pogo (cuerpo de 6,0 + colas de 1,5) queda dentro de la placa, con 1,0 mm libre bajo las colas;
- el rebaje de las orejas sigue abierto por abajo; tornillos M2 × 4 como máximo;
- la pared de la cápsula se recorta en vertical con la forma de la placa pogo, que entra desde arriba;
- conector de y = −20,2 a y = −18,7 (0,8 mm de pared hasta la ranura de la junta); cuna de la batería 1,0 mm hacia +Y (`BAT_Y`).
- los 8 agujeros M3 del cierre en la base pasan a ser pasantes (sin capa de sacrificio).
**Por qué:** petición del usuario: «engrosar el soporte para que quede empotrado completamente el pogo» y «recortar la pared para poder introducir por arriba el pogo sin problemas»; «faltan los agujeros pasantes para todos los tornillos que cierran la caja».
**Validación:** CI sin interferencias y 1 sólido por pieza. NO VERIFICADO en impresión.

---

## 2026-10-31 — Cincha (CAD) REV 5.9.1 — conector pogo según el modelo STEP real
**Autor:** Claude · Rama `feature/girth-rev5-9-1-pogo-medido`, fusionada en `feature/avo-wifi-sync` a petición del usuario
**Qué cambia:**
- el conector sale del modelo STEP que aporta el usuario (`hardware/girth/REV5/ref/pogo_3pin_assembly.step`, exportado de Onshape), medido en el CI (`inspect_pogo.py`);
- **placa en la base:** cara de 15,5 × 4,65 a ras del fondo y reborde de 17,1 × 6,25 × 3,5;
- **pines en el soporte:** cuerpo de 15,5 × 4,65 × 6 con la cara a ras; orejas de 25 × 5,5 a media altura en un rebaje abierto por abajo; tornillos M2 a 19,5 mm;
- paso de 2,3 entre contactos (no 2,54);
- las piezas de referencia salen del STEP.
**Por qué:** petición del usuario, que sustituye a las medidas estimadas y a las lecturas de calibre en fotos.
**Validación:** CI sin interferencias y 1 sólido por pieza. NO VERIFICADO en impresión.
**Pendiente:** prueba impresa del encaje de las dos mitades y de los tornillos M2.

---

## 2026-10-31 — Windows V2 PRO — gráficas del movimiento de la cincha (propuesta)
**Autor:** Claude · Rama `feature/windows-girth-movimiento` (desde `feature/windows-advanced-analysis`) · **CI:** run 41221077611 (éxito: autopruebas, compilación, capturas)
**Qué cambia:** nueva fila de Gráficas, que solo aparece si la sesión trae IMU_SAMPLE fmt 1 (cincha GIRTH 0.4.x):
- **Aceleración sin gravedad (m/s²) en ejes del mundo:** la vertical (arriba +) y la horizontal salen de rotar la aceleración lineal con el cuaternión del game rotation vector;
- **Orientación de la cincha (°):** balanceo y cabeceo. El rumbo no se muestra porque, sin magnetómetro, deriva.
- Casilla «Movimiento de la cincha» en «Mostrar datos».
**Autopruebas:** cuaternión identidad; giro de 90° en x; reposo real de la cincha (balanceo ≈ 8,2°, cabeceo ≈ −5,6°, igual que el monitor serie de 0.4.2).
**Validación:** CI. Pendiente de ver en el PC del usuario con una sesión real (NO VERIFICADO).

---

## 2026-10-31 — Cincha 0.4.3 + Windows V2 PRO — PRUEBA FÍSICA: IMU de la cincha en unidades reales
**Autor:** Claude · Evidencia: foto de Windows Advanced Analysis V2 PRO (build de `feature/windows-girth-bno-units`, CI run 41217576644), «Entrenamiento 31/10/2026 17:10», HORSE_001
- **PROBADO FÍSICAMENTE:**
  - la app reconoce las unidades declaradas por la cincha 0.4.3: la gráfica muestra «g, unidades del BNO085»;
  - en reposo la aceleración vertical está en torno a 1 g (menos al inclinar la cincha) y, al moverla a mano, da picos de más de 2 g.
- Fusionado `feature/windows-girth-bno-units` → `feature/windows-advanced-analysis` (`28bd3cd`).
- **Pendiente:**
  - dibujar fmt 1 (aceleración lineal y cuaternión);
  - cadencia con el caballo en marcha;
  - unidades en la app de Android (RawSession solo usa |a| para la cadencia; no le afecta la escala).

---

## 2026-10-31 — Cincha GIRTH 0.4.3 — las muestras de IMU declaran sus unidades
**Autor:** Claude · Rama `feature/girth-fw-0-4-0-bno085`
**Qué cambia:**
- el byte 15 de la cabecera IMU_SAMPLE («reserved» en avo_payloads.h, que la espalda conserva al reenviar) vale 1, que significa «unidades del BNO085»: acc y aceleración lineal Q8 m/s², giro Q9 rad/s, mag Q4 µT y cuaternión Q14;
- con 0 (cinchas anteriores o REV B), las apps siguen usando su escala nominal.
**Por qué:** la app de Windows dibujaba la IMU con la escala nominal del LSM6 (±8 g): 1 g del BNO085 (2511 LSB) salía como 0,61 g.
**No se ha tocado:** espalda, pecho y formato de la trama (mismo tamaño y mismos campos).
**Validación:** host 40/40 (la prueba comprueba que la espalda conserva el byte). **CI:** run 41217466325 (éxito). App de Windows: rama `feature/windows-girth-bno-units`, CI run 41217576644 (éxito). NO VERIFICADO en el hardware.

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
## 2026-11-09 — Pecho 3.7.10 CARGA APAGADO — encendido por USB: sin despertar la espalda y apagado al desenchufar
**Autor:** Claude · **Rama:** `feature/chest-3-7-7-despertar-espalda` · **Commits:** `bf7022b` + corrección del workflow · **CI:** [42619748077](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42619748077) (**éxito**; incluye 3.7.7–3.7.9)
**Qué cambia:** lee el origen del encendido del AXP2101 (reg. 0x20). Encendido por USB: nunca transmite a la espalda y se apaga (apagado controlado) 2 s después de desenchufar, salvo si se pulsa BOOT/PWR o empieza una sesión. Tampoco transmite antes de leer el PMU. `V3_7_10_CARGA_APAGADO/tools/apply_v3710.py`.
**Validación:** IMPLEMENTADO · CI · **NO VERIFICADO** (falta confirmar en el reloj el valor del registro 0x20 en el monitor: `encendido por USB (solo carga) (AXP2101 0x20 = 0x..)`).

## 2026-11-09 — Pecho 3.7.9 CARGA — la espalda no se despierta con el pecho cargando
**Autor:** Claude · **Rama:** `feature/chest-3-7-7-despertar-espalda` · **Commits:** `57edcd0`, siguiente · **CI:** [42617435387](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42617435387) (**éxito**; incluye 3.7.7 y 3.7.8)
**Por qué:** el usuario vio que al conectar el pecho a cargar la espalda se despertaba (baliza de la 3.7.7).
**Qué cambia:** con USB y sin grabar: `BACK_SLEEP` si la espalda está enlazada y, 1,5 s después, ninguna transmisión a la espalda (ni baliza ni DATA). Al quitar el USB o grabar, vuelve la baliza. `V3_7_9_CARGA/tools/apply_v379.py`.
**Validación:** IMPLEMENTADO · CI · **NO VERIFICADO** en el reloj.

## 2026-11-09 — Pecho 3.7.8 VINCULAR — 3 pulsaciones de BOOT para vincular un móvil
**Autor:** Claude · **Rama:** `feature/chest-3-7-7-despertar-espalda` · **Commit:** `94e6053` · **CI:** [42603761121](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42603761121) (**éxito**; artefacto [`AVO-CHEST-V3-7-8-VINCULAR-UNVERIFIED`](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42603761121/artifacts/13665944700); incluye todo lo de la 3.7.7)
**Qué cambia:** evento `TRIPLE` de `BootButton`; triple pulsación → 120 s de modo vincular: desconecta y bloquea el móvil actual, anuncia, autoriza el CLAIM del nuevo sin pulsar BOOT, pantalla «MODO VINCULAR». La doble pulsación se reconoce 350 ms después de soltar. Detalle: `V3_7_7_DESPERTAR/INFORME.md` §7.
**Validación:** IMPLEMENTADO · CI (prueba de host del botón) · **NO VERIFICADO** en el reloj.

## 2026-11-09 — Pecho 3.7.7 DESPERTAR — sueño de la espalda, bloqueo Wi-Fi y vínculos Bluetooth
**Autor:** Claude · **Rama:** `feature/chest-3-7-7-despertar-espalda` (desde 3.7.6 GNSS QUALITY) · **Commits:** `5cf704c` … `7e5c0b0` · **CI:** [42587757628](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42587757628) (**éxito**; artefacto [`AVO-CHEST-V3-7-7-DESPERTAR-UNVERIFIED`](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42587757628/artifacts/13659991810), SHA-256 `365c2851…2fff`)
**Qué cambia:** `V3_7_7_DESPERTAR/tools/apply_v377.py` + `build-chest-v377-despertar.yml`. Al apagar manda `BACK_SLEEP` (2 veces) antes de cortar el AXP2101; baliza DATA cada 100 ms mientras la espalda no responde; el bloqueo Wi-Fi `wifi_off` guarda el firmware que lo puso y se borra con otro firmware; motivos 6/7; NimBLE con 6 vínculos y 20 CCCD (antes 3/8: el tercer móvil borraba el vínculo del más antiguo). Detalle: `firmware/chest/V3_7_7_DESPERTAR/INFORME.md`.
**Hallazgo en CI:** un texto que terminaba en «3.7.7» hacía que el enlazador fusionara con él la cadena de versión (ya no quedaba junto a `AVO-CHEST`); corregido en `7e5c0b0`.
**No se ha tocado:** RAW/SD, sesiones, tramas ESP-NOW, NTRIP/RTCM, GNSS, pantallas, USB, OTA, particiones (todas las pruebas de la 3.7.6 pasan).
**Validación:** IMPLEMENTADO · CI · **NO VERIFICADO** en el reloj.
**Pendiente:** pasos de `INFORME.md` §6.

## 2026-10-31 — CHEST 3.7.6 GNSS QUALITY — calidad GNSS de la espalda hasta Android, sobre la 3.7.5-usb1
**Autor:** Claude · **Rama:** `feature/chest-v3-7-6-gnss-quality` (desde `feature/chest-usb-pc-sync`) · **Commits:** `8494035`, `e76347d`
**Qué cambia:**
- **Cadena de compilación:** el pecho se compila como la 3.7.5-usb1 y después se le aplica la calidad GNSS:
  - `avo_payloads` de la espalda, que es el mismo archivo con el que se compila la 3.13.11 y decodifica `BackStatus` v3;
  - `apply_v376.py`, que envía `TELEMETRY` v3 de 116 B por BLE, el formato que Android ya decodifica;
  - un parche nuevo de frescura.
- **Frescura:** si el último `BackStatus` tiene más de 5 s, se envía `q_flags = 0`. Además, `quality_age_s` suma la antigüedad del enlace. Así no se presentan como actuales valores viejos de una espalda apagada.
- **Versión:** `3.7.6`, sin sufijo.
**Por qué:**
- Con la espalda 3.13.11 y el pecho 3.7.5-usb1, Android mostraba «Necesita espalda 3.9.0 y pecho 3.7.6».
- La usb1 se compiló sobre la rc5, sin el parche 3.7.6. Su decodificador solo lee la v2 (82 B) y envía `TELEMETRY` v2 (83 B).
- La espalda sí envía la v3 (108 B, `s.v3 = true`).
**Hallazgo (no corregido, documentado):**
- `ota.cpp` `version_cmp()` rechaza toda OTA firmada si la versión instalada lleva sufijo (`3.7.5-usb1`, `3.7.0-rc2`). Comprobado en el PC con el código real.
- Por eso la 3.7.6 se instala con AVO Update por USB y se llama `3.7.6`, para que la próxima OTA firmada funcione.
- No se ha tocado la verificación ES256.
**Archivos:**
- `firmware/chest/V3_7_6_GNSS_QUALITY/{tools/apply_v376_gq.py, tests_test_gnss_quality_v376.py, host/gnss_quality_host.cpp, INFORME_COMPATIBILIDAD.md}`;
- `.github/workflows/build-chest-v376-gnss-quality.yml`.
- En el árbol compilado solo cambian `avo_payloads.*`, `avo_ble_proto.*`, `ble_service.cpp` y `avo_version.h`. El CI lo comprueba con `diff`.
**No se ha tocado:**
- `main`, el firmware y la alimentación de la espalda, ni Android (no necesita cambios);
- RAW, sesiones y geocercas;
- UART/ESP-NOW, NTRIP/RTCM y GNSS;
- pantallas, batería, OTA con ES256, particiones, Wi-Fi y USB AVO1.
**Validación:**
- IMPLEMENTADO.
- Pruebas locales y en CI:
  - todas las de la usb1 antes y después del parche, incluida la transcripción USB de Windows;
  - la `TELEMETRY` v3 es idéntica byte a byte al vector de `FirmwareVectorsTest` de Android;
  - el `BackStatus` v3 de la espalda se decodifica en el pecho.
- CI: run 41190303008 (éxito, `e76347d`), los 13 pasos en verde.
  - `AVO_CHEST_V3_7_6_GNSS_QUALITY.bin`: 1.582.779 B, +576 B respecto a la usb1.
  - SHA-256 `d413f5ec14d6d3cf0c9885c062f924eb8e2aa4447e28f0c17e497d7abae7af4b`.
  - RAM estática: 71.800 B.
  - Artefacto `AVO-CHEST-V3-7-6-GNSS-QUALITY-UNVERIFIED` (13038657376), caduca el 29/01/2027.
- **NO VERIFICADO en el reloj.**
**Pendiente:** prueba física, según el apartado 6 de `INFORME_COMPATIBILIDAD.md`.

## 2026-10-30 — CHEST 3.7.5-usb1 — pantalla «CONECTADO AL PC» (solo con PC; con cargador, la de siempre)
**Autor:** Claude · **Rama:** `feature/chest-usb-pc-sync` · **Commits:** `1192c49`, `4801bec`
**Qué cambia:**
- **Detección:** con un PC en el cable, el reloj muestra «CONECTADO AL PC» en lugar de la pantalla de carga. El PC se reconoce por las tramas USB de inicio de trama (`Serial.isPlugged()`) o por órdenes AVO1 en los últimos 30 s.
- **Contenido:** estado (abre AVO Windows / comparando / descargando i de n con barra y % / sincronizado con N nuevos / interrumpida / grabando) y la batería real.
- **Con un cargador o batería externa** se ve la pantalla de carga de la 3.7.2 sin ningún cambio.
- **Mismas reglas que la pantalla de carga:** grabación → tarjetas, toque → tarjetas 30 s, OTA y apagado con prioridad, mismo brillo.
- **Nueva orden `AVO1 PROGRESS`:** AVO Windows la envía en cada fase y cada 5 %. Con un firmware anterior es inofensiva.
**Por qué:** petición del usuario. La pantalla debe aparecer al conectar al PC y, sin PC, seguir como estaba.
**Archivos:**
- `firmware/chest/V3_7_5_USB/src/{ui_pc.h,ui_pc_draw.h,usb_sync.*}`, `tools/apply_v375_usb.py` (parches en `ui.cpp` y `ui_dash.cpp` durante la compilación; no cambian las fuentes de `V3_7_2_UI`), `host/pc_preview.cpp`, `PROTOCOLO_USB.md`, workflow;
- `windows/AVO.Windows.Core/ChestUsb.cs` y las autopruebas.
**CI:**
- firmware: run 41076422328 (éxito, `4801bec`). BIN de 1.582.203 B; RAM estática +96 B respecto a la rc5. Incluye la vista previa `AVO-CHEST-V3-7-5-USB1-PANTALLA-PC-PREVIEW`.
- Windows: run 41075952072 (éxito, `1192c49`), 49 autopruebas.
**Validación:** IMPLEMENTADO · CI. **NO VERIFICADO** en el reloj.
**Pendiente:** comprobar en el reloj que `isPlugged()` distingue el PC del cargador de pared y de la batería externa (prueba 5 de `PROTOCOLO_USB.md`).

---

## 2026-10-30 — CHEST 3.7.5-usb1 + AVO Windows V1.1 — descarga automática de entrenamientos al PC por USB
**Autor:** Claude · **Rama:** `feature/chest-usb-pc-sync` (desde `feature/avo-wifi-sync`, sin fusionar) · **Commits:** `b4e57c8`, `261bee3`
**Qué cambia:**
- **Firmware del pecho 3.7.5-usb1** (`firmware/chest/V3_7_5_USB`), sobre 3.7.5-rc5, la última con pruebas de campo. El parche también se aplica sin cambios sobre 3.7.6-rc1.
  - Protocolo AVO1 de texto en el puerto serie USB: HELLO, LIST, SHA, READ.
  - Lo atiende la tarea `loop` de Arduino, que estaba parada. No hay tarea nueva: los buffers van en PSRAM y la RAM interna estática sube 64 B.
  - Solo lectura. No sirve sesiones OPEN y no responde mientras se graba.
  - Usa el mismo etag y SHA-256 que la descarga Wi-Fi.
- **AVO Windows V1.1:**
  - detecta el reloj al conectarlo (USB VID 303A / PID 1001, con `WM_DEVICECHANGE` y una comprobación cada 4 s);
  - compara su lista con `Documentos\AVO Performance Horse\Reloj`, incluidos los `.avo` ya importados de Android, que se reconocen por SHA-256;
  - descarga los que faltan: bloques de 4 KB con CRC-32, reintentos, reanudación y SHA-256 final;
  - los guarda como `.avo` (AVO-TRAINING-1) y los importa;
  - añade la tarjeta «RELOJ POR USB» en Inicio y el botón SINCRONIZAR RELOJ.
- Detalle: `firmware/chest/V3_7_5_USB/PROTOCOLO_USB.md`.
**Por qué:** petición del usuario. Al conectar el reloj al PC, la app de Windows debe reconocerlo, comparar los entrenamientos y descargar los que falten.
**Archivos:**
- `firmware/chest/V3_7_5_USB/*`, `.github/workflows/build-chest-v375-usb.yml`;
- `windows/AVO.Windows.Core/ChestUsb.cs`, `windows/AVO.Windows/MainWindow.Usb.cs`, XAML y csproj (System.IO.Ports);
- `windows/AVO.Windows.SelfTest/{SimWatch.cs,usb_transcript.json,Program.cs}`;
- `TrainingImporter` lee el `sha256` del manifiesto;
- `build-avo-windows.yml`: se añade la rama.
**No se ha tocado:** RAW, grabación, BLE, ESP-NOW, NTRIP/RTCM, GNSS, OTA, Wi-Fi, pantalla y particiones del pecho; app Android.
**CI:**
- firmware: run 41073707599 (éxito, `261bee3`), BIN de 1.579.967 B. Incluye `usb_sync.cpp` real compilado en el PC y probado: descarga, rechazos, microSD intacta y transcripción idéntica.
- Windows: run 41072995871 (éxito, `b4e57c8`), 46 autopruebas, 18 de ellas de USB, con el firmware real (transcripción) y un reloj simulado con fallos.
**Validación:** IMPLEMENTADO · CI. **NO VERIFICADO** en el reloj ni en un PC real.
**Pendiente:** las pruebas físicas 1–6 de `PROTOCOLO_USB.md`. La más importante: comprobar que el reloj no se reinicia al abrir el puerto y que `[AVO MEM] ready` no baja respecto a la rc5. Después, decidir si se fusiona en `feature/avo-wifi-sync` y se lleva a la 3.7.6.

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

## 2026-11-09 — Licencias — AVO Tarjetas 1.4-nfc-movil-dev1 + Android 2.5-roles-dev2: activar un móvil por NFC con AVO Tarjetas
**Autor:** Claude · **Rama:** `feature/avo-license-nfc` · **Commits:** `ac97d61`, `0f2bad2` · **CI:** run 42672931752 ✅ (`android-apk`: 141 pruebas core, 0 fallos; app y AVO Tarjetas compiladas y firmadas; el trabajo del emulador no llegó a arrancar por un fallo de GitHub al crear los trabajos)
**Qué cambia:**
- **AVO Tarjetas hace de tarjeta NFC** (Host Card Emulation, `AvoHceService`, AID `F041564F4C494301`, `requireDeviceUnlock`): en un usuario del registro, «ACTIVAR SU MÓVIL POR NFC (SIN TARJETA)» → roles y fecha → «Preparar»; durante 2 minutos (una sola activación) responde al móvil que se le junte. Mientras espera, desactiva el modo lector y se marca como servicio preferido. Diálogo con cuenta atrás, cancelar, resultado; historial «Licencia en móvil por NFC · móvil XXXXXXXX» (`RegEvent.Kind.MOVIL`).
- **La licencia queda atada al móvil activado:** `LicenseIssuer.issueForDevice` firma un token v2 con el **id del móvil** (SHA-256 de Android ID + paquete, 10 B) en el campo UID y `LicenseToken.FLAG_DEVICE` (0x02). `LicensePolicy.activateOnDevice` lo exige; la tarjeta y el archivo rechazan tokens de móvil y viceversa.
- **App AVO:** en el lector NFC global, una etiqueta sin NDEF con IsoDep se prueba como AVO Tarjetas (`onPhoneCard`): recibe la tarjeta de usuario (adoptada como identidad igual que al acercar la tarjeta) y la licencia (`LicenseManager.activateFromPhone`, `deviceId`). Otros dispositivos se ignoran sin aviso. Tarjeta nueva en Ajustes → Licencia explicándolo.
- **Protocolo** en `core/.../license/NfcActivation.kt` (SELECT / ACTIVATE / READ por trozos de 240 B), sin Android, con pruebas JVM `NfcActivationTest` (intercambio completo en bucle, nombre largo en varios trozos, otro móvil, tarjeta y archivo con token de móvil, otra clave, no preparado, comandos mal formados).
**Por qué:** el usuario pide que AVO Tarjetas sirva como tarjeta NFC para activar un móvil; eligió que el móvil del emisor active al del usuario y que la licencia quede atada al móvil activado.
**Archivos:** `core/.../license/NfcActivation.kt` (nuevo), `LicenseToken.kt`, `LicenseIssuer.kt`, `LicensePolicy.kt`, `IssuerRegistry.kt`, `core/src/test/.../NfcActivationTest.kt` (nuevo), `cards/.../PhoneActivation.kt` (nuevo), `cards/.../CardsActivity.kt`, `cards/src/main/AndroidManifest.xml`, `cards/src/main/res/xml/avo_hce_service.xml` (nuevo), `cards/src/main/res/values/strings.xml` (nuevo), `app/.../MainActivity.kt`, `app/.../license/LicenseManager.kt`, `app/.../ui/screens/LicenseScreens.kt`, versiones, `docs/LICENCIAS_AVO.md`, `README.md`, `docs/ESTADO_DESARROLLO_Y_VERSIONES.md`.
**Validación:** IMPLEMENTADO · CI ✅ (run 42672931752) · NO VERIFICADO con dos móviles.
**Limitaciones:** solo Android ↔ Android con NFC y HCE; el iPad no tiene NFC. Restablecer el móvil de fábrica cambia su id (hay que activarlo otra vez).
## 2026-11-09 — Android 2.8-wifi-ble-dev1 — descarga Wi-Fi y Bluetooth con varios móviles
**Autor:** Claude · **Rama:** `feature/android-2-8-wifi-ble` (desde 2.7-borrado-reloj-dev1) · **Commits:** `c134463`, `ee93fa1` · **CI:** [42587795621](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42587795621) (**éxito**: core 150 pruebas, emulador 2, firma estable, licencias F5EEE5D2; artefacto [`AVO-Performance-Horse-V2_8_WIFI_BLE_DEV1-APK`](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42587795621/artifacts/13659668221)), versionCode 41
**Qué cambia:**
- Bloqueo Wi-Fi: el intento se borra con cualquier respuesta a `WIFI_SYNC(start)`; solo cuenta un reinicio en los 5 min siguientes (antes un `start` sin respuesta + un apagado normal del reloj bloqueaba el Wi-Fi para siempre). Botón «Probar Wi-Fi» en Entrenamientos.
- Tras unirse a la red del reloj: `/api/v1/status` cada segundo (4 s) hasta 30 s antes de descargar (mismo caso que el iPad el 07/11).
- Un corte corto reintenta el mismo entrenamiento 2 veces y reanuda (prueba `t21_shortHiccupIsRetriedInTheSamePass`).
- Motivos 6 y 7 del pecho 3.7.7 en el registro.
- BLE: dos fallos rápidos seguidos tras conectar con el reloj «vinculado» → se borra el vínculo del móvil y se empareja de nuevo (la clave AVO de la app se conserva).
**Validación:** IMPLEMENTADO · CI · **NO VERIFICADO** en el móvil.
**Pendiente:** descarga Wi-Fi real con el pecho 3.7.7; un segundo y tercer móvil conectando y el primero sin perder el enlace.

## 2026-11-03 — Android 2.7-borrado-reloj-dev1 — borrar entrenamientos del reloj con contraseña «AVO»
**Autor:** Claude · **Rama:** `feature/avo-ntrip-auto` (sobre 2.6-ntrip-auto-dev3) · **Commit:** `a64fc96` · **CI:** [41608193129](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41608193129) (**éxito** a la primera: core 149 pruebas, emulador 2, licencias F5EEE5D2, firma estable; artefacto `AVO-Performance-Horse-V2_7_BORRADO_RELOJ_DEV1-APK`)
**Situación anterior:** «Borrar del reloj» solo se activaba con entrenamientos verificados por el servidor, que no está configurado, así que nunca se podía usar. Además la app no enviaba `force`, y el reloj rechaza sin él lo que no está marcado como subido (`storage.cpp`, DELETE_COMMIT).
**Qué cambia:**
- `core/sync/WatchDelete.kt`:
  - contraseña exacta «AVO» (ignora espacios alrededor; en minúsculas no vale);
  - seguridad: copia en el móvil verificada con el SHA-256 del reloj, o «se perderá para siempre»;
  - nunca grabando ni dos veces;
  - lista de los que se pueden liberar sin perder nada;
  - 4 pruebas.
- `AvoClient.deleteSession(force)`: `force` = 1 solo después de la contraseña. El reloj sigue negándose a borrar la sesión que se graba (STATE_CONFLICT).
- `WatchSyncManager.deleteFromWatchProtected`:
  - comprueba contraseña, licencia, que no se esté grabando ni descargando ese entrenamiento, y la conexión;
  - con copia verificada, la conserva y la marca `BORRADO_RELOJ`;
  - sin copia, quita también los restos del móvil y la fila de la lista.
- `freeWatch`: borra todos los ya guardados.
- Interfaz:
  - diálogo común con la contraseña (teclado en mayúsculas, aviso en rojo si se pierde el entrenamiento);
  - «Borrar del reloj» en cada entrenamiento de la lista y en el análisis;
  - tarjeta «Liberar espacio en el reloj» en Ajustes → Descarga del reloj.
- Corrección: al refrescar la lista del reloj, los entrenamientos que ya no están en él conservan su `watchState`. Antes pasaban a «UNKNOWN», y se perdían las marcas «IMPORTADO» y «BORRADO_RELOJ».
**Nota:** la contraseña evita borrados por error; está en el código público, no es una clave de seguridad.
**Validación:** IMPLEMENTADO · COMPILADO / CI 41608193129 · reglas 4/4 pruebas JVM · **NO VERIFICADO** con el reloj.

## 2026-11-02 — Android 2.6-ntrip-auto-dev3 — estado de los mensajes de calidad y contadores de la espalda 3.13.12
**Autor:** Claude · **Rama:** `feature/avo-ntrip-auto` (sobre dev2 `72222af`) · **Commit:** `ff3f2ce` · **CI:** [41534048266](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41534048266) (**éxito**: core 145 pruebas, emulador 2; artefacto `AVO-Performance-Horse-V2_6_NTRIP_AUTO_DEV3-APK`, caduca 02/12/2026)
**Prueba de la dev2 (02/11/2026, 22:54–22:57):**
- «Edad de la corrección: hace 0,4 s»: funciona con el contador RTCM.
- NTRIP: 1 reconexión, 4 GGA, 0 errores. DGNSS con 42,6 cm.
- «Calidad GNSS» se quedó fija en «Esperando el resumen de señales del receptor». La causa está en la espalda: ver BACK 3.13.12 en la rama `fix/back-3-13-12-nav-sig-watchdog`.

**Qué cambia:**
- `TelemetryV3.monitorState`, `monitorRearms` y `receiverResets` leen el byte `quality_mon`: estado en los bits 0–3, peticiones repetidas en los bits 4–5 y redetecciones del receptor en los bits 6–7.
  - Una espalda anterior envía 0 en los bits altos.
  - El pecho 3.7.6 no cambia.
- Tarjeta «Calidad GNSS»:
  - con el resumen caducado, el estado 0 se muestra como «pidiéndolos al receptor»;
  - el estado 1 se muestra como «activados, pero no llegan (último hace N s)»;
  - el estado 5 se muestra como «solo NAV-SIG»; antes no se mostraba ninguno de los tres;
  - filas nuevas «Resumen de señales pedido de nuevo» y «Reinicios del receptor», con «3 o más».
- `QualityMonBitsTest`: 2 pruebas nuevas. El vector del firmware comprueba también los campos nuevos.
- Versión 2.6-ntrip-auto-dev3 (vc 39).

**Validación:** IMPLEMENTADO · COMPILADO / CI 41534048266 · **NO VERIFICADO** en el móvil.

## 2026-11-02 — Android 2.6-ntrip-auto-dev2 — arreglos de la prueba GNSS/NTRIP del balcón
**Autor:** Claude · **Rama:** `feature/avo-ntrip-auto` (sobre 2.6-ntrip-auto-dev1 `e6ff84d`) · **Commit:** `fb985d8` · **CI:** [41520440227](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41520440227) (**éxito** a la primera: core 143 pruebas, 3 nuevas; emulador 2; artefacto `AVO-Performance-Horse-V2_6_NTRIP_AUTO_DEV2-APK`, caduca 02/12/2026)
**Prueba que lo motiva (02/11/2026, 21:23–21:30, balcón de casa, de noche):** pecho 3.7.6 GNSS QUALITY + espalda 3.13.11 + app 2.6-ntrip-auto-dev1, caster IMAX3.
- La tarjeta «Calidad GNSS» ya muestra datos (22–25/32–33 satélites, C/N₀ media 35–36 dBHz, 16–22 señales < 30 dBHz, L2 5/10–11, **0 con fase de portadora**, 6–7 con correcciones). Sin FLOAT ni FIX: cielo tapado y reflejos.
- Cadena RTCM correcta de punta a punta: 1,1 MB del caster, 4525–4575 tramas válidas y 0 con CRC erróneo, 0 B descartados, 1,1 MB reenviado a la espalda, **4139 mensajes usados por el receptor**. Tipos 1006, 1008, 1013, 1029, 1032, 1033, 1075, 1085, 1095, 1125 y 1230 (MSM5, 1 Hz).
- Esto cierra para la 3.7.6 el punto «RTK con NTRIP (RTCM usado > 0)».

**Qué cambia:**
1. **NTRIP, reconexiones (`core/ntrip/Ntrip.kt`).** La espera entre intentos volvía a 1 s después de cada sesión aceptada, aunque el caster cerrara al momento. Con la app abierta sin chaleco, el caster de red cerraba la conexión por falta de GGA y se acumularon **966 reconexiones**. Eso arriesga un bloqueo de la cuenta.
   - Ahora la espera solo vuelve a 1 s si la sesión duró al menos `stableSessionMs` (30 s). Si no, sigue creciendo 1, 2, 4… hasta 60 s.
   - El último error lo explica: «sin posición GNSS para enviar GGA».
   - Prueba `shortSessionsKeepBackoffGrowing`.
2. **«Edad de la corrección» (Inicio).** El receptor deja NAV-PVT `lastCorrectionAge` = 0 («no disponible») aunque usa las correcciones, y la app mostraba «—».
   - Si falta ese dato, la edad se mide con el contador «RTCM usado por el receptor» de la espalda (`core/telemetry/RtcmUseTracker.kt`), con resolución de unos 0,5 s.
   - Se muestra en amarillo por encima de 10 s.
   - 2 pruebas en `RtcmUseTrackerTest`.
3. **Aviso de «Calidad GNSS».** Con 0 señales con fase y más de un tercio de señales débiles (o C/N₀ media ≤ 37), ya no dice «RTK aún convergiendo». Ahora dice «Correcciones recibidas, pero la señal es débil o reflejada: sin fase de portadora no hay RTK (cielo tapado, paredes o tejados cerca)».
4. Versión 2.6-ntrip-auto-dev2 (vc 38).

**No se ha tocado:** firmware del pecho ni de la espalda, BLE, formato de telemetría, selector de mountpoint.
**Validación:** IMPLEMENTADO · COMPILADO / CI 41520440227 · **NO VERIFICADO** en el móvil.
**Pendiente:** prueba al aire libre (FLOAT/FIX) con 2.6-ntrip-auto-dev2.

## 2026-11-01 — Android 2.6-ntrip-auto-dev1 — mountpoint NTRIP automático según la posición
**Autor:** Claude · **Rama:** `feature/avo-ntrip-auto` (desde `feature/avo-license-nfc` 43f2fc0, app 2.5) · **Commit:** `2b1d36f` · **CI:** [41292158228](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41292158228) (**éxito** a la primera: core 140 pruebas, emulador 2, licencias F5EEE5D2, firma estable; artefacto `AVO-Performance-Horse-V2_6_NTRIP_AUTO_DEV1-APK`)
**Qué cambia:**
- Núcleo:
  - `core/ntrip/MountSelector.kt`: `SourceEntry`, que lee todas las columnas de las líneas STR de la sourcetable (posición, formato, frecuencias, red/VRS, NMEA).
  - `MountSelector.choose`: elige solo RTCM 3; la base más cercana de doble frecuencia dentro de `autoMaxKm` (20 km por defecto); más lejos, la red/VRS del caster; sin red, la base más cercana aunque esté lejos (nunca una de solo L1 si hay otra); histéresis de 5 km y 20 % para no saltar entre bases parecidas; tres bases de reserva y la red al final.
  - `NtripClient.fetchSourcetableText/Entries`.
  - 8 pruebas con una sourcetable inventada.
- App:
  - opción «Elegir mountpoint automáticamente según la posición GPS» y distancia máxima en Ajustes → NTRIP;
  - tarjeta «Selección automática» (en uso, motivo, reservas, los 8 más cercanos con distancia y frecuencias, botón para actualizar la lista).
- Gestor:
  - la sourcetable se guarda en caché 24 h (y se usa sin red);
  - posición de la espalda o, sin FIX, la última guardada; sin ninguna, la red/VRS o el mountpoint manual de respaldo;
  - revisa cada minuto y al primer FIX;
  - **cambia de base solo cuando no se está grabando** (se apunta y se cambia al terminar);
  - tras un fallo de la base principal se queda 10 min en la reserva;
  - el failover existente se mantiene.
- CI: la rama nueva compila la APK.
**Por qué:** petición del usuario: activar el servidor NTRIP mejor para la zona según la posición del GPS.
**Alcance:** un solo caster, el configurado; elige entre sus mountpoints. Varios casters con cuentas distintas quedan para otra versión.
**Validación:** IMPLEMENTADO · COMPILADO / CI 41292158228 · selector 8/8 pruebas JVM · **NO VERIFICADO** con un caster real ni en el móvil.

## 2026-10-27 — AVO Tarjetas 1.3-registro-dev1 — registro de usuarios, activar sin tarjeta y copia completa
**Autor:** Claude · **Rama:** `feature/avo-license-nfc` · **Commit:** `438a887` · **CI:** [40471096243](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40471096243) (**éxito** a la primera: core 132 pruebas, emulador 2; licencias activadas con F5EEE5D2; app y Tarjetas con el mismo certificado estable SHA-256 8807ef9cec7f4eb2…)
**Qué cambia:**
- Núcleo: `IssuerRegistry` (usuarios, licencias, contactos e historial; formato de texto con campos base64; fusión de copias), `IssuerBackup` (clave + registro en un archivo con contraseña), `PasswordBox`. 6 pruebas nuevas (34 en total de licencias).
- AVO Tarjetas:
  - registro cifrado con el Keystore (migra y borra la lista anterior, que guardaba las claves de las tarjetas en claro);
  - búsqueda;
  - ficha de usuario con historial, edición de datos, «Activar por archivo (sin tarjeta)» por WhatsApp (a su número), email (a su dirección) u otra app, renovar en tarjeta, copia, baja y reactivación;
  - «Añadir al registro» para tarjetas leídas que no estaban;
  - copia completa (clave + registro) y restauración, compatible con la copia de solo la clave;
  - aviso de copia pendiente.
- CI: `apksigner` comprueba que la app y AVO Tarjetas llevan el mismo certificado estable (falla si no), para que se actualicen sin desinstalar.
**Por qué:** peticiones del usuario: actualizar AVO Tarjetas sin borrarla y tener una base de datos para activar licencias y crear archivos sin leer la tarjeta.
**Validación:** IMPLEMENTADO · COMPILADO / CI 40471096243 · 34/34 pruebas JVM del núcleo de licencias · **NO VERIFICADO** en el teléfono.

## 2026-10-27 — Claves públicas de licencias desde `config/license_public_keys.txt`
**Autor:** Claude · **Rama:** `feature/avo-license-nfc`
**Qué cambia:** si no existe la variable de Actions `AVO_LICENSE_PUBLIC_KEYS`, la compilación lee las claves públicas de `config/license_public_keys.txt`, una por línea y con `#` para comentarios. El aviso de CI muestra el identificador de cada clave (los 4 primeros bytes del SHA-256 del SPKI, el mismo que muestra AVO Tarjetas). Se añade la clave pública **F5EEE5D2** (P-256, generada por el usuario en AVO Tarjetas el 27/10/2026; comprobada con openssl: SPKI de 91 B, curva prime256v1, identificador igual al de su copia cifrada). **Desde esta compilación la app exige licencia.**
**Por qué:** desde esta sesión no se pueden crear variables de Actions, y el usuario pide que la clave la meta el asistente.
**Validación:** CI [40469807184](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40469807184): «Licencias ACTIVADAS: 1 clave (id: F5EEE5D2)».

## 2026-10-27 — Android 2.5-roles-dev1 + AVO Tarjetas 1.2-roles-dev1 — roles en la licencia
**Autor:** Claude · **Rama:** `feature/avo-license-nfc` · **Commits:** `d506983`, `42d4f0f` · **CI:** Android [40468818227](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40468818227) (**éxito**: core 126 pruebas, emulador 2, artefacto `AVO-Performance-Horse-V2_5_ROLES_DEV1-APK`; la 40468164700 falló por `LicenseAsk` dentro de `Mode` en Tarjetas, corregido en `42d4f0f`) · reglas Firebase [40468164673](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40468164673) (**éxito**, 11 pruebas)
**Qué cambia:**
- Licencia v2 (108 B): byte de roles firmado (jinete, entrenador, desarrollador, propietario, veterinario). La v1 se sigue leyendo como todos los roles. Tabla única rol → funciones en `core/.../license/LicenseRoles.kt`.
- App: las pantallas y los servicios se habilitan por función (chaleco y grabación, elegir jinete, mareas, enviar y recibir, ajustes, diagnósticos). Inicio en modo consulta para roles sin chaleco (propietario, veterinario). Pantalla Licencia con roles y funciones.
- Jinete: el titular queda como jinete (fijo si no es también entrenador o desarrollador). Se escribe en el chaleco al conectar (`WatchConfigOps.setRider`, nunca grabando) y se pone en los entrenamientos descargados sin jinete (no en los importados).
- Envío entre apps: la licencia se publica en el perfil (`users/<código>/lic`) y la app receptora verifica la firma y muestra «Nombre · roles» en invitaciones, destinatarios, buscador, enviados y recibidos. Reglas de Firebase ampliadas (campo `lic`, base64 ≤ 200) y pruebas del emulador.
- AVO Tarjetas: casillas de roles al crear, renovar y enviar por archivo, con las funciones que activa cada combinación; los roles se muestran en la lectura y en las tarjetas emitidas.
**Supuesto:** «desaroyador» se ha interpretado como **Desarrollador** (todas las funciones y diagnósticos). Pendiente de confirmar.
**Validación:** IMPLEMENTADO · COMPILADO / CI 40468818227 · núcleo 28/28 pruebas JVM · **NO VERIFICADO** en teléfono. **Hay que publicar las reglas nuevas de Firebase.**

## 2026-10-27 — Android 2.4-license-dev1 + AVO Tarjetas 1.1-license-dev1 — licencia de la app por tarjeta NFC o archivo
**Autor:** Claude · **Rama:** `feature/avo-license-nfc` (desde `feature/avo-wifi-sync` 2ab1ff4) · **Commit:** `1fbf2e3` · **CI:** [40433800797](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/40433800797) (**éxito**: core 123 pruebas, emulador 2, artefacto `AVO-Performance-Horse-V2_4_LICENSE_DEV1-APK`; compilada **sin** `AVO_LICENSE_PUBLIC_KEYS` → sin control de licencias)
**Qué cambia:**
- **Núcleo** (`core/.../license/`): licencia binaria firmada ECDSA P-256 ligada al UID del chip, registro NDEF externo `avoperformance.org:lic`, reloj anti-retroceso (hora de red, última hora conocida, contador desde el arranque), estados y reglas de activación/renovación sin rebaja, archivo de licencia `.avolic` cifrado con el secreto de la tarjeta del usuario, copia de la clave con contraseña (PBKDF2 + AES-GCM).
- **AVO Tarjetas 1.1** (vc 2): generar / exportar / importar la clave de firma (guardada con SecureStore del Keystore), opción «Licencia de la app» con fecha al crear, «Renovar», «Por archivo» (compartir por WhatsApp/email), lectura que comprueba firma, UID y caducidad. Las tarjetas con licencia no se bloquean.
- **App 2.4-license-dev1** (vc 35): activación al acercar la tarjeta de usuario o al abrir el archivo; pantalla Licencia (también en Ajustes → Sistema); aviso en Inicio 7 días antes; **modo consulta** al caducar o sin licencia (entrenamientos, análisis, comparativas y cuadra visibles; chaleco, grabación, descargas, NTRIP, mareas, compartir, ajustes y NFC de caballo/jinete bloqueados; servicio en segundo plano detenido).
- Claves públicas desde la variable de Actions `AVO_LICENSE_PUBLIC_KEYS` (BuildConfig). **Sin la variable la APK no controla licencias** (aviso en CI y en la app).
- CI: nombre del APK y del artefacto con la versión real (antes fijo «V2-1-motor»).
**Por qué:** petición del usuario: activación de la app hasta una fecha por la tarjeta NFC, sin que se pueda copiar ni cambiar la fecha, y activación remota por archivo.
**Corrección a lo dicho en el chat:** la hora del reloj de pecho la fija el móvil (`TIME_SET`), así que no sirve como referencia independiente; se usa hora de red de Android y contador monotónico.
**No se ha tocado:** firmware, protocolo BLE/ESP-NOW/Wi-Fi, formato RAW, base de datos.
**Validación:** IMPLEMENTADO · COMPILADO / CI 40433800797 · núcleo 25/25 pruebas JVM · **NO VERIFICADO** en teléfono ni con tarjetas. Limitaciones: tarjetas «mágicas» con UID modificable pueden clonar una NTAG21x; el repositorio público permite recompilar sin licencias.
**Pendiente:** lista de `docs/LICENCIAS_AVO.md` (apartado «Pendiente de verificar en teléfono»).
## 2026-11-01 — Espalda · Rev E.7.4: alojamiento del conector de muelles pasante (sin membrana)
**Autor:** Claude · Rama `feature/avo-back-rev-e7-iman` · **Commits:** el de esta entrada · **CI:** no aplica (CAD)
**Qué cambia:**
- **Petición del usuario:** el soporte tiene que tener un agujero pasante para el pogo. Estaba mirando el STL de la E.7.2 (4,5 mm).
- **Soporte y base de carga:** se quita la membrana de sacrificio de 0,2 → el alojamiento es pasante de arriba abajo.
- **Ficheros:** STL y STEP renombrados con la versión (`AVO_RevE7_4_*`) para no confundirlos con los anteriores.

**Validación:** IMPLEMENTADO (CAD):
- conector STEP / soporte: 0 mm³;
- STL cerrados de 1 cuerpo.
- Voladizos: el techo de las orejas es un puente de 5,8 mm con un lado abierto hacia el agujero (el analizador lo marca como
  voladizo de 2,7). Se imprime como puente en PETG. El resto, 0 fuera de límite.

**NO VERIFICADO** físicamente.

## 2026-10-31 — Espalda · Rev E.7.3: conector de muelles completamente empotrado (soporte de 8,8 mm)
**Autor:** Claude · Rama `feature/avo-back-rev-e7-iman` · **Commits:** el de esta entrada · **CI:** no aplica (CAD)
**Qué cambia:** el usuario (captura de Shapr3D) pide que el conector de muelles no asome por debajo del soporte, sino que quede
completamente empotrado.
- **Soporte y base de carga:** pasan de 4,5 a **8,8 mm** (`MT_E73`). El conector queda dentro: cuerpo hasta −6,2, patas hasta
  −7,74 y 1,06 libre para el puente. La cara superior y el cierre a la cápsula no cambian.
- **La espalda queda 4,3 mm más separada del caballo.**
- **Contraplaca:** vuelve a la original, sin hueco, construida igual y bajada con el soporte. **La tela no se corta.**
- **Probetas:** las del soporte llegan ahora hasta la cara inferior.

**Validación:** IMPLEMENTADO (CAD, con el STEP colocado):
- 0 interferencias, salvo la membrana prevista;
- 0 voladizos fuera de límite en 6 piezas;
- STL cerrados de 1 cuerpo.

**NO VERIFICADO** físicamente.

## 2026-10-31 — Espalda · Rev E.7.2: conectores con las cotas del STEP del usuario
**Autor:** Claude · Rama `feature/avo-back-rev-e7-iman` · **Commits:** el de esta entrada · **CI:** no aplica (CAD)
**Qué cambia:** el usuario envió el STEP de los conectores (`Assembly Pogo 3er`, Onshape) y una captura de Shapr3D con la
orientación: el plano en la cápsula con los contactos hacia abajo y el de muelles en el soporte con las puntas hacia arriba.

**Cotas del STEP:**
- **plano:** cara 15,5 × 4,65 × 1,7, reborde 17,1 × 6,25 × 1,8, patas 1,0;
- **muelles:** cuerpo 15,5 × 4,65 × **6,0**, orejas 25 × 5,5 × 2,0 en medio del grueso, agujeros Ø2,0 a 19,5, puntas y patas
  de 1,5;
- contactos a 2,3; imanes Ø3 a ±5,42.

**Base:** el conector plano se mete desde dentro. La cara pasa por un agujero de 15,7 × 4,85 y queda a ras; el reborde apoya en
un escalón a Z 1,7.

**Soporte:** el conector de muelles va desde abajo, atornillado con 2 × M2 de rosca chapa (pilotos Ø1,6):
- ventana del cuerpo hasta la cara de apoyo, con la cara 0,2 por debajo;
- orejas con techo a Z −2,7;
- membrana de sacrificio de 0,2 que hay que cortar.

**Contraplaca (nueva):** hueco de 26 × 7 × 2,1 para lo que asoma bajo el soporte (cuerpo, cabezas M2, patas y puente). En la
tela hace falta una ranura de 26 × 7.

**Base de carga:** 9 mm de grueso (`MT_CARGA`).

**Validación:** IMPLEMENTADO (CAD, con el STEP colocado):
- plano / base: 0 mm³;
- muelles / soporte: solo la membrana (13,5 mm³, prevista);
- muelles y cabezas M2 / contraplaca: 0 mm³;
- puntas a Z +1,3;
- 0 voladizos fuera de límite en las 7 piezas;
- STL cerrados de 1 cuerpo.

**NO VERIFICADO** físicamente.
**Pendiente:**
- confirmar que el conector real es como el STEP: 6,0 de grueso, orejas en medio y agujeros Ø2,0 (el usuario midió Ø2,5);
- imprimir las probetas;
- probar el rebote al galope.

## 2026-10-31 — Espalda · Rev E.7.1: conector de muelles montado desde arriba (corrige la E.7)
**Autor:** Claude · Rama `feature/avo-back-rev-e7-iman` · **Commits:** el de esta entrada · **CI:** no aplica (CAD)
**Qué cambia:**
- **Error de la E.7:** supuse que las orejas del conector de muelles iban a ras de la cara trasera y diseñé el soporte para
  meterlo desde abajo. La foto de perfil muestra que las orejas están a ras de la cara de los **muelles y los imanes**. Con la
  E.7, la cara habría quedado 1,4 mm hundida y los muelles apenas habrían asomado.
- **Soporte y base de carga E.7.1:** conector **desde arriba**, con los muelles hacia arriba:
  - rebaje de las orejas en la cara de apoyo, óvalo de 25,0 × 5,8 y 1,9 de hondo;
  - hueco del cuerpo de 14,9 × 5,8, pasante hasta la cara inferior;
  - taladros ciegos de Ø2,0 bajo los agujeros de las orejas, para que el epoxi haga de remache;
  - cara de los muelles 0,2 bajo la cara de apoyo;
  - sin membrana.
- **Base:** sin cambios. El conector plano va a ras del fondo, con los contactos hacia abajo.

**Validación:** IMPLEMENTADO (CAD):
- sólidos válidos;
- STL cerrados de 1 cuerpo;
- 0 voladizos fuera de límite;
- 0 interferencias entre los conectores y sus piezas.

**NO VERIFICADO** físicamente.
**Pendiente:** el mismo que en la E.7.

## 2026-10-31 — Espalda · prototipo Rev E.7: conectores magnéticos de 3 vías en lugar del reed
**Autor:** Claude · Rama `feature/avo-back-rev-e7-iman` (sale de `feature/avo-back-v4`) · **Commits:** el de esta entrada · **CI:** no aplica (CAD)
**Qué cambia:**
- **Base E.7:** se quitan los 3 contactos de tornillo M2 de la E.6 y el alojamiento del reed. Ahora lleva el conector
  magnético PLANO, ovalado:
  - alojamiento de 15,3 × 6,5 en (X 9, Y 0), desde el fondo hasta Z 4,0, con escalón a 45° y paso al interior;
  - cara enrasada con el fondo y pegada con epoxi.
- **Soporte del chaleco E.7 / base de carga E.7:** en lugar de los 2 pines sueltos, el conector de MUELLES con orejas:
  - ventana del cuerpo de 14,9 × 5,8;
  - orejas de 25,0 × 5,8 desde abajo hasta Z −1,4, con membrana de sacrificio de 0,2 que hay que cortar;
  - cara del cuerpo 0,2 bajo la cara de apoyo;
  - la base de carga lleva un canal para el cable.
- **Orden de los contactos:** BAT (Y−) · SYS · GND (Y+). El soporte une BAT y SYS; la base de carga lleva BAT y GND.
- **Probetas P3** del cuello para la base, el soporte y la base de carga.

**Por qué:** el usuario ha comprado conectores magnéticos comerciales (fotos con calibre del 31/10/2026). Los planos van en la
caja y los de muelles en el soporte.
**Medidas:**
- **Del usuario:** puntas 1,5, agujeros de las orejas Ø2,5 a 19,5 entre centros, imanes a ras.
- **Por foto (±0,3):** conector plano 15,0 × 6,2 (otra foto dio 16,5: pendiente de confirmar); cuerpo de muelles 14,6 × 5,5 × 2,9;
  largo total 24,7; orejas 1,7.

**Archivos:** `hardware/back/V4/PROTOTIPO_IMAN_REV_E7/` (STL, STEP, fuente, VALIDACION, IMAGENES, LEEME).
**No se ha tocado:** tapa E.5, cuna de la Heltec E.6, junta, contraplaca, firmware (la 3.13.11 ya va sin reed) y `main`.
**Validación:** IMPLEMENTADO (CAD):
- sólidos válidos;
- STL cerrados de 1 cuerpo;
- 0 voladizos fuera de límite;
- el conector plano no interfiere con la base;
- en el soporte, la única interferencia es la membrana de sacrificio (16 mm³, prevista).

**NO VERIFICADO** físicamente.
**Pendiente:**
- imprimir las probetas;
- confirmar el largo del conector plano y los gruesos;
- probar el rebote del contacto al galope.

## 2026-10-30 — Espalda · prototipo Rev E.6: cuna sin canal −Y y con 4 pinzas sobre el refuerzo
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** el de esta entrada · **CI:** no aplica (CAD)
**Qué cambia** (render anotado del usuario):
- Quitado el canal del borde −Y y sus labios.
- 4 pinzas iguales a la del cuello (Y −7,5) sobre el refuerzo, en las posiciones 1–4 marcadas: extremo de la antena (Y 11 y
  Y −2), entre el Pololu y la Heltec (X 38) y borde −Y junto al cuello (X 14,5).
- Alojamiento del Pololu: **1,2 mm de profundidad** (medido con calibre por el usuario; antes 2,54 mm, el 0,1″ de la ficha
  de Pololu). Heltec: la foto del calibre da 1,7–1,9 mm, compatible con el 1,8 del modelo (sin cambio). Rebajado en el refuerzo y enrasado con él; sin marco por encima.
**No se ha tocado:** base, soportes, tapa E.5, versión V4 con PCB.
**Validación:** 1 sólido válido, STL estancos, 0 voladizos fuera de límite, 0 interferencias con tapa E.5, Heltec, ZED, Pololu
y batería. **NO VERIFICADO** físicamente.
**Pendiente:** comprobar en la impresión que la Heltec no baila (lectura por foto ±0,1 mm).

## 2026-10-30 — Espalda · prototipo Rev E.6: cuna de la Heltec nueva (Pololu, sujetacables, pestañas) y batería 1 mm más baja
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** el de esta entrada · **CI:** no aplica (CAD)
**Qué cambia** (anotaciones del usuario sobre la cuna en Shapr3D, 30/10/2026):
- **Cuna `AVO_RevE6_CUNA_HELTEC`:**
  - un solo pasacables centrado en lugar de las 2 ranuras del reed;
  - ventana ampliada hacia el conector SH1.25;
  - alojamiento del Pololu S7V8F3 a 1 mm del borde −Y, en el sitio de la placa Qi;
  - 3 sujetacables para 5 × AWG30;
  - Heltec calzada 1 mm, con todas las pestañas 1 mm más altas;
  - labio en las 4 guías laterales y 2 pestañas nuevas en el borde +Y;
  - torres con pestaña también en el extremo USB, entre el USB-C y los pulsadores.
- **Base `AVO_RevE6_BASE_POGO`:** sin bobina Qi; la batería apoya en el suelo (1,4 mm) y baja 1 mm. La bandeja baja con
  ella, así que la Heltec queda a la misma altura que en la E.5 y la **tapa E.5 se conserva**. El refuerzo de la bandeja
  pasa de 1,2 a 2,2 mm para que los pisadores de la tapa sigan apoyando igual.
- **Guía actualizada:** `hardware/back/V4/DOCS/PROTOTIPO_POGO_REV_E.md`.
**Validación:**
- Software: piezas B-Rep válidas (1 sólido), STL estancos.
- Voladizos: 0 fuera de límite.
- Interferencias: 0 con la tapa E.5, la Heltec, el ZED + L, la batería, el Pololu y el canal de cables. Las únicas
  coincidencias con la clavija USB-C son las esquinas redondeadas de la boca (aproximación de la comprobación).
- **NO PROBADO** físicamente.
**Pendiente:** imprimir y comprobar el encaje real de la Heltec (pestañas de 0,5 mm en los bordes) y del Pololu.

## 2026-10-30 — Espalda · AVO BACK V4 REV B (contactos pogo, sin Qi ni Hall) + BACK 4.0.0-dev2 + prototipo Rev E.6 con BACK 3.12.0
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** `89ad681`…`c1e0e26` y siguientes de esta entrada ·
**CI:** PCB run 41048486880 (`c1e0e26`) y 41050496945 (`6e5b54d`, informe con las existencias del TVS: 496 730 uds.): **puerta superada**; firmware V4 4.0.0-dev2 run 41044961345 (`8e38b61`, éxito,
resultado guardado por el CI en `e151fcc`); BACK 3.12.0 run 41044381974 (`2750d3c`): éxito; existencias run 41042078297
**Qué cambia:** petición del usuario: quitar todo el Qi y alimentar la espalda por 3 contactos (sistema pogo).
- **Contactos:** 3 en el fondo de la cápsula, tornillo M2 avellanado inox + junta tórica 2 × 1 + tuerca M2.
  - **SYS y BAT** en la cola, donde estaba el reed. **GND** aparte, a ~30 mm de BAT.
  - **Soporte del chaleco:** 2 pines con muelle unidos por un hilo puentean SYS–BAT → encendido. Fuera del soporte, 0 µA.
  - **Base de carga:** cargador externo entre BAT y GND, con la placa apagada.
- **PCB REV B:**
  - Sin BQ51013B, bobina, Hall ni conmutación AD (−24 piezas; 61 montadas).
  - Celda → F1 → contacto BAT; contacto SYS → Q3 (polaridad) → BAT del BQ24072, que queda solo para el USB-C del taller.
  - TVS PESD5V0S1BA (C2827694) en SYS y BAT.
  - KiCad 9 en el CI: DRC 0, 0 conexiones incompletas, 0 cortocircuitos, paridad 0, ERC 0/0.
  - La REV A con Qi queda congelada en `hardware/back/V4/PCB_REV_A_QI/`.
- **Carcasa V4:**
  - Sin alojamiento de la bobina. Avellanados, pasos y ranuras de junta de los 3 contactos en la base; 2 agujeros de pin
    y canal del puente en el soporte. Sin imanes del Hall.
  - 0 interferencias con las envolventes y con el STEP de `c1e0e26`; 0 voladizos fuera de límite.
  - Medidas sin cambios: 118,2 × 59,0 × 17,1 mm.
- **BACK 4.0.0-dev2:**
  - Sin Hall ni sueño por soporte.
  - Emparejamiento con 3 encendidos de menos de 4 s seguidos (contador en NVS).
  - microSD vaciada cada 1 s.
  - Línea `ALIMENTACION` en el monitor.
- **Prototipo actual (Rev E + Heltec)** — para probar el sistema antes de fabricar:
  - Base, soporte del chaleco y base de carga **Rev E.6** (`hardware/back/V4/PROTOTIPO_POGO_REV_E6/`): BAT y SYS en
    (8,8; ∓4), GND en (8,8; 14). Válidas, sin voladizos fuera de límite y sin interferencias con la Heltec ni el ZED.
  - **BACK 3.12.0** (Heltec): sin reed, emparejamiento con 3 encendidos rápidos.
  - Guía de adaptación, cableado y pruebas: `hardware/back/V4/DOCS/PROTOTIPO_POGO_REV_E.md`.
**Por qué:** el usuario prefiere contactos pogo a la carga Qi: menos piezas, carga más rápida, encendido y apagado sin
sensor.
**Archivos:**
- `hardware/back/V4/**` (PCB, PCB_REV_A_QI, CAD, PROTOTIPO_POGO_REV_E6, DOCS).
- `firmware/back/V4_0_0/**`, `firmware/back/V3_8_0/**`.
- `.github/workflows/build-back-v4-fw.yml`, `build-back-v380.yml`.
**No se ha tocado:** `main`, `develop/avo-performance-horse`, pecho, cincha, Android.
**Validación:** CAD y PCB comprobados por software; los dos firmwares compilan en el CI. **NO VERIFICADO** físicamente
(nada fabricado, impreso ni montado).
**Pendiente:**
- Probar primero el prototipo E.6: rebote del contacto al galope, estanqueidad de los contactos, carga en la base.
- Medir con polímetro el pinout de la URTK1.2.
- Diseñar la base de carga definitiva de la V4.

## 2026-10-30 — Espalda · AVO BACK V4 (PCB propia ESP32-S3 + URTK1.2, carcasa 48 mm más corta) + firmware 4.0.0-dev1
**Autor:** Claude · Rama `feature/avo-back-v4` (desde `feature/avo-girth-pcb`) · **Commits:** `9573ef3`…`3f81b45` ·
**CI:** PCB `build-back-v4-pcb.yml` run 40971520610 (`3f81b45`): **puerta superada**; firmware `build-back-v4-fw.yml`
run 40920249110 (`4059f5f`): compilación correcta; existencias `jlc-stock-back-v4.yml`
**Qué cambia:** rediseño conjunto de electrónica y carcasa de la espalda (`hardware/back/V4/`).
- **Carcasa** (FreeCAD 1.0.2, paramétrica, desde la Rev E.4.1/E.5): longitud **166,2 → 118,2 mm (−48,0 mm, −28,9 %)**,
  mismo grosor (17,1 mm) y misma anchura (59 mm); volumen exterior 157,8 → 110,1 cm³; impresas ≈ 208 → 131 g. La URTK1.2
  va sobre la batería a la misma cota que la Heltec (Z 9,6) y la PCB nueva en la cola (Z 2,5) con la bobina Qi debajo;
  8 tornillos M3; Hall soldado en la PCB en lugar del reed. STL sin soportes, STEP por pieza, conjunto montado y
  explosionado, plano de cotas, comparativa con la Rev E.5, estudio de distribuciones A–D.
- **PCB REV A** (KiCad 9, 4 capas, ≈ 1785 mm², 85 piezas montadas, 35 referencias LCSC): ESP32-S3-MINI-1U-N8 (un solo
  ESP32; comparación con S3 + C3/C6 documentada), BQ51013B (Qi) + BQ24072, TLV75733P, **RT9080 propio del ZED con EN**,
  microSD SDMMC 4 bits con alimentación conmutada, Hall DRV5032FA, USB-C, 8 pads para el mazo de la URTK1.2 (UART1,
  UART2, PPS, RESET). Ruteado: Freerouting 1.9.0 + `fuente/repair.py`. KiCad 9 en el CI: DRC 0 errores, 0 conexiones
  incompletas, 0 cortocircuitos, paridad 0; ERC 0/0. Ficheros `PCB/out/FINAL/` (Gerber, BOM y CPL de JLCPCB, STEP).
- **Firmware 4.0.0-dev1** (`firmware/back/V4_0_0`): port de BACK 3.11.0 a la placa V4 (ZED por UART2 en GPIO7/8, EN del
  ZED en GPIO10, Hall en GPIO1 con despertar ext0, emparejamiento con 3 apoyos en el soporte, registro UBX en microSD,
  PPS por interrupción, PGOOD del cargador); 44 pruebas en el ordenador.
**Por qué:** petición del usuario (brief «AVO BACK V4 — rediseño electrónico y mecánico integrado»): acortar la carcasa
sin aumentar el grosor, una sola placa propia con el ZED integrado físicamente y corte físico del ZED.
**Archivos:** `hardware/back/V4/**`, `firmware/back/V4_0_0/**`, `.github/workflows/build-back-v4-pcb.yml`,
`build-back-v4-fw.yml`, `jlc-stock-back-v4.yml`, `docs/REGISTRO_DE_CAMBIOS.md`.
**No se ha tocado:** `main`, `develop/avo-performance-horse`, Rev E de la espalda, firmware 3.x, pecho, cincha, Android.
**Validación:** CAD comprobado por software (piezas B-Rep válidas, 0 interferencias con las envolventes de la electrónica y
con el STEP de KiCad de `3f81b45` (holguras mín.: tapa 0,19, anillos 0,09, bobina 0,20 mm; la placa apoya en la base);
STL/STEP releídos; 0 voladizos fuera de límite) · PCB: CI con puerta superada · firmware: CI compila.
**NO VERIFICADO** físicamente (nada impreso, fabricado ni montado).
**Pendiente:** comprobar con polímetro el pinout de la URTK1.2 (las fotos muestran serigrafías distintas) antes del mazo;
imprimir las probetas P1/P2; medir la bobina Qi y ajustar C1–C4; BLE directo con Android, Wi-Fi y OTA firmada en el
firmware V4; revisar giros en la vista previa de JLCPCB; pruebas de consumo, GNSS (C/N0), alcance y estanqueidad.

## 2026-10-29 — Cincha · auditoría de validación virtual de la PCB REV B y propuesta REV B.1
**Autor:** Claude · Rama `audit/avo-girth-pcb-revb` (derivada de `feature/avo-girth-pcb` en `2a70369`) · **Commits:**
`82b9609`…`b582bed` y el de esta entrada · **CI:** `audit-girth-revb.yml`, runs 40938084601 … 40955158865 (éxito; las
evidencias se guardan en `hardware/girth/PCB/AUDITORIA_REV_B/resultados_ci/`)
**Qué cambia:** informe `hardware/girth/PCB/AUDITORIA_REV_B/INFORME_VALIDACION_REV_B.md` con veredicto **APTO PARA
PROTOTIPOS CON RIESGOS IDENTIFICADOS**. Fases ejecutadas: KiCad 9 (ERC, DRC con paridad, DRC tras rellenar zonas,
auditoría de redes, Gerber regenerados = entregados), ngspice (alimentación, enclavamiento Q10/Q11, Monte Carlo de 200),
Qi (`qi/`), mecánica frente al STL (`mecanica/`), GPIO, sensores con simulador de marcha, pruebas de ESP-NOW con la
`avo_core` real, autonomía, fabricación JLCPCB (existencias, BOM/CPL, giros, presupuesto 5 PCB / 2 montadas) y QEMU.
**REV B.1 propuesta** (`AUDITORIA_REV_B/corregida/`, generada desde la placa entregada sin tocarla): BQ24072 en USB500
(EN1 = VSYS, EN2 = GND, R8 DNP), C41 220 n → 470 n (C47339), R40 1 M → 100 k, cajetín «B.1». Firmware (rama de
auditoría): corregido `out_since = now | 1` (apagado instantáneo ≈ 50 %), `girth_pack.h`/`girth_policy.h`,
`gpio_hold_en` en PWR_HOLD, línea de arranque temprana. Documentación: fórmula de C2 en `DOCS/AJUSTE_QI.md`, autonomía
(≈ 5 h, no 11–20 h) y consumo apagado en el README, «W.FL / MHF III» en `fuente/gate.py`.
**Por qué:** misión de validación virtual exhaustiva antes de fabricar 5 PCB y montar 2.
**Archivos:** `hardware/girth/PCB/AUDITORIA_REV_B/**`, `.github/workflows/audit-girth-revb.yml`,
`firmware/girth/V0_3_0_C3/**`, `hardware/girth/PCB/README.md`, `DOCS/AJUSTE_QI.md`, `fuente/gate.py` (solo texto).
**No se ha tocado:** `main`, `develop/avo-performance-horse`, `feature/avo-girth-pcb`, los ficheros entregados de
`hardware/girth/PCB/out/C3/`, el firmware de la espalda. **No se ha hecho ningún pedido.**
**Validación:** CI (KiCad: REV B y REV B.1 con ERC 0 / DRC 0 / paridad 0; firmware compila, 19 + 37 pruebas en el PC sin
fallos; SPICE con modelos de nivel 1 y de comportamiento). QEMU: el boceto de control arranca; la cincha se queda en la
calibración del ADC2 de ESP-IDF (QEMU no emula el ADC del C3). **NO VERIFICADO** físicamente.
**Pendiente:** pruebas físicas de la sección 14 del informe; bobina Qi (TDK WR202010-18M8-ID); NTC en la celda; CAD de
la cápsula REV 5.9; duplicados/desorden en `GirthHub`; ±16 g; pasar los cambios de cobre de la B.1 a `fuente/` si se
adopta.
## 2026-10-29 — Cincha · PCB REV B → paquete ODB++ para AISLER (5 PCB / 2 montadas)
**Autor:** Claude · Rama `export/avo-girth-aisler` (derivada de `feature/avo-girth-pcb` en `2a70369`) · **Commits:**
`981f17f`…`779eefa` y el de esta entrada · **CI:** `export-girth-aisler.yml`, run 40960122600 (éxito)
**Qué cambia:** `hardware/girth/PCB/AISLER/`: copia del proyecto KiCad REV B con TP1–TP8, L1/L2 y SW1/SW2 marcados
DNP, cajetín «B» y MPN/fabricante reales en las 85 piezas montadas (solo campos de texto). ODB++ exportado con KiCad
9.0.9 (`AVO_GIRTH_PCB_REV_B_AISLER_ODB.zip`, SHA-256 `d3c662b2…ed03`), validado leyendo el ZIP (98 componentes, 85 para
montar, 13 `.no_pop` incluido C5, posiciones y giros idénticos a la placa y al CPL) y contrastado con Gerber/Excellon
de la misma placa. Informe: `AISLER/INFORME_AISLER.md`.
**Por qué:** presupuestar en AISLER 5 PCB de 4 capas, 1,0 mm, ENIG, con montaje de 2.
**No se ha tocado:** `feature/avo-girth-pcb`, los ficheros entregados (`out/C3/`), el diseño eléctrico ni las
posiciones (comprobado por el script). **Ningún pedido ni subida.**
**Validación:** CI (ERC 0, DRC 0 con las reglas del diseño; con las reglas de AISLER: 16 violaciones, 8 de las ranuras de
0,6 mm del USB-C J1 y 8 de textos de serigrafía). **NO VERIFICADO** en la web de AISLER.
**Pendiente:** AISLER no ofrece 4 capas de 1,0 mm en su catálogo estándar (0,8/1,6 mm) y fabrica PCB de 3 en 3;
confirmar las ranuras de J1; revisar en su visor los giros y el pin 1.

---

## 2026-10-29 — Cincha · PCB REV B (ESP32-C3) + firmware V0.3.0 — rediseño para montaje completo en JLCPCB y coste ~½
**Autor:** Claude · Rama `feature/avo-girth-pcb` · **Commits:** `c151a4a`…`6b01cb8` (y siguientes de esta entrada) ·
**CI:** existencias JLCPCB (`jlc-stock-girth.yml`), PCB `build-girth-pcb.yml` (puerta superada en `6b01cb8`),
firmware `build-girth-c3.yml` (compilación correcta en `01f8093`)
**Qué cambia:** JLCPCB no tiene el ESP32-C6-MINI-1U-N4 (0 uds.). REV B con **ESP32-C3-MINI-1U-N4** (C2911374,
1191 uds. y 3,15 US$ el 2026-10-29 según la consulta del CI); IMU **LSM6DS3TR-C + MMC5983MA** por I²C en lugar del
BNO085 (19,50 US$, 80 uds.); corte de batería con **enclavamiento de MOSFET** en lugar del relé biestable; R6/R7
Basic. Mismas funciones (ESP-NOW, IMU de 9 ejes, encendido magnético, apagado remoto, < 1 µA apagada, carga USB y
Qi, medida de batería, programación por USB y UART0, antena externa). 85 piezas montadas (antes 104), 14 Extended
(antes 17). Coste de componentes + cargo de Extended: 22,1 US$/placa a 5 uds. (REV A ≥ 39,9) y 16,5 a 10 uds.
(REV A ≥ 32,9): −45 % a −53 %, con la REV A subestimada porque el C6 no tiene precio real. Firmware V0.3.0 para el
C3 con IMU, batería, enclavamiento, apagado remoto (bit 1 de `GirthPing.flags`, la espalda aún no lo envía) y
diagnóstico. La REV A queda congelada en `hardware/girth/PCB_REV_A_C6`.
**Por qué:** placa montable entera por JLCPCB y coste a la mitad sin perder funciones (petición del usuario).
**Archivos:** `hardware/girth/PCB/**`, `hardware/girth/PCB_REV_A_C6/**`, `firmware/girth/V0_3_0_C3/**`,
`firmware/back/V3_8_0/lib/avo_core/src/avo_girth_link.h` (solo constantes y comentarios),
`.github/workflows/build-girth-pcb.yml`, `build-girth-c3.yml`, `jlc-stock-girth.yml`.
**No se ha tocado:** `main`, `develop/avo-performance-horse`, app Android, AVO Update, firmware de pecho y espalda.
**Validación:** CI (KiCad 9: DRC 0, ERC 0, 0 conexiones incompletas, 0 cortocircuitos, paridad 0; firmware compila
para ESP32-C3). **NO VERIFICADO** físicamente.
**Revisión independiente** (agente sin acceso al razonamiento del diseño): sin errores de pines; corregidos el
despertar por reed ya cerrado (no se podía apagar), el rearmado lento del reed, la lectura retrasada del reed, la
corriente sin límite por el reed y el ritmo de lectura de la IMU.
**Pendiente:** ajustar el Qi con la bobina real; medir los tiempos del enclavamiento; comprobar ejes de la IMU;
adaptar AVO Update al ESP32-C3 (id 5) y la espalda para enviar el apagado remoto; revisar giros en JLCPCB.

## 2026-10-29 — Cincha · PCB REV A — ruteado completo y puerta de fabricación superada
**Autor:** Claude · Rama `feature/avo-girth-pcb` · **Commits:** `7f80a18`, `05556bb`, `e9e5166` · **CI:** runs 40881786227 (`05556bb`) y 40882718676 (`e9e5166`): éxito, puerta superada
**Qué cambia:** placa de la cincha (ESP32-C6-MINI-1U + BNO085 + BQ51013B + BQ24072 + relé biestable de corte) ruteada al
100 %: Freerouting 1.9.0 + reparación de QI_ADEN, QI_ILIM y SS_G con `fuente/repair.py` → `kicad/AVO_GIRTH_PCB_ruteado.kicad_pcb`.
KiCad 9 en el CI: DRC 0 errores, 0 advertencias, 0 conexiones incompletas, 0 cortocircuitos, 0 diferencias esquema ↔ placa;
ERC 0 errores y 0 advertencias. Se generan los ficheros FINAL (Gerber JLCPCB, BOM, CPL, STEP, DRC, ERC, informe y fuentes
KiCad con SHA256). BOM y CPL comprobados contra `piezas.json` y las posiciones de KiCad (104 piezas, LCSC coincidentes).
Además: modelo 3D del ESP32 con la colocación de Espressif (salía girado en el render/STEP) y descarga en el CI de los
modelos 3D de la librería de KiCad para el STEP (4 sin descargar: JST SH, USB-C, RHL-20, VQFN-16; solo afecta al STEP); README con GPIO14 = RELÉ ON, capas y ficheros FINAL.
**Archivos:** `hardware/girth/PCB/kicad/AVO_GIRTH_PCB_ruteado.kicad_pcb`, `…_colocacion.kicad_pcb`, `fuente/fplib.py`,
`fuente/gate.py`, `README.md`, `.github/workflows/build-girth-pcb.yml`.
**No se ha tocado:** `main`, `develop/avo-performance-horse`, firmware ni app.
**Validación:** CI (KiCad 9: DRC/ERC/paridad). **NO VERIFICADO** físicamente: nada fabricado ni medido.
**Pendiente:** medir la bobina Qi y ajustar C1–C5; BNO085 por Global Sourcing; confirmar existencias del relé G6KU-2F-Y
(alternativa AGQ210S03); polaridad real del relé (R40/R41); cambios de la carcasa; adaptar el firmware a los nuevos GPIO.

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
## 2026-11-09 — Espalda 3.14.3 — dormida, el USB solo carga y al desenchufar sigue dormida
**Autor:** Claude · **Rama:** `fix/back-3-14-0-sueno-pecho` · **Commit:** `084a64c` · **CI:** [42636407029](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42636407029) (**éxito**)
**Qué cambia:** el estado «esperando al pecho» se guarda en NVS (`avonow/wait`). Tras un reinicio con ese estado no enciende el GPS: con USB, modo carga y al desenchufar vuelve a esperar; sin USB, espera directamente. PRG o 3 encendidos rápidos fuerzan el arranque normal.
**Validación:** IMPLEMENTADO · CI · **NO VERIFICADO**.

## 2026-11-09 — Espalda 3.14.1 / 3.14.2 — GPS cortado con el Pololu al perder el pecho
**Autor:** Claude · **Rama:** `fix/back-3-14-0-sueno-pecho` · **Commits:** `d32cd05` (3.14.1), `9015857` (3.14.2) · **CI:** [42602791173](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42602791173) (**éxito**; artefacto [`AVO-BACK-V3-14-2-HELTEC`](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42602791173/artifacts/13667705186))
**Por qué:** con la 3.14.0 y el pecho apagado el LED blanco (TX del ZED, GPIO35) seguía encendido: el GPS tenía corriente en el sueño profundo. El usuario pide cortar el GPS con el Pololu como en el modo carga.
**Qué cambia:** 3.14.1 deja VDD_SPI encendido en el sueño profundo (hipótesis no confirmada). 3.14.2: sin pecho (BACK_SLEEP o 90 s) → `chest_wait_mode()`, los mismos pasos que `usb_charge_mode()` (UART cerrada, GPIO33/35 en alta impedancia, GPIO34 OUTPUT LOW activo + hold), **sin sueño profundo**: sueño ligero entre escuchas de 160 ms cada 10 s; al oír el pecho, Pololu encendido y reinicio limpio.
**Validación:** IMPLEMENTADO · CI · **NO VERIFICADO**. Comprobar: LED blanco apagado y VOUT del Pololu ≈ 0 V con polímetro tras 90 s sin pecho.

## 2026-11-09 — Espalda 3.14.0 — sueño con el pecho apagado
**Autor:** Claude · **Rama:** `fix/back-3-14-0-sueno-pecho` (desde 3.13.12) · **Commit:** `09c68ab` · **CI:** [42585459626](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42585459626) (**éxito**: 43 casos de host, 456 comprobaciones; artefacto [`AVO-BACK-V3-14-0-HELTEC`](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/42585459626/artifacts/13658587927), SHA-256 `818e11ec…a4`)
**Qué cambia:** se duerme (GPS a 0 V, radio apagada) con la orden `BackCmd::BACK_SLEEP` (8) del pecho ≥ 3.7.7 o tras 90 s sin oír a su pecho; dormida despierta cada 10 s, escucha 160 ms y solo arranca si oye a su pecho (`avo_chest_sleep.h`). Batería < 3,30 V dormida: deja de escuchar (despierta cada 5 min a medir). Carga USB sin cambios.
**Por qué:** petición del usuario (09/11): dormir del todo con el pecho apagado, despertar al encenderlo, 90 s y 10 s.
**No se ha tocado:** protocolo con el pecho (la orden 8 es nueva y opcional), GNSS/RTK, RTCM, cincha, modo carga USB.
**Validación:** IMPLEMENTADO · CI · **NO VERIFICADO** en la espalda. Sin V_BCKP el GPS arranca en frío al despertar (~30 s).
**Pendiente:** con el pecho 3.7.7: apagar el pecho → la espalda duerme en ≤ 1 s; encenderlo → arranca en ≤ 10 s. Medir el consumo dormida.

## 2026-11-02 — BACK 3.13.12 (Heltec) — vigilancia del resumen de señales y de reinicios del receptor
**Autor:** Claude · **Rama:** `fix/back-3-13-12-nav-sig-watchdog` (desde `fix/back-3-13-11-usb-pololu-off` 9dce9f4) · **Commit:** `483e98f` · **CI:** [41533949119](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41533949119) (**éxito**: pruebas de host, imagen ESP32-S3 válida de 917 888 B con la versión 3.13.12; artefacto `AVO-BACK-V3-13-12-HELTEC`, caduca 01/01/2027)
**Por qué:** prueba del 02/11/2026 (22:54), con el pecho 3.7.6, la espalda 3.13.11 al 28 % y la app 2.6-ntrip-auto-dev2.
- La tarjeta «Calidad GNSS» se quedó fija en «Esperando el resumen de señales del receptor».
- NAV-PVT seguía llegando (DGNSS, 43 cm) y el receptor usaba RTCM (17 195 mensajes).
- La 3.13.11 activa NAV-SAT/NAV-SIG en RAM una sola vez. Si el receptor pierde ese ajuste sin quedarse callado 5 s (reinicio breve, bajada de tensión), no lo vuelve a pedir.
**Qué cambia:**
- `avo_ubx_zed.{h,cpp}`: vigila el mensaje del resumen. Si en 10 s no llega, lo vuelve a pedir; tras 3 peticiones seguidas, una por minuto. Contadores `monitor_rearms()` y `receiver_resets()`. Diferencias con signo para no dar una pérdida falsa cuando el byte llega con una marca de tiempo posterior a la del tick.
- `avo_back_core.cpp`: `quality_mon` = estado (bits 0–3), peticiones repetidas (bits 4–5) y redetecciones del receptor (bits 6–7), con saturación en 3. **Sin cambio de formato ni de longitud**: el pecho 3.7.6 lo reenvía tal cual.
- `.ino`: línea `VIGILANCIA` en el monitor serie. Versión 3.13.12. CI con la rama nueva.
- 2 pruebas nuevas en el host: 39 casos y 432 comprobaciones, todas en verde en local.
**No se ha tocado:** NAV-PVT, RTCM, ESP-NOW, la batería, el modo carga ni el Pololu.
**Validación:** IMPLEMENTADO · COMPILADO / CI 41533949119 · **NO VERIFICADO** en la espalda.
**Pendiente:** instalar y comprobar que el resumen vuelve solo y que los contadores se ven en la app dev3.

## 2026-10-31 — BACK 3.13.11 (Heltec) — apagado real del Pololu con el USB
**Autor:** Claude · Rama `fix/back-3-13-11-usb-pololu-off` (desde `fix/back-3-13-10-usb-umbral`) · **Commits:** `e097c69` (CI 41165198487 falló: saltos de línea sin escapar), `b54848c` · **CI:** [41165334025](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41165334025) (éxito: pruebas de ordenador + imagen de 917 696 B)
**Qué cambia:** `AVO_USB_AUTO_OFF 1`. GPIO20 por unidad ADC2 propia (lecturas rechazadas = inválidas, se ignoran);
confirmación de 2 s con ≥ 6 muestras válidas. USB conectado → UART del ZED cerrada, GPIO33/35 en alta impedancia,
GPIO34 OUTPUT LOW, radio apagada, bucle de carga despierto (sin sueño profundo) que mantiene SHDN en LOW. USB retirado →
GPIO34 libre, 1,5 s y reinicio limpio (UART1 RX35/TX33, GNSS, NAV-PVT, ESP-NOW, RTCM).
**Por qué:** petición del usuario (activar el apagado real con los umbrales de 100/50 mV).
**Riesgo:** umbrales dentro de la zona imprecisa del ADC; un GPIO20 sin divisor real puede dar ~170 mV y dejar la espalda
en modo carga sin USB.
**Validación:** IMPLEMENTADO · COMPILADO / CI · **NO VERIFICADO**. VOUT no medida; detección USB por umbrales sin comprobar en la placa.

## 2026-10-31 — BACK 3.13.10 (Heltec) — diagnóstico de USB por umbrales en GPIO20
**Autor:** Claude · Rama `fix/back-3-13-10-usb-umbral` (desde `fix/back-3-13-9-usb-gps-off`) · **Commits:** `b35e976` (CI 41164215802 falló: variable declarada tarde), `0302d6a` · **CI:** [41164361647](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41164361647) (éxito: pruebas de ordenador + imagen de 916 880 B)
**Qué cambia:** USB por tensión en GPIO20 (ADC, mediana de 9, > 100 mV conectado / < 50 mV desconectado, histéresis,
confirmación de 2 s), GPIO7 (ADC1) medido como alternativa, línea `[USB]` cada segundo y motivo de cada transición.
`AVO_USB_AUTO_OFF 0`: **ningún apagado por USB** (ni en el bucle, ni al arrancar, ni al despertar); las transiciones se
registran como simulación. Se elimina la lectura digital de GPIO20 de la 3.13.9.
**Por qué:** petición del usuario; requisito de seguridad de no apagar el GPS con estos umbrales sin comprobarlos.
**Auditoría:** ADC2 compartido con la Wi-Fi (lecturas rechazadas = 0), GPIO20 = D+ del USB nativo (pad desactivado),
ADC impreciso por debajo de ~100 mV y lectura de ~170 mV con el pin suelto: umbrales de 100/50 mV no fiables. Propuesto
GPIO7 (ADC1) con el mismo divisor alimentado desde un punto con 5 V solo con USB.
**Validación:** IMPLEMENTADO · COMPILADO / CI · **NO VERIFICADO**. Apagado por USB no validado (desactivado).

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
## 2026-11-09 — iPad — Vídeo de carrera: marcar el caballo con el Pencil y pausa automática
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (prueba del entrenador 11:55: «se vuelve loco buscando»):**
- Rodear el caballo con el Pencil o el dedo pausa el vídeo y sigue esa zona (si dentro hay un jinete detectado, se usa su recuadro). Botones «Pausar» / «Continuar».
- Pausa automática (activada por defecto): si al empezar o tras un cambio de cámara no encuentra el caballo en ~6 fotogramas, el vídeo se para y pide marcarlo; «No se ve: seguir» continúa sin él hasta el siguiente cambio de cámara.
- Fotogramas analizados a 960 px de ancho (una grabación de pantalla del iPad a resolución completa solo dejó analizar 14 fotogramas).
- El reanclaje del seguimiento a un jinete detectado solo se hace si el tamaño es parecido (evita saltos de escala).
**Archivos:** `App/RaceVideoTracker.swift`, `App/RaceVideoModel.swift`, `Views/RaceVideoView.swift`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-09 — iPad — Reloj: «internal error» del Wi-Fi y cortes de Bluetooth durante la descarga
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (captura 11:43, pecho 3.7.7):**
- Wi-Fi: el error `NEHotspotConfigurationError.internal` («internal error») de iOS al unirse a AVO_CHEST_… ahora se trata como fallo conocido: se borra la configuración de esa red, se espera 2 s y se reintenta (3 intentos). Si sigue, la app pide apagar y encender el Wi-Fi del iPad.
- Bluetooth: si el enlace se corta en mitad de la descarga, la app se reconectaba sola pero dejaba el entreno «Pendiente» sin decir por qué. Ahora espera la reconexión (hasta 30 s) y continúa la descarga una vez; si no puede, el motivo es «se cortó el Bluetooth con el reloj durante la descarga».
**Archivos:** `App/WifiJoin.swift`, `App/WatchWifiModel.swift`.
**Validación:** IMPLEMENTADO · CI pendiente. Hipótesis del «Pendiente» sin motivo: corte del enlace BLE (linkLost cancela la pasada y reconecta); no confirmada con el registro del iPad.

## 2026-11-09 — iPad — Reloj: emparejamiento Bluetooth perdido
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:** el error de CoreBluetooth «Peer removed pairing information» (CBError 14, y 15 «encryption timed out») aparecía en inglés. Significa que el reloj borró su emparejamiento (actualización de firmware o borrado de emparejamientos) y el iPad conserva el antiguo; iOS no deja borrarlo desde una app. Ahora la app explica qué hacer: Ajustes › Bluetooth › (i) AVO_CHEST… › «Omitir este dispositivo», volver a conectar y pulsar BOOT.
**Archivos:** `App/IosBle.swift`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-09 — iPad — Copia automática en «AVO Horse» y análisis automático del vídeo de carrera
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:**
- **Copia automática en Archivos › En mi iPad › AVO Horse** (petición 09:37): la app comprueba y crea sus carpetas y copia, por caballo, `Entrenamientos/<caballo>` (originales verificados .avo/.avr), `Informes/<caballo>` (todo lo de «Informes» y los PDF de tramo), `Informes IA/<caballo>`, `Carreras/<caballo>` (PDF de tracking) y `Carreras/Vídeos`, y `Copia de seguridad` (los .json de la app y las notas). Se ejecuta al abrir, cada 2 min, al pasar a segundo plano y tras crear cada informe. Solo añade o actualiza; nunca borra. Botón «Copiar todo a AVO Horse» en Entrenamientos. La búsqueda de entrenamientos perdidos ignora esas carpetas (y las copias de entrenamientos salen como duplicadas por SHA-256).
- **Análisis automático del vídeo de la carrera** (petición 09:28, «Fase 2 en automático»): en el navegador de France Galop, «Analizar el vídeo de esta carrera» lee participantes, puestos, números y colores de cada chaquetilla, distancia y tiempo, y abre el vídeo (HLS/MP4 de la página; si no se puede, grabación de pantalla desde Fotos o Archivos; también «Analizar vídeo» en Carreras). Vision detecta los jinetes en cada fotograma, encuentra el nuestro por los colores (o por un toque, y aprende sus colores), lo sigue tras los cortes de cámara y mide el movimiento de cámara. `Core/RaceVideoAnalysis.swift` calcula la velocidad relativa (alturas de jinete/s, independiente del zoom), la calibra con distancia y tiempo oficiales, y obtiene parciales de 200 m, frecuencia de zancada (rebote del jinete, autocorrelación 1,6–3,2 Hz), zancadas y posición estimada. Se guarda como carrera «VÍDEO» (valores ESTIMADOS, con confianza y cobertura) y usa la misma comparación con entrenamientos que las carreras con tracker.
**Archivos:** `App/AppModel+DocumentsSync.swift` (nuevo), `App/AVOiPadApp.swift`, `App/AppModel+Shell.swift`, `App/TrainingListModel.swift`, `Views/TrainingListView.swift`, `App/ReportsModel.swift`, `App/StretchModel.swift`, `App/AssistantModel.swift`, `App/RacesModel.swift`, `Core/RaceVideoAnalysis.swift` (nuevo), `App/RaceVideoTracker.swift` (nuevo), `App/RaceVideoModel.swift` (nuevo), `Views/RaceVideoView.swift` (nuevo), `Views/FranceGalopView.swift`, `Views/RacesView.swift`, `Views/RaceDetailView.swift`, `Core/RaceModels.swift`, `App/AppModel.swift`, `App/RootView.swift`.
**Validación:** IMPLEMENTADO · CI pendiente. El análisis de vídeo no se ha podido probar con un vídeo real de France Galop.

## 2026-11-09 — iPad — Informes IA guardados en la ficha del caballo
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (bocetos 09/11/2026 00:09):**
- Asistente IA: botón **«Guardar informe PDF»** bajo cada respuesta. Guarda pregunta + respuesta en `informes_ia.json` (carpeta de la app) asociado al caballo y al entrenamiento, genera el PDF (cabecera AVO, datos del entrenamiento, pregunta, análisis con títulos, listas y tablas con celdas que se ajustan) y lo abre con «Compartir».
- Cuadra › Entrenamientos del caballo: los botones son ahora **Abrir · Tramo · Análisis IA · Informe completo** (sale «Asignar», que sigue en la barra superior). «Tramo» abre el tramo guardado de ese entrenamiento (menú si hay varios); «Análisis IA» abre el informe IA guardado (menú si hay varios); «Informe completo» genera el PDF de «Informes» con las secciones activas y lo muestra.
- Informe completo: la sección «Análisis IA y recomendaciones» incluye también los informes del asistente guardados. Las tablas Markdown de la IA se dibujan como tablas en PDF y HTML (antes salían como líneas con «|»).
- Visor de PDF común (`Views/PdfViewerSheet.swift`).
**Archivos:** `Core/AIReports.swift` (nuevo), `Core/ReportBuilder.swift`, `Core/PdfDocument.swift`, `App/AssistantModel.swift`, `App/ReportsModel.swift`, `App/AppModel.swift`, `App/RootView.swift`, `Views/AssistantView.swift`, `Views/StableView.swift`, `Views/ReportsView.swift`, `Views/PdfViewerSheet.swift` (nuevo).
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — Análisis IA en los informes
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (petición 13:55):**
- Informe del entrenamiento (PDF y HTML): nueva sección **«Análisis IA y recomendaciones»** (opción «Análisis IA (tramos)», activada) con el análisis IA de cada tramo de ese entrenamiento: los guardados con texto IA y los analizados en esta ejecución aunque no se hayan guardado.
- Análisis del tramo: el texto IA se conserva al cerrar y volver a abrir el tramo, se guarda solo en el tramo guardado al terminar, y «Informe PDF» espera a que termine el análisis.
- PDF: «≈ → ← ≥ ≤ − Δ ≠» se escriben como «~ -> <- >= <= - D !=» (antes salían como «?»).
**Archivos:** `Core/ReportBuilder.swift`, `App/ReportsModel.swift`, `App/StretchModel.swift`, `Views/ReportsView.swift`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — Nombres de archivo: caballo, fecha y tipo
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (boceto 13:34):** los archivos exportados se llaman `<Caballo>_<aaaa-mm-dd>_<hhmm>_<Tipo>.<ext>` (fecha y hora del entrenamiento, Europe/Madrid): informe/HTML/JSON `…_Completo`, CSV/GPX con selección `…_Tramo_<inicio>-<fin>`, PDF del tramo `…_Tramo[-nombre]_<inicio>-<fin>.pdf`, CSV de Gráficas `…_Datos-completo` / `…_Datos-tramo_<inicio>-<fin>`, CSV de Tramos `…_Tramos`. Antes: `AVO_<sesión>…`. `App/ExportNaming.swift` (nuevo).
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — Gráficas en una fila; Informes y Biomecánica al menú lateral
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (bocetos 13:10–13:13):**
- Gráficas: sin título de página, sin el botón «Seleccionar rango» (el tramo se selecciona manteniendo pulsado y arrastrando) y sin la fila «VER Completo/Calentamiento/Trabajo/Enfriamiento»; zoom, «Guardar como tramo», «Quitar selección», «Exportar CSV» y reproducción en una sola fila; debajo, la barra de vista general.
- Menú lateral: **Informes** y **Biomecánica** debajo de Análisis (salen de la barra de pestañas del entrenamiento). «Análisis» no se resalta en esas dos páginas. Prueba de capturas actualizada (nav.Biomech, nav.Reports). En Informes y Biomecánica no se muestra la fila de pestañas del entrenamiento (boceto 13:35).
**Archivos:** `App/RootView.swift`, `Views/ChartsView.swift`, `AVOiPadUITests/ScreenshotTests.swift`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — PDF del tramo: regla de distancias sobre el satélite
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (boceto 13:05):** en la imagen «Recorrido del tramo» del PDF, una regla arriba con una marca cada 200 m (0, 200, 400…) y líneas de puntos azules desde cada marca hasta su punto del recorrido; la Vmáx con una línea de puntos roja y su distancia desde el inicio (p. ej. «1910 m»). `RouteImageRenderer.render(distanceMarks:)`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — PDF del tramo: ajustes tras la primera prueba
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:** PDF del tramo revisado con el iPad (BELLA AL SHAHANIA, 07/11/2026): satélite, giro, Vmáx y parciales correctos. Ajustes: la etiqueta «Fin»/«Inicio» ya no se sale de la imagen; más solape entre teselas (se veían líneas finas); el título «Velocidad en el tramo» no se queda solo al final de la página.
**Validación:** PROBADO FÍSICAMENTE (iPad, compilación anterior) lo descrito; los ajustes IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — Satélite de fondo en los informes y Vmáx con su valor
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (peticiones 10:54–10:56):**
- Informes (PDF y vista HTML) y PDF del tramo: el recorrido se dibuja **sobre la imagen de satélite** (Esri World Imagery, primero la caché de teselas del mapa, después la red), girado igual que antes (horizontal), con colores por velocidad, inicio/fin, **Vmáx con su valor**, escala, norte y atribución. Sin teselas (sin conexión ni caché) se dibuja como antes sobre fondo liso. `App/RouteImageRenderer.swift` (nuevo); `PdfDocument.image` (JPEG como XObject DCTDecode); `ReportData.routeImage`, `StretchPdfData.routeImage`; `RouteLayout` guarda su transformación.
- Vmáx con la velocidad exacta visible: gráfica del «Análisis del tramo» (etiqueta sobre el punto), gráfica del PDF del tramo y mapas de los informes (también en el dibujo sin satélite).
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — Informe PDF del tramo, recorrido horizontal en los informes y cifras del Dashboard
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia (capturas del entrenador 10:41–10:45):**
- «Análisis del tramo»: botón **Informe PDF** (junto a «Guardar en…»): PDF con datos del tramo, 12 cifras, recorrido del tramo, velocidad frente a metros con líneas cada 200 m y Vmáx, desglose de 200 m, observaciones, comparación con los tramos guardados y el análisis IA (si se ha hecho). Se guarda en `exportaciones/AVO_tramo_<sesión>_<hhmmss>.pdf` y abre el menú de compartir. `ReportBuilder.stretchPdf` reutiliza la cabecera y tablas de los informes (`PdfReportWriter` ya no es `final`; subtítulo configurable).
- Informes (PDF y vista HTML): el **recorrido se dibuja girado en horizontal** (eje principal por PCA, inicio a la izquierda), con flecha de norte girada y escala correcta (`ReportBuilder.routeLayout`). Antes salía en vertical, norte arriba.
- Páginas del entrenamiento: las pestañas (Análisis, Resumen, Gráficas, Trabajo en pista…) en **su propia fila** bajo la barra (entrenamiento, Entreno 2, Asignar).
- Mapas («Mapa» y «Análisis»): encuadre de serie = recorrido en horizontal y **zoom sobre la fase de trabajo** del motor (con las correcciones), en vez de todo el recorrido; «Ajustar» vuelve a ese encuadre. Sin fase de trabajo, todo el recorrido.
- Todas las páginas: **sin la barra de título** centrada («Jinetes», «Reloj Wi-Fi»…); la cabecera AVO / barra del entrenamiento sube a la primera fila. Con el menú lateral oculto aparece un botón a su izquierda para volver a mostrarlo.
- Dashboard: las 5 cifras en una fila a **todo el ancho** bajo la portada y los accesos, sin cortarse.
**Archivos:** `Core/ReportBuilder.swift`, `App/StretchModel.swift`, `Views/StretchAnalysisView.swift`, `Views/ReportsView.swift`, `Views/HomeView.swift`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — IA sin texto («respuesta cortada por longitud») y cifras del Dashboard
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:**
- Análisis IA del tramo: gastaba ~7600 tokens y no mostraba texto. Claude Sonnet 5.5 piensa por defecto (pensamiento adaptativo) y `max_tokens` cubre pensamiento + texto: con 4096 todo se iba en pensar. Ahora el tramo usa `max_tokens` 32 000 con `output_config.effort = "medium"`, y el Asistente IA 16 000 (antes 4096, mismo problema posible). `ClaudeClient.stream` acepta `effort`.
- Dashboard: las 5 cifras siempre en una fila (con 3 columnas se cortaban Velocidad máxima y Sesión activa).
**Archivos:** `Core/ClaudeAPI.swift`, `App/AssistantModel.swift`, `App/StretchModel.swift`, `Views/HomeView.swift`.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — Corrige el archivo para TestFlight (Xcode 26)
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:** el run 42429837057 compiló y pasó las pruebas, pero el archivo Release falló: «the compiler is unable to type-check this expression in reasonable time» en la fila de «Tramos guardados» (`StableView.swift`). La fila pasa a una vista propia (`StableStretchRow`) y se simplifican las expresiones largas de `StretchAnalysisView` (parciales y observaciones). Sin cambios de comportamiento.
**Validación:** IMPLEMENTADO · CI pendiente.

## 2026-11-08 — iPad — France Galop: fichas de la cuadra y carreras (uso privado)
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (petición del entrenador 01:01/01:16, uso privado):**
- Cuadra: botón **France Galop** (cabecera) que abre france-galop.com en un navegador dentro de la app (`FranceGalopView`, WKWebView). «Leer página» lee lo que muestra la página: datos de la ficha (sexo/raza/capa, nacimiento, padres, entrenador, colores, criadores, valor, actuaciones, país…), **todas sus tablas** (resumen de carrera, actuaciones = carreras, compromisos) y los enlaces a fichas de caballos (página del entrenador o propietario = **toda la cuadra**).
- Ficha leída → «Guardar en la Cuadra» en un caballo existente o creándolo (nombre, raza y año de la ficha; solo rellena raza/año si estaban vacíos).
- Página del entrenador → «Vincular estos caballos con la Cuadra» (propone el caballo por nombre; «Crear en la Cuadra») → «Actualizar toda la cuadra»: abre cada ficha vinculada una a una, con pausas de ~3 s, y guarda sus datos y tablas.
- Ficha del caballo en Cuadra: tarjeta **France Galop** con los datos y las tablas guardadas, «Actualizar» y «Desvincular».
- No depende de la estructura interna de la web (lee texto visible, tablas HTML y enlaces); solo a petición del usuario. Datos en `france_galop.json` en la carpeta de la app.
**Archivos:** `ipad/AVOiPad/Core/FranceGalop.swift`, `ipad/AVOiPad/App/FranceGalopModel.swift`, `ipad/AVOiPad/Views/FranceGalopView.swift` (nuevos); `AppModel.swift`, `RootView.swift`, `StableView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO (sin acceso a france-galop.com desde el entorno de desarrollo: la lectura de etiquetas está hecha con la ficha de la captura del usuario).

## 2026-11-08 — iPad — Análisis del tramo (pantalla completa) y tramos guardados por caballo
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (petición del entrenador 00:57):**
- «Mapa»: botón **Análisis tramo** (arriba a la derecha, activo con un tramo seleccionado) que abre a pantalla completa `StretchAnalysisView`:
  - 14 cifras del tramo (distancia, duración, vel. media/máx., mejor 200 m, último 200 m frente al mejor, 2.ª mitad frente a 1.ª, tiempo hasta el 90 % de Vmáx, distancia y tiempo por encima del 90 %, aceleración/frenada máx. validadas, regularidad CV, cadencia, RTK FIX);
  - perfil de velocidad frente a metros con líneas cada 200 m y la Vmáx;
  - **desglose por tramos de 200 m** (tiempo, media, máx., aceleración media; el mejor resaltado; parcial final marcado);
  - observaciones calculadas con los datos (caída final, mitades, regularidad, punta, calidad GNSS, comparación con su mejor tramo guardado de distancia parecida);
  - comparación con los tramos guardados del caballo;
  - **análisis completo IA y recomendaciones** (Claude con la clave del Asistente IA, o el modelo de Apple), con el tramo, el resumen del entrenamiento completo y los tramos guardados; respeta el límite de gasto mensual.
- **Guardar el tramo en el caballo** (`tramos_guardados.json` en la carpeta de la app; con nombre opcional y el texto IA). Cuadra › caballo: además de «Entrenamientos de …» (completos), nueva lista **«Tramos guardados de …»** con Abrir (selecciona el entrenamiento y el tramo y abre el análisis) y Borrar.
**Archivos:** `ipad/AVOiPad/Core/StretchAnalysis.swift`, `ipad/AVOiPad/App/StretchModel.swift`, `ipad/AVOiPad/Views/StretchAnalysisView.swift` (nuevos); `AppModel.swift`, `RootView.swift`, `StableView.swift`, `AssistantModel.swift` (`addSpend` accesible).
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-08 — iPad — Inicio: sin logo redondo, rótulo y accesos más arriba
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** pantalla de inicio (`StartView`): quitado el logo redondo; el rótulo AVO / PERFORMANCE HORSE / TRAINING ANALYSIS sube a su sitio; la columna de accesos empieza arriba (antes centrada). Petición del entrenador: el jinete de la foto con los colores de la Cuadra Lezama — **no hecho**: requiere una foto propia (no se usan imágenes de Internet).
Dashboard en horizontal sin desplazamiento (se cortaba arriba): portada y cifras a la izquierda, accesos a toda la altura a la derecha.
**Archivos:** `ipad/AVOiPad/Views/StartView.swift`, `ipad/AVOiPad/Views/HomeView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-08 — iPad — Menú: Dashboard, Entrenamientos y Mapa antes de Análisis
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (bocetos del entrenador, 00:20–00:24):**
- Barra lateral: «Entrenamientos» (página `.sessions`) pasa a **Dashboard**; «Listado» pasa a **Entrenamientos** (título de la página también); **Mapa** va antes que Análisis.
- Dashboard: solo la portada, los accesos rápidos y las cifras (entrenamientos, distancia medida, demostración, velocidad máxima, sesión activa). Quitadas las tarjetas de sesiones recientes, Reloj AVO, Caballos, Disponibilidad de sensores, Estado de importaciones y Estado del sistema.
**Archivos:** `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPad/Views/HomeView.swift`, `ipad/AVOiPad/Views/StartView.swift`, `ipad/AVOiPad/Views/TrainingListView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-08 — iPad — Marca fija de velocidad máxima y barra de «Mapa» solo con el entrenamiento
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:**
- Marca fija en el punto de velocidad máxima (velocidad filtrada): en el mapa, marcador naranja con rayo y «Vmáx 51,1 km/h» (`VmaxAnnotation`); en la gráfica de velocidad de «Mapa» y en el perfil de «Análisis», punto naranja. `SessionItem.maxSpeedPoint` (en caché por línea de tiempo).
- «Mapa»: la barra de arriba solo tiene el selector de entrenamiento (boceto del entrenador); Entreno 2, pestañas y Asignar siguen en «Análisis». «Mapa» ya no usa la vista de comparación.
**Archivos:** `ipad/AVOiPad/App/SessionItem.swift`, `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPad/Views/MapKitRoute.swift`, `ipad/AVOiPad/Views/MapPageView.swift`.
- «Mapa» con un tramo seleccionado: arriba los datos del tramo y, a la vez, abajo a la izquierda los del punto seleccionado (tiempo, distancia, velocidad, aceleración y fase).
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-08 — iPad — Mapa sin tarjetas inferiores y doble toque para quitar el tramo
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:**
- «Mapa»: quitadas las tarjetas Entrenamiento, leyenda de velocidad y Punto seleccionado bajo la gráfica (boceto del entrenador); la gráfica con pestañas y zonas ocupa el resto de la página, sin desplazamiento vertical. En «Análisis» siguen.
- Todas las gráficas sincronizadas: doble toque con el dedo o doble toque lateral del Apple Pencil (`UIPencilInteraction`) quita el tramo seleccionado.
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/Views/ChartsView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Satélite con zoom máximo y fuera el aviso NFC de Cuadra/Jinetes
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:**
- Mapa: con el zoom al máximo la imagen de satélite desaparecía (rejilla vacía), porque Esri solo sirve hasta el nivel 19. `RouteEsriTileOverlay` llega ahora al nivel 22 ampliando un trozo de la tesela del nivel 19; si falta una tesela en un nivel ≥ 16 se amplía la del nivel anterior.
- Cuadra y Jinetes: quitada la tarjeta «El iPad no tiene NFC… / Pegar enlace avohorse://…» de la cabecera y la nota NFC de la ficha (petición del entrenador).
**Archivos:** `ipad/AVOiPad/Views/MapKitRoute.swift`, `ipad/AVOiPad/Views/StableView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: sigue al cursor, datos del tramo, mapa en la mitad y desplazamiento lateral con zoom
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (bocetos del entrenador, 23:25–23:31):**
- El mapa se centra en el punto elegido en la gráfica o en la barra de tiempo **sin cambiar el zoom ni el giro** (`MapKitRoute.applyCursor`). No se mueve cuando el punto se toca en el propio mapa ni en el primer cursor de un recorrido.
- Con un tramo seleccionado en la gráfica, la franja superior del mapa muestra los datos del **tramo**: duración, distancia, vel. media, vel. máx., aceleración y frenada máx. validadas, inicio–fin.
- «Mapa»: mapa en la mitad superior, barra de tiempo (reproducción) entre el mapa y las gráficas, y debajo las gráficas con desplazamiento vertical (gráfica con pestañas + zonas, y las tarjetas Entrenamiento / leyenda / punto). En «Análisis» la reproducción sigue sobre el mapa.
- Gráficas con zoom: desplazamiento lateral con **dos dedos** (`TwoFingerPan`, UIKit, simultáneo con el resto de gestos), al arrastrar el cursor contra un borde, y en «Mapa» la barra de vista general con el recuadro arrastrable y «Completo».
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/Views/MapKitRoute.swift`, `ipad/AVOiPad/Views/ChartsView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: nueva distribución según el boceto del entrenador
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (página «Mapa»; los elementos sobre el mapa también en «Análisis»):**
- Franja de datos del punto del cursor (tiempo, distancia, velocidad, aceleración y fase) arriba del mapa, en lugar de abajo.
- Estadísticas en columna arriba a la derecha: Distancia, Vel. media, Tiempo, Vel. máx.
- Reproducción (play, velocidad, barra y tiempo) sobre el borde inferior del mapa.
- «Capas» abajo a la derecha, junto a los botones de zoom (el panel se abre encima).
- Debajo del mapa, una sola gráfica grande con pestañas Velocidad · Aceleración · Lateral · Inclinación · Vertical · Cadencia (las de cincha y cadencia solo si hay datos), con las franjas y asas de zonas y los botones de zonas dentro de la misma tarjeta. La pestaña elegida se recuerda.
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Reloj Wi-Fi: motivo real del fallo, sondeo HTTP y protección de reinicios
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:**
- Con el pecho 3.7.6 (AVO_1E8C) la página decía «WI-FI DISPONIBLE» mientras descargaba por Bluetooth «(no se pudo usar el Wi-Fi del reloj)», sin el motivo. Ahora `WifiSyncReport.wifiReason` y `WifiConnector.lastFailure` llevan el motivo hasta la pantalla (reloj rechaza activar el Wi-Fi, el iPad no se une a la red, o se une pero el reloj no responde por HTTP), y la etiqueta pasa a «WI-FI FALLÓ» con el motivo debajo hasta que una pasada por Wi-Fi funcione o se reconecte.
- Sondeo HTTP tras unirse: antes una sola petición con 20 s de tiempo de espera agotaba toda la ventana de 20 s; ahora peticiones de 4 s cada segundo durante 30 s (DHCP, ruta a 192.168.4.x y permiso de red local de iOS la primera vez).
- Unión a la red del reloj: un segundo intento a los 3 s si el primero falla (el SoftAP puede no estar emitiendo todavía), salvo que el usuario la rechace.
- `WifiBootGuard`: si `WIFI_SYNC(start)` no respondía (excepción) el intento quedaba marcado; cualquier apagado y encendido normal posterior del reloj bloqueaba el Wi-Fi como si se hubiera reiniciado por él. Ahora se borra el intento si el enlace Bluetooth sigue vivo.
**Archivos:** `ipad/AVOiPad/Core/WifiSync.swift`, `ipad/AVOiPad/App/WifiJoin.swift`, `ipad/AVOiPad/App/WatchWifiModel.swift`, `ipad/AVOiPad/Views/WatchWifiView.swift`.
**No se ha tocado:** firmware del pecho, protocolo BLE/HTTP, descarga por Bluetooth.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.
**Pendiente:** con el motivo visible, decidir si el fallo está en el reloj (3.7.6) o en iOS. La app Android tiene la misma marca de intento en `AvoWifiSyncManager` (revisar).

## 2026-11-07 — iPad — Mapa: datos del cursor en una franja horizontal
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** en la compilación 38 el recuadro del cursor ocupaba todo el ancho y casi la mitad del mapa (el `Divider` lo estiraba). Ahora es una sola franja horizontal y baja en la parte inferior del mapa, como en el boceto del usuario: Punto · tiempo · distancia · velocidad · aceleración | fase · tiempo fase · distancia fase · «de» total; solo ocupa lo que necesita y deja libres los botones de zoom.
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: tiempo y distancia del cursor dentro de la fase
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** el recuadro «Punto del cursor» añade, cuando el cursor cae dentro de una fase del motor (calentamiento, trabajo o enfriamiento de «trabajo_pista», ya con las correcciones a mano), «En <fase>»: tiempo y distancia desde el inicio de esa fase y la duración y distancia totales de la fase. Se detecta por la posición del cursor, sin tener que pulsar «Ver: Calentamiento / Trabajo / Enfriamiento» (que solo acerca las gráficas), así que funciona también en «Mapa».
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: datos del punto exacto del cursor
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** recuadro «Punto del cursor» en la esquina inferior izquierda del mapa (Análisis y Mapa, `MapCursorOverlay`): tiempo, distancia desde el inicio (m), velocidad (km/h) y aceleración longitudinal validada (m/s²) del punto exacto donde está el cursor (toque en el recorrido, en la línea de tiempo o reproducción). Usa los mismos valores que las lecturas de las gráficas (`cursorSpeed`, `cursorAccel`; nuevo `cursorDistanceM`). Petición del usuario sobre captura de la compilación 36.
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/App/AppModel+Shell.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.

## 2026-11-07 — iPad — Mapa: playa en horizontal y giro con dos dedos
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** el mapa del recorrido (`MapKitRoute`) se puede girar con dos dedos y «Ajustar» lo orienta para que el recorrido quede en HORIZONTAL: eje principal de las posiciones (componentes principales en Web Mercator), rumbo de la cámara elegido lo más cerca posible del norte (en el Regatón el mar queda arriba); si el recorrido no tiene una dirección clara (ratio de varianzas < 1,6) se deja el norte arriba. El encuadre mide el recorrido a lo largo y a lo ancho de la pantalla girada y respeta los márgenes (datos arriba a la derecha). El zoom +/− mantiene el giro (cámara en vez de `setVisibleMapRect`). Botón nuevo en Análisis y Mapa: «Norte arriba» / «Recorrido en horizontal» (se recuerda en `map.alignRoute`). Petición del usuario: «necesito ver la playa en horizontal».
**Archivos:** `ipad/AVOiPad/Views/MapKitRoute.swift`, `ipad/AVOiPad/Views/MapPageView.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad. El mapa de la comparación (Entreno 2, SwiftUI `Map`) se gira con dos dedos pero no se orienta solo.

## 2026-11-06 — iPad — Análisis rediseñado: mapa a todo el ancho, línea de tiempo y todas las gráficas con scroll; «Entreno 2»; «Mapa» en el menú
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia (pedido del usuario sobre una captura anotada de la compilación 33):**
- **Análisis** (`MapPageView`): una sola columna con scroll vertical:
  - mapa a todo el ancho (58 % de la altura, mínimo 380 pt); el panel «Capa base / Trazo» queda oculto tras el botón «Capas»; distancia, tiempo, velocidad media y máxima van en pequeño sobre la esquina superior derecha del mapa (`MapStatsOverlay`); los botones de zoom bajan a la esquina inferior derecha;
  - debajo, la línea de tiempo (perfil de velocidad con zonas y asas, reproducción) y los botones de zonas;
  - después, TODAS las gráficas de «Gráficas» (`ChartsNavigator` + `ChartsStack(skipSpeed: true)`, sin repetir la velocidad), con el mismo cursor, zoom y rango;
  - al final, las tarjetas que estaban en la columna derecha: Entrenamiento (fases), leyenda y punto seleccionado (`MapInfoCards`). Se elimina `MapSidePanel`; los tramos siguen en su página.
- **«Entreno 2»** (`RootPairMenu`, en la barra del entrenamiento junto al entrenamiento activo): elige un segundo entrenamiento y Análisis pasa a comparar los dos (entreno 1 azul, entreno 2 amarillo): cabecera con ambos y «Quitar entreno 2», barra de zoom y rango de la comparación, recorridos superpuestos grandes y gráficas alineadas (`CompareResults`, `CompareMap`, `CompareChartToolbar`, `CompareRangeCard` pasan a ser internos). `CompareModel.pairId` / `setPair(_:)`: la comparación contiene solo esos dos; al cambiar el entrenamiento activo se mantiene el entreno 2 (si coinciden, se quita).
- **Menú lateral:** nueva entrada **«Mapa»** debajo de «Análisis» (`Page.map`, `nav.Map`): el mapa ocupa la página con la línea de tiempo debajo y sin gráficas (o los dos recorridos con «Entreno 2»).
**Archivos:** `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/Views/ChartsView.swift`, `ipad/AVOiPad/Views/CompareView.swift`, `ipad/AVOiPad/App/CompareModel.swift`, `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPad/App/AppModel+Shell.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO en el iPad.
**Pendiente:** cursor de la línea de tiempo sobre el mapa de la comparación; revisar con el usuario la altura del mapa.

## 2026-11-06 — iPad — Asistente IA: corrección de «Probar conexión» que borraba la clave
**Autor:** Claude · **Rama:** `feature/ipad-app` · **CI:** pendiente
**Qué cambia:** en Ajustes del asistente, «Guardar clave», «Probar conexión» y «Borrar clave» estaban en la misma fila del `Form`; en SwiftUI un toque en esa fila dispara todos los botones, así que «Probar conexión» borraba la clave y respondía «No hay clave guardada» (visto en el iPad con la compilación 33). Ahora cada botón va en su fila con `.buttonStyle(.borderless)` y «Borrar clave del iPad» queda aparte, al final. Al guardar, se comprueba que la clave se lee del Llavero y el asistente pasa a usar Claude (se desactiva «Usar el modelo de Apple»).
**Archivos:** `ipad/AVOiPad/Views/AssistantView.swift`, `ipad/AVOiPad/App/AssistantModel.swift`.
**Validación:** IMPLEMENTADO · error reproducido por el usuario en el iPad (compilación 33) · corrección NO VERIFICADA.

## 2026-11-06 — iPad — Asistente IA: Claude (API) y modelo de Apple analizan el entrenamiento activo
**Autor:** Claude · **Rama:** `feature/ipad-app` · **Commits:** ver `git log` · **CI:** pendiente
**Qué cambia:**
- **Nueva pestaña «Asistente IA»** en la barra del entrenamiento (`Page.assistant` = `Assistant`, `tab.Assistant`, después de «Trabajo en pista»; `App/AssistantModel.swift`, `Views/AssistantView.swift`):
  - conversación sobre el entrenamiento activo con respuesta en streaming, botón Detener y «Nueva conversación»;
  - preguntas rápidas: explicar la sesión, fatiga y recuperación, comparar con la historia, zancada y cincha, próximo entrenamiento;
  - la conversación se reinicia al cambiar de entrenamiento.
- **Claude por la API, directo desde el iPad** (`Core/ClaudeAPI.swift`): `POST https://api.anthropic.com/v1/messages` (`anthropic-version: 2023-06-01`, SSE).
  - Modelos: Sonnet 5.5 (por defecto), Haiku 5.5 y Opus 5.5.
  - **Contexto:** cabecera (caballo, raza de la Cuadra, jinete, fecha, ventana útil, estado del motor), resumen `avo-training-session`, análisis completo del motor compactado (sin `series`, listas numéricas largas resumidas en n/mín./máx./media, listas de objetos recortadas, decimales redondeados; incluye `trabajo_pista`) y resúmenes ya calculados de hasta 15 sesiones anteriores del mismo caballo. Tope de 180 000 caracteres (por debajo de los 100 000 tokens de Haiku 5.5).
  - El contexto va en un bloque de sistema con `cache_control` (las preguntas siguientes leen de caché) y se reutiliza mientras no cambie la sesión ni su análisis.
  - Instrucciones: responder en español, solo con los datos recibidos, citando cifras; umbrales de raza y mano de galope tratados como no validados; sin diagnósticos veterinarios.
- **Clave de API en el Llavero de iOS** (`AvoKeychain`, `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`): la pega el usuario en Ajustes del asistente; nunca está en el código ni en el repositorio (regla 6). «Probar conexión» y «Borrar clave».
- **Gasto:** estimación por respuesta con los precios de lista (tokens y ~$ en el pie de cada respuesta), contador del mes en el iPad y límite configurable (5–100 $, 50 $ por defecto) que bloquea las preguntas al alcanzarlo. El tope real son los 100 $/mes de créditos de API del plan Max en Claude Console (organización sin método de pago ni recarga automática).
- **Modelo de Apple sin conexión** (`Core/OnDeviceAssistant.swift`, Foundation Models, iPadOS 26 con Apple Intelligence): opción gratuita que solo recibe el resumen de la sesión; compila con `#if canImport(FoundationModels)`, así que el CI de pruebas con un SDK anterior lo deja desactivado.
- **Pruebas:** `AVOiPadTests/AssistantTests.swift` (compactación del JSON, coste estimado, forma de la clave, mensajes de error, mezcla del `usage` del streaming); captura de la página `Assistant` en `ScreenshotTests` (sin clave: tarjeta de configuración).
**Por qué:** el usuario quiere un analista IA dentro de la app con los créditos de API incluidos en su plan Max, sin servidor (el Servidor AVO aún no funciona). Cuando funcione, `ClaudeClient.endpoint` puede apuntar a él y quitar la clave del iPad.
**Archivos:** `ipad/AVOiPad/Core/ClaudeAPI.swift` (nuevo), `ipad/AVOiPad/Core/OnDeviceAssistant.swift` (nuevo), `ipad/AVOiPad/App/AssistantModel.swift` (nuevo), `ipad/AVOiPad/Views/AssistantView.swift` (nuevo), `ipad/AVOiPad/App/AppModel.swift`, `ipad/AVOiPad/App/AppModel+Shell.swift`, `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPadTests/AssistantTests.swift` (nuevo), `ipad/AVOiPadUITests/ScreenshotTests.swift`, `ipad/UI_CONTRACT.md`.
**No se ha tocado:** el motor (`equine-intelligence`), Android, Windows, firmware.
**Validación:** IMPLEMENTADO · sin compilador Swift en la sesión (pendiente de CI macOS) · NO VERIFICADO en el iPad ni con la API real.
**Pendiente:** probar en el iPad con la clave real; renderizado completo de Markdown (títulos y listas se muestran como texto); llevarlo a Android y Windows; pasar por el Servidor AVO cuando esté operativo.

## 2026-11-03 — iPad — AVO Track Work 1.0.0 integrado: página «Trabajo en pista», entrenamiento vs carrera y Track Work en la historia
**Autor:** Claude · **Rama:** `feature/ipad-app` (sobre `7a6bb83`) · **Commits:** pendiente · **CI:** pendiente
**Qué cambia:**
- **`Core/TrackWork.swift`:** decodifica TODO el bloque `trabajo_pista` (tolerante, `nil` si falta):
  - perfil de raza (umbrales, velocidades de referencia, base de parciales 200 m o furlong);
  - cincha (VeDBA medio, por aire y carga, giros y grados por mano, saturación), zancadas (resumen y lista), mano (EXPERIMENTAL);
  - trabajos y pasadas: parciales con tiempo acumulado y velocidad, mejores 200…1600 m (tiempo, velocidad, dónde), v. máx y tiempo hasta ella, distancia > 90 %, últimos 200/400 m, índice de caída, zancada a la máxima y a las velocidades de referencia, ajustes f/l, mano por trabajo, recuperación y pausa;
  - recorrido (pasadas, mejor pasada, % dentro de la geocerca, cruces ignorados en sentido contrario), fases, series, eventos y avisos.
  - Se mantienen los nombres antiguos (`efforts`, `passes`, `sectionals`, `fatiguePct`, `recoveryS`…).
- **Nueva página «Trabajo en pista»** (`Page.trackWork`, pestaña de la barra del entrenamiento después de Gráficas, `tab.TrackWork`; `App/TrackWorkModel.swift`, `Views/TrackWorkView.swift`):
  - cabecera con la raza de la ficha, el perfil usado (aviso y «Volver a analizar» si no coinciden), la base de las fases (velocidad / líneas / corregidas) y los avisos;
  - franja de la estructura (calentamiento / trabajo / calma con minutos al paso, trote y galope) y fichas de resumen de las series;
  - tabla ordenable de trabajos y pasadas; al tocar una fila se selecciona en toda la app (rango, cursor y ventana de Gráficas) y se abre su detalle: parciales (tabla y barras en s o km/h), mejores distancias, velocidad frente a distancia con la máxima y la franja del 90 %, frecuencia y longitud de zancada frente a la velocidad con los valores de referencia resaltados, cincha y giros del trabajo, eventos;
  - «Mejores distancias de la sesión», cincha de la sesión, recorrido y eventos.
  - Sin datos: «Sin datos», «Requiere cincha» o «Requiere líneas de salida y meta».
- **Análisis (mapa):** el panel «Entrenamiento» queda como resumen (fases, recuentos, seleccionado) con el botón «Ver trabajo en pista»; la lista de trabajos pasa a la nueva página.
- **Ficha de la carrera:** bloque «Entrenamiento vs carrera, tramo a tramo» (`Views/RaceTrainingSplitsView.swift`, `RaceTrainingSplits` en `Core/RaceAnalysis.swift`):
  - por defecto, el trabajo o pasada más rápido por velocidad media (con ≥ 2 parciales completos) de los 60 días anteriores a la carrera; menú para elegir otro;
  - tramos alineados desde la meta (último parcial completo ↔ 200–ARR), solo piezas completas; tiempo y km/h de entrenamiento y carrera, % de la velocidad de carrera y perfil de caída (último / mejor tramo) en ambos;
  - analiza con el motor (resultado en caché) los entrenamientos de la ventana que aún no tienen resultado;
  - explica que los parciales del entrenamiento son en la playa y los de la carrera en la pista.
- **Historia del caballo:** sección «Trabajo en pista»: evolución de la mejor pasada, su velocidad media, índice de caída, recuperación y VeDBA en galope; carga VeDBA por día/semana con su ACWR; tabla de líneas base y tendencias de `TRABAJO.*`, `CINCHA.*`, `RECORRIDO.*` y `carga_vedba`; impactos atípicos y motivos de la cincha. `TrainingSessionSummary.trabajoPista` y la carga VeDBA de `TrainingLoad` se decodifican; las tendencias de Track Work salen de la tarjeta general.
- **Pruebas:** `AVOiPadTests/TrackWorkTests.swift` (JSON real del motor para las sesiones sintéticas de `test_racing.cpp` con cincha y con líneas tipo Regatón; decodificación tolerante; velocidad-distancia; motor real sobre la demo con raza PSI; alineación entrenamiento-carrera). Capturas: página `TrackWork` añadida a `ScreenshotTests`.
**Supuestos:** «mejor pasada» por defecto en la carrera = mayor velocidad media (el motor llama mejor pasada a la más corta en tiempo); un parcial cuenta como completo si mide ±5 % de la base; los giros por mano de un trabajo se calculan con el giro medio de sus zancadas (|giro| ≥ 4 °/s).
**Archivos:** `ipad/AVOiPad/Core/TrackWork.swift`, `ipad/AVOiPad/Core/RaceAnalysis.swift`, `ipad/AVOiPad/Core/TrainingAnalytics.swift`, `ipad/AVOiPad/App/TrackWorkModel.swift` (nuevo), `ipad/AVOiPad/App/AppModel.swift`, `ipad/AVOiPad/App/AppModel+Shell.swift`, `ipad/AVOiPad/App/RootView.swift`, `ipad/AVOiPad/App/RacesModel.swift`, `ipad/AVOiPad/App/HorseHistoryModel.swift`, `ipad/AVOiPad/Views/TrackWorkView.swift` (nuevo), `ipad/AVOiPad/Views/RaceTrainingSplitsView.swift` (nuevo), `ipad/AVOiPad/Views/RaceDetailView.swift`, `ipad/AVOiPad/Views/MapPageView.swift`, `ipad/AVOiPad/Views/HorseHistoryView.swift`, `ipad/AVOiPadTests/TrackWorkTests.swift` (nuevo), `ipad/AVOiPadUITests/ScreenshotTests.swift`, `ipad/UI_CONTRACT.md`.
**No se ha tocado:** el motor (`equine-intelligence`), Android, Windows, firmware.
**Validación:** IMPLEMENTADO · sin compilador Swift en la sesión (pendiente de CI macOS) · NO VERIFICADO en el iPad ni con caballos reales.

## 2026-11-03 — iPad — raza en la ficha del caballo: desplegable de razas de carreras
**Autor:** Claude · **Rama:** `feature/ipad-app`
**Qué cambia:** el campo «Raza» de la ficha del caballo (Cuadra) pasa a ser un desplegable agrupado:
- **Galope:** Pura Sangre Inglés (PSI), AQPS, Pura Sangre Árabe (PSA), Anglo-Árabe (AA) y Cuarto de Milla de carreras.
- **Trote:** Trotón Francés, Standardbred y Trotón escandinavo/sueco.
- **Otra:** texto libre.

Debajo se indica el perfil de AVO Track Work que se aplicará:
- PSI y AQPS → `PSI`;
- PSA y AA → `ARABE`;
- trotones y Cuarto de Milla → `GENERICO`, con un aviso de que el análisis de galope no aplica al trote.

Se guarda como texto en `Breed`, compatible con Android y Windows; las razas escritas a mano se conservan.
**Archivos:** `ipad/AVOiPad/Core/TrackWork.swift`, `ipad/AVOiPad/Views/StableView.swift`, `ipad/AVOiPadTests/RacingBreedTests.swift`.
**Validación:** IMPLEMENTADO · NO VERIFICADO.

## 2026-11-01 — iPad 1.0.x — Biomecánica en la línea de tiempo del entrenamiento (zoom, tramo, desplazamiento, leyendas activables)
**Autor:** Claude · **Rama:** `feature/ipad-analisis-entreno` → `feature/ipad-app` · **Commits:** `0160099` · **CI:** iPad run 41356107914 ✅ (compilación, pruebas, todas las capturas) · TestFlight compilación 30
**Qué cambia (petición del usuario con captura):**
- Las gráficas de la cincha ya no usan una ventana local de 4 s: están en la **línea de tiempo compartida** (`charts.domain`), igual que Análisis y Gráficas.
  - Gráficas: |a|, ejes x/y/z, giro, movimiento sin gravedad, balanceo/cabeceo y cadencia.
  - Comparten cursor, zoom (pellizco y botones), selección de tramo («Guardar como tramo»), filtro por fase y barra de desplazamiento (`ChartsNavigator`).
- **Barra común `SyncZoomBar`:** seleccionar tramo, acercar y alejar, desplazar, restablecer, **«Ver ±2 s del cursor»** (la vista de detalle anterior), guardar o quitar tramo y reproducción.
- **Leyendas activables** en todas las gráficas de la cincha (`BiomechModel.legend`, que busca el nombre exacto de la serie).
- **Datos:** series de sesión completa (`SyncSource`) reducidas con LTTB a la ventana visible fuera del hilo principal (`BiomechModel.refreshPanels`); franjas de fases bajo cada gráfica.
**Validación:** IMPLEMENTADO · CI ✅ · NO VERIFICADO en el iPad.

---

## 2026-11-01 — iPad 1.0.x — Gráficas: líneas activables, barra de desplazamiento y filtro por fase; Listado: eliminar y exportar entrenamientos
**Autor:** Claude · **Rama:** `feature/ipad-analisis-entreno` → `feature/ipad-app` · **Commits:** `ed7d6fc` y siguientes · **CI:** iPad run 41349352965 ✅ (84 pruebas, todas las capturas)
**Qué cambia (peticiones del usuario con capturas del iPad):**
- **Gráficas:**
  - cada entrada de la leyenda es un interruptor que muestra u oculta su línea, la banda ±σ o los marcadores de su color (`SyncLegend.keys`, `sigma` y `marker`; `ChartsModel.hiddenLegend`; `ChartsLegends`);
  - **barra de vista general** (`ChartsOverviewBar`) con el perfil de velocidad, las fases, las repeticiones, el cursor y el **recuadro de la ventana visible, que se arrastra para desplazarse** con zoom o en sesiones largas. Sin zoom, al tocar se acerca a ¼ de la sesión;
  - **filtro por fase:** Completo, Calentamiento, Trabajo y Enfriamiento hacen zoom a la fase del motor.
- **Listado, «Eliminar entrenamiento…»:**
  - pide confirmación;
  - borra solo lo que guarda la app (copia de la biblioteca, RAW, análisis, resumen, correcciones, valoración, tramos, notas y favorito) y **nunca los archivos del usuario**;
  - `eliminados.json` evita que «Buscar entrenamientos perdidos» lo vuelva a importar; abrirlo a propósito lo importa otra vez.
- **Listado, «Exportar a AVO Horse»** (de uno o de todos los filtrados):
  - copia el **original verificado** (.avo o .avr, mismo SHA-256) en Archivos › En mi iPad › AVO Horse › **Exportados** con el nombre `AVO_<fecha_hora>_<caballo>`;
  - si ya estaba exportado, no lo duplica;
  - sirve para enviarlo por AirDrop o correo, o para pasarlo a otro iPad, a AVO Windows o a Android.
- **Pruebas:** borrar (lista, biblioteca, archivo del usuario intacto, marca de eliminado, reimportar) y exportar (mismo SHA-256, sin duplicar).
**Validación:** IMPLEMENTADO · CI ✅ · **NO VERIFICADO** en el iPad real.

---

## 2026-11-01 — iPad 1.0.x — líneas de salida y meta en el mapa, zonas arrastrables e integración en `feature/ipad-app`
**Autor:** Claude · **Rama:** `feature/ipad-analisis-entreno` → **`feature/ipad-app`** (avance rápido, sin cambios de otros autores desde `babaf8c`) · **Commits:** `78ed42c`, `d3b038d` · **CI:** iPad run 41343000760 ✅ (83 pruebas unitarias; capturas)
**Qué cambia:**
- **Mapa de Análisis:** líneas de salida (verde) y meta (roja) de las correcciones, con una bandera y el nombre, y una **flecha hacia el lado por el que cuenta el cruce**. Sin flecha si el sentido es AMBOS. Archivos: `MapCourseLine`, `CourseLineOverlay` y `CourseLabelAnnotation` en `MapKitRoute.swift`.
- **Perfil de velocidad:** **asas arrastrables** en los bordes de la fase de trabajo (fila baja) y de cada repetición (fila alta).
  - Al arrastrar, el cursor se mueve (el mapa sigue al caballo) y aparece la hora.
  - Al soltar, se guarda la corrección y el motor vuelve a analizar.
  - Archivos: `SyncHandle`, `SyncHandleLayer` y `CorrectionsModel.handles/moveHandle`.
  - Solo las asas reciben los toques; el resto de la gráfica mantiene el cursor, el rango y el zoom.
- **Prueba unitaria:** dirección de la flecha (DCHA_A_IZQ con A al oeste y B al este → norte) y sin flecha con AMBOS.
**Validación:** IMPLEMENTADO · CI ✅ · captura del simulador con las asas sobre las franjas · **NO VERIFICADO** en el iPad real.
**Pendiente:** Windows y Android.

---

## 2026-11-01 — iPad 1.0.x — navegación reorganizada y «Análisis» con zonas editables (+ motor: correcciones manuales)
**Autor:** Claude · **Rama:** `feature/ipad-analisis-entreno` (sale de `feature/ipad-app` `babaf8c` + `feature/avo-training-analytics`) · **Commits:** `008443c`, `3e5045f`, `4287548` · **CI:** iPad run 41338103300 ✅ (compilación, 83 pruebas unitarias, capturas; falla la captura de Inicio en horizontal, que no ha cambiado) · motor run 41337324883 ✅
**Qué cambia (petición del usuario con una foto de la pantalla):**
- **Barra lateral solo con páginas generales:** Inicio, Entrenamientos, Listado, Análisis, Carreras, Cuadra, Jinetes, Geocercas y líneas, Reloj Wi-Fi y Servidor AVO.
- **Barra del entrenamiento**, arriba en las páginas de un entrenamiento (`TrainingBar` en `RootView.swift`):
  - entrenamiento activo;
  - pestañas Análisis, Resumen, Gráficas, Tramos, GPS, Biomecánica, Comparar, Mareas, Informes y Motor;
  - Asignar.
  - `Page.isTrainingPage`; nueva página `.summary`, que es la antigua vista «Análisis del caballo».
- **«Análisis» = la foto:** es la antigua página Mapa.
  - Mapa y panel derecho con distancia, tiempo y velocidades, la nueva tarjeta **«Entrenamiento»** (fases, repeticiones y pasadas, que se seleccionan al tocarlas), la leyenda, los tramos y el punto seleccionado.
  - Perfil de velocidad con **franjas de zonas**: fases, repeticiones y pasadas (`SyncBand` con `lane` y `height`).
  - Barra de tiempo.
  - **Botones de zonas:** Salida aquí, Meta aquí, Inicio trabajo, Fin trabajo, Inicio/Fin repetición, Quitar repetición y Restablecer.
- **Correcciones:**
  - se guardan en `correcciones.json` (`CorrectionsModel`), en tiempo GPS absoluto (iTOW), sin tocar los datos;
  - cada cambio vuelve a analizar con el motor;
  - las líneas de salida y meta se calculan a 50 m a través del recorrido en el cursor, en el sentido del movimiento (`DCHA_A_IZQ`).
- **Raza:** el texto de la Cuadra (PSI, Pura sangre inglés, Árabe…) se pasa al motor como `raza` (`TrackWorkBreed`).
- **Motor:**
  - opciones `trabajos_manuales` y `fases_manuales` (iTOW);
  - trabajos `manual`, `fases.base` = `MANUAL` y `correcciones_manuales`;
  - el hash de parámetros incluye las correcciones;
  - prueba `pista.manual_corrections` (83 casos).
- **Swift:** `Core/TrackWork.swift` lee `trabajo_pista`; `EquineAnalysis.trackWork`.
- **Prueba de capturas:** navega por la barra lateral y por las pestañas (`tab.*`).
**Validación:**
- IMPLEMENTADO · CI ✅.
- Capturas del simulador iPad Pro 13" en horizontal y vertical (rama `ci/ipad-visual-evidence`).
- Prueba unitaria con la sesión DEMO del Regatón: 1 repetición manual de 30 s, fase MANUAL y recorrido con salida y meta.
- **NO VERIFICADO** en el iPad real.
**Pendiente:**
- Dibujar las líneas de salida y meta en el mapa.
- Mover las zonas arrastrándolas.
- Llevar lo mismo a Windows y Android.
- Integrar en `feature/ipad-app`.

---

## 2026-11-01 — Motor AVO Equine — Track Work: recorrido de entrenamiento con líneas de salida y meta (opcional)
**Autor:** Claude · **Rama:** `feature/avo-training-analytics` · **Commits:** `7a34604` · **CI:** run 41334018208 ✅ (Linux ASan/UBSan 82 casos/1157 comprobaciones, Windows MSVC, Android NDK ×3, JNI, fixtures)
**Por qué:** el usuario comparte su zona de entrenamiento (Playa del Regatón, Laredo), con la geocerca de grabación, el calentamiento, la salida, el trabajo, la meta y el enfriamiento.
- Aclara que es una **referencia aproximada que puede variar**.
- Aclara que **todos los datos salen del chaleco GPS RTK y de la cincha BNO085**.
- Por eso el recorrido es **opcional**: sin líneas sigue la detección por velocidad y cincha.
**Qué cambia:**
- **Opciones** `recorrido` (líneas `salida`, `meta` o `salida_meta` con sentido, y `geocerca`) o `plan_geocercas` (el `geocercas.json` de Windows/iPad: `Lines` con `Role` y `Direction`, y `Fences` de tipo polígono).
- **Cruces:** misma geometría que el reloj y AVO Windows, con el instante interpolado.
- **Pasadas** SALIDA → META con el mismo análisis que los trabajos. La SALIDA cruzada al revés anula la salida pendiente; así el calentamiento que pasa la línea hacia atrás no crea pasadas falsas.
- **Fases** por líneas (`fases.base` = `LINEAS`).
- **Geocerca:** porcentaje de épocas dentro y aviso.
- **Parciales:** último tramo hasta la línea.
- **Hash de parámetros** con el recorrido.
- **Historia:** `RECORRIDO.mejor_pasada_s` y `RECORRIDO.v_media_mejor`.
- **Refactorización:** el cálculo de un trabajo se hace en una sola función (`fill_effort`) para trabajos y pasadas.
- **Fixtures** regeneradas.
**Validación:**
- IMPLEMENTADO. 82 casos y 1157 comprobaciones con ASan/UBSan, y en Release.
- **Recorrido sintético como el del dibujo:** calentamiento hacia atrás pasando la salida, giro, galope de 1200 m, enfriamiento pasando la meta y vuelta cruzando la meta al revés.
  - 1 pasada de 75,08 s (real 75,08 s).
  - Recuperación de 15,8 s (real 15,83 s).
  - Igual con sentido AMBOS.
  - Con las líneas en el sentido equivocado no aparecen pasadas.
  - Con una geocerca menor, avisa.
  - También a través de la API C con un `geocercas.json` de Windows.
- **NO VERIFICADO** con datos reales.
**Pendiente:** que las apps pasen su `geocercas.json` al motor.

---

## 2026-11-01 — Motor AVO Equine — AVO Track Work 1.0.0: el módulo de «carreras» pasa a ser de ENTRENAMIENTO (fases, series, recuperación)
**Autor:** Claude · **Rama:** `feature/avo-training-analytics` · **Commits:** `ef704d8` · **CI:** run 41330093878 ✅ (Linux ASan/UBSan 79 casos/1103 comprobaciones, Windows MSVC, Android NDK ×3, JNI, fixtures)
**Por qué:** el usuario aclara que el objetivo es analizar los **entrenamientos** de caballos de carreras PSI y árabes, no las carreras. Esta entrada corrige el enfoque de la anterior («AVO Racing 1.0.0»).
**Qué cambia:**
- **Nombres:**
  - bloque JSON `carreras` → **`trabajo_pista`** (con `modulo` = `AVO_TRACK_WORK`);
  - `procedencia.algoritmos.carreras` → `trabajo_pista`;
  - métricas de la historia `CARRERA.*` → **`TRABAJO.*`**;
  - resumen de sesión `carreras` → `trabajo_pista`;
  - ficha `13_CARRERAS.md` → **`13_TRABAJO_PISTA.md`**.
  - El código interno se sigue llamando `racing`.
  - Ninguna app leía todavía estos nombres.
- **Nuevo: estructura del entrenamiento (`SESSION_PHASES_V1`):**
  - fases de calentamiento, trabajo y vuelta a la calma, con duración, distancia y tiempo por aire;
  - por trabajo: **recuperación hasta el paso** y **pausa hasta la siguiente repetición**, con su velocidad;
  - **series:** repeticiones y rápidas, **caída de la máxima y de la zancada** entre la primera y la última repetición rápida, y recuperación media;
  - aviso de **calentamiento corto** (menos de 10 min antes del primer trabajo rápido; valor de partida).
- **Historia:**
  - el resumen guarda `trabajo_pista.sesion`;
  - métricas informativas `TRABAJO.recuperacion_hasta_paso_s`, `TRABAJO.caida_entre_series_pct` y `TRABAJO.calentamiento_s`;
  - el calentamiento corto aparece como motivo.
- **Fixtures** regeneradas.
**Validación:**
- IMPLEMENTADO.
- 79 casos y 1103 comprobaciones con ASan/UBSan.
- Nueva prueba `pista.training_morning_structure`: mañana sintética con calentamiento de 4 min, 2 repeticiones a 16 y 15 m/s con paseo entre ellas y vuelta a la calma.
  - Caída 6,24 % (real 6,25 %).
  - Recuperación 6,5 s (real 6,1 s).
  - Pausa y fases correctas.
- **NO VERIFICADO** con caballos reales.

---

## 2026-11-01 — Motor AVO Equine — AVO Racing 1.0.0 (caballos de carreras PSI y árabe)
**Autor:** Claude · **Rama:** `feature/avo-training-analytics` · **Commits:** `3631bd9` · **CI:** run 41328572986 ✅ (Linux ASan/UBSan 78 casos/1086 comprobaciones, Windows MSVC 78 casos, Android NDK ×3, JNI en JVM, fixtures)
**Qué cambia (petición del usuario: «añadir todo lo posible a los caballos de carreras PSI y árabes»):**
- **Nuevo módulo** `src/racing/` + `include/avo_eq/racing.h`. Añade el bloque `carreras` al análisis y lo documenta la ficha 13.
- **Perfiles de raza** `GENERICO` / `PSI` / `ARABE`: velocidades de trabajo, rápida y alta, velocidades de referencia y rangos de zancada.
- **Cincha en el marco del caballo:**
  - escala BNO085 (byte 15 = 1) o por gravedad;
  - vertical por gravedad y eje de avance por PCA, con el sentido confirmado por la inclinación frente a la aceleración GNSS;
  - **VeDBA** y carga de la cincha;
  - **giros a cada mano** (tiempo y grados, por aire);
  - saturación.
- **Zancadas en galope:**
  - frecuencia y longitud (con la velocidad GNSS);
  - pico vertical y desplazamiento vertical del tronco;
  - rasgo lateral.
- **Mano de galope** (experimental): el rasgo lateral es especular entre manos. Se autocalibra en curvas o se fija con `signo_mano`. Da los cambios de mano y el porcentaje de mano de fuera en curva.
- **Trabajos (GNSS):**
  - galope de trabajo o trabajo rápido;
  - parciales cada 200 m o cada furlong (`parcial_m`);
  - mejores 200–1600 m;
  - máxima y tiempo hasta ella, distancia por encima del 90 %;
  - últimos 200/400 m e **índice de caída**;
  - zancada a la máxima, rectas frecuencia/longitud–velocidad y **zancada a las velocidades de referencia**.
- **Eventos** (experimentales): impacto atípico, movimiento lateral brusco y saturación.
- **Ingesta:** `Session::imu_units` (byte 15 de la cabecera IMU) y recuento de lotes fusionados (formato 1).
- **Historia de entrenamientos:**
  - el resumen guarda el bloque `carreras`;
  - la distancia a alta velocidad usa el umbral de la raza;
  - carga VeDBA con ACWR;
  - líneas base y tendencias `CARRERA.*` y `CINCHA.*`;
  - las métricas se definen en una sola tabla (`metric_specs`).
- **Opciones de la API** (`avo_eq_analyse_ex`): `raza`, `parcial_m` y `signo_mano`. El hash de parámetros y `procedencia.algoritmos.carreras` invalidan la caché.
- **Fixtures** `core/src/test/resources/equine/*_analysis.json` regeneradas: añaden el bloque `carreras` y cambia el hash de parámetros.
**Archivos:** `equine-intelligence/{include/avo_eq/racing.h,src/racing/racing.cpp,include/avo_eq/{types,engine,training,avo_eq_c}.h,src/core/engine.cpp,src/capi/capi.cpp,src/ingestion/ingestion.cpp,src/training/training.cpp,tests/test_racing.cpp,tests/test_training.cpp,README.md,docs/FORMATO_RESULTADOS.md,docs/algoritmos/{12_ENTRENAMIENTO,13_CARRERAS}.md}`, fixtures.
**Validación:**
- IMPLEMENTADO.
- Linux: 78 casos y 1086 comprobaciones con ASan/UBSan, y en Release.
- Sesión sintética con física conocida (cincha girada 170°/35°, curvas y cambios de mano):
  - máxima 17,04 m/s;
  - frecuencia 2,451 Hz (real 2,43) y longitud 6,95 m (real 7,0);
  - mano 100 % en curvas y 2 de 2 cambios;
  - giros de 71° y 85° (reales 73° y 86°).
- **NO VERIFICADO** con caballos reales.
**Pendiente:**
- Validar la mano con vídeo.
- Ajustar los perfiles PSI y árabe con sesiones reales.
- Usar los lotes fusionados (cuaternión) del BNO085.
- Rango de ±16 g para impactos fuertes.
- Pantallas en las apps.

---

## 2026-11-01 — iPad 1.0.x — AVO Training Analytics 1.0.0 en la app: valoración del entrenador, «Historia del caballo» y forma antes de la carrera
**Autor:** Claude · **Rama:** `feature/ipad-app` (sobre `18e647e`) · **Commits:** pendiente · **CI:** pendiente
**Qué cambia:**
- **Envoltorios Swift** (`Engine/EquineEngine.swift`): `trainingSummary(analysisJson:extraJson:)` (síncrono) y `trainingAnalyse(inputJson:optionsJson:)` (async, cancelable con la bandera nativa, más `trainingAnalyseSync`), mismos códigos y `{"error"}` que `analyseJson`.
- **Modelos** (`Core/TrainingAnalytics.swift`): «avo-training-session» y «avo-training-analysis» con decodificación tolerante (claves ausentes, `null` o tipos erróneos → nil): carga (externa, sRPE, aguda, crónica semanal, ACWR, monotonía, tensión), desvíos con z y VIGILAR/REVISAR (solo el sentido malo se marca; la velocidad es informativa), líneas base, tendencias SUBE/BAJA/ESTABLE y estado NORMAL/VIGILAR/REVISAR con motivos. `TrainingRating` + `valoraciones.json`.
- **Resumen por sesión** (`App/AppModel+Training.swift`, `runEngine`): tras cada análisis se guarda `paths.analysis/<id>/training_summary.json` con extra `{"id","caballo" (código de la Cuadra o nombre),"jinete","fecha_utc" (inicio de la sesión, ISO UTC),"valoracion","pista"}`; se regenera al cambiar la valoración. Si falta el resumen, la historia lo genera reutilizando el resultado guardado del motor.
- **Análisis:** tarjeta «Valoración del entrenador» (RPE 1–10, estado BIEN/CANSADO/RARO/COJERA, pista superficie/estado, nota) guardada en `paths.root/valoraciones.json` por id de sesión. El nombre del caballo de la cabecera abre su historia.
- **«Historia del caballo»** (`App/HorseHistoryModel.swift`, `Views/HorseHistoryView.swift`, pantalla completa desde RootView): botón «Historia de entrenamientos» en la ficha del caballo (Cuadra) y desde Análisis. Estado con motivos («orientativo, no es un diagnóstico veterinario»), carga por día/semana apilada por aire + alta velocidad con aguda 7 d / crónica 28 d, ACWR con la banda, sRPE, monotonía/tensión, última sesión frente a su línea base, tendencias de 8 semanas y lista de sesiones (abre la sesión en Análisis). Excluye DEMO salvo caballo DEMO.
- **Carreras:** bloque «Forma antes de la carrera» en la ficha (`fecha_referencia` = día de la carrera): estado, ACWR, monotonía y tendencias; se añade a las observaciones si es VIGILAR/REVISAR o el ACWR sale de la banda.
- **Pruebas** `AVOiPadTests/TrainingAnalyticsTests.swift`: API C real con resúmenes sintéticos (ACWR ≈ 1 con carga estable, línea base con ≥ 4 sesiones, z ≥ 2 → VIGILAR, z ≥ 3 → REVISAR, COJERA y sRPE, errores y cancelación, valoraciones tolerantes).
**Archivos:** `ipad/AVOiPad/Engine/EquineEngine.swift`, `ipad/AVOiPad/Core/{TrainingAnalytics,RaceAnalysis}.swift`, `ipad/AVOiPad/App/{AppModel,AppModel+Shell,AppModel+Training,HorseHistoryModel,RacesModel,RootView}.swift`, `ipad/AVOiPad/Views/{HorseHistoryView,TrainingRatingCard,AnalysisView,SharedShellComponents,StableView,RaceDetailView}.swift`, `ipad/AVOiPadTests/TrainingAnalyticsTests.swift`.
**No se ha tocado:** motor C++ (`equine-intelligence/`), importación, reloj, capturas (la historia no es una página del menú).
**Validación:** IMPLEMENTADO · sin compilador Swift en la sesión (CI macOS pendiente) · **NO VERIFICADO** en iPad ni con sesiones reales.
**Pendiente:** compilar en CI y pasar `TrainingAnalyticsTests`; probar en iPad con la historia real de un caballo; ajustar factores de carga y umbrales con el entrenador; la primera apertura de la historia puede tardar si hay muchas sesiones sin resumen (se generan una a una con el resultado guardado del motor).

---

## 2026-11-01 — iPad 1.0.x — «Carreras»: PDF de tracking de France Galop / McLloyd y análisis frente a los entrenamientos
**Autor:** Claude · **Rama:** `feature/ipad-app` · **Commits:** pendiente · **CI:** pendiente
**Qué cambia (petición del entrenador):**
- **Nueva página «Carreras»** (`Page.races` = "Races", menú tras «Listado», icono `flag.checkered`, `App/RacesModel.swift`, `Views/RacesView.swift`): lista con fecha, hipódromo, carrera, distancia, caballo, puesto/participantes, tiempo y diferencia con el ganador; filtros por caballo y fechas; botón **«Añadir carrera»** (selector de PDF).
- **Ficha del caballo (Cuadra):** tarjeta «Carreras de …» con **«Añadir carrera»** y la lista de sus carreras (al tocar, se abre la ficha de la carrera).
- **Lectura del PDF «Statistiques Tracking»** (`Core/RaceTrackingParser.swift`, PDFKit): cabecera (hipódromo, categoría, carrera, distancia, fecha y «Redk du 1er»), resumen (número, cuerda, tiempo oficial, últimos 600 m, «Parcouru vs. 1er») y una página por caballo (jockey, puesto, tiempo y redk, tramo más rápido, velocidad máxima y media; por tramo de 200 m: tiempo acumulado, tiempo del tramo, velocidad media, foulées). Acepta texto con un valor por línea o con etiqueta y valores en la misma línea. Las posiciones por tramo se calculan ordenando los tiempos acumulados (el texto del gráfico de posiciones del PDF no tiene un orden fiable); coinciden con el PDF en la muestra. Zancada = longitud del tramo / foulées (primer tramo = distancia − resto). Otro PDF: «Formato de carrera no reconocido».
- **Caballo:** se busca por nombre normalizado y prefijo de palabras (Zakyna ⊂ ZAKYNA AL ZARAYAN). Desde la ficha del caballo se guarda directamente si hay una sola coincidencia; si no, o desde «Carreras», hoja «Añadir carrera» para confirmar caballo de la Cuadra y participante (preseleccionada la mejor coincidencia).
- **Guardado:** `carreras.json` en la carpeta de la app (escritura atómica) + copia del PDF en `carreras/`.
- **Ficha de la carrera** (`Views/RaceDetailView.swift`): cabecera, resultado (puesto, tiempo oficial, distancia al ganador en s y cuerpos con 1 cuerpo ≈ 0,2 s), tabla completa transcrita (nuestro caballo resaltado), tabla por tramos de cualquier participante, gráficas (velocidad por tramo frente a ganador y mediana del campo, posición en carrera, foulées y zancada, distancia al primero), notas, compartir el PDF y eliminar.
- **«Análisis según los entrenamientos»** (`Core/RaceAnalysis.swift`, funciones puras): caída en el final (último tramo / mejor tramo anterior) frente a la mediana del campo, segundos perdidos en el final, por terreno de más y en la salida; entrenamientos del caballo anteriores al día de la carrera (mejor 200/400/600 m sostenido con ventana por distancia y velocidad filtrada, trabajos > 40 km/h ≥ 200 m, caída en trabajos ≥ 400 m, tendencia de los 3 últimos); tiempo corregido y puesto estimado («habría ganado N posiciones» / «no habría cambiado el puesto: le faltaron X s para el N.º»), «Hemos optimizado N posiciones» cuando el caballo terminó mejor de lo que indicaba su perfil, nivel de confianza (Alta/Media/Baja), observaciones concretas y nota de método. Se comparan proporciones, no velocidades absolutas.
- **Capturas (CI):** en modo captura se importa la carrera de muestra incluida en la app (`Resources/demo_race_20261029BOU03.pdf`) enlazada al caballo DEMO «Rayo (demo)» como Zakyna, marcada DEMOSTRACIÓN; `ScreenshotTests` incluye "Races".
**Archivos:** `ipad/AVOiPad/Core/{RaceModels,RaceTrackingParser,RaceAnalysis}.swift`, `ipad/AVOiPad/App/{RacesModel,AppModel,AppModel+Shell,RootView}.swift`, `ipad/AVOiPad/Views/{RacesView,RaceDetailView,SharedRaceImport,StableView}.swift`, `ipad/AVOiPad/Resources/demo_race_20261029BOU03.pdf`, `ipad/AVOiPadTests/RaceParserTests.swift`, `ipad/AVOiPadTests/Fixtures/20261029BOU03_last_times_fr.pdf`, `ipad/AVOiPadUITests/ScreenshotTests.swift`, `ipad/UI_CONTRACT.md`.
**No se ha tocado:** núcleo de entrenamientos (`SessionTimeline`, importación .avo/.avr), motor, reloj Wi‑Fi/BLE, resto de páginas.
**Validación:** IMPLEMENTADO · sin compilar en la sesión (CI macOS pendiente) · el algoritmo de lectura se comprobó fuera de Swift con `pdftotext` (texto simple y con maquetación) sobre la muestra · **NO VERIFICADO** en iPad ni con el texto real que devuelve PDFKit.
**Pendiente:** compilar en CI y pasar `RaceParserTests`; comprobar con PDFKit en iPad que el orden del texto es el esperado; probar con más PDF de France Galop (otras distancias, no clasificados, empates); validar con el entrenador la referencia de caída y el umbral de 40 km/h.

---

## 2026-11-01 — iPad 1.0.x — página «Listado de entrenamientos» y búsqueda de entrenamientos perdidos
**Autor:** Claude · **Rama:** `feature/ipad-app` · **Commits:** pendiente · **CI:** pendiente
**Qué cambia (petición del entrenador):**
- **Nueva página «Listado»** (`Page.trainingList` = "List", menú tras «Entrenamientos», `App/TrainingListModel.swift`, `Views/TrainingListView.swift`): tabla densa a todo el ancho (`Table` ordenable en ancho regular, lista de filas en ancho compacto) con Fecha y hora, Caballo, Jinete, Modalidad, Duración, Distancia, Vel. máx., Cincha, Geocercas visitadas, Origen (Archivo / Wi-Fi / Bluetooth / Demo / Recuperado, leído del `source` del manifiesto .avo), Estado del motor y favorito. Tocar una fila la selecciona (entrenamiento activo); el botón «Abrir» de la fila o el menú contextual la abre en Análisis. Cabecera «N entrenamientos · X km · HH:MM total» del conjunto filtrado.
- **Filtros** (guardados en UserDefaults): texto, caballo y jinete (sesiones + Cuadra/Jinetes), modalidad, fecha desde/hasta (días de Europe/Madrid) con atajos Hoy / 7 días / 30 días / Todo, geocerca (las definidas en `geocercas.json`; un entrenamiento coincide si algún punto del recorrido cae dentro: círculo por haversine, polígono por punto en polígono; se calcula una vez por sesión fuera del hilo principal y se guarda en caché hasta que cambien las geocercas), solo con cincha, solo favoritos, ocultar DEMO y «Limpiar filtros».
- **«Buscar entrenamientos perdidos»:** recorre fuera del hilo principal Documents (Archivos › En mi iPad › AVO Horse), Documents/Inbox, tmp, Library/Caches, Application Support y la carpeta de la app (biblioteca, caché RAW, `reloj/descargas`). Toma .avo, .avr y carpetas de segmentos P00n.avr; descarta por SHA-256 del archivo, SHA-256 de segmentos o ID de sesión lo que ya está cargado; las carpetas completas se empaquetan como .avo (`AvoPackageWriter`, `source: recuperado-ipad`, en `reloj/recuperados`) y las que tienen `.wifi_etag`/`.ble_sizes` o huecos se informan como incompletas; .part/.tmp como interrumpidas. Lo nuevo se importa con `app.importFiles`. Hoja de resultado «N archivos revisados · M recuperados · K duplicados · J incompletos/dañados» con la lista y el motivo. «Buscar en una carpeta…»: carpeta de Archivos con acceso de seguridad, profundidad 6 y máximo 2000 archivos (los archivos se copian a `entrada` antes de importar).
- Estado vacío «No hay entrenamientos en el iPad» con Abrir / Reloj Wi-Fi / Buscar perdidos.
- `Info.plist`: `LSSupportsOpeningDocumentsInPlace = true`; al arrancar se crea `Documents/Entrenamientos` para que la carpeta de la app aparezca en Archivos.
**Archivos:** `ipad/AVOiPad/App/{TrainingListModel,AppModel,AppModel+Shell,RootView}.swift`, `ipad/AVOiPad/Views/TrainingListView.swift`, `ipad/AVOiPad/Resources/Info.plist`, `ipad/AVOiPadTests/TrainingListTests.swift`, `ipad/AVOiPadUITests/ScreenshotTests.swift`, `ipad/UI_CONTRACT.md`.
**No se ha tocado:** núcleo (`Core/`, `Engine/`), importación (`importFiles`), descarga Wi-Fi/BLE del reloj, resto de páginas.
**Validación:** IMPLEMENTADO · sin compilar en la sesión (CI macOS pendiente) · NO VERIFICADO en iPad.
**Pendiente:** compilar en CI; probar en iPad la tabla (columnas, orden, selección), el doble toque (no implementado: se abre con el botón de la fila o el menú contextual) y la búsqueda con archivos reales en Archivos.
## 2026-11-01 — Motor AVO Equine — AVO Training Analytics 1.0.0 (análisis de la historia de entrenamientos, fase 1)
**Autor:** Claude · **Rama:** `feature/avo-training-analytics` (sale de `feature/ipad-app` `33476df`) · **Commits:** `78893e4`, `d1edc03`, `6816a98` · **CI:** run 41315952401 ✅ (Linux ASan/UBSan 71 casos/1020 comprobaciones, Windows MSVC 71 casos, Android NDK ×3, JNI en JVM, fixtures, resumen → historia) sobre `6816a98`
**Qué cambia (petición del usuario: analizar los entrenamientos para Android, Windows e iOS):**
- **Nuevo módulo del motor C++** `src/training/` + `include/avo_eq/training.h`. Es una sola implementación para
  las tres plataformas: Android (JNI), Windows (DLL) e iPad (compila `equine-intelligence/src` entero).
- **Resumen por sesión** (`avo-training-session`):
  - tiempo y distancia por aire;
  - velocidad, tranco, cadencia y regularidad;
  - distancia a alta velocidad;
  - aceleraciones de la trayectoria GNSS;
  - calidad, valoración del entrenador (RPE, estado, nota) y pista.
- **Historia del caballo** (`avo-training-analysis`):
  - carga externa por aires (heurística `AVO_TRAINING_LOAD_V1`, configurable) y carga sRPE;
  - carga aguda 7 d, crónica 28 d, ACWR, monotonía y tensión;
  - línea base propia (mediana y MAD de 60 d, mínimo 4 sesiones) y desvíos z robustos;
  - tendencias Theil-Sen por semana;
  - estado NORMAL / VIGILAR / REVISAR con motivos. No es un diagnóstico.
- **API C:** `avo_eq_training_summary` y `avo_eq_training_analyse`, con cancelación y los mismos códigos.
- **CLI:** `avo_training_cli`.
- **Análisis de sesión:** añade `sesion.inicio_utc` (primera época GNSS con fecha y hora UTC). Fixtures
  `core/src/test/resources/equine/*_analysis.json` regeneradas (solo cambia esa clave).
- **CI:** `build-equine-engine.yml` se lanza también en esta rama y ejecuta resumen → historia con la fixture.
- `tests/test_fusion.cpp`: falta `#include <algorithm>` (rompía la compilación con el GCC nuevo del runner, run 41314987063).
- `tests/test_dsp.cpp`: `normal_distribution` con desviación 0 abortaba con las aserciones de GCC 15 (run 41315372137); se construye con 1 cuando no hay ruido (no se usa).
**Archivos:** `equine-intelligence/{include/avo_eq/training.h,include/avo_eq/avo_eq_c.h,src/training/training.cpp,src/capi/training_capi.cpp,src/core/engine.cpp,tools/training/avo_training_cli.cpp,tests/test_training.cpp,CMakeLists.txt,README.md,docs/FORMATO_RESULTADOS.md,docs/algoritmos/12_ENTRENAMIENTO.md}`, `core/src/test/resources/equine/{synthetic,sample}_analysis.json`, `.github/workflows/build-equine-engine.yml`.
**No se ha tocado:** el resto de algoritmos del motor, las apps Android, Windows e iPad (sin pantallas todavía) y el firmware.
**Validación:** IMPLEMENTADO · compilado y probado en Linux (71 casos, 1020 comprobaciones, ASan/UBSan) · CI run 41315952401 en verde · **NO VERIFICADO** con sesiones reales. Los factores de carga y los umbrales son valores de partida.
**Pendiente:**
- Integrar en las apps: JNI/Kotlin, P/Invoke/C# y Swift.
- Pantalla «Entrenamientos del caballo» y formulario de valoración tras cada sesión.
- Ajustar umbrales con datos reales.
- Fases 2 (etiquetas) y 3 (modelos).

---

## 2026-11-01 — iPad 1.0.x — página GPS, Análisis centrado en el caballo, Comparar rediseñado
**Autor:** Claude · **Rama:** `feature/ipad-app` · **Commits:** pendiente · **CI:** pendiente
**Qué cambia (petición del usuario tras revisar la app en su iPad):**
- **Nueva página «GPS»** (`Page.gps`, menú tras «Mapa», `App/GpsModel.swift`, `Views/GpsView.swift`): todos los datos GNSS/RTK del chaleco sin mapa (distribución de soluciones y franja temporal, satélites, hAcc mediana/p95, precisión de velocidad, pérdidas de señal, saltos descartados, frecuencia, épocas, altitud MSL, velocidad reportada frente a derivada, receptor y sensores, nota de la antena del chaleco).
- **GNSS fuera del resto de páginas:** Análisis, Mapa (sin modo «Calidad GNSS» ni tarjeta GNSS/RTK), Tramos (sin fila RTK FIX ni observaciones GNSS), Comparar, Motor (sin dominio GNSS ni eventos GNSS), Entrenamientos, Cuadra, pie de página, Biomecánica y Mareas. En Informes la opción pasa a «Datos GPS», desactivada por defecto. Las exportaciones CSV/Core no cambian.
- **Análisis centrado en el caballo:** caballo · jinete · modalidad a la derecha del título; sección «Análisis del caballo» (aires del motor, zonas de velocidad, esfuerzo, aceleraciones/frenadas validadas, curvas, marcha de la cincha) solo con datos medidos; el mosaico de altitud pasa a «Esfuerzo · tiempo en movimiento».
- **Inicio sin menú lateral** (botón «Menú» arriba a la izquierda); accesos «Entrenamientos» y «Análisis» en Inicio.
- **Comparar:** columna derecha con un único desplazamiento vertical (recorridos, velocidad, aceleración, IMU cincha → desvíos laterales e inclinaciones, cadencia del motor, estadísticas y motor al final); `Views/CompareImuSeries.swift`.
- Diagrama de la cincha: las etiquetas ya no se cortan en el borde.
**Archivos:** `ipad/AVOiPad/App/{GpsModel,AppModel,AppModel+Shell,RootView,MapModel,SegmentsModel,ReportsModel,CompareModel,BiomechModel}.swift`, `ipad/AVOiPad/Views/{GpsView,CompareImuSeries,AnalysisView,MapPageView,SegmentsView,CompareView,EngineView,HomeView,StableView,StartView,ReportsView,BiomechView,HorseDiagramView,TidesView,SharedShellComponents}.swift`, `ipad/AVOiPadUITests/ScreenshotTests.swift`.
**No se ha tocado:** núcleo (`Core/`, `Engine/`), Gráficas, Reloj Wi‑Fi/BLE.
**Validación:** IMPLEMENTADO · sin compilar en la sesión (CI macOS pendiente) · NO VERIFICADO en iPad.

---

## 2026-11-01 — iPad 1.0.0 — duplicado de la app Windows V2 PRO para iPad Pro M4 (SwiftUI nativo)
**Autor:** Claude · **Rama:** `feature/ipad-app` (sale de `feature/windows-girth-movimiento` `8101304`)
**Qué cambia:**
- **Nueva app `ipad/`**, nativa en SwiftUI para iPadOS 17 o posterior, con las 16 pantallas de Windows: Inicio, Entrenamientos, Cuadra, Jinetes, Análisis, Mapa (Esri satélite/híbrido con caché, o vectorial sin conexión, más reproducción), Gráficas sincronizadas, Tramos, Biomecánica, Comparar, Geocercas y líneas, Mareas y entorno, Informes, Servidor y Motor, además de la hoja Asignar.
- **Núcleo portado de `AVO.Windows.Core` a Swift** con los mismos formatos y cálculos:
  - lectura de `.avo` y `.avr` con SHA-256 y lector ZIP propio;
  - filtro Kalman con suavizado RTS, tramos, comparador, entorno IHM y Open-Meteo;
  - informes PDF (escritor propio), HTML, CSV, GPX y JSON;
  - `cuadra.json`, `geocercas.json` y `recortes.json`, intercambiables con Windows.
- **Motor C++ AVO Equine:** el mismo código fuente compilado dentro de la app, con su API en C.
- **Reloj:**
  - protocolo BLE portado de Windows/Android, con la clave en el llavero de iOS;
  - envío y lectura de geocercas;
  - **descarga por Wi‑Fi** (`WIFI_SYNC` + HTTP, pecho ≥ 3.7.4) en lugar del USB.
- **Sin NFC:** el iPad no tiene NFC.
- **CI `build-avo-ipad.yml` (macOS):**
  - sesiones DEMO, XcodeGen y compilación;
  - XCTest en el simulador del iPad Pro 13" (M4);
  - capturas en horizontal y vertical en `ci/ipad-visual-evidence`;
  - subida a TestFlight cuando están los secretos `APPLE_TEAM_ID`, `ASC_KEY_ID`, `ASC_ISSUER_ID` y `ASC_KEY_P8_BASE64` (ver `ipad/README.md`).
**Por qué:** usar la app de análisis en el iPad Pro M4.
**Archivos:** `ipad/**`, `.github/workflows/build-avo-ipad.yml`.
**No se ha tocado:** `windows/`, Android, firmware y motor (solo se compilan).
**Validación:** COMPILADO / CI run 41297030454 (`commit` de la rama): compilación, 51 pruebas unitarias en verde (formatos, seguridad, algoritmos, vectores del reloj, Wi‑Fi simulado, motor, sesiones DEMO) y 32 capturas. **NO VERIFICADO** en un iPad real, con el reloj por Bluetooth o Wi‑Fi, ni con sesiones reales.
**TestFlight:** compilación 1.0.0 (8) firmada con Xcode 26.6 y subida a App Store Connect (`org.avoperformance.horse.ipad`, equipo 4J2D6P5BJX), run 41307176561, 01/11/2026 13:40.
**Pendiente:** probar en el iPad, probar la descarga Wi‑Fi con un pecho 3.7.4 o posterior, e integrar en develop.

## 2026-10-31 — Windows V2 PRO — geocercas, líneas de salida y meta con sentido, y envío al reloj por Bluetooth
**Autor:** Claude · **Rama:** `feature/windows-advanced-analysis`
**Qué cambia:**
- **Página «Geocercas y líneas»:** mapa editable por clic con los 8 huecos de geocerca del reloj (círculo de 5 m a 5 km o polígono de hasta 24 vértices, activa o no) y sus 4 líneas virtuales (extremos A y B, uso salida y meta, salida, meta o control, y sentido que marca).
  - Las validaciones son las de `validate_fence()`.
  - Los cruces del entrenamiento abierto aparecen con su sentido y con «Marca» o «No marca», junto con las vueltas y los tiempos de salida a meta.
  - «Crear tramos» convierte esos tiempos en tramos.
- **Enviar al reloj / Leer del reloj** por Bluetooth del PC (WinRT), con el **mismo protocolo y formato que la app Android** (portado de `BleProtocol.kt`, `AvoClient.kt`, `WatchConfig.kt` y `Fence.kt`):
  - emparejamiento sin código y autorización del PC con BOOT, la misma reclamación de Android;
  - clave guardada con DPAPI por usuario;
  - `SET_FENCE` por hueco, `SET_ACTIVE_FENCES` y `SET_CONFIG` leer-modificar-escribir solo para las líneas;
  - comprobación final con `GET_CONFIG`.
  - Antes de enviar se confirma la lista de cambios. Solo se envía lo que cambia y se conservan la identidad y las secciones desconocidas.
**Limitación del reloj (no se ha tocado el firmware):** el pecho cuenta los cruces de las líneas en los dos sentidos.
- `VirtualLine` no tiene campo de sentido y `crosses()` es simétrico.
- El sentido se guarda en el PC y se aplica al analizar el entrenamiento.
- La línea 1 es la que el reloj usa para cronometrar vueltas.
- Para que el reloj marque solo en un sentido habría que ampliar el firmware: un byte de sentido al final de la sección de línea, que el formato permite.
**Archivos:**
- `windows/AVO.Windows.Core/Watch/{AvoBle.cs,AvoConfig.cs,Geofences.cs}`, `windows/AVO.Windows/Ble/WinBle.cs`;
- `ViewModels/MainViewModel.Geofences.cs`, `Views/GeofencesView.*`, `Controls/MapControl.cs` (formas y clic);
- csproj: TFM `net10.0-windows10.0.19041.0` y DPAPI;
- `windows/tools/watch-vectors/`, `AVO.Windows.SelfTest/{WatchTests.cs,watch_vectors.json}`.
**Validación:**
- IMPLEMENTADO.
- Las autopruebas comprueban la configuración, las geocercas, los fragmentos BLE, las pruebas HMAC y el test de cruce **byte a byte contra el código real del firmware**.
- Flujo completo (autorización con BOOT, envío, verificación y rechazo sin autorización) contra un reloj simulado.
- **NO VERIFICADO con el reloj ni con Bluetooth real.**

## 2026-10-31 — Windows V2 PRO — pantalla de inicio: logo y letras nítidos (vectoriales)
**Autor:** Claude · **Rama:** `feature/windows-advanced-analysis`
**Qué cambia:**
- **Antes:** la foto de inicio (recorte ampliado ×3 de CONCEPTO_02) llevaba la cabeza de caballo y los textos incrustados y borrosos.
- **Foto:** se han borrado de ella con *inpainting* (OpenCV); la escena no cambia.
- **Cabeza de caballo:** trazada desde el original como contornos de grosor variable.
- **«AVO»:** reconstruido geométricamente con las medidas del original.
- **Textos:** PERFORMANCE HORSE, TRAINING ANALYSIS y CIENCIA · TECNOLOGÍA · RENDIMIENTO pasan a contornos de Montserrat (OFL), con el interletrado ajustado al ancho original.
- **Resultado:** todo se dibuja en vectores sobre la foto (`Views/HeroArt.xaml`), así que se ve nítido a cualquier tamaño y escala.
**Por qué:** lo pidió el usuario. Las letras y la cabeza del caballo se veían borrosas en el PC.
**Archivos:** `windows/AVO.Windows/{Views/HeroArt.xaml(.cs),Views/StartView.xaml,Assets/avo_home_hero.jpg}`, `windows/tools/hero-art/`.
**Validación:** IMPLEMENTADO · capturas del CI.

## 2026-10-31 — Windows V2 PRO — Cuadra, Jinetes, asignación de entrenamientos y lector NFC USB
**Autor:** Claude · **Rama:** `feature/windows-advanced-analysis` · **Commits:** ver `git log`
**Qué cambia:**
- **Cuadra y Jinetes:** páginas nuevas en el menú lateral.
  - Fichas con los campos de Android (`HorseEntity`/`RiderEntity`).
  - Cada ficha muestra sus entrenamientos, totales (entrenamientos, km, tiempo, velocidad máxima, último) y la etiqueta NFC asociada.
  - Los caballos y jinetes que traen los archivos importados se dan de alta solos: por código, o por nombre si no hay código. Los de demostración quedan marcados DEMO.
- **Asignar caballo y jinete** a un entrenamiento, desde la cabecera, la lista de entrenamientos o la ficha.
  - Si se escribe un nombre nuevo, se crea su ficha.
  - Opción para rellenar lo que falte en los demás entrenamientos.
  - Botón «Asignar a los N sin caballo/jinete» en la ficha.
  - Orden de prioridad: asignación del usuario > código del archivo > nombre del archivo.
  - Solo se cambian los metadatos en el PC (`cuadra.json`); el archivo no se toca.
- **Lector NFC USB PC/SC** (`winscard.dll`):
  - Lee las etiquetas `avohorse://identity/horse|rider/…` de la app Android con las mismas validaciones que `AvoNfc.import`, incluidas las tarjetas de usuario con licencia. Nunca sobrescribe una ficha existente.
  - Rellena el panel Asignar.
  - Graba fichas en NTAG213/215/216 con el mismo NDEF que `NfcScreen` de Android y lo verifica leyéndolo.
  - Solo escribe el área NDEF y rechaza las etiquetas bloqueadas.
**Por qué:** lo pidió el usuario. Quiere los caballos con sus entrenamientos, los jinetes con los suyos, asignar los entrenamientos que llegan sin ellos y registrar caballos y jinetes por NFC.
**Archivos:**
- `windows/AVO.Windows.Core/Stable/{Stable.cs,Nfc.cs}`; `Models.cs`, `TrainingImporter.cs`, `RawReader.cs` (código del archivo) y `SessionTimeline.cs`;
- `windows/AVO.Windows/ViewModels/{MainViewModel.Stable.cs,SessionItem.cs,Mvvm.cs,MainViewModel.cs}`, `Views/StableView.*`, `MainWindow.xaml`, `HomeView.xaml`, temas;
- `App.xaml.cs`: recorrido NFC en el modo captura;
- `windows/AVO.Windows.SelfTest/StableTests.cs`.
**No se ha tocado:** firmware, Android ni el formato de los archivos.
**Validación:**
- IMPLEMENTADO.
- Autopruebas de URI, NDEF, NTAG215 simulada tras un lector PC/SC y almacén.
- Recorrido NFC en el modo captura de CI con lector simulado.
- **NO VERIFICADO con un lector NFC real ni con etiquetas físicas.**

## 2026-10-30 — Windows Advanced Analysis V2 PRO 2.0.0 (rama feature/windows-advanced-analysis)
**Autor:** Claude · **Commits:** `2d3383c` (importa motor EIE + Windows de `feature/avo-wifi-sync`), `f9f9fdc` (integra develop
18a9823), `18bbe5c`…`f626309` · **CI:** build-avo-windows run [41084991763](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41084991763) (éxito: 106 autopruebas, publicación, 33 capturas)
**Qué cambia:** nueva app Windows V2 PRO sobre la V1 con motor (pestaña «Motor AVO» de EIE): paleta de `Theme.kt`, componentes
XAML reutilizables, MVVM, 11 vistas (inicio, análisis, mapa satélite/híbrido Esri con reproducción, gráficas sincronizadas con
el mapa, tramos persistentes, biomecánica con el motor, comparador, mareas IHM + Open-Meteo, informes PDF/HTML/CSV/GPX/JSON,
servidor no conectado, motor). Lectura RAW ampliada (todos los campos de GNSS_SAMPLE, IMU_SAMPLE 9 ejes en LSB, MARKER),
velocidad reportada/derivada/filtrada (Kalman + RTS documentado), biblioteca con SHA-256 y duplicados, registro JSON.
Generador de sesiones de DEMOSTRACIÓN sintéticas (`windows/tools/demo-fixtures`) y modo `--capture` para evidencia visual.
**Por qué:** encargo «Windows Advanced Analysis V2 PRO» con las referencias `AVO_WINDOWS_CONCEPTO_01/02`.
**Archivos:** `windows/**`, `equine-intelligence/**` (copia sin cambios de wifi-sync), `.github/workflows/build-avo-windows.yml`,
`build-equine-engine.yml`, `core/src/test/resources/equine/*` (fixtures).
**No se ha tocado:** Android, firmware, motor C++ (solo se compila y se usa).
**Validación:** IMPLEMENTADO · COMPILADO / CI (run 41084991763, `f626309`) · PROBADO AUTOMÁTICAMENTE (106 comprobaciones) ·
**NO VERIFICADO** con sesiones reales con cincha (no existen) ni manualmente en un PC con Windows.
**Actualización 30/10 17:30:** pantalla de inicio reproducida como en `AVO_WINDOWS_CONCEPTO_02` (foto, logotipo y lema
recortados de la imagen de referencia del usuario, acciones reales a la derecha, ventana sin barra ni menú en el inicio); el
panel anterior pasa a «Entrenamientos». La foto sale de la maqueta (1536×1024) y se reescala: sustituible por un original
de alta resolución en `windows/AVO.Windows/Assets/avo_home_hero.jpg`.
**Actualización 30/10 21:45:** las 5 acciones del inicio son funcionales y se comprueban en CI pulsándolas por UI Automation
(abrir → importa y abre «Análisis»; recientes → «Entrenamientos» con historial y favoritos persistentes; servidor; comparar; informes).
**Actualización 30/10 23:30 (tras la primera prueba del usuario en su PC, sin entrenamientos):** mapa centrado en el Regatón
cuando no hay recorrido (antes mostraba océano 0°,0° con teselas «Map data not yet available»), panel claro «Todavía no hay
entrenamientos» con «Abrir» y «Cargar demostración» (descarga las sesiones SINTÉTICAS publicadas en la pre-release).
Descarga directa: pre-release `windows-v2-pro-latest` (EXE único con el motor incluido).
**Actualización 30/10 23:50:** integrada en V2 PRO la descarga automática del reloj por USB de `feature/chest-usb-pc-sync`
(`ChestUsb.cs`, `SimWatch.cs`, `usb_transcript.json` y sus pruebas sin cambios; interfaz portada a MVVM: botón «Reloj USB»,
tarjeta en «Entrenamientos», aviso en el estado vacío, detección por WM_DEVICECHANGE y sondeo cada 4 s). Requiere el
firmware de pecho **3.7.5-usb1** (rama `feature/chest-usb-pc-sync`, NO VERIFICADO); con otro firmware se informa al usuario.
**Actualización 31/10 00:20 (petición del usuario con sesiones reales HORSE_001):** inicio y fin del entrenamiento útil por
sesión («Inicio = cursor», «Fin = cursor», «Usar selección», «Archivo completo» en la cabecera de sesión). Se guarda en
`recortes.json`; todas las vistas, tramos, comparativas e informes usan ese tramo con la base de tiempo del archivo completo.
**Pendiente:** prueba manual en Windows; sesiones reales `.avo`; calibración/orientación IMU; contrato del servidor; firma
del ejecutable; modelo 3D autorizado; integración en develop.

---

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

## 2026-10-31 — BACK 3.13.0 (Heltec) — Pololu en GPIO34 y carga por USB con todo dormido
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** `93cb8a9` · **CI:** [41150163565](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41150163565) (éxito)
**Qué cambia:** SHDN del Pololu S7V8F3 de GPIO6 a **GPIO34** (pin entre los del ZED en 33 y 35, comprobado con la lista
de pines de la Heltec Wireless Stick Lite V3). Detección del USB por el pin 5V con divisor 10 k / 15 k a **GPIO7** (antes
reed): con USB la placa entra en sueño profundo con el ZED sin corriente, radio y LEDs apagados (solo carga) y se despierta
por ext0 al desaparecer los 5 V. USER en 3 s = modo taller. Contador de encendidos rápidos solo con `ESP_RST_POWERON`.
**Por qué:** el usuario quita el Qi y carga por el USB-C; pide que con el USB conectado solo cargue y que al desconectarlo
se despierte todo. La Heltec (CP2102 + TP4054) no tiene ningún pin que indique USB: hace falta el divisor.
**Validación:** IMPLEMENTADO · COMPILADO-CI · **NO VERIFICADO** en la placa.

## 2026-10-31 — BACK 3.13.1 (Heltec) — USB comprobado por temporizador
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** `f3b19d5` · **CI:** [41151001126](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41151001126) (éxito)
**Qué cambia:** el sueño por USB despierta cada 3 s por temporizador y vuelve a dormir al instante si el ADC sigue viendo
el USB en GPIO7 (umbral 1,5 V con pull-down interno), en vez de despertar por nivel bajo en GPIO7 (ext0). Se imprime el
motivo de reinicio y de despertar al arrancar.
**Por qué:** prueba del usuario 31/10 01:34 con la 3.13.0: «al conectar el USB lo duerme un segundo y vuelve a arrancar».
La placa estaba **sin el divisor**, así que el firmware no podía detectar el USB: lo que se ve es el reinicio del CP2102 al
conectar. Aun así, con el divisor el nivel de GPIO7 en sueño queda cerca del umbral de entrada RTC: el ADC es más seguro.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.

## 2026-10-31 — BACK 3.13.2 (Heltec) — detección del USB también en GPIO20
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** `f0d20f7` · **CI:** [41151554311](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41151554311) (éxito)
**Qué cambia:** `usb_present()` = GPIO7 por ADC (> 1,5 V) **o** GPIO20 digital con pull-down (divisor 10 k / 22 k). Se
desactivan el pad USB-Serial-JTAG y los pull-up de D+/D− para usar GPIO20 como entrada; GPIO20 fijado con pull-down
durante el sueño. El monitor muestra `GPIO20 ALTO/bajo`.
**Por qué:** el usuario prefiere GPIO20 (está junto al pin 5V en la misma fila).
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.

## 2026-10-31 — BACK 3.13.3 (Heltec) — corte por batería baja, USB solo en GPIO20
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** `69f851c` · **CI:** [41153737708](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41153737708) (éxito)
**Qué cambia:** antes de arrancar la radio, batería en reposo < 3,30 V sin USB → sueño profundo (ZED sin corriente),
reintento cada 60 s, vuelve por encima de 3,45 V (estado en RTC). Detección del USB solo por GPIO20 digital; se quita la
lectura ADC de GPIO7. Línea de arranque con la batería y el nivel de GPIO20.
**Por qué:** monitor del usuario 31/10 02:05 con la 3.13.2 y el USB del móvil: batería 2954 mV, `E BOD: Brownout detector
was triggered` justo al encender la radio y reinicio (`rst:0x3`, `esp_reset_reason` 9) en bucle; el USB no se detectó
(no salió «USB conectado»). analogRead deja GPIO7 sin pull-down: sin divisor flotaba.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.

## 2026-10-31 — BACK 3.13.4 (Heltec) — USB en GPIO20 también por ADC (umbral 1,0 V)
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** `4a8ca17` (CI 41154849274 falló: variable declarada tarde), `c648d5a` · **CI:** [41155004469](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41155004469) (éxito)
**Qué cambia:** `usb_present()` = GPIO20 digital alto **o** ADC de GPIO20 > 1000 mV (lecturas a 0 por el árbitro del ADC2
ignoradas). Antirrebote del bucle: hacen falta 2 fallos seguidos para reiniciar la cuenta. Tensión de GPIO20 en el monitor.
**Por qué:** monitor del usuario 31/10 02:16 con la 3.13.3: arranca bien con 3351 mV, pero `USB: no (GPIO20 bajo)` con el
USB conectado. El usuario pide bajar el umbral de tensión para dormir.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.

## 2026-10-31 — BACK 3.13.5 (Heltec) — divisor del USB en cualquier pin libre de la fila del 5V
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** `0e07869` · **CI:** [41155792294](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41155792294) (éxito)
**Qué cambia:** la detección del USB acepta nivel alto en GPIO20, 18, 21, 19, 47 o 48 (pull-down interno) y al arrancar
imprime el nivel de todos y el ADC de 20/18/19.
**Por qué:** monitor del usuario 31/10 02:29 con la 3.13.4: `USB (GPIO20 171 mV): no detectado` con el USB conectado; con
5,1 k / 10 k desde 5 V debería medir ≈ 3,3 V → el divisor no está en GPIO20. También: reinicio por caída de tensión tras
instalar (batería 3454 mV) y `ZED: SIN_RESPUESTA_UBX` en los primeros segundos.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.

## 2026-10-31 — BACK 3.13.6 (Heltec) — RX/TX del ZED cruzados automáticamente
**Autor:** Claude · Rama `feature/avo-back-v4` · **Commits:** `a1c3ea1` · **CI:** [41156288729](https://github.com/avotattoocastro-creator/apk_android_avo/actions/runs/41156288729) (éxito)
**Qué cambia:** pines del UART del ZED variables; sin bytes del ZED durante 10 s tras darle corriente → se intercambian
GPIO33/GPIO35 (alternando); con más de 64 bytes recibidos se guarda el orden en NVS `zedswap`. Al arrancar se liberan los
holds de los dos pines.
**Por qué:** el usuario dice que el GPS no funciona y pide invertir RX/TX por si los soldó al revés.
**Validación:** IMPLEMENTADO · **NO VERIFICADO**.
