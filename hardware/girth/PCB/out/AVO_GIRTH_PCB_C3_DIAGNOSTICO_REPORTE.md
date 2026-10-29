# AVO GIRTH · placa de la cincha · REV B (ESP32-C3) — informe de diagnóstico

- Estado: **DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar
- Commit: `ffe91b8a9e67fcd58ec3550300434f215cf9e1ec` · ejecución de CI: 40905560178
- Ruteado: Freerouting 1.9.0 sobre la placa de colocación (sin reparar)
- Placa: 4 capas (F.Cu señal · In1.Cu GND · In2.Cu +3V3 · B.Cu señal + GND), 1,0 mm, ENIG, cobre exterior 1 oz; contorno 65,5 × 43,5 mm con 8 muescas para los tornillos y una ranura para el cable de la batería
- Componentes: 98 en total, 85 para montar, 1 sin montar (DNP: C5), 12 a mano (pads de hilo y de prueba)
- Pistas: 859 · vías: 148 · ruteado INCOMPLETO (5 conexiones)

## Comprobaciones bloqueantes
| Comprobación | Resultado | Cantidad |
|---|---|---|
| DRC: errores | correcto | 0 |
| DRC: conexiones incompletas | **FALLA** | 5 |
| DRC: cortocircuitos | correcto | 0 |
| DRC: paridad esquema ↔ placa | correcto | 0 |
| ERC: errores | correcto | 0 |
| ERC: advertencias | correcto | 0 |


### Conexiones incompletas
- Track [+3V3] on F.Cu, length 1.1000 mm ↔ Via [+3V3] on F.Cu - B.Cu
- Track [+3V3] on F.Cu, length 0.8467 mm ↔ Track [+3V3] on F.Cu, length 0.2478 mm
- Pad 4 [IMU_INT] of U5 on F.Cu ↔ Pad 12 [IMU_INT] of U4 on F.Cu
- Pad 8 [QI_ADEN] of U1 on F.Cu ↔ Track [QI_ADEN] on B.Cu, length 4.4798 mm
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

## Microcontrolador
| | |
|---|---|
| Seleccionado | **ESP32-C3-MINI-1U-N4** (Espressif), chip ESP32-C3FN4, 4 MB de flash en el encapsulado, −40…85 °C |
| Código JLCPCB / LCSC | **C2911374** (pieza *Extended*, montaje SMT estándar) |
| Existencias y precio | ver la tabla de existencias de abajo (consulta del CI con fecha) |
| Alternativa | ESP32-C3-MINI-1U-H4 (C3013922): mismo módulo con chip de 105 °C y la misma memoria; el firmware sirve sin cambios |
| Antena | conector del módulo de 3.ª generación (W.FL / MHF III), como el C6-MINI-1U: la antena FPC no cambia |

**Por qué el C3:** es el único módulo Espressif con antena externa y el mismo tamaño (13,2 × 12,5 mm, huella con
los mismos pads) que JLCPCB tiene en existencias. El ESP32-S3-MINI-1U (C2980299) también está, pero mide
15,4 × 20,5 mm, consume más y cuesta más; no hace falta porque todas las funciones caben en el C3 con la IMU por I²C.
El C3 tiene 13 GPIO libres + USB: con el BNO085 por SPI habrían hecho falta 16.

## Diferencias frente a la REV A (ESP32-C6)
- MCU ESP32-C3 (RISC-V 160 MHz, Wi-Fi 4 + BLE 5) en lugar del C6 (Wi-Fi 6 + BLE 5 + 802.15.4): ESP-NOW igual.
- IMU: BNO085 (fusión en el chip, SPI, cristal, alimentación conmutada) → **LSM6DS3TR-C + MMC5983MA** por I²C. El
  protocolo de la cincha ya enviaba 9 ejes brutos (`IMU_FMT_9AXIS_I16`), así que la información que llega es la misma.
- Corte de batería: relé biestable G6KU (+ 2 × 220 µF, 9 transistores) → **enclavamiento con 2 MOSFET y 2 diodos**.
  Mismas funciones: encendido magnético, apagado remoto, consumo apagado < 1 µA, no se bloquea al cargar.
