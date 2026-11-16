"""AVO DOCK V1 · soporte de pared cargador (2 cascos BACK V5 + 2 cinchas REV 5.9.1) — generador del proyecto KiCad 9.

Un solo origen de datos (piezas, redes, posiciones) genera el esquema, la placa, las reglas, la lista de piezas para
JLCPCB y las comprobaciones de colocación. Derivado del generador de la BACK V5 CASCO (avo_back_v5_pcb.py).

Decisiones del usuario (15/11/2026):
  - cinchas: pogo magnético de 3 contactos de la REV 5.9.1 (1 = +5 V · 2 = GND · 3 = MTCK, GPIO6 de la cápsula);
  - cascos: pogo de 5 contactos de la BACK V5 (VBUS · D− · D+ · GND · AUX) con hub USB + ESP32-S3 en el soporte;
  - 220 V con módulo AC-DC certificado encapsulado (Mean Well IRM-20-5, 5 V 4 A, clase II) + USB-C de 5 V.

Placa de 130 × 76 mm, 4 capas, 1,6 mm. Todos los componentes en F.
  - F.Cu y B.Cu = señales (con relleno GND tras el ruteado); In1 = plano GND; In2 = plano +3V3 (vías desde cada pad).
  - ZONA DE RED (220 V): esquina −X/+Y, rodeada por un FOSO de 6,5 mm sin cobre en ninguna capa (distancia de fuga
    reforzada entre red y MBTS ≥ 6,4 mm, EN 62368-1, 250 V, grado de contaminación 2, CTI ≥ 175). Las pistas de red
    se trazan aquí (MAINS_TRACKS), a 1,0 mm, solo en F.Cu; ningún plano entra en la zona de red ni en el foso.
Coordenadas de diseño: origen en el centro de la placa, X a la derecha e Y hacia arriba, VISTA DESDE LA CARA F.
En KiCad: x = 100 + X, y = 100 − Y.

Bloques: red 220 V (fusible T1 A, varistor, IRM-20-5) · USB-C del PC (CC, PTC, ESD) · selector de alimentación con
prioridad a la red (PMOS ideales, sin retroalimentar el USB del PC ni el módulo) · 3,3 V (AMS1117) · ESP32-S3-MINI-1U
(BLE + Wi-Fi + USB OTG) · hub USB2514B · 2 conmutadores USB TS3USB221 (modo PC / modo autónomo) · 4 interruptores de
potencia con límite TPS2553 + 4 medidores de corriente INA180 · 2 puertos de casco (USB + carga + AUX) · 2 puertos de
cincha (carga + línea de datos de 1 hilo por MTCK) · pantalla ST7789 de 2" por cable JST-GH de 8 · pulsador frontal.
Uso:  python avo_dock_v1_pcb.py --place   (comprueba la colocación)
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from custom_fp import test_pad, wire_pad   # noqa: E402
from fplib import Footprint, Pad, circle, load, rect_lines   # noqa: E402

OUT = os.path.join(HERE, "..", "kicad")
os.makedirs(OUT, exist_ok=True)
NAME = "AVO_DOCK_V1_PCB"
TITLE = "AVO DOCK V1 · soporte de pared cargador"
REV, DATE = "A", "2026-11-15"
THICK = 1.6
W, H, CORNER_R = 130.0, 76.0, 3.0
HOLE_D, HOLE_KEEP = 3.2, 3.6                           # taladros M3 (tornillo de nailon a los pilares de la caja)
Z_MAX_F = 30.0                                        # hueco sobre la cara F dentro de la caja (el IRM-20 mide 24)

# zona de red y foso (coordenadas de diseño)
MAINS_RECT = (-65.0, -12.0, -46.0, 38.0)              # x0, y0, x1, y1
MOAT = 6.5
MOAT_POLY = [(-65.0, -12.0), (-46.0, -12.0), (-46.0, 38.0), (-46.0 + MOAT, 38.0), (-46.0 + MOAT, -12.0 - MOAT),
             (-65.0, -12.0 - MOAT)]
MAINS_POLY = [(-65.0, -12.0), (-46.0, -12.0), (-46.0, 38.0), (-65.0, 38.0)]


def K(X, Y):
    return (round(100 + X, 4), round(100 - Y, 4))


# =============================================================================== contorno (rectángulo con R3)
def arc_center(a, m, b):
    ax, ay = a; bx, by = m; cx, cy = b
    d = 2 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))
    ux = ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) + (cx * cx + cy * cy) * (ay - by)) / d
    uy = ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) + (cx * cx + cy * cy) * (bx - ax)) / d
    return ux, uy


def sample_arc(a, m, b, step_deg=5):
    c = arc_center(a, m, b)
    r = math.hypot(a[0] - c[0], a[1] - c[1])
    t0 = math.atan2(a[1] - c[1], a[0] - c[0]); tm = math.atan2(m[1] - c[1], m[0] - c[0])
    t1 = math.atan2(b[1] - c[1], b[0] - c[0])

    def norm(t):
        return (t - t0) % (2 * math.pi)
    ccw = norm(tm) < norm(t1)
    span = norm(t1) if ccw else -((t0 - t1) % (2 * math.pi))
    n = max(2, int(abs(math.degrees(span)) / step_deg))
    return [(c[0] + r * math.cos(t0 + span * k / n), c[1] + r * math.sin(t0 + span * k / n)) for k in range(n + 1)]


def outline_prims():
    hx, hy, r = W / 2, H / 2, CORNER_R
    s = math.sqrt(0.5) * r
    P = []
    corners = [((hx, -hy + r), (hx, hy - r)), ((hx - r, hy), (-hx + r, hy)), ((-hx, hy - r), (-hx, -hy + r)),
               ((-hx + r, -hy), (hx - r, -hy))]
    centers = [(hx - r, hy - r), (-hx + r, hy - r), (-hx + r, -hy + r), (hx - r, -hy + r)]
    mids = [(s, s), (-s, s), (-s, -s), (s, -s)]
    for k in range(4):
        a, b = corners[k]
        P.append(("line", a, b))
        c = centers[k]; m = (c[0] + mids[k][0], c[1] + mids[k][1])
        nxt = corners[(k + 1) % 4][0]
        P.append(("arc", b, m, nxt))
    return P


def slot_prims():
    return []


def prims_pts(prims, step_deg=5):
    pts = []
    for p in prims:
        seg = [p[1], p[2]] if p[0] == "line" else sample_arc(p[1], p[2], p[3], step_deg)
        pts += seg[:-1]
    return pts


def outline_pts(step_deg=5):
    return prims_pts(outline_prims(), step_deg)


# =============================================================================== huellas
M3 = "${KICAD9_3DMODEL_DIR}/"


def npth_hole(d, keep, label):
    pads = [Pad("", "np_thru_hole", "circle", 0, 0, d, d, drill=d, layers=["*.Cu", "*.Mask"])]
    g = [circle(0, 0, keep, "F.CrtYd", 0.05), circle(0, 0, d / 2 + 0.2, "F.SilkS", 0.12)]
    return Footprint("AVO_Taladro_NPTH_D%.1f" % d, pads, g, "smd board_only exclude_from_pos_files exclude_from_bom", None,
                     label, 0.0)


S3 = load("ESP32-S3-MINI-1U.kicad_mod", "${KIPRJMOD}/../fuente/3d/ESP32-S3-MINI-1U.STEP", 2.6)
S3.graphics = [g for g in S3.graphics if not (len(g) > 1 and any(isinstance(x, list) and x[0] == "layer" and "CrtYd" in str(x[1]) for x in g))]
S3.graphics += rect_lines(-7.85, -7.85, 7.85, 7.85, "F.CrtYd", 0.05)
FP = {
    "R0402": load("R_0402_1005Metric.kicad_mod", M3 + "Resistor_SMD.3dshapes/R_0402_1005Metric.step", 0.4),
    "R0805": load("R_0805_2012Metric.kicad_mod", M3 + "Resistor_SMD.3dshapes/R_0805_2012Metric.step", 0.6),
    "R1206": load("C_1206_3216Metric.kicad_mod", M3 + "Resistor_SMD.3dshapes/R_1206_3216Metric.step", 0.6),
    "C0402": load("C_0402_1005Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0402_1005Metric.step", 0.6),
    "C0603": load("C_0603_1608Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0603_1608Metric.step", 0.9),
    "C0805": load("C_0805_2012Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0805_2012Metric.step", 1.35),
    "CTANT": load("CP_EIA-3528-21_Kemet-B.kicad_mod", M3 + "Capacitor_Tantalum_SMD.3dshapes/CP_EIA-3528-21_Kemet-B.step", 2.1),
    "F1206": load("Fuse_1206_3216Metric.kicad_mod", M3 + "Fuse.3dshapes/Fuse_1206_3216Metric.step", 1.1),
    "SOT23": load("SOT-23.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23.step", 1.1),
    "SOT23-5": load("SOT-23-5.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23-5.step", 1.45),
    "SOT23-6": load("SOT-23-6.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23-6.step", 1.45),
    "SOT223": load("SOT-223.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-223.step", 1.8),
    "SOD323": load("D_SOD-323.kicad_mod", M3 + "Diode_SMD.3dshapes/D_SOD-323.step", 1.1),
    "QFN36": load("QFN-36-1EP_6x6mm_P0.5mm_EP3.7x3.7mm_ThermalVias.kicad_mod",
                  M3 + "Package_DFN_QFN.3dshapes/QFN-36-1EP_6x6mm_P0.5mm_EP3.7x3.7mm.step", 1.0),
    "DFN10": load("DFN-10-1EP_3x3mm_P0.5mm_EP1.65x2.38mm.kicad_mod",
                  M3 + "Package_DFN_QFN.3dshapes/DFN-10-1EP_3x3mm_P0.5mm_EP1.65x2.38mm.step", 1.0),
    "XTAL": load("Crystal_SMD_3225-4Pin_3.2x2.5mm.kicad_mod",
                 M3 + "Crystal.3dshapes/Crystal_SMD_3225-4Pin_3.2x2.5mm.step", 0.8),
    "USBC": load("USB_C_Receptacle_HRO_TYPE-C-31-M-12.kicad_mod",
                 M3 + "Connector_USB.3dshapes/USB_C_Receptacle_HRO_TYPE-C-31-M-12.step", 3.3),
    "GH8": load("JST_GH_SM08B-GHS-TB_1x08-1MP_P1.25mm_Horizontal.kicad_mod",
                M3 + "Connector_JST.3dshapes/JST_GH_SM08B-GHS-TB_1x08-1MP_P1.25mm_Horizontal.step", 4.25),
    "IRM20": load("Converter_ACDC_MeanWell_IRM-20-xx_THT.kicad_mod",
                  M3 + "Converter_ACDC.3dshapes/Converter_ACDC_MeanWell_IRM-20-xx_THT.step", 24.0),
    "FUSE372": load("Fuse_Littelfuse_372_D8.50mm.kicad_mod", M3 + "Fuse.3dshapes/Fuse_Littelfuse_372_D8.50mm.step", 8.0),
    "MOV7": load("RV_Disc_D7mm_W4.8mm_P5mm.kicad_mod", M3 + "Varistor.3dshapes/RV_Disc_D7mm_W4.8mm_P5mm.step", 10.0),
    "MINI1U": S3,
    "TP": test_pad(1.0),
    "WIRE": wire_pad("(hilo)", drill=0.9, d=1.7),
    "WIREAC": wire_pad("(hilo de red)", drill=1.3, d=2.6),
    "HOLE": npth_hole(HOLE_D, HOLE_KEEP, "Taladro del tornillo M3 de la caja"),
}
for k in ("QFN36",):
    for p in FP[k].pads:
        if p.kind == "thru_hole":
            p.drill, p.w, p.h = 0.3, 0.5, 0.5

# =============================================================================== piezas y redes
PARTS = []


def part(ref, fp, value, pos, rot, nets, lcsc="", mpn="", block="", sym=None, dnp=False, note="", jlc_rot=0,
         no_assembly=False):
    PARTS.append(dict(ref=ref, fp=fp, value=value, pos=pos, rot=rot, nets={str(k): v for k, v in nets.items()},
                      lcsc=lcsc, mpn=mpn, block=block, sym=sym, dnp=dnp, note=note, jlc_rot=jlc_rot,
                      no_assembly=no_assembly))


# Códigos LCSC: los de la V5 (consultados en el CI 14/11/2026) más USB2514B-I/M2 C220679 y HRO TYPE-C-31-M-12 C165948.
# Los que quedan vacíos se buscan con el workflow de existencias antes de pedir (ver DOCS/ARQUITECTURA.md).
LC = {
    "0R": "C17168", "22R": "C25092", "1k": "C11702", "10k": "C25744", "100k": "C25741", "47k": "C25792",
    "5k1": "C25905", "12k": "C25752", "68k": "C36871", "24k9": "", "49k9": "",
    "100n": "C1525", "1u": "C52923", "10n": "C15195", "4u7": "C19666", "18p": "C1549",
    "10u": "C96446", "22u": "C45783", "47u": "C16780",
    "AO3401A": "C15127", "2N7002": "C8545", "USBLC6": "C7519", "AMS1117": "C6186", "MINI1U": "C2980299",
    "PTC": "C20802", "TVS": "C2827694", "USB2514B": "C220679", "TYPEC": "C165948",
    "TPS2553": "", "INA180A2": "", "TS3USB221": "", "XTAL24": "", "GH8": "", "R50m": "",
}


def R(ref, val, n1, n2, pos=(0, 0), rot=0, block="", dnp=False, fp="R0402", note="", lcsc=None):
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, lcsc if lcsc is not None else LC.get(val, ""), block=block,
         sym="R", dnp=dnp, note=note)


def C(ref, val, n1, n2, pos=(0, 0), rot=0, block="", fp="C0402", dnp=False, lcsc=None, note=""):
    key = val.split()[0]
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, lcsc if lcsc is not None else LC.get(key, ""),
         block=block, sym="C", dnp=dnp, note=note)


def TVS(ref, net, block, note=""):
    part(ref, "SOD323", "TVS 5 V", (0, 0), 0, {1: net, 2: GND}, LC["TVS"], "PESD5V0S1BA", block,
         sym=dict(L=[(1, "K")], R=[(2, "A")]), note=note or "ESD en un contacto expuesto")


GND, V3, V5 = "GND", "+3V3", "+5V_SYS"
# nombres que usa build.py (heredado de la V5)
VSYS, VBUS, VBAT, VZED, VSD, VIN5 = V5, "VBUS_PC", "-", "-", "-", "-"
V5AC = "+5V_RED"
TP = lambda ref, label, net, note="": part(ref, "TP", label, (0, 0), 0, {1: net}, block="Pruebas", sym="TP",
                                           no_assembly=True, note=note)

# ---------------------------------------------------------------------------------------- red 220 V (zona aislada)
part("J1", "WIREAC", "RED L", (0, 0), 0, {1: "AC_L_IN"}, block="Red", sym="TP", no_assembly=True,
     note="fase desde la base IEC C8 (hilo 0,75 mm², doble aislamiento): soldado y con brida")
part("J2", "WIREAC", "RED N", (0, 0), 0, {1: "AC_N"}, block="Red", sym="TP", no_assembly=True,
     note="neutro desde la base IEC C8 (sin tierra: equipo de clase II)")
part("F1", "FUSE372", "T1A 250V", (0, 0), 0, {1: "AC_L_IN", 2: "AC_L"}, "", "Littelfuse 37211000411 (TR5, T 1 A)", "Red",
     sym="R", note="fusible lento de 1 A en la fase (el IRM-20 pide fusible externo); montaje manual")
part("RV1", "MOV7", "MOV 275 VAC", (0, 0), 0, {1: "AC_L", 2: "AC_N"}, "", "S07K275 (TDK) o equivalente", "Red",
     sym="R", note="varistor de 7 mm, 275 VAC, tras el fusible; montaje manual")
part("PS1", "IRM20", "IRM-20-5", (0, 0), 0, {1: "AC_L", 2: "AC_N", 3: GND, 4: V5AC}, "", "Mean Well IRM-20-5 (5 V 4 A)",
     "Red", sym=dict(L=[(1, "AC/L"), (2, "AC/N")], R=[(4, "+V"), (3, "-V")]),
     note="módulo AC-DC encapsulado y certificado (clase II, 3000 VAC entrada-salida); montaje manual")
C("C1", "47u 6V3", V5AC, GND, block="Red", fp="C0805", note="salida del IRM (la hoja pide 47 µF o más cerca de +V)")
C("C2", "100n", V5AC, GND, block="Red")
R("R1", "100k", V5AC, "ACOK_SNS", block="Red", note="divisor 1:2 → GPIO10: hay red")
R("R2", "100k", "ACOK_SNS", GND, block="Red")

# ---------------------------------------------------------------------------------------- USB-C del PC (J3)
part("J3", "USBC", "USB-C PC", (0, 0), 0,
     {"A1": GND, "B12": GND, "B1": GND, "A12": GND, "A4": "VBUS_C_RAW", "B9": "VBUS_C_RAW", "B4": "VBUS_C_RAW",
      "A9": "VBUS_C_RAW", "A5": "CC1", "B5": "CC2", "A6": "USBC_DP_C", "B6": "USBC_DP_C", "A7": "USBC_DM_C",
      "B7": "USBC_DM_C", "A8": None, "B8": None, "S1": GND}, LC["TYPEC"], "TYPE-C-31-M-12 (HRO)", "USB-C",
     sym=dict(L=[("A4", "VBUS"), ("A9", "VBUS"), ("B4", "VBUS"), ("B9", "VBUS"), ("A5", "CC1"), ("B5", "CC2"),
                 ("A6", "D+"), ("B6", "D+"), ("A7", "D-"), ("B7", "D-"), ("A8", "SBU1"), ("B8", "SBU2")],
              R=[("A1", "GND"), ("A12", "GND"), ("B1", "GND"), ("B12", "GND"), ("S1", "SHIELD")]),
     note="al PC (datos) y fuente de 5 V cuando no hay red")
R("R3", "5k1", "CC1", GND, block="USB-C", note="Rd: el soporte es consumidor (sink)")
R("R4", "5k1", "CC2", GND, block="USB-C")
part("F2", "F1206", "PTC 1,5 A", (0, 0), 0, {1: "VBUS_C_RAW", 2: VBUS}, LC["PTC"], "SMD1206P150TF", "USB-C", sym="R")
TVS("D1", "VBUS_C_RAW", "USB-C", "ESD en el VBUS del USB-C")
part("U1", "SOT23-6", "USBLC6-2SC6", (0, 0), 0,
     {1: "USBC_DP_C", 6: "USBC_DP_C", 3: "USBC_DM_C", 4: "USBC_DM_C", 2: GND, 5: VBUS}, LC["USBLC6"], block="USB-C",
     sym=dict(L=[(1, "IO1"), (6, "IO1"), (3, "IO2"), (4, "IO2")], R=[(5, "VBUS"), (2, "GND")]))
C("C3", "10u 25V", VBUS, GND, block="USB-C", fp="C0603")
R("R5", "100k", VBUS, "VBUSC_SNS", block="USB-C", note="divisor 1:2 → GPIO7: PC conectado")
R("R6", "100k", "VBUSC_SNS", GND, block="USB-C")

# ---------------------------------------------------------------------------------------- selector de alimentación
# Red presente: Q3 conduce → ACG = 0 → Q1 y Q1B (PMOS en paralelo) conducen 5V_RED → 5V_SYS con ≈ 30 mΩ.
# Sin red: ACG = 5V_SYS por R8 → Q1 apagado; su diodo interno bloquea 5V_SYS → 5V_RED (no se alimenta el IRM al revés).
# USB: Q2 conduce solo sin red (puerta = 5V_RED con R9 a GND); su diodo interno impide devolver corriente al PC.
for q in ("Q1", "Q1B"):
    part(q, "SOT23", "AO3401A", (0, 0), 0, {1: "ACG", 2: V5, 3: V5AC}, LC["AO3401A"], block="Selector",
         sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]), note="PMOS: D = 5V_RED, S = 5V_SYS (dos en paralelo: ≤ 2,5 A)")
part("Q3", "SOT23", "2N7002", (0, 0), 0, {1: "RED_DET", 2: GND, 3: "ACG"}, LC["2N7002"], block="Selector",
     sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]))
R("R7", "10k", V5AC, "RED_DET", block="Selector")
R("R10", "100k", "RED_DET", GND, block="Selector")
R("R8", "100k", "ACG", V5, block="Selector", note="sin red: Q1 apagado")
part("Q2", "SOT23", "AO3401A", (0, 0), 0, {1: "USBG", 2: V5, 3: VBUS}, LC["AO3401A"], block="Selector",
     sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]), note="PMOS: D = VBUS del PC, S = 5V_SYS; conduce solo sin red")
R("R9", "100k", "USBG", GND, block="Selector")
R("R11", "0R", V5AC, "USBG", block="Selector", note="puerta de Q2 = 5V_RED (con red, Q2 apagado)")
part("C4", "CTANT", "100u 10V", (0, 0), 0, {1: V5, 2: GND}, "", "TAJB107K010RNJ (AVX) o equivalente", "Selector",
     sym=dict(L=[(1, "+")], R=[(2, "-")]), note="reserva de 5V_SYS para las conexiones en caliente de las cápsulas")
C("C5", "47u 6V3", V5, GND, block="Selector", fp="C0805")
R("R12", "100k", V5, "V5_SNS", block="Selector", note="divisor 1:2 → GPIO6: tensión de 5V_SYS")
R("R13", "100k", "V5_SNS", GND, block="Selector")

# ---------------------------------------------------------------------------------------- 3,3 V (U2)
part("U2", "SOT223", "AMS1117-3.3", (0, 0), 0, {1: GND, 2: V3, 3: V5, 4: V3}, LC["AMS1117"], "AMS1117-3.3", "3V3",
     sym=dict(L=[(3, "VIN"), (1, "GND")], R=[(2, "VOUT"), (4, "TAB")]),
     note="≈ 300 mA medios (S3 + hub + pantalla): ≈ 0,5 W en SOT-223 con cobre")
C("C6", "22u 10V", V5, GND, block="3V3", fp="C0805")
C("C7", "22u 10V", V3, GND, block="3V3", fp="C0805")
C("C8", "100n", V3, GND, block="3V3")

# ---------------------------------------------------------------------------------------- ESP32-S3 (U3)
GPIO = {  # pad del módulo: (GPIO, red)
    4: ("IO0", "BOOT"), 5: ("IO1", "ISNS_CA"), 6: ("IO2", "ISNS_CB"), 7: ("IO3", None),
    8: ("IO4", "ISNS_GA"), 9: ("IO5", "ISNS_GB"), 10: ("IO6", "V5_SNS"), 11: ("IO7", "VBUSC_SNS"), 12: ("IO8", "CC1"),
    13: ("IO9", "CC2"), 14: ("IO10", "ACOK_SNS"), 15: ("IO11", "LCD_MOSI"),
    16: ("IO12", "LCD_SCK"), 17: ("IO13", "LCD_CS"), 18: ("IO14", "LCD_DC"), 19: ("IO15", "LCD_RST"), 20: ("IO16", "LCD_BL"),
    21: ("IO17", "EN_CA"), 22: ("IO18", "EN_CB"), 23: ("IO19 D-", "S3_DM"), 24: ("IO20 D+", "S3_DP"),
    25: ("IO21", "EN_GA"),
    26: ("IO26", None), 27: ("IO47", "EN_GB"), 28: ("IO33", "FLT_C"), 29: ("IO34", "FLT_G"), 30: ("IO48", "BTN"),
    31: ("IO35", "GIRTH_A_IO"), 32: ("IO36", "GIRTH_B_IO"), 33: ("IO37", "HUB_RST_N"), 34: ("IO38", "HUB_VBUS_EN"),
    35: ("IO39", "USB_SEL"), 36: ("IO40", "AUX_A"), 37: ("IO41", "AUX_B"), 38: ("IO42", None), 39: ("TXD0", "U0TX"),
    40: ("RXD0", "U0RX"), 41: ("IO45", None), 44: ("IO46", None), 45: ("EN", "EN"), 3: ("3V3", V3),
}
GND_PADS = (1, 2, 42, 43) + tuple(range(46, 66))
u3nets = {n: GND for n in GND_PADS}
u3nets.update({k: v[1] for k, v in GPIO.items()})
part("U3", "MINI1U", "ESP32-S3-MINI-1U-N8", (0, 0), 0, u3nets, LC["MINI1U"], "ESP32-S3-MINI-1U-N8", "ESP32-S3",
     sym=dict(L=[(k, v[0] + (" " + v[1] if v[1] and v[1] not in (V3,) else "")) for k, v in sorted(GPIO.items()) if k <= 25 or k == 3],
              R=[(k, v[0] + (" " + v[1] if v[1] else "")) for k, v in sorted(GPIO.items()) if 25 < k] +
                [(n, "GND") for n in GND_PADS]),
     note="BLE + Wi-Fi (app) y USB OTG; antena FPC de 2,4 GHz pegada en la tapa superior de la caja, lejos del IRM")
C("C9", "22u 10V", V3, GND, block="ESP32-S3", fp="C0805")
C("C10", "100n", V3, GND, block="ESP32-S3")
C("C11", "1u", V3, GND, block="ESP32-S3")
R("R14", "10k", "EN", V3, block="ESP32-S3")
C("C12", "1u", "EN", GND, block="ESP32-S3", note="EN: RC 10 k / 1 µF (guía de diseño de Espressif)")
R("R15", "22R", "S3_DP", "S3_DP_R", block="ESP32-S3", note="serie del USB del S3")
R("R16", "22R", "S3_DM", "S3_DM_R", block="ESP32-S3")

# ---------------------------------------------------------------------------------------- conmutadores USB (U4, U5)
# USB_SEL = 0 (por defecto, 100 k a GND): MODO PC. Hub ← USB-C; S3 en el puerto 3 del hub (CDC con la app de Windows y
#   programación del propio soporte). Con el firmware estropeado se sigue pudiendo programar desde el PC.
# USB_SEL = 1: MODO AUTÓNOMO (sin PC). Hub ← S3 como anfitrión USB: el S3 lee los cascos por el hub y sirve los
#   entrenamientos por Wi-Fi/BLE.
part("U4", "DFN10", "TS3USB221", (0, 0), 0,
     {1: "USBC_DP_C", 2: "USBC_DM_C", 3: "S3H_DP", 4: "S3H_DM", 5: GND, 6: GND, 7: "HUB_UP_DM", 8: "HUB_UP_DP",
      9: "USB_SEL", 10: V3, 11: GND}, LC["TS3USB221"], "TS3USB221ADRCR", "USB",
     sym=dict(L=[(1, "1D+"), (2, "1D-"), (3, "2D+"), (4, "2D-"), (9, "S"), (6, "OE")],
              R=[(8, "D+"), (7, "D-"), (10, "VCC"), (5, "GND"), (11, "EP")]),
     note="entrada del hub: S = 0 USB-C del PC, S = 1 el S3 (anfitrión)")
part("U5", "DFN10", "TS3USB221", (0, 0), 0,
     {1: "HUB_DN3_DP", 2: "HUB_DN3_DM", 3: "S3H_DP", 4: "S3H_DM", 5: GND, 6: GND, 7: "S3_DM_R", 8: "S3_DP_R",
      9: "USB_SEL", 10: V3, 11: GND}, LC["TS3USB221"], "TS3USB221ADRCR", "USB",
     sym=dict(L=[(1, "1D+"), (2, "1D-"), (3, "2D+"), (4, "2D-"), (9, "S"), (6, "OE")],
              R=[(8, "D+"), (7, "D-"), (10, "VCC"), (5, "GND"), (11, "EP")]),
     note="USB del S3: S = 0 puerto 3 del hub (dispositivo), S = 1 entrada del hub (anfitrión)")
C("C13", "100n", V3, GND, block="USB")
C("C14", "100n", V3, GND, block="USB")
R("R17", "100k", "USB_SEL", GND, block="USB", note="modo PC por defecto (arranque y programación)")

# ---------------------------------------------------------------------------------------- hub USB2514B (U6)
# Patillaje QFN-36 (Microchip DS00001692): 1/2 DN1 −/+ · 3/4 DN2 · 6/7 DN3 · 8/9 DN4 · 5,10,29,36 VDDA33 · 11 TEST ·
# 12/16/18/20 PRTPWR1-4 · 13/17/19/21 OCS_N1-4 · 14 CRFILT · 15,23 VDD33 · 22 SDA/NON_REM1 · 24 SCL/CFG_SEL0 ·
# 25 HS_IND/CFG_SEL1 · 26 RESET_N · 27 VBUS_DET · 28 SUSP_IND/LOCAL_PWR · 30/31 UP −/+ · 32 XTALOUT · 33 XTALIN ·
# 34 PLLFILT · 35 RBIAS · 37 almohadilla = VSS.
# Configuración por patillas: CFG_SEL1:0 = 00 (configuración interna), LOCAL_PWR = 1 (autoalimentado), NON_REM = 00,
# puerto 4 desactivado (PRT_DIS_P4 y PRT_DIS_M4 a VDD33). La potencia de los puertos la manda el S3 (no PRTPWR) y
# OCS_N1-4 van a VDD33 (sin sobrecorriente hacia el hub: la vigila el S3 con FLT_C/FLT_G).
hub = {1: "CA_DM", 2: "CA_DP", 3: "CB_DM", 4: "CB_DP", 5: V3, 6: "HUB_DN3_DM", 7: "HUB_DN3_DP", 8: V3, 9: V3,
       10: V3, 11: GND, 12: None, 13: V3, 14: "HUB_CRFILT", 15: V3, 16: None, 17: V3, 18: None,
       19: V3, 20: None, 21: V3, 22: "HUB_NONREM1", 23: V3, 24: "HUB_CFG0", 25: "HUB_CFG1",
       26: "HUB_RST_N", 27: "HUB_VBUS_DET", 28: "HUB_LOCALPWR", 29: V3, 30: "HUB_UP_DM", 31: "HUB_UP_DP",
       32: "XTAL_O", 33: "XTAL_I", 34: "HUB_PLLFILT", 35: "HUB_RBIAS", 36: V3, 37: GND}
part("U6", "QFN36", "USB2514B-I/M2", (0, 0), 0, hub, LC["USB2514B"], "USB2514B-I/M2 (Microchip)", "Hub",
     sym=dict(L=[(31, "USBDP_UP"), (30, "USBDM_UP"), (33, "XTALIN"), (32, "XTALOUT"), (26, "RESET_N"),
                 (27, "VBUS_DET"), (24, "SCL/CFG_SEL0"), (25, "HS_IND/CFG_SEL1"), (22, "SDA/NON_REM1"),
                 (28, "SUSP_IND/LOCAL_PWR"), (35, "RBIAS"), (34, "PLLFILT"), (14, "CRFILT"), (11, "TEST")] +
                [(n, "VDDA33") for n in (5, 10, 29, 36)] + [(15, "VDD33"), (23, "VDD33")],
              R=[(2, "DN1_DP"), (1, "DN1_DM"), (4, "DN2_DP"), (3, "DN2_DM"), (7, "DN3_DP"), (6, "DN3_DM"),
                 (9, "DN4_DP/PRT_DIS_P4"), (8, "DN4_DM/PRT_DIS_M4"), (12, "PRTPWR1"), (16, "PRTPWR2"),
                 (18, "PRTPWR3"), (20, "PRTPWR4"), (13, "OCS_N1"), (17, "OCS_N2"), (19, "OCS_N3"), (21, "OCS_N4"),
                 (37, "VSS")]),
     note="hub USB 2.0 de 4 puertos: 1 = casco A, 2 = casco B, 3 = S3, 4 = desactivado")
for i, n in enumerate((5, 10, 29, 36, 15, 23)):
    C("C%d" % (20 + i), "100n", V3, GND, block="Hub", note="desacoplo del pin %d" % n)
C("C26", "4u7", V3, GND, block="Hub", fp="C0603")
C("C27", "100n", "HUB_CRFILT", GND, block="Hub", note="CRFILT (pin 14)")
C("C28", "100n", "HUB_PLLFILT", GND, block="Hub", note="PLLFILT (pin 34)")
R("R20", "12k", "HUB_RBIAS", GND, block="Hub", note="RBIAS 12,0 k 1 %", lcsc="C25752")
R("R21", "10k", "HUB_CFG0", GND, block="Hub", note="CFG_SEL0 = 0")
R("R22", "10k", "HUB_CFG1", GND, block="Hub", note="CFG_SEL1 = 0")
R("R23", "10k", "HUB_NONREM1", GND, block="Hub", note="NON_REM1 = 0: todos los puertos extraíbles")
R("R24", "10k", "HUB_LOCALPWR", V3, block="Hub", note="LOCAL_PWR = 1: hub autoalimentado")
R("R26", "10k", "HUB_RST_N", V3, block="Hub", note="hub en marcha por defecto (GPIO37 puede reiniciarlo)")
C("C29", "100n", "HUB_RST_N", GND, block="Hub")
# VBUS_DET: alto con el PC conectado (divisor 68 k / 100 k desde el VBUS del USB-C ≈ 3,0 V) o cuando el S3 lo fuerza
# (GPIO38 por 10 k ≈ 2,6 V en modo autónomo); el S3 puede bajarlo (≈ 0,6 V) para desconectar el hub del PC.
R("R27", "68k", VBUS, "HUB_VBUS_DET", block="Hub")
R("R28", "100k", "HUB_VBUS_DET", GND, block="Hub")
R("R29", "10k", "HUB_VBUS_EN", "HUB_VBUS_DET", block="Hub")
part("Y1", "XTAL", "24 MHz", (0, 0), 0, {1: "XTAL_I", 2: GND, 3: "XTAL_O", 4: GND}, LC["XTAL24"],
     "X322524MOB4SI (Yangxing) 24 MHz 12 pF o equivalente", "Hub", sym=dict(L=[(1, "1")], R=[(3, "3"), (2, "GND"), (4, "GND")]))
C("C30", "18p", "XTAL_I", GND, block="Hub")
C("C31", "18p", "XTAL_O", GND, block="Hub")

# ---------------------------------------------------------------------------------------- puertos (2 cascos + 2 cinchas)
# Cada puerto: TPS2553 (límite de corriente, EN desde el S3, FAULT a FLT_x) → 50 mΩ → contacto, con INA180A2 (× 50:
# 1 A → 2,5 V) a un ADC del S3 → «cargando / cargado / sin cápsula» sin depender del firmware de la cápsula.
PORTS = [  # id, nombre, bloque, EN, FLT, ISNS, R_ILIM (k), nota
    ("CA", "casco A", "Casco A", "EN_CA", "FLT_C", "ISNS_CA", "24k9", "≈ 1,0 A (BQ24072 del casco ≈ 0,8 A)"),
    ("CB", "casco B", "Casco B", "EN_CB", "FLT_C", "ISNS_CB", "24k9", "≈ 1,0 A"),
    ("GA", "cincha A", "Cincha A", "EN_GA", "FLT_G", "ISNS_GA", "49k9", "≈ 0,5 A (XIAO ESP32-C6 ≈ 0,1 A)"),
    ("GB", "cincha B", "Cincha B", "EN_GB", "FLT_G", "ISNS_GB", "49k9", "≈ 0,5 A"),
]
refn = {"CA": 0, "CB": 1, "GA": 2, "GB": 3}
for pid, nm, blk, en, flt, isn, rlim, nt in PORTS:
    k = refn[pid]
    vo, vp = "VSW_" + pid, "VPOGO_" + pid
    part("U%d" % (10 + k), "SOT23-6", "TPS2553DBVR", (0, 0), 0,
         {1: V5, 2: GND, 3: en, 4: flt, 5: "ILIM_" + pid, 6: vo}, LC["TPS2553"], "TPS2553DBVR (TI)", blk,
         sym=dict(L=[(1, "IN"), (3, "EN"), (5, "ILIM")], R=[(6, "OUT"), (4, "FAULT"), (2, "GND")]),
         note="interruptor de potencia del %s, límite %s" % (nm, nt))
    R("R%d" % (40 + k), rlim, "ILIM_" + pid, GND, block=blk, note="R_ILIM: I_OS ≈ 23 850 / R^0,977 (SLVS841)")
    R("R%d" % (44 + k), "100k", en, GND, block=blk, note="puerto apagado mientras arranca el S3")
    C("C%d" % (40 + k), "100n", V5, GND, block=blk)
    R("R%d" % (48 + k), "50m 1%", vo, vp, block=blk, fp="R0805", lcsc=LC["R50m"],
      note="shunt de 50 mΩ (0805, 1/4 W)")
    part("U%d" % (14 + k), "SOT23-5", "INA180A2", (0, 0), 0, {1: isn, 2: GND, 3: vo, 4: vp, 5: V3},
         LC["INA180A2"], "INA180A2IDBVR (TI)", blk,
         sym=dict(L=[(3, "IN+"), (4, "IN-"), (5, "VS")], R=[(1, "OUT"), (2, "GND")]),
         note="corriente del %s → ADC" % nm)
    C("C%d" % (44 + k), "100n", V3, GND, block=blk)
    C("C%d" % (48 + k), "10u 25V", vp, GND, block=blk, fp="C0603", note="salida del puerto")
    TVS("D%d" % (10 + k), vp, blk, "ESD en el contacto +5 V expuesto")
R("R30", "10k", "FLT_C", V3, block="Casco A", note="FAULT de los dos cascos (colector abierto)")
R("R31", "10k", "FLT_G", V3, block="Cincha A", note="FAULT de las dos cinchas (colector abierto)")

# cascos: pogo de 5 contactos (VBUS · D− · D+ · GND · AUX) por hilos, ESD en D± y AUX
for pid, side, xb in (("CA", "A", 0), ("CB", "B", 1)):
    blk = "Casco " + side
    base = 1 + 5 * xb
    for i, (net, lab) in enumerate((("VPOGO_" + pid, "VBUS"), (pid + "_DM_P", "D-"), (pid + "_DP_P", "D+"),
                                    (GND, "GND"), ("AUX_" + pid + "_P", "AUX"))):
        part("P%d" % (base + i), "WIRE", "%s %s" % (side, lab), (0, 0), 0, {1: net}, block=blk, sym="TP",
             no_assembly=True, note="hilo al conector pogo de 5 contactos del alojamiento del casco %s" % side)
    part("U%d" % (18 + xb), "SOT23-6", "USBLC6-2SC6", (0, 0), 0,
         {1: pid + "_DP_P", 6: pid + "_DP_P", 3: pid + "_DM_P", 4: pid + "_DM_P", 2: GND, 5: "VPOGO_" + pid},
         LC["USBLC6"], block=blk,
         sym=dict(L=[(1, "IO1"), (6, "IO1"), (3, "IO2"), (4, "IO2")], R=[(5, "VBUS"), (2, "GND")]))
    R("R%d" % (52 + 2 * xb), "22R", pid + "_DP", pid + "_DP_P", block=blk)
    R("R%d" % (53 + 2 * xb), "22R", pid + "_DM", pid + "_DM_P", block=blk)
    R("R%d" % (56 + xb), "1k", "AUX_" + side, "AUX_" + pid + "_P", block=blk,
      note="AUX: el soporte lo pone a 3,3 V → el casco (GPIO40) sabe que está en el soporte de pared")
    TVS("D%d" % (14 + xb), "AUX_" + pid + "_P", blk, "ESD en AUX")

# cinchas: pogo de 3 contactos (1 = +5 V · 2 = GND · 3 = MTCK) por hilos
for pid, side, xb in (("GA", "A", 0), ("GB", "B", 1)):
    blk = "Cincha " + side
    base = 11 + 3 * xb
    for i, (net, lab) in enumerate((("VPOGO_" + pid, "+5V"), (GND, "GND"), ("G%s_IO_P" % side, "MTCK"))):
        part("P%d" % (base + i), "WIRE", "%s %s" % ("G" + side, lab), (0, 0), 0, {1: net}, block=blk, sym="TP",
             no_assembly=True, note="hilo al lado de muelles del pogo de 3 contactos (STEP real, paso 2,3)")
    R("R%d" % (60 + xb), "1k", "GIRTH_%s_IO" % side, "G%s_IO_P" % side, block=blk,
      note="línea de datos de 1 hilo (semidúplex 9600 baudios) con el GPIO6 de la cincha (que lleva otro 1 k)")
    R("R%d" % (62 + xb), "47k", "GIRTH_%s_IO" % side, V3, block=blk, note="reposo alto (≠ puente a GND del soporte)")
    TVS("D%d" % (16 + xb), "G%s_IO_P" % side, blk, "ESD en MTCK")

# ---------------------------------------------------------------------------------------- pantalla y pulsador
part("J4", "GH8", "PANTALLA 2\" ST7789", (0, 0), 0,
     {1: GND, 2: V3, 3: "LCD_SCK", 4: "LCD_MOSI", 5: "LCD_RST", 6: "LCD_DC", 7: "LCD_CS", 8: "LCD_BL", "MP": GND},
     LC["GH8"], "SM08B-GHS-TB (JST)", "Pantalla",
     sym=dict(L=[(1, "GND"), (2, "VCC"), (3, "SCL"), (4, "SDA")], R=[(5, "RES"), (6, "DC"), (7, "CS"), (8, "BLK"),
                                                                     ("MP", "MP")]),
     note="cable de 8 hilos al módulo IPS de 2,0\" 240 × 320 ST7789V (GND·VCC·SCL·SDA·RES·DC·CS·BLK)")
C("C15", "10u 25V", V3, GND, block="Pantalla", fp="C0603")
part("P20", "WIRE", "PULSADOR", (0, 0), 0, {1: "BTN"}, block="Pantalla", sym="TP", no_assembly=True,
     note="pulsador frontal (cambia de pantalla; 5 s = emparejar app)")
part("P21", "WIRE", "PULSADOR GND", (0, 0), 0, {1: GND}, block="Pantalla", sym="TP", no_assembly=True)
R("R32", "10k", "BTN", V3, block="Pantalla")
C("C16", "100n", "BTN", GND, block="Pantalla")

# ---------------------------------------------------------------------------------------- pruebas y mecánica
TP("TP1", "EN", "EN"); TP("TP2", "BOOT", "BOOT", "GPIO0 a GND al arrancar = descarga (también por USB desde el PC)")
TP("TP3", "GND", GND); TP("TP4", "TXD0", "U0TX"); TP("TP5", "RXD0", "U0RX"); TP("TP6", "3V3", V3)
TP("TP7", "5V_SYS", V5); TP("TP8", "5V_RED", V5AC); TP("TP9", "VBUS_PC", VBUS)
HOLES = [(61.0, 34.0), (61.0, -34.0), (-61.0, -34.0), (-34.5, 34.0)]
for i, (hx, hy) in enumerate(HOLES, 1):
    part("H%d" % i, "HOLE", "TALADRO M3", (hx, hy), 0, {}, block="Mecánica", sym=None, no_assembly=True,
         note="taladro NPTH Ø3,2 (tornillo M3 de nailon al pilar de la caja)")

# pistas de la red (diseño, F.Cu, 1,0 mm): se generan aquí para no depender del enrutador
MAINS_W = 1.0
MAINS_NETS = ("AC_L_IN", "AC_L", "AC_N")

# --------------------------------------------------------------------------------- colocación (X, Y, giro)
POSF = os.path.join(HERE, "colocacion_dock.json")
POS = json.load(open(POSF, encoding="utf-8")) if os.path.exists(POSF) else {}
for p in PARTS:
    if p["ref"] in POS:
        x, y, r = POS[p["ref"]]
        p["pos"], p["rot"] = (x, y), r
MECH = [p for p in PARTS if p["fp"] in ("HOLE",)]
KEEPOUT_RECTS = [("red y foso", -66.0, -12.0 - MOAT, -46.0 + MOAT, 39.0)]
EDGE_OK = {"J3"}            # el USB-C asoma por el canto a propósito

# =============================================================================== redes
NETS = []
for p in PARTS:
    for n in p["nets"].values():
        if n and n not in NETS:
            NETS.append(n)
NETS.sort(key=lambda n: (n not in (GND, V3, V5, V5AC, VBUS), n))


def pin_name(p, num):
    s = p["sym"]
    if isinstance(s, dict):
        for k, nm in list(s.get("L", [])) + list(s.get("R", [])):
            if str(k) == str(num):
                return nm
        return str(num)
    return str(num)


for p in PARTS:
    nums = []
    for pd in FP[p["fp"]].pads:
        if pd.num and pd.num not in nums and pd.kind != "np_thru_hole":
            nums.append(pd.num)
    for num in nums:
        if p["nets"].get(num) is None:
            listed = isinstance(p["sym"], dict) and any(str(k) == str(num) for k, _ in
                                                         list(p["sym"].get("L", [])) + list(p["sym"].get("R", [])))
            if isinstance(p["sym"], dict) and not listed:
                nc = "unconnected-(%s-Pad%s)" % (p["ref"], num)
            else:
                nc = "unconnected-(%s-%s-Pad%s)" % (p["ref"], pin_name(p, num), num)
            p["nets"][num] = nc
            p.setdefault("nc", set()).add(num)
            NETS.append(nc)
CODE = {n: i + 1 for i, n in enumerate(NETS)}


def fp_of(p):
    return FP[p["fp"]]


def kpos(p):
    return K(*p["pos"])


# =============================================================================== comprobaciones de colocación
def courtyard_abs(p):
    fp = fp_of(p)
    x0, y0, x1, y1 = fp.courtyard()
    cx, cy = kpos(p)
    from fplib import rot
    pts = [rot(x, y, p["rot"]) for x, y in ((x0, y0), (x1, y0), (x1, y1), (x0, y1))]
    xs = [cx + u for u, _ in pts]; ys = [cy + v for _, v in pts]
    return min(xs), min(ys), max(xs), max(ys)


def courtyard_casing(p):
    x0, y0, x1, y1 = courtyard_abs(p)
    return x0 - 100, 100 - y1, x1 - 100, 100 - y0


def zone_limit(x, y):
    return Z_MAX_F


CIRC = {"HOLE": HOLE_KEEP}


def is_mains(p):
    return any(n in MAINS_NETS for n in p["nets"].values())


def pads_abs(p):
    from fplib import pad_center
    out = []
    for pd in fp_of(p).pads:
        if pd.num == "" and pd.kind != "np_thru_hole":
            continue
        x, y = pad_center(pd, *kpos(p), p["rot"])
        out.append((pd, x - 100, 100 - y))
    return out


def in_rect(x, y, r, grow=0.0):
    return r[0] - grow <= x <= r[2] + grow and r[1] - grow <= y <= r[3] + grow


def check_placement():
    errs = []
    boxes = [(p["ref"], courtyard_abs(p)) for p in PARTS]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, ba = boxes[i]; b, bb = boxes[j]
            pa = next(q for q in PARTS if q["ref"] == a); pb = next(q for q in PARTS if q["ref"] == b)
            if pa["fp"] in CIRC and pb["fp"] in CIRC:
                (ax_, ay_), (bx_, by_) = kpos(pa), kpos(pb)
                if math.hypot(ax_ - bx_, ay_ - by_) >= CIRC[pa["fp"]] + CIRC[pb["fp"]]:
                    continue
            if ba[0] < bb[2] and bb[0] < ba[2] and ba[1] < bb[3] and bb[1] < ba[3]:
                ox = min(ba[2], bb[2]) - max(ba[0], bb[0]); oy = min(ba[3], bb[3]) - max(ba[1], bb[1])
                if ox > 0.02 and oy > 0.02:
                    if pa["fp"] in CIRC or pb["fp"] in CIRC:
                        q, z = (pa, pb) if pa["fp"] in CIRC else (pb, pa)
                        r = CIRC[q["fp"]]
                        zx0, zy0, zx1, zy1 = courtyard_abs(z); cx, cy = kpos(q)
                        dx = max(zx0 - cx, 0, cx - zx1); dy = max(zy0 - cy, 0, cy - zy1)
                        if math.hypot(dx, dy) >= r:
                            continue
                    errs.append("solape de patio %s–%s (%.2f × %.2f)" % (a, b, ox, oy))
    poly = [K(x, y) for x, y in outline_pts(3)]
    for ref, bb in boxes:
        p = next(q for q in PARTS if q["ref"] == ref)
        if p["fp"] in CIRC or ref in EDGE_OK:
            continue
        samples = []
        for k in range(9):
            t = k / 8
            samples += [(bb[0] + t * (bb[2] - bb[0]), bb[1]), (bb[0] + t * (bb[2] - bb[0]), bb[3]),
                        (bb[0], bb[1] + t * (bb[3] - bb[1])), (bb[2], bb[1] + t * (bb[3] - bb[1]))]
        for (x, y) in samples:
            if not point_in_poly(x, y, poly):
                errs.append("%s se sale de la placa en (%.2f, %.2f)" % (ref, x - 100, 100 - y)); break
            if dist_to_poly(x, y, poly) < 0.25:
                errs.append("%s a %.2f del borde" % (ref, dist_to_poly(x, y, poly))); break
        if fp_of(p).height > Z_MAX_F + 1e-6:
            errs.append("%s demasiado alto: %.2f > %.2f" % (ref, fp_of(p).height, Z_MAX_F))
    # aislamiento de red: pads de red dentro de la zona de red; nada de MBTS en la zona de red ni en el foso
    for p in PARTS:
        for pd, x, y in pads_abs(p):
            net = p["nets"].get(pd.num)
            r = max(pd.w, pd.h) / 2
            if net in MAINS_NETS:
                if not in_rect(x, y, MAINS_RECT, -r - 0.5):
                    errs.append("pad de red %s.%s fuera de la zona de red" % (p["ref"], pd.num))
            elif net or pd.kind == "np_thru_hole":
                if point_in_poly(x, y, MOAT_POLY + []) or in_rect(x, y, MAINS_RECT, r) or \
                        in_rect(x, y, (MAINS_RECT[0], MAINS_RECT[1] - MOAT, MAINS_RECT[2] + MOAT, MAINS_RECT[3]), r):
                    errs.append("pad MBTS %s.%s (%s) dentro de la zona de red o del foso" % (p["ref"], pd.num, net))
    return errs


def point_in_poly(x, y, poly):
    c = False
    n = len(poly)
    for k in range(n):
        xa, ya = poly[k]; xb, yb = poly[(k + 1) % n]
        if (ya > y) != (yb > y) and x < xa + (y - ya) * (xb - xa) / (yb - ya):
            c = not c
    return c


def dist_to_poly(x, y, poly):
    best = 1e9
    n = len(poly)
    for k in range(n):
        xa, ya = poly[k]; xb, yb = poly[(k + 1) % n]
        dx, dy = xb - xa, yb - ya
        L2 = dx * dx + dy * dy
        t = 0 if L2 == 0 else max(0, min(1, ((x - xa) * dx + (y - ya) * dy) / L2))
        best = min(best, math.hypot(x - xa - t * dx, y - ya - t * dy))
    return best


def pad_xy(ref, num):
    p = next(q for q in PARTS if q["ref"] == ref)
    for pd, x, y in pads_abs(p):
        if pd.num == str(num):
            return (x, y)
    raise KeyError((ref, num))


def mains_tracks():
    """[(red, [(x, y), …])] en coordenadas de diseño: pistas de 1,0 mm en F.Cu dentro de la zona de red."""
    l_in = [pad_xy("J1", 1), pad_xy("F1", 1)]
    f2, rv1, ps1 = pad_xy("F1", 2), pad_xy("RV1", 1), pad_xy("PS1", 1)
    l_f1 = [f2, (rv1[0], f2[1]), rv1]
    l_f2 = [rv1, (ps1[0], rv1[1]), ps1]
    j2, rv2, ps2 = pad_xy("J2", 1), pad_xy("RV1", 2), pad_xy("PS1", 2)
    n1 = [j2, (j2[0], rv2[1]), rv2]
    n2 = [rv2, (rv2[0], ps2[1]), ps2]
    return [("AC_L_IN", l_in), ("AC_L", l_f1), ("AC_L", l_f2), ("AC_N", n1), ("AC_N", n2)]


def mecanica():
    """taladros, pads de hilos, envolventes y conectores → CAD de la caja (pcb_mecanica.json)"""
    env = []
    for p in PARTS:
        h = fp_of(p).height
        if h > 0:
            x0, y0, x1, y1 = courtyard_casing(p)
            env.append([p["ref"], round(x0, 3), round(y0, 3), round(x1, 3), round(y1, 3), h])
    return dict(placa=dict(ancho=W, alto=H, radio_esquina=CORNER_R, espesor=THICK, vista="cara F (componentes)"),
                taladros=[list(p["pos"]) for p in PARTS if p["fp"] == "HOLE"],
                hilos={p["ref"]: dict(pos=list(p["pos"]), red=p["nets"]["1"]) for p in PARTS if p["fp"] in ("WIRE", "WIREAC")},
                usb_c=dict(pos=list(next(p for p in PARTS if p["ref"] == "J3")["pos"]),
                           giro=next(p for p in PARTS if p["ref"] == "J3")["rot"]),
                zona_red=MAINS_RECT, foso=MOAT,
                envolventes=env, origen="generado por PCB/fuente/avo_dock_v1_pcb.py (colocacion_dock.json)")


if __name__ == "__main__" and "--place" in sys.argv:
    errs = check_placement()
    for e in errs:
        print(e)
    print("piezas:", len(PARTS), "· errores:", len(errs))
    sys.exit(1 if errs else 0)
