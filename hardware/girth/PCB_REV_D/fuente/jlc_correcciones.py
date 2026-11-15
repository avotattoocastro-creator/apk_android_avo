"""Giro y centro de cada pieza montada según la huella de JLCPCB/EasyEDA (lib_easyeda/<LCSC>.pretty).

JLCPCB coloca su propia huella en (Mid X, Mid Y) con el giro del CPL. Si su huella no tiene el mismo origen o el mismo
giro que la nuestra, la pieza queda desplazada o girada. Aquí se busca, para cada pieza, el giro (0/90/180/270) y el
desplazamiento que llevan sus pads numerados encima de los nuestros. Escribe jlc_correcciones.json:
{ref: {"rot": grados a sumar al giro de KiCad, "off": [dx, dy] en coordenadas locales de NUESTRA huella (mm)}}.
"""
import glob
import json
import math
import re
import sys

import avo_girth_revd_pcb as D


def ee_pads(code):
    f = glob.glob("lib_easyeda/%s.pretty/*.kicad_mod" % code)
    if not f:
        return None
    s = open(f[0]).read()
    return {a: (float(x), float(y)) for a, x, y in re.findall(r'\(pad "?([^"\s]*)"? \w+ \w+ \(at ([\-\d.]+) ([\-\d.]+)', s)}


def rot(p, deg):
    t = math.radians(deg); c, s_ = round(math.cos(t)), round(math.sin(t))
    return (p[0] * c + p[1] * s_, -p[0] * s_ + p[1] * c)     # KiCad (y hacia abajo), giro antihorario en pantalla


out, rep = {}, []
for p in D.PARTS:
    if p.get("dnp") or not p.get("lcsc") or p.get("no_assembly"):
        continue
    ee = ee_pads(p["lcsc"])
    if not ee:
        rep.append("%-4s %-9s sin huella EasyEDA" % (p["ref"], p["lcsc"])); continue
    ours = {str(pd.num): (pd.x, pd.y) for pd in D.fp_of(p).pads if str(pd.num)}
    common = [n for n in ours if n in ee]
    if len(common) < 2:
        rep.append("%-4s %-9s pads sin numeración común" % (p["ref"], p["lcsc"])); continue
    best = None
    for r in (0, 90, 180, 270):
        # su huella girada r debe caer sobre la nuestra: ours ≈ rot(ee, r) + o  (o = origen de su huella en la nuestra)
        pts = [(ours[n], rot(ee[n], r)) for n in common]
        o = (sum(a[0] - b[0] for a, b in pts) / len(pts), sum(a[1] - b[1] for a, b in pts) / len(pts))
        err = max(math.hypot(a[0] - b[0] - o[0], a[1] - b[1] - o[1]) for a, b in pts)
        if best is None or err < best[0]:
            best = (err, r, o)
    err, r, o = best
    # pads simétricos (2 pads iguales): 0 y 180 empatan; se queda 0 salvo que la polaridad lo pida (el error lo decide)
    out[p["ref"]] = {"rot": r, "off": [round(o[0], 3), round(o[1], 3)], "err": round(err, 3)}
    flag = "" if (r == 0 and math.hypot(*o) < 0.05) else "  <-- CORRECCIÓN"
    if err > 0.15:
        flag += "  ¡¡ajuste malo, revisar a mano!!"
    rep.append("%-4s %-9s giro +%3d  centro (%.2f, %.2f)  error %.2f%s" % (p["ref"], p["lcsc"], r, o[0], o[1], err, flag))
json.dump(out, open("jlc_correcciones.json", "w"), indent=1, sort_keys=True)
print("\n".join(rep))
