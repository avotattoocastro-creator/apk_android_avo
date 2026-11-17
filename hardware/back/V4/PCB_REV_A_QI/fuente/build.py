"""Builds the KiCad project from avo_back_v4_pcb.py: places, routes, writes board, schematic, rules, BOM data."""
import json
import math
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import avo_back_v4_pcb as D                                   # noqa: E402
import board as B                                           # noqa: E402
import project                                              # noqa: E402
from fplib import emit, pad_poly, pad_center, pad_copper_layers, uid   # noqa: E402
from router import Router, GRID, seg_mask, poly_mask         # noqa: E402
from sexpr import Sym                                       # noqa: E402

S = Sym
PLANES = {D.GND: "In1.Cu"}                 # In1 = plano GND macizo
# In2 es capa de señal (+3V3 se rutea y se rellena con una zona +3V3 después del ruteado)
ROUTE_LAYERS = ["F.Cu", "In2.Cu", "B.Cu"]
CLEAR = 0.15
VIA = (0.5, 0.3)

# widths per net (mm)
WIDTH = {"QI_AC1": 0.5, "QI_AC2": 0.5, "QI_COIL1": 0.5, "QI_RECT": 0.4, D.VIN5: 0.4, D.VBUS: 0.4,
         D.VSYS: 0.5, D.VBAT: 0.5, "AD_SRC": 0.4, "BAT_IN": 0.5, "BAT_F": 0.5, D.VZED: 0.4, D.V3: 0.4, D.VSD: 0.3}
ORDER = ["QI_COIL1", "QI_AC1", "QI_AC2", "QI_BOOT1", "QI_BOOT2", "QI_CLAMP1", "QI_CLAMP2", "QI_COMM1",
         "QI_COMM2", "QI_RECT", "QI_ILIM", "QI_FOD", "QI_TS", D.VIN5, "AD_SRC", "QI_ADEN", D.VBUS, D.VBAT,
         "BAT_IN", "BAT_F", "BAT_G", "CHG_ISET", "CHG_ILIM", "CHG_TS", "CHG_EN2", D.VSYS, D.VZED, D.V3, D.VSD,
         "USB_DP_C", "USB_DM_C", "USB_DP", "USB_DM", "CC1", "CC2",
         "SD_CLK0", "SD_CLK", "SD_CMD", "SD_D0", "SD_D1", "SD_D2", "SD_D3", "SD_CD", "SD_PWR_N",
         "ZED_TX1_C", "ZED_TX1", "S3_TX1", "ZED_RX1", "ZED_TX2_C", "ZED_TX2", "S3_TX2", "ZED_RX2", "ZED_PPS_C", "ZED_PPS",
         "S3_ZRST", "ZED_RST", "ZED_EN", "EN", "BOOT", "LED", "LED_K", "U0TX", "U0RX", "HALL", "BAT_ADC",
         "CHG_PG", "CHG_STAT", "QI_CHG", "GPIO41"]


class Ctx:
    pass


def kpoly(pts):
    return [D.K(x, y) for x, y in pts]


def collect_pads():
    """Absolute pad records: (part, pad, net, layers, poly, center)."""
    out = []
    dummy = 100000
    for p in D.PARTS:
        fp = D.fp_of(p)
        cx, cy = D.kpos(p)
        for pd in fp.pads:
            ls = pad_copper_layers(pd)
            if pd.kind == "np_thru_hole":
                out.append(dict(part=p, pad=pd, net=None, layers=["F.Cu", "In1.Cu", "In2.Cu", "B.Cu"],
                                poly=pad_poly(pd, cx, cy, p["rot"]), c=pad_center(pd, cx, cy, p["rot"]), npth=True))
                continue
            if not ls:
                continue
            net = p["nets"].get(pd.num)
            if pd.num == "" and pd.kind == "smd":
                continue            # paste-only apertures
            out.append(dict(part=p, pad=pd, net=net, layers=ls, poly=pad_poly(pd, cx, cy, p["rot"]),
                            c=pad_center(pd, cx, cy, p["rot"]), npth=False))
    return out


