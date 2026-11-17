"""AVO GIRTH · montaje del sistema en una cincha de caballo (cápsula REV 6, funda de piel y electrodos ECG).

Diseño · NO VERIFICADO en caballo real.

Genera (en ../out):
  STEP/  conjunto montado (curvado sobre el tórax y recto), ensamblaje por subconjuntos y STEP de cada pieza;
  STL/   piezas impresas (PETG / TPU) en posición de impresión;
  informe.json  (medidas, comprobaciones de estanqueidad de cada sólido, volúmenes, holguras).

Coordenadas de la cincha (u, v, w), en mm:
  u: a lo largo de la cincha, 0 en el centro (bajo el esternón), + hacia el lado IZQUIERDO del caballo;
  v: a lo ancho, + hacia el canto TRASERO (cola), − hacia el canto DELANTERO (codos);
  w: grosor, 0 = piel del caballo (cara interior de la funda), + hacia fuera.
Mundo del conjunto curvado: X + = izquierda del caballo, Y + = hacia la cabeza, Z + = arriba; origen en la piel, bajo
el esternón, en el plano de la cincha (justo detrás de los codos). Conjunto recto: X = u, Y = v, Z = w (cincha
tumbada sobre la mesa con la cara interior abajo).

Uso:  python3 avo_cincha_montaje.py
"""
import json
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avo_cad as A   # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "out"))
os.makedirs(os.path.join(OUT, "STEP", "piezas"), exist_ok=True)
os.makedirs(os.path.join(OUT, "STL"), exist_ok=True)

# =============================================================================================== colores (RGB 0..1)
C_PETG = (0.12, 0.13, 0.14)        # PETG negro
C_PETG_TAPA = (0.80, 0.10, 0.12)   # PETG rojo AVO (opaco)
C_PETG_TRANS = (0.86, 0.88, 0.84)  # PETG translúcido «natural» (base = aro de luz)
C_LED = (0.97, 0.97, 0.92)
C_TPU = (0.15, 0.15, 0.16)
C_TPU_ROJO = (0.85, 0.15, 0.15)
C_PCB = (0.05, 0.35, 0.15)
C_IC = (0.10, 0.10, 0.10)
C_PAS = (0.55, 0.45, 0.30)
C_METAL = (0.72, 0.73, 0.75)
C_ORO = (0.85, 0.68, 0.25)
C_BAT = (0.25, 0.35, 0.70)
C_IMAN = (0.55, 0.55, 0.60)
C_CABLE = (0.08, 0.08, 0.08)
C_HILO = {"r": (0.8, 0.1, 0.1), "n": (0.1, 0.1, 0.1), "a": (0.9, 0.8, 0.1), "v": (0.1, 0.6, 0.2), "b": (0.9, 0.9, 0.9),
          "az": (0.1, 0.3, 0.8)}
C_CUERO = (0.36, 0.20, 0.10)       # piel curtido vegetal teñida marrón
C_CUERO_OSC = (0.22, 0.12, 0.06)
C_TELA = (0.42, 0.30, 0.20)        # cincha de tela marrón (Decathlon)
C_CINTA = (0.18, 0.15, 0.13)
C_ELAST = (0.70, 0.62, 0.50)
C_VELCRO = (0.10, 0.10, 0.10)
C_ELECTRODO = (0.12, 0.12, 0.12)
C_CABALLO = (0.55, 0.38, 0.24)

# =============================================================================================== parámetros
P = dict(
    # tórax del caballo (sección en el plano de la cincha, justo detrás del codo)
    torax_perimetro=1880.0,       # 500 kg ≈ 185 cm (OMAFRA); PSI húngaro 192 cm (Hrčak); se toma 188 cm
    torax_ancho=480.0,            # anchura de pecho 48,0 cm (PSI, Hrčak)
    torax_n=2.15,                 # exponente de la superelipse (vientre algo más plano que una elipse)
    # cincha tipo Decathlon Fouganza (tela con elásticos): medidas de catálogo + estimadas por la foto
    cincha_largo=1100.0,          # talla del ejemplo (punta de hebilla a punta de hebilla)
    cincha_ancho=110.0,           # ESTIMADO por la foto (10–12 cm)
    cincha_grosor=8.0,            # ESTIMADO (acolchada)
    cinta_central_ancho=50.0,     # cinta oscura central (ESTIMADO)
    hebilla_int=(25.0, 14.0),     # hebilla de rodillo inox de 25 mm (pethardware: luz 25 × 14, varilla 5)
    correa_ancho=25.0,
    # funda de piel
    funda_largo=800.0,
    holgura_delante=7.0,          # canal delantero para el cable (entre el canto de la cincha y el pliegue)
    holgura_detras=1.0,
    holgura_arriba=4.0,           # entre la cincha y el panel exterior (paso del cable hasta el canal)
    cuero=2.0,                    # piel de curtido vegetal de 2,0 mm (≈ 5 oz)
    # electrodos (centro u, v) en la cara interior: Vialta PG980/51 (caucho conductor 60 × 85 con cable moldeado)
    e_pos={"ECG+": (190.0, -20.0), "REF": (-150.0, -20.0), "ECG-": (-280.0, -20.0)},
    e_tam={"ECG+": (85.0, 60.0), "ECG-": (85.0, 60.0), "REF": (60.0, 40.0)},   # (a lo largo de u, a lo ancho v)
    e_ventana_margen=5.0,         # la piel solapa 5 mm el borde del electrodo (costura perimetral a 4–5 mm)
    e_grosor=2.0,                 # caucho conductor (ESTIMADO 2 mm)
    eva=2.5,                      # espuma EVA / neopreno detrás del electrodo
)

# ---------------------------------------------------------------------------------------------- pila en w (funda)
W_IN0, W_IN1 = 0.0, P["cuero"]                 # panel interior (piel del caballo en w = 0)
W_REB = W_IN0 + 1.0                            # piel rebajada a 1,0 mm alrededor de la ventana del electrodo
W_E0 = W_REB                                   # electrodo (detrás de la piel, asoma por la ventana)
W_E1 = W_E0 + P["e_grosor"]
W_FR1 = W_E1 + P["eva"]                        # espuma EVA detrás del electrodo
W_G0 = W_FR1 + 0.4                             # cincha
W_G1 = W_G0 + P["cincha_grosor"]
W_OUT0 = W_G1 + P["holgura_arriba"]            # panel exterior
W_OUT1 = W_OUT0 + P["cuero"]
VG = P["cincha_ancho"] / 2
VF_D = VG + P["holgura_delante"] + P["cuero"]  # canto delantero exterior de la funda (v = −VF_D)
VF_T = VG + P["holgura_detras"] + P["cuero"]   # canto trasero exterior (v = +VF_T)
UF = P["funda_largo"] / 2

# ---------------------------------------------------------------------------------------------- cápsula REV 6.1
# REV 6.1: base entera de PETG translúcido «natural» (es el aro de luz: rodea la PCB a la altura de los 4 LED) y tapa
# plana de PETG opaco. La junta sube por encima de la PCB (z = 13,0): una sola junta TPU 85A en ranura, con los 6
# tornillos FUERA de la línea de estanqueidad (insertos ciegos en orejas macizas).
CAP = dict(
    I=dict(x0=-25.5, x1=25.5, y0=-26.25, y1=17.5, r=2.5),   # hueco interior (celda 50 × 34 + placas pogo en −Y)
    pared=4.0,                     # pared gruesa: ranura de 1,9 + 2 × 1,05 de apoyo; difusor de 4 mm
    suelo=1.7,                     # = altura de la cara de la placa pogo (queda a ras)
    bat=(50.0, 34.0, 6.0),         # LiPo 603450 1000 mAh
    pad=1.2,                       # separador TPU 85A celda–PCB
    pcb=1.0,
    comp=2.6,                      # altura máx. de componente (REV D; SK6812SIDE-A = 2,0)
    aire=0.5,
    techo=2.5,                     # tapa plana opaca
    ranura=dict(off0=1.05, off1=2.95, prof=1.2),             # ranura de la junta (desde el hueco I)
    junta=dict(off0=1.4, off1=2.6, alto=1.6),                # junta TPU 85A 1,2 × 1,6 → 25 % de compresión
    lengueta=1.0, lengueta_alto=1.2,
    pogo_y=-21.4, pogo_x={"ECG": -13.0, "CARGA": 13.0},
    tornillo_off=5.2,              # centro de los tornillos a 5,2 mm del hueco (fuera de la ranura)
    boss_r=3.0,
)
OREJA = dict(y=27.3, r_agujero=1.6)   # oreja maciza en la tapa, agujero vertical Ø3,2 para el cordón
LEDS = [("D10", -15.0, 13.30, +1), ("D11", 14.0, 13.30, +1), ("D12", 14.0, -13.30, -1), ("D13", -15.0, -13.30, -1)]
LED_LENTE_Y = 14.66                # cara de la lente (a 0,34 mm del canto de la PCB)


def _tornillos():
    I = CAP["I"]; r = I["r"]; d = CAP["tornillo_off"]
    k = (r + d) / math.sqrt(2)
    xs = (I["x0"] + r, I["x1"] - r); ys = (I["y0"] + r, I["y1"] - r)
    return [(xs[0] - k, ys[1] + k), (xs[1] + k, ys[1] + k), (xs[0] - k, ys[0] - k), (xs[1] + k, ys[0] - k),
            (0.0, I["y1"] + d), (0.0, I["y0"] - d)]


CAP["tornillos"] = _tornillos()
ZB0 = CAP["suelo"]                             # celda
ZB1 = ZB0 + CAP["bat"][2]
ZP0 = ZB1 + CAP["pad"]                          # PCB cara B
ZP1 = ZP0 + CAP["pcb"]                          # PCB cara F
ZC1 = ZP1 + CAP["comp"]
ZT0 = ZC1 + CAP["aire"]                         # cara inferior de la tapa = canto superior de la base
ZT1 = ZT0 + CAP["techo"]                        # cara superior de la cápsula
ZJ0, ZJ1 = ZT0 - CAP["ranura"]["prof"], ZT0     # ranura de la junta en el canto de la base
Z_LED = ZP1 + 1.0                               # centro de la luz de los LED
H_CAP = ZT1

# soporte
SOP = dict(holgura=0.25, cerco=3.0, cerco_h=4.5, cama=8.0, pestana=2.5, ala=8.0,
           precarga=0.7)               # la cápsula apoya en 4 tacos TPU 85A: fondo a 0,7 mm sobre la cama (compresión 0,15)
