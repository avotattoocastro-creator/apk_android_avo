# AVO GIRTH · placa de la cincha · REV D (ESP32-C6 + LSM6DSV16X + MMC5983MA + ADS1292, ECG) — informe de diagnóstico

- Estado: **DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar
- Commit: `f12567bfb30c295483121a28a8882b4d809afd67` · ejecución de CI: 43710447179
- Ruteado: Freerouting 1.9.0 sobre la placa de colocación (sin reparar)
- Placa: 46 × 30 mm (R2), 4 capas (F.Cu componentes, señal y relleno GND · In1.Cu GND macizo · In2.Cu señal + relleno +3V3 · B.Cu señal y relleno GND), 1,0 mm, ENIG, cobre exterior 1 oz
- Componentes: 78 en total, 61 para montar, 1 sin montar (DNP: C54), 16 a mano (pads de hilo y de prueba)
- Pistas: 705 · vías: 119 · ruteado INCOMPLETO (8 conexiones)

## Comprobaciones bloqueantes
| Comprobación | Resultado | Cantidad |
|---|---|---|
| DRC: errores | correcto | 0 |
| DRC: conexiones incompletas | **FALLA** | 8 |
| DRC: cortocircuitos | correcto | 0 |
| DRC: paridad esquema ↔ placa | correcto | 0 |
| ERC: errores | correcto | 0 |
| ERC: advertencias | correcto | 0 |


### Conexiones incompletas
- Track [+3V3] on In2.Cu, length 8.5092 mm ↔ Pad 14 [+3V3] of U6 on F.Cu
- Pad 5 [+3V3] of U5 on F.Cu ↔ Track [+3V3] on F.Cu, length 0.6788 mm
- Track [+3V3A] on F.Cu, length 0.2000 mm ↔ Pad 12 [+3V3A] of U6 on F.Cu
- Zone [GND] on F.Cu, priority 0 ↔ Pad 14 [GND] of U4 on F.Cu
- Track [VSYS] on F.Cu, length 2.6680 mm ↔ Track [VSYS] on F.Cu, length 0.5000 mm
- Track [ECGP] on F.Cu, length 0.7164 mm ↔ Pad 6 [ECGP] of U6 on F.Cu
- Pad 18 [ECG_CS] of U6 on F.Cu ↔ Pad 12 [ECG_CS] of U4 on F.Cu
- PTH pad 1 [POGO_5V] of P1 ↔ Track [POGO_5V] on F.Cu, length 3.3564 mm

## Advertencias de DRC (no bloqueantes)
- silk_over_copper: 4
- silk_overlap: 2

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: ninguna
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 9; sin descargar: Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step
- ESP32-C6-MINI-1U: modelo de Espressif (`fuente/3d`). LSM6DSV16X, MMC5983MA, ADS1292 y pads de hilo/prueba: sin modelo 3D.

## Existencias en JLCPCB (consulta del CI: 2026-11-15 09:10 UTC)
| LCSC | Pieza | Por placa | Existencias | Tipo | Precio (1 ud.) |
|---|---|---|---|---|---|
| C544416 | ADS1292IRSMR | 1 | 2953 | Extended | 5.7657 US$ |
| C20627095 | ESP32-C6-MINI-1U-H4 | 1 | 3425 | Extended | 4.1902 US$ |
| C5267406 | LSM6DSV16XTR | 1 | 6523 | Extended | 2.9369 US$ |
| C404329 | MMC5983MA | 1 | 5716 | Extended | 1.9896 US$ |
| C140288 | BQ24072RGTR | 1 | 1216 | Extended | 1.0488 US$ |
| C7192 | TAJB105K035RNJ | 1 | 26712 | Extended | 0.2898 US$ |
| C841192 | RT9080-33GJ5 | 2 | 27566 | Extended | 0.1197 US$ |
| C20802 | SMD1206P150TF | 2 | 11293 | Extended | 0.1187 US$ |
| C45783 | CL21A226MAQNNNE | 2 | 4120506 | Basic | 0.1084 US$ |
| C2827694 | PESD5V0S1BA | 2 | 330776 | Extended | 0.0359 US$ |
| C96446 | CL10A106MA8NRNC | 7 | 6146056 | Basic | 0.0342 US$ |
| C85980 | GRM1885C1H472JA01D | 2 | 107669 | Extended | 0.0187 US$ |
| C668348 | GRM1555C1H152JA01D | 1 | 68649 | Extended | 0.0179 US$ |
| C77131 | NCP15XH103F03RC | 1 | 297342 | Extended | 0.0164 US$ |
| C2286 | KT-0603R | 1 | 5778398 | Basic | 0.0077 US$ |
| C52923 | CL05A105KA5NQNC | 5 | 10280744 | Basic | 0.0057 US$ |
| C53547 | 0402CG102J500NT | 2 | 472693 | Extended | 0.0050 US$ |
| C1525 | CL05B104KO5NNNC | 8 | 38113115 | Basic | 0.0024 US$ |
| C4109 | 0402WGF2001TCE | 1 | 10027954 | Basic | 0.0019 US$ |
| C25792 | 0402WGF4702TCE | 2 | 5707267 | Basic | 0.0019 US$ |
| C11702 | 0402WGF1001TCE | 2 | 31426879 | Basic | 0.0013 US$ |
| C26083 | 0402WGF1004TCE | 3 | 2341718 | Basic | 0.0012 US$ |
| C25879 | 0402WGF2201TCE | 3 | 3053586 | Basic | 0.0011 US$ |
| C25744 | 0402WGF1002TCE | 6 | 21069013 | Basic | 0.0010 US$ |
| C25741 | 0402WGF1003TCE | 3 | 10386367 | Basic | 0.0009 US$ |

- Piezas sin existencias para 5 placas: ninguna

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **no**
- Apto para solicitar prototipos: **no**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- Todas las piezas montadas tienen código LCSC; comprobar existencias el día del pedido (out_stock).
- ADS1292: canal 2 = ECG con RLD al electrodo de referencia; canal 1 apagado; respiración no incluida en esta revisión.
- VCAP1 en C0G (no ferroeléctrico) por la vibración, como pide la hoja de TI.
- LSM6DSV16X y MMC5983MA por I²C a 400 kHz; ejes de la placa a comprobar con el firmware 0.6.0.
- Batería de 1000 mAh (603450) con carga de ≈ 445 mA: base de carga de ≥ 1 A (DOCS/CONSUMO_BATERIA.md).
- Primera programación por los pads TP4/TP5 (USB nativo) con pinza de pogo-pins; después por radio.
- Pad de esquina 51 del C6-MINI-1U sin conectar (GND de anclaje encerrado por las salidas de los pads 24/25).
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
