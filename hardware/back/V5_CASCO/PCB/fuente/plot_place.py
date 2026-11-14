"""Vista de la colocación V5 (patios y contorno, vista desde la cara F) → ../out_local_colocacion_v5.png"""
import os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Circle
import avo_back_v5_pcb as D
HERE = os.path.dirname(os.path.abspath(__file__))
fig, ax = plt.subplots(figsize=(11, 11))
pts = D.outline_pts(3); pts.append(pts[0]); ax.plot([p[0] for p in pts], [p[1] for p in pts], "k-")
a = D.ANT; ax.add_patch(Rectangle((a[0] - a[2] / 2, a[1] - a[2] / 2), a[2], a[2], fc="#ffe9a8", ec="#e0a100", ls="--", alpha=.5))
ax.text(a[0], a[1] - 11.5, "antena GNSS (cara B)", ha="center", fontsize=8, color="#a07000")
for p in D.PARTS:
    if p["fp"] in D.CIRC:
        ax.add_patch(Circle(p["pos"], D.CIRC[p["fp"]], fc="none", ec="r")); ax.text(*p["pos"], p["ref"], fontsize=6, ha="center"); continue
    x0, y0, x1, y1 = D.courtyard_casing(p)
    big = D.fp_of(p).height > 1.5 or p["ref"].startswith(("U", "J"))
    ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fc="#cfe2ff" if big else "#eee", ec="b" if big else "gray", lw=.6))
    ax.text((x0 + x1) / 2, (y0 + y1) / 2, p["ref"], fontsize=7 if big else 4.5, ha="center", va="center")
ax.set_xlim(-27, 27); ax.set_ylim(-27, 27); ax.set_aspect("equal"); ax.grid(alpha=.2)
ax.set_title("AVO BACK V5 CASCO — colocación (vista desde la cara F de componentes)")
plt.savefig(os.path.join(HERE, "..", "out_local_colocacion_v5.png"), dpi=90, bbox_inches="tight")
