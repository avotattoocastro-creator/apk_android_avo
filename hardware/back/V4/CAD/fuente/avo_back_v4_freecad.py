# -*- coding: utf-8 -*-
"""
AVO Performance Horse · AVO BACK V4 · carcasa de espalda compacta (PCB propia + URTK1.2 + batería 654060)
Modelo B-Rep paramétrico (FreeCAD 1.0.2 / OpenCascade). Parte de la Rev E.5 (avo_v22h_revE_freecad.py, 29/10/2026):
conserva casco, chaflanes, labio, junta TPU, tornillería de cierre, soporte con imanes + gancho, contraplaca y torre de la L.

Distribución elegida (estudio A–D en DOCS/ESTUDIO_DISTRIBUCION.md): MIXTA C + contorno D
  · Batería 654060 en su cuna en el suelo (sin bobina debajo), PCM hacia +X.
  · URTK1.2 (ZED-F9P) ENCIMA de la batería, donde estaba la Heltec, a la MISMA altura que en la Rev E (PCB del ZED a Z 9,6):
    la L, la torre y la antena no cambian de altura. Lado −X sobre la bandeja (2 pivotes en sus agujeros + 2 pisadores de la
    tapa); lado +X atornillado a 2 separadores M3 que suben del suelo justo detrás de la batería.
  · PCB AVO BACK V4 (ESP32-S3) en la COLA, en un bolsillo de la base (Z 2,5–3,5), con recortes para separadores y tornillos.
    La cola es obligatoria de todos modos: la antena Q39 Ø44,3 necesita ~29 mm de tapa por detrás del eje de la L.
  · REV B (30/10/2026): sin Qi ni reed/Hall. 3 contactos en el fondo (tornillos M2: SYS y BAT en la cola, GND aparte);
    el soporte del chaleco puentea SYS–BAT con 2 pines con muelle. Antena FPC de 2,4 GHz en el techo del cuello.
  · Topes de la L en la TAPA (paredes que bajan del techo alrededor del cuerpo de la L): la base queda libre para la PCB.
  · Mismo grosor (cápsula 17,1; soporte 4,5; contraplaca 2,6) y misma anchura (59,0). Solo se acorta X.
Ejes: X 0 = cara del cuello, Y lateral (0 = eje de la L), Z 0 = cara inferior de la base. mm.
"""
import os, sys, json, math
import FreeCAD as App, Part
from FreeCAD import Vector as V

HERE = os.environ.get("AVO_DIR") or (os.path.dirname(os.path.abspath(__file__)) if "__file__" in dir() else os.getcwd())
P = json.load(open(os.path.join(HERE, "parametros_revB.json")))
OUT = os.environ.get("AVO_OUT", os.path.join(HERE, "salida")); os.makedirs(OUT, exist_ok=True)
LOG = []
def log(*a):
    s = " ".join(str(x) for x in a); LOG.append(s); print(s, flush=True)
g = lambda k: P[k]

# ============================================================ PARÁMETROS V4
RE = dict(
    # ----- heredados de la Rev E.5 (sin cambios)
    ZF=6.0, TOP_CHAMFER=(3.5, 4.2), BOT_CHAMFER=0.8, SCREW_CB=(5.9, 3.7, 0.0), SCREW_BRIDGE=0.2,
    INSERT=(4.0, 5.0, 3.2), SCREW_TIP_Z=13.6, COL_WEB=0.7, TOP_Z=17.1, CROWN_DROP=1.2,
    L_FROM_EDGE=18.6, L_BODY=7.6, L_THREAD_D=6.2, L_THREAD_LEN=8.6, L_HEIGHT=14.9, L_LENGTH=16.9, L_NUT_ENV_R=4.39,
    TOWER_R=6.0, HOLE_CLR=0.30, ORING_ANT=(6.0, 1.0), ORING_DEPTH=0.75,
    ANT_D=44.3, ANT_H=40.8, ANT_ENGAGE=4.4, ANT_SEAT=False,
    ZED_CEIL_RELIEF=0.7,
    MAG=(5.0, 1.0), MAG_SKIN=0.3, MAG_CLR=0.15,
    REED=(14.0, 3.2), REED_Z0=1.0, REED_CLR_L=1.0, REED_CLR_W=0.4, REED_LEG=(4.0, 4.0),
    COL_R=3.3, SCREW_R={}, ORING_CB_D=5.1,
    GROOVE=(1.4, 3.0, 0.9), LIP_Y=10.0, ZC=0.10,
    CL=0.12, RW=2.6, MT=4.5, BEAM_T=1.4, BEAM_Y=(-9.5, 7.5), SUP_HOOK_Y=(-1.0, 7.0), HOOK_DEPTH=0.76, RIM_CUT_Y=(-8.6, 9.2), TAB=(1.8, 5.0),
    INS_SUP=(4.0, 4.2), FABRIC=1.5, PLATE_T=2.6, PLATE_MARGIN=4.0, BACK_R=220.0,
    # ----- batería LiPo 654060 en el suelo (PCM y cable hacia +X, hacia la PCB)
    BAT=(60.0, 40.0, 6.5), BAT_CLR=0.2, BAT_X0=4.0, BAT_SKIN=0.8, BAT_HEAD=0.3, FRAME_T=0.8,
    BAT_WIRE_Y=(-14.0, -6.0),         # paso del cable de la batería (PH2.0) del extremo +X al bolsillo de la PCB
    # ----- bandeja de la URTK1.2 sobre la batería
    TRAY_T=0.8, TRAY_HALF_W=21.0, TRAY_RIB=1.2, TRAY_EDGE=0.7,
    STOP_WALL_T=1.2, STOP_WALL_CLR=0.15,
    CLIPS=((14.0, -1, 5.0), (60.0, -1, 6.0), (14.0, 1, 5.0), (60.0, 1, 6.0)), CLIP_ROOT_Z=2.6, CLIP_T=1.2, CLIP_SLOT=0.4, CLIP_ENG=0.40, CLIP_LIP_H=0.6, CLIP_GAP=0.10,
    ZED_POST_R=2.4, ZED_PIN=(1.35, 1.0),   # pivotes de la bandeja bajo los agujeros −X de la URTK1.2: Ø4,8 + pasador Ø2,7 × 1,0 en el agujero Ø3,2
    # ----- URTK1.2 (ZED-F9P): misma altura que la Rev E (PCB a Z 9,6; J2 a Z 10,4)
    ZB=9.6, ZED_Y0=-23.2,
    SEP_R=3.2, SEP_GAP=0.2,           # separadores M3 del lado +X (Ø6,4: pared 1,2 alrededor del inserto Ø4,0), a 0,2 de la batería
    ZED_PAD_R=2.0, ZED_PAD_GAP=0.15, ZED_PAD_DY=-1.0,  # pisadores de la tapa sobre los agujeros −X de la URTK1.2
    # ----- topes de la L en la TAPA (bajan del techo alrededor del cuerpo de la L)
    LSTOP_CLR=0.10, LSTOP_T=2.5, LSTOP_ZLOW=1.0,   # holgura al cuerpo, espesor de pared; la pared baja hasta L_BOT + 1,0
    # ----- PCB en la cola
    PCB_Z=2.5, PCB_T=1.0, POCKET_INSET=5.5, POCKET_WALL_X=1.0, PCB_CLR=0.3,
    RING_R=4.4,                       # anillo exterior (zona libre de la PCB R4,6)
    PCB_KEEP_SCREW=4.05,              # alrededor de cada tornillo que cae en el bolsillo: alojamiento Ø5,9 + 1,1 de pared
    PCB_PINS=((0.0, 0.0),),           # (se recalculan abajo) pivotes de centrado de la PCB desde el fondo del bolsillo
    PCB_PIN=(1.0, 0.8),               # pivote Ø2,0 × 0,8 en agujero NPTH Ø2,2 de la PCB
    PCB_PAD_R=2.0, PCB_PAD_GAP=0.10,  # pisadores de la tapa sobre la PCB (zonas libres reservadas en la PCB, Ø5)
    COMP_MAX_Z=14.4,                  # cota máxima de los componentes de la PCB (techo 15,1 − 0,7)
    # ----- antena FPC de 2,4 GHz (ESP32-S3-MINI-1U) en el techo del cuello, lejos de la antena GNSS
    FPC=(36.0, 10.0, 0.2),
    # ----- tornillos de cierre: 8 × M3 en 4 parejas. S3/S4 bajo el canto de la URTK1.2: columna CORTA (M3 × 6 + inserto M3 × 3)
    SCREWS_SHORT=(), SHORT_TOP=9.3, INSERT_SHORT=(4.0, 3.3),   # V4: sin columnas cortas (no se imprimen sin soportes y quedaban bajo los pads de la URTK1.2)
    INS_SUP_Z=None,
)
RE["CROWN_R"] = g("HALF_W") ** 2 / (2 * RE["CROWN_DROP"])
P["ZF"] = RE["ZF"]; ZF = RE["ZF"]
WALL = g("WALL"); CEIL = RE["TOP_Z"] - WALL; HW, HC = g("HALF_W"), g("HEAD_CORNER")
# --- batería
BL, BW, BT = RE["BAT"]; BC = RE["BAT_CLR"]; FT = RE["FRAME_T"]
BX0 = RE["BAT_X0"]; BX1 = BX0 + BL + 2 * BC; BY = BW / 2 + BC
BZ0 = RE["BAT_SKIN"]; BZ1 = BZ0 + BT
TRAY_Z0 = BZ1 + RE["BAT_HEAD"]; TRAY_Z1 = TRAY_Z0 + RE["TRAY_T"]
NX0 = max(BX0 - FT, g("RIM_W") + 0.15)          # V4: marco y bandeja empiezan detrás del labio de la tapa (cuello)
# --- URTK1.2: el agujero +X queda a SEP_R + SEP_GAP detrás de la batería
ZHX, ZHY = P["ZED_HOLES"][1]                 # (40,767; 2,794) desde la esquina −X −Y
ZED_X1 = BX1 + RE["SEP_GAP"] + RE["SEP_R"] + (g("ZED_SIZE") - ZHX)
ZED_X0 = ZED_X1 - g("ZED_SIZE"); ZED_Y0 = RE["ZED_Y0"]; ZED_Y1 = ZED_Y0 + g("ZED_SIZE_Y")
ZED_PTS = [(ZED_X0 + hx, ZED_Y0 + hy) for hx, hy in P["ZED_HOLES"]]
ZED_PTS_MX = [p for p in ZED_PTS if p[0] < ZED_X0 + 10]; ZED_PTS_PX = [p for p in ZED_PTS if p[0] > ZED_X0 + 10]
ZB = RE["ZB"]; ZED_T = 1.6
SMA_Z = ZB + (g("SMA_Z") - g("ZB")); SMA_Y = 0.0
OX = ZED_X1 + RE["L_FROM_EDGE"]; LB = RE["L_BODY"] / 2
L_BOT = SMA_Z - LB; L_TIP = L_BOT + RE["L_HEIGHT"]; L_SH = L_TIP - RE["L_THREAD_LEN"]; L_NUT = OX + LB - RE["L_LENGTH"]
ANT_FLOOR = RE["TOP_Z"]
# --- planta: el centro del extremo redondo queda 0,4 por detrás del eje de la L (como en la Rev E: XA 136,714 / OX 137,114)
XA = OX - 0.4; L = XA + HW
P["XA"] = XA; P["L_TOTAL"] = L
# --- pivotes y pisadores de la PCB: los decide el generador de la PCB (zonas libres) → pcb_mecanica.json
_PM = os.path.join(HERE, "pcb_mecanica.json")
PCB_MEC = json.load(open(_PM)) if os.path.exists(_PM) else None
# --- tornillos (Rev E.4: 8 en 4 parejas; reubicados para la planta corta)
S_NECK = 7.5; S_TAIL_RECT = ZED_X1 + 5.0; S_MID = ZED_X0 - 5.0   # V4: S3/S4 delante de la URTK1.2 (columnas completas)
SCREWS = [(S_NECK, -24.3), (S_NECK, 24.3), (S_MID, -24.3), (S_MID, 24.3),
          (S_TAIL_RECT, -24.3), (S_TAIL_RECT, 24.3), (XA + 15.3, -17.0), (XA + 15.3, 17.0)]
