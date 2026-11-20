# Auditoría GNSS 20/11/2026 — mensajes de calidad, RTCM y precisión de velocidad (espalda 3.14.4 + Android 2.14-gnss-dev1)

Estado: **IMPLEMENTADO · COMPILADO EN CI · NO VERIFICADO** en la espalda, el reloj ni el móvil.
Rama `claude/gnss-calidad-rtcm-back-3-14-4`, desde `develop/avo-performance-horse` (`daab9d1`).

## 1. Punto de partida (código real)
| Unidad | Versión en `develop` | Dónde |
|---|---|---|
| Espalda PROTOTIPO | 3.14.3 | `firmware/back/V3_8_0` (`avo_version.h`) |
| Pecho PROTOTIPO | 3.7.10 (cadena ZIP 3.7.0-rc2 + parches; la calidad GNSS entra en el parche 3.7.6) | `firmware/chest/V3_7_*` |
| Android | 2.13-qr-dev1 (vc 46) | `app/`, `core/` |

Las versiones del encargo: **3.7.6** es el pecho (TELEMETRY v3 de 116 B con la calidad), **3.8.2** es la espalda con
modo carga y **3.9.0** es la espalda que introdujo NAV-SAT/NAV-SIG. Su fallo de recepción GPS está analizado en
`AUDITORIA_GNSS_3_9_0_vs_3_13_6.md`: tenía RX/TX del UART cruzados respecto al cableado real.

### Pines (verificado contra el código, no contra el encargo)
El encargo dice «GPIO33 RX ← TX ZED, GPIO35 TX → RX ZED». **Eso es lo que hacían la 3.9.0 y la 3.13.7, y por eso no
llegaba ningún byte.** El usuario confirmó el cableado el 31/10 por colores (verde = TX del ZED → GPIO35, blanco = RX del
ZED → GPIO33). Desde la 3.13.8 el código usa `UART1 RX=GPIO35, TX=GPIO33` (`ZED_RX_PIN = 35`, `ZED_TX_PIN = 33`), y las
instrucciones del proyecto dicen lo mismo. Con esa configuración llegan NAV-PVT (la captura muestra «último dato GNSS
hace 79 ms»), así que **no se han tocado los pines**. GPIO34 = SHDN del Pololu: coincide.

## 2. Qué dice la captura y qué no
- **NAV-PVT llega** (79 ms), el enlace reloj → móvil funciona (43 ms), la espalda está en el estado de mensajes
  «activados» (`quality_mon` = 1) y el último NAV-SIG tiene 49 s. **Antes llegó al menos uno**: si no hubiera llegado
  ninguno, la edad sería 255 y la app no escribiría «último hace…».
- «Satélites 24» sale de NAV-PVT (actual). «18 / 26 usados / seguidos» sale de NAV-SAT. Con 24 satélites en la
  solución, un NAV-SAT actual daría unos 24 usados. Esos 18 / 26 son, por tanto, **del último NAV-SAT que llegó**.
  - La 3.14.3 mandaba esos recuentos para siempre, y la app los enseñaba aunque el resumen estuviera caducado.
  - Conclusión: se pararon **los dos mensajes grandes** (NAV-SAT ~0,5 KB y NAV-SIG ~1 KB) mientras el pequeño NAV-PVT
    (100 B) seguía llegando.
- 64,9 cm H / 47,9 cm V, «primer FIX todavía no», FIX/FLOAT 0/0: el receptor **no tiene solución RTK**. La captura no
  dice si NTRIP estaba conectado ni si el receptor usaba RTCM. Eso se ve en la tarjeta «Correcciones NTRIP», que no se
  envió. No se puede concluir nada sobre NTRIP con esta captura.

