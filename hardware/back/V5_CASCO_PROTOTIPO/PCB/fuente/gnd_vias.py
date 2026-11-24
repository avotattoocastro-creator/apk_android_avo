"""Pads de masa SMD sin vía propia al plano In1 (24/11, tras sacar las vías de los pads): les busca una vía fuera de
cualquier pad (2,5 → 4 mm); donde no cabe ninguna (junto a U11/U4), los une con una pista a la vía de masa existente
más cercana (≤ 5 mm). Lee y escribe kicad/..._ruteado.kicad_pcb.

Uso: python gnd_vias.py            → arregla todos los pads de masa sin vía
     python gnd_vias.py --check    → solo lista
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import avo_back_v5_pcb as D   # noqa: E402
import build                  # noqa: E402
import repair                 # noqa: E402

# pads de masa que ya bajan al plano por otro camino a propósito (sin vía propia): stubs al EP del BQ24072 y los del
# diseño original que tampoco la tenían
SIN_VIA_OK = {"U2.4", "U2.6", "U2.8", "U2.15", "U2.17"}   # U2.17 = EP con vías térmicas de la huella


def missing(pads, segs, vias):
    g, _ = repair.clusters(D.GND, pads, segs, vias)
    out = set()
    for grp in g:
        if not any(k == "via" for k, _ in grp):
            for k, d in grp:
                if k == "pad" and d["pad"].kind == "smd":
                    out.add((d["part"]["ref"], d["pad"].num))
    return out


def join_one(r, rec, pads, segs, vias, name):
    """Une el pad (misma capa) a una vía de masa o a cobre de masa que ya baja al plano (≤ 5 mm). True si lo consigue."""
    import math
    import numpy as np
    from router import seg_mask, poly_mask
    nid = D.CODE[D.GND]
    l = r.layers.index(rec["layers"][0])
    conn = np.zeros((r.H, r.W), bool)
    g, _ = repair.clusters(D.GND, pads, segs, vias)
    for grp in g:
        if not any(k == "via" for k, _ in grp):
            continue
        for k, d in grp:
            if k == "pad" and rec["layers"][0] in d["layers"] and not d["npth"]:
                conn |= poly_mask((r.H, r.W), r.x0, r.y0, d["poly"])
            elif k == "seg" and d["layer"] == rec["layers"][0]:
                conn |= seg_mask((r.H, r.W), r.x0, r.y0, d["a"], d["b"], 0.05)
            elif k == "via":
                conn |= seg_mask((r.H, r.W), r.x0, r.y0, d["p"], d["p"], 0.12)
    ci, cj = r.ij(*rec["c"]); R = int(5.0 / 0.05)
    win = np.zeros((r.H, r.W), bool); win[max(0, ci - R):ci + R, max(0, cj - R):cj + R] = True
    conn &= win
    for w in (0.3, 0.2):
        free = r.free_mask(nid, w)
        goals = set((l, i, j) for i, j in np.argwhere(conn & free[l]))
        if not goals:
            continue
        starts = build.pad_cells(r, rec, rec["layers"][0], free)
        path = r.astar(nid, set(starts), goals, w, free, np.zeros((r.H, r.W), bool), rec["c"], max_exp=400000)
        if path:
            nt = len(r.tracks)
            r.commit(nid, path, w, start_xy=rec["c"])
            for (net, layer, a, b, ww) in r.tracks[nt:]:
                segs.append(dict(net=name[net], layer=layer, a=a, b=b, w=ww))
            return True
    return False


def join_existing(pads, segs, vias, todo, name):
    for key in sorted(todo):
        rec = [x for x in pads if (x["part"]["ref"], x["pad"].num) == key][0]
        r = repair.make_router(pads, segs, vias)
        ok = join_one(r, rec, pads, segs, vias, name)
        print("  %s.%s: %s" % (key[0], key[1], "unido a masa conectada al plano" if ok else "SIN conexión al plano"))
    left = {k for k in missing(pads, segs, vias) if "%s.%s" % k not in SIN_VIA_OK}
    print("Quedan sin vía: %s" % (", ".join(sorted("%s.%s" % k for k in left)) or "ninguno"))
    return left


def clear_and_drop(pads, segs, vias, todo, name, half=2.0):
    """Para cada pad pendiente: quita las pistas/vías de señal de una caja de ±half mm, pone la vía de masa y vuelve a
    unir las redes quitadas. Si alguna no se une, deshace ese pad (no empeora la placa)."""
    import copy
    for key in sorted(todo):
        rec = [x for x in pads if (x["part"]["ref"], x["pad"].num) == key][0]
        cx, cy = rec["c"]
        x0, y0, x1, y1 = cx - half, cy - half, cx + half, cy + half
        inb = lambda p: x0 <= p[0] <= x1 and y0 <= p[1] <= y1
        box = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        s_bak, v_bak = copy.deepcopy(segs), copy.deepcopy(vias)
        hit = set(t["net"] for t in segs if t["net"] and t["net"] not in build.PLANES and
                  (inb(t["a"]) or inb(t["b"]) or repair.seg_poly(t["a"], t["b"], box) <= t["w"] / 2))
        hit |= set(v["net"] for v in vias if v["net"] and v["net"] not in build.PLANES and inb(v["p"]))
        segs[:] = [t for t in segs if not (t["net"] in hit and (inb(t["a"]) or inb(t["b"]) or
                                                                repair.seg_poly(t["a"], t["b"], box) <= t["w"] / 2))]
        vias[:] = [v for v in vias if not (v["net"] in hit and inb(v["p"]))]
        repair.prune(pads, segs, vias)
        r = repair.make_router(pads, segs, vias)
        nt, nv = len(r.tracks), len(r.vias)
        log = []
        build.via_drops(r, pads, log, only={key}, radius=2.0)
        ok = len(r.vias) > nv
        for (net, layer, a, b, w) in r.tracks[nt:]:
            segs.append(dict(net=name[net], layer=layer, a=a, b=b, w=w))
        for (net, p) in r.vias[nv:]:
            vias.append(dict(net=name[net], p=p, d=build.VIA[0], drill=build.VIA[1]))
        if not ok:
            ok = join_one(r, rec, pads, segs, vias, name)
        if ok:
            for net in sorted(hit):
                while ok:
                    g, _ = repair.clusters(net, pads, segs, vias)
                    if len(g) <= 1:
                        break
                    path, w = repair.try_route(r, pads, net, D.CODE[net], g)
                    if not path:
                        ok = False
                        break
                    nv2 = len(r.vias)
                    for (layer, a, b) in r.commit(D.CODE[net], path, w):
                        segs.append(dict(net=net, layer=layer, a=a, b=b, w=w))
                    for (_, vp) in r.vias[nv2:]:
                        vias.append(dict(net=net, p=vp, d=build.VIA[0], drill=build.VIA[1]))
        if ok:
            print("  %s.%s: vía de masa puesta despejando %s" % (key[0], key[1], ", ".join(sorted(hit)) or "—"))
        else:
            segs[:], vias[:] = s_bak, v_bak
            print("  %s.%s: no se pudo (se deja como estaba)" % key)
    left = {k for k in missing(pads, segs, vias) if "%s.%s" % k not in SIN_VIA_OK}
    print("Quedan sin vía: %s" % (", ".join(sorted("%s.%s" % k for k in left)) or "ninguno"))
    return left


def ripup_drop(pads, segs, vias, todo, name):
    """Bajada de masa con rip-up mínimo: se traza ignorando las pistas de las demás redes (solo pads y masa), se quitan las
    pistas/vías que estorban y esas redes se vuelven a unir. Si alguna no se une, se deshace ese pad."""
    import copy
    import math
    for key in sorted(todo):
        rec = [x for x in pads if (x["part"]["ref"], x["pad"].num) == key][0]
        s_bak, v_bak = copy.deepcopy(segs), copy.deepcopy(vias)
        r2 = repair.make_router(pads, [t for t in segs if t["net"] == D.GND], [v for v in vias if v["net"] == D.GND])
        nt, nv = len(r2.tracks), len(r2.vias)
        log = []
        if "--unir-ripup" in sys.argv:   # en vez de vía nueva: pista a masa ya conectada al plano
            tmp = []
            join_one(r2, rec, pads, [t for t in segs if t["net"] == D.GND] + tmp, [v for v in vias if v["net"] == D.GND], name)
        else:
            build.via_drops(r2, pads, log, only={key}, radius=2.0)
        new_t = r2.tracks[nt:]
        new_v = [p for _, p in r2.vias[nv:]]
        if not new_v and not new_t:
            print("  %s.%s: ni ignorando las demás redes cabe una vía" % key)
            continue
        victims = set()
        cl = build.CLEAR + 0.02
        for t in list(segs):
            if t["net"] in (D.GND, "") or t["net"] in build.PLANES:
                continue
            bad = any(lay == t["layer"] and repair.seg_seg(a, b, t["a"], t["b"]) < (w + t["w"]) / 2 + cl
                      for (_, lay, a, b, w) in new_t)
            bad = bad or any(repair.seg_seg(vp, vp, t["a"], t["b"]) < build.VIA[0] / 2 + t["w"] / 2 + cl for vp in new_v)
            if bad:
                segs.remove(t); victims.add(t["net"])
        for v in list(vias):
            if v["net"] == D.GND:
                continue
            if any(math.hypot(v["p"][0] - vp[0], v["p"][1] - vp[1]) < build.VIA[0] + cl for vp in new_v) or \
                    any(lay in ("F.Cu", "In2.Cu") and repair.seg_seg(v["p"], v["p"], a, b) < build.VIA[0] / 2 + w / 2 + cl
                        for (_, lay, a, b, w) in new_t):
                vias.remove(v); victims.add(v["net"])
        for (net, lay, a, b, w) in new_t:
            segs.append(dict(net=D.GND, layer=lay, a=a, b=b, w=w))
        for vp in new_v:
            vias.append(dict(net=D.GND, p=vp, d=build.VIA[0], drill=build.VIA[1]))
        pre = {net: len(repair.clusters(net, pads, s_bak, v_bak)[0]) for net in victims}
        repair.prune(pads, segs, vias)
        r = repair.make_router(pads, segs, vias)
        ok = True
        for net in sorted(victims):
            while ok:
                g, _ = repair.clusters(net, pads, segs, vias)
                if len(g) <= max(1, pre[net]):   # igual o mejor que antes (VBUS/VSYS ya venían partidas)
                    break
                path, w = repair.try_route(r, pads, net, D.CODE[net], g)
                if not path:
                    ok = False
                    print("  %s.%s: %s no se vuelve a unir" % (key[0], key[1], net))
                    break
                nv2 = len(r.vias)
                for (layer, a, b) in r.commit(D.CODE[net], path, w):
                    segs.append(dict(net=net, layer=layer, a=a, b=b, w=w))
                for (_, vp) in r.vias[nv2:]:
                    vias.append(dict(net=net, p=vp, d=build.VIA[0], drill=build.VIA[1]))
        if ok:
            print("  %s.%s: vía de masa con rip-up de %s" % (key[0], key[1], ", ".join(sorted(victims)) or "—"))
        else:
            segs[:], vias[:] = s_bak, v_bak
    left = {k for k in missing(pads, segs, vias) if "%s.%s" % k not in SIN_VIA_OK}
    print("Quedan sin vía: %s" % (", ".join(sorted("%s.%s" % k for k in left)) or "ninguno"))
    return left


def main():
    path = os.path.join(D.OUT, "AVO_BACK_V5P_PCB_ruteado.kicad_pcb")
    segs, vias, _ = repair.read_board(path)
    pads = build.collect_pads()
    todo = {k for k in missing(pads, segs, vias) if "%s.%s" % k not in SIN_VIA_OK}
    print("Pads de masa sin vía: %s" % (", ".join(sorted("%s.%s" % k for k in todo)) or "ninguno"))
    if "--check" in sys.argv or not todo:
        sys.exit(1 if todo else 0)
    name = {c: n for n, c in D.CODE.items()}
    for radius in (() if "--solo-unir" in sys.argv else (2.5, 4.0)):
        r = repair.make_router(pads, segs, vias)
        nt, nv = len(r.tracks), len(r.vias)
        log = []
        build.via_drops(r, pads, log, only=todo, radius=radius)
        for (net, layer, a, b, w) in r.tracks[nt:]:
            segs.append(dict(net=name[net], layer=layer, a=a, b=b, w=w))
        for (net, p) in r.vias[nv:]:
            vias.append(dict(net=name[net], p=p, d=build.VIA[0], drill=build.VIA[1]))
        todo = {k for k in missing(pads, segs, vias) if "%s.%s" % k not in SIN_VIA_OK}
        print("radio %.1f mm: %s · quedan %s" % (radius, "; ".join(log), ", ".join(sorted("%s.%s" % k for k in todo)) or "ninguno"))
        if not todo:
            break
    if todo and "--sin-unir" not in sys.argv:
        todo = join_existing(pads, segs, vias, todo, name)
    if todo and "--ripup" in sys.argv:
        todo = ripup_drop(pads, segs, vias, todo, name)
    if todo and "--despejar" in sys.argv:
        todo = clear_and_drop(pads, segs, vias, todo, name)
    r = repair.make_router(pads, segs, vias)
    r.tracks = [(D.CODE.get(s["net"], 0), s["layer"], s["a"], s["b"], s["w"]) for s in segs if s["net"]]
    r.vias = [(D.CODE.get(v["net"], 0), v["p"]) for v in vias if v["net"]]
    build.write_board(r, path, outer_pours=True)
    print("Escrito", path)
    sys.exit(1 if todo else 0)


if __name__ == "__main__":
    main()