SCREWS = [(round(x * 2) / 2, y) for x, y in SCREWS]       # V4: X a 0,5 mm (puentes en escalón medidos igual que en la Rev E)
RE["SCREWS"] = [tuple(round(c, 3) for c in s) for s in SCREWS]
# --- imanes de sujeción (6 × Ø5 × 1) y reed (en la cola, bajo la PCB, a lo largo de Y) con sus 3 imanes en el soporte
RE["MAGS"] = ((30.0, -23.8), (30.0, 23.8), (52.0, -23.8), (52.0, 23.8), (XA + 8.0, -23.0), (XA + 8.0, 23.0))
# REV B (30/10/2026): sin Qi ni Hall. Contactos del fondo: tornillo M2 avellanado (inox A2) desde fuera, junta tórica 2 × 1
# en una ranura de la cara superior del suelo (la aprieta la PCB) y tuerca M2 sobre la PCB. Posiciones: las da el generador
# de la PCB (SYS y BAT en la cola, donde estaba el reed; GND aparte). En el soporte del chaleco, 2 pines con muelle bajo
# SYS y BAT unidos por un hilo (puente = encendido).
CONTACTS = [(tuple(v["pos"]), v["red"], k) for k, v in sorted(PCB_MEC["contactos"].items())] if PCB_MEC and "contactos" in PCB_MEC else \
    [((101.0, -8.6), "SYS_IN", "P1"), ((106.8, -8.6), "BAT_F", "P2"), ((80.0, 0.0), "GND", "P3")]
RE["CONTACTS"] = [[round(c[0][0], 3), round(c[0][1], 3), c[1], c[2]] for c in CONTACTS]
RE.update(CONTACT_CSK_D=4.1, CONTACT_HOLE=2.3, CONTACT_ORING=(2.0, 1.0), CONTACT_GROOVE=(2.2, 4.4, 0.75),
          POGO_D=2.05, POGO_TIP=0.8, POGO_CH=(1.6, 1.4), POGO_ON=("SYS_IN", "BAT_F"))
RE["REED_MAGS"] = ()                       # V4 REV B: sin imanes de sensor en el soporte
REED_C = HALL_C = None
# --- tornillos del soporte a la contraplaca
RE["SUP_SCREWS"] = ((18.0, -14.0), (18.0, 14.0), (56.0, -14.0), (56.0, 14.0), (XA + 4.0, -11.0), (XA + 4.0, 11.0))
def col_r(i): return RE["SCREW_R"].get(i, RE["COL_R"])

RE.update(DERIVADOS=dict(LARGO=round(L, 3), XA=round(XA, 3), BAT_X=[round(BX0, 3), round(BX1, 3)], BAT_Y=round(BY, 3), BAT_Z=[BZ0, BZ1],
                         TRAY_Z=[round(TRAY_Z0, 3), round(TRAY_Z1, 3)], ZED_X=[round(ZED_X0, 3), round(ZED_X1, 3)], ZED_Y=[ZED_Y0, round(ZED_Y1, 3)],
                         ZED_AGUJEROS=[[round(a, 3), round(b, 3)] for a, b in ZED_PTS], SALIDA_ANTENA_X=round(OX, 3),
                         L_Z=[round(L_BOT, 3), round(L_SH, 3), round(L_TIP, 3)], L_CARA_MACHO_X=round(L_NUT, 3), CONTACTOS=RE["CONTACTS"],
                         TECHO_INTERIOR=CEIL, TORNILLOS=RE["SCREWS"]))

# ============================================================ primitivas (Rev D/E)
# ============================================================ primitivas (Rev D)
def box(a, c):
    x0, x1 = sorted([a[0], c[0]]); y0, y1 = sorted([a[1], c[1]]); z0, z1 = sorted([a[2], c[2]])
    return Part.makeBox(x1 - x0, y1 - y0, z1 - z0, V(x0, y0, z0))
def ctype(e):
    try: return e.Curve
    except Exception: return None
def is_circle(e, r=None, tol=1e-4):
    c = ctype(e); return isinstance(c, Part.Circle) and (r is None or abs(c.Radius - r) < tol)
def vcyl(x, y, r, z0, z1): return Part.makeCylinder(r, z1 - z0, V(x, y, z0), V(0, 0, 1))
def xcyl(y, z, r, x0, x1): return Part.makeCylinder(r, x1 - x0, V(x0, y, z), V(1, 0, 0))
def outline_wire(d=0.0, z=0.0):
    r, R, hw, x0 = HC + d, HW + d, HW + d, -d
    cy = HW - HC; c1, c2 = (HC, -cy), (HC, cy); s = math.sqrt(0.5)
    e = [Part.LineSegment(V(HC, -hw, z), V(XA, -hw, z)).toShape(),
         Part.Arc(V(XA, -R, z), V(XA + R, 0, z), V(XA, R, z)).toShape(),
         Part.LineSegment(V(XA, hw, z), V(HC, hw, z)).toShape(),
         Part.Arc(V(HC, hw, z), V(c2[0] - r * s, c2[1] + r * s, z), V(x0, cy, z)).toShape(),
         Part.LineSegment(V(x0, cy, z), V(x0, -cy, z)).toShape(),
         Part.Arc(V(x0, -cy, z), V(c1[0] - r * s, c1[1] - r * s, z), V(HC, -hw, z)).toShape()]
    return Part.Wire(e)
