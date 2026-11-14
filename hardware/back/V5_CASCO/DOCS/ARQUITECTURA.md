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
- ESP32-S3-MINI-1U-N8, que lleva BLE, Wi-Fi, ESP-NOW con el pecho y las cinchas (GirthHub), microSD y PPS.
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
