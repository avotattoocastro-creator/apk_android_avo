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
REV B (17/11/2026, decisiones del usuario tras la auditoría BETA y la revisión electrónica):
  - ESP32-S3-WROOM-1U-N16R8 (16 MB de flash, 8 MB de PSRAM octal) en lugar del MINI-1U-N8: 3,2 mm de alto, la
    cápsula sube 0,6 mm (Z_MAX_F 2,6 → 3,2); la planta de 51 × 51 no cambia.
  - Encendido y apagado total: táctil TTP223 siempre alimentado + enclavamiento (OR de diodos) en el EN del 3,3 V
    principal: táctil, POWER_HOLD del micro (GPIO46) y VBUS del pogo. Hall y VBUS_DET siguen despertando del reposo.
  - LDO de µA siempre encendido (XC6206, +3V3_AON) desde la batería: V_BCKP del ZED (arranque en caliente también
    con el casco apagado) y alimentación del táctil.
  - Anillo de LED a 4,3 V con elevador TPS61023 (corte real de la carga con EN = 0): el anillo ya no consume en
    reposo (0,6 mA por LED) y funciona con la batería por debajo de 3,7 V. DIN a 3,3 V válido (VIH = 0,65 × 4,3 V).
  - Cargador: temporizador de seguridad con R_TMR 68 kΩ (≈ 8,5 h; antes 5 h por defecto).
  - Protección de polaridad de la batería (PMOS, como la V4).
  - Medidor de batería MAX17048 (I²C) e IMU LSM6DSV16X (I²C, INT1 despierta), sin agrandar la placa.
