# AVO BACK V5 CASCO · PCB REV A (14/11/2026)

**Estado:** diseño verificado por software (KiCad 9 en el CI: DRC 0, 0 conexiones incompletas, paridad esquema ↔ placa 0, ERC 0/0). La puerta de fabricación está superada y los ficheros están en `out/FINAL/`. **No fabricada. No verificada en hardware.**

## Placa
- 51 × 51 mm, esquinas R3, 4 capas, 1,6 mm, ENIG.
- 4 taladros de Ø2,8 para los tornillos M2,5 de la caja, en (±22, ±22), y un paso de Ø3 para el coaxial de la antena.
- **Todos los componentes en la cara F**, que mira a la batería; la altura máxima es 2,6 mm.
- **B.Cu es masa maciza, sin pistas:** sirve de plano de masa de la antena GNSS plana activa de 25 × 25, pegada en el centro de la cara B.
- In1 es GND; In2 lleva señales y un relleno de +3V3.

## Bloques
- **ESP32-S3-MINI-1U-N8:** BLE con el móvil y ESP-NOW con el pecho y las cinchas. Antena FPC de 2,4 GHz en el conector del módulo, pegada a la pared de la cápsula.
- **ZED-F9P soldado.**
  - Comunicación con el S3: UART1 + UART2 + PPS + RESET.
  - 3,3 V propio con EN (RT9080).
  - V_BCKP desde el 3,3 V principal, para arrancar en caliente.
- **Antena activa:**
  - VCC_RF → 22 Ω en 1206 → 47 nH → línea de RF, protegida contra descargas;
  - línea de 50 Ω de 0,36 mm hasta RF_IN, con un puente de 0 Ω.
- **Pogo magnético de 5 contactos (por hilos):** VBUS, D−, D+, GND y AUX.
  - Protecciones: PTC y TVS en VBUS, USBLC6 en D±.
  - El USB nativo del S3 sirve para cargar, descargar sesiones y programar.
- **Cargador y alimentación:** cargador BQ24072, con unos 590 mA de carga y unos 800 mA de entrada; batería soldada con PTC; 3,3 V TLV75733P de 1 A.
- **microSD** con alimentación conmutada.
- **Hall DRV5032:** detecta el imán de la base del casco y despierta la placa.

## Conexiones del ESP32-S3
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 1 | HALL (despertar) | 12–17 | microSD (SDMMC 4 bits) |
| 2 | BAT_ADC | 18 | VBUS_DET (despertar) |
| 4 | PPS del ZED | 19/20 | USB D−/D+ (pogo) |
| 5/6 | UART1 del ZED (RX/TX) | 21 | alimentación de la microSD (0 = encendida) |
| 7/8 | UART2 del ZED (RX/TX) | 38/39 | PGOOD / CHG del cargador |
| 9 | RESET_N del ZED | 40 | POGO_AUX |
| 10 | ZED_EN | 41/47/48 | libres (puntos de prueba) |

## Pendiente antes de pedir
- Piezas sin código LCSC: ZED-F9P (suministrarlo aparte o por *global sourcing*), U.FL, bobina de 47 nH, 22 Ω en 1206 y ESD de RF.
- Modelo real del pogo de 5 contactos y de la batería (≥ 2000 mAh).
- Confirmar el ancho de la línea de 50 Ω con la calculadora de JLC.
- **Firmware:** poner GPIO6, GPIO8 y GPIO9 como entradas antes de bajar ZED_EN.
- **Prueba de la antena** sobre un plano de 51 × 51: tiempo hasta el fix y ruido de velocidad.
