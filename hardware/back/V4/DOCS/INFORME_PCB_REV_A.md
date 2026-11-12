## Diseño de la placa (texto fijo del generador)
- **MCU**: ESP32-S3-MINI-1U-N8 (8 MB, sin PSRAM), antena externa por el conector del módulo → antena FPC de 2,4 GHz en el
  techo del cuello (a ~75 mm de la antena GNSS). Un solo ESP32: comparación en `DOCS/ARQUITECTURA_Y_CONSUMO.md`.
- **Alimentación**: BQ51013B (Qi) + BQ24072 (camino de potencia, 445 mA de carga) · PTC 1,5 A + PMOS de polaridad ·
  TLV75733P 1 A (ESP32-S3 + microSD) · **RT9080 propio del ZED con EN (GPIO10)**.
- **ZED-F9P (URTK1.2)**: 8 pads pasantes (J4) para el mazo: 3V3_ZED, GND, UART1, UART2, PPS, RESET; serie de 1 kΩ en
  las salidas del ESP32 y de 330 Ω en las entradas.
- **microSD**: Hirose DM3AT-SF-PEJM5, SDMMC 4 bits, alimentación conmutada (AO3401A, GPIO21).
- **Soporte**: Hall DRV5032FA (salida push-pull) en GPIO1 (despertador ext0); sustituye al reed.
- **Mecánica**: contorno, pivotes, pisadores y anillos generados con el CAD V4 (`pcb_contorno_v4.json`,
  `pcb_mecanica.json`); alturas de componentes limitadas por zona (bajo la URTK1.2 5,8 mm, bajo J2/L 2,3 mm, topes
  de la L 3,8 mm, resto 10,9 mm).

## Pines del ESP32-S3
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 0 | BOOT (TP2) | 12–17 | microSD CLK (22 Ω), CMD, D0–D3 (10 k a 3V3_SD) |
| 1 | Hall (LOW = en el soporte) | 18 | detección de tarjeta (100 k) |
| 2 | VBAT/2 (ADC1) | 19 / 20 | USB D− / D+ |
| 4 | PPS del ZED | 21 | alimentación microSD (LOW = encendida) |
| 5 / 6 | RX / TX ↔ UART1 del ZED | 38 / 39 / 40 | PGOOD / CHG del BQ24072, CHG del BQ51013B |
| 7 / 8 | RX / TX ↔ UART2 del ZED (la que usa el firmware) | 41 | libre (TP10) |
| 9 | RESET_N del ZED | 43 / 44 | TXD0 / RXD0 (TP4 / TP5) |
| 10 | EN del regulador del ZED | 11 | LED (activo bajo) |