## 3. Causa raíz
### Probable, sin medición en hardware: desbordamiento de la FIFO RX del ESP32-S3
- La FIFO RX del ESP32-S3 tiene 128 B. El núcleo Arduino-ESP32 3.3.12 pide la interrupción cuando hay unos 120 bytes
  esperando, así que solo deja 8 bytes de margen:
  - a 230 400 baudios, 0,35 ms;
  - a 460 800 baudios, 0,17 ms. La 3.13.8 se recuperó a 460 800: si el ZED ya estaba a 230 400, `PROBE_PORT` sube a 460 800.
- Si la interrupción se retrasa más de eso (Wi-Fi/ESP-NOW, acceso a la flash), la FIFO se desborda y el driver de
  ESP-IDF la vacía entera. Se pierden hasta 128 bytes de golpe.
  - Un NAV-PVT de 100 B cabe entero en la FIFO y casi nunca cae.
  - Un NAV-SIG de ~1 KB ocupa 44 ms seguidos de línea y basta un retraso en esa ventana para perderlo. NAV-SAT va pegado
    a él, en la misma época.
- Esta causa encaja con todo lo que muestra la captura: los mensajes grandes se pierden, el pequeño sigue llegando y
  el receptor no está reiniciado. Si el receptor se hubiera reiniciado, también habría perdido el ajuste de NAV-PVT.
- **No está demostrada**: la 3.14.3 no contaba los errores de la UART. La 3.14.4 los cuenta (§5).

### Defectos confirmados en el código (pruebas de host que fallaban con la lógica anterior)
1. **Parser UBX (`UbxStream`).** Tras una trama mala tiraba todos sus bytes. Si faltaban bytes dentro de un NAV-SIG, la
   longitud de su cabecera hacía que el parser se tragara también el principio del NAV-PVT siguiente, y lo perdía.
   - Prueba `ubx.bytes_lost_inside_nav_sig_do_not_take_the_next_nav_pvt_with_them`.
2. **Vigilancia de la 3.13.12.** Con los dos mensajes aceptados, solo vigilaba NAV-SIG. Si se paraba NAV-SAT, nunca se
   volvía a pedir.
   - Prueba `quality.lost_nav_sat_alone_is_requested_again`.
3. **Recuentos caducados presentados como actuales**, en `STATUS` y en la app (el «18 / 26» de la captura).
   - Prueba `quality.stale_counts_are_not_reported_as_current`.
4. **Activación «a ciegas».** Solo se comprobaba `baud ≥ 115 200`. No se calculaba la carga de la UART ni si la ráfaga
   de 1 Hz cabía en una época.

### Descartado con el código
- Claves `CFG-MSGOUT` y estructuras de NAV-SAT/NAV-SIG/RXM-RTCM: coinciden con la *Interface Description* de u-blox F9 HPG.
- Búfer del parser (2100 B frente a ~1,9 KB de un NAV-SIG con 120 señales) y búfer RX del ESP32 (8 KB): suficientes.
- Pecho 3.7.6+: reenvía `quality_mon`/`quality_age_s` tal cual y suma la edad del enlace. Android interpreta bien el
  campo. El texto «activados, pero no llegan» es correcto: describe lo que pasa en la espalda.

## 4. Ancho de banda (calculado antes de activar nada)
8N1 = 10 bits por byte. Peor caso usado por el firmware: 60 satélites en NAV-SAT, 120 señales en NAV-SIG y 12 mensajes
RTCM por segundo (`zed_uart_budget`, prueba `budget.uart_load_of_the_quality_messages`).

| Baudios | Línea | Media a 8 Hz | Carga | Ráfaga de 1 Hz (PVT+SAT+SIG) | Época | ¿Calidad? |
|---|---|---|---|---|---|---|
| 38 400 | 3 840 B/s | 3 707 B/s | 97 % | 730 ms | 125 ms | **no** (estado 3 «UART lenta») |
| 115 200 | 11 520 B/s | 3 707 B/s | 32 % | 243 ms | 125 ms | sí (retrasa un NAV-PVT una vez por segundo) |
| 230 400 | 23 040 B/s | 3 707 B/s | 16 % | 122 ms | 125 ms | sí |
| 460 800 | 46 080 B/s | 3 707 B/s | 8 % | 61 ms | 125 ms | sí |

