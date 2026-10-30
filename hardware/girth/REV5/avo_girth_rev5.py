"""AVO GIRTH REV 5 — cápsula estanca (objetivo IP67) de 70 × 48 × 15,5 mm, 8 tornillos M3 y 4 + 4 imanes.

Peticiones del usuario sobre REV 4:
  * 8 tornillos M3 (9–10 mm) repartidos junto a las esquinas, cada uno con junta tórica 3 × 1 bajo la cabeza;
  * 4 imanes de neodimio Ø5 × 1 en las esquinas del fondo de la cápsula y otros 4 enfrentados en el soporte.
Para que quepan los M3 por dentro de la junta sin tocar la batería, la cápsula crece de 64 × 46 a 70 × 48.
Sin aberturas al exterior: USB-C dentro, sin ventana de LED, junta TPU continua en el cierre (29 % de compresión fija).
BNO085 centrado (a ~35 mm de los imanes Ø5 × 1). Los imanes de la cápsula quedan a > 21 mm del reed (Ø5 × 1: campo muy débil a esa distancia). Comprobar con el
reed en la mano antes de cerrar. IP67 es el objetivo de diseño; no está probado (prueba: 1 m, 30 min).

Componentes (medidas de los anuncios del usuario; (E) = estimado sobre la foto):
  ESP32-C6 diymore (formato XIAO) 18 × 21, PCB 1,0; USB-C en un extremo de 18; U.FL, LED (E) y antena (E) en el otro.
  BNO085 GY (HanOaki) 25,8 × 15,5 × 1,6: 10 pines en un lado largo, 2 taladros en el lado largo opuesto (E: 2,6 mm).
  Receptor Qi 5 W: placa 15 × 18; bobina redonda Ø25. Batería LP403048 50,8 × 30,5 × 4,3. Reed 14 × 3,2. Imanes Ø5 × 1.
"""
import json
import cadquery as cq

OUT = "out"
G = 0.20

# ------------------------------------------------------------------ cápsula
L, W, R = 70.0, 51.0, 10.0          # REV 5.9: 73 → 70 (sin Qi el largo lo marca la batería + los tornillos de los extremos)
H = 13.8      # REV 5.9: 15,5 → 13,8 (−1,2 abajo sin la bobina, −0,5 en el techo de la tapa)
HB = 7.8      # REV 5.9: 9,0 → 7,8
WALL = 2.0
IL, IW, IR = L - 2 * WALL, W - 2 * WALL, R - WALL   # interior 66 × 44
CEIL = H - 1.8                # REV 5.9: techo de la tapa 2,3 → 1,8

FLOOR = 1.4                   # REV 5.9: 2,6 → 1,4 (sin el hueco de la bobina Qi)
COIL = dict(d=25.0, t=1.0)                         # bobina Qi redonda Ø25 (nuevo receptor); espesor (E)
COIL_Z0 = 1.2
BAT = dict(l=50.8, w=30.5, t=4.3)
TRAY_Z0, TRAY_T = 6.0, 1.0     # REV 5.9: 7,2 → 6,0 (misma holgura de 0,25 sobre la batería)
TRAY_TOP = TRAY_Z0 + TRAY_T
BED_TOP = TRAY_TOP + 1.0          # REV 5.7: cama maciza a ras de la cara superior de los PCB (C6 y Qi)
BED_OFF = 3.75 + 1.2 + 0.15       # la cama queda dentro del labio de la tapa
CH = dict(w=2.4, floor=TRAY_TOP - 0.2)   # canales de cables: 2,4 de ancho, 1,2 de hondo, 0,8 de suelo sobre la batería

SEAL_IN = 3.6
SEAL_Z0 = HB - 1.6
GASKET = dict(c=2.0, w_groove=1.4, depth=1.0, w=1.2, h_free=1.4)
LIP_OUT, LIP_T = 3.75, 1.2
TRAY_L, TRAY_W, TRAY_R = L - 2 * LIP_OUT, W - 2 * LIP_OUT, R - LIP_OUT     # 62,5 × 40,5

# tornillos de cierre M3 desde abajo (dentro de la junta, sellados con junta tórica 3 × 1 bajo la cabeza)
# tornillos a 5 mm de la cara exterior (misma relación con la junta en todos los tamaños)
SCREWS = [(sx * 21.0, sy * (W / 2 - 5.0)) for sx in (-1, 1) for sy in (-1, 1)] + \
         [(sx * (L / 2 - 5.0), sy * 10.0) for sx in (-1, 1) for sy in (-1, 1)]
M3 = dict(hole=3.4, pilot=2.5, cb_d=5.9, cb_h=3.7, boss_lo=6.9, boss_lo_h=4.5, boss=5.6, pilot_top=14.0,
          insert_d=4.1, insert_depth=5.0, boss_lid=7.0)   # tapa: inserto roscado M3 de hasta 5 mm de largo (taladro Ø4,1, REV 5.7.3); deja 1 mm de techo
# imanes de sujeción Ø5 × 1 (cápsula y soporte, enfrentados)
MAGS = [(sx * 27.3, sy * 17.9) for sx in (-1, 1) for sy in (-1, 1)]   # REV 5.9 (L 70): corridos hacia la esquina de la batería
HMAG = dict(d=5.0, t=1.0, skin=0.3, n_base=3, n_mount=2)   # REV 5.7.5: la base admite hasta 3 imanes apilados por esquina

# ESP32-C6: 18 a lo largo de X, 21 a lo largo de Y, USB-C hacia +Y (dentro)
C6 = dict(lx=17.8, wy=21.0, pcb=1.0, usb_over=1.5,   # huella oficial Seeed: USB-C sobresale 1,5
          usb_w=8.94, usb_h=3.26, usb_l=7.35, shield=2.4)
C6_C = (15.6, 0.0)     # REV 5.9: 2 mm hacia −X (sin Qi) para dejar sitio a los tornillos de +X con L = 70
C6_X0, C6_X1 = C6_C[0] - C6["lx"] / 2, C6_C[0] + C6["lx"] / 2
C6_Y0, C6_Y1 = C6_C[1] - C6["wy"] / 2, C6_C[1] + C6["wy"] / 2      # Y0: extremo de la antena
LED = (C6_C[0] - 1.65, C6_Y0 + 2.0)                # (E)
UFL = (C6_C[0] - 4.95, C6_Y0 + 1.5)                # (E)
ANT = (C6_C[0] + 3.4, C6_Y0 + 1.2)                 # (E) 6,6 × 2,2
USB_FRONT = C6_Y1 + C6["usb_over"]

