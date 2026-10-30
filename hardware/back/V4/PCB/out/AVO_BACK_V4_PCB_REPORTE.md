# AVO BACK V4 · placa de la espalda · REV B (ESP32-S3, contactos pogo) — informe de fabricación

- Estado: **DISEÑO VERIFICADO POR SOFTWARE — APTO PARA SOLICITAR PROTOTIPOS — PENDIENTE DE VALIDACIÓN FÍSICA**
- Commit: `c1e0e26b63beb865c8883951074bc387bdedbc01` · ejecución de CI: 41048486880
- Ruteado: placa ruteada de la fuente (Freerouting + reparación con fuente/repair.py)
- Placa: 4 capas (F.Cu señal · In1.Cu GND · In2.Cu señal + relleno +3V3 · B.Cu señal + GND), 1,0 mm, ENIG, cobre exterior 1 oz; contorno de la cola de la carcasa V4 (CAD/pcb_contorno_v4.json), ≈ 1785 mm²
- Componentes: 75 en total, 61 para montar, 0 sin montar (DNP: —), 14 a mano (pads de hilo y de prueba)
- Pistas: 791 · vías: 173 · ruteado completo (0 conexiones incompletas)

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
- track_dangling: 3
- silk_edge_clearance: 2
- silk_over_copper: 2

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: ninguna
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 11; sin descargar: Connector_JST.3dshapes/JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.step, Connector_USB.3dshapes/USB_C_Receptacle_HRO_TYPE-C-31-M-12.step, Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step
- ESP32-S3-MINI-1U: modelo de Espressif (`fuente/3d`). Pads de hilo/prueba: sin modelo 3D.

## Diseño de la placa REV B (texto fijo del generador)
- **Cambio respecto a la REV A** (congelada en `PCB_REV_A_QI/`): sin receptor Qi (BQ51013B, bobina y 22 piezas) y sin
  sensor Hall. La alimentación entra por **3 contactos en el fondo de la cápsula** (tornillo M2 avellanado de acero
  inoxidable desde fuera + tuerca M2 sobre la placa; junta tórica 2 × 1 entre la base y la placa alrededor de cada
  tornillo).
- **Contactos**: **SYS** (P1) y **BAT** (P2) en la cola, donde estaban el reed / el Hall, a 5,8 mm; **GND** (P3) aparte,
  en el centro de la placa, lejos de BAT.
  - **Soporte del chaleco**: puente entre SYS y BAT → la celda alimenta la electrónica. Fuera del soporte la placa no
    tiene alimentación (0 µA; sin sueño profundo ni sensor).
  - **Base de carga**: cargador Li-ion externo (CC/CV 4,2 V, ≤ 1 A) entre BAT y GND; SYS sin conectar → la electrónica
    está apagada mientras carga.
- **Batería**: celda → J2 → F1 (PTC 1,5 A) → contacto BAT. Contacto SYS → Q3 (PMOS de polaridad) → BAT del BQ24072.
  TVS bidireccionales de 5 V (D2, D3: PESD5V0S1BA, C2827694) en los dos contactos que tocan el exterior.
- **USB-C del taller**: BQ24072 (camino de potencia, 445 mA de carga): con USB la placa funciona sin batería y, si la
  cápsula está en el soporte del chaleco, carga la celda a través del puente.
- **MCU**: ESP32-S3-MINI-1U-N8 (8 MB, sin PSRAM), antena externa → antena FPC de 2,4 GHz en el techo del cuello.
- **ZED-F9P (URTK1.2)**: 8 pads pasantes (J4) para el mazo: 3V3_ZED, GND, UART1, UART2, PPS, RESET; RT9080 propio con EN
  (GPIO10).
- **microSD**: Hirose DM3AT-SF-PEJM5, SDMMC 4 bits, alimentación conmutada (AO3401A, GPIO21). Al quitar la cápsula del
  soporte se corta la alimentación sin aviso: el firmware vacía el fichero cada segundo.

