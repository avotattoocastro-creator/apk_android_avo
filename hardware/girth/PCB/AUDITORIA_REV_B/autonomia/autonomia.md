# Consumo y autonomía teóricos (REV B) — VERIFICADO POR CÁLCULO, sin mediciones

Ciclo de transmisión supuesto: 11.4 paquetes/s de 220 B a 1 Mbps (×1.3 por reintentos) → 2.89 % del tiempo en TX.

| Escenario | Corriente | Autonomía 500 mAh nueva | envejecida (80 %) | a 0 °C (85 %) |
|---|---|---|---|---|
| Funcionando (firmware V0.3.0: WIFI_PS_NONE, receptor siempre encendido) | 94.0 mA | 5.1 h | 4.0 h | 4.3 h |
| Funcionando con ahorro de radio (propuesta: ventana de recepción ~15 %) | 45.5 mA | 10.4 h | 8.3 h | 8.9 h |
| Funcionando con ahorro de radio y magnetómetro a 20 Hz (propuesta) | 42.9 mA | 11.1 h | 8.8 h | 9.4 h |

Desglose (mA): Funcionando: {'esp': 89.753, 'sensores': 4.114, 'divisor_bat': 0.002, 'R40_puerta_Q10': 0.004, 'R45_reed': 0.004, 'R49_R50_reed': 0.004, 'R31_GPIO1_reed_cerrado': 0.033, 'ldo': 0.002, 'led': 0.042}

Apagada: 1.0 µA fuera del soporte, 9.0 µA dentro del soporte (reed cerrado) → la autodescarga de la celda domina.

Carga: ICHG = KISET/3,3 kΩ = 242–295 mA (típ. 270); límite de entrada = KILIM/3,3 kΩ = 403–515 mA (típ. 458). Tiempo de carga ≈ 1.9–2.7 (CC hasta ~80 % + CV, estimado) h.

Fuentes:
- ESP32-C3-MINI-1 datasheet, tabla 9: RX 802.11b/g/n HT20 82 mA
- ESP32-C3-MINI-1 datasheet, tabla 9: TX 802.11b 1 Mbps 20,5 dBm 350 mA (pico)
- ESP32-C3-MINI-1 datasheet, tabla 10: modem-sleep 160 MHz CPU activa 23 mA
- ESP32-C3-MINI-1 datasheet, tabla 11: deep-sleep 5 µA
- ST LSM6DS3TR-C, página de producto: 0,90 mA en modo combinado de alto rendimiento
- MEMSIC MMC5983MA Rev A: BW=01 225 µA con 7 medidas/s (proporcional al nº de medidas)
- MEMSIC MMC5983MA Rev A: power-down 1,0 µA
- Richtek RT9080: corriente de reposo 2 µA típ.
- TI BQ2407x SLUS937C: IBAT(PDWN) ≤ 6,5 µA sin entrada
