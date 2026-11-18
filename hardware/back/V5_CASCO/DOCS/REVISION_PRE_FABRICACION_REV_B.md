# Casco BETA BACK V5: revisión previa a fabricación de la PCB REV B (18/11/2026)

**Commit revisado:** `bb2908a` (rama `feature/back-v5-casco`) · **CI:** run 44302396164, puerta de fabricación **superada**.
**Nivel:** DISEÑO VERIFICADO POR SOFTWARE — **NO VERIFICADO EN HARDWARE**. Ninguna comprobación de este documento sustituye a
encender una placa real.

## 1. Veredicto honesto

No se puede tener la **certeza** de que una placa nueva funcione a la primera sin construirla: el software no comprueba
la soldadura, la radiofrecuencia, el ruido que llega al GNSS, el calor real ni los tiempos analógicos del encendido.
Lo que sí se ha hecho es eliminar todos los fallos que se pueden encontrar **antes** de pagar:

| Comprobación | Resultado | Qué garantiza | Qué NO garantiza |
|---|---|---|---|
| DRC KiCad 9 (reglas JLC 4 capas) | 0 errores, 4 avisos menores (2 restos de pista de 0,2 mm, 2 serigrafías recortadas) | Fabricable: separaciones, anillos, bordes | Que el circuito sea correcto |
| ERC del esquema | 0 errores | Pines sin conectar, salidas enfrentadas | Valores de componentes |
| Conexiones placa ↔ esquema | 0 conexiones incompletas, 1248 pistas, 269 vías | La placa es el esquema | — |
| Revisión pin a pin contra hojas de datos (los 13 CI) | Problemas encontrados y corregidos (`123fc25`): retención de EN en reinicios, arranque suave de la SD, VBUS_DET, condensador del cargador | Pines, tensiones máximas, niveles lógicos | Tolerancias reales |
| Revisión independiente (segundo agente, sin ver mi trabajo) | Confirmó las correcciones; 8 hallazgos más, todos aplicados en `767fdce` (R70, C64, D6, R24, R20…) | Segunda opinión | — |
| Huellas y giros de JLC | Huellas EasyEDA oficiales + correcciones de giro revisadas en el visor de JLC | Montaje correcto en JLC | Otros fabricantes (ver §7) |
| CAD con la placa REV B | 0 interferencias, cápsula 56,4 × 56,4 × 24,7 mm | Que la placa y la batería caben | Holguras reales de impresión |
| Existencias JLC | Todas las piezas con stock (ZED-F9P: 880 uds.) | Que se puede montar hoy | — |

**Riesgo residual (por orden):** 1) RF del GNSS junto al ESP32 y al elevador del anillo (ruido en L1/L2);
2) enclavamiento del encendido (tiempos con tolerancias reales); 3) temperatura del cargador al cargar dentro de la
cápsula al sol; 4) soldadura del ZED-F9P (LGA) y del LSM6DSV16X (LGA-14).
Los puntos 2 y 3 se pueden probar **antes** con la maqueta (§5); 1 y 4 solo con la placa real.

## 2. Corrección de la documentación anterior

`claude/AVO_BACK_V5_PCB_REV_B_2026-11-18.md` y el README decían que el MAX17048 «sigue midiendo con el casco
apagado». **Es incorrecto:** las resistencias de I²C van a +3V3, que se apaga; SDA y SCL quedan a 0 V y la hoja de datos
dice que el CI entra en reposo cuando ambas líneas están bajas más de 2,5 s (≈ 0,5 µA). Al encender recalcula el % por
tensión (ModelGauge) en segundos. Consecuencia: no hay error de diseño, solo de descripción; el % tras semanas apagado
sale de la tensión de la celda.

## 3. Cálculos de potencia (analíticos, hojas de datos; NO medidos)

### 3.1 Consumo en sesión (batería ≥ 2000 mAh)

Todos los reguladores de 3,3 V son lineales: la corriente de la batería ≈ la corriente de carga.

