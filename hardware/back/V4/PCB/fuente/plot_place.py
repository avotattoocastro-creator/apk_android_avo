"""Vista de la colocación (patios, zonas de la carcasa, contorno) → ../out_local_colocacion_v4.png"""
import os, sys, math
import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, Circle, Polygon
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import avo_back_v4_pcb as D
fig, ax = plt.subplots(figsize=(16, 14))
ax.add_patch(Polygon(D.outline_pts(3), fill=False, lw=1.5, color="g"))
z = D.ZONAS; b = z["bajo_J2_L"]; ax.add_patch(Rectangle((b["x0"], b["y"][0]), b["x1"] - b["x0"], b["y"][1] - b["y"][0], color="r", alpha=0.12))
t = z["topes_L"]; ax.add_patch(Rectangle((t["x0"], t["y"][0]), t["x1"] - t["x0"], t["y"][1] - t["y"][0], color="orange", alpha=0.12))
ax.axvspan(60, z["bajo_URTK"]["x1"], color="b", alpha=0.06)
col = {"Contactos": "tab:purple", "Cargador": "tab:orange", "USB": "tab:cyan", "ESP32-S3": "tab:blue", "microSD": "tab:green", "ZED": "tab:red",
       "3V3": "tab:brown", "Batería": "gold", "Soporte": "k", "Pruebas": "gray", "Mecánica": "m"}
for p in D.PARTS:
    if p["fp"] in ("PAD_LID", "RING"):
        ax.add_patch(Circle(p["pos"], 2.5 if p["fp"] == "PAD_LID" else 4.6, color="m", alpha=0.15)); ax.text(*p["pos"], p["ref"], fontsize=7, ha="center"); continue
    x0, y0, x1, y1 = D.courtyard_casing(p)
    ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fill=True, alpha=0.35, color=col.get(p["block"], "gray"), lw=0.5))
    ax.text((x0 + x1) / 2, (y0 + y1) / 2, p["ref"], fontsize=6 if (x1 - x0) < 3 else 9, ha="center", va="center")
ax.set_xlim(64, 114); ax.set_ylim(-25, 25); ax.set_aspect("equal"); ax.grid(True, alpha=0.25)
ax.set_title("AVO BACK V4 — colocación (coordenadas de la carcasa, vista desde la tapa)")
plt.savefig(os.path.join(HERE, "..", "out_local_colocacion_v4.png"), dpi=75, bbox_inches="tight")
