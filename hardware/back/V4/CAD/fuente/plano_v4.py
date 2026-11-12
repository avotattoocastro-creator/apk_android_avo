"""Plano de dimensiones de la V4 y comparativa visual con la Rev E.5 (matplotlib) → PNG + PDF"""
import json, sys, math
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon, Circle, Rectangle
from matplotlib.backends.backend_pdf import PdfPages
D = json.load(open("/home/claude/v4/analisis/perfiles.json"))
INF = json.load(open("/home/claude/v4/cad/salida/informe_modelo_v4.json"))
DER = INF["RE"]["DERIVADOS"]
OUT = sys.argv[1]
def draw_planta(ax, k, color, lw=1.6, alpha=1.0, label=None):
    first = True
    for pts in D[k]["planta"]:
        xs = [p[0] for p in pts]; ys = [p[1] for p in pts]
        ax.plot(xs, ys, color=color, lw=lw if len(pts) > 200 else 0.6, alpha=alpha, label=label if first else None); first = False
def draw_perfil(ax, k, color, alpha=1.0, label=None, keys=("tapa", "base", "soporte", "contraplaca", "antena")):
    first = True
    for part in keys:
        for pts in D[k]["perfil_" + part]:
            ax.plot([p[0] for p in pts], [p[2] for p in pts], color=color, lw=0.9, alpha=alpha, label=label if first else None); first = False
def dim(ax, a, b, off, txt, vertical=False, fs=9):
    if not vertical:
        y = off; ax.annotate("", xy=(a, y), xytext=(b, y), arrowprops=dict(arrowstyle="<->", lw=0.8))
        ax.text((a + b) / 2, y + 1.0, txt, ha="center", va="bottom", fontsize=fs)
    else:
        x = off; ax.annotate("", xy=(x, a), xytext=(x, b), arrowprops=dict(arrowstyle="<->", lw=0.8))
        ax.text(x + 1.0, (a + b) / 2, txt, ha="left", va="center", fontsize=fs, rotation=90)
# -------------------------------------------------- 1) comparativa
fig, axs = plt.subplots(2, 1, figsize=(16, 11), gridspec_kw=dict(height_ratios=[1.25, 1]))
ax = axs[0]
draw_planta(ax, "RevE5", "#b0b0b0", lw=2.2, label="Rev E.5 (actual)")
draw_planta(ax, "V4", "#1f5fbf", lw=2.2, label="AVO BACK V4")
a5 = D["RevE5"]["bbox"]["antena"]; a4 = D["V4"]["bbox"]["antena"]
ax.add_patch(Circle(((a5[0] + a5[1]) / 2, 0), 22.15, fill=False, ls="--", color="#b0b0b0"))
ax.add_patch(Circle(((a4[0] + a4[1]) / 2, 0), 22.15, fill=False, ls="--", color="#1f5fbf"))
dim(ax, 0, 166.214, 34, "Rev E.5: 166,2 mm"); dim(ax, 0, 118.167, -36, "V4: 118,2 mm (−48,0 mm, −28,9 %)")
dim(ax, -29.5, 29.5, -6, "59,0 (igual)", vertical=True)
ax.set_aspect("equal"); ax.set_xlim(-12, 178); ax.set_ylim(-42, 42); ax.legend(loc="upper right"); ax.grid(alpha=0.2)
ax.set_title("Planta (desde arriba; círculos: antena Q39 Ø44,3)")
ax = axs[1]
draw_perfil(ax, "RevE5", "#b0b0b0", label="Rev E.5")
draw_perfil(ax, "V4", "#1f5fbf", label="V4")
dim(ax, -11.143, 17.1, 172, "28,2 (igual)", vertical=True); dim(ax, 0, 17.1, -8, "17,1", vertical=True)
ax.set_aspect("equal"); ax.set_xlim(-12, 182); ax.set_ylim(-14, 60); ax.legend(loc="upper left"); ax.grid(alpha=0.2)
ax.set_title("Corte longitudinal Y = 0 (cápsula, soporte, contraplaca y antena): mismo grosor, 48 mm más corta")
fig.suptitle("AVO BACK V4 frente a la Rev E.5 — misma anchura y grosor, más corta", fontsize=14, weight="bold")
fig.tight_layout(); fig.savefig(OUT + "/AVO_BACK_V4_COMPARATIVA_REV_E5.png", dpi=110); plt.close(fig)
# -------------------------------------------------- 2) plano de dimensiones (A3 apaisado, 1:1 aproximado en pantalla)
pdf = PdfPages(OUT + "/AVO_BACK_V4_PLANO_DIMENSIONES.pdf")
fig, axs = plt.subplots(2, 1, figsize=(16.5, 11.7), gridspec_kw=dict(height_ratios=[1.3, 1]))
ax = axs[0]
draw_planta(ax, "V4", "k", lw=1.6)
sc = DER["TORNILLOS"]
for i, (x, y) in enumerate(sc):
    ax.add_patch(Circle((x, y), 2.95, fill=False, color="r", lw=0.8)); ax.text(x, y + (3.8 if y > 0 else -5.2), "S%d\n(%.1f; %.1f)" % (i + 1, x, y), fontsize=6.5, ha="center", color="r")
