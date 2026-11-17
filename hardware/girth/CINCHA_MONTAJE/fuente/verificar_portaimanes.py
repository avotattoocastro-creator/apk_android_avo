"""REV 6.5 · comprobación del portaimanes por vóxeles (lados +X y −X).

Muestrea el volumen del portaimanes y de los 2 imanes de la pared, y mide:
- interferencia con la base (debe ser 0: entra con 0,1 mm de holgura por lado y se pega);
- interferencia imanes ↔ portaimanes (0);
- holguras y paredes que quedan, y que el imán queda a la misma distancia del balancín que en la REV 6.4.
Uso: python3 verificar_portaimanes.py  → out/verificacion_portaimanes.json
"""
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import verificar_cierre as V  # noqa: E402  (envuelve A.layered para guardar las capas)

M = V.M
RES = 0.05


def puntos_portaiman(sg):
    G = M.portaiman_geo()
    xs = np.arange(G["xc0"] + RES / 2, G["xc1"], RES)
    ys = np.arange(G["yc"] - G["hy_c"] + RES / 2, G["yc"] + G["hy_c"], RES)
    zs = np.arange(RES / 2, G["zc1"], RES)
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    P = np.c_[X.ravel(), Y.ravel(), Z.ravel()]
    dy = np.abs(P[:, 1] - G["yc"])
    keep = (P[:, 0] - G["xc0"]) + (G["hy_c"] - dy) >= G["key"]                  # chaflanes de la llave
    cuna = (P[:, 0] > G["xs0"]) & (dy < G["hy_s"]) & (P[:, 2] > G["zs0"]) & (P[:, 2] < G["zs1"])
    P = P[keep & ~cuna]
    P[:, 0] *= sg
    return P


def puntos_imanes(sg):
    b = M.BAL
    K = M.bal_x()
    x2 = K["xb"] - b["skin_w"] - 0.02
    xs = np.arange(x2 - 2.0 + RES / 2, x2, RES)
    ys = np.arange(-2.5, 2.5, RES) + K["yc"]
    zs = np.arange(-2.5, 2.5, RES) + b["mag_c"]
    X, Y, Z = np.meshgrid(xs, ys, zs, indexing="ij")
    P = np.c_[X.ravel(), Y.ravel(), Z.ravel()]
    P = P[(P[:, 1] - K["yc"]) ** 2 + (P[:, 2] - b["mag_c"]) ** 2 < 2.5 ** 2]
    P[:, 0] *= sg
    return P


def main():
    M.pieza_base()
    base = V.Capas(V.CAPT["AVO_CINCHA_R6_9_base_aro_luz"])
    G = M.portaiman_geo()
    vox = RES ** 3
    rep = {"rejilla_mm": RES}
    for sg in (1, -1):
        tag = "+X" if sg > 0 else "-X"
        Pp, Pm = puntos_portaiman(sg), puntos_imanes(sg)
        r = {"portaiman_en_base_mm3": round(float(base.inside(Pp).sum() * vox), 4),
             "imanes_en_base_mm3": round(float(base.inside(Pm).sum() * vox), 4)}
        # imanes dentro del macizo del portaimanes: con la misma rejilla, punto a punto
        Pq = Pm.copy(); Pq[:, 0] *= sg
        dy = np.abs(Pq[:, 1] - G["yc"])
        en_cuna = (Pq[:, 0] > G["xs0"]) & (dy < G["hy_s"]) & (Pq[:, 2] > G["zs0"]) & (Pq[:, 2] < G["zs1"])
        en_bloque = (Pq[:, 0] > G["xc0"]) & (Pq[:, 0] < G["xc1"]) & (dy < G["hy_c"]) & (Pq[:, 2] < G["zc1"])
        r["imanes_en_portaiman_mm3"] = round(float((en_bloque & ~en_cuna).sum() * vox), 4)
        rep[tag] = r
    c = G["c"]
    rep["cotas_mm"] = {
        "portaiman_XxYxZ": [round(G["xc1"] - G["xc0"], 2), round(2 * G["hy_c"], 2), round(G["zc1"], 2)],
        "abertura_XxYxZ": [round(G["xm1"] - G["xc0"] + c, 2), round(2 * (G["hy_c"] + c), 2), round(G["zc1"] + c, 2)],
        "cuna_XxYxZ": [round(G["xc1"] - G["xs0"], 2), round(2 * G["hy_s"], 2), round(G["zs1"] - G["zs0"], 2)],
        "holgura_por_lado": c,
        "pared_portaiman": M.BAL["pi_wall"], "techo_portaiman": M.BAL["pi_roof"],
        "pared_abertura_a_interior": round(G["xc0"] - c - M.CAP["I"]["x1"], 2),
        "piel_iman_a_hueco_balancin": M.BAL["skin_w"],
        "llave_chaflan": G["key"],
        "techo_abertura_z": round(G["zc1"] + c, 2), "insertos_M2_desde_z": round(M.ZT0 - 5.0, 2),
    }
    out = os.path.normpath(os.path.join(HERE, "..", "out", "verificacion_portaimanes.json"))
    json.dump(rep, open(out, "w"), indent=1, ensure_ascii=False)
    print(json.dumps(rep, indent=1, ensure_ascii=False))
    return rep


if __name__ == "__main__":
    main()
