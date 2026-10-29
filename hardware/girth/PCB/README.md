# AVO GIRTH · placa de la cincha · REV A

Placa propia para la cápsula de la cincha (REV 5.8.1): sustituye al XIAO ESP32-C6, a la placa GY-BNO08X y al
receptor Qi de 18 × 15 por **una sola PCB de 4 capas** del tamaño de la bandeja, montada por JLCPCB.
Lleva **conector para la batería** (JST SH 1,0) y **pads para soldar la bobina Qi** y el reed.

**Estado:** diseño generado y comprobado en CI con KiCad 9 (ver `out/drc.rpt` y `out/erc.rpt`).
**NO VERIFICADO** en hardware: no se ha fabricado ni medido ninguna placa.

## Qué lleva
| Bloque | Pieza | Notas |
|---|---|---|
| MCU | ESP32-C6-MINI-1U-N4 (U4) | antena externa por conector **MHF III / W.FL** (no es U.FL): la antena FPC tiene que llevar ese conector |
| IMU | BNO085 (U5) por **SPI** | cristal 32,768 kHz (Y1); alimentación conmutada con Q3 (GPIO5 a LOW = encendido); opción I²C con R22/R23/R28/R29 |
| Qi | BQ51013B (U1), salida 5 V | bobina Ø25 a los pads L1/L2; condensadores de resonancia **a ajustar** (`DOCS/AJUSTE_QI.md`) |
| Carga | BQ24072 (U2) con camino de potencia | 247 mA de carga (0,5 C), entrada limitada a 450 mA, NTC en placa (RT2) |
| USB-C | J1 + ESD (U6) | solo con la tapa abierta; el USB entra en el BQ51013B por AD/AD-EN (Q1/Q2) y **también carga la batería** |
| 3,3 V | RT9080-33 (U3) | 600 mA, 2 µA de consumo propio |
| Batería | J2 JST SH 1,0 (pin 1 = +) | el cable pasa por la ranura fresada junto al borde −X |
| Reed | pads SW1/SW2 → GPIO6 | mismo pin que en el XIAO |

## Por qué no el BQ51050B (Qi + cargador en un chip)
Su corriente mínima de carga es **500 mA** (1 C para la LP403048 de 500 mAh), **no puede cargar por USB** y no
tiene camino de potencia: con el ESP32 encendido la carga no termina nunca y la celda se queda a 4,2 V hasta el
temporizador de 10 h. Con BQ51013B + BQ24072 la carga es de 0,5 C, termina bien con el ESP32 encendido y el USB
también carga.

## Pines del ESP32-C6 (cambian respecto al XIAO: hay que adaptar el firmware de la cincha)
| GPIO | Función | Nota |
|---|---|---|
| 0 | IMU_INT (H_INTN) | LP: puede despertar |
| 1 | IMU_RST (NRST) | |
| 2 | BAT_ADC (ADC1_CH2) | divisor 1 MΩ / 1 MΩ → V_bat / 2 |
| 3 | CHG_PG (PGOOD del cargador, LOW = hay alimentación Qi o USB) | LP: despierta al poner la cápsula en la base |
| 4 | CHG_STAT (LOW = cargando) | strapping (MTMS), sin efecto práctico |
| 5 | IMU_PWR_N (LOW = BNO encendido) | strapping (MTDI); R30 lo mantiene apagado en el arranque |
| 6 | REED (LOW = cápsula en el soporte) | LP: despierta (ext1, nivel bajo) |
| 7 | IMU_WAKE (PS0/WAKE) | debe estar a HIGH antes de soltar NRST (modo SPI) |
| 8 | libre (pull-up 10 k, strapping) | |
| 9 | BOOT (pad TP2) | strapping |
| 12 / 13 | USB D− / D+ | USB-Serial-JTAG |
| 15 | LED (activo alto, D1) | strapping JTAG, pull-down 10 k |
| 16 / 17 | TXD0 / RXD0 (pads TP4 / TP5) | |
| 18 / 19 / 20 / 21 | IMU CS / SCK / MOSI / MISO | SPI modo 3, ≤ 3 MHz |
| 22 | QI_CHG (LOW = el receptor Qi entrega potencia) | |
| 14, 23 | libres | |

## Consumo estimado
- **Dormida** (fuera del soporte, sin base): RT9080 2 µA + ESP32-C6 en sueño profundo ~7 µA + BQ24072 4,3 µA +
  divisor 2 µA + BNO apagado ≈ **15 µA** → la autodescarga de la celda manda.
- **Funcionando**: ESP32-C6 con ESP-NOW + BNO085 ≈ 30–60 mA (estimado) → 8–15 h con 500 mAh.

## Cambios mecánicos que pide la placa (siguiente revisión del CAD de la cápsula)
1. **Cuna de la batería +0,6 mm** (apoyo de la placa a z 7,75; antes 7,15): deja hueco bajo la placa para las
   patas pasantes del blindaje del USB-C, que caen encima de la batería. El techo sigue en z 13,2: quedan
   4,1 mm sobre la placa (lo más alto es el USB-C, 3,3 mm).
2. **Labio de la tapa** apoyado sobre la placa (como sobre la bandeja), 0,6 mm más alto.
3. **Cable de la batería** por la ranura de la placa en (−29; 4,6). Hilos de la bobina a L1/L2 en X −28,6 e hilos
   del reed a SW1/SW2 en Y −17,8: suben por el hueco entre la cuna y la pared.
4. **Antena FPC** pegada al techo de la tapa sobre la banda sin cobre (X −17…13, Y 12,6 al borde).
5. **Postes de la tapa**: rehacerlos para que apoyen en zonas libres de la placa.
6. La bandeja impresa desaparece: la placa es la bandeja.

## Fabricación (JLCPCB)
- 4 capas, **1,0 mm**, ENIG, máscara cualquiera, vías 0,3/0,5 mm, pista/separación mínimas 0,15 mm.
- Ficheros: `out/AVO_GIRTH_PCB_GERBER_JLCPCB.zip`, `out/JLCPCB_BOM.csv`, `out/JLCPCB_CPL.csv`.
- **BNO085 sin existencias en LCSC** (C5189642): pedirlo por *Global Sourcing* de JLCPCB o reservarlo antes.
  JLCPCB lo monta con inspección por rayos X.
- **Revisar el giro de cada pieza en la vista previa de JLCPCB** antes de pagar (sobre todo U1, U2, U4, U5,
  U6, Q1–Q3, J1, J2, D1, Y1): el CPL sale de KiCad sin correcciones de giro.
- Las piezas «sin montar» (DNP: C5, R22, R23, R28, R29) no entran en la BOM.

## Medidas y comprobaciones pendientes
1. Inductancia de la bobina y ajuste de C1–C5 (`DOCS/AJUSTE_QI.md`).
2. Polaridad del cable de la batería contra J2 (pin 1 = +).
3. Antena FPC con conector MHF III.
4. Primer encendido con fuente limitada a 100 mA; medir 3,3 V, consumo dormido y carga por USB y por Qi.
5. Comprobar que el reed y PGOOD despiertan al ESP32-C6.

## Fuentes del diseño
`fuente/avo_girth_pcb.py` (piezas, redes, colocación) → `fuente/build.py` (ruteado y placa) +
`fuente/write_sch.py` (esquema, reglas, lista de piezas). El CI (`.github/workflows/build-girth-pcb.yml`) rellena
las zonas con KiCad 9, pasa DRC y ERC y exporta Gerber, taladros, posiciones, renders y STEP a `out/`.
