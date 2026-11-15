"""AVO GIRTH · placa de la cincha · REV D (ESP32-C6 + LSM6DSV16X + MMC5983MA + ADS1292, ECG) — generador KiCad 9.

Derivada de la REV C (MAX30003 + BNO085, sin existencias en JLCPCB el 15/11/2026). Sensores con existencias en JLCPCB:
  - ECG: TI ADS1292 (24 bits, ganancia programable, RLD al electrodo de referencia, reloj interno), AVDD propio de 3,3 V;
  - IMU: ST LSM6DSV16X (acelerómetro + giróscopo con fusión SFLP en el chip) y MEMSIC MMC5983MA (magnetómetro), I²C.
Batería de 1000 mAh (DOCS/CONSUMO_BATERIA.md): carga a ≈ 445 mA.
Placa de 40 × 26 mm, 4 capas, 1,0 mm, todos los componentes en F; In1 = GND; F, In2 y B = señales.
Coordenadas de diseño: origen en el centro, X a la derecha, Y hacia arriba, vista desde F. En KiCad: x = 100 + X, y = 100 − Y.
Firmware: AVO GIRTH 0.6.0 (firmware/girth/V0_6_0). Mismo formato por radio que la 0.5.0 (lotes fmt 0, 1 y 2).
Uso:  python avo_girth_revd_pcb.py --place   (comprueba la colocación)
"""
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from custom_fp import ads1292_vqfn32, lga14_st, mmc5983ma, test_pad, wire_pad   # noqa: E402
from fplib import Footprint, Pad, circle, load, rect_lines   # noqa: E402
from sexpr import Sym   # noqa: E402

OUT = os.path.join(HERE, "..", "kicad")
os.makedirs(OUT, exist_ok=True)
NAME = "AVO_GIRTH_REVD_PCB"
REV, DATE = "D", "2026-11-15"
THICK = 1.0
W, H, CORNER_R = 40.0, 26.0, 2.0
HOLE_XY, HOLE_D, HOLE_KEEP = (17.8, 10.8), 2.2, 2.2    # 4 taladros M2 (tornillos a la tapa)
Z_MAX_F = 2.6                                         # altura máxima de componente en F (hueco hasta la tapa)


def K(X, Y):
    return (round(100 + X, 4), round(100 - Y, 4))


# =============================================================================== contorno (rectángulo 40 × 26 con R2)
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
    w, h, r = W / 2, H / 2, CORNER_R
    s = math.sqrt(0.5) * r
    P = []
    corners = [((w, -h + r), (w, h - r)), ((w - r, h), (-w + r, h)), ((-w, h - r), (-w, -h + r)), ((-w + r, -h), (w - r, -h))]
    centers = [(w - r, h - r), (-w + r, h - r), (-w + r, -h + r), (w - r, -h + r)]
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


C6 = load("ESP32-C6-MINI-1U.kicad_mod", "${KIPRJMOD}/../fuente/3d/ESP32-C6-MINI-1U.STEP", 2.6)
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
    "RGT16": load("VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm_ThermalVias.kicad_mod",
                  M3 + "Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step", 1.0),
    "SOD323": load("D_SOD-323.kicad_mod", M3 + "Diode_SMD.3dshapes/D_SOD-323.step", 1.1),
    "XTAL3215": load("Crystal_SMD_3215-2Pin_3.2x1.5mm.kicad_mod",
                     M3 + "Crystal.3dshapes/Crystal_SMD_3215-2Pin_3.2x1.5mm.step", 0.9),
    "TANT_B": load("CP_EIA-3528-21_Kemet-B.kicad_mod", M3 + "Capacitor_Tantalum_SMD.3dshapes/CP_EIA-3528-21_Kemet-B.step", 2.1),
    "MINI1U": C6,
    "LGA14": lga14_st(),
    "MMC": mmc5983ma(),
    "ADS": ads1292_vqfn32(),
    "TP": test_pad(1.0),
    "WIRE": wire_pad("(hilo)", drill=0.8, d=1.5),
    "HOLE": npth_hole(HOLE_D, HOLE_KEEP, "Taladro del tornillo M2 de la tapa"),
}
for k in ("RGT16",):
    for p in FP[k].pads:
        if p.kind == "thru_hole":
            p.drill, p.w, p.h = 0.3, 0.5, 0.5
