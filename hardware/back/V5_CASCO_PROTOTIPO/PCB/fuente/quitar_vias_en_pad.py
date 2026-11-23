"""Saca de los pads SMD las vías de una placa YA ruteada, sin tocar el resto del ruteado.

Motivo: pedido PCBA 13966268A (23/11/2026). JLCPCB avisó de vías abiertas dentro de los pads. La placa pedida
(`711b097`) tenía 114. Volver a rutear todo con Freerouting cambia la placa entera y vuelve a dejar conexiones
pendientes; este script parte de la placa pedida (DRC limpio, todo conectado) y solo rehace lo necesario:

1. Quita cada vía que invade la abertura de máscara de un pad con pasta (cobre + 0,05 mm, con margen
   `via_en_pad.MARGEN`) y los tramos que quedan dentro del pad.
2. Pads de plano (GND → In1): vía nueva fuera del pad (misma búsqueda que `build.via_drops`, con `smd_pad_block`).
3. Redes de señal: las que quedan partidas se vuelven a unir con `repair.py` (sin vías en pads).

Uso (desde PCB/): python3 fuente/quitar_vias_en_pad.py ORIGEN.kicad_pcb
Escribe kicad/AVO_BACK_V5P_PCB.kicad_pcb; después hay que pasar `python3 fuente/repair.py`, que escribe
kicad/AVO_BACK_V5P_PCB_ruteado.kicad_pcb (la que usa el CI).
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import avo_back_v5_pcb as D                                    # noqa: E402
import build                                                 # noqa: E402
import repair                                                # noqa: E402
import via_en_pad                                            # noqa: E402
from fplib import pad_poly                                   # noqa: E402,F401
from router import seg_mask                                  # noqa: E402,F401


def con_pasta(rec):
    return rec["pad"].kind == "smd" and any(str(c).endswith("Paste") for c in rec["pad"].layers)


def unir_a_via_gnd(r, pads, recs, radio=4.0):
    """Pads de GND sin sitio para su vía: pista en su capa hasta una vía GND existente u otro pad GND cercano."""
    import numpy as np
    nid = D.CODE[D.GND]
    fails = []
    for rec in recs:
        layer = rec["layers"][0]
        l = r.layers.index(layer)
        cand = [p for (n, p) in r.vias if n == nid and math.hypot(p[0] - rec["c"][0], p[1] - rec["c"][1]) < radio]
        hecho = False
        for w in (0.3, 0.2):
            free = r.free_mask(nid, w)
            goals = set()
            for p in cand:
                i, j = r.ij(*p)
                goals.add((l, i, j))
            # también otro pad GND de la misma capa (que ya llega al plano por su vía)
            for q in pads:
                if q is rec or q["net"] != D.GND or layer not in q["layers"] or q["npth"]:
                    continue
                if math.hypot(q["c"][0] - rec["c"][0], q["c"][1] - rec["c"][1]) < radio:
                    goals |= set(build.pad_cells(r, q, layer, free))
            starts = build.pad_cells(r, rec, layer, free)
            path = r.astar(nid, set(starts), goals, w, free, np.zeros((r.H, r.W), bool), rec["c"], max_exp=300000)
            if path:
                r.commit(nid, path, w, start_xy=rec["c"])
                hecho = True
                break
        if not hecho:
            fails.append("%s.%s" % (rec["part"]["ref"], rec["pad"].num))
    return fails


def main():
    src = sys.argv[1]
    segs, vias, fps = repair.read_board(src)
    bad = repair.check_positions(fps)
    if bad:
        print("La placa no corresponde a la colocación actual:", ", ".join(bad[:12]))
        sys.exit(2)
    pads = build.collect_pads()
    pp = [rec for rec in pads if con_pasta(rec)]
    lim = 0.05 + via_en_pad.MARGEN          # abertura de máscara del pad + margen
    quitar, pads_plano = [], []
    for v in vias:
        for rec in pp:
            if repair.seg_poly(v["p"], v["p"], rec["poly"]) < v["d"] / 2 + lim:
                quitar.append(v)
                if v["net"] in build.PLANES and rec["net"] == v["net"]:
                    pads_plano.append(rec)
                break
    ids = set(id(v) for v in quitar)
    vias[:] = [v for v in vias if id(v) not in ids]
    # redes de señal con una vía en pad: se quitan enteras y repair.py las vuelve a rutear (mover solo la vía deja
    # tramos de capa interior sueltos; CI 45263403036)
    senal = sorted(set(v["net"] for v in quitar if v["net"] and v["net"] not in build.PLANES))
    segs[:] = [s_ for s_ in segs if s_["net"] not in senal]
    vias[:] = [v for v in vias if v["net"] not in senal]
    print("Redes de señal que se rehacen enteras: %s" % ", ".join(senal))
    # tramos que quedan enteros dentro de un pad de su red (los «rabos» de la vía quitada)
    n0 = len(segs)
    keep = []
    for s in segs:
        dentro = any(rec["net"] == s["net"] and s["layer"] in rec["layers"] and
                     repair.seg_poly(s["a"], s["a"], rec["poly"]) <= 0 and repair.seg_poly(s["b"], s["b"], rec["poly"]) <= 0
                     for rec in pp)
        if not dentro:
            keep.append(s)
    segs[:] = keep
    # tramos de plano que unían la vía quitada con otra cosa: se dejan (GND también rellena F.Cu)
    podados = repair.prune(pads, segs, vias)
    print("Vías quitadas: %d (%d de plano) · tramos dentro de pads: %d · tramos colgantes podados: %d"
          % (len(quitar), len(pads_plano), n0 - len(keep), podados))
    # vías nuevas para los pads de plano, fuera de cualquier pad con pasta
    r = repair.make_router(pads, segs, vias)
    hechos = set()
    unicos = []
    for rec in pads_plano:
        k = (rec["part"]["ref"], rec["pad"].num)
        if k not in hechos:
            hechos.add(k); unicos.append(rec)
    log = []
    nv, nt = len(r.vias), len(r.tracks)
    fails = build.via_drops(r, unicos, log, all_pads=pads)
    print(log[-1])
    if fails:
        # segundo intento para los que no encontraron sitio: franja de máscara 0,10 mm y radio de 4 mm
        resto = [rec for rec in unicos if "%s.%s" % (rec["part"]["ref"], rec["pad"].num) in fails]
        fails = build.via_drops(r, resto, log, all_pads=pads, web=0.15, radio=3.5)
        print("2.º intento (franja 0,15 mm, radio 3,5 mm):", log[-1])
        resto = [rec for rec in resto if "%s.%s" % (rec["part"]["ref"], rec["pad"].num) in fails]
        # 3.er intento: se quitan las pistas de señal que encierran el pad (repair.py las vuelve a rutear después)
        cerca = set()
        # primero se prueba la pista hasta otra vía o pad GND (no toca el ruteado); solo se despeja alrededor de los
        # que sigan sin unir
        resto = [rec for rec in resto if "%s.%s" % (rec["part"]["ref"], rec["pad"].num) in
                 set(unir_a_via_gnd(r, pads, resto))]
        for rec in resto:
            for s_ in segs:
                if s_["net"] and s_["net"] not in build.PLANES and s_["layer"] in rec["layers"] and \
                        repair.seg_poly(s_["a"], s_["b"], rec["poly"]) < 0.8:
                    cerca.add(s_["net"])
        if cerca and "--despejar" in sys.argv:
            print("Pistas que encierran pads GND, se rehacen: %s" % ", ".join(sorted(cerca)))
            segs[:] = [s_ for s_ in segs if s_["net"] not in cerca]
            vias[:] = [v for v in vias if v["net"] not in cerca]
            nuevos_t = [(t[0], t[1], t[2], t[3], t[4]) for t in r.tracks[nt:]]
            nuevas_v = list(r.vias[nv:])
            r = repair.make_router(pads, segs, vias)
            for (net, layer, a, b, w) in nuevos_t:
                r.add_track(net, layer, a, b, w)
            for (net, p) in nuevas_v:
                r.vias.append((net, p))
                m = seg_mask((r.H, r.W), r.x0, r.y0, p, p, build.VIA[0] / 2)
                for l in range(r.L):
                    r._mark(l, m, net)
            nv, nt = len(r.vias) - len(nuevas_v), len(r.tracks) - len(nuevos_t)
            fails = build.via_drops(r, resto, log, all_pads=pads)
            print("3.er intento:", log[-1])
            resto = [rec for rec in resto if "%s.%s" % (rec["part"]["ref"], rec["pad"].num) in fails]
        fails = unir_a_via_gnd(r, pads, resto)
        print("4.º intento (pista hasta una vía o un pad GND cercano): sin unir: %s" % (", ".join(fails) or "ninguno"))
    for (net, layer, a, b, w) in r.tracks[nt:]:
        segs.append(dict(net=D.GND, layer=layer, a=a, b=b, w=w))
    for (net, p) in r.vias[nv:]:
        vias.append(dict(net=D.GND, p=p, d=build.VIA[0], drill=build.VIA[1]))
    r.tracks = [(D.CODE.get(s["net"], 0), s["layer"], s["a"], s["b"], s["w"]) for s in segs if s["net"]]
    r.vias = [(D.CODE.get(v["net"], 0), v["p"]) for v in vias if v["net"]]
    out = os.path.join(D.OUT, "AVO_BACK_V5P_PCB.kicad_pcb")
    build.write_board(r, out, outer_pours=True)
    print("Escrito", out)
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