- R6/R7 a 3,3 kΩ (pieza *Basic*): carga 270 mA, entrada 462 mA.
- 81 piezas montadas (REV A: 104); 13 referencias *Extended* (REV A: 17).
- Contorno, capas, grosor, acabado, conectores (USB-C, batería, bobina, reed) y posiciones de los conectores: **sin
  cambios**. La tapa ya no necesita el rebaje del relé.

## Asignación de GPIO
Ver la tabla del README y `DOCS/ANALISIS_ELECTRICO.md` §4 (comprobada contra el símbolo y la hoja de Espressif).

## Firmware
`firmware/girth/V0_3_0_C3` (V0.3.0): compila en el CI para ESP32-C3 (imagen comprobada: chip id 5, particiones,
dos ranuras OTA). Diferencias con el firmware del C6 en `DIFERENCIAS_C6_C3.md` (dentro del zip). **No probado en
placa.** AVO Update todavía solo instala en el ESP32-C6: la primera carga se hace con esptool por USB.

## Riesgos eléctricos y mecánicos
- **Qi:** inductancia de la bobina sin medir; C1–C5 supuestos. Ajustar con la primera placa (`DOCS/AJUSTE_QI.md`).
- **Corte de batería:** calculado, no medido. Si Q11 tuviera un umbral alto y la celda estuviera baja, el impulso del
  reed podría quedarse corto: el arreglo es subir C40 (misma huella 0603).
- **Arranque del ESP32-C3 tras un reinicio:** el corte aguanta ~1,5 s; medir el tiempo real hasta PWR_HOLD.
- **IMU:** ejes y signos sin comprobar; el magnetómetro necesita calibración dentro de la cápsula (imanes).
- **BQ51013B:** 476 uds. en JLCPCB: es la pieza con menos existencias; reservarla si se va a tardar en pedir.
- **Mecánica:** cuna +0,6 mm, ranura del cable y postes de la tapa pendientes en el CAD de la cápsula.
- **Giro de las piezas:** el CPL sale de KiCad sin corregir; revisar la vista previa de JLCPCB.

