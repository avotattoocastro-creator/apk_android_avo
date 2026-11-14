"""AVO BACK V5 CASCO · placa de la espalda para el casco (ESP32-S3 + ZED-F9P) — generador del proyecto KiCad 9.

Un solo origen de datos (piezas, redes, posiciones) genera el esquema, la placa, las reglas, la lista de piezas para
JLCPCB y las comprobaciones de colocación. Derivado de la V4 REV B (avo_back_v4_pcb.py).

Placa de 51 × 51 mm, 4 capas, 1,6 mm:
  - TODOS los componentes en F (cara que mira a la batería, hacia abajo en la cápsula);
  - B.Cu = plano de masa macizo sin pistas: es el plano de masa de la antena GNSS plana activa (25 × 25), pegada en
    el centro de la cara B y mirando al cielo;
  - In1 = GND macizo; In2 = señales + relleno +3V3.
Coordenadas de diseño: origen en el centro de la placa, X a la derecha e Y hacia arriba, VISTA DESDE LA CARA F
(componentes). En KiCad: x = 100 + X, y = 100 − Y.

Decisión del usuario (14/11/2026): UN SOLO ESP32-S3 (BLE con el móvil + ESP-NOW con pecho y cinchas, como el pecho).
Bloques: cargador BQ24072 (USB por el pogo) · batería con PTC · 3,3 V TLV75733P · 3,3 V del ZED RT9080 con EN ·
  ZED-F9P soldado (UART1 + UART2 + PPS + RESET, antena activa por VCC_RF) · ESP32-S3-MINI-1U-N8 (antena FPC 2,4 GHz
  en el conector del módulo) · USB nativo del S3 por el pogo con ESD · microSD SDMMC 4 bits conmutada · Hall DRV5032.
Uso:  python avo_back_v5_pcb.py --place   (comprueba la colocación)
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
NAME = "AVO_BACK_V5_PCB"
REV, DATE = "A", "2026-11-14"
THICK = 1.6
SIZE, CORNER_R = 51.0, 3.0
HOLE_XY, HOLE_D, HOLE_KEEP = 22.0, 2.8, 3.0          # 4 taladros de los tornillos de la caja (M2,5)
ANT = (0.0, 0.0, 25.0)                                # antena GNSS en la cara B: centro y lado
Z_MAX_F = 2.6                                         # altura máxima de componente en F (hueco hasta la batería)


def K(X, Y):
    return (round(100 + X, 4), round(100 - Y, 4))


# =============================================================================== contorno (cuadrado 51 × 51 con R3)
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
    h, r = SIZE / 2, CORNER_R
    s = math.sqrt(0.5) * r
    P = []
    corners = [((h, -h + r), (h, h - r)), ((h - r, h), (-h + r, h)), ((-h, h - r), (-h, -h + r)), ((-h + r, -h), (h - r, -h))]
    centers = [(h - r, h - r), (-h + r, h - r), (-h + r, -h + r), (h - r, -h + r)]
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
    "L0402": load("R_0402_1005Metric.kicad_mod", M3 + "Inductor_SMD.3dshapes/L_0402_1005Metric.step", 0.6),
    "C0402": load("C_0402_1005Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0402_1005Metric.step", 0.6),
    "C0603": load("C_0603_1608Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0603_1608Metric.step", 0.9),
    "C0805": load("C_0805_2012Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0805_2012Metric.step", 1.35),
    "F1206": load("Fuse_1206_3216Metric.kicad_mod", M3 + "Fuse.3dshapes/Fuse_1206_3216Metric.step", 1.1),
    "SOT23": load("SOT-23.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23.step", 1.1),
    "SOT23-5": load("SOT-23-5.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23-5.step", 1.45),
    "SOT23-6": load("SOT-23-6.kicad_mod", M3 + "Package_TO_SOT_SMD.3dshapes/SOT-23-6.step", 1.45),
    "RGT16": load("VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm_ThermalVias.kicad_mod",
                  M3 + "Package_DFN_QFN.3dshapes/VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm.step", 1.0),
    "MICROSD": load("microSD_HC_Hirose_DM3AT-SF-PEJM5.kicad_mod",
                    M3 + "Connector_Card.3dshapes/microSD_HC_Hirose_DM3AT-SF-PEJM5.step", 1.6),
    "SOD323": load("D_SOD-323.kicad_mod", M3 + "Diode_SMD.3dshapes/D_SOD-323.step", 1.1),
    "ZED": load("ublox_ZED.kicad_mod", M3 + "RF_GPS.3dshapes/ublox_ZED.step", 2.4),
    "UFL": load("U.FL_Hirose_U.FL-R-SMT-1_Vertical.kicad_mod",
                M3 + "Connector_Coaxial.3dshapes/U.FL_Hirose_U.FL-R-SMT-1_Vertical.step", 1.25),
    "MINI1U": S3,
    "TP": test_pad(1.0),
    "WIRE": wire_pad("(hilo)", drill=0.9, d=1.7),
    "HOLE": npth_hole(HOLE_D, HOLE_KEEP, "Taladro del tornillo M2,5 de la caja"),
    "CABLE": npth_hole(3.0, 1.9, "Paso del cable coaxial de la antena GNSS (cara B → U.FL en F)"),
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


# códigos LCSC de la V4 (consultados en el CI el 29/10/2026). Los nuevos (ZED-F9P, U.FL, bobina de 47 nH, condensador
# de 47 pF C0G) quedan SIN código: se buscan con stock_jlc.py antes del pedido (ver el informe).
LC = {
    "0R": "C17168", "10R": "C25077", "22R": "C25092", "330R": "C25104", "1k": "C11702", "1k5": "C25867", "2k": "C4109",
    "10k": "C25744", "100k": "C25741", "1M": "C26083",
    "100n": "C1525", "1u": "C52923", "10n": "C15195", "4u7": "C19666",
    "10u": "C96446", "22u": "C45783", "47u": "C16780",
    "NTC10k": "C77131", "AO3401A": "C15127", "USBLC6": "C7519",
    "RT9080": "C841192", "TLV75733P": "C485517", "BQ24072": "C140288", "MINI1U": "C2980299",
    "MICROSD": "C114218", "PTC": "C20802", "DRV5032FA": "C140921", "TVS": "C2827694",
}


def R(ref, val, n1, n2, pos=(0, 0), rot=0, block="", dnp=False, fp="R0402", note=""):
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, LC.get(val, ""), block=block, sym="R", dnp=dnp, note=note)


def C(ref, val, n1, n2, pos=(0, 0), rot=0, block="", fp="C0402", dnp=False, lcsc=None, note=""):
    key = val.split()[0]
    part(ref, fp, val, pos, rot, {1: n1, 2: n2}, lcsc if lcsc is not None else LC.get(key, ""),
         block=block, sym="C", dnp=dnp, note=note)


GND, V3, VSYS, VBAT, VBUS, VZED, VSD = "GND", "+3V3", "VSYS", "VBAT", "VBUS", "+3V3_ZED", "+3V3_SD"
VIN5 = "VIN5"   # (sin uso en la V5; se mantiene por compatibilidad con build.py)
TP = lambda ref, label, net, note="": part(ref, "TP", label, (0, 0), 0, {1: net}, block="Pruebas", sym="TP",
                                           no_assembly=True, note=note)

# ---------------------------------------------------------------------------------------- pogo (5 contactos, por hilos)
# El conector pogo magnético de 5 contactos va en el fondo de la cápsula (sellado con epoxi); se une a la placa con
# 5 hilos cortos soldados en estos pads pasantes.
for ref, net, lab, nt in (("P1", "POGO_VBUS", "POGO VBUS", "5 V del cable USB magnético"),
                          ("P2", "USB_DM_C", "POGO D−", "USB D−"),
                          ("P3", "USB_DP_C", "POGO D+", "USB D+"),
                          ("P4", GND, "POGO GND", "masa"),
                          ("P5", "POGO_AUX_C", "POGO AUX", "contacto libre (reservado: base o accesorio)")):
    part(ref, "WIRE", lab, (0, 0), 0, {1: net}, block="Pogo", sym="TP", no_assembly=True, note=nt)
part("F2", "F1206", "PTC 1,5 A", (0, 0), 0, {1: "POGO_VBUS", 2: VBUS}, LC["PTC"], "SMD1206P150TF", "Pogo", sym="R",
     note="fusible rearmable del VBUS expuesto")
part("D2", "SOD323", "TVS 5 V", (0, 0), 0, {1: "POGO_VBUS", 2: GND}, LC["TVS"], "PESD5V0S1BA", "Pogo",
     sym=dict(L=[(1, "K")], R=[(2, "A")]), note="ESD en VBUS del pogo")
part("D3", "SOD323", "TVS 5 V", (0, 0), 0, {1: "POGO_AUX_C", 2: GND}, LC["TVS"], "PESD5V0S1BA", "Pogo",
     sym=dict(L=[(1, "K")], R=[(2, "A")]), note="ESD en el contacto AUX")
R("R20", "1k", "POGO_AUX_C", "POGO_AUX", block="Pogo", note="serie del contacto AUX → GPIO40")
R("R21", "100k", "POGO_AUX", GND, block="Pogo")
part("U6", "SOT23-6", "USBLC6-2SC6", (0, 0), 0,
     {1: "USB_DP_C", 6: "USB_DP_C", 3: "USB_DM_C", 4: "USB_DM_C", 2: GND, 5: VBUS}, LC["USBLC6"], block="Pogo",
     sym=dict(L=[(1, "IO1"), (6, "IO1"), (3, "IO2"), (4, "IO2")], R=[(5, "VBUS"), (2, "GND")]))
R("R18", "22R", "USB_DP_C", "USB_DP", block="Pogo")
R("R19", "22R", "USB_DM_C", "USB_DM", block="Pogo")
R("R22", "100k", VBUS, "VBUS_DET", block="Pogo", note="divisor 1:2 → GPIO18 (despierta al conectar el cable)")
R("R23", "100k", "VBUS_DET", GND, block="Pogo")

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
R("R6", "1k5", "CHG_ISET", GND, block="Cargador", note="I_carga = 890/1k5 ≈ 590 mA (0,3 C de 2000 mAh; ≈ 4 h)")
R("R7", "2k", "CHG_ILIM", GND, block="Cargador", note="I_entrada = 1525/2k ≈ 760 mA")
part("RT2", "R0402", "NTC 10k B3380", (0, 0), 0, {1: "CHG_TS", 2: GND}, LC["NTC10k"], "NCP15XH103F03RC", "Cargador", sym="R",
     note="NTC junto a la batería (cara F, encima de la celda)")
R("R8", "100k", "CHG_EN2", VSYS, block="Cargador", note="EN2 = 1, EN1 = 0: límite por ILIM")
R("R9", "100k", "CHG_PG", V3, block="Cargador")
R("R10", "100k", "CHG_STAT", V3, block="Cargador")

# ---------------------------------------------------------------------------------------- batería (hilos soldados)
part("J2", "WIRE", "BAT +", (0, 0), 0, {1: "BAT_IN"}, block="Batería", sym="TP", no_assembly=True,
     note="hilo + de la celda (≥ 2000 mAh): soldado, sin conector (más plano y sin holgura al galope)")
part("J6", "WIRE", "BAT −", (0, 0), 0, {1: GND}, block="Batería", sym="TP", no_assembly=True, note="hilo − de la celda")
part("F1", "F1206", "PTC 1,5 A", (0, 0), 0, {1: "BAT_IN", 2: VBAT}, LC["PTC"], "SMD1206P150TF", "Batería", sym="R",
     note="fusible rearmable entre la celda y el cargador (la celda lleva además su PCM)")
R("R32", "1M", VBAT, "BAT_ADC", block="Batería", note="divisor 1:2 → GPIO2 (ADC1_CH1)")
R("R33", "1M", "BAT_ADC", GND, block="Batería")
C("C34", "100n", "BAT_ADC", GND, block="Batería")

# ---------------------------------------------------------------------------------------- 3,3 V principal (U3) y del ZED (U7)
part("U3", "SOT23-5", "TLV75733PDBVR", (0, 0), 0, {1: VSYS, 2: GND, 3: VSYS, 4: None, 5: V3}, LC["TLV75733P"],
     "TLV75733PDBVR", "3V3", sym=dict(L=[(1, "IN"), (3, "EN"), (2, "GND")], R=[(5, "OUT"), (4, "NC")]),
     note="1 A: ESP32-S3 (picos de radio ≈ 0,35 A) + microSD + V_BCKP del ZED")
C("C21", "10u 25V", VSYS, GND, block="3V3", fp="C0603")
C("C22", "22u 10V", V3, GND, block="3V3", fp="C0805")
part("U7", "SOT23-5", "RT9080-33GJ5", (0, 0), 0, {1: VSYS, 2: GND, 3: "ZED_EN", 4: None, 5: VZED}, LC["RT9080"],
     "RT9080-33GJ5", "ZED", sym=dict(L=[(1, "VIN"), (3, "EN"), (2, "GND")], R=[(5, "VOUT"), (4, "NC")]),
     note="regulador propio del ZED y de la antena activa: EN = 0 corta receptor y LNA")
C("C60", "10u 25V", VSYS, GND, block="ZED", fp="C0603")
C("C61", "22u 10V", VZED, GND, block="ZED", fp="C0805")
R("R60", "100k", "ZED_EN", GND, block="ZED", note="ZED apagado mientras arranca el ESP32")

# ---------------------------------------------------------------------------------------- ZED-F9P (U1), soldado
# Pines según la hoja de datos del ZED-F9P (UBX-17051259 / UBX-21023276). Sin usar: ANT_DETECT/ANT_OFF/ANT_SHORT_N,
# I2C, TX_READY, EXTINT, GEOFENCE_STAT, RTK_STAT, USB del ZED (V_USB a GND, como pide la hoja si no se usa), reservados.
zed = {n: GND for n in (1, 3, 12, 14, 32, 37, 41, 48, 55)}
zed.update({2: "RF_ZED", 7: "VCC_RF", 26: "ZED_RX2", 27: "ZED_TX2_C", 33: VZED, 34: VZED, 36: V3, 38: GND,
            42: "ZED_TX1_C", 43: "ZED_RX1", 49: "ZED_RST", 50: "ZED_SAFEBOOT", 53: "ZED_PPS_C"})
part("U1", "ZED", "ZED-F9P-01B", (0, 0), 0, zed, "", "ZED-F9P-01B-01 (u-blox)", "ZED",
     sym=dict(L=[(2, "RF_IN"), (7, "VCC_RF"), (33, "VCC"), (34, "VCC"), (36, "V_BCKP"), (38, "V_USB"),
                 (49, "RESET_N"), (50, "SAFEBOOT_N"), (53, "TIMEPULSE")],
              R=[(42, "TXD"), (43, "RXD"), (27, "TXD2"), (26, "RXD2")] +
                [(n, "GND") for n in (1, 3, 12, 14, 32, 37, 41, 48, 55)]),
     note="ZED-F9P soldado (LGA 17 × 22). V_BCKP desde el 3,3 V principal (siempre encendido): arranque en caliente")
C("C62", "47u 6V3", VZED, GND, block="ZED", fp="C0805")
C("C63", "100n", VZED, GND, block="ZED")
C("C64", "100n", V3, GND, block="ZED", note="V_BCKP")
# antena activa: VCC_RF → 10 Ω → 47 nH → línea de RF (lado de la antena); bloqueo de continua hacia RF_IN
R("R70", "10R", "VCC_RF", "VCC_RF_F", block="ZED", note="limita la corriente si el cable de antena se cortocircuita")
C("C71", "10n", "VCC_RF_F", GND, block="ZED")
part("L70", "L0402", "47 nH", (0, 0), 0, {1: "VCC_RF_F", 2: "RF_ANT"}, "", "LQG15HS47NJ02D (Murata)", "ZED", sym="R",
     note="alimentación de la antena activa por el vivo del coaxial (choque de RF)")
C("C70", "47p C0G", "RF_ANT", "RF_ZED", block="ZED", lcsc="",
  note="bloqueo de continua hacia RF_IN (inofensivo si el ZED ya lo lleva dentro); línea de 50 Ω ≈ 0,36 mm")
part("J5", "UFL", "U.FL GNSS", (0, 0), 0, {1: "RF_ANT", 2: GND}, "", "U.FL-R-SMT-1(10) (Hirose)", "ZED",
     sym=dict(L=[(1, "SIG")], R=[(2, "GND")]), note="cable de la antena plana activa L1/L2 (AHP2258 o similar)")
R("R50", "1k", "S3_TX1", "ZED_RX1", block="ZED", note="serie: limita la alimentación parásita del ZED apagado")
R("R51", "1k", "S3_TX2", "ZED_RX2", block="ZED")
R("R52", "1k", "S3_ZRST", "ZED_RST", block="ZED", note="RESET_N del ZED (GPIO9 en colector abierto)")
R("R53", "330R", "ZED_TX1_C", "ZED_TX1", block="ZED")
R("R54", "330R", "ZED_TX2_C", "ZED_TX2", block="ZED")
R("R55", "330R", "ZED_PPS_C", "ZED_PPS", block="ZED", note="PPS → GPIO4")

# ---------------------------------------------------------------------------------------- ESP32-S3 (U4)
GPIO = {  # pad del módulo: (GPIO, red)
    4: ("IO0", "BOOT"), 5: ("IO1", "HALL"), 6: ("IO2", "BAT_ADC"), 7: ("IO3", None),
    8: ("IO4", "ZED_PPS"), 9: ("IO5", "ZED_TX1"), 10: ("IO6", "S3_TX1"), 11: ("IO7", "ZED_TX2"), 12: ("IO8", "S3_TX2"),
    13: ("IO9", "S3_ZRST"), 14: ("IO10", "ZED_EN"), 15: ("IO11", None),
    16: ("IO12", "SD_CLK0"), 17: ("IO13", "SD_CMD"), 18: ("IO14", "SD_D0"), 19: ("IO15", "SD_D1"), 20: ("IO16", "SD_D2"),
    21: ("IO17", "SD_D3"), 22: ("IO18", "VBUS_DET"), 23: ("IO19 D-", "USB_DM"), 24: ("IO20 D+", "USB_DP"),
    25: ("IO21", "SD_PWR_N"),
    26: ("IO26", None), 27: ("IO47", "GPIO47"), 28: ("IO33", None), 29: ("IO34", None), 30: ("IO48", "GPIO48"),
    31: ("IO35", None), 32: ("IO36", None), 33: ("IO37", None), 34: ("IO38", "CHG_PG"), 35: ("IO39", "CHG_STAT"),
    36: ("IO40", "POGO_AUX"), 37: ("IO41", "GPIO41"), 38: ("IO42", None), 39: ("TXD0", "U0TX"), 40: ("RXD0", "U0RX"),
    41: ("IO45", None), 44: ("IO46", None), 45: ("EN", "EN"), 3: ("3V3", V3),
}
GND_PADS = (1, 2, 42, 43) + tuple(range(46, 66))
u4nets = {n: GND for n in GND_PADS}
u4nets.update({k: v[1] for k, v in GPIO.items()})
part("U4", "MINI1U", "ESP32-S3-MINI-1U-N8", (0, 0), 0, u4nets, LC["MINI1U"], "ESP32-S3-MINI-1U-N8", "ESP32-S3",
     sym=dict(L=[(k, v[0] + (" " + v[1] if v[1] and v[1] not in (V3,) else "")) for k, v in sorted(GPIO.items()) if k <= 25 or k == 3],
              R=[(k, v[0] + (" " + v[1] if v[1] else "")) for k, v in sorted(GPIO.items()) if 25 < k] +
                [(n, "GND") for n in GND_PADS]),
     note="antena FPC de 2,4 GHz en el conector del módulo, pegada a la pared de la cápsula (lejos de la GNSS)")
C("C24", "22u 10V", V3, GND, block="ESP32-S3", fp="C0805")
C("C25", "100n", V3, GND, block="ESP32-S3")
C("C26", "1u", V3, GND, block="ESP32-S3")
R("R11", "10k", "EN", V3, block="ESP32-S3")
C("C27", "1u", "EN", GND, block="ESP32-S3", note="EN: RC 10 k / 1 µF (guía de diseño de Espressif)")

# ---------------------------------------------------------------------------------------- Hall (encendido en la base)
part("U8", "SOT23", "DRV5032FA", (0, 0), 0, {1: V3, 2: "HALL", 3: GND}, LC["DRV5032FA"], "DRV5032FADBZR", "Hall",
     sym=dict(L=[(1, "VCC")], R=[(2, "OUT"), (3, "GND")]),
     note="imán de la base del casco: OUT = 0 en la base → GPIO1 (RTC, despierta del sueño profundo)")
C("C80", "100n", V3, GND, block="Hall")

# ---------------------------------------------------------------------------------------- microSD (J3), SDMMC 4 bits
part("J3", "MICROSD", "microSD DM3AT", (0, 0), 0,
     {1: "SD_D2", 2: "SD_D3", 3: "SD_CMD", 4: VSD, 5: "SD_CLK", 6: GND, 7: "SD_D0", 8: "SD_D1", 9: None, 10: GND, 11: GND},
     LC["MICROSD"], "DM3AT-SF-PEJM5", "microSD",
     sym=dict(L=[(4, "VDD"), (5, "CLK"), (3, "CMD"), (7, "DAT0"), (8, "DAT1"), (1, "DAT2"), (2, "CD/DAT3")],
              R=[(6, "VSS"), (9, "DET"), (10, "DET_COM"), (11, "SHELL")]),
     note="sin detección de tarjeta (caja estanca: la tarjeta va siempre puesta)")
part("Q4", "SOT23", "AO3401A", (0, 0), 0, {1: "SD_PWR_N", 2: V3, 3: VSD}, LC["AO3401A"], block="microSD",
     sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]), note="alimentación de la tarjeta: GPIO21 = 0 la enciende")
R("R40", "100k", "SD_PWR_N", V3, block="microSD", note="tarjeta apagada mientras arranca el ESP32")
C("C40", "10u 25V", VSD, GND, block="microSD", fp="C0603")
C("C41", "100n", VSD, GND, block="microSD")
for i, n in enumerate(("SD_CMD", "SD_D0", "SD_D1", "SD_D2", "SD_D3")):
    R("R%d" % (41 + i), "10k", n, VSD, block="microSD")
R("R46", "22R", "SD_CLK0", "SD_CLK", block="microSD", note="serie del reloj (amortigua el flanco)")

# ---------------------------------------------------------------------------------------- pruebas y mecánica
TP("TP1", "EN", "EN"); TP("TP2", "BOOT", "BOOT", "GPIO0 a GND al arrancar = descarga (también por USB nativo)")
TP("TP3", "GND", GND); TP("TP4", "TXD0", "U0TX"); TP("TP5", "RXD0", "U0RX"); TP("TP6", "3V3", V3)
TP("TP7", "VBAT", VBAT); TP("TP8", "VSYS", VSYS); TP("TP9", "3V3_ZED", VZED); TP("TP10", "GPIO41", "GPIO41")
TP("TP11", "GPIO47", "GPIO47", "libre (futuro)"); TP("TP12", "GPIO48", "GPIO48", "libre (futuro)")
TP("TP13", "SAFEBOOT", "ZED_SAFEBOOT", "SAFEBOOT_N del ZED: solo para recuperar su firmware")
for i, (sx, sy) in enumerate(((1, 1), (-1, 1), (-1, -1), (1, -1)), 1):
    part("H%d" % i, "HOLE", "TALADRO M2,5", (sx * HOLE_XY, sy * HOLE_XY), 0, {}, block="Mecánica", sym=None,
         no_assembly=True, note="taladro NPTH Ø2,8 del tornillo de la caja")
part("H5", "CABLE", "PASO COAXIAL", (0, 0), 0, {}, block="Mecánica", sym=None, no_assembly=True,
     note="paso del coaxial de la antena GNSS (cara B) al U.FL J5 (cara F)")

# --------------------------------------------------------------------------------- colocación (X, Y, giro)
POSF = os.path.join(HERE, "colocacion_v5.json")
POS = json.load(open(POSF, encoding="utf-8")) if os.path.exists(POSF) else {}
for p in PARTS:
    if p["ref"] in POS:
        x, y, r = POS[p["ref"]]
        p["pos"], p["rot"] = (x, y), r
MECH = [p for p in PARTS if p["fp"] in ("HOLE", "CABLE")]
KEEPOUT_RECTS = []

# =============================================================================== redes
NETS = []
for p in PARTS:
    for n in p["nets"].values():
        if n and n not in NETS:
            NETS.append(n)
NETS.sort(key=lambda n: (n not in (GND, V3, VSYS, VBAT, VBUS, VZED, VSD), n))


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


CIRC = {"HOLE": HOLE_KEEP, "CABLE": 1.9}   # patios circulares (radio)


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
    """taladros, paso del coaxial, pads de hilos y envolventes → CAD de la cápsula (pcb_mecanica.json)"""
    env = []
    for p in PARTS:
        h = fp_of(p).height
        if h > 0:
            x0, y0, x1, y1 = courtyard_casing(p)
            env.append([p["ref"], round(x0, 3), round(y0, 3), round(x1, 3), round(y1, 3), h])
    return dict(placa=dict(lado=SIZE, radio_esquina=CORNER_R, espesor=THICK, vista="cara F (componentes)"),
                taladros=[list(p["pos"]) for p in PARTS if p["fp"] == "HOLE"],
                paso_coaxial=[list(p["pos"]) for p in PARTS if p["fp"] == "CABLE"],
                antena_cara_B=dict(centro=list(ANT[:2]), lado=ANT[2]),
                hilos={p["ref"]: dict(pos=list(p["pos"]), red=p["nets"]["1"]) for p in PARTS if p["fp"] == "WIRE"},
                envolventes=env, altura_max_cara_F=Z_MAX_F,
                origen="generado por PCB/fuente/avo_back_v5_pcb.py (colocacion_v5.json)")


if __name__ == "__main__" and "--place" in sys.argv:
    errs = check_placement()
    for e in errs:
        print(e)
    print("piezas:", len(PARTS), "· errores:", len(errs))
    sys.exit(1 if errs else 0)