def prism(d, z0, z1): return Part.Face(outline_wire(d, z0)).extrude(V(0, 0, z1 - z0))
def ring(d_out, d_in, z0, z1): return prism(d_out, z0, z1).cut(prism(d_in, z0 - 0.5, z1 + 0.5))
def fuse_all(shapes):
    out = shapes[0]
    for sh in shapes[1:]: out = out.fuse(sh)
    return out.removeSplitter()
def edges_on_cyl(sol, cx, cy, r, tol=1e-3):
    res = []
    for f in sol.Faces:
        sf = f.Surface
        if isinstance(sf, Part.Cylinder) and abs(sf.Radius - r) < tol and abs(sf.Center.x - cx) < tol and abs(sf.Center.y - cy) < tol and abs(abs(sf.Axis.z) - 1) < 1e-6:
            res += f.Edges
    return res
def mesh_volume(s, tol=0.01):
    v, f = s.tessellate(tol); tot = 0.0
    for a, b, c in f:
        p, q, r_ = v[a], v[b], v[c]; tot += p.dot(q.cross(r_))
    return tot / 6.0
FALLOS = []
def try_fillet(sol, r, edges, name, dvmax=None, convex=False):
    if not edges: log("  redondeo", name, ": sin aristas"); return sol
    try:
        out = sol.makeFillet(r, edges)
        if not out.isValid() or len(out.Solids) != 1: raise RuntimeError("no válido")
        dv = mesh_volume(out) - mesh_volume(sol)
        if convex: bad = dv > 0.5 or (dvmax is not None and -dv > dvmax)
        else: bad = dv < -0.5 or (dvmax is not None and dv > dvmax)
        if bad: raise RuntimeError("volumen incoherente (dV=%.1f)" % dv)
        log("  redondeo", name, "R%s ok (dV %.1f mm3)" % (r, dv)); return out
    except Exception as ex:
        log("  AVISO redondeo", name, "R%s no realizado:" % r, str(ex)[:60]); FALLOS.append(name); return sol

# ============================================================ casco: techo abombado, SIN asiento de pedestal
def is_vertical_face(f):
    s = f.Surface
    if isinstance(s, Part.Plane): return abs(s.Axis.z) < 1e-6
    if isinstance(s, Part.Cylinder): return abs(abs(s.Axis.z) - 1) < 1e-6
    return False
def top_edges(sol, zlo):
    out = []
    for e in sol.Edges:
        fs = sol.ancestorsOfType(e, Part.Face)
        if len(fs) != 2: continue
        v = [is_vertical_face(f) for f in fs]
        if v[0] != v[1]:
            other = fs[1] if v[0] else fs[0]
            if isinstance(other.Surface, Part.Plane) and abs(other.Surface.Axis.z) > 0.999 and abs(other.CenterOfMass.z - zlo) < 1e-6: continue
            if e.BoundBox.ZMax < zlo + 1e-6: continue
            out.append(e)
    return out
def chamfer_inset(d):
    """chaflán interior paralelo al exterior a distancia d: (inserción en planta, altura) desde la pared y el techo desplazados"""
    a, h = RE["TOP_CHAMFER"]; sl = math.hypot(a, h)
    xt = (a * h + d * sl - d * a) / h; dw = (a * h + d * sl - d * h) / a
    return xt - d, dw - d
def shell_body(d, zlo):
    """cuerpo de la cápsula desplazado d hacia dentro: paredes verticales + techo plano (TOP_Z − d) + chaflán reglado"""
    ins, hv = chamfer_inset(d)
    zt = RE["TOP_Z"] - d; zb = zt - hv
    low = prism(-d, zlo, zb)
    top = Part.makeLoft([outline_wire(-d, zb), outline_wire(-d - ins, zt)], True, True)
    return low.fuse(top).removeSplitter()
def hull(d=0.0, zlo=0.0):
    s = shell_body(d, zlo); log("  casco d=%.2f válido %s" % (d, s.isValid())); return s
def build_common():
    H0 = hull(0.0, 0.0)
    OUTER = H0.makeChamfer(RE["BOT_CHAMFER"], [e for e in H0.Edges if e.BoundBox.ZMax < 1e-6])   # 45° en la cama
    CAV = hull(WALL, -5.0); CAV.fixTolerance(1e-3)
    CLIP_CAV = hull(WALL + 0.3, -5.0); CLIP_CAV.fixTolerance(1e-3)
    OUTER_REF[0], CLIP_REF[0] = OUTER, CLIP_CAV
    global MID
    MID = hull(1.8, -5.0); MID.fixTolerance(1e-3)
    return OUTER, CAV, CLIP_CAV
MID = None

KIT = {"tapa": [], "base": []}
def kreg(part, name, shape, role): KIT[part].append((name, shape.copy(), role))

OUTER_REF, CLIP_REF = [None], [None]

# ============================================================ BOLSILLO DE LA PCB (cola) y contorno de la PCB
def screws_in_pocket():
    return [(i, s) for i, s in enumerate(SCREWS) if s[0] > BX1]
def pocket_face(z=0.0):
    """Planta del bolsillo de la PCB: contorno interior desplazado POCKET_INSET (libre de la lengüeta de la base y de la ranura de
    la junta), desde la pared de la batería hasta el extremo, menos islas bajo los separadores +X de la URTK1.2 y los tornillos."""
    f = Part.Face(outline_wire(-RE["POCKET_INSET"], z))
    x0 = BX1 + RE["POCKET_WALL_X"]
    f = f.common(Part.Face(Part.makePolygon([V(x0, -40, z), V(L + 10, -40, z), V(L + 10, 40, z), V(x0, 40, z), V(x0, -40, z)])))
    holes = [Part.Face(Part.Wire(Part.makeCircle(RE["SEP_R"], V(x, y, z)))) for x, y in ZED_PTS_PX]
    holes += [Part.Face(Part.Wire(Part.makeCircle(RE["PCB_KEEP_SCREW"], V(x, y, z)))) for _, (x, y) in screws_in_pocket()]
    for h in holes: f = f.cut(h)
    return f.removeSplitter() if hasattr(f, "removeSplitter") else f
def pcb_face():
    f = pocket_face(RE["PCB_Z"])
    w = f.Faces[0].makeOffset2D(-RE["PCB_CLR"], join=0, openResult=False, intersection=False)
    return w.Faces[0] if hasattr(w, "Faces") and w.Faces else w
def pcb_pins():
    """2 pivotes de centrado (agujeros NPTH Ø2,2 en la PCB) en zonas libres: delante del eje de la L y en la punta"""
    if PCB_MEC: return [tuple(p) for p in PCB_MEC["pivotes"]]
    return [(ZED_X1 + 6.5, 14.0), (XA + 12.0, -6.0)]
def pcb_pads():
    """pisadores de la tapa sobre la PCB (zonas Ø5 sin componentes reservadas en la PCB)"""
    if PCB_MEC: return [tuple(p) for p in PCB_MEC["pisadores"]]
    return [(ZED_X1 + 6.5, -16.0), (OX + 9.0, 13.0), (XA + 18.0, -4.0)]

