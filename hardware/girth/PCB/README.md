# AVO GIRTH · placa de la cincha · REV B (ESP32-C3)

Placa propia para la cápsula de la cincha (REV 5.8.1), montada por JLCPCB: **una sola PCB de 4 capas** del tamaño de la
bandeja, con **conector para la batería** (JST SH 1,0) y **pads para soldar la bobina Qi** y el reed.

**Por qué REV B:** JLCPCB no tiene el ESP32-C6-MINI-1U-N4 de la REV A (0 uds. el 2026-10-29). La REV B usa el
**ESP32-C3-MINI-1U-N4** (C2911374, 1191 uds.), cambia el BNO085 (19,50 US$, 80 uds.) por **LSM6DS3TR-C + MMC5983MA**
y el relé biestable por un **enclavamiento con MOSFET**: mismas funciones, ~50 % menos de coste por placa
(`out_stock/COSTE.md`). La REV A queda congelada en `../PCB_REV_A_C6`.

**Estado:** diseño generado y comprobado en CI con KiCad 9 (`out/`). **NO VERIFICADO** en hardware: no se ha
fabricado ni medido ninguna placa.

## Qué lleva
| Bloque | Pieza | Notas |
|---|---|---|
| MCU | ESP32-C3-MINI-1U-N4 (U4) | antena externa por el conector de 3.ª generación del módulo (**W.FL / MHF III**, no U.FL). Alternativa: -H4 (C3013922, 105 °C, misma memoria) |
| IMU | LSM6DS3TR-C (U5) + MMC5983MA (U7) por **I²C** | 9 ejes brutos como pide el protocolo de la cincha; la huella de U5 admite el LSM6DSV16X |
| Qi | BQ51013B (U1), salida 5 V | bobina Ø25 a los pads L1/L2; condensadores de resonancia **a ajustar** (`DOCS/AJUSTE_QI.md`) |
| Carga | BQ24072 (U2) con camino de potencia | 270 mA de carga (0,54 C), entrada limitada a 462 mA (< 494 mA del Qi), NTC en placa (RT2) |
| USB-C | J1 + ESD (U6) | programación y consola; entra en el BQ51013B por AD/AD-EN (Q1/Q2) y **también carga** |
| 3,3 V | RT9080-33 (U3) | 600 mA, 2 µA de consumo propio |
| Batería | J2 JST SH 1,0 (pin 1 = +) | el cable pasa por la ranura fresada junto al borde −X |
| Reed | pads SW1/SW2 (SW2 al + de la batería) | enciende por flanco y se lee en GPIO1 (Q16) |
| **Corte de batería** | **Q10 (PMOS) + Q11 (NMOS) + D10–D13 (BAV70)** | **< 1 µA apagada**; ver abajo |

## Corte de batería (enclavamiento con MOSFET)
- **Se enciende solo**, sin firmware: al **cerrarse** el reed (C40 da un impulso de ≈ 2,5 s, con la corriente por el
  reed limitada a 19 mA y rearmado en ~2–3 s tras abrirse) o con 5 V de la base Qi o del USB (D10, mientras estén).
- **El firmware lo mantiene** con PWR_HOLD (GPIO5) = 1, que pone lo primero al arrancar. Si el ESP32 se reinicia, C41
  sostiene el corte ~1,2 s.
- **Se apaga desde el ESP32**: PWR_HOLD = 0 → el corte se abre en ~2,7 s. Funciona también con el reed cerrado (el reed
  actúa por flanco), así que el **apagado remoto** sigue siendo posible en el soporte.
- **Nunca queda bloqueado al cargar**: con 5 V presentes el corte está cerrado pase lo que pase en el firmware.
- **Batería agotada**: con la base puesta, el diodo interno de Q10 deja precargar la celda y luego Q10 conduce.
- Cálculos en `DOCS/ANALISIS_ELECTRICO.md` §3 (red del reed revisada tras una revisión independiente). Respecto al relé de la REV A: no necesita rebaje en la tapa ni
  condensadores de 220 µF, no tiene polaridad que adivinar (R40/R41 desaparecen) y no lleva imán junto a la IMU.

## Pines del ESP32-C3 (firmware V0.3.0: `firmware/girth/V0_3_0_C3`)
| GPIO | Función | Nota |
|---|---|---|
| 0 | IMU_INT (INT1 del LSM6) | despierta |
| 1 | REED (LOW = cápsula en el soporte) | despierta |
| 2 | I²C SCL | strapping: 1 al arrancar gracias al pull-up de 4,7 k |
| 3 | BAT_ADC (ADC1_CH3) | divisor 1 MΩ / 1 MΩ → V_bat / 2 |
| 4 | CHG_PG (LOW = hay 5 V) | despierta |
| 5 | PWR_HOLD | 1 = mantener la alimentación |
| 6 | I²C SDA | |
| 7 | CHG_STAT (LOW = cargando) | |
| 8 | LED rojo (activo bajo) | strapping: 1 al arrancar |
| 9 | BOOT (pad TP2) | strapping; 5 s pulsado = olvidar la espalda |
| 10 | QI_CHG (LOW = el Qi entrega potencia) | |
| 18 / 19 | USB D− / D+ | USB-Serial-JTAG |
| 20 / 21 | RXD0 / TXD0 (pads TP5 / TP4) | UART0 de la ROM: registro y recuperación |

