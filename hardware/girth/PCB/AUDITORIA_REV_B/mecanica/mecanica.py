#!/usr/bin/env python3
"""AVO GIRTH PCB REV B · auditoría mecánica de encaje en la cápsula REV 5.8.1.

Reproducible: solo necesita Python 3 + numpy (+ scipy y matplotlib para etiquetar zonas y dibujar).
No usa trimesh/shapely (el índice de PyPI no es accesible desde el entorno de la auditoría): las STL se leen,
se cortan por planos y se atraviesan con rayos con numpy.

Uso:   python3 mecanica.py           → imprime el informe y escribe mecanica_salida.txt y los PNG en esta carpeta.

Entradas (rutas relativas a la raíz del repositorio):
  hardware/girth/PCB/out/C3/KiCad/AVO_GIRTH_PCB.kicad_pcb      contorno, huellas, zonas (independiente del .py)
  hardware/girth/PCB/out/C3/AVO_GIRTH_PCB_C3_GERBER_JLCPCB.zip Edge_Cuts, cobre y job (independiente del .py)
  hardware/girth/PCB/fuente/avo_girth_pcb.py                   alturas de huella (FP[*].height) y constantes
  hardware/girth/REV5/out/montaje/*.stl                         base, tapa, junta, bandeja en posición de montaje
  hardware/girth/REV5/out/ref_*.stl                             batería, bobina, reed, antena, imanes (referencias)
Coordenadas: las de la cápsula (X a lo largo, Y, Z hacia la tapa; origen en el centro, Z = 0 bajo la base).
KiCad: x = 100 + X, y = 100 − Y.  Gerber (KiCad): xg = x, yg = −y  →  X = xg − 100, Y = yg + 100.
"""
import io
import json
import math
import os
import re
import sys
import zipfile

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
PCB_DIR = os.path.join(REPO, "hardware", "girth", "PCB")
CAD_DIR = os.path.join(REPO, "hardware", "girth", "REV5", "out")
KICAD_PCB = os.path.join(PCB_DIR, "out", "C3", "KiCad", "AVO_GIRTH_PCB.kicad_pcb")
GERBER_ZIP = os.path.join(PCB_DIR, "out", "C3", "AVO_GIRTH_PCB_C3_GERBER_JLCPCB.zip")

sys.dont_write_bytecode = True          # no deja __pycache__ en fuente/
sys.path.insert(0, os.path.join(PCB_DIR, "fuente"))
import avo_girth_pcb as D  # noqa: E402  (alturas de huella y constantes de diseño)

OUT_LINES = []


def out(s=""):
    print(s)
    OUT_LINES.append(s)


def sec(t):
    out("")
    out("=" * 100)
    out(t)
    out("=" * 100)


# ============================================================================================ STL
def load_stl(path):
    data = open(path, "rb").read()
    n = int.from_bytes(data[80:84], "little") if len(data) >= 84 else 0
    if len(data) == 84 + 50 * n:
        a = np.frombuffer(data[84:], dtype=np.dtype([("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")]), count=n)
        return a["v"].astype(np.float64)
    txt = data.decode("ascii", "ignore")
    v = np.array(re.findall(r"vertex\s+(\S+)\s+(\S+)\s+(\S+)", txt), dtype=float)
    return v.reshape(-1, 3, 3)


def bbox(tris):
    p = tris.reshape(-1, 3)
    return p.min(0), p.max(0)


def slice_mesh(tris, axis, value):
    """Corte de la malla por el plano coord[axis] = value → segmentos 2D en las otras dos coordenadas."""
    value = value + 1.234e-7
    ax2 = [i for i in range(3) if i != axis]
    d = tris[:, :, axis] - value
    m = (d.min(1) < 0) & (d.max(1) > 0)
    T, dd = tris[m], d[m]
    segs = []
    for (i, j) in ((0, 1), (1, 2), (2, 0)):
        c = (dd[:, i] * dd[:, j]) < 0
        t = dd[:, i] / np.where(c, dd[:, i] - dd[:, j], 1)
        p = T[:, i] + (T[:, j] - T[:, i]) * t[:, None]
        segs.append((c, p[:, ax2]))
    # cada triángulo cortado tiene exactamente 2 aristas cruzadas
    c = np.stack([s[0] for s in segs], 1)
    P = np.stack([s[1] for s in segs], 1)
    idx = np.argsort(~c, axis=1, kind="stable")[:, :2]
    a = P[np.arange(len(P)), idx[:, 0]]
    b = P[np.arange(len(P)), idx[:, 1]]
    return np.concatenate([a, b], 1)        # (n, 4): x1 y1 x2 y2


def inside_segs(pts, segs, chunk=4000):
    """Par/impar con un rayo hacia +x: ¿está el punto dentro de la sección (material)?"""
    pts = np.atleast_2d(pts)
    res = np.zeros(len(pts), bool)
    x1, y1, x2, y2 = segs.T
    for k in range(0, len(pts), chunk):
        P = pts[k:k + chunk]
        px, py = P[:, 0:1], P[:, 1:2]
        c = (y1 > py) != (y2 > py)
        xi = x1 + (py - y1) * (x2 - x1) / np.where(y2 != y1, y2 - y1, 1e-30)
        res[k:k + chunk] = ((c & (px < xi)).sum(1) % 2) == 1
    return res


def dist_segs(pts, segs, chunk=2000):
    pts = np.atleast_2d(pts)
    res = np.empty(len(pts))
    a, b = segs[:, :2], segs[:, 2:]
    ab = b - a
    L2 = np.maximum((ab ** 2).sum(1), 1e-30)
    for k in range(0, len(pts), chunk):
        P = pts[k:k + chunk][:, None, :]
        t = np.clip(((P - a) * ab).sum(2) / L2, 0, 1)
        q = a + t[..., None] * ab
        res[k:k + chunk] = np.sqrt(((P - q) ** 2).sum(2)).min(1)
    return res


def zmap(tris, xs, ys):
    """Rayos verticales en la rejilla xs × ys: z mínimo y máximo de los cortes con la malla (nan si no hay)."""
    nx, ny = len(xs), len(ys)
    zmin = np.full((ny, nx), np.inf)
    zmax = np.full((ny, nx), -np.inf)
    x0, dx = xs[0], xs[1] - xs[0]
    y0, dy = ys[0], ys[1] - ys[0]
    A, B, C = tris[:, 0], tris[:, 1], tris[:, 2]
    det = (B[:, 1] - C[:, 1]) * (A[:, 0] - C[:, 0]) + (C[:, 0] - B[:, 0]) * (A[:, 1] - C[:, 1])
    ok = np.abs(det) > 1e-12
    lo = tris[:, :, :2].min(1)
    hi = tris[:, :, :2].max(1)
    i0 = np.clip(np.ceil((lo[:, 0] - x0) / dx).astype(int), 0, nx)
    i1 = np.clip(np.floor((hi[:, 0] - x0) / dx).astype(int) + 1, 0, nx)
    j0 = np.clip(np.ceil((lo[:, 1] - y0) / dy).astype(int), 0, ny)
    j1 = np.clip(np.floor((hi[:, 1] - y0) / dy).astype(int) + 1, 0, ny)
    for t in np.nonzero(ok & (i1 > i0) & (j1 > j0))[0]:
        X, Y = np.meshgrid(xs[i0[t]:i1[t]], ys[j0[t]:j1[t]])
        a, b, c = A[t], B[t], C[t]
        l1 = ((b[1] - c[1]) * (X - c[0]) + (c[0] - b[0]) * (Y - c[1])) / det[t]
        l2 = ((c[1] - a[1]) * (X - c[0]) + (a[0] - c[0]) * (Y - c[1])) / det[t]
        l3 = 1 - l1 - l2
        m = (l1 >= -1e-9) & (l2 >= -1e-9) & (l3 >= -1e-9)
        if not m.any():
            continue
        z = l1 * a[2] + l2 * b[2] + l3 * c[2]
        sub_min = zmin[j0[t]:j1[t], i0[t]:i1[t]]
        sub_max = zmax[j0[t]:j1[t], i0[t]:i1[t]]
        np.minimum(sub_min, np.where(m, z, np.inf), out=sub_min)
        np.maximum(sub_max, np.where(m, z, -np.inf), out=sub_max)
    return zmin, zmax


def ray_hits(tris, o, d):
    """Möller–Trumbore: distancias t > 0 de los cortes del rayo o + t·d con la malla (ordenadas)."""
    o, d = np.asarray(o, float), np.asarray(d, float)
    v0, v1, v2 = tris[:, 0], tris[:, 1], tris[:, 2]
    e1, e2 = v1 - v0, v2 - v0
    p = np.cross(d, e2)
    det = (e1 * p).sum(1)
    ok = np.abs(det) > 1e-12
    inv = 1 / np.where(ok, det, 1)
    s = o - v0
    u = (s * p).sum(1) * inv
    q = np.cross(s, e1)
    v = (q * d).sum(1) * inv
    t = (e2 * q).sum(1) * inv
    m = ok & (u >= 0) & (v >= 0) & (u + v <= 1) & (t > 1e-9)
    return np.sort(t[m])


# ============================================================================================ S-expresiones (KiCad)
def sexpr_parse(txt):
    tok = re.findall(r'\(|\)|"(?:\\.|[^"\\])*"|[^\s()"]+', txt)
    stack = [[]]
    for t in tok:
        if t == "(":
            stack.append([])
        elif t == ")":
            e = stack.pop()
            stack[-1].append(e)
        else:
            stack[-1].append(t[1:-1] if t.startswith('"') else t)
    return stack[0][0]


