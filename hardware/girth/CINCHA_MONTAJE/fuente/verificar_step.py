"""Comprobación independiente de los STEP generados (sin núcleo CAD): vuelve a leer el archivo y verifica que
  - todas las referencias #n existen;
  - en cada CLOSED_SHELL cada EDGE_CURVE la usan exactamente 2 ORIENTED_EDGE con sentidos opuestos (sólido cerrado);
  - los vértices de cada arista coinciden con los extremos de su LINE (punto + vector·longitud);
  - cada ADVANCED_FACE es plana (todos sus vértices en el PLANE, tolerancia 1e-3 mm).
Uso: python3 verificar_step.py archivo.step [...]"""
import re
import sys
from collections import Counter

import numpy as np


def parse(path):
    E = {}
    txt = open(path, encoding="ascii").read()
    body = txt.split("DATA;", 1)[1]
    for m in re.finditer(r"#(\d+)=(.*?);\s*$", body, re.M | re.S):
        E[int(m.group(1))] = m.group(2)
    return E


def refs(s):
    return [int(x) for x in re.findall(r"#(\d+)", s)]


def nums(s):
    return [float(x) for x in re.findall(r"[-+]?\d*\.\d*(?:[eE][-+]?\d+)?|[-+]?\d+(?:[eE][-+]?\d+)?", s)]


def check(path):
    E = parse(path)
    missing = set()
    for k, s in E.items():
        for r in refs(s):
            if r not in E:
                missing.add(r)
    pt = {}

    def P(i):
        if i not in pt:
            s = E[i]
            inner = s[s.index("(", s.index("(") + 1):]
            pt[i] = np.array(nums(inner)[:3])
        return pt[i]
    shells = [k for k, s in E.items() if s.startswith("CLOSED_SHELL")]
    bad_edges = 0; bad_geo = 0; bad_plane = 0; nfaces = 0
    for sh in shells:
        use = Counter(); sense = {}
        for f in refs(E[sh]):
            nfaces += 1
            fs = E[f]
            r = refs(fs)
            plane = r[-1]
            ax = refs(E[plane])[0]
            o, nrm = refs(E[ax])[0], refs(E[ax])[1]
            O = P(o); N = P(nrm)
            for b in r[:-1]:
                el = refs(E[b])[0]
                for oe in refs(E[el]):
                    s = E[oe]
                    ec = refs(s)[0]
                    same = s.strip().endswith(".T.)")
                    use[ec] += 1
                    sense.setdefault(ec, []).append(same)
                    v1, v2, ln = refs(E[ec])[:3]
                    p1 = P(refs(E[v1])[0]); p2 = P(refs(E[v2])[0])
                    for p in (p1, p2):
                        if abs(np.dot(p - O, N)) > 1e-3:
                            bad_plane += 1
                    lp, vec = refs(E[ln])
                    d, = refs(E[vec])[:1]
                    L = nums(E[vec].split(",")[-1])[0]
                    if np.linalg.norm(P(lp) + P(d) * L - p2) > 1e-3 or np.linalg.norm(P(lp) - p1) > 1e-3:
                        bad_geo += 1
        for ec, k in use.items():
            if k != 2 or sense[ec][0] == sense[ec][1]:
                bad_edges += 1
    return dict(entidades=len(E), referencias_que_faltan=len(missing), cuerpos=len(shells), caras=nfaces,
                aristas_mal_cosidas=bad_edges, aristas_fuera_de_su_recta=bad_geo, vertices_fuera_del_plano=bad_plane)


if __name__ == "__main__":
    ok = True
    for p in sys.argv[1:]:
        r = check(p)
        good = r["referencias_que_faltan"] == 0 and r["aristas_mal_cosidas"] == 0 and r["aristas_fuera_de_su_recta"] == 0 \
            and r["vertices_fuera_del_plano"] == 0
        ok &= good
        print(("OK  " if good else "MAL ") + p.split("/")[-1], r)
    sys.exit(0 if ok else 1)