# ============================================================ TAPA
def build_tapa(OUTER, CAV):
    top = OUTER.common(box((-20, -50, ZF), (L + 20, 50, 60)))
    lip = ring(0.0, -g("RIM_W"), ZF, ZF + g("RIM_H"))
    z1_ = ZF + g("RIM_H"); dz_ = g("RIM_W") - WALL
    ramp = prism(-(WALL - 1.0), z1_ - 0.01, z1_ + dz_).cut(Part.makeLoft([outline_wire(-g("RIM_W"), z1_ - 0.01), outline_wire(-WALL, z1_ + dz_)], True, True))
    lip = lip.fuse(ramp).removeSplitter()
    sh = top.cut(CAV.cut(lip)).removeSplitter()
    kreg("tapa", "TAPA_casco_y_labio", sh, "cuerpo"); log("  tapa: casco + labio", sh.isValid())
    # --- columnas de cierre; S3/S4 cortas (bajo el canto de la URTK1.2): de la cara de unión a SHORT_TOP
    for i, (sx, sy) in enumerate(SCREWS):
        r = col_r(i); short = i in RE["SCREWS_SHORT"]
        ztop = RE["SHORT_TOP"] if short else 50
        col = vcyl(sx, sy, r, ZF, ztop).common(MID)
        if sx > XA: ux, uy = sx - XA, sy
        elif sx < HC + 1: ux, uy = (0.0, math.copysign(1, sy))
        else: ux, uy = 0.0, math.copysign(1, sy)
        n_ = math.hypot(ux, uy); ux, uy = ux / n_, uy / n_
        wb = Part.makeBox(12.0, 2 * r * RE["COL_WEB"], (ztop - ZF - P["TONGUE"][1] - 0.2) if short else 60, V(0, -r * RE["COL_WEB"], 0))
        wb.rotate(V(0, 0, 0), V(0, 0, 1), math.degrees(math.atan2(uy, ux)))
        wb.translate(V(sx, sy, ZF + P["TONGUE"][1] + 0.2)); col = col.fuse(wb.common(MID)).removeSplitter()
        kreg("tapa", "COLUMNA_S%d_X%.1f_Y%.1f%s" % (i + 1, sx, sy, "_CORTA" if short else ""), col, "union")
        sh = sh.fuse(col).removeSplitter()
    # --- torre de la L (aprieta el hombro con la junta tórica 6 × 1) + TOPES DE LA L en la tapa (3 paredes alrededor del cuerpo)
    tw = vcyl(OX, 0, RE["TOWER_R"], L_SH, 40).common(CAV)
    tw = tw.cut(Part.makeCylinder(RE["L_NUT_ENV_R"] + 0.4, OX - LB - L_NUT + 5, V(L_NUT - 5, SMA_Y, SMA_Z), V(1, 0, 0)))
    c_, t_ = RE["LSTOP_CLR"], RE["LSTOP_T"]; zl = L_BOT + RE["LSTOP_ZLOW"]
    st = fuse_all([box((OX - LB, sg * (LB + c_), zl), (OX + LB + c_ + t_, sg * (LB + c_ + t_), 40)) for sg in (-1, 1)] +
                  [box((OX + LB + c_, -(LB + c_ + t_), zl), (OX + LB + c_ + t_, LB + c_ + t_, 40))]).common(CAV)
    ant = tw.fuse(st).removeSplitter(); kreg("tapa", "ANTENA_TORRE_Y_TOPES_L", ant, "union"); sh = sh.fuse(ant).removeSplitter()
    # --- insertos: M3 ≤ 5 mm (Ø4,0 × 5,5) + paso de la punta; columnas cortas: inserto M3 × 3 (Ø4,0 × 3,3), sin paso
    idd, idp, ipd = RE["INSERT"]
    for i_, (sx, sy) in enumerate(SCREWS):
        if i_ in RE["SCREWS_SHORT"]:
            sd, sp = RE["INSERT_SHORT"]; t_ = vcyl(sx, sy, sd / 2, ZF - 1, ZF + sp)
            kreg("tapa", "CORTE_INSERTO_M3x3_S%d_D4.0_P3.3" % (i_ + 1), t_, "corte")
        else:
            t_ = vcyl(sx, sy, idd / 2, ZF - 1, ZF + idp + 0.5).fuse(vcyl(sx, sy, ipd / 2, ZF, RE["SCREW_TIP_Z"])).removeSplitter()
            kreg("tapa", "CORTE_INSERTO_M3_S%d_D4.0_P5.5" % (i_ + 1), t_, "corte")
        sh = sh.cut(t_)
    # --- paso de la rosca SMA + ranura de la junta tórica
    rh = RE["L_THREAD_D"] / 2 + RE["HOLE_CLR"]
    t_ = vcyl(OX, 0, rh, L_SH - 1, 40); kreg("tapa", "CORTE_PASO_ROSCA_SMA_D%.2f" % (2 * rh), t_, "corte"); sh = sh.cut(t_)
    oid, ocs = RE["ORING_ANT"]
    t_ = vcyl(OX, 0, oid / 2 + ocs + 0.1, L_SH - 1, L_SH + RE["ORING_DEPTH"]); kreg("tapa", "CORTE_RANURA_JUNTA_TORICA_6x1", t_, "corte"); sh = sh.cut(t_)
    # --- hueco del cuerpo de la L entre los topes (por si la pared roza el hexágono) y rebaje del techo sobre J3/J1
    if RE["ZED_CEIL_RELIEF"] > 0:
        cv = CAV.copy(); cv.translate(V(0, 0, RE["ZED_CEIL_RELIEF"]))
        t_ = cv.common(box((ZED_X0 - 0.5, ZED_Y0 + 2.0, CEIL - 3.0), (ZED_X0 + 9.5, ZED_Y1 - 1.0, CEIL + 2.0)))
        kreg("tapa", "CORTE_REBAJE_TECHO_CONECTORES_ZED", t_, "corte"); sh = sh.cut(t_)
    # --- (V4: después del rebaje del techo, para que no queden sueltos) pisadores sobre los agujeros −X de la URTK1.2 y sobre la PCB
    for k_, (px, py) in enumerate(ZED_PTS_MX):
        py = py + (RE["ZED_PAD_DY"] if py < 0 else 0.0)        # V4: el del lado −Y se aparta del J1 (USB-C, posición estimada)
        pd = vcyl(px, py, RE["ZED_PAD_R"], ZB + ZED_T + RE["ZED_PAD_GAP"], 40).common(OUTER_REF[0])   # hasta el techo rebajado
        kreg("tapa", "PISADOR_URTK_%d" % (k_ + 1), pd, "union"); sh = sh.fuse(pd).removeSplitter()
    for k_, (px, py) in enumerate(pcb_pads()):
        pd = vcyl(px, py, RE["PCB_PAD_R"], RE["PCB_Z"] + RE["PCB_T"] + RE["PCB_PAD_GAP"], 40).common(MID)
        kreg("tapa", "PISADOR_PCB_%d" % (k_ + 1), pd, "union"); sh = sh.fuse(pd).removeSplitter()
    sh = sh.removeSplitter()
    if not sh.isValid(): raise SystemExit("TAPA NO VÁLIDA")
    return sh

# ============================================================ BASE
def column_keep(extra=0.3):
    return Part.makeCompound([vcyl(sx, sy, col_r(i) + extra, -5, 60) for i, (sx, sy) in enumerate(SCREWS)])
