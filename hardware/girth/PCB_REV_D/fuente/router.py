"""Grid maze router (A*) for 2+ copper layers with through vias.

Copper of every net is rasterised on a 0.05 mm grid. For each new connection the cells closer than
clearance + half the track width to copper of other nets are blocked (Euclidean distance transform), so
every routed track respects the clearance by construction (plus a margin for the rasterisation error).
"""
import heapq
import math

import numpy as np
from scipy import ndimage

GRID = 0.05
EPS = 0.045            # margin for rasterisation (max error of a cell centre: 0.035)


def poly_mask(shape, x0, y0, poly):
    """Boolean mask of cells whose centre is inside polygon (even-odd)."""
    h, w = shape
    xs = np.array([p[0] for p in poly]); ys = np.array([p[1] for p in poly])
    i0 = max(0, int((ys.min() - y0) / GRID) - 1); i1 = min(h, int((ys.max() - y0) / GRID) + 2)
    j0 = max(0, int((xs.min() - x0) / GRID) - 1); j1 = min(w, int((xs.max() - x0) / GRID) + 2)
    m = np.zeros(shape, bool)
    if i0 >= i1 or j0 >= j1:
        return m
    jj, ii = np.meshgrid(np.arange(j0, j1), np.arange(i0, i1))
    px = x0 + (jj + 0.5) * GRID; py = y0 + (ii + 0.5) * GRID
    inside = np.zeros(px.shape, bool)
    n = len(poly)
    for k in range(n):
        xa, ya = poly[k]; xb, yb = poly[(k + 1) % n]
        cond = ((ya > py) != (yb > py))
        with np.errstate(divide="ignore", invalid="ignore"):
            xint = xa + (py - ya) * (xb - xa) / (yb - ya)
        inside ^= cond & (px < xint)
    m[i0:i1, j0:j1] = inside
    return m


def seg_mask(shape, x0, y0, a, b, r):
    """Cells whose centre is within r of segment a-b."""
    h, w = shape
    i0 = max(0, int((min(a[1], b[1]) - r - y0) / GRID) - 1); i1 = min(h, int((max(a[1], b[1]) + r - y0) / GRID) + 2)
    j0 = max(0, int((min(a[0], b[0]) - r - x0) / GRID) - 1); j1 = min(w, int((max(a[0], b[0]) + r - x0) / GRID) + 2)
    m = np.zeros(shape, bool)
    if i0 >= i1 or j0 >= j1:
        return m
    jj, ii = np.meshgrid(np.arange(j0, j1), np.arange(i0, i1))
    px = x0 + (jj + 0.5) * GRID; py = y0 + (ii + 0.5) * GRID
    dx, dy = b[0] - a[0], b[1] - a[1]
    L2 = dx * dx + dy * dy
    if L2 == 0:
        d2 = (px - a[0]) ** 2 + (py - a[1]) ** 2
    else:
        t = np.clip(((px - a[0]) * dx + (py - a[1]) * dy) / L2, 0, 1)
        d2 = (px - a[0] - t * dx) ** 2 + (py - a[1] - t * dy) ** 2
    m[i0:i1, j0:j1] = d2 <= r * r
    return m