## Existencias en JLCPCB (consulta del CI: 2026-10-29 15:27 UTC)
| LCSC | Pieza | Por placa | Existencias | Tipo | Precio (1 ud.) |
|---|---|---|---|---|---|
| C55663 | BQ51013BRHLR | 1 | 476 | Extended | 3.6045 US$ |
| C2911374 | ESP32-C3-MINI-1U-N4 | 1 | 1191 | Extended | 3.1542 US$ |
| C404329 | MMC5983MA | 1 | 7710 | Extended | 1.9914 US$ |
| C967633 | LSM6DS3TR-C | 1 | 23404 | Extended | 1.4559 US$ |
| C140288 | BQ24072RGTR | 1 | 2873 | Extended | 0.9957 US$ |
| C97946 | GRM31C5C1H104JA01L | 2 | 67333 | Extended | 0.2773 US$ |
| C45783 | CL21A226MAQNNNE | 1 | 3820092 | Basic | 0.1918 US$ |
| C165948 | TYPE-C-31-M-12 | 1 | 290139 | Extended | 0.1871 US$ |
| C7519 | USBLC6-2SC6 | 1 | 38837 | Extended | 0.1798 US$ |
| C21812 | GRM31M5C1H473JA01L | 1 | 66831 | Extended | 0.1689 US$ |
| C160402 | SM02B-SRSS-TB(LF)(SN) | 1 | 75764 | Extended | 0.1324 US$ |
| C841192 | RT9080-33GJ5 | 1 | 36728 | Extended | 0.1198 US$ |
| C15127 | AO3401A | 3 | 949077 | Basic | 0.0960 US$ |
| C20917 | AO3400A | 1 | 1147315 | Basic | 0.0890 US$ |
| C51795 | 0805CG222J500NT | 1 | 3262 | Extended | 0.0425 US$ |
| C96446 | CL10A106MA8NRNC | 7 | 8289919 | Basic | 0.0387 US$ |
| C19702 | CL10A106KP8NNNC | 1 | 12137255 | Basic | 0.0212 US$ |
| C77131 | NCP15XH103F03RC | 2 | 295086 | Extended | 0.0187 US$ |
| C8545 | 2N7002 | 1 | 3093827 | Basic | 0.0161 US$ |
| C68978 | BAV70 | 4 | 637912 | Basic | 0.0152 US$ |
| C1623 | CL10B474KA8NNNC | 2 | 691127 | Basic | 0.0130 US$ |
| C23630 | CL10A225KO8NNNC | 1 | 2898561 | Basic | 0.0122 US$ |
| C2286 | KT-0603R | 1 | 7358378 | Basic | 0.0077 US$ |
| C52923 | CL05A105KA5NQNC | 5 | 10458281 | Basic | 0.0064 US$ |
| C1532 | 0402B223K500NT | 2 | 610107 | Basic | 0.0049 US$ |
| C15195 | CL05B103KB5NNNC | 3 | 6256201 | Basic | 0.0039 US$ |
| C25890 | 0402WGF3301TCE | 2 | 1623716 | Basic | 0.0036 US$ |
| C1525 | CL05B104KO5NNNC | 7 | 32023248 | Basic | 0.0031 US$ |
| C25087 | 0402WGF2000TCE | 1 | 1923580 | Basic | 0.0029 US$ |
| C25744 | 0402WGF1002TCE | 3 | 17223387 | Basic | 0.0024 US$ |
| C25905 | 0402WGF5101TCE | 2 | 3841658 | Basic | 0.0023 US$ |
| C25900 | 0402WGF4701TCE | 2 | 15195941 | Basic | 0.0020 US$ |
| C26083 | 0402WGF1004TCE | 5 | 3011508 | Basic | 0.0015 US$ |
| C25092 | 0402WGF220JTCE | 2 | 2995327 | Basic | 0.0014 US$ |
| C11702 | 0402WGF1001TCE | 1 | 21984432 | Basic | 0.0013 US$ |
| C25741 | 0402WGF1003TCE | 7 | 8556838 | Basic | 0.0012 US$ |
| C25104 | 0402WGF3300TCE | 1 | 2205913 | Basic | 0.0011 US$ |
| C25765 | 0402WGF2002TCE | 1 | 2906534 | Basic | 0.0011 US$ |
| C16772 | ? | 1 | sin respuesta | Extended | ? |
| C26082 | ? | 2 | sin respuesta | Extended | ? |
| C25091 | ? | 1 | sin respuesta | Extended | ? |

- Piezas sin existencias para 5 placas: C16772, C26082, C25091

## Coste por placa frente a la REV A (componentes + cargo de piezas Extended; detalle en out_stock/COSTE.md)
| Pedido | REV A componentes | REV A Extended | REV A total | REV B componentes | REV B Extended | REV B total | Reducción |
|---|---|---|---|---|---|---|---|
| 5 placas | 29.74 US$ | 17 · 10.20 US$ | **39.94 US$** | 13.72 US$ | 13 · 7.80 US$ | **21.52 US$** | **46 %** |
| 10 placas | 27.80 US$ | 17 · 5.10 US$ | **32.90 US$** | 12.31 US$ | 13 · 3.90 US$ | **16.21 US$** | **51 %** |
| 30 placas | 25.32 US$ | 17 · 1.70 US$ | **27.02 US$** | 11.15 US$ | 13 · 1.30 US$ | **12.45 US$** | **54 %** |

## Estado de fabricación
- Diseño verificado por software (KiCad 9 en el CI): **no**
- Apto para solicitar prototipos: **no**
- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)

## Limitaciones pendientes (ver README)
- Inductancia de la bobina Qi sin medir: C1–C5 con valores supuestos (DOCS/AJUSTE_QI.md).
- Existencias consultadas en el CI (out_stock/stock_jlc.json): volver a comprobarlas el día del pedido.
- Enclavamiento de la batería (Q10/Q11) calculado, no medido: comprobar tiempos de encendido y de apagado.
- Tensión de umbral de Q11 (AO3400A, 0,65–1,45 V) y tiempos de C40/C41: medir en el prototipo.
- Antena externa con conector del módulo (U.FL / MHF I del ESP32-C3-MINI-1U).
- Cambios en la carcasa (cuna +0,6 mm, ranura del cable, postes de la tapa); ya no hace falta el rebaje del relé.
- Nada de esto se ha fabricado ni medido: no es un prototipo validado.