def build_base(OUTER, CAV, CLIP_CAV):
    fl = OUTER.common(box((-20, -50, -1), (L + 20, 50, ZF)))
    gw, gd = g("GROOVE_W"), g("GROOVE_D"); g0 = g("RIM_W") / 2 - gw / 2
    fl = fl.cut(ring(-g0, -(g0 + gw), ZF - gd, ZF + 1))
    tw, th, tg = P["TONGUE"]
    tong = ring(-(g("RIM_W") + tg), -(g("RIM_W") + tg + tw), ZF, ZF + th)
    md_, _ = RE["MAG"]
    tong = tong.cut(Part.makeCompound([vcyl(sx, sy, col_r(i) + 0.6, -5, 60) for i, (sx, sy) in enumerate(SCREWS)] +
                                      [vcyl(mx, my, (md_ + RE["MAG_CLR"]) / 2 + 0.2, -5, 60) for mx, my in RE["MAGS"]] +
                                      [box((-5, -BY - FT - 0.8, -5), (BX0 + 2.0, BY + FT + 0.8, 60))])).removeSplitter()   # V4: sin lengüeta en el cuello sobre la batería   # un solo corte (V4: dos cortes seguidos dejaban la base no orientable)
    fl = fl.fuse(tong).removeSplitter()
    kreg("base", "BASE_placa_ranura_lengueta", fl.removeSplitter(), "cuerpo")
    feats, FN = [], []
    def F(nm, s): feats.append(s); FN.append(nm)
    # ---- separadores +X de la URTK1.2 (suben del suelo, detrás de la batería; inserto M3 ≤ 5 mm)
    for i_, (hx, hy) in enumerate(ZED_PTS_PX): F("URTK_SEPARADOR_%d" % (i_ + 1), vcyl(hx, hy, RE["SEP_R"], ZF - 0.1, ZB))
    # ---- marco de la batería hasta la bandeja; paso del cable en el extremo +X
    fr = box((NX0, -BY - FT, ZF - 0.1), (BX1 + FT, BY + FT, TRAY_Z0)).cut(box((BX0, -BY, 0), (BX1, BY, 20)))
    wy0, wy1 = RE["BAT_WIRE_Y"]
    fr = fr.cut(box((BX1 - 1, wy0, BZ0 + 1.0), (BX1 + FT + 1, wy1, 20)))
    fr = fr.cut(column_keep(1.0))
    F("BATERIA_CUNA_MARCO", fr)
    # ---- paredes de tope de la bandeja + 4 clics (como la Rev E)
    yo = BY + FT; wt = RE["STOP_WALL_T"]; wc = RE["STOP_WALL_CLR"]; ct, sl, e, lh = RE["CLIP_T"], RE["CLIP_SLOT"], RE["CLIP_ENG"], RE["CLIP_LIP_H"]
    for sg in (-1, 1):
        wall = box((NX0, sg * yo, ZF - 0.1), (BX1 + FT, sg * (yo + wt), TRAY_Z0))
        wall = wall.fuse(box((NX0, sg * (RE["TRAY_HALF_W"] + wc), TRAY_Z0 - 0.05), (BX1 + FT, sg * (yo + wt), TRAY_Z1))).removeSplitter()
        for (cx, cs, cw) in RE["CLIPS"]:
            if cs == sg: wall = wall.cut(box((cx - cw / 2 - sl, sg * (yo - 0.01), RE["CLIP_ROOT_Z"] - 1), (cx + cw / 2 + sl, sg * (yo + wt + 5), 30)))
        for (px, py) in ZED_PTS_MX:                                             # muesca para las orejas de la bandeja bajo los pivotes
            if py * sg > 0: wall = wall.cut(vcyl(px, py, RE["ZED_POST_R"] + 0.3, TRAY_Z0 - 0.2, 30))
        F("BANDEJA_PARED_TOPE_%s" % ("Ymenos" if sg < 0 else "Ymas"), wall)
    for i_, (cx, sg, cw) in enumerate(RE["CLIPS"]):
        yi = RE["TRAY_HALF_W"] + wc + RE["CLIP_GAP"]
        beam = box((cx - cw / 2, sg * yi, RE["CLIP_ROOT_Z"]), (cx + cw / 2, sg * (yi + ct), TRAY_Z1 + lh + 0.6))
        prof = Part.makePolygon([V(cx - cw / 2, sg * (yi + 0.01), TRAY_Z1 + 0.05), V(cx - cw / 2, sg * (RE["TRAY_HALF_W"] - e), TRAY_Z1 + 0.05),
                                 V(cx - cw / 2, sg * (RE["TRAY_HALF_W"] - e), TRAY_Z1 + 0.25), V(cx - cw / 2, sg * (yi + 0.01), TRAY_Z1 + lh + 0.6),
                                 V(cx - cw / 2, sg * (yi + 0.01), TRAY_Z1 + 0.05)])
        F("BANDEJA_CLIC_%d" % (i_ + 1), beam.fuse(Part.Face(prof).extrude(V(cw, 0, 0))).removeSplitter())
    for (cx, sg, cw) in RE["CLIPS"]:
        yi = RE["TRAY_HALF_W"] + RE["STOP_WALL_CLR"] + RE["CLIP_GAP"]
        fl = fl.cut(box((cx - cw / 2 - RE["CLIP_SLOT"], sg * (BY + FT + 0.05), RE["CLIP_ROOT_Z"]), (cx + cw / 2 + RE["CLIP_SLOT"], sg * (yi + RE["CLIP_T"] + RE["CLIP_SLOT"]), ZF + 0.01)))
    # ---- pivotes de centrado de la PCB (desde el fondo del bolsillo)
    pr_, ph_ = RE["PCB_PIN"]
    for i_, (px, py) in enumerate(pcb_pins()): F("PCB_PIVOTE_%d" % (i_ + 1), vcyl(px, py, pr_, RE["PCB_Z"] - 0.1, RE["PCB_Z"] + ph_))
    keep = column_keep(0.3)
    zk = Part.makeCompound([vcyl(hx, hy, RE["SEP_R"] + 0.3, -5, 60) for (hx, hy) in ZED_PTS_PX] +
                           [vcyl(mx, my, (RE["MAG"][0] + RE["MAG_CLR"]) / 2 + 0.4, -5, 60) for (mx, my) in RE["MAGS"]])
    feats = [f.cut(keep) if (nm.startswith("URTK_SEPARADOR") or nm.startswith("PCB_PIVOTE")) else f.cut(keep).cut(zk) for f, nm in zip(feats, FN)]
    feat = fuse_all(feats)
    clip = CLIP_CAV.common(prism(-(g("RIM_W") + 0.3), -10, 60).fuse(box((-20, -50, ZF + g("RIM_H")), (L + 20, 50, 60))))
    feat = feat.common(clip)
    for nm_, f_ in zip(FN, feats): kreg("base", nm_, f_.common(clip), "union")
    def C(nm_, t_):
        kreg("base", nm_, t_, "corte"); return fl.cut(t_)
    # ---- bolsillo de la PCB (antes de unir los elementos: los separadores y pivotes quedan de pie dentro)
    pf = pocket_face(RE["PCB_Z"]); pk = pf.extrude(V(0, 0, ZF + 1 - RE["PCB_Z"]))
    fl = C("CORTE_BOLSILLO_PCB_Z%.1f" % RE["PCB_Z"], pk)
    fl = fl.fuse(feat).removeSplitter()
    # ---- alojamientos en el suelo
    fl = C("CORTE_BATERIA_ALOJAMIENTO", box((BX0, -BY, BZ0), (BX1, BY, ZF + 1)))
    fl = C("CORTE_PASO_CABLE_BATERIA", box((BX1 - 1, wy0, BZ0 + 1.0), (BX1 + RE["POCKET_WALL_X"] + 1, wy1, ZF + 1)))
    # ---- contactos del fondo (REV B): avellanado 90° Ø4,1 desde fuera + paso Ø2,3 + ranura de la junta tórica 2 × 1 bajo la PCB
    gi, go, gd = RE["CONTACT_GROOVE"]; ck = RE["CONTACT_CSK_D"] / 2; hr_ = RE["CONTACT_HOLE"] / 2
    for (cx_, cy_), net_, ref_ in CONTACTS:
        cone = Part.makeCone(ck + 0.5, hr_, ck + 0.5 - hr_, V(cx_, cy_, -0.5))          # 90°: radio = ck en Z 0
        t_ = fuse_all([cone, vcyl(cx_, cy_, hr_, -1, RE["PCB_Z"] + 0.1),
                       vcyl(cx_, cy_, go / 2, RE["PCB_Z"] - gd, RE["PCB_Z"] + 0.1)]).removeSplitter()
        fl = C("CORTE_CONTACTO_%s_%s_M2_AVELLANADO_Y_JUNTA" % (ref_, net_), t_)
    md, mt_ = RE["MAG"]
    for i_, (mx, my) in enumerate(RE["MAGS"]):
        fl = C("CORTE_IMAN_%d_D%.2f" % (i_ + 1, md + RE["MAG_CLR"]), vcyl(mx, my, (md + RE["MAG_CLR"]) / 2, RE["MAG_SKIN"], ZF + 1))
    # ---- tornillos (alojamiento de cabeza Ø5,9 × 3,7 + junta tórica, puentes en escalón, paso Ø3,4 pasante)
    cbd, cbh, sac = RE["SCREW_CB"]
    for i_, (sx, sy) in enumerate(SCREWS):
        bz = RE["SCREW_BRIDGE"]; hr = 3.4 / 2
        cb_ = vcyl(sx, sy, cbd / 2, -1, cbh)
        slot = box((sx - cbd / 2 - 0.1, sy - hr, cbh - 0.01), (sx + cbd / 2 + 0.1, sy + hr, cbh + bz)).common(vcyl(sx, sy, cbd / 2, cbh - 0.02, cbh + bz + 0.01))
        sq = box((sx - hr, sy - hr, cbh + bz - 0.01), (sx + hr, sy + hr, cbh + 2 * bz))
        t_ = fuse_all([cb_, slot, sq, vcyl(sx, sy, hr, cbh + 2 * bz - 0.01, ZF + 1)]).removeSplitter()
        fl = C("CORTE_TORNILLO_S%d_CABEZA_Y_JUNTA_TORICA_D5.9x3.7_PASANTE" % (i_ + 1), t_)
    # ---- ranuras exteriores del cierre al soporte
    gz0, gz1, gd = RE["GROOVE"]
    nk = box((-1.0, -RE["LIP_Y"], gz0), (gd, RE["LIP_Y"], gz1 - gd))
    wd = Part.Face(Part.makePolygon([V(-1.0, -RE["LIP_Y"], gz1 - gd), V(gd, -RE["LIP_Y"], gz1 - gd), V(0.0, -RE["LIP_Y"], gz1), V(-1.0, -RE["LIP_Y"], gz1 + 1.0),
                                     V(-1.0, -RE["LIP_Y"], gz1 - gd)])).extrude(V(0, 2 * RE["LIP_Y"], 0))
    fl = C("CORTE_RANURA_LABIO_CUELLO", nk.fuse(wd).removeSplitter())
    hya, hyb = RE["SUP_HOOK_Y"][0] - 1.5, RE["SUP_HOOK_Y"][1] + 1.5
    ar = Part.makeCylinder(HW + 2, gz1 - gd - gz0, V(XA, 0, gz0)).cut(Part.makeCylinder(HW - gd, gz1 - gd - gz0 + 2, V(XA, 0, gz0 - 1)))
    ar = ar.fuse(Part.makeCylinder(HW + 2, gd + 1.0, V(XA, 0, gz1 - gd)).cut(Part.makeCone(HW - gd, HW + 1.0, gd + 1.0, V(XA, 0, gz1 - gd))))
    fl = C("CORTE_RANURA_GANCHO_EXTREMO", ar.common(box((XA + 20, hya, gz0 - 1), (XA + 40, hyb, gz1 + 2))))
    idd, idp, ipd = RE["INSERT"]
    for i_, (hx, hy) in enumerate(ZED_PTS_PX):
        fl = C("CORTE_INSERTO_M3_URTK_%d_D4.0_P5.5" % (i_ + 1), vcyl(hx, hy, idd / 2, ZB - idp - 0.5, ZB + 1))
    return fl.removeSplitter()