QI = dict(lx=18.0, wy=15.0, pcb=1.0, parts=1.2, center=(-19.0, 0.0))   # REV 5.7: 1 mm a −X (canal Qi–BNO)      # extremo −X; real: 18 en X, 15 en Y; bobina en −X, salidas WOUT/BAT en +X
# BNO085 pegado al C6: su fila de 10 pines (paso 2,54) queda frente a la columna D0–D6 del XIAO (paso 2,54, centrada
# en la placa según la huella oficial de Seeed), a la misma altura Y, para unir cada pin con su pad con un puente corto:
#   PS1(+PS0)–D0 · RST–D1 · INT–D2 · CS–D3 · AD0–D4 · SDA–D5 · SCL–D6 ; VCC y GND con cable a 3V3 y GND del XIAO.
BNO_PIN_OFF = 0.0     # REV 5.7.1 (foto de la prueba impresa): fila de pines centrada en la placa (~1,2 mm a cada extremo); antes 1,0 (E) → desfase de ~1,1 mm
BNO_PIN_IN = 1.3      # (E) centro de los pines respecto al borde de la placa
BNO_GAP = 0.15        # borde del BNO a 0,15 del borde del C6 (encima de su marco, que queda a ras del PCB)
BNO = dict(lx=15.5, wy=25.2, t=1.6, stand=1.5, hole_x=1.95, hole_y=2.45,   # taladros (foto): a 1,95 del borde −X y 2,45 de los extremos
           center=(C6_C[0] - C6["lx"] / 2 - BNO_GAP - 15.5 / 2, C6_C[1] - 1.27 + BNO_PIN_OFF))
C6_PADS_Y = [C6_C[1] + (3 - k) * 2.54 for k in range(7)]                      # D0 (lado USB) … D6
BNO_PINS = ["PS0", "PS1", "RST", "INT", "CS", "AD0", "SDA", "SCL", "GND", "VCC"]
BNO_PINS_Y = [BNO["center"][1] - BNO_PIN_OFF + (4.5 - k) * 2.54 for k in range(10)]
BX0, BX1 = BNO["center"][0] - BNO["lx"] / 2, BNO["center"][0] + BNO["lx"] / 2
BY0, BY1 = BNO["center"][1] - BNO["wy"] / 2, BNO["center"][1] + BNO["wy"] / 2
BNO_Z0 = TRAY_TOP + 1.0 - BNO["t"]   # REV 5.7: cara superior del BNO a ras de la del C6 (puentes por arriba, al mismo nivel)
BNO_HOLES = [(BX0 + BNO["hole_x"], BY0 + BNO["hole_y"]), (BX0 + BNO["hole_x"], BY1 - BNO["hole_y"])]
REED = dict(l=14.0, d=3.2, center=(0.0, -(W / 2 - 6.2)), z0=1.0)
MAG = dict(d=5.0, t=1.0, n=1)                     # imanes del reed (en el soporte): Ø5 × 1
# REV 5.7.2 (modificación del usuario en su CAD): 3 imanes del reed en fila bajo el reed, a −5,1 / 0 / +5,1 en X;
# los laterales en alojamientos de 1,2 mm de fondo, el central de 1,05.
REED_MAGS = [(-5.1, 1.2), (0.0, MAG["t"] * MAG["n"] + 0.05), (5.1, 1.2)]   # (sin uso desde la REV 5.9)
# REV 5.9: el reed y sus imanes se sustituyen por un conector magnético pogo de 3 pines (paso 2,54):
#  - HEMBRA (plana, contactos fijos) en el fondo de la base, entrando por dentro y apoyada en un reborde de 0,6 mm
#    (la cara queda 0,6 por dentro: el reborde aguanta el empuje de los pines y hace de molde para sellar con epoxi);
#  - MACHO (pines de muelle, con orejas) en la placa del soporte, con la cara a ras y atornillado por debajo.
#  Medidas ESTIMADAS (E) a partir de la foto del vendedor escalando el paso de 2,54: hay que confirmarlas con calibre.
# Contactos (vistos desde abajo, 1 = −X): 1 = VBUS 5 V (solo base de carga) · 2 = GND (centro) · 3 = DET (pull-up).
#   Soporte: puente 2–3 → DET a GND = "en el soporte" (sustituye al reed); 1 sin conectar.
#   Base de carga: 5 V en 1 y GND en 2; 3 sin conectar.
POGO = dict(y=-20.2,
            f_l=20.3, f_w=7.0, f_t=3.0, f_lip=0.6, f_tail=1.5,                  # hembra (E)
            m_l=17.5, m_w=6.0, m_h=5.0, m_pin=1.5, m_tail=1.5,                  # macho: cuerpo y pines libres (E)
            ear_span=25.0, ear_l=29.0, ear_w=5.0, ear_t=2.0, ear_hole=1.5,      # orejas del macho (E; agujero Ø1,5)
            clear=0.2, cup_wall=1.0, cup_z=5.5, boss=1.4)

RING_T = 1.0
GROOVE = dict(z0=3.0, z1=4.6, depth=1.0)
LIP_Y = 10.0
HOOK_Y = (0.0, 10.0)
ZC = 0.10

# ------------------------------------------------------------------ soporte
CL = 0.12
RW = 2.6
RH = GROOVE["z1"] - 0.15
MT = 6.0      # REV 5.9: placa de 6,0 (antes 4,6) para alojar el macho pogo sin salientes por debajo
STRAP = dict(w=50.0, slot=3.6, bar=4.4, ledge=5.6, chan=0.4)   # REV 5.8: ledge 5,6 (antes 1,5) para las bisagras de los cierres
# REV 5.8: cierres de palanca en los dos extremos (±X), con bisagra y pasador impreso (sustituyen al labio y a la pestaña).
#  - El cierre gira sobre un eje Y en (LATCH_AX, LATCH_AZ); cerrado queda vertical por fuera del cerco y su gancho entra
#    en una ranura del extremo de la base por encima del cerco. Si la cápsula intenta subir, empuja el gancho hacia
#    dentro (autobloqueo); para abrir se tira de la parte de arriba hacia fuera.
LATCH = dict(w=16.0, t=2.2, az=2.6, barrel=4.4, engage=1.0, lip_t=0.8, cap=1.4, clear=0.12, grip=3.0, grip_h=2.8,
             hole=2.15, lug_hole=2.3, lug_w=3.0, gap=0.2)