from sexpr import find as _find   # noqa: E402
FP["XTAL3215"].graphics = [g for g in FP["XTAL3215"].graphics if _find(g, "layer")[1] != "F.SilkS"]

# =============================================================================== piezas y redes
PARTS = []


def part(ref, fp, value, pos, rot, nets, lcsc="", mpn="", block="", sym=None, dnp=False, note="", jlc_rot=0,
         no_assembly=False):
    PARTS.append(dict(ref=ref, fp=fp, value=value, pos=pos, rot=rot, nets={str(k): v for k, v in nets.items()},
                      lcsc=lcsc, mpn=mpn, block=block, sym=sym, dnp=dnp, note=note, jlc_rot=jlc_rot,
                      no_assembly=no_assembly))


# códigos LCSC (casco V5 y cincha REV A/B consultados en el CI; nuevos de la REV C: MAX30003CTI+ C1519515,
# RT9080-18GJ5 C426476, SiT1533AI-H4-DCC C367058, BNO085 C5189642, 47 kΩ C25792, 1 nF C0G C53547). El CI vuelve a consultarlos.
LC = {
    "0R": "C17168", "22R": "C25092", "1k": "C11702", "2k2": "C25879", "3k4": "C4940", "3k6": "C25891",
    "10k": "C25744", "47k": "C25792", "100k": "C25741", "1M": "C26083",
    "100n": "C1525", "1u": "C52923", "10n": "C15195", "22p": "C1555", "4u7": "C19666", "10u": "C96446", "22u": "C45783",
    "1n C0G": "C53547", "100n C0G": "C97946",
    "NTC10k": "C77131", "USBLC6": "C7519", "LED": "C2286", "PTC": "C20802", "TVS": "C2827694",
    "RT9080-33": "C841192", "RT9080-18": "C426476", "BQ24072": "C140288", "MINI1U": "C20627095",
    "LSM6DSV16X": "C5267406", "MMC5983MA": "C404329", "ADS1292": "C544416", "2k": "C4109", "4n7 C0G": "C85980", "1n5 C0G": "C668348", "1u TANT": "C7192",
}


def R(ref, val, n1, n2, pos=(0, 0), rot=0, block="", dnp=False, fp="R0402", note=""):
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, LC.get(val, ""), block=block, sym="R", dnp=dnp, note=note)


def C(ref, val, n1, n2, pos=(0, 0), rot=0, block="", fp="C0402", dnp=False, lcsc=None, note=""):
    key = val.split()[0] if val.split()[-1] != "C0G" else val.split()[0] + " C0G"
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, lcsc if lcsc is not None else LC.get(key, ""),
         block=block, sym="C", dnp=dnp, note=note)


GND, V3, VA, VSYS, VBAT, VBUS = "GND", "+3V3", "+3V3A", "VSYS", "VBAT", "VBUS"
V18 = VA   # (nombre heredado de la REV C en las herramientas)
TP = lambda ref, label, net, note="": part(ref, "TP", label, (0, 0), 0, {1: net}, block="Pruebas", sym="TP",
                                           no_assembly=True, note=note)

# ---------------------------------------------------------------------------------------- pogo de carga (3, por hilos)
# Mismo conector magnético de 3 contactos que la REV 5.9.1 (STEP real del usuario), en el fondo de la cápsula y
# sellado con epoxi; 3 hilos cortos a estos pads. Contacto 1 = 5 V de la base · 2 = GND · 3 = DET (el soporte de la
# cincha une 2 y 3: la cápsula sabe que está montada).
for ref, net, lab, nt in (("P1", "POGO_5V", "CARGA 5V", "contacto 1: 5 V de la base de carga"),
                          ("P2", GND, "CARGA GND", "contacto 2: masa"),
                          ("P3", "POGO_DET", "CARGA DET", "contacto 3: a GND en el soporte (cápsula montada)")):
    part(ref, "WIRE", lab, (0, 0), 0, {1: net}, block="Pogo carga", sym="TP", no_assembly=True, note=nt)
