"""Placa de masa de la antena GNSS del casco V5 PROTOTIPO (PROTO A, 18/11/2026).

Va entre la URTK1.2 y la antena plana (Taoglas AHP2258, probada por el fabricante sobre 70 × 70 mm): sin ella la
antena solo vería la URTK1.2 (43 × 43, con componentes). PCB de 2 capas, 0,8 mm, cobre macizo en las dos caras unido
por vías cada ≈ 4 mm, máscara en las dos caras (la de abajo apoya en el blindaje del ZED, con kapton además).
Recortes: esquinas (postes de la tapa), tiras de pines de la URTK1.2, portapilas J6, USB-C J1, conector J3 y el U.FL
J4 con la clavija del cable. Pad de masa Ø1,8 junto al pin GND de la tira de 9: un hilo corto a ese pin.

Marco: VISTA DESDE ARRIBA (cielo), origen en el centro de la cápsula = marco del CAD (X del CAD = −X de la PCB).
Las posiciones de J1/J3/J4/J6 salen del plano del anuncio de la URTK1.2: VERIFICAR CON LA PLACA REAL.

Salidas (PCB/PLACA_MASA/): Gerber RS-274X (GTL, GBL, GTS, GBS, GTO, GM1), taladros Excellon, vista PNG, ZIP para
JLCPCB y placa_masa.json (geometría para el CAD). Uso: python3 fuente/placa_masa.py (desde PCB/)."""
import json
import math
import os
import sys
import zipfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import avo_back_v5_pcb as D   # noqa: E402

OUT = "PLACA_MASA"                    # fuera de out/: el CI de la PCB reescribe out/
os.makedirs(OUT, exist_ok=True)
NAME = "AVO_CASCO_V5P_PLACA_MASA"

SIDE = 52.0                 # lado de la placa (interior de la cápsula 56,6)
POST = (D.HOLE_XY, 3.0 + 0.5)   # postes de la tapa: centro (±24,5) y radio del recorte (Ø6 + 0,5)
EDGE_CU = 0.4               # retirada del cobre respecto al contorno y a los recortes
MARGIN = 1.0                # holgura alrededor de los componentes de la URTK1.2 (cotas estimadas)


def u2sky(u, v):
    """marco U de la URTK1.2 → vista desde arriba (marco del CAD)"""
    x, y = D.urtk_xy(u, v)          # vista desde F
    return (-x, y)


# recortes en el marco U de la URTK1.2: (tipo, ...) con cotas del plano del anuncio
R_U = [
    ("circ", -10.93, 13.04, 6.0 + MARGIN),                         # J6 portapilas (Ø hasta 12 mm)
    ("rect", -23.9, -13.81, -15.56, -4.27),                        # J1 USB-C (asoma por el canto)
    ("rect", -22.3, 3.78, -17.1, 15.82),                           # J3 GH de 6
    ("circ", 18.95, 6.87, 3.0 + MARGIN),                           # J4 U.FL + clavija + salida del cable
]
for v in (URTK_F := D.URTK["fila"], -URTK_F):                      # tiras de pines (puntas cortadas a ras)
    n = 9 if v > 0 else 10
    R_U.append(("rect", D.URTK["u0"] - 1.5, v - 1.5, D.URTK["u0"] + (n - 1) * D.URTK["pitch"] + 1.5, v + 1.5))

ARC = 24


def circle_pts(cx, cy, r, n=ARC):
    return [(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n)) for k in range(n)]


def rect_pts(x0, y0, x1, y1):
    return [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]


def cutouts_sky(grow=0.0):
    polys = []
    for c in R_U:
        if c[0] == "circ":
            x, y = u2sky(c[1], c[2])
            polys.append(circle_pts(x, y, c[3] + grow))
        else:
            pts = [u2sky(c[1], c[2]), u2sky(c[3], c[4])]
            xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
            polys.append(rect_pts(min(xs) - MARGIN - grow, min(ys) - MARGIN - grow, max(xs) + MARGIN + grow,
                                  max(ys) + MARGIN + grow))
    return polys


def outline(inset=0.0):
    """cuadrado de SIDE con las 4 esquinas mordidas por los postes (arco cóncavo de radio POST[1]), antihorario"""
    h = SIDE / 2 - inset
    c, r = POST[0], POST[1] + inset
    dy = math.sqrt(max(r * r - (h - c) ** 2, 0))
    e = c - dy                                       # donde el círculo del poste corta el canto
    corners = [((1, 1), (h, e), (e, h)), ((-1, 1), (-e, h), (-h, e)),
               ((-1, -1), (-h, -e), (-e, -h)), ((1, -1), (e, -h), (h, -e))]
    pts = []
    for (sx, sy), p_in, p_out in corners:
        cx, cy = c * sx, c * sy
        t0 = math.atan2(p_in[1] - cy, p_in[0] - cx); t1 = math.atan2(p_out[1] - cy, p_out[0] - cx)
        best = None
        for span in ((t1 - t0) % (2 * math.pi), -((t0 - t1) % (2 * math.pi))):
            tm = t0 + span / 2
            mx, my = cx + r * math.cos(tm), cy + r * math.sin(tm)
            if abs(mx) < h and abs(my) < h:
                best = span
        pts += [(cx + r * math.cos(t0 + best * k / 12), cy + r * math.sin(t0 + best * k / 12)) for k in range(13)]
    return pts


