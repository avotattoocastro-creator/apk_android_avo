"""Colocación de la placa AVO BACK V4.

Las piezas grandes y las que fija la mecánica (módulo, conectores, microSD, contactos del fondo, pivotes, pisadores, anillos) tienen
posición a mano (FIJAS). El resto se coloca con un algoritmo voraz: cada pieza va al hueco libre más cercano a su
objetivo (el pin del integrado al que se conecta o el ancla del bloque), dentro del contorno, sin solapar patios
(+0,1 mm) y respetando la altura máxima de cada zona de la carcasa (bajo la URTK1.2, bajo J2/L, topes de la L).
Escribe colocacion_v5.json y ../pcb_mecanica.json. Uso: python3 place_v4.py
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
POSF = os.path.join(HERE, "colocacion_v5.json")

FIJAS = {
    # V5 CASCO PROTOTIPO A (18/11/2026): placa de 56 × 56. 24/11/2026: 60 × 60 (+2 mm por lado) para sacar las vías de los
    # pads con sitio (aviso de JLCPCB, PCBA 13966268A): las piezas de canto se desplazan 2 mm hacia fuera. Tiras de la URTK1.2 en su sitio exacto (FILA9_POS / FILA10_POS).
    # Petición del usuario (16:37): WROOM a la izquierda, microSD abajo en el centro (la tarjeta sale por el canto
    # inferior) y el pogo al canto SUPERIOR (en la cápsula la copa del pogo pasa a la franja +Y del suelo).
    "J10": (20.62, 1.27, 0), "J11": (-20.02, 2.54, 0),
    "U4": (-1.0, 7.3, 0), "J7": (-27.7, 17.0, 0), "J3": (1.0, -15.8, 0),
    # 19/11: USB-C de programación J16 en el canto superior (frente a ras, rot 180 = boca hacia +Y); el pogo pasa a 3 + 2
    "J16": (4.2, 26.35, 180),
    "P1": (-8.65, 27.5, 0), "P2": (-6.3, 27.5, 0), "P3": (-3.95, 27.5, 0), "P4": (-8.65, 25.05, 0), "P5": (-6.3, 25.05, 0),
    "J2": (-17.9, -27.5, 0), "J6": (-15.4, -27.5, 0),
    "J12": (20.0, 23.0, 0), "J13": (-20.0, 23.0, 0), "J14": (-20.0, -23.0, 0), "J15": (20.0, -23.0, 0),
    "D10": (-12.0, 28.25, 180), "D11": (12.0, 28.25, 180), "D12": (28.25, 12.0, 90), "D13": (28.25, -12.0, 90),
    "D14": (12.0, -28.25, 0), "D15": (-12.0, -28.25, 0), "D16": (-28.25, -12.0, 270), "D17": (-28.25, 12.0, 270),   # D14/D15 alineados con D11/D10
    "H1": (26.5, 26.5, 0), "H2": (-26.5, 26.5, 0), "H3": (-26.5, -26.5, 0), "H4": (26.5, -26.5, 0),
}
ANCLAS = {
    "U2": (-12.0, -15.0), "U6": (-2.0, 21.0), "F2": (-12.0, 21.0), "U3": (-12.0, -8.0), "U7": (14.0, 16.0),
    "U8": (23.5, -1.0), "Q4": (12.0, -8.0), "F1": (-15.0, -21.0),
    "Q7": (-15.0, -20.0), "U9": (-14.0, 20.0), "U10": (-19.0, 21.0), "U11": (-14.0, 15.0), "U12": (14.0, 6.0),
    "U13": (14.0, 11.0), "D5": (-14.0, -2.0), "D6": (-14.0, 2.0),
}
ORDEN_IC = ["U2", "U6", "F2", "U3", "U7", "U8", "Q4", "F1", "Q7", "U11", "U13", "U12", "U9", "U10", "D5", "D6"]
DECAP = {"C21": ("U3", "1"), "C22": ("U3", "5"), "C60": ("U7", "1"), "C61": ("J10", "3"),
         "C63": ("J10", "3"), "C24": ("U4", "2"), "C25": ("U4", "2"), "C26": ("U4", "2"), "C27": ("U4", "3"), "R11": ("U4", "3"),
         "C18": ("U2", "13"), "C19": ("U2", "10"), "C20": ("U2", "2"), "C35": ("U2", "11"), "C40": ("Q4", "3"),
         "C41": ("J3", "4"),
         "C80": ("U8", "1"), "TP9": ("U7", "5"), "TP6": ("U3", "5"), "TP8": ("U3", "1"), "TP7": ("F1", "2"),
         "R60": ("U7", "3"), "R40": ("Q4", "1"), "D2": ("P1", "1"), "D3": ("P5", "1"), "R18": ("U6", "1"),
         "R19": ("U6", "3"), "R6": ("U2", "16"), "R7": ("U2", "12"),
         "R8": ("U2", "5"), "R9": ("U4", "31"), "R10": ("U4", "32"),   # REV B: pull-ups de estado junto al micro (despejan OUT del BQ24072) "R22": ("U6", "5"), "R23": ("U6", "5"),
         "R20": ("P5", "1"), "R21": ("P5", "1"), "R30": ("J16", "A5"), "R31": ("J16", "B5"),
         "C90": ("D10", "2"), "C91": ("D11", "2"), "C92": ("D12", "2"), "C93": ("D13", "2"),
         "C94": ("D14", "2"), "C95": ("D15", "2"), "C96": ("D16", "2"), "C97": ("D17", "2"), "R24": ("U4", "24"),
         # REV B
         "C66": ("U9", "3"), "C67": ("U9", "2"), "C68": ("U10", "5"), "C69": ("U10", "3"), "R16": ("U10", "3"),
         "R17": ("U10", "1"), "C36": ("U12", "3"), "C37": ("U13", "8"), "C38": ("U13", "5"), "C98": ("U11", "3"),
         "C99": ("U11", "6"), "L71": ("U11", "5"), "R25": ("U11", "1"), "R26": ("U11", "1"), "R27": ("U11", "2"),
         "R12": ("U2", "14"), "R13": ("Q7", "1"), "R14": ("U3", "3"), "R15": ("D5", "2"), "R28": ("U13", "13"),
         "R29": ("U13", "14"), "TP10": ("U9", "2"), "TP12": ("U11", "6"),
         # revisión 18/11: arranque suave de la microSD y mantenimiento del EN
         "R47": ("Q4", "1"), "C42": ("Q4", "1"), "C28": ("U3", "3"),
         # REV B: pull-ups y serie de la microSD junto a sus pines (canal entre el WROOM y J3)
         "R41": ("J3", "3"), "R42": ("J3", "7"), "R43": ("J3", "8"), "R44": ("J3", "1"), "R45": ("J3", "2"),
         "R46": ("J3", "5")}
# auditoría 22/11/2026: piezas con objetivo fijo (no junto a un pin): la NTC sobre el centro de la batería, lejos del
# BQ24072, y el Schottky del USB-C junto a J16
OBJETIVO = {"RT2": (8.0, -3.0), "D18": (8.0, 21.0)}
GAP = 0.12            # separación mínima entre patios
STEP = 0.2


def main():
    # posiciones iniciales: fijas + anclas (el generador lee el JSON al importarse)
    base = {k: list(v) for k, v in FIJAS.items()}
    json.dump(base, open(POSF, "w"), indent=1)
    import importlib
    import avo_back_v5_pcb as D
    importlib.reload(D)
    from fplib import pad_center, rot
    poly = [D.K(x, y) for x, y in D.outline_pts(3)]
    placed = {}

    import numpy as np
    from matplotlib.path import Path
    from scipy import ndimage
    G = 0.1; X0, X1, Y0, Y1 = -31.5, 31.5, -31.5, 31.5   # 24/11: placa de 60
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
        if p["fp"] in ("HOLE", "CABLE"):
            r = {"HOLE": 3.0, "CABLE": 1.9}[p["fp"]]
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
        if p["ref"] in OBJETIVO:
            return OBJETIVO[p["ref"]]
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
                if ref == p["ref"] or q["fp"] in ("HOLE", "CABLE"):
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
