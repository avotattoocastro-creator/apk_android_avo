# AVO GIRTH · placa de la cincha · REV A — informe de diagnóstico

- Estado: **DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar
- Commit: `7f80a1878dbb4b767139b7c7d3d5c47936f2166a` · ejecución de CI: 40880129461
- Ruteado: Freerouting 1.9.0 sobre la placa de colocación (sin reparar)
- Placa: 4 capas (F.Cu señal · In1.Cu GND · In2.Cu +3V3 · B.Cu señal + GND), 1,0 mm, ENIG, cobre exterior 1 oz; contorno 65,5 × 43,5 mm con 8 muescas para los tornillos y una ranura para el cable de la batería
- Componentes: 122 en total, 104 para montar, 6 sin montar (DNP: C5, R22, R23, R28, R29, R41), 12 a mano (pads de hilo y de prueba)
- Pistas: 1149 · vías: 192

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
- Pad 8 [QI_ADEN] of U1 on F.Cu ↔ Track [QI_ADEN] on B.Cu, length 4.4773 mm
- Pad 12 [QI_ILIM] of U1 on F.Cu ↔ Pad 1 [QI_ILIM] of R1 on F.Cu
- Pad 1 [SS_G] of Q10 on F.Cu ↔ Track [SS_G] on F.Cu, length 1.4001 mm

## Advertencias de DRC (no bloqueantes)
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
