# -*- coding: utf-8 -*-
"""AVO BACK V4: STEP finales con nombre de cuerpo, STL de impresión y de montaje desde el B-Rep, y validación completa:
relectura de cada STEP (válido, sólidos, cáscaras cerradas, mm) y de cada STL ESCRITO (estanco, orientado, sin degenerados,
un único cuerpo, sin autointersecciones, volumen = B-Rep)."""
import os, json, re, struct, glob
import numpy as np
import FreeCAD as App, Part, Mesh, Import
from FreeCAD import Vector as V
H = os.path.dirname(os.path.abspath(__file__)); D = os.path.join(H, "salida")
PIEZAS = ["TAPA", "BASE", "BANDEJA_URTK", "JUNTA_TPU", "SOPORTE", "CONTRAPLACA", "ANILLOS_SEPARADOR"]
PROBETAS = ["P1_COLA_BASE", "P1_COLA_TAPA", "P1_COLA_SOPORTE", "P2_CUELLO_BASE", "P2_CUELLO_TAPA", "P2_CUELLO_SOPORTE", "P2_CUELLO_BANDEJA"]
# orientación de impresión: solo giros (nunca simetrías)
GIRO = {"TAPA": ("X", 180),           # Rev E.3: boca abajo, techo plano sobre la cama, sin soportes
        "BASE": None,                 # cara exterior sobre la cama
        "BANDEJA_URTK": None,         # placa sobre la cama, pivotes hacia arriba
        "JUNTA_TPU": None,
        "SOPORTE": None,              # cara de la tela sobre la cama, cerco hacia arriba
        "CONTRAPLACA": ("X", 180),    # cara de la tela (plana) sobre la cama
        "ANILLOS_SEPARADOR": None}    # V4: 2 anillos de pie
for k in PROBETAS: GIRO[k] = ("X", 180) if k.endswith("TAPA") else None
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
def step_check(path):
    r = Part.read(path); txt = open(path, encoding="latin-1").read()
    return dict(relectura_valida=bool(r.isValid()), solidos=len(r.Solids), cascaras_cerradas=all(x.isClosed() for x in r.Shells),
                unidades_mm=bool(re.search(r"SI_UNIT\(\.MILLI\.,\.METRE\.\)", txt)), caras=len(r.Faces),
                tipos_superficie=sorted({type(fc.Surface).__name__ for fc in r.Faces}), volumen_mm3=round(mv(r), 1),
                nombres=re.findall(r"PRODUCT\('([^']*)'", txt)[:12])
SD = os.path.join(D, "STEP_SHAPR3D"); os.makedirs(SD, exist_ok=True)
for d in ("STL", "STL_PROBETAS", os.path.join("STL", "posicion_montaje")): os.makedirs(os.path.join(D, d), exist_ok=True)
PD = os.path.join(D, "STEP_PROBETAS"); os.makedirs(PD, exist_ok=True)
doc = App.newDocument("exp"); R = {}; objs = []
for k in PIEZAS + PROBETAS:
    nm = "AVO_BACK_V4_" + k; s = rd(os.path.join(D, "PROBETAS" if k in PROBETAS else "BREP", nm + ".brep"))
    o = doc.addObject("Part::Feature", nm); o.Shape = s; o.Label = nm
    if k in PIEZAS: objs.append(o)
    stp = os.path.join(SD if k in PIEZAS else PD, nm + ".step"); Import.export([o], stp)
    sp = s.copy()
    if GIRO[k]:
        ax, ang = GIRO[k]; c = sp.BoundBox.Center; sp.rotate(c, V(1, 0, 0) if ax == "X" else V(0, 1, 0), ang)
    ob = sp.optimalBoundingBox(); sp.translate(V(-ob.XMin, -ob.YMin, -ob.ZMin))
    p_imp = os.path.join(D, "STL" if k in PIEZAS else "STL_PROBETAS", nm + ".stl"); write_stl(p_imp, sp, nm + " imprimir mm")
    p_mon = os.path.join(D, "STL", "posicion_montaje", nm + "_montaje.stl"); write_stl(p_mon, s, nm + " montaje mm")
    vb = mv(s)
    R[k] = dict(brep_volumen_mm3=round(vb, 1), step=step_check(stp), stl_imprimir=check_stl(p_imp), stl_montaje=check_stl(p_mon), orientacion_impresion=GIRO[k] or "sin giro")
    R[k]["dif_volumen_STL_vs_BREP_%"] = round(100 * (R[k]["stl_imprimir"]["volumen_mm3"] - vb) / vb, 3)
    R[k]["dif_volumen_STEP_vs_BREP_%"] = round(100 * (R[k]["step"]["volumen_mm3"] - vb) / vb, 4)
    print(k, json.dumps(R[k], ensure_ascii=False), flush=True)
cj = os.path.join(SD, "AVO_BACK_V4_CONJUNTO_MONTADO.step"); Import.export(objs, cj)
R["CONJUNTO"] = dict(step=step_check(cj))
pc = os.path.join(D, "STL", "AVO_BACK_V4_CONJUNTO_MONTADO.stl")
TOL = 0.05; parts_v = []
for o in objs:
    tmp = pc + ".tmp"; write_stl(tmp, rd(os.path.join(D, "BREP", o.Label + ".brep")), "x"); bb_ = open(tmp, "rb").read(); parts_v.append(bb_[84:]); os.remove(tmp)
ntot = sum(len(x) // 50 for x in parts_v)
with open(pc, "wb") as fo:
    fo.write(b"AVO BACK V4 conjunto montado mm (solo visualizar)".ljust(80, b" ")); fo.write(struct.pack("<I", ntot)); [fo.write(x) for x in parts_v]
TOL = 0.02
R["CONJUNTO"]["stl"] = check_stl(pc)
R["CONJUNTO"]["nota"] = "7 piezas en contacto (junta comprimida): el STL del conjunto es solo para visualizar"
for p in glob.glob(os.path.join(D, "STEP_KIT", "*.step")): R[os.path.basename(p)] = dict(step=step_check(p))
json.dump(R, open(os.path.join(D, "validacion_step_stl_v4.json"), "w"), indent=1, ensure_ascii=False)
print("FIN")
