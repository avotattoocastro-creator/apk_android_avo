"""Tabla GPIO firmware ↔ esquema/placa (fase 5). Fuentes independientes:
 - firmware: firmware/girth/V0_3_0_C3/AVO_GIRTH_V0_3_0/girth_board.h (PIN_*)
 - módulo: símbolo oficial de Espressif (ESP32-C3-MINI-1, número de pin → GPIO)
 - placa: red de cada pad de U4 en la placa entregada (out/C3/KiCad/AVO_GIRTH_PCB.kicad_pcb)
Uso: python3 gpio_tabla.py [ruta_simbolo_espressif]  → gpio_tabla.md + gpio_tabla.json"""
import json
import os
import re
import sys

H = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(H, "..", "..", "..", "..", "..")
SYM = sys.argv[1] if len(sys.argv) > 1 else os.path.join(H, "ESP32-C3-MINI-1_simbolo_espressif.kicad_sym.txt")
board_h = open(os.path.join(ROOT, "firmware/girth/V0_3_0_C3/AVO_GIRTH_V0_3_0/girth_board.h")).read()
fw = {name: int(v) for name, v in re.findall(r"static const int (PIN_\w+)\s*=\s*(\d+);", board_h)}
# símbolo: pines del ESP32-C3-MINI-1 (el -1U usa el mismo)
s = open(SYM).read()
i = s.find('(symbol "ESP32-C3-MINI-1"'); j = s.find('\n\t(symbol "', i + 10)
blk = s[i:j]
pin_gpio = {}
for name, num in re.findall(r'\(pin \w+ \w+.*?\(name "([^"]*)".*?\(number "([^"]*)"', blk, re.S):
    m = re.match(r"GPIO(\d+)", name)
    if m:
        pin_gpio[num] = int(m.group(1))
gpio_pin = {g: p for p, g in pin_gpio.items()}
# placa: red de cada pad de U4
pcb = open(os.path.join(ROOT, "hardware/girth/PCB/out/C3/KiCad/AVO_GIRTH_PCB.kicad_pcb")).read()
u4 = [b for b in pcb.split("\n\t(footprint ")[1:] if re.search(r'"Reference" "U4"', b)][0]
pad_net = {}
for m in re.finditer(r'\(pad "(\d+)".*?\(net \d+ "([^"]*)"\)', u4, re.S):
    pad_net.setdefault(m.group(1), m.group(2))
EXPECT = {"PIN_IMU_INT": "IMU_INT", "PIN_REED": "REED", "PIN_SCL": "I2C_SCL", "PIN_BAT_ADC": "BAT_ADC",
          "PIN_CHG_PG": "CHG_PG", "PIN_PWR_HOLD": "PWR_HOLD", "PIN_SDA": "I2C_SDA", "PIN_CHG_STAT": "CHG_STAT",
          "PIN_LED": "LED", "PIN_BOOT": "BOOT", "PIN_QI_CHG": "QI_CHG"}
rows, bad = [], 0
for name, g in sorted(fw.items(), key=lambda kv: kv[1]):
    pin = gpio_pin.get(g)
    net = pad_net.get(pin)
    ok = net == EXPECT.get(name)
    bad += not ok
    rows.append(dict(firmware=name, gpio=g, pin_modulo=pin, red_placa=net, esperada=EXPECT.get(name), ok=ok))
for g, fixed in ((18, "USB_DM"), (19, "USB_DP"), (20, "U0RX"), (21, "U0TX")):
    pin = gpio_pin.get(g); net = pad_net.get(pin); ok = net == fixed; bad += not ok
    rows.append(dict(firmware="(núcleo: USB / UART0)", gpio=g, pin_modulo=pin, red_placa=net, esperada=fixed, ok=ok))
used = {r["gpio"] for r in rows}
free = sorted(set(pin_gpio.values()) - used)
L = ["| Nombre en el firmware | GPIO | Pin del módulo | Red en la placa | Esperada | Coincide |", "|---|---|---|---|---|---|"]
for r in rows:
    L.append("| %s | %d | %s | %s | %s | %s |" % (r["firmware"], r["gpio"], r["pin_modulo"], r["red_placa"], r["esperada"],
                                              "sí" if r["ok"] else "**NO**"))
L.append("")
L.append("GPIO del módulo sin usar: %s · discrepancias: %d" % (free or "ninguno", bad))
open(os.path.join(H, "gpio_tabla.md"), "w").write("\n".join(L) + "\n")
json.dump(dict(filas=rows, libres=free, discrepancias=bad), open(os.path.join(H, "gpio_tabla.json"), "w"), indent=1)
print("\n".join(L))
sys.exit(1 if bad else 0)