part("F2", "F1206", "PTC 1,5 A", (0, 0), 0, {1: "POGO_5V", 2: VBUS}, LC["PTC"], "SMD1206P150TF", "Pogo carga", sym="R",
     note="fusible rearmable del contacto de 5 V expuesto")
part("D2", "SOD323", "TVS 5 V", (0, 0), 0, {1: "POGO_5V", 2: GND}, LC["TVS"], "PESD5V0S1BA", "Pogo carga",
     sym=dict(L=[(1, "K")], R=[(2, "A")]), note="ESD en el contacto de 5 V")
part("D3", "SOD323", "TVS 5 V", (0, 0), 0, {1: "POGO_DET", 2: GND}, LC["TVS"], "PESD5V0S1BA", "Pogo carga",
     sym=dict(L=[(1, "K")], R=[(2, "A")]), note="ESD en el contacto DET")
R("R20", "1k", "POGO_DET", "DET", block="Pogo carga", note="serie del contacto DET → GPIO6 (como la REV 5.9.1)")
R("R21", "100k", "DET", V3, block="Pogo carga", note="DET = 1 suelta, 0 en el soporte")

# ---------------------------------------------------------------------------------------- cargador (U2)
part("U2", "RGT16", "BQ24072RGTR", (0, 0), 0,
     {1: "CHG_TS", 2: VBAT, 3: VBAT, 4: GND, 5: "CHG_EN2", 6: GND, 7: None, 8: GND, 9: "CHG_STAT",
      10: VSYS, 11: VSYS, 12: "CHG_ILIM", 13: VBUS, 14: None, 15: GND, 16: "CHG_ISET", 17: GND},
     LC["BQ24072"], "BQ24072RGTR", "Cargador",
     sym=dict(L=[(13, "IN"), (4, "CE"), (6, "EN1"), (5, "EN2"), (16, "ISET"), (12, "ILIM"), (14, "TMR"),
                 (15, "TD"), (1, "TS")],
              R=[(10, "OUT"), (11, "OUT"), (2, "BAT"), (3, "BAT"), (7, "PGOOD"), (9, "CHG"), (8, "VSS"), (17, "EP")]))
C("C18", "1u", VBUS, GND, block="Cargador")
C("C19", "10u", VSYS, GND, block="Cargador", fp="C0603")
C("C20", "10u", VBAT, GND, block="Cargador", fp="C0603")
R("R6", "2k", "CHG_ISET", GND, block="Cargador", note="I_carga = 890/2k ≈ 445 mA (0,45 C de 1000 mAh; ≈ 2,5 h)")
R("R7", "2k2", "CHG_ILIM", GND, block="Cargador", note="I_entrada = 1525/2,2k ≈ 690 mA (carga + placa; base de ≥ 1 A)")
part("RT2", "R0402", "NTC 10k B3380", (0, 0), 0, {1: "CHG_TS", 2: GND}, LC["NTC10k"], "NCP15XH103F03RC", "Cargador",
     sym="R", note="NTC en la cara F, encima de la celda")
R("R8", "100k", "CHG_EN2", VSYS, block="Cargador", note="EN2 = 1, EN1 = 0: límite por ILIM")
R("R10", "10k", "CHG_STAT", V3, block="Cargador",
  note="CHG → GPIO8 (pin de arranque: 10 k a 3V3 como pide Espressif; cargando = 0, solo importa con BOOT pulsado)")