Regla: carga ≤ 50 % y ráfaga ≤ 2 épocas. **No se activa ningún mensaje nuevo de salida continua**.
MON-COMMS es un sondeo de 8 B cada 5 s, con una respuesta de unos 216 B.

## 5. Cambios
### Espalda 3.14.4 (`firmware/back/V3_8_0`)
- `.ino`:
  - Umbral de la FIFO RX del ZED a 32 B, con 96 B de margen (4,2 ms a 230 400). Se aplica tras cada `begin()` y cada
    cambio de baudios.
  - `onReceiveError`, que cuenta FIFO desbordada, búfer lleno, trama, paridad y *break*.
  - Monitor serie, líneas nuevas:
    - `MENSAJES ZED:` recuentos y edades de NAV-PVT, NAV-SAT y NAV-SIG; UBX malos, demasiado largos y resincronizaciones.
    - `UART ESP32 (ZED):`
    - `PRESUPUESTO UART:`
    - `MON-COMMS:`
- `avo_ubx_zed.*`:
  - El parser resincroniza tras una trama mala.
  - `zed_uart_budget()` decide si se activan NAV-SAT/SIG.
  - Contadores y tiempos por mensaje; NAV-SAT y NAV-SIG se vigilan por separado.
  - Sondeo y decodificación de UBX-MON-COMMS. Con él, el propio receptor dice si su búfer TX desborda (`txErrors`:
    descarta mensajes antes de salir) y si pierde bytes RTCM a la entrada (`overrunErrs`, `skipped`).
- `avo_back_core.cpp`: los recuentos de satélites y señales solo van en `STATUS` si tienen ≤ 5 s; si no, van a 0.
  **Formato y longitud de `BackStatus` v3 (108 B) sin cambios.**
- Sin tocar: pines, alimentación, sueño, carga USB, RTCM, ESP-NOW, emparejamiento, cincha y perfil de precisión. **No
  se reinicia el ZED**: la vigilancia solo vuelve a enviar el `VALSET` de NAV-SAT/SIG, sin tocar NAV-PVT ni RTCM.

### Pecho
Sin cambios. Reenvía el byte `quality_mon`, la edad del resumen y los contadores RTCM, como en la 3.7.6+.

### Android 2.14-gnss-dev1 (vc 47)
- `core/.../telemetry/GnssChain.kt`: lee la cadena completa a partir del texto de `DIAG_GET`, que el reloj ya
  devuelve desde la 3.5.0. **Sin cambio de protocolo.** Toma dos lecturas separadas 5 s:
  - Etapas de RTCM: caster → móvil → reloj → espalda → UART del receptor → usadas por el receptor (RXM-RTCM).
  - Detecta la primera etapa parada y las pérdidas (CRC, huecos de radio, sin escribir, rechazadas por el receptor).
  - Recepción UBX en la espalda, en tramas/s, con estado y baudios.
  - «NTRIP recibiendo» nunca se presenta como RTK; «usadas por el receptor» tampoco se presenta como FIX.
- `HomeScreen.kt` › «Calidad GNSS»:
  - Siempre visibles: solución GNSS, NTRIP, recepción UBX y cadena RTCM.
  - Ya no muestra satélites de un resumen caducado.
  - Precisión de la velocidad comparada con el objetivo de 0,20 km/h, sin filtrar.
- `Components.kt`: `KV` reparte la fila y permite partir líneas, y `MetricTile` reduce el texto de los valores largos.
  Era la causa probable de los solapes. **El adjunto solo traía el texto del encargo, no la captura**: el arreglo es
  genérico y queda pendiente comprobarlo en el móvil.

