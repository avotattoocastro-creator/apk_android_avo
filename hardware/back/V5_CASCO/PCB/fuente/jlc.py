"""BOM and CPL (pick & place) in JLCPCB format, from the part list written by the generator and the
positions exported by KiCad (out/posiciones_kicad.csv). Run from hardware/back/V4/PCB."""
import csv
import json
import os
from collections import OrderedDict

parts = json.load(open("kicad/piezas.json", encoding="utf-8"))
pos = {}
with open("out/posiciones_kicad.csv", newline="", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        pos[r["Ref"]] = r

bom = OrderedDict()
missing = []
for p in parts:
    if p.get("dnp") or not p.get("lcsc") or p.get("no_assembly"):
        continue
    key = (p["value"], p["footprint"], p["lcsc"])
    bom.setdefault(key, []).append(p["ref"])
    if p["ref"] not in pos:
        missing.append(p["ref"])

with open("out/JLCPCB_BOM.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
    for (val, fp, lcsc), refs in bom.items():
        w.writerow([val, ",".join(sorted(refs, key=lambda r: (r.rstrip("0123456789"), int("0" + r.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZ"))))), fp, lcsc])

with open("out/JLCPCB_CPL.csv", "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
    for p in parts:
        if p.get("dnp") or not p.get("lcsc") or p.get("no_assembly"):
            continue
        r = pos.get(p["ref"])
        if not r:
            continue
        rot = (float(r["Rot"]) + p.get("jlc_rot", 0)) % 360
        w.writerow([p["ref"], "%smm" % r["PosX"], "%smm" % r["PosY"],
                    "Top" if r["Side"].lower().startswith("top") else "Bottom", "%g" % rot])

print("BOM: %d líneas, %d piezas" % (len(bom), sum(len(v) for v in bom.values())))
if missing:
    print("::warning title=CPL::sin posición en KiCad: " + ", ".join(missing))