# ---------------------------------------------------------------------------------------- batería (hilos soldados)
part("J2", "WIRE", "BAT +", (0, 0), 0, {1: "BAT_IN"}, block="Batería", sym="TP", no_assembly=True,
     note="hilo + de la celda de 1000 mAh (603450): soldado, sin conector")
part("J6", "WIRE", "BAT -", (0, 0), 0, {1: GND}, block="Batería", sym="TP", no_assembly=True, note="hilo − de la celda")
part("F1", "F1206", "PTC 1,5 A", (0, 0), 0, {1: "BAT_IN", 2: VBAT}, LC["PTC"], "SMD1206P150TF", "Batería", sym="R",
     note="fusible rearmable entre la celda y el cargador (la celda lleva además su PCM)")
R("R32", "1M", VBAT, "BAT_ADC", block="Batería", note="divisor 1:2 → GPIO5 (el firmware usa 2,00 por defecto)")
R("R33", "1M", "BAT_ADC", GND, block="Batería")
C("C34", "100n", "BAT_ADC", GND, block="Batería")

# ---------------------------------------------------------------------------------------- 3,3 V (U3)
part("U3", "SOT23-5", "RT9080-33GJ5", (0, 0), 0, {1: VSYS, 2: GND, 3: VSYS, 4: None, 5: V3}, LC["RT9080-33"],
     "RT9080-33GJ5", "3V3", sym=dict(L=[(1, "VIN"), (3, "EN"), (2, "GND")], R=[(5, "VOUT"), (4, "NC")]),
     note="600 mA, Iq 2 µA: ESP32-C6 (picos de radio ≈ 0,35 A) + BNO085 + MAX30003")
C("C21", "10u", VSYS, GND, block="3V3", fp="C0603")
C("C22", "22u", V3, GND, block="3V3", fp="C0805")

# ---------------------------------------------------------------------------------------- ESP32-C6 (U4)
# pad del módulo: (GPIO, red). Mismos GPIO que el XIAO ESP32-C6 (firmware 0.5.0 sin cambios).
GPIO = {
    12: ("IO0", None), 13: ("IO1", "IMU_INT2"), 5: ("IO2", "IMU_INT1"), 6: ("IO3", None),
    9: ("IO4", "ECG_RESET"), 10: ("IO5", "BAT_ADC"), 15: ("IO6", "DET"), 16: ("IO7", "ECG_DRDY"),
    22: ("IO8", "CHG_STAT"), 23: ("IO9", "BOOT"), 19: ("IO14", None), 20: ("IO15", "LED_K"),
    17: ("IO12 D-", "USB_DM"), 18: ("IO13 D+", "USB_DP"), 24: ("IO18", "ECG_MOSI"), 25: ("IO19", "ECG_SCK"),
    26: ("IO20", "ECG_MISO"), 27: ("IO21", "ECG_START"), 28: ("IO22", "MAG_INT"), 29: ("IO23", "I2C_SDA"),
    30: ("IO17", "ECG_CS"), 31: ("IO16", "I2C_SCL"), 8: ("EN", "EN"), 3: ("3V3", V3),
}
NC_PADS = (4, 7, 21, 32, 33, 34, 35)
GND_PADS = (1, 2, 11, 14) + tuple(n for n in range(36, 54) if n != 51)
u4nets = {n: GND for n in GND_PADS}
u4nets.update({n: None for n in NC_PADS})
u4nets.update({k: v[1] for k, v in GPIO.items()})
# pad de esquina 51 (GND de anclaje, el módulo ya va a masa por el EPAD 49 y los pads 1, 2, 11, 14, 36–48, 50, 52, 53):
# queda sin conectar porque las salidas de los pads 24/25 lo encierran (sin pista ni vía posible sin vía en pad)
u4nets[51] = None
part("U4", "MINI1U", "ESP32-C6-MINI-1U-H4", (0, 0), 0, u4nets, LC["MINI1U"], "ESP32-C6-MINI-1U-H4 (alt. -N4)", "ESP32-C6",
     sym=dict(L=[(k, v[0] + (" " + v[1] if v[1] and v[1] != V3 else "")) for k, v in sorted(GPIO.items()) if k <= 23] +
                [(n, "NC") for n in NC_PADS],
              R=[(k, v[0] + (" " + v[1] if v[1] else "")) for k, v in sorted(GPIO.items()) if k > 23] +
                [(n, "GND") for n in GND_PADS]),
     note="antena FPC de 2,4 GHz en el U.FL del módulo, pegada a la tapa de la cápsula")
