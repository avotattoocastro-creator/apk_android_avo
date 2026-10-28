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
L, W, R = 73.0, 51.0, 10.0          # REV 5.5: +3/+3 para pared maciza e imanes de esquina sin voladizo
H = 15.5
HB = 9.0
WALL = 2.0
IL, IW, IR = L - 2 * WALL, W - 2 * WALL, R - WALL   # interior 66 × 44
CEIL = H - 2.3

FLOOR = 2.6
COIL = dict(d=25.0, t=1.0)                         # bobina Qi redonda Ø25 (nuevo receptor); espesor (E)
COIL_Z0 = 1.2
BAT = dict(l=50.8, w=30.5, t=4.3)
TRAY_Z0, TRAY_T = 7.2, 1.0
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
MAGS = [(sx * (L / 2 - 7.6), sy * (W / 2 - 7.2)) for sx in (-1, 1) for sy in (-1, 1)]   # entre la cuna y la pared maciza
HMAG = dict(d=5.0, t=1.0, skin=0.3, n_base=3)   # REV 5.7.5: la base admite hasta 3 imanes apilados por esquina

# ESP32-C6: 18 a lo largo de X, 21 a lo largo de Y, USB-C hacia +Y (dentro)
C6 = dict(lx=17.8, wy=21.0, pcb=1.0, usb_over=1.5,   # huella oficial Seeed: USB-C sobresale 1,5
          usb_w=8.94, usb_h=3.26, usb_l=7.35, shield=2.4)
C6_C = (17.6, 0.0)
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
REED_MAGS = [(-5.1, 1.2), (0.0, MAG["t"] * MAG["n"] + 0.05), (5.1, 1.2)]

RING_T = 1.0
GROOVE = dict(z0=3.0, z1=4.6, depth=1.0)
LIP_Y = 10.0
HOOK_Y = (0.0, 10.0)
ZC = 0.10

