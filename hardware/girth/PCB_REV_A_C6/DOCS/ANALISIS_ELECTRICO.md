# Análisis eléctrico — AVO GIRTH REV A

Cálculos y razonamiento de diseño. **Nada de esto está medido**: es la base para la prueba del prototipo.

## 1. Corrientes y anchos de pista
Cobre exterior 1 oz (35 µm), interior 0,5 oz (planos). Fórmula IPC-2221, capa externa:
I = 0,048 · ΔT^0,44 · A^0,725 (A en mil², ΔT en °C).

| Red | Corriente prevista (pico) | Ancho mínimo para ΔT = 10 °C | Ancho usado | Capacidad con el ancho usado (ΔT 10 °C) | Caída (30 mm) |
|---|---|---|---|---|---|
| VBAT (batería ↔ cargador ↔ relé) | 0,63 A (0,38 A del ESP32 en TX + 0,25 A de carga) | 0,15 mm | 0,3 mm | ≈ 1,0 A | 31 mV a 0,63 A |
| VSYS (cargador → RT9080) | 0,45 A (ESP32 + BNO + LDO) | 0,11 mm | 0,3 mm | ≈ 1,0 A | 22 mV |
| VIN5 / VBUS (5 V Qi o USB → cargador) | 0,45 A (límite ILIM del BQ24072) | 0,11 mm | 0,3 mm | ≈ 1,0 A | 22 mV |
| QI_AC1 / QI_AC2 / bobina | ~0,6 A eficaces a 110–205 kHz | 0,14 mm (efecto pelicular despreciable a 35 µm) | 0,3 mm | ≈ 1,0 A | — |
| QI_RECT | 0,1 A eficaces (TI) | — | 0,3 mm | — | — |
| Bobina del relé | 46 mA durante 20–40 ms | — | 0,2 mm | — | — |

Resistencia de la pista de 0,3 mm en 1 oz: 1,64 mΩ/mm. **Conclusión:** 0,3 mm da un margen de ≥ 1,6× en todas
las redes de potencia, y es el ancho que entra limpio en los pines de 0,24 mm de las QFN de paso 0,5 mm
(holgura al pin vecino 0,225 mm ≥ 0,15 mm). Los planos In1 (GND) e In2 (+3V3) cubren toda la placa.

## 2. Caminos de alimentación y realimentaciones
- **USB → Qi:** VBUS va al pin AD del BQ51013B. Q1/Q2 (dos PMOS espalda con espalda, fuentes comunes) unen VBUS
  con VIN5 solo cuando AD-EN los enciende. Apagados, sus diodos internos se oponen: **no hay paso en ningún
  sentido**. Con USB presente, el BQ51013B apaga la recepción inalámbrica y avisa al emisor.
- **VIN5 → batería:** solo a través del BQ24072 (no conduce de BAT/OUT hacia IN).
- **Batería → sistema:** BAT → OUT por el transistor interno del BQ24072 (camino de potencia). La carga termina
  aunque el ESP32 consuma, porque el cargador mide la corriente de la batería por separado.
- **Pulso del relé:** D10 (BAT54C) une REED_HI y VIN5 hacia RLY_P sin que ninguno alimente al otro.
- **Lectura del reed:** Q16 traslada el nivel (REED_HI puede ser 4,2 V) a GPIO6 a 3,3 V; nada de la batería entra en
  un pin del ESP32.
- **GPIO14 → puerta de Q11:** a través de D11 (BAT54C): con el ESP32 apagado, el pulso no puede entrar en el pin.

## 3. Relé biestable: secuencias
Relé Omron G6KU-2F-Y DC3: una bobina, 91 Ω, SET/RESET con ≥ 2,25 V durante ≥ 10 ms, máximo 4,5 V. SET = pin 1 (+).