C("C24", "22u", V3, GND, block="ESP32-C6", fp="C0805")
C("C25", "100n", V3, GND, block="ESP32-C6")
R("R11", "10k", "EN", V3, block="ESP32-C6")
C("C27", "1u", "EN", GND, block="ESP32-C6", note="EN: RC 10 k / 1 µF (guía de diseño de Espressif)")
R("R12", "10k", "BOOT", V3, block="ESP32-C6", note="GPIO9 alto = arranque normal; a GND con TP2 = descarga")
R("R14", "1k", V3, "LED_A", block="ESP32-C6")
part("D1", "LED0603", "LED verde", (0, 0), 0, {1: "LED_K", 2: "LED_A"}, LC["LED"], block="ESP32-C6", sym="LED",
     note="activo a nivel bajo en GPIO15, como el LED del XIAO")

# ---------------------------------------------------------------------------------------- IMU LSM6DSV16X (U5) + MMC5983MA (U8)
# Bus I²C a 400 kHz (el MMC5983MA no pasa de 400 kHz): LSM6DSV16X en 0x6A (SA0 = 0), MMC5983MA en 0x30. Igual que la REV B
# (LSM6 + MMC5983MA): CS del LSM6 a VDDIO (I²C), SDx/SCx a GND (sin concentrador), OCS_Aux y SDO_Aux sin conectar;
# SPI_CS del MMC a VDDIO (I²C), CAP con 10 µF.
part("U5", "LGA14", "LSM6DSV16X", (0, 0), 0,
     {1: GND, 2: GND, 3: GND, 4: "IMU_INT1", 5: V3, 6: GND, 7: GND, 8: V3, 9: "IMU_INT2", 10: None, 11: None, 12: V3,
      13: "I2C_SCL", 14: "I2C_SDA"},
     LC["LSM6DSV16X"], "LSM6DSV16XTR (ST)", "IMU",
     sym=dict(L=[(8, "VDD"), (5, "VDDIO"), (12, "CS"), (1, "SDO/SA0"), (2, "SDx"), (3, "SCx"), (6, "GND"), (7, "GND")],
              R=[(13, "SCL"), (14, "SDA"), (4, "INT1"), (9, "INT2"), (10, "OCS_Aux"), (11, "SDO_Aux")]),
     note="en el centro de la placa (eje de la cincha)")
C("C30", "100n", V3, GND, block="IMU", note="VDD del LSM6")
C("C31", "100n", V3, GND, block="IMU", note="VDDIO del LSM6")
R("R29", "2k2", "I2C_SCL", V3, block="IMU", note="pull-up I²C (400 kHz)")
R("R30", "2k2", "I2C_SDA", V3, block="IMU")
part("U8", "MMC", "MMC5983MA", (0, 0), 0,
     {1: "I2C_SCL", 2: V3, 3: None, 4: V3, 5: None, 6: None, 7: None, 8: None, 9: GND, 10: "MAG_CAP", 11: GND,
      12: None, 13: V3, 14: None, 15: "MAG_INT", 16: "I2C_SDA"},
     LC["MMC5983MA"], "MMC5983MA (MEMSIC)", "IMU",
     sym=dict(L=[(2, "VDD"), (13, "VDDIO"), (4, "SPI_CS"), (10, "CAP"), (9, "GND"), (11, "GND")],
              R=[(1, "SCL"), (16, "SDA"), (15, "INT"), (5, "SPI_SDO"), (3, "NC"), (6, "NC"), (7, "NC"), (8, "NC"),
                 (12, "NC"), (14, "NC")]),
     note="lejos de la batería, del cargador y de los hilos de corriente (campo magnético)")
