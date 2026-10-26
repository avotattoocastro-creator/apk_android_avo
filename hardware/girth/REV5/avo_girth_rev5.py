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
  Receptor Qi 5 W: placa 15 × 18; bobina 23 × 30. Batería LP403048 50,8 × 30,5 × 4,3. Reed 14 × 3,2. Imanes Ø5 × 1.
"""
import json
import cadquery as cq

OUT = "out"
G = 0.20

# ------------------------------------------------------------------ cápsula
L, W, R = 70.0, 48.0, 10.0
H = 15.5
HB = 9.0
WALL = 2.0
IL, IW, IR = L - 2 * WALL, W - 2 * WALL, R - WALL   # interior 66 × 44
CEIL = H - 2.3

FLOOR = 2.6
COIL = dict(lx=30.0, wy=23.0, t=1.0)
COIL_Z0 = 1.2
BAT = dict(l=50.8, w=30.5, t=4.3)
TRAY_Z0, TRAY_T = 7.2, 1.0
TRAY_TOP = TRAY_Z0 + TRAY_T

SEAL_IN = 3.6
SEAL_Z0 = HB - 1.6
GASKET = dict(c=2.0, w_groove=1.4, depth=1.0, w=1.2, h_free=1.4)
LIP_OUT, LIP_T = 3.75, 1.2
TRAY_L, TRAY_W, TRAY_R = L - 2 * LIP_OUT, W - 2 * LIP_OUT, R - LIP_OUT     # 62,5 × 40,5

# tornillos de cierre M3 desde abajo (dentro de la junta, sellados con junta tórica 3 × 1 bajo la cabeza)
SCREWS = [(sx * 21.0, sy * 19.0) for sx in (-1, 1) for sy in (-1, 1)] + \
         [(sx * 30.0, sy * 10.0) for sx in (-1, 1) for sy in (-1, 1)]
M3 = dict(hole=3.4, pilot=2.5, cb_d=5.9, cb_h=3.7, boss_lo=6.9, boss_lo_h=4.5, boss=5.6, pilot_top=14.0)
# imanes de sujeción Ø5 × 1 (cápsula y soporte, enfrentados)
MAGS = [(sx * 28.5, sy * 17.5) for sx in (-1, 1) for sy in (-1, 1)]
HMAG = dict(d=5.0, t=1.0, skin=0.3)

# ESP32-C6: 18 a lo largo de X, 21 a lo largo de Y, USB-C hacia +Y (dentro)
C6 = dict(lx=17.8, wy=21.0, pcb=1.0, usb_over=1.3, usb_w=8.94, usb_h=3.26, usb_l=7.35, shield=2.4)
C6_C = (18.0, 0.0)
C6_X0, C6_X1 = C6_C[0] - C6["lx"] / 2, C6_C[0] + C6["lx"] / 2
C6_Y0, C6_Y1 = C6_C[1] - C6["wy"] / 2, C6_C[1] + C6["wy"] / 2      # Y0: extremo de la antena
LED = (C6_C[0] - 1.65, C6_Y0 + 2.0)                # (E)
UFL = (C6_C[0] - 4.95, C6_Y0 + 1.5)                # (E)
ANT = (C6_C[0] + 3.4, C6_Y0 + 1.2)                 # (E) 6,6 × 2,2
USB_FRONT = C6_Y1 + C6["usb_over"]

QI = dict(lx=18.0, wy=15.0, pcb=1.0, parts=1.2, center=(-18.0, 0.0))      # extremo −X; real: 18 en X, 15 en Y; bobina en −X, salidas WOUT/BAT en +X
BNO = dict(lx=15.5, wy=25.2, t=1.6, stand=1.5, hole_in=3.0, center=(0.0, 0.0))   # 25,2 y taladros a 3,0: medido en la foto de la placa real (confirmar con calibre)   # CENTRADO: lo más lejos posible de los imanes; pines hacia +X
BX0, BX1 = BNO["center"][0] - BNO["lx"] / 2, BNO["center"][0] + BNO["lx"] / 2
BY0, BY1 = BNO["center"][1] - BNO["wy"] / 2, BNO["center"][1] + BNO["wy"] / 2
BNO_HOLES = [(BX0 + BNO["hole_in"], BY0 + BNO["hole_in"]), (BX0 + BNO["hole_in"], BY1 - BNO["hole_in"])]
REED = dict(l=14.0, d=3.2, center=(0.0, -19.0), z0=1.0)
MAG = dict(d=5.0, t=1.0, n=1)                     # imán del reed (en el soporte): 1 × Ø5 × 1, mínimo campo en el BNO

RING_T = 1.0
PANEL = dict(margin=3.5, t=0.9, pocket=1.2)
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
    outer = rrect(L, W, R, HB).faces("<Z").edges().fillet(1.0)
    b = outer.cut(rrect(IL, IW, IR, HB, z0=FLOOR))
    b = b.cut(box(0, 0, COIL_Z0, COIL["lx"] + 2 * G, COIL["wy"] + 2 * G, FLOOR))
    b = b.cut(box(-(COIL["lx"] / 2 + 32.6) / 2, -5.0, COIL_Z0 + 0.4, 32.6 - COIL["lx"] / 2, 2.0, FLOOR))   # hilos de la bobina
    bl, bw = BAT["l"] + 2 * G, BAT["w"] + 2 * G
    cr = frame(0, 0, FLOOR, bl, bw, 1.0, TRAY_Z0 - FLOOR - 0.05)
    cr = cr.cut(box(bl / 2 + 0.5, -bw / 2 + 4.0, FLOOR - 1, 2, 7.0, 10))
    cr = cr.cut(box(-(bl / 2 + 0.5), -3.5, FLOOR - 1, 2, 6.0, 10))   # paso de los hilos de la bobina en la pared −X (prueba impresa)
    b = b.union(cr)
    for x in (-15, 0, 15):
        for s in (-1, 1):
            b = b.union(box(x, s * (bw / 2 - 0.15), FLOOR, 1.2, 0.3, BAT["t"]))
    rx, ry = REED["center"]
    b = b.cut(box(rx, ry, REED["z0"], REED["l"] + 2 * G + 2.0, REED["d"] + 2 * G, FLOOR))      # +1 mm por extremo (prueba impresa)
    b = b.union(rshell(0.5, SEAL_IN, HB - SEAL_Z0, SEAL_Z0))
    # 8 columnas M3: más gruesas abajo (avellanado Ø5,9 para cabeza + junta tórica)
    for (x, y) in SCREWS:
        b = b.union(cyl(x, y, 0, M3["boss_lo"], M3["boss_lo_h"])).union(cyl(x, y, 0, M3["boss"], HB))
    for (x, y) in SCREWS:
        b = b.cut(cyl(x, y, -1, M3["hole"], HB + 2)).cut(cyl(x, y, -1, M3["cb_d"], M3["cb_h"] + 1))
    # imanes de sujeción: alojamiento desde dentro, 0,3 mm de piel abajo
    for (x, y) in MAGS:
        b = b.cut(cyl(x, y, HMAG["skin"], HMAG["d"] + 0.15, FLOOR))
    gc, gw = GASKET["c"], GASKET["w_groove"]
    b = b.cut(rshell(gc - gw / 2, gc + gw / 2, GASKET["depth"] + 1, HB - GASKET["depth"]))
    gz, gh, gd = GROOVE["z0"], GROOVE["z1"] - GROOVE["z0"], GROOVE["depth"]
    b = b.cut(box(-L / 2 + gd / 2 - 0.5, 0, gz, gd + 1.0, 2 * LIP_Y + 1.0, gh))
    b = b.cut(box(L / 2 - gd / 2 + 0.5, sum(HOOK_Y) / 2, gz, gd + 1.0, HOOK_Y[1] - HOOK_Y[0] + 2.0, gh))
    return b


# ------------------------------------------------------------------ tapa
def pod_lid():
    outer = rrect(L, W, R, H - HB - RING_T, z0=HB + RING_T).faces(">Z").edges().fillet(2.5)
    outer = outer.union(rshell(1.1, LIP_OUT + LIP_T, RING_T + 0.6, HB))
    lid = outer.cut(rrect(IL, IW, IR, CEIL - HB - RING_T - 0.6, z0=HB + RING_T + 0.6))
    lid = lid.cut(rrect(L - 2 * (LIP_OUT + LIP_T), W - 2 * (LIP_OUT + LIP_T), R - LIP_OUT - LIP_T, 3, z0=HB - 1))
    lid = lid.union(rshell(LIP_OUT, LIP_OUT + LIP_T, HB - TRAY_TOP - 0.05 + 0.2, TRAY_TOP + 0.05))
    qx, qy = QI["center"]
    for (x, y) in SCREWS:
        lid = lid.cut(cyl(x, y, TRAY_TOP - 1, M3["boss"] + 1.0, HB - TRAY_TOP + 1))
    for (x, y) in SCREWS:
        lid = lid.union(cyl(x, y, HB, M3["boss"], CEIL - HB + 0.5))
        lid = lid.cut(cyl(x, y, HB - 0.5, M3["pilot"], M3["pilot_top"] - HB + 0.5))
    for (x, y) in ((-3.0, -16.5), (-3.0, 16.5), (17.0, -15.0), (-17.0, 16.0), (-17.0, -16.0), (14.0, 15.5)):
        lid = lid.union(cyl(x, y, TRAY_TOP + 0.05, 2.4, CEIL - TRAY_TOP))
    for (x, y) in ((C6_X0 + 0.8, C6_Y0 + 0.8), (C6_X1 - 0.8, C6_Y0 + 0.8)):
        lid = lid.union(cyl(x, y, TRAY_TOP + C6["pcb"] + 0.05, 2.0, CEIL - TRAY_TOP - C6["pcb"]))
    for x in (qx - QI["lx"] / 2 + 1.5, qx + QI["lx"] / 2 - 1.5):
        lid = lid.union(cyl(x, qy + QI["wy"] / 2 - 0.8, TRAY_TOP + QI["pcb"] + 0.05, 2.0, CEIL - TRAY_TOP - QI["pcb"]))
    # tope que aprieta el conector USB-C desde arriba (sujeta el extremo del USB; las esquinas tienen los botones)
    usb_top = TRAY_TOP + C6["pcb"] + C6["usb_h"]
    lid = lid.union(box(C6_C[0], USB_FRONT - 4.0, usb_top + 0.05, 6.0, 4.0, CEIL - usb_top - 0.05 + 0.3))
    lid = lid.cut(box(-7, -4.5, CEIL - 0.4, 29, 7, 0.45))               # antena FPC opcional (interior)
    m = PANEL["margin"]
    return lid.cut(rrect(L - 2 * m, W - 2 * m, R - m, 3, z0=H - PANEL["pocket"]))


def gasket(free=True):
    c, w = GASKET["c"], GASKET["w"]
    return rshell(c - w / 2, c + w / 2, GASKET["h_free"] if free else GASKET["depth"], HB - GASKET["depth"])


def panel():
    m = PANEL["margin"] + 0.1
    z0 = H - PANEL["pocket"]
    pn = rrect(L - 2 * m, W - 2 * m, R - m, PANEL["t"], z0=z0)
    top = z0 + PANEL["t"]
    try:
        pn = pn.union(cq.Workplane("XY").workplane(offset=top - 0.05)
                      .text("AVO", 11.0, 0.65, kind="bold", halign="center", valign="center").translate((-8, 3.5, 0)))
        pn = pn.union(cq.Workplane("XY").workplane(offset=top - 0.05)
                      .text("GIRTH", 3.6, 0.45, kind="bold", halign="center", valign="center").translate((-8, -7.0, 0)))
    except Exception as e:
        print("logo omitido:", e)
    return pn


def ring():
    return rshell(0, 1.0, RING_T, HB)


# ------------------------------------------------------------------ bandeja
def tray():
    t = rrect(TRAY_L, TRAY_W, TRAY_R, TRAY_T, z0=TRAY_Z0)
    cx, cy = C6_C
    t = t.cut(box(cx, cy, TRAY_Z0 - 1, C6["lx"] - 2.0, C6["wy"] - 2.0, 3))     # ventana bajo el C6
    t = t.cut(box(26.0, -13.0, TRAY_Z0 - 1, 3, 4, 3))                # cables de la batería
    t = t.cut(box(-29.0, -3.0, TRAY_Z0 - 1, 2.6, 3, 3))              # hilos de la bobina (junto a sus pads, lado −X de la placa Qi)
    rx, ry = REED["center"]
    for x in (rx - REED["l"] / 2 - 2.5, rx + REED["l"] / 2 + 2.5):
        t = t.cut(box(x, ry + 0.2, TRAY_Z0 - 1, 3, 3, 3))
    # C6: marco en los 4 costados (0,15 de holgura, 1,2 de pared), a ras de la cara superior del PCB:
    # no se mueve en X ni en Y y los cables de los pads laterales salen por encima del marco
    t = t.union(frame(cx, cy, TRAY_TOP, C6["lx"] + 0.2, C6["wy"] + 0.2, 1.2, C6["pcb"]))     # 0,1 por lado
    # placa Qi
    qx, qy = QI["center"]
    # marco solo en los lados largos (Y); los lados X quedan abiertos: hilos de la bobina (−X) y salidas WOUT/BAT (+X)
    fq = frame(qx, qy, TRAY_TOP, QI["lx"] + 0.3, QI["wy"] + 0.3, 1.0, 1.0)
    for sx in (-1, 1):
        fq = fq.cut(box(qx + sx * (QI["lx"] / 2 + 0.6), qy, TRAY_TOP - 1, 2.0, QI["wy"] + 4, 3))
    # topes cortos en las esquinas para que no se deslice en X
    for sx in (-1, 1):
        for sy in (-1, 1):
            fq = fq.union(box(qx + sx * (QI["lx"] / 2 + 0.15 + 0.5), qy + sy * (QI["wy"] / 2 - 1.0), TRAY_TOP, 1.0, 2.0, 1.0))
    t = t.union(fq)
    # BNO085 (girado: lado largo en Y), 2 postes M2 en el lado −X, apoyos junto a los pines (+X)
    for (hx, hy) in BNO_HOLES:
        t = t.union(cyl(hx, hy, TRAY_TOP, 4.2, BNO["stand"]))
        t = t.cut(cyl(hx, hy, TRAY_Z0 - 0.1, 1.7, TRAY_T + BNO["stand"] + 0.2))
    for hy in (BY0 + 5.0, BY1 - 5.0):
        t = t.union(cyl(BX1 - 4.2, hy, TRAY_TOP, 3.0, BNO["stand"]))
    for yy in (BY0 - 0.15 - 0.5, BY1 + 0.15 + 0.5):                  # topes en los extremos (0,15 de holgura)
        t = t.union(box(BNO["center"][0], yy, TRAY_TOP, 6.0, 1.0, BNO["stand"] + 1.0))
    t = t.union(box(BX0 - 0.15 - 0.5, BNO["center"][1], TRAY_TOP, 1.0, BNO["wy"] - 2.0, BNO["stand"] + 1.0))   # pared lado −X
    for (x, y) in SCREWS:
        t = t.cut(cyl(x, y, TRAY_Z0 - 1, M3["boss"] + 0.8, 6))
    return t.intersect(rrect(TRAY_L, TRAY_W, TRAY_R, 10, z0=TRAY_Z0 - 1))


# ------------------------------------------------------------------ soporte (una sola pieza)
def _mount_geom():
    il, iw, ir = L + 2 * CL, W + 2 * CL, R + CL
    ol, ow, orr = il + 2 * RW, iw + 2 * RW, ir + RW
    xs0 = ol / 2 + STRAP["ledge"]                      # borde interior de los pasos de cinta
    xs1 = xs0 + STRAP["slot"]
    pl = 2 * (xs1 + STRAP["bar"])
    pw = STRAP["w"] + 2.0 + 2 * 3.2
    return il, iw, ir, ol, ow, orr, xs0, xs1, pl, pw


def mount():
    il, iw, ir, ol, ow, orr, xs0, xs1, pl, pw = _mount_geom()
    p = rrect(pl, pw, 7.0, MT, z0=-MT)
    p = p.faces(">Z").edges().fillet(1.8).faces("<Z").edges().chamfer(0.5)
    # pasos de cinta cerrados (52 × 3,6, extremos redondeados) y canal inferior de 0,4 para la cinta
    for sx in (-1, 1):
        p = p.cut(rrect(STRAP["slot"], STRAP["w"] + 2.0, 1.6, MT + 2, z0=-MT - 1).translate((sx * (xs0 + xs1) / 2, 0, 0)))
    p = p.cut(box(0, 0, -MT - 1, 2 * xs1 + 0.01, STRAP["w"] + 1.0, 1 + STRAP["chan"]))
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
    beam = box(bx0 + BEAM["t"] / 2, (BEAM["y_root"] - 1.5 + BEAM["y_free"]) / 2, BEAM["z0"],
               BEAM["t"], BEAM["y_free"] - BEAM["y_root"] + 1.5, RH - BEAM["z0"])
    p = p.union(beam)
    tip = bx0 - 0.88
    hook = (cq.Workplane("XZ", origin=(0, HOOK_Y[1], 0))
            .polyline([(bx0 + 0.3, gz + ZC), (tip, gz + ZC), (tip, gz + 0.5), (bx0, RH), (bx0 + 0.3, RH)])
            .close().extrude(HOOK_Y[1] - HOOK_Y[0]))
    p = p.union(hook)
    p = p.union(box(bx0 + BEAM["t"] + 0.5, BEAM["y_free"] - TAB["len"] / 2, 1.6, 1.0, TAB["len"] - 4.0, RH - 2.0))
    rx, ry = REED["center"]
    p = p.cut(cyl(rx, ry, -MAG["t"] * MAG["n"] - 0.05, MAG["d"] + 0.15, 2))
    for (x, y) in MAGS:                                              # imanes de sujeción Ø5 × 1 (enfrentados a los de la cápsula)
        p = p.cut(cyl(x, y, -HMAG["t"] - 0.05, HMAG["d"] + 0.15, 2))
    return p


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
    bz = TRAY_TOP + BNO["stand"] + 0.02
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
        "bobina_Qi": box(0, 0, COIL_Z0 + 0.1, COIL["lx"], COIL["wy"], COIL["t"]),
        "bateria_LP403048": box(0, 0, FLOOR + 0.05, BAT["l"], BAT["w"], BAT["t"]),
        "ESP32_C6": c6,
        "placa_Qi": box(qx, qy, TRAY_TOP + 0.02, QI["lx"], QI["wy"], QI["pcb"] - 0.02).union(
            box(qx, qy + 0.5, TRAY_TOP + QI["pcb"], 9.0, 9.0, QI["parts"])),
        "BNO085": bno,
        "reed": box(rx, ry, REED["z0"] + 0.1, REED["l"], REED["d"], REED["d"]),
        "antena_FPC": box(-7, -4.5, CEIL - 0.35, 28, 6, 0.3),
        "imanes": cyl(rx, ry, -MAG["t"] * MAG["n"] - 0.02, MAG["d"], MAG["t"] * MAG["n"]),
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
        P + "panel_rojo": panel(),
        P + "bandeja": tray(),
        P + "junta_TPU": gasket(free=False),
        P + "soporte": mount(),
        P + "tirador_rojo": tab(),
    }
    comps = components()
    report = {"piezas": {}, "interferencias": {}, "medidas": {}}
    for n, s in parts.items():
        cq.exporters.export(s, f"{OUT}/{n}.step")
        cq.exporters.export(s, f"{OUT}/{n}.stl", tolerance=0.02, angularTolerance=0.1)
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
                         "bno_taladros": BNO_HOLES, "c6_centro": C6_C, "led": LED}
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
