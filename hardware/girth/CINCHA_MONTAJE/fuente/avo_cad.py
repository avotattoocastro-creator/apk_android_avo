"""avo_cad · mini-núcleo CAD poliédrico (numpy + OpenCV) para el montaje de la cincha AVO.

Se escribió porque en el entorno de generación no hay CadQuery/OCP ni FreeCAD. Produce:
  - sólidos B-rep poliédricos cerrados (caras planas, aristas compartidas) → STEP AP214 (ADVANCED_BREP);
  - mallas estancas → STL binario;
  - comprobación de estanqueidad (cada arista orientada aparece una vez en cada sentido).

Primitivas:
  - `layered`: sólido 2,5D por capas en Z (contornos 2D que no se cruzan, regla par-impar), con capas «loft» para
    chaflanes. Es la base de todas las piezas impresas (caras grandes planas con agujeros: STEP pequeño).
  - `grid_slab`: placa sobre una rejilla (u, v) con celdas quitadas (ventanas rectangulares), curvable.
  - `sweep_u`: perfil (v, w) barrido a lo largo de u (perfil variable con el mismo número de vértices), curvable.
  - `tube`: tubo de sección circular a lo largo de una polilínea 3D (abierta con tapas o cerrada).
Unidades: mm.
"""
import math
import struct

import cv2
import numpy as np


# ============================================================================ triangulación (earcut sencillo)
def _area2(p):
    x, y = p[:, 0], p[:, 1]
    return float(np.dot(x, np.roll(y, -1)) - np.dot(np.roll(x, -1), y))


def _pt_in_tri(px, py, ax, ay, bx, by, cx, cy):
    d1 = (px - bx) * (ay - by) - (ax - bx) * (py - by)
    d2 = (px - cx) * (by - cy) - (bx - cx) * (py - cy)
    d3 = (px - ax) * (cy - ay) - (cx - ax) * (py - ay)
    neg = (d1 < 0) or (d2 < 0) or (d3 < 0)
    pos = (d1 > 0) or (d2 > 0) or (d3 > 0)
    return not (neg and pos)


def _seg_inter(p1, p2, p3, p4):
    """¿se cruzan los segmentos abiertos p1p2 y p3p4? (sin contar extremos comunes)"""
    def orient(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
    d1 = orient(p3, p4, p1); d2 = orient(p3, p4, p2); d3 = orient(p1, p2, p3); d4 = orient(p1, p2, p4)
    return (d1 * d2 < 0) and (d3 * d4 < 0)


def triangulate(loops2d):
    """loops2d: lista de arrays (n,2): [exterior, agujero1, ...]. Devuelve triángulos como pares (loop, índice).
    El exterior se toma CCW y los agujeros CW. Algoritmo: puentes de agujeros (Eberly) + corte de orejas."""
    loops = []
    for k, L in enumerate(loops2d):
        L = np.asarray(L, float)
        idx = list(range(len(L)))
        a = _area2(L)
        if (k == 0 and a < 0) or (k > 0 and a > 0):
            idx = idx[::-1]
        loops.append([(k, i) for i in idx])
    P = {(k, i): tuple(loops2d[k][i]) for k in range(len(loops2d)) for i in range(len(loops2d[k]))}
    poly = loops[0]
    holes = sorted(loops[1:], key=lambda h: -max(P[q][0] for q in h))
    outer0 = [P[q] for q in loops[0]]
    hole_pts = [[P[q] for q in h] for h in holes]

    def inside_region(x, y):
        def pip(poly):
            ins = False
            n = len(poly); j = n - 1
            for i in range(n):
                xi, yi = poly[i]; xj, yj = poly[j]
                if (yi > y) != (yj > y) and x < xi + (y - yi) * (xj - xi) / (yj - yi):
                    ins = not ins
                j = i
            return ins
        return pip(outer0) and not any(pip(hp) for hp in hole_pts)

    for hi, h in enumerate(holes):
        m = max(range(len(h)), key=lambda i: (P[h[i]][0], -P[h[i]][1]))
        hh = h[m:] + h[:m]
        n = len(poly)
        best = None
        # probar vértices del agujero (el más a la derecha primero) contra vértices del polígono por distancia
        hverts = [0] + sorted(range(1, len(hh)), key=lambda i: -P[hh[i]][0])[:12]
        for hv in hverts:
            M = P[hh[hv]]
            order = sorted(range(n), key=lambda i: (P[poly[i]][0] - M[0]) ** 2 + (P[poly[i]][1] - M[1]) ** 2)
            for ci in order[:200]:
                B = P[poly[ci]]
                if B == M:
                    continue
                ok = True
                segs = [(P[poly[i]], P[poly[(i + 1) % n]]) for i in range(n)]
                for H in holes[hi:]:
                    segs += [(P[H[i]], P[H[(i + 1) % len(H)]]) for i in range(len(H))]
                for a_, b_ in segs:
                    if _seg_inter(M, B, a_, b_):
                        ok = False; break
                if not ok:
                    continue
                mx, my = (M[0] + B[0]) / 2, (M[1] + B[1]) / 2
                if not inside_region(mx, my):
                    continue
                best = (hv, ci); break
            if best:
                break
        if best is None:
            raise ValueError("agujero sin puente")
        hv, ci = best
        # si el vértice elegido aparece varias veces (extremo de un puente anterior), usar la copia cuya cuña
        # interior contiene la dirección del puente
        B = P[poly[ci]]
        M = P[hh[hv]]
        dups = [i for i in range(n) if P[poly[i]] == B]
        if len(dups) > 1:
            def ang(v):
                return math.atan2(v[1], v[0]) % (2 * math.pi)
            for i in dups:
                nx_ = P[poly[(i + 1) % n]]; pv = P[poly[i - 1]]
                a0 = ang((nx_[0] - B[0], nx_[1] - B[1]))
                a1 = (ang((pv[0] - B[0], pv[1] - B[1])) - a0) % (2 * math.pi)
                ad = (ang((M[0] - B[0], M[1] - B[1])) - a0) % (2 * math.pi)
                if 0 < ad < a1:
                    ci = i; break
        hh = hh[hv:] + hh[:hv]
        poly = poly[:ci + 1] + hh + [hh[0]] + poly[ci:]
    # corte de orejas
    tris = []
    V = list(poly)

    def is_convex(a, b, c):
        return (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0]) > 1e-14

    guard = 0
    i = 0
    while len(V) > 3 and guard < 100000:
        guard += 1
        n = len(V)
        i0, i1, i2 = V[(i - 1) % n], V[i % n], V[(i + 1) % n]
        a, b, c = P[i0], P[i1], P[i2]
        ear = False
        if is_convex(a, b, c):
            ear = True
            for q in V:
                if q in (i0, i1, i2):
                    continue
                pq = P[q]
                if pq in (a, b, c):
                    continue
                if _pt_in_tri(pq[0], pq[1], a[0], a[1], b[0], b[1], c[0], c[1]):
                    ear = False; break
        if ear:
            tris.append((i0, i1, i2))
            del V[i % n]
            guard = 0
            i = max(i - 1, 0)
        else:
            i += 1
            if i > 2 * n + 2:
                # degenerado: forzar
                tris.append((i0, i1, i2)); del V[i % n]; i = 0
    if len(V) == 3:
        tris.append(tuple(V))
    # quitar degenerados
    out = []
    for t in tris:
        a, b, c = (P[q] for q in t)
        if abs((b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])) > 1e-12:
            out.append(t)
    return out