# ============================================================ BANDEJA DE LA URTK1.2 (sobre la batería)
def build_bandeja(CLIP_CAV):
    hw = RE["TRAY_HALF_W"]
    t = box((NX0 + 0.15, -hw, TRAY_Z0), (BX1 + FT - 0.15, hw, TRAY_Z1))
    pr_ = RE["ZED_POST_R"]; pinr, pinh = RE["ZED_PIN"]
    feats = [t]
    for (px, py) in ZED_PTS_MX:
        feats.append(vcyl(px, py, pr_, TRAY_Z0, ZB))                           # pivote hasta la cara inferior de la URTK1.2 (con su oreja)
        feats.append(vcyl(px, py, pinr, ZB - 0.1, ZB + pinh))                  # pasador dentro del agujero Ø3,2
    # refuerzo +1,2 fuera de la URTK1.2 (cuello) y a lo largo de los bordes
    rb = box((NX0 + 0.15, -hw + RE["TRAY_EDGE"], TRAY_Z1 - 0.05), (ZED_X0 - 0.6, hw - RE["TRAY_EDGE"], TRAY_Z1 + RE["TRAY_RIB"]))
    feats.append(rb)
    b = fuse_all(feats)
    b = b.cut(column_keep(0.3)).common(CLIP_CAV)
    for (hx, hy) in ZED_PTS_PX: b = b.cut(vcyl(hx, hy, RE["SEP_R"] + 0.3, -5, 40))
    return b.removeSplitter()


# ============================================================ ANILLOS DE LOS SEPARADORES (PCB ↔ URTK1.2)
def build_anillos():
    """2 anillos impresos alrededor de los separadores +X de la URTK1.2: apoyan en la cara superior de la PCB y los aprieta la
    URTK1.2 al atornillarla → la PCB queda sujeta en el lado de la batería sin tornillos propios."""
    ri, ro = RE["SEP_R"] + 0.15, RE["RING_R"]
    z0, z1 = RE["PCB_Z"] + RE["PCB_T"], ZB
    out = []
    for (x, y) in ZED_PTS_PX:
        a = vcyl(x, y, ro, z0, z1).cut(vcyl(x, y, ri, z0 - 1, z1 + 1))
        a = a.common(pocket_face(z0 - 1).extrude(V(0, 0, z1 - z0 + 2)))       # dentro de la planta del bolsillo de la PCB
        a = a.common(box((BX1 + RE["POCKET_WALL_X"] + 0.15, -40, z0 - 1), (L, 40, z1 + 1)))
        out.append(a)
    return Part.makeCompound(out)
# ============================================================ JUNTA TPU
def build_junta():
    j0 = g("RIM_W") / 2 - g("GASKET_W") / 2
    j = ring(-j0, -(j0 + g("GASKET_W")), ZF - g("GROOVE_D"), ZF - g("GROOVE_D") + g("GASKET_H"))
    return j.removeSplitter()

# ============================================================ SOPORTE (cerco + labio + gancho elástico + 6 imanes + imán del reed)
def build_soporte():
    CL, RW, MT = RE["CL"], RE["RW"], RE["MT"]
    gz0, gz1, gd = RE["GROOVE"]; ZC = RE["ZC"]; RH = gz1 - 0.15
    p = prism(CL + RW, -MT, 0)
    p = p.makeChamfer(RE["BOT_CHAMFER"], [e for e in p.Edges if e.BoundBox.ZMax < -MT + 1e-6])   # 45° en la cama
    rim = prism(CL + RW, 0, RH).cut(prism(CL, -1, RH + 1))
    y0c, y1c = RE["RIM_CUT_Y"]
    rim = rim.cut(box((L - 6, y0c, -1), (L + 10, y1c, RH + 3)))
    p = p.fuse(rim).removeSplitter()
    # labio del cuello (entra en la ranura de la tapa)
    lip_in = 0.71
    ly_ = RE["LIP_Y"] - 0.2; zt_ = gz1 - lip_in - 0.15                         # techo del labio a 45°, paralelo a la ranura (0,15)
    lipf = Part.Face(Part.makePolygon([V(-CL - 0.3, -ly_, gz0 + ZC), V(lip_in, -ly_, gz0 + ZC), V(lip_in, -ly_, zt_), V(lip_in - (RH - zt_), -ly_, RH),
                                       V(-CL - 0.3, -ly_, RH), V(-CL - 0.3, -ly_, gz0 + ZC)])).extrude(V(0, 2 * ly_, 0))
    p = p.fuse(lipf).removeSplitter()
    # viga elástica CURVA concéntrica al extremo redondo + gancho concéntrico (engancha 0,76 en todo su largo).
    # Baja hasta la cama por una ranura pasante del soporte (0,3): se imprime sin soportes. Se suelta tirando del tirador.
    by0, by1 = RE["BEAM_Y"]; bt = RE["BEAM_T"]; hy0, hy1 = RE["SUP_HOOK_Y"]
    ri = HW + CL; ro = ri + bt; rt = HW - RE["HOOK_DEPTH"]                    # radios: cara interior de la viga, exterior, punta del gancho
    def ann(r0, r1, ya, yb, za, zb):                                           # sector anular en el extremo redondo
        a = Part.makeCylinder(r1, zb - za, V(XA, 0, za)).cut(Part.makeCylinder(r0, zb - za + 2, V(XA, 0, za - 1)))
        return a.common(box((XA + 10, ya, za - 1), (XA + 60, yb, zb + 1)))
    beam = ann(ri, ro, by0, by1, -MT, RH)
    prof = Part.Face(Part.makePolygon([V(XA + rt, 0, gz0 + ZC), V(XA + ri + 0.2, 0, gz0 + ZC), V(XA + ri + 0.2, 0, RH), V(XA + ri, 0, RH),
                                       V(XA + rt, 0, gz0 + 0.5), V(XA + rt, 0, gz0 + ZC)]))
    hk = prof.revolve(V(XA, 0, 0), V(0, 0, 1), 360).common(box((XA + 10, hy0, gz0), (XA + 60, hy1, RH + 1)))
    tw_, tl_ = RE["TAB"]
    tab = ann(ro - 0.1, ro + tw_, by1 - tl_, by1, -MT, RH + 1.6)                # el tirador también baja hasta la cama
    beam = fuse_all([beam, hk, tab])
    # ranura pasante alrededor de la viga (0,3 por dentro): la viga queda libre salvo en su raíz (Y < by0 + 2)
    p = p.cut(ann(ri - 0.3, ro + 10, by0 + 2.0, by1 + 0.6, -MT - 1, RH + 5))
    p = p.fuse(beam).removeSplitter()
    # imanes (cara superior, enrasados) e insertos M3×3 desde abajo para la contraplaca
    md, mt_ = RE["MAG"]
    for (mx, my) in list(RE["MAGS"]) + [tuple(c) for c in RE["REED_MAGS"]]:
        p = p.cut(vcyl(mx, my, (md + RE["MAG_CLR"]) / 2, -mt_ - 0.05, 1))
    # REV B: pines con muelle bajo SYS y BAT (Ø2,05 pasante, pegados; la punta sobresale POGO_TIP) y canal del puente por debajo
    on = [c for c in CONTACTS if c[1] in RE["POGO_ON"]]
    cw_, ch_ = RE["POGO_CH"]
    for (cx_, cy_), net_, ref_ in on:
        p = p.cut(vcyl(cx_, cy_, RE["POGO_D"] / 2, -MT - 1, 1))
        p = p.cut(vcyl(cx_, cy_, 1.6, -MT - 1, -MT + ch_))                       # alojamiento de la soldadura del hilo
    if len(on) == 2:
        (ax_, ay_), (bx_, by_) = on[0][0], on[1][0]
        p = p.cut(box((min(ax_, bx_), ay_ - cw_ / 2, -MT - 1), (max(ax_, bx_), ay_ + cw_ / 2, -MT + ch_)))
    hd, hdep = RE["INS_SUP"]
    for (sx, sy) in RE["SUP_SCREWS"]:
        p = p.cut(vcyl(sx, sy, hd / 2, -MT - 1, -MT + hdep))
    return p.removeSplitter()

# ============================================================ TOPE DEL REED (pieza suelta: entra en el alojamiento del reed y queda
#   atrapado entre el reed y la cara inferior de la bandeja; el reed no puede subir ni moverse)
def build_tope_reed():
    rx, ry = RE["REED_C"]; rl, rt = RE["REED"]; cw = RE["REED_CLR_W"]; sc, sz, st, hl, ch = RE["REED_STOP"]
    x0 = rx - rt / 2 - cw + sc + 0.05                    # 0,15 a la pared del alojamiento y 0,1 al faldón del cuello
    x1 = rx + rt / 2 + cw - sc                           # 0,1 a la pared; el conector SH1.25 queda a 0,3
    z0 = RE["REED_Z0"] + rt + sz                         # 0,1 sobre el reed apoyado en el fondo
    z1 = TRAY_Z0 - st                                    # 0,1 bajo la bandeja
    t = box((x0, ry - hl, z0), (x1, ry + hl, z1))
    t = t.makeChamfer(ch, [e for e in t.Edges if abs(e.BoundBox.ZMax - e.BoundBox.ZMin) < 1e-6])   # entrada en el alojamiento
    return t.removeSplitter()