C("C32", "1u", V3, GND, block="IMU", note="VDD del MMC5983MA")
C("C33", "10u", "MAG_CAP", GND, block="IMU", fp="C0603", note="CAP (SET/RESET): 10 µF de baja ESR junto al pin 10")
C("C35", "100n", V3, GND, block="IMU", note="VDDIO del MMC5983MA")

# ---------------------------------------------------------------------------------------- ECG ADS1292 (U6)
# Hoja SBAS502C: VREFN y EP a AVSS; entradas sin usar a AVDD; 4,7 nF en las salidas del PGA; 10 µF + 0,1 µF por
# alimentación; VCAP1 de dieléctrico no ferroeléctrico si hay vibración (C0G); CLKSEL = 1 (reloj interno).
# Canal 2 = ECG (IN2P/IN2N). Canal 1 apagado (IN1P/IN1N a AVDD). RLD con referencia interna (RLDREF_INT): RLDIN a AVDD,
# realimentación 1 MΩ ∥ 1,5 nF entre RLDOUT y RLDINV, salida al electrodo de referencia por 100 kΩ.
# AVDD con regulador propio (U7) para separar el ruido de la radio del 3,3 V digital.
part("U6", "ADS", "ADS1292", (0, 0), 0,
     {1: "ECG_PGA1N", 2: "ECG_PGA1P", 3: VA, 4: VA, 5: "ECGN", 6: "ECGP", 7: "ECG_PGA2N", 8: "ECG_PGA2P",
      9: "ECG_VREFP", 10: GND, 11: "ECG_VCAP1", 12: VA, 13: GND, 14: V3, 15: "ECG_RESET", 16: "ECG_START",
      17: "ECG_CLK", 18: "ECG_CS", 19: "ECG_MOSI", 20: "ECG_SCK", 21: "ECG_MISO", 22: "ECG_DRDY", 23: V3, 24: GND,
      25: GND, 26: GND, 27: "ECG_VCAP2", 28: "ECG_RLDINV", 29: VA, 30: "ECG_RLDOUT", 31: VA, 32: VA, 33: GND},
     LC["ADS1292"], "ADS1292IRSMR (TI) · alt. ADS1292RIRSMR C456281", "ECG",
     sym=dict(L=[(6, "IN2P"), (5, "IN2N"), (4, "IN1P"), (3, "IN1N"), (8, "PGA2P"), (7, "PGA2N"), (2, "PGA1P"), (1, "PGA1N"),
                 (9, "VREFP"), (10, "VREFN"), (11, "VCAP1"), (27, "VCAP2"), (12, "AVDD"), (13, "AVSS"),
                 (28, "RLDINV"), (29, "RLDIN/RLDREF"), (30, "RLDOUT"), (31, "IN3P"), (32, "IN3N")],
              R=[(18, "CS"), (20, "SCLK"), (19, "DIN"), (21, "DOUT"), (22, "DRDY"), (15, "PWDN/RESET"), (16, "START"),
                 (14, "CLKSEL"), (17, "CLK"), (23, "DVDD"), (24, "DGND"), (25, "GPIO2"), (26, "GPIO1"), (33, "EP")]),
     note="24 bits, 500 muestras/s, ganancia 6; GPIO1/2 a GND (entradas por defecto)")
part("U7", "SOT23-5", "RT9080-33GJ5", (0, 0), 0, {1: VSYS, 2: GND, 3: VSYS, 4: None, 5: VA}, LC["RT9080-33"],
     "RT9080-33GJ5", "ECG", sym=dict(L=[(1, "VIN"), (3, "EN"), (2, "GND")], R=[(5, "VOUT"), (4, "NC")]),
     note="AVDD analógico propio (PSRR 75 dB a 1 kHz)")