# ============================================================================ malla con caras poligonales planas
class Mesh:
    def __init__(self, name="pieza", color=(0.7, 0.7, 0.7)):
        self.name = name
        self.color = color
        self.V = []                 # lista de (x, y, z)
        self.F = []                 # cara = [bucle exterior, agujeros...] (índices); exterior CCW visto desde fuera
        self._key = {}

    def v(self, xyz, key=None):
        if key is not None:
            k = self._key.get(key)
            if k is not None:
                return k
        self.V.append(tuple(float(c) for c in xyz))
        i = len(self.V) - 1
        if key is not None:
            self._key[key] = i
        return i

    def face(self, loops):
        self.F.append([list(L) for L in loops])

    def copy(self, name=None, color=None):
        m = Mesh(name or self.name, color or self.color)
        m.V = list(self.V); m.F = [[list(L) for L in f] for f in self.F]
        return m

    def merge(self, other):
        off = len(self.V)
        self.V += other.V
        self.F += [[[i + off for i in L] for L in f] for f in other.F]
        return self

    def transform(self, M):
        A = np.asarray(self.V, float)
        A = A @ M[:3, :3].T + M[:3, 3]
        self.V = [tuple(r) for r in A]
        return self

    def map(self, fn):
        """deforma (fn: (N,3)->(N,3)); las caras que dejan de ser planas se dividen en triángulos"""
        A0 = np.asarray(self.V, float)
        A = fn(A0)
        newF = []
        for f in self.F:
            if len(f) == 1 and len(f[0]) == 3:
                newF.append(f); continue
            Q = A[[i for L in f for i in L]]
            c = Q.mean(0)
            _, sv, vt = np.linalg.svd(Q - c, full_matrices=False)
            if sv[-1] / max(1.0, np.sqrt(len(Q))) < 1e-5:
                newF.append(f)
            else:
                tmp = Mesh(); tmp.V = self.V; tmp.F = [f]
                newF += [[list(t)] for t in tmp.triangles()]
        self.V = [tuple(r) for r in A]
        self.F = newF
        return self

    def np(self):
        return np.asarray(self.V, float)

    def face_normal(self, f):
        V = self.np() if not hasattr(self, "_npcache") else self._npcache
        L = V[f[0]]
        n = np.zeros(3)
        for i in range(len(L)):
            a, b = L[i], L[(i + 1) % len(L)]
            n += np.cross(a, b)
        nn = np.linalg.norm(n)
        return n / nn if nn > 0 else n

    def triangles(self):
        V = np.asarray(self.V, float)
        out = []
        for f in self.F:
            if len(f) == 1 and len(f[0]) == 3:
                out.append(tuple(f[0])); continue
            L = V[f[0]]
            n = np.zeros(3)
            for i in range(len(L)):
                n += np.cross(L[i], L[(i + 1) % len(L)])
            nn = np.linalg.norm(n)
            if nn == 0:
                continue
            n /= nn
            # base del plano
            ax = np.argmax(np.abs(n))
            e1 = np.zeros(3); e1[(ax + 1) % 3] = 1
            e1 = e1 - n * np.dot(e1, n); e1 /= np.linalg.norm(e1)
            e2 = np.cross(n, e1)
            loops2 = [np.c_[V[L_] @ e1, V[L_] @ e2] for L_ in f]
            tri = triangulate(loops2)
            for t in tri:
                out.append(tuple(f[k][i] for k, i in t))
        return out

    # ------------------------------------------------------------------ comprobaciones
    def check_closed(self):
        from collections import Counter
        c = Counter()
        for f in self.F:
            for L in f:
                for i in range(len(L)):
                    c[(L[i], L[(i + 1) % len(L)])] += 1
        bad = 0
        for (a, b), k in c.items():
            if k != 1 or c.get((b, a), 0) != 1:
                bad += 1
        return bad

    def bbox(self):
        A = self.np()
        return A.min(0), A.max(0)

    def volume(self):
        V = self.np()
        tot = 0.0
        for t in self.triangles():
            a, b, c = V[list(t)]
            tot += np.dot(a, np.cross(b, c)) / 6.0
        return tot

    def weld(self, tol=1e-6):
        """une vértices coincidentes (útil tras unir piezas generadas por separado)"""
        A = self.np()
        q = np.round(A / tol).astype(np.int64)
        _, inv, = np.unique(q, axis=0, return_inverse=True)[0:2], None
        uq, idx, inv = np.unique(q, axis=0, return_index=True, return_inverse=True)
        self.V = [tuple(A[i]) for i in idx]
        inv = inv.ravel()
        self.F = [[[int(inv[i]) for i in L] for L in f] for f in self.F]
        return self