| Bloque | Típico | Pico | Fuente |
|---|---|---|---|
| ZED-F9P (4 constelaciones, RTK) | ≈ 70 mA | ≈ 130 mA (adquisición) | hoja u-blox |
| Antena activa (por R70 56 Ω) | 10–20 mA | 59 mA (coaxial en corto, limitado) | Taoglas / cálculo |
| ESP32-S3 (BLE + ESP-NOW, CPU 160 MHz) | 80–110 mA | ≈ 350 mA (TX Wi-Fi) | Espressif |
| microSD (escritura por bloques) | ≈ 20 mA medio | ≈ 100 mA | SD spec |
| LSM6DSV16X + MAX17048 + TTP223 | < 1 mA | — | hojas |
| Anillo LED (7 × SK6812, brillo de estado ≈ 10 %) | ≈ 20 mA | ≈ 500 mA de batería a 3,4 V (blanco 100 %) | cálculo |
| **Total** | **≈ 210–250 mA** | **≈ 1,1 A (todo a la vez)** | |

**Autonomía estimada:** 2000 mAh × 0,9 útil / 0,23 A ≈ **7–8 h** (sin anillo a pleno brillo).
**Apagado:** ≈ 50 µA estimados (V_BCKP del ZED + XC6206 + TTP223 + BQ24072 + divisor); manda la autodescarga de la celda.

### 3.2 Reguladores y calor

| Pieza | Peor caso | Disipación | Subida de temperatura | Veredicto |
|---|---|---|---|---|
| TLV75733 (3V3, SOT-23-5) | VSYS = VBAT + 225 mV ≈ 4,43 V (cargando, BQ24072), 150 mA medios | (4,43 − 3,3) × 0,15 ≈ 0,17 W | ≈ +35 °C | OK |
| RT9080 (3V3 del ZED) | 4,43 V, 90 mA | ≈ 0,10 W | ≈ +25 °C | OK |
| BQ24072 (QFN-16 con pad) | cargando 590 mA con la celda a 3,5 V + 200 mA de sistema | (5 − 3,5) × 0,59 + (5 − 3,7) × 0,2 ≈ 1,15 W | ≈ +45–50 °C | **Vigilar.** Al sol (35 °C dentro) llega a ≈ 85 °C; el CI reduce solo la corriente a 125 °C (regulación térmica). No se daña, carga más lento |
| R70 56 Ω 1206 | coaxial en corto | 0,19 W | — | OK (0,25 W) |

Con la batería a 4,2 V el BQ24072 no puede dar más de 4,43 V a VSYS: los 3,3 V nunca ven 5 V.
Por debajo de VBAT ≈ 3,45 V el TLV75733 pierde regulación con 0,35 A de pico (caída ≈ 0,15–0,2 V): por eso el firmware
corta a **3,4 V** (el ESP32 funciona hasta 3,0 V; el ZED hasta 2,7 V).

### 3.3 Anillo LED (TPS61023 → 4,28 V)

- Blanco 100 %: 7 × ≈ 50 mA = 0,35 A a 4,28 V → ≈ 0,5 A de entrada a 3,4 V (η ≈ 0,9).
- Pico de bobina (1 µH, 1 MHz, D ≈ 0,21): rizado ≈ 0,7 A → pico ≈ 0,85 A, muy por debajo del límite del CI y de la
  saturación de L71.
- **Hallazgo:** todo a la vez (anillo al 100 % + TX Wi-Fi + ZED + SD) ≈ 1,1 A por F1 (PTC 1,5 A de mantenimiento a
  25 °C; a 60 °C baja a ≈ 1,1 A). No hay fallo de diseño, pero **el firmware debe limitar el anillo al 30 %**
  (≈ 0,15 A) — además es suficiente para verse de día con difusor y ahorra batería.

### 3.4 Cargador

- I_carga = 890 / 1,5 kΩ ≈ 590 mA (0,3 C de 2000 mAh, ≈ 4 h). I_entrada = K_ILIM / 2 kΩ ≈ 775–800 mA.
- Con el anillo encendido en el DOCK, la carga se reduce sola (DPPM): correcto.
- Temporizador 68 kΩ ≈ 8,5–9 h. NTC 10 kΩ directa a TS (método por corriente del BQ24072 sin «T»): correcto.
- Nota menor: algunas notas citan la hoja SLUS937 (BQ24072**T**); la pieza es BQ24072RGTR (SLUS810). Las constantes
  son casi iguales (K_ILIM 1550 frente a 1600) y no cambian ningún valor.

## 4. Reglas de firmware obligatorias (derivadas de la revisión)

1. `PWR_HOLD` (GPIO46) a 1 en el primer arranque y con `gpio_hold_en` + `gpio_deep_sleep_hold_en`; apagar = poner 0
   tras soltar el táctil.
