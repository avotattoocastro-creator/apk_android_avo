# Planta y perfiles (lateral) de la Rev E.5 y de la V4 para el plano y la comparativa → analisis/perfiles.json
import Part, json, math
from FreeCAD import Vector as V
def rd(p):
    s=Part.Shape(); s.read(p); return s
E="/home/claude/v4/ref_E41/AVO_V22H_REV_E4_1_COMPLETA/STEP_SHAPR3D/"; E5="/home/claude/v4/ref_E5/AVO_V22H_REV_E5_TAPA/STEP_SHAPR3D/"
B="/home/claude/v4/cad/salida/BREP/"; R="/home/claude/v4/cad/salida/REFERENCIAS/"
sets={"RevE5":dict(tapa=Part.read(E5+"AVO_RevE5_TAPA.step"),base=Part.read(E+"AVO_RevE_BASE.step"),soporte=Part.read(E+"AVO_RevE_SOPORTE.step"),
                   contraplaca=Part.read(E+"AVO_RevE_CONTRAPLACA.step"),antena=Part.read("/home/claude/v4/ref_E41/AVO_V22H_REV_E4_1_COMPLETA/REFERENCIAS_ELECTRONICA/ANTENA_GNSS.step")),
      "V4":dict(tapa=rd(B+"AVO_BACK_V4_TAPA.brep"),base=rd(B+"AVO_BACK_V4_BASE.brep"),soporte=rd(B+"AVO_BACK_V4_SOPORTE.brep"),
                contraplaca=rd(B+"AVO_BACK_V4_CONTRAPLACA.brep"),antena=rd(R+"_antena_GNSS_Q39.brep"))}
out={}
def section_pts(shape, plane_normal, d):
    sec=shape.slice(plane_normal, d)
    res=[]
    for w in sec:
        pts=w.discretize(Deflection=0.05)
        res.append([[round(p.x,3),round(p.y,3),round(p.z,3)] for p in pts])
    return res
for nm,S in sets.items():
    o={}
    o["planta"]=section_pts(S["base"],V(0,0,1),0.9)       # contorno a media altura de la base
    for k in ("tapa","base","soporte","contraplaca","antena"):
        o["perfil_"+k]=section_pts(S[k],V(0,1,0),0.0)      # corte longitudinal Y = 0
    o["bbox"]={k:[round(v,3) for v in (s.BoundBox.XMin,s.BoundBox.XMax,s.BoundBox.YMin,s.BoundBox.YMax,s.BoundBox.ZMin,s.BoundBox.ZMax)] for k,s in S.items()}
    out[nm]=o
json.dump(out,open("/home/claude/v4/analisis/perfiles.json","w"))
print({k:v["bbox"] for k,v in out.items()})
