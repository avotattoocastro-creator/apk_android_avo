## Diseño de la placa REV B (texto fijo del generador)
- **Cambio respecto a la REV A** (congelada en `PCB_REV_A_QI/`): sin receptor Qi (BQ51013B, bobina y 22 piezas) y sin
  sensor Hall. La alimentación entra por **3 contactos en el fondo de la cápsula** (tornillo M2 avellanado de acero
  inoxidable desde fuera + tuerca M2 sobre la placa; junta tórica 2 × 1 entre la base y la placa alrededor de cada
  tornillo).
- **Contactos**: **SYS** (P1) y **BAT** (P2) en la cola, donde estaban el reed / el Hall, a 5,8 mm; **GND** (P3) aparte,
  en el centro de la placa, lejos de BAT.
  - **Soporte del chaleco**: puente entre SYS y BAT → la celda alimenta la electrónica. Fuera del soporte la placa no
    tiene alimentación (0 µA; sin sueño profundo ni sensor).
  - **Base de carga**: cargador Li-ion externo (CC/CV 4,2 V, ≤ 1 A) entre BAT y GND; SYS sin conectar → la electrónica
    está apagada mientras carga.
- **Batería**: celda → J2 → F1 (PTC 1,5 A) → contacto BAT. Contacto SYS → Q3 (PMOS de polaridad) → BAT del BQ24072.
  TVS bidireccionales de 5 V (D2, D3: PESD5V0S1BA, C2827694) en los dos contactos que tocan el exterior.
- **USB-C del taller**: BQ24072 (camino de potencia, 445 mA de carga): con USB la placa funciona sin batería y, si la
  cápsula está en el soporte del chaleco, carga la celda a través del puente.
- **MCU**: ESP32-S3-MINI-1U-N8 (8 MB, sin PSRAM), antena externa → antena FPC de 2,4 GHz en el techo del cuello.
- **ZED-F9P (URTK1.2)**: 8 pads pasantes (J4) para el mazo: 3V3_ZED, GND, UART1, UART2, PPS, RESET; RT9080 propio con EN
  (GPIO10).
- **microSD**: Hirose DM3AT-SF-PEJM5, SDMMC 4 bits, alimentación conmutada (AO3401A, GPIO21). Al quitar la cápsula del
  soporte se corta la alimentación sin aviso: el firmware vacía el fichero cada segundo.

## Pines del ESP32-S3
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 0 | BOOT (TP2) | 12–17 | microSD CLK (22 Ω), CMD, D0–D3 (10 k a 3V3_SD) |
| 1 | libre (REV A: Hall) | 18 | detección de tarjeta (100 k) |
| 2 | VBAT/2 (ADC1) | 19 / 20 | USB D− / D+ |
| 4 | PPS del ZED | 21 | alimentación microSD (LOW = encendida) |
| 5 / 6 | RX / TX ↔ UART1 del ZED | 38 / 39 | PGOOD / CHG del BQ24072 |
| 7 / 8 | RX / TX ↔ UART2 del ZED (la que usa el firmware) | 40 / 41 | libre (REV A: CHG del Qi) / libre (TP10) |
| 9 | RESET_N del ZED | 43 / 44 | TXD0 / RXD0 (TP4 / TP5) |
| 10 | EN del regulador del ZED | 11 | LED (activo bajo) |
