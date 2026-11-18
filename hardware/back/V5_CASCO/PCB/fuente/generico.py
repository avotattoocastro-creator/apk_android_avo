"""Paquete de montaje GENÉRICO (PCBasic, PCBWay, Eurocircuits, etc.), sin las correcciones propias de JLCPCB.

Genera en out/GENERICO/:
  - AVO_BACK_V5_BOM_generica.csv  : BOM con fabricante y MPN (sacados de out_stock/stock_jlc.json), código LCSC
                                     como referencia de compra y piezas NO montadas (DNP / pads de cable) aparte.
  - AVO_BACK_V5_CPL_generico.csv  : posiciones con el giro NATIVO de KiCad (IPC-7351, sin correcciones de JLC).
  - AVO_BACK_V5_montaje.pdf       : plano de montaje (cara superior) con contorno, pads, designadores y pin 1.
  - LEEME_FABRICANTE.txt          : especificaciones de placa y notas de montaje para el fabricante.

Ejecutar desde hardware/back/V5_CASCO/PCB tras el CI (necesita out/posiciones_kicad.csv o usa kicad/piezas.json)."""
import csv
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import matplotlib                                    # noqa: E402
matplotlib.use("Agg")
import matplotlib.pyplot as plt                      # noqa: E402
from matplotlib.backends.backend_pdf import PdfPages  # noqa: E402
from matplotlib.patches import Polygon, Rectangle    # noqa: E402

import avo_back_v5_pcb as D                          # noqa: E402
from fplib import pad_poly                           # noqa: E402

OUT = "out/GENERICO"
os.makedirs(OUT, exist_ok=True)
parts = json.load(open("kicad/piezas.json", encoding="utf-8"))
stock = {}
if os.path.exists("out_stock/stock_jlc.json"):
    stock = json.load(open("out_stock/stock_jlc.json", encoding="utf-8")).get("parts", {})

pos = {}
if os.path.exists("out/posiciones_kicad.csv"):
    with open("out/posiciones_kicad.csv", newline="", encoding="utf-8") as f:
        for r in csv.DictReader(f):
            pos[r["Ref"]] = (float(r["PosX"]), float(r["PosY"]), float(r["Rot"]),
                             "Top" if r["Side"].lower().startswith("top") else "Bottom")
fuente_pos = "out/posiciones_kicad.csv" if pos else "kicad/piezas.json"