def point_in(poly, x, y):
    c = False
    for k in range(len(poly)):
        xa, ya = poly[k]; xb, yb = poly[(k + 1) % len(poly)]
        if (ya > y) != (yb > y) and x < xa + (y - ya) * (xb - xa) / (yb - ya):
            c = not c
    return c


def dist_poly(poly, x, y):
    best = 1e9
    for k in range(len(poly)):
        xa, ya = poly[k]; xb, yb = poly[(k + 1) % len(poly)]
        dx, dy = xb - xa, yb - ya
        L2 = dx * dx + dy * dy
        t = 0 if L2 == 0 else max(0, min(1, ((x - xa) * dx + (y - ya) * dy) / L2))
        best = min(best, math.hypot(x - xa - t * dx, y - ya - t * dy))
    return best


# --------------------------------------------------------------------------------------------- geometría
OUTL = outline()
CU = outline(EDGE_CU)
CUTS = cutouts_sky()
CUTS_CU = cutouts_sky(EDGE_CU)
GND_PAD = (u2sky(D.URTK["u0"], D.URTK["fila"])[0] + 0.0, u2sky(D.URTK["u0"] - 4.0, D.URTK["fila"])[1])
# vías de unión de las dos caras (Ø0,6 / 0,3) en rejilla de 4 mm, lejos de bordes y recortes
VIAS = []
for i in range(-6, 7):
    for j in range(-6, 7):
        x, y = i * 4.0, j * 4.0
        if not point_in(CU, x, y) or dist_poly(CU, x, y) < 0.8:
            continue
        if any(point_in(c, x, y) or dist_poly(c, x, y) < 0.8 for c in CUTS_CU):
            continue
        if math.hypot(x - GND_PAD[0], y - GND_PAD[1]) < 2.5:
            continue
        VIAS.append((x, y))


# --------------------------------------------------------------------------------------------- Gerber
def fmt(v):
    return "%d" % round(v * 1e6)


def region(pts):
    s = ["G36*", "X%sY%sD02*" % (fmt(pts[0][0]), fmt(pts[0][1]))]
    s += ["X%sY%sD01*" % (fmt(x), fmt(y)) for x, y in pts[1:]] + ["X%sY%sD01*" % (fmt(pts[0][0]), fmt(pts[0][1])), "G37*"]
    return s


def header(func, polarity="Positive"):
    return ["%FSLAX46Y46*%", "%MOMM*%", "%%TF.GenerationSoftware,AVO,placa_masa.py,1*%%",
            "%%TF.FileFunction,%s*%%" % func, "%%TF.FilePolarity,%s*%%" % polarity, "G01*", "%LPD*%"]


def write(name, lines):
    open(os.path.join(OUT, name), "w").write("\n".join(lines + ["M02*"]) + "\n")


def copper(func):
    L = header(func) + ["%ADD10C,0.600000*%", "%ADD11C,1.800000*%"] + region(CU) + ["%LPC*%"]
    for c in CUTS_CU:
        L += region(c)
    L += ["%LPD*%", "D10*"] + ["X%sY%sD03*" % (fmt(x), fmt(y)) for x, y in VIAS]
    L += ["D11*", "X%sY%sD03*" % (fmt(GND_PAD[0]), fmt(GND_PAD[1]))]
    return L


def mask(func):
    # máscara en todo; solo se abre el pad de masa (las vías quedan tapadas)
    return header(func) + ["%ADD12C,2.000000*%", "D12*", "X%sY%sD03*" % (fmt(GND_PAD[0]), fmt(GND_PAD[1]))]


def outline_g():
    L = header("Profile,NP") + ["%ADD13C,0.100000*%", "D13*"]
    for poly in [OUTL] + CUTS:
        L.append("X%sY%sD02*" % (fmt(poly[0][0]), fmt(poly[0][1])))
        L += ["X%sY%sD01*" % (fmt(x), fmt(y)) for x, y in poly[1:]]
        L.append("X%sY%sD01*" % (fmt(poly[0][0]), fmt(poly[0][1])))
    return L


