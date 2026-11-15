"""Vista de la colocación REV C (patios y contorno, vista desde la cara F) → ../out_local_colocacion_revd.png"""
import os
import matplotlib; matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Circle
import avo_girth_revd_pcb as D
HERE = os.path.dirname(os.path.abspath(__file__))
fig, ax = plt.subplots(figsize=(15, 10))
pts = D.outline_pts(3); pts.append(pts[0]); ax.plot([p[0] for p in pts], [p[1] for p in pts], "k-")
for p in D.PARTS:
    if p["fp"] in D.CIRC:
        ax.add_patch(Circle(p["pos"], D.CIRC[p["fp"]], fc="none", ec="r")); ax.text(*p["pos"], p["ref"], fontsize=6, ha="center"); continue
    x0, y0, x1, y1 = D.courtyard_casing(p)
    big = D.fp_of(p).height > 1.5 or p["ref"].startswith(("U", "J"))
    ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fc="#cfe2ff" if big else "#eee", ec="b" if big else "gray", lw=.6))
    ax.text((x0 + x1) / 2, (y0 + y1) / 2, p["ref"], fontsize=8 if big else 6, ha="center", va="center")
ax.set_xlim(-24, 24); ax.set_ylim(-16, 16); ax.set_aspect("equal"); ax.grid(alpha=.2)
ax.set_title("AVO GIRTH REV D (46 × 30) — colocación (vista desde la cara F de componentes)")
plt.savefig(os.path.join(HERE, "..", "out_local_colocacion_revd.png"), dpi=90, bbox_inches="tight")
