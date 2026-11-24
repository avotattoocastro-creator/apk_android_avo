"""Busca un sitio libre para mover una pieza pequeña en una placa YA ruteada (para usar después `repair.py --moved`).

El sitio vale si: los pads de la pieza caen sobre cobre libre de otras redes (con la separación de la clase) en su
capa, el patio no pisa el de otra pieza (D.check_placement) y queda lo más cerca posible del pad objetivo.

Uso (desde PCB/): python3 fuente/hueco_libre.py PLACA.kicad_pcb REF REF_OBJ.PIN [radio_mm]
Imprime las mejores posiciones en el marco de colocacion_v5.json (X, Y, giro). No escribe nada.
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import avo_back_v5_pcb as D                                    # noqa: E402
import build                                                 # noqa: E402
import repair                                                # noqa: E402
from fplib import pad_poly                                   # noqa: E402
from router import poly_mask                                 # noqa: E402


def main():
    src, ref, obj = sys.argv[1], sys.argv[2], sys.argv[3]
    radio = float(sys.argv[4]) if len(sys.argv) > 4 else 4.0
    segs, vias, _ = repair.read_board(src)
    pads = build.collect_pads()
    part = next(p for p in D.PARTS if p["ref"] == ref)
    mine = set(r["net"] for r in pads if r["part"]["ref"] == ref)
    # se quitan las pistas que llegan a la pieza (repair.py --moved las poda igual)
    otros = [r for r in pads if r["part"]["ref"] != ref]
    r = repair.make_router(otros, [s for s in segs if s["net"] not in mine or True], vias)
    oref, onum = obj.split(".")
    tgt = next(q for q in pads if q["part"]["ref"] == oref and q["pad"].num == onum)["c"]
    fp = D.fp_of(part)
    posf = D.POSF
    pos0 = json.load(open(posf))
    l = r.layers.index("F.Cu")
    best = []
    free_by_net = {}
    for dx in np.arange(-radio, radio + 1e-9, 0.1):
        for dy in np.arange(-radio, radio + 1e-9, 0.1):
            kx, ky = tgt[0] + dx, tgt[1] + dy
            for rot in (0, 90, 180, 270):
                ok = True
                for pd in fp.pads:
                    net = part["nets"].get(pd.num)
                    nid = D.CODE.get(net, -1)
                    if nid not in free_by_net:
                        free_by_net[nid] = r.free_mask(nid, 0.2)[l]
                    m = poly_mask((r.H, r.W), r.x0, r.y0, pad_poly(pd, kx, ky, rot))
                    if not free_by_net[nid][m].all():
                        ok = False
                        break
                if ok:
                    best.append((math.hypot(dx, dy), round(kx - 100, 2), round(100 - ky, 2), rot))
    best.sort()
    print("candidatos de cobre libre:", len(best), flush=True)
    # patio: probar en orden con check_placement
    for d, X, Y, rot in best[:400]:
        pos = dict(pos0)
        pos[ref] = [X, Y, rot]
        json.dump(pos, open(posf, "w"), indent=1)
        import importlib
        importlib.reload(D)
        errs = [e for e in D.check_placement() if ref in e]
        if not errs:
            print("OK %s → (%.2f, %.2f, %d)  a %.2f mm del objetivo" % (ref, X, Y, rot, d))
            break
    json.dump(pos0, open(posf, "w"), indent=1)


if __name__ == "__main__":
    main()
