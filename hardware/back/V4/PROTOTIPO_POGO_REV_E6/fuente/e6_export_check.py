# -*- coding: utf-8 -*-
"""Rev E.6 (prototipo pogo): STL de impresión de la base y el soporte, comprobación de la malla y de interferencias con la
electrónica de referencia de la Rev E (Heltec, ZED + L)."""
import os, json
import Part, FreeCAD as App
H = os.path.dirname(os.path.abspath(__file__))
import os, json, re, struct, glob
import numpy as np
import FreeCAD as App, Part, Mesh, Import
from FreeCAD import Vector as V
TOL = 0.02
def rd(p):
    s = Part.Shape(); s.read(p); return s
def mv(s):
    v, f = s.tessellate(0.01); t = 0.0
    for a, b, c in f: t += v[a].dot(v[b].cross(v[c]))
    return t / 6.0
def write_stl(path, s, name):
    v, f = s.tessellate(TOL)
    v = np.array([[p.x, p.y, p.z] for p in v]); f = np.array(f)
    v32 = np.asarray(v, np.float32); vu, inv = np.unique(v32.view(np.dtype((np.void, 12))), return_inverse=True)
    vv = np.frombuffer(vu.tobytes(), dtype=np.float32).reshape(-1, 3); ff = inv.reshape(-1)[f]
    ff = ff[(ff[:, 0] != ff[:, 1]) & (ff[:, 1] != ff[:, 2]) & (ff[:, 0] != ff[:, 2])]
    t = vv[ff]; n = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]); ln = np.linalg.norm(n, axis=1); keep = ln > 0; ff, t, n, ln = ff[keep], t[keep], n[keep], ln[keep]
    n = n / ln[:, None]
    a = np.zeros(len(ff), dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")]); a["n"] = n; a["v"] = t
    with open(path, "wb") as o: o.write(name.encode()[:80].ljust(80, b" ")); o.write(struct.pack("<I", len(ff))); o.write(a.tobytes())
def check_stl(path):
    """relee el STL escrito y comprueba la malla"""
    b = open(path, "rb").read(); n = struct.unpack("<I", b[80:84])[0]
    a = np.frombuffer(b[84:84 + 50 * n], dtype=[("n", "<f4", 3), ("v", "<f4", (3, 3)), ("a", "<u2")])
    tv = a["v"].reshape(-1, 3); vu, inv = np.unique(tv.view(np.dtype((np.void, 12))), return_inverse=True)
    f = inv.reshape(-1, 3); vv = np.frombuffer(vu.tobytes(), dtype=np.float32).reshape(-1, 3).astype(np.float64)
    e_dir = np.concatenate([f[:, [0, 1]], f[:, [1, 2]], f[:, [2, 0]]])
    e_und = np.sort(e_dir, 1); u, c = np.unique(e_und, axis=0, return_counts=True)
    no_manifold = int((c != 2).sum())
    ud, cd = np.unique(e_dir, axis=0, return_counts=True); orient_bad = int((cd > 1).sum())        # arista recorrida 2 veces en el mismo sentido
    t = vv[f]; area = 0.5 * np.linalg.norm(np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]), axis=1)
    vol = float(np.einsum("ij,ij->i", t[:, 0], np.cross(t[:, 1], t[:, 2])).sum() / 6.0)
    # componentes conexas
    from scipy.sparse import coo_matrix; from scipy.sparse.csgraph import connected_components
    m = coo_matrix((np.ones(len(e_dir)), (e_dir[:, 0], e_dir[:, 1])), shape=(len(vv), len(vv)))
    ncomp = connected_components(m, directed=False)[0]
    # normales guardadas coherentes con el orden de vértices
    nn = np.cross(t[:, 1] - t[:, 0], t[:, 2] - t[:, 0]); nn /= np.maximum(np.linalg.norm(nn, axis=1, keepdims=True), 1e-12)
    normal_ok = float((np.einsum("ij,ij->i", nn, a["n"].astype(np.float64)) > 0.99).mean())
    me = Mesh.Mesh(path)
    euler = len(vv) - len(u) + len(f)
    bb = vv.min(0), vv.max(0)
    return dict(triangulos=int(n), vertices=int(len(vv)), aristas_no_manifold=no_manifold, aristas_mal_orientadas=orient_bad, triangulos_degenerados=int((area <= 0).sum()),
                componentes=int(ncomp), euler=int(euler), volumen_mm3=round(vol, 1), normales_coherentes=round(normal_ok, 4),
                freecad_isSolid=bool(me.isSolid()), freecad_autointersecciones=bool(me.hasSelfIntersections()), freecad_puntos_no_manifold=int(me.hasNonManifolds()),
                bbox_mm=[round(float(x), 3) for x in list(bb[0]) + list(bb[1])])
S = os.path.join(H, "salida"); O = os.path.join(S, "STL"); os.makedirs(O, exist_ok=True)
res = {}
P = {}
for nm in ("AVO_RevE6_BASE_POGO", "AVO_RevE6_CUNA_HELTEC", "AVO_RevE6_SOPORTE_POGO", "AVO_RevE6_BASE_CARGA_POGO"):
    s = rd(os.path.join(S, "BREP", nm + ".brep")); P[nm] = s
    sp = s.copy(); sp.translate(V(0, 0, -s.BoundBox.ZMin))          # posición de impresión: cara inferior sobre la cama (Z 0)
    p = os.path.join(O, nm + ".stl"); write_stl(p, sp, nm)
    r = check_stl(p); r["volumen_brep_mm3"] = round(mv(s), 1); r["nota"] = "STL en posición de impresión (Z mínima = 0); STEP en posición de montaje"; res[nm] = r
R = "/home/claude/v4/ref_E41/AVO_V22H_REV_E4_1_COMPLETA/REFERENCIAS_ELECTRONICA"
inter = {}
for e in ("HELTEC_WIRELESS_STICK_LITE_V3.step", "ZED_F9P_Y_ADAPTADOR_L.step"):
    sh = Part.read(os.path.join(R, e))
    for nm, s in P.items():
        try: v = round(sh.common(s).Volume, 3)
        except Exception as ex: v = "error " + str(ex)[:40]
        inter["%s / %s" % (e[:-5], nm)] = v
res["interferencias_mm3"] = inter
json.dump(res, open(os.path.join(S, "validacion_E6.json"), "w"), indent=1, ensure_ascii=False)
print("FIN", json.dumps(res, ensure_ascii=False)[:2500])
