# AVO BACK V5 CASCO · placa de la espalda para el casco · REV A (ESP32-S3 + ZED-F9P soldado) — informe de fabricación

- Estado: **DISEÑO VERIFICADO POR SOFTWARE — APTO PARA SOLICITAR PROTOTIPOS — PENDIENTE DE VALIDACIÓN FÍSICA**
- Commit: `c6b264870152dd1a16a8151b5b8ef59dbb9ccb89` · ejecución de CI: 43612963625
- Ruteado: placa ruteada de la fuente (Freerouting + reparación con fuente/repair.py)
- Placa: 51 × 51 mm (R3), 4 capas (F.Cu componentes y señal · In1.Cu GND · In2.Cu señal + relleno +3V3 · B.Cu plano GND macizo de la antena GNSS, sin pistas), 1,6 mm, ENIG, cobre exterior 1 oz
- Componentes: 88 en total, 68 para montar, 0 sin montar (DNP: —), 20 a mano (pads de hilo y de prueba)
- Pistas: 812 · vías: 171 · ruteado completo (0 conexiones incompletas)

## Comprobaciones bloqueantes
| Comprobación | Resultado | Cantidad |
|---|---|---|
| DRC: errores | correcto | 0 |
| DRC: conexiones incompletas | correcto | 0 |
| DRC: cortocircuitos | correcto | 0 |
| DRC: paridad esquema ↔ placa | correcto | 0 |
| ERC: errores | correcto | 0 |
| ERC: advertencias | correcto | 0 |


## Advertencias de DRC (no bloqueantes)
- silk_over_copper: 4
- silk_overlap: 1

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: ninguna
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 13; sin descargar: Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step, RF_GPS.3dshapes/ublox_ZED.step
- ESP32-S3-MINI-1U: modelo de Espressif (`fuente/3d`). Pads de hilo/prueba: sin modelo 3D.

## Existencias en JLCPCB (consulta del CI: 2026-11-14 15:55 UTC)
| LCSC | Pieza | Por placa | Existencias | Tipo | Precio (1 ud.) |
|---|---|---|---|---|---|
| C5120257 | ZED-F9P-04B | 1 | 895 | Extended | 76.2695 US$ |
| C2980299 | ESP32-S3-MINI-1U-N8 | 1 | 2857 | Extended | 4.7366 US$ |
| C114218 | DM3AT-SF-PEJM5 | 1 | 14931 | Extended | 1.3908 US$ |
| C140288 | BQ24072RGTR | 1 | 1219 | Extended | 1.0488 US$ |
| C485517 | TLV75733PDBVR | 1 | 20199 | Extended | 0.2078 US$ |
| C140921 | DRV5032FADBZR | 1 | 61540 | Extended | 0.1707 US$ |
| C7519 | USBLC6-2SC6 | 1 | 41434 | Extended | 0.1570 US$ |
| C841192 | RT9080-33GJ5 | 1 | 27658 | Extended | 0.1197 US$ |
| C20802 | SMD1206P150TF | 2 | 11303 | Extended | 0.1187 US$ |
| C45783 | CL21A226MAQNNNE | 3 | 4136701 | Basic | 0.1084 US$ |
| C15127 | AO3401A | 1 | 1526914 | Basic | 0.0814 US$ |
| C16780 | CL21A476MQYNNNE | 2 | 1268170 | Basic | 0.0743 US$ |
| C2827694 | PESD5V0S1BA | 2 | 330840 | Extended | 0.0359 US$ |
| C96446 | CL10A106MA8NRNC | 5 | 6173323 | Basic | 0.0342 US$ |
| C77131 | NCP15XH103F03RC | 1 | 297586 | Extended | 0.0164 US$ |
| C52923 | CL05A105KA5NQNC | 4 | 10250118 | Basic | 0.0057 US$ |
| C15195 | CL05B103KB5NNNC | 1 | 6083074 | Basic | 0.0037 US$ |
| C25867 | 0402WGF1501TCE | 1 | 1274558 | Basic | 0.0029 US$ |
| C1525 | CL05B104KO5NNNC | 6 | 38184330 | Basic | 0.0024 US$ |
| C4109 | 0402WGF2001TCE | 1 | 10026671 | Basic | 0.0019 US$ |
| C11702 | 0402WGF1001TCE | 4 | 31458906 | Basic | 0.0013 US$ |
| C26083 | 0402WGF1004TCE | 2 | 2332165 | Basic | 0.0012 US$ |
| C17168 | 0402WGF0000TCE | 1 | 15625434 | Basic | 0.0012 US$ |
| C25104 | 0402WGF3300TCE | 3 | 1490369 | Basic | 0.0011 US$ |
| C25092 | 0402WGF220JTCE | 3 | 4784854 | Basic | 0.0010 US$ |
| C25744 | 0402WGF1002TCE | 6 | 21086182 | Basic | 0.0010 US$ |
| C25741 | 0402WGF1003TCE | 8 | 10404587 | Basic | 0.0009 US$ |
| C17958 | ? | 1 | sin respuesta | Extended | ? |
| C97998 | ? | 1 | sin respuesta | Extended | ? |
| C10662 | ? | 1 | sin respuesta | Extended | ? |
| C88373 | ? | 1 | sin respuesta | Extended | ? |

- Piezas sin existencias para 5 placas: C17958, C97998, C10662, C88373

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **sí**
- Apto para solicitar prototipos: **sí, pendiente de validación física**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- Línea de 50 Ω de la antena (J5 → R71 0 Ω → RF_IN, ESD D4): microcinta de 0,36 mm calculada para el apilado JLC de 1,6 mm (preimpregnado 0,21 mm sobre In1); confirmar con la calculadora de JLC al pedir.
- Antena GNSS plana activa L1/L2 pegada en el centro de la cara B; plano de masa de 51 × 51 (el fabricante afina sobre 70 × 70): medir fix y velocidad.
- ZED-F9P-04B montado por JLCPCB (C5120257, Extended; 895 uds. y 76,27 US$ el 14/11/2026): comprobar existencias el día del pedido.
- Alimentación de la antena: 22 Ω en 1206 (corto del coaxial ≈ 150 mA, ≈ 0,5 W durante el fallo): sin limitador activo ni uso de ANT_SHORT_N.
- Firmware: poner GPIO6, GPIO8 y GPIO9 como entradas antes de bajar ZED_EN (el ZED apagado no debe recibir tensión por sus E/S).
- Pines 9/10 de la microSD Hirose DM3AT según la huella de KiCad: comprobar con la hoja.
- Pogo de 5 contactos y batería por hilos: el modelo real del pogo está pendiente (STEP).
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
