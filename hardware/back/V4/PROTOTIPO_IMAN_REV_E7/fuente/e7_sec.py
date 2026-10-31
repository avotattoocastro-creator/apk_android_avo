# -*- coding: utf-8 -*-
import os, json, sys
H = os.path.dirname(os.path.abspath(__file__)); os.environ["AVO_DIR"] = H
src = open(os.path.join(H, "avo_v22h_revE7_freecad.py"), encoding="utf-8").read()
src = src[:src.index('if __name__ == "__main__" or "AVO_RUN" in os.environ:')]
exec(compile(src, "e7", "exec"))
import Part
from FreeCAD import Vector as V
def rd(p): s = Part.Shape(); s.read(p); return s
base = rd(os.path.join(H, "salida_E7/PROBETAS/AVO_RevE_P3_CONECTOR_BASE.brep"))
sop = rd(os.path.join(H, "salida_E7/PROBETAS/AVO_RevE_P3_CONECTOR_SOPORTE.brep"))
cx, cy = RE["OVAL_C"]; ol, ow = RE["OVAL"]; bl, bw, bt = RE["EAR_BODY"]
T_OVAL = 2.9   # grueso supuesto (no medido) solo para el dibujo
oval = obround_solid(cx, cy, ol, ow, 0.0, T_OVAL)
zf = -RE["EAR_RECESS"]; zb = zf - bt; ze = zb + RE["EAR_T"]
earc = rrect_solid(cx, cy, bl, bw, RE["EAR_CORNER_R"], zb, zf).fuse(obround_solid(cx, cy, RE["EAR_LEN"], RE["EAR_W"], zb, ze))
hd, hs = RE["EAR_HOLE"]
for sg in (-1, 1): earc = earc.cut(vcyl(cx, cy + sg * hs / 2, hd / 2, zb - 1, ze + 1))
res = dict(interf_oval_base=round(oval.common(base).Volume, 4), interf_conector_soporte=round(earc.common(sop).Volume, 4))
out = {}
def sec(shape, n, d):
    w = shape.slice(n, d); return [[(p.x, p.y, p.z) for p in e.discretize(Distance=0.1)] for wi in w for e in wi.Edges]
for nm, sh in (("base", base), ("sop", sop), ("oval", oval), ("ear", earc)):
    out[nm] = dict(x=sec(sh, V(1, 0, 0), cx), y=sec(sh, V(0, 1, 0), 2.6))
json.dump(dict(res=res, sec=out), open(os.path.join(H, "E7", "secciones.json"), "w"))
print("RES", res)
