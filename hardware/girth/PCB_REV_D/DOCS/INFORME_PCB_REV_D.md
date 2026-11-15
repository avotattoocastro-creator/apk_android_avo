# AVO GIRTH · PCB de la cincha REV D — informe

**Estado: DISEÑO VERIFICADO POR SOFTWARE (CI 43721512373, commit `b63c741`) · NO VERIFICADO EN HARDWARE REAL.**
Apto para pedir prototipos a JLCPCB; nada se ha montado ni medido.

## Qué cambia respecto a la REV C
| | REV C | REV D |
|---|---|---|
| IMU | BNO085 (sin existencias en JLCPCB) | **LSM6DSV16X** (C5267406) con fusión SFLP en el chip (game rotation vector) |
| Magnetómetro | (en el BNO085) | **MMC5983MA** (C404329), 18 bits |
| ECG | MAX30003 | **ADS1292** en **TQFP-32** (ADS1292IPBSR, C2651570, 1057 en stock el 15/11/2026), 24 bits, 500 m/s, ganancia 6 |
| Alimentación analógica | — | RT9080-33 propio (U7) para AVDD (+3V3A), separado del 3,3 V digital |
| Placa | — | 46 × 30 mm, 4 capas, 1,0 mm, ENIG |
| Batería | 600 mAh | **1000 mAh 603450** (ver `CONSUMO_BATERIA.md`) |

## Decisiones de esta revisión
- **ADS1292 en TQFP-32 en lugar de VQFN-32.** Con el VQFN (paso 0,4 mm), Freerouting y la reparación local no conseguían
  sacar todas las pistas del chip en 46 × 30 mm: siempre quedaban de 2 a 11 conexiones. El TQFP (paso 0,5 mm, patillas
  hacia fuera) lo resolvió a la primera. La hoja SBAS502C usa la **misma numeración de pines** para PBS y RSM; el
  TQFP **no tiene pad térmico**, y sus masas bajan a In1 con vías propias.
- **CLK del ADS1292 (pin 17) a DGND.** Con el reloj interno (CLKSEL = 1) y `CLK_EN = 0` (CONFIG2 = 0xE0 en el
  firmware 0.6.0) el pin no se usa, y ya no hace falta R46. **El firmware no debe activar nunca CLK_EN**: queda
  anotado en `girth_ecg.h`.
- **SPI del ECG en los GPIO del C6 que miran al ADS:** CS 0, SCLK 1, DOUT 7, DIN 14, DRDY 3, RESET 4, START 21.
  IMU: SDA 23, SCL 16, INT1 2, INT2 17, MMC INT 22. El firmware 0.6.0 ya usa estos pines.
- **Pads 14 y 51 del ESP32-C6-MINI-1U (GND) sin conectar.** Quedan encerrados por las salidas de las señales. El
  módulo va a masa por el EPAD y el resto de pads GND.
- **Cosido de GND:** se han añadido 4 vías de cosido en islas del relleno de F.Cu (`fuente/stitch_gnd.py`).

## Comprobaciones (CI 43721512373, KiCad 9)
- DRC: 0 errores · 0 conexiones incompletas · 0 cortocircuitos · paridad esquema ↔ placa 0.
- ERC: 0 errores · 0 advertencias.
- Advertencias no bloqueantes: serigrafía sobre cobre y serigrafía solapada.

## Pedido a JLCPCB
1. **PCB:** sube `AVO_GIRTH_REVD_PCB_FINAL_GERBER_JLCPCB.zip` con 4 capas, 1,0 mm, ENIG, cobre exterior de 1 oz y
   la pila de capas por defecto.
2. **Montaje (PCB Assembly, Top):** usa la BOM (`…_BOM_JLCPCB.csv`) y la lista de posiciones (`…_CPL_JLCPCB.csv`).
3. **Comprobar en la vista previa la orientación** de U6 (TQFP, pin 1 arriba a la izquierda), U5/U8 (LGA),
   U2 (VQFN), U4 (módulo, girado 270°), los diodos, el LED y el tántalo C47.
4. **Piezas extendidas** (cobran tasa de carga): el ADS1292, el LSM6DSV16X, el MMC5983MA, el ESP32-C6-MINI-1U-H4,
   el BQ24072 y otras.
5. **Se montan a mano:** los pads de hilo de los electrodos (P4–P6), los pogos (P1–P3), J2/J6 y los pads de prueba.
   **C54 no se monta (DNP).**

## Pendiente (hardware real)
- Montar, alimentar y medir los 3,3 V y los 3,3 V analógicos.
- Leer el ID del ADS1292 (0x53), comprobar WHO_AM_I = 0x70 en el LSM6 y el PID = 0x30 del MMC.
- Medir el ruido del ECG con los electrodos de caucho en el caballo.
- Medir el consumo real frente al cálculo de `CONSUMO_BATERIA.md`.