# ------------------------------------------------------------------ soporte
CL = 0.12
RW = 2.6
RH = GROOVE["z1"] - 0.15
MT = 4.6
STRAP = dict(w=50.0, slot=3.6, bar=4.4, ledge=1.5, chan=0.4)
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
    b = b.cut(cyl(0, 0, COIL_Z0, COIL["d"] + 2 * G, FLOOR))                       # alojamiento de la bobina Ø25,4
    b = b.cut(box(-(11.0 + 31.0) / 2, -5.0, COIL_Z0 + 0.4, 31.0 - 11.0, 2.0, FLOOR))   # hilos de la bobina hacia −X
    bl, bw = BAT["l"] + 2 * G, BAT["w"] + 2 * G
    cr = frame(0, 0, FLOOR, bl, bw, 1.0, TRAY_Z0 - FLOOR - 0.05)
    cr = cr.cut(box(-(bl / 2 + 0.5), bw / 2 - 4.0, FLOOR - 1, 2, 7.0, 10))   # REV 5.7: cables de la batería por −X/+Y
    cr = cr.cut(box(-(bl / 2 + 0.5), -3.5, FLOOR - 1, 2, 6.0, 10))   # paso de los hilos de la bobina en la pared −X (prueba impresa)
    b = b.union(cr)
    for x in (-15, 0, 15):
        for s in (-1, 1):
            b = b.union(box(x, s * (bw / 2 - 0.15), FLOOR, 1.2, 0.3, BAT["t"]))
    rx, ry = REED["center"]
    b = b.cut(box(rx, ry, REED["z0"], REED["l"] + 2 * G + 2.0, REED["d"] + 2 * G, FLOOR))      # +1 mm por extremo (prueba impresa)
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
        b = b.union(cyl(x, y, FLOOR - 0.1, HMAG["d"] + 0.15 + 2.4, top - FLOOR + 0.1))
        b = b.cut(cyl(x, y, HMAG["skin"], HMAG["d"] + 0.15, top - HMAG["skin"] + 0.01))   # no entra en la cuna (sin voladizo)
    gc, gw = GASKET["c"], GASKET["w_groove"]
    b = b.cut(rshell(gc - gw / 2, gc + gw / 2, GASKET["depth"] + 1, HB - GASKET["depth"]))
    gz, gh, gd = GROOVE["z0"], GROOVE["z1"] - GROOVE["z0"], GROOVE["depth"]
    z1 = GROOVE["z1"]
    for sx, (ya, yb) in ((-1, (-LIP_Y - 0.5, LIP_Y + 0.5)), (1, (HOOK_Y[0] - 1.0, HOOK_Y[1] + 1.0))):
        xf = sx * L / 2
        b = b.cut(box(xf - sx * (gd / 2 - 0.5), (ya + yb) / 2, gz, gd + 1.0, yb - ya, gh))
        # techo de la ranura a 45° (la cara inferior, la que bloquea, sigue horizontal): sin soportes
        wedge = (cq.Workplane("XZ", origin=(0, yb, 0))
                 .polyline([(xf + sx * 0.5, z1 - 0.01), (xf - sx * gd, z1 - 0.01), (xf + sx * 0.5, z1 + gd + 0.5)])
                 .close().extrude(yb - ya))
        b = b.cut(wedge)
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
    for x in (qx - QI["lx"] / 2 + 1.5, qx + QI["lx"] / 2 - 1.5):
        lid = lid.union(cyl(x, qy + QI["wy"] / 2 - 0.8, TRAY_TOP + QI["pcb"] + 0.05, 2.0, CEIL - TRAY_TOP - QI["pcb"]))
    # tope que aprieta el conector USB-C desde arriba (sujeta el extremo del USB; las esquinas tienen los botones)
    usb_top = TRAY_TOP + C6["pcb"] + C6["usb_h"]
    lid = lid.union(box(C6_C[0], USB_FRONT - 4.0, usb_top + 0.05, 6.0, 4.0, CEIL - usb_top - 0.05 + 0.3))
    lid = lid.cut(box(-7, -4.5, CEIL - 0.4, 29, 7, 0.45))               # antena FPC opcional (interior)
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
    t = t.cut(box(qx, qy, TRAY_TOP, QI["lx"] + 0.3, QI["wy"] + 0.3, hb))
    qx0, qx1 = qx - QI["lx"] / 2 - 0.15, qx + QI["lx"] / 2 + 0.15
    # hilos de la bobina: ranura ABIERTA hasta el borde −X de la bandeja (los hilos entran de lado, sin desoldar la bobina)
    t = t.cut(box((qx0 - L / 2 - 1.0) / 2 + 0.0, -3.0, TRAY_Z0 - 1, qx0 + L / 2 + 1.0, 3.0, 4))
    # --- canales (suelo a 0,8 sobre la batería)
    z, w = CH["floor"], CH["w"]
    hc = BED_TOP - z + 1
    xa, xb = qx1, BX0 - 0.15 - 0.8                  # canal vertical entre la Qi y el BNO (deja 0,8 de pared al BNO)
    yb0, yb1 = BY0 - 0.15 - 1.0 - 0.1 - w, BY0 - 0.15 - 1.0 - 0.1   # canal inferior, bajo el tope −Y del BNO
    yt0, yt1 = 11.1, 11.1 + w                       # canal superior (cables de la batería hasta la Qi)
    bat_hole = (-26.0, 13.2)
    t = t.cut(box((xa + xb) / 2, (yb0 + yt1) / 2, z, xb - xa, yt1 - yb0, hc))
    t = t.cut(box((bat_hole[0] - 1.5 + xa) / 2, (yt0 + yt1) / 2, z, xa - bat_hole[0] + 1.5, w, hc))
    xw = 12.0                                       # bajada a la ventana del C6
    t = t.cut(box((xa + xw + w / 2) / 2, (yb0 + yb1) / 2, z, xw + w / 2 - xa, w, hc))
    t = t.cut(box(xw, (yb0 + C6_Y0 + 1.0) / 2, TRAY_Z0 - 1, w, C6_Y0 + 1.0 - yb0, 4))   # pasa bajo el PCB hasta la ventana
    t = t.cut(box(*bat_hole, TRAY_Z0 - 1, 3, 4, 4))                                    # paso de los cables de la batería (−X/+Y)
    rx, ry = REED["center"]
    for x in (rx - REED["l"] / 2 - 2.5, rx + REED["l"] / 2 + 2.5):                     # patas del reed → canal inferior
        t = t.cut(box(x, ry + 0.2, TRAY_Z0 - 1, 3, 3, 4))
        t = t.cut(box(x, (ry + 1.7 + yb0 + 0.5) / 2, z, 2.2, yb0 + 0.5 - ry - 1.7, hc))
    t = t.cut(box(BX1 - 1.3, (yb1 + BNO_PINS_Y[8] + 0.9) / 2, z, 2.2, BNO_PINS_Y[8] + 0.9 - yb1, hc))  # GND/VCC del BNO
    # topes de la Qi en +X (dentro del canal, dejan 2,3 de paso a los cables)
    for sy in (-1, 1):
        t = t.union(box(qx1 + 0.3, qy + sy * 5.0, z, 0.6, 2.0, BED_TOP - z))
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
    bx0 = il / 2
    rim = rim.cut(box(bx0 + RW / 2, (BEAM["y_root"] + BEAM["y_free"] + 1.2) / 2, -1,
                      RW + 2, BEAM["y_free"] + 1.2 - BEAM["y_root"], RH + 3))
    p = p.union(rim)
    gz = GROOVE["z0"]
    lip_in = -il / 2 + 0.71
    p = p.union(box((-il / 2 - 0.3 + lip_in) / 2, 0, gz + ZC, lip_in + il / 2 + 0.3, 2 * LIP_Y - 0.4, RH - gz - ZC))
    # la pestaña baja hasta la cama por una ranura de la placa (holgura 0,6): se imprime desde la cama, sin voladizo
    t, yr, yf = BEAM["t"], BEAM["y_root"], BEAM["y_free"]
    p = p.cut(box(bx0 + t / 2, (yr + yf + 0.6) / 2, -MT - 1, t + 1.2, yf + 0.6 - yr, MT + 1.0))
    sy0, sy1 = BEAM["y_free"] - TAB["len"] - 0.6, BEAM["y_free"] + 0.6       # REV 5.7.2: nervio a todo el largo del tirador
    p = p.cut(box(bx0 + t + 0.5, (sy0 + sy1) / 2, -MT - 1, 1.0 + 1.2, sy1 - sy0, MT + 1.0))
    beam = box(bx0 + t / 2, (yr - 1.5 + yf) / 2, -MT, t, yf - yr + 1.5, RH + MT)
    p = p.union(beam)
    tip = bx0 - 0.88
    hook = (cq.Workplane("XZ", origin=(0, HOOK_Y[1], 0))
            .polyline([(bx0 + 0.3, gz + ZC), (tip, gz + ZC), (tip, gz + 0.5), (bx0, RH), (bx0 + 0.3, RH)])
            .close().extrude(HOOK_Y[1] - HOOK_Y[0]))
    p = p.union(hook)
    p = p.union(box(bx0 + BEAM["t"] + 0.5, BEAM["y_free"] - TAB["len"] / 2, -MT, 1.0, TAB["len"], RH - 2.0 + 1.6 + MT))
    rx, ry = REED["center"]
    for (dx, depth) in REED_MAGS:
        p = p.cut(cyl(rx + dx, ry, -depth, MAG["d"] + 0.15, 2))
    for (x, y) in MAGS:                                              # imanes de sujeción Ø5 × 1 (enfrentados a los de la cápsula)
        p = p.cut(cyl(x, y, -HMAG["t"] - 0.05, HMAG["d"] + 0.15, 2))
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
    mmags = cyl(*MAGS[0], -HMAG["t"] - 0.02, HMAG["d"], HMAG["t"])
    for (x, y) in MAGS[1:]:
        mmags = mmags.union(cyl(x, y, -HMAG["t"] - 0.02, HMAG["d"], HMAG["t"]))
    return {
        "bobina_Qi": cyl(0, 0, COIL_Z0 + 0.1, COIL["d"], COIL["t"]),
        "bateria_LP403048": box(0, 0, FLOOR + 0.05, BAT["l"], BAT["w"], BAT["t"]),
        "ESP32_C6": c6,
        "placa_Qi": box(qx, qy, TRAY_TOP + 0.02, QI["lx"], QI["wy"], QI["pcb"] - 0.02).union(
            box(qx, qy + 0.5, TRAY_TOP + QI["pcb"], 9.0, 9.0, QI["parts"])),
        "BNO085": bno,
        "reed": box(rx, ry, REED["z0"] + 0.1, REED["l"], REED["d"], REED["d"]),
        "antena_FPC": box(-7, -4.5, CEIL - 0.35, 28, 6, 0.3),
        "imanes": cyl(rx + REED_MAGS[0][0], ry, -REED_MAGS[0][1] + 0.03, MAG["d"], MAG["t"]).union(
            cyl(rx + REED_MAGS[1][0], ry, -REED_MAGS[1][1] + 0.03, MAG["d"], MAG["t"])).union(
            cyl(rx + REED_MAGS[2][0], ry, -REED_MAGS[2][1] + 0.03, MAG["d"], MAG["t"])),
        "imanes_capsula_5x1": mags,
        "imanes_soporte_5x1": mmags,
    }


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
        P + "soporte": mount_with_tab(),          # REV 5.7.2: con el tirador integrado (una sola pieza)
    }
    comps = components()
    report = {"piezas": {}, "interferencias": {}, "medidas": {}}
    for n, s in parts.items():
        # STEP/STL de cada pieza YA ORIENTADOS PARA IMPRIMIR (tapa y tirador boca abajo), apoyados en Z = 0
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
