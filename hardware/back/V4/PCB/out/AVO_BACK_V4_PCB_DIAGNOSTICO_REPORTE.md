# AVO BACK V4 · placa de la espalda · REV A (ESP32-S3) — informe de diagnóstico

- Estado: **DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar
- Commit: `7ee8318d82db8122947e4a0963250b302d256035` · ejecución de CI: 40957092657
- Ruteado: Freerouting 1.9.0 sobre la placa de colocación (sin reparar)
- Placa: 4 capas (F.Cu señal · In1.Cu GND · In2.Cu señal + relleno +3V3 · B.Cu señal + GND), 1,0 mm, ENIG, cobre exterior 1 oz; contorno de la cola de la carcasa V4 (CAD/pcb_contorno_v4.json), ≈ 1785 mm²
- Componentes: 99 en total, 85 para montar, 1 sin montar (DNP: C5), 13 a mano (pads de hilo y de prueba)
- Pistas: 1043 · vías: 177 · ruteado INCOMPLETO (7 conexiones)

## Comprobaciones bloqueantes
| Comprobación | Resultado | Cantidad |
|---|---|---|
| DRC: errores | **FALLA** | 3 |
| DRC: conexiones incompletas | **FALLA** | 7 |
| DRC: cortocircuitos | correcto | 0 |
| DRC: paridad esquema ↔ placa | correcto | 0 |
| ERC: errores | correcto | 0 |
| ERC: advertencias | correcto | 0 |

Errores de DRC por tipo: copper_edge_clearance 3

### Conexiones incompletas
- Track [VBUS] on F.Cu, length 2.4505 mm ↔ Pad A9 [VBUS] of J1 on F.Cu
- Pad 1 [VIN5] of C18 on F.Cu ↔ Track [VIN5] on In2.Cu, length 7.6330 mm
- Pad 10 [VSYS] of U2 on F.Cu ↔ Pad 11 [VSYS] of U2 on F.Cu
- Track [VSYS] on In2.Cu, length 2.9856 mm ↔ Pad 10 [VSYS] of U2 on F.Cu
- Pad 12 [CHG_ILIM] of U2 on F.Cu ↔ Pad 1 [CHG_ILIM] of R7 on F.Cu
- Pad 7 [QI_CHG] of U1 on F.Cu ↔ Track [QI_CHG] on In2.Cu, length 0.0543 mm
- Pad 1 [QI_COMM1] of C8 on F.Cu ↔ Pad 6 [QI_COMM1] of U1 on F.Cu

## Advertencias de DRC (no bloqueantes)
- connection_width: 2
- silk_edge_clearance: 2

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: ninguna
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 11; sin descargar: Connector_JST.3dshapes/JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.step, Connector_USB.3dshapes/USB_C_Receptacle_HRO_TYPE-C-31-M-12.step, Package_DFN_QFN.3dshapes/Texas_VQFN-RHL-20.step, Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step
- ESP32-S3-MINI-1U: modelo de Espressif (`fuente/3d`). Pads de hilo/prueba: sin modelo 3D.

## Diseño de la placa (texto fijo del generador)
- **MCU**: ESP32-S3-MINI-1U-N8 (8 MB, sin PSRAM), antena externa por el conector del módulo → antena FPC de 2,4 GHz en el
  techo del cuello (a ~75 mm de la antena GNSS). Un solo ESP32: comparación en `DOCS/ARQUITECTURA_Y_CONSUMO.md`.
- **Alimentación**: BQ51013B (Qi) + BQ24072 (camino de potencia, 445 mA de carga) · PTC 1,5 A + PMOS de polaridad ·
  TLV75733P 1 A (ESP32-S3 + microSD) · **RT9080 propio del ZED con EN (GPIO10)**.
- **ZED-F9P (URTK1.2)**: 8 pads pasantes (J4) para el mazo: 3V3_ZED, GND, UART1, UART2, PPS, RESET; serie de 1 kΩ en
  las salidas del ESP32 y de 330 Ω en las entradas.
- **microSD**: Hirose DM3AT-SF-PEJM5, SDMMC 4 bits, alimentación conmutada (AO3401A, GPIO21).
- **Soporte**: Hall DRV5032FA (salida push-pull) en GPIO1 (despertador ext0); sustituye al reed.
- **Mecánica**: contorno, pivotes, pisadores y anillos generados con el CAD V4 (`pcb_contorno_v4.json`,
  `pcb_mecanica.json`); alturas de componentes limitadas por zona (bajo la URTK1.2 5,8 mm, bajo J2/L 2,3 mm, topes
  de la L 3,8 mm, resto 10,9 mm).

## Pines del ESP32-S3
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 0 | BOOT (TP2) | 12–17 | microSD CLK (22 Ω), CMD, D0–D3 (10 k a 3V3_SD) |
| 1 | Hall (LOW = en el soporte) | 18 | detección de tarjeta (100 k) |
| 2 | VBAT/2 (ADC1) | 19 / 20 | USB D− / D+ |
| 4 | PPS del ZED | 21 | alimentación microSD (LOW = encendida) |
| 5 / 6 | RX / TX ↔ UART1 del ZED | 38 / 39 / 40 | PGOOD / CHG del BQ24072, CHG del BQ51013B |
| 7 / 8 | RX / TX ↔ UART2 del ZED (la que usa el firmware) | 41 | libre (TP10) |
| 9 | RESET_N del ZED | 43 / 44 | TXD0 / RXD0 (TP4 / TP5) |
| 10 | EN del regulador del ZED | 11 | LED (activo bajo) |

