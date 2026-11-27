# PPK — posición poscalculada de la espalda (espalda 3.16.0 · motor 2.0.0-dev33)

**Estado:** IMPLEMENTADO · pruebas de anfitrión correctas · **NO VERIFICADO** en hardware ni con datos de la cuadra.

## Para qué sirve
- Posición al centímetro **sin RTK en directo**: el trabajo se puede hacer **sin el móvil** (sin NTRIP). La base se
  descarga después (IGN, ficheros horarios a 1 s).
- Parciales de 200/600/1000 m, distancia real y curvas con precisión de centímetros; velocidad media por tramo sin
  sesgo. La velocidad en directo sigue saliendo del Doppler de NAV-PVT (8 Hz) y la cadencia de la IMU.
- Límite: la antena va en la espalda del jinete; zancada a zancada se mide el jinete, no el caballo.

## Cadena
```
ZED-F9P ── UART ──> espalda 3.16.0 ── ESP-NOW (GNSS_UBX_FRAG 0x12) ──> pecho (sin cambios) ──> .avr
                                                                                              │
IGN ERGNSS horario_1s (RINEX 3 .crx.gz) ── app: quita gzip ──> motor: Hatanaka + RTKLIB ──> avo-ppk
```
- **Espalda PROTOTIPO (Heltec):** RXM-RAWX a **1 Hz** (2 Hz con la UART a ≥ 460 800 baudios) y todos los RXM-SFRBX,
  pedidos en un VALSET propio (RAM) después de la salida de calidad y solo si caben en el presupuesto de la UART
  (`zed_uart_budget_raw`). NAV-PVT sigue a 8 Hz.
- **Casco BETA V5:** el ZED va por UART al ESP32-S3, que tiene microSD propia: puede grabar RAWX a la frecuencia de
  navegación directamente, como tramas `GNSS_UBX` (0x11) enteras. El motor acepta las dos formas.
- **Pecho:** graba cada trama de la espalda tal cual (`RecType::UART_FRAME`). No hace falta firmware nuevo.

## Contrato `GNSS_UBX_FRAG` (tipo de trama AVO 0x12, v1)
Carga útil (little-endian), definida en `firmware/back/V3_8_0/lib/avo_core/src/avo_ubx_frag.h`:

| Offset | Tamaño | Campo |
|---|---|---|
| 0 | 1 | versión (1) |
| 1 | 1 | índice del trozo (0 … total − 1) |
| 2 | 1 | número de trozos (1 … 22) |
| 3 | 1 | reservado (0) |
| 4 | 2 | secuencia del mensaje (por arranque de la espalda; comparten todos los trozos) |
| 6 | 2 | longitud total de la trama UBX completa (sync … checksum, ≤ 4096) |
| 8 | n | bytes `[índice·192, …)` de la trama UBX (192 salvo el último) |

- Trama AVO: 15 + 8 + 192 + 4 = **219 B ≤ 234** (un paquete ESP-NOW por trozo, **un solo intento**, sin reintentos:
  una ráfaga de fallos nunca retiene el bucle lo bastante para desbordar la UART del ZED).
- El primer trozo que falla abandona el resto del mensaje. El motor solo entrega tramas completas con checksum UBX
  correcto y cuenta las perdidas (`mensajes_perdidos`).
- `CAPS`: bit `CAP_GNSS_RAW` (1 << 8) mientras el receptor envía RAWX/SFRBX. Se reenvía CAPS en cuanto cambia.

## Compatibilidad
| Espalda | Pecho | Motor / apps | Resultado |
|---|---|---|---|
| ≥ 3.16.0 | cualquiera ≥ 3.7.x | ≥ 2.0.0-dev33 | PPK disponible |
| ≥ 3.16.0 | cualquiera | < dev33 | las tramas 0x12 se cuentan como desconocidas y se ignoran (sin error) |
| < 3.16.0 | cualquiera | ≥ dev33 | `avo_eq_ppk_need` → `"tiene_rawx": false` |
| ZED sin las claves RAWX/SFRBX | — | — | `raw_state = 2` (rechazado); NAV-PVT, RTCM y NAV-SIG como antes |
| UART < 230 400 baudios | — | — | `raw_state = 3` (omitido) |