def netid(n):
    return D.CODE[n] if n else -1


def build_router(pads):
    xs = [D.K(x, 0)[0] for x, _ in D.outline_pts()]
    ys = [D.K(0, y)[1] for _, y in D.outline_pts()]
    r = Router(min(xs) - 0.5, min(ys) - 0.5, max(xs) + 0.5, max(ys) + 0.5, ROUTE_LAYERS, CLEAR, VIA, 0.35)
    inside = poly_mask((r.H, r.W), r.x0, r.y0, kpoly(D.outline_pts(3)))
    if D.slot_prims():
        inside &= ~poly_mask((r.H, r.W), r.x0, r.y0, kpoly(D.prims_pts(D.slot_prims(), 10)))
    from scipy import ndimage
    d = ndimage.distance_transform_edt(inside) * GRID
    for l in range(r.L):
        r.hard[l] |= d < 0.35
    dummy = 90000
    for rec in pads:
        if rec["npth"]:
            pd = rec["pad"]
            from fplib import Pad
            big = Pad("", "np_thru_hole", "circle", pd.x, pd.y, pd.w + 0.25, pd.h + 0.25)
            poly = pad_poly(big, *D.kpos(rec["part"]), rec["part"]["rot"])
            for l in ROUTE_LAYERS:
                r.add_copper_poly(-2, l, poly)
            continue
        n = netid(rec["net"]) if rec["net"] else None
        if n is None:
            dummy += 1
            n = dummy
        for l in rec["layers"]:
            r.add_copper_poly(n, l, rec["poly"])
        if rec["pad"].kind == "thru_hole":       # drilled: inner planes are handled by KiCad
            pass
    return r


def pad_cells(r, rec, layer, free=None):
    l = r.layers.index(layer)
    m = poly_mask((r.H, r.W), r.x0, r.y0, rec["poly"])
    cells = np.argwhere(m)
    if free is not None:
        ok = [tuple(c) for c in cells if free[l, c[0], c[1]]]
        if ok:
            return [(l, i, j) for i, j in ok]
    # fall back to the cell of the pad centre
    i, j = r.ij(*rec["c"])
    return [(l, i, j)]


def via_drops(r, pads, log):
    """Connects every pad of a plane net (GND → In1, +3V3 → In2) with a short track and a via."""
    done = 0
    fails = []
    for rec in pads:
        net = rec["net"]
        if net not in PLANES or rec["npth"]:
            continue
        if rec["pad"].kind == "thru_hole":
            continue                                   # already reaches the planes
        fp = D.fp_of(rec["part"])
        if any(q.kind == "thru_hole" and q.num == rec["pad"].num for q in fp.pads):
            continue                                   # exposed pad with its own thermal vias
        if (rec["part"]["ref"], rec["pad"].num) in EP_STUB_PINS:
            continue                                   # joined to the exposed pad by a short stub (ep_stubs)
        if rec["part"]["ref"] == "U4" and rec["pad"].num not in ("1", "2", "42", "43", "46", "53", "60", "62", "63", "64", "65"):
            continue                                   # módulo: el resto se une por el relleno de F.Cu y las vías del EPAD
        nid = netid(net)
        layer = rec["layers"][0]
        if layer not in r.layers:
            continue
        w = 0.3
        free = r.free_mask(nid, w)
        vm = r.via_mask(nid) & ~drill_block(r, pads)
        # goal: any cell where a via fits, within 2.5 mm of the pad centre
        ci, cj = r.ij(*rec["c"])
        R = int(2.5 / GRID)
        i0, i1 = max(0, ci - R), min(r.H, ci + R); j0, j1 = max(0, cj - R), min(r.W, cj + R)
        l = r.layers.index(layer)
        sub = vm[i0:i1, j0:j1] & free[l, i0:i1, j0:j1]
        cand = np.argwhere(sub)
        if len(cand) == 0:
            fails.append(rec["part"]["ref"] + "." + rec["pad"].num)
            continue
        # skip if a via of the same net is already within 0.9 mm (shared via)
        near = [v for v in r.vias if v[0] == nid and math.hypot(v[1][0] - rec["c"][0], v[1][1] - rec["c"][1]) < 0.9]
        starts = pad_cells(r, rec, layer, free)
        goals = set((l, i0 + a, j0 + b) for a, b in cand)
        path = r.astar(nid, set(starts), goals, w, free, np.zeros_like(vm), rec["c"], max_exp=200000)
        if not path:
            fails.append(rec["part"]["ref"] + "." + rec["pad"].num)
            continue
        end = path[-1]
        exy = r.xy(end[1], end[2])
        if near and not path_inside_pad(path, r, rec):
            pass
        segs = r.commit(nid, path, w, start_xy=rec["c"])
        r.add_via(nid, exy)
        done += 1
    log.append("vías a planos: %d, sin vía: %s" % (done, ", ".join(fails) or "ninguna"))
    return fails