C("C40", "1u", VSYS, GND, block="ECG", note="entrada del AVDD")
C("C41", "10u", VA, GND, block="ECG", fp="C0603", note="AVDD")
C("C42", "100n", VA, GND, block="ECG", note="AVDD (pin 12)")
C("C43", "100n", V3, GND, block="ECG", note="DVDD (pin 23)")
C("C44", "10u", V3, GND, block="ECG", fp="C0603", note="DVDD")
C("C45", "10u", "ECG_VREFP", GND, block="ECG", fp="C0603", note="VREFP (referencia interna 2,42 V)")
C("C46", "100n", "ECG_VREFP", GND, block="ECG")
part("C47", "TANT_B", "1u 35V tántalo", (0, 0), 0, {1: "ECG_VCAP1", 2: GND}, LC["1u TANT"], "TAJB105K035RNJ (Kyocera AVX)",
     "ECG", sym=dict(L=[(1, "+")], R=[(2, "−")]),
     note="VCAP1 de tántalo (no ferroeléctrico, como pide TI si hay vibración); + al pin 11")
C("C48", "1u", "ECG_VCAP2", GND, block="ECG", note="VCAP2")
C("C49", "4n7 C0G", "ECG_PGA2P", "ECG_PGA2N", block="ECG", fp="C0603", note="CFILTER del canal 2 (ECG), GRM1885C1H472JA01D")
C("C50", "4n7 C0G", "ECG_PGA1P", "ECG_PGA1N", block="ECG", fp="C0603", note="CFILTER del canal 1 (apagado)")
R("R40", "47k", "ECG_E_P", "ECGP", block="ECG", note="serie del electrodo + (EMI, ESD)")
R("R41", "47k", "ECG_E_N", "ECGN", block="ECG", note="serie del electrodo −")
C("C52", "1n C0G", "ECGP", GND, block="ECG")
C("C53", "1n C0G", "ECGN", GND, block="ECG")
C("C54", "1n C0G", "ECGP", "ECGN", block="ECG", dnp=True, note="filtro diferencial opcional (sin montar)")
R("R42", "1M", "ECG_RLDOUT", "ECG_RLDINV", block="ECG", note="realimentación del RLD")
C("C55", "1n5 C0G", "ECG_RLDOUT", "ECG_RLDINV", block="ECG", note="realimentación del RLD, GRM1555C1H152JA01D")
R("R43", "100k", "ECG_RLDOUT", "ECG_E_REF", block="ECG", note="RLD al electrodo de referencia (limita la corriente)")
R("R44", "10k", "ECG_RESET", V3, block="ECG", note="PWDN/RESET alto (GPIO4 lo baja para reiniciar o apagar)")
R("R45", "10k", "ECG_START", GND, block="ECG", note="START bajo: la conversión arranca por orden SPI o por GPIO21")
R("R46", "10k", "ECG_CLK", GND, block="ECG", note="CLK sin usar (reloj interno)")
for ref, net, lab, nt in (("P4", "ECG_E_P", "ECG +", "pogo ECG contacto 1: placa izquierda"),
                          ("P5", "ECG_E_REF", "ECG REF", "pogo ECG contacto 2: referencia (RLD)"),
                          ("P6", "ECG_E_N", "ECG -", "pogo ECG contacto 3: placa derecha")):
    part(ref, "WIRE", lab, (0, 0), 0, {1: net}, block="Pogo ECG", sym="TP", no_assembly=True, note=nt)

