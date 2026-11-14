# AVO BACK V5 CASCO · placa de la espalda para el casco · REV A (ESP32-S3 + ZED-F9P soldado) — informe de fabricación

- Estado: **DISEÑO VERIFICADO POR SOFTWARE — APTO PARA SOLICITAR PROTOTIPOS — PENDIENTE DE VALIDACIÓN FÍSICA**
- Commit: `ce624ad872dfbb27cfcb434fbce5c7b0e87ad75f` · ejecución de CI: 43597476741
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
- Piezas montadas sin número LCSC: U1, R70, L70, D4, J5
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 13; sin descargar: Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step, RF_GPS.3dshapes/ublox_ZED.step
- ESP32-S3-MINI-1U: modelo de Espressif (`fuente/3d`). Pads de hilo/prueba: sin modelo 3D.

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **sí**
- Apto para solicitar prototipos: **sí, pendiente de validación física**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- Línea de 50 Ω de la antena (J5 → R71 0 Ω → RF_IN, ESD D4): microcinta de 0,36 mm calculada para el apilado JLC de 1,6 mm (preimpregnado 0,21 mm sobre In1); confirmar con la calculadora de JLC al pedir.
- Antena GNSS plana activa L1/L2 pegada en el centro de la cara B; plano de masa de 51 × 51 (el fabricante afina sobre 70 × 70): medir fix y velocidad.
- Piezas sin código LCSC (ZED-F9P, U.FL, 47 nH, 22 Ω 1206, ESD de RF): buscarlas con stock_jlc.py o suministrarlas aparte (el ZED-F9P suele ir consignado).
- Alimentación de la antena: 22 Ω en 1206 (corto del coaxial ≈ 150 mA, ≈ 0,5 W durante el fallo): sin limitador activo ni uso de ANT_SHORT_N.
- Firmware: poner GPIO6, GPIO8 y GPIO9 como entradas antes de bajar ZED_EN (el ZED apagado no debe recibir tensión por sus E/S).
- Pines 9/10 de la microSD Hirose DM3AT según la huella de KiCad: comprobar con la hoja.
- Pogo de 5 contactos y batería por hilos: el modelo real del pogo está pendiente (STEP).
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