2. Antes de bajar `ZED_EN`: GPIO6 y GPIO8 (TX hacia el ZED) a 0 o en entrada, para no alimentar el ZED por la UART.
3. Antes de cortar la microSD (GPIO21 = 1): líneas SD en entrada.
4. Corte por batería baja a 3,4 V. Encendido escalonado: ESP32 → SD → ZED → anillo.
5. GPIO47 (DIN del anillo) a 0 con el anillo apagado. Hay 7 LED (no 8). Brillo máximo 30 %.
6. No usar `RESET_N` del ZED de forma rutinaria (borra la configuración en RAM); usar `ZED_EN`.
7. MAX17048: no se puede leer con el casco apagado (reposo por bus bajo). Leer el % 2–3 s después de encender.

## 5. Maqueta en protoboard antes de pagar la PCB

Objetivo: probar con piezas sueltas los bloques **nuevos** del diseño (encendido por táctil, enclavamiento, anillo a
4,3 V, arranque suave de la microSD, I²C, medidor) con el **mismo** firmware y los mismos GPIO. La placa de la espalda
prototipo (Heltec + ZED-F9P URTK1.2) **no se toca**; solo se reaprovechan el ZED URTK1.2 y la antena para probar las UART.

### 5.1 Lista de compra (precios consultados el 18/11/2026; IVA y envío aparte salvo indicación)

| # | Pieza | Para qué | Precio | Dónde |
|---|---|---|---|---|
| 1 | Espressif ESP32-S3-DevKitC-1U-N8R8 (o Waveshare ESP32-S3-DEV-KIT-N16R8-U) | Mismo módulo, antena externa, GPIO idénticos | 20,00 € | Tinytronics |
| 2 | Adafruit 5580 MAX17048 | Medidor y su reposo por bus bajo | 5,14 € | DigiKey ES |
| 3 | Adafruit 4654 MiniBoost 5 V (TPS61023) | Anillo: cambiar la resistencia de realimentación para 4,3 V | ≈ 3,4–4,5 € | DigiKey |
| 4 | Adafruit 4755 cargador BQ24074 | Ruta de potencia, PG/CHG, NTC (pariente del BQ24072: VSYS fija a 4,4 V en vez de VBAT + 225 mV) | 12,87 € | DigiKey (Letonia/UE) |
| 5 | SparkFun SEN-21325 LSM6DSV16X | IMU, INT1 → GPIO4, despertar del sueño profundo | 23,60 £ | The Pi Hut |
| 6 | Módulos TTP223 (pack de 10) | Táctil: modo, salida y consumo | ≈ 2–17 € | eBay / Fruugo |
| 7 | SK6812 4020 laterales (pack de 10, p. ej. Adafruit 4691) | Los mismos LED del anillo | orientativo ≈ 5–8 € | Adafruit / distribuidor |
| 8 | Adaptadores SOT-23 → DIP + BAT54C, AO3401A, XC6206P332 (unos pocos) | Enclavamiento (D5/D6), polaridad (Q7), carril siempre encendido (U9), interruptor de la SD (Q4) | orientativo ≈ 5–10 € | AliExpress / LCSC |
| 9 | Módulo microSD **sin** regulador (o tarjeta en adaptador) | Arranque suave con Q4 + 10 kΩ + 100 nF | orientativo ≈ 3–8 € | cualquiera |
| 10 | LiPo 1S 2000 mAh con protección | Batería real | orientativo ≈ 10–15 € | cualquiera |
| 11 | (opcional) Taoglas AHP2258.07.0060A | La antena de la BETA | 26,62 € (32,21 € con IVA) | DigiKey ES |
| — | ZED-F9P URTK1.2 + antena, Pololu S7V8F3 | Ya los tienes (prototipo) | 0 € | — |

**Maqueta mínima** (1, 2, 6, 8, 10 + resistencias y condensadores que ya tengas): **≈ 45–55 €**.
**Maqueta completa** (1–10): **≈ 105–120 €**; con la antena, ≈ 140 €.

### 5.2 Plan de pruebas (criterio de aprobado)

