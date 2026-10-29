"""Completes the routing that Freerouting left unfinished.

Reads the board routed in CI (kicad/AVO_BACK_V4_PCB.kicad_pcb), checks that every footprint is where the generator
puts it, rebuilds the connectivity of every signal net from the real copper (pads, tracks, vias), and routes each
missing link with the grid router (same clearances as the net class). Writes kicad/AVO_BACK_V4_PCB_ruteado.kicad_pcb,
which the CI then uses as is (no Freerouting) and checks with KiCad's DRC.

Usage: python repair.py            → report + repaired board
       python repair.py --check    → report only
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import avo_back_v4_pcb as D                                    # noqa: E402
import build                                                 # noqa: E402
from router import GRID, poly_mask, seg_mask                 # noqa: E402
from sexpr import find, find_all, parse                      # noqa: E402

SIGNAL_W = {"Potencia": 0.3, "Qi_AC": 0.3, "Default": 0.2}
POWER = {"QI_RECT", D.VBAT, D.VBUS, D.VIN5, D.VSYS, "BAT_IN", "BAT_F", D.VZED}
QIAC = {"QI_AC1", "QI_AC2", "QI_COIL1"}


def net_width(n):
    return 0.3 if (n in POWER or n in QIAC) else 0.2


# ------------------------------------------------------------------------------------------- geometry
def seg_seg(a, b, c, d):
    def ps(p, q, r):
        dx, dy = r[0] - q[0], r[1] - q[1]
        L2 = dx * dx + dy * dy
        t = 0 if L2 == 0 else max(0, min(1, ((p[0] - q[0]) * dx + (p[1] - q[1]) * dy) / L2))
        return math.hypot(p[0] - q[0] - t * dx, p[1] - q[1] - t * dy)

    def cross(o, p, q):
        return (p[0] - o[0]) * (q[1] - o[1]) - (p[1] - o[1]) * (q[0] - o[0])
    d1, d2, d3, d4 = cross(c, d, a), cross(c, d, b), cross(a, b, c), cross(a, b, d)
    if ((d1 > 0) != (d2 > 0)) and ((d3 > 0) != (d4 > 0)):
        return 0.0
    return min(ps(a, c, d), ps(b, c, d), ps(c, a, b), ps(d, a, b))


def seg_poly(a, b, poly):
    if D.point_in_poly(a[0], a[1], poly) or D.point_in_poly(b[0], b[1], poly):
        return 0.0
    n = len(poly)
    return min(seg_seg(a, b, poly[k], poly[(k + 1) % n]) for k in range(n))


# ------------------------------------------------------------------------------------------- board reading
def read_board(path):
    t = parse(open(path, encoding="utf-8").read())
    names = {}
    for it in find_all(t, "net"):
        names[it[1]] = it[2]
    segs, vias, fps = [], [], {}
    for it in t:
        if not isinstance(it, list) or not it:
            continue
        if it[0] == "segment":
            st, en = find(it, "start"), find(it, "end")
            segs.append(dict(net=names.get(find(it, "net")[1], ""), layer=find(it, "layer")[1],
                             a=(st[1], st[2]), b=(en[1], en[2]), w=find(it, "width")[1]))
        elif it[0] == "via":
            at = find(it, "at")
            vias.append(dict(net=names.get(find(it, "net")[1], ""), p=(at[1], at[2]), d=find(it, "size")[1],
                             drill=find(it, "drill")[1]))
        elif it[0] == "footprint":
            ref = [p for p in it if isinstance(p, list) and p and p[0] == "property" and p[1] == "Reference"][0][2]
            at = find(it, "at")
            fps[ref] = (at[1], at[2], at[3] if len(at) > 3 else 0)
    return segs, vias, fps


def check_positions(fps):
    bad = []
    for p in D.PARTS:
        x, y = D.kpos(p)
        q = fps.get(p["ref"])
        if q is None or abs(q[0] - x) > 1e-3 or abs(q[1] - y) > 1e-3 or abs((q[2] - p["rot"]) % 360) > 1e-3:
            bad.append(p["ref"])
    return bad


# ------------------------------------------------------------------------------------------- connectivity
class UF:
    def __init__(self, n):
        self.p = list(range(n))

    def f(self, i):
        while self.p[i] != i:
            self.p[i] = self.p[self.p[i]]
            i = self.p[i]
        return i

    def u(self, a, b):
        a, b = self.f(a), self.f(b)
        if a != b:
            self.p[a] = b


def clusters(net, pads, segs, vias):
    items = []      # (kind, data)
    for rec in pads:
        if rec["net"] == net and not rec["npth"]:
            items.append(("pad", rec))
    for s in segs:
        if s["net"] == net:
            items.append(("seg", s))
    for v in vias:
        if v["net"] == net:
            items.append(("via", v))
    uf = UF(len(items))

    def layers(it):
        k, d = it
        if k == "pad":
            return set(d["layers"])
        if k == "seg":
            return {d["layer"]}
        return {"F.Cu", "In1.Cu", "In2.Cu", "B.Cu"}

    def touch(i, j):
        (ki, di), (kj, dj) = items[i], items[j]
        if not (layers(items[i]) & layers(items[j])):
            return False
        if ki == "pad" and kj == "pad":
            return False          # pads of the same net never touch by design
        if ki == "pad" or kj == "pad":
            pad, other = (di, (kj, dj)) if ki == "pad" else (dj, (ki, di))
            k2, d2 = other
            if k2 == "seg":
                return seg_poly(d2["a"], d2["b"], pad["poly"]) <= d2["w"] / 2 + 1e-3
            return seg_poly(d2["p"], d2["p"], pad["poly"]) <= d2["d"] / 2 + 1e-3
        if ki == "seg" and kj == "seg":
            return seg_seg(di["a"], di["b"], dj["a"], dj["b"]) <= (di["w"] + dj["w"]) / 2 + 1e-3
        s, v = (di, dj) if ki == "seg" else (dj, di)
        if ki == "via" and kj == "via":
            return math.hypot(di["p"][0] - dj["p"][0], di["p"][1] - dj["p"][1]) <= (di["d"] + dj["d"]) / 2
        return seg_seg(s["a"], s["b"], v["p"], v["p"]) <= s["w"] / 2 + v["d"] / 2 + 1e-3

    n = len(items)
    for i in range(n):
        for j in range(i + 1, n):
            if touch(i, j):
                uf.u(i, j)
    groups = {}
    for i in range(n):
        groups.setdefault(uf.f(i), []).append(items[i])
    # only groups that contain a pad matter (stray copper is reported apart)
    with_pad = [g for g in groups.values() if any(k == "pad" for k, _ in g)]
    stray = [g for g in groups.values() if not any(k == "pad" for k, _ in g)]
    return with_pad, stray


def group_cells(r, g, free, w):
    cells = set()
    for k, d in g:
        if k == "pad":
            for l in d["layers"]:
                if l in r.layers:
                    cells |= set(build.pad_cells(r, d, l, free))
        elif k == "seg":
            if d["layer"] in r.layers:
                l = r.layers.index(d["layer"])
                m = seg_mask((r.H, r.W), r.x0, r.y0, d["a"], d["b"], max(0.02, d["w"] / 2 - 0.05))
                for i, j in np.argwhere(m):
                    cells.add((l, i, j))
        else:
            for l in range(r.L):
                i, j = r.ij(*d["p"])
                cells.add((l, i, j))
    return cells


def prune(pads, segs, vias):
    """Removes track stubs with a free end (and signal vias that join nothing) — repeat until stable."""
    removed = 0
    changed = True
    while changed:
        changed = False
        for s in list(segs):
            if s["net"] in build.PLANES or not s["net"]:
                continue
            for end in (s["a"], s["b"]):
                hit = False
                for rec in pads:
                    if rec["net"] == s["net"] and not rec["npth"] and s["layer"] in rec["layers"] and \
                            seg_poly(end, end, rec["poly"]) <= s["w"] / 2 + 1e-3:
                        hit = True; break
                if not hit:
                    for v in vias:
                        if v["net"] == s["net"] and math.hypot(v["p"][0] - end[0], v["p"][1] - end[1]) <= v["d"] / 2 + 1e-3:
                            hit = True; break
                if not hit:
                    for t in segs:
                        if t is not s and t["net"] == s["net"] and t["layer"] == s["layer"] and \
                                seg_seg(end, end, t["a"], t["b"]) <= (s["w"] + t["w"]) / 2 + 1e-3:
                            hit = True; break
                if not hit:
                    segs.remove(s); removed += 1; changed = True
                    break
        for v in list(vias):
            if v["net"] in build.PLANES or not v["net"]:
                continue
            n = sum(1 for t in segs if t["net"] == v["net"] and
                    seg_seg(v["p"], v["p"], t["a"], t["b"]) <= v["d"] / 2 + t["w"] / 2 + 1e-3)
            n += sum(1 for rec in pads if rec["net"] == v["net"] and seg_poly(v["p"], v["p"], rec["poly"]) <= v["d"] / 2)
            if n < 2:
                vias.remove(v); removed += 1; changed = True
    return removed


def make_router(pads, segs, vias):
    r = build.build_router(pads)
    for s in segs:
        r.add_track(D.CODE.get(s["net"], -1) if s["net"] else -2, s["layer"], s["a"], s["b"], s["w"])
    for v in vias:
        r.vias.append((D.CODE.get(v["net"], -1), v["p"]))
        m = seg_mask((r.H, r.W), r.x0, r.y0, v["p"], v["p"], v["d"] / 2)
        for l in range(r.L):
            r._mark(l, m, D.CODE.get(v["net"], -1))
    return r


def try_route(r, pads, net, nid, g):
    for w in (net_width(net), 0.2):
        free = r.free_mask(nid, w)
        vm = r.via_mask(nid) & ~build.drill_block(r, pads)
        a = group_cells(r, g[0], free, w)
        best = None
        for k in range(1, len(g)):
            b = group_cells(r, g[k], free, w)
            tgt = next(d for kk, d in g[k] if kk == "pad")["c"]
            path = r.astar(nid, a, b, w, free, vm, tgt, via_cost=30, layer_cost=[1.0, 1.3, 1.6])
            if path and (best is None or len(path) < len(best)):
                best = path
        if best:
            return best, w
    return None, None


def main():
    src = os.path.join(D.OUT, "AVO_BACK_V4_PCB_colocacion.kicad_pcb" if "--from-placement" in sys.argv
                       else "AVO_BACK_V4_PCB.kicad_pcb")
    segs, vias, fps = read_board(src)
    bad = check_positions(fps)
    if bad:
        print("La placa ruteada no corresponde a la colocación actual: %s" % ", ".join(bad[:12]))
        sys.exit(2)
    pads = build.collect_pads()
    r = make_router(pads, segs, vias)
    report = []
    pending = []
    for net in D.NETS:
        if net in build.PLANES:
            continue
        g, stray = clusters(net, pads, segs, vias)
        if len(g) > 1:
            pending.append(net)
            report.append("%s: %d grupos sin unir (%s)" % (
                net, len(g), " | ".join(",".join("%s.%s" % (d["part"]["ref"], d["pad"].num)
                                                  for k, d in grp if k == "pad") for grp in g)))
    print("Conexiones pendientes en la placa del CI: %d redes" % len(pending))
    for line in report:
        print("  " + line)
    if "--check" in sys.argv:
        sys.exit(1 if pending else 0)
    queue = list(pending)
    ripped = {}
    failed = []
    fixed = set()
    it = 0
    while queue and it < 400:
        it += 1
        net = queue.pop(0)
        g, _ = clusters(net, pads, segs, vias)
        if len(g) <= 1:
            continue
        nid = D.CODE[net]
        # 1) normal route between the first group and the nearest other group
        path, w = try_route(r, pads, net, nid, g)
        if path:
            nv = len(r.vias)
            for (layer, p0, p1) in r.commit(nid, path, w):
                segs.append(dict(net=net, layer=layer, a=p0, b=p1, w=w))
            for (vn, vp) in r.vias[nv:]:
                vias.append(dict(net=net, p=vp, d=build.VIA[0], drill=build.VIA[1]))
            fixed.add(net)
            queue.insert(0, net)                  # more groups may remain
            continue
        # 2) rip-up: route ignoring other nets' tracks, then remove the tracks in the way and re-queue their nets
        if ripped.get(net, 0) >= 6:
            failed.append(net)
            continue
        ripped[net] = ripped.get(net, 0) + 1
        r2 = make_router(pads, [s_ for s_ in segs if s_["net"] == net], vias)
        path, w = try_route(r2, pads, net, nid, g)
        if not path:
            failed.append(net)
            continue
        nv = len(r2.vias)
        new = r2.commit(nid, path, w)
        newvias = [vp for (vn, vp) in r2.vias[nv:]]
        victims = set()
        for s_ in list(segs):
            if s_["net"] == net or not s_["net"]:
                continue
            for (layer, p0, p1) in new:
                if layer == s_["layer"] and seg_seg(p0, p1, s_["a"], s_["b"]) < (w + s_["w"]) / 2 + build.CLEAR + 0.02:
                    segs.remove(s_); victims.add(s_["net"]); break
            else:
                for vp in newvias:
                    if seg_seg(vp, vp, s_["a"], s_["b"]) < build.VIA[0] / 2 + s_["w"] / 2 + build.CLEAR + 0.02:
                        segs.remove(s_); victims.add(s_["net"]); break
        for (layer, p0, p1) in new:
            segs.append(dict(net=net, layer=layer, a=p0, b=p1, w=w))
        for vp in newvias:
            vias.append(dict(net=net, p=vp, d=build.VIA[0], drill=build.VIA[1]))
        prune(pads, segs, vias)
        r = make_router(pads, segs, vias)
        fixed.add(net)
        print("  rip-up para %s: se rehacen %s" % (net, ", ".join(sorted(victims)) or "—"))
        queue.insert(0, net)
        for v in sorted(victims):
            if v not in queue and v not in build.PLANES:
                queue.append(v)
    # final status
    left = []
    for net in D.NETS:
        if net in build.PLANES:
            continue
        g, _ = clusters(net, pads, segs, vias)
        if len(g) > 1:
            left.append(net)
    failed = sorted(set(left))
    fixed = sorted(n for n in fixed if n not in failed)
    removed = prune(pads, segs, vias)
    print("Tramos colgantes eliminados: %d" % removed)
    print("Reparadas: %s" % (", ".join(fixed) or "ninguna"))
    print("Sin reparar: %s" % (", ".join(failed) or "ninguna"))
    # rebuild router track list for the writer (imported + new)
    r.tracks = [(D.CODE.get(s["net"], 0), s["layer"], s["a"], s["b"], s["w"]) for s in segs if s["net"]]
    r.vias = [(D.CODE.get(v["net"], 0), v["p"]) for v in vias if v["net"]]
    out = os.path.join(D.OUT, "AVO_BACK_V4_PCB_ruteado.kicad_pcb")
    build.write_board(r, out, outer_pours=True)
    import plot
    plot.draw(os.path.join(D.OUT, "..", "out_local_reparado.png"), r.tracks, r.vias, "ruteado reparado")
    print("Escrito", out)
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