# GND pins of the QFNs that sit next to their exposed pad: a short inward stub joins them to it (the EP has its
# own thermal vias to the planes), so no fan-out via blocks the escape of the neighbouring signal pins.
EP_STUB_PINS = {("U2", "4"), ("U2", "6"), ("U2", "8"), ("U2", "15"), ("U1", "1"), ("U1", "20"), ("U1", "10"), ("U1", "11")}


def ep_stubs(r, pads):
    for rec in pads:
        key = (rec["part"]["ref"], rec["pad"].num)
        if key not in EP_STUB_PINS:
            continue
        cx, cy = D.kpos(rec["part"])
        px, py = rec["c"]
        dx, dy = cx - px, cy - py
        # straight inward along the pad's own axis (never diagonally towards a neighbour), 0.75 mm
        if abs(dx) >= abs(dy):
            end = (px + math.copysign(0.75, dx), py)
        else:
            end = (px, py + math.copysign(0.75, dy))
        r.add_track(D.CODE[D.GND], "F.Cu", (px, py), end, 0.2)


def drill_block(r, pads):
    """Cells too close to a drilled hole for another via (hole-to-hole ≥ 0.25 mm with 0.3 mm drills)."""
    m = np.zeros((r.H, r.W), bool)
    holes = [rec["c"] for rec in pads if rec["pad"].kind in ("thru_hole", "np_thru_hole")]
    holes += [p for _, p in r.vias]
    for c in holes:
        m |= seg_mask((r.H, r.W), r.x0, r.y0, c, c, 0.62)
    return m


def path_inside_pad(path, r, rec):
    return False


def route_nets(r, pads, log, prio=()):
    by_net = {}
    for rec in pads:
        if rec["net"] and not rec["npth"] and rec["net"] not in PLANES:
            by_net.setdefault(rec["net"], []).append(rec)
    nets = [n for n in ORDER if n in by_net] + sorted(n for n in by_net if n not in ORDER)
    nets = [n for n in prio if n in by_net] + [n for n in nets if n not in prio]
    failed = []
    for net in nets:
        recs = by_net[net]
        if len(recs) < 2:
            continue
        nid = netid(net)
        ok = False
        for w in ([WIDTH.get(net, 0.2), 0.3, 0.2] if WIDTH.get(net, 0.2) > 0.2 else [0.2]):
            snapshot = (r.label.copy(), list(r.tracks), list(r.vias))
            if route_tree(r, net, nid, recs, w):
                ok = True
                if w != WIDTH.get(net, 0.2):
                    log.append("%s: ancho reducido a %.2f" % (net, w))
                break
            r.label, r.tracks, r.vias = snapshot
        if not ok:
            failed.append(net)
    log.append("redes sin rutear: %s" % (", ".join(failed) or "ninguna"))
    return failed