**Reglas para el firmware:** PWR_HOLD = 1 lo primero; fuera del soporte 3 s sin carga → apagar; batería < 3,30 V →
apagar; en la base Qi fuera del soporte → sueño profundo. Detalle en `firmware/girth/V0_3_0_C3/DIFERENCIAS_C6_C3.md`.

## Programación y recuperación
Por el USB-C interno (USB-Serial-JTAG) con esptool o Arduino: `AVO_GIRTH_V0_3_0_C3_COMPLETO.bin` en 0x0. Si el
firmware no arranca: mantener BOOT (TP2) a masa al encender para entrar en modo descarga, o usar el UART0 (TP4/TP5).
**AVO Update todavía solo instala en el ESP32-C6**: hay que adaptarlo (id de chip 5 y vigilantes del C3) antes de
usarlo con esta placa.

## Consumo estimado
- **Apagada** (fuera del soporte): < 1 µA (fuga de Q10) + autodescarga de la celda.
- **Funcionando**: ESP32-C3 con ESP-NOW + IMU ≈ 25–45 mA (estimado) → 11–20 h con 500 mAh.
- **En la base Qi**: sueño profundo, lo alimenta la base.

## Cambios mecánicos que pide la placa (siguiente revisión del CAD de la cápsula)
1. **Cuna de la batería +0,6 mm** (apoyo de la placa a z 7,75): hueco bajo la placa para las patas del blindaje del
   USB-C. El techo sigue en z 13,2: quedan 4,1 mm sobre la placa (lo más alto es el USB-C, 3,3 mm).
2. **Labio de la tapa** apoyado sobre la placa, 0,6 mm más alto.
3. **Cable de la batería** por la ranura de la placa en (−29; 4,6). Hilos de la bobina a L1/L2 en X −28,6 e hilos
   del reed a SW1/SW2 en Y −17,8.
4. **Antena FPC** pegada al techo de la tapa sobre la banda sin cobre (X −3,3…25,5; Y 12,6 al borde).
5. **Postes de la tapa**: rehacerlos para que apoyen en zonas libres de la placa.
6. La bandeja impresa desaparece: la placa es la bandeja.
7. Ya **no** hace falta el rebaje de 1,3 mm de la REV A (no hay relé).

## Fabricación (JLCPCB)
- 4 capas, **1,0 mm**, ENIG, vías 0,3/0,5 mm, pista/separación mínimas 0,15 mm. Capas: F.Cu señal · In1.Cu plano
  GND · In2.Cu señal + relleno +3V3 · B.Cu señal + relleno GND.
- Ficheros, solo si la puerta del CI pasa, en `out/C3/`: `AVO_GIRTH_PCB_C3_GERBER_JLCPCB.zip`, `_BOM_JLCPCB.csv`,
  `_CPL_JLCPCB.csv`, `_STEP.step`, `_DRC.txt`, `_ERC.txt`, `_FIRMWARE.zip`, `_REPORTE.md`, fuentes de KiCad y
  `SHA256SUMS.txt`. Si falla, solo hay `out/AVO_GIRTH_PCB_C3_DIAGNOSTICO_REPORTE.md` y el job termina en rojo.
- Existencias, precios y tipo (Basic/Extended) consultados en el CI: `out_stock/stock_jlc.json` (con fecha);
  coste comparado con la REV A: `out_stock/COSTE.md`. **Volver a comprobar las existencias el día del pedido.**
- **Revisar el giro de cada pieza en la vista previa de JLCPCB** antes de pagar (sobre todo U1, U2, U4, U5, U7, U6,
  Q1–Q3, Q10, Q11, D10, D11, J1, J2, D1): el CPL sale de KiCad sin correcciones de giro.
- Piezas sin montar (DNP): C5.

## Medidas y comprobaciones pendientes
1. Inductancia de la bobina y ajuste de C1–C5 (`DOCS/AJUSTE_QI.md`).
2. Polaridad del cable de la batería contra J2 (pin 1 = +).
3. Corte de batería: tiempo de encendido con el reed, tiempo que sostiene un reinicio, tiempo de apagado y
   consumo apagado (< 1 µA esperado).
4. Primer encendido con fuente limitada a 100 mA; medir 3,3 V, consumo dormido y carga por USB y por Qi.
5. IMU: direcciones I²C (`DIAG`), signos de los ejes y calibración del magnetómetro dentro de la cápsula.

## Fuentes del diseño
`fuente/avo_girth_pcb.py` (piezas, redes, colocación) → `fuente/build.py` (placa de colocación) +
`fuente/write_sch.py` (esquema, reglas, lista de piezas). Ruteado: Freerouting 1.9.0 en el CI sobre
`kicad/AVO_GIRTH_PCB_colocacion.kicad_pcb` y reparación de lo que deja sin unir con `fuente/repair.py`
(→ `kicad/AVO_GIRTH_PCB_ruteado.kicad_pcb`, que el CI usa tal cual si existe). El CI
(`.github/workflows/build-girth-pcb.yml`) rellena las zonas con KiCad 9, pasa DRC con paridad de esquema y ERC,
aplica la puerta bloqueante (`fuente/gate.py`) y solo entonces exporta los ficheros de fabricación.