## Motor (API C, `avo_eq_c.h`)
- `avo_eq_ppk_need(paths, n, &json)` → `avo-ppk-necesita`: hay RAWX, inicio y fin UTC y posición aproximada, para
  elegir la estación y las horas que hay que descargar.
- `avo_eq_ppk(paths, n, base_paths, nb, opciones, cancel, &json)` → `avo-ppk`. La base: RINEX 3 de observación
  (texto o Hatanaka `.crx`, **ya sin gzip**) y, opcionalmente, de navegación. Sin SFRBX en la sesión, las efemérides
  salen del RINEX de navegación.
- Resolución: RTKLIB demo5 (`equine-intelligence/src/ppk/rtklib`, BSD-2, cambios en su `README_AVO.md`), cinemático,
  L1 + L2/E5b, GPS + Galileo + GLONASS + BeiDou + QZSS, máscara de 15°, *fix-and-hold*, ratio 3, pasada adelante y
  atrás combinada. Velocidad por diferencias centrales entre épocas de la misma calidad.
- Avisos: línea base > 30 km, posición de la base tomada de la cabecera (indicar las ETRS89 oficiales en `base_xyz`
  para coordenadas absolutas), sin ANTEX (altura absoluta ± cm).

## Pruebas (anfitrión)
- Espalda: 7 casos nuevos en `firmware/back/V3_8_0/test/test_espnow.cpp` (trozos de cualquier longitud, pérdidas y
  duplicados, presupuesto de UART, cadena ZED simulado → espalda → pecho byte a byte, radio con pérdidas, receptor sin
  claves). 66 casos, 836 comprobaciones; ASan/UBSan limpio.
- Motor: `equine-intelligence/tests/test_ppk.cpp` con datos reales (`tests/data/ppk/README.md`):
  - CRINEX 3 de P433: 70 épocas, primera 20:56:45, 27 satélites; C1C − λ·L1C varía ≤ 4,4 m (reconstrucción correcta).
  - GEONET 2005, línea base de 3,3 km a 30 s, antena estática procesada como cinemática: **98 % FIX**, dispersión
    horizontal máx. 4,2 cm y vertical 9,5 cm, velocidad media < 5 mm/s.
  - La misma sesión convertida a RXM-RAWX y grabada en `.avr` con trozos (y entera, y con 1 trozo de cada 37 perdido):
    mismas épocas FIX y diferencia máxima de **0,07 cm** con la solución del RINEX.

## Apps
### iPad (23/11/2026) — IMPLEMENTADO, sin compilar (sin Xcode en la sesión; lo compila el CI al fusionar)
- Motor › botón **«PPK (base IGN)»** → hoja PPK: estación ERGNSS (código de 4 letras, se recuerda; botón «Ver estaciones
  disponibles a esa hora» lee el índice del IGN), «Calcular PPK», «Importar la base a mano» (RINEX de Archivos, también
  `.gz`) y resultado (FIX %, épocas, base, distancia a la base, avisos).
- Base del IGN, estructura comprobada por el usuario (capturas del 23/11): `http://datos-geodesia.ign.es/ERGNSS/horario_1s/AAAAMMDD/HH/`
  con `<EST>00ESP_R_AAAADDDHH00_01H_01S_MO.crx.gz` (observación) y `…_01H_MN.rnx.gz` (navegación). El servidor
  redirige https → http: **excepción ATS solo para `datos-geodesia.ign.es`** en `Info.plist` (aprobada por el usuario).
  gzip con el framework Compression (`Core/PpkService.swift`); Hatanaka en el motor.
- Orden: resultado guardado en el iPad → `AVO_<id>.ppk.json` de la nube (si su `avo_sha256` coincide con el `.avo`)
  → cálculo en el iPad y **subida a la nube** junto al `.avo`. Al descargar entrenamientos de la nube (Servidor ›
  Nube AVO) se intenta el PPK en segundo plano; si el IGN aún no ha publicado la hora, queda para otra vez.
- Pruebas: `AVOiPadTests/PpkTests.swift` (gzip, nombres del IGN, lectura de las respuestas del motor).

### Nube
- `firebase/storage.rules`: se admite `trainings/<CÓDIGO>/AVO_<id>.ppk.json` (≤ 10 MB, `application/json`, metadatos
  `sha256` y `avo_sha256`). Pruebas en `firebase/test/storage.test.js`. **Hay que publicarlas en la consola** (Storage ›
  Reglas). Las apps antiguas solo listan `.avo`: no ven el fichero nuevo.