| # | Prueba | Montaje | Aprobado si |
|---|---|---|---|
| M1 | Encendido por táctil | TTP223 + D5 + R14 1 MΩ + C28 1 µF → EN del regulador | Toque de 0,3 s enciende; el firmware pone GPIO46 a 1 antes de 0,5 s |
| M2 | Reinicio sin apagarse | `esp_restart()`, OTA simulada y watchdog | EN no baja de 1,0 V (osciloscopio) en ningún reinicio |
| M3 | Apagado | Toque largo 2 s → GPIO46 = 0 | Se apaga; consumo total < 100 µA (multímetro en serie) |
| M4 | USB enciende | 5 V por D6 y divisor 100k/150k a GPIO18 | Enciende con USB; GPIO18 lee 1 (≈ 3,0 V > 2,48 V de VIH) |
| M5 | Anillo a 4,3 V | MiniBoost con realimentación cambiada, DIN por 330 Ω | 7 LED sin parpadeos ni colores falsos de 0 a 30 %; GPIO47 a 0 apagado sin LED encendidos por la entrada |
| M6 | microSD | Q4 + R47 10 kΩ + C42 100 nF | Al encender la tarjeta, 3V3 baja < 100 mV; el ESP32 no se reinicia; escritura a 1 kHz sin errores 1 h |
| M7 | I²C | MAX17048 (0x36) + LSM6DSV16X (0x6A) con 2,2 kΩ | Ambos responden a 400 kHz; el MAX17048 entra en reposo con 3V3 apagado |
| M8 | IMU despierta | INT1 → GPIO4, sueño profundo | Despierta al mover; corriente de sueño < 1 mA del conjunto |
| M9 | UART del ZED | URTK1.2: ZED_TX1 → GPIO5, ZED_TX2 → GPIO3, GPIO6/8 → RX, PPS → GPIO7 | NMEA/UBX a 460800 baudios sin errores 30 min; PPS medido; con el ZED apagado y GPIO6/8 a 0, VCC del ZED < 0,3 V |
| M10 | Consumo y calor | Todo funcionando + carga desde USB | Corriente de batería en sesión 0,2–0,26 A; cargador < 85 °C con termopar |

Lo que la maqueta **no** prueba: huellas, giros de montaje, la RF de la placa real, la disposición y el ruido sobre el
GNSS. Eso lo cubre la fabricación de 1–2 unidades.

## 6. Coste de fabricación y alternativas

Desglose (precios de piezas de JLC del 18/11 para 2 placas): **ZED-F9P 2 × 76 $ = 153 $**, ESP32-S3-WROOM-1U 10 $,
LSM6DSV16X 6 $, MAX17048 4 $, resto < 15 $. Más 19 piezas «extended» (≈ 3 $ de carga cada una ≈ 57 $), la placa de
4 capas ENIG, plantilla y montaje. **El ZED-F9P es casi la mitad del pedido.**

| Opción | Coste aprox. | Ventaja | Inconveniente |
|---|---|---|---|
| A. JLC, 2 placas completas | ≈ 350 € | Paquete listo y revisado en su visor | Mínimo 2 montadas |
| B. JLC, 2 placas con U1 (ZED-F9P) **sin montar** | ≈ 170–190 € | Se prueba todo lo demás (encendido, carga, SD, LED, IMU, Wi-Fi) en 2 placas | El ZED (LGA) se suelda después con aire caliente/placa calefactora o en un taller |
| C. PCBasic u otro, 1 unidad | según presupuesto | Una sola placa | Giros sin las correcciones de JLC: hay que revisarlos en su visor (paquete genérico) |
| D. Panel casco + cincha | no recomendable | — | La cincha es de 1,0 mm y el casco de 1,6 mm; JLC cobra «diseño diferente» y el montaje se cotiza por diseño |

## 7. Paquetes entregados (commit `bb2908a`)

- `JLCPCB_CASCO_BETA_V5_PCB_REVB_bb2908a.zip`: Gerber + taladros, BOM y CPL de JLC (con correcciones de giro), informe,
  DRC, ERC, `SHA256SUMS.txt`, `jlc_correcciones.json`. **Sustituye a todos los ZIP anteriores.**
- `PCBASIC_CASCO_BETA_V5_PCB_REVB_bb2908a.zip`: los mismos Gerber, BOM genérica con fabricante y MPN, CPL con giros
  nativos de KiCad (IPC-7351), lista de piezas no montadas, plano de montaje PDF, esquema PDF, STEP y
  `LEEME_FABRICANTE.txt` (generado por `fuente/generico.py`).
- `CAD_CASCO_BETA_V5_REVB.zip`: sin cambios (la placa no cambia de tamaño ni de altura).