def silk():
    # texto mínimo con trazos: «GND» junto al pad y una flecha hacia la antena (sin fuentes externas)
    L = header("Legend,Top") + ["%ADD14C,0.150000*%", "D14*"]
    x, y = GND_PAD[0] + 2.0, GND_PAD[1]
    for (x0, y0), (x1, y1) in (((x, y + 0.6), (x + 0.9, y + 0.6)), ((x, y + 0.6), (x, y - 0.6)), ((x, y - 0.6), (x + 0.9, y - 0.6)),
                               ((x + 0.9, y - 0.6), (x + 0.9, y))):
        L += ["X%sY%sD02*" % (fmt(x0), fmt(y0)), "X%sY%sD01*" % (fmt(x1), fmt(y1))]
    ax, ay = D.urtk_xy(*D.ANT[:2]); ax = -ax
    a = D.ANT[2] / 2
    for (x0, y0), (x1, y1) in ((((ax - a, ay - a), (ax + a, ay - a))), (((ax + a, ay - a), (ax + a, ay + a))),
                               (((ax + a, ay + a), (ax - a, ay + a))), (((ax - a, ay + a), (ax - a, ay - a)))):
        L += ["X%sY%sD02*" % (fmt(x0), fmt(y0)), "X%sY%sD01*" % (fmt(x1), fmt(y1))]
    return L


write(NAME + "-F_Cu.gtl", copper("Copper,L1,Top"))
write(NAME + "-B_Cu.gbl", copper("Copper,L2,Bot"))
write(NAME + "-F_Mask.gts", mask("Soldermask,Top"))
write(NAME + "-B_Mask.gbs", mask("Soldermask,Bot"))
write(NAME + "-F_Silkscreen.gto", silk())
write(NAME + "-Edge_Cuts.gm1", outline_g())
drl = ["M48", "METRIC,TZ", "T1C0.300", "T2C1.000", "%", "G90", "G05", "T1"]
drl += ["X%.3fY%.3f" % (x, y) for x, y in VIAS] + ["T2", "X%.3fY%.3f" % GND_PAD, "M30"]
open(os.path.join(OUT, NAME + "-PTH.drl"), "w").write("\n".join(drl) + "\n")

with zipfile.ZipFile(os.path.join(OUT, NAME + "_GERBER_JLCPCB.zip"), "w", zipfile.ZIP_DEFLATED) as z:
    for f in sorted(os.listdir(OUT)):
        if f.endswith((".gtl", ".gbl", ".gts", ".gbs", ".gto", ".gm1", ".drl")):
            z.write(os.path.join(OUT, f), f)

geo = dict(lado=SIDE, espesor=0.8, contorno=[list(map(lambda v: round(v, 3), p)) for p in OUTL],
           recortes=[[list(map(lambda v: round(v, 3), p)) for p in c] for c in CUTS], pad_gnd=list(GND_PAD),
           vias=len(VIAS), marco="vista desde arriba (marco del CAD), mm", pedido="JLCPCB 2 capas 0,8 mm, 52 × 52, "
           "máscara en las dos caras, sin montaje")
json.dump(geo, open(os.path.join(OUT, "placa_masa.json"), "w"), indent=1, ensure_ascii=False)

# vista rápida
import matplotlib                                   # noqa: E402
matplotlib.use("Agg")
import matplotlib.pyplot as plt                     # noqa: E402
from matplotlib.patches import Polygon              # noqa: E402
fig, ax = plt.subplots(figsize=(7, 7))
ax.add_patch(Polygon(OUTL, closed=True, fc="#c88a3a", ec="k"))
for c in CUTS:
    ax.add_patch(Polygon(c, closed=True, fc="white", ec="k"))
ax.plot([v[0] for v in VIAS], [v[1] for v in VIAS], "k.", ms=2)
ax.plot(*GND_PAD, "go", ms=7)
ux, uy = D.urtk_xy(0, 0)
hx, hy = D.URTK["ly"] / 2, D.URTK["lx"] / 2
ax.add_patch(Polygon([(-ux - hx, uy - hy), (-ux + hx, uy - hy), (-ux + hx, uy + hy), (-ux - hx, uy + hy)], closed=True,
                     fill=False, ec="#2a8a2a", ls="--"))
ax.set_xlim(-30, 30); ax.set_ylim(-30, 30); ax.set_aspect("equal"); ax.grid(alpha=.2)
ax.set_title("Placa de masa 52 × 52 × 0,8 (vista desde arriba) · verde: URTK1.2 · punto: pad GND")
plt.savefig(os.path.join(OUT, NAME + "_vista.png"), dpi=90, bbox_inches="tight")
print("placa de masa: %d vías, %d recortes → %s" % (len(VIAS), len(CUTS), OUT))