## Diagnóstico desde la grabación: `BackStatus v5` (espalda 3.16.1)

La primera grabación real (27/11/2026 00:49, espalda 3.16.0, pecho 3.7.11) llevaba 407 `RXM-SFRBX` íntegros en tramas
0x12, pero **ningún `RXM-RAWX`**, y tampoco llegaba `NAV-SIG`. El receptor estaba en su **UART2**. Los mensajes cortos
(< 200 B) llegaban y los largos (1–2,5 KB) no. Para saber si el receptor no los envía o se pierden en la espalda sin
necesitar el monitor USB, la 3.16.1 añade 36 B al final del estado de la espalda (`STATUS` 0x41, 130 → **166 B**). El
pecho lo graba en el `.avr` tal cual. Los lectores v4 (pecho 3.7.11, apps) leen los primeros 130 B e ignoran el resto.

| Offset (desde 130) | Tipo | Campo |
|---|---|---|
| 0 | u8 | estado RAW (0 sin pedir, 1 activo, 2 rechazado, 3 UART lenta, 7 esperando ACK) |
| 1 | u8 | RAWX pedido (Hz) |
| 2 | u32 | `RXM-RAWX` recibidos del receptor |
| 6 | u32 | `RXM-SFRBX` recibidos del receptor |
| 10 | u32 | tramas RAW enviadas enteras al pecho |
| 14 | u32 | abandonadas (falló un trozo en ESP-NOW) |
| 18 | u16 | demasiado largas (> 4096 B) |
| 20 | u32 | UBX con checksum malo |
| 24 | u16 | UBX con longitud imposible |
| 26 | u32 | UBX válidos de **512 B o más** (0 = no llega ningún mensaje largo) |
| 30 | u16 | `NAV-SIG` recibidos |
| 32 | u8 | MON-COMMS: b0 respondido, b1–2 errores de TX del receptor (descarta salida) |
| 33 | u8 | pico del búfer TX del receptor (%) |
| 34 | u8 + u8 | firmware del receptor (`HPG 1.32` → 1, 32; 0, 0 sin leer) |

Vector de prueba en `firmware/back/V3_8_0/test/test_espnow.cpp` (`ppk.status_v5_roundtrip_and_shared_vector`).

Lectura: RAWX recibidos = 0 y UBX de ≥ 512 B = 0 con checksum malo ≈ 0 → el receptor no envía mensajes largos por
ese puerto (revisar el cableado al UART1). RAWX recibidos > 0 y enviados = 0 → fallo en la espalda.

### Resultado de la v5 y cambio en la 3.16.2

En la grabación de las 01:34 del 27/11 (espalda 3.16.1, receptor **HPG 1.51** en UART2 a 230 400 baudios), en los
primeros ~5 s llegaron 5 RAWX y 5 NAV-SIG. Después dejó de llegar cualquier mensaje de ≥ 512 B, con 0 UBX malos en la
espalda. MON-COMMS informó de **errores de TX del receptor** (memoria y reserva) con pico de búfer del 106 %. El
receptor descarta salida: no es la espalda.

La 3.16.2 reduce la salida del receptor: **RXM-SFRBX apagado** (unos 19 mensajes/s; las efemérides salen del RINEX de
navegación de la base, `_01H_MN.rnx.gz`, que el PPK ya descarga) y **NAV-SAT/NAV-SIG cada 5 s** en vez de cada
segundo, también el sondeo de respaldo. RAWX sigue a 1 Hz. Si con esto el receptor sigue descartando, el siguiente paso
es cablear la espalda al UART1 del ZED.

## Pendiente
1. Android y Windows: mismo flujo que el iPad (descarga del IGN, gzip, `avo_eq_ppk`, `.ppk.json` en la nube).
2. Usar las posiciones PPK en el análisis del motor (parciales, distancia y velocidad media por tramo) cuando existan.
3. Prueba física: espalda 3.16.0 en el banco (monitor serie «PPK: RAWX/SFRBX ACTIVO»), sesión en pista sin móvil,
   PPK con la estación ERGNSS más cercana y comparación con distancias medidas.
