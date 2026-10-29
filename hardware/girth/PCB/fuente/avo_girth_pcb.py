"""AVO GIRTH · placa de la cincha REV A — generador del proyecto KiCad 9.

Un solo origen de datos (piezas, redes, posiciones) genera el esquema, la placa, las reglas, la lista de
piezas para JLCPCB y las comprobaciones. Coordenadas de diseño = las de la cápsula (avo_girth_rev5.py):
X a lo largo de la cápsula, Y hacia +Y de la cápsula, origen en el centro; vista desde la tapa.
En KiCad: x = 100 + X, y = 100 − Y.

Uso:  python avo_girth_pcb.py            (escribe ../kicad/*)
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import board as B                      # noqa: E402
import project                         # noqa: E402
import schematic as SCH                # noqa: E402
from custom_fp import bno085, test_pad, wire_pad   # noqa: E402
from fplib import load, emit, pad_poly, pad_center, pad_copper_layers, uid   # noqa: E402
from router import Router              # noqa: E402
from sexpr import Sym                  # noqa: E402

OUT = os.path.join(HERE, "..", "kicad")
os.makedirs(OUT, exist_ok=True)
REV, DATE = "A", "2026-10-29"
THICK = 1.0


def K(X, Y):
    return (round(100 + X, 4), round(100 - Y, 4))


# =============================================================================== mecánica (cápsula REV 5.8.1)
L_CAP, W_CAP = 73.0, 51.0
LIP_OUT = 3.75                       # la placa ocupa el sitio de la bandeja: 65,5 × 43,5, R6,25
PL, PW, PR = L_CAP - 2 * LIP_OUT, W_CAP - 2 * LIP_OUT, 10.0 - LIP_OUT
LIP_BAND = 1.2 + 0.25                # el labio de la tapa pisa 1,2 mm del borde: sin componentes en 1,45 mm
SCREWS = [(sx * 21.0, sy * (W_CAP / 2 - 5.0)) for sx in (-1, 1) for sy in (-1, 1)] + \
         [(sx * (L_CAP / 2 - 5.0), sy * 10.0) for sx in (-1, 1) for sy in (-1, 1)]
NOTCH_R = 3.6                        # columnas Ø5,6 de la base + corte Ø6,6 de la tapa + holgura
Z_PCB_BOTTOM = 7.8                   # cuna de la batería +0,6 mm (z 7,75): hueco para las patas del USB-C
Z_CEIL = 15.5 - 2.3                  # techo interior de la tapa
H_MAX = Z_CEIL - (Z_PCB_BOTTOM + THICK) - 0.3        # altura libre sobre la placa con 0,3 de holgura
SLOT = dict(c=(-29.0, 4.6), w=1.6, h=3.4)           # paso del cable de la batería (fresado)
LID_POCKET = {"K1": 1.3}                             # rebaje en el techo de la tapa sobre el relé (mm)
ANT_KEEPOUT = (-3.3, 12.6, 25.5, PW / 2 + 1)        # banda sin cobre bajo la antena FPC (pegada al techo)


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
    """Board outline as lines and 3-point arcs (capsule coordinates), counter-clockwise. Notches are circles
    of radius NOTCH_R around the 8 closing screws (centres taken from the capsule CAD)."""
    hx, hy, r = PL / 2, PW / 2, PR
    nr = NOTCH_R
    sy = W_CAP / 2 - 5.0                 # 20,5: screws on the long sides, X = ±21
    sx = L_CAP / 2 - 5.0                 # 31,5: screws on the ends, Y = ±10
    ey = math.sqrt(nr ** 2 - (hy - sy) ** 2)     # half chord on the long edges
    ex = math.sqrt(nr ** 2 - (hx - sx) ** 2)     # half chord on the ends
    c45 = r * math.cos(math.radians(45))
    P = []

    def L(a, b):
        P.append(("line", a, b))

    def A(a, m, b):
        P.append(("arc", a, m, b))
    L((hx, -hy + r), (hx, -10 - ex)); A((hx, -10 - ex), (sx - nr, -10), (hx, -10 + ex))
    L((hx, -10 + ex), (hx, 10 - ex)); A((hx, 10 - ex), (sx - nr, 10), (hx, 10 + ex))
    L((hx, 10 + ex), (hx, hy - r)); A((hx, hy - r), (hx - r + c45, hy - r + c45), (hx - r, hy))
    L((hx - r, hy), (21 + ey, hy)); A((21 + ey, hy), (21, sy - nr), (21 - ey, hy))
    L((21 - ey, hy), (-21 + ey, hy)); A((-21 + ey, hy), (-21, sy - nr), (-21 - ey, hy))
    L((-21 - ey, hy), (-hx + r, hy)); A((-hx + r, hy), (-hx + r - c45, hy - r + c45), (-hx, hy - r))
    L((-hx, hy - r), (-hx, 10 + ex)); A((-hx, 10 + ex), (-sx + nr, 10), (-hx, 10 - ex))
    L((-hx, 10 - ex), (-hx, -10 + ex)); A((-hx, -10 + ex), (-sx + nr, -10), (-hx, -10 - ex))
    L((-hx, -10 - ex), (-hx, -hy + r)); A((-hx, -hy + r), (-hx + r - c45, -hy + r - c45), (-hx + r, -hy))
    L((-hx + r, -hy), (-21 - ey, -hy)); A((-21 - ey, -hy), (-21, -sy + nr), (-21 + ey, -hy))
    L((-21 + ey, -hy), (21 - ey, -hy)); A((21 - ey, -hy), (21, -sy + nr), (21 + ey, -hy))
    L((21 + ey, -hy), (hx - r, -hy)); A((hx - r, -hy), (hx - r + c45, -hy + r - c45), (hx, -hy + r))
    return P


def slot_prims():
    cx, cy = SLOT["c"]; rr = SLOT["w"] / 2; hh = SLOT["h"] / 2 - rr
    return [("line", (cx + rr, cy - hh), (cx + rr, cy + hh)),
            ("arc", (cx + rr, cy + hh), (cx, cy + hh + rr), (cx - rr, cy + hh)),
            ("line", (cx - rr, cy + hh), (cx - rr, cy - hh)),
            ("arc", (cx - rr, cy - hh), (cx, cy - hh - rr), (cx + rr, cy - hh))]


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
FP = {
    "R0805": load("R_0805_2012Metric.kicad_mod", M3 + "Resistor_SMD.3dshapes/R_0805_2012Metric.step", 0.6),
    "R0402": load("R_0402_1005Metric.kicad_mod", M3 + "Resistor_SMD.3dshapes/R_0402_1005Metric.step", 0.4),
    "C0402": load("C_0402_1005Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0402_1005Metric.step", 0.6),
    "C0603": load("C_0603_1608Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0603_1608Metric.step", 0.9),
    "TANT_B": load("CP_EIA-3528-21_Kemet-B.kicad_mod",
                   M3 + "Capacitor_Tantalum_SMD.3dshapes/CP_EIA-3528-21_Kemet-B.step", 2.1),
    "C1206": load("C_1206_3216Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_1206_3216Metric.step", 1.8),
    "C0805": load("C_0805_2012Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0805_2012Metric.step", 1.35),
    "LED0603": load("LED_0603_1608Metric.kicad_mod", M3 + "LED_SMD.3dshapes/LED_0603_1608Metric.step", 0.8),
    "SOT23": load("SOT-23.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23.step", 1.1),
    "SOT23-5": load("SOT-23-5.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23-5.step", 1.45),
    "SOT23-6": load("SOT-23-6.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23-6.step", 1.45),
    "RHL20": load("Texas_VQFN-RHL-20_ThermalVias.kicad_mod",
                  M3 + "Package_DFN_QFN.3dshapes/Texas_VQFN-RHL-20.step", 1.0),
    "RGT16": load("VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm_ThermalVias.kicad_mod",
                  M3 + "Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step", 1.0),
    "XTAL3215": load("Crystal_SMD_3215-2Pin_3.2x1.5mm.kicad_mod",
                     M3 + "Crystal.3dshapes/Crystal_SMD_3215-2Pin_3.2x1.5mm.step", 0.9),
    "USBC": load("USB_C_Receptacle_HRO_TYPE-C-31-M-12.kicad_mod",
                 M3 + "Connector_USB.3dshapes/USB_C_Receptacle_HRO_TYPE-C-31-M-12.step", 3.3),
    "JST_SH2": load("JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.kicad_mod",
                    M3 + "Connector_JST.3dshapes/JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.step", 2.95),
    "RELAY": load("Relay_DPDT_Omron_G6K-2F-Y.kicad_mod",
                   M3 + "Relay_SMD.3dshapes/Relay_DPDT_Omron_G6K-2F-Y.step", 5.2),
    "MINI1U": load("ESP32-C6-MINI-1U.kicad_mod", "${KIPRJMOD}/../fuente/3d/ESP32-C6-MINI-1U.STEP", 2.6),
    "BNO": bno085(),
    "WIRE": wire_pad("bobina / reed"),
    "TP": test_pad(1.0),
}
# vías térmicas de las QFN: taladro 0,3 (estándar JLCPCB) en lugar de 0,2
for k in ("RHL20", "RGT16"):
    for p in FP[k].pads:
        if p.kind == "thru_hole":
            p.drill, p.w, p.h = 0.3, 0.5, 0.5
FP["BNO"].model = None

# =============================================================================== piezas y redes
PARTS = []


def part(ref, fp, value, pos, rot, nets, lcsc="", mpn="", block="", sym=None, dnp=False, note="", jlc_rot=0,
         no_assembly=False):
    PARTS.append(dict(ref=ref, fp=fp, value=value, pos=pos, rot=rot, nets={str(k): v for k, v in nets.items()},
                      lcsc=lcsc, mpn=mpn, block=block, sym=sym, dnp=dnp, note=note, jlc_rot=jlc_rot,
                      no_assembly=no_assembly))


# --- piezas básicas (LCSC verificados en la lista de materiales; ver DOCS) -----------------------------
LC = {
    "0R": "C17168", "22R": "C25092", "100R": "C25076", "330R": "C25104", "200R": "C25087", "1k": "C11702",
    "3k4": "C4940", "3k6": "C25891", "5k1": "C25905", "10k": "C25744", "20k": "C25765", "100k": "C25741",
    "1M": "C26083",
    "100n": "C1525", "1u": "C52923", "10n": "C15195", "22n": "C1532", "22p": "C1555", "4u7": "C19666",
    "10u": "C96446", "22u": "C45783", "470n": "C1623",
    "100n C0G": "C97946", "47n C0G": "C21812", "2n2 C0G": "C51795", "1n C0G": "C1636",
    "NTC10k": "C77131", "G6KU": "C6259328", "AO3400A": "C20917", "2N7002": "C8545", "BAT54C": "C2135",
    "0R0805": "C17477", "220u": "C79111", "AO3401A": "C15127", "USBLC6": "C7519", "LED": "C2286",
    "RT9080": "C841192", "BQ51013B": "C55663", "BQ24072": "C140288", "MINI1U": "C7558096",
    "BNO085": "C5189642", "XTAL": "C32346", "USBC": "C165948", "JST_SH2": "C160402",
}


def R(ref, val, n1, n2, pos, rot=0, block="", dnp=False, fp="R0402", note=""):
    lc = LC["0R0805"] if (fp == "R0805" and val == "0R") else LC.get(val.replace("Ω", ""), "")
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, lc, block=block, sym="R", dnp=dnp,
         note=note)


def C(ref, val, n1, n2, pos, rot=0, block="", fp="C0402", dnp=False, lcsc=None, note=""):
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, lcsc if lcsc is not None else LC.get(val.split()[0], ""),
         block=block, sym="C", dnp=dnp, note=note)


GND, V3, VSYS, VBAT, VBUS, VIN5 = "GND", "+3V3", "VSYS", "VBAT", "VBUS", "VIN5"

# ---------------------------------------------------------------------------------------- Qi (U1)
QI = (-21.0, -3.0)
part("U1", "RHL20", "BQ51013BRHLR", QI, 90,
     {1: GND, 20: GND, 21: GND, 2: "QI_AC1", 19: "QI_AC2", 3: "QI_BOOT1", 17: "QI_BOOT2", 4: VIN5,
      5: "QI_CLAMP1", 16: "QI_CLAMP2", 6: "QI_COMM1", 15: "QI_COMM2", 7: "QI_CHG", 8: "QI_ADEN", 9: VBUS,
      10: GND, 11: GND, 12: "QI_ILIM", 13: "QI_TS", 14: "QI_FOD", 18: "QI_RECT"},
     LC["BQ51013B"], "BQ51013BRHLR (alt. BQ51013CRHLR C43043533)", "Qi",
     sym=dict(L=[(2, "AC1"), (19, "AC2"), (3, "BOOT1"), (17, "BOOT2"), (5, "CLAMP1"), (16, "CLAMP2"),
                 (6, "COMM1"), (15, "COMM2"), (9, "AD"), (8, "AD-EN"), (10, "EN1"), (11, "EN2")],
              R=[(18, "RECT"), (4, "OUT"), (7, "CHG"), (12, "ILIM"), (14, "FOD"), (13, "TS/CTRL"),
                 (1, "PGND"), (20, "PGND"), (21, "EP")]))
part("L1", "WIRE", "BOBINA Qi (1)", (-28.4, -6.2), 0, {1: "QI_COIL1"}, block="Qi", sym="TP", no_assembly=True,
     note="hilo de la bobina Ø25 (desde abajo)")
part("L2", "WIRE", "BOBINA Qi (2)", (-28.4, -2.0), 0, {1: "QI_AC2"}, block="Qi", sym="TP", no_assembly=True,
     note="hilo de la bobina Ø25 (desde abajo)")
# condensadores de resonancia: C1 serie (bobina → AC1), C2 paralelo (AC1–AC2). Valores para Ls' ≈ 10 µH:
# C1 = 1/((2π·100 kHz)²·Ls') ≈ 253 nF → 100 + 100 + 47 nF. AJUSTAR con la bobina real (DOCS/AJUSTE_QI.md).
C("C1", "100n C0G 50V", "QI_COIL1", "QI_AC1", (-25.6, -9.4), 0, "Qi", "C1206", lcsc=LC["100n C0G"])
C("C2", "100n C0G 50V", "QI_COIL1", "QI_AC1", (-25.6, -11.2), 0, "Qi", "C1206", lcsc=LC["100n C0G"])
C("C3", "47n C0G 50V", "QI_COIL1", "QI_AC1", (-25.6, -13.0), 0, "Qi", "C1206", lcsc=LC["47n C0G"])
C("C4", "2n2 C0G 50V", "QI_AC1", "QI_AC2", (-25.8, -4.1), 90, "Qi", "C0805", lcsc=LC["2n2 C0G"])
C("C5", "1n C0G 50V", "QI_AC1", "QI_AC2", (-24.3, -4.1), 90, "Qi", "C0603", dnp=True, lcsc=LC["1n C0G"],
  note="ajuste de C2 (sin montar)")
C("C6", "10n 50V", "QI_BOOT1", "QI_AC1", (-22.4, -6.4), 90, "Qi")
C("C7", "470n 25V", "QI_CLAMP1", "QI_AC1", (-20.9, -6.6), 90, "Qi", "C0603")
C("C8", "22n 50V", "QI_COMM1", "QI_AC1", (-19.6, -6.4), 90, "Qi")
C("C9", "10n 50V", "QI_BOOT2", "QI_AC2", (-21.9, 0.4), 90, "Qi")
C("C10", "470n 25V", "QI_CLAMP2", "QI_AC2", (-20.6, 0.6), 90, "Qi", "C0603")
C("C11", "22n 50V", "QI_COMM2", "QI_AC2", (-19.3, 0.4), 90, "Qi")
C("C12", "10u 25V", "QI_RECT", GND, (-25.6, 0.9), 90, "Qi", "C0603")
C("C13", "10u 25V", "QI_RECT", GND, (-24.1, 0.9), 90, "Qi", "C0603")
C("C14", "100n", "QI_RECT", GND, (-23.1, 2.6), 0, "Qi")
C("C15", "10u 25V", VIN5, GND, (-17.6, -9.0), 0, "Qi", "C0603")
C("C16", "100n", VIN5, GND, (-19.4, -9.0), 0, "Qi")
# límite de corriente de salida: R_ILIM = R1 + R_FOD = 330 + 200 = 530 Ω → 262/530 ≈ 494 mA (límite duro ≈ 590 mA)
R("R1", "330R", "QI_ILIM", "QI_FOD", (-17.6, 0.9), 90, "Qi")
R("R2", "200R", "QI_FOD", GND, (-16.5, 0.9), 90, "Qi")
R("R3", "20k", "QI_RECT", "QI_FOD", (-15.4, 0.9), 90, "Qi", note="R_OS (TI: RECT → FOD); se ajusta en la calibración FOD")
part("RT1", "R0402", "NTC 10k B3380", (-18.7, 1.6), 90, {1: "QI_TS", 2: GND}, LC["NTC10k"],
     "NCP15XH103F03RC", "Qi", sym="R")
R("R4", "100k", "QI_CHG", V3, (-15.6, -6.6), 90, "Qi")
C("C17", "1u", VBUS, GND, (-16.4, -10.6), 0, "Qi")
# USB → AD/AD-EN: dos PMOS espalda con espalda (fuentes comunes) entre VBUS y VIN5 (TI SLUSAF8 §9.2.2)
part("Q1", "SOT23", "AO3401A", (-12.6, -9.8), 0, {1: "QI_ADEN", 2: "AD_SRC", 3: VBUS}, LC["AO3401A"],
     block="USB", sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]))
part("Q2", "SOT23", "AO3401A", (-12.6, -13.6), 0, {1: "QI_ADEN", 2: "AD_SRC", 3: VIN5}, LC["AO3401A"],
     block="USB", sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]))

# ---------------------------------------------------------------------------------------- cargador (U2)
CH = (-12.6, -2.6)
part("U2", "RGT16", "BQ24072RGTR", CH, 0,
     {1: "CHG_TS", 2: VBAT, 3: VBAT, 4: GND, 5: "CHG_EN2", 6: GND, 7: "CHG_PG", 8: GND, 9: "CHG_STAT",
      10: VSYS, 11: VSYS, 12: "CHG_ILIM", 13: VIN5, 14: None, 15: GND, 16: "CHG_ISET", 17: GND},
     LC["BQ24072"], "BQ24072RGTR", "Cargador",
     sym=dict(L=[(13, "IN"), (4, "CE"), (6, "EN1"), (5, "EN2"), (16, "ISET"), (12, "ILIM"), (14, "TMR"),
                 (15, "TD"), (1, "TS")],
              R=[(10, "OUT"), (11, "OUT"), (2, "BAT"), (3, "BAT"), (7, "PGOOD"), (9, "CHG"), (8, "VSS"), (17, "EP")]))
C("C18", "1u", VIN5, GND, (-15.6, -2.6), 90, "Cargador")
C("C19", "10u 25V", VSYS, GND, (-9.6, -1.6), 90, "Cargador", "C0603")
C("C20", "10u 25V", VBAT, GND, (-14.6, 0.6), 0, "Cargador", "C0603")
R("R6", "3k6", "CHG_ISET", GND, (-11.6, -5.6), 0, "Cargador", note="I_carga = 890/3,6k ≈ 247 mA")
R("R7", "3k4", "CHG_ILIM", GND, (-9.6, -4.6), 90, "Cargador", note="I_entrada = 1525/3,4k = 450 mA")
part("RT2", "R0402", "NTC 10k B3380", (-13.8, -5.6), 0, {1: "CHG_TS", 2: GND}, LC["NTC10k"],
     "NCP15XH103F03RC", "Cargador", sym="R")
R("R8", "100k", "CHG_EN2", VSYS, (-8.6, -2.8), 90, "Cargador", note="EN2 = 1, EN1 = 0: límite por ILIM")
R("R9", "100k", "CHG_PG", V3, (-8.4, -6.6), 90, "Cargador")
R("R10", "100k", "CHG_STAT", V3, (-7.3, -6.6), 90, "Cargador")
part("J2", "JST_SH2", "BATERÍA 1S", (-21.6, 5.4), 270, {1: "BAT_RAW", 2: GND, "MP": GND}, LC["JST_SH2"],
     "SM02B-SRSS-TB (JST SH 1,0)", "Batería", sym=dict(L=[(1, "+"), (2, "−")], R=[("MP", "MP")]),
     note="pin 1 = + · comprobar la polaridad del cable antes de enchufar")

# ---------------------------------------------------------------------------------------- 3,3 V (U3)
LDO = (22.6, -15.0)
part("U3", "SOT23-5", "RT9080-33GJ5", LDO, 0, {1: VSYS, 2: GND, 3: VSYS, 4: None, 5: V3}, LC["RT9080"],
     "RT9080-33GJ5", "3V3", sym=dict(L=[(1, "VIN"), (3, "EN"), (2, "GND")], R=[(5, "VOUT"), (4, "NC")]))
C("C21", "10u 25V", VSYS, GND, (25.6, -15.6), 90, "3V3", "C0603")
C("C22", "10u 25V", V3, GND, (19.8, -16.4), 0, "3V3", "C0603")

# ---------------------------------------------------------------------------------------- ESP32-C6 (U4)
MCU = (11.6, -7.0)
part("U4", "MINI1U", "ESP32-C6-MINI-1U-N4", MCU, 90,
     dict([(n, GND) for n in (1, 2, 11, 14) + tuple(range(36, 54))] +
          [(3, V3), (4, None), (7, None), (21, None), (32, None), (33, None), (34, None), (35, None),
           (8, "EN"), (12, "IMU_INT"), (13, "IMU_RST"), (5, "BAT_ADC"), (6, "CHG_PG"), (9, "CHG_STAT"),
           (10, "IMU_PWR_N"), (15, "REED"), (16, "IMU_WAKE"), (17, "USB_DM"), (18, "USB_DP"),
           (19, None), (20, "LED"), (22, "GPIO8"), (23, "BOOT"), (24, "IMU_CS"), (25, "IMU_SCK"),
           (26, "IMU_MOSI"), (27, "IMU_MISO"), (28, "QI_CHG"), (29, "RLY_OFF"), (30, "U0RX"), (31, "U0TX")]),
     LC["MINI1U"], "ESP32-C6-MINI-1U-N4 (alt. -H4 C20627095)", "ESP32-C6",
     sym=dict(L=[(3, "3V3"), (8, "EN"), (12, "IO0 IMU_INT"), (13, "IO1 IMU_RST"), (5, "IO2 BAT_ADC"),
                 (6, "IO3 CHG_PG"), (9, "IO4 CHG_STAT"), (10, "IO5 IMU_PWR"), (15, "IO6 REED"),
                 (16, "IO7 IMU_WAKE"), (22, "IO8"), (23, "IO9 BOOT"), (19, "IO14"), (20, "IO15 LED"),
                 (4, "NC"), (7, "NC"), (21, "NC"), (32, "NC"), (33, "NC"), (34, "NC"), (35, "NC")],
              R=[(17, "IO12 D-"), (18, "IO13 D+"), (24, "IO18 CS"), (25, "IO19 SCK"), (26, "IO20 MOSI"),
                 (27, "IO21 MISO"), (28, "IO22 QI_CHG"), (29, "IO23 RELÉ OFF"), (30, "IO17 RXD0"), (31, "IO16 TXD0")] +
                [(n, "GND") for n in (1, 2, 11, 14) + tuple(range(36, 54))]))
C("C23", "22u 10V", V3, GND, (11.2, -15.4), 0, "ESP32-C6", "C0805")
C("C24", "100n", V3, GND, (13.4, -15.2), 0, "ESP32-C6")
R("R11", "10k", "EN", V3, (16.2, -15.2), 90, "ESP32-C6")
C("C25", "1u", "EN", GND, (17.4, -15.2), 90, "ESP32-C6")
R("R12", "10k", "BOOT", V3, (21.0, -2.0), 0, "ESP32-C6")
R("R13", "10k", "GPIO8", V3, (21.0, -3.2), 0, "ESP32-C6")
R("R14", "10k", "LED", GND, (21.0, -10.2), 0, "ESP32-C6", note="GPIO15 (strapping) a nivel definido")
R("R15", "1k", "LED", "LED_A", (21.0, -11.4), 0, "ESP32-C6")
part("D1", "LED0603", "LED verde", (21.4, -12.8), 180, {1: GND, 2: "LED_A"}, LC["LED"], block="ESP32-C6",
     sym="LED")
part("TP1", "TP", "EN", (4.0, -17.2), 0, {1: "EN"}, block="Pruebas", sym="TP", no_assembly=True)
part("TP2", "TP", "BOOT", (6.0, -17.2), 0, {1: "BOOT"}, block="Pruebas", sym="TP", no_assembly=True)
part("TP3", "TP", "GND", (8.0, -17.2), 0, {1: GND}, block="Pruebas", sym="TP", no_assembly=True)
part("TP4", "TP", "TXD0", (4.0, -15.2), 0, {1: "U0TX"}, block="Pruebas", sym="TP", no_assembly=True)
part("TP5", "TP", "RXD0", (6.0, -15.2), 0, {1: "U0RX"}, block="Pruebas", sym="TP", no_assembly=True)
part("TP6", "TP", "3V3", (8.0, -15.2), 0, {1: V3}, block="Pruebas", sym="TP", no_assembly=True)
part("TP7", "TP", "VBAT", (10.0, -17.6), 0, {1: VBAT}, block="Pruebas", sym="TP", no_assembly=True)
part("TP8", "TP", "VSYS", (12.0, -17.6), 0, {1: VSYS}, block="Pruebas", sym="TP", no_assembly=True)

# ---------------------------------------------------------------------------------------- USB-C (J1)
USB = (26.15, 0.0)
part("J1", "USBC", "USB-C 16P", USB, 90,
     {"A1": GND, "B12": GND, "A12": GND, "B1": GND, "A4": VBUS, "B9": VBUS, "A9": VBUS, "B4": VBUS,
      "A5": "CC1", "B5": "CC2", "A6": "USB_DP_C", "B6": "USB_DP_C", "A7": "USB_DM_C", "B7": "USB_DM_C",
      "A8": None, "B8": None, "S1": GND},
     LC["USBC"], "TYPE-C-31-M-12", "USB",
     sym=dict(L=[("A4", "VBUS"), ("A9", "VBUS"), ("B4", "VBUS"), ("B9", "VBUS"), ("A5", "CC1"), ("B5", "CC2"),
                 ("A6", "D+"), ("B6", "D+"), ("A7", "D−"), ("B7", "D−"), ("A8", "SBU1"), ("B8", "SBU2")],
              R=[("A1", "GND"), ("A12", "GND"), ("B1", "GND"), ("B12", "GND"), ("S1", "SHIELD")]))
R("R16", "5k1", "CC1", GND, (20.4, 5.6), 90, "USB")
R("R17", "5k1", "CC2", GND, (21.5, 5.6), 90, "USB")
part("U6", "SOT23-6", "USBLC6-2SC6", (24.2, -8.8), 0,
     {1: "USB_DP_C", 6: "USB_DP_C", 3: "USB_DM_C", 4: "USB_DM_C", 2: GND, 5: VBUS}, LC["USBLC6"], block="USB",
     sym=dict(L=[(1, "IO1"), (6, "IO1"), (3, "IO2"), (4, "IO2")], R=[(5, "VBUS"), (2, "GND")]))
R("R18", "22R", "USB_DP_C", "USB_DP", (21.0, -5.6), 0, "USB")
R("R19", "22R", "USB_DM_C", "USB_DM", (21.0, -6.8), 0, "USB")
C("C26", "1u", VBUS, GND, (27.2, -8.6), 90, "USB")

# ---------------------------------------------------------------------------------------- IMU (U5)
IMU = (0.0, 3.0)
part("U5", "BNO", "BNO085", IMU, 0,
     {1: None, 2: GND, 3: "IMU_VDD", 4: "IMU_BOOTN", 5: "IMU_PS1", 6: "IMU_WAKE", 7: None, 8: None,
      9: "IMU_CAP", 10: GND, 11: "IMU_RST", 12: None, 13: None, 14: "IMU_INT", 15: "IMU_ENV_SCL",
      16: "IMU_ENV_SDA", 17: "IMU_MOSI", 18: "IMU_CS", 19: "IMU_SCK", 20: "IMU_MISO", 21: None, 22: None,
      23: None, 24: None, 25: GND, 26: "IMU_XOUT", 27: "IMU_XIN", 28: "IMU_VDD"},
     LC["BNO085"], "BNO085 (alt. BNO086)", "IMU",
     sym=dict(L=[(3, "VDD"), (28, "VDDIO"), (9, "CAP"), (4, "BOOTN"), (11, "NRST"), (5, "PS1"),
                 (6, "PS0/WAKE"), (10, "CLKSEL0"), (27, "XIN32"), (26, "XOUT32"), (2, "GND"), (25, "GND")],
              R=[(18, "H_CSN"), (19, "SCK/SCL"), (17, "MOSI/SA0"), (20, "MISO/SDA"), (14, "H_INTN"),
                 (15, "ENV_SCL"), (16, "ENV_SDA"), (1, "NC"), (7, "NC"), (8, "NC"), (12, "NC"), (13, "NC"),
                 (21, "NC"), (22, "NC"), (23, "NC"), (24, "NC")]))
part("Y1", "XTAL3215", "32,768 kHz 12,5 pF", (-3.0, 6.9), 0, {1: "IMU_XIN", 2: "IMU_XOUT"}, LC["XTAL"],
     "Q13FC13500004", "IMU", sym="XTAL")
C("C27", "22p", "IMU_XIN", GND, (-5.2, 8.6), 0, "IMU")
C("C28", "22p", "IMU_XOUT", GND, (-0.8, 8.6), 0, "IMU")
C("C29", "100n", "IMU_VDD", GND, (-5.6, 3.6), 90, "IMU")
C("C30", "100n", "IMU_VDD", GND, (-5.6, 5.8), 90, "IMU")
C("C31", "4u7", "IMU_VDD", GND, (-7.0, 4.6), 90, "IMU", "C0603")
C("C32", "100n", "IMU_CAP", GND, (-2.6, -0.6), 0, "IMU")
R("R20", "10k", "IMU_BOOTN", "IMU_VDD", (-5.6, 1.4), 0, "IMU")
R("R21", "10k", "IMU_PS1", "IMU_VDD", (-5.6, 0.2), 0, "IMU", note="PS1 = 1, PS0 = 1 → SPI")
R("R22", "10k", "IMU_PS1", GND, (-5.6, -1.0), 0, "IMU", dnp=True, note="I²C: montar R22/R23, quitar R21")
R("R23", "10k", "IMU_WAKE", GND, (-4.4, -2.2), 0, "IMU", dnp=True)
R("R24", "10k", "IMU_RST", "IMU_VDD", (-0.6, -2.0), 90, "IMU")
R("R25", "10k", "IMU_CS", "IMU_VDD", (2.4, 5.2), 90, "IMU")
R("R26", "10k", "IMU_ENV_SCL", "IMU_VDD", (1.4, -1.0), 90, "IMU")
R("R27", "10k", "IMU_ENV_SDA", "IMU_VDD", (2.6, -1.0), 90, "IMU")
R("R28", "4k7", "IMU_SCK", "IMU_VDD", (3.6, 5.2), 90, "IMU", dnp=True, note="pull-up I²C (sin montar)")
R("R29", "4k7", "IMU_MISO", "IMU_VDD", (4.8, 5.2), 90, "IMU", dnp=True)
part("Q3", "SOT23", "AO3401A", (3.6, 9.4), 0, {1: "IMU_PWR_N", 2: V3, 3: "IMU_VDD"}, LC["AO3401A"],
     block="IMU", sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]), note="alimentación del BNO (LOW = encendido)")
R("R30", "100k", "IMU_PWR_N", V3, (6.0, 9.4), 90, "IMU")

# ---------------------------------------------------------------------------------------- reed y batería
part("SW1", "WIRE", "REED (1)", (-1.27, -17.8), 0, {1: "REED_HI"}, block="Reed", sym="TP", no_assembly=True,
     note="reed 14 × 3,2 del suelo de la cápsula")
part("SW2", "WIRE", "REED (2)", (1.27, -17.8), 0, {1: "BAT_RAW"}, block="Reed", sym="TP", no_assembly=True)
R("R31", "100k", "REED", V3, (-1.6, -13.2), 90, "Reed", note="GPIO6: LOW = reed cerrado (cápsula en el soporte)")
C("C33", "10n 50V", "REED", GND, (-0.4, -13.2), 90, "Reed")
R("R32", "1M", VBAT, "BAT_ADC", (2.6, -12.8), 90, "Batería", note="divisor 1:2 → GPIO2 (ADC1_CH2)")
R("R33", "1M", "BAT_ADC", GND, (3.8, -12.8), 90, "Batería")
C("C34", "100n", "BAT_ADC", GND, (5.0, -12.8), 90, "Batería")

# ---------------------------------------------------------------------------------------- corte de batería (K1)
# Relé biestable de una bobina (Omron G6KU-2F-Y DC3, 5,2 mm). Sus dos polos en paralelo cortan el + de la batería.
#  · ENCENDER sin alimentación: al cerrarse el reed (cápsula en el soporte) o al llegar 5 V (Qi o USB), el pulso de
#    C40–C41 (≈ 40 ms) pasa por la bobina de K_A a K_B; Q11 cierra K_B a masa durante el pulso.
#  · APAGAR: el ESP32 pone GPIO23 a HIGH ~20 ms: Q13 lleva K_A a masa y Q14 lleva K_B a VBAT (bobina al revés);
#    Q12 anula Q11 para que no haya cortocircuito. Al abrirse el relé todo queda a 0 µA.
#  · Arranque suave: el relé cierra sobre Q10 (PMOS) apagado; C43/R51 lo encienden en ~0,1 s, así los contactos no
#    ven el pico de carga de los condensadores (el reed de la espalda se soldó por eso).
#  · Polaridad: se supone que el pulso K_A(+)→K_B(−) cierra los contactos NA (4 y 5). Si al probar es al revés, se
#    quita R40 y se monta R41 (contactos NC): no hace falta cambiar nada más.
part("K1", "RELAY", "G6KU-2F-Y DC3", (-11.5, 15.6), 90,
     {1: "K_A", 8: "K_B", 3: "BAT_RAW", 6: "BAT_RAW", 4: "RLY_NO", 5: "RLY_NO", 2: "RLY_NC", 7: "RLY_NC"},
     LC["G6KU"], "G6KU-2F-Y-TR DC3", "Corte",
     sym=dict(L=[(1, "BOBINA A"), (8, "BOBINA B")], R=[(3, "COM1"), (6, "COM2"), (4, "NA1"), (5, "NA2"),
                                                     (2, "NC1"), (7, "NC2")]))
R("R40", "0R", "RLY_NO", "BAT_SW", (-4.6, 16.0), 90, "Corte", fp="R0805", note="contactos NA (por defecto)")
R("R41", "0R", "RLY_NC", "BAT_SW", (-17.8, 14.6), 90, "Corte", fp="R0805", dnp=True,
  note="montar en lugar de R40 si la polaridad del relé es la contraria")
part("Q10", "SOT23", "AO3401A", (-19.0, 11.0), 0, {1: "SS_G", 2: "BAT_SW", 3: VBAT}, LC["AO3401A"], block="Corte",
     sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]), note="arranque suave tras el relé")
C("C43", "100n", "BAT_SW", "SS_G", (-16.0, 10.0), 0, "Corte")
R("R51", "1M", "SS_G", GND, (-16.0, 8.9), 0, "Corte")
part("D10", "SOT23", "BAT54C", (-18.8, -14.6), 0, {1: "REED_HI", 2: VIN5, 3: "RLY_P"}, LC["BAT54C"],
     block="Corte", sym=dict(L=[(1, "A1"), (2, "A2")], R=[(3, "K")]), note="reed o 5 V → pulso de encendido")
# pulso: el relé pide ≥ 10 ms con ≥ 2,25 V en la bobina (91 Ω) → 2 × 220 µF de polímero (τ ≈ 40 ms)
C("C40", "220u 6V3 polímero", "RLY_P", "K_A", (-23.2, 13.6), 90, "Corte", "TANT_B", lcsc=LC["220u"])
C("C41", "220u 6V3 polímero", "RLY_P", "K_A", (-26.6, 15.2), 90, "Corte", "TANT_B", lcsc=LC["220u"])
R("R44", "10k", "RLY_P", GND, (-17.6, -16.9), 0, "Corte", note="descarga del pulso")
R("R45", "10k", "RLY_P", "RLY_GB", (-15.7, -16.9), 0, "Corte")
R("R46", "100k", "RLY_GB", GND, (-13.8, -16.9), 0, "Corte")
part("Q11", "SOT23", "AO3400A", (-15.2, -14.6), 0, {1: "RLY_GB", 2: GND, 3: "K_B"}, LC["AO3400A"], block="Corte",
     sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]), note="K_B a masa durante el pulso de encendido")
part("Q12", "SOT23", "2N7002", (-11.6, -14.6), 0, {1: "RLY_OFF", 2: GND, 3: "RLY_GB"}, LC["2N7002"], block="Corte",
     sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]))
part("Q13", "SOT23", "AO3400A", (-8.0, -14.6), 0, {1: "RLY_OFF", 2: GND, 3: "K_A"}, LC["AO3400A"], block="Corte",
     sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]))
part("Q14", "SOT23", "AO3401A", (-4.4, -14.6), 0, {1: "RLY_PG", 2: VBAT, 3: "K_B"}, LC["AO3401A"], block="Corte",
     sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]))
part("Q15", "SOT23", "2N7002", (-7.4, -10.4), 0, {1: "RLY_OFF", 2: GND, 3: "RLY_PG"}, LC["2N7002"], block="Corte",
     sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]))
R("R47", "100k", "RLY_PG", VBAT, (-11.9, -16.9), 0, "Corte")
R("R48", "100k", "RLY_OFF", GND, (-10.0, -16.9), 0, "Corte", note="relé quieto durante el arranque del ESP32")
part("Q16", "SOT23", "2N7002", (-3.8, -10.4), 0, {1: "REED_G", 2: GND, 3: "REED"}, LC["2N7002"], block="Reed",
     sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]), note="reed (a + batería) → GPIO6 a 3,3 V")
R("R49", "100k", "REED_HI", "REED_G", (-8.1, -16.9), 0, "Reed")
R("R50", "1M", "REED_G", GND, (-6.2, -16.9), 0, "Reed")

# --------------------------------------------------------------------------------- colocación (X, Y, giro)
POS = {
    # Qi
    "U1": (-19.5, -3.0, 90), "L1": (-28.6, -5.2, 0), "L2": (-28.6, -2.0, 0),
    "C1": (-24.8, -8.4, 0), "C2": (-24.8, -10.8, 0), "C3": (-24.8, -13.2, 0),
    "C4": (-25.2, -3.0, 90), "C5": (-23.4, -3.0, 90),
    "C6": (-20.7, -7.3, 270), "C7": (-19.4, -7.6, 270), "C8": (-18.1, -7.3, 270),
    "C9": (-20.2, 1.4, 90), "C10": (-18.9, 1.7, 90), "C11": (-17.6, 1.4, 90),
    "C12": (-23.0, 0.9, 90), "C13": (-24.5, 0.9, 90), "C14": (-21.6, 1.2, 90),
    "C15": (-15.2, -7.6, 270), "C16": (-14.0, -7.3, 270), "C17": (-16.6, -7.3, 270),
    "R1": (-16.3, 1.6, 90), "R2": (-15.2, 1.6, 90), "R3": (-14.1, 1.6, 90), "RT1": (-16.0, -1.6, 90),
    "R4": (-12.8, -7.3, 90), "Q1": (-15.6, -11.0, 0), "Q2": (-11.0, -11.0, 0),
    # cargador y batería
    "U2": (-9.9, -3.0, 0), "C18": (-8.3, 0.4, 90), "C19": (-6.8, -4.3, 90), "C20": (-13.3, -3.3, 90),
    "R6": (-10.8, 0.4, 90), "R7": (-6.8, -1.8, 90), "RT2": (-13.2, -0.9, 0),
    "R8": (-10.6, -6.9, 90), "R9": (-9.5, -6.9, 90), "R10": (-8.4, -6.9, 90),
    "J2": (-22.6, 6.3, 270),
    # 3,3 V
    "U3": (3.0, -10.0, 0), "C21": (0.2, -10.0, 90), "C22": (6.0, -10.0, 90),
    # ESP32-C6
    "C23": (11.0, -15.6, 0), "C24": (13.8, -15.4, 0), "R11": (15.6, -15.4, 90), "C25": (16.8, -15.4, 90),
    "R12": (17.0, 1.2, 90), "R13": (18.2, 1.2, 90),
    "R14": (21.7, -9.4, 0), "R15": (21.7, -10.6, 0), "D1": (21.9, -12.0, 0),
    # USB
    "R16": (22.0, 6.4, 90), "R17": (23.2, 6.4, 90), "U6": (24.9, -8.0, 0),
    "R18": (21.7, -6.6, 0), "R19": (21.7, -7.8, 0), "C26": (24.8, -11.4, 0),
    # IMU
    "Y1": (-1.0, 7.4, 180), "C27": (-3.6, 7.4, 90), "C28": (1.6, 7.4, 90),
    "C29": (-4.6, 3.1, 0), "C30": (-4.4, 5.8, 0), "C31": (-6.4, 4.8, 90),
    "C32": (-0.6, -0.4, 0), "R20": (-4.6, 2.0, 0), "R21": (-4.6, 0.8, 0), "R22": (-4.6, -0.4, 0),
    "R23": (-2.6, -0.6, 0), "R24": (1.4, -0.6, 0), "R25": (4.0, 5.4, 90), "R26": (3.8, 0.6, 90),
    "R27": (4.9, 0.6, 90), "R28": (5.1, 5.4, 90), "R29": (6.2, 5.4, 90),
    "Q3": (6.2, 8.8, 0), "R30": (8.6, 8.8, 90),
    # reed, batería, pruebas
    "R31": (-1.6, -13.2, 90), "C33": (-0.4, -13.2, 90),
    "R32": (2.6, -13.2, 90), "R33": (3.8, -13.2, 90), "C34": (5.0, -13.2, 90),
}
for p in PARTS:
    if p["ref"] in POS:
        x, y, r = POS[p["ref"]]
        p["pos"], p["rot"] = (x, y), r

for p in PARTS:
    if p["fp"] in ("R0402",) and not p["lcsc"]:
        p["lcsc"] = LC.get(p["value"], "")

# =============================================================================== redes
NETS = []
for p in PARTS:
    for n in p["nets"].values():
        if n and n not in NETS:
            NETS.append(n)
NETS.sort(key=lambda n: (n not in (GND, V3, VSYS, VBAT, VBUS, VIN5), n))
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


def rrect_pts(step=5):
    hx, hy, r = PL / 2, PW / 2, PR
    pts = []
    for cx, cy, a0 in ((hx - r, hy - r, 0), (-hx + r, hy - r, 90), (-hx + r, -hy + r, 180), (hx - r, -hy + r, 270)):
        for k in range(0, 91, step):
            t = math.radians(a0 + k)
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    return pts


RRECT_K = [K(x, y) for x, y in rrect_pts()]


def check_placement():
    errs = []
    boxes = [(p["ref"], courtyard_abs(p)) for p in PARTS]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, ba = boxes[i]; b, bb = boxes[j]
            if ba[0] < bb[2] and bb[0] < ba[2] and ba[1] < bb[3] and bb[1] < ba[3]:
                ox = min(ba[2], bb[2]) - max(ba[0], bb[0]); oy = min(ba[3], bb[3]) - max(ba[1], bb[1])
                if ox > 0.02 and oy > 0.02:
                    errs.append("solape de patio %s–%s (%.2f × %.2f)" % (a, b, ox, oy))
    poly = [K(x, y) for x, y in outline_pts(5)]
    inner = [K(x, y) for x, y in outline_pts(5)]
    for ref, bb in boxes:
        samples = []
        for k in range(9):
            t = k / 8
            samples += [(bb[0] + t * (bb[2] - bb[0]), bb[1]), (bb[0] + t * (bb[2] - bb[0]), bb[3]),
                        (bb[0], bb[1] + t * (bb[3] - bb[1])), (bb[2], bb[1] + t * (bb[3] - bb[1]))]
        bad = set()
        for (x, y) in samples:
            if ref in bad:
                break
            if not point_in_poly(x, y, poly):
                errs.append("%s se sale de la placa en (%.2f, %.2f)" % (ref, x - 100, 100 - y)); bad.add(ref)
            else:
                tall = fp_of(next(p for p in PARTS if p["ref"] == ref)).height > 0.3
                d_lip = dist_to_poly(x, y, RRECT_K)
                d_any = dist_to_poly(x, y, poly)
                if tall and d_lip < LIP_BAND and ref != "J1":
                    errs.append("%s bajo el labio de la tapa (%.2f del borde)" % (ref, d_lip)); bad.add(ref)
                elif d_any < 0.3:
                    errs.append("%s a %.2f del borde" % (ref, d_any)); bad.add(ref)
    for p in PARTS:
        if p["ref"] in LID_POCKET:
            if fp_of(p).height > H_MAX + LID_POCKET[p["ref"]]:
                errs.append("%s no cabe ni con el rebaje de la tapa" % p["ref"])
            continue
        if fp_of(p).height > H_MAX:
            errs.append("%s demasiado alto: %.2f > %.2f" % (p["ref"], fp_of(p).height, H_MAX))
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


if __name__ == "__main__" and "--place" in sys.argv:
    for e in check_placement():
        print(e)
    sys.exit(0)