Uso:  python avo_back_v5_pcb.py --place   (comprueba la colocación)
"""
import glob
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from custom_fp import lga14_st, test_pad, wire_pad   # noqa: E402
from fplib import Footprint, Pad, circle, load, rect_lines   # noqa: E402
from sexpr import Sym   # noqa: E402

OUT = os.path.join(HERE, "..", "kicad")
os.makedirs(OUT, exist_ok=True)
NAME = "AVO_BACK_V5_PCB"
REV, DATE = "B", "2026-11-17"
THICK = 1.6
SIZE, CORNER_R = 51.0, 3.0
HOLE_XY, HOLE_D, HOLE_KEEP = 22.0, 2.8, 3.0          # 4 taladros de los tornillos de la caja (M2,5)
ANT = (0.0, 0.0, 25.0)                                # antena GNSS en la cara B: centro y lado
Z_MAX_F = 3.2                                         # altura máxima en F (REV B: WROOM-1U de 3,2; antes 2,6)


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


def sk6812_side():
    """SK6812SIDE-A (OPSCO, LCSC C5378721): RGB direccionable de emisión lateral, 4,0 × 1,6 × 2,0 de alto.
    Pads según el patrón recomendado de la hoja (pág. 5) y la huella EasyEDA de LCSC: 1 DIN · 2 VDD · 3 DOUT · 4 GND.
    La lente mira a +y local (lado opuesto a las pistas): se coloca con la lente hacia el canto de la placa."""
    pads = [Pad("1", "smd", "rect", -1.575, -0.01, 0.55, 1.2), Pad("2", "smd", "rect", -0.45, -0.01, 0.70, 1.2),
            Pad("3", "smd", "rect", 0.57, -0.01, 0.45, 1.2), Pad("4", "smd", "rect", 1.575, -0.01, 0.55, 1.2)]
    g = rect_lines(-2.1, -0.75, 2.1, 1.45, "F.CrtYd", 0.05) + rect_lines(-2.0, -0.24, 2.0, 1.36, "F.Fab", 0.1)
    g += [[Sym("fp_line"), [Sym("start"), -1.0, 1.55], [Sym("end"), 1.0, 1.55],
           [Sym("stroke"), [Sym("width"), 0.12], [Sym("type"), Sym("solid")]], [Sym("layer"), "F.SilkS"]]]
    return Footprint("AVO_SK6812SIDE-A_4.0x1.6mm", pads, g, "smd", None, "SK6812SIDE-A emisión lateral (lente hacia +y)", 2.0)


def npth_hole(d, keep, label):
    pads = [Pad("", "np_thru_hole", "circle", 0, 0, d, d, drill=d, layers=["*.Cu", "*.Mask"])]
    g = [circle(0, 0, keep, "F.CrtYd", 0.05), circle(0, 0, d / 2 + 0.2, "F.SilkS", 0.12)]
    return Footprint("AVO_Taladro_NPTH_D%.1f" % d, pads, g, "smd board_only exclude_from_pos_files exclude_from_bom", None,
                     label, 0.0)


def _sin_patio(fp):
    fp.graphics = [g for g in fp.graphics if not (len(g) > 1 and any(isinstance(x, list) and x[0] == "layer" and "CrtYd" in str(x[1]) for x in g))]
    return fp


# REV B: ESP32-S3-WROOM-1U (Espressif kicad-libraries): cuerpo 18,0 × 19,2 × 3,2, de y −9,45 a +9,75 (U.FL junto al
# borde de y −9,45). Los pads asoman fuera del cuerpo (x ±9,5; fila inferior hasta y +10,25): patio = pads + 0,25
# por los lados y abajo, cuerpo + 0,1 arriba (el de la librería añade 0,8 por arriba).
S3 = _sin_patio(load("ESP32-S3-WROOM-1U.kicad_mod", "${KIPRJMOD}/../fuente/3d/ESP32-S3-WROOM-1U.STEP", 3.2))
S3.graphics += rect_lines(-9.75, -9.55, 9.75, 10.5, "F.CrtYd", 0.05)


def easyeda(code, height, prov):
    """Huella de EasyEDA/LCSC descargada en el CI (lib_easyeda/<código>.pretty). Mientras no exista se usa una
    provisional del mismo tamaño (solo para la colocación local; el CI no rutea con la provisional)."""
    f = sorted(glob.glob(os.path.join(HERE, "lib_easyeda", code + ".pretty", "*.kicad_mod")))
    if not f:
        return prov
    fp = _sin_patio(load(f[0], None, height))
    # EasyEDA no trae patio (F.CrtYd): rectángulo que envuelve los pads (girados) + 0,25 mm
    xs, ys = [], []
    for p in fp.pads:
        w, h = (p.h, p.w) if round(p.rot) % 180 == 90 else (p.w, p.h)
        xs += [p.x - w / 2, p.x + w / 2]; ys += [p.y - h / 2, p.y + h / 2]
    fp.graphics += rect_lines(min(xs) - 0.25, min(ys) - 0.25, max(xs) + 0.25, max(ys) + 0.25, "F.CrtYd", 0.05)
    return fp


def _prov(name, pads, cx, cy, h):
    g = rect_lines(-cx, -cy, cx, cy, "F.CrtYd", 0.05)
    return Footprint(name + "_PROVISIONAL", [Pad(str(n), "smd", "rect", x, y, w, hh) for n, x, y, w, hh in pads], g,
                     "smd", None, "provisional", h)


# TPS61023 SOT-563 (DRL): 1 FB · 2 EN · 3 VIN | 4 GND · 5 SW · 6 VOUT
SOT563 = easyeda("C919459", 0.6, _prov("SOT563", [(1, -0.7, -0.5, .6, .3), (2, -0.7, 0, .6, .3), (3, -0.7, .5, .6, .3),
                                                   (4, .7, .5, .6, .3), (5, .7, 0, .6, .3), (6, .7, -.5, .6, .3)], 1.15, 1.0, 0.6))
# MAX17048 TDFN-8 2 × 2 (T822): 1 CTG · 2 CELL · 3 VDD · 4 GND | 5 ALRT · 6 QSTRT · 7 SCL · 8 SDA · 9 EP
TDFN8 = easyeda("C2682616", 0.8, _prov("TDFN8", [(n, -0.95 if n <= 4 else 0.95, (-0.75 + 0.5 * (n - 1)) if n <= 4 else
                                                   (0.75 - 0.5 * (n - 5)), .6, .28) for n in range(1, 9)] +
                                        [(9, 0, 0, .7, 1.3)], 1.35, 1.25, 0.8))
L0806 = easyeda("C97016", 1.0, _prov("L0806", [(1, -0.85, 0, .8, 1.7), (2, .85, 0, .8, 1.7)], 1.5, 1.1, 1.0))
FP = {
    "R0402": load("R_0402_1005Metric.kicad_mod", M3 + "Resistor_SMD.3dshapes/R_0402_1005Metric.step", 0.4),
    "L0402": load("R_0402_1005Metric.kicad_mod", M3 + "Inductor_SMD.3dshapes/L_0402_1005Metric.step", 0.6),
    "C0402": load("C_0402_1005Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0402_1005Metric.step", 0.6),
    "C0603": load("C_0603_1608Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0603_1608Metric.step", 0.9),
    "C0805": load("C_0805_2012Metric.kicad_mod", M3 + "Capacitor_SMD.3dshapes/C_0805_2012Metric.step", 1.35),
    "R1206": load("C_1206_3216Metric.kicad_mod", M3 + "Resistor_SMD.3dshapes/R_1206_3216Metric.step", 0.6),
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
    "WROOM1U": S3,
    "SOT563": SOT563,
    "TDFN8": TDFN8,
    "L0806": L0806,
    "LGA14": lga14_st(),
    "LEDSIDE": sk6812_side(),
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


# códigos LCSC consultados en el CI (V4 29/10/2026; V5 14/11/2026, out_stock/stock_jlc.json): ZED-F9P-04B C5120257 (895 uds.,
# 76,27 US$), U.FL C88373, 47 nH C97998, 22 Ω 1206 C17958 (Basic), ESD de RF PESD0402-140 C10662.
LC = {
    "0R": "C17168", "10R": "C25077", "22R": "C25092", "33R": "C25105", "22R 1206": "C17958", "330R": "C25104", "1k": "C11702", "1k5": "C25867", "2k": "C4109",
    "10k": "C25744", "100k": "C25741", "1M": "C26083",
    "100n": "C1525", "1u": "C52923", "10n": "C15195", "4u7": "C19666",
    "10u": "C96446", "22u": "C45783", "47u": "C16780",
    "NTC10k": "C77131", "AO3401A": "C15127", "USBLC6": "C7519",
    "RT9080": "C841192", "TLV75733P": "C485517", "BQ24072": "C140288", "MINI1U": "C2980299",
    "MICROSD": "C114218", "PTC": "C20802", "SK6812SIDE": "C5378721", "DRV5032FA": "C140921", "TVS": "C2827694",
    # REV B (17/11/2026; existencias consultadas en el CI: out_stock/stock_jlc.json)
    "WROOM1U": "C3013946", "TPS61023": "C919459", "MAX17048": "C2682616", "1uH 0806": "C97016", "TTP223": "C42422127",
    "XC6206": "C5446", "BAT54C": "C2135", "LSM6DSV16X": "C5267406", "68k": "C36871", "2k2": "C25879", "22p": "C1555",
    "620k": "C137952",
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
      10: VSYS, 11: VSYS, 12: "CHG_ILIM", 13: VBUS, 14: "CHG_TMR", 15: GND, 16: "CHG_ISET", 17: GND},
     LC["BQ24072"], "BQ24072RGTR", "Cargador",
     sym=dict(L=[(13, "IN"), (4, "CE"), (6, "EN1"), (5, "EN2"), (16, "ISET"), (12, "ILIM"), (14, "TMR"),
                 (15, "TD"), (1, "TS")],
              R=[(10, "OUT"), (11, "OUT"), (2, "BAT"), (3, "BAT"), (7, "PGOOD"), (9, "CHG"), (8, "VSS"), (17, "EP")]))
C("C18", "1u", VBUS, GND, block="Cargador")
C("C19", "10u 25V", VSYS, GND, block="Cargador", fp="C0603")
C("C20", "10u 25V", VBAT, GND, block="Cargador", fp="C0603")
C("C35", "47u 6V3", VSYS, GND, block="Cargador", fp="C0805", note="reserva de VSYS para los picos de radio y del ZED")
R("R6", "1k5", "CHG_ISET", GND, block="Cargador", note="I_carga = 890/1k5 ≈ 590 mA (0,3 C de 2000 mAh; ≈ 4 h)")
R("R7", "2k", "CHG_ILIM", GND, block="Cargador", note="I_entrada = K_ILIM/R_ILIM ≈ 1600/2k ≈ 800 mA (BQ24072T, SLUS937)")
part("RT2", "R0402", "NTC 10k B3380", (0, 0), 0, {1: "CHG_TS", 2: GND}, LC["NTC10k"], "NCP15XH103F03RC", "Cargador", sym="R",
     note="NTC junto a la batería (cara F, encima de la celda)")
R("R12", "68k", "CHG_TMR", GND, block="Cargador",
  note="REV B: temporizador de seguridad t_MAXCH = 10 × K_TMR × R_TMR ≈ 10 × 45 × 68k ≈ 8,5 h (35–55 s/kΩ: 6,6–10,4 h; "
       "SLUS937). Al aire eran 4–6 h y podía cortar la carga con el casco encendido en el DOCK")
R("R8", "100k", "CHG_EN2", VSYS, block="Cargador", note="EN2 = 1, EN1 = 0: límite por ILIM")
R("R9", "100k", "CHG_PG", V3, block="Cargador")
R("R10", "100k", "CHG_STAT", V3, block="Cargador")

# ---------------------------------------------------------------------------------------- batería (hilos soldados)
part("J2", "WIRE", "BAT +", (0, 0), 0, {1: "BAT_IN"}, block="Batería", sym="TP", no_assembly=True,
     note="hilo + de la celda (≥ 2000 mAh): soldado, sin conector (más plano y sin holgura al galope)")
part("J6", "WIRE", "BAT −", (0, 0), 0, {1: GND}, block="Batería", sym="TP", no_assembly=True, note="hilo − de la celda")
part("F1", "F1206", "PTC 1,5 A", (0, 0), 0, {1: "BAT_IN", 2: "BAT_F"}, LC["PTC"], "SMD1206P150TF", "Batería", sym="R",
     note="fusible rearmable entre la celda y el cargador (la celda lleva además su PCM)")
part("Q7", "SOT23", "AO3401A", (0, 0), 0, {1: "BAT_G", 2: VBAT, 3: "BAT_F"}, LC["AO3401A"], block="Batería",
     sym=dict(L=[(1, "G")], R=[(2, "S"), (3, "D")]),
     note="REV B: polaridad de la celda (como Q3 de la V4). D a la celda, S al sistema, G a GND: con la celda al revés "
          "queda cortado; en uso conduce en los dos sentidos (carga y descarga), ≈ 60 mΩ")
R("R13", "100k", "BAT_G", GND, block="Batería", note="puerta de Q7 a GND")
R("R32", "1M", VBAT, "BAT_ADC", block="Batería", note="divisor 1:2 → GPIO2 (ADC1_CH1)")
R("R33", "1M", "BAT_ADC", GND, block="Batería")
C("C34", "100n", "BAT_ADC", GND, block="Batería")

# ---------------------------------------------------------------------------------------- 3,3 V principal (U3) y del ZED (U7)
part("U3", "SOT23-5", "TLV75733PDBVR", (0, 0), 0, {1: VSYS, 2: GND, 3: "EN_3V3", 4: None, 5: V3}, LC["TLV75733P"],
     "TLV75733PDBVR", "3V3", sym=dict(L=[(1, "IN"), (3, "EN"), (2, "GND")], R=[(5, "OUT"), (4, "NC")]),
     note="1 A: ESP32-S3 (picos de radio ≈ 0,35 A) + microSD + IMU. REV B: EN = OR(táctil, POWER_HOLD, VBUS)")
# --- REV B: enclavamiento de alimentación (apagado total). Encender: pulsación larga en el táctil (el TTP223 sube
# TOUCH_OUT, EN_3V3 sube, el S3 arranca y mantiene POWER_HOLD) o conectar el cable / DOCK (VBUS). Apagar: el firmware
# confirma con el anillo, cierra la sesión y la microSD y suelta POWER_HOLD.
part("D5", "SOT23", "BAT54C", (0, 0), 0, {1: "TOUCH_OUT", 2: "PWR_HOLD", 3: "EN_3V3"}, LC["BAT54C"], "BAT54C", "Encendido",
     sym=dict(L=[(1, "A1"), (2, "A2")], R=[(3, "K")]), note="OR del táctil y de POWER_HOLD al EN del 3,3 V")
part("D6", "SOT23", "BAT54C", (0, 0), 0, {1: VBUS, 2: None, 3: "EN_3V3"}, LC["BAT54C"], "BAT54C", "Encendido",
     sym=dict(L=[(1, "A1"), (2, "A2")], R=[(3, "K")]),
     note="VBUS del pogo (cargador o DOCK) al EN: una cápsula apagada se enciende al cargar (decisión D1 de la auditoría)")
R("R14", "1M", "EN_3V3", GND, block="Encendido", note="EN a 0 sin ninguna fuente: apagado (fuga ≈ 0)")
R("R15", "100k", "PWR_HOLD", GND, block="Encendido",
  note="GPIO46 (de arranque: bajo por defecto) — el firmware lo sube nada más arrancar y lo retiene en el sueño")
# --- REV B: 3,3 V siempre encendido (µA) desde la batería: V_BCKP del ZED + táctil
part("U9", "SOT23", "XC6206P332MR", (0, 0), 0, {1: GND, 2: "+3V3_AON", 3: VBAT}, LC["XC6206"], "XC6206P332MR-G (Torex)",
     "Siempre", sym=dict(L=[(3, "VIN"), (1, "VSS")], R=[(2, "VOUT")]),
     note="LDO de ≈ 1 µA: mantiene V_BCKP del ZED (efemérides) con el casco apagado y alimenta el táctil")
C("C66", "1u", VBAT, GND, block="Siempre")
C("C67", "1u", "+3V3_AON", GND, block="Siempre")
# --- REV B: táctil sellado (electrodo de lámina de cobre por dentro de la pared adelgazada, unido a TP_TOUCH)
part("U10", "SOT23-6", "TTP223-BA6-TD", (0, 0), 0,
     {1: "TOUCH_OUT", 2: GND, 3: "TOUCH_I", 4: GND, 5: "+3V3_AON", 6: GND}, LC["TTP223"], "TTP223-BA6-TD (TDSEMIC)", "Táctil",
     sym=dict(L=[(5, "VDD"), (3, "I"), (4, "AHLB"), (6, "TOG")], R=[(1, "Q"), (2, "VSS")]),
     note="AHLB = 0 (activo alto), TOG = 0 (directo): Q = 1 mientras se toca. Modo de bajo consumo (≈ 1,5 µA a 3 V). "
          "TDSEMIC TTP223-BA6-TD (C42422127): mismo patillaje que el TTP223-BA6 de Tontek, sin existencias en JLC")
C("C68", "100n", "+3V3_AON", GND, block="Táctil", note="obligatorio y pegado a VDD/VSS (hoja del TTP223)")
C("C69", "22p", "TOUCH_I", GND, block="Táctil", dnp=True,
  note="Cs de sensibilidad (0–50 pF): sin montar; se ajusta tras la prueba con la pared de 1,2–1,5 mm y agua")
R("R16", "1k", "TOUCH_E", "TOUCH_I", block="Táctil", note="serie del electrodo (ESD)")
part("J7", "WIRE", "TÁCTIL", (0, 0), 0, {1: "TOUCH_E"}, block="Táctil", sym="TP", no_assembly=True,
     note="hilo o muelle a la lámina de cobre del electrodo (pared interior adelgazada, sin agujero)")
R("R17", "10k", "TOUCH_OUT", "TOUCH_SENSE", block="Táctil",
  note="→ GPIO11 (RTC: despierta del sueño y mide la pulsación larga); limita la corriente si el S3 está sin tensión")
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
zed.update({2: "RF_ZED", 7: "VCC_RF", 26: "ZED_RX2", 27: "ZED_TX2_C", 33: VZED, 34: VZED, 36: "+3V3_AON", 38: GND,
            42: "ZED_TX1_C", 43: "ZED_RX1", 49: "ZED_RST", 50: "ZED_SAFEBOOT", 53: "ZED_PPS_C"})
part("U1", "ZED", "ZED-F9P-04B", (0, 0), 0, zed, "C5120257", "ZED-F9P-04B (u-blox)", "ZED",
     sym=dict(L=[(2, "RF_IN"), (7, "VCC_RF"), (33, "VCC"), (34, "VCC"), (36, "V_BCKP"), (38, "V_USB"),
                 (49, "RESET_N"), (50, "SAFEBOOT_N"), (53, "TIMEPULSE")],
              R=[(42, "TXD"), (43, "RXD"), (27, "TXD2"), (26, "RXD2")] +
                [(n, "GND") for n in (1, 3, 12, 14, 32, 37, 41, 48, 55)]),
     note="ZED-F9P soldado (LGA 17 × 22). REV B: V_BCKP desde +3V3_AON (LDO de µA desde la batería): arranque en caliente "
          "también tras el apagado total")
C("C62", "47u 6V3", VZED, GND, block="ZED", fp="C0805")
C("C63", "100n", VZED, GND, block="ZED")
C("C65", "1u", VZED, GND, block="ZED", note="pegado a los pines VCC 33/34")
C("C64", "100n", "+3V3_AON", GND, block="ZED", note="V_BCKP")
# antena activa: VCC_RF → 10 Ω → 47 nH → línea de RF (lado de la antena); bloqueo de continua hacia RF_IN
R("R70", "22R 1206", "VCC_RF", "VCC_RF_F", block="ZED", fp="R1206",
  note="revisión independiente: limita un corto del coaxial a ≈ 150 mA (bobina de 300 mA); cae ≈ 0,4 V a 20 mA de LNA")
C("C71", "10n", "VCC_RF_F", GND, block="ZED")
part("L70", "L0402", "47 nH", (0, 0), 0, {1: "VCC_RF_F", 2: "RF_ANT"}, "C97998", "LQG15HS47NJ02D (Murata)", "ZED", sym="R",
     note="alimentación de la antena activa por el vivo del coaxial (choque de RF)")
R("R71", "0R", "RF_ANT", "RF_ZED", block="ZED",
  note="puente de 0 Ω en la línea de 50 Ω (≈ 0,36 mm): la referencia de u-blox (UBX-18010802, fig. 42) pone la bobina "
       "directamente sobre RF_IN; el pad admite un condensador de RF si hiciera falta bloquear la continua")
part("D4", "C0402", "ESD RF 0,25 pF", (0, 0), 0, {1: "RF_ANT", 2: GND}, "C10662", "PESD0402-140 (Littelfuse/TE)",
     "ZED", sym=dict(L=[(1, "IO")], R=[(2, "GND")]),
     note="ESD obligatoria en la entrada de RF según el manual de integración del ZED-F9P")
part("J5", "UFL", "U.FL GNSS", (0, 0), 0, {1: "RF_ANT", 2: GND}, "C88373", "U.FL-R-SMT-1(10) (Hirose)", "ZED",
     sym=dict(L=[(1, "SIG")], R=[(2, "GND")]), note="cable de la antena plana activa L1/L2 (AHP2258 o similar)")
R("R50", "1k", "S3_TX1", "ZED_RX1", block="ZED", note="serie: limita la alimentación parásita del ZED apagado")
R("R51", "1k", "S3_TX2", "ZED_RX2", block="ZED")
R("R52", "1k", "S3_ZRST", "ZED_RST", block="ZED", note="RESET_N del ZED (GPIO9 en colector abierto)")
R("R53", "330R", "ZED_TX1_C", "ZED_TX1", block="ZED")
R("R54", "330R", "ZED_TX2_C", "ZED_TX2", block="ZED")
R("R55", "330R", "ZED_PPS_C", "ZED_PPS", block="ZED", note="PPS → GPIO4")

# ---------------------------------------------------------------------------------------- ESP32-S3 (U4)
# REV B: ESP32-S3-WROOM-1U-N16R8 (pines del módulo según su hoja de datos y el símbolo de Espressif). Con la PSRAM octal
# (R8) los GPIO35–37 son del módulo: sin conectar. GPIO de la REV A conservados salvo el RX de la UART2 del ZED, que
# pasa de IO7 a IO3 (pad de la fila inferior, junto a los pines 26/27 del ZED): el ruteado no cerraba la IMU por el
# pasillo ZED ↔ módulo (CI 44177067166). Nuevos: IO7 = IMU_INT1 (RTC: despierta por movimiento) · IO3 = ZED_TX2 (RX)
# · IO11 = TOUCH_SENSE (RTC) · IO41/IO42 = I²C (medidor + IMU)
# · IO46 = POWER_HOLD (de arranque, bajo por defecto) · IO48 = LED_PWR (EN del elevador del anillo).
GPIO = {  # pad del módulo: (GPIO, red)
    2: ("3V3", V3), 3: ("EN", "EN"),
    4: ("IO4", "ZED_PPS"), 5: ("IO5", "ZED_TX1"), 6: ("IO6", "S3_TX1"), 7: ("IO7", "IMU_INT1"),
    8: ("IO15", "SD_D1"), 9: ("IO16", "SD_D2"), 10: ("IO17", "SD_D3"), 11: ("IO18", "VBUS_DET"), 12: ("IO8", "S3_TX2"),
    13: ("IO19 D-", "USB_DM"), 14: ("IO20 D+", "USB_DP"), 15: ("IO3", "ZED_TX2"), 16: ("IO46", "PWR_HOLD"),
    17: ("IO9", "S3_ZRST"), 18: ("IO10", "ZED_EN"), 19: ("IO11", "TOUCH_SENSE"), 20: ("IO12", "SD_CLK0"),
    21: ("IO13", "SD_CMD"), 22: ("IO14", "SD_D0"), 23: ("IO21", "SD_PWR_N"), 24: ("IO47", "LED_DIN_S3"),
    25: ("IO48", "LED_PWR"), 26: ("IO45", None), 27: ("IO0", "BOOT"), 28: ("IO35_PSRAM", None),
    29: ("IO36_PSRAM", None), 30: ("IO37_PSRAM", None), 31: ("IO38", "CHG_PG"), 32: ("IO39", "CHG_STAT"),
    33: ("IO40", "POGO_AUX"), 34: ("IO41", "I2C_SCL"), 35: ("IO42", "I2C_SDA"), 36: ("RXD0", "U0RX"),
    37: ("TXD0", "U0TX"), 38: ("IO2", "BAT_ADC"), 39: ("IO1", "HALL"),
}
GND_PADS = (1, 40, 41)
u4nets = {n: GND for n in GND_PADS}
u4nets.update({k: v[1] for k, v in GPIO.items()})
part("U4", "WROOM1U", "ESP32-S3-WROOM-1U-N16R8", (0, 0), 0, u4nets, LC["WROOM1U"], "ESP32-S3-WROOM-1U-N16R8", "ESP32-S3",
     sym=dict(L=[(k, v[0] + (" " + v[1] if v[1] and v[1] not in (V3,) else "")) for k, v in sorted(GPIO.items()) if k <= 20],
              R=[(k, v[0] + (" " + v[1] if v[1] else "")) for k, v in sorted(GPIO.items()) if 20 < k] +
                [(n, "GND") for n in GND_PADS]),
     note="16 MB de flash + 8 MB de PSRAM octal (3,2 mm de alto). Antena FPC de 2,4 GHz en el U.FL del módulo, pegada "
          "a la pared de la cápsula (lejos de la GNSS)")
C("C24", "22u 10V", V3, GND, block="ESP32-S3", fp="C0805")
C("C25", "100n", V3, GND, block="ESP32-S3")
C("C26", "1u", V3, GND, block="ESP32-S3")
R("R11", "10k", "EN", V3, block="ESP32-S3")
C("C27", "1u", "EN", GND, block="ESP32-S3", note="EN: RC 10 k / 1 µF (guía de diseño de Espressif)")

# ---------------------------------------------------------------------------------------- anillo de luz (4 LED laterales)
# Petición del usuario (14/11/2026): anillo translúcido de resina en la unión base–tapa, iluminado desde dentro. 8 SK6812SIDE-A
# (2 por lado, ≈ 27 mm entre LED a lo largo del anillo) en los cantos de la placa (cara F), con la lente hacia la pared, en
# cadena: arriba izq. → arriba der. → derecha arriba → derecha abajo → abajo der. → abajo izq. → izquierda abajo → izquierda arriba.
# REV B: VDD = VLED (4,3 V del elevador TPS61023). La hoja pide 3,7–5,5 V (pág. 6) y cada LED gasta 0,6 mA en reposo:
# con EN = 0 el TPS61023 desconecta la salida de la entrada («true disconnection», 0,1 µA), así que el anillo no
# consume con el casco dormido ni apagado. DIN a 3,3 V: VIH = 0,65 × 4,3 ≈ 2,8 V (por encima de 4,3 V de VSYS, al
# cargar, el elevador pasa la entrada: VIH ≈ 2,9 V). El firmware deja GPIO47 a 0 con el anillo apagado.
R("R24", "33R", "LED_DIN_S3", "LED_D1", block="Anillo", note="serie de la línea de datos (GPIO47)")
LEDS = ["D%d" % (10 + k) for k in range(8)]
for i, ref in enumerate(LEDS):
    part(ref, "LEDSIDE", "SK6812SIDE-A", (0, 0), 0,
         {1: "LED_D%d" % (i + 1), 2: "VLED", 3: ("LED_D%d" % (i + 2)) if i < len(LEDS) - 1 else None, 4: GND},
         LC["SK6812SIDE"], "SK6812SIDE-A (OPSCO)", "Anillo",
         sym=dict(L=[(1, "DIN"), (2, "VDD")], R=[(3, "DOUT"), (4, "GND")]), note="RGB direccionable, emisión lateral")
    C("C%d" % (90 + i), "100n", "VLED", GND, block="Anillo")
part("U11", "SOT563", "TPS61023DRLR", (0, 0), 0, {1: "VLED_FB", 2: "LED_PWR", 3: VSYS, 4: GND, 5: "VLED_SW", 6: "VLED"},
     LC["TPS61023"], "TPS61023DRLR (TI)", "Anillo",
     sym=dict(L=[(3, "VIN"), (2, "EN"), (1, "FB")], R=[(6, "VOUT"), (5, "SW"), (4, "GND")]),
     note="elevador síncrono 3,7 A, 1 MHz; V_REF 0,595 V; pasa la entrada si VIN > VOUT; salida desconectada con EN = 0")
part("L71", "L0806", "1 µH", (0, 0), 0, {1: VSYS, 2: "VLED_SW"}, LC["1uH 0806"], "WPN201610U1R0MT (Sunlord)", "Anillo",
     sym="R", note="1 µH, I_sat 3 A, 50 mΩ (≈ 0,45 A de pico con los 8 LED a tope desde 3 V)")
C("C98", "10u 25V", VSYS, GND, block="Anillo", fp="C0603", note="entrada del elevador")
C("C99", "22u 10V", "VLED", GND, block="Anillo", fp="C0805", note="salida del elevador (≥ 10 µF efectivos)")
R("R25", "620k", "VLED", "VLED_FB", block="Anillo", note="V_OUT = 0,595 × (1 + 620k/100k) ≈ 4,28 V")
R("R26", "100k", "VLED_FB", GND, block="Anillo")
R("R27", "100k", "LED_PWR", GND, block="Anillo", note="elevador apagado por defecto (arranque y casco apagado)")

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

# ---------------------------------------------------------------------------------------- REV B: bus I²C (medidor + IMU)
# I²C a 400 kHz en GPIO41 (SCL) / GPIO42 (SDA): MAX17048 en 0x36, LSM6DSV16X en 0x6A (SA0 = 0). Pull-ups al 3,3 V
# principal: con el casco apagado el bus queda a 0 y el MAX17048 sigue midiendo (sin EnSleep no entra en reposo por el
# bus; SDA/SCL aguantan 5,5 V con independencia de VDD).
R("R28", "2k2", "I2C_SCL", V3, block="I2C", note="pull-up I²C (400 kHz)")
R("R29", "2k2", "I2C_SDA", V3, block="I2C")
part("U12", "TDFN8", "MAX17048G+T10", (0, 0), 0,
     {1: GND, 2: VBAT, 3: VBAT, 4: GND, 5: None, 6: GND, 7: "I2C_SCL", 8: "I2C_SDA", 9: GND},
     LC["MAX17048"], "MAX17048G+T10 (Analog Devices)", "Medidor",
     sym=dict(L=[(3, "VDD"), (2, "CELL"), (1, "CTG"), (6, "QSTRT")], R=[(7, "SCL"), (8, "SDA"), (5, "ALRT"), (4, "GND"), (9, "EP")]),
     note="medidor ModelGauge (% de batería sin resistencia de medida): VDD y CELL a la celda (tras Q7), CTG y QSTRT a GND, "
          "ALRT sin usar (se lee por I²C). ≈ 3 µA en hibernación: sigue contando con el casco apagado")
C("C36", "1u", VBAT, GND, block="Medidor", note="VDD del MAX17048, pegado al pin 3")
part("U13", "LGA14", "LSM6DSV16X", (0, 0), 0,
     {1: GND, 2: GND, 3: GND, 4: "IMU_INT1", 5: V3, 6: GND, 7: GND, 8: V3, 9: None, 10: None, 11: None, 12: V3,
      13: "I2C_SCL", 14: "I2C_SDA"},
     LC["LSM6DSV16X"], "LSM6DSV16XTR (ST)", "IMU",
     sym=dict(L=[(8, "VDD"), (5, "VDDIO"), (12, "CS"), (1, "SDO/SA0"), (2, "SDx"), (3, "SCx"), (6, "GND"), (7, "GND")],
              R=[(13, "SCL"), (14, "SDA"), (4, "INT1"), (9, "INT2"), (10, "OCS_Aux"), (11, "SDO_Aux")]),
     note="IMU del casco (la misma que la cincha REV D): movimiento de la cabeza frente al tronco, reposo automático y "
          "caídas. INT1 → GPIO7 (RTC: despierta del sueño por movimiento)")
C("C37", "100n", V3, GND, block="IMU", note="VDD del LSM6")
C("C38", "100n", V3, GND, block="IMU", note="VDDIO del LSM6")

# ---------------------------------------------------------------------------------------- pruebas y mecánica
TP("TP1", "EN", "EN"); TP("TP2", "BOOT", "BOOT", "GPIO0 a GND al arrancar = descarga (también por USB nativo)")
TP("TP3", "GND", GND); TP("TP4", "TXD0", "U0TX"); TP("TP5", "RXD0", "U0RX"); TP("TP6", "3V3", V3)
TP("TP7", "VBAT", VBAT); TP("TP8", "VSYS", VSYS); TP("TP9", "3V3_ZED", VZED); TP("TP10", "3V3_AON", "+3V3_AON")
TP("TP12", "VLED", "VLED", "4,3 V del anillo (solo con LED_PWR = 1)")
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
