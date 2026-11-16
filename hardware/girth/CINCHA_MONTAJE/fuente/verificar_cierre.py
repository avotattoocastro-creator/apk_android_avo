"""REV 6.3 · comprobación del cierre magnético de balancín (lado +X) por vóxeles.

El núcleo `avo_cad` no hace operaciones booleanas, así que las interferencias se miden muestreando el volumen del
balancín (rejilla de 0,05 mm en su perfil XZ y cada 0,25 mm en Y) y preguntando si cada punto cae dentro del soporte,
la base o la tapa (sólidos por capas en Z: se rasterizan sus contornos con la regla par-impar).

Comprueba:
  1. cerrado: 0 puntos del balancín dentro del soporte, la base o la tapa;
  2. apertura (parte de arriba hacia dentro) con la cápsula apoyada: sin choques con el soporte; ángulo al que el diente
     sale del cerco; ángulo al que el balancín toca la cápsula (tope);
  3. al bajar la cápsula para cerrar, el bisel del diente apoya en el canto del cerco (el imán lo vuelve a meter).

Uso: python3 verificar_cierre.py  (escribe ../out/verificacion_cierre.json)
"""
import json
import math
import os
import sys

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avo_cad as A  # noqa: E402

CAPT = {}
_orig = A.layered


def _cap(layers, name="pieza", color=(0.8, 0.8, 0.8)):
    CAPT[name] = layers
    return _orig(layers, name, color)


A.layered = _cap
import avo_cincha_montaje as M  # noqa: E402

RES = 0.05


class Capas:
    """sólido por capas en Z (contornos XY, regla par-impar), desplazado dz"""

    def __init__(self, layers, dz=0.0, region=(-60, -60, 60, 60)):
        self.z = np.array([[l[0] + dz, l[1] + dz] for l in layers])
        self.x0, self.y0, x1, y1 = region
        self.W = int((x1 - self.x0) / RES) + 1
        self.H = int((y1 - self.y0) / RES) + 1
        self.layers = layers
        self.cache = {}

    def mask(self, k):
        if k not in self.cache:
            m = np.zeros((self.H, self.W), np.uint8)
            for c in self.layers[k][2]:
                t = np.zeros_like(m)
                P = np.round(np.c_[(c.p[:, 0] - self.x0) / RES, (c.p[:, 1] - self.y0) / RES] * 16).astype(np.int32)
                cv2.fillPoly(t, [P], 1, lineType=cv2.LINE_8, shift=4)
                m ^= t
            self.cache[k] = m
        return self.cache[k]

    def inside(self, P):
        out = np.zeros(len(P), bool)
        for k in range(len(self.layers)):
            sel = (P[:, 2] > self.z[k, 0]) & (P[:, 2] < self.z[k, 1])
            if not sel.any():
                continue
            Q = P[sel]
            ix = np.round((Q[:, 0] - self.x0) / RES).astype(int)
            iy = np.round((Q[:, 1] - self.y0) / RES).astype(int)
            ok = (ix >= 0) & (ix < self.W) & (iy >= 0) & (iy < self.H)
            r = np.zeros(len(Q), bool)
            r[ok] = self.mask(k)[iy[ok], ix[ok]] > 0
            out[np.where(sel)[0]] = r
        return out


def puntos_balancin(sg=1):
    """puntos del volumen del balancín en la cápsula (z = 0 fondo)"""
    pts = []
    for (y0, y1, cs) in M.balancin_capas(sg):
        xs = np.concatenate([c.p[:, 0] for c in cs]); zs = np.concatenate([c.p[:, 1] for c in cs])
        x0, z0 = xs.min() - 0.1, zs.min() - 0.1
        W = int((xs.max() - x0) / RES) + 3; H = int((zs.max() - z0) / RES) + 3
        m = np.zeros((H, W), np.uint8)
        for c in cs:
            t = np.zeros_like(m)
            P = np.round(np.c_[(c.p[:, 0] - x0) / RES, (c.p[:, 1] - z0) / RES] * 16).astype(np.int32)
            cv2.fillPoly(t, [P], 1, lineType=cv2.LINE_8, shift=4)
            m ^= t
        iz, ix = np.nonzero(m)
        X = x0 + ix * RES; Z = z0 + iz * RES
        for y in np.arange(y0 + 0.05, y1, 0.25):
            pts.append(np.c_[X, np.full_like(X, y), Z])
    P = np.vstack(pts)
    if sg < 0:
        P[:, 0] *= -1
    return P


