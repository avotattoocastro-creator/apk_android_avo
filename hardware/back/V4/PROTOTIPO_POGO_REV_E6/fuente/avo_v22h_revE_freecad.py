# -*- coding: utf-8 -*-
"""
AVO Performance Horse V2.2-H · Rev E.2 · carcasa de espalda a batería, carga Qi, sellada (objetivo IP67)
Modelo B-Rep paramétrico (FreeCAD 1.0 / OpenCascade 7.8). Parte del modelo Rev D (avo_v22h_revD_freecad.py).

Peticiones del usuario (26/10/2026) y cómo se resuelven:
  1. Batería LiPo 654060 (60 × 40 × 6,5, Ellenne 2000 mAh) sin perder compacidad: en su cuna en el suelo, BAJO la Heltec.
     La Heltec va encima, en una bandeja propia (CUNA_HELTEC). Techo 15,0 → 15,5 (+0,5 mm). Planta igual (166,2 × 59,0).
  2. Carga Qi como la cincha: bobina 23 × 30 en un alojamiento del suelo bajo la ZED (0,7 de piel), placa Qi 15 × 18 en su cuna.
  3. Antena: adaptador SMA en L (macho → hembra 90°) directo en J2. La rosca hembra atraviesa la tapa; la antena se enrosca
     fuera, dentro de un asiento rebajado. Topes laterales y final fuertes en la base ajustados al cuerpo de la L
     (0,1 por lado) + torre en la tapa con junta tórica 6 × 1 sobre el hombro de la L.
     Pedestal, pasamuros y coaxial eliminados.
  4. Eliminados: pisa-cables, salida de cable y manguito, abertura USB-C, sujeción por puente (2 × M2) y punto GND.
  5. Cierre: 12 tornillos M3 avellanados desde abajo (antes 7) en insertos M3×6 de la tapa, todos por dentro de la junta;
     junta tórica 3 × 1 en cada taladro de la base (sella el vástago contra la columna). Junta TPU perimetral continua.
  6. Cada componente (menos la ZED, que sigue en sus 4 separadores) con su cuna: batería, Heltec, bobina Qi, placa Qi, reed.
  7. Interruptor magnético (reed 14 × 3,2) como la cincha: lo activa 1 imán Ø5 × 1 del soporte.
  8. Sujeción al soporte como la cincha: 6 imanes Ø5 × 1 (polaridad alterna), cerco, labio en el cuello y gancho
     elástico con tirador en el extremo redondo. El soporte se fija al chaleco con la contraplaca (tela en medio, 6 × M3).
Ejes: X 0 = cara del cuello, Y lateral (0 = eje), Z 0 = cara inferior de la base. mm.
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
XA, HW, HC, ZF = g("XA"), g("HALF_W"), g("HEAD_CORNER"), g("ZF")
L = g("L_TOTAL")

# ============================================================ PARÁMETROS REV E
RE = dict(
    # ===== Rev E.3: impresión SIN SOPORTES en todas las piezas + tornillería igual que la cincha REV 5.5
    ZF=6.0,                # cara de unión base/tapa (Rev E.2: 2,5). Suelo de la base 6,0: cabe el alojamiento de cabeza + junta tórica
                           # con ≥ 1,1 de pared hasta la ranura de la junta TPU (Z 4,8)
                           # (Ø5,9 × 3,7 + capa de sacrificio 0,3) lejos de la ranura de la junta TPU. La altura total NO cambia.
    TOP_CHAMFER=(3.5, 4.2),  # tapa: techo plano + chaflán (3,5 en planta × 4,2 en altura, 50°): se imprime boca abajo sin soportes
    BOT_CHAMFER=0.8,       # chaflán 45° en la arista de la cama (base y soporte), como la cincha
    SCREW_CB=(5.9, 3.7, 0.0), SCREW_BRIDGE=0.2,   # Rev E.4.1: agujero PASANTE sin capa de sacrificio: 2 capas de puente en escalón (ranura 3,4 y cuadrado 3,4) sobre el alojamiento;   # tornillo M3 de cabeza cilíndrica (Ø5,5 × 3) + junta tórica 3 × 1 bajo la cabeza: Ø × prof. + capa de sacrificio
    INSERT=(4.0, 5.0, 3.2),     # inserto M3 ≤ 5 mm (igual que la cincha): taladro Ø4,0 × 5,0 (+0,5) y paso Ø3,2 por encima para la punta
    SCREW_TIP_Z=13.6,      # fondo del paso de la punta (M3×10 llega a 12,95)
    COL_WEB=0.7,           # nervio de cada columna a la pared (ancho = 2·r·0,7)
    TOP_Z=17.1,            # sin cambios            # techo en el eje (Rev D 15,0; Rev E 15,5): Rev E.1 +1,6 por la bobina Qi bajo la batería
    CROWN_DROP=1.2,
    # --- batería LiPo 654060 (anuncio: 60 × 40 × 6,5; cables por el lado corto del PCM, conector PH2.0)
    BAT=(60.0, 40.0, 6.5), BAT_CLR=0.2, BAT_X0=13.3, BAT_HEAD=0.3, FRAME_T=0.8,
    # --- bandeja de la Heltec sobre la cuna de la batería
    TRAY_T=0.8, TRAY_HALF_W=21.0,
    TRAY_POSTS=((10.6, -16.0),), POST_R=2.5, PIN_R=1.3, PIN_H=0.7,     # Rev E.1: sin poste +Y (quedaría bajo los SOT-23 de la Heltec)
    TRAY_PADS=((16.0, -12.0), (20.0, -16.5), (36.0, -16.5), (66.0, -16.5), (72.0, -8.0), (72.0, 16.0)),   # Rev E.5 (pisadores de la tapa)
    PAD_R=2.0, PAD_GAP=0.05,
    TRAY_RIB=2.2, TRAY_EDGE=0.7,   # Rev E.6: 1,2 → 2,2 (la bandeja baja 1,0: la cara del refuerzo queda donde la pisan los pisadores de la tapa E.5)
    # Rev E.6 (30/10/2026, sin Qi): la batería baja 1,0 (sin bobina debajo) y la bandeja con ella; la Heltec se calza 1,0 sobre
    # la bandeja → queda a la MISMA altura que en la E.5 (la tapa E.5 sirve tal cual) y las pestañas son 1,0 más altas.
    BAT_DROP=1.0, HELTEC_SHIM=1.0,
    POLOLU=(17.8, 11.4), POLOLU_CLR=0.2, POLOLU_X=51.0, POLOLU_WALL=1.0,       # S7V8F3 en el sitio de la placa Qi, a 1,0 del borde −Y del refuerzo
    CABLE_SLOT=(5.0, 6.9, -2.0, 2.0),                                          # un solo pasacables centrado (sustituye a las 2 ranuras del reed)
    CABLE_LIPS_X=(21.0, 38.0, 53.0), CABLE_LIP=(3.0, 1.2),                     # sujetacables (5 × AWG30) en el canto del refuerzo junto a la Heltec
    EDGE_HOOKS_X=(30.0, 46.0), EDGE_HOOK=(2.5, 1.0, 0.5),                      # pestañas nuevas en el borde +Y (largo, espesor, solape)   # Rev E.2: bandeja 0,8 + 1,2 = 2,0 fuera de la Heltec y de la placa Qi (marco rígido); borde de 0,7 sin engordar para los clics
    # Rev E.2: pared de tope pegada al marco de la batería (centra la bandeja) + 4 clics de seguridad en la base (la bandeja no cambia)
    STOP_WALL_T=1.2, STOP_WALL_CLR=0.15,
    CLIPS=((20.0, -1, 8.0), (70.5, -1, 4.0), (20.0, 1, 8.0), (40.5, 1, 8.0)), CLIP_ROOT_Z=2.6, CLIP_T=1.2, CLIP_SLOT=0.4, CLIP_ENG=0.40, CLIP_LIP_H=0.6, CLIP_GAP=0.10,   # Rev E.3: clics con raíz en Z 2,6 (rebaje en el suelo): brazo libre 7,5, deformación ≈ 2 %; gancho con voladizo 0,65 (≤ 1,0)
    END_STOPS_Y=(-11.0, 11.0), END_STOP=(0.35, 5.0),   # topes finales fuera de los separadores de la ZED (Ø8)
    # --- Heltec HTIT-WSL_V3 (V3.2), centrada en Y sobre la bandeja
    MCU_X0=8.6,            # +5,0 respecto a Rev D: el USB-C queda por debajo del redondeo interior del cuello (Heltec elevada)
    MCU_T=1.8, MCU_Y0=-4.2,     # Rev E.1: Heltec hacia +Y para dejar sitio a la placa Qi en la bandeja
    SOT_ZONE=(1.7, 9.0, 1.0), USB_H=2.8, USB_OVER=1.3, SHIELD_H=2.8,   # SOT_ZONE: componentes inferiores SOT-23 (fotos): desde/hasta el extremo USB, alto
    BTN_ZONE=(0.7, 5.8), BTN_STEM=(2.2, 4.3, 1.1, 1.4), BTN_TOP=1.9,
    MCU_WALL_X0=7.0, HOOK_Y=(0.5, 3.0),
    CONN_POCKET=(0.6, 4.3, 4.05, 3.5, 0.4),
    # --- ZED-F9P URTK1.2: se desplaza +5,0 en X para dejar sitio a la batería (sus separadores no cambian)
    ZED_DX=5.4,
    ZED_DZ=4.1,            # Rev E.2: ZED + L subidas 4,1 → la rosca SMA sale 4,4 sobre la tapa plana (sin asiento rebajado)
    ZED_CEIL_RELIEF=0.7,   # Rev E.2: rebaje interior del techo sobre el borde −X de la ZED (J3 GH 6 pines, J1 USB-C)
    # --- adaptador SMA en L macho-hembra (anuncio Boobrie): rosca hembra Ø6,2 × 8,6; 14,9 de la base del cuerpo a la punta;
    #     16,9 de la cara del macho al lado opuesto; cuerpo y tuerca 7,6. Salida a 18,6 del canto de la ZED (foto del montaje)
    L_FROM_EDGE=18.6, L_BODY=7.6, L_THREAD_D=6.2, L_THREAD_LEN=8.6, L_HEIGHT=14.9, L_LENGTH=16.9, L_NUT_ENV_R=4.39,
    STOP_CLR=0.10, STOP_T=2.5, STOP_TOP=8.6, POCKET_Z=1.3,
    TOWER_R=6.0, HOLE_CLR=0.30, ORING_ANT=(6.0, 1.0), ORING_DEPTH=0.75,   # Rev E.3: paso Ø6,8 para la rosca SMA (1/4"-36 = 6,35; los taladros impresos salen ~0,2 más pequeños)
    ANT_D=44.3, ANT_H=40.8, ANT_SEAT_CLR=0.3, ANT_ENGAGE=4.4, LID_THICK_ZB=11.2, LID_THICK_R=24.8,   # antena Q39: Ø44,3 × 40,8 (anuncio)
    # --- Qi 5 W (como la cincha). Rev E.1: bobina 30 (X) × 23 (Y) con ferrita BAJO LA BATERÍA; placa 18 × 15 en la bandeja junto a la Heltec
    COIL=(23.0, 30.0, 1.6), COIL_CLR=0.2, COIL_SKIN=0.7, COIL_POS=(52.5, -5.0),   # Rev E.2: girada 23 (X) × 30 (Y), pegada al lado −Y, salida de cobre frente a la muesca (foto de la base impresa)
    QI=(18.0, 15.0, 1.0, 1.2), QI_C=(51.0, -12.35), QI_WALL_H=1.6, QI_WIRE_X=(55.5, 59.5),
    # --- reed (Gebildet 14 × 3,2) a lo largo de X
    REED=(14.0, 3.2), REED_C=(7.0, 0.0), REED_Z0=2.5, REED_CLR_L=1.0, REED_CLR_W=0.4, REED_LEG=(4.0, 4.0),   # Rev E.2: cuna más ancha + huecos de 4 × 4 en los extremos para doblar/soldar las patas
    TRAY_CABLE_HOLE=(10.0, 15.0, -10.0, -5.0),
    TRAY_NECK_X=3.0, NECK_SKIRT_X=(4.0, 5.0), NECK_SKIRT_Y=16.0,   # Rev E.3: el faldón del cuello pasa a la BASE (apoyo de la bandeja; la bandeja queda plana por debajo)
    REED_SLOT_X=(5.0, 8.2), REED_SLOT_Y=(8.5, 12.5),                 # ranuras en la bandeja encima de las patas del reed
      # Rev E.2: paso de cables batería → conector de la Heltec (X0, X1, Y0, Y1)
      # 1,0 de holgura en cada extremo (lección de la cincha)     # Rev E.1: en el cuello, a lo largo de Y
    # --- 6 imanes Ø5 × 1 de sujeción (cápsula y soporte enfrentados) + 1 para el reed en el soporte
    MAGS=((48.0, -23.8), (48.0, 23.8), (96.0, -21.5), (92.0, 21.5), (158.0, -9.5), (158.0, 9.5)),   # Rev E.3: imán 4 a (92; 21,5), lejos del alojamiento del tornillo S7; la lengüeta se recorta con su forma
    MAG=(5.0, 1.0), MAG_SKIN=0.3, MAG_CLR=0.15,
    REED_STOP=(0.10, 0.10, 0.10, 6.5, 0.4),   # Rev E.3.1: tope del reed (holgura lateral, sobre el reed asentado, bajo la bandeja, medio largo, chaflán)
    REED_MAGS=(),   # Rev E.6 (prototipo pogo, 30/10/2026): sin reed ni sus imanes
    # Rev E.6: contactos del fondo (tornillo M2 × 5 avellanado inox + junta tórica 2 × 1 + terminal de ojal + tuerca M2):
    # BAT y SYS donde estaba el reed (X 8,8, Y ∓4; X 7 cortaba el faldón del cuello), GND en el cuello lejos de BAT. Pines con muelle del soporte bajo SYS y BAT.
    CONTACTS=(((8.8, -4.0), "BAT"), ((8.8, 4.0), "SYS"), ((8.8, 14.0), "GND")),
    CONTACT_CSK_D=4.1, CONTACT_HOLE=2.3, CONTACT_GROOVE=(2.2, 4.4, 0.75), CONTACT_Z=2.5, CONTACT_POCKET_R=3.4,
    POGO_D=2.05, POGO_CH=(1.6, 1.4), POGO_ON=("SYS", "BAT"),   # Rev E.3.2: 3 imanes Ø5 × 1 del reed en línea con el reed (eje Y), central en la posición de la Rev E, sin separación (se tocan; alojamientos Ø5,15 unidos)
    # --- tornillos de cierre: M3 avellanado (ISO 10642) desde abajo → inserto M3×6 en la columna de la tapa
    # Rev E.4: 8 tornillos en 4 parejas simétricas (se quitan los de X 32, X 100 y la punta X 160,5)
    SCREWS=((6.0, -21.5), (6.0, 21.5), (64.0, -24.3), (64.0, 24.3),
            (122.2, -23.8), (122.2, 23.8), (152.0, -17.0), (152.0, 17.0)),
    SCREW_R={}, COL_R=3.3, CSK_D=6.3, ORING_SCREW=(3.0, 1.0), ORING_CB_D=5.1, ORING_CB_H=0.75,
    # --- cierre al soporte (como la cincha)
    GROOVE=(1.4, 3.0, 0.9), LIP_Y=10.0, HOOK_HALF=5.0, ZC=0.10,   # Rev E.3: ranuras del cierre al soporte en la BASE (Z 1,4–3,0), techo de la ranura a 45°
    CL=0.12, RW=2.6, MT=4.5, BEAM_T=1.4, BEAM_Y=(-9.5, 7.5), SUP_HOOK_Y=(-1.0, 7.0), HOOK_DEPTH=0.76, RIM_CUT_Y=(-8.6, 9.2), TAB=(1.8, 5.0),   # Rev E.3: MT +1,0 para el inserto y el M3×8 desde la contraplaca
    SUP_SCREWS=((22.0, -14.0), (22.0, 14.0), (80.0, -14.0), (80.0, 14.0), (142.0, -11.0), (142.0, 11.0)),
    INS_SUP=(4.0, 4.2),   # Rev E.3: inserto M3 ≤ 4 mm (taladro Ø4,0 × 4,2) desde abajo, 0,3 de piel arriba
    FABRIC=1.5, PLATE_T=2.6, PLATE_MARGIN=4.0, BACK_R=220.0,
    LOGO=None, ANT_SEAT=False,   # Rev E.2: sin letras · antena apoyada en la tapa plana
    LOGO_TXT="AVO.PERFORMANCE", LOGO_CAP=6.4, LOGO_X=60.0, LOGO_RELIEF=0.6,
)
if os.environ.get("AVO_E6_CARGA"):                   # variante: base de carga (pines en BAT y GND, sin puente)
    RE["POGO_ON"] = ("BAT", "GND")
RE["CROWN_R"] = HW ** 2 / (2 * RE["CROWN_DROP"])
P["ZF"] = RE["ZF"]; ZF = RE["ZF"]
WALL = g("WALL"); CEIL = RE["TOP_Z"] - WALL
# --- derivados
BL, BW, BT = RE["BAT"]; BC = RE["BAT_CLR"]
BX0 = RE["BAT_X0"]; BX1 = BX0 + BL + 2 * BC; BY = BW / 2 + BC
BZ0 = RE["COIL_SKIN"] + RE["COIL"][2] + 0.1 - RE["BAT_DROP"]; BZ1 = BZ0 + BT     # Rev E.6: sin bobina, suelo de 1,4 bajo la batería
TRAY_Z0 = BZ1 + RE["BAT_HEAD"]; TRAY_Z1 = TRAY_Z0 + RE["TRAY_T"]
FT = RE["FRAME_T"]
MCU = dict(x0=RE["MCU_X0"], y0=RE["MCU_Y0"], lx=g("MCU")["lx"], ly=g("MCU")["ly"], t=RE["MCU_T"])
MCU_X1 = MCU["x0"] + MCU["lx"]; MCU_Y1 = MCU["y0"] + MCU["ly"]; MCU_Z = TRAY_Z1 + RE["HELTEC_SHIM"]; MCU_T = MCU_Z + MCU["t"]   # Rev E.6: Heltec calzada 1,0
ZDX = RE["ZED_DX"]
ZED_X0 = g("ZED_X0") + ZDX; ZED_Y0 = g("ZED_Y0"); ZED_X1 = ZED_X0 + g("ZED_SIZE"); ZED_Y1 = ZED_Y0 + g("ZED_SIZE_Y")
ZED_PTS = [(x + ZDX, y) for x, y in P["ZED_PTS"]]; ZB = g("ZB") + RE["ZED_DZ"]; ZED_T = 1.6
SMA_Z, SMA_Y = g("SMA_Z") + RE["ZED_DZ"], g("SMA_Y")
STOP_TOP = RE["STOP_TOP"] + RE["ZED_DZ"]
ZP = min(ZF, SMA_Z - RE["L_NUT_ENV_R"] - 0.3)        # rebaje del suelo solo lo justo bajo la tuerca de la L (0,3 de holgura)
OX = ZED_X1 + RE["L_FROM_EDGE"]                       # eje de la salida hembra (vertical)
LB = RE["L_BODY"] / 2
L_BOT = SMA_Z - LB                                    # cara inferior del cuerpo de la L
L_TIP = L_BOT + RE["L_HEIGHT"]                        # punta de la rosca hembra
L_SH = L_TIP - RE["L_THREAD_LEN"]                     # hombro (arranque de la rosca)
L_NUT = OX + LB - RE["L_LENGTH"]                      # cara del macho (frente de la tuerca)
ANT_FLOOR = L_TIP - RE["ANT_ENGAGE"] if RE["ANT_SEAT"] else RE["TOP_Z"]   # apoyo de la antena
COIL_C = tuple(RE["COIL_POS"])
SCREWS = [tuple(s) for s in RE["SCREWS"]]
def col_r(i): return RE["SCREW_R"].get(i, RE["COL_R"])
RE.update(DERIVADOS=dict(BAT_X=[round(BX0, 3), round(BX1, 3)], BAT_Y=round(BY, 3), BAT_Z=[BZ0, BZ1], TRAY_Z=[round(TRAY_Z0, 3), round(TRAY_Z1, 3)],
                         MCU_Z=round(MCU_Z, 3), ZED_X=[round(ZED_X0, 3), round(ZED_X1, 3)], SALIDA_ANTENA_X=round(OX, 3), L_Z=[round(L_BOT, 3), round(L_SH, 3), round(L_TIP, 3)],
                         L_CARA_MACHO_X=round(L_NUT, 3), ASIENTO_ANTENA_Z=round(ANT_FLOOR, 3), BOBINA_C=[round(c, 3) for c in COIL_C], TECHO_INTERIOR=CEIL))
FONT = os.path.join(HERE, "Poppins-BoldItalic.ttf")

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
    global MID
    MID = hull(1.8, -5.0); MID.fixTolerance(1e-3)
    return OUTER, CAV, CLIP_CAV
MID = None

KIT = {"tapa": [], "base": []}
def kreg(part, name, shape, role): KIT[part].append((name, shape.copy(), role))

def logo_solid(zlo=8.0):
    ws = Part.makeWireString(RE["LOGO_TXT"], FONT, 10.0, 0.0)
    faces = [Part.makeFace(ch, "Part::FaceMakerBullseye") for ch in ws if ch]
    comp = Part.makeCompound(faces)
    capf = faces[1].BoundBox; k = RE["LOGO_CAP"] / capf.YLength
    m = App.Matrix(); m.scale(k, k, 1); comp = comp.transformGeometry(m); bb = comp.BoundBox
    comp.translate(V(RE["LOGO_X"] - (bb.XMin + bb.XMax) / 2, -(capf.YMin * k + RE["LOGO_CAP"] / 2), zlo))
    return Part.makeCompound([f.extrude(V(0, 0, 12)) for f in comp.Faces]), comp.BoundBox

# ============================================================ TAPA
def build_tapa(OUTER, CAV):
    top = OUTER.common(box((-20, -50, ZF), (L + 20, 50, 60)))
    lip = ring(0.0, -g("RIM_W"), ZF, ZF + g("RIM_H"))
    # Rev E.3: transición a 45° entre el labio (3,6) y la pared (2,0): boca abajo no queda escalón en el perímetro
    z1_ = ZF + g("RIM_H"); dz_ = g("RIM_W") - WALL
    ramp = prism(-(WALL - 1.0), z1_ - 0.01, z1_ + dz_).cut(Part.makeLoft([outline_wire(-g("RIM_W"), z1_ - 0.01), outline_wire(-WALL, z1_ + dz_)], True, True))
    lip = lip.fuse(ramp).removeSplitter()
    sh = top.cut(CAV.cut(lip)).removeSplitter()
    kreg("tapa", "TAPA_casco_y_labio", sh, "cuerpo"); log("  tapa: casco + labio", sh.isValid())
    # --- logotipo (opcional)
    if not RE["LOGO"]: lg = None
    else: lg, lbb = logo_solid()
    if lg is not None:
     
     skin = shell_body(-RE["LOGO_RELIEF"], 0.0)
     letters = lg.common(skin).cut(CAV)
     kreg("tapa", "LOGO_AVO_PERFORMANCE", letters, "union"); sh = sh.fuse(letters).removeSplitter()
     LOGO_INFO.update(x0=round(lbb.XMin, 2), x1=round(lbb.XMax, 2)); log("  logotipo válido", sh.isValid())
    # --- 12 columnas de cierre (de la cara de unión al techo). Sin acuerdo con el techo: el techo abombado + redondeo R6,5 no lo admite
    for i, (sx, sy) in enumerate(SCREWS):
        r = col_r(i)
        col = vcyl(sx, sy, r, ZF, 50).common(MID)
        # nervio de la columna a la pared más cercana (por encima de la lengüeta de la base): la columna no queda exenta
        if sx > XA: ux, uy = sx - XA, sy
        elif sx < HC + 1: ux, uy = (0.0, math.copysign(1, sy)) if abs(sy) > 10 else (-1.0, 0.0)
        else: ux, uy = 0.0, math.copysign(1, sy)
        n_ = math.hypot(ux, uy); ux, uy = ux / n_, uy / n_
        wb = Part.makeBox(12.0, 2 * r * RE["COL_WEB"], 60, V(0, -r * RE["COL_WEB"], 0)); wb.rotate(V(0, 0, 0), V(0, 0, 1), math.degrees(math.atan2(uy, ux)))
        wb.translate(V(sx, sy, ZF + P["TONGUE"][1] + 0.2)); col = col.fuse(wb.common(MID)).removeSplitter()
        kreg("tapa", "COLUMNA_S%d_X%.1f_Y%.1f" % (i + 1, sx, sy), col, "union")
        sh = sh.fuse(col).removeSplitter()
    # --- refuerzo interior bajo el asiento de la antena + torre que aprieta el hombro de la L
    th = vcyl(OX, 0, RE["LID_THICK_R"], RE["LID_THICK_ZB"], 40).common(CAV)
    tw = vcyl(OX, 0, RE["TOWER_R"], L_SH, 40).common(CAV)
    tw = tw.cut(Part.makeCylinder(RE["L_NUT_ENV_R"] + 0.4, OX - LB - L_NUT + 5, V(L_NUT - 5, SMA_Y, SMA_Z), V(1, 0, 0)))   # libre de la tuerca hexagonal
    th = th.cut(Part.makeCylinder(RE["L_NUT_ENV_R"] + 0.4, OX - LB - L_NUT + 5, V(L_NUT - 5, SMA_Y, SMA_Z), V(1, 0, 0)))
    ant = (th.fuse(tw) if RE["ANT_SEAT"] else tw).removeSplitter(); kreg("tapa", "ANTENA_REFUERZO_Y_TORRE" if RE["ANT_SEAT"] else "ANTENA_TORRE", ant, "union")
    sh = sh.fuse(ant).removeSplitter()
    # --- topes del extremo USB de la Heltec (delante del canto del PCB)
    x0, y0, y1 = MCU["x0"], MCU["y0"], MCU_Y1
    for k_, (ya, yb) in enumerate(((y0 + 0.3, y0 + 2.5), (y1 - 2.5, y1 - 0.3))):
        tp = box((1.0, ya, TRAY_Z1 + 0.05), (x0 - 0.3, yb, CEIL + 1.0)).common(OUTER)   # hasta el techo: impresa boca abajo crece desde la cama
        kreg("tapa", "HELTEC_TOPE_USB_%d" % (k_ + 1), tp, "union"); sh = sh.fuse(tp).removeSplitter()
    # --- pisadores de la bandeja (bajan del techo hasta la cara superior de la bandeja)
    for k_, (px, py) in enumerate(RE["TRAY_PADS"]):
        pd = vcyl(px, py, RE["PAD_R"], TRAY_Z1 + RE["TRAY_RIB"] + RE["PAD_GAP"], 40).common(MID)
        kreg("tapa", "PISADOR_BANDEJA_%d" % (k_ + 1), pd, "union"); sh = sh.fuse(pd).removeSplitter()
    # --- cortes: inserto M3 ≤ 5 mm (Ø4,0 × 5,5) + paso Ø3,2 para la punta del tornillo (como la cincha REV 5.5)
    idd, idp, ipd = RE["INSERT"]
    for i_, (sx, sy) in enumerate(SCREWS):
        t_ = vcyl(sx, sy, idd / 2, ZF - 1, ZF + idp + 0.5).fuse(vcyl(sx, sy, ipd / 2, ZF, RE["SCREW_TIP_Z"])).removeSplitter()
        kreg("tapa", "CORTE_INSERTO_M3_S%d_D4.0_P5.5" % (i_ + 1), t_, "corte"); sh = sh.cut(t_)
    # --- antena: paso de la rosca, ranura de la junta tórica en la cara de la torre, asiento rebajado
    rh = RE["L_THREAD_D"] / 2 + RE["HOLE_CLR"]
    t_ = vcyl(OX, 0, rh, L_SH - 1, 40); kreg("tapa", "CORTE_PASO_ROSCA_SMA_D%.2f" % (2 * rh), t_, "corte"); sh = sh.cut(t_)
    oid, ocs = RE["ORING_ANT"]
    t_ = vcyl(OX, 0, oid / 2 + ocs + 0.1, L_SH - 1, L_SH + RE["ORING_DEPTH"])
    kreg("tapa", "CORTE_RANURA_JUNTA_TORICA_6x1", t_, "corte"); sh = sh.cut(t_)
    ra = RE["ANT_D"] / 2 + RE["ANT_SEAT_CLR"]
    if RE["ANT_SEAT"]:
        t_ = vcyl(OX, 0, ra, ANT_FLOOR, 40); kreg("tapa", "CORTE_ASIENTO_ANTENA_D%.1f" % (2 * ra), t_, "corte"); sh = sh.cut(t_)
    # --- rebaje interior del techo sobre el borde −X de la ZED (J3 / J1 suben con la ZED)
    if RE["ZED_CEIL_RELIEF"] > 0:
        cv = CAV.copy(); cv.translate(V(0, 0, RE["ZED_CEIL_RELIEF"]))
        t_ = cv.common(box((ZED_X0 - 0.5, ZED_Y0 + 2.0, CEIL - 3.0), (ZED_X0 + 9.5, ZED_Y1 - 1.0, CEIL + 2.0)))
        kreg("tapa", "CORTE_REBAJE_TECHO_CONECTORES_ZED", t_, "corte"); sh = sh.cut(t_)
    sh = sh.removeSplitter()
    # redondeo R0,6 del borde del asiento de la antena
    es = [e for e in sh.Edges if is_circle(e, ra, 1e-3) and e.BoundBox.ZMin > ANT_FLOOR + 0.3]
    if RE["ANT_SEAT"]: sh = try_fillet(sh, 0.6, es, "borde asiento antena", convex=True, dvmax=30)
    sh = sh.removeSplitter()
    if not sh.isValid(): raise SystemExit("TAPA NO VÁLIDA")
    return sh
LOGO_INFO = {}

# ============================================================ BASE
def column_keep(extra=0.3):
    return Part.makeCompound([vcyl(sx, sy, col_r(i) + extra, -5, 60) for i, (sx, sy) in enumerate(SCREWS)])
def build_base(OUTER, CAV, CLIP_CAV):
    fl = OUTER.common(box((-20, -50, -1), (L + 20, 50, ZF)))
    gw, gd = g("GROOVE_W"), g("GROOVE_D"); g0 = g("RIM_W") / 2 - gw / 2
    fl = fl.cut(ring(-g0, -(g0 + gw), ZF - gd, ZF + 1))
    tw, th, tg = P["TONGUE"]
    tong = ring(-(g("RIM_W") + tg), -(g("RIM_W") + tg + tw), ZF, ZF + th)
    tong = tong.cut(column_keep(0.6))
    md_, _ = RE["MAG"]
    tong = tong.cut(Part.makeCompound([vcyl(mx, my, (md_ + RE["MAG_CLR"]) / 2 + 0.2, -5, 60) for mx, my in RE["MAGS"]]))   # recorte con la forma del imán (+0,2)
    fl = fl.fuse(tong)
    kreg("base", "BASE_placa_ranura_lengueta", fl.removeSplitter(), "cuerpo")
    feats, FN = [], []
    def F(nm, s): feats.append(s); FN.append(nm)
    # ---- separadores de la ZED (sin cambios, desplazados +ZED_DX)
    for i_, (hx, hy) in enumerate(ZED_PTS): F("ZED_SEPARADOR_%d" % (i_ + 1), vcyl(hx, hy, 4.0, ZF - 0.1, ZB))
    # ---- cuna de la batería: marco 0,8 hasta la bandeja (lado +X solo hasta la ZED); muescas de cables en el lado −X
    fr = box((BX0 - FT, -BY - FT, ZF - 0.1), (BX1 + FT, BY + FT, TRAY_Z0)).cut(box((BX0, -BY, 0), (BX1, BY, 20)))
    for yn in (-14.0, 14.0): fr = fr.cut(box((BX0 - FT - 1, yn - 3.0, BZ0 + 1.6), (BX0 + 1, yn + 3.0, 20)))   # cables de la batería (PCM)
    zc = MCU_Z - MCU["t"] - RE["CONN_POCKET"][3] - 0.4                                                       # bajo el conector SH1.25 inferior
    fr = fr.cut(box((BX0 - FT - 1, MCU["y0"] + 0.2, zc), (BX0 + 1, MCU_Y1 - 0.2, 20)))
    wx0, wx1 = RE["QI_WIRE_X"]
    fr = fr.cut(box((wx0, -BY - FT - 1, ZF), (wx1, -BY + 1, 20)))                                            # hilos de la bobina Qi hacia la placa
    fr = fr.cut(column_keep(1.0))       # el marco se interrumpe en las columnas S3–S6 (sin láminas finas)
    F("BATERIA_CUNA_MARCO", fr)
    # ---- pared de tope pegada al marco (hasta la cara superior de la bandeja) con 4 clics elásticos sueltos de la pared
    yo = BY + FT; wt = RE["STOP_WALL_T"]; wc = RE["STOP_WALL_CLR"]; ct, sl, e, lh = RE["CLIP_T"], RE["CLIP_SLOT"], RE["CLIP_ENG"], RE["CLIP_LIP_H"]
    for sg in (-1, 1):
        wall = box((BX0 - FT, sg * yo, ZF - 0.1), (BX1 + FT, sg * (yo + wt), TRAY_Z0))
        wall = wall.fuse(box((BX0 - FT, sg * (RE["TRAY_HALF_W"] + wc), TRAY_Z0 - 0.05), (BX1 + FT, sg * (yo + wt), TRAY_Z1))).removeSplitter()
        for (cx, cs, cw) in RE["CLIPS"]:
            if cs == sg: wall = wall.cut(box((cx - cw / 2 - sl, sg * (yo - 0.01), RE["CLIP_ROOT_Z"] - 1), (cx + cw / 2 + sl, sg * (yo + wt + 5), 30)))
        if sg < 0:                                                                 # rebaje para el cable de la bobina Qi
            wx0, wx1 = RE["QI_WIRE_X"]; wall = wall.cut(box((wx0, sg * (yo - 0.5), ZF), (wx1, sg * (yo + wt + 5), 30)))
        F("BANDEJA_PARED_TOPE_%s" % ("Ymenos" if sg < 0 else "Ymas"), wall)
    for i_, (cx, sg, cw) in enumerate(RE["CLIPS"]):
        yi = RE["TRAY_HALF_W"] + wc + RE["CLIP_GAP"]          # cara interior del clip (suelto del marco)
        beam = box((cx - cw / 2, sg * yi, RE["CLIP_ROOT_Z"]), (cx + cw / 2, sg * (yi + ct), TRAY_Z1 + lh + 0.6))
        prof = Part.makePolygon([V(cx - cw / 2, sg * (yi + 0.01), TRAY_Z1 + 0.05), V(cx - cw / 2, sg * (RE["TRAY_HALF_W"] - e), TRAY_Z1 + 0.05),
                                 V(cx - cw / 2, sg * (RE["TRAY_HALF_W"] - e), TRAY_Z1 + 0.25), V(cx - cw / 2, sg * (yi + 0.01), TRAY_Z1 + lh + 0.6),
                                 V(cx - cw / 2, sg * (yi + 0.01), TRAY_Z1 + 0.05)])
        F("BANDEJA_CLIC_%d" % (i_ + 1), beam.fuse(Part.Face(prof).extrude(V(cw, 0, 0))).removeSplitter())
    # ---- topes del extremo de la ZED (por fuera del lado +X del marco, hasta la cara superior de la bandeja)
    st_t, st_w = RE["END_STOP"]
    for i_, ly in enumerate(RE["END_STOPS_Y"]):
        F("BANDEJA_TOPE_FINAL_%d" % (i_ + 1), box((BX1 + FT - 0.05, ly - st_w / 2, ZF - 0.1), (BX1 + FT + wc + st_t, ly + st_w / 2, TRAY_Z0)).fuse(
            box((BX1 + FT + wc, ly - st_w / 2, TRAY_Z0 - 0.05), (BX1 + FT + wc + st_t, ly + st_w / 2, TRAY_Z1))).removeSplitter())
    # ---- faldón del cuello (antes colgaba de la bandeja): pared de la base que sube hasta la bandeja
    sx0, sx1 = RE["NECK_SKIRT_X"]; sy_ = RE["NECK_SKIRT_Y"]
    F("BANDEJA_FALDON_CUELLO", box((sx0, -sy_, ZF - 0.1), (sx1, sy_, TRAY_Z0)))
    # ---- postes de la bandeja (con pasador de centrado)
    for i_, (px, py) in enumerate(RE["TRAY_POSTS"]):
        F("BANDEJA_POSTE_%d" % (i_ + 1), vcyl(px, py, RE["POST_R"], ZF - 0.1, TRAY_Z0).fuse(vcyl(px, py, RE["PIN_R"], TRAY_Z0 - 0.1, TRAY_Z0 + RE["PIN_H"])))
    # ---- topes de la L: paredes laterales ajustadas al cuerpo (0,1), tope final y calzo bajo el cuerpo
    sc, st = RE["STOP_CLR"], RE["STOP_T"]; zp = ZF
    for sg in (-1, 1):
        F("L_TOPE_LATERAL_%s" % ("Ymenos" if sg < 0 else "Ymas"),
          box((OX - LB, sg * (LB + sc), zp - 0.1), (OX + LB + sc + st, sg * (LB + sc + st), STOP_TOP)))
    F("L_TOPE_FINAL", box((OX + LB + sc, -(LB + sc + st), zp - 0.1), (OX + LB + sc + st, LB + sc + st, STOP_TOP)))
    F("L_CALZO", box((OX - LB, -LB + 0.3, zp - 0.1), (OX + LB, LB - 0.3, L_BOT - sc)))
    # ---- cuna del reed en el cuello (eje Y; 2 paredes laterales, patas libres por los extremos)
    rx, ry = RE["REED_C"]; rl, rd_ = RE["REED"]
    for sg in (-1, 1):
        if REED_TOP > ZF: F("REED_CUNA_%d" % (1 if sg < 0 else 2), box((rx + sg * (rd_ / 2 + RE["REED_CLR_W"]), ry - rl / 2 + 1.5, ZF - 0.1), (rx + sg * (rd_ / 2 + RE["REED_CLR_W"] + 1.2), ry + rl / 2 - 1.5, REED_TOP)))
    # rebaje del suelo alrededor de cada clic: la viga nace en CLIP_ROOT_Z (brazo largo, no se rompe al encajar)
    for (cx, sg, cw) in RE["CLIPS"]:
        yi = RE["TRAY_HALF_W"] + RE["STOP_WALL_CLR"] + RE["CLIP_GAP"]
        fl = fl.cut(box((cx - cw / 2 - RE["CLIP_SLOT"], sg * (BY + FT + 0.05), RE["CLIP_ROOT_Z"]), (cx + cw / 2 + RE["CLIP_SLOT"], sg * (yi + RE["CLIP_T"] + RE["CLIP_SLOT"]), ZF + 0.01)))
    keep = column_keep(0.3)
    zk = Part.makeCompound([vcyl(hx, hy, 4.3, -5, 60) for (hx, hy) in ZED_PTS] +
                           [vcyl(mx, my, (RE["MAG"][0] + RE["MAG_CLR"]) / 2 + 0.4, -5, 60) for (mx, my) in RE["MAGS"]])   # ni separadores ZED ni imanes bajo ninguna pared
    feats = [f.cut(keep) if nm.startswith("ZED_SEPARADOR") else f.cut(keep).cut(zk) for f, nm in zip(feats, FN)]   # nada pisa los separadores de la ZED
    feat = fuse_all(feats)
    clip = CLIP_CAV.common(prism(-(g("RIM_W") + 0.3), -10, 60).fuse(box((-20, -50, ZF + g("RIM_H")), (L + 20, 50, 60))))
    feat = feat.common(clip)
    for nm_, f_ in zip(FN, feats): kreg("base", nm_, f_.common(clip), "union")
    fl = fl.fuse(feat).removeSplitter()
    def C(nm_, t_):
        kreg("base", nm_, t_, "corte"); return fl.cut(t_)
    # ---- alojamientos en el suelo
    fl = C("CORTE_BATERIA_ALOJAMIENTO", box((BX0, -BY, BZ0), (BX1, BY, ZF + 1)))
    # Rev E.6: sin bobina Qi ni su canal (la batería apoya en el suelo, 1,4 mm)
    cw_ = RE["REED_CLR_W"]; lx_, ly_ = RE["REED_LEG"]; yl = rl / 2 + RE["REED_CLR_L"]
    fl = C("CORTE_REED_L%.1f" % (2 * yl), box((rx - rd_ / 2 - cw_, ry - yl, RE["REED_Z0"]), (rx + rd_ / 2 + cw_, ry + yl, ZF + 1)))
    for sg in (-1, 1):
        fl = C("CORTE_REED_HUECO_PATA_%d" % (1 if sg < 0 else 2), box((rx - lx_ / 2, ry + sg * yl, RE["REED_Z0"]), (rx + lx_ / 2, ry + sg * (yl + ly_), ZF + 1)))
    # ---- Rev E.6: contactos del fondo. Avellanado 90° desde fuera, paso Ø2,3, ranura de la junta tórica en la cara Z 2,5 y
    #      alojamiento Ø6,8 de Z 2,5 hasta el suelo (terminal de ojal + tuerca M2; el cable sube a la Heltec)
    gi, go, gd = RE["CONTACT_GROOVE"]; ck = RE["CONTACT_CSK_D"] / 2; hr_ = RE["CONTACT_HOLE"] / 2; cz = RE["CONTACT_Z"]
    for (cx_, cy_), nm_c in RE["CONTACTS"]:
        t_ = fuse_all([Part.makeCone(ck + 0.5, hr_, ck + 0.5 - hr_, V(cx_, cy_, -0.5)), vcyl(cx_, cy_, hr_, -1, cz + 0.1),
                       vcyl(cx_, cy_, go / 2, cz - gd, cz + 0.1), vcyl(cx_, cy_, RE["CONTACT_POCKET_R"], cz, ZF + 1)]).removeSplitter()
        fl = C("CORTE_CONTACTO_%s_M2_AVELLANADO_JUNTA_Y_TUERCA" % nm_c, t_)
    md, mt_ = RE["MAG"]
    for i_, (mx, my) in enumerate(RE["MAGS"]):
        fl = C("CORTE_IMAN_%d_D%.2f" % (i_ + 1, md + RE["MAG_CLR"]), vcyl(mx, my, (md + RE["MAG_CLR"]) / 2, RE["MAG_SKIN"], ZF + 1))
    xa, xb, hw2, zb_ = P["J2_POCKET"]
    if ZP < ZF: fl = C("CORTE_REBAJE_TUERCA_L", box((L_NUT - 1.0, SMA_Y - RE["L_NUT_ENV_R"] - 0.3, ZP), (OX - LB, SMA_Y + RE["L_NUT_ENV_R"] + 0.3, ZF + 1)))   # solo bajo la tuerca, 0,3 de holgura
    # ---- tornillos (como la cincha REV 5.5): alojamiento Ø5,9 × 3,7 desde abajo para cabeza cilíndrica + junta tórica 3 × 1,
    #      Rev E.4.1: agujero pasante; sobre el alojamiento 2 capas de puente en escalón (ranura y cuadrado de 3,4) y paso Ø3,4 hasta la cara de unión
    ins = P["INS"]; cbd, cbh, sac = RE["SCREW_CB"]
    for i_, (sx, sy) in enumerate(SCREWS):
        bz = RE["SCREW_BRIDGE"]; hr = 3.4 / 2
        cb_ = vcyl(sx, sy, cbd / 2, -1, cbh)
        slot = box((sx - cbd / 2 - 0.1, sy - hr, cbh - 0.01), (sx + cbd / 2 + 0.1, sy + hr, cbh + bz)).common(vcyl(sx, sy, cbd / 2, cbh - 0.02, cbh + bz + 0.01))   # capa 1: ranura (puentes en X)
        sq = box((sx - hr, sy - hr, cbh + bz - 0.01), (sx + hr, sy + hr, cbh + 2 * bz))                                                                       # capa 2: cuadrado (puentes en Y)
        t_ = fuse_all([cb_, slot, sq, vcyl(sx, sy, hr, cbh + 2 * bz - 0.01, ZF + 1)]).removeSplitter()                                                         # paso Ø3,4 pasante
        fl = C("CORTE_TORNILLO_S%d_CABEZA_Y_JUNTA_TORICA_D5.9x3.7_PASANTE" % (i_ + 1), t_)
    # ---- ranuras exteriores del cierre al soporte (en la base): techo a 45° para imprimir sin soporte
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
    for i_, (hx, hy) in enumerate(ZED_PTS):
        fl = C("CORTE_INSERTO_M3_ZED_%d_D4.0_P5.5" % (i_ + 1), vcyl(hx, hy, idd / 2, ZB - idp - 0.5, ZB + 1))
    for i_, (px, py) in enumerate(RE["TRAY_POSTS"]): pass
    return fl.removeSplitter()
REED_TOP = RE["REED_Z0"] + RE["REED"][1] + 0.2

# ============================================================ CUNA DE LA HELTEC (bandeja sobre la batería)
def build_bandeja(CLIP_CAV):
    """Rev E.6: cuna de la Heltec para el prototipo con contactos pogo (sin Qi ni reed)."""
    x0, y0, x1, y1 = MCU["x0"], MCU["y0"], MCU_X1, MCU_Y1; g_ = 0.15
    # la bandeja baja 1,0: en el cuello empieza en X 3,5 (en X 3,0–3,4 la pared interior de la tapa E.5 baja hasta Z 8,6)
    t = box((RE["TRAY_NECK_X"] + 0.5, -RE["TRAY_HALF_W"], TRAY_Z0), (BX1 + FT, RE["TRAY_HALF_W"], TRAY_Z1))
    # un solo pasacables centrado (cables de los contactos del fondo)
    cx0, cx1, cy0, cy1 = RE["CABLE_SLOT"]
    t = t.cut(box((cx0, cy0, TRAY_Z0 - 1), (cx1, cy1, TRAY_Z1 + 5)))
    # ventana bajo la Heltec: componentes inferiores (X 10,3–17,6) y conector SH1.25 que cuelga (X 9,2–12,9); el tramo X 8,75–10,15
    # queda macizo a los lados del conector para los calzos del extremo USB
    t = t.cut(box((x0 + 1.6, y0 + 0.5, TRAY_Z0 - 1), (x0 + RE["SOT_ZONE"][1] + 0.4, y1 - 0.5, TRAY_Z1 + 1)))
    t = t.cut(box((x0 + 0.4, 2.85, TRAY_Z0 - 1), (x0 + 4.5, 11.35, TRAY_Z1 + 1)))
    for (px, py) in RE["TRAY_POSTS"]: t = t.cut(vcyl(px, py, RE["PIN_R"] + 0.15, TRAY_Z0 - 1, TRAY_Z1 + 1))
    feats = [t]
    zs = TRAY_Z1 - 0.1; sh_ = MCU_Z                       # calzos: de la bandeja a la cara inferior de la Heltec
    # calzos 1,0 (a los dos lados del conector en el extremo USB; extremo de la antena; bajo los apoyos de la tapa)
    for (a_, b_, c_, d_) in ((x0 + 0.15, y0 + 0.2, x0 + 1.55, 2.65), (x0 + 0.15, 11.55, x0 + 1.55, y1 - 0.2),
                             (x1 - 5.8, y0 + 0.3, x1 - 0.3, y1 - 0.3),
                             (28.0, y0 + 0.2, 30.0, y0 + 1.8), (28.0, y1 - 1.8, 30.0, y1 - 0.2),
                             (46.0, y0 + 0.2, 48.0, y0 + 1.8), (46.0, y1 - 1.8, 48.0, y1 - 0.2)):
        feats.append(box((a_, b_, zs), (c_, d_, sh_)))
    xw0 = x0 + RE["MCU_WALL_X0"]
    c0 = 0.6 / math.sqrt(0.5); z0 = MCU_T + 0.05
    def lip_cut(xa, xb, ya, yb, edge, sgn, axis):
        """recorte a 45° bajo el labio de una pestaña (se imprime sin soportes); edge = cara del canto de la Heltec"""
        if axis == "x":
            hs = Part.makePolygon([V(edge - sgn * 5, ya - 1, z0 + c0 - 5), V(edge + sgn * 10, ya - 1, z0 + c0 + 10), V(edge + sgn * 10, ya - 1, -10),
                                   V(edge - sgn * 5, ya - 1, -10), V(edge - sgn * 5, ya - 1, z0 + c0 - 5)])
            return Part.Face(hs).extrude(V(0, yb - ya + 2, 0))
        hs = Part.makePolygon([V(xa - 1, edge - sgn * 5, z0 + c0 - 5), V(xa - 1, edge + sgn * 10, z0 + c0 + 10), V(xa - 1, edge + sgn * 10, -10),
                               V(xa - 1, edge - sgn * 5, -10), V(xa - 1, edge - sgn * 5, z0 + c0 - 5)])
        return Part.Face(hs).extrude(V(xb - xa + 2, 0, 0))
    # guías laterales existentes, ahora con labio (pestañas en los dos bordes)
    for sg, yy in ((1, y0), (-1, y1)):
        yo, yi = yy - sg * (g_ + 1.2), yy - sg * g_
        for (xa, xb, top) in ((xw0, xw0 + 3.0, MCU_T + 1.8), (x1 - 6.0, x1 + g_, MCU_T + 1.8)):
            gd = box((xa, min(yo, yi), zs), (xb, max(yo, yi), top))
            lip = box((xa, min(yi, yy + sg * 0.5), z0), (xb, max(yi, yy + sg * 0.5), top)).common(lip_cut(xa, xb, 0, 0, yi, -sg, "y"))
            feats.append(gd.fuse(lip))
    # pestañas nuevas en el borde +Y (en el −Y va el canal de los cables)
    hl, ht, ho = RE["EDGE_HOOK"]
    for xc in RE["EDGE_HOOKS_X"]:
        xa, xb = xc - hl / 2, xc + hl / 2; yi = y1 + g_
        beam = box((xa, yi, zs), (xb, yi + ht, MCU_T + 1.8))
        lip = box((xa, y1 - ho, z0), (xb, yi, MCU_T + 1.8)).common(lip_cut(xa, xb, 0, 0, yi, 1, "y"))
        feats.append(beam.fuse(lip))
    # torres con pestaña en los DOS extremos (antena: las de siempre, 1,0 más altas; USB: iguales, entre el USB-C y los pulsadores)
    lx = x1 + g_
    for (ya, yb) in ((y0 + RE["HOOK_Y"][0], y0 + RE["HOOK_Y"][1]), (y1 - RE["HOOK_Y"][1], y1 - RE["HOOK_Y"][0])):
        beam = box((lx, ya, zs), (lx + 1.4, yb, MCU_T + 1.8))
        hook = box((lx - 0.9, ya, z0), (lx + 0.1, yb, MCU_T + 1.8))
        feats.append(beam.fuse(hook.common(lip_cut(0, 0, ya, yb, lx, 1, "x"))))
    ux = x0 - g_                                           # USB: viga de 1,1 (la clavija del cable llega hasta X 7,3)
    for (ya, yb) in ((-0.9, 2.3), (11.9, 15.1)):
        beam = box((ux - 1.1, ya, zs), (ux, yb, MCU_T + 1.8))
        hook = box((ux - 0.1, ya, z0), (ux + 0.9, yb, MCU_T + 1.8))
        feats.append(beam.fuse(hook.common(lip_cut(0, 0, ya, yb, ux, -1, "x"))))
    b = fuse_all(feats)
    # ---- refuerzo (2,2) fuera de la Heltec; alojamiento del Pololu S7V8F3 a 1,0 del borde −Y del refuerzo
    rb = box((x0 - 0.15, -RE["TRAY_HALF_W"] + RE["TRAY_EDGE"], TRAY_Z1 - 0.05), (BX1 + FT, RE["TRAY_HALF_W"] - RE["TRAY_EDGE"], TRAY_Z1 + RE["TRAY_RIB"]))
    rb = rb.cut(box((x0 - 0.6, y0 - 1.6, 0), (x1 + 2.0, y1 + 1.6, 30)))                                  # Heltec + pulsadores + pestañas
    pl, pw = RE["POLOLU"]; pc = RE["POLOLU_CLR"]; py0 = -RE["TRAY_HALF_W"] + RE["TRAY_EDGE"] + RE["POLOLU_WALL"]
    POL = (RE["POLOLU_X"] - pl / 2 - pc, py0, RE["POLOLU_X"] + pl / 2 + pc, py0 + pw + 2 * pc)
    rb = rb.cut(box((POL[0], POL[1], 0), (POL[2], POL[3], 30)))
    b = b.fuse(rb).removeSplitter()
    # sujetacables: labio a 45° en el canto del refuerzo junto a la Heltec (canal de los cables entre el refuerzo y la Heltec)
    ll, lo = RE["CABLE_LIP"]; ye = y0 - 1.6; zt = TRAY_Z1 + RE["TRAY_RIB"]
    for xc in RE["CABLE_LIPS_X"]:
        zb_ = TRAY_Z1 + 1.3; zh = zb_ + lo + 0.8          # canal libre de 1,3 junto al refuerzo (5 × AWG30 en 2 capas); labio 45° hacia la Heltec
        pr = Part.Face(Part.makePolygon([V(xc - ll / 2, ye - 0.3, zb_), V(xc - ll / 2, ye, zb_), V(xc - ll / 2, ye + lo, zb_ + lo),
                                         V(xc - ll / 2, ye + lo, zh), V(xc - ll / 2, ye - 0.3, zh), V(xc - ll / 2, ye - 0.3, zb_)])).extrude(V(ll, 0, 0))
        pr = pr.fuse(box((xc - ll / 2, ye - 0.8, zt - 0.1), (xc + ll / 2, ye, zh)))          # apoyo del labio sobre el refuerzo (lejos de las láminas del botón USER de la tapa)
        b = b.fuse(pr)
    b = b.removeSplitter()
    for (px, py) in RE["TRAY_POSTS"]: b = b.cut(vcyl(px, py, RE["PIN_R"] + 0.15, TRAY_Z0 - 1, TRAY_Z1 + 5))
    hx0, hx1, hy0, hy1 = RE["TRAY_CABLE_HOLE"]
    b = b.cut(box((hx0, hy0, TRAY_Z0 - 1), (hx1, hy1, TRAY_Z1 + 5)))                                         # paso de cables de la batería
    b = b.cut(column_keep(0.3)).common(CLIP_CAV)
    for (hx, hy) in ZED_PTS: b = b.cut(vcyl(hx, hy, 4.3, -5, 40))      # libre de los separadores de la ZED (más altos en Rev E.2)
    RE["POLOLU_ALOJ"] = [round(v, 3) for v in POL]
    return b.removeSplitter()

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
    # Rev E.6: pines con muelle bajo SYS y BAT (Ø2,05 pasante, pegados) y canal del hilo del puente por debajo
    on = [c for c in RE["CONTACTS"] if c[1] in RE["POGO_ON"]]
    cw_, ch_ = RE["POGO_CH"]
    for (cx_, cy_), nm_c in on:
        p = p.cut(vcyl(cx_, cy_, RE["POGO_D"] / 2, -MT - 1, 1))
        p = p.cut(vcyl(cx_, cy_, 1.6, -MT - 1, -MT + ch_))
    if len(on) == 2 and "SYS" in RE["POGO_ON"]:            # canal del puente SYS–BAT (solo en el soporte del chaleco)
        (ax_, ay_), (bx_, by_) = on[0][0], on[1][0]
        p = p.cut(box((ax_ - cw_ / 2, min(ay_, by_), -MT - 1), (ax_ + cw_ / 2, max(ay_, by_), -MT + ch_)))
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

# ============================================================ PROBETAS (trozos reales de la base y la tapa para probar antes de imprimir todo)
def probetas(parts):
    pr = {}
    # P1: zona de la L (topes, torre, junta tórica, asiento de la antena) + columnas S8/S9
    bx = box((ZED_X1 - 1.0, -40, -6), (L + 5.0, 40, 60))          # Rev E.3: hasta el final (no corta el alojamiento del tornillo S12)
    pr["P1_L_ANTENA_BASE"] = parts["base"].common(bx)
    pr["P1_L_ANTENA_TAPA"] = parts["tapa"].common(bx)
    pr["P1_L_ANTENA_SOPORTE"] = parts["soporte"].common(box((ZED_X1 - 1.0, -40, -6), (L + 10.0, 40, 60)))   # gancho del extremo
    # P2: cuello: columnas S1/S2 con avellanado + junta tórica, postes y extremo USB de la bandeja, ranura del labio
    bx = box((-5, -40, -6), (26.0, 40, 60))
    pr["P2_CUELLO_BASE"] = parts["base"].common(bx)
    pr["P2_CUELLO_TAPA"] = parts["tapa"].common(bx)
    pr["P2_CUELLO_SOPORTE"] = parts["soporte"].common(bx)
    return {k: v.removeSplitter() for k, v in pr.items()}

# ============================================================ informe
def report(s):
    ob = s.optimalBoundingBox()
    info = dict(valido=bool(s.isValid()), solidos=len(s.Solids), cascaras_cerradas=all(x.isClosed() for x in s.Shells), caras=len(s.Faces),
                volumen_mm3=round(mesh_volume(s), 1), bbox=[round(v, 3) for v in (ob.XMin, ob.XMax, ob.YMin, ob.YMax, ob.ZMin, ob.ZMax)])
    return info
NOMBRES = dict(tapa="AVO_RevE_TAPA", base="AVO_RevE6_BASE_POGO", cuna_heltec="AVO_RevE6_CUNA_HELTEC", junta_TPU="AVO_RevE_JUNTA_TPU",
               soporte="AVO_RevE6_BASE_CARGA_POGO" if os.environ.get("AVO_E6_CARGA") else "AVO_RevE6_SOPORTE_POGO",
               contraplaca="AVO_RevE_CONTRAPLACA")
if __name__ == "__main__" or "AVO_RUN" in os.environ:
    import time, shutil
    T0 = time.time(); RES = {}
    log("RE:", json.dumps(RE, ensure_ascii=False))
    OUTER, CAV, CLIP_CAV = build_common(); log("cascos", round(time.time() - T0, 1), "s")
    parts = {}
    parts["tapa"] = build_tapa(OUTER, CAV); log("tapa", round(time.time() - T0, 1), "s")
    parts["base"] = build_base(OUTER, CAV, CLIP_CAV); log("base", round(time.time() - T0, 1), "s")
    parts["cuna_heltec"] = build_bandeja(CLIP_CAV)
    parts["junta_TPU"] = build_junta()
    parts["soporte"] = build_soporte(); log("soporte", round(time.time() - T0, 1), "s")
    parts["contraplaca"] = build_contraplaca(); log("contraplaca", round(time.time() - T0, 1), "s")
    # Rev E.6: sin reed → sin tope del reed
    for d in ("STEP", "BREP", "PROBETAS"): os.makedirs(os.path.join(OUT, d), exist_ok=True)
    for k, s in parts.items():
        RES[k] = report(s); log(k, RES[k])
        s.exportStep(os.path.join(OUT, "STEP", NOMBRES[k] + ".step"))
        s.exportBrep(os.path.join(OUT, "BREP", NOMBRES[k] + ".brep"))
    Part.makeCompound([parts[k] for k in NOMBRES]).exportStep(os.path.join(OUT, "STEP", "AVO_RevE_CONJUNTO_MONTADO.step"))
    for k, s in (("OUTER", OUTER), ("CAV", CAV)): s.exportBrep(os.path.join(OUT, "BREP", "_aux_%s.brep" % k))
    PR = probetas(parts)
    for k, s in PR.items():
        RES["probeta_" + k] = report(s); s.exportBrep(os.path.join(OUT, "PROBETAS", "AVO_RevE_" + k + ".brep"))
    for part, items in KIT.items():
        d_ = os.path.join(OUT, "KIT", part); shutil.rmtree(d_, ignore_errors=True); os.makedirs(d_)
        for i_, (nm_, sh_, role_) in enumerate(items): sh_.exportBrep(os.path.join(d_, "%03d__%s__%s.brep" % (i_, role_, nm_)))
    log("kit de edición:", {k: len(v) for k, v in KIT.items()})
    json.dump(dict(piezas=RES, RE=RE, logotipo=LOGO_INFO, fallos_redondeo=FALLOS, tiempo_s=round(time.time() - T0, 1)),
              open(os.path.join(OUT, "informe_modelo_revE.json"), "w"), indent=1, ensure_ascii=False)
    log("FIN", round(time.time() - T0, 1), "s · fallos:", FALLOS)
