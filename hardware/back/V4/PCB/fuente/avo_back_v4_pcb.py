"""AVO BACK V4 · placa de la espalda (ESP32-S3) — generador del proyecto KiCad 9.

Un solo origen de datos (piezas, redes, posiciones) genera el esquema, la placa, las reglas, la lista de piezas para
JLCPCB, las comprobaciones de colocación y pcb_mecanica.json (pivotes, pisadores y contactos del fondo para el CAD).
Coordenadas de diseño = las de la carcasa V4 (CAD/avo_back_v4_freecad.py): X del cuello a la cola, Y lateral,
vista desde la tapa. En KiCad: x = X, y = 100 − Y. El contorno sale del CAD (pcb_contorno_v4.json).

REV B (30/10/2026): sin Qi ni Hall. Alimentación por 3 contactos en el fondo de la cápsula (tornillos M2 pasantes):
  SYS y BAT en la cola (donde estaba el reed) y GND aparte. Soporte del chaleco = puente SYS–BAT (encendido); base de
  carga = cargador externo entre BAT y GND. Cargador BQ24072 solo para el USB-C del taller (camino de potencia).
Bloques: batería con PTC · protección de polaridad del contacto SYS · TVS en los contactos expuestos · 3,3 V principal
  TLV75733P (1 A) · 3,3 V del ZED RT9080 con EN (corte físico del receptor) · ESP32-S3-MINI-1U-N8 · USB-C · microSD
  (SDMMC 4 bits, alimentación conmutada) · conexión a la URTK1.2 (UART1 + UART2 + PPS + RESET).
Uso:  python avo_back_v4_pcb.py --place   (comprueba la colocación)
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from custom_fp import test_pad   # noqa: E402
from fplib import Footprint, Pad, circle, load, rect_lines   # noqa: E402

OUT = os.path.join(HERE, "..", "kicad")
os.makedirs(OUT, exist_ok=True)
NAME = "AVO_BACK_V4_PCB"
REV, DATE = "B", "2026-10-30"
THICK = 1.0


def K(X, Y):
    return (round(X, 4), round(100 - Y, 4))


# =============================================================================== mecánica (CAD V4)
CADJ = json.load(open(os.path.join(HERE, "pcb_contorno_v4.json"), encoding="utf-8"))
Z_PCB_TOP = CADJ["z_cara_inferior"] + CADJ["espesor"]
ZONAS = CADJ["zonas"]


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
    P = []
    for w in CADJ["contorno"]:
        for s in w["segmentos"]:
            if s["t"] == "L":
                P.append(("line", tuple(s["a"]), tuple(s["b"])))
            else:
                P.append(("arc", tuple(s["a"]), tuple(s["m"]), tuple(s["b"])))
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


def pivot_hole(d=2.2):
    pads = [Pad("", "np_thru_hole", "circle", 0, 0, d, d, drill=d, layers=["*.Cu", "*.Mask"])]
    g = [circle(0, 0, d / 2 + 0.3, "F.CrtYd", 0.05), circle(0, 0, d / 2 + 0.2, "F.SilkS", 0.12)]
    return Footprint("AVO_Pivote_NPTH_D%.1f" % d, pads, g, "smd board_only exclude_from_pos_files exclude_from_bom", None,
                     "Agujero del pivote de centrado (base)", 0.0)


def keepout_disc(r):
    """Zona sin componentes (pisador de la tapa o anillo del separador): solo patio y serigrafía."""
    g = [circle(0, 0, r, "F.CrtYd", 0.05), circle(0, 0, r - 0.15, "F.SilkS", 0.12)]
    return Footprint("AVO_Zona_Libre_R%.1f" % r, [], g, "smd board_only exclude_from_pos_files exclude_from_bom", None,
                     "Zona sin componentes (apoyo mecánico)", 0.0)


def pads_2x4():
    """8 pads pasantes 2 × 4 (paso 2,54) para el mazo de la URTK1.2 (hilos soldados o tira de pines acodada)."""
    pads = []
    for i in range(8):
        col, row = i % 2, i // 2
        pads.append(Pad(str(i + 1), "thru_hole", "rect" if i == 0 else "circle", (col - 0.5) * 2.54, (row - 1.5) * 2.54,
                        1.6, 1.6, drill=1.0, layers=["*.Cu", "*.Mask"]))
    g = rect_lines(-2.7, -5.2, 2.7, 5.2, "F.CrtYd", 0.05) + rect_lines(-2.55, -5.05, 2.55, 5.05, "F.SilkS", 0.12)
    return Footprint("AVO_URTK_Pads_2x04_P2.54mm", pads, g, "through_hole", None, "Conexión a la URTK1.2 (8 hilos)", 0.0)


def contact_m2():
    """Contacto del fondo: tornillo M2 avellanado (inox A2) desde fuera de la base + tuerca M2 sobre la placa.
    Taladro metalizado Ø2,3, corona Ø4,6 en las dos caras (apoyo de la tuerca arriba y de la junta tórica abajo)."""
    pads = [Pad("1", "thru_hole", "circle", 0, 0, 4.6, 4.6, drill=2.3, layers=["*.Cu", "*.Mask"])]
    g = [circle(0, 0, 2.9, "F.CrtYd", 0.05), circle(0, 0, 2.6, "F.SilkS", 0.12), circle(0, 0, 2.9, "B.CrtYd", 0.05)]
    return Footprint("AVO_Contacto_M2_Tornillo", pads, g, "through_hole", None,
                     "Contacto pogo del fondo (tornillo M2 × 5 + tuerca DIN 934)", 1.8)


S3 = load("ESP32-S3-MINI-1U.kicad_mod", "${KIPRJMOD}/../fuente/3d/ESP32-S3-MINI-1U.STEP", 2.6)
# patio: cuerpo 15,4 + 0,15 (el de la librería, ±8, deja 0,3 mm más; el borde de cobre se comprueba aparte)
S3.graphics = [g for g in S3.graphics if not (len(g) > 1 and any(isinstance(x, list) and x[0] == "layer" and "CrtYd" in str(x[1]) for x in g))]
S3.graphics += rect_lines(-7.85, -7.85, 7.85, 7.85, "F.CrtYd", 0.05)
FP = {
    "R0402": load("R_0402_1005Metric.kicad_mod", M3 + "Resistor_SMD.3dshapes/R_0402_1005Metric.step", 0.4),
    "C0402": load("C_0402_1005Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0402_1005Metric.step", 0.6),
    "C0603": load("C_0603_1608Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0603_1608Metric.step", 0.9),
    "C0805": load("C_0805_2012Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0805_2012Metric.step", 1.35),
    "C1206": load("C_1206_3216Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_1206_3216Metric.step", 1.8),
    "F1206": load("Fuse_1206_3216Metric.kicad_mod", M3 + "Fuse.3dshapes/Fuse_1206_3216Metric.step", 1.1),
    "LED0603": load("LED_0603_1608Metric.kicad_mod", M3 + "LED_SMD.3dshapes/LED_0603_1608Metric.step", 0.8),
    "SOT23": load("SOT-23.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23.step", 1.1),
    "SOT23-5": load("SOT-23-5.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23-5.step", 1.45),
    "SOT23-6": load("SOT-23-6.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23-6.step", 1.45),
    "RGT16": load("VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm_ThermalVias.kicad_mod",
                  M3 + "Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step", 1.0),
    "USBC": load("USB_C_Receptacle_HRO_TYPE-C-31-M-12.kicad_mod",
                 M3 + "Connector_USB.3dshapes/USB_C_Receptacle_HRO_TYPE-C-31-M-12.step", 3.3),
    "JST_SH2": load("JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.kicad_mod",
                    M3 + "Connector_JST.3dshapes/JST_SH_SM02B-SRSS-TB_1x02-1MP_P1.00mm_Horizontal.step", 2.95),
    "MICROSD": load("microSD_HC_Hirose_DM3AT-SF-PEJM5.kicad_mod",
                    M3 + "Connector_Card.3dshapes/microSD_HC_Hirose_DM3AT-SF-PEJM5.step", 1.6),
    "SOD323": load("D_SOD-323.kicad_mod", M3 + "Diode_SMD.3dshapes/D_SOD-323.step", 1.1),
    "CONTACT_M2": contact_m2(),
    "MINI1U": S3,
    "URTK8": pads_2x4(),
    "TP": test_pad(1.0),
    "PIVOT": pivot_hole(2.2),
    "PAD_LID": keepout_disc(2.5),
    "RING": keepout_disc(4.6),
}
for k in ("RGT16",):
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


# códigos LCSC: existencias, precio y tipo consultados en el CI (out_stock/stock_jlc.json, 29/10/2026)
LC = {
    "0R": "C17168", "22R": "C25092", "200R": "C25087", "330R": "C25104", "1k": "C11702", "1k5": "C25867", "2k": "C4109",
    "4k7": "C25900", "5k1": "C25905", "10k": "C25744", "20k": "C25765", "100k": "C25741", "1M": "C26083",
    "100n": "C1525", "1u": "C52923", "10n": "C15195", "22n": "C1532", "4u7": "C19666", "2u2": "C23630",
    "10u": "C96446", "22u": "C45783", "47u": "C16780", "470n": "C1623", "220n": "C16772",
    "100n C0G": "C97946", "47n C0G": "C21812", "2n2 C0G": "C51795", "1n C0G": "C1636",
    "NTC10k": "C77131", "AO3401A": "C15127", "AO3400A": "C20917", "2N7002": "C8545", "USBLC6": "C7519", "LED": "C2286",
    "RT9080": "C841192", "TLV75733P": "C485517", "BQ51013B": "C55663", "BQ24072": "C140288", "MINI1U": "C2980299",
    "USBC": "C165948", "JST_SH2": "C160402", "MICROSD": "C114218", "PTC": "C20802", "DRV5032FA": "C140921", "TVS": "C2827694",
}


def R(ref, val, n1, n2, pos=(0, 0), rot=0, block="", dnp=False, fp="R0402", note=""):
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, LC.get(val, ""), block=block, sym="R", dnp=dnp, note=note)


def C(ref, val, n1, n2, pos=(0, 0), rot=0, block="", fp="C0402", dnp=False, lcsc=None, note=""):
    key = val.split()[0] + (" C0G" if "C0G" in val else "")
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, lcsc if lcsc is not None else LC.get(key, ""),
         block=block, sym="C", dnp=dnp, note=note)


GND, V3, VSYS, VBAT, VBUS, VIN5, VZED, VSD = "GND", "+3V3", "VSYS", "VBAT", "VBUS", "VIN5", "+3V3_ZED", "+3V3_SD"
TP = lambda ref, label, net, note="": part(ref, "TP", label, (0, 0), 0, {1: net}, block="Pruebas", sym="TP",
                                           no_assembly=True, note=note)

# ---------------------------------------------------------------------------------------- cargador (U2)
part("U2", "RGT16", "BQ24072RGTR", (0, 0), 0,
     {1: "CHG_TS", 2: VBAT, 3: VBAT, 4: GND, 5: "CHG_EN2", 6: GND, 7: "CHG_PG", 8: GND, 9: "CHG_STAT",
      10: VSYS, 11: VSYS, 12: "CHG_ILIM", 13: VBUS, 14: None, 15: GND, 16: "CHG_ISET", 17: GND},
     LC["BQ24072"], "BQ24072RGTR", "Cargador",
     sym=dict(L=[(13, "IN"), (4, "CE"), (6, "EN1"), (5, "EN2"), (16, "ISET"), (12, "ILIM"), (14, "TMR"),
                 (15, "TD"), (1, "TS")],
              R=[(10, "OUT"), (11, "OUT"), (2, "BAT"), (3, "BAT"), (7, "PGOOD"), (9, "CHG"), (8, "VSS"), (17, "EP")]))
C("C18", "1u", VBUS, GND, block="Cargador")
C("C19", "10u 25V", VSYS, GND, block="Cargador", fp="C0603")
C("C20", "10u 25V", VBAT, GND, block="Cargador", fp="C0603")
C("C35", "47u 6V3", VSYS, GND, block="Cargador", fp="C0805", note="reserva de VSYS para los picos de radio y del ZED")
R("R6", "2k", "CHG_ISET", GND, block="Cargador", note="I_carga = 890/2k ≈ 445 mA (0,22 C de 2000 mAh)")
R("R7", "2k", "CHG_ILIM", GND, block="Cargador", note="I_entrada = 1525/2k ≈ 760 mA (USB-C del taller)")
part("RT2", "R0402", "NTC 10k B3380", (0, 0), 0, {1: "CHG_TS", 2: GND}, LC["NTC10k"], "NCP15XH103F03RC", "Cargador", sym="R")
R("R8", "100k", "CHG_EN2", VSYS, block="Cargador", note="EN2 = 1, EN1 = 0: límite por ILIM")
R("R9", "100k", "CHG_PG", V3, block="Cargador")
R("R10", "100k", "CHG_STAT", V3, block="Cargador")

# ---------------------------------------------------------------------------------------- batería
part("J2", "JST_SH2", "BATERÍA 1S", (0, 0), 0, {1: "BAT_IN", 2: GND, "MP": GND}, LC["JST_SH2"],
     "SM02B-SRSS-TB (JST SH 1,0)", "Batería", sym=dict(L=[(1, "+"), (2, "−")], R=[("MP", "MP")]),
     note="pin 1 = + · la 654060 trae PH2.0: cambiar la clavija a SH 1,0 y comprobar la polaridad antes de enchufar")
part("F1", "F1206", "PTC 1,5 A", (0, 0), 0, {1: "BAT_IN", 2: "BAT_F"}, LC["PTC"], "SMD1206P150TF", "Batería", sym="R",
     note="fusible rearmable entre la celda y el contacto BAT (la celda lleva además su PCM)")
part("Q3", "SOT23", "AO3401A", (0, 0), 0, {1: "BAT_G", 2: VBAT, 3: "SYS_IN"}, LC["AO3401A"], block="Batería",
     sym=dict(L=[(1, "G")], R=[(3, "D"), (2, "S")]),
     note="polaridad del contacto SYS (PMOS: D al contacto, S a VBAT); deja pasar la carga por USB hacia la celda")
# contactos del fondo (tornillo M2 avellanado de acero inoxidable desde fuera + tuerca M2 sobre la placa)
for ref, net, lab, nt in (("P1", "SYS_IN", "CONTACTO SYS", "puente SYS–BAT en el soporte del chaleco = encendido"),
                          ("P2", "BAT_F", "CONTACTO BAT", "+ de la celda (tras F1): puente en el chaleco, cargador en la base"),
                          ("P3", GND, "CONTACTO GND", "solo para la base de carga (lejos de BAT)")):
    part(ref, "CONTACT_M2", lab, (0, 0), 0, {1: net}, block="Contactos", sym="TP", no_assembly=True, note=nt)
part("D2", "SOD323", "TVS 5 V", (0, 0), 0, {1: "SYS_IN", 2: GND}, LC["TVS"], "PESD5V0S1BA", "Contactos",
     sym=dict(L=[(1, "K")], R=[(2, "A")]), note="ESD en el contacto SYS")
part("D3", "SOD323", "TVS 5 V", (0, 0), 0, {1: "BAT_F", 2: GND}, LC["TVS"], "PESD5V0S1BA", "Contactos",
     sym=dict(L=[(1, "K")], R=[(2, "A")]), note="ESD en el contacto BAT")
R("R30", "10k", "BAT_G", GND, block="Batería")
R("R32", "1M", VBAT, "BAT_ADC", block="Batería", note="divisor 1:2 → GPIO2 (ADC1_CH1)")
R("R33", "1M", "BAT_ADC", GND, block="Batería")
C("C34", "100n", "BAT_ADC", GND, block="Batería")

# ---------------------------------------------------------------------------------------- 3,3 V principal (U3) y del ZED (U7)
part("U3", "SOT23-5", "TLV75733PDBVR", (0, 0), 0, {1: VSYS, 2: GND, 3: VSYS, 4: None, 5: V3}, LC["TLV75733P"],
     "TLV75733PDBVR", "3V3", sym=dict(L=[(1, "IN"), (3, "EN"), (2, "GND")], R=[(5, "OUT"), (4, "NC")]),
     note="1 A: ESP32-S3 (picos de radio ≈ 0,35 A) + microSD")
C("C21", "10u 25V", VSYS, GND, block="3V3", fp="C0603")
C("C22", "22u 10V", V3, GND, block="3V3", fp="C0805")
part("U7", "SOT23-5", "RT9080-33GJ5", (0, 0), 0, {1: VSYS, 2: GND, 3: "ZED_EN", 4: None, 5: VZED}, LC["RT9080"],
     "RT9080-33GJ5", "ZED", sym=dict(L=[(1, "VIN"), (3, "EN"), (2, "GND")], R=[(5, "VOUT"), (4, "NC")]),
     note="regulador propio del ZED: el pico de arranque no toca el 3,3 V del ESP32; EN = 0 corta el receptor")
C("C60", "10u 25V", VSYS, GND, block="ZED", fp="C0603")
C("C61", "22u 10V", VZED, GND, block="ZED", fp="C0805")
C("C62", "47u 6V3", VZED, GND, block="ZED", fp="C0805")
R("R60", "100k", "ZED_EN", GND, block="ZED", note="ZED apagado mientras arranca el ESP32")

# ---------------------------------------------------------------------------------------- ESP32-S3 (U4)
GPIO = {  # pad del módulo: (GPIO, red)
    4: ("IO0", "BOOT"), 5: ("IO1", None), 6: ("IO2", "BAT_ADC"), 7: ("IO3", None),
    8: ("IO4", "ZED_PPS"), 9: ("IO5", "ZED_TX1"), 10: ("IO6", "S3_TX1"), 11: ("IO7", "ZED_TX2"), 12: ("IO8", "S3_TX2"),
    13: ("IO9", "S3_ZRST"), 14: ("IO10", "ZED_EN"), 15: ("IO11", "LED"),
    16: ("IO12", "SD_CLK0"), 17: ("IO13", "SD_CMD"), 18: ("IO14", "SD_D0"), 19: ("IO15", "SD_D1"), 20: ("IO16", "SD_D2"),
    21: ("IO17", "SD_D3"), 22: ("IO18", "SD_CD"), 23: ("IO19 D-", "USB_DM"), 24: ("IO20 D+", "USB_DP"), 25: ("IO21", "SD_PWR_N"),
    26: ("IO26", None), 27: ("IO47", None), 28: ("IO33", None), 29: ("IO34", None), 30: ("IO48", None),
    31: ("IO35", None), 32: ("IO36", None), 33: ("IO37", None), 34: ("IO38", "CHG_PG"), 35: ("IO39", "CHG_STAT"),
    36: ("IO40", None), 37: ("IO41", "GPIO41"), 38: ("IO42", None), 39: ("TXD0", "U0TX"), 40: ("RXD0", "U0RX"),
    41: ("IO45", None), 44: ("IO46", None), 45: ("EN", "EN"), 3: ("3V3", V3),
}
GND_PADS = (1, 2, 42, 43) + tuple(range(46, 66))
u4nets = {n: GND for n in GND_PADS}
u4nets.update({k: v[1] for k, v in GPIO.items()})
part("U4", "MINI1U", "ESP32-S3-MINI-1U-N8", (0, 0), 0, u4nets, LC["MINI1U"], "ESP32-S3-MINI-1U-N8", "ESP32-S3",
     sym=dict(L=[(k, v[0] + (" " + v[1] if v[1] and v[1] not in (V3,) else "")) for k, v in sorted(GPIO.items()) if k <= 25 or k == 3],
              R=[(k, v[0] + (" " + v[1] if v[1] else "")) for k, v in sorted(GPIO.items()) if 25 < k] +
                [(n, "GND") for n in GND_PADS]),
     note="antena externa por el conector del módulo → antena FPC de 2,4 GHz pegada al techo del cuello")
C("C24", "22u 10V", V3, GND, block="ESP32-S3", fp="C0805")
C("C25", "100n", V3, GND, block="ESP32-S3")
C("C26", "1u", V3, GND, block="ESP32-S3")
R("R11", "10k", "EN", V3, block="ESP32-S3")
C("C27", "1u", "EN", GND, block="ESP32-S3", note="EN: RC 10 k / 1 µF (guía de diseño de Espressif)")
R("R15", "1k", "LED", "LED_K", block="ESP32-S3")
part("D1", "LED0603", "LED rojo", (0, 0), 0, {1: "LED_K", 2: V3}, LC["LED"], "KT-0603R", "ESP32-S3",
     sym="LED", note="activo a nivel bajo (GPIO11 = 0 enciende)")

# ---------------------------------------------------------------------------------------- USB-C (J1)
part("J1", "USBC", "USB-C 16P", (0, 0), 0,
     {"A1": GND, "B12": GND, "A12": GND, "B1": GND, "A4": VBUS, "B9": VBUS, "A9": VBUS, "B4": VBUS,
      "A5": "CC1", "B5": "CC2", "A6": "USB_DP_C", "B6": "USB_DP_C", "A7": "USB_DM_C", "B7": "USB_DM_C",
      "A8": None, "B8": None, "S1": GND},
     LC["USBC"], "TYPE-C-31-M-12", "USB",
     sym=dict(L=[("A4", "VBUS"), ("A9", "VBUS"), ("B4", "VBUS"), ("B9", "VBUS"), ("A5", "CC1"), ("B5", "CC2"),
                 ("A6", "D+"), ("B6", "D+"), ("A7", "D−"), ("B7", "D−"), ("A8", "SBU1"), ("B8", "SBU2")],
              R=[("A1", "GND"), ("A12", "GND"), ("B1", "GND"), ("B12", "GND"), ("S1", "SHIELD")]),
     note="programación, registro y carga con la tapa abierta (la carcasa sigue estanca)")
R("R16", "5k1", "CC1", GND, block="USB")
R("R17", "5k1", "CC2", GND, block="USB")
part("U6", "SOT23-6", "USBLC6-2SC6", (0, 0), 0,
     {1: "USB_DP_C", 6: "USB_DP_C", 3: "USB_DM_C", 4: "USB_DM_C", 2: GND, 5: VBUS}, LC["USBLC6"], block="USB",
     sym=dict(L=[(1, "IO1"), (6, "IO1"), (3, "IO2"), (4, "IO2")], R=[(5, "VBUS"), (2, "GND")]))
R("R18", "22R", "USB_DP_C", "USB_DP", block="USB")
R("R19", "22R", "USB_DM_C", "USB_DM", block="USB")
C("C28", "1u", VBUS, GND, block="USB")

# ---------------------------------------------------------------------------------------- microSD (J3), SDMMC 4 bits
# Hirose DM3AT-SF-PEJM5 (empuje-empuje). 1 DAT2 · 2 CD/DAT3 · 3 CMD · 4 VDD · 5 CLK · 6 VSS · 7 DAT0 · 8 DAT1 ·
# 9/10 interruptor de tarjeta (uno a GND, el otro a SD_CD con pull-up: el firmware lee el nivel) · 11 carcasa.
part("J3", "MICROSD", "microSD DM3AT", (0, 0), 0,
     {1: "SD_D2", 2: "SD_D3", 3: "SD_CMD", 4: VSD, 5: "SD_CLK", 6: GND, 7: "SD_D0", 8: "SD_D1", 9: "SD_CD", 10: GND, 11: GND},
     LC["MICROSD"], "DM3AT-SF-PEJM5", "microSD",
     sym=dict(L=[(4, "VDD"), (5, "CLK"), (3, "CMD"), (7, "DAT0"), (8, "DAT1"), (1, "DAT2"), (2, "CD/DAT3")],
              R=[(6, "VSS"), (9, "DET"), (10, "DET_COM"), (11, "SHELL")]),
     note="pines 9/10 según la huella de KiCad: comprobar con la hoja de Hirose antes del pedido")
part("Q4", "SOT23", "AO3401A", (0, 0), 0, {1: "SD_PWR_N", 2: V3, 3: VSD}, LC["AO3401A"], block="microSD",
     sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]), note="alimentación de la tarjeta: GPIO21 = 0 la enciende")
R("R40", "100k", "SD_PWR_N", V3, block="microSD", note="tarjeta apagada mientras arranca el ESP32")
C("C40", "10u 25V", VSD, GND, block="microSD", fp="C0603")
C("C41", "100n", VSD, GND, block="microSD")
for i, n in enumerate(("SD_CMD", "SD_D0", "SD_D1", "SD_D2", "SD_D3")):
    R("R%d" % (41 + i), "10k", n, VSD, block="microSD")
R("R46", "22R", "SD_CLK0", "SD_CLK", block="microSD", note="serie del reloj (amortigua el flanco)")
R("R47", "100k", "SD_CD", V3, block="microSD")

# ---------------------------------------------------------------------------------------- URTK1.2 (ZED-F9P) por 8 hilos
# Señales según la serigrafía de la cara de componentes de la URTK1.2 (fotos del usuario, 29/10/2026):
# 3V3 · GND · TX/MISO + RX/MOSI (UART1, compartidos con SPI) · TX2 + RX2 (UART2) · PPS · RST. EL MAZO SE HACE SEGÚN EL
# PINOUT VERIFICADO CON POLÍMETRO (ver DOCS/INTEGRACION_GNSS.md); la placa no depende de la posición de los pads.
part("J4", "URTK8", "URTK1.2 (8 hilos)", (0, 0), 0,
     {1: VZED, 2: GND, 3: "ZED_TX1_C", 4: "ZED_RX1", 5: "ZED_TX2_C", 6: "ZED_RX2", 7: "ZED_PPS_C", 8: "ZED_RST"},
     block="ZED", sym=dict(L=[(1, "3V3"), (2, "GND"), (3, "TX/MISO"), (4, "RX/MOSI"), (5, "TX2"), (6, "RX2"), (7, "PPS"), (8, "RST")], R=[]),
     no_assembly=True, note="8 pads pasantes: hilos soldados al mazo de la URTK1.2")
R("R50", "1k", "S3_TX1", "ZED_RX1", block="ZED", note="serie: limita la alimentación parásita del ZED apagado por su RX")
R("R51", "1k", "S3_TX2", "ZED_RX2", block="ZED")
R("R52", "1k", "S3_ZRST", "ZED_RST", block="ZED", note="RESET_N del ZED (GPIO9 en colector abierto)")
R("R53", "330R", "ZED_TX1_C", "ZED_TX1", block="ZED")
R("R54", "330R", "ZED_TX2_C", "ZED_TX2", block="ZED")
R("R55", "330R", "ZED_PPS_C", "ZED_PPS", block="ZED", note="PPS → GPIO4 (captura MCPWM para la marca de tiempo)")

# ---------------------------------------------------------------------------------------- pruebas y mecánica
TP("TP1", "EN", "EN"); TP("TP2", "BOOT", "BOOT", "GPIO0 a GND al arrancar = descarga")
TP("TP3", "GND", GND); TP("TP4", "TXD0", "U0TX"); TP("TP5", "RXD0", "U0RX"); TP("TP6", "3V3", V3)
TP("TP7", "VBAT", VBAT); TP("TP8", "VSYS", VSYS); TP("TP9", "3V3_ZED", VZED); TP("TP10", "GPIO41", "GPIO41")
for i in (1, 2):
    part("H%d" % i, "PIVOT", "PIVOTE", (0, 0), 0, {}, block="Mecánica", sym=None, no_assembly=True,
         note="agujero NPTH Ø2,2 del pivote de centrado de la base")
for i in (1, 2):
    part("MP%d" % i, "PAD_LID", "PISADOR", (0, 0), 0, {}, block="Mecánica", sym=None, no_assembly=True,
         note="apoyo del pisador de la tapa: Ø5 sin componentes")
for i in (1, 2):
    part("MR%d" % i, "RING", "ANILLO", (0, 0), 0, {}, block="Mecánica", sym=None, no_assembly=True,
         note="anillo impreso entre la PCB y la URTK1.2 alrededor del separador: Ø9,2 sin componentes")

# --------------------------------------------------------------------------------- colocación (X, Y, giro) — coordenadas de la carcasa
POS = json.load(open(os.path.join(HERE, "colocacion_v4.json"), encoding="utf-8"))
for p in PARTS:
    if p["ref"] in POS:
        x, y, r = POS[p["ref"]]
        p["pos"], p["rot"] = (x, y), r
MECH = [p for p in PARTS if p["fp"] in ("PIVOT", "PAD_LID", "RING")]
# zonas rectangulares sin componentes (carcasa): (nombre, X0, Y0, X1, Y1)
_j2 = next(p for p in PARTS if p["ref"] == "J2")["pos"]
KEEPOUT_RECTS = [("clavija de la batería delante de J2", 60.0, _j2[1] - 2.6, _j2[0] - 3.4, _j2[1] + 2.6)]

# =============================================================================== redes
NETS = []
for p in PARTS:
    for n in p["nets"].values():
        if n and n not in NETS:
            NETS.append(n)
NETS.sort(key=lambda n: (n not in (GND, V3, VSYS, VBAT, VBUS, VIN5, VZED, VSD), n))


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


def courtyard_casing(p):
    x0, y0, x1, y1 = courtyard_abs(p)
    return x0, 100 - y1, x1, 100 - y0


def zone_limit(x, y):
    """altura máxima de componente sobre la cara superior de la PCB en (x, y) de la carcasa"""
    z = ZONAS["resto"]["zmax"]
    if x < ZONAS["bajo_URTK"]["x1"]:
        z = min(z, ZONAS["bajo_URTK"]["zmax"])
    b = ZONAS["bajo_J2_L"]
    if b["x0"] <= x <= b["x1"] and b["y"][0] <= y <= b["y"][1]:
        z = min(z, b["zmax"])
    t = ZONAS["topes_L"]
    if t["x0"] <= x <= t["x1"] and t["y"][0] <= y <= t["y"][1]:
        z = min(z, t["zmax"])
    return z - Z_PCB_TOP


CIRC = {"PAD_LID": 2.5, "RING": 4.6, "CONTACT_M2": 2.9, "PIVOT": 1.4}   # patios circulares (radio)


def check_placement():
    errs = []
    boxes = [(p["ref"], courtyard_abs(p)) for p in PARTS]
    for i in range(len(boxes)):
        for j in range(i + 1, len(boxes)):
            a, ba = boxes[i]; b, bb = boxes[j]
            pa = next(q for q in PARTS if q["ref"] == a); pb = next(q for q in PARTS if q["ref"] == b)
            if pa["fp"] == "PIVOT" or pb["fp"] == "PIVOT":
                if pa["fp"] in ("PAD_LID", "RING") or pb["fp"] in ("PAD_LID", "RING"):
                    continue
            if pa["fp"] in CIRC and pb["fp"] in CIRC:
                (ax_, ay_), (bx_, by_) = kpos(pa), kpos(pb)
                if math.hypot(ax_ - bx_, ay_ - by_) >= CIRC[pa["fp"]] + CIRC[pb["fp"]]:
                    continue
            if ba[0] < bb[2] and bb[0] < ba[2] and ba[1] < bb[3] and bb[1] < ba[3]:
                ox = min(ba[2], bb[2]) - max(ba[0], bb[0]); oy = min(ba[3], bb[3]) - max(ba[1], bb[1])
                if ox > 0.02 and oy > 0.02:
                    if (pa["fp"] in CIRC or pb["fp"] in CIRC):
                        # zona circular: solape real con el disco
                        q, z = (pa, pb) if pa["fp"] in CIRC else (pb, pa)
                        r = CIRC[q["fp"]]
                        zx0, zy0, zx1, zy1 = courtyard_abs(z); cx, cy = kpos(q)
                        dx = max(zx0 - cx, 0, cx - zx1); dy = max(zy0 - cy, 0, cy - zy1)
                        if math.hypot(dx, dy) >= r:
                            continue
                    errs.append("solape de patio %s–%s (%.2f × %.2f)" % (a, b, ox, oy))
    for nm, x0, y0, x1, y1 in KEEPOUT_RECTS:
        for ref, bb in boxes:
            c0, c1, c2, c3 = bb[0], 100 - bb[3], bb[2], 100 - bb[1]
            if c0 < x1 and x0 < c2 and c1 < y1 and y0 < c3 and next(q for q in PARTS if q["ref"] == ref)["fp"] not in ("PIVOT", "PAD_LID", "RING"):
                errs.append("%s en la zona libre: %s" % (ref, nm))
    poly = [K(x, y) for x, y in outline_pts(3)]
    for ref, bb in boxes:
        p = next(q for q in PARTS if q["ref"] == ref)
        samples = []
        if p["fp"] == "CONTACT_M2":
            cx, cy = kpos(p)
            samples = [(cx + 2.9 * math.cos(math.radians(a)), cy + 2.9 * math.sin(math.radians(a))) for a in range(0, 360, 15)]
        for k in range(9 if p["fp"] != "CONTACT_M2" else 0):
            t = k / 8
            samples += [(bb[0] + t * (bb[2] - bb[0]), bb[1]), (bb[0] + t * (bb[2] - bb[0]), bb[3]),
                        (bb[0], bb[1] + t * (bb[3] - bb[1])), (bb[2], bb[1] + t * (bb[3] - bb[1]))]
        bad = False
        h = fp_of(p).height
        for (x, y) in samples:
            if p["fp"] in ("PAD_LID", "RING"):
                break
            if not point_in_poly(x, y, poly):
                errs.append("%s se sale de la placa en (%.2f, %.2f)" % (ref, x, 100 - y)); bad = True; break
            if dist_to_poly(x, y, poly) < 0.25:
                errs.append("%s a %.2f del borde" % (ref, dist_to_poly(x, y, poly))); bad = True; break
        if bad:
            continue
        # altura: muestreo del patio contra las zonas de la carcasa
        hmin = min(zone_limit(x, 100 - y) for (x, y) in samples + [((bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2)])
        if h > hmin + 1e-6:
            errs.append("%s demasiado alto: %.2f > %.2f" % (ref, h, hmin))
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


def mecanica():
    """pivotes, pisadores, anillos y contactos del fondo → CAD (pcb_mecanica.json)"""
    g = lambda pref: [list(p["pos"]) for p in PARTS if p["ref"].startswith(pref) and p["fp"] in ("PIVOT", "PAD_LID", "RING")]
    contactos = {p["ref"]: dict(pos=list(p["pos"]), red=p["nets"]["1"]) for p in PARTS if p["fp"] == "CONTACT_M2"}
    env = []
    for p in PARTS:
        h = fp_of(p).height
        if h > 0:
            x0, y0, x1, y1 = courtyard_casing(p)
            env.append([p["ref"], round(x0, 3), round(y0, 3), round(x1, 3), round(y1, 3), h])
    return dict(pivotes=g("H"), pisadores=g("MP"), anillos=g("MR"), contactos=contactos, envolventes=env,
                nota_envolventes="patio × altura de la huella (conservador); la comprobación fina usa el STEP de KiCad",
                origen="generado por PCB/fuente/avo_back_v4_pcb.py (colocacion_v4.json)")


if __name__ == "__main__" and "--place" in sys.argv:
    errs = check_placement()
    for e in errs:
        print(e)
    print("piezas:", len(PARTS), "· errores:", len(errs))
    sys.exit(1 if errs else 0)