def route_tree(r, net, nid, recs, w):
    free = r.free_mask(nid, w)
    vm = r.via_mask(nid)
    # order pads: start from the first, then nearest unconnected
    tree_cells = set()
    first = recs[0]
    connected = [first]
    for l in first["layers"]:
        if l in r.layers:
            tree_cells |= set(pad_cells(r, first, l, free))
    remaining = recs[1:]
    lc = [1.0, 1.3, 1.6]
    while remaining:
        # nearest remaining pad to the connected set
        def dist(rec):
            return min(math.hypot(rec["c"][0] - c["c"][0], rec["c"][1] - c["c"][1]) for c in connected)
        remaining.sort(key=dist)
        tgt = remaining.pop(0)
        goals = set()
        for l in tgt["layers"]:
            if l in r.layers:
                goals |= set(pad_cells(r, tgt, l, free))
        path = r.astar(nid, tree_cells, goals, w, free, vm, tgt["c"], via_cost=30, layer_cost=lc)
        if not path:
            return False
        # starting point: which pad / track does the path start on?
        start = path[0]
        sxy = None
        for c in connected:
            if (start[0], start[1], start[2]) in set(pad_cells(r, c, r.layers[start[0]], None)) or \
                    point_in(r.xy(start[1], start[2]), c["poly"]):
                sxy = c["c"]
                break
        r.commit(nid, path, w, start_xy=sxy, end_xy=tgt["c"])
        free = r.free_mask(nid, w)
        vm = r.via_mask(nid)
        tree_cells |= set(path)
        connected.append(tgt)
        for l in tgt["layers"]:
            if l in r.layers:
                tree_cells |= set(pad_cells(r, tgt, l, free))
    return True


def point_in(p, poly):
    return D.point_in_poly(p[0], p[1], poly)


# ======================================================================================= writers
def edge_bands(w=0.45):
    """Thin keepout polygons (tracks/vias only) inside each arc of the outline, so the router keeps
    0.3 mm from the real arcs although the DSN boundary approximates them with straight segments."""
    bands = []
    for pr in D.outline_prims() + D.slot_prims():
        if pr[0] != "arc":
            continue
        pts = D.sample_arc(pr[1], pr[2], pr[3], 6)
        c = D.arc_center(pr[1], pr[2], pr[3])
        rr = math.hypot(pts[0][0] - c[0], pts[0][1] - c[1])
        # the board lies on the side of the arc that contains the arc's chord midpoint... use the probe
        mid = pr[2]
        probe_in = (mid[0] + (c[0] - mid[0]) * 0.05, mid[1] + (c[1] - mid[1]) * 0.05)
        poly_outline = D.outline_pts(3)
        inside_towards_centre = D.point_in_poly(probe_in[0], probe_in[1], poly_outline) if pr in D.outline_prims() \
            else not D.point_in_poly(probe_in[0], probe_in[1], D.prims_pts(D.slot_prims(), 10))
        sgn = -1 if inside_towards_centre else 1
        inner = [(c[0] + (rr + sgn * w) * (x - c[0]) / rr, c[1] + (rr + sgn * w) * (y - c[1]) / rr) for x, y in pts]
        outer = [(c[0] + (rr - sgn * 0.05) * (x - c[0]) / rr, c[1] + (rr - sgn * 0.05) * (y - c[1]) / rr) for x, y in pts]
        bands.append(outer + inner[::-1])
    return bands