# REV 6.3 (16/11/2026, decisión del usuario): CIERRE MAGNÉTICO DE BALANCÍN en cada lado corto ±X. Sustituye a los
# pestillos elásticos y a los seguros TPU de la REV 6.2. Cerco de 2,0 → 3,0 (aloja los imanes).
#  - El balancín va en la cápsula, por fuera del cerco, con la cara superior A RAS DE LA TAPA (protección contra golpes).
#    Gira sobre 2 pasadores CORTOS de acero ISO 2338 Ø2 × 6 metidos a presión en 2 aletas de la base (las aletas pasan
#    por ranuras del cerco: llave de posición, balancín de 14 mm en +X y de 12 mm en −X).
#  - Por debajo del eje, 2 dientes RECTOS entran 1,0 mm en ventanas de la cara exterior del cerco. 2 + 2 imanes Ø5 × 1
#    (los de siempre, apilados de 2) en el balancín y en el cerco se ATRAEN y mantienen los dientes dentro (sin muelle).
#  - Los 4 tacos TPU y los pogo empujan la cápsula hacia arriba: el diente queda cargado contra el techo de la ventana
#    (sin juego) y, cargado, el rozamiento y los imanes impiden abrirlo. Para abrir: empujar la cápsula hacia abajo y
#    apretar los dos balancines por arriba hacia dentro (una mano). Para cerrar: bajarla; el bisel del diente resbala.
#  - Imanes con orificio y tapa impresa (sin pausa de impresión). Sin imanes de repulsión arriba: en la REV 6 la
#    pared de la base lleva la ranura de la junta a z 11,8–13,0 y la tapa solo tiene 2,5 mm (no caben a una altura útil).
END_T = 5.0     # REV 6.4: cada extremo ±X de la cápsula crece 5 mm hacia fuera (pared plana con el balancín empotrado)
# REV 6.4 (17/11/2026, captura del usuario): BALANCÍN EMPOTRADO A RAS en la pared del extremo (sustituye a la REV 6.3.x,
# que iba por fuera con aletas). La junta no se toca: el hueco queda fuera de su línea.
#  - Eje: pasador de acero ISO 2338 Ø2 × 20 (+X) / Ø2 × 18 (−X) que atraviesa el balancín y descansa en 2 ranuras
#    verticales de las paredes del hueco; las cierran 2 lengüetas de la tapa al atornillarla (sin aletas ni tornillos).
#  - Imanes: 2 + 2 Ø5 × 1 por lado entre el balancín (abajo, cara interior) y el fondo del hueco: tiran de la parte de
#    abajo hacia dentro, contra el tope del hueco (balancín a ras), y mantienen el diente dentro. Orificio + tapa.
#  - Diente recto en la parte del balancín que baja por debajo de la cápsula: engancha en una ventana de la cama del
#    soporte. Los tacos TPU y los pogo lo cargan hacia arriba.
#  - Abrir: empujar la cápsula hacia abajo y apretar arriba los 2 balancines hacia dentro. Cerrar: bajarla (bisel).
BAL = dict(t=3.1, t_low=4.3, w={1: 14.0, -1: 12.0}, side=0.25, back_low=0.3, back_up=1.5, pz_c=8.0, dx_eje=0.2,
           z_grueso=9.6, hole=1.95, pin_len={1: 20.0, -1: 18.0}, slot_w=2.05, blk=3.25, blk_emb=0.5,
           tongue_gap=0.05, tongue_clear=0.1,
           mag=5.1, mag_t=2.1, mag_c=3.7, skin_w=0.65, cb=0.55, cap_lip=0.25, cap_t=0.5, chaf=0.3,
           bot_c=-4.0, e=1.0, top_c=-1.9, tip_b_c=-2.4, root_b_c=-3.3, ty0=3.5, tyend=0.6, roof_gap=0.05,
           win_deep=0.5, win_w=0.3, pock_out=2.5, pock_clear=0.25)
# t: grueso del balancín por encima del eje; t_low: por debajo (llega al tope del hueco, a back_low); el hueco de la
# pared es CONSTANTE en toda la altura (fondo a back_up del balancín de arriba): el núcleo poliédrico no admite
# contornos exteriores que cambien de una capa a otra en un solo punto. Los cojinetes del eje (bloques a los lados
# del balancín, con la ranura del pasador abierta por arriba) se imprimen con la base, en el mismo STL.
TACOS = [(-27.3, 6.0), (27.3, 6.0), (-27.3, -15.0), (27.3, -15.0)]
REPORT = {"parametros": {}, "piezas": {}, "comprobaciones": []}


def note(msg):
    REPORT["comprobaciones"].append(msg)
    print("  ·", msg)


# =============================================================================================== curva del tórax
class Torax:
    def __init__(self, perim, ancho, n):
        self.n = n
        a = ancho / 2

        def curve(a, b, N=20000):
            t = np.linspace(-math.pi, math.pi, N, endpoint=False)
            c, s = np.cos(t), np.sin(t)
            x = a * np.sign(c) * np.abs(c) ** (2 / n)
            z = b * np.sign(s) * np.abs(s) ** (2 / n)
            return x, z

        def perimeter(b):
            x, z = curve(a, b)
            return float(np.sum(np.hypot(np.diff(np.r_[x, x[0]]), np.diff(np.r_[z, z[0]]))))
        lo, hi = a * 0.5, a * 3
        for _ in range(60):
            mid = (lo + hi) / 2
            if perimeter(mid) < perim:
                lo = mid
            else:
                hi = mid
        self.a, self.b = a, (lo + hi) / 2
        # parametrización por longitud de arco desde el punto más bajo (θ = −π/2), + hacia +X
        t = np.linspace(-math.pi / 2 - math.pi, -math.pi / 2 + math.pi, 40001)
        c, s = np.cos(t), np.sin(t)
        x = self.a * np.sign(c) * np.abs(c) ** (2 / n)
        z = self.b * np.sign(s) * np.abs(s) ** (2 / n) + self.b
        d = np.r_[0, np.cumsum(np.hypot(np.diff(x), np.diff(z)))]
        d -= np.interp(-math.pi / 2, t, d)
        self.s, self.x, self.z = d, x, z
        self.perim = perimeter(self.b)

    def point(self, s):
        s = np.asarray(s, float)
        x = np.interp(s, self.s, self.x); z = np.interp(s, self.s, self.z)
        h = 0.5
        x1 = np.interp(s + h, self.s, self.x); z1 = np.interp(s + h, self.s, self.z)
        x0 = np.interp(s - h, self.s, self.x); z0 = np.interp(s - h, self.s, self.z)
        tx, tz = x1 - x0, z1 - z0
        L = np.hypot(tx, tz)
        return x, z, tx / L, tz / L

    def radius(self, s):
        x, z, tx, tz = self.point(s)
        x2, z2, tx2, tz2 = self.point(s + 2.0)
        ang = math.atan2(tx * tz2 - tz * tx2, tx * tx2 + tz * tz2)
        return 2.0 / ang if ang else float("inf")

    def outline(self, n=400):
        t = np.linspace(-math.pi, math.pi, n, endpoint=False)
        c, s = np.cos(t), np.sin(t)
        return np.c_[self.a * np.sign(c) * np.abs(c) ** (2 / self.n), self.b * np.sign(s) * np.abs(s) ** (2 / self.n) + self.b]


TX = Torax(P["torax_perimetro"], P["torax_ancho"], P["torax_n"])


def bend_curvo(UVW):
    """(u, v, w) → mundo curvado (X izq., Y cabeza, Z arriba)"""
    UVW = np.asarray(UVW, float)
    u, v, w = UVW[:, 0], UVW[:, 1], UVW[:, 2]
    x, z, tx, tz = TX.point(u)
    nx, nz = tz, -tx                         # normal hacia fuera
    return np.c_[x + w * nx, -v, z + w * nz]


def bend_recto(UVW):
    return np.asarray(UVW, float).copy()


def frame(u, v, w, curvo=True, rot_deg=0.0):
    """matriz 4×4 local (x a lo largo de u, y a lo largo de v, z hacia fuera) → mundo"""
    R = A.T_rotz(rot_deg)
    if not curvo:
        M = np.eye(4); M[:3, 3] = (u, v, w)
        return M @ R
    x, z, tx, tz = TX.point(u)
    T = np.array([tx, 0, tz]); V = np.array([0, -1.0, 0]); N = np.array([tz, 0, -tx])
    M = np.eye(4)
    M[:3, 0], M[:3, 1], M[:3, 2] = T, V, N
    M[:3, 3] = np.array([x, 0, z]) + N * w + V * v
    return M @ R


def fix_orient(m):
    if m.volume() < 0:
        m.F = [[L[::-1] for L in f] for f in m.F]
    return m


def bend_mesh(m, curvo):
    m.map(bend_curvo if curvo else bend_recto)
    return fix_orient(m)


def swap_uwv(m):
    """malla construida en (u, w, v) → (u, v, w)"""
    m.transform(A.swap_axes(("x", "z", "y")))
    return fix_orient(m)


# =============================================================================================== contornos de la cápsula
def bal_x():
    """REV 6.4: cotas del cierre en el lado +X (el de −X es simétrico): cara exterior de la pared (= del balancín),
    cara interior del balancín por encima (xi) y por debajo del eje (xl), fondo del hueco, centro del eje y centro
    del lado corto en Y"""
    I = CAP["I"]
    xo = I["x1"] + CAP["pared"] + END_T
    xi = xo - BAL["t"]
    xl = xo - BAL["t_low"]
    return dict(xw=xo, xo=xo, xi=xi, xl=xl, xb=xi - BAL["back_up"], px=xl + 1.2 + BAL["dx_eje"],
                yc=(I["y0"] + I["y1"]) / 2)


def _rrx(sg, x0, x1, y0, y1):
    """rectángulo en planta dado en el lado +X, reflejado al lado sg"""
    xa, xb = sorted((sg * x0, sg * x1))
    return A.rrect((xa + xb) / 2, (y0 + y1) / 2, xb - xa, y1 - y0, 0, 1)


def cap_contours():
    I = CAP["I"]
    cx, cy = (I["x0"] + I["x1"]) / 2, (I["y0"] + I["y1"]) / 2
    w, h = I["x1"] - I["x0"], I["y1"] - I["y0"]
    C = {}
    C["I"] = A.rrect(cx, cy, w, h, I["r"], 6)
    C["O0"] = A.rrect(cx, cy, w + 2 * CAP["pared"] + 2 * END_T, h + 2 * CAP["pared"], I["r"] + CAP["pared"], 6)
    R = A.Raster(-50, -48, 50, 40, 0.02)
    R.add(C["O0"])
    for (x, y) in CAP["tornillos"]:
        R.add(A.circle(x, y, CAP["boss_r"], 40))
    C["O"] = R.contour(0.03)
    C["_rasterO"] = R
    # REV 6.4: hueco del balancín en cada extremo, constante en toda la altura (fondo xb; a los lados, sitio para los
    # cojinetes del eje, que van en piezas aparte del mismo STL)
    K = bal_x()
    xo, xi, xb, yc = K["xo"], K["xi"], K["xb"], K["yc"]
    Rp = A.Raster(R.x0, R.y0, R.x0 + R.W * R.res, R.y0 + R.H * R.res, R.res); Rp.m = R.m.copy()
    for sg in (1, -1):
        hw = BAL["w"][sg] / 2 + BAL["side"] + BAL["blk"] - BAL["blk_emb"]
        Rp.sub(_rrx(sg, xb, xo + 2.0, yc - hw, yc + hw))
    C["O"] = Rp.contour(0.03)
    C["O_chaflan"] = Rp.offset(-BAL["chaf"]).contour(0.03)            # chaflán del fondo (entrada)
    Rl = A.Raster(-50, -48, 50, 40, 0.02)
    Rl.add(C["O0"])
    for (x, y) in CAP["tornillos"]:
        Rl.add(A.circle(x, y, CAP["boss_r"], 40))
    Rl.add(A.rrect(0.0, OREJA["y"] - 0.5, 12.0, 7.0, 3.0, 6))            # oreja del cordón de seguridad
    for sg in (1, -1):                                                 # REV 6.4: hueco del balancín (arriba)
        hw = BAL["w"][sg] / 2 + BAL["side"]
        Rl.sub(_rrx(sg, xb, xo + 2.0, yc - hw, yc + hw))
    C["O_tapa"] = Rl.contour(0.03)
    for nm, (o0, o1) in (("g", (CAP["ranura"]["off0"], CAP["ranura"]["off1"])),
                         ("j", (CAP["junta"]["off0"], CAP["junta"]["off1"]))):
        C[nm + "I"] = A.rrect(cx, cy, w + 2 * o0, h + 2 * o0, I["r"] + o0, 6)
        C[nm + "O"] = A.rrect(cx, cy, w + 2 * o1, h + 2 * o1, I["r"] + o1, 6)
    lg = CAP["lengueta"]
    C["I_l0"] = A.rrect(cx, cy, w - 0.4, h - 0.4, I["r"] - 0.2, 6)            # cara exterior de la lengüeta
    C["I_l1"] = A.rrect(cx, cy, w - 0.4 - 2 * lg, h - 0.4 - 2 * lg, max(0.5, I["r"] - 0.2 - lg), 6)
    return C