for (x, y) in INF["RE"]["MAGS"]:
    ax.add_patch(Circle((x, y), 2.575, fill=False, color="#7a00a0", lw=0.7))
hx, hy = INF["RE"]["HALL_C"]; ax.plot([hx], [hy], "s", color="#007a3d"); ax.text(hx + 1, hy - 2.5, "Hall (imanes del soporte debajo)", fontsize=7, color="#007a3d")
ox = DER["SALIDA_ANTENA_X"]; ax.plot([ox], [0], "+", ms=14, color="b"); ax.text(ox + 1.5, 1.5, "eje L / antena X %.2f" % ox, fontsize=8, color="b")
zx0, zx1 = DER["ZED_X"]; zy0, zy1 = DER["ZED_Y"]
ax.add_patch(Rectangle((zx0, zy0), zx1 - zx0, zy1 - zy0, fill=False, ls="--", color="#c06000")); ax.text(zx0 + 1, zy1 - 3, "URTK1.2 (Z 9,6–11,2) sobre la batería", fontsize=7, color="#c06000")
bx0, bx1 = DER["BAT_X"]; by = DER["BAT_Y"]
ax.add_patch(Rectangle((bx0, -by), bx1 - bx0, 2 * by, fill=False, ls=":", color="#a08000")); ax.text(bx0 + 1, -by + 1, "batería 654060 (Z 0,8–7,3)", fontsize=7, color="#a08000")
pc = json.load(open("/home/claude/v4/cad/salida/pcb_contorno_v4.json"))
def arcpts(a, m, b, n=24):
    ax_, ay = a; bx, by_ = m; cx, cy = b; d = 2 * (ax_ * (by_ - cy) + bx * (cy - ay) + cx * (ay - by_))
    ux = ((ax_**2 + ay**2) * (by_ - cy) + (bx**2 + by_**2) * (cy - ay) + (cx**2 + cy**2) * (ay - by_)) / d
    uy = ((ax_**2 + ay**2) * (cx - bx) + (bx**2 + by_**2) * (ax_ - cx) + (cx**2 + cy**2) * (bx - ax_)) / d
    r = math.hypot(ax_ - ux, ay - uy); t0 = math.atan2(ay - uy, ax_ - ux); tm = math.atan2(by_ - uy, bx - ux); t1 = math.atan2(cy - uy, cx - ux)
    nm = lambda t: (t - t0) % (2 * math.pi); sp = nm(t1) if nm(tm) < nm(t1) else -((t0 - t1) % (2 * math.pi))
    return [(ux + r * math.cos(t0 + sp * k / n), uy + r * math.sin(t0 + sp * k / n)) for k in range(n + 1)]
for w in pc["contorno"]:
    for s in w["segmentos"]:
        P = [s["a"], s["b"]] if s["t"] == "L" else arcpts(s["a"], s["m"], s["b"])
        ax.plot([p[0] for p in P], [p[1] for p in P], color="g", lw=1.0)
ax.text(96, -20.5, "PCB V4 (Z 2,5–3,5)\n%.0f mm²" % pc["area_mm2"], fontsize=7, color="g")
dim(ax, 0, 118.167, 33, "118,2"); dim(ax, -29.5, 29.5, -7, "59,0", vertical=True)
dim(ax, 0, ox, -34, "%.2f" % ox)
ax.set_aspect("equal"); ax.set_xlim(-12, 130); ax.set_ylim(-40, 40); ax.grid(alpha=0.2)
ax.set_title("Planta: tornillos S1–S8 (alojamiento Ø5,9), imanes Ø5 × 1 (morado), URTK1.2, batería, PCB y eje de la antena")
ax = axs[1]
draw_perfil(ax, "V4", "k")
for z, t in ((17.1, "techo 17,1"), (6.0, "unión base/tapa 6,0"), (0, "cara inferior 0"), (-4.5, "soporte −4,5"), (-11.143, "contraplaca −11,1"), (57.9, "punta antena 57,9")):
    ax.axhline(z, color="#999", lw=0.5, ls=":"); ax.text(-11, z + 0.4, t, fontsize=7)
dim(ax, -11.143, 17.1, 125, "28,2", vertical=True); dim(ax, 17.1, 57.9, 115, "40,8 (antena)", vertical=True)
ax.set_aspect("equal"); ax.set_xlim(-12, 135); ax.set_ylim(-14, 60); ax.grid(alpha=0.2)
ax.set_title("Corte longitudinal Y = 0")
fig.suptitle("AVO BACK V4 · plano de dimensiones (mm) · cotas del modelo B-Rep (CAD/fuente/avo_back_v4_freecad.py)", fontsize=13, weight="bold")
fig.tight_layout(); pdf.savefig(fig); fig.savefig(OUT + "/AVO_BACK_V4_PLANO_DIMENSIONES.png", dpi=100); plt.close(fig); pdf.close()
print("ok")