## 6. Velocidad (objetivo < 0,20 km/h = `sAcc` < 55,6 mm/s)
- La app ya muestra la velocidad del receptor: `gSpeed` de NAV-PVT, que es Doppler. No hay filtro ni derivada de
  posiciones. `sAcc` es la estimación del propio receptor y **no se ha tocado**: maquillarla con filtros iría contra el
  encargo.
- El ZED-F9P especifica 0,05 m/s (0,18 km/h) en condiciones abiertas. El objetivo está en el límite del receptor, y
  solo se alcanza con buen cielo y buena relación C/N₀. 0,52 km/h (144 mm/s) con 64,9 cm de precisión horizontal y sin
  fase de portadora es lo esperable con señal pobre (balcón, edificios), no un fallo del firmware.
- **No se cambia** el modelo dinámico (Airborne < 2g), la frecuencia (8 Hz con 4 constelaciones, el límite RTK de la
  hoja de datos) ni las máscaras. Cualquier cambio necesita un ensayo A/B en pista (§8). Sin medición sería una
  suposición.

## 7. Pruebas (todas simuladas; ninguna física)
| Prueba | Resultado | Nivel |
|---|---|---|
| Host espalda: 52 casos, 519 comprobaciones (9 nuevos: parser con bytes perdidos, checksums, falsa sincronía y longitud excesiva, fragmentación de 1 a 300 B, presupuesto UART, MON-COMMS con y sin respuesta, NAV-SAT perdido, recuentos caducados) | OK, local y CI | simulado (ZED modelado según u-blox) |
| Ya existentes en la espalda: RTCM byte a byte, radio con pérdidas y ACK perdidos, reinicio del pecho y de la espalda, reconexión, ZED apagado y encendido, perfil de precisión | OK | simulado |
| Compilación del firmware de la espalda (arduino-cli, esp32 3.3.12), imagen ESP32-S3, marcas 3.14.4 | OK, CI | CI |
| Android: 7 pruebas JVM de `GnssChainTest` + todas las existentes; APK | ver el PR | CI |
| Regresión de la grabación RAW (pecho) | no aplica: el pecho no cambia | — |
| En hardware: espalda, reloj y móvil | **pendiente** | — |

## 8. Validación en vuestro hardware
1. Instalar la espalda 3.14.4 con AVO Update y la app 2.14-gnss-dev1. El pecho no cambia (3.7.10).
2. Monitor serie de la espalda (115 200) al aire libre, 10 min:
   - `UART ESP32 (ZED): FIFO desbordada` debe quedarse en **0**. Si sube, la causa era esa y el umbral no basta:
     probar a fijar el ZED en 230 400.
   - `MENSAJES ZED`: la edad de NAV-SAT y NAV-SIG debe ser ≤ 1,5 s siempre, y `UBX malos` no debe crecer.
   - `MON-COMMS`: sin «ERROR: el receptor DESCARTA», `desbordes` = 0 y pico TX < 80 %.
3. App › INICIO › Calidad GNSS: el resumen no debe volver a «Esperando…» más de 2 s seguidos.
   «Resumen de señales pedido de nuevo» debe quedarse en 0.
4. Cadena RTCM con NTRIP activo: todas las etapas en verde y «El receptor está usando las correcciones». Si una etapa
   sale en ámbar, esa es la que falla. Anotar «Primer RTK FIX» y FIX/FLOAT tras 5 min con cielo abierto.
5. Velocidad, ensayos de 5 min:
   - Parado, con la espalda quieta: la media de la velocidad debe ser < 0,1 km/h. Anotar `sAcc`.
   - Paso y trote en línea recta.
   - Giros y paradas.
   - Comparar `gSpeed` con la velocidad calculada a partir de las posiciones RTK FIX del `.avr`, y anotar el porcentaje
     de épocas con `sAcc` < 55 mm/s. Solo con esos datos se decide si cambiar el modelo dinámico.