# ---------------------------------------------------------------------------------------- pruebas y mecánica
# Primera programación: USB nativo del C6 por los pads TP (pinza de pogo-pins), con la cápsula abierta. Después, por radio.
TP("TP1", "EN", "EN"); TP("TP2", "BOOT", "BOOT", "GPIO9 a GND al arrancar = descarga")
TP("TP3", "GND", GND); TP("TP4", "D-", "USB_DM", "USB nativo del C6 (programación)")
TP("TP5", "D+", "USB_DP", "USB nativo del C6 (programación)"); TP("TP6", "3V3", V3)
TP("TP7", "VBAT", VBAT); TP("TP8", "5V", VBUS, "5 V para programar sin batería")
for i, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1)), 1):
    part("H%d" % i, "HOLE", "TALADRO M2", (sx * HOLE_XY[0], sy * HOLE_XY[1]), 0, {}, block="Mecánica", sym=None,
         no_assembly=True, note="taladro NPTH Ø2,2 del tornillo M2 de la tapa")

# --------------------------------------------------------------------------------- colocación (X, Y, giro)
POSF = os.path.join(HERE, "colocacion_revd.json")
POS = json.load(open(POSF, encoding="utf-8")) if os.path.exists(POSF) else {}
for p in PARTS:
    if p["ref"] in POS:
        x, y, r = POS[p["ref"]]
        p["pos"], p["rot"] = (x, y), r
MECH = [p for p in PARTS if p["fp"] == "HOLE"]
# anillo libre de 1 mm alrededor del ADS1292 (QFN de paso 0,4): sitio para las salidas y las vías de todos sus pines
_U6 = (-12.4, 1.8); _r0, _r1 = 2.7, 3.7
KEEPOUT_RECTS = [("U6_N", _U6[0] - _r1, _U6[1] + _r0, _U6[0] + _r1, _U6[1] + _r1),
                 ("U6_S", _U6[0] - _r1, _U6[1] - _r1, _U6[0] + _r1, _U6[1] - _r0),
                 ("U6_W", _U6[0] - _r1, _U6[1] - _r1, _U6[0] - _r0, _U6[1] + _r1),
                 ("U6_E", _U6[0] + _r0, _U6[1] - _r1, _U6[0] + _r1 + 0.8, _U6[1] + _r1)]

# =============================================================================== redes
NETS = []
for p in PARTS:
    for n in p["nets"].values():
        if n and n not in NETS:
            NETS.append(n)
NETS.sort(key=lambda n: (n not in (GND, V3, VA, VSYS, VBAT, VBUS), n))


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
            listed = isinstance(p["sym"], dict) and any(str(k) == str(num) for k, _ in
                                                         list(p["sym"].get("L", [])) + list(p["sym"].get("R", [])))
            if isinstance(p["sym"], dict) and not listed:
                nc = "unconnected-(%s-Pad%s)" % (p["ref"], num)        # pin sin nombre en el símbolo (como KiCad)
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
    """altura máxima de componente sobre la cara F en (x, y): hueco hasta la batería"""
    return Z_MAX_F


CIRC = {"HOLE": HOLE_KEEP}   # patios circulares (radio)


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
        if p["fp"] in CIRC:
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
    """taladros, pads de hilos y envolventes → CAD de la cápsula (pcb_mecanica.json)"""
    env = []
    for p in PARTS:
        h = fp_of(p).height
        if h > 0:
            x0, y0, x1, y1 = courtyard_casing(p)
            env.append([p["ref"], round(x0, 3), round(y0, 3), round(x1, 3), round(y1, 3), h])
    return dict(placa=dict(ancho=W, alto=H, radio_esquina=CORNER_R, espesor=THICK, vista="cara F (componentes)"),
                taladros=[list(p["pos"]) for p in PARTS if p["fp"] == "HOLE"],
                hilos={p["ref"]: dict(pos=list(p["pos"]), red=p["nets"]["1"]) for p in PARTS if p["fp"] == "WIRE"},
                envolventes=env, altura_max_cara_F=Z_MAX_F,
                origen="generado por PCB_REV_D/fuente/avo_girth_revd_pcb.py (colocacion_revd.json)")


if __name__ == "__main__" and "--place" in sys.argv:
    errs = check_placement()
    for e in errs:
        print(e)
    print("piezas:", len(PARTS), "· errores:", len(errs))
    sys.exit(1 if errs else 0)
