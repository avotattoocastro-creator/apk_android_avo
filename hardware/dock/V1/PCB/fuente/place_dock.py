"""Colocación de la placa AVO DOCK V1 (soporte de pared cargador).

Las piezas grandes y las que fija la mecánica (red 220 V, IRM-20, USB-C, módulo S3, hilos de los alojamientos, pantalla,
taladros) tienen posición a mano (FIJAS). El resto se coloca con un algoritmo voraz: cada pieza va al hueco libre más
cercano a su objetivo (el pin del integrado al que se conecta o el ancla del bloque), dentro del contorno, sin solapar
patios (+0,12 mm) y fuera de la zona de red y del foso de aislamiento. Escribe colocacion_dock.json y ../pcb_mecanica.json.
Uso: python3 place_dock.py
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
POSF = os.path.join(HERE, "colocacion_dock.json")

CA_X, CB_X, GA_X, GB_X, PY = -29.0, -14.0, 4.0, 15.0, 33.0
FIJAS = {
    # red 220 V (zona aislada, esquina −X/+Y)
    "J1": (-62.5, 34.0, 0), "F1": (-62.5, 27.0, 0), "J2": (-50.0, 34.0, 0), "RV1": (-57.5, 20.5, 0),
    "PS1": (-58.0, 12.0, 0),
    # conectores y módulo
    "J3": (61.5, -24.0, 90), "U3": (50.0, 22.0, 0), "J4": (33.0, 34.0, 0),
    "H1": (61.0, 34.0, 0), "H2": (61.0, -34.0, 0), "H3": (-61.0, -34.0, 0), "H4": (-34.5, 34.0, 0),
    "P20": (-34.0, 22.0, 0), "P21": (-34.0, 19.46, 0),
    # hub girado 270°: pines 28–36 (USB de subida, cristal, PLLFILT) hacia +X (muxes y S3); 1–9 (puertos) hacia +Y
    "U6": (20.0, 2.0, 270),
}
for i in range(5):
    FIJAS["P%d" % (1 + i)] = (CA_X + 2.54 * i, PY, 0)
    FIJAS["P%d" % (6 + i)] = (CB_X + 2.54 * i, PY, 0)
for i in range(3):
    FIJAS["P%d" % (11 + i)] = (GA_X + 2.54 * i, PY, 0)
    FIJAS["P%d" % (14 + i)] = (GB_X + 2.54 * i, PY, 0)
ANCLAS = {
    "Q1": (-4.0, -2.0), "Q1B": (-4.0, -6.0), "Q3": (-4.0, 4.0), "Q2": (2.0, -14.0), "C4": (-2.0, -10.0),
    "U2": (8.0, -24.0), "U6": (20.0, 2.0), "Y1": (28.5, 9.0), "U4": (42.0, -16.0), "U5": (40.0, 6.0),
    "U1": (52.0, -24.0), "F2": (50.0, -30.0),
    "U10": (-26.0, 24.0), "U11": (-11.0, 24.0), "U12": (5.0, 22.0), "U13": (16.0, 22.0),
    "U14": (-21.0, 24.0), "U15": (-6.0, 24.0), "U16": (9.0, 18.0), "U17": (20.0, 18.0),
    "U18": (-24.0, 29.0), "U19": (-9.0, 29.0),
}
ORDEN_IC = ["Q1", "Q1B", "Q3", "Q2", "C4", "U2", "Y1", "U4", "U5", "U1", "F2",
            "U10", "U11", "U12", "U13", "U14", "U15", "U16", "U17", "U18", "U19"]
DECAP = {"C1": ("PS1", "4"), "C2": ("PS1", "4"), "C3": ("F2", "2"), "C5": ("Q1", "2"), "C6": ("U2", "3"),
         "C7": ("U2", "2"), "C8": ("U2", "2"), "C9": ("U3", "3"), "C10": ("U3", "3"), "C11": ("U3", "3"),
         "C13": ("U4", "10"), "C14": ("U5", "10"), "C20": ("U6", "5"), "C21": ("U6", "10"), "C22": ("U6", "29"),
         "C23": ("U6", "36"), "C24": ("U6", "15"), "C25": ("U6", "23"), "C27": ("U6", "14"), "C28": ("U6", "34"),
         "C30": ("Y1", "1"), "C31": ("Y1", "3"), "R20": ("U6", "35"), "C15": ("J4", "2"),
         "R3": ("J3", "A5"), "R4": ("J3", "B5"), "D1": ("J3", "A4"), "R15": ("U3", "24"), "R16": ("U3", "23"),
         "TP7": ("Q1", "2"), "TP8": ("PS1", "4"), "TP9": ("F2", "2"), "TP6": ("U2", "2")}
for k in range(4):
    DECAP["C%d" % (40 + k)] = ("U%d" % (10 + k), "1")
    DECAP["R%d" % (40 + k)] = ("U%d" % (10 + k), "5")
    DECAP["C%d" % (44 + k)] = ("U%d" % (14 + k), "5")
for k, pads_ in enumerate((("P1", "D10", "C48"), ("P6", "D11", "C49"), ("P11", "D12", "C50"), ("P14", "D13", "C51"))):
    DECAP[pads_[1]] = (pads_[0], "1"); DECAP[pads_[2]] = (pads_[0], "1")
DECAP.update({"D14": ("P5", "1"), "D15": ("P10", "1"), "D16": ("P13", "1"), "D17": ("P16", "1"),
              "R56": ("P5", "1"), "R57": ("P10", "1"), "R60": ("P13", "1"), "R61": ("P16", "1"),
              "R52": ("U18", "1"), "R53": ("U18", "3"), "R54": ("U19", "1"), "R55": ("U19", "3")})
GAP = 0.25            # separación mínima entre patios (más sitio para rutear que en la V5)
STEP = 0.2


def main():
    # posiciones iniciales: fijas + anclas (el generador lee el JSON al importarse)
    base = {k: list(v) for k, v in FIJAS.items()}
    json.dump(base, open(POSF, "w"), indent=1)
    import importlib
    import avo_dock_v1_pcb as D
    importlib.reload(D)
    from fplib import pad_center, rot
    poly = [D.K(x, y) for x, y in D.outline_pts(3)]
    placed = {}

    import numpy as np
    from matplotlib.path import Path
    from scipy import ndimage
    G = 0.1; X0, X1, Y0, Y1 = -66.0, 66.0, -39.0, 39.0
    W, H = int((X1 - X0) / G), int((Y1 - Y0) / G)
    xs = X0 + (np.arange(W) + 0.5) * G; ys = Y0 + (np.arange(H) + 0.5) * G
    XX, YY = np.meshgrid(xs, ys)
    inside = Path([(x - 100, 100 - y) for x, y in poly]).contains_points(np.c_[XX.ravel(), YY.ravel()]).reshape(H, W)
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
        cx0, cx1 = b[0] - 100 - grow, b[2] - 100 + grow; cy0, cy1 = 100 - b[3] - grow, 100 - b[1] + grow
        i0 = max(0, int(math.floor((cy0 - Y0) / G))); i1 = min(H, int(math.ceil((cy1 - Y0) / G)))
        j0 = max(0, int(math.floor((cx0 - X0) / G))); j1 = min(W, int(math.ceil((cx1 - X0) / G)))
        return i0, i1, j0, j1

    def mark(p):
        b = bbox(p, p["pos"], p["rot"])
        if p["fp"] in ("HOLE",):
            r = D.HOLE_KEEP
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

    BIG = {D.GND, D.V3, D.V5, D.V5AC, D.VBUS}

    def target_of(p):
        if p["ref"] in DECAP:
            ic, num = DECAP[p["ref"]]
            q = byref[ic]
            pd = next(pd for pd in D.fp_of(q).pads if pd.num == num)
            x, y = pad_center(pd, *D.K(*q["pos"]), q["rot"])
            return (x - 100, 100 - y)
        pts = []
        for num, net in p["nets"].items():
            if not net or net.startswith("unconnected"):
                continue
            for ref, (_, q) in placed.items():
                if ref == p["ref"] or q["fp"] in ("HOLE",):
                    continue
                for pd in D.fp_of(q).pads:
                    if q["nets"].get(pd.num) == net and (net not in BIG or ref.startswith("U")):
                        x, y = pad_center(pd, *D.K(*q["pos"]), q["rot"])
                        pts.append((x - 100, 100 - y, 0.3 if net in BIG else 1.0))
        if not pts:
            return None
        w = sum(t[2] for t in pts)
        return (sum(t[0] * t[2] for t in pts) / w, sum(t[1] * t[2] for t in pts) / w)

    rest = [p for p in D.PARTS if p["ref"] not in placed]
    # primero las que tocan señales del integrado (más conexiones primero)
    rest.sort(key=lambda p: (p["ref"] not in DECAP or p["ref"].startswith("TP"), p["block"] == "Pruebas",
                             -sum(1 for n in p["nets"].values() if n and n not in BIG)))
    for p in rest:
        t = target_of(p) or (0.0, 0.0)
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