def kids(node, name):
    return [e for e in node if isinstance(e, list) and e and e[0] == name]


def kid(node, name):
    k = kids(node, name)
    return k[0] if k else None


def arc3(a, m, b, step_deg=2.0):
    (ax, ay), (bx, by), (cx, cy) = a, m, b
    d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
    uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
    r = math.hypot(ax - ux, ay - uy)
    t0 = math.atan2(ay - uy, ax - ux)
    tm = math.atan2(by - uy, bx - ux)
    t1 = math.atan2(cy - uy, cx - ux)
    norm = lambda t: (t - t0) % (2 * math.pi)  # noqa: E731
    span = norm(t1) if norm(tm) < norm(t1) else -((t0 - t1) % (2 * math.pi))
    n = max(2, int(abs(math.degrees(span)) / step_deg))
    pts = [(ux + r * math.cos(t0 + span * k / n), uy + r * math.sin(t0 + span * k / n)) for k in range(n + 1)]
    return pts, (ux, uy), r


def chain(polylines, tol=1e-3):
    """Une polilíneas sueltas en lazos cerrados por sus extremos."""
    segs = [list(p) for p in polylines]
    loops = []
    while segs:
        cur = segs.pop(0)
        changed = True
        while changed:
            changed = False
            for i, s in enumerate(segs):
                if math.dist(cur[-1], s[0]) < tol:
                    cur += s[1:]
                elif math.dist(cur[-1], s[-1]) < tol:
                    cur += s[::-1][1:]
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        loops.append(np.array(cur))
    return loops


def poly_area(p):
    x, y = p[:, 0], p[:, 1]
    return 0.5 * (x * np.roll(y, -1) - np.roll(x, -1) * y).sum()


def poly_segs(p):
    q = np.roll(p, -1, axis=0)
    return np.concatenate([p, q], 1)


def K2C(x, y):
    return x - 100.0, 100.0 - y


def rot_local(x, y, deg):
    """Giro de KiCad (y hacia abajo, ángulo positivo antihorario en pantalla)."""
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return x * c + y * s, -x * s + y * c


def fab_abs(fab, x, y, r):
    if not fab:
        return None
    pts = [K2C(x + rot_local(a, b, r)[0], y + rot_local(a, b, r)[1]) for a, b in fab]
    P = np.array(pts)
    return (P[:, 0].min(), P[:, 1].min(), P[:, 0].max(), P[:, 1].max())


def read_kicad(path):
    root = sexpr_parse(open(path, encoding="utf-8").read())
    res = {"thickness": float(kid(kid(root, "general"), "thickness")[1])}
    pl = []
    for e in root:
        if not isinstance(e, list) or e[0] not in ("gr_line", "gr_arc", "gr_circle", "gr_rect", "gr_poly"):
            continue
        if kid(e, "layer")[1] != "Edge.Cuts":
            continue
        if e[0] == "gr_line":
            a = K2C(*map(float, kid(e, "start")[1:3]))
            b = K2C(*map(float, kid(e, "end")[1:3]))
            pl.append([a, b])
        elif e[0] == "gr_arc":
            a = K2C(*map(float, kid(e, "start")[1:3]))
            m = K2C(*map(float, kid(e, "mid")[1:3]))
            b = K2C(*map(float, kid(e, "end")[1:3]))
            pts, c, r = arc3(a, m, b)
            pl.append(pts)
            res.setdefault("arcs", []).append((c, r))
        else:
            raise SystemExit("Edge.Cuts con %s: no previsto" % e[0])
    res["edge_loops"] = chain(pl)
    fps = {}
    for f in kids(root, "footprint"):
        at = kid(f, "at")
        x, y = float(at[1]), float(at[2])
        r = float(at[3]) if len(at) > 3 else 0.0
        ref = next(p[2] for p in kids(f, "property") if p[1] == "Reference")
        pads = []
        for p in kids(f, "pad"):
            pa = kid(p, "at")
            lx, ly = float(pa[1]), float(pa[2])
            gx, gy = rot_local(lx, ly, r)
            sz = kid(p, "size")
            pads.append(dict(num=p[1], kind=p[2], X=K2C(x + gx, y + gy)[0], Y=K2C(x + gx, y + gy)[1],
                             size=(float(sz[1]), float(sz[2])) if sz else (0, 0), drill=kid(p, "drill")))
        cy = []
        for g in kids(f, "fp_line") + kids(f, "fp_rect"):
            if kid(g, "layer")[1] == "F.CrtYd":
                for k in ("start", "end"):
                    lx, ly = map(float, kid(g, k)[1:3])
                    gx, gy = rot_local(lx, ly, r)
                    cy.append(K2C(x + gx, y + gy))
        cy = np.array(cy) if cy else None
        fab = []
        for g in kids(f, "fp_line"):
            if kid(g, "layer")[1] == "F.Fab":
                for k in ("start", "end"):
                    fab.append(tuple(map(float, kid(g, k)[1:3])))
        fps[ref] = dict(name=f[1], layer=kid(f, "layer")[1], X=K2C(x, y)[0], Y=K2C(x, y)[1], rot=r, pads=pads,
                        crt=(cy[:, 0].min(), cy[:, 1].min(), cy[:, 0].max(), cy[:, 1].max()) if cy is not None else None,
                        fab_local=fab, kx=x, ky=y, fab=fab_abs(fab, x, y, r))
    res["fps"] = fps
    zones = {}
    for z in kids(root, "zone"):
        nm = kid(z, "name")
        if nm is None:
            continue
        pts = kid(kid(z, "polygon"), "pts")
        zones[nm[1]] = np.array([K2C(float(p[1]), float(p[2])) for p in kids(pts, "xy")])
    res["zones"] = zones
    return res


# ============================================================================================ Gerber
def gerber_paths(txt):
    """Trazos de un Gerber (D01 lineal y circular; D03 destellos) → polilíneas y destellos en coordenadas de cápsula."""
    fs = re.search(r"%FSLAX(\d)(\d)Y(\d)(\d)\*%", txt)
    sc = 10 ** int(fs.group(2))
    mode, x, y = "G01", 0.0, 0.0
    paths, flashes = [], []
    for blk in txt.replace("\n", "").split("*"):
        for g in re.findall(r"G0?([123])(?=\D|$)", blk.split("X")[0].split("Y")[0]):
            mode = "G0" + g
        m = re.search(r"(?:X(-?\d+))?(?:Y(-?\d+))?(?:I(-?\d+))?(?:J(-?\d+))?D0?([123])$", blk)
        if not m or not blk.strip() or blk.startswith("%"):
            continue
        nx = int(m.group(1)) / sc if m.group(1) else x
        ny = int(m.group(2)) / sc if m.group(2) else y
        i = int(m.group(3)) / sc if m.group(3) else 0.0
        j = int(m.group(4)) / sc if m.group(4) else 0.0
        dc = m.group(5)
        if dc == "1":
            if mode == "G01":
                paths.append([(x, y), (nx, ny)])
            else:
                cx, cy = x + i, y + j
                r = math.hypot(x - cx, y - cy)
                a0 = math.atan2(y - cy, x - cx)
                a1 = math.atan2(ny - cy, nx - cx)
                if mode == "G02":          # horario
                    sp = -((a0 - a1) % (2 * math.pi)) or -2 * math.pi
                else:
                    sp = ((a1 - a0) % (2 * math.pi)) or 2 * math.pi
                n = max(2, int(abs(math.degrees(sp)) / 2))
                paths.append([(cx + r * math.cos(a0 + sp * k / n), cy + r * math.sin(a0 + sp * k / n)) for k in range(n + 1)])
        elif dc == "3":
            flashes.append((nx, ny))
        x, y = nx, ny
    tf = lambda p: (p[0] - 100.0, p[1] + 100.0)  # noqa: E731
    return [[tf(p) for p in pl] for pl in paths], [tf(p) for p in flashes]


def seg_rect_hit(a, b, r):
    """¿Corta el segmento ab el rectángulo r = (x0, y0, x1, y1)? (Liang–Barsky)"""
    x0, y0, x1, y1 = r
    dx, dy = b[0] - a[0], b[1] - a[1]
    t0, t1 = 0.0, 1.0
    for p, q in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])):
        if p == 0:
            if q < 0:
                return False
        else:
            t = q / p
            if p < 0:
                t0 = max(t0, t)
            else:
                t1 = min(t1, t)
            if t0 > t1:
                return False
    return True


# ============================================================================================ campo de imanes
MU0 = 4e-7 * math.pi


def dipole_B(m_vec, r_vec):
    r = np.linalg.norm(r_vec)
    rh = r_vec / r
    return MU0 / (4 * math.pi) * (3 * np.dot(m_vec, rh) * rh - m_vec) / r ** 3


def cylinders_from_stl(tris, n_expected):
    """Centros (x, y), Ø y z de cada cilindro (componente conexa de la malla) de una STL de imanes."""
    v = np.round(tris.reshape(-1, 3), 4)
    _, inv = np.unique(v, axis=0, return_inverse=True)
    inv = inv.ravel()
    parent = np.arange(inv.max() + 1)

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a
    for t in inv.reshape(-1, 3):
        ra, rb, rc = find(t[0]), find(t[1]), find(t[2])
        parent[rb] = ra
        parent[find(rc)] = ra
    roots = np.array([find(i) for i in inv])
    res = []
    P = tris.reshape(-1, 3)
    for r in np.unique(roots):
        g = P[roots == r]
        res.append(dict(x=(g[:, 0].min() + g[:, 0].max()) / 2, y=(g[:, 1].min() + g[:, 1].max()) / 2,
                        d=g[:, 0].max() - g[:, 0].min(), z0=g[:, 2].min(), z1=g[:, 2].max()))
    res.sort(key=lambda r: (r["x"], r["y"]))
    if len(res) != n_expected:
        out("  AVISO: %d cilindros encontrados (esperados %d)" % (len(res), n_expected))
    return res