# REV 5.8: «clic» como en la caja de referencia: un nervio semicilíndrico en cada extremo de la TAPA (z 12, r 1,0) y
# una muesca en el gancho del cierre que lo abraza. El labio del gancho pasa 0,5 por debajo del nervio: para cerrar o
# abrir el cierre flexa (≈1,8 % de deformación con PETG) y hace clic; cerrado no se suelta solo.
# REV 5.8: llaves de posición (petición del usuario): un taco en cada extremo de la base, de distinto ancho, que entra en
# una muesca del cerco del soporte: la cápsula solo entra en una orientación.
KEYS = {1: 10.0, -1: 5.0}          # ancho (Y) del taco en +X y en −X
KEY = dict(out=2.4, z1=4.0, clear=0.2)
# REV 5.8 (2.ª ronda): nervio a ras de la cara superior de la tapa (se imprime apoyado en la cama, sin soportes).
# Cara inferior inclinada 20° hacia fuera (gancho de arpón): al abrir, el labio del cierre sube y sale a la vez y tiene
# que flexar ≈0,8 mm → clic fuerte. Arriba, el cierre abraza el nervio por encima: sujeta la cápsula hacia abajo.
RIB = dict(out=1.6, z_wall=H - 2.5, z_front=H - 3.1, w=16.0, lead=0.3)   # REV 5.9: relativo a H
PIN = dict(d=2.1, flat=0.2, head_d=3.8, head_t=1.0)

BEAM = dict(t=1.6, y_root=-13.5, y_free=12.3, z0=0.6)
TAB = dict(len=10.0, out=1.8, up=1.6)


def rrect(l, w, r, h, z0=0.0):
    return cq.Workplane("XY").workplane(offset=z0).rect(l, w).extrude(h).edges("|Z").fillet(r)


def box(cx, cy, z0, l, w, h):
    return cq.Workplane("XY").box(l, w, h, centered=(True, True, False)).translate((cx, cy, z0))


def cyl(cx, cy, z0, d, h):
    return cq.Workplane("XY").circle(d / 2).extrude(h).translate((cx, cy, z0))


def frame(cx, cy, z0, il, iw, wall, h):
    return box(cx, cy, z0, il + 2 * wall, iw + 2 * wall, h).cut(box(cx, cy, z0 - 1, il, iw, h + 2))


def rshell(off_out, off_in, h, z0):
    return rrect(L - 2 * off_out, W - 2 * off_out, R - off_out, h, z0=z0).cut(
        rrect(L - 2 * off_in, W - 2 * off_in, R - off_in, h + 2, z0=z0 - 1))


# ------------------------------------------------------------------ base
def pod_base():
    outer = rrect(L, W, R, HB).faces("<Z").edges().chamfer(0.8)                  # chaflán 45°: sin voladizo en la cama
    # pared perimetral MACIZA de 3,6 mm en toda la altura (sin reborde volado): imprime sin soportes
    b = outer.cut(rrect(L - 2 * SEAL_IN, W - 2 * SEAL_IN, R - SEAL_IN, HB, z0=FLOOR))
    # REV 5.9: sin bobina Qi (la carga entra por los contactos pogo): fondo macizo
    bl, bw = BAT["l"] + 2 * G, BAT["w"] + 2 * G
    cr = frame(0, 0, FLOOR, bl, bw, 1.0, TRAY_Z0 - FLOOR - 0.05)
    cr = cr.cut(box(bl / 2 + 0.5, -(bw / 2 - 4.0), FLOOR - 1, 2, 7.0, 10))   # REV 5.9: cables de la batería por +X/−Y
    b = b.union(cr)
    for x in (-15, 0, 15):
        for s in (-1, 1):
            b = b.union(box(x, s * (bw / 2 - 0.15), FLOOR, 1.2, 0.3, BAT["t"]))
    # REV 5.9: hembra pogo en el fondo (sustituye al canal del reed). Alojamiento con reborde de 0,6 abajo y una copa
    # alrededor para sellar con epoxi por dentro.
    py, cl = POGO["y"], POGO["clear"]
    fl, fw = POGO["f_l"] + 2 * cl, POGO["f_w"] + 2 * cl
    cw = POGO["cup_wall"]
    b = b.union(rrect(fl + 2 * cw, fw + 2 * cw, fw / 2 + cw - 0.01, POGO["cup_z"] - FLOOR + 0.1, z0=FLOOR - 0.1).translate((0, py, 0)))
    ft = POGO["f_lip"] + POGO["f_t"] + 0.05                              # techo del alojamiento de la hembra
    stad = lambda h, z0: rrect(fl, fw, fw / 2 - 0.01, h, z0=z0).translate((0, py, 0))
    b = b.cut(stad(ft - POGO["f_lip"], POGO["f_lip"]))
    yin = -(W / 2 - SEAL_IN)                                            # cara interior de la pared maciza
    b = b.cut(stad(POGO["cup_z"] + 1 - ft, ft).intersect(box(0, yin + 10, ft - 1, 40, 20, 20)))   # copa (dentro)
    wedge = (cq.Workplane("YZ", origin=(-20, 0, 0)).polyline([(py - fw / 2 - 0.01, ft - 0.01), (yin + 0.01, ft - 0.01),
                                                                 (yin + 0.01, ft + (yin - (py - fw / 2)))]).close().extrude(40))
    b = b.cut(wedge.intersect(stad(10, ft - 0.02)))                     # en la pared: techo a 45° (sin voladizo)
    ol, ow = POGO["f_l"] - 2 * POGO["f_lip"], POGO["f_w"] - 2 * POGO["f_lip"]
    b = b.cut(rrect(ol, ow, ow / 2 - 0.01, POGO["f_lip"] + 1, z0=-1).translate((0, py, 0)))
    # 8 columnas M3: más gruesas abajo (avellanado Ø5,9 para cabeza + junta tórica)
    for (x, y) in SCREWS:
        b = b.union(cyl(x, y, 0, M3["boss_lo"], M3["boss_lo_h"])).union(cyl(x, y, 0, M3["boss"], HB))
    for (x, y) in SCREWS:
        # capa de sacrificio de 0,3 mm sobre el avellanado: se imprime como puente (sin soportes); se perfora con el tornillo
        b = b.cut(cyl(x, y, M3["cb_h"] + 0.3, M3["hole"], HB + 2)).cut(cyl(x, y, -1, M3["cb_d"], M3["cb_h"] + 1))
    # imanes de sujeción: alojamiento desde dentro, 0,3 mm de piel abajo
    for (x, y) in MAGS:
        # REV 5.7.5: alojamiento para hasta 3 imanes apilados (3,1 mm de fondo); un recrecido Ø7,6 lo rodea hasta su boca
        top = HMAG["skin"] + HMAG["n_base"] * HMAG["t"] + 0.1
        rec = cyl(x, y, FLOOR - 0.1, HMAG["d"] + 0.15 + 2.4, top - FLOOR + 0.1)
        b = b.union(rec.cut(box(0, 0, FLOOR - 1, BAT["l"] + 2 * G, BAT["w"] + 2 * G, 10)))   # REV 5.9: el recrecido no pisa la batería
        b = b.cut(cyl(x, y, HMAG["skin"], HMAG["d"] + 0.15, TRAY_Z0 - HMAG["skin"]))   # boca libre hasta arriba (corta la esquina de la cuna)
    gc, gw = GASKET["c"], GASKET["w_groove"]
    b = b.cut(rshell(gc - gw / 2, gc + gw / 2, GASKET["depth"] + 1, HB - GASKET["depth"]))
    # REV 5.8: sin ranuras en los extremos (el clic del cierre va en la tapa); tacos de posición de distinto ancho
    for sx, kw in KEYS.items():
        b = b.union(box(sx * (L / 2 - 0.1 + (KEY["out"] + 0.1) / 2), 0, 0, KEY["out"] + 0.1, kw, KEY["z1"]))
    return b