# ============================================================ CONTRAPLACA (por dentro del chaleco; tela entre soporte y contraplaca)
CONTRA_R = [1.6]
def build_contraplaca():
    ztop = -RE["MT"] - RE["FABRIC"]; t = RE["PLATE_T"]; R = RE["BACK_R"]; m = RE["PLATE_MARGIN"]
    pl = prism(m, -14, ztop)
    Y = 45.0; zf = lambda y: ztop - t - y * y / (2 * R)
    par = Part.BezierCurve(); par.setPoles([V(0, -Y, zf(-Y)), V(0, 0, zf(-Y) + (Y / R) * Y), V(0, Y, zf(Y))])
    w = Part.Wire([par.toShape(), Part.LineSegment(V(0, Y, zf(Y)), V(0, Y, -30)).toShape(), Part.LineSegment(V(0, Y, -30), V(0, -Y, -30)).toShape(),
                   Part.LineSegment(V(0, -Y, -30), V(0, -Y, zf(-Y))).toShape()])
    f = Part.Face(w); f.translate(V(-20, 0, 0)); below = f.extrude(V(L + 40, 0, 0))
    pl = pl.cut(below).removeSplitter()
    top_e = [e for e in pl.Edges if abs(e.BoundBox.ZMax - ztop) < 1e-6 and abs(e.BoundBox.ZMin - ztop) < 1e-6]
    pl = pl.makeChamfer(0.8, top_e)                                                 # 45°: esta cara va en la cama
    def bottom_edge(e):
        try: return all(abs(p.z - zf(p.y)) < 1e-3 for p in e.discretize(8))
        except Exception: return False
    bot_e = [e for e in pl.Edges if bottom_edge(e)]
    pl0 = pl; pl = try_fillet(pl, 1.6, bot_e, "contraplaca arista espalda R1,6", convex=True, dvmax=400)
    if pl is pl0:
        for r in (1.5, 1.4, 1.3):
            FALLOS.pop()
            pl = try_fillet(pl0, r, bot_e, "contraplaca arista espalda R%s" % r, convex=True, dvmax=400)
            if pl is not pl0: CONTRA_R[0] = r; break
    cd = P["INS"]["M3x6"]["clear_d"] / 2
    for (sx, sy) in RE["SUP_SCREWS"]:
        zb = ztop - t - sy ** 2 / (2 * R)
        pl = pl.cut(vcyl(sx, sy, cd, -40, 10))
        rcs = 3.5                                                                   # avellanado Ø7,0 (ISO 10642 M3: cabeza Ø6,72)
        pl = pl.cut(Part.makeCone(rcs + 1.0, cd, rcs + 1.0 - cd, V(sx, sy, zb - 1.0), V(0, 0, 1)))
    sl = []; x = 22.0
    while x < L - 30:
        for sy in (-18.0, -7.0, 4.0, 15.0):
            if any(abs(x - a) < 9 and abs(sy - b) < 9 for a, b in RE["SUP_SCREWS"]): continue
            sl.append(fuse_all([vcyl(x, sy - 2.5, 1.5, -40, 10), vcyl(x, sy + 2.5, 1.5, -40, 10), box((x - 1.5, sy - 2.5, -40), (x + 1.5, sy + 2.5, 10))]))
        x += 8.5
    pl = pl.cut(fuse_all(sl))
    return pl.removeSplitter()


# ============================================================ REFERENCIAS DE LA ELECTRÓNICA (no se imprimen)
def referencias(pcb_comp=None):
    E = {}
    E["bateria_654060"] = box((BX0 + BC, -BW / 2, BZ0), (BX0 + BC + BL, BW / 2, BZ1))
    # contactos (REV B): tornillo M2 × 5 avellanado (cabeza Ø3,8 enrasada) + junta tórica 2 × 1 aplastada a 0,75
    ck_ = 1.9; trs = []
    for (cx_, cy_), net_, ref_ in CONTACTS:
        trs += [Part.makeCone(ck_, 1.0, ck_ - 1.0, V(cx_, cy_, 0.02)), vcyl(cx_, cy_, 1.0, 0.9, RE["PCB_Z"] - 0.02)]
    E["contactos_M2"] = Part.makeCompound(trs)
    E["juntas_contactos"] = Part.makeCompound([vcyl(cx_, cy_, 2.0, RE["PCB_Z"] - 0.74, RE["PCB_Z"] - 0.01).cut(vcyl(cx_, cy_, 1.12, 0, 9))
                                             for (cx_, cy_), _, _ in CONTACTS])
    E["pines_pogo_soporte"] = Part.makeCompound([vcyl(cx_, cy_, 0.95, -RE["MT"] + RE["POGO_CH"][1], RE["POGO_TIP"] - 0.82)
                                               for (cx_, cy_), net_, _ in CONTACTS if net_ in RE["POGO_ON"]])
    zpcb = box((ZED_X0, ZED_Y0, ZB), (ZED_X1, ZED_Y1, ZB + ZED_T))
    for hx, hy in ZED_PTS: zpcb = zpcb.cut(Part.makeCylinder(1.6, 3, V(hx, hy, ZB - 0.5)))
    E["urtk_pcb"] = zpcb
    zcx, zcy = (ZED_X0 + ZED_X1) / 2, (ZED_Y0 + ZED_Y1) / 2
    E["urtk_modulo_ZED"] = box((zcx - 8.5, zcy - 11, ZB + ZED_T), (zcx + 8.5, zcy + 11, ZB + ZED_T + 2.4))
    E["urtk_J3_GH6_estimado"] = box((ZED_X0 + 3.0, ZED_Y1 - 29.0, ZB + ZED_T), (ZED_X0 + 7.3, ZED_Y1 - 17.0, ZB + ZED_T + 4.25))
    E["urtk_J1_USBC_estimado"] = box((ZED_X0 + 0.5, ZED_Y0 + 4.0, ZB + ZED_T), (ZED_X0 + 8.0, ZED_Y0 + 13.0, ZB + ZED_T + 3.3))
    E["urtk_J2_SMA"] = box((ZED_X1, SMA_Y - 3.2, SMA_Z - 3.2), (ZED_X1 + 2.1, SMA_Y + 3.2, SMA_Z + 3.2)).fuse(
        Part.makeCylinder(3.1, L_NUT - ZED_X1 - 2.1, V(ZED_X1 + 2.1, SMA_Y, SMA_Z), V(1, 0, 0)))
    hexr = RE["L_NUT_ENV_R"]
    hexw = Part.makePolygon([V(L_NUT, SMA_Y + hexr * math.cos(math.radians(60 * k)), SMA_Z + hexr * math.sin(math.radians(60 * k))) for k in range(7)])
    E["L_tuerca_y_cuerpo_hex"] = Part.Face(hexw).extrude(V(OX - LB - L_NUT, 0, 0))
    E["L_cuerpo"] = box((OX - LB, SMA_Y - LB, L_BOT), (OX + LB, SMA_Y + LB, L_SH))
    E["L_rosca_hembra"] = vcyl(OX, SMA_Y, RE["L_THREAD_D"] / 2, L_SH, L_TIP)
    E["antena_GNSS_Q39"] = vcyl(OX, 0, RE["ANT_D"] / 2, ANT_FLOOR + 0.02, ANT_FLOOR + RE["ANT_H"]).cut(vcyl(OX, 0, 4.5, ANT_FLOOR - 1, ANT_FLOOR + RE["ANT_ENGAGE"] + 0.5))
    fl_, fw_, ft_ = RE["FPC"]
    E["antena_FPC_2G4"] = box((BX0 + 2.0, -fl_ / 2, CEIL - ft_ - 0.05), (BX0 + 2.0 + fw_, fl_ / 2, CEIL - 0.05))
    md, mth = RE["MAG"]
    E["imanes_capsula"] = Part.makeCompound([vcyl(mx, my, md / 2, RE["MAG_SKIN"] + 0.02, RE["MAG_SKIN"] + mth) for mx, my in RE["MAGS"]])
    E["imanes_soporte"] = Part.makeCompound([vcyl(mx, my, md / 2, -mth, -0.02) for mx, my in list(RE["MAGS"]) + [tuple(c) for c in RE["REED_MAGS"]]])
    E["pcb_placa"] = pcb_face().extrude(V(0, 0, RE["PCB_T"])).cut(Part.makeCompound([vcyl(x, y, 1.1, 0, 10) for x, y in pcb_pins()]))
    if PCB_MEC and PCB_MEC.get("envolventes"):
        zt = RE["PCB_Z"] + RE["PCB_T"]
        E["pcb_componentes"] = Part.makeCompound([box((a, b, zt + 0.01), (c, d, zt + h)) for _, a, b, c, d, h in PCB_MEC["envolventes"]])
    if pcb_comp is not None: E["pcb_componentes"] = pcb_comp
    return E

