"""Contraste independiente del ODB++ con los Gerber/Excellon que KiCad genera de la MISMA placa:
- cada taladro del ODB++ (vías, PTH, NPTH) tiene un taladro en el Excellon en la misma posición y con el mismo diámetro;
- número de pads «flash» (D03) de cada capa de cobre del Gerber frente a los pads (P) de la capa ODB++.
Uso: comparar_gerber_odb.py <odb.zip> <dir_gerber> <validacion_odb.json> <salida.md>"""
import json
import math
import os
import re
import sys
import zipfile
from collections import Counter

ZIP, GD, VJ, OUT = sys.argv[1:5]
V = json.load(open(VJ, encoding="utf-8"))
T = V["transformacion_num"]
z = zipfile.ZipFile(ZIP)
root = V["raiz"] if V["raiz"] != "(raíz del ZIP)" else ""
SP = root + "steps/%s/" % V["steps"][0]
L, ok = [], True


def odb_pads(layer):
    t = z.read(SP + "layers/%s/features" % layer).decode()
    syms = {int(m.group(1)): m.group(2) for m in re.finditer(r"^\$(\d+)\s+(\S+)", t, re.M)}
    out = []
    for line in t.splitlines():
        if line.startswith("P "):
            f = line.split()
            out.append((float(f[1]), float(f[2]), syms.get(int(f[3]), "")))
    return out


# ---------------- taladros
exc = []
for fn in sorted(os.listdir(GD)):
    if not fn.endswith(".drl"):
        continue
    tools, cur, metric = {}, None, True
    for line in open(os.path.join(GD, fn)):
        line = line.strip()
        m = re.match(r"^T(\d+)C([\d.]+)", line)
        if m:
            tools[int(m.group(1))] = float(m.group(2)); continue
        m = re.match(r"^T(\d+)$", line)
        if m:
            cur = int(m.group(1)); continue
        m = re.match(r"^X(-?[\d.]+)Y(-?[\d.]+)", line)
        if m and cur is not None:
            exc.append((float(m.group(1)), float(m.group(2)), tools[cur], fn))
odb = []
for d in V["capas"]:
    if d["tipo"] == "DRILL" and d["contexto"] == "BOARD":
        for x, y, s in odb_pads(d["nombre"]):
            m = re.match(r"r([\d.]+)", s)
            dia = float(m.group(1)) / (1000.0 if float(m.group(1)) > 20 else 1.0) if m else None   # r300 = 300 µm
            odb.append((x, y, dia, d["nombre"]))
# ODB = KiCad + desplazamiento; Excellon de KiCad = (x, −y) en coordenadas absolutas → KiCad = (x, −y)
def to_odb(x, y):
    return (x + T["ox"], T["sy"] * (-y) + T["oy"])
ex_odb = [(to_odb(x, y), d) for x, y, d, _ in exc]
sin_par, dia_mal = 0, 0
for x, y, d, ln in odb:
    best = min(ex_odb, key=lambda e: math.hypot(e[0][0] - x, e[0][1] - y))
    if math.hypot(best[0][0] - x, best[0][1] - y) > 0.002:
        sin_par += 1
    elif d is not None and abs(best[1] - d) > 0.002:
        dia_mal += 1
L.append("Taladros: ODB++ %d · Excellon %d · sin pareja en el Excellon: %d · diámetro distinto: %d"
         % (len(odb), len(exc), sin_par, dia_mal))
L.append("Diámetros en el Excellon: %s" % dict(Counter(d for _, _, d, _ in exc)))
L.append("Diámetros en el ODB++: %s" % dict(Counter(d for _, _, d, _ in odb)))
ok &= sin_par == 0 and dia_mal == 0 and len(odb) == len(exc)

# ---------------- pads de cobre
gmap = {"F_Cu": "gtl", "In1_Cu": "g1", "In2_Cu": "g2", "B_Cu": "gbl"}
for d in V["capas"]:
    if d["tipo"] in ("SIGNAL", "POWER_GROUND", "MIXED") and d["contexto"] == "BOARD":
        n_odb = len(odb_pads(d["nombre"]))
        key = re.sub(r"[^a-z0-9]", "", d["nombre"].lower())
        cand = [f for f in os.listdir(GD) if re.sub(r"[^a-z0-9]", "", f.lower()).endswith(key + "g" + key[0]) or key in re.sub(r"[^a-z0-9]", "", f.lower())]
        gf = [f for f in cand if f.split(".")[-1] in gmap.values()]
        n_g = None
        if gf:
            t = open(os.path.join(GD, gf[0])).read()
            n_g = len(re.findall(r"D03\*", t))
        L.append("Capa %s: pads ODB++ %d · flashes (D03) en %s: %s" % (d["nombre"], n_odb, gf[0] if gf else "?", n_g))
open(OUT, "w", encoding="utf-8").write("# Contraste ODB++ ↔ Gerber/Excellon de la misma placa\n\n" +
                                       "\n".join("- " + l for l in L) + "\n\nRESULTADO taladros: %s\n" % ("IGUALES" if ok else "DIFERENCIAS"))
print("\n".join(L)); print("taladros", "IGUALES" if ok else "DIFERENCIAS")
sys.exit(0 if ok else 1)