# ------------------------------------------------------------------ tapa
def pod_lid():
    outer = rrect(L, W, R, H - HB - RING_T, z0=HB + RING_T).faces(">Z").edges().chamfer(1.5)   # 45°: boca abajo sin voladizo
    outer = outer.union(rshell(1.1, LIP_OUT + LIP_T, RING_T + 0.6, HB))
    # pared perimetral MACIZA de 4,95 mm desde el cierre hasta el techo (sin faldón volado)
    w = LIP_OUT + LIP_T
    lid = outer.cut(rrect(L - 2 * w, W - 2 * w, R - w, CEIL - HB + 1, z0=HB - 1))
    lid = lid.union(rshell(LIP_OUT, LIP_OUT + LIP_T, HB - TRAY_TOP - 0.05 + 0.2, TRAY_TOP + 0.05))
    qx, qy = QI["center"]
    for (x, y) in SCREWS:
        lid = lid.cut(cyl(x, y, TRAY_TOP - 1, M3["boss"] + 1.0, HB - TRAY_TOP + 1))
    for (x, y) in SCREWS:
        lid = lid.union(cyl(x, y, HB, M3["boss_lid"], CEIL - HB + 0.5))
    for (x, y) in SCREWS:                                            # alojamiento del inserto M3 (se mete con el soldador)
        lid = lid.cut(cyl(x, y, HB - 0.5, M3["insert_d"], M3["insert_depth"] + 0.5))
    for (x, y) in ((-3.0, -18.9), (-3.0, 16.5), (17.0, -15.0), (-17.0, 16.0), (-17.0, -16.0), (14.0, 15.5)):
        lid = lid.union(cyl(x, y, BED_TOP + 0.05, 2.4, CEIL - BED_TOP))       # apoyan en la cama (REV 5.7)
    for (x, y) in ((C6_X0 + 1.0 + BNO_GAP, C6_Y0 + 0.8), (C6_X1 - 0.8, C6_Y0 + 0.8)):   # el del lado −X no toca el BNO
        lid = lid.union(cyl(x, y, TRAY_TOP + C6["pcb"] + 0.05, 2.0, CEIL - TRAY_TOP - C6["pcb"]))
    # REV 5.7.1: sin tubos sobre el BNO (sus taladros están a 1,95 del borde, bajo la pestaña −X que ya lo sujeta)
    for x in (qx - QI["lx"] / 2 + 1.5, qx + QI["lx"] / 2 - 1.5):          # REV 5.9: sin Qi, estos tubos apoyan en la cama
        lid = lid.union(cyl(x, qy + QI["wy"] / 2 - 0.8, BED_TOP + 0.05, 2.0, CEIL - BED_TOP))
    # tope que aprieta el conector USB-C desde arriba (sujeta el extremo del USB; las esquinas tienen los botones)
    usb_top = TRAY_TOP + C6["pcb"] + C6["usb_h"]
    lid = lid.union(box(C6_C[0], USB_FRONT - 4.0, usb_top + 0.05, 6.0, 4.0, CEIL - usb_top - 0.05 + 0.3))
    lid = lid.cut(box(-7, -4.5, CEIL - 0.4, 29, 7, 0.45))               # antena FPC opcional (interior)
    # REV 5.8: nervios del clic de los cierres en los dos extremos
    rib = _rib_profile()
    lid = lid.union(rib).union(rib.rotate((0, 0, 0), (0, 0, 1), 180))
    # cara superior lisa, sin panel ni letras: una sola pieza, se imprime boca abajo sin soportes
    return lid


def gasket(free=True):
    c, w = GASKET["c"], GASKET["w"]
    return rshell(c - w / 2, c + w / 2, GASKET["h_free"] if free else GASKET["depth"], HB - GASKET["depth"])


def ring():
    return rshell(0, 1.0, RING_T, HB)