def pogo_plate_contours(cx, cy):
    """placa de contactos planos (lado cápsula), medidas del STEP real del usuario (REV 5.9.1)"""
    return dict(face=A.stadium(cx, cy, 15.5, 4.65), flange=A.stadium(cx, cy, 17.1, 6.25),
                contacts=[(cx + dx, cy) for dx in (-2.3, 0.0, 2.3)], mags=[(cx + dx, cy) for dx in (-5.425, 5.425)])


# =============================================================================================== piezas de la cápsula
def pieza_base():
    """REV 6.4: base con los extremos 5 mm más largos y el hueco del balancín empotrado (constante en altura). El imán
    del lado de la cápsula entra por un pozo desde la cara inferior (se tapa con un tapón); los cojinetes del eje son
    piezas aparte del mismo STL (pieza_cojinetes)."""
    C = cap_contours()
    O, I = C["O"], C["I"]
    win, cupi, cupo = [], [], []
    for k, x in CAP["pogo_x"].items():
        y = CAP["pogo_y"]
        win.append(A.stadium(x, y, 15.5 + 0.4, 4.65 + 0.4))
        cupi.append(A.stadium(x, y, 17.1 + 0.6, 6.25 + 0.6))
        cupo.append(A.stadium(x, y, 17.1 + 0.6 + 1.6, 6.25 + 0.6 + 1.6))
    ins = [A.circle(x, y, 1.6, 24) for (x, y) in CAP["tornillos"]]     # insertos M2 × 4 ciegos (Ø3,2 × 5)
    z_ins = ZT0 - 5.0
    z_cup = 5.0
    assert z_cup < z_ins < ZJ0
    K = bal_x()
    b = BAL
    xm1 = K["xb"] - b["skin_w"]
    pozo = [_rrx(sg, xm1 - b["mag_t"], xm1, K["yc"] - b["mag"] / 2 - 0.025, K["yc"] + b["mag"] / 2 + 0.025)
            for sg in (1, -1)]
    zp = b["mag_c"] + b["mag"] / 2 + 0.05                              # techo del pozo del imán
    assert zp < z_ins
    zs = sorted({0.0, b["chaf"], ZB0, z_cup, zp, z_ins, ZJ0, ZT0})
    L = []
    for z0, z1 in zip(zs[:-1], zs[1:]):
        zm = (z0 + z1) / 2
        o = C["O_chaflan"] if zm < b["chaf"] else O
        if zm < ZB0:
            cs = [o] + win
        elif zm < z_cup:
            cs = [o, I] + cupo + cupi
        elif zm < z_ins:
            cs = [o, I]
        elif zm < ZJ0:
            cs = [o, I] + ins
        else:
            cs = [o, I, C["gO"], C["gI"]] + ins
        if zm < zp:
            cs = cs + pozo
        L.append((z0, z1, cs))
    return A.layered(L, "AVO_CINCHA_R6_4_base_aro_luz", C_PETG_TRANS)


def pieza_cojinetes(sg):
    """REV 6.4: los 2 cojinetes del eje del lado sg, a los lados del balancín, dentro del hueco de la pared y a ras de
    su cara. Ranura del pasador abierta por arriba (la cierra una lengüeta de la tapa). Se imprimen con la base (mismo
    STL; entran 0,5 mm en la pared)."""
    K = bal_x()
    b = BAL
    xo, xb, px, yc = K["xo"], K["xb"], K["px"], K["yc"]
    pz = b["pz_c"]
    r = b["slot_w"] / 2
    pts = [(xb - b["blk_emb"], 0.0), (xo, 0.0), (xo, ZT0), (px + r, ZT0)]
    pts += [(px + r * math.cos(t), pz + r * math.sin(t)) for t in np.linspace(0, -math.pi, 13)]
    pts += [(px - r, ZT0), (xb - b["blk_emb"], ZT0)]
    prof = A.polygon(pts)
    w = b["w"][sg]
    out = A.Mesh("AVO_CINCHA_R6_4_cojinetes_%s" % ("Xpos" if sg > 0 else "Xneg"), C_PETG_TRANS)
    for sy in (1, -1):
        ya, yb = sorted((yc + sy * (w / 2 + b["side"]), yc + sy * (w / 2 + b["side"] + b["blk"])))
        m = A.layered([(ya, yb, [prof])])
        m.transform(np.array([[sg, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0], [0, 0, 0, 1.0]]))   # (x, z, y) → (±x, y, z)
        out.merge(fix_orient(m))
    return out


def pieza_junta(comprimida=True):
    """junta TPU 85A de 1,2 × 1,6 en la ranura de 1,9 × 1,2: 25 % de compresión, 84 % de llenado.
    En el conjunto se dibuja comprimida (1,2 de alto); el STL sale libre (1,6)."""
    C = cap_contours()
    h = CAP["ranura"]["prof"] if comprimida else CAP["junta"]["alto"]
    return A.layered([(ZJ0, ZJ0 + h, [C["jO"], C["jI"]])], "AVO_CINCHA_R6_4_junta_TPU85A", C_TPU_ROJO)


PCB_HOLES = [(sx * 20.8, sy * 12.8) for sx in (1, -1) for sy in (1, -1)]
ANT = dict(cx=0.0, cy=-20.2, L=35.0, W=9.0)      # Molex 146153 (35 × 9 × 0,1)


def pieza_tapa():
    """tapa plana de PETG opaco: apoya en el canto de la base (tope duro → compresión fija de la junta), lengüeta de
    centrado dentro del hueco, 4 columnas que sujetan la PCB, rebaje de la antena y avellanados con arandela"""
    C = cap_contours()
    O = C["O_tapa"]
    l0, l1 = C["I_l0"], C["I_l1"]
    sh = [A.circle(x, y, 1.2, 20) for (x, y) in CAP["tornillos"]]      # paso M2
    sh.append(A.circle(0.0, OREJA["y"], OREJA["r_agujero"], 24))       # agujero del cordón (en la oreja, fuera de la junta)
    cb = [A.circle(x, y, 2.3, 28) for (x, y) in CAP["tornillos"]]      # cabeza ISO 7380 M2 + arandela DIN 433
    boss = [A.circle(x, y, 2.2, 28) for (x, y) in PCB_HOLES]
    pil = [A.circle(x, y, 0.875, 16) for (x, y) in PCB_HOLES]          # guía ciega para M2 roscado en PETG
    ant = A.rrect(ANT["cx"], ANT["cy"], ANT["L"] + 0.6, ANT["W"] + 0.4, 0.5, 2)
    z_l = ZT0 - CAP["lengueta_alto"]
    z_ant, z_pil, z_cb = ZT0 + 0.3, ZT0 + 1.0, ZT1 - 1.4
    # REV 6.4: 2 lengüetas por lado que bajan a las ranuras del pasador de la base y lo dejan cautivo
    K = bal_x()
    px, yc = K["px"], K["yc"]
    b = BAL
    z_tg = b["pz_c"] + b["slot_w"] / 2 + b["tongue_gap"]
    tg = []
    for sg in (1, -1):
        w = b["w"][sg]
        hw = w / 2 + b["side"]
        for sy in (1, -1):
            ya, yb = sorted((yc + sy * (hw + b["tongue_clear"]), yc + sy * (hw + b["blk"] - b["blk_emb"] - b["tongue_clear"])))
            tg.append(_rrx(sg, px - b["slot_w"] / 2 + 0.05, px + b["slot_w"] / 2 - 0.05, ya, yb))
    assert z_tg < ZP1
    L = [(z_tg, ZP1, tg),
         (ZP1, z_l, boss + pil + tg),
         (z_l, ZT0, [l0, l1] + boss + pil + tg),
         (ZT0, z_ant, [O, ant] + sh + pil),
         (z_ant, z_pil, [O] + sh + pil),
         (z_pil, z_cb, [O] + sh),
         (z_cb, ZT1, [O] + cb + [sh[-1]])]
    return A.layered(L, "AVO_CINCHA_R6_4_tapa", C_PETG_TAPA)


def pieza_separador():
    R = A.Raster(-25, -17, 25, 17, 0.02)
    R.add(A.rrect(0, 0, 45.0, 29.0, 2.0, 4))
    for (x, y) in PCB_HOLES:
        R.sub(A.circle(x, y, 2.3, 32))           # paso de las cabezas de los tornillos de la PCB
    return A.layered([(ZB1, ZP0, [R.contour(0.03)])], "AVO_CINCHA_R6_4_separador_TPU85A", C_TPU)


# ---------------------------------------------------------------------------------------------- compra: cápsula
FP_SIZE = {"R_0402_1005Metric": (1.0, 0.5, 0.35), "C_0402_1005Metric": (1.0, 0.5, 0.5),
           "C_0603_1608Metric": (1.6, 0.8, 0.8), "C_0805_2012Metric": (2.0, 1.25, 1.25),
           "Fuse_1206_3216Metric": (3.2, 1.6, 1.0), "D_SOD-323": (1.7, 1.25, 1.0), "SOT-23-5": (2.9, 1.6, 1.1),
           "VQFN-16-1EP_3x3mm_P0.5mm_EP1.68x1.68mm_ThermalVias": (3.0, 3.0, 1.0),
           "ST_LGA-14L_2.5x3mm_P0.5mm": (2.5, 3.0, 0.83), "MEMSIC_MMC5983MA_LGA-16_3x3mm_P0.5mm": (3.0, 3.0, 1.0),
           "AVO_VQFN-32-1EP_4x4mm_P0.4mm_EP2.8mm": (4.0, 4.0, 0.8), "CP_EIA-3528-21_Kemet-B": (3.5, 2.8, 1.9),
           "AVO_TQFP-32_5x5mm_P0.5mm": (7.0, 7.0, 1.2),
           "LED_0603_1608Metric": (1.6, 0.8, 0.6)}


