"""Vista de la colocación V5 (patios y contorno, vista desde la cara F) → ../out_local_colocacion_v5.png"""
import os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Circle
import avo_back_v5_pcb as D
HERE = os.path.dirname(os.path.abspath(__file__))
fig, ax = plt.subplots(figsize=(11, 11))
pts = D.outline_pts(3); pts.append(pts[0]); ax.plot([p[0] for p in pts], [p[1] for p in pts], "k-")
c = D.urtk_xy(0, 0); hx, hy = D.URTK["ly"] / 2, D.URTK["lx"] / 2      # en la placa: X ↔ v, Y ↔ u
ax.add_patch(Rectangle((c[0] - hx, c[1] - hy), 2 * hx, 2 * hy, fc="none", ec="#2a8a2a", ls="--"))
ax.text(c[0], c[1] + hy - 1.5, "URTK1.2 (cara B)", ha="center", fontsize=8, color="#2a8a2a")
a = D.ANT; ac = D.urtk_xy(a[0], a[1])
ax.add_patch(Rectangle((ac[0] - a[2] / 2, ac[1] - a[2] / 2), a[2], a[2], fc="#ffe9a8", ec="#e0a100", ls="--", alpha=.4))
ax.text(ac[0], ac[1] - 11.5, "antena GNSS (sobre la URTK1.2)", ha="center", fontsize=8, color="#a07000")
for p in D.PARTS:
    if p["fp"] in D.CIRC:
        ax.add_patch(Circle(p["pos"], D.CIRC[p["fp"]], fc="none", ec="r")); ax.text(*p["pos"], p["ref"], fontsize=6, ha="center"); continue
    x0, y0, x1, y1 = D.courtyard_casing(p)
    big = D.fp_of(p).height > 1.5 or p["ref"].startswith(("U", "J"))
    ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fc="#cfe2ff" if big else "#eee", ec="b" if big else "gray", lw=.6))
    ax.text((x0 + x1) / 2, (y0 + y1) / 2, p["ref"], fontsize=7 if big else 4.5, ha="center", va="center")
ax.set_xlim(-29.5, 29.5); ax.set_ylim(-29.5, 29.5); ax.set_aspect("equal"); ax.grid(alpha=.2)
ax.set_title("AVO BACK V5 CASCO PROTOTIPO — colocación (vista desde la cara F de componentes)")
plt.savefig(os.path.join(HERE, "..", "out_local_colocacion_v5.png"), dpi=90, bbox_inches="tight")