# ============================================================================ contornos 2D
class Contour:
    _n = 0

    def __init__(self, pts, name=""):
        P = np.asarray(pts, float)
        # quitar duplicados consecutivos
        keep = [0]
        for i in range(1, len(P)):
            if np.hypot(*(P[i] - P[keep[-1]])) > 1e-7:
                keep.append(i)
        P = P[keep]
        if np.hypot(*(P[0] - P[-1])) < 1e-7:
            P = P[:-1]
        if _area2(P) < 0:
            P = P[::-1]
        self.p = P
        self.name = name
        Contour._n += 1
        self.id = Contour._n
        self.area = abs(_area2(P)) / 2

    def contains(self, x, y):
        P = self.p
        inside = False
        n = len(P)
        j = n - 1
        for i in range(n):
            xi, yi = P[i]; xj, yj = P[j]
            if (yi > y) != (yj > y):
                xc = xi + (y - yi) * (xj - xi) / (yj - yi)
                if x < xc:
                    inside = not inside
            j = i
        return inside

    def translated(self, dx, dy):
        return Contour(self.p + [dx, dy], self.name)


def rrect(cx, cy, w, h, r, seg=6):
    """rectángulo con esquinas redondeadas (CCW), seg segmentos por esquina"""
    r = min(r, w / 2 - 1e-9, h / 2 - 1e-9) if r > 0 else 0
    hw, hh = w / 2, h / 2
    pts = []
    if r <= 1e-9:
        return Contour([(cx - hw, cy - hh), (cx + hw, cy - hh), (cx + hw, cy + hh), (cx - hw, cy + hh)])
    for (sx, sy, a0) in ((1, -1, -90), (1, 1, 0), (-1, 1, 90), (-1, -1, 180)):
        ccx, ccy = cx + sx * (hw - r), cy + sy * (hh - r)
        for k in range(seg + 1):
            a = math.radians(a0 + 90 * k / seg)
            pts.append((ccx + r * math.cos(a), ccy + r * math.sin(a)))
    return Contour(pts)


def circle(cx, cy, r, n=None):
    if n is None:
        n = max(12, min(48, int(2 * math.pi * r / 0.6)))
        n = (n + 3) // 4 * 4
    return Contour([(cx + r * math.cos(2 * math.pi * k / n), cy + r * math.sin(2 * math.pi * k / n)) for k in range(n)])


def stadium(cx, cy, L, W, along_x=True, seg=8):
    if along_x:
        return rrect(cx, cy, L, W, W / 2 - 1e-6, seg)
    return rrect(cx, cy, W, L, W / 2 - 1e-6, seg)


def polygon(pts):
    return Contour(pts)