# ============================================================================================ principal
def main():
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from scipy import ndimage

    sec("0. ENTRADAS")
    import subprocess
    try:
        head = subprocess.run(["git", "-C", REPO, "rev-parse", "--short", "HEAD"], capture_output=True, text=True).stdout.strip()
        br = subprocess.run(["git", "-C", REPO, "rev-parse", "--abbrev-ref", "HEAD"], capture_output=True, text=True).stdout.strip()
    except Exception:
        head, br = "?", "?"
    out("Repositorio: %s  (rama %s, HEAD %s)" % (REPO, br, head))
    rd = open(os.path.join(REPO, "hardware", "girth", "REV5", "README.md"), encoding="utf-8").read()
    mver = re.search(r"\*\*REV (5\.\d+(?:\.\d+)?) \(actual\)", rd)
    out("CAD de la cápsula: hardware/girth/REV5 — README marca como actual: REV %s" % (mver.group(1) if mver else "?"))
    out("PCB: diseño REV %s (%s), espesor THICK = %.2f mm" % (D.REV, D.DATE, D.THICK))

    # ---------------------------------------------------------------------------------- 1. contorno
    sec("1. CONTORNO DE LA PLACA (KiCad Edge.Cuts y Gerber Edge_Cuts, independientes del .py)")
    kc = read_kicad(KICAD_PCB)
    loops = sorted(kc["edge_loops"], key=lambda p: -abs(poly_area(p)))
    outer, holes = loops[0], loops[1:]
    out("KiCad: %d lazos en Edge.Cuts; exterior %d puntos, área %.1f mm²; huecos internos: %d" %
        (len(loops), len(outer), abs(poly_area(outer)), len(holes)))
    bx0, by0 = outer.min(0)
    bx1, by1 = outer.max(0)
    out("KiCad: caja del contorno X %.3f…%.3f, Y %.3f…%.3f → %.3f × %.3f mm (eje); espesor en <general>: %.2f mm"
        % (bx0, bx1, by0, by1, bx1 - bx0, by1 - by0, kc["thickness"]))
    for h in holes:
        hx0, hy0 = h.min(0)
        hx1, hy1 = h.max(0)
        out("KiCad: hueco interno (ranura) X %.2f…%.2f, Y %.2f…%.2f → centro (%.2f; %.2f), %.2f × %.2f"
            % (hx0, hx1, hy0, hy1, (hx0 + hx1) / 2, (hy0 + hy1) / 2, hx1 - hx0, hy1 - hy0))
    notch_arcs = [(c, r) for c, r in kc["arcs"] if abs(r - D.NOTCH_R) < 0.05]
    corner_arcs = [(c, r) for c, r in kc["arcs"] if abs(r - D.PR) < 0.05]
    out("KiCad: %d arcos de muesca R %s; %d esquinas R %s" %
        (len(notch_arcs), sorted({round(r, 3) for _, r in notch_arcs}), len(corner_arcs),
         sorted({round(r, 3) for _, r in corner_arcs})))

    z = zipfile.ZipFile(GERBER_ZIP)
    gname = {n.split("-")[-1].split(".")[0]: n for n in z.namelist()}
    gtxt = z.read(next(n for n in z.namelist() if "Edge_Cuts" in n)).decode()
    gp, _ = gerber_paths(gtxt)
    gloops = sorted(chain(gp, tol=2e-3), key=lambda p: -abs(poly_area(p)))
    gouter = gloops[0]
    gx0, gy0 = gouter.min(0)
    gx1, gy1 = gouter.max(0)
    out("Gerber: %d lazos; exterior X %.3f…%.3f, Y %.3f…%.3f → %.3f × %.3f mm; área %.1f mm²"
        % (len(gloops), gx0, gx1, gy0, gy1, gx1 - gx0, gy1 - gy0, abs(poly_area(gouter))))
    job = json.loads(z.read(next(n for n in z.namelist() if n.endswith(".gbrjob"))))
    gs = job["GeneralSpecs"]
    out("Gerber job: Size %.2f × %.2f (incluye el ancho de línea 0,1), capas %d, espesor %.2f, acabado %s, Revision «%s»"
        % (gs["Size"]["X"], gs["Size"]["Y"], gs["LayerNumber"], gs["BoardThickness"], gs.get("Finish"),
           gs["ProjectId"].get("Revision")))
    dpts = np.array(D.outline_pts(2))
    h1 = dist_segs(outer, poly_segs(gouter)).max()
    h2 = dist_segs(gouter, poly_segs(outer)).max()
    h3 = dist_segs(dpts, poly_segs(outer)).max()
    out("Desviación máxima KiCad↔Gerber: %.4f / %.4f mm; .py (outline_pts) → KiCad: %.4f mm" % (h1, h2, h3))
    out("Nominal del .py: %.2f × %.2f, R%.2f, muescas R%.2f, ranura %s" % (D.PL, D.PW, D.PR, D.NOTCH_R, D.SLOT))
    OUTLINE = outer
    SLOT_POLY = holes[0] if holes else None

    # posiciones de huellas: KiCad vs .py
    mism = []
    for p in D.PARTS:
        f = kc["fps"].get(p["ref"])
        if f is None:
            mism.append("%s falta en KiCad" % p["ref"])
            continue
        if math.hypot(f["X"] - p["pos"][0], f["Y"] - p["pos"][1]) > 0.01 or abs((f["rot"] - p["rot"]) % 360) > 0.01:
            mism.append("%s: KiCad (%.2f; %.2f; %g°) ≠ .py (%.2f; %.2f; %g°)" % (p["ref"], f["X"], f["Y"], f["rot"],
                                                                              p["pos"][0], p["pos"][1], p["rot"]))
    bottom = [r for r, f in kc["fps"].items() if f["layer"] != "F.Cu"]
    out("Huellas en KiCad: %d (todas en la cara %s); diferencias de posición/giro KiCad↔.py: %s"
        % (len(kc["fps"]), "F.Cu" if not bottom else "F.Cu y B.Cu: " + ", ".join(bottom),
           "ninguna" if not mism else "; ".join(mism)))

    # ---------------------------------------------------------------------------------- 2. STL
    sec("2. CAD DE LA CÁPSULA (STL de out/montaje y out/ref_*)")
    M = {}
    for n in ("base", "tapa", "junta_TPU", "bandeja", "aro_rojo"):
        M[n] = load_stl(os.path.join(CAD_DIR, "montaje", "AVO_GIRTH_R5_%s.stl" % n))
    for n in ("bateria_LP403048", "bobina_Qi", "antena_FPC", "reed", "imanes_capsula_5x1", "imanes_soporte_5x1",
              "imanes", "placa_Qi", "ESP32_C6", "BNO085"):
        M["ref_" + n] = load_stl(os.path.join(CAD_DIR, "ref_%s.stl" % n))
    for n, t in M.items():
        lo, hi = bbox(t)
        out("  %-24s %6d triángulos  X %7.2f…%6.2f  Y %7.2f…%6.2f  Z %6.2f…%6.2f" % (n, len(t), lo[0], hi[0], lo[1], hi[1], lo[2], hi[2]))
    base, lid = M["base"], M["tapa"]

    # rejilla sobre la placa
    STEP = 0.2
    xs = np.arange(-36.6, 36.6 + 1e-9, STEP)
    ys = np.arange(-25.6, 25.6 + 1e-9, STEP)
    GX, GY = np.meshgrid(xs, ys)
    GP = np.stack([GX.ravel(), GY.ravel()], 1)
    in_board = inside_segs(GP, poly_segs(OUTLINE)).reshape(GX.shape)
    if SLOT_POLY is not None:
        in_board &= ~inside_segs(GP, poly_segs(SLOT_POLY)).reshape(GX.shape)
    base_min, base_top = zmap(base, xs, ys)
    lid_bot, lid_max = zmap(lid, xs, ys)
    tray_bot, tray_top = zmap(M["bandeja"], xs, ys)

    # alturas clave medidas
    def zhits(mesh, x, y):
        return ray_hits(mesh, (x, y, -50), (0, 0, 1)) - 50

    cradle_pts = [(0.0, 15.95), (0.0, -15.95), (-26.1, 0.0 - 10), (26.1, 5.0)]
    cradle_top = max(zhits(base, x, y).max() for x, y in cradle_pts)
    bat_lo, bat_hi = bbox(M["ref_bateria_LP403048"])
    ceil_pts = [(5.0, 5.0), (-10.0, 8.0), (10.0, -5.0)]
    ceil = min(zhits(lid, x, y).min() for x, y in ceil_pts)
    lip_z = zhits(lid, 0.0, 25.5 - 4.35).min()          # banda del labio (entre 3,75 y 4,95 del borde exterior)
    wall_top = zhits(base, 0.0, 25.5 - 1.0).max()       # pared de la base junto al borde
    lid_wall_bot = zhits(lid, 0.0, 25.5 - 3.0).min()    # cara inferior de la tapa sobre la junta
    out("")
    out("Medidas en las STL:")
    out("  techo interior de la tapa (rayo en %s): z = %.3f   [.py de la PCB: Z_CEIL = %.2f]" % (ceil_pts, ceil, D.Z_CEIL))
    out("  cara superior de la cuna de la batería (rayos en %s): z = %.3f" % (cradle_pts, cradle_top))
    out("  batería de referencia: z %.3f…%.3f (%.2f mm); X %.2f…%.2f, Y %.2f…%.2f"
        % (bat_lo[2], bat_hi[2], bat_hi[2] - bat_lo[2], bat_lo[0], bat_hi[0], bat_lo[1], bat_hi[1]))
    out("  labio de la tapa (Y = %.2f): cara inferior z = %.3f" % (25.5 - 4.35, lip_z))
    out("  pared de la base (Y = 24,5): cara superior z = %.3f; tapa sobre la junta (Y = 22,5): cara inferior z = %.3f"
        % (wall_top, lid_wall_bot))
    lo, hi = bbox(M["bandeja"])
    out("  bandeja (pieza que la PCB sustituye): z %.2f…%.2f" % (lo[2], hi[2]))

    SCEN = {
        "A": dict(name="A · como pide la PCB (cuna +0,6 → placa en z %.2f)" % D.Z_PCB_BOTTOM, zb=D.Z_PCB_BOTTOM),
        "B": dict(name="B · CAD 5.8.1 sin cambios (placa apoyada en la cuna, z %.2f)" % cradle_top, zb=cradle_top),
    }
    T = kc["thickness"]

    # ---------------------------------------------------------------------------------- 3. holgura lateral
    sec("3. HOLGURA LATERAL PLACA ↔ CAVIDAD DE LA BASE, COLUMNAS DE LOS TORNILLOS Y TAPA")
    res_lat = {}
    for key, sc in SCEN.items():
        zb = sc["zb"]
        mins = []
        for zz in (zb + 0.05, zb + T / 2, zb + T - 0.05):
            sg = slice_mesh(base, 2, zz)
            pts = OUTLINE
            dd = dist_segs(pts, sg)
            inmat = inside_segs(pts, sg)
            mins.append((zz, dd.min(), pts[dd.argmin()], inmat.sum()))
        res_lat[key] = mins
        out(sc["name"])
        for zz, dmin, p, nin in mins:
            out("  corte de la base a z %.2f: holgura mínima contorno↔base %.3f mm en (%.2f; %.2f); puntos del contorno dentro de material: %d"
                % (zz, dmin, p[0], p[1], nin))
    # holgura a lo largo del contorno, por tramos
    zb = SCEN["A"]["zb"]
    sg = slice_mesh(base, 2, zb + T / 2)
    dd = dist_segs(OUTLINE, sg)
    rect_sides = {"lado +X (x = 32,75)": np.abs(OUTLINE[:, 0] - 32.75) < 0.01,
                  "lado −X": np.abs(OUTLINE[:, 0] + 32.75) < 0.01,
                  "lado +Y (y = 21,75)": np.abs(OUTLINE[:, 1] - 21.75) < 0.01,
                  "lado −Y": np.abs(OUTLINE[:, 1] + 21.75) < 0.01}
    for k, m in rect_sides.items():
        if m.any():
            out("  [A] %s: holgura a la pared interior %.3f…%.3f mm" % (k, dd[m].min(), dd[m].max()))
    # columnas de los tornillos (corte de la base) y columnas de la tapa
    out("")
    out("Muescas de la placa (KiCad) frente a las columnas M3 de la base (corte a z %.2f) y de la tapa (corte a z 11,0):" % (zb + T / 2))
    sgL = slice_mesh(lid, 2, 11.0)
    notch_rows = []
    for (c, r) in sorted(notch_arcs, key=lambda a: (a[0][0], a[0][1])):
        # columna de la base: puntos del corte a < 4 mm del centro de la muesca
        u = -np.array(c) / np.hypot(*c)                  # hacia el interior de la cápsula
        P = np.concatenate([sg[:, :2], sg[:, 2:]])
        rP = np.hypot(P[:, 0] - c[0], P[:, 1] - c[1])
        fac = ((P - np.array(c)) @ u) / np.maximum(rP, 1e-9)
        q = P[(rP > 2.0) & (rP < 3.5) & (fac > 0.6)]       # cara exterior de la columna (sin el taladro Ø3,4 ni la pared)
        cxb, cyb, rb = fit_circle(q)
        PL_ = np.concatenate([sgL[:, :2], sgL[:, 2:]])
        rL = np.hypot(PL_[:, 0] - c[0], PL_[:, 1] - c[1])
        facL = ((PL_ - np.array(c)) @ u) / np.maximum(rL, 1e-9)
        q2 = PL_[(rL > 2.5) & (rL < 3.8) & (facL > 0.6)]
        cxl, cyl, rl = fit_circle(q2)
        gb = r - rb - math.hypot(cxb - c[0], cyb - c[1])
        gl = r - rl - math.hypot(cxl - c[0], cyl - c[1])
        notch_rows.append((c, r, (cxb, cyb, rb), (cxl, cyl, rl), gb, gl))
        out("  muesca (%6.2f; %6.2f) R%.2f | columna base (%6.2f; %6.2f) Ø%.2f → holgura radial %.2f | columna tapa (%6.2f; %6.2f) Ø%.2f → %.2f"
            % (c[0], c[1], r, cxb, cyb, 2 * rb, gb, cxl, cyl, 2 * rl, gl))
    zl_boss = []
    for c, _ in notch_arcs:
        u = -np.array(c) / np.hypot(*c)                 # hacia el centro de la cápsula
        zl_boss.append(zhits(lid, c[0] + 3.2 * u[0], c[1] + 3.2 * u[1]).min())
    zl_boss = min(zl_boss)
    out("  cara inferior de las columnas Ø7 de la tapa (rayo a 3,2 del eje, hacia el interior): z = %.3f" % zl_boss)

    # ---------------------------------------------------------------------------------- 4. vertical
    sec("4. APILADO VERTICAL Y COMPONENTES BAJO LA TAPA")
    h_of = {p["ref"]: D.FP[p["fp"]].height for p in D.PARTS}
    fp_of = {p["ref"]: p["fp"] for p in D.PARTS}
    out("Alturas de huella usadas (FP[*].height del .py): USB-C %.2f, ESP32-C3-MINI-1U %.2f, JST SH %.2f, C1206 %.2f, SOT-23-5/6 %.2f"
        % (D.FP["USBC"].height, D.FP["MINI1U"].height, D.FP["JST_SH2"].height, D.FP["C1206"].height, D.FP["SOT23-5"].height))
    for key, sc in SCEN.items():
        zb = sc["zb"]
        zt = zb + T
        out("")
        out(sc["name"])
        out("  suelo z %.2f · batería %.2f…%.2f · cuna (CAD) %.2f · placa %.2f…%.2f · techo %.2f → libre sobre la placa %.2f mm (H_MAX del .py %.2f)"
            % (2.6, bat_lo[2], bat_hi[2], cradle_top, zb, zt, ceil, ceil - zt, D.H_MAX))
        out("  hueco batería ↔ cara inferior de la placa: %.2f mm" % (zb - bat_hi[2]))
        under = np.where(in_board, base_top, np.nan)
        inter = np.nanmax(under) - zb
        out("  base bajo la placa: z máx. %.3f → %s" % (np.nanmax(under), "INTERFERENCIA %.2f mm" % inter if inter > 1e-3 else
                                                           "apoyo / holgura %.2f mm" % (-inter)))
        gap = np.where(in_board, lid_bot - zt, np.nan)
        neg = in_board & (lid_bot - zt < -1e-3)
        out("  tapa sobre la placa (sin componentes): hueco mínimo %.3f mm; superficie con la tapa DENTRO de la placa: %.1f mm²"
            % (np.nanmin(gap), neg.sum() * STEP * STEP))
        if neg.any():
            out("     zona: X %.2f…%.2f, Y %.2f…%.2f (labio de la tapa, z %.2f)"
                % (GX[neg].min(), GX[neg].max(), GY[neg].min(), GY[neg].max(), np.nanmin(lid_bot[neg])))
        rows = []
        for ref, f in kc["fps"].items():
            if f["crt"] is None:
                continue
            x0, y0, x1, y1 = f["crt"]
            m = (GX >= x0) & (GX <= x1) & (GY >= y0) & (GY <= y1)
            lb = lid_bot[m].min() if m.any() else np.inf
            h = h_of.get(ref, 0.0)
            rows.append((lb - zt - h, ref, h, lb, f))
        rows.sort()
        sc["rows"] = rows
        bad = [r for r in rows if r[0] < 0]
        out("  componentes cuyo patio (courtyard) choca con la tapa: %d" % len(bad))
        for mg, ref, h, lb, f in bad:
            body = ""
            if f["fab"] is not None:
                x0, y0, x1, y1 = f["fab"]
                m = (GX >= x0) & (GX <= x1) & (GY >= y0) & (GY <= y1)
                lbb = lid_bot[m].min() if m.any() else np.inf
                body = "; con el cuerpo (F.Fab %.1f × %.1f): %s" % (x1 - x0, y1 - y0, "INTERFERENCIA %.2f" % (zt + h - lbb)
                                                                    if lbb < zt + h else "libre (margen %.2f)" % (lbb - zt - h))
            out("     %-5s %-22s h %.2f  cima z %.2f  tapa z %.2f  → INTERFERENCIA %.2f mm (patio)%s"
                % (ref, fp_of.get(ref, f["name"]), h, zt + h, lb, -mg, body))
        ok = [r for r in rows if r[0] >= 0][:6]
        out("  los 6 márgenes positivos más pequeños:")
        for mg, ref, h, lb, f in ok:
            out("     %-5s %-22s h %.2f  cima z %.2f  tapa z %.2f  → margen %.2f mm" % (ref, fp_of.get(ref, f["name"]), h, zt + h, lb, mg))
        tall = sorted(((h_of.get(r, 0), r) for r in kc["fps"]), reverse=True)[:4]
        out("  los más altos: " + ", ".join("%s %.2f (cima z %.2f, techo %.2f → %.2f)" % (r, h, zt + h, ceil, ceil - zt - h) for h, r in tall))

    # elementos de la tapa que bajan por debajo del techo (postes, tope del USB, columnas)
    out("")
    out("Elementos interiores de la tapa que bajan del techo (rejilla 0,2 mm, z inferior < techo − 0,5, dentro de la placa):")
    feat = in_board & (lid_bot < ceil - 0.5) & np.isfinite(lid_bot)
    lab, nl = ndimage.label(feat)
    feats = []
    for k in range(1, nl + 1):
        m = lab == k
        a = m.sum() * STEP * STEP
        cx, cy = GX[m].mean(), GY[m].mean()
        feats.append(dict(cx=cx, cy=cy, area=a, zmin=lid_bot[m].min(), x0=GX[m].min(), x1=GX[m].max(),
                          y0=GY[m].min(), y1=GY[m].max(), mask=m))
    feats.sort(key=lambda f: (round(f["cy"], 0), f["cx"]))
    for f in feats:
        hits = []
        for key, sc in SCEN.items():
            zt = sc["zb"] + T
            for ref, fp in kc["fps"].items():
                if fp["crt"] is None:
                    continue
                x0, y0, x1, y1 = fp["crt"]
                mm = f["mask"] & (GX >= x0) & (GX <= x1) & (GY >= y0) & (GY <= y1)
                if mm.any() and lid_bot[mm].min() < zt + h_of.get(ref, 0) - 1e-3:
                    hits.append("%s:%s" % (key, ref))
        kind = ("labio" if f["zmin"] < 8.6 else "columna M3" if f["zmin"] < 9.1 else
                "tope USB C6" if f["zmin"] > 11 else "poste")
        f["kind"] = kind
        out("  %-11s centro (%6.2f; %6.2f)  X %6.2f…%6.2f  Y %6.2f…%6.2f  área %6.1f mm²  z inf. %.2f  hueco a la placa A %.2f / B %.2f  choca con: %s"
            % (kind, f["cx"], f["cy"], f["x0"], f["x1"], f["y0"], f["y1"], f["area"], f["zmin"],
               f["zmin"] - (SCEN["A"]["zb"] + T), f["zmin"] - (SCEN["B"]["zb"] + T), ", ".join(hits) if hits else "nada"))

    # bandeja: ocupa el volumen de la placa
    tb = np.where(in_board & np.isfinite(tray_top), tray_top, np.nan)
    out("")
    out("Bandeja 5.8.1 dentro de la huella de la placa: z %.2f…%.2f, %.0f mm² de solape en planta → con la PCB hay que quitarla del conjunto"
        % (np.nanmin(np.where(in_board, tray_bot, np.nan)), np.nanmax(tb), np.isfinite(tb).sum() * STEP * STEP))

    # ---------------------------------------------------------------------------------- 5. patas del USB y J1
    sec("5. USB-C (J1): POSICIÓN, PATAS BAJO LA PLACA Y ACCESO")
    j1 = kc["fps"]["J1"]
    out("J1 en KiCad: (%.2f; %.2f), giro %g°" % (j1["X"], j1["Y"], j1["rot"]))
    fab = np.array(j1["fab_local"])
    ymax_local = fab[:, 1].max()
    mx, _ = rot_local(0, ymax_local, j1["rot"])
    mouth_X = j1["X"] + mx
    out("Boca del receptáculo (línea F.Fab local y = %.2f): X = %.2f → %.2f mm del borde de la placa (X %.2f)"
        % (ymax_local, mouth_X, bx1 - mouth_X, bx1))
    legs = [p for p in j1["pads"] if p["kind"] in ("thru_hole", "np_thru_hole")]
    for key, sc in SCEN.items():
        zb = sc["zb"]
        out(sc["name"])
        for p in legs:
            r = 1.0
            m = (np.hypot(GX - p["X"], GY - p["Y"]) < r)
            below = np.nanmax(np.where(m & np.isfinite(base_top), base_top, -np.inf))
            bat_under = (bat_lo[0] <= p["X"] <= bat_hi[0]) and (bat_lo[1] <= p["Y"] <= bat_hi[1])
            floor_z = max(below, bat_hi[2] if bat_under else -np.inf)
            out("  pata %-3s %-12s (%6.2f; %6.2f): lo más alto debajo (r 1 mm) z %.2f (%s) → profundidad libre bajo la placa %.2f mm"
                % (p["num"] or "NPTH", p["kind"], p["X"], p["Y"], floor_z, "batería" if bat_under and bat_hi[2] >= below else "base",
                   zb - floor_z))
    out("  Longitud de las patas bajo la placa: NO VERIFICADO (no hay modelo 3D del TYPE-C-31-M-12 en el repositorio ni en el STEP de la placa).")
    # abertura en la cápsula
    for key, sc in SCEN.items():
        zax = sc["zb"] + T + D.FP["USBC"].height / 2
        tb_ = ray_hits(base, (mouth_X, 0.0, zax), (1, 0, 0))
        tl_ = ray_hits(lid, (mouth_X, 0.0, zax), (1, 0, 0))
        hits = sorted([("base", t) for t in tb_] + [("tapa", t) for t in tl_], key=lambda a: a[1])
        first = hits[0] if hits else None
        exits = [(n, t) for n, t in hits]
        out("  %s: eje del USB z ≈ %.2f; rayo +X desde la boca: primer material %s a %.2f mm (X %.2f); total de caras atravesadas %d → %s"
            % (key, zax, first[0] if first else "-", first[1] if first else float("nan"),
               mouth_X + first[1] if first else float("nan"), len(exits),
               "SIN ABERTURA en la cápsula" if len(exits) >= 2 else "ABERTURA"))
    for key, sc in SCEN.items():
        zt = sc["zb"] + T
        zax = zt + D.FP["USBC"].height / 2
        out("  %s (tapa quitada): pared de la base z %.2f; eje del USB z %.2f → %.2f mm por encima de la pared; boca a %.2f mm de la cara interior (X %.2f) y a %.2f de la exterior (X 36,50)"
            % (key, wall_top, zax, zax - wall_top, 32.9 - mouth_X, 32.9, 36.5 - mouth_X))
    # tope antiguo del USB en la tapa
    out("  Tope de la tapa para el USB del C6 (REV 5.8.1): ver «tope USB C6» de la sección 4 (ya no hay conector ahí).")

    # ---------------------------------------------------------------------------------- 6. ranura y cables
    sec("6. CABLE DE LA BATERÍA (RANURA), HILOS DE LA BOBINA (L1/L2) Y DEL REED (SW1/SW2)")
    sgc = slice_mesh(base, 2, 5.0)
    out("Huecos de la pared de la cuna (corte de la base a z 5,0):")
    for nm, line in (("pared −X (x = −26,1)", [(-26.1, y) for y in np.arange(-16.4, 16.41, 0.05)]),
                     ("pared +X (x = +26,1)", [(26.1, y) for y in np.arange(-16.4, 16.41, 0.05)]),
                     ("pared +Y (y = +15,95)", [(x, 15.95) for x in np.arange(-26.5, 26.51, 0.05)]),
                     ("pared −Y (y = −15,95)", [(x, -15.95) for x in np.arange(-26.5, 26.51, 0.05)])):
        line = np.array(line)
        mat = inside_segs(line, sgc)
        gaps = runs(~mat, line)
        out("  %-24s huecos: %s" % (nm, ", ".join("%s %.2f…%.2f" % ("Y" if "X" in nm else "X", a, b) for a, b in gaps) or "ninguno"))
    if SLOT_POLY is not None:
        sx0, sy0 = SLOT_POLY.min(0)
        sx1, sy1 = SLOT_POLY.max(0)
        scx, scy = (sx0 + sx1) / 2, (sy0 + sy1) / 2
        m = in_board.copy()
        mm = (GX >= sx0) & (GX <= sx1) & (GY >= sy0) & (GY <= sy1)
        out("Ranura de la placa: centro (%.2f; %.2f), %.2f × %.2f mm. Debajo (base) z máx. %.2f; batería X ≥ %.2f"
            % (scx, scy, sx1 - sx0, sy1 - sy0, np.nanmax(np.where(mm, base_top, -np.inf)), bat_lo[0]))
        for yy in (sy0, scy, sy1, 8.0, 10.0, 11.5, 14.5):
            line = np.array([(x, yy) for x in np.arange(-26.65, -34.0, -0.02)])
            mat = inside_segs(line, sgc)
            xm = line[np.argmax(mat), 0] if mat.any() else float("nan")
            out("  pasillo junto a la cara exterior de la cuna (X −26,6) a Y %5.2f (z 5): libre hasta X %.2f → %.2f mm"
                % (yy, xm, -26.6 - xm))
        dmin_edge = dist_segs(SLOT_POLY, poly_segs(OUTLINE)).min()
        out("  distancia ranura ↔ borde de la placa: %.2f mm; J2 en KiCad (%.2f; %.2f) a %.2f mm del centro de la ranura"
            % (dmin_edge, kc["fps"]["J2"]["X"], kc["fps"]["J2"]["Y"], math.hypot(kc["fps"]["J2"]["X"] - scx, kc["fps"]["J2"]["Y"] - scy)))
    # bobina
    clo, chi = bbox(M["ref_bobina_Qi"])
    ccx, ccy, cr = (clo[0] + chi[0]) / 2, (clo[1] + chi[1]) / 2, (chi[0] - clo[0]) / 2
    out("Bobina Qi (ref): centro (%.2f; %.2f), Ø%.2f, z %.2f…%.2f" % (ccx, ccy, 2 * cr, clo[2], chi[2]))
    sgw = slice_mesh(base, 2, 2.0)
    line = np.array([(-20.0, y) for y in np.arange(-10, 0.01, 0.05)])
    gaps = runs(~inside_segs(line, sgw), line)
    out("  canal de los hilos en el suelo (corte z 2,0 en X −20): Y " + ", ".join("%.2f…%.2f" % g for g in gaps))
    line = np.array([(x, -5.0) for x in np.arange(-10.0, -34.0, -0.05)])
    gaps = runs(~inside_segs(line, sgw), line)
    out("  canal a lo largo de X (Y −5, z 2,0): X " + ", ".join("%.2f…%.2f" % g for g in gaps))
    for ref in ("L1", "L2"):
        f = kc["fps"][ref]
        pz = zhits(base, f["X"], f["Y"])
        out("  %s (%.2f; %.2f): %.2f mm del borde de la bobina; base debajo z máx. %.2f (camino libre hasta la placa)"
            % (ref, f["X"], f["Y"], math.hypot(f["X"] - ccx, f["Y"] - ccy) - cr, pz.max() if len(pz) else float("nan")))
    over = [r for r, f in kc["fps"].items() if math.hypot(f["X"] - ccx, f["Y"] - ccy) < cr]
    out("  piezas de la placa sobre la bobina (centro a < %.1f mm del eje): %s" % (cr, ", ".join(sorted(over))))
    out("  entre la bobina y la placa: batería (z %.2f…%.2f, %.2f mm por encima de la bobina)" % (bat_lo[2], bat_hi[2], bat_lo[2] - chi[2]))
    # reed
    rlo, rhi = bbox(M["ref_reed"])
    rcx, rcy = (rlo[0] + rhi[0]) / 2, (rlo[1] + rhi[1]) / 2
    out("Reed (ref): X %.2f…%.2f, Y %.2f…%.2f, z %.2f…%.2f (centro (%.2f; %.2f))" % (rlo[0], rhi[0], rlo[1], rhi[1], rlo[2], rhi[2], rcx, rcy))
    for ref in ("SW1", "SW2"):
        f = kc["fps"][ref]
        pz = zhits(base, f["X"], f["Y"])
        endx = rlo[0] if f["X"] < 0 else rhi[0]
        d3 = math.dist((endx, rcy, (rlo[2] + rhi[2]) / 2), (f["X"], f["Y"], SCEN["A"]["zb"]))
        out("  %s (%.2f; %.2f): sobre el cuerpo del reed (Y %.2f…%.2f): %s; base debajo z máx. %.2f; extremo del reed (X %.2f) → pad: %.1f mm en línea recta (A)"
            % (ref, f["X"], f["Y"], rlo[1], rhi[1], "sí" if rlo[1] <= f["Y"] <= rhi[1] else "no",
               pz.max() if len(pz) else float("nan"), endx, d3))
    sgr = slice_mesh(base, 2, 2.0)
    line = np.array([(x, rcy) for x in np.arange(-15, 15.01, 0.05)])
    out("  alojamiento del reed en el suelo (corte z 2,0, Y %.2f): hueco X %s" % (rcy, ", ".join("%.2f…%.2f" % g for g in runs(~inside_segs(line, sgr), line))))
    line = np.array([(0.0, y) for y in np.arange(-16.5, -22.5, -0.05)])
    out("  entre la cuna y la pared −Y (corte z 5, X 0): hueco Y %s" % ", ".join("%.2f…%.2f" % g for g in runs(~inside_segs(line, sgc), line)))

    # ---------------------------------------------------------------------------------- 7. antena
    sec("7. ANTENA FPC Y BANDA SIN COBRE")
    alo, ahi = bbox(M["ref_antena_FPC"])
    ko = kc["zones"]["ANTENA_SIN_COBRE"]
    kx0, ky0 = ko.min(0)
    kx1, ky1 = ko.max(0)
    out("Banda sin cobre (zona de KiCad ANTENA_SIN_COBRE): X %.2f…%.2f, Y %.2f…%.2f [.py ANT_KEEPOUT %s]" % (kx0, kx1, ky0, ky1, D.ANT_KEEPOUT))
    out("  reglas de la zona en KiCad: pistas/vías/rellenos prohibidos; pads y huellas PERMITIDOS")
    ox = max(0, min(ahi[0], kx1) - max(alo[0], kx0))
    oy = max(0, min(ahi[1], ky1) - max(alo[1], ky0))
    out("Antena FPC en el CAD 5.8.1 (ref): X %.2f…%.2f, Y %.2f…%.2f, z %.2f…%.2f (%.1f × %.1f × %.2f) → solape con la banda: %.1f mm²"
        % (alo[0], ahi[0], alo[1], ahi[1], alo[2], ahi[2], ahi[0] - alo[0], ahi[1] - alo[1], ahi[2] - alo[2], ox * oy))
    m = (GX >= alo[0]) & (GX <= ahi[0]) & (GY >= alo[1]) & (GY <= ahi[1])
    under_refs = [r for r, f in kc["fps"].items() if alo[0] <= f["X"] <= ahi[0] and alo[1] <= f["Y"] <= ahi[1]]
    out("  piezas de la placa bajo la antena en su sitio actual: %s" % ", ".join(sorted(under_refs)))
    # cobre dentro de la banda (Gerber)
    rect = (kx0 + 0.05, ky0 + 0.05, kx1 - 0.05, min(ky1, by1) - 0.05)
    for lay in ("F_Cu", "In1_Cu", "In2_Cu", "B_Cu"):
        nm = next(n for n in z.namelist() if lay in n)
        paths, flashes = gerber_paths(z.read(nm).decode())
        nseg = sum(1 for pl in paths for a, b in zip(pl[:-1], pl[1:]) if seg_rect_hit(a, b, rect))
        nfl = [f for f in flashes if rect[0] <= f[0] <= rect[2] and rect[1] <= f[1] <= rect[3]]
        out("  Gerber %-6s (%d trazos, %d destellos leídos): trazos que cruzan la banda (reducida 0,05) %d; destellos dentro %d %s"
            % (lay, len(paths), len(flashes), nseg, len(nfl), ("en " + ", ".join("(%.2f; %.2f)" % f for f in nfl[:6])) if nfl else ""))
    pads_in = [(r, p["num"]) for r, f in kc["fps"].items() for p in f["pads"]
               if rect[0] <= p["X"] <= rect[2] and rect[1] <= p["Y"] <= rect[3]]
    out("  pads de huellas dentro de la banda (KiCad): %s" % (pads_in or "ninguno"))
    # ¿cabe la FPC pegada al techo sobre la banda?
    aw, ah = ahi[0] - alo[0], ahi[1] - alo[1]
    flat = np.isfinite(lid_bot) & (lid_bot >= ceil - 0.05)
    best = None
    for y0 in np.arange(ky0, 25.0 - ah, 0.2):
        for x0 in np.arange(kx0, kx1 - aw + 1e-6, 0.1):
            mm = (GX >= x0) & (GX <= x0 + aw) & (GY >= y0) & (GY <= y0 + ah)
            bad = (mm & ~flat).sum()
            if best is None or bad < best[0]:
                best = (bad, x0, y0)
    out("  FPC de %.1f × %.1f pegada al techo dentro de la banda: mejor posición X0 %.2f, Y0 %.2f con %.1f mm² de techo NO plano (postes/columnas/pared)"
        % (aw, ah, best[1], best[2], best[0] * STEP * STEP))
    x0, y0 = best[1], best[2]
    rr = (GX >= x0) & (GX <= x0 + aw) & (GY >= y0) & (GY <= y0 + ah) & ~flat
    for f in feats:
        mm = f["mask"] & rr
        if mm.any():
            out("     invade: %s en (%.2f; %.2f) — %.1f mm²" % (f["kind"], f["cx"], f["cy"], mm.sum() * STEP * STEP))
    for c, r, cb_, cl_, gb_, gl_ in notch_rows:
        mm = rr & (np.hypot(GX - cl_[0], GY - cl_[1]) <= cl_[2] + 0.2)
        if mm.any():
            out("     invade: columna Ø%.1f del inserto M3 de la tapa en (%.2f; %.2f) — %.1f mm²" % (2 * cl_[2], cl_[0], cl_[1], mm.sum() * STEP * STEP))
    # posición alternativa: FPC desplazada hasta no tocar nada (la banda limita X); se busca en Y sin la banda
    alt = None
    for y0b in np.arange(ky0, 20.6 - ah + 1e-6, 0.1):
        for x0b in np.arange(-31.0, 31.0 - aw, 0.2):
            mm = (GX >= x0b) & (GX <= x0b + aw) & (GY >= y0b) & (GY <= y0b + ah)
            if not (mm & ~flat).any():
                ovl = max(0, min(x0b + aw, kx1) - max(x0b, kx0)) * max(0, min(y0b + ah, ky1) - max(y0b, ky0))
                if alt is None or ovl > alt[0]:
                    alt = (ovl, x0b, y0b)
    if alt:
        out("  sin quitar postes: la FPC solo cabe en techo plano con Y0 ≥ %.2f en X0 %.2f (solape con la banda %.1f de %.1f mm²)"
            % (alt[2], alt[1], alt[0], aw * ah))
    else:
        out("  sin quitar postes ni columnas: no hay ninguna posición con Y ≥ %.2f donde la FPC de %.1f × %.1f quede en techo plano" % (ky0, aw, ah))
    lid_wall_y = None
    sg11 = slice_mesh(lid, 2, 12.5)
    line = np.array([(10.0, y) for y in np.arange(12.0, 25.6, 0.02)])
    mat = inside_segs(line, sg11)
    if mat.any():
        lid_wall_y = line[np.argmax(mat), 1]
    out("  pared interior de la tapa en X 10 (z 12,5): Y %.2f → la banda (hasta Y %.2f) llega %.2f mm más allá de la pared"
        % (lid_wall_y, ky1, ky1 - lid_wall_y))
    out("  hueco antena ↔ cara superior de la placa (A): %.2f mm (techo %.2f − FPC %.2f − placa %.2f)"
        % (ceil - (ahi[2] - alo[2]) - (SCEN["A"]["zb"] + T), ceil, ahi[2] - alo[2], SCEN["A"]["zb"] + T))
    out("  Conector W.FL/MHF III del módulo: posición NO VERIFICADA (no hay dato de posición en la huella; el STEP del módulo es un ensamblaje sin resolver).")

    # ---------------------------------------------------------------------------------- 8. imanes
    sec("8. IMANES ↔ MAGNETÓMETRO U7 (MMC5983MA) Y ↔ REED")
    u7 = kc["fps"]["U7"]
    zU7 = SCEN["A"]["zb"] + T + D.FP["MMC"].height / 2
    out("U7 en KiCad (%.2f; %.2f) [diseño (-5,0; 9,6)]; centro del sensor z ≈ %.2f (A: placa + 1/2 de %.2f)" % (u7["X"], u7["Y"], zU7, D.FP["MMC"].height))
    mc = cylinders_from_stl(M["ref_imanes_capsula_5x1"], 4)
    ms = cylinders_from_stl(M["ref_imanes_soporte_5x1"], 4)
    mr = cylinders_from_stl(M["ref_imanes"], 3)
    allm = [("cápsula", c) for c in mc] + [("soporte", c) for c in ms] + [("reed", c) for c in mr]
    for grp, c in allm:
        zc = (c["z0"] + c["z1"]) / 2
        out("  imán %-8s (%6.2f; %6.2f) Ø%.2f z %.2f…%.2f → distancia a U7 %.2f mm; al reed (centro) %.2f mm"
            % (grp, c["x"], c["y"], c["d"], c["z0"], c["z1"], math.dist((c["x"], c["y"], zc), (u7["X"], u7["Y"], zU7)),
               math.dist((c["x"], c["y"], zc), (rcx, rcy, (rlo[2] + rhi[2]) / 2))))
    # modelo de dipolo (hipótesis del README de REV 5: N35; Br = 1,17–1,21 T → 1,2 T)
    Br = 1.2
    out("Estimación con dipolos (hipótesis: N35, Br = %.2f T como el README de REV 5; imanes axiales ±Z; no es una medida):" % Br)

    def field(pattern, n_caps=1):
        Btot = np.zeros(3)
        for grp, c in allm:
            t = c["z1"] - c["z0"]
            if grp == "cápsula":
                t = t * n_caps
            V = math.pi * (c["d"] / 2) ** 2 * t * 1e-9
            mmag = Br * V / MU0
            s = pattern(grp, c)
            r = np.array([u7["X"] - c["x"], u7["Y"] - c["y"], zU7 - (c["z0"] + t / 2)]) * 1e-3
            Btot += dipole_B(np.array([0, 0, s * mmag]), r)
        return Btot * 1e6       # µT

    def diag(grp, c):
        if grp == "reed":
            return 1
        return 1 if (c["x"] > 0) == (c["y"] > 0) else -1

    worst = 0.0
    for nm, pat in (("diagonales opuestas (README), reed +", diag),
                    ("diagonales opuestas, reed −", lambda g, c: -1 if g == "reed" else diag(g, c)),
                    ("todos iguales", lambda g, c: 1)):
        for n_caps in (1, 3):
            B = field(pat, n_caps)
            worst = max(worst, np.linalg.norm(B))
            out("  %-38s · %d imán(es) por esquina en la cápsula: |B| en U7 = %6.0f µT (%.2f G)" % (nm, n_caps, np.linalg.norm(B), np.linalg.norm(B) / 100))
    out("  peor caso calculado: %.0f µT = %.2f G; rango del MMC5983MA ±8 G = ±800 µT (hoja de datos, no del repositorio)" % (worst, worst / 100))
    caps_to_reed = min(math.dist((c["x"], c["y"], (c["z0"] + c["z1"]) / 2), (rcx, rcy, (rlo[2] + rhi[2]) / 2)) for c in mc)
    out("  imán de la cápsula más cercano al reed: %.2f mm" % caps_to_reed)

    # ---------------------------------------------------------------------------------- 9. sujeción
    sec("9. SUJECIÓN / VIBRACIÓN (lo que muestra el CAD)")
    for key, sc in SCEN.items():
        zb = sc["zb"]
        sup = in_board & (base_top >= zb - 0.05) & (base_top <= zb + 0.05)
        out(sc["name"])
        out("  apoyo inferior (base a ±0,05 de la cara inferior): %.1f mm² (%.1f %% de la placa)"
            % (sup.sum() * STEP * STEP, 100 * sup.sum() / in_board.sum()))
        if sup.any():
            dist = ndimage.distance_transform_edt(~sup) * STEP
            dmax = np.where(in_board, dist, 0)
            k = np.unravel_index(dmax.argmax(), dmax.shape)
            out("  distancia máxima de un punto de la placa al apoyo más cercano: %.2f mm en (%.2f; %.2f)" % (dmax[k], GX[k], GY[k]))
            corner = [(32.75 - 1.8, 21.75 - 1.8), (-32.75 + 1.8, 21.75 - 1.8)]
            for cx_, cy_ in corner:
                kk = (np.abs(ys - cy_)).argmin(), (np.abs(xs - cx_)).argmin()
                out("     voladizo en la esquina (%.2f; %.2f): %.2f mm" % (cx_, cy_, dist[kk]))
            sc["dist"] = dist
        else:
            out("  la placa NO apoya en la base con este CAD (la cuna está a %.2f, %.2f mm por debajo)" % (cradle_top, zb - cradle_top))
        zt = zb + T
        top_contact = in_board & (lid_bot - zt <= 0.1)
        out("  tapa a ≤ 0,1 mm de la cara superior: %.1f mm²; hueco del labio a la placa: %.2f mm; postes de la tapa (z %.2f): %.2f mm"
            % (top_contact.sum() * STEP * STEP, lip_z - zt, min(f["zmin"] for f in feats if f["kind"] == "poste"),
               min(f["zmin"] for f in feats if f["kind"] == "poste") - zt))
    lx = np.array([(x, 0.0) for x in np.arange(0, 30, 0.02)])
    ly = np.array([(7.0, y) for y in np.arange(0, 22, 0.02)])
    ix = lx[np.argmax(inside_segs(lx, sgc)), 0]
    iy = ly[np.argmax(inside_segs(ly, sgc)), 1]
    out("Vano sin apoyo dentro de la cuna (cara interior, corte z 5): %.2f × %.2f mm, sobre la batería (con la cuna +0,6 del escenario A el anillo de apoyo sería el mismo)" % (2 * ix, 2 * iy))
    # zonas candidatas para postes de sujeción: sobre el anillo de apoyo de la cuna, sin patios a < 1,5 mm (poste Ø2,4 + 0,3)
    sup = in_board & (base_top >= cradle_top - 0.05) & (base_top <= cradle_top + 0.05)
    occ = np.zeros_like(sup)
    for ref, f in kc["fps"].items():
        if f["crt"] is not None:
            x0, y0, x1, y1 = f["crt"]
            occ |= (GX >= x0 - 1.5) & (GX <= x1 + 1.5) & (GY >= y0 - 1.5) & (GY <= y1 + 1.5)
    occ |= (GX >= kx0 - 1.5) & (GX <= kx1 + 1.5) & (GY >= ky0 - 1.5)        # no bajo la antena
    cand = sup & ~occ
    labc, nc = ndimage.label(cand)
    out("Zonas del anillo de la cuna libres de piezas (±1,5 mm) y fuera de la banda de la antena — candidatas para postes que aprieten la placa contra la cuna:")
    for k in range(1, nc + 1):
        m = labc == k
        if m.sum() * STEP * STEP < 0.8:
            continue
        out("  centro (%6.2f; %6.2f)  X %6.2f…%6.2f  Y %6.2f…%6.2f  (%.1f mm²)" % (GX[m].mean(), GY[m].mean(), GX[m].min(), GX[m].max(),
                                                                                GY[m].min(), GY[m].max(), m.sum() * STEP * STEP))
    out("Apoyo superior: no hay ningún elemento de la tapa que apriete la placa en el CAD 5.8.1 (labio y postes con hueco, ver arriba).")

    # ---------------------------------------------------------------------------------- 10. junta
    sec("10. JUNTA TPU Y CIERRE")
    jlo, jhi = bbox(M["junta_TPU"])
    sgj = slice_mesh(M["junta_TPU"], 2, (jlo[2] + jhi[2]) / 2)
    line = np.array([(0.0, y) for y in np.arange(20.0, 25.6, 0.01)])
    gj = runs(inside_segs(line, sgj), line)
    sgb = slice_mesh(base, 2, 8.5)
    gb = runs(~inside_segs(line, sgb), line)
    out("Junta (STL de montaje, altura comprimida): z %.2f…%.2f; ancho en X 0: Y %s" % (jlo[2], jhi[2], ", ".join("%.2f…%.2f" % g for g in gj)))
    out("Ranura de la base a z 8,5 (X 0): huecos Y %s" % ", ".join("%.2f…%.2f" % g for g in gb))
    out("Cara superior de la pared de la base %.2f; cara inferior de la tapa sobre la junta %.2f → tope rígido plástico-plástico: %s"
        % (wall_top, lid_wall_bot, "sí" if abs(wall_top - lid_wall_bot) < 0.02 else "NO"))
    out("Compresión fija (README REV 5: libre 1,4, ranura 1,0): %.0f %% — solo si la tapa asienta en la base" % (100 * 0.4 / 1.4))
    for key, sc in SCEN.items():
        zt = sc["zb"] + T
        neg = in_board & (lid_bot - zt < -1e-3)
        worst_c = min(sc["rows"])[0]
        lift = max(0.0, -(np.nanmin(np.where(in_board, lid_bot - zt, np.nan))), -worst_c)
        out("  %s: la tapa quedaría levantada %.2f mm por interferencias → junta comprimida %.2f de 0,40 mm (%s)"
            % (key, lift, max(0, 0.4 - lift), "SIN SELLADO" if lift >= 0.4 else "reducida" if lift > 0 else "correcta"))

    # ---------------------------------------------------------------------------------- figuras
    plot_plan(plt, OUTLINE, SLOT_POLY, kc, GX, GY, in_board, base_top, lid_bot, feats, SCEN, ceil, T,
              (alo, ahi), (kx0, ky0, kx1, ky1), (clo, chi), (rlo, rhi), mc, ms, mr, notch_rows, best, (aw, ah), h_of)
    plot_section(plt, M, SCEN, T, kc, h_of, ceil)
    out("")
    out("Figuras: plano_planta.png, corte_vertical.png")

    with open(os.path.join(HERE, "mecanica_salida.txt"), "w", encoding="utf-8") as fh:
        fh.write("\n".join(OUT_LINES) + "\n")


