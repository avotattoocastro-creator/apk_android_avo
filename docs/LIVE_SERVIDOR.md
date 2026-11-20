# LIVE desde el servidor (Android → Firebase → iPad)

Decisión del usuario (19/11/2026): **«El iPad es Live desde el servidor»**. El iPad no se conecta al pecho, porque el pecho
acepta un solo móvil (`firmware/chest/V3_7_8_VINCULAR`) y ese móvil es el Android, que le envía el RTCM. El Android sube
lo que recibe del pecho y el iPad lo muestra en la pantalla **LIVE** (barra lateral, debajo de «Carreras»).

```
Pecho ──BLE TELEMETRY v3 (2 Hz)──▶ Android ──Firebase RTDB──▶ iPad (LIVE)
   ▲                                   │
   └──────────── RTCM3 (BLE) ──────────┘   (sin cambios)
```

**No cambia ningún contrato binario.** `TELEMETRY v3` (116 B), `BackStatus v3`, lotes de cincha, `AVO1`, `.avr` y RTCM
siguen igual. LIVE es una copia en texto de campos que ya trae la `TELEMETRY`.

## Qué llega en directo y qué no
| Dato | En directo | Origen |
|---|---|---|
| Posición, velocidad, distancia, tiempo | sí, 2 Hz | `TELEMETRY` (lat/lon E7, `speed_mm_s`, `distance_cm`) |
| Calidad GNSS (fix, RTK FLOAT/FIX, satélites, hAcc) | sí | `TELEMETRY` |
| Aceleración | **aproximada**: derivada de la velocidad GNSS en el iPad | — |
| Aire (paso, trote, galope, rápido) | **orientativo**: por velocidad, con 3 s de histéresis | — |
| Pulso | **no** | necesita la cincha con ECG (REV 5.10) y un `TELEMETRY v4` |
| Aceleración de la IMU (VeDBA) | **no** | necesita un `TELEMETRY v4` |

Un `TELEMETRY v4` (pulso, VeDBA) es un cambio de protocolo: pecho + espalda/`GirthHub` + Android + Windows + iPad a la
vez (skill `avo-cambio-protocolo`). Encaja con la fase F2 «Cardio» de la hoja de ruta.

## Firebase (proyecto `avo-performance-horse-7be14`, el mismo de Compartir)
Nodo `live/{owner}/{sid}`. `owner` = código de la tarjeta AVO (`AVO-XXXX-XXXX`) y `sid` = inicio UTC `yyyyMMdd-HHmmss`.

| Ruta | Contenido | Quién escribe |
|---|---|---|
| `meta` | `horseName`, `riderName`, `breed`, `startMs`, `state` (`REC`/`PAUSE`/`END`), `updatedMs`, `expiresMs` (≤ 48 h) | el dueño |
| `last` | última muestra `LIVE1` (2 Hz, solo con conexión) | el dueño |
| `s/{n}` | bloque de ~10 s (≤ 40 muestras, ≤ 6000 caracteres) | el dueño |

**Lectura:** el dueño (su iPad con la misma tarjeta) y quien haya **aceptado** sus envíos (`grants/{lector}/{dueño}`
= `ACCEPTED`). PENDING, REJECTED y BLOCKED no leen. Reglas en `firebase/database.rules.json` y pruebas en
`firebase/test/rules.test.js` (bloque «LIVE»). **Las reglas se publican a mano** en la consola de Firebase cuando el
workflow `firebase-rules.yml` pasa en `develop`. Hasta entonces, el servidor rechaza las escrituras de `live/`.

**Limpieza:** no hay funciones en el servidor (plan Spark). Cada vez que empieza un directo, el Android borra sus
sesiones caducadas (`expiresMs`, 24 h desde el inicio).

**Consumo:** unos 60 B por muestra a 2 Hz, más los bloques. En total, unos 0,5 MB por hora y caballo, de subida en el
Android y de bajada en cada iPad.

## Formato `LIVE1`
```
muestra = t_ms,latE7,lonE7,speed_mm_s,dist_cm,fix,carr,hacc_mm,num_sv,session
last    = "LIVE1," muestra
s/{n}   = "LIVE1," muestra *(";" muestra)
```
- Solo enteros. `t_ms` cuenta desde el inicio del directo (reloj del Android al recibir la `TELEMETRY`).
- `fix` = `fixType` de NAV-PVT. `carr` = `carrSoln` (1 FLOAT, 2 FIX). `session` = estado del pecho (2 grabando, 3 en pausa).
- Vector común de las pruebas: `LIVE1,1500,434190000,-34540000,15200,250000,3,0,180,31,2`
  (`core/src/test/.../LiveCodecTest.kt` y `ipad/AVOiPadTests/LiveCodecTests.swift`).

## Android (2.10-live-dev1)
- `core/.../live/LiveCodec.kt`: formato y `LiveRecorder`, una máquina de estados pura con pruebas. Empieza al pasar a
  GRABANDO, sigue en PAUSA y termina con cualquier otro estado.
- `app/.../cloud/LiveShare.kt`: escribe en Firebase con el SDK, que guarda las escrituras sin conexión y las envía al
  volver. Se alimenta de `WatchConnection.telemetry` desde `AvoLinkService`.
- **Compartir › «Directo (LIVE en el iPad)»:** interruptor, desactivado por defecto. Necesita la tarjeta AVO personal y
  la licencia con COMPARTIR.
- **Compartir › Mi cuenta › «Entrar en el iPad (LIVE)»:** muestra el código y la clave de la tarjeta, o comparte el
  enlace, para entrar en el iPad, que no tiene NFC.

## iPad
- `Core/LiveCodec.swift`: formato, estado de la sesión a partir de los eventos y series derivadas.
- `Core/LiveFirebase.swift`: Firebase por REST, **sin SDK ni dependencias**: Authentication (`signInWithPassword` y
  renovación del token), lecturas y flujo `text/event-stream`. La tarjeta se guarda en el Llavero.
- `App/LiveModel.swift` y `Views/LiveView.swift`: pantalla del boceto del 19/11/2026.
  - Arriba, la franja de datos en tiempo real.
  - El mapa sigue al caballo, con los botones «Centrar» y «Ver todo».
  - Sobre la parte baja del mapa, la velocidad en tiempo real.
  - Debajo, las gráficas de pulso (vacía, con el motivo) y de aceleración.
  - Sin panel derecho y sin barra de pestañas.
- **Simulación:** «Simular con el entrenamiento abierto» reproduce un entrenamiento real a 2 Hz y se marca siempre
  SIMULACIÓN. Las capturas de CI la usan al instante.

### Riesgo conocido: clave de Firebase restringida
El iPad usa la misma clave web pública que el Android. Si en Google Cloud la clave está restringida a apps Android, el
iPad recibe un error al entrar («Firebase rechaza la clave de la app para iPad»). Hay dos soluciones, y las dos se hacen
en la consola, no en el repositorio:
1. Añadir una app iOS al proyecto de Firebase y poner su clave (pública) en `LiveFirebaseConfig.apiKey`.
2. Permitir el bundle `org.avoperformance.horse.ipad` en las restricciones de la clave.

## Validación
IMPLEMENTADO · pruebas añadidas (reglas, Kotlin y Swift) · **NO VERIFICADO** en hardware. Prueba física pendiente:
pecho AVO_1E8C grabando, Android con «Directo» activado y el iPad en LIVE, con la misma tarjeta y con un invitado.
