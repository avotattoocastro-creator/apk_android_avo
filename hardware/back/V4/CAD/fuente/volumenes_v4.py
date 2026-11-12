import os, json
os.environ["AVO_DIR"]="/home/claude/v4/cad"
src=open("/home/claude/v4/cad/avo_back_v4_freecad.py",encoding="utf-8").read()
head, rest = src.split("# ============================================================ primitivas (Rev D/E)")
prim = rest.split("OUTER_REF, CLIP_REF = [None], [None]")[0]
res={}
for nm, xa in (("RevE5", 136.714), ("V4", None)):
    g={}
    exec(head, g)
    if xa is not None:
        g["XA"]=xa; g["L"]=xa+g["HW"]; g["P"]["XA"]=xa; g["P"]["L_TOTAL"]=g["L"]
    exec(prim, g)
    H0=g["hull"](0.0,0.0)
    OUT=H0.makeChamfer(g["RE"]["BOT_CHAMFER"],[e for e in H0.Edges if e.BoundBox.ZMax<1e-6])
    CAV=g["hull"](g["WALL"],-5.0).common(OUT)
    res[nm]=dict(largo=round(OUT.BoundBox.XLength,3),ancho=round(OUT.BoundBox.YLength,3),alto=round(OUT.BoundBox.ZLength,3),
                 vol_exterior_cm3=round(OUT.Volume/1000,2),vol_interior_cm3=round(CAV.Volume/1000,2),planta_cm2=round(g["Part"].Face(g["outline_wire"](0,0)).Area/100,2))
json.dump(res,open("/home/claude/v4/analisis/volumenes.json","w"),indent=1)
print(res)