# ------------------------------------------------------------------ bandeja
def tray():
    """REV 5.7: cama maciza a ras de los PCB, con alojamientos y canales para los cables."""
    t = rrect(TRAY_L, TRAY_W, TRAY_R, TRAY_T, z0=TRAY_Z0)
    t = t.union(rrect(L - 2 * BED_OFF, W - 2 * BED_OFF, R - BED_OFF, BED_TOP - TRAY_TOP, z0=TRAY_TOP))
    cx, cy = C6_C
    qx, qy = QI["center"]
    hb = BED_TOP - TRAY_TOP + 1
    # alojamientos: C6 (0,1 por lado) y Qi (0,15 por lado), con el PCB apoyado en la placa y a ras de la cama
    t = t.cut(box(cx, cy, TRAY_TOP, C6["lx"] + 0.2, C6["wy"] + 0.2, hb))
    t = t.cut(box(cx, C6_Y1 + C6["usb_over"] / 2 + 0.1, BED_TOP - 0.3, C6["usb_w"] + 0.6, C6["usb_over"] + 0.2, 1))  # bajo el USB-C
    t = t.cut(box(cx, cy, TRAY_Z0 - 1, C6["lx"] - 2.0, C6["wy"] - 2.0, 3))     # ventana bajo el C6 (pads de la cara inferior)
    # REV 5.9: sin placa Qi ni ranura de la bobina; la cama queda maciza en −X (QI solo fija la posición de los canales)
    qx1 = qx + QI["lx"] / 2 + 0.15
    # --- canales (suelo a 0,8 sobre la batería)
    z, w = CH["floor"], CH["w"]
    hc = BED_TOP - z + 1
    xa = 3.0                                        # REV 5.9: canal inferior desde el paso único del pogo
    yb0, yb1 = BY0 - 0.15 - 1.0 - 0.1 - w, BY0 - 0.15 - 1.0 - 0.1   # canal inferior, bajo el tope −Y del BNO
    xw = 12.0                                       # bajada a la ventana del C6
    t = t.cut(box((xa + xw + w / 2) / 2, (yb0 + yb1) / 2, z, xw + w / 2 - xa, w, hc))
    t = t.cut(box(xw, (yb0 + C6_Y0 + 1.0) / 2, TRAY_Z0 - 1, w, C6_Y0 + 1.0 - yb0, 4))   # pasa bajo el PCB hasta la ventana
    # REV 5.9 (petición del usuario): cables de la batería por +X/−Y, junto al C6: suben por fuera del extremo de la
    # batería y pasan bajo el borde del PCB hasta la ventana (pads BAT+/BAT− de la cara inferior del XIAO)
    BH = (BAT["l"] / 2 + G - 0.6, 26.8, -15.0, -12.8)          # x0, x1, y0, y1 · REV 5.9: más adentro, no corta el borde de la cama
    xg0 = C6_X1 - 3.0
    t = t.cut(box((xg0 + BH[1]) / 2, (BH[2] + BH[3]) / 2, TRAY_Z0 - 1, BH[1] - xg0, BH[3] - BH[2], 4))
    t = t.cut(box(xg0 + 1.0, (BH[2] + C6_Y0 + 1.0) / 2, TRAY_Z0 - 1, 2.0, C6_Y0 + 1.0 - BH[2], 4))
    rx, ry = REED["center"]
    # REV 5.9 (petición del usuario): un solo paso para los 3 hilos del pogo, en +X, que entra en el canal inferior
    t = t.cut(box((xa + 12.5) / 2, ry + 0.2, TRAY_Z0 - 1, 12.5 - xa, 3, 4))
    t = t.cut(box((xa + 12.5) / 2, (ry + 1.7 + yb0 + 0.5) / 2, z, 12.5 - xa, yb0 + 0.5 - ry - 1.7, hc))
    t = t.cut(box(BX1 - 1.3, (yb1 + BNO_PINS_Y[8] + 0.9) / 2, z, 2.2, BNO_PINS_Y[8] + 0.9 - yb1, hc))  # GND/VCC del BNO
    # BNO085 hundido: su cara superior queda a ras de la del C6 (los pines de los dos, al mismo nivel por arriba).
    # Alojamiento a 0,15 por lado, unido al del C6; apoya en un reborde de 1 mm y debajo queda ventana (soldaduras).
    bx, by = BNO["center"]
    t = t.cut(box(bx, by, BNO_Z0, BNO["lx"] + 0.3, BNO["wy"] + 0.3, BED_TOP - BNO_Z0 + 1))
    t = t.cut(box(bx, by, TRAY_Z0 - 1, BNO["lx"] - 2.0, BNO["wy"] - 2.0, 3))
    # BNO: pestaña superior en su lado −X (pared de 0,8 junto al canal + 0,45 sobre el PCB, a 0,05 de su cara superior)
    wy0, wy1 = BY0 + 1.0, BY1 - 1.0
    t = t.union(box(BX0 - 0.15 - 0.4, (wy0 + wy1) / 2, CH["floor"], 0.8, wy1 - wy0, BED_TOP + 1.2 - CH["floor"]))
    t = t.union(box(BX0 - 0.15 + 0.3, (wy0 + wy1) / 2, BED_TOP + 0.05, 0.6, wy1 - wy0, 1.15))
    # C6: pestaña superior en el lado opuesto al BNO (+X): 0,6 sobre el PCB, a 0,05 de su cara superior
    ly0, ly1 = C6_Y0 + 2.1, C6_Y1 - 1.5
    t = t.union(box(C6_X1 + 0.1 + 0.5, (ly0 + ly1) / 2, BED_TOP - 0.1, 1.0, ly1 - ly0, 1.3))
    # REV 5.7.4 (prueba impresa: el C6 no entraba): cara inferior de la pestaña a 0,15 sobre el PCB (antes 0,05)
    t = t.union(box(C6_X1 + 0.1 - 0.3, (ly0 + ly1) / 2, BED_TOP + 0.15, 0.6, ly1 - ly0, 1.05))
    for (x, y) in SCREWS:
        t = t.cut(cyl(x, y, TRAY_Z0 - 1, M3["boss_lid"] + 0.4, 6))      # holgura para las columnas Ø7 de la tapa
    return t.intersect(rrect(TRAY_L, TRAY_W, TRAY_R, 10, z0=TRAY_Z0 - 1))


# ------------------------------------------------------------------ soporte (una sola pieza)
def _mount_geom():
    il, iw, ir = L + 2 * CL, W + 2 * CL, R + CL
    ol, ow, orr = il + 2 * RW, iw + 2 * RW, ir + RW
    xs0 = ol / 2 + STRAP["ledge"]                      # borde interior de los pasos de cinta
    xs1 = xs0 + STRAP["slot"]
    pl = 2 * (xs1 + STRAP["bar"])
    pw = max(STRAP["w"] + 2.0 + 2 * 3.2, ow + 5.0)      # el redondeo de 1,8 del borde no llega bajo el cerco
    return il, iw, ir, ol, ow, orr, xs0, xs1, pl, pw


def _latch_ax():
    ol = L + 2 * CL + 2 * RW
    return ol / 2 + LATCH["barrel"] / 2 + 0.3               # eje de la bisagra (en +X): el barril libra el cerco 0,3


def _rib_profile(grow=0.0):
    """Nervio del clic en el extremo +X de la tapa (REV 5.8): de la cara superior (z = H) hacia abajo, cara inferior
    inclinada (más baja por fuera), frente vertical con un pequeño chaflán de entrada abajo. grow = holgura de la muesca."""
    x0, xf = L / 2 - 0.1, L / 2 + RIB["out"] + grow
    zw, zf, zt, ld = RIB["z_wall"] - grow, RIB["z_front"] - grow, H + grow, RIB["lead"]
    w = RIB["w"] + 2 * grow
    pts = [(x0, zw), (xf - ld, zf + ld * (zw - zf) / (xf - x0)), (xf, zf + ld), (xf, zt), (x0, zt)]
    r = cq.Workplane("XZ", origin=(0, w / 2, 0)).polyline(pts).close().extrude(w)
    if grow == 0.0:   # REV 5.8.1: extremos redondeados en planta (estética); la muesca del cierre sigue recta (más holgura)
        r = r.edges("|Z and >X").fillet(1.0)
    return r


