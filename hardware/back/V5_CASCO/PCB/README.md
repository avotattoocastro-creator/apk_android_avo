# AVO BACK V5 CASCO · PCB REV B (17/11/2026)

**Estado:** diseño verificado por software (KiCad 9 en el CI, run 44211872811, `62d0fe7`): DRC 0, 0 conexiones
incompletas, paridad 0, ERC 0/0. Ficheros en `out/FINAL/`. **No fabricada. No verificada en hardware.** La REV A (14/11/2026) queda en el historial de git (`c3a9778`).

## Cambios de la REV B (decisiones del usuario, 17/11/2026)
| Bloque | REV A | REV B |
|---|---|---|
| Micro | ESP32-S3-MINI-1U-N8 (8 MB, sin PSRAM, 2,4 mm) | **ESP32-S3-WROOM-1U-N16R8** (16 MB + 8 MB de PSRAM octal, 18 × 19,2 × 3,2 mm, C3013946). GPIO de la REV A salvo el RX de la UART2 del ZED (GPIO7 → GPIO3) y el PPS (GPIO4 → GPIO7) |
| Altura en la cara F | 2,6 mm | **3,2 mm**: la cápsula sube 0,6 mm (24,1 → 24,7). La planta de 51 × 51 no cambia |
| Encendido | siempre alimentada; Hall y VBUS despiertan del reposo | **apagado total**: EN del TLV75733P = OR(táctil TTP223, POWER_HOLD en GPIO46, VBUS) con 2 × BAT54C. Hall y VBUS_DET siguen despertando del reposo |
| V_BCKP del ZED | del 3,3 V principal | **+3V3_AON** (XC6206, ≈ 1 µA, desde la batería): arranque en caliente también tras apagar |
| Anillo de LED | VDD = VSYS: 0,6 mA por LED siempre (≈ 4,8 mA) y fuera de hoja por debajo de 3,7 V | **4,3 V con TPS61023** (EN = GPIO48; salida desconectada con EN = 0). DIN a 3,3 V válido |
| Cargador | TMR al aire (4–6 h) | **R_TMR 68 kΩ** (≈ 8,5 h; 6,6–10,4 h con la tolerancia de K_TMR) |
| Batería | sin protección de polaridad | **PMOS AO3401A** (como Q3 de la V4) |
| % de batería | divisor al ADC | divisor + **MAX17048** (I²C 0x36, ≈ 23 µA activo). Con el casco apagado el bus I²C queda sin tensión (pull-ups a +3V3), SDA/SCL a 0 V durante > 2,5 s y el medidor entra en reposo (≈ 0,5 µA): **no mide apagado**; al encender estima el % por tensión (ModelGauge) en segundos |
| IMU | — | **LSM6DSV16X** (I²C 0x6A; INT1 → GPIO4, despierta por movimiento) |

**Consumo con el casco apagado (ESTIMADO, hojas de datos):** ZED V_BCKP (decenas de µA) + MAX17048 en reposo ≈ 0,5 µA + TTP223
≈ 1,5 µA + XC6206 ≈ 1 µA + BQ24072 ≈ 6,5 µA + divisor del ADC ≈ 2 µA. Del orden de 50 µA: años de reposo con 2000 mAh.
Hay que medirlo.

### Montaje y JLC (18/11/2026)
- **microSD «push-pull»:** la tarjeta sobresale del conector hasta el canto inferior de la placa. Esa franja queda sin
  piezas (comprobación en el generador). El LED D14 se **quita** (petición del usuario: el anillo queda con 7 LED,
  D13 → D15) y los pads del pogo se desplazan 1 mm a la izquierda (P5 quedaba delante de la tarjeta). La tarjeta se pone con la placa fuera de la cápsula.
- **CPL corregido** con `fuente/jlc_correcciones.py` (como la cincha REV D): ZED-F9P +270°, IMU +180°, SOT-23 +180°,
  SOT-23-5/6 +270°, WROOM con su origen desplazado 0,63 mm. Ver `fuente/jlc_correcciones.json` (notas de los ajustes a
  mano). Comprobar igualmente la vista previa de JLC antes de pagar.

### Firmware (BACK 5.x, sin escribir)
- Al arrancar: subir **POWER_HOLD (GPIO46)** cuanto antes y comprobar la pulsación larga en **TOUCH_SENSE (GPIO11)**; si
  no llega a ~2 s, soltar POWER_HOLD (apagado). Mantener GPIO46 con `gpio_hold` en el sueño profundo.