def fit_circle(P):
    if len(P) < 3:
        return float("nan"), float("nan"), float("nan")
    x, y = P[:, 0], P[:, 1]
    A = np.stack([x, y, np.ones_like(x)], 1)
    b = x * x + y * y
    c = np.linalg.lstsq(A, b, rcond=None)[0]
    cx, cy = c[0] / 2, c[1] / 2
    return cx, cy, math.sqrt(c[2] + cx * cx + cy * cy)


def runs(mask, line):
    """Tramos consecutivos True de una línea muestreada → [(inicio, fin)] en la coordenada que varía."""
    axis = 0 if np.ptp(line[:, 0]) > np.ptp(line[:, 1]) else 1
    res = []
    start = None
    for i, v in enumerate(mask):
        if v and start is None:
            start = i
        if (not v or i == len(mask) - 1) and start is not None:
            end = i if v else i - 1
            a, b = line[start, axis], line[end, axis]
            res.append((min(a, b), max(a, b)))
            start = None
    return res


def plot_plan(plt, outline, slot, kc, GX, GY, in_board, base_top, lid_bot, feats, SCEN, ceil, T, ant, ko, coil, reed,
              mc, ms, mr, notch_rows, best, asz, h_of):
    from matplotlib.patches import Rectangle, Circle
    fig, ax = plt.subplots(figsize=(15, 10.5))
    zt = SCEN["A"]["zb"] + T
    gap = np.where(in_board, lid_bot - zt, np.nan)
    im = ax.pcolormesh(GX, GY, np.clip(gap, -1, 4.5), cmap="RdYlGn", vmin=-1, vmax=4.5, shading="auto", alpha=0.55)
    cb = fig.colorbar(im, ax=ax, shrink=0.7)
    cb.set_label("hueco tapa ↔ cara superior de la placa, escenario A (mm)")
    ax.plot(*np.vstack([outline, outline[:1]]).T, "k-", lw=1.4, label="contorno de la placa (KiCad)")
    if slot is not None:
        ax.plot(*np.vstack([slot, slot[:1]]).T, "k-", lw=1.2)
    for c, r, cb_, cl_, gb, gl in notch_rows:
        ax.add_patch(Circle(cb_[:2], cb_[2], fill=False, ec="tab:blue", lw=1))
        ax.add_patch(Circle(cl_[:2], cl_[2], fill=False, ec="tab:purple", lw=0.8, ls="--"))
    rows = {r[1]: r for r in SCEN["A"]["rows"]}
    for ref, f in kc["fps"].items():
        if f["crt"] is None:
            continue
        x0, y0, x1, y1 = f["crt"]
        mg = rows[ref][0] if ref in rows else 9
        col = "red" if mg < 0 else ("orange" if mg < 0.3 else "0.35")
        ax.add_patch(Rectangle((x0, y0), x1 - x0, y1 - y0, fill=False, ec=col, lw=1.6 if mg < 0 else 0.5))
        if mg < 0 or h_of.get(ref, 0) >= 2 or ref in ("U7", "L1", "L2", "SW1", "SW2", "J2", "U5"):
            ax.text((x0 + x1) / 2, (y0 + y1) / 2, ref, fontsize=7, ha="center", va="center", color=col if mg < 0 else "k")
    for f in feats:
        if f["kind"] != "labio":
            ax.text(f["cx"], f["cy"] + 1.6, "z%.2f" % f["zmin"], fontsize=6, ha="center", color="tab:purple")
    (alo, ahi) = ant
    ax.add_patch(Rectangle(alo[:2], ahi[0] - alo[0], ahi[1] - alo[1], fill=False, ec="tab:cyan", lw=2, ls=":",
                           label="antena FPC en el CAD 5.8.1"))
    kx0, ky0, kx1, ky1 = ko
    ax.add_patch(Rectangle((kx0, ky0), kx1 - kx0, ky1 - ky0, fill=False, ec="tab:blue", lw=1.5, ls="--",
                           label="banda sin cobre (KiCad)"))
    ax.add_patch(Rectangle((best[1], best[2]), asz[0], asz[1], fill=False, ec="magenta", lw=1.5,
                           label="mejor sitio para la FPC en la banda"))
    clo, chi = coil
    ax.add_patch(Circle(((clo[0] + chi[0]) / 2, (clo[1] + chi[1]) / 2), (chi[0] - clo[0]) / 2, fill=False, ec="tab:brown",
                        lw=1.2, ls="-.", label="bobina Qi (ref)"))
    rlo, rhi = reed
    ax.add_patch(Rectangle(rlo[:2], rhi[0] - rlo[0], rhi[1] - rlo[1], fill=True, fc="tab:olive", alpha=0.5, label="reed (ref)"))
    for grp, lst, col in (("cápsula", mc, "tab:red"), ("soporte", ms, "darkred"), ("reed", mr, "tab:pink")):
        for c in lst:
            ax.add_patch(Circle((c["x"], c["y"]), c["d"] / 2, fill=False, ec=col, lw=1.2))
    ax.plot([], [], "o", mfc="none", mec="tab:red", label="imanes (cápsula / soporte / reed)")
    ax.set_aspect("equal")
    ax.set_xlim(-37, 37)
    ax.set_ylim(-26, 26)
    ax.grid(alpha=0.25)
    ax.set_title("AVO GIRTH REV B en la cápsula REV 5.8.1 — planta (escenario A: placa en z %.2f). Rojo = patio que choca con la tapa"
                 % SCEN["A"]["zb"], fontsize=10)
    ax.legend(loc="lower left", fontsize=7, ncol=2)
    ax.set_xlabel("X (mm)")
    ax.set_ylabel("Y (mm)")
    fig.tight_layout()
    fig.savefig(os.path.join(HERE, "plano_planta.png"), dpi=130)
    plt.close(fig)


