# AVO GIRTH · placa de la cincha · REV B (ESP32-C3) — informe de diagnóstico

- Estado: **DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar
- Commit: `01f8093615fe34df7d3c73181d172dfeabb763fb` · ejecución de CI: 40901729893
- Ruteado: Freerouting 1.9.0 sobre la placa de colocación (sin reparar)
- Placa: 4 capas (F.Cu señal · In1.Cu GND · In2.Cu +3V3 · B.Cu señal + GND), 1,0 mm, ENIG, cobre exterior 1 oz; contorno 65,5 × 43,5 mm con 8 muescas para los tornillos y una ranura para el cable de la batería
- Componentes: 94 en total, 81 para montar, 1 sin montar (DNP: C5), 12 a mano (pads de hilo y de prueba)
- Pistas: 875 · vías: 144 · ruteado INCOMPLETO (3 conexiones)

## Comprobaciones bloqueantes
| Comprobación | Resultado | Cantidad |
|---|---|---|
| DRC: errores | correcto | 0 |
| DRC: conexiones incompletas | **FALLA** | 3 |
| DRC: cortocircuitos | correcto | 0 |
| DRC: paridad esquema ↔ placa | correcto | 0 |
| ERC: errores | correcto | 0 |
| ERC: advertencias | correcto | 0 |


### Conexiones incompletas
- Pad 2 [QI_AC1] of C1 on F.Cu ↔ Track [QI_AC1] on F.Cu, length 1.2374 mm
- Pad 8 [QI_ADEN] of U1 on F.Cu ↔ Pad 1 [QI_ADEN] of Q1 on F.Cu
- Pad 12 [QI_ILIM] of U1 on F.Cu ↔ Pad 1 [QI_ILIM] of R1 on F.Cu

## Advertencias de DRC (no bloqueantes)
- ninguna

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: ninguna
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 9; sin descargar: Connector_JST.3dshapes/JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.step, Connector_USB.3dshapes/USB_C_Receptacle_HRO_TYPE-C-31-M-12.step, Package_DFN_QFN.3dshapes/Texas_VQFN-RHL-20.step, Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step
- ESP32-C3-MINI-1U: modelo de Espressif (`fuente/3d`). MMC5983MA y pads de hilo/prueba: sin modelo 3D.

## Limitaciones pendientes (ver README)
- Inductancia de la bobina Qi sin medir: C1–C5 con valores supuestos (DOCS/AJUSTE_QI.md).
- Existencias consultadas en el CI (out_stock/stock_jlc.json): volver a comprobarlas el día del pedido.
- Enclavamiento de la batería (Q10/Q11) calculado, no medido: comprobar tiempos de encendido y de apagado.
- Tensión de umbral de Q11 (AO3400A, 0,65–1,45 V) y tiempos de C40/C41: medir en el prototipo.
- Antena externa con conector del módulo (U.FL / MHF I del ESP32-C3-MINI-1U).
- Cambios en la carcasa (cuna +0,6 mm, ranura del cable, postes de la tapa); ya no hace falta el rebaje del relé.
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
