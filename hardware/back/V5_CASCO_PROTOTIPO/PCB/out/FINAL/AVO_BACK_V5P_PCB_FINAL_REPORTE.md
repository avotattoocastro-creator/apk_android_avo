# AVO BACK V5 CASCO PROTOTIPO · PROTO A (ESP32-S3-WROOM-1U-N16R8 + URTK1.2 por tiras de pines) — informe de fabricación

- Estado: **DISEÑO VERIFICADO POR SOFTWARE — APTO PARA SOLICITAR PROTOTIPOS — PENDIENTE DE VALIDACIÓN FÍSICA**
- Commit: `8da50c8e2ae46b263927d750c263f3765caaa1a7` · ejecución de CI: 44333638870
- Ruteado: placa ruteada de la fuente (Freerouting + reparación con fuente/repair.py)
- Placa: 56 × 56 mm (R3), 4 capas (F.Cu componentes y señal · In1.Cu GND · In2.Cu señal + relleno +3V3 · B.Cu plano GND macizo bajo la URTK1.2, sin pistas), 1,6 mm, ENIG, cobre exterior 1 oz
- Componentes: 129 en total, 106 para montar, 1 sin montar (DNP: C69), 22 a mano (pads de hilo y de prueba)
- Pistas: 1023 · vías: 181 · ruteado completo (0 conexiones incompletas)

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
- silk_over_copper: 2
- connection_width: 1

## Lista de materiales y posiciones
- Piezas montadas sin número LCSC: ninguna
- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).
- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.

## Modelo 3D (STEP y renders, no afecta a la fabricación)
- Modelos de la librería de KiCad 9.0.0 descargados: 10; sin descargar: Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step
- ESP32-S3-WROOM-1U: modelo de Espressif (`fuente/3d`). Piezas de EasyEDA y pads de hilo/prueba: sin modelo 3D.

## Existencias en JLCPCB (consulta del CI: 2026-11-18 11:44 UTC)
| LCSC | Pieza | Por placa | Existencias | Tipo | Precio (1 ud.) |
|---|---|---|---|---|---|
| C3013946 | ESP32-S3-WROOM-1U-N16R8 | 1 | 19960 | Extended | 5.1853 US$ |
| C5267406 | LSM6DSV16XTR | 1 | 19522 | Extended | 2.8613 US$ |
| C2682616 | MAX17048G+T10 | 1 | 25538 | Extended | 1.9457 US$ |
| C114218 | DM3AT-SF-PEJM5 | 1 | 14167 | Extended | 1.3922 US$ |
| C140288 | BQ24072RGTR | 1 | 1062 | Extended | 1.0499 US$ |
| C919459 | TPS61023DRLR | 1 | 1239 | Extended | 0.2333 US$ |
| C485517 | TLV75733PDBVR | 1 | 12791 | Extended | 0.2107 US$ |
| C42422127 | TTP223-BA6-TD | 1 | 38627 | Extended | 0.1713 US$ |
| C140921 | DRV5032FADBZR | 1 | 59895 | Extended | 0.1709 US$ |
| C7519 | USBLC6-2SC6 | 1 | 34897 | Extended | 0.1571 US$ |
| C5446 | XC6206P332MR-G | 1 | 432363 | Basic | 0.1381 US$ |
| C841192 | RT9080-33GJ5 | 1 | 26322 | Extended | 0.1198 US$ |
| C20802 | SMD1206P150TF | 2 | 11243 | Extended | 0.1188 US$ |
| C45783 | CL21A226MAQNNNE | 5 | 3659847 | Basic | 0.1085 US$ |
| C15127 | AO3401A | 2 | 1392256 | Basic | 0.0814 US$ |
| C97016 | WPN201610U1R0MT | 1 | 4071 | Extended | 0.0457 US$ |
| C2827694 | PESD5V0S1BA | 2 | 470715 | Extended | 0.0359 US$ |
| C96446 | CL10A106MA8NRNC | 6 | 5739712 | Basic | 0.0343 US$ |
| C2135 | BAT54C | 2 | 150474 | Extended | 0.0246 US$ |
| C77131 | NCP15XH103F03RC | 1 | 293593 | Extended | 0.0164 US$ |
| C52923 | CL05A105KA5NQNC | 7 | 9100317 | Basic | 0.0055 US$ |
| C25867 | 0402WGF1501TCE | 1 | 1179471 | Basic | 0.0029 US$ |
| C1525 | CL05B104KO5NNNC | 17 | 35317245 | Basic | 0.0024 US$ |
| C4109 | 0402WGF2001TCE | 1 | 9762766 | Basic | 0.0019 US$ |
| C25744 | 0402WGF1002TCE | 9 | 36586442 | Basic | 0.0015 US$ |
| C11702 | 0402WGF1001TCE | 4 | 30290405 | Basic | 0.0013 US$ |
| C36871 | 0402WGF6802TCE | 1 | 1080092 | Extended | 0.0012 US$ |
| C25755 | 0402WGF1503TCE | 1 | 1002574 | Extended | 0.0011 US$ |
| C26083 | 0402WGF1004TCE | 3 | 2854070 | Basic | 0.0011 US$ |
| C25104 | 0402WGF3300TCE | 4 | 2218307 | Basic | 0.0011 US$ |
| C25879 | 0402WGF2201TCE | 2 | 2895113 | Basic | 0.0011 US$ |
| C25092 | 0402WGF220JTCE | 3 | 4483746 | Basic | 0.0010 US$ |
| C25741 | 0402WGF1003TCE | 11 | 8706634 | Basic | 0.0009 US$ |
| C5378721 | ? | 8 | sin respuesta | Extended | ? |
| C137952 | ? | 1 | sin respuesta | Extended | ? |

- Piezas sin existencias para 5 placas: C5378721, C137952

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **sí**
- Apto para solicitar prototipos: **sí, pendiente de validación física**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- PROTO A: GNSS en placa URTK1.2 (ZED-F9P-04B) soldada sobre la cara B con tiras de 9 + 10 pines y plástico de 2,5 mm; cotas de la URTK1.2 tomadas del plano del anuncio: VERIFICAR CON CALIBRE antes de pedir.
- PROTO A: placa de 56 × 56 (tornillos a ±24,5) y cápsula más ancha y más alta; antena sobre la URTK1.2 con placa de masa de 0,8 mm (fuente/placa_masa.py).
- Firmware: poner GPIO6, GPIO8 y GPIO9 como entradas antes de bajar ZED_EN (el ZED apagado no debe recibir tensión por sus E/S).
- Pines 9/10 de la microSD Hirose DM3AT según la huella de KiCad: comprobar con la hoja.
- Pogo de 5 contactos y batería por hilos: el modelo real del pogo está pendiente (STEP).
- REV B: táctil TTP223-BA6-TD (TDSEMIC) con Cs sin montar: ajustar la sensibilidad con la pared adelgazada y probar con agua.
- REV B: firmware nuevo (BACK 5.x): POWER_HOLD (GPIO46) al arrancar, pulsación larga, LED_PWR (GPIO48), I²C (MAX17048 + LSM6DSV16X).
- Con el anillo apagado, GPIO47 a 0 (no alimentar los LED por DIN). PROTO A: 8 LED (D14 a la derecha de la salida de la microSD).
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