def plot_section(plt, M, SCEN, T, kc, h_of, ceil):
    from matplotlib.patches import Rectangle
    fig, axs = plt.subplots(2, 1, figsize=(15, 8))
    for ax, yc in zip(axs, (-9.7, 6.7)):
        for n, col in (("base", "0.3"), ("tapa", "0.55"), ("junta_TPU", "tab:green"), ("ref_bateria_LP403048", "tab:orange"),
                       ("ref_bobina_Qi", "tab:brown"), ("ref_reed", "tab:olive")):
            sg = slice_mesh(M[n], 1, yc)
            for s in sg:
                ax.plot([s[0], s[2]], [s[1], s[3]], "-", color=col, lw=0.8)
        for key, sc, col in (("A", SCEN["A"], "tab:blue"), ("B", SCEN["B"], "tab:red")):
            zb = sc["zb"]
            ax.add_patch(Rectangle((-32.75, zb), 65.5, T, fc=col, alpha=0.25, ec=col, lw=0.8))
            if key == "A":
                for ref, f in kc["fps"].items():
                    if f["crt"] is None:
                        continue
                    x0, y0, x1, y1 = f["crt"]
                    if y0 <= yc <= y1 and h_of.get(ref, 0) > 0:
                        ax.add_patch(Rectangle((x0, zb + T), x1 - x0, h_of[ref], fc="tab:blue", alpha=0.5))
                        if h_of[ref] > 1.2:
                            ax.text((x0 + x1) / 2, zb + T + h_of[ref] + 0.15, ref, fontsize=7, ha="center")
        ax.set_title("Corte Y = %.1f — gris: base/tapa; azul: placa y piezas en el escenario A; rojo: placa en el escenario B" % yc, fontsize=9)
        ax.set_aspect("equal")
        ax.set_xlim(-37, 37)
        ax.set_ylim(-0.5, 16)
        ax.grid(alpha=0.25)
        ax.set_xlabel("X (mm)")
        ax.set_ylabel("Z (mm)")
    fig.tight_layout()
    fig.savefig(os.path.join(HERE, "corte_vertical.png"), dpi=130)
    plt.close(fig)


if __name__ == "__main__":
    main()
