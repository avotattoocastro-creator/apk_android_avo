# Análisis eléctrico — AVO GIRTH REV B (ESP32-C3)

Cálculos y razonamiento de diseño. **Nada de esto está medido**: es la base para la prueba del prototipo.
La REV A (ESP32-C6, BNO085, relé) tiene su análisis en `../../PCB_REV_A_C6/DOCS/ANALISIS_ELECTRICO.md`.

## 1. Corrientes y anchos de pista
Cobre exterior 1 oz (35 µm). Fórmula IPC-2221, capa externa: I = 0,048 · ΔT^0,44 · A^0,725 (A en mil², ΔT en °C).

| Red | Corriente prevista (pico) | Ancho mínimo (ΔT 10 °C) | Ancho usado | Capacidad (ΔT 10 °C) |
|---|---|---|---|---|
| BAT_RAW / VBAT (celda ↔ Q10 ↔ cargador) | 0,65 A (0,35 A del ESP32-C3 en TX + 0,27 A de carga) | 0,16 mm | 0,3 mm | ≈ 1,0 A |
| VSYS (cargador → RT9080) | 0,45 A | 0,11 mm | 0,3 mm | ≈ 1,0 A |
| VIN5 / VBUS | 0,46 A (límite ILIM) | 0,11 mm | 0,3 mm | ≈ 1,0 A |
| QI_AC1 / QI_AC2 / bobina | ~0,6 A eficaces a 110–205 kHz | 0,14 mm | 0,3 mm | ≈ 1,0 A |

0,3 mm da ≥ 1,5× de margen y entra limpio en los pines de 0,24 mm de las QFN de paso 0,5 mm.
Caída en Q10 (AO3401A, ≈ 85 mΩ con Vgs = −2,5 V): 55 mV a 0,65 A.

## 2. Caminos de alimentación y realimentaciones
- **USB → Qi:** VBUS va al pin AD del BQ51013B; Q1/Q2 (PMOS espalda con espalda) solo unen VBUS y VIN5 con AD-EN.
  Apagados, sus diodos se oponen: no hay paso en ningún sentido.
- **VIN5 → batería:** solo a través del BQ24072.
- **Celda → sistema:** BAT_RAW → Q10 → VBAT → BQ24072 (camino de potencia) → VSYS → RT9080 → 3,3 V.
- **Q10 apagado:** su diodo interno va de VBAT a la celda (sentido de carga). Sin 5 V nada lo polariza; la celda
  no alimenta nada.
- **D10 (BAV70):** VIN5 y PWR_HOLD llegan a PWR_G cada uno por su diodo: los 5 V nunca entran en GPIO5.
- **D11 (BAV70, los dos diodos en paralelo):** solo deja pasar el impulso del reed hacia PWR_G.
- **Lectura del reed:** Q16 traslada REED_HI (hasta 4,2 V) a GPIO1 a 3,3 V.

## 3. Corte de batería (Q10/Q11) — sustituye al relé
Q11 (AO3400A, Vth 0,65–1,45 V a 250 µA) solo tiene que bajar la puerta de Q10 contra R40 (1 MΩ): 4,2 µA. Con
tan poca corriente conduce por debajo de su Vth nominal, así que 1,45 V es un límite conservador.

| Situación | Cálculo | Resultado |
|---|---|---|
| **Se cierra el reed** (cápsula al soporte) | C40 (10 µF) sube X a V_bat; reparto con C41 (2,2 µF): PWR_G ≈ (V_bat − 0,7)·10/12,2 = 2,2 V (3,4 V) … 2,9 V (4,2 V). Descarga por R41‖R42 = 0,5 MΩ con 12,2 µF: τ ≈ 6,1 s | PWR_G > 1,45 V durante **≥ 2,6 s** (celda a 3,4 V). El ESP32-C3 pone PWR_HOLD en < 0,5 s (estimado) |
| **Funcionando** | PWR_HOLD = 3,3 V → PWR_G ≈ 2,9 V | Q10 cerrado; consumo propio del corte 4,2 µA (R40) |
| **Reinicio del ESP32** (vigilante, fallo) | PWR_HOLD queda en alta impedancia (R43 a 0); C41 se descarga por R42: τ = 2,2 s | PWR_G > 1,45 V durante **≈ 1,5 s**: el firmware vuelve a poner PWR_HOLD antes |
| **Apagar** (firmware: fuera del soporte 3 s, batería baja, orden remota o «APAGAR») | PWR_HOLD = 0; PWR_G de 2,9 V a 0,65 V: 2,2·ln(2,9/0,65) | Corte abierto en **≈ 3,3 s**; el ESP32 duerme mientras tanto |
| **Apagado remoto con la cápsula en el soporte** | el reed es por flanco (C40): con el reed fijo cerrado PWR_G no recibe nada de él | **Se puede apagar** igual que con el relé |
| **Base Qi o USB** | VIN5 por D10: PWR_G ≈ 4,3 V | Corte cerrado siempre que haya 5 V: **nunca queda bloqueado al cargar** |
| **Batería agotada** (protección de la celda abierta) | Con la base, el diodo de Q10 deja pasar la precarga del BQ24072 hacia la celda; al subir la tensión, Q10 conduce | Se recupera sin intervención |
| **Batería agotada y sin base** | sin energía | Normal: poner en la base |
| **Apagada** | Q10 con Vgs = 0 (fuga ≤ 1 µA máx. a 30 V; nA a 4 V); con el reed cerrado, R49 + R50 = 1,1 MΩ → 3,8 µA | **< 1 µA** fuera del soporte; 3,8 µA si se apaga en el soporte |