# ------------------------------------------------------------------ uniones 2D por rasterizado (para contornos libres)
class Raster:
    """lienzo 2D para unir/restar/desplazar formas y sacar contornos (resolución res mm)"""

    def __init__(self, x0, y0, x1, y1, res=0.02):
        self.x0, self.y0, self.res = x0, y0, res
        self.W = int(math.ceil((x1 - x0) / res)); self.H = int(math.ceil((y1 - y0) / res))
        self.m = np.zeros((self.H, self.W), np.uint8)

    def _px(self, P):
        P = np.asarray(P, float)
        return np.round(np.c_[(P[:, 0] - self.x0) / self.res, (P[:, 1] - self.y0) / self.res] * 16).astype(np.int32)

    def add(self, c, val=255):
        cv2.fillPoly(self.m, [self._px(c.p)], val, lineType=cv2.LINE_8, shift=4)
        return self

    def sub(self, c):
        return self.add(c, 0)

    def offset(self, d):
        """nuevo raster desplazado d mm (d>0 crece)"""
        R = Raster.__new__(Raster)
        R.x0, R.y0, R.res, R.W, R.H = self.x0, self.y0, self.res, self.W, self.H
        if d > 0:
            dist = cv2.distanceTransform(255 - self.m, cv2.DIST_L2, 5) * self.res
            R.m = np.where((self.m > 0) | (dist <= d), 255, 0).astype(np.uint8)
        else:
            dist = cv2.distanceTransform(self.m, cv2.DIST_L2, 5) * self.res
            R.m = np.where(dist > -d, 255, 0).astype(np.uint8)
        return R

    def contours(self, eps=0.01):
        cs, hier = cv2.findContours(self.m, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
        out = []
        for c in cs:
            c = cv2.approxPolyDP(c, eps / self.res, True).reshape(-1, 2).astype(float)
            if len(c) < 3:
                continue
            pts = np.c_[self.x0 + (c[:, 0] + 0.5) * self.res, self.y0 + (c[:, 1] + 0.5) * self.res]
            out.append(Contour(pts))
        return out

    def contour(self, eps=0.01):
        cs = self.contours(eps)
        return max(cs, key=lambda c: c.area)


# ============================================================================ sólido por capas
def _region_has(contours, x, y):
    k = 0
    for c in contours:
        if c.contains(x, y):
            k += 1
    return k % 2 == 1


def _face_tree(contours):
    """árbol de anidamiento de contornos que no se cruzan → caras (contorno, hijos)"""
    cs = sorted(set(contours), key=lambda c: -c.area)
    parent = {}
    for i, c in enumerate(cs):
        x, y = c.p[0]
        par = None
        for d in cs[:i][::-1]:
            if d.area > c.area and d.contains(x, y):
                par = d; break
        parent[c.id] = par
    faces = []
    for c in cs:
        kids = [d for d in cs if parent[d.id] is c]
        faces.append((c, kids))
    return faces


def _face_sample(c, kids):
    loops = [c.p] + [k.p for k in kids]
    tris = triangulate(loops)
    if not tris:
        return None
    # triángulo de mayor área
    best = None
    for t in tris:
        a, b, d = (loops[k][i] for k, i in t)
        ar = abs((b[0] - a[0]) * (d[1] - a[1]) - (b[1] - a[1]) * (d[0] - a[0]))
        if best is None or ar > best[0]:
            best = (ar, (a + b + d) / 3)
    return best[1]


def layered(layers, name="pieza", color=(0.8, 0.8, 0.8)):
    """layers: lista de (z0, z1, contornos) o (z0, z1, contornos_abajo, contornos_arriba) (loft, mismo nº de vértices).
    Las capas deben ser contiguas (z1 de una = z0 de la siguiente). Regla par-impar dentro de cada capa."""
    M = Mesh(name, color)
    L = []
    for ly in layers:
        if len(ly) == 3:
            L.append((ly[0], ly[1], list(ly[2]), list(ly[2])))
        else:
            L.append((ly[0], ly[1], list(ly[2]), list(ly[3])))
    for k in range(len(L) - 1):
        assert abs(L[k][1] - L[k + 1][0]) < 1e-9, "capas no contiguas"

    def vid(c, i, z):
        return M.v((c.p[i][0], c.p[i][1], z), key=(c.id, i, round(z, 6)))

    def hface(c, kids, z, up):
        loops = [c] + kids
        idx = []
        for j, cc in enumerate(loops):
            ii = list(range(len(cc.p)))
            ccw = (j == 0) == up       # exterior CCW si mira arriba; agujeros al revés
            if not ccw:
                ii = ii[::-1]
            idx.append([vid(cc, i, z) for i in ii])
        M.face(idx)

    # interfaces horizontales
    zs = [L[0][0]] + [ly[1] for ly in L]
    for k, z in enumerate(zs):
        below = L[k - 1][3] if k > 0 else []
        above = L[k][2] if k < len(L) else []
        allc = list({c.id: c for c in below + above}.values())
        for c, kids in _face_tree(allc):
            s = _face_sample(c, kids)
            if s is None:
                continue
            b = _region_has(below, *s); a = _region_has(above, *s)
            if b and not a:
                hface(c, kids, z, True)
            elif a and not b:
                hface(c, kids, z, False)
    # paredes
    for (z0, z1, cb, ct) in L:
        for c0, c1 in zip(cb, ct):
            n = len(c0.p)
            assert n == len(c1.p)
            # ¿la región está a la izquierda (dentro del contorno CCW)?
            a, b = c0.p[0], c0.p[1]
            t = (b - a) / np.linalg.norm(b - a)
            nl = np.array([-t[1], t[0]])
            mid = (a + b) / 2
            e = min(1e-3, 0.25 * np.linalg.norm(b - a))
            inside = _region_has(cb, *(mid + nl * e))
            for i in range(n):
                j = (i + 1) % n
                q = [vid(c0, i, z0), vid(c0, j, z0), vid(c1, j, z1), vid(c1, i, z1)]
                if not inside:
                    q = q[::-1]
                # ¿plano?
                P = np.asarray([M.V[x] for x in q])
                nrm = np.cross(P[1] - P[0], P[2] - P[0])
                d = abs(np.dot(P[3] - P[0], nrm)) / (np.linalg.norm(nrm) + 1e-30)
                if d > 1e-6:
                    M.face([[q[0], q[1], q[2]]]); M.face([[q[0], q[2], q[3]]])
                else:
                    M.face([q])
    return M


def prism(contours, z0, z1, name="prisma", color=(0.8, 0.8, 0.8)):
    return layered([(z0, z1, contours)], name, color)


def box(x0, y0, z0, x1, y1, z1, name="caja", color=(0.6, 0.6, 0.6)):
    return prism([polygon([(x0, y0), (x1, y0), (x1, y1), (x0, y1)])], z0, z1, name, color)


def cylinder_z(cx, cy, r, z0, z1, name="cilindro", color=(0.6, 0.6, 0.6), n=None, hole=None):
    cs = [circle(cx, cy, r, n)]
    if hole:
        cs.append(circle(cx, cy, hole, n))
    return prism(cs, z0, z1, name, color)


# ============================================================================ placa en rejilla (curvable)
def grid_slab(us, vs, w0, w1, keep=None, name="placa", color=(0.5, 0.4, 0.3)):
    """us, vs: cortes de la rejilla (ordenados); keep(i, j) -> bool para la celda [us[i],us[i+1]]×[vs[j],vs[j+1]]"""
    M = Mesh(name, color)
    nu, nv = len(us) - 1, len(vs) - 1
    K = np.ones((nu, nv), bool)
    if keep is not None:
        for i in range(nu):
            for j in range(nv):
                K[i, j] = keep((us[i] + us[i + 1]) / 2, (vs[j] + vs[j + 1]) / 2)

    def vid(i, j, top):
        return M.v((us[i], vs[j], w1 if top else w0), key=(i, j, top))

    def kept(i, j):
        return 0 <= i < nu and 0 <= j < nv and K[i, j]

    for i in range(nu):
        for j in range(nv):
            if not K[i, j]:
                continue
            M.face([[vid(i, j, 1), vid(i + 1, j, 1), vid(i + 1, j + 1, 1), vid(i, j + 1, 1)]])
            M.face([[vid(i, j, 0), vid(i, j + 1, 0), vid(i + 1, j + 1, 0), vid(i + 1, j, 0)]])
            if not kept(i - 1, j):   # cara −u
                M.face([[vid(i, j, 0), vid(i, j, 1), vid(i, j + 1, 1), vid(i, j + 1, 0)]])
            if not kept(i + 1, j):   # cara +u
                M.face([[vid(i + 1, j, 0), vid(i + 1, j + 1, 0), vid(i + 1, j + 1, 1), vid(i + 1, j, 1)]])
            if not kept(i, j - 1):   # cara −v
                M.face([[vid(i, j, 0), vid(i + 1, j, 0), vid(i + 1, j, 1), vid(i, j, 1)]])
            if not kept(i, j + 1):   # cara +v
                M.face([[vid(i, j + 1, 0), vid(i, j + 1, 1), vid(i + 1, j + 1, 1), vid(i + 1, j + 1, 0)]])
    return M


def breaks(a, b, step, extra=()):
    """cortes de a a b cada ~step, incluyendo los cortes extra"""
    n = max(1, int(math.ceil((b - a) / step)))
    s = set(np.round(np.linspace(a, b, n + 1), 6))
    for e in extra:
        if a <= e <= b:
            s.add(round(e, 6))
    s = sorted(s)
    out = [s[0]]
    for x in s[1:]:
        if x - out[-1] > 0.05:
            out.append(x)
    out[-1] = b
    return out


# ============================================================================ barrido de perfil a lo largo de u
def sweep_u(stations, name="barrido", color=(0.5, 0.5, 0.5)):
    """stations: lista de (u, perfil (n,2) en (v, w)). Perfil CCW en (v, w)."""
    M = Mesh(name, color)
    prof = []
    for u, P in stations:
        P = np.asarray(P, float)
        prof.append((u, P))
    n = len(prof[0][1])
    # orientar perfiles: queremos que (u, v, w) con perfil CCW en (v,w) dé normales hacia fuera
    sgn = _area2(prof[0][1])
    if sgn < 0:
        prof = [(u, P[::-1]) for u, P in prof]

    def vid(k, i):
        u, P = prof[k]
        return M.v((u, P[i][0], P[i][1]), key=(k, i))

    for k in range(len(prof) - 1):
        for i in range(n):
            j = (i + 1) % n
            q = [vid(k, i), vid(k, j), vid(k + 1, j), vid(k + 1, i)]
            P = np.asarray([M.V[x] for x in q])
            nrm = np.cross(P[1] - P[0], P[2] - P[0])
            d = abs(np.dot(P[3] - P[0], nrm)) / (np.linalg.norm(nrm) + 1e-30)
            if d > 1e-6:
                M.face([[q[0], q[1], q[2]]]); M.face([[q[0], q[2], q[3]]])
            else:
                M.face([q])
    # tapas
    k0, k1 = 0, len(prof) - 1
    M.face([[vid(k0, i) for i in range(n)][::-1]])
    M.face([[vid(k1, i) for i in range(n)]])
    # comprobar orientación con el volumen
    if M.volume() < 0:
        M.F = [[L[::-1] for L in f] for f in M.F]
    return M


# ============================================================================ tubo
def _frames(P, closed):
    n = len(P)
    T = []
    for i in range(n):
        if closed:
            t = P[(i + 1) % n] - P[i - 1]
        else:
            t = P[min(i + 1, n - 1)] - P[max(i - 1, 0)]
        T.append(t / np.linalg.norm(t))
    T = np.array(T)
    a = np.array([0, 0, 1.0]) if abs(T[0][2]) < 0.9 else np.array([1.0, 0, 0])
    N0 = np.cross(T[0], a); N0 /= np.linalg.norm(N0)
    Ns = [N0]
    for i in range(1, n):
        b = np.cross(T[i - 1], T[i])
        N = Ns[-1]
        if np.linalg.norm(b) > 1e-9:
            b /= np.linalg.norm(b)
            ang = math.acos(max(-1, min(1, np.dot(T[i - 1], T[i]))))
            N = N * math.cos(ang) + np.cross(b, N) * math.sin(ang) + b * np.dot(b, N) * (1 - math.cos(ang))
        N = N - T[i] * np.dot(N, T[i]); N /= np.linalg.norm(N)
        Ns.append(N)
    return T, np.array(Ns)


def tube(path, r, nseg=10, closed=False, name="tubo", color=(0.2, 0.2, 0.2)):
    P = np.asarray(path, float)
    T, N = _frames(P, closed)
    B = np.cross(T, N)
    if closed:
        # corregir el giro acumulado repartiéndolo
        tw = math.atan2(np.dot(np.cross(N[-1], N[0]), T[0]), np.dot(N[-1], N[0]))
        n = len(P)
        for i in range(n):
            a = -tw * i / n
            Ni = N[i] * math.cos(a) + B[i] * math.sin(a)
            Bi = np.cross(T[i], Ni)
            N[i], B[i] = Ni, Bi
    M = Mesh(name, color)
    n = len(P)
    for i in range(n):
        for k in range(nseg):
            a = 2 * math.pi * k / nseg
            M.v(P[i] + r * (N[i] * math.cos(a) + B[i] * math.sin(a)), key=(i, k))
    rng = range(n) if closed else range(n - 1)
    for i in rng:
        i2 = (i + 1) % n
        for k in range(nseg):
            k2 = (k + 1) % nseg
            q = [M._key[(i, k)], M._key[(i2, k)], M._key[(i2, k2)], M._key[(i, k2)]]
            M.face([[q[0], q[1], q[2]]]); M.face([[q[0], q[2], q[3]]])
    if not closed:
        M.face([[M._key[(0, k)] for k in range(nseg)]])
        M.face([[M._key[(n - 1, k)] for k in range(nseg)][::-1]])
    if M.volume() < 0:
        M.F = [[L[::-1] for L in f] for f in M.F]
    return M


def polyline_round(pts, r=3.0, n=4):
    """suaviza las esquinas de una polilínea 3D con arcos aproximados (radio r)"""
    P = [np.asarray(p, float) for p in pts]
    if len(P) < 3:
        return np.array(P)
    out = [P[0]]
    for i in range(1, len(P) - 1):
        a, b, c = P[i - 1], P[i], P[i + 1]
        d1 = (a - b); l1 = np.linalg.norm(d1); d1 /= l1
        d2 = (c - b); l2 = np.linalg.norm(d2); d2 /= l2
        rr = min(r, 0.45 * l1, 0.45 * l2)
        p0 = b + d1 * rr; p1 = b + d2 * rr
        for k in range(n + 1):
            t = k / n
            q = (1 - t) ** 2 * p0 + 2 * (1 - t) * t * b + t ** 2 * p1
            out.append(q)
    out.append(P[-1])
    # quitar puntos casi repetidos
    res = [out[0]]
    for q in out[1:]:
        if np.linalg.norm(q - res[-1]) > 0.05:
            res.append(q)
    return np.array(res)


def resample(path, step):
    P = np.asarray(path, float)
    out = [P[0]]
    for i in range(1, len(P)):
        a, b = P[i - 1], P[i]
        L = np.linalg.norm(b - a)
        k = max(1, int(math.ceil(L / step)))
        for j in range(1, k + 1):
            out.append(a + (b - a) * j / k)
    return np.array(out)


# ============================================================================ transformaciones
def T_translate(x, y, z):
    M = np.eye(4); M[:3, 3] = (x, y, z); return M


def T_rotz(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    M = np.eye(4); M[0, 0], M[0, 1], M[1, 0], M[1, 1] = c, -s, s, c; return M


def T_rotx(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    M = np.eye(4); M[1, 1], M[1, 2], M[2, 1], M[2, 2] = c, -s, s, c; return M


def T_roty(deg):
    a = math.radians(deg); c, s = math.cos(a), math.sin(a)
    M = np.eye(4); M[0, 0], M[0, 2], M[2, 0], M[2, 2] = c, s, -s, c; return M


def swap_axes(order):
    """matriz que lleva (x, y, z) local a los ejes dados, p. ej. ('y','z','x')"""
    M = np.zeros((4, 4)); M[3, 3] = 1
    ax = {"x": 0, "y": 1, "z": 2}
    for i, a in enumerate(order):
        sgn = -1 if a.startswith("-") else 1
        M[ax[a[-1]], i] = sgn
    return M


# ============================================================================ STL
def write_stl(path, meshes):
    tris_all = []
    for m in meshes:
        V = m.np()
        for t in m.triangles():
            tris_all.append(V[list(t)])
    with open(path, "wb") as f:
        f.write(b"AVO CINCHA - generado por avo_cad.py".ljust(80, b" "))
        f.write(struct.pack("<I", len(tris_all)))
        for T in tris_all:
            n = np.cross(T[1] - T[0], T[2] - T[0]); nn = np.linalg.norm(n)
            n = n / nn if nn > 0 else n
            f.write(struct.pack("<12fH", *n, *T[0], *T[1], *T[2], 0))
    return len(tris_all)


# ============================================================================ STEP AP214 (ADVANCED_BREP poliédrico)
class _StepW:
    def __init__(self):
        self.lines = []
        self.n = 0

    def add(self, s):
        self.n += 1
        self.lines.append("#%d=%s;" % (self.n, s))
        return self.n


def _f(x, nd=4):
    x = float(x)
    if abs(x) < 5e-12:
        x = 0.0
    s = ("%%.%df" % nd) % x
    s = s.rstrip("0")
    if s.endswith("."):
        s += "0"
    return s.replace("-0.0", "0.0") if s in ("-0.0",) else s


def _esc(s):
    """texto STEP: apóstrofos dobles y no-ASCII codificado \\X2\\…\\X0\\"""
    out = []
    for ch in s.replace("'", "''"):
        if ord(ch) < 128:
            out.append(ch)
        else:
            out.append("\\X2\\%04X\\X0\\" % ord(ch))
    return "".join(out)


def _brep(W, m, ctx_unused=None):
    """escribe un MANIFOLD_SOLID_BREP de la malla m (puntos y direcciones compartidos); devuelve el id del brep"""
    V = m.np()
    cps, vps, dirs = {}, {}, {}

    def cp(p):
        k = "(%s,%s,%s)" % tuple(_f(c) for c in p)
        if k not in cps:
            cps[k] = W.add("CARTESIAN_POINT('',%s)" % k)
        return cps[k]

    def dr(d):
        k = "(%s,%s,%s)" % tuple(_f(c, 11) for c in d)
        if k not in dirs:
            dirs[k] = W.add("DIRECTION('',%s)" % k)
        return dirs[k]

    def vp(i):
        if i not in vps:
            vps[i] = W.add("VERTEX_POINT('',#%d)" % cp(V[i]))
        return vps[i]

    edges = {}

    def edge(a, b):
        k = (a, b) if a < b else (b, a)
        if k not in edges:
            p0, p1 = V[k[0]], V[k[1]]
            d = p1 - p0; L = np.linalg.norm(d)
            d = d / L if L > 0 else np.array([1.0, 0, 0])
            vec = W.add("VECTOR('',#%d,%s)" % (dr(d), _f(L, 6)))
            ln = W.add("LINE('',#%d,#%d)" % (cp(p0), vec))
            edges[k] = W.add("EDGE_CURVE('',#%d,#%d,#%d,.T.)" % (vp(k[0]), vp(k[1]), ln))
        return edges[k], (a, b) == k

    faces = []
    for f in m.F:
        L0 = V[f[0]]
        n = np.zeros(3)
        for i in range(len(L0)):
            n += np.cross(L0[i], L0[(i + 1) % len(L0)])
        nn = np.linalg.norm(n)
        if nn < 1e-12:
            continue
        n /= nn
        ax = np.argmax(np.abs(n))
        e1 = np.zeros(3); e1[(ax + 1) % 3] = 1
        e1 = e1 - n * np.dot(e1, n); e1 /= np.linalg.norm(e1)
        bounds = []
        for li, L in enumerate(f):
            oes = []
            for i in range(len(L)):
                ec, same = edge(L[i], L[(i + 1) % len(L)])
                oes.append(W.add("ORIENTED_EDGE('',*,*,#%d,%s)" % (ec, ".T." if same else ".F.")))
            el = W.add("EDGE_LOOP('',(%s))" % ",".join("#%d" % o for o in oes))
            bounds.append(W.add("%s('',#%d,.T.)" % ("FACE_OUTER_BOUND" if li == 0 else "FACE_BOUND", el)))
        a2 = W.add("AXIS2_PLACEMENT_3D('',#%d,#%d,#%d)" % (cp(L0[0]), dr(n), dr(e1)))
        pl = W.add("PLANE('',#%d)" % a2)
        faces.append(W.add("ADVANCED_FACE('',(%s),#%d,.T.)" % (",".join("#%d" % b for b in bounds), pl)))
    sh = W.add("CLOSED_SHELL('',(%s))" % ",".join("#%d" % x for x in faces))
    return W.add("MANIFOLD_SOLID_BREP('%s',#%d)" % (_esc(m.name), sh))


def write_step(path, parts, assembly_name="CONJUNTO", author="AVO Performance Horse"):
    """parts: lista de (nombre_producto, [mallas]) — cada producto es una pieza (con uno o varios sólidos).
    Si hay más de una pieza se escribe un ensamblaje (NEXT_ASSEMBLY_USAGE_OCCURRENCE) con transformaciones identidad."""
    import datetime
    W = _StepW()
    app = W.add("APPLICATION_CONTEXT('core data for automotive mechanical design processes')")
    W.add("APPLICATION_PROTOCOL_DEFINITION('international standard','automotive_design',2000,#%d)" % app)
    lu = W.add("( LENGTH_UNIT() NAMED_UNIT(*) SI_UNIT(.MILLI.,.METRE.) )")
    au = W.add("( NAMED_UNIT(*) PLANE_ANGLE_UNIT() SI_UNIT($,.RADIAN.) )")
    su = W.add("( NAMED_UNIT(*) SI_UNIT($,.STERADIAN.) SOLID_ANGLE_UNIT() )")
    unc = W.add("UNCERTAINTY_MEASURE_WITH_UNIT(LENGTH_MEASURE(1.E-04),#%d,'distance_accuracy_value','confusion accuracy')" % lu)
    ctx = W.add("( GEOMETRIC_REPRESENTATION_CONTEXT(3) GLOBAL_UNCERTAINTY_ASSIGNED_CONTEXT((#%d)) "
                "GLOBAL_UNIT_ASSIGNED_CONTEXT((#%d,#%d,#%d)) REPRESENTATION_CONTEXT('Context #1',"
                "'3D Context with UNIT and UNCERTAINTY') )" % (unc, lu, au, su))

    def axis():
        o = W.add("CARTESIAN_POINT('',(0.,0.,0.))")
        z = W.add("DIRECTION('',(0.,0.,1.))")
        x = W.add("DIRECTION('',(1.,0.,0.))")
        return W.add("AXIS2_PLACEMENT_3D('',#%d,#%d,#%d)" % (o, z, x))

    def product(name):
        pc = W.add("PRODUCT_CONTEXT('',#%d,'mechanical')" % app)
        pr = W.add("PRODUCT('%s','%s','',(#%d))" % (_esc(name), _esc(name), pc))
        W.add("PRODUCT_RELATED_PRODUCT_CATEGORY('part',$,(#%d))" % pr)
        pdf = W.add("PRODUCT_DEFINITION_FORMATION('','',#%d)" % pr)
        pdc = W.add("PRODUCT_DEFINITION_CONTEXT('part definition',#%d,'design')" % app)
        pd = W.add("PRODUCT_DEFINITION('design','',#%d,#%d)" % (pdf, pdc))
        pds = W.add("PRODUCT_DEFINITION_SHAPE('','',#%d)" % pd)
        return pd, pds

    styled = []

    def colour(item, rgb):
        c = W.add("COLOUR_RGB('',%s,%s,%s)" % tuple(_f(x) for x in rgb))
        fac = W.add("FILL_AREA_STYLE_COLOUR('',#%d)" % c)
        fas = W.add("FILL_AREA_STYLE('',(#%d))" % fac)
        ssfa = W.add("SURFACE_STYLE_FILL_AREA(#%d)" % fas)
        sss = W.add("SURFACE_SIDE_STYLE('',(#%d))" % ssfa)
        ssu = W.add("SURFACE_STYLE_USAGE(.BOTH.,#%d)" % sss)
        psa = W.add("PRESENTATION_STYLE_ASSIGNMENT((#%d))" % ssu)
        styled.append(W.add("STYLED_ITEM('color',(#%d),#%d)" % (psa, item)))

    reps = []
    for pname, meshes in parts:
        pd, pds = product(pname)
        ax = axis()
        items = []
        for m in meshes:
            b = _brep(W, m)
            items.append(b)
            colour(b, m.color)
        rep = W.add("ADVANCED_BREP_SHAPE_REPRESENTATION('%s',(%s),#%d)" % (
            _esc(pname), ",".join("#%d" % i for i in [ax] + items), ctx))
        W.add("SHAPE_DEFINITION_REPRESENTATION(#%d,#%d)" % (pds, rep))
        reps.append((pname, pd, rep, ax))
    if len(parts) > 1:
        apd, apds = product(assembly_name)
        axes = [axis() for _ in reps]
        arep = W.add("SHAPE_REPRESENTATION('',(%s),#%d)" % (",".join("#%d" % a for a in axes), ctx))
        W.add("SHAPE_DEFINITION_REPRESENTATION(#%d,#%d)" % (apds, arep))
        for k, (pname, pd, rep, ax) in enumerate(reps):
            nauo = W.add("NEXT_ASSEMBLY_USAGE_OCCURRENCE('%d','%s','',#%d,#%d,$)" % (k + 1, _esc(pname), apd, pd))
            pdsn = W.add("PRODUCT_DEFINITION_SHAPE('Placement','Placement of an item',#%d)" % nauo)
            idt = W.add("ITEM_DEFINED_TRANSFORMATION('','',#%d,#%d)" % (ax, axes[k]))
            rr = W.add("( REPRESENTATION_RELATIONSHIP('','',#%d,#%d) REPRESENTATION_RELATIONSHIP_WITH_TRANSFORMATION(#%d) "
                       "SHAPE_REPRESENTATION_RELATIONSHIP() )" % (rep, arep, idt))
            W.add("CONTEXT_DEPENDENT_SHAPE_REPRESENTATION(#%d,#%d)" % (rr, pdsn))
    if styled:
        W.add("MECHANICAL_DESIGN_GEOMETRIC_PRESENTATION_REPRESENTATION('',(%s),#%d)" % (
            ",".join("#%d" % s for s in styled), ctx))
    now = datetime.datetime(2026, 11, 15, 12, 0, 0).strftime("%Y-%m-%dT%H:%M:%S")
    head = ["ISO-10303-21;", "HEADER;",
            "FILE_DESCRIPTION(('AVO Performance Horse - montaje de la cincha (B-rep poliedrico)'),'2;1');",
            "FILE_NAME('%s','%s',('%s'),('AVO Performance Horse'),'avo_cad.py','avo_cad.py (numpy)','');" % (
                _esc(assembly_name), now, _esc(author)),
            "FILE_SCHEMA(('AUTOMOTIVE_DESIGN { 1 0 10303 214 1 1 1 1 }'));", "ENDSEC;", "DATA;"]
    with open(path, "w", encoding="ascii") as f:
        f.write("\n".join(head) + "\n")
        f.write("\n".join(W.lines) + "\n")
        f.write("ENDSEC;\nEND-ISO-10303-21;\n")
    return W.n


def check_step_refs(path):
    """comprobación sintáctica mínima: todas las referencias #n están definidas"""
    import re
    txt = open(path, encoding="ascii").read()
    defined = set(int(x) for x in re.findall(r"^#(\d+)=", txt, re.M))
    used = set(int(x) for x in re.findall(r"#(\d+)", txt))
    return sorted(used - defined)
