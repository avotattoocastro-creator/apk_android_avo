# AVO BACK V5 · CASCO — espalda GNSS RTK montada en el casco (propuesta de arquitectura)

**Estado (14/11/2026):** propuesta para confirmar. No hay PCB, CAD de fabricación ni firmware.
Medidas y pesos **estimados (E)**; ninguno está medido.

## Requisitos del usuario (14/11/2026)
- Se monta en el casco del jockey **solo en entrenamientos**.
- Sujeción en una **base magnética desprendible**.
- Lo más compacta y ligera posible, **sin perder prestaciones**.
- PCB propia con **antena plana activa RTK**.
- **Batería de 2000 mAh como mínimo**, lo más plana posible; autonomía como ahora (~8 h).
- **Conector pogo con las líneas del USB**, para cargar y para leer con el PC por él.
- **Caja totalmente estanca**: sin USB-C, sin botones y sin aberturas.
- Planta de unos 55 × 55 mm, aceptando algo de pérdida de RTK frente al plano de masa de 70 × 70.

## Qué se conserva de la V4 (prestaciones)
- Funciones de la V4: BLE, Wi-Fi, ESP-NOW con el pecho y las cinchas (GirthHub), microSD y PPS. Ahora repartidas entre dos ESP32 (ver más abajo).
- u-blox ZED-F9P, multibanda L1/L2 con RTK, a 8 Hz.
- Cargador BQ24072, regulador TLV75733P y RT9080 para el ZED con EN en GPIO10.
- microSD alimentada por PMOS.
- Contratos binarios sin cambios: `BackStatus` v3 (108 B), lotes de cincha (220 B), RTCM3 y `.avr`. **Desde fuera la unidad sigue siendo «la espalda».**

## Qué cambia
| | V4 (chaleco) | V5 casco (propuesta) |
|---|---|---|
| GNSS | placa URTK1.2 (43,4 × 43,7) con mazo | **ZED-F9P soldado en la PCB** |
| Antena | Q39 externa (Ø44,3 × 40,8) | **antena plana activa L1/L2 de 25 × 25 × 8,1** sobre la PCB, por ejemplo la Taoglas AHP2258 (20 g, IPEX) |
| Plano de masa de la antena | — | toda la cara superior de la PCB, 51 × 51 (el fabricante afina sobre 70 × 70) |
| Componentes | por las dos caras | **todos en la cara inferior**, para que la superior sea masa continua |
| Batería | 654060 (60 × 40 × 6,5) | **≥ 2000 mAh en 45 × 50 × ~7 (E)**, bajo la PCB |
| Conexión exterior | 3 contactos (SYS, BAT, GND) + USB-C | **pogo magnético de 5 contactos**: VBUS · D− · D+ · GND · libre |
| Encendido | puente SYS–BAT en el soporte | **sensor Hall (DRV5032) + imán en la base del casco**: se enciende al ponerla. También al conectar el cable (VBUS) |
| Datos con el PC | USB-C del taller | **USB nativo del ESP32-S3 (GPIO19/20) por el pogo**, con ESD USBLC6-2SC6. Sirve para la carga, la descarga de sesiones y la programación |

## Decisión final del usuario (14/11/2026, 13:40): UN SOLO ESP32-S3
Hace BLE con el móvil y ESP-NOW con el pecho y las cinchas a la vez, igual que ya hace el pecho, que en la prueba del 02/11 pasó 1,1 MB de RTCM sin ningún CRC erróneo. Autonomía de unos 8 h con 2000 mAh.
**La PCB REV A está hecha así:** `hardware/back/V5_CASCO/PCB/`. La propuesta de dos chips que sigue queda **descartada**; se guarda como referencia.

## (Descartada) Propuesta de 13:29: dos ESP32 con funciones separadas
Esta decisión sustituye a la de un solo ESP32-S3 que se tomó para la V4.