Al soltar el reed, X baja a −V_bat durante un momento: D11 queda en inversa (30 V) y Q11 no ve tensión negativa.

## 4. ESP32-C3-MINI-1U-N4: pines (hoja del módulo y guía de diseño de Espressif)
| Pin del módulo | GPIO | Uso | Restricción comprobada |
|---|---|---|---|
| 12 | 0 | IMU_INT (INT1 del LSM6) | RTC: despierta del sueño profundo |
| 13 | 1 | REED (vía Q16) | RTC: despierta |
| 5 | 2 | I²C SCL | **strapping**: la hoja del módulo pide 1 en el arranque (la guía dice que no decide el modo y recomienda pull-up): R21 4,7 k a 3,3 V |
| 6 | 3 | BAT_ADC | ADC1_CH3 (el ADC2 no se usa: choca con la radio) |
| 18 | 4 | CHG_PG | RTC: despierta al quitar la base (sueño en carga) |
| 19 | 5 | PWR_HOLD | R43 100 k a masa: 0 mientras arranca |
| 20 | 6 | I²C SDA | R20 4,7 k |
| 21 | 7 | CHG_STAT | pulso bajo de ~5 ns al encender (guía de Espressif): es una entrada, sin efecto |
| 22 | 8 | LED (activo bajo) | **strapping**: 1 para el modo descarga → R13 10 k a 3,3 V y el LED va a 3,3 V |
| 23 | 9 | BOOT (TP2) | **strapping**: R12 10 k a 3,3 V; a masa = descarga. Sin condensador (la guía lo prohíbe) |
| 16 | 10 | QI_CHG | pulso bajo de ~5 ns al encender: entrada, sin efecto |
| 26 / 27 | 18 / 19 | USB D− / D+ | USB-Serial-JTAG: programación y consola |
| 30 / 31 | 20 / 21 | RXD0 / TXD0 (TP5 / TP4) | UART0 de la ROM: registro y recuperación (la guía pide conservarlo) |
| 8 | EN | 10 k + 1 µF (valores de la guía), TP1 | |
| 3 | 3V3 | 22 µF + 100 nF junto al pin; RT9080 de 600 mA (la guía pide ≥ 500 mA) | |

Los 13 GPIO libres del C3 están todos usados. Con el BNO085 por SPI habrían hecho falta 16: por eso el C3 obliga a
una IMU por I²C (y el BNO08x tiene problemas conocidos de I²C con los ESP32).

## 5. IMU por I²C
- LSM6DS3TR-C (dirección 0x6A, SA0 a masa; CS a 3,3 V = I²C; SDx/SCx a masa; OCS_Aux y SDO_Aux sin conectar, como
  permite la hoja del LSM6DSV16X, que comparte huella). 100 nF en VDD y en VDDIO.
- MMC5983MA (0x30): SPI_CS a VDDIO = I²C; CAP con 10 µF (la hoja pide ≥ 10 µF de baja ESR junto al pin); 1 µF en VDD
  y 100 nF en VDDIO. Lejos de las pistas de batería (Q10 a 14 mm) y de la bobina.
- Bus a 400 kHz con 4,7 k: tiempo de subida ≈ 0,85·4,7 k·(≈ 30 pF) ≈ 0,12 µs < 0,3 µs (modo rápido).

## 6. Consumo estimado
| Estado | Consumo |
|---|---|
| Apagada (fuera del soporte) | < 1 µA (fuga de Q10) + autodescarga de la celda |
| Funcionando: ESP32-C3 con ESP-NOW + LSM6 (104 Hz) + MMC5983MA (100 Hz) | ≈ 25–45 mA (estimado) → 11–20 h con 500 mAh |
| En la base Qi, fuera del soporte (sueño profundo) | ≈ 5 µA ESP32-C3 + 2 µA RT9080 + reposo de LSM6/MMC (≈ 3 + 1 µA); lo da la base |