# ============================================================ PROBETAS
def probetas(parts):
    pr = {}
    bx = box((ZED_X1 - 1.0, -40, -6), (L + 5.0, 40, 60))
    pr["P1_COLA_BASE"] = parts["base"].common(bx); pr["P1_COLA_TAPA"] = parts["tapa"].common(bx)
    pr["P1_COLA_SOPORTE"] = parts["soporte"].common(box((ZED_X1 - 1.0, -40, -6), (L + 10.0, 40, 60)))
    bx = box((-5, -40, -6), (34.0, 40, 60))
    pr["P2_CUELLO_BASE"] = parts["base"].common(bx); pr["P2_CUELLO_TAPA"] = parts["tapa"].common(bx)
    pr["P2_CUELLO_SOPORTE"] = parts["soporte"].common(bx); pr["P2_CUELLO_BANDEJA"] = parts["bandeja_urtk"].common(bx)
    return {k: v.removeSplitter() for k, v in pr.items()}

def report(s):
    ob = s.optimalBoundingBox()
    try: s.check(True); bop = True
    except Exception: bop = False
    return dict(valido=bool(s.isValid()), comprobacion_BOP=bop, solidos=len(s.Solids), cascaras_cerradas=all(x.isClosed() for x in s.Shells), caras=len(s.Faces),
                volumen_mm3=round(mesh_volume(s), 1), bbox=[round(v, 3) for v in (ob.XMin, ob.XMax, ob.YMin, ob.YMax, ob.ZMin, ob.ZMax)])

def edges_json(face):
    """contorno exacto de la PCB (rectas y arcos) en coordenadas de la carcasa, para el generador de KiCad"""
    out = []
    for w in face.Wires:
        segs = []
        for e in w.OrderedEdges:
            c = ctype(e); a, b = e.valueAt(e.FirstParameter), e.valueAt(e.LastParameter)
            if e.Orientation == "Reversed": a, b = b, a
            if isinstance(c, Part.Line) or isinstance(c, Part.LineSegment):
                segs.append(dict(t="L", a=[round(a.x, 4), round(a.y, 4)], b=[round(b.x, 4), round(b.y, 4)]))
            elif isinstance(c, Part.Circle):
                m = e.valueAt(0.5 * (e.FirstParameter + e.LastParameter))
                segs.append(dict(t="A", a=[round(a.x, 4), round(a.y, 4)], m=[round(m.x, 4), round(m.y, 4)], b=[round(b.x, 4), round(b.y, 4)]))
            else:
                pts = e.discretize(Deflection=0.01)
                for p, q in zip(pts[:-1], pts[1:]): segs.append(dict(t="L", a=[round(p.x, 4), round(p.y, 4)], b=[round(q.x, 4), round(q.y, 4)]))
        out.append(dict(exterior=(w.isSame(face.OuterWire)), segmentos=segs))
    return out

NOMBRES = dict(tapa="AVO_BACK_V4_TAPA", base="AVO_BACK_V4_BASE", bandeja_urtk="AVO_BACK_V4_BANDEJA_URTK", junta_TPU="AVO_BACK_V4_JUNTA_TPU",
               soporte="AVO_BACK_V4_SOPORTE", contraplaca="AVO_BACK_V4_CONTRAPLACA", anillos="AVO_BACK_V4_ANILLOS_SEPARADOR")
if __name__ == "__main__" or "AVO_RUN" in os.environ:
    import time, shutil
    T0 = time.time(); RES = {}
    log("RE:", json.dumps(RE, ensure_ascii=False))
    OUTER, CAV, CLIP_CAV = build_common(); OUTER_REF[0], CLIP_REF[0] = OUTER, CLIP_CAV; log("cascos", round(time.time() - T0, 1), "s")
    parts = {}
    parts["tapa"] = build_tapa(OUTER, CAV); log("tapa", round(time.time() - T0, 1), "s")
    parts["base"] = build_base(OUTER, CAV, CLIP_CAV); log("base", round(time.time() - T0, 1), "s")
    parts["bandeja_urtk"] = build_bandeja(CLIP_CAV)
    parts["junta_TPU"] = build_junta()
    parts["soporte"] = build_soporte(); log("soporte", round(time.time() - T0, 1), "s")
    parts["contraplaca"] = build_contraplaca(); log("contraplaca", round(time.time() - T0, 1), "s")
    parts["anillos"] = build_anillos()
    for d in ("STEP", "BREP", "PROBETAS", "REFERENCIAS"): os.makedirs(os.path.join(OUT, d), exist_ok=True)
    for k, s in parts.items():
        RES[k] = report(s); log(k, RES[k])
        s.exportStep(os.path.join(OUT, "STEP", NOMBRES[k] + ".step")); s.exportBrep(os.path.join(OUT, "BREP", NOMBRES[k] + ".brep"))
    for k, s in (("OUTER", OUTER), ("CAV", CAV)): s.exportBrep(os.path.join(OUT, "BREP", "_aux_%s.brep" % k))
    PR = probetas(parts)
    for k, s in PR.items():
        RES["probeta_" + k] = report(s); s.exportBrep(os.path.join(OUT, "PROBETAS", "AVO_BACK_V4_" + k + ".brep"))
    E = referencias()
    shutil.rmtree(os.path.join(OUT, "REFERENCIAS"), ignore_errors=True); os.makedirs(os.path.join(OUT, "REFERENCIAS"))
    for k, s in E.items(): s.exportBrep(os.path.join(OUT, "REFERENCIAS", "_%s.brep" % k))
    pf = pcb_face()
    json.dump(dict(origen="coordenadas de la carcasa (X cuello→cola, Y lateral, mm); KiCad: x = X, y = −Y",
                   z_cara_inferior=RE["PCB_Z"], espesor=RE["PCB_T"], area_mm2=round(pf.Area, 1),
                   contorno=edges_json(pf), pivotes_NPTH=[list(p) for p in pcb_pins()], pivote_d=2 * RE["PCB_PIN"][0] + 0.2,
                   pisadores=[list(p) for p in pcb_pads()], pisador_r=RE["PCB_PAD_R"] + 0.5,
                   separadores_urtk=[list(p) for p in ZED_PTS_PX], separador_r=RE["SEP_R"] + RE["PCB_CLR"],
                   urtk_agujeros_mx=[list(p) for p in ZED_PTS_MX], urtk=dict(x0=ZED_X0, x1=ZED_X1, y0=ZED_Y0, y1=ZED_Y1, zb=ZB),
                   zonas=dict(
                       bajo_URTK=dict(x1=ZED_X1 + 0.3, zmax=ZB - 0.3, nota="componentes bajo la URTK1.2: altura ≤ ZB − 0,3 − cara superior PCB"),
                       bajo_J2_L=dict(x0=ZED_X1 - 0.3, x1=OX + LB + 0.4, y=[-(RE["L_NUT_ENV_R"] + 0.6), RE["L_NUT_ENV_R"] + 0.6],
                                      zmax=SMA_Z - RE["L_NUT_ENV_R"] - 0.2, nota="banda bajo J2/tuerca/cuerpo de la L"),
                       topes_L=dict(x0=OX - LB, x1=OX + LB + RE["LSTOP_CLR"] + RE["LSTOP_T"] + 0.3, y=[-(LB + RE["LSTOP_CLR"] + RE["LSTOP_T"] + 0.3), LB + RE["LSTOP_CLR"] + RE["LSTOP_T"] + 0.3],
                                    zmax=L_BOT + RE["LSTOP_ZLOW"] - 0.3),
                       resto=dict(zmax=RE["COMP_MAX_Z"])),
                   contactos=RE["CONTACTS"],
                   bateria_cable_y=list(RE["BAT_WIRE_Y"]), bateria_x1=BX1),
              open(os.path.join(OUT, "pcb_contorno_v4.json"), "w"), indent=1, ensure_ascii=False)
    for part, items in KIT.items():
        d_ = os.path.join(OUT, "KIT", part); shutil.rmtree(d_, ignore_errors=True); os.makedirs(d_)
        for i_, (nm_, sh_, role_) in enumerate(items): sh_.exportBrep(os.path.join(d_, "%03d__%s__%s.brep" % (i_, role_, nm_)))
    json.dump(dict(piezas=RES, RE=RE, pcb_area_mm2=round(pf.Area, 1), fallos_redondeo=FALLOS, tiempo_s=round(time.time() - T0, 1)),
              open(os.path.join(OUT, "informe_modelo_v4.json"), "w"), indent=1, ensure_ascii=False, default=str)
    log("FIN", round(time.time() - T0, 1), "s · largo", round(L, 2), "· PCB", round(pf.Area, 1), "mm2 · fallos:", FALLOS)