## Pines del ESP32-S3
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 0 | BOOT (TP2) | 12–17 | microSD CLK (22 Ω), CMD, D0–D3 (10 k a 3V3_SD) |
| 1 | libre (REV A: Hall) | 18 | detección de tarjeta (100 k) |
| 2 | VBAT/2 (ADC1) | 19 / 20 | USB D− / D+ |
| 4 | PPS del ZED | 21 | alimentación microSD (LOW = encendida) |
| 5 / 6 | RX / TX ↔ UART1 del ZED | 38 / 39 | PGOOD / CHG del BQ24072 |
| 7 / 8 | RX / TX ↔ UART2 del ZED (la que usa el firmware) | 40 / 41 | libre (REV A: CHG del Qi) / libre (TP10) |
| 9 | RESET_N del ZED | 43 / 44 | TXD0 / RXD0 (TP4 / TP5) |
| 10 | EN del regulador del ZED | 11 | LED (activo bajo) |

## Existencias en JLCPCB (consulta del CI: 2026-10-30 10:37 UTC)
| LCSC | Pieza | Por placa | Existencias | Tipo | Precio (1 ud.) |
|---|---|---|---|---|---|
| C2980299 | ESP32-S3-MINI-1U-N8 | 1 | 2476 | Extended | 4.7689 US$ |
| C114218 | DM3AT-SF-PEJM5 | 1 | 19353 | Extended | 1.3930 US$ |
| C140288 | BQ24072RGTR | 1 | 2861 | Extended | 0.9964 US$ |
| C485517 | TLV75733PDBVR | 1 | 30076 | Extended | 0.2162 US$ |
| C45783 | CL21A226MAQNNNE | 3 | 3511830 | Basic | 0.1920 US$ |
| C165948 | TYPE-C-31-M-12 | 1 | 284585 | Extended | 0.1872 US$ |
| C7519 | USBLC6-2SC6 | 1 | 34295 | Extended | 0.1799 US$ |
| C160402 | SM02B-SRSS-TB(LF)(SN) | 1 | 75017 | Extended | 0.1325 US$ |
| C841192 | RT9080-33GJ5 | 1 | 36403 | Extended | 0.1198 US$ |
| C20802 | SMD1206P150TF | 1 | 11691 | Extended | 0.1189 US$ |
| C16780 | CL21A476MQYNNNE | 2 | 1043100 | Basic | 0.1020 US$ |
| C15127 | AO3401A | 2 | 1019514 | Basic | 0.0961 US$ |
| C96446 | CL10A106MA8NRNC | 5 | 8141381 | Basic | 0.0377 US$ |
| C77131 | NCP15XH103F03RC | 1 | 300534 | Extended | 0.0187 US$ |
| C2286 | KT-0603R | 1 | 7299516 | Basic | 0.0077 US$ |
| C52923 | CL05A105KA5NQNC | 4 | 10277067 | Basic | 0.0064 US$ |
| C1525 | CL05B104KO5NNNC | 3 | 36046904 | Basic | 0.0031 US$ |
| C4109 | 0402WGF2001TCE | 2 | 10000134 | Basic | 0.0026 US$ |
| C25744 | 0402WGF1002TCE | 7 | 16775240 | Basic | 0.0024 US$ |
| C25905 | 0402WGF5101TCE | 2 | 3771850 | Basic | 0.0023 US$ |
| C26083 | 0402WGF1004TCE | 2 | 2930444 | Basic | 0.0015 US$ |
| C25092 | 0402WGF220JTCE | 3 | 2888893 | Basic | 0.0014 US$ |
| C11702 | 0402WGF1001TCE | 4 | 21596913 | Basic | 0.0013 US$ |
| C25741 | 0402WGF1003TCE | 6 | 8390086 | Basic | 0.0012 US$ |
| C25104 | 0402WGF3300TCE | 3 | 2182960 | Basic | 0.0011 US$ |
| C2827694 | ? | 2 | sin respuesta | Extended | ? |

- Piezas sin existencias para 5 placas: C2827694

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **sí**
- Apto para solicitar prototipos: **sí, pendiente de validación física**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- REV B: contactos del fondo por tornillo M2 (SYS, BAT, GND); la estanqueidad depende de las juntas tóricas de los tornillos.
- Pinout de la URTK1.2 por verificar con polímetro antes de hacer el mazo (DOCS/INTEGRACION_GNSS.md).
- Pines 9/10 (detección) de la microSD Hirose DM3AT según la huella de KiCad: comprobar con la hoja.
- Batería 654060 con clavija PH2.0: cambiarla a JST SH 1,0 (J2) y comprobar la polaridad.
- Existencias consultadas en el CI (out_stock/stock_jlc.json): volver a comprobarlas el día del pedido.
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