def compra_pcb():
    """PCB REV D de 46 × 30 × 1,0 con los componentes principales como cajas (posiciones de piezas.json)"""
    out = []
    board = A.layered([(ZP0, ZP1, [A.rrect(0, 0, 46, 30, 2.0, 6)] + [A.circle(x, y, 1.1, 20) for x, y in PCB_HOLES])],
                      "PCB_REV_D_46x30", C_PCB)
    out.append(board)
    parts = json.load(open(os.path.join(HERE, "datos", "piezas_pcb_revd.json")))
    ics, pas = [], []
    for p in parts:
        fp = p["footprint"]
        if fp == "ESP32-C6-MINI-1U":
            # cuerpo 13,2 × 12,5 × 2,4 (huella −6,6..6,6 × −4,2..8,3), girado 270°: centro en x − 2,05
            m = A.box(p["x"] - 2.05 - 6.25, p["y"] - 6.6, ZP1, p["x"] - 2.05 + 6.25, p["y"] + 6.6, ZP1 + 2.4,
                      "U4_ESP32-C6-MINI-1U", C_METAL)
            out.append(m)
            continue
        if fp in ("WirePad_D1.5_Drill0.8",):
            pas.append(A.cylinder_z(p["x"], p["y"], 0.75, ZP1, ZP1 + 0.3, "pad", C_METAL, 12))
            continue
        if fp not in FP_SIZE:
            continue
        w, h, t = FP_SIZE[fp]
        if p["rot"] in (90, 270):
            w, h = h, w
        m = A.box(p["x"] - w / 2, p["y"] - h / 2, ZP1, p["x"] + w / 2, p["y"] + h / 2, ZP1 + t, p["ref"],
                  C_IC if p["ref"][0] in "U" or fp.startswith(("D_", "SOT", "CP_")) else C_PAS)
        (ics if p["ref"][0] == "U" else pas).append(m)
    big = A.Mesh("PCB_componentes", C_IC)
    for m in ics:
        big.merge(m)
    sm = A.Mesh("PCB_pasivos", C_PAS)
    for m in pas:
        sm.merge(m)
    out += [big, sm]
    # 4 LED SK6812SIDE-A (4,0 × 1,6 × 2,0), lente al canto (y = ±14,66): luz por los dos lados largos
    leds = A.Mesh("LED_SK6812SIDE-A_x4", C_LED)
    for ref, x, y, sg in LEDS:
        y0, y1 = sorted((y - sg * 0.8, sg * LED_LENTE_Y))
        leds.merge(A.box(x - 2.0, y0, ZP1, x + 2.0, y1, ZP1 + 2.0, ref, C_LED))
    out.append(leds)
    # U.FL (Hirose U.FL-R-SMT-1, 3 × 3 × 1,25) junto al canto +X del módulo, con la clavija acodada
    out.append(A.box(19.3, -5.5, ZP1 + 2.4 - 1.25, 22.3, -2.5, ZP1 + 2.4, "UFL_conector", C_ORO))
    return out


def compra_bateria():
    bx, by, bz = CAP["bat"]
    cel = A.layered([(ZB0, ZB1, [A.rrect(0, 0, bx, by, 1.0, 4)])], "LiPo_603450_1000mAh", C_BAT)
    return [cel]


def compra_pogo_placas():
    out = []
    for k, x in CAP["pogo_x"].items():
        y = CAP["pogo_y"]
        c = pogo_plate_contours(x, y)
        ch1 = [A.circle(px, py, 1.0, 16) for px, py in c["contacts"]]
        ch0 = [A.circle(px, py, 0.4, 10) for px, py in c["contacts"]]
        mh = [A.circle(px, py, 1.5, 20) for px, py in c["mags"]]
        body = A.layered([(0, 0.5, [c["face"]] + ch1 + mh), (0.5, 1.7, [c["face"]] + ch0 + mh),
                          (1.7, 3.0, [c["flange"]] + ch0 + mh), (3.0, 3.5, [c["flange"]] + ch0)],
                         "POGO_placa_%s" % k, (0.15, 0.15, 0.15))
        out.append(body)
        con = A.Mesh("POGO_placa_%s_contactos" % k, C_ORO)
        for px, py in c["contacts"]:
            con.merge(A.layered([(0, 0.5, [A.circle(px, py, 1.0, 16)]), (0.5, 4.5, [A.circle(px, py, 0.4, 10)])]))
        out.append(con)
        mg = A.Mesh("POGO_placa_%s_imanes" % k, C_IMAN)
        for px, py in c["mags"]:
            mg.merge(A.cylinder_z(px, py, 1.5, 0, 3.0, "", C_IMAN, 20))
        out.append(mg)
    return out


def compra_tornilleria_capsula():
    out = []
    ins = A.Mesh("Inserto_M2x4_ciego_x6", C_ORO)
    scr = A.Mesh("Tornillo_ISO7380_M2x6_inox_x6", C_METAL)
    was = A.Mesh("Arandela_DIN433_M2_inox_x6", C_METAL)
    for (x, y) in CAP["tornillos"]:
        ins.merge(A.cylinder_z(x, y, 1.6, ZT0 - 4.0, ZT0, "", C_ORO, 24, hole=1.0))
        zw = ZT1 - 1.4
        was.merge(A.cylinder_z(x, y, 2.0, zw, zw + 0.3, "", C_METAL, 24, hole=1.1))
        zh = zw + 0.3
        scr.merge(A.layered([(zh - 6.0, zh, [A.circle(x, y, 0.95, 16)]), (zh, zh + 1.04, [A.circle(x, y, 1.75, 24)])]))
    pcbs = A.Mesh("Tornillo_ISO7380_M2x5_inox_x4_PCB", C_METAL)
    for (x, y) in PCB_HOLES:
        pcbs.merge(A.layered([(ZP0 - 1.04, ZP0, [A.circle(x, y, 1.75, 24)]),
                              (ZP0, ZP0 + 5.0, [A.circle(x, y, 0.95, 16)])]))
    out += [ins, scr, was, pcbs]
    return out


def compra_antena():
    z1 = ZT0 + 0.3
    ant = A.box(ANT["cx"] - ANT["L"] / 2, ANT["cy"] - ANT["W"] / 2, z1 - 0.15, ANT["cx"] + ANT["L"] / 2,
                ANT["cy"] + ANT["W"] / 2, z1, "Antena_Molex_146153-0050", (0.75, 0.55, 0.15))
    # coaxial Ø1,13 de 50 mm: del extremo +X de la antena al U.FL por fuera del canto +X de la PCB
    x_end = ANT["cx"] + ANT["L"] / 2
    path = A.polyline_round([(x_end - 1.0, ANT["cy"], z1 - 0.7), (x_end + 4.5, ANT["cy"], z1 - 0.7),
                             (23.65, -16.5, ZP1 + 1.6), (23.65, -6.0, ZP1 + 1.6), (21.0, -4.0, ZP1 + 2.4 + 0.2)], 2.0)
    cab = A.tube(A.resample(path, 1.5), 0.565, 8, name="Coaxial_1.13_50mm", color=(0.6, 0.6, 0.6))
    return [ant, cab]


def compra_hilos_capsula():
    """hilos de silicona AWG 28 (Ø0,9): placas pogo → pads P1–P6; celda → J2/J6"""
    out = []
    ecg_pads = [(-21.6, 2.54), (-21.6, 0.0), (-21.6, -2.54)]       # P4 ECG+, P5 REF, P6 ECG−
    chg_pads = [(-7.0, -13.6), (-4.6, -13.6), (-2.2, -13.6)]       # P1 5V, P2 GND, P3 DET
    cols = ["r", "a", "az"]
    xe = CAP["pogo_x"]["ECG"]; xc = CAP["pogo_x"]["CARGA"]; y0 = CAP["pogo_y"]
    m = A.Mesh("Hilos_AWG28_pogo", C_HILO["a"])
    for k, (dx, pad) in enumerate(zip((-2.3, 0.0, 2.3), ecg_pads)):
        path = A.polyline_round([(xe + dx, y0, 4.5), (xe + dx, y0, 5.6 + 0.6 * k), (-23.9 + 0.0 * k, -16.5 + 0.0, 6.0 + 0.6 * k),
                                 (-23.9, pad[1], ZP1 + 0.9 + 0.3 * k), (pad[0], pad[1], ZP1 + 0.3)], 1.5)
        m.merge(A.tube(A.resample(path, 2.5), 0.45, 6))
    for k, (dx, pad) in enumerate(zip((-2.3, 0.0, 2.3), chg_pads)):
        path = A.polyline_round([(xc + dx, y0, 4.5), (xc + dx, y0, 6.5 + 0.8 * k), (pad[0], -17.2, ZP1 + 1.2 + 0.5 * k),
                                 (pad[0], pad[1], ZP1 + 0.3)], 1.5)
        m.merge(A.tube(A.resample(path, 2.5), 0.45, 6))
    out.append(m)
    b = A.Mesh("Hilos_bateria", C_HILO["r"])
    for k, pad in enumerate([(2.6, -13.6), (5.0, -13.6)]):
        path = A.polyline_round([(25.0, -8.0 - 2.5 * k, ZB0 + 3.0), (26.0, -8.0 - 2.5 * k, ZB0 + 3.0),
                                 (24.4, -11.0 - 2.5 * k, ZP1 + 1.4 + 0.5 * k), (pad[0], -16.0, ZP1 + 1.4 + 0.5 * k),
                                 (pad[0], pad[1], ZP1 + 0.3)], 1.5)
        b.merge(A.tube(A.resample(path, 2.5), 0.45, 6))
    out.append(b)
    return out


# =============================================================================================== soporte (en la funda)
Z0_CAP = SOP["cama"] + SOP["precarga"]          # fondo de la cápsula en el soporte (z del soporte)


def bal_sop_cuts(sg):
    """REV 6.4: vaciados del soporte para el balancín del lado sg (cajas x0, x1, y0, y1, z0, z1 en el soporte):
    paso por el cerco, rebaje de la cama bajo la cápsula (con su desagüe) y ventanas de los dientes"""
    K = bal_x()
    xi, xo, yc = K["xl"], K["xo"], K["yc"]                             # xi = cara interior del balancín (abajo)
    b = BAL
    w = b["w"][sg]
    hw = w / 2 + 0.3
    cer = SOP["cama"] + SOP["cerco_h"]
    roof = Z0_CAP + b["top_c"] + b["roof_gap"]
    x_in = xi - b["back_low"]                                          # pared interior del rebaje (= tope de la cápsula)

    def bx(x0, x1, y0, y1, z0, z1):
        xa, xb = sorted((sg * x0, sg * x1))
        return (xa, xb, y0, y1, z0, z1)
    out = dict(roof=roof)
    out["slot"] = bx(xo - 1.0, xo + 0.25 + SOP["cerco"] + 1.0, yc - hw, yc + hw, SOP["cama"], cer + 0.1)
    out["pocket"] = bx(x_in, xo + b["pock_out"], yc - hw, yc + hw, Z0_CAP + b["bot_c"] - b["pock_clear"],
                       SOP["cama"] + 0.01)
    out["wins"] = []
    t0, t1 = b["ty0"] - b["win_w"], w / 2 - b["tyend"] + b["win_w"]
    for (ya, yb) in ((yc + t0, yc + t1), (yc - t1, yc - t0)):
        out["wins"].append(bx(xi - b["e"] - b["win_deep"], x_in + 0.1, ya, yb, out["pocket"][4], roof))
    Rw = A.Raster(-55, -55, 55, 55, 0.02)
    Rw.add(_rect(out["pocket"]))
    for wb in out["wins"]:
        Rw.add(_rect(wb))
    out["pocket_c"] = _rect(out["pocket"])
    out["pocket_win_c"] = Rw.offset(0.05).contour(0.03)                # anidado: contiene al rebaje sin ventanas
    out["drain_c"] = A.circle(sg * (xo + 1.0), yc, 0.7, 16)
    return out


def _rect(b):
    return A.rrect((b[0] + b[1]) / 2, (b[2] + b[3]) / 2, b[1] - b[0], b[3] - b[2], 0, 1)