def rot_y(P, cx, cz, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    Q = P.copy()
    dx, dz = P[:, 0] - cx, P[:, 2] - cz
    Q[:, 0] = cx + dx * c + dz * s
    Q[:, 2] = cz - dx * s + dz * c
    return Q


def main():
    M.pieza_soporte(); M.pieza_base(); M.pieza_tapa()
    z0 = M.Z0_CAP
    sop = Capas(CAPT["AVO_CINCHA_R6_3_soporte_PETG"], dz=-z0)      # en z de la cápsula
    base = Capas(CAPT["AVO_CINCHA_R6_3_base_aro_luz"])
    tapa = Capas(CAPT["AVO_CINCHA_R6_3_tapa"])
    xw, x_rim, xi, xo, yc = M.bal_x()
    pz = M.BAL["pz_c"]
    vox = RES * RES * 0.25
    rep = {"rejilla_mm": [RES, RES, 0.25]}
    for sg in (1, -1):
        P = puntos_balancin(sg)
        tag = "+X" if sg > 0 else "-X"
        r = {}
        r["cerrado_mm3"] = {n: round(float(S.inside(P).sum() * vox), 3) for n, S in (("soporte", sop), ("base", base),
                                                                                    ("tapa", tapa))}
        sw = {}
        suelto, tope = None, None
        teeth = (P[:, 0] * sg < xi) & (P[:, 2] < M.BAL["top_c"] + 0.01) & (P[:, 2] > M.BAL["root_b_c"] - 0.01)
        for ang in [0, -2, -4, -6, -8, -10, -12, -14, -16, -18, -20, -22, -24, -26, -28]:
            Q = rot_y(P, sg * xi, pz, ang * sg)
            v_s = float(sop.inside(Q).sum() * vox)
            v_c = float((base.inside(Q) | tapa.inside(Q)).sum() * vox)
            en_cerco = int(((Q[teeth][:, 0] * sg) < x_rim).sum())
            sw[ang] = {"soporte_mm3": round(v_s, 3), "capsula_mm3": round(v_c, 3), "puntos_del_diente_en_el_cerco": en_cerco}
            if suelto is None and en_cerco == 0:
                suelto = ang
            if tope is None and v_c > 0.01:
                tope = ang
        r["apertura"] = sw
        r["angulo_diente_fuera_grados"] = suelto
        r["angulo_tope_contra_la_capsula_grados"] = tope
        r["recorrido_pulsador_al_soltar_mm"] = round((M.H_CAP - pz) * math.sin(math.radians(-suelto)), 2) if suelto else None
        rep[tag] = r
    # palanca, imanes, rozamiento
    b = M.BAL
    rep["balancin"] = {
        "eje_capsula_xz_mm": [round(xi, 2), pz],
        "brazo_pulsador_mm": round(M.H_CAP - pz, 2),
        "brazo_iman_mm": round(pz - b["mag_c"], 2),
        "brazo_diente_mm": round(pz - b["top_c"], 2),
        "separacion_imanes_mm": round((xi + b["skin"]) - (x_rim - b["skin"]), 2),
        "diente": "recto, entra %.1f mm; bisel de entrada abajo" % b["e"],
        "rozamiento_minimo_para_bloquear_con_carga": round(b["e"] / (pz - b["top_c"]), 3),
        "imanes": "2 + 2 Ø5 × 1 apilados por lado (balancín y cerco), en atracción: 8 en total",
        "pasadores": "4 × ISO 2338 Ø2 × 6 (2 por balancín, a presión en las aletas)",
    }
    out = os.path.normpath(os.path.join(HERE, "..", "out", "verificacion_cierre.json"))
    json.dump(rep, open(out, "w"), indent=1, ensure_ascii=False)
    print(json.dumps({k: v for k, v in rep.items() if k in ("+X", "-X")}, indent=1, ensure_ascii=False)[:3000])
    print(json.dumps(rep["balancin"], indent=1, ensure_ascii=False))
    return rep


if __name__ == "__main__":
    main()