| Chip | Función | Por qué este chip |
|---|---|---|
| **ESP32-C6-MINI-1U** («radio de equipos») | ESP-NOW con la cincha (GirthHub) y con el pecho, y **futuros equipos** | Es el mismo chip que la cincha. Tiene Wi-Fi 6, BLE 5 y 802.15.4 (Thread/Zigbee), útil para sensores futuros |
| **ESP32-S3-MINI-1U-N8** («registro y móvil») | ZED-F9P por UART, PPS, microSD (SDMMC), **BLE/Wi-Fi con el móvil para NTRIP**, USB nativo por el pogo (carga, descarga y programación) | Tiene USB OTG y SDMMC de 4 bits, como en la V4 |

### Enlace entre los dos chips
- **UART a 2–3 Mbaud con tramas COBS + CRC**, el formato AVO UART v1 que ya usa el proyecto, más RTS/CTS.
  - El C6 pasa al S3 los lotes de la cincha, tal cual (220 B).
  - El S3 pasa al C6 lo que hay que enviar al pecho.
- **PPS del ZED a los dos chips**, para tener la misma marca de tiempo en los dos.
- **EN y BOOT del C6 controlados por el S3:** el S3 programa el C6 por el UART, así que con un solo USB en el pogo se actualizan los dos.
- **Línea de coordinación de radio:** 1 GPIO en cada sentido, «voy a transmitir» y «estoy recibiendo».
  - Las dos radios están en 2,4 GHz a pocos centímetros y sin el árbitro de coexistencia que tiene un solo chip.
  - El S3 usa sobre todo **BLE** con el móvil y retrasa sus ráfagas mientras el C6 recibe un lote.
  - Si el S3 usa Wi-Fi, conviene el mismo canal que ESP-NOW.
- **Antenas de 2,4 GHz:** dos FPC en esquinas opuestas, lo más lejos posible entre ellas y de la antena GNSS. **Hay que medir los paquetes perdidos** con las dos radios activas a la vez.

### Consumo y autonomía con dos ESP32 (estimado)
- El C6 escuchando ESP-NOW de forma continua añade unos 75–95 mA, así que el total pasa a **≈ 300–320 mA**.
- **Con 2000 mAh salen unas 5,5–6 h** (antes ~8 h).
- **Para 8 h hacen falta unos 2700 mAh**, por ejemplo 45 × 50 × ~9,5 mm (E): **+2,5 mm de alto** (cápsula de ≈ 55 × 55 × 25) y **+12 g**, lo que da unos 117 g de cápsula y **≈ 127 g en el casco**.
- Otra opción es mantener 2000 mAh y aceptar unas 6 h.

### Planta de la PCB de 51 × 51
Caben en la cara inferior: ZED-F9P (17 × 22), S3 (15,4 × 15,4), C6 (13,2 × 16,6), microSD, cargador y reguladores, unos 1500 de los 2600 mm². Va justo, pero cabe.
Las dos antenas de 2,4 GHz van en los cantos, por fuera del plano de masa de la antena GNSS.

## Medidas y peso (estimados)
- **Cápsula: 55 × 55 × 22,6 mm** (esquinas R5).
  - Desde abajo: suelo 1,4; batería 7,0; holgura 0,4; componentes 2,6; PCB 1,6; antena 8,1; holgura 0,3; tapa 1,2.
  - **La altura la marca la antena** (8,1 de los 22,6).
- **Base del casco:** 55 × 55 × ~3, con 4 imanes y cinta VHB. **Sobre el casco: unos 25,6 mm en total.**
- Plano de concepto: `AVO_BACK_V5_CASCO_concepto.png` (fuente `concepto_plano.py`).

| Pieza | Peso (E) |
|---|---|
| Batería ≥ 2000 mAh | 38 g |
| Antena activa L1/L2 25 × 25 con cable | 20 g |
| PCB de 4 capas con componentes (ZED, S3, microSD, cargador…) | 14 g |
| Caja PETG (base y tapa, pared de 2,0, maciza) | 24 g |
| Pogo, junta TPU, tornillos, insertos, epoxi y microSD | 7 g |
| 4 imanes de la cápsula | 2 g |
| **Cápsula** | **≈ 105 g** |
| Base del casco (PETG, 4 imanes, VHB) | ≈ 10 g |
| **Total en el casco** | **≈ 115 g (100–125 g)** |