def sop_contours():
    C = cap_contours()
    R = C["_rasterO"]
    Rin = R.offset(SOP["holgura"]).contour(0.03)
    Rc = R.offset(SOP["holgura"] + SOP["cerco"])
    cuts = [bal_sop_cuts(1), bal_sop_cuts(-1)]
    for K in cuts:
        Rc.sub(_rect(K["slot"]))
    Rc.sub(Rin)
    cerco = Rc.contours(0.03)
    Rout = R.offset(SOP["holgura"] + SOP["cerco"]).contour(0.03)
    xs = list(Rout.p[:, 0]); ys = list(Rout.p[:, 1])
    for K in cuts:
        p = K["pocket"]
        xs += [p[0], p[1]]; ys += [p[2], p[3]]
    bx0, bx1, by0, by1 = min(xs) - 1.5, max(xs) + 1.5, min(ys) - 1.0, max(ys) + 1.0
    BODY = A.rrect((bx0 + bx1) / 2, (by0 + by1) / 2, bx1 - bx0, by1 - by0, 4.0, 6)
    fx0, fx1 = bx0 - SOP["ala"], bx1 + SOP["ala"]
    fy0, fy1 = by0 - SOP["ala"], by1 + SOP["ala"]
    F = A.rrect((fx0 + fx1) / 2, (fy0 + fy1) / 2, fx1 - fx0, fy1 - fy0, 6.0, 6)
    chic = [(fx0 + 4.5, fy0 + 4.5), (fx1 - 4.5, fy0 + 4.5), (fx0 + 4.5, fy1 - 4.5), (fx1 - 4.5, fy1 - 4.5)]
    cordon = (0.0, by1 + 4.0)
    return dict(Rin=Rin, Rout=Rout, cerco=cerco, BODY=BODY, F=F, chic=chic, fx=(fx0, fx1), fy=(fy0, fy1),
                body=(bx0, bx1, by0, by1), cordon=cordon, cuts=cuts)


def z_soporte():
    cama = SOP["cama"]
    K = bal_sop_cuts(1)
    return dict(body=cama - 6.0, pest=SOP["pestana"], ear=cama - 4.5, tac=cama - 1.0, cama=cama,
                cer=cama + SOP["cerco_h"], roof=K["roof"], pock=K["pocket"][4])


def pieza_soporte():
    S = sop_contours()
    y = CAP["pogo_y"]
    pb, pc, er, pil = [], [], [], []
    for k, x in CAP["pogo_x"].items():
        pb.append(A.stadium(x, y, 17.0, 6.95))                      # hueco inferior para soldar las colas
        pc.append(A.stadium(x, y, 15.5 + 0.3, 4.65 + 0.3))          # cuerpo del lado de los pines
        er.append(A.stadium(x, y, 25.0 + 0.4, 5.5 + 0.4))           # orejas, abierto por arriba
        pil += [A.circle(x + dx, y, 0.8, 14) for dx in (-9.75, 9.75)]   # guía M2 × 4 (Ø1,6)
    ch = [A.circle(cx, cy, 2.6, 24) for cx, cy in S["chic"]]       # tornillo de Chicago Ø5
    cord = A.circle(*S["cordon"], 1.6, 24)                          # anclaje del cordón de seguridad
    tac = [A.circle(x, yy, 1.5, 20) for x, yy in TACOS]            # alojamientos de los tacos TPU (Ø3,0 × 1,0)
    z = z_soporte()
    pest, cama = z["pest"], z["cama"]
    zs = sorted(set([0.0] + list(z.values())))
    L = []
    for z0, z1 in zip(zs[:-1], zs[1:]):
        zm = (z0 + z1) / 2
        cs = []
        if zm < pest:
            cs += [S["F"]] + ch + [cord]
        elif zm < cama:
            cs.append(S["BODY"])
        if zm < cama:
            cs += pb if zm < z["body"] else (pc if zm < z["ear"] else er)
            if zm < z["ear"]:
                cs += pil
            if zm > z["tac"]:
                cs += tac
            for K in S["cuts"]:
                if zm < K["pocket"][4]:
                    cs.append(K["drain_c"])                          # desagüe Ø1,4 del rebaje
                elif zm < K["roof"]:
                    cs.append(K["pocket_win_c"])                     # rebaje con las ventanas de los dientes
                else:
                    cs.append(K["pocket_c"])                         # rebaje bajo el balancín (lo deja girar)
        elif zm < z["cer"]:
            cs += S["cerco"]
        if cs:
            L.append((z0, z1, cs))
    return A.layered(L, "AVO_CINCHA_R6_4_soporte_PETG", C_PETG)


def balancin_capas(sg):
    """REV 6.4: capas del balancín empotrado (lado +X; el de −X se refleja). Perfil en XZ (z de la cápsula, 0 = fondo)
    y capas a lo largo de Y. Más grueso por debajo del eje (llega al tope del hueco). Zonas (en |y − yc|): centro con
    el alojamiento del imán (abierto en la cara interior de abajo, con tapa), dientes en los lados (por debajo de la
    cápsula) y placa. Agujero del pasador (a presión, en gota) en todo el ancho. Perfiles vecinos anidados (0,05 mm)."""
    K = bal_x()
    xi, xl, xo, px, yc = K["xi"], K["xl"], K["xo"], K["px"], K["yc"]
    b = BAL
    w = b["w"][sg]
    zb, zt, e = b["bot_c"], H_CAP, b["e"]

    def raster():
        return A.Raster(xl - e - 1.5, zb - 1, xo + 1, zt + 1, 0.02)
    Rp = raster()
    Rp.add(A.rrect((xi + xo) / 2, (zb + zt) / 2, xo - xi, zt - zb, 0, 1))
    Rp.add(A.rrect((xl + xi + 0.05) / 2, (zb + b["z_grueso"]) / 2, xi + 0.05 - xl, b["z_grueso"] - zb, 0, 1))
    P_t = raster(); P_t.m = Rp.m.copy()
    P_t.add(A.polygon([(xl + 0.05, b["root_b_c"]), (xl - e, b["tip_b_c"]), (xl - e, b["top_c"]), (xl + 0.05, b["top_c"])]))
    c_t = P_t.contour(0.02)
    c_a = Rp.offset(-0.05).contour(0.02)
    Rm = Rp.offset(-0.10)
    hm = b["mag"] / 2
    Rm.sub(A.rrect(xl - 0.5 + (b["cb"] + 0.5) / 2, b["mag_c"], b["cb"] + 0.5, b["mag"] + 2 * b["cap_lip"], 0, 1))
    Rm.sub(A.rrect(xl + b["cb"] + b["mag_t"] / 2 - 0.01, b["mag_c"], b["mag_t"] + 0.02, b["mag"], 0, 1))
    c_m = Rm.contour(0.02)
    rh = b["hole"] / 2
    hole = A.polygon([(px + rh * math.cos(t), b["pz_c"] + rh * math.sin(t))
                      for t in np.linspace(-0.75 * math.pi, 0.75 * math.pi, 25)] + [(px - rh * 1.4142, b["pz_c"])])
    hzm = hm + b["cap_lip"]
    ty0, ty1 = b["ty0"], w / 2 - b["tyend"]
    assert hzm < ty0
    br = sorted({0.0, hzm, ty0, ty1, w / 2})
    edges = sorted({-v for v in br} | set(br))
    L = []
    for ya, yb in zip(edges[:-1], edges[1:]):
        d = abs((ya + yb) / 2)
        cs = [c_m] if d < hzm else ([c_t] if ty0 < d < ty1 else [c_a])
        L.append((yc + ya, yc + yb, cs + [hole]))
    return L


def pieza_balancin(sg, impresion=False):
    """balancín en su sitio (cápsula, z = 0 fondo) o, con impresion=True, con la cara exterior en la cama"""
    m = A.layered(balancin_capas(sg), "AVO_CINCHA_R6_4_balancin_%s" % ("Xpos" if sg > 0 else "Xneg"), C_TPU_ROJO)
    m.transform(np.array([[sg, 0, 0, 0], [0, 0, 1, 0], [0, 1, 0, 0], [0, 0, 0, 1.0]]))   # (x, z, y) → (±x, y, z)
    fix_orient(m)
    if impresion:
        m.transform(np.array([[0, 0, sg, 0], [0, 1, 0, 0], [-sg, 0, 0, 0], [0, 0, 0, 1.0]]))   # cara exterior abajo
        fix_orient(m)
    return m


def compra_cierre():
    """REV 6.4: pasadores de acero e imanes Ø5 × 1 (2 apilados en cada alojamiento), en la cápsula (z = 0 fondo)"""
    K = bal_x()
    xl, xb, px, yc = K["xl"], K["xb"], K["px"], K["yc"]
    b = BAL
    pins = A.Mesh("Pasador_ISO2338_2x20_y_2x18_acero", C_METAL)
    mags = A.Mesh("Imanes_5x1_x8_cierre", C_IMAN)
    for sg in (1, -1):
        L = b["pin_len"][sg]
        pins.merge(A.tube([(sg * px, yc - L / 2, b["pz_c"]), (sg * px, yc + L / 2, b["pz_c"])], 1.0, 16))
        x1 = xl + b["cb"] + 0.02                                               # en el balancín
        mags.merge(A.tube([(sg * x1, yc, b["mag_c"]), (sg * (x1 + 2.0), yc, b["mag_c"])], 2.5, 20))
        x2 = xb - b["skin_w"] - 0.02                                           # en la pared (pozo desde abajo)
        mags.merge(A.tube([(sg * (x2 - 2.0), yc, b["mag_c"]), (sg * x2, yc, b["mag_c"])], 2.5, 20))
    for m in (pins, mags):
        fix_orient(m)
    return [pins, mags]


def pieza_tapas_imanes():
    """REV 6.4: tapas de los imanes (juego para una cápsula, PETG, planas en la cama, se pegan a ras): 2 tapas de los
    balancines (5,5 × 5,5 × 0,5) y 2 tapones de los pozos de la pared (2,05 × 5,1 × 1,1, por debajo de la cápsula)"""
    b = BAL
    a = b["mag"] + 2 * b["cap_lip"] - 0.1
    hp = b["mag_c"] - b["mag"] / 2 - 0.05
    m = A.Mesh("AVO_CINCHA_R6_4_tapas_imanes_PETG", C_PETG)
    for k in range(2):
        m.merge(A.box(k * 7.0, 0, 0, k * 7.0 + a, a, b["cap_t"]))
        m.merge(A.box(15.0 + k * 4.0, 0, 0, 15.0 + k * 4.0 + b["mag_t"] - 0.05, b["mag"], round(hp, 2)))
    return m


def pieza_tacos(libre=False):
    zb = SOP["cama"] - 1.0
    h = 1.85 if libre else 1.0 + SOP["precarga"]
    m = A.Mesh("AVO_CINCHA_R6_4_tacos_precarga_TPU85A_x4", C_TPU)
    for x, y in TACOS:
        m.merge(A.cylinder_z(x, y, 1.45, zb, zb + h, "", C_TPU, 20))
    return m


def compra_pogo_pines():
    """lado de los pines (muelles), en el soporte: medidas del STEP real (REV 5.9.1)"""
    out = []
    cama = SOP["cama"]
    y = CAP["pogo_y"]
    for k, x in CAP["pogo_x"].items():
        pins = [A.circle(x + dx, y, 0.4, 10) for dx in (-2.3, 0, 2.3)]
        mg = [A.circle(x + dx, y, 1.5, 20) for dx in (-5.425, 5.425)]
        eh = [A.circle(x + dx, y, 1.0, 16) for dx in (-9.75, 9.75)]
        body = A.layered([(cama - 6.0, cama - 4.5, [A.stadium(x, y, 15.5, 4.65)] + pins + mg),
                          (cama - 4.5, cama - 2.5, [A.stadium(x, y, 25.0, 5.5)] + pins + mg + eh),
                          (cama - 2.5, cama, [A.stadium(x, y, 15.5, 4.65)] + pins + mg)],
                         "POGO_pines_%s" % k, (0.15, 0.15, 0.15))
        out.append(body)
        pm = A.Mesh("POGO_pines_%s_muelles" % k, C_ORO)
        for dx in (-2.3, 0, 2.3):
            pm.merge(A.cylinder_z(x + dx, y, 0.4, cama - 7.5, cama + SOP["precarga"], "", C_ORO, 10))
        out.append(pm)
        mm = A.Mesh("POGO_pines_%s_imanes" % k, C_IMAN)
        for dx in (-5.425, 5.425):
            mm.merge(A.cylinder_z(x + dx, y, 1.5, cama - 6.0, cama, "", C_IMAN, 20))
        out.append(mm)
        sc = A.Mesh("Tornillo_M2x4_pines_%s" % k, C_METAL)
        for dx in (-9.75, 9.75):
            sc.merge(A.layered([(cama - 2.5 - 4.0, cama - 2.5, [A.circle(x + dx, y, 0.95, 16)]),
                                (cama - 2.5, cama - 2.5 + 1.04, [A.circle(x + dx, y, 1.75, 24)])]))
        out.append(sc)
    return out