def write_board(r, path, outer_pours=True):
    tree = B.header(D.THICK)
    tree += B.nets_block(D.NETS)
    for p in D.PARTS:
        fp = D.fp_of(p)
        x, y = D.kpos(p)
        netmap = {}
        for pd in fp.pads:
            n = p["nets"].get(pd.num)
            if n:
                netmap[pd.num] = (D.CODE[n], n)
        props = {"LCSC": p["lcsc"], "MPN": p["mpn"] or p["value"]}
        if p["dnp"]:
            props["DNP"] = "1"
        tree.append(emit(fp, p["ref"], p["value"], x, y, p["rot"], netmap, props))
    # outline
    for pr in D.outline_prims() + D.slot_prims():
        if pr[0] == "line":
            tree.append(B.gr_line(D.K(*pr[1]), D.K(*pr[2]), "Edge.Cuts", 0.1))
        else:
            tree.append(B.gr_arc(D.K(*pr[1]), D.K(*pr[2]), D.K(*pr[3]), "Edge.Cuts", 0.1))
    # tracks and vias
    names = {v: k for k, v in D.CODE.items()}
    for (net, layer, a, b, w) in r.tracks:
        tree.append(B.segment(a, b, w, layer, net))
    seen = set()
    for (net, p) in r.vias:
        key = (round(p[0], 3), round(p[1], 3))
        if key in seen:
            continue
        seen.add(key)
        tree.append(B.via(p, net, *VIA))
    # zones
    poly = kpoly(D.outline_pts(3))
    tree.append(B.zone(D.CODE[D.GND], D.GND, "In1.Cu", poly, key="in1", connect="solid"))
    if outer_pours:
        tree.append(B.zone(D.CODE[D.V3], D.V3, "In2.Cu", poly, key="in2", connect="solid"))
    if outer_pours:      # Freerouting would take these as planes: the CI adds them after routing
        tree.append(B.zone(D.CODE[D.GND], D.GND, "F.Cu", poly, key="f"))
        tree.append(B.zone(D.CODE[D.GND], D.GND, "B.Cu", poly, key="b"))
    for k, band in enumerate(edge_bands()):
        tree.append(B.keepout(["F.Cu", "B.Cu"], kpoly(band), "BORDE_%02d" % k, copperpour=False))
    # texts
    tree.append(B.gr_text("AVO BACK V4 · REV " + D.REV + " · ESP32-S3 · " + D.DATE, *D.K(88.0, -9.0), "B.SilkS", 1.0, mirror=True))
    tree.append(B.gr_text("4 capas 1,0 mm · ENIG", *D.K(88.0, -11.0), "B.SilkS", 0.8, mirror=True, bold=False))
    tree.append(B.gr_text("BOBINA Qi DEBAJO", *D.K(83.0, -12.6), "B.SilkS", 0.8, mirror=True, bold=False))
    B.write(path, tree)


