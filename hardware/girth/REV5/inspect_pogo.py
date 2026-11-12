"""Measures the pogo connector model supplied by the user (ref/pogo_3pin_assembly.step, Onshape export, metres).
Prints every solid with its name (when the STEP carries it), bounding box in mm and volume, so the CAD can use the real
dimensions instead of estimates."""
import cadquery as cq
from OCP.STEPCAFControl import STEPCAFControl_Reader
from OCP.TDocStd import TDocStd_Document
from OCP.TCollection import TCollection_ExtendedString
from OCP.XCAFDoc import XCAFDoc_DocumentTool
from OCP.TDF import TDF_LabelSequence
from OCP.TDataStd import TDataStd_Name
from OCP.TopLoc import TopLoc_Location
from OCP.Bnd import Bnd_Box
from OCP.BRepBndLib import BRepBndLib

doc = TDocStd_Document(TCollection_ExtendedString("doc"))
r = STEPCAFControl_Reader()
r.SetNameMode(True)
r.ReadFile("ref/pogo_3pin_assembly.step")
r.Transfer(doc)
st = XCAFDoc_DocumentTool.ShapeTool_s(doc.Main())

def name(lab):
    n = TDataStd_Name()
    return n.Get().ToExtString() if lab.FindAttribute(TDataStd_Name.GetID_s(), n) else "?"

rows = []
def walk(lab, loc, path):
    if st.IsAssembly_s(lab):
        comps = TDF_LabelSequence()
        st.GetComponents_s(lab, comps)
        for i in range(1, comps.Length() + 1):
            c = comps.Value(i)
            ref = c.__class__()
            st.GetReferredShape_s(c, ref)
            walk(ref, loc.Multiplied(st.GetLocation_s(c)), path + [name(c)])
    else:
        shp = st.GetShape_s(lab).Moved(loc)
        s = cq.Shape.cast(shp)
        for k, so in enumerate(s.Solids() or [s]):
            bb = so.BoundingBox()
            rows.append(("/".join(path + [name(lab)]) + (f"#{k}" if len(s.Solids()) > 1 else ""),
                         bb.xmin * 1000, bb.xmax * 1000, bb.ymin * 1000, bb.ymax * 1000, bb.zmin * 1000, bb.zmax * 1000,
                         so.Volume() * 1e9))

free = TDF_LabelSequence()
st.GetFreeShapes(free)
for i in range(1, free.Length() + 1):
    walk(free.Value(i), TopLoc_Location(), [])
print("solid | x0 x1 | y0 y1 | z0 z1 (mm) | size dx dy dz | volume mm3")
for n, x0, x1, y0, y1, z0, z1, v in rows:
    print(f"{n} | {x0:.3f} {x1:.3f} | {y0:.3f} {y1:.3f} | {z0:.3f} {z1:.3f} | {x1-x0:.3f} {y1-y0:.3f} {z1-z0:.3f} | {v:.3f}")

# Cylindrical faces of the two bodies (holes, magnet seats, round ends) and the outline at a few heights
from OCP.BRepAdaptor import BRepAdaptor_Surface
from OCP.GeomAbs import GeomAbs_Cylinder
import cadquery as cq2
for n, x0, x1, y0, y1, z0, z1, v in rows:
    pass
def body_solids():
    out = {}
    free2 = TDF_LabelSequence(); st.GetFreeShapes(free2)
    def w(lab, loc, path):
        if st.IsAssembly_s(lab):
            cs = TDF_LabelSequence(); st.GetComponents_s(lab, cs)
            for i in range(1, cs.Length() + 1):
                c = cs.Value(i); ref = c.__class__(); st.GetReferredShape_s(c, ref)
                w(ref, loc.Multiplied(st.GetLocation_s(c)), path + [name(c)])
        else:
            nm = name(lab)
            if nm.startswith("Body"): out[nm] = cq.Shape.cast(st.GetShape_s(lab).Moved(loc))
    for i in range(1, free2.Length() + 1): w(free2.Value(i), TopLoc_Location(), [])
    return out
for nm, sh in body_solids().items():
    print(f"\n== {nm}")
    seen = set()
    for f in sh.Faces():
        a = BRepAdaptor_Surface(f.wrapped)
        if a.GetType() == GeomAbs_Cylinder:
            c = a.Cylinder(); p = c.Location(); d = c.Axis().Direction()
            bb = f.BoundingBox()
            key = (round(c.Radius(), 3), round(p.X(), 2), round(p.Y(), 2), round(bb.zmin, 2), round(bb.zmax, 2))
            if key in seen: continue
            seen.add(key)
            print(f"cyl r={c.Radius():.3f} axis=({d.X():.0f},{d.Y():.0f},{d.Z():.0f}) at x={p.X():.3f} y={p.Y():.3f} | face z {bb.zmin:.3f}..{bb.zmax:.3f} x {bb.xmin:.3f}..{bb.xmax:.3f}")
    bb = sh.BoundingBox()
    for z in [bb.zmin + 0.05 + k * (bb.zlen - 0.1) / 6 for k in range(7)]:
        try:
            sec = sh.intersect(cq.Solid.makeBox(100, 100, 0.02, cq.Vector(-50, -50, z)))
            sb = sec.BoundingBox()
            print(f"  section z={z:.2f}: x {sb.xmin:.3f}..{sb.xmax:.3f} y {sb.ymin:.3f}..{sb.ymax:.3f} area {sec.Volume()/0.02:.2f} mm2")
        except Exception as e:
            print(f"  section z={z:.2f}: {e}")