# =============================================================================================== electrodos (Vialta PG980/51)
def e_lado_capsula(k):
    """extremo del electrodo (en u) por el que sale el cable: el más cercano a la cápsula"""
    ue, ve = P["e_pos"][k]; L, Wd = P["e_tam"][k]
    return ue - L / 2 if ue > 0 else ue + L / 2


def compra_electrodo(k, curvo):
    """electrodo de caucho conductor con el cable moldeado en el extremo; detrás, espuma EVA. Curvado con la cincha."""
    ue, ve = P["e_pos"][k]; L, Wd = P["e_tam"][k]
    out = []
    us = A.breaks(ue - L / 2, ue + L / 2, 8.0)
    prof = rr_profile(ve - Wd / 2, ve + Wd / 2, W_E0, W_E1, 0.8, 2)
    out.append(bend_mesh(A.sweep_u([(u, prof) for u in us], "Electrodo_Vialta_%s_%dx%d" % (k, Wd, L), C_ELECTRODO),
                         curvo))
    ub = e_lado_capsula(k)
    sg = 1 if ue > 0 else -1
    boss = A.grid_slab([min(ub, ub + sg * 8.0), max(ub, ub + sg * 8.0)], [ve - 5.0, ve + 5.0], W_E1, W_E1 + 2.5, None,
                       "Electrodo_%s_moldeado_cable" % k, C_ELECTRODO)
    out.append(bend_mesh(boss, curvo))
    eu0, eu1 = (ub + sg * 10.0, ue + sg * (L / 2 + 2.0))
    us = A.breaks(min(eu0, eu1), max(eu0, eu1), 8.0)
    prof = rr_profile(ve - Wd / 2 - 2.0, ve + Wd / 2 + 2.0, W_E1, W_FR1, 0.8, 2)
    out.append(bend_mesh(A.sweep_u([(u, prof) for u in us], "Espuma_EVA_%s" % k, (0.35, 0.35, 0.38)), curvo))
    return out


# =============================================================================================== cincha (tipo Decathlon)
def rr_profile(v0, v1, w0, w1, r, seg=3):
    c = A.rrect((v0 + v1) / 2, (w0 + w1) / 2, v1 - v0, w1 - w0, r, seg)
    return c.p


def cincha_decathlon(curvo, step=20.0):
    out = []
    L = P["cincha_largo"]
    ub = L / 2 - 120.0                       # extremo del cuerpo acolchado (cada punta: 120 de correas + hebillas)
    t = P["cincha_grosor"]
    # cuerpo: extremos redondeados en planta (radio 40) → perfil que se estrecha en las puntas
    us = A.breaks(-ub, ub, step, [0])
    st = []
    for u in us:
        e = abs(u) - (ub - 40.0)
        half = VG if e <= 0 else max(8.0, math.sqrt(max(0.0, 40.0 ** 2 - e ** 2)) + VG - 40.0)
        if abs(u) >= ub - 1e-6:
            half = VG - 40.0 + 4.0
        st.append((u, rr_profile(-half, half, W_G0, W_G1, 2.5, 3)))
    body = A.sweep_u(st, "Cincha_cuerpo_tela", C_TELA)
    out.append(bend_mesh(body, curvo))
    cw = P["cinta_central_ancho"] / 2
    cs = [(u, rr_profile(-cw, cw, W_G1 - 0.2, W_G1 + 1.0, 0.4, 1)) for u in A.breaks(-ub + 25, ub - 25, step)]
    out.append(bend_mesh(A.sweep_u(cs, "Cincha_cinta_central", C_CINTA), curvo))
    # correas y hebillas
    cw2 = P["correa_ancho"] / 2
    wm = (W_G0 + W_G1) / 2
    for side in (1, -1):
        for vc in (-27.0, 27.0):
            u0, u1 = ub - 35.0, L / 2 - 30.0
            us2 = A.breaks(u0, u1, 10.0)
            prof = rr_profile(vc - cw2, vc + cw2, wm - 1.5, wm + 1.5, 0.6, 1)
            elast = side > 0
            nm = "Cincha_%s_%s_%s" % ("elastico" if elast else "correa", "izq" if side > 0 else "der",
                                      "tras" if vc > 0 else "del")
            m = A.sweep_u([(side * u, prof) for u in (us2 if side > 0 else us2[::-1])], nm,
                          C_ELAST if elast else C_CINTA)
            out.append(bend_mesh(m, curvo))
            # hebilla de rodillo 25 mm: marco de varilla Ø4 + rodillo Ø7 + lengüeta
            ub0 = L / 2 - 30.0
            hb = hebilla(ub0, vc, wm, side, curvo)
            for h in hb:
                h.name = "Hebilla_rodillo_25mm_%s_%s" % ("izq" if side > 0 else "der", "tras" if vc > 0 else "del") + h.name
            out += hb
    # anilla D central en una pestaña de cinta sobre el canto delantero
    out += anilla_d(curvo)
    return out


def hebilla(u0, vc, wm, side, curvo):
    hx, hy = P["hebilla_int"]       # luz 25 (a lo ancho) × 14
    rr = 2.0
    pts = []
    xa, xb = 2.0, 2.0 + hy + 4.0
    ya, yb = -(hx / 2 + 2.0), hx / 2 + 2.0
    for (cx, cy, a0) in ((xb - 3, ya + 3, -90), (xb - 3, yb - 3, 0), (xa + 3, yb - 3, 90), (xa + 3, ya + 3, 180)):
        for k in range(5):
            a = math.radians(a0 + 90 * k / 4)
            pts.append((cx + 3 * math.cos(a), cy + 3 * math.sin(a), 0.0))
    M = frame(side * u0, vc, wm, curvo, 0 if side > 0 else 180)
    fr = A.tube(pts, rr, 8, closed=True, name="_marco", color=C_METAL).transform(M)
    rol = A.tube([(xb, ya + 2.5, 0), (xb, yb - 2.5, 0)], 3.5, 14, name="_rodillo", color=C_METAL).transform(M)
    pr = A.tube([(xa, 0, 0.5), (xb - 1.0, 0, 1.6), (xb + 2.0, 0, 1.2)], 1.5, 8, name="_lengueta", color=C_METAL).transform(M)
    return [fix_orient(fr), fix_orient(rol), fix_orient(pr)]


def anilla_d(curvo):
    out = []
    tab = A.grid_slab(A.breaks(-15, 15, 6), A.breaks(-(VG + 26), -(VG - 30), 6), W_G1 + 0.8, W_G1 + 2.0,
                      name="Cincha_pestana_anilla_D", color=C_CINTA)
    out.append(bend_mesh(tab, curvo))
    # anilla D de varilla Ø5: lado recto de 38 mm a lo largo de u, arco de 30 mm hacia −v
    pts = []
    yb = -(VG + 22.0)
    for k in range(9):
        pts.append((-19 + 38 * k / 8, yb, 0))
    for k in range(1, 24):
        a = math.pi * k / 24
        pts.append((19 * math.cos(a), yb - 30 * math.sin(a), 0))
    M = frame(0, 0, W_G1 + 1.4 + 2.5, curvo)
    d = A.tube(pts, 2.5, 10, closed=True, name="Cincha_anilla_D_38mm", color=C_METAL).transform(M)
    out.append(fix_orient(d))
    return out


def cincha_horze(curvo, step=20.0):
    """cincha anatómica de cuero tipo Horze (110 cm): 120 en el centro, 85 en el recorte del codo, 70 en las puntas.
    Medidas ESTIMADAS (el catálogo no da anchuras; una de cuero comparable — Kramer Naira — mide 11 cm)."""
    out = []
    L = P["cincha_largo"]
    ub = L / 2 - 120.0
    t = 10.0

    def edges(u):
        a = abs(u) / ub
        rear = 60.0 - 25.0 * max(0.0, a - 0.55) / 0.45
        # recorte del codo en el canto delantero
        front = 60.0 - 32.0 * math.exp(-((abs(u) - 230.0) / 90.0) ** 2) - 25.0 * max(0.0, a - 0.75) / 0.25
        if abs(u) > ub - 30:
            k = (abs(u) - (ub - 30)) / 30.0
            front = front * (1 - 0.5 * k ** 2); rear = rear * (1 - 0.5 * k ** 2)
        return front, rear
    st = []
    for u in A.breaks(-ub, ub, step, [0]):
        f, r = edges(u)
        st.append((u, rr_profile(-f, r, 0.0, t, 3.0, 3)))
    out.append(bend_mesh(A.sweep_u(st, "Cincha_Horze_cuero", (0.05, 0.05, 0.05)), curvo))
    wm = t / 2
    for side in (1, -1):
        for vc in (-13.0 + 2.0, 13.0 + 18.0):
            vcc = -14.0 if vc < 0 else 18.0
            us2 = A.breaks(ub - 35.0, L / 2 - 30.0, 10.0)
            prof = rr_profile(vcc - 12.5, vcc + 12.5, wm - 1.5, wm + 1.5, 0.6, 1)
            m = A.sweep_u([(side * u, prof) for u in (us2 if side > 0 else us2[::-1])], "Horze_elastico",
                          (0.08, 0.08, 0.08))
            out.append(bend_mesh(m, curvo))
            out += hebilla(L / 2 - 30.0, vcc, wm, side, curvo)
    return out


