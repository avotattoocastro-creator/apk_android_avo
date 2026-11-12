"""Fase 8 — consumo y autonomía TEÓRICOS de la REV B a partir de hojas de datos (nada medido).
Uso: python3 autonomia.py → autonomia.md + autonomia.json (en esta carpeta)."""
import json
import os

H = os.path.dirname(os.path.abspath(__file__))
SRC = {
    "esp_rx": (0.082, "ESP32-C3-MINI-1 datasheet, tabla 9: RX 802.11b/g/n HT20 82 mA"),
    "esp_tx": (0.350, "ESP32-C3-MINI-1 datasheet, tabla 9: TX 802.11b 1 Mbps 20,5 dBm 350 mA (pico)"),
    "esp_modem": (0.023, "ESP32-C3-MINI-1 datasheet, tabla 10: modem-sleep 160 MHz CPU activa 23 mA"),
    "esp_deep": (5e-6, "ESP32-C3-MINI-1 datasheet, tabla 11: deep-sleep 5 µA"),
    "lsm6": (0.90e-3, "ST LSM6DS3TR-C, página de producto: 0,90 mA en modo combinado de alto rendimiento"),
    "mmc_per_meas": (225e-6 / 7, "MEMSIC MMC5983MA Rev A: BW=01 225 µA con 7 medidas/s (proporcional al nº de medidas)"),
    "mmc_pd": (1.0e-6, "MEMSIC MMC5983MA Rev A: power-down 1,0 µA"),
    "ldo_iq": (2e-6, "Richtek RT9080: corriente de reposo 2 µA típ."),
    "bq_ibat": (6.5e-6, "TI BQ2407x SLUS937C: IBAT(PDWN) ≤ 6,5 µA sin entrada"),
}
V = {k: v[0] for k, v in SRC.items()}
CAP_MAH = 500.0
PKT_PER_S = 104 / 10 + 1          # lotes IMU + STATUS (pruebas del firmware)
PKT_BYTES = 220                   # paquete IMU (pruebas del firmware)
PHY_US = 192 + PKT_BYTES * 8 / 1.0  # 802.11b 1 Mbps (velocidad por defecto de ESP-NOW) + preámbulo largo
TRIES = 1.3                       # reintentos/ACK supuestos

tx_duty = PKT_PER_S * PHY_US * 1e-6 * TRIES
static = dict(
    divisor_bat=4.2 / 2e6, R40_puerta_Q10=4.2 / 1e6, R45_reed=4.2 / 1e6, R49_R50_reed=4.2 / 1.1e6,
    R31_GPIO1_reed_cerrado=3.3 / 100e3, ldo=V["ldo_iq"], led=(3.3 - 1.9) / 1e3 * 0.03)


def scenario(name, esp, sensors, extra):
    i = esp + sensors + sum(extra.values())
    return dict(nombre=name, corriente_mA=round(i * 1e3, 2), componentes_mA={k: round(v * 1e3, 3) for k, v in
                dict(esp=esp, sensores=sensors, **extra).items()})


S = []
esp_active = V["esp_rx"] + tx_duty * (V["esp_tx"] - V["esp_rx"])
sens = V["lsm6"] + V["mmc_per_meas"] * 100
S.append(scenario("Funcionando (firmware V0.3.0: WIFI_PS_NONE, receptor siempre encendido)", esp_active, sens, static))
esp_ps = V["esp_modem"] + tx_duty * (V["esp_tx"] - V["esp_modem"]) + 0.15 * (V["esp_rx"] - V["esp_modem"])
S.append(scenario("Funcionando con ahorro de radio (propuesta: ventana de recepción ~15 %)", esp_ps, sens, static))
S.append(scenario("Funcionando con ahorro de radio y magnetómetro a 20 Hz (propuesta)", esp_ps,
                  V["lsm6"] + V["mmc_per_meas"] * 20, static))
for s in S:
    i = s["corriente_mA"]
    s["autonomia_h"] = dict(nueva_25C=round(CAP_MAH * 0.95 / i, 1), envejecida_80pc=round(CAP_MAH * 0.8 * 0.95 / i, 1),
                            frio_0C=round(CAP_MAH * 0.85 * 0.95 / i, 1))
off_out = 1e-6 + 0                                          # Q10 IDSS máx. a 30 V (a 4 V es menor)
off_in = 1e-6 + static["R45_reed"] + static["R49_R50_reed"]
R = dict(fuentes=SRC, tx_duty_pc=round(tx_duty * 100, 2), escenarios=S,
         apagada=dict(fuera_soporte_uA=round(off_out * 1e6, 2), dentro_soporte_uA=round(off_in * 1e6, 2),
                      anos_fuera=round(CAP_MAH * 1e-3 / off_out / 8760, 1), anos_dentro=round(CAP_MAH * 1e-3 / off_in / 8760, 1),
                      nota="la autodescarga de la celda LiPo (≈ 2–3 %/mes, dato típico de fabricantes) domina"),
         carga=dict(ichg_mA=dict(min=round(797 / 3.3, 0), tip=round(890 / 3.3, 0), max=round(975 / 3.3, 0)),
                    iin_mA=dict(min=round(1330 / 3.3, 0), tip=round(1512 / 3.3, 0), max=round(1700 / 3.3, 0)),
                    tiempo_h="≈ %.1f–%.1f (CC hasta ~80 %% + CV, estimado)" % (CAP_MAH * 0.8 / (975 / 3.3) + 0.5,
                                                                            CAP_MAH * 0.8 / (797 / 3.3) + 1.0)))
json.dump(R, open(os.path.join(H, "autonomia.json"), "w"), indent=1, ensure_ascii=False)
L = ["# Consumo y autonomía teóricos (REV B) — VERIFICADO POR CÁLCULO, sin mediciones", "",
     "Ciclo de transmisión supuesto: %.1f paquetes/s de %d B a 1 Mbps (×%.1f por reintentos) → %.2f %% del tiempo en TX."
     % (PKT_PER_S, PKT_BYTES, TRIES, tx_duty * 100), "",
     "| Escenario | Corriente | Autonomía 500 mAh nueva | envejecida (80 %) | a 0 °C (85 %) |", "|---|---|---|---|---|"]
for s in S:
    a = s["autonomia_h"]
    L.append("| %s | %.1f mA | %.1f h | %.1f h | %.1f h |" % (s["nombre"], s["corriente_mA"], a["nueva_25C"],
                                                          a["envejecida_80pc"], a["frio_0C"]))
L += ["", "Desglose (mA): " + "; ".join("%s: %s" % (s["nombre"].split(" (")[0], s["componentes_mA"]) for s in S[:1]), "",
      "Apagada: %.1f µA fuera del soporte, %.1f µA dentro del soporte (reed cerrado) → la autodescarga de la celda domina."
      % (R["apagada"]["fuera_soporte_uA"], R["apagada"]["dentro_soporte_uA"]), "",
      "Carga: ICHG = KISET/3,3 kΩ = %(min).0f–%(max).0f mA (típ. %(tip).0f); límite de entrada = KILIM/3,3 kΩ = " % R["carga"]["ichg_mA"]
      + "%(min).0f–%(max).0f mA (típ. %(tip).0f)." % R["carga"]["iin_mA"] + " Tiempo de carga " + R["carga"]["tiempo_h"] + " h.",
      "", "Fuentes:"] + ["- %s" % v[1] for v in SRC.values()]
open(os.path.join(H, "autonomia.md"), "w").write("\n".join(L) + "\n")
print("\n".join(L))