- Apagar: confirmación en el anillo, cerrar sesión y microSD, soltar POWER_HOLD. Nunca a mitad de una grabación sin confirmar.
- Anillo: **LED_PWR (GPIO48)** = 1 antes de enviar datos por GPIO47; con el anillo apagado, GPIO47 a 0.
- I²C en GPIO41 (SCL) / GPIO42 (SDA): MAX17048 (0x36) y LSM6DSV16X (0x6A). UART2 del ZED: RX = GPIO3, TX = GPIO8. PPS en GPIO7.
- Siguen vigentes los avisos de la REV A (GPIO6/8/9 como entradas antes de bajar ZED_EN).

## Placa
- 51 × 51 mm, esquinas R3, 4 capas, 1,6 mm, ENIG.
- 4 taladros de Ø2,8 para los tornillos M2,5 de la caja, en (±22, ±22), y un paso de Ø3 para el coaxial de la antena.
- **Todos los componentes en la cara F**, que mira a la batería; la altura máxima es 2,6 mm.
- **B.Cu es masa maciza, sin pistas:** sirve de plano de masa de la antena GNSS plana activa de 25 × 25, pegada en el centro de la cara B.
- In1 es GND; In2 lleva señales y un relleno de +3V3.

## Bloques
- **ESP32-S3-WROOM-1U-N16R8** (REV B): BLE con el móvil y ESP-NOW con las cinchas. Antena FPC de 2,4 GHz (conector U.FL del módulo), pegada a la pared de la cápsula.
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
- **Anillo de luz:** 8 LED RGB direccionables de emisión lateral **SK6812SIDE-A** (LCSC C5378721), 2 por lado (a ±12 mm del centro; ±10 abajo), con la lente a 0,3 mm del canto frente al anillo de resina.
  - Van en cadena desde el GPIO47 con 33 Ω en serie y se alimentan de VSYS.
  - La hoja pide 3,7–5,5 V: con la batería por debajo de unos 3,6 V pueden fallar.
  - Con los 8 en blanco al máximo consumen unos 290 mA; el firmware limita el brillo.

## Conexiones del ESP32-S3 (REV B; en negrita, las nuevas)
| GPIO | Función | GPIO | Función |
|---|---|---|---|
| 1 | HALL (despertar) | 12–17 | microSD (SDMMC 4 bits) |
| 2 | BAT_ADC | 18 | VBUS_DET (despertar) |
| **3** | **RX de la UART2 del ZED (antes GPIO7)** | 19/20 | USB D−/D+ (pogo) |
| **4** | **IMU_INT1 (despertar)** | 21 | alimentación de la microSD (0 = encendida) |
| 5/6 | UART1 del ZED (RX/TX) | 35–37 | PSRAM octal del módulo (no usar) |
| **7** | **PPS del ZED (antes GPIO4)** | 38/39 | PGOOD / CHG del cargador |
| 8 | TX de la UART2 del ZED | | |
| 9 | RESET_N del ZED | 40 | POGO_AUX |
| 10 | ZED_EN | **41/42** | **I²C SCL / SDA** |
| **11** | **TOUCH_SENSE (despertar)** | **46** | **POWER_HOLD** |
| | | 47 | datos del anillo de luz |
| | | **48** | **LED_PWR (EN del elevador)** |

## Pendiente antes de pedir
- Piezas sin código LCSC: ZED-F9P (suministrarlo aparte o por *global sourcing*), U.FL, bobina de 47 nH, 22 Ω en 1206 y ESD de RF.
- Modelo real del pogo de 5 contactos y de la batería (≥ 2000 mAh).
- **REV B:** TTP223-BA6-TD (TDSEMIC, C42422127; el de Tontek no tiene existencias): mismo patillaje; ajustar Cs (C69, sin montar) con la pared real y probar con agua.
- **REV B:** piezas fuera de la BOM de JLC: antena FPC de 2,4 GHz con U.FL, antena GNSS AHP2258, batería, pogo, microSD, lámina de cobre del táctil.
- Confirmar el ancho de la línea de 50 Ω con la calculadora de JLC.
- **Firmware:** poner GPIO6, GPIO8 y GPIO9 como entradas antes de bajar ZED_EN.
- **Prueba de la antena** sobre un plano de 51 × 51: tiempo hasta el fix y ruido de velocidad.