# =============================================================================================== funda de piel
def funda(curvo, step=20.0):
    out = []
    e = P["cuero"]
    S = sop_contours()
    V_OFF = sop_v_off()
    fx0, fx1 = S["fx"]
    fy0, fy1 = S["fy"]
    win, reb = [], []
    mg = P["e_ventana_margen"]
    for k, (ue, ve) in P["e_pos"].items():
        L, Wd = P["e_tam"][k]
        win.append((ue - L / 2 + mg, ue + L / 2 - mg, ve - Wd / 2 + mg, ve + Wd / 2 - mg))
        reb.append((ue - L / 2 - 1.0, ue + L / 2 + 1.0, ve - Wd / 2 - 1.0, ve + Wd / 2 + 1.0))
    us_extra = [x for w in win + reb for x in (w[0], w[1])]
    vs_extra = [x for w in win + reb for x in (w[2], w[3])]
    # --- panel interior (lado del caballo): capa de 1,0 con las ventanas y capa de 1,0 rebajada alrededor del electrodo
    us = A.breaks(-UF, UF, step, us_extra)
    vs = A.breaks(-VF_D, VF_T, 30.0, vs_extra)
    keep = lambda u, v: not any(a < u < b and c < v < d for a, b, c, d in win)
    out.append(bend_mesh(A.grid_slab(us, vs, W_IN0, W_REB, keep, "Funda_panel_interior", C_CUERO), curvo))
    keep = lambda u, v: not any(a < u < b and c < v < d for a, b, c, d in reb)
    out.append(bend_mesh(A.grid_slab(us, vs, W_REB, W_IN1, keep, "Funda_panel_interior_rebaje", C_CUERO), curvo))
    # --- panel exterior, con la ranura del cable bajo el pogo del ECG y los 4 pasos de los tornillos de Chicago
    xe = CAP["pogo_x"]["ECG"]
    slot = (xe - 7.0, xe + 7.0, CAP["pogo_y"] + V_OFF - 3.5, CAP["pogo_y"] + V_OFF + 3.5)
    holes = [slot] + [(cx - 2.6, cx + 2.6, cy + V_OFF - 2.6, cy + V_OFF + 2.6) for cx, cy in S["chic"]]
    us = A.breaks(-UF, UF, step, [x for h in holes for x in h[:2]])
    vs = A.breaks(-VF_D, VF_T - e, 30.0, [x for h in holes for x in h[2:]])
    keep = lambda u, v: not any(a < u < b and c < v < d for a, b, c, d in holes)
    out.append(bend_mesh(A.grid_slab(us, vs, W_OUT0, W_OUT1, keep, "Funda_panel_exterior", C_CUERO), curvo))
    # --- pliegue delantero (pared), con la ventana de la pestaña de la anilla D
    us = A.breaks(-UF, UF, step, [-20, 20])
    ws = [W_IN1, W_G1 - 1.0, W_G1 + 3.0, W_OUT0]
    keep = lambda u, w: not (-20 < u < 20 and W_G1 - 1.0 < w < W_G1 + 3.0)
    m = A.grid_slab(us, ws, -VF_D, -VF_D + e, keep, "Funda_pliegue_delantero", C_CUERO)
    out.append(bend_mesh(swap_uwv(m), curvo))
    # --- pliegue trasero que sube hasta la solapa de cierre
    W_V0 = W_OUT1; W_V1 = W_V0 + 1.5; W_H1 = W_V1 + 1.5; W_S1 = W_H1 + e
    m = A.grid_slab(A.breaks(-UF, UF, step), [W_IN1, W_S1], VF_T - e, VF_T, None, "Funda_pliegue_trasero", C_CUERO)
    out.append(bend_mesh(swap_uwv(m), curvo))
    # --- solapa de cierre (sobre el panel exterior) y velcro, interrumpidos en el soporte
    ucut = max(abs(fx0), abs(fx1)) + 8.0
    for (a, b) in ((-UF, -ucut), (ucut, UF)):
        us = A.breaks(a, b, step)
        out.append(bend_mesh(A.grid_slab(us, [VF_T - 32.0, VF_T - e], W_H1, W_S1, None, "Funda_solapa_cierre",
                                         C_CUERO), curvo))
        out.append(bend_mesh(A.grid_slab(us, [VF_T - 30.0, VF_T - 5.0], W_V0, W_V1, None, "Velcro_25mm_rizo",
                                         C_VELCRO), curvo))
        out.append(bend_mesh(A.grid_slab(us, [VF_T - 30.0, VF_T - 5.0], W_V1, W_H1, None, "Velcro_25mm_gancho",
                                         (0.2, 0.2, 0.2)), curvo))
    # --- canal cosido del cable, por dentro del pliegue delantero (tramos entre las salidas a los electrodos)
    vi = -VF_D + e
    prof = [(vi, 2.6), (vi + 5.8, 3.6), (vi + 5.8, 12.4), (vi, 13.4), (vi, 12.2), (vi + 4.6, 11.4),
            (vi + 4.6, 4.8), (vi, 4.0)]
    prof = [(v, w + W_IN1 + 0.6 - 2.6) for v, w in prof]
    for (a, b) in CANAL_TRAMOS:
        st = [(u, prof) for u in A.breaks(a, b, step)]
        out.append(bend_mesh(A.sweep_u(st, "Funda_canal_cable", C_CUERO_OSC), curvo))
    # --- pasadores (trabillas) en los extremos: anillos de piel de 25 mm alrededor de todo
    for uc in (-UF + 30.0, UF - 30.0):
        R = [(-VF_D - 2.2, W_IN0 - 2.2), (VF_T + 2.2, W_IN0 - 2.2), (VF_T + 2.2, W_S1 + 2.2), (-VF_D - 2.2, W_S1 + 2.2)]
        Ri = [(-VF_D - 0.2, W_IN0 - 0.2), (VF_T + 0.2, W_IN0 - 0.2), (VF_T + 0.2, W_S1 + 0.2), (-VF_D - 0.2, W_S1 + 0.2)]
        co = A.polygon(R); ci = A.polygon(Ri)
        m = A.layered([(0, 25.0, [co, ci])], "Funda_pasador", C_CUERO_OSC)
        # local (v, w, u) → (u, v, w)
        m.transform(A.swap_axes(("y", "z", "x")))
        m.transform(A.T_translate(uc - 12.5, 0, 0))
        fix_orient(m)
        # subdividir para curvar: suficiente con triangular (25 mm)
        out.append(bend_mesh(m, curvo))
    return out


CANAL_TRAMOS = [(-228.0, -125.0), (-113.0, -42.0), (42.0, 138.0)]


def sop_v_off():
    S = sop_contours()
    return -(S["fy"][0] + S["fy"][1]) / 2


def chicago(S):
    m = A.Mesh("Tornillo_Chicago_5mm_x4", C_METAL)
    for cx, cy in S["chic"]:
        m.merge(A.layered([(-e_cuero() - 1.5, -e_cuero(), [A.circle(cx, cy, 4.75, 32)]),
                           (-e_cuero(), SOP["pestana"], [A.circle(cx, cy, 2.45, 24)]),
                           (SOP["pestana"], SOP["pestana"] + 1.5, [A.circle(cx, cy, 4.75, 32)])]))
    return m


def e_cuero():
    return P["cuero"]


# =============================================================================================== cables de los electrodos
def cables(curvo):
    """cable moldeado de cada electrodo (Ø 2,5, rojo) recortado: va por el canal cosido del pliegue delantero, sube por
    encima de la cincha y llega a un empalme soldado y encapsulado en termorretráctil con adhesivo, bajo la ranura del soporte. El de REF va trenzado con el de
    ECG− en el tramo común. Devuelve también las longitudes (mm)."""
    out, lens = [], {}
    V_OFF = sop_v_off()
    xe = CAP["pogo_x"]["ECG"]
    ys = CAP["pogo_y"] + V_OFF
    wc = W_G1 + 1.9                                   # entre la cincha y el panel exterior
    vc = -VF_D + P["cuero"] + 2.3                     # centro del canal (v)
    wks = {"ECG+": W_IN1 + 6.1, "ECG-": W_IN1 + 4.6, "REF": W_IN1 + 7.6}
    jst = (xe, ys - 9.0)                              # empalme soldado (dentro de la funda, bajo el panel exterior)
    for k, (ue, ve) in P["e_pos"].items():
        sg = 1 if ue > 0 else -1
        ub = e_lado_capsula(k)
        wk = wks[k]
        dv = {"ECG+": 0.0, "ECG-": -1.3, "REF": 1.3}[k]
        pts = [(ub + sg * 8.0, ve, W_E1 + 1.25), (ub - sg * 4.0, ve, W_E1 + 1.25), (ub - sg * 9.0, ve - 22.0, W_E1 + 1.0),
               (ub - sg * 11.0, -VG - 1.0, wk), (ub - sg * 13.0, vc, wk), (sg * 42.0, vc, wk), (sg * 34.0, vc, wc),
               (sg * 30.0, -VG + 8.0, wc), (jst[0] + sg * 9.0 + dv, jst[1] - 4.0, wc), (jst[0] + sg * 4.0, jst[1], wc)]
        uvw = A.resample(A.polyline_round(pts, 6.0, 6), 8.0)
        L = float(np.sum(np.linalg.norm(np.diff(uvw, axis=0), axis=1)))
        lens[k] = L
        xyz = (bend_curvo if curvo else bend_recto)(uvw)
        out.append(A.tube(xyz, 1.25, 7, name="Cable_electrodo_%s_%dmm" % (k, round(L)),
                          color=(0.80, 0.08, 0.08) if k != "REF" else (0.85, 0.45, 0.10)))
    # empalme soldado de los 3 cables con el rabillo, dentro de termorretráctil con adhesivo 3:1 (Ø ≈ 5 × 30 mm)
    Mj = frame(jst[0], jst[1], wc, curvo)
    j = A.tube([(-15.0, 0, 0), (15.0, 0, 0)], 2.5, 12, name="Empalme_soldado_termorretractil_adhesivo",
               color=(0.05, 0.05, 0.05))
    out.append(fix_orient(j.transform(Mj)))
    # rabillo del empalme a las colas del pogo del ECG (sube por la ranura del panel exterior)
    pts = [(jst[0], jst[1] + 4.0, wc), (jst[0], ys - 2.5, wc + 0.5), (jst[0], ys, W_OUT0 - 0.5), (jst[0], ys, W_OUT1 - 3.5)]
    uvw = A.resample(A.polyline_round(pts, 2.0, 4), 2.0)
    out.append(A.tube((bend_curvo if curvo else bend_recto)(uvw), 1.0, 8, name="Rabillo_empalme_pogo_ECG",
                      color=(0.9, 0.8, 0.1)))
    cables.longitudes = lens
    return out


# =============================================================================================== ensamblaje
def capsula_local():
    """todas las piezas de la cápsula en coordenadas de la cápsula (z = 0 en la cara inferior)"""
    imp = [pieza_base(), pieza_cojinetes(1), pieza_cojinetes(-1), pieza_junta(), pieza_tapa(), pieza_separador(),
           pieza_balancin(1), pieza_balancin(-1)]
    com = (compra_pcb() + compra_bateria() + compra_pogo_placas() + compra_tornilleria_capsula() + compra_antena() +
           compra_hilos_capsula() + compra_cierre())
    return imp, com


def soporte_local():
    S = sop_contours()
    imp = [pieza_soporte(), pieza_tacos()]
    com = compra_pogo_pines()
    com.append(chicago(S))
    # puente DET (contactos 2–3 del pogo de carga) y hilos ECG en el hueco inferior
    xc = CAP["pogo_x"]["CARGA"]; xe = CAP["pogo_x"]["ECG"]; y = CAP["pogo_y"]
    br = A.tube([(xc, y, SOP["cama"] - 7.5), (xc, y - 0.8, SOP["cama"] - 7.7), (xc + 2.3, y - 0.8, SOP["cama"] - 7.7),
                 (xc + 2.3, y, SOP["cama"] - 7.5)], 0.35, 6, name="Puente_DET_2-3", color=C_HILO["b"])
    com.append(br)
    hs = A.Mesh("Hilos_pogo_ECG_soporte", C_HILO["a"])
    for k, dx in enumerate((-2.3, 0, 2.3)):
        hs.merge(A.tube([(xe + dx, y, SOP["cama"] - 7.5), (xe + dx, y, SOP["cama"] - 7.75),
                         (xe + 0.6 * (k - 1), y, -0.8), (xe + 0.6 * (k - 1), y, -3.5)], 0.4, 6))
    com.append(hs)
    # encapsulado de las colas de los dos conectores de pines (silicona neutra / resina de colada, enrasado)
    pot = A.Mesh("Encapsulado_colas_pogo_silicona", (0.85, 0.85, 0.9))
    for k, x in CAP["pogo_x"].items():
        pot.merge(A.layered([(0.0, SOP["cama"] - 6.0, [A.stadium(x, y, 17.0, 6.95)])]))
    com.append(pot)
    # cordón de seguridad (Dyneema Ø1,5) de la oreja de la tapa al anclaje del soporte
    zc = SOP["cama"] + SOP["precarga"]
    cx, cy = S["cordon"]
    pts = [(0.0, OREJA["y"], zc + ZT1 + 1.0), (0.0, OREJA["y"], zc + ZT1 + 2.2), (0.0, OREJA["y"] + 3.0, zc + ZT1 + 1.5),
           (0.0, cy, SOP["pestana"] + 4.0), (0.0, cy, SOP["pestana"] + 0.8)]
    com.append(A.tube(A.resample(A.polyline_round(pts, 2.0, 4), 2.0), 0.75, 8, name="Cordon_seguridad_Dyneema_1.5",
                      color=(0.95, 0.85, 0.1)))
    return imp, com