## Existencias en JLCPCB (consulta del CI: 2026-10-29 17:03 UTC)
| LCSC | Pieza | Por placa | Existencias | Tipo | Precio (1 ud.) |
|---|---|---|---|---|---|
| C2980299 | ESP32-S3-MINI-1U-N8 | 1 | 2475 | Extended | 4.7656 US$ |
| C55663 | BQ51013BRHLR | 1 | 476 | Extended | 3.6045 US$ |
| C114218 | DM3AT-SF-PEJM5 | 1 | 19399 | Extended | 1.3920 US$ |
| C140288 | BQ24072RGTR | 1 | 2868 | Extended | 0.9957 US$ |
| C97946 | GRM31C5C1H104JA01L | 2 | 67333 | Extended | 0.2773 US$ |
| C485517 | TLV75733PDBVR | 1 | 31607 | Extended | 0.2161 US$ |
| C45783 | CL21A226MAQNNNE | 3 | 3827085 | Basic | 0.1918 US$ |
| C165948 | TYPE-C-31-M-12 | 1 | 289232 | Extended | 0.1871 US$ |
| C7519 | USBLC6-2SC6 | 1 | 38847 | Extended | 0.1798 US$ |
| C140921 | DRV5032FADBZR | 1 | 44668 | Extended | 0.1750 US$ |
| C21812 | GRM31M5C1H473JA01L | 1 | 66831 | Extended | 0.1689 US$ |
| C160402 | SM02B-SRSS-TB(LF)(SN) | 1 | 75734 | Extended | 0.1324 US$ |
| C841192 | RT9080-33GJ5 | 1 | 36708 | Extended | 0.1198 US$ |
| C20802 | SMD1206P150TF | 1 | 11710 | Extended | 0.1188 US$ |
| C16780 | CL21A476MQYNNNE | 2 | 1051141 | Basic | 0.1019 US$ |
| C15127 | AO3401A | 4 | 948884 | Basic | 0.0960 US$ |
| C51795 | 0805CG222J500NT | 1 | 3262 | Extended | 0.0425 US$ |
| C96446 | CL10A106MA8NRNC | 8 | 8289244 | Basic | 0.0387 US$ |
| C77131 | NCP15XH103F03RC | 2 | 304175 | Extended | 0.0187 US$ |
| C1623 | CL10B474KA8NNNC | 2 | 690947 | Basic | 0.0130 US$ |
| C2286 | KT-0603R | 1 | 7355952 | Basic | 0.0077 US$ |
| C52923 | CL05A105KA5NQNC | 5 | 10462929 | Basic | 0.0064 US$ |
| C1532 | 0402B223K500NT | 2 | 610127 | Basic | 0.0049 US$ |
| C15195 | CL05B103KB5NNNC | 2 | 6252722 | Basic | 0.0039 US$ |
| C1525 | CL05B104KO5NNNC | 6 | 32018469 | Basic | 0.0031 US$ |
| C25087 | 0402WGF2000TCE | 1 | 1923640 | Basic | 0.0029 US$ |
| C4109 | 0402WGF2001TCE | 2 | 10037510 | Basic | 0.0026 US$ |
| C25744 | 0402WGF1002TCE | 7 | 17205666 | Basic | 0.0024 US$ |
| C25905 | 0402WGF5101TCE | 2 | 3839517 | Basic | 0.0023 US$ |
| C26083 | 0402WGF1004TCE | 2 | 3011950 | Basic | 0.0015 US$ |
| C25092 | 0402WGF220JTCE | 3 | 2991830 | Basic | 0.0014 US$ |
| C11702 | 0402WGF1001TCE | 4 | 21922409 | Basic | 0.0013 US$ |
| C25741 | 0402WGF1003TCE | 7 | 8556411 | Basic | 0.0012 US$ |
| C25104 | 0402WGF3300TCE | 4 | 2206034 | Basic | 0.0011 US$ |
| C25765 | 0402WGF2002TCE | 1 | 2906692 | Basic | 0.0011 US$ |

- Piezas sin existencias para 5 placas: ninguna

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **no**
- Apto para solicitar prototipos: **no**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- Inductancia de la bobina Qi sin medir: C1–C5 con valores supuestos (como la cincha).
- Pinout de la URTK1.2 por verificar con polímetro antes de hacer el mazo (DOCS/INTEGRACION_GNSS.md).
- Pines 9/10 (detección) de la microSD Hirose DM3AT según la huella de KiCad: comprobar con la hoja.
- Batería 654060 con clavija PH2.0: cambiarla a JST SH 1,0 (J2) y comprobar la polaridad.
- Existencias consultadas en el CI (out_stock/stock_jlc.json): volver a comprobarlas el día del pedido.
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