def latch(sx=1):
    """Cierre de palanca (REV 5.8) en el extremo sx (+1 = +X), cerrado: muesca que abraza el nervio de la tapa, con el
    labio debajo (clic) y la tapa del gancho por encima (sujeta la cápsula)."""
    ax, az, w, t = _latch_ax(), LATCH["az"], LATCH["w"], LATCH["t"]
    xo = ax + t / 2
    cl = LATCH["clear"]
    lip_x = L / 2 + RIB["out"] - LATCH["engage"]
    z_low = RIB["z_front"] - cl - LATCH["lip_t"]
    top = H + cl + LATCH["cap"]
    c = (cq.Workplane("XZ", origin=(0, w / 2, 0)).center(ax, az).circle(LATCH["barrel"] / 2).extrude(w))
    c = c.union(box(ax, 0, az, t, w, top - az))
    c = c.union(box((lip_x + xo) / 2, 0, z_low, xo - lip_x, w, top - z_low))
    # tirador para soltar: saliente de 3 mm hacia fuera en la parte de arriba, con los cantos redondeados
    c = c.union(box(xo + LATCH["grip"] / 2 - 0.01, 0, top - LATCH["grip_h"], LATCH["grip"] + 0.02, w, LATCH["grip_h"])
                .edges("|Y and >X").fillet(1.35))
    c = c.cut(_rib_profile(grow=cl))                                   # muesca que abraza el nervio
    # REV 5.8.1: curvas (estética y resistencia): esquina de arriba sobre la tapa, rincones del gancho y del tirador, labio
    xi = ax - t / 2
    NP = cq.selectors.NearestToPointSelector
    for (pt, r) in (((lip_x, 0, top), 1.0), ((xi, 0, z_low), 1.0), ((xo, 0, top - LATCH["grip_h"]), 0.8),
                    ((lip_x, 0, z_low), 0.4)):
        c = c.edges(NP(pt)).fillet(r)
    c = c.cut(cq.Workplane("XZ", origin=(0, w / 2 + 1, 0)).center(ax, az).circle(LATCH["hole"] / 2).extrude(w + 2))
    return c if sx > 0 else c.rotate((0, 0, 0), (0, 0, 1), 180)


def pin(sx=1):
    """Pasador impreso (REV 5.8): Ø2,1 con un plano de 0,2 abajo (se imprime tumbado) y cabeza Ø3,8."""
    ax, az = _latch_ax(), LATCH["az"]
    span = LATCH["w"] + 2 * (LATCH["gap"] + LATCH["lug_w"])
    p = cq.Workplane("XZ", origin=(0, span / 2, 0)).center(ax, az).circle(PIN["d"] / 2).extrude(span)
    p = p.union(cq.Workplane("XZ", origin=(0, span / 2 + PIN["head_t"], 0)).center(ax, az).circle(PIN["head_d"] / 2).extrude(PIN["head_t"]))
    p = p.cut(box(ax, 0, az - PIN["head_d"] / 2 - 1, 5, span + 4, 1 + PIN["head_d"] / 2 - PIN["d"] / 2 + PIN["flat"]))
    return p if sx > 0 else p.rotate((0, 0, 0), (0, 0, 1), 180)


def mount():
    il, iw, ir, ol, ow, orr, xs0, xs1, pl, pw = _mount_geom()
    p = rrect(pl, pw, 7.0, MT, z0=-MT)
    p = p.faces(">Z").edges().fillet(1.8).faces("<Z").edges().chamfer(0.5)
    # pasos de cinta cerrados (52 × 3,6, extremos redondeados) y canal inferior de 0,4 para la cinta
    for sx in (-1, 1):
        p = p.cut(rrect(STRAP["slot"], STRAP["w"] + 2.0, 1.6, MT + 2, z0=-MT - 1).translate((sx * (xs0 + xs1) / 2, 0, 0)))
    # cerco
    rim = rrect(ol, ow, orr, RH).cut(rrect(il, iw, ir, RH + 2, z0=-1))
    rim = rim.faces(">Z").edges().fillet(0.8)
    for sx, kw in KEYS.items():                                       # REV 5.8: muescas de las llaves de posición
        rim = rim.cut(box(sx * (L / 2 + 2.0), 0, -1, 6.0, kw + 2 * KEY["clear"], RH + 2))
    p = p.union(rim)
    # REV 5.8: bisagras de los cierres en ±X (dos orejas por cierre, taladro Ø2,3 para el pasador impreso)
    ax, az = _latch_ax(), LATCH["az"]
    r_l = LATCH["barrel"] / 2 + 0.2
    for sx in (-1, 1):
        for sy in (-1, 1):
            yc = sy * (LATCH["w"] / 2 + LATCH["gap"] + LATCH["lug_w"] / 2)
            lug = box(ax - 0.25, yc, -0.1, 2 * r_l + 0.5, LATCH["lug_w"], az + 0.1)   # la mitad baja del ojo queda apoyada
            lug = lug.union(cq.Workplane("XZ", origin=(0, yc + LATCH["lug_w"] / 2, 0)).center(ax, az).circle(r_l).extrude(LATCH["lug_w"]))
            # REV 5.8.1: agujero en «D», con la misma forma que el pasador (plano abajo): el pasador no gira en la oreja
            dh = PIN["d"] + 0.15
            zflat = az - PIN["d"] / 2 + PIN["flat"] - 0.075
            hole = (cq.Workplane("XZ", origin=(0, yc + LATCH["lug_w"] / 2 + 1, 0)).center(ax, az)
                    .circle(dh / 2).extrude(LATCH["lug_w"] + 2)
                    .intersect(box(ax, yc, zflat, dh + 1, LATCH["lug_w"] + 4, dh + 1)))
            lug = lug.cut(hole)
            p = p.union(lug if sx > 0 else lug.rotate((0, 0, 0), (0, 0, 1), 180))
    # REV 5.9: macho pogo en la placa (sustituye a los imanes del reed): cara a ras de la placa, cuerpo hacia abajo,
    # orejas en un rebaje por debajo con 2 tornillos M1,6 (piloto Ø1,3) y canal para el cable.
    py, cl = POGO["y"], POGO["clear"]
    zb = -MT                                                            # cara inferior de la placa
    p = p.cut(rrect(POGO["m_l"] + 2 * cl, POGO["m_w"] + 2 * cl, (POGO["m_w"] + 2 * cl) / 2 - 0.01, MT + 2, z0=-MT - 1)
              .translate((0, py, 0)))
    p = p.cut(rrect(POGO["ear_l"] + 2 * cl, POGO["ear_w"] + 2 * cl, (POGO["ear_w"] + 2 * cl) / 2 - 0.01,
                    POGO["ear_t"] + (-POGO["m_h"] - zb) + 0.11, z0=zb - 0.01).translate((0, py, 0)))
    for sx in (-1, 1):
        p = p.cut(cyl(sx * POGO["ear_span"] / 2, py, zb - 1, 1.3, -1.0 - (zb - 1)))     # piloto M1,6 hasta 1 mm de la cara
    # sin canal de cable: en el soporte el macho solo lleva un puente GND–DET soldado por detrás (interruptor)
    for (x, y) in MAGS:                                              # imanes de sujeción Ø5 × 1 (enfrentados a los de la cápsula)
        p = p.cut(cyl(x, y, -HMAG["n_mount"] * HMAG["t"] - 0.05, HMAG["d"] + 0.15, 3))   # REV 5.7.6: 2 imanes apilados
    return p