class Router:
    def __init__(self, x0, y0, x1, y1, layers, clearance=0.15, via=(0.5, 0.3), edge_clear=0.35):
        self.x0, self.y0 = x0, y0
        self.W = int(math.ceil((x1 - x0) / GRID)); self.H = int(math.ceil((y1 - y0) / GRID))
        self.layers = layers                     # list of layer names usable for routing
        self.L = len(layers)
        self.clear = clearance
        self.via_d, self.via_drill = via
        self.label = np.full((self.L, self.H, self.W), -1, np.int32)   # net id of copper, -1 none
        self.hard = np.zeros((self.L, self.H, self.W), bool)            # outside board / keepouts
        self.tracks = []        # (net, layer, (x, y), (x, y), width)
        self.vias = []          # (net, (x, y))
        self.edge_clear = edge_clear

    # ---------------------------------------------------------------- coordinates
    def ij(self, x, y):
        return int((y - self.y0) / GRID), int((x - self.x0) / GRID)

    def xy(self, i, j):
        return self.x0 + (j + 0.5) * GRID, self.y0 + (i + 0.5) * GRID

    # ---------------------------------------------------------------- obstacles
    def set_outline(self, poly):
        inside = poly_mask((self.H, self.W), self.x0, self.y0, poly)
        d = ndimage.distance_transform_edt(inside) * GRID
        out = d < self.edge_clear
        for l in range(self.L):
            self.hard[l] |= out
        self.inside = inside

    def add_keepout(self, poly, layers=None):
        m = poly_mask((self.H, self.W), self.x0, self.y0, poly)
        for l, name in enumerate(self.layers):
            if layers is None or name in layers:
                self.hard[l] |= m

    def add_copper_poly(self, net, layer, poly):
        if layer not in self.layers:
            return
        l = self.layers.index(layer)
        m = poly_mask((self.H, self.W), self.x0, self.y0, poly)
        self._mark(l, m, net)

    def _mark(self, l, m, net):
        conflict = m & (self.label[l] >= 0) & (self.label[l] != net)
        self.label[l][m & (self.label[l] < 0)] = net
        if net < 0:
            self.hard[l] |= m
        return conflict.any()

    def add_track(self, net, layer, a, b, w):
        self.tracks.append((net, layer, a, b, w))
        if layer in self.layers:
            l = self.layers.index(layer)
            self._mark(l, seg_mask((self.H, self.W), self.x0, self.y0, a, b, w / 2), net)

    def add_via(self, net, p):
        self.vias.append((net, p))
        m = seg_mask((self.H, self.W), self.x0, self.y0, p, p, self.via_d / 2)
        for l in range(self.L):
            self._mark(l, m, net)

    # ---------------------------------------------------------------- free space
    def free_mask(self, net, w):
        r = self.clear + w / 2 + EPS
        free = np.zeros_like(self.hard)
        for l in range(self.L):
            other = ((self.label[l] >= 0) & (self.label[l] != net)) | (self.label[l] == -2)
            if other.any():
                d = ndimage.distance_transform_edt(~other) * GRID
                ok = d >= r
            else:
                ok = np.ones((self.H, self.W), bool)
            # hard keepouts (board edge etc.): the track centre must stay w/2 away
            hd = ndimage.distance_transform_edt(~self.hard[l]) * GRID
            free[l] = ok & (hd >= w / 2 + EPS)
        return free

    def via_mask(self, net):
        r = self.clear + self.via_d / 2 + EPS
        ok = np.ones((self.H, self.W), bool)
        for l in range(self.L):
            other = ((self.label[l] >= 0) & (self.label[l] != net)) | self.hard[l]
            d = ndimage.distance_transform_edt(~other) * GRID
            ok &= d >= r
        return ok

    # ---------------------------------------------------------------- A*
    def astar(self, net, starts, goals, w, free, vmask, goal_xy, via_cost=40.0, max_exp=4_000_000,
              layer_cost=None):
        """starts/goals: sets of (l, i, j). Returns list of (l, i, j) or None."""
        L, H, W = self.L, self.H, self.W
        gl = goal_xy
        gi, gj = int((gl[1] - self.y0) / GRID), int((gl[0] - self.x0) / GRID)
        INF = 1e18
        g = {}
        came = {}
        heap = []
        for s in starts:
            g[s] = 0.0
            heapq.heappush(heap, (self._h(s, gi, gj), 0.0, s))
        moves = [(0, 1, 1.0), (1, 0, 1.0), (0, -1, 1.0), (-1, 0, 1.0),
                 (1, 1, 1.4142), (1, -1, 1.4142), (-1, 1, 1.4142), (-1, -1, 1.4142)]
        exp = 0
        lc = layer_cost or [1.0] * L
        while heap:
            f, gc, cur = heapq.heappop(heap)
            if gc > g.get(cur, INF):
                continue
            if cur in goals:
                path = [cur]
                while path[-1] in came:
                    path.append(came[path[-1]])
                return path[::-1]
            exp += 1
            if exp > max_exp:
                return None
            l, i, j = cur
            prev = came.get(cur)
            pd = None if prev is None or prev[0] != l else (i - prev[1], j - prev[2])
            for di, dj, c in moves:
                ni, nj = i + di, j + dj
                if not (0 <= ni < H and 0 <= nj < W):
                    continue
                nxt = (l, ni, nj)
                if not free[l, ni, nj] and nxt not in goals:
                    continue
                if di and dj:
                    # no corner cutting
                    if not (free[l, i + di, j] or (l, i + di, j) in goals) or not (free[l, i, j + dj] or (l, i, j + dj) in goals):
                        continue
                cost = c * lc[l]
                if pd is not None and (di, dj) != pd:
                    cost += 0.6                       # bends
                ng = gc + cost
                if ng < g.get(nxt, INF):
                    g[nxt] = ng; came[nxt] = cur
                    heapq.heappush(heap, (ng + self._h(nxt, gi, gj), ng, nxt))
            if vmask[i, j]:
                for nl in range(L):
                    if nl == l:
                        continue
                    nxt = (nl, i, j)
                    if not free[nl, i, j] and nxt not in goals:
                        continue
                    ng = gc + via_cost
                    if ng < g.get(nxt, INF):
                        g[nxt] = ng; came[nxt] = cur
                        heapq.heappush(heap, (ng + self._h(nxt, gi, gj), ng, nxt))
        return None

    @staticmethod
    def _h(s, gi, gj):
        di, dj = abs(s[1] - gi), abs(s[2] - gj)
        return (max(di, dj) - min(di, dj)) + 1.4142 * min(di, dj)

    # ---------------------------------------------------------------- path → copper
    def commit(self, net, path, w, start_xy=None, end_xy=None):
        """Turns a cell path into straight segments + vias and registers them. start_xy/end_xy: exact pad
        centres joined to the first/last cell."""
        segs = []
        run = [path[0]]
        for c in path[1:]:
            if c[0] != run[-1][0]:
                segs.append(run); run = [c]
            else:
                run.append(c)
        segs.append(run)
        out = []
        for k, run in enumerate(segs):
            l = run[0][0]
            pts = [self.xy(c[1], c[2]) for c in run]
            if k == 0 and start_xy is not None:
                pts.insert(0, start_xy)
            if k == len(segs) - 1 and end_xy is not None:
                pts.append(end_xy)
            pts = simplify(pts)
            for a, b in zip(pts, pts[1:]):
                if a != b:
                    self.add_track(net, self.layers[l], a, b, w)
                    out.append((self.layers[l], a, b))
            if k < len(segs) - 1:
                self.add_via(net, pts[-1])
        return out


def simplify(pts):
    if len(pts) < 3:
        return pts
    out = [pts[0]]
    for k in range(1, len(pts) - 1):
        a, b, c = out[-1], pts[k], pts[k + 1]
        cross = (b[0] - a[0]) * (c[1] - b[1]) - (b[1] - a[1]) * (c[0] - b[0])
        if abs(cross) > 1e-9:
            out.append(b)
    out.append(pts[-1])
    return out