Referencia: solo las piezas impresas de la V4 pesan unos 131 g. Las de la Rev E.5 con la Heltec pesan 208 g, sin contar la electrónica ni la antena.

## Consumo y autonomía (estimados)
- El consumo es el de la V4, unos 230 mA. La antena plana gasta unos 10 mA (la Q39, unos 15 mA), así que el total queda en **≈ 225 mA**.
- Con 2000 mAh (≈ 1800 útiles): **≈ 8 h**. Va justo; con 2200–2500 mAh hay margen, a cambio de +1 mm.
- Dormida: unos 45 µA con el Hall, lo que da meses de reposo.

## Sujeción desprendible
- **Imanes:** 4 de Ø6 × 2 N52 por lado (E), con unos 30 N de tracción en total.
- **Centrado:** borde cónico a 45°. Aguanta el cortante del galope (cápsula de 105 g × 5 g ≈ 5 N) y se suelta con un golpe.
- **Validación:** la fuerza real se mide con dinamómetro antes de usarla.
- **Cinta VHB sobre la carcasa del casco:** sin taladrar. Hay que comprobar con el fabricante del casco que el adhesivo no ataca la carcasa.
- **Cuidado:** un estudio del TRL no encontró más riesgo de lesión con cámaras en el casco en las pruebas de impacto. Aun así, British Eventing mantiene la prohibición. Por eso esta unidad es **solo para entrenamiento** y no se ha validado para carreras.

## Riesgos por validar antes de la PCB
1. **RTK con un plano de masa de 51 × 51** (en lugar de 70 × 70): tiempo hasta el fijo y porcentaje de fijo al galope.
   - **Prueba previa sin PCB:** una o dos antenas candidatas sobre una chapa de cobre de 51 × 51, conectadas a la URTK1.2 actual. Se comparan con la Q39 en el mismo recorrido.
2. **Elegir la antena:** tiene que cubrir L1 y L2 (más E5b), porque el ZED-F9P no usa L5. Una antena L1/L5, como la Taoglas AGVB.25A, **no sirve** con el ZED-F9P-01B.
3. **Radio de 2,4 GHz a ~30 mm de la antena GNSS:** el S3 va en la esquina opuesta, con filtrado y, si hace falta, una tapa de blindaje.
4. **Enlace casco ↔ cincha** (unos 1,5 m, con el cuerpo del jinete en medio): medir los paquetes perdidos de ESP-NOW.
5. **La cabeza no es el tronco:** la velocidad del GNSS es la del casco. Hay que validar con vídeo las métricas de zancada que salen del GNSS. La cadencia sigue saliendo de la cincha.
6. **Estanqueidad:** junta TPU, 6 tornillos M2,5 y el pogo sellado con epoxi, como en la cincha. Prueba de inmersión.
7. **Pogo de 5 contactos:** pedir el STEP del modelo real. USB full-speed (12 Mbit/s) por contactos de muelle: probar la descarga.

## Siguientes pasos (después de confirmar)
1. Prueba previa de la antena (punto 1).
2. Esquema y PCB de 51 × 51 en KiCad 9, reutilizando los bloques de la V4 REV B.
3. CAD de la cápsula y de la base, con prueba impresa.
4. Firmware BACK 5.x, derivado de la V4 4.0.0-dev2: USB nativo (MSC/CDC por el pogo) y Hall.
   **La 4.0.0-dev2 no se instala en el hardware actual.**

Fuentes:
[Taoglas AHP2258 (L1/L2, 25 × 25, 20 g, plano de 70 × 70)](https://taoglas.com/product/active-gnss-l1-l2-band-antenna) ·
[Taoglas AGVB.25A (L1/L5)](https://www.taoglas.com/datasheets/AGVB.25A.07.0060A.pdf) ·
[Antenova: requisitos de antena para el ZED-F9P](https://ask.antenova.com/1050/best-active-gnss-antena-for-zed-f9p-in-small-foot-print) ·
[Horse & Hound: estudio TRL sobre cámaras en el casco](https://www.horseandhound.co.uk/plus/helmet-cameras-latest-research-523412) ·
[IHRB: normas de cascos](https://www.ihrb.ie/safety-equipment-for-riding-out/)