| Situación | Qué pasa | Resultado |
|---|---|---|
| Cápsula entra en el soporte (relé abierto) | Reed cierra → REED_HI = batería → D10 → C40+C41 (440 µF) → bobina 1→8, Q11 a masa. τ = 440 µF × 91 Ω ≈ 40 ms; con 3,3 V de batería quedan ≥ 2,25 V durante ≈ 11 ms | Relé cerrado, el sistema arranca |
| Se pone en la base Qi o en USB (relé abierto) | VIN5 → D10 → mismo pulso; además el cargador alimenta VSYS por su camino de potencia y el ESP32 arranca | Relé cerrado por el pulso y, si hiciera falta, por el firmware (GPIO14) |
| Salida del soporte | GPIO6 pasa a HIGH. El firmware guarda, espera 3 s y pone GPIO23 en HIGH 20 ms (Q13 + Q14 invierten la bobina) | Relé abierto: 0 µA |
| **Apagado pedido con el cargador puesto** | El relé se abre, pero el ESP32 sigue vivo por VSYS (cargador). El firmware **no debe** apagar con CHG_PG = LOW; si lo hiciera, en el siguiente arranque cierra el relé con GPIO14 | **No se bloquea**: con la base puesta siempre hay alimentación y el firmware recupera el relé |
| Batería agotada (protección de la celda abierta) | En la base: VIN5 da el pulso y alimenta VSYS; el BQ24072 precarga la celda | Se recupera sin intervención |
| Batería agotada y sin base | No hay energía para nada | Normal: poner en la base |
| GPIO14 y GPIO23 a la vez (error de firmware) | Q12 apaga Q11; en K_A, Q17 (por R52 de 10 Ω) contra Q13: ≈ 0,4 A durante el pulso | Sin daño (R52 0805, pulso de 20 ms) |
| Reset/arranque del ESP32 | R48 y R54 mantienen GPIO23 y GPIO14 a LOW; R30 mantiene el BNO apagado | El relé no se mueve |

Transitorios de la bobina: al cortar el pulso de RESET, los diodos internos de Q11 y Q13 recortan las dos patas de
la bobina a −0,7 V y C40/C41 absorben la energía (L·I² ínfimo). En SET por pulso, la corriente se extingue
suavemente al cargarse los condensadores.

Reglas para el firmware (también en el README):
1. Al arrancar con CHG_PG = LOW (cargador presente): pulso SET de 20 ms en GPIO14 (inocuo si ya está cerrado).
2. Nunca GPIO23 (RESET) con CHG_PG = LOW.
3. GPIO14 y GPIO23 nunca a la vez; pulsos de 20 ms.

## 4. ESP32-C6-MINI-1U: pines (datasheet del módulo v1.5 y guía de diseño de Espressif)
| Pin del módulo | GPIO | Uso | Restricción comprobada |
|---|---|---|---|
| 12 | 0 | IMU_INT | LP GPIO (despertar ext1); pin del cristal de 32 kHz, que no se usa |
| 13 | 1 | IMU_RST | LP GPIO |
| 5 | 2 | BAT_ADC | ADC1_CH2 |
| 6 | 3 | CHG_PG | LP GPIO |
| 9 | 4 | CHG_STAT | strapping MTMS (solo flanco SDIO): sin efecto en el arranque por flash |
| 10 | 5 | IMU_PWR_N | strapping MTDI (solo flanco SDIO); R30 lo lleva a HIGH (BNO apagado) |
| 15 | 6 | REED (vía Q16) | LP GPIO |
| 16 | 7 | IMU_WAKE (PS0) | LP GPIO |
| 22 | 8 | libre con pull-up 10 k | strapping: debe estar en HIGH para descargar por USB |
| 23 | 9 | BOOT (TP2) | strapping: pull-up 10 k; a masa = modo descarga |
| 17 / 18 | 12 / 13 | USB D− / D+ | USB-Serial-JTAG |
| 19 | 14 | RELÉ ON | GPIO normal, pull-down 100 k |
| 20 | 15 | LED | strapping de JTAG: pull-down 10 k (nivel definido) |
| 24–27 | 18–21 | SPI del BNO085 (CS, SCK, MOSI, MISO) | sin restricciones |
| 28 | 22 | QI_CHG | — |
| 29 | 23 | RELÉ OFF | pull-down 100 k |
| 30 / 31 | 17 / 16 | RXD0 / TXD0 (TP5 / TP4) | registro de arranque de la ROM |
| 8 | EN | 10 k + 1 µF, TP1 | — |

Alimentación: RT9080-33 (600 mA; pico del ESP32 382 mA), 22 µF + 100 nF junto al pin 3 y 10 µF a la salida del LDO.
Espressif pide ≥ 500 mA de capacidad y 10 µF en la entrada: se cumple.

## 5. BNO085
SPI modo 3 a ≤ 3 MHz (PS0 = PS1 = 1). Cristal de 32,768 kHz (FC-135, 12,5 pF) con 22 pF; CLKSEL0 a masa; CAP 100 nF;
BOOTN, NRST, H_CSN, ENV_SCL y ENV_SDA con 10 k a IMU_VDD. Alimentación conmutada por Q3: todas las resistencias de
pull-up van a IMU_VDD, así un BNO apagado no recibe corriente por ellas. Opción I²C: montar R22/R23 (PS1/PS0 a masa)
y R28/R29 (pull-ups de 4,7 k), quitar R21; dirección 0x4A.