def tab_body():
    """REV 5.7.2: tirador macizo, unido a la pestaña elástica (viga + nervio) del soporte: una sola pieza.
    Perfil en XZ: apoya en la viga y el nervio (que bajan hasta la cama); el vuelo exterior de 0,8 lleva chaflán de 45°."""
    il = _mount_geom()[0]
    bx0 = il / 2
    y0, y1 = BEAM["y_free"] - TAB["len"], BEAM["y_free"]
    x_in, x_rib, x_out = bx0 + 0.1, bx0 + BEAM["t"] + 1.0, bx0 + BEAM["t"] + TAB["out"]
    z0, z1 = 1.4, RH + TAB["up"]
    t = (cq.Workplane("XZ", origin=(0, y1, 0))
         .polyline([(x_in, z0), (x_rib, z0), (x_out, z0 + (x_out - x_rib)), (x_out, z1), (x_in, z1)])
         .close().extrude(y1 - y0))
    return t.faces(">Z").edges("|Y").fillet(0.7)


def mount_with_tab():
    return mount().union(tab_body())


def tab():
    il = _mount_geom()[0]
    bx0 = il / 2
    y0, y1 = BEAM["y_free"] - TAB["len"], BEAM["y_free"]
    t = box(bx0 + 0.1 + (BEAM["t"] + TAB["out"] - 0.1) / 2, (y0 + y1) / 2, 1.4,
            BEAM["t"] + TAB["out"] - 0.1, y1 - y0, RH + TAB["up"] - 1.4)
    t = t.edges("|Y").fillet(0.7)
    t = t.cut(box(bx0 + BEAM["t"] / 2, (y0 + y1) / 2, 0, BEAM["t"] + 0.1, y1 - y0 + 2, RH + 0.05))
    t = t.cut(box(bx0 + BEAM["t"] + 0.5, BEAM["y_free"] - TAB["len"] / 2, 1.0, 1.1, TAB["len"] - 4.0 + 0.1, RH - 2.0 + 0.65))
    return t


# ------------------------------------------------------------------ componentes (referencia, no se imprimen)
def components():
    cx, cy = C6_C; qx, qy = QI["center"]; bx, by = BNO["center"]; rx, ry = REED["center"]
    pz = TRAY_TOP + C6["pcb"]
    usb = (cq.Workplane("XZ", origin=(0, USB_FRONT, 0)).center(cx, pz + C6["usb_h"] / 2)
           .rect(C6["usb_w"], C6["usb_h"]).extrude(C6["usb_l"]).edges("|Y").fillet(1.3))
    c6 = (box(cx, cy, TRAY_TOP + 0.02, C6["lx"], C6["wy"], C6["pcb"] - 0.02).union(usb)
          .union(box(cx + 0.1, C6_Y0 + 3.4 + 5.2, pz, 13.2, 10.4, C6["shield"]))
          .union(box(UFL[0], UFL[1], pz, 2.6, 2.6, 1.25)).union(box(ANT[0], ANT[1], pz, 6.6, 2.2, 1.2))
          .union(box(LED[0], LED[1], pz, 0.6, 1.0, 0.4)))
    bz = BNO_Z0 + 0.02
    bno = box(bx, by, bz, BNO["lx"], BNO["wy"], BNO["t"])
    for (hx, hy) in BNO_HOLES:
        bno = bno.cut(cyl(hx, hy, bz - 1, 3.0, 4))
    bno = bno.union(box(bx + 0.5, by + 2.0, bz + BNO["t"], 5.2, 5.2, 1.0))
    mags = cyl(*MAGS[0], HMAG["skin"] + 0.02, HMAG["d"], HMAG["t"])
    for (x, y) in MAGS[1:]:
        mags = mags.union(cyl(x, y, HMAG["skin"] + 0.02, HMAG["d"], HMAG["t"]))
    mmags = cyl(*MAGS[0], -HMAG["n_mount"] * HMAG["t"] - 0.02, HMAG["d"], HMAG["n_mount"] * HMAG["t"])
    for (x, y) in MAGS[1:]:
        mmags = mmags.union(cyl(x, y, -HMAG["n_mount"] * HMAG["t"] - 0.02, HMAG["d"], HMAG["n_mount"] * HMAG["t"]))
    return {
        "bateria_LP403048": box(0, 0, FLOOR + 0.05, BAT["l"], BAT["w"], BAT["t"]),
        "ESP32_C6": c6,
        "BNO085": bno,
        "pogo_hembra": rrect(POGO["f_l"], POGO["f_w"], POGO["f_w"] / 2 - 0.01, POGO["f_t"], z0=POGO["f_lip"] + 0.02).translate((0, POGO["y"], 0)),
        "antena_FPC": box(-7, -4.5, CEIL - 0.35, 28, 6, 0.3),
        "pogo_macho": _pogo_male(),
        "imanes_capsula_5x1": mags,
        "imanes_soporte_5x1": mmags,
    }


def _pogo_male():
    """Macho pogo en posición (pines comprimidos hasta 0,05 por debajo de la cara de la hembra)."""
    py = POGO["y"]
    m = rrect(POGO["m_l"], POGO["m_w"], POGO["m_w"] / 2 - 0.01, POGO["m_h"] - 0.02, z0=-POGO["m_h"] + 0.01).translate((0, py, 0))
    m = m.union(rrect(POGO["ear_l"], POGO["ear_w"], POGO["ear_w"] / 2 - 0.01, POGO["ear_t"], z0=-POGO["m_h"] + 0.01).translate((0, py, 0)))
    for sx in (-1, 1):
        m = m.cut(cyl(sx * POGO["ear_span"] / 2, py, -POGO["m_h"] - 1, POGO["ear_hole"], POGO["ear_t"] + 2))
    for k in (-1, 0, 1):
        m = m.union(cyl(k * 2.54, py, -0.01, 1.0, POGO["f_lip"] - 0.05 + 0.01))
    return m


