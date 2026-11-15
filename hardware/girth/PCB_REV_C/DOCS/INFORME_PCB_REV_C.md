## Arquitectura (confirmada por el usuario el 15/11/2026)
- **Pogo + BNO085 + MAX30003**, dos placas de electrodo en la cincha unidas por cable plano al soporte.
- **Cápsula nueva más pequeña** con la PCB apilada sobre la batería LP403048 (500 mAh).
- **Dos pogos de 3 contactos** (el modelo real ya medido): carga 5 V / GND / DET y ECG + / REF / ECG −, por hilos.

## Microcontrolador e IMU
| | |
|---|---|
| MCU | **ESP32-C6-MINI-1U-N4** (mismo chip que el XIAO actual), antena FPC por U.FL |
| IMU | **BNO085** soldado, por **I²C a 0x4A**, cristal de 32,768 kHz |
| ECG | **MAX30003CTI+** (TQFN-28), 1,8 V propio (RT9080-18), oscilador MEMS **SiT1533** de 32,768 kHz |
| Firmware | **AVO GIRTH 0.5.0 sin cambios**: los GPIO son los del XIAO ESP32-C6 |

## GPIO (iguales que el XIAO)
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 0 | PS0 del BNO085 | 15 | LED (activo a nivel bajo) |
| 1 | RST del BNO085 | 16 | SCL del BNO085 |
| 2 | INT del BNO085 | 17 | CS del MAX30003 |
| 4 | FCLK de reserva (R46 sin montar) | 18 | MOSI del MAX30003 |
| 5 | Batería (divisor 1:2) | 19 | SCK del MAX30003 |
| 6 | DET (soporte de la cincha) | 20 | MISO del MAX30003 |
| 7 | INTB del MAX30003 | 21 | CS del BNO085 (alto) |
| 8 | CHG del cargador | 22 | SA0 del BNO085 (bajo = 0x4A) |
| 9 | BOOT | 23 | SDA del BNO085 |
| 12 / 13 | USB D− / D+ (pads de programación) | 3, 14 | libres (eran el conmutador de antena del XIAO) |

## Entrada del ECG
- Cada electrodo: **47 kΩ en serie + 1 nF C0G a masa** (filtro de EMI de 3,2 kHz). El electrodo de referencia va a
  **VCM** por 47 kΩ.
- Paso alto analógico: **C50 = 100 nF C0G (≈ 3,5 Hz)**, como recomienda ADI para uso con movimiento. **C51 = 1 µF sin
  montar**: si se monta, el paso alto baja a ≈ 0,35 Hz y se ve el ECG completo.
- Sin TVS en los electrodos: el MAX30003 ya protege sus entradas, y la fuga de un TVS falsearía la detección de
  electrodo despegado (5 nA).
