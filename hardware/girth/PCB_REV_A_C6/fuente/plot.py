"""Vista rápida (PNG) de la colocación y el ruteado — herramienta de diseño."""
import sys

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt                     # noqa: E402
from matplotlib.patches import Polygon, Rectangle   # noqa: E402

import avo_girth_pcb as D                           # noqa: E402
from fplib import pad_poly                          # noqa: E402

COL = {"F.Cu": "#d04040", "B.Cu": "#3060d0", "In2.Cu": "#c0a000", "In1.Cu": "#20a020"}


def draw(path, tracks=(), vias=(), title="", zoom=None, scale=1.0):
    fig, ax = plt.subplots(figsize=(18 * scale, 12 * scale), dpi=110)
    poly = [D.K(x, y) for x, y in D.outline_pts(5)]
    ax.add_patch(Polygon(poly, closed=True, fill=False, ec="k", lw=1.2))
    x0, y0, x1, y1 = D.ANT_KEEPOUT
    a, b = D.K(x0, y1), D.K(x1, y0)
    ax.add_patch(Rectangle((a[0], a[1]), b[0] - a[0], b[1] - a[1], fill=True, fc="#e8f4ff", ec="#88aaff", lw=0.5))
    for p in D.PARTS:
        fp = D.fp_of(p)
        cx, cy = D.kpos(p)
        bb = D.courtyard_abs(p)
        ax.add_patch(Rectangle((bb[0], bb[1]), bb[2] - bb[0], bb[3] - bb[1], fill=False,
                               ec="#999999" if not p["dnp"] else "#cc88cc", lw=0.4, ls="--"))
        for pd in fp.pads:
            if pd.num == "":
                continue
            pp = pad_poly(pd, cx, cy, p["rot"])
            ax.add_patch(Polygon(pp, closed=True, fc="#e0b060", ec="#a07020", lw=0.2, alpha=0.8))
        ax.text(cx, cy, p["ref"], fontsize=5.5 * scale, ha="center", va="center", color="#202020")
    for (net, layer, a, b, w) in tracks:
        ax.plot([a[0], b[0]], [a[1], b[1]], color=COL.get(layer, "m"), lw=max(0.6, w * 9 * scale),
                solid_capstyle="round", alpha=0.75)
    for (net, p) in vias:
        ax.add_patch(plt.Circle(p, 0.25, color="#202020", alpha=0.8))
    ax.set_aspect("equal")
    if zoom:
        ax.set_xlim(zoom[0], zoom[2]); ax.set_ylim(zoom[3], zoom[1])
    else:
        ax.set_xlim(66, 134); ax.set_ylim(123, 77)
    ax.set_title(title)
    ax.grid(True, lw=0.2)
    fig.tight_layout()
    fig.savefig(path)
    plt.close(fig)


if __name__ == "__main__":
    draw(sys.argv[1] if len(sys.argv) > 1 else "colocacion.png", title="colocación")
