# -*- coding: utf-8 -*-
"""Rev E.7.2: coloca el STEP real de los conectores (usuario) en la base, el soporte y la contraplaca; interferencias y secciones."""
import os, json
H = os.path.dirname(os.path.abspath(__file__)); os.environ["AVO_DIR"] = H
src = open(os.path.join(H, "avo_v22h_revE7_freecad.py"), encoding="utf-8").read()
src = src[:src.index('if __name__ == "__main__" or "AVO_RUN" in os.environ:')]
exec(compile(src, "e7", "exec"))
import FreeCAD as App, Import, Part
from FreeCAD import Vector as V
STEP = os.environ.get("POGO_STEP", "/home/claude/pogo/step/pogo.step")
doc = App.newDocument("p"); Import.insert(STEP, "p")
S = {o.Label: o.Shape.copy() for o in doc.Objects if o.TypeId == "Part::Feature" and o.Shape.Solids}
cx, cy = RE["CON_C"]
def place(sh, dz):
    sh = sh.copy(); sh.rotate(V(0, 0, 0), V(1, 0, 0), 180); sh.rotate(V(0, 0, 0), V(0, 0, 1), 90); sh.translate(V(cx, cy, dz)); return sh
plate = {k: place(v, 0.0) for k, v in S.items() if k in ("Body Plattenseite", "Kontakt 1", "Kontakt 2", "Kontakt 3", "Magnet 3", "Magnet 4")}
pins = {k: place(v, -RE["PN_RECESS"]) for k, v in S.items() if k in ("Body Pinseite", "Pogopin", "Pogopin 2", "Pogopin 3", "Magnet 1", "Magnet 2")}
def rd(p): s = Part.Shape(); s.read(p); return s
base = rd(os.path.join(H, "salida_E7/BREP/AVO_RevE7_BASE_IMAN.brep"))
sop = rd(os.path.join(H, "salida_E7/BREP/AVO_RevE7_SOPORTE_IMAN.brep"))
con = rd(os.path.join(H, "salida_E7/BREP/AVO_RevE_CONTRAPLACA.brep"))
car = rd(os.path.join(H, "salida_E7_carga/BREP/AVO_RevE7_BASE_CARGA_IMAN.brep"))
res = {}
for k, v in plate.items(): res["plano/%s vs base" % k] = round(v.common(base).Volume, 4)
for k, v in pins.items():
    res["muelles/%s vs soporte" % k] = round(v.common(sop).Volume, 4)
    res["muelles/%s vs contraplaca" % k] = round(v.common(con).Volume, 4)
    res["muelles/%s vs base de carga" % k] = round(v.common(car).Volume, 4)
pb = pins["Body Pinseite"].BoundBox; plb = plate["Body Plattenseite"].BoundBox
res["cara_plano_Z"] = round(plb.ZMin, 3); res["cara_muelles_Z"] = round(pins["Body Pinseite"].BoundBox.ZMax, 3)
res["punta_pines_Z"] = round(max(pins[k].BoundBox.ZMax for k in ("Pogopin", "Pogopin 2", "Pogopin 3")), 3)
res["fondo_conector_muelles_Z"] = round(pb.ZMin, 3); res["patas_muelles_Z"] = round(min(pins[k].BoundBox.ZMin for k in ("Pogopin", "Pogopin 2", "Pogopin 3")), 3)
res["patas_plano_Z"] = round(max(plate[k].BoundBox.ZMax for k in ("Kontakt 1", "Kontakt 2", "Kontakt 3")), 3)
res["contraplaca_cara_Z"] = round(-RE["MT"] - RE["FABRIC"], 3)
# huecos tornillos M2 (cabeza Ø3,8 × 1,6) bajo las orejas
zf, ze1, ze0, zb = pin_geom()
heads = Part.makeCompound([vcyl(cx, cy + sg * RE["PN_HOLE"][1] / 2, 1.9, ze0 - 1.6, ze0) for sg in (-1, 1)])
res["cabezas_M2 vs contraplaca"] = round(heads.common(con).Volume, 4); res["cabezas_M2 vs soporte"] = round(heads.common(sop).Volume, 4)
out = {}
def sec(shape, n, d):
    return [[(p.x, p.y, p.z) for p in e.discretize(Distance=0.08)] for w in shape.slice(n, d) for e in w.Edges]
grp = dict(base=[base], sop=[sop], con=[con], plano=list(plate.values()), muelles=list(pins.values()), cabezas=[heads])
for nm, shs in grp.items():
    out[nm] = dict(x=[s_ for sh in shs for s_ in sec(sh, V(1, 0, 0), cx)], y=[s_ for sh in shs for s_ in sec(sh, V(0, 1, 0), 2.3)])
os.makedirs(os.path.join(H, "E7", "VALIDACION"), exist_ok=True)
json.dump(res, open(os.path.join(H, "E7", "VALIDACION", "interferencias_conectores_STEP.json"), "w"), indent=1, ensure_ascii=False)
json.dump(out, open(os.path.join(H, "E7", "VALIDACION", "secciones.json"), "w"))
print("RES", json.dumps(res, ensure_ascii=False))