def main():
    t0 = time.time()
    log = []
    errs = D.check_placement()
    if errs:
        print("\n".join(errs))
        if "--force" not in sys.argv:
            sys.exit(1)
    pads = collect_pads()
    out = D.OUT
    if "--local" not in sys.argv:
        # placement + plane fan-outs only; Freerouting (CI) routes the signals
        log = []
        r = build_router(pads)
        add_epad_vias(r)
        ep_stubs(r, pads)
        fails_v = via_drops(r, pads, log)
        # short critical connections pre-routed here (Freerouting keeps them): Qi pump capacitors, USB, battery
        # rev. 2 (V4): sin pre-ruteo del bloque Qi; los pre-ruteos bloqueados encajonaban U1 y Freerouting no
        # podía terminar sus redes. Se dejan solo USB, CC y los pines del cargador.
        PRE_QI = "--pre-qi" in sys.argv
        pre = ["QI_BOOT1", "QI_BOOT2", "QI_CLAMP1", "QI_CLAMP2", "QI_COMM1", "QI_COMM2", "QI_FOD", "QI_TS",
               "QI_RECT", D.VIN5, "USB_DP_C", "USB_DM_C", "CC1", "CC2", "CHG_ILIM", "CHG_ISET", "CHG_TS"]
        # local pieces of long nets: the pin and its pull-up/neighbour (Freerouting finishes the long run)
        pairs = [("CHG_PG", ["U2.7", "R9.1"]), ("CHG_STAT", ["U2.9", "R10.1"]), ("QI_CHG", ["U1.7", "R4.1"]),
                 ("QI_ADEN", ["U1.8", "Q1.1", "Q2.1"]), ("CHG_EN2", ["U2.5", "R8.1"])]
        if not PRE_QI:
            pre = [n for n in pre if not n.startswith("QI_") and n != D.VIN5]
            pairs = [pr for pr in pairs if not pr[0].startswith("QI_")]
        for net, refs in pairs:
            recs = [rec for rec in pads if rec["net"] == net and "%s.%s" % (rec["part"]["ref"], rec["pad"].num) in refs]
            if len(recs) > 1 and not route_tree(r, net, netid(net), recs, 0.2):
                log.append("pre-ruteo local fallido: " + net)
        by_net = {}
        for rec in pads:
            if rec["net"] in pre and not rec["npth"]:
                by_net.setdefault(rec["net"], []).append(rec)
        for net in pre:
            if net in by_net and len(by_net[net]) > 1:
                w = 0.3 if (net.startswith("QI_AC") or net in ("QI_COIL1", "QI_RECT", D.VIN5, D.VBUS, "AD_SRC")) else 0.2
                if not route_tree(r, net, netid(net), by_net[net], w) and not route_tree(r, net, netid(net), by_net[net], 0.2):
                    log.append("pre-ruteo fallido: " + net)
        write_board(r, os.path.join(out, "AVO_BACK_V4_PCB_colocacion.kicad_pcb"), outer_pours=False)
        stale = os.path.join(out, "AVO_BACK_V4_PCB_ruteado.kicad_pcb")
        if os.path.exists(stale):
            os.remove(stale)            # the routed board belongs to the previous placement
        print("\n".join(log))
        import plot
        plot.draw(os.path.join(out, "..", "out_local_colocacion.png"), r.tracks, r.vias, "colocación + vías a planos")
        import write_sch
        import shutil
        write_sch.write(os.path.join(out, "AVO_BACK_V4_PCB.kicad_sch"), os.path.join(out, "AVO_BACK_V4_PCB.kicad_pro"),
                        os.path.join(out, "piezas.json"))
        shutil.copy(os.path.join(out, "AVO_BACK_V4_PCB.kicad_pro"), os.path.join(out, "AVO_BACK_V4_PCB_colocacion.kicad_pro"))
        print("tiempo %.0f s" % (time.time() - t0))
        return
    prio = []
    for attempt in range(4):
        r, failed, fails_v, log = attempt_route(pads, prio)
        print("intento %d: sin rutear %s" % (attempt + 1, failed), flush=True)
        if not failed:
            break
        prio = failed + [n for n in prio if n not in failed]
    out = D.OUT
    write_board(r, os.path.join(out, "AVO_BACK_V4_PCB.kicad_pcb"))
    log.append("tiempo %.0f s, pistas %d, vías %d" % (time.time() - t0, len(r.tracks), len(r.vias)))
    print("\n".join(log))
    import plot
    plot.draw(os.path.join(out, "..", "out_local_ruteado.png"), r.tracks, r.vias, "ruteado (vista previa local)")
    json.dump(dict(failed=failed, via_fails=fails_v), open(os.path.join(out, "..", "out_local_route.json"), "w"))
    import write_sch
    write_sch.write(os.path.join(out, "AVO_BACK_V4_PCB.kicad_sch"), os.path.join(out, "AVO_BACK_V4_PCB.kicad_pro"),
                    os.path.join(out, "piezas.json"))


def add_epad_vias(r):
    """Vías en las rendijas del EPAD del módulo (GND)."""
    u4 = next(p for p in D.PARTS if p["ref"] == "U4")
    from fplib import rot
    cx, cy = D.kpos(u4)
    ep = [pd for pd in D.fp_of(u4).pads if pd.num == "61" and pd.shape == "rect"]
    xs = sorted({round(pd.x, 4) for pd in ep}); ys = sorted({round(pd.y, 4) for pd in ep})
    for vx in [(a + b) / 2 for a, b in zip(xs, xs[1:])]:          # gaps between the 3 × 3 EPAD squares
        for vy in [(a + b) / 2 for a, b in zip(ys, ys[1:])]:
            dx, dy = rot(vx, vy, u4["rot"])
            r.add_via(D.CODE[D.GND], (cx + dx, cy + dy))


def attempt_route(pads, prio):
    log = []
    r = build_router(pads)
    add_epad_vias(r)
    fails_v = via_drops(r, pads, log)
    failed = route_nets(r, pads, log, prio)
    return r, failed, fails_v, log


if __name__ == "__main__":
    main()
