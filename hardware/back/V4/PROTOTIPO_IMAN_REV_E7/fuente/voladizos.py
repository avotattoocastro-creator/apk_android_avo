# -*- coding: utf-8 -*-
"""Análisis de voladizos capa a capa sobre los STL de impresión (como un laminador).
Uso: python3 voladizos.py <carpeta_STL> [<carpeta_STL> ...] -> salida/voladizos.json + resumen por pantalla.
Criterio: una celda de una capa está apoyada si hay material en la capa anterior a ≤ capa·tan(45°) (pared hasta 45°).
Las celdas sin apoyo se agrupan en zonas; para cada zona se da el voladizo máximo (distancia a material apoyado de la misma capa)
y si es PUENTE (apoyada por dos lados opuestos) o VOLADIZO (libre por un lado)."""
import sys, os, json, struct, glob
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

LH = 0.2            # altura de capa (mm)
PX = 0.1            # resolución XY (mm)
OK_VOLADIZO = 1.0   # voladizo libre admisible sin soporte (caras de bloqueo de clics/ganchos)
OK_PUENTE = 10.0    # puente admisible en PETG


def read_stl(p):
    b = open(p, "rb").read(); n = struct.unpack("<I", b[80:84])[0]
    a = np.frombuffer(b[84:84 + 50 * n], dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    return a["v"].astype(np.float64)


def slice_layer(tri, z):
    """segmentos de la sección a la altura z"""
    zs = tri[:, :, 2]
    m = (zs.min(1) < z) & (zs.max(1) > z)
    t = tri[m]
    segs = []
    for tr in t:
        pts = []
        for i in range(3):
            a, b = tr[i], tr[(i + 1) % 3]
            if (a[2] - z) * (b[2] - z) < 0:
                f = (z - a[2]) / (b[2] - a[2]); pts.append(a[:2] + f * (b[:2] - a[:2]))
        if len(pts) == 2: segs.append(pts)
    return np.array(segs)


def chain(segs, tol=1e-4):
    """une segmentos en polígonos cerrados"""
    from collections import defaultdict
    key = lambda p: (round(p[0] / tol), round(p[1] / tol))
    adj = defaultdict(list)
    for i, (a, b) in enumerate(segs):
        adj[key(a)].append((i, 0)); adj[key(b)].append((i, 1))
    used = np.zeros(len(segs), bool); polys = []
    for s in range(len(segs)):
        if used[s]: continue
        used[s] = True; poly = [segs[s][0], segs[s][1]]; cur = segs[s][1]
        for _ in range(len(segs)):
            nxt = None
            for (j, e) in adj[key(cur)]:
                if not used[j]: nxt = (j, e); break
            if nxt is None: break
            j, e = nxt; used[j] = True; cur = segs[j][1 - e]; poly.append(cur)
        polys.append(np.array(poly))
    return polys


def raster(polys, x0, y0, W, H):
    acc = np.zeros((H, W), bool)
    for p in polys:
        if len(p) < 3: continue
        im = Image.new("1", (W, H), 0)
        ImageDraw.Draw(im).polygon([((x - x0) / PX, (y - y0) / PX) for x, y in p], fill=1)
        acc ^= np.array(im, bool)
    return acc


def scan_fill(segs, x0, y0, W, H):
    """relleno par-impar por filas directamente desde los segmentos (no necesita cerrar contornos)"""
    out = np.zeros((H, W), bool)
    ya, yb = segs[:, 0, 1], segs[:, 1, 1]; xa, xb = segs[:, 0, 0], segs[:, 1, 0]
    lo, hi = np.minimum(ya, yb), np.maximum(ya, yb)
    for j in range(H):
        yc = y0 + (j + 0.5) * PX
        m = (lo <= yc) & (hi > yc)
        if not m.any(): continue
        t = (yc - ya[m]) / (yb[m] - ya[m]); xs = np.sort(xa[m] + t * (xb[m] - xa[m]))
        for k in range(0, len(xs) - 1, 2):
            i0 = int(np.ceil((xs[k] - x0) / PX - 0.5)); i1 = int(np.floor((xs[k + 1] - x0) / PX - 0.5))
            if i1 >= i0: out[j, max(i0, 0):min(i1 + 1, W)] = True
    return out


def analyse(path):
    tri = read_stl(path)
    v = tri.reshape(-1, 3); mn, mx = v.min(0), v.max(0)
    x0, y0 = mn[0] - 1, mn[1] - 1
    W, H = int((mx[0] - x0 + 1) / PX) + 1, int((mx[1] - y0 + 1) / PX) + 1
    nl = int(np.ceil((mx[2] - 1e-6) / LH))
    prev = None; zonas = []
    k = int(round(LH / PX))                                  # 45°: dilatación = altura de capa
    st = np.ones((2 * k + 1, 2 * k + 1), bool)
    for i in range(nl):
        z = (i + 0.5) * LH + 0.0137          # fuera de los planos exactos del modelo
        segs = slice_layer(tri, z)
        cur = scan_fill(segs, x0, y0, W, H) if len(segs) else np.zeros((H, W), bool)
        if prev is None:
            prev = cur; continue
        sup = ndimage.binary_dilation(prev, structure=st)
        U = cur & ~sup
        if U.any():
            S = cur & sup
            d = ndimage.distance_transform_edt(~S) * PX if S.any() else np.full(cur.shape, 99.0)
            lab, n = ndimage.label(U)
            for j in range(1, n + 1):
                m = lab == j
                if m.sum() < 4: continue                     # ruido de teselado
                dmax = float(d[m].max())
                if dmax <= 0.25: continue                    # dentro del margen de 45°
                # puente: el punto más alejado está rodeado de material de la capa por ambos lados
                ys, xs = np.nonzero(m); bb = [x0 + xs.min() * PX, x0 + xs.max() * PX, y0 + ys.min() * PX, y0 + ys.max() * PX]
                edge_free = (m & ~ndimage.binary_erosion(cur, structure=np.ones((3, 3), bool))).sum()
                Mp = ndimage.binary_dilation(m, iterations=2) & ~m & ~cur      # borde de la zona que da al vacío
                Ms = ndimage.binary_dilation(m, iterations=2) & S              # borde que toca material apoyado
                tipo = "PUENTE" if Ms.sum() > 0 and Mp.sum() < 0.15 * (Mp.sum() + Ms.sum()) else "VOLADIZO"
                lim = OK_PUENTE if tipo == "PUENTE" else OK_VOLADIZO
                span = 2 * dmax if tipo == "PUENTE" else dmax
                zonas.append(dict(z=round(z, 2), tipo=tipo, voladizo_mm=round(span, 2), area_mm2=round(m.sum() * PX * PX, 2),
                                  caja=[round(c, 1) for c in bb], ok=bool(span <= lim)))
        prev = cur
    # fusiona zonas iguales en capas consecutivas
    return dict(capas=nl, zonas=zonas, peor=max([z["voladizo_mm"] for z in zonas if not z["ok"]], default=0.0),
                n_mal=sum(1 for z in zonas if not z["ok"]))


if __name__ == "__main__":
    out = {}
    for d in sys.argv[1:]:
        for p in sorted(glob.glob(os.path.join(d, "*.stl"))):
            nm = os.path.basename(p)[:-4]
            if "CONJUNTO" in nm: continue
            r = analyse(p); out[nm] = r
            bad = [z for z in r["zonas"] if not z["ok"]]
            print("%-34s capas %3d · zonas sin apoyo %3d · fuera de límite %3d" % (nm, r["capas"], len(r["zonas"]), len(bad)), flush=True)
            seen = set()
            for z in bad:
                k_ = (z["tipo"], tuple(round(c) for c in z["caja"]))
                if k_ in seen: continue
                seen.add(k_)
                print("    %-8s z %5.2f  %5.2f mm  área %6.1f  X %s–%s Y %s–%s" % (z["tipo"], z["z"], z["voladizo_mm"], z["area_mm2"], *z["caja"]))
    json.dump(out, open(os.environ.get("VOL_OUT", "salida/voladizos.json"), "w"), indent=1, ensure_ascii=False)
