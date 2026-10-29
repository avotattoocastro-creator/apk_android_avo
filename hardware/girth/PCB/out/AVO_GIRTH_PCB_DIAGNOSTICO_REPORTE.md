# AVO GIRTH · placa de la cincha · REV A — informe de diagnóstico

- Estado: **DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar
- Commit: `8f7eaffa81837f47b9ddac0ebea3cd0a38e470f1` · ejecución de CI: 40872806000
- Ruteado: Freerouting 1.9.0 sobre la placa de colocación (sin reparar)
- Placa: 4 capas (F.Cu señal · In1.Cu GND · In2.Cu +3V3 · B.Cu señal + GND), 1,0 mm, ENIG, cobre exterior 1 oz; contorno 65,5 × 43,5 mm con 8 muescas para los tornillos y una ranura para el cable de la batería
- Componentes: 122 en total, 104 para montar, 6 sin montar (DNP: C5, R22, R23, R28, R29, R41), 12 a mano (pads de hilo y de prueba)
- Pistas: 1157 · vías: 196

## Comprobaciones bloqueantes
| Comprobación | Resultado | Cantidad |
|---|---|---|
| DRC: errores | correcto | 0 |
| DRC: conexiones incompletas | **FALLA** | 5 |
| DRC: cortocircuitos | correcto | 0 |
| DRC: paridad esquema ↔ placa | **FALLA** | 29 |
| ERC: errores | correcto | 0 |
| ERC: advertencias | correcto | 0 |


### Conexiones incompletas
- Pad 7 [CHG_PG] of U2 on F.Cu ↔ Track [CHG_PG] on F.Cu, length 1.2787 mm
- Track [QI_AC2] on F.Cu, length 1.2750 mm ↔ Track [QI_AC2] on F.Cu, length 0.7050 mm
- Pad 8 [QI_ADEN] of U1 on F.Cu ↔ Track [QI_ADEN] on F.Cu, length 0.8055 mm
- Pad 7 [QI_CHG] of U1 on F.Cu ↔ Pad 1 [QI_CHG] of R4 on F.Cu
- Pad 1 [QI_CHG] of R4 on F.Cu ↔ Pad 28 [QI_CHG] of U4 on F.Cu

### Paridad esquema ↔ placa
- net_conflict: Pad missing net given by schematic (unconnected-(D11-A2-Pad2)).
- net_conflict: Pad missing net given by schematic (unconnected-(J1-SBU1-PadA8)).
- net_conflict: Pad missing net given by schematic (unconnected-(J1-SBU2-PadB8)).
- net_conflict: Pad net (+3V3) doesn't match net given by schematic (IMU_VDD).
- net_conflict: Pad net (IMU_VDD) doesn't match net given by schematic (+3V3).
- net_conflict: Pad net (BAT_SW) doesn't match net given by schematic (VBAT).
- net_conflict: Pad net (VBAT) doesn't match net given by schematic (BAT_SW).
- net_conflict: Pad net (VBAT) doesn't match net given by schematic (K_B).
- net_conflict: Pad net (K_B) doesn't match net given by schematic (VBAT).
- net_conflict: Pad net (VSYS) doesn't match net given by schematic (K_A_SET).
- net_conflict: Pad net (K_A_SET) doesn't match net given by schematic (VSYS).
- net_conflict: Pad missing net given by schematic (unconnected-(U2-TMR-Pad14)).
- net_conflict: Pad missing net given by schematic (unconnected-(U3-NC-Pad4)).
- net_conflict: Pad missing net given by schematic (unconnected-(U4-NC-Pad4)).
- net_conflict: Pad missing net given by schematic (unconnected-(U4-NC-Pad7)).
- net_conflict: Pad missing net given by schematic (unconnected-(U4-NC-Pad21)).
- net_conflict: Pad missing net given by schematic (unconnected-(U4-NC-Pad32)).
- net_conflict: Pad missing net given by schematic (unconnected-(U4-NC-Pad33)).
- net_conflict: Pad missing net given by schematic (unconnected-(U4-NC-Pad34)).
- net_conflict: Pad missing net given by schematic (unconnected-(U4-NC-Pad35)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad1)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad7)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad8)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad12)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad13)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad21)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad22)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad23)).
- net_conflict: Pad missing net given by schematic (unconnected-(U5-NC-Pad24)).

## Advertencias de DRC (no bloqueantes)
- silk_over_copper: 3
- track_dangling: 1

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: ninguna
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Limitaciones pendientes (ver README)
- Inductancia de la bobina Qi sin medir: C1–C5 con valores supuestos (DOCS/AJUSTE_QI.md).
- BNO085 sin existencias en LCSC: pedir por Global Sourcing o reservar.
- Relé G6KU-2F-Y posiblemente en fin de fabricación; altura 5,2 mm → rebaje de 1,3 mm en la tapa.
- Polaridad del relé tomada del símbolo de KiCad; si sale al revés, R40 ↔ R41.
- Antena con conector MHF III / W.FL.
- Cambios en la carcasa (cuna +0,6 mm, ranura del cable, rebaje del relé, postes de la tapa).
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
