"""AVO GIRTH · placa de la cincha REV B (ESP32-C3) — generador del proyecto KiCad 9.

REV B: ESP32-C3-MINI-1U-N4 (el C6-MINI-1U no está en JLCPCB), IMU LSM6DS3TR-C + MMC5983MA por I²C y corte de
batería con enclavamiento de MOSFET (sin relé). La REV A (ESP32-C6) está congelada en ../../PCB_REV_A_C6.

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
from custom_fp import lga14_st, mmc5983ma, test_pad, wire_pad   # noqa: E402
from fplib import load, emit, pad_poly, pad_center, pad_copper_layers, uid   # noqa: E402
from router import Router              # noqa: E402
from sexpr import Sym                  # noqa: E402

OUT = os.path.join(HERE, "..", "kicad")
os.makedirs(OUT, exist_ok=True)
REV, DATE = "B", "2026-10-29"
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
LID_POCKET = {}                                      # REV B: sin relé, no hace falta rebaje en la tapa
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
    "USBC": load("USB_C_Receptacle_HRO_TYPE-C-31-M-12.kicad_mod",
                 M3 + "Connector_USB.3dshapes/USB_C_Receptacle_HRO_TYPE-C-31-M-12.step", 3.3),
    "JST_SH2": load("JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.kicad_mod",
                    M3 + "Connector_JST.3dshapes/JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.step", 2.95),
    "MINI1U": load("ESP32-C3-MINI-1U.kicad_mod", "${KIPRJMOD}/../fuente/3d/ESP32-C3-MINI-1U.STEP", 2.6),
    "LGA14": lga14_st(),
    "MMC": mmc5983ma(),
    "WIRE": wire_pad("bobina / reed"),
    "TP": test_pad(1.0),
}
# vías térmicas de las QFN: taladro 0,3 (estándar JLCPCB) en lugar de 0,2
for k in ("RHL20", "RGT16"):
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


# --- piezas básicas (LCSC verificados en la lista de materiales; ver DOCS) -----------------------------
LC = {
    # resistencias y condensadores: todos «Basic» en JLCPCB salvo los C0G de resonancia del Qi y el NTC
    # (existencias y tipo consultados en el CI: out_stock/stock_jlc.json)
    "0R": "C17168", "22R": "C25092", "100R": "C25076", "330R": "C25104", "200R": "C25087", "1k": "C11702",
    "3k3": "C25890", "4k7": "C25900", "5k1": "C25905", "10k": "C25744", "20k": "C25765", "100k": "C25741",
    "1M": "C26083",
    "100n": "C1525", "1u": "C52923", "10n": "C15195", "22n": "C1532", "4u7": "C19666", "2u2": "C23630",
    "10u": "C96446", "10u6V3": "C19702", "22u": "C45783", "470n": "C1623",
    "100n C0G": "C97946", "47n C0G": "C21812", "2n2 C0G": "C51795", "1n C0G": "C1636",
    "NTC10k": "C77131", "AO3400A": "C20917", "2N7002": "C8545", "BAV70": "C68978",
    "AO3401A": "C15127", "USBLC6": "C7519", "LED": "C2286",
    "RT9080": "C841192", "BQ51013B": "C55663", "BQ24072": "C140288", "MINI1U": "C2911374",
    "LSM6DS3TRC": "C967633", "MMC5983MA": "C404329", "USBC": "C165948", "JST_SH2": "C160402",
}


def R(ref, val, n1, n2, pos, rot=0, block="", dnp=False, fp="R0402", note=""):
    lc = LC.get(val + "0805", "") if fp == "R0805" else LC.get(val.replace("Ω", ""), "")
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
R("R6", "3k3", "CHG_ISET", GND, (-11.6, -5.6), 0, "Cargador", note="I_carga = 890/3,3k ≈ 270 mA (0,54 C)")
R("R7", "3k3", "CHG_ILIM", GND, (-9.6, -4.6), 90, "Cargador", note="I_entrada = 1525/3,3k ≈ 462 mA (< 494 mA del Qi)")
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

# ---------------------------------------------------------------------------------------- ESP32-C3 (U4)
# ESP32-C3-MINI-1U-N4 (C2911374; alt. -H4 C3013922, 105 °C, misma memoria). Pines del módulo según el símbolo y la
# huella de Espressif (kicad-libraries). Huella idéntica en pads a la del C6-MINI-1U (origen desplazado 2 mm).
# Arranque (guía de diseño de Espressif, ESP32-C3): GPIO9 = 1 → arranque normal, 0 → descarga (con GPIO8 = 1);
# GPIO2: la hoja del módulo pide 1 en el arranque (la guía de diseño dice que no decide el modo pero recomienda
# pull-up): lleva SCL con 4,7 k a 3,3 V, siempre a 1 al arrancar. GPIO0–5 despiertan del sueño profundo; ADC1 = GPIO0–4.
MCU = (13.6, -7.0)
part("U4", "MINI1U", "ESP32-C3-MINI-1U-N4", MCU, 90,
     dict([(n, GND) for n in (1, 2, 11, 14) + tuple(range(36, 54))] +
          [(3, V3), (8, "EN"), (12, "IMU_INT"), (13, "REED"), (5, "I2C_SCL"), (6, "BAT_ADC"), (18, "CHG_PG"),
           (19, "PWR_HOLD"), (20, "I2C_SDA"), (21, "CHG_STAT"), (22, "LED"), (23, "BOOT"), (16, "QI_CHG"),
           (26, "USB_DM"), (27, "USB_DP"), (30, "U0RX"), (31, "U0TX")] +
          [(n, None) for n in (4, 7, 9, 10, 15, 17, 24, 25, 28, 29, 32, 33, 34, 35)]),
     LC["MINI1U"], "ESP32-C3-MINI-1U-N4 (alt. ESP32-C3-MINI-1U-H4 C3013922)", "ESP32-C3",
     sym=dict(L=[(3, "3V3"), (8, "EN"), (12, "IO0 IMU_INT"), (13, "IO1 REED"), (5, "IO2 SCL"),
                 (6, "IO3 BAT_ADC"), (18, "IO4 CHG_PG"), (19, "IO5 PWR_HOLD"), (20, "IO6 SDA"), (21, "IO7 CHG_STAT"),
                 (22, "IO8 LED"), (23, "IO9 BOOT"), (16, "IO10 QI_CHG")] +
                [(n, "NC") for n in (4, 7, 9, 10, 15, 17, 24, 25, 28, 29, 32, 33, 34, 35)],
              R=[(26, "IO18 D-"), (27, "IO19 D+"), (30, "IO20 RXD0"), (31, "IO21 TXD0")] +
                [(n, "GND") for n in (1, 2, 11, 14) + tuple(range(36, 54))]))
C("C23", "22u 10V", V3, GND, (11.2, -15.4), 0, "ESP32-C3", "C0805")
C("C24", "100n", V3, GND, (13.4, -15.2), 0, "ESP32-C3")
R("R11", "10k", "EN", V3, (16.2, -15.2), 90, "ESP32-C3")
C("C25", "1u", "EN", GND, (17.4, -15.2), 90, "ESP32-C3")
R("R12", "10k", "BOOT", V3, (21.0, -2.0), 0, "ESP32-C3", note="GPIO9 strapping: 1 = arranque normal")
R("R13", "10k", "LED", V3, (21.0, -3.2), 0, "ESP32-C3", note="GPIO8 strapping: 1 en el arranque (LED apagado)")
R("R15", "1k", "LED", "LED_K", (21.0, -11.4), 0, "ESP32-C3")
part("D1", "LED0603", "LED rojo", (21.4, -12.8), 180, {1: "LED_K", 2: V3}, LC["LED"], "KT-0603R", "ESP32-C3",
     sym="LED", note="activo a nivel bajo (GPIO8 = 0 enciende)")
part("TP1", "TP", "EN", (4.0, -17.2), 0, {1: "EN"}, block="Pruebas", sym="TP", no_assembly=True)
part("TP2", "TP", "BOOT", (6.0, -17.2), 0, {1: "BOOT"}, block="Pruebas", sym="TP", no_assembly=True)
part("TP3", "TP", "GND", (8.0, -17.2), 0, {1: GND}, block="Pruebas", sym="TP", no_assembly=True)
part("TP4", "TP", "TXD0", (4.0, -15.2), 0, {1: "U0TX"}, block="Pruebas", sym="TP", no_assembly=True,
     note="UART0 de la ROM: registro y recuperación por puerto serie")
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

# ---------------------------------------------------------------------------------------- IMU (U5, U7)
# LSM6DS3TR-C (acelerómetro + giroscopio, LGA-14L 2,5 × 3) y MMC5983MA (magnetómetro, LGA-16 3 × 3) en el mismo I²C
# (GPIO6 SDA, GPIO2 SCL, 4,7 k a 3,3 V). Mismas 9 magnitudes brutas que envía el protocolo de la cincha (IMU_FMT_9AXIS).
# La huella del LSM6 admite también el LSM6DSV16X (C5267406, misma distribución de pines; el firmware detecta cuál).
#  LSM6: SA0 a GND → 0x6A; CS a 3,3 V → I²C; SDx/SCx a GND (sin concentrador auxiliar); OCS_Aux/SDO_Aux sin conectar.
#  MMC5983MA: 0x30; SPI_CS a VDDIO → I²C; CAP con 10 µF; INT sin conectar (lectura por sondeo).
IMU = (0.0, 3.0)
part("U5", "LGA14", "LSM6DS3TR-C", IMU, 0,
     {1: GND, 2: GND, 3: GND, 4: "IMU_INT", 5: V3, 6: GND, 7: GND, 8: V3, 9: None, 10: None, 11: None, 12: V3,
      13: "I2C_SCL", 14: "I2C_SDA"},
     LC["LSM6DS3TRC"], "LSM6DS3TR-C (alt. LSM6DSV16XTR C5267406)", "IMU",
     sym=dict(L=[(8, "VDD"), (5, "VDDIO"), (12, "CS"), (1, "SDO/SA0"), (2, "SDx"), (3, "SCx"), (6, "GND"), (7, "GND")],
              R=[(13, "SCL"), (14, "SDA"), (4, "INT1"), (9, "INT2"), (10, "OCS_Aux"), (11, "SDO_Aux")]))
C("C27", "100n", V3, GND, (-2.6, 3.0), 90, "IMU", note="VDD del LSM6")
C("C28", "100n", V3, GND, (2.6, 3.0), 90, "IMU", note="VDDIO del LSM6")
R("R20", "4k7", "I2C_SDA", V3, (4.0, 1.0), 90, "IMU", note="pull-up I²C (GPIO6)")
R("R21", "4k7", "I2C_SCL", V3, (5.1, 1.0), 90, "IMU", note="pull-up I²C; también fija GPIO2 = 1 en el arranque")
part("U7", "MMC", "MMC5983MA", (-8.0, 10.0), 0,
     {1: "I2C_SCL", 2: V3, 3: None, 4: V3, 5: None, 6: None, 7: None, 8: None, 9: GND, 10: "MAG_CAP", 11: GND,
      12: None, 13: V3, 14: None, 15: None, 16: "I2C_SDA"},
     LC["MMC5983MA"], "MMC5983MA", "IMU",
     sym=dict(L=[(2, "VDD"), (13, "VDDIO"), (4, "SPI_CS"), (10, "CAP"), (9, "GND"), (11, "GND")],
              R=[(1, "SCL"), (16, "SDA"), (15, "INT"), (5, "SPI_SDO"), (3, "NC"), (6, "NC"), (7, "NC"), (8, "NC"),
                 (12, "NC"), (14, "NC")]))
C("C29", "1u", V3, GND, (-10.6, 10.0), 90, "IMU", note="VDD del MMC5983MA")
C("C30", "10u 6V3", "MAG_CAP", GND, (-8.0, 7.4), 0, "IMU", "C0603", lcsc=LC["10u6V3"],
  note="CAP (SET/RESET): >= 10 µF de baja ESR, junto al pin 10")
C("C31", "100n", V3, GND, (-5.4, 10.0), 90, "IMU", note="VDDIO del MMC5983MA")

# ---------------------------------------------------------------------------------------- reed y batería
part("SW1", "WIRE", "REED (1)", (-1.27, -17.8), 0, {1: "REED_HI"}, block="Reed", sym="TP", no_assembly=True,
     note="reed 14 × 3,2 del suelo de la cápsula")
part("SW2", "WIRE", "REED (2)", (1.27, -17.8), 0, {1: "BAT_RAW"}, block="Reed", sym="TP", no_assembly=True)
R("R31", "100k", "REED", V3, (-1.6, -13.2), 90, "Reed", note="GPIO1: LOW = reed cerrado (cápsula en el soporte)")
C("C33", "10n 50V", "REED", GND, (-0.4, -13.2), 90, "Reed")
R("R32", "1M", VBAT, "BAT_ADC", (2.6, -12.8), 90, "Batería", note="divisor 1:2 → GPIO3 (ADC1_CH3)")
R("R33", "1M", "BAT_ADC", GND, (3.8, -12.8), 90, "Batería")
C("C34", "100n", "BAT_ADC", GND, (5.0, -12.8), 90, "Batería")

# ---------------------------------------------------------------------------------------- corte de batería (Q10)
# Enclavamiento con MOSFET (sustituye al relé de la REV A). Q10 (PMOS) une la celda (BAT_RAW) con VBAT del cargador;
# su puerta tiene 1 MΩ a la fuente (apagado: Vgs = 0, solo la fuga del MOSFET). Q11 (NMOS de umbral bajo) la lleva a
# masa cuando su puerta PWR_G supera ~1,45 V. PWR_G (C41 2,2 µF + R42 1 MΩ) se carga por tres caminos con diodos:
#  · REED: al cerrarse el reed, C40 (10 µF) da un impulso (D11) que mantiene PWR_G ≥ 1,45 V unos 2,5 s: el ESP32
#    arranca y pone PWR_HOLD. Es por flanco: con el reed cerrado el sistema se puede apagar igual (apagado remoto).
#  · PWR_HOLD (GPIO5, D10 A2): el firmware lo mantiene a 1. Si el ESP32 se reinicia, C41 sostiene PWR_G > 1,45 V
#    unos 1,3 s, más de lo que tarda en volver a poner PWR_HOLD. Para apagar: PWR_HOLD = 0 → corte en ~3 s.
#  · VIN5 (Qi o USB, D10 A1): con la base puesta el corte está siempre cerrado: nunca queda bloqueado al cargar.
# Batería agotada (protección de la celda abierta): con la base, el diodo interno de Q10 deja pasar la precarga del
# BQ24072 hacia la celda; cuando sube la tensión, Q10 conduce del todo.
part("Q10", "SOT23", "AO3401A", (-19.0, 11.0), 0, {1: "PWR_PG", 2: "BAT_RAW", 3: VBAT}, LC["AO3401A"], block="Corte",
     sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]), note="interruptor de la batería (PMOS)")
R("R40", "1M", "BAT_RAW", "PWR_PG", (-19.0, 13.6), 0, "Corte", note="Q10 apagado por defecto")
part("Q11", "SOT23", "AO3400A", (-15.6, 11.0), 0, {1: "PWR_G", 2: GND, 3: "PWR_PG"}, LC["AO3400A"], block="Corte",
     sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]), note="Vth 0,65–1,45 V")
C("C41", "2u2", "PWR_G", GND, (-15.6, 14.0), 0, "Corte", "C0603", note="sostiene el corte durante un reinicio")
R("R42", "1M", "PWR_G", GND, (-13.6, 14.0), 0, "Corte")
part("D10", "SOT23", "BAV70", (-12.0, 11.0), 0, {1: VIN5, 2: "PWR_HOLD", 3: "PWR_G"}, LC["BAV70"], block="Corte",
     sym=dict(L=[(1, "A1"), (2, "A2")], R=[(3, "K")]), note="5 V de carga o PWR_HOLD → PWR_G")
part("D11", "SOT23", "BAV70", (-12.0, 14.6), 0, {1: "REED_PULSE", 2: "REED_PULSE", 3: "PWR_G"}, LC["BAV70"],
     block="Corte", sym=dict(L=[(1, "A1"), (2, "A2")], R=[(3, "K")]), note="impulso del reed → PWR_G")
C("C40", "10u 6V3", "REED_HI", "REED_PULSE", (-9.0, 14.6), 0, "Corte", "C0603", lcsc=LC["10u6V3"],
  note="impulso de encendido al cerrarse el reed")
R("R41", "1M", "REED_PULSE", GND, (-9.0, 12.8), 0, "Corte")
R("R43", "100k", "PWR_HOLD", GND, (-10.0, 16.6), 0, "Corte", note="PWR_HOLD a 0 mientras arranca el ESP32")
part("Q16", "SOT23", "2N7002", (-3.8, -10.4), 0, {1: "REED_G", 2: GND, 3: "REED"}, LC["2N7002"], block="Reed",
     sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]), note="reed (a + batería) → GPIO1 a 3,3 V")
R("R49", "100k", "REED_HI", "REED_G", (-8.1, -16.9), 0, "Reed")
R("R50", "1M", "REED_G", GND, (-6.2, -16.9), 0, "Reed")

# --------------------------------------------------------------------------------- colocación (X, Y, giro)
POS = {
    # Qi
    "U1": (-19.5, -3.0, 90), "L1": (-28.6, -5.2, 0), "L2": (-28.6, -2.0, 0),
    "C1": (-25.2, -8.4, 0), "C2": (-25.2, -10.8, 0), "C3": (-25.2, -13.2, 0),
    "C4": (-25.2, -3.0, 90), "C5": (-23.4, -3.0, 90),
    "C6": (-22.4, -9.4, 270), "C7": (-20.6, -9.6, 270), "C8": (-19.4, -9.4, 270),
    "C9": (-20.2, 3.0, 90), "C10": (-18.9, 3.3, 90), "C11": (-17.6, 3.0, 90),
    "C12": (-23.0, 0.9, 90), "C13": (-24.5, 0.9, 90), "C14": (-21.6, 1.2, 90),
    "C15": (-21.3, -11.9, 0), "C16": (-18.9, -11.9, 0), "C17": (-16.6, -7.3, 270),
    "R1": (-16.3, 1.6, 90), "R2": (-15.2, 1.6, 90), "R3": (-14.1, 1.6, 90), "RT1": (-16.0, -1.6, 90),
    "R4": (-12.8, -7.3, 90), "Q1": (-15.6, -11.0, 0), "Q2": (-11.0, -11.0, 0),
    # cargador y batería
    "U2": (-9.9, -3.0, 0), "C18": (-8.3, 0.4, 90), "C19": (-6.8, -4.3, 90), "C20": (-13.3, -3.3, 90),
    "R6": (-10.8, 0.4, 90), "R7": (-6.8, -1.8, 90), "RT2": (-13.2, -0.9, 0),
    "R8": (-10.6, -6.9, 90), "R9": (-9.5, -6.9, 90), "R10": (-8.4, -6.9, 90),
    "J2": (-24.2, 6.3, 270),
    # 3,3 V
    "U3": (3.0, -10.0, 0), "C21": (0.2, -10.0, 90), "C22": (6.0, -10.0, 90),
    # ESP32-C3
    "C23": (11.0, -15.6, 0), "C24": (13.8, -15.4, 0), "R11": (15.6, -15.4, 90), "C25": (16.8, -15.4, 90),
    "R12": (17.0, 1.2, 90), "R13": (18.2, 1.2, 90),
    "R15": (21.7, -10.6, 0), "D1": (21.9, -12.0, 0),
    # USB
    "R16": (22.0, 6.4, 90), "R17": (23.2, 6.4, 90), "U6": (24.9, -8.0, 0),
    "R18": (21.7, -6.6, 0), "R19": (21.7, -7.8, 0), "C26": (24.8, -11.4, 0),
    # IMU
    "U7": (-5.0, 9.6, 0), "C29": (-7.4, 9.6, 90), "C31": (-5.0, 12.0, 0), "C30": (-5.0, 7.0, 0),
    # corte de batería
    "Q10": (-19.0, 11.0, 0), "Q11": (-15.6, 11.0, 0), "D10": (-12.2, 11.0, 0), "R40": (-19.0, 13.8, 0),
    "C41": (-15.6, 14.2, 0), "R42": (-13.2, 14.2, 90), "D11": (-10.6, 14.6, 0), "C40": (-7.6, 14.6, 90),
    "R41": (-7.6, 17.2, 0), "R43": (-12.6, 17.6, 0),
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


def pin_name(p, num):
    s = p["sym"]
    if isinstance(s, dict):
        for k, nm in list(s.get("L", [])) + list(s.get("R", [])):
            if str(k) == str(num):
                return nm
        return str(num)
    if s == "LED":
        return {"1": "K", "2": "A"}.get(str(num), str(num))
    return str(num)


# pins left open get the net name KiCad gives them in the schematic ("unconnected-(REF-PIN-PadN)") → parity holds
for p in PARTS:
    nums = []
    for pd in FP[p["fp"]].pads:
        if pd.num and pd.num not in nums and pd.kind != "np_thru_hole":
            nums.append(pd.num)
    for num in nums:
        if p["nets"].get(num) is None:
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
    errs = check_placement()
    for e in errs:
        print(e)
    sys.exit(1 if errs else 0)