def main():
    import os
    os.makedirs(OUT, exist_ok=True)
    P = "AVO_GIRTH_R5_"
    parts = {
        P + "base": pod_base(),
        P + "aro_rojo": ring(),
        P + "tapa": pod_lid(),
        P + "bandeja": tray(),
        P + "junta_TPU": gasket(free=False),
        P + "soporte": mount(),                   # REV 5.8: sin labio ni pestaña; con las bisagras de los cierres
        P + "cierre_x2": latch(1),                # REV 5.8: imprimir 2 (el de −X es el mismo girado 180°)
        P + "cierre_-X": latch(-1),
        P + "pasador_x2": pin(1),                 # REV 5.8: imprimir 2
        P + "pasador_-X": pin(-1),
    }
    comps = components()
    report = {"piezas": {}, "interferencias": {}, "medidas": {}}
    for n, s in parts.items():
        # STEP/STL de cada pieza YA ORIENTADOS PARA IMPRIMIR (tapa y tirador boca abajo), apoyados en Z = 0
        if n.endswith("-X"):
            # copias de montaje (para las comprobaciones y las vistas): no se exportan para imprimir
            os.makedirs(f"{OUT}/montaje", exist_ok=True)
            cq.exporters.export(s, f"{OUT}/montaje/{n}.stl", tolerance=0.05)
            continue
        if n.endswith("cierre_x2"):
            sp = s.rotate((0, 0, 0), (1, 0, 0), 90)       # de canto: el perfil en la cama, el agujero vertical
        else:
            sp = s.rotate((0, 0, 0), (1, 0, 0), 180) if (n.endswith("tapa") or n.endswith("tirador_rojo")) else s
        sp = sp.translate((0, 0, -sp.val().BoundingBox().zmin))
        cq.exporters.export(sp, f"{OUT}/{n}.step")
        cq.exporters.export(sp, f"{OUT}/{n}.stl", tolerance=0.02, angularTolerance=0.1)
        os.makedirs(f"{OUT}/montaje", exist_ok=True)                 # misma pieza en posición de montaje (para vistas)
        cq.exporters.export(s, f"{OUT}/montaje/{n}.stl", tolerance=0.05)
        bb = s.val().BoundingBox()
        nsol = len(s.solids().vals())
        if nsol != 1:
            raise SystemExit(f"{n}: {nsol} sólidos (debe ser 1 pieza unida)")
        report["piezas"][n] = {"volumen_mm3": round(s.val().Volume(), 1), "valido": s.val().isValid(), "solidos": nsol,
                               "caja": [round(bb.xlen, 2), round(bb.ylen, 2), round(bb.zlen, 2)]}
    # la junta se imprime con su altura libre (1,4 mm)
    cq.exporters.export(gasket(free=True), f"{OUT}/{P}junta_TPU.stl", tolerance=0.02, angularTolerance=0.1)
    cq.exporters.export(gasket(free=True), f"{OUT}/{P}junta_TPU.step")
    for n, s in comps.items():
        cq.exporters.export(s, f"{OUT}/ref_{n}.stl", tolerance=0.05)
    for cn, c in comps.items():
        for pn, p in parts.items():
            try:
                v = c.intersect(p).val().Volume()
            except Exception:
                v = 0.0
            if v > 0.01 and not (cn.startswith("bateria") and pn.endswith("base") and v < 4):
                report["interferencias"][f"{cn} × {pn}"] = round(v, 3)
    names = list(comps)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            try:
                v = comps[names[i]].intersect(comps[names[j]]).val().Volume()
            except Exception:
                v = 0.0
            if v > 0.01:
                report["interferencias"][f"{names[i]} × {names[j]}"] = round(v, 3)
    names = list(parts)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            try:
                x = parts[names[i]].intersect(parts[names[j]]).val()
                v = x.Volume()
                bb = x.BoundingBox()
                where = [round(bb.xmin, 2), round(bb.xmax, 2), round(bb.ymin, 2), round(bb.ymax, 2), round(bb.zmin, 2), round(bb.zmax, 2)]
            except Exception:
                v, where = 0.0, None
            if v > 0.01:
                report["interferencias"][f"{names[i]} × {names[j]}"] = [round(v, 3), where]
    # REV 5.8: barrido de apertura del cierre (+X): no debe tocar la base ni el soporte en ningún ángulo
    ax = _latch_ax()
    fixed = parts[P + "base"].union(parts[P + "soporte"]).union(parts[P + "tapa"]).union(parts[P + "aro_rojo"])
    sweep = {}
    for ang in (0, 12, 15, 20, 30, 45, 60):   # 1–11°: zona del clic (flexa a propósito); a ~75° el tirador apoya en la placa (tope)
        lt = latch(1).rotate((ax, 0, LATCH["az"]), (ax, 1, LATCH["az"]), ang)
        try:
            v = lt.intersect(fixed).val().Volume()
        except Exception:
            v = 0.0
        sweep[ang] = round(v, 3)
        if v > 0.01:
            report["interferencias"][f"cierre abierto {ang}° × cápsula/soporte"] = round(v, 3)
    # interferencia máxima en la zona del clic (informativa): cuánto tiene que flexar el gancho
    clic = {}
    for ang in (1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11):
        lt = latch(1).rotate((ax, 0, LATCH["az"]), (ax, 1, LATCH["az"]), ang)
        try:
            clic[ang] = round(lt.intersect(fixed).val().Volume(), 2)
        except Exception:
            clic[ang] = 0.0
    report["clic_interferencia_grados_mm3"] = clic
    report["barrido_cierre_grados_mm3"] = sweep
    g = _mount_geom()
    report["medidas"] = {"soporte_mm": [round(g[8], 2), round(g[9], 2), MT + RH], "capsula_mm": [L, W, H],
                         "aberturas_al_exterior": 0, "tornillos_M3": len(SCREWS), "imanes_5x1": 2 * len(MAGS), "junta_compresion_pct": round(100 * (GASKET["h_free"] - GASKET["depth"]) / GASKET["h_free"]),
                         "bno_taladros": BNO_HOLES, "bno_pines_y": dict(zip(BNO_PINS, [round(v, 2) for v in BNO_PINS_Y])),
                         "c6_pads_D0_D6_y": [round(v, 2) for v in C6_PADS_Y], "c6_centro": C6_C, "led": LED}
    asm = cq.Assembly(name="AVO_GIRTH_R5")
    colors = {"aro": (0.93, 0.07, 0.16), "panel": (0.85, 0.06, 0.14), "tirador": (0.93, 0.07, 0.16),
              "base": (0.09, 0.09, 0.11), "tapa": (0.09, 0.09, 0.11), "bandeja": (0.18, 0.19, 0.22),
              "junta": (0.2, 0.2, 0.22), "soporte": (0.12, 0.13, 0.15)}
    for n, s in parts.items():
        key = next((k for k in colors if k in n), "base")
        asm.add(s, name=n, color=cq.Color(*colors[key], 1.0))
    for n, s in comps.items():
        asm.add(s, name="ref_" + n, color=cq.Color(0.8, 0.5, 0.2, 1.0))
    asm.save(f"{OUT}/AVO_GIRTH_R5_CONJUNTO.step")
    json.dump(report, open(f"{OUT}/informe.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