def orden(r):
    return (r.rstrip("0123456789"), int("0" + r.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZ")))


def montar(p):
    return not p.get("dnp") and not p.get("no_assembly") and p.get("lcsc")


# ------------------------------------------------------------------------------------------------ BOM
grupos = {}
for p in parts:
    if not montar(p):
        continue
    grupos.setdefault((p["value"], p["footprint"], p["lcsc"]), []).append(p)
faltan_mpn = []
with open(os.path.join(OUT, "AVO_BACK_V5_BOM_generica.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["Item", "Qty", "Designators", "Value", "Description", "Manufacturer", "MPN", "Footprint",
                "LCSC (reference)"])
    for i, ((val, fp, lcsc), ps) in enumerate(sorted(grupos.items(), key=lambda kv: orden(min((p["ref"] for p in kv[1]), key=orden))), 1):
        s = stock.get(lcsc, {})
        mpn = s.get("mpn") or ps[0].get("mpn", "").split(" (")[0]
        maker = s.get("maker", "")
        if not mpn:
            faltan_mpn.append(lcsc)
        w.writerow([i, len(ps), ",".join(sorted((p["ref"] for p in ps), key=orden)), val, s.get("describe", ""),
                    maker, mpn, fp, lcsc])
with open(os.path.join(OUT, "AVO_BACK_V5_NO_MONTAR.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["Designator", "Value", "Footprint", "Reason"])
    for p in sorted(parts, key=lambda p: orden(p["ref"])):
        if montar(p):
            continue
        w.writerow([p["ref"], p["value"], p["footprint"],
                    "DNP (do not place)" if p.get("dnp") else "Wire/pad or test point, no component"])

# ------------------------------------------------------------------------------------------------ CPL
with open(os.path.join(OUT, "AVO_BACK_V5_CPL_generico.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["Designator", "Value", "Footprint", "Mid X (mm)", "Mid Y (mm)", "Rotation (deg, KiCad/IPC-7351)", "Layer"])
    for p in sorted(parts, key=lambda p: orden(p["ref"])):
        if not montar(p):
            continue
        if pos:
            if p["ref"] not in pos:
                continue
            x, y, rot, side = pos[p["ref"]]
        else:
            x, y, rot, side = p["x"], p["y"], p["rot"], "Top"
        w.writerow([p["ref"], p["value"], p["footprint"], "%.4f" % x, "%.4f" % y, "%g" % (rot % 360), side])

# ------------------------------------------------------------------------------------------------ plano de montaje
by_ref = {p["ref"]: p for p in D.PARTS}
with PdfPages(os.path.join(OUT, "AVO_BACK_V5_montaje.pdf")) as pdf:
    for titulo, filtro in (("Cara superior: piezas a montar", lambda p: montar(p)),
                           ("Cara superior: solo CI, conectores y polarizados", lambda p: montar(p) and p["ref"][0] in "UJDQFL")):
        fig, ax = plt.subplots(figsize=(11.69, 8.27))
        poly = [D.K(x, y) for x, y in D.outline_pts(5)]
        ax.add_patch(Polygon(poly, closed=True, fill=False, ec="k", lw=1.2))
        for pj in parts:
            p = by_ref.get(pj["ref"])
            if p is None:
                continue
            fp = D.fp_of(p)
            cx, cy = D.kpos(p)
            sel = filtro(pj)
            bb = D.courtyard_abs(p)
            ax.add_patch(Rectangle((bb[0], bb[1]), bb[2] - bb[0], bb[3] - bb[1], fill=False,
                                   ec="#404040" if sel else "#cccccc", lw=0.35 if sel else 0.2))
            for pd in fp.pads:
                if pd.num == "":
                    continue
                pp = pad_poly(pd, cx, cy, p["rot"])
                ax.add_patch(Polygon(pp, closed=True, fc=("#d9a441" if sel else "#eeeeee"),
                                     ec=("#8a6010" if sel else "#cccccc"), lw=0.15))
                if pd.num == "1" and sel and len(fp.pads) > 2 and pj["ref"][0] in "UJDQ":
                    mx = sum(q[0] for q in pp) / len(pp); my = sum(q[1] for q in pp) / len(pp)
                    ax.plot(mx, my, "o", ms=1.6, color="#c00000")
            if sel:
                ax.text(cx, cy, pj["ref"], fontsize=4.2, ha="center", va="center", color="#000080",
                        fontweight="bold")
        ax.set_aspect("equal")
        ax.set_xlim(72, 128); ax.set_ylim(128, 72)
        ax.set_title("AVO BACK V5 casco · PCB REV B · %s\n(vista desde arriba; punto rojo = pin 1; DNP y pads de cable en gris)" % titulo,
                     fontsize=9)
        ax.set_xlabel("mm (origen KiCad)")
        fig.tight_layout()
        pdf.savefig(fig)
        plt.close(fig)

with open(os.path.join(OUT, "LEEME_FABRICANTE.txt"), "w", encoding="utf-8") as f:
    f.write("""AVO BACK V5 (casco) - PCB REV B - paquete generico de fabricacion y montaje
==========================================================================
PCB:   4 capas, FR-4 TG155+, 1,6 mm, 51 x 51 mm (esquinas R3), cobre exterior 1 oz, interior 0,5 oz,
       mascara verde, serigrafia blanca en ambas caras, acabado ENIG (recomendado por el modulo
       ESP32-S3-WROOM-1U y el LGA del ZED-F9P), via 0,5/0,3 mm (anillo 0,1), pista minima 0,20 mm,
       separacion minima 0,15 mm. Tramo RF de antena (U.FL -> ZED-F9P) de 0,36 mm, calculado como 50 ohm
       para el apilado JLC04161H-7628; con otro apilado, pedir al fabricante que lo ajuste a 50 ohm.
Montaje: una sola cara (TOP). Las coordenadas del CPL son las de KiCad 9 (origen de la placa en KiCad),
       con el giro NATIVO de KiCad (IPC-7351, pin 1 arriba-izquierda a 0 grados). NO incluyen las
       correcciones de rotacion de JLCPCB: el fabricante debe revisar la rotacion con su propio visor.
       Piezas de referencia: la columna LCSC es solo orientativa; puede sustituirse cualquier pasivo por uno
       equivalente (mismo valor, encapsulado, tension y dielectrico X5R/X7R).
Piezas criticas (no sustituir): U1 ZED-F9P-04B (u-blox, LGA, sensible a la humedad: respetar su nivel MSL y hornear si procede),
       U4 ESP32-S3-WROOM-1U-N16R8, U2 BQ24072RGTR (QFN con pad central), U11 TPS61023DRLR, U12 MAX17048G+T10,
       U13 LSM6DSV16XTR, J3 Hirose DM3AT-SF-PEJM5, J5 Hirose U.FL-R-SMT-1(10), D10-D17 SK6812SIDE-A
       (hay 7 LED: D10, D11, D12, D13, D15, D16, D17; D14 no existe).
No montar: ver AVO_BACK_V5_NO_MONTAR.csv (DNP, pads de cable P1-P5/J7 y puntos de prueba).
Inspeccion: rayos X recomendados para U1 (LGA), U2 (QFN) y U13 (LGA-14).
Bateria, antena y cable pogo: los suelda el cliente; no forman parte del montaje.
""")

print("BOM generica: %d lineas, %d piezas · CPL desde %s" % (len(grupos), sum(len(v) for v in grupos.values()), fuente_pos))
if faltan_mpn:
    print("Sin MPN: " + ", ".join(faltan_mpn))
