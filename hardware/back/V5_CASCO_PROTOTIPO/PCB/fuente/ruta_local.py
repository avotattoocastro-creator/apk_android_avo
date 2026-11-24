"""Re-ruteo local y ordenado (24/11, tras sacar las vías de los pads): quita las pistas y vías de unas redes dentro de una
caja y las vuelve a unir en el orden dado, sin rip-up (rápido). Si alguna no se puede unir, no escribe nada.

Uso: python ruta_local.py x0 y0 x1 y1 RED1,RED2,... [--via-gap 0.35]   (coordenadas KiCad; lee y escribe
     kicad/..._ruteado.kicad_pcb)
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import avo_back_v5_pcb as D   # noqa: E402
import build                  # noqa: E402
import repair                 # noqa: E402


def main():
    x0, y0, x1, y1 = map(float, sys.argv[1:5])
    if "--via-gap" in sys.argv:                 # p. ej. 0.35 = mínimo de la puerta (0,10 mm de cobre), solo en esta caja
        build.VIA_PAD_GAP = float(sys.argv[sys.argv.index("--via-gap") + 1])
    order = sys.argv[5].split(",")
    path = os.path.join(D.OUT, "AVO_BACK_V5P_PCB_ruteado.kicad_pcb")
    segs, vias, _ = repair.read_board(path)
    pads = build.collect_pads()
    inb = lambda p: x0 <= p[0] <= x1 and y0 <= p[1] <= y1
    box = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
    segs[:] = [s for s in segs if not (s["net"] in order and (inb(s["a"]) or inb(s["b"]) or
                                                              repair.seg_poly(s["a"], s["b"], box) <= s["w"] / 2))]
    vias[:] = [v for v in vias if not (v["net"] in order and inb(v["p"]))]
    repair.prune(pads, segs, vias)
    r = repair.make_router(pads, segs, vias)
    for net in order:
        while True:
            g, _ = repair.clusters(net, pads, segs, vias)
            if len(g) <= 1:
                break
            p, w = repair.try_route(r, pads, net, D.CODE[net], g)
            if not p:
                print("NO se une %s (%d grupos): no se escribe nada" % (net, len(g)))
                sys.exit(1)
            nv = len(r.vias)
            for (layer, a, b) in r.commit(D.CODE[net], p, w):
                segs.append(dict(net=net, layer=layer, a=a, b=b, w=w))
            for (_, vp) in r.vias[nv:]:
                vias.append(dict(net=net, p=vp, d=build.VIA[0], drill=build.VIA[1]))
        print("unida %s" % net)
    left = [n for n in D.NETS if n not in build.PLANES and len(repair.clusters(n, pads, segs, vias)[0]) > 1]
    print("Redes sin unir en toda la placa: %s" % (", ".join(left) or "ninguna"))
    r.tracks = [(D.CODE.get(s["net"], 0), s["layer"], s["a"], s["b"], s["w"]) for s in segs if s["net"]]
    r.vias = [(D.CODE.get(v["net"], 0), v["p"]) for v in vias if v["net"]]
    build.write_board(r, path, outer_pours=True)
    print("Escrito", path)


if __name__ == "__main__":
    main()