def place(meshes, M):
    for m in meshes:
        m.transform(M)
        fix_orient(m)
    return meshes


def conjunto(curvo):
    groups = {}
    V_OFF = sop_v_off()
    # soporte sobre el panel exterior, centrado en u = 0
    Ms = frame(0.0, V_OFF, W_OUT1, curvo)
    imp, com = soporte_local()
    groups["Soporte_impreso"] = place(imp, Ms)
    groups["Soporte_compra"] = place(com, Ms)
    Mc = frame(0.0, V_OFF, W_OUT1 + SOP["cama"] + SOP["precarga"], curvo)
    imp, com = capsula_local()
    groups["Capsula_impresa"] = place(imp, Mc)
    groups["Capsula_electronica"] = place(com, Mc)
    ec = []
    for k in P["e_pos"]:
        ec += compra_electrodo(k, curvo)
    groups["Electrodos"] = ec
    groups["Funda"] = funda(curvo)
    groups["Cables"] = cables(curvo)
    groups["Cincha"] = cincha_decathlon(curvo)
    return groups


# =============================================================================================== exportación
def export_step(path, groups, name):
    parts = [(g, ms) for g, ms in groups.items() if ms]
    n = A.write_step(path, parts, name)
    bad = A.check_step_refs(path)
    assert not bad, bad
    return n


def check_all(groups):
    tot = 0
    for g, ms in groups.items():
        for m in ms:
            b = m.check_closed()
            tot += b
            if b:
                note("ABIERTO: %s / %s: %d aristas" % (g, m.name, b))
    return tot


def stl_print(m, name, flip=False):
    mm = m.copy()
    if flip:
        mm.transform(A.T_rotx(180))
    lo, hi = mm.bbox()
    mm.transform(A.T_translate(-(lo[0] + hi[0]) / 2, -(lo[1] + hi[1]) / 2, -lo[2]))
    fix_orient(mm)
    return mm


def main():
    print("tórax: a = %.1f, b = %.1f, n = %.2f, perímetro = %.1f mm" % (TX.a, TX.b, TX.n, TX.perim))
    REPORT["parametros"] = dict(P, torax=dict(a=TX.a, b=TX.b, n=TX.n, perimetro=TX.perim,
                                              radio_bajo_esternon=TX.radius(0.0), radio_u200=TX.radius(200.0),
                                              radio_u_menos330=TX.radius(-330.0)),
                                capsula=dict(alto=H_CAP, z=dict(bateria=(ZB0, ZB1), pcb=(ZP0, ZP1), techo=(ZT0, ZT1),
                                                                junta=(ZJ0, ZJ1))),
                                funda_w=dict(interior=(W_IN0, W_IN1), cincha=(W_G0, W_G1), exterior=(W_OUT0, W_OUT1)),
                                funda_v=dict(delantero=-VF_D, trasero=VF_T))
    REPORT["parametros"].pop("e_pos")
    REPORT["parametros"]["electrodos"] = P["e_pos"]
    for u in (0, 100, 200, -170, -330, 450):
        x, z, tx, tz = TX.point(u)
        note("tórax u=%+5.0f mm: X=%+6.1f Z=%6.1f, inclinación %.1f°, radio %.0f mm" % (
            u, x, z, math.degrees(math.atan2(tz, tx)), TX.radius(u)))
    # ------------------------------------------------------------------ piezas impresas: STL + STEP por pieza
    C = cap_contours()
    note("cápsula REV 6.4: %.1f × %.1f × %.1f mm (exterior, con los extremos alargados)" % (
        np.ptp(C["O"].p[:, 0]), np.ptp(C["O"].p[:, 1]), H_CAP))
    S = sop_contours()
    note("soporte: %.1f × %.1f × %.1f mm" % (S["fx"][1] - S["fx"][0], S["fy"][1] - S["fy"][0],
                                             SOP["cama"] + SOP["cerco_h"]))
    impresas = [
        (pieza_base(), "AVO_CINCHA_R6_4_base_aro_luz_PETG_translucido", False, "PETG translúcido natural"),
        (pieza_tapa(), "AVO_CINCHA_R6_4_tapa_PETG_opaco", True, "PETG opaco"),
        (pieza_junta(False), "AVO_CINCHA_R6_4_junta_TPU85A", False, "TPU 85A"),
        (pieza_separador(), "AVO_CINCHA_R6_4_separador_TPU85A", False, "TPU 85A"),
        (pieza_soporte(), "AVO_CINCHA_R6_4_soporte_PETG", False, "PETG opaco"),
        (pieza_balancin(1, True), "AVO_CINCHA_R6_4_balancin_Xpos_PETG", False, "PETG (cara exterior en la cama)"),
        (pieza_balancin(-1, True), "AVO_CINCHA_R6_4_balancin_Xneg_PETG", False, "PETG (cara exterior en la cama)"),
        (pieza_tapas_imanes(), "AVO_CINCHA_R6_4_tapas_imanes_PETG", False, "PETG"),
        (pieza_tacos(True), "AVO_CINCHA_R6_4_tacos_precarga_TPU85A_x4", False, "TPU 85A"),
    ]
    extras = {"AVO_CINCHA_R6_4_base_aro_luz_PETG_translucido": [pieza_cojinetes(1), pieza_cojinetes(-1)]}
    for m, nm, flip, mat in impresas:
        b = m.check_closed()
        assert b == 0, (nm, b)
        ex = extras.get(nm, [])
        for e_ in ex:
            assert e_.check_closed() == 0, (e_.name, e_.check_closed())
        mm = m.copy()
        for e_ in ex:                       # REV 6.3: las aletas van en el mismo STL que la base (se imprimen juntas)
            mm.merge(e_.copy())
        pm = stl_print(mm, nm, flip)
        nt = A.write_stl(os.path.join(OUT, "STL", nm + ".stl"), [pm])
        A.write_step(os.path.join(OUT, "STEP", "piezas", nm + ".step"), [(nm, [m] + ex)], nm)
        lo, hi = m.bbox()
        REPORT["piezas"][nm] = dict(material=mat, volumen_cm3=round(m.volume() / 1000, 3), triangulos=nt,
                                    caja_mm=[round(x, 2) for x in (hi - lo)], estanca=True)
        note("%s: %.2f cm³, %d triángulos, caja %s" % (nm, m.volume() / 1000, nt, np.round(hi - lo, 1)))
    # ------------------------------------------------------------------ subconjuntos (cápsula, soporte) en local
    imp, com = capsula_local()
    groups = {"Capsula_impresa": imp, "Capsula_electronica": com}
    check_all(groups)
    export_step(os.path.join(OUT, "STEP", "AVO_CINCHA_R6_4_CAPSULA_CONJUNTO.step"), groups, "AVO_CINCHA_R6_4_CAPSULA")
    imp2, com2 = soporte_local()
    export_step(os.path.join(OUT, "STEP", "AVO_CINCHA_R6_4_SOPORTE_CONJUNTO.step"),
                {"Soporte_impreso": imp2, "Soporte_compra": com2}, "AVO_CINCHA_R6_4_SOPORTE")
    # compra sueltas (STEP por pieza)
    for m in compra_pcb()[:1] + compra_bateria() + compra_antena()[:1]:
        A.write_step(os.path.join(OUT, "STEP", "piezas", "REF_" + m.name + ".step"), [(m.name, [m])], m.name)
    el = compra_electrodo("ECG+", False)
    A.write_step(os.path.join(OUT, "STEP", "piezas", "REF_Electrodo_Vialta_PG980-51_60x85_con_EVA.step"),
                 [("Electrodo", el)], "Electrodo")
    pcb_all = compra_pcb()
    A.write_step(os.path.join(OUT, "STEP", "piezas", "REF_PCB_REV_D_con_componentes.step"),
                 [("PCB_REV_D", pcb_all)], "PCB_REV_D")
    # ------------------------------------------------------------------ conjuntos completos
    meshes_out = {}
    for curvo, tag in ((True, "CURVADO"), (False, "RECTO")):
        g = conjunto(curvo)
        bad = check_all(g)
        note("conjunto %s: %d sólidos, aristas abiertas: %d" % (tag, sum(len(v) for v in g.values()), bad))
        n = export_step(os.path.join(OUT, "STEP", "AVO_CINCHA_MONTAJE_CONJUNTO_%s.step" % tag), g,
                        "AVO_CINCHA_MONTAJE_%s" % tag)
        note("STEP %s: %d entidades" % (tag, n))
        note("longitud de los cables de electrodo (%s): %s mm" % (tag, {k: round(v) for k, v in cables.longitudes.items()}))
        REPORT["parametros"]["cables_mm_" + tag] = {k: round(v) for k, v in cables.longitudes.items()}
        meshes_out[tag] = g
        # piezas de tela/piel por separado
        if curvo:
            A.write_step(os.path.join(OUT, "STEP", "piezas", "Funda_piel_CURVADA.step"),
                         [("Funda", g["Funda"])], "Funda")
            A.write_step(os.path.join(OUT, "STEP", "piezas", "Cincha_tipo_Decathlon_CURVADA.step"),
                         [("Cincha", g["Cincha"])], "Cincha")
        else:
            A.write_step(os.path.join(OUT, "STEP", "piezas", "Funda_piel_RECTA.step"),
                         [("Funda", g["Funda"])], "Funda")
            A.write_step(os.path.join(OUT, "STEP", "piezas", "Cincha_tipo_Decathlon_RECTA.step"),
                         [("Cincha", g["Cincha"])], "Cincha")
    for curvo, tag in ((True, "CURVADA"), (False, "RECTA")):
        hz = cincha_horze(curvo)
        A.write_step(os.path.join(OUT, "STEP", "piezas", "Cincha_tipo_Horze_anatomica_%s.step" % tag),
                     [("Cincha_Horze", hz)], "Cincha_Horze")
        if curvo:
            meshes_out["HORZE"] = {"Cincha": hz}
    # tórax de referencia
    tor = A.layered([(-150.0, 150.0, [A.polygon(TX.outline(360))])], "REF_torax_caballo_seccion", C_CABALLO)
    tor.transform(A.swap_axes(("x", "z", "y")))       # (x, z_local, y) → mundo: perfil en XZ, extrusión en Y
    fix_orient(tor)
    A.write_step(os.path.join(OUT, "STEP", "REF_torax_caballo_seccion.step"), [("REF_torax", [tor])], "REF_torax")
    meshes_out["TORAX"] = {"Torax": [tor]}
    json.dump(REPORT, open(os.path.join(OUT, "informe.json"), "w"), indent=1, ensure_ascii=False, default=float)
    return meshes_out


if __name__ == "__main__":
    main()
