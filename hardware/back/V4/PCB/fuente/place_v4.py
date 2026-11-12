"""Colocación de la placa AVO BACK V4.

Las piezas grandes y las que fija la mecánica (módulo, conectores, microSD, contactos del fondo, pivotes, pisadores, anillos) tienen
posición a mano (FIJAS). El resto se coloca con un algoritmo voraz: cada pieza va al hueco libre más cercano a su
objetivo (el pin del integrado al que se conecta o el ancla del bloque), dentro del contorno, sin solapar patios
(+0,1 mm) y respetando la altura máxima de cada zona de la carcasa (bajo la URTK1.2, bajo J2/L, topes de la L).
Escribe colocacion_v4.json y ../pcb_mecanica.json. Uso: python3 place_v4.py
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
POSF = os.path.join(HERE, "colocacion_v4.json")

FIJAS = {
    # módulo y conectores
    "U4": (87.9, 14.0, 0), "J4": (75.2, 12.2, 0), "J2": (73.7, -10.0, 270), "J3": (88.57, -13.85, 90),
    "J1": (107.0, 0.0, 90),
    # REV B: contactos del fondo. SYS y BAT en la cola, donde estaban el reed / el Hall (paso 5,8 mm); GND aparte, en el
    # hueco que deja el Qi, para que BAT y GND no queden juntos (sudor, objetos metálicos)
    "P1": (101.0, -8.6, 0), "P2": (106.8, -8.6, 0), "P3": (80.0, 0.0, 0),
    # mecánica
    "H1": (67.6, -13.8, 0), "H2": (99.0, -12.6, 0), "MP1": (98.0, -3.5, 0), "MP2": (98.4, 13.2, 0),
    "MR1": (67.8, -20.406, 0), "MR2": (67.8, 18.075, 0),
}
# anclas de los bloques (integrados): objetivo de la búsqueda
ANCLAS = {
    "U2": (89.5, -0.5), "U3": (73.4, -15.6), "U7": (68.3, 9.5), "U6": (102.5, 8.6),
    "Q3": (94.5, -4.5), "F1": (70.6, -4.6), "Q4": (82.0, -4.0), "D1": (97.0, 16.0),
}
ORDEN_IC = ["U2", "U3", "U7", "U6", "Q3", "F1", "Q4", "D1"]
# condensadores de desacoplo → integrado al que sirven (se colocan junto a su pin, no en el centro de la red)
DECAP = {"C21": ("U3", "1"), "C22": ("U3", "5"), "C60": ("U7", "1"), "C61": ("U7", "5"), "C62": ("J4", "1"),
         "C24": ("U4", "3"), "C25": ("U4", "3"), "C26": ("U4", "3"), "C18": ("U2", "13"), "C19": ("U2", "10"),
         "C20": ("U2", "2"), "C35": ("U2", "11"), "C28": ("J1", "A4"), "C40": ("Q4", "3"),
         "C41": ("J3", "4"), "TP9": ("J4", "1"), "TP6": ("U3", "5"), "TP8": ("U3", "1"),
         "TP7": ("Q3", "2"), "R60": ("U7", "3"), "R40": ("Q4", "1"), "D2": ("P1", "1"), "D3": ("P2", "1")}
GAP = 0.12            # separación mínima entre patios
STEP = 0.2


def main():
    # posiciones iniciales: fijas + anclas (el generador lee el JSON al importarse)
    base = {k: list(v) for k, v in FIJAS.items()}
    json.dump(base, open(POSF, "w"), indent=1)
    import importlib
    import avo_back_v4_pcb as D
    importlib.reload(D)
    from fplib import pad_center, rot
    poly = [D.K(x, y) for x, y in D.outline_pts(3)]
    placed = {}

    import numpy as np
    from matplotlib.path import Path
    from scipy import ndimage
    G = 0.1; X0, X1, Y0, Y1 = 60.0, 120.0, -30.0, 30.0
    W, H = int((X1 - X0) / G), int((Y1 - Y0) / G)
    xs = X0 + (np.arange(W) + 0.5) * G; ys = Y0 + (np.arange(H) + 0.5) * G
    XX, YY = np.meshgrid(xs, ys)
    inside = Path([(x, 100 - y) for x, y in poly]).contains_points(np.c_[XX.ravel(), YY.ravel()]).reshape(H, W)
    inside = ndimage.distance_transform_edt(inside) * G >= 0.45
    zmax = np.vectorize(lambda x, y: D.zone_limit(x, y))(XX, YY)
    occ = np.zeros((H, W), bool)

    def bbox(p, pos, r):
        fp = D.fp_of(p); x0, y0, x1, y1 = fp.courtyard(); cx, cy = D.K(*pos)
        pts = [rot(x, y, r) for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1))]
        kx = [cx + u for u, _ in pts]; ky = [cy + v for _, v in pts]
        return min(kx), min(ky), max(kx), max(ky)

    def cells(b, grow=0.0):
        """bbox KiCad → índices (casing Y = 100 − y)"""
        cx0, cx1 = b[0] - grow, b[2] + grow; cy0, cy1 = 100 - b[3] - grow, 100 - b[1] + grow
        i0 = max(0, int(math.floor((cy0 - Y0) / G))); i1 = min(H, int(math.ceil((cy1 - Y0) / G)))
        j0 = max(0, int(math.floor((cx0 - X0) / G))); j1 = min(W, int(math.ceil((cx1 - X0) / G)))
        return i0, i1, j0, j1

    def mark(p):
        b = bbox(p, p["pos"], p["rot"])
        if p["fp"] in ("PAD_LID", "RING", "CONTACT_M2"):
            r = {"PAD_LID": 2.5, "RING": 4.6, "CONTACT_M2": 2.9 + GAP / 2}[p["fp"]]
            occ[(XX - p["pos"][0]) ** 2 + (YY - p["pos"][1]) ** 2 < r * r] = True
        else:
            i0, i1, j0, j1 = cells(b, GAP / 2)
            occ[i0:i1, j0:j1] = True

    def ok(p, pos, r):
        b = bbox(p, pos, r)
        i0, i1, j0, j1 = cells(b, GAP / 2)
        i0b, i1b, j0b, j1b = cells(b)
        if i1 <= i0 or j1 <= j0 or i1b <= i0b or j1b <= j0b:
            return False
        if not inside[i0b:i1b, j0b:j1b].all():
            return False
        if occ[i0:i1, j0:j1].any():
            return False
        h = D.fp_of(p).height
        if h > 0 and zmax[i0b:i1b, j0b:j1b].min() < h:
            return False
        return True

    def place(p, target, rots=(0, 90, 180, 270)):
        tx, ty = target
        best = None
        for ring_ in range(0, 300):
            rad = ring_ * STEP
            n = max(1, int(2 * math.pi * rad / STEP)) if rad > 0 else 1
            for k in range(n):
                a = 2 * math.pi * k / n
                pos = (round(tx + rad * math.cos(a), 2), round(ty + rad * math.sin(a), 2))
                for r in rots:
                    if ok(p, pos, r):
                        best = (pos, r); break
                if best:
                    break
            if best:
                break
        if not best:
            raise SystemExit("sin hueco para %s cerca de %s" % (p["ref"], target))
        p["pos"], p["rot"] = best
        placed[p["ref"]] = (bbox(p, p["pos"], p["rot"]), p)
        mark(p)
        return best

    byref = {p["ref"]: p for p in D.PARTS}
    for ref, (x, y, r) in FIJAS.items():
        p = byref[ref]; p["pos"], p["rot"] = (x, y), r
        placed[ref] = (bbox(p, p["pos"], r), p); mark(p)
    for nm, x0, y0, x1, y1 in D.KEEPOUT_RECTS:
        occ[(XX >= x0) & (XX <= x1) & (YY >= y0) & (YY <= y1)] = True
    for ref in ORDEN_IC:
        place(byref[ref], ANCLAS[ref], (0, 90))

    BIG = {D.GND, D.V3, D.VSYS, D.VBAT, D.VBUS, D.VZED, D.VSD}

    def target_of(p):
        if p["ref"] in DECAP:
            ic, num = DECAP[p["ref"]]
            q = byref[ic]
            pd = next(pd for pd in D.fp_of(q).pads if pd.num == num)
            x, y = pad_center(pd, *D.K(*q["pos"]), q["rot"])
            return (x, 100 - y)
        pts = []
        for num, net in p["nets"].items():
            if not net or net.startswith("unconnected"):
                continue
            for ref, (_, q) in placed.items():
                if ref == p["ref"] or q["fp"] in ("PIVOT", "PAD_LID", "RING"):
                    continue
                for pd in D.fp_of(q).pads:
                    if q["nets"].get(pd.num) == net and (net not in BIG or ref.startswith("U")):
                        x, y = pad_center(pd, *D.K(*q["pos"]), q["rot"])
                        pts.append((x, 100 - y, 0.3 if net in BIG else 1.0))
        if not pts:
            return None
        w = sum(t[2] for t in pts)
        return (sum(t[0] * t[2] for t in pts) / w, sum(t[1] * t[2] for t in pts) / w)

    rest = [p for p in D.PARTS if p["ref"] not in placed]
    # primero las que tocan señales del integrado (más conexiones primero)
    rest.sort(key=lambda p: (p["ref"] not in DECAP or p["ref"].startswith("TP"), p["block"] == "Pruebas",
                             -sum(1 for n in p["nets"].values() if n and n not in BIG)))
    for p in rest:
        t = target_of(p) or (90.0, 0.0)
        place(p, t)
    out = {p["ref"]: [round(p["pos"][0], 3), round(p["pos"][1], 3), p["rot"]] for p in D.PARTS}
    json.dump(out, open(POSF, "w"), indent=1)
    importlib.reload(D)
    errs = D.check_placement()
    print("\n".join(errs) or "colocación sin errores", "·", len(out), "piezas")
    json.dump(D.mecanica(), open(os.path.join(HERE, "..", "pcb_mecanica.json"), "w"), indent=1, ensure_ascii=False)
    return errs


if __name__ == "__main__":
    sys.exit(1 if main() else 0)
