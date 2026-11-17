"""AVO GIRTH REV 3 — interior ajustado a los componentes reales y soporte de una sola pieza, compacto y fuerte.

Base visual: concepto REV 0 (hardware/girth/REV0/out_hero.png).
Piezas (CadQuery → STEP B-Rep + STL, PETG en Elegoo Centauri Carbon, cada pieza de un solo color):
  negro: base, tapa, bandeja, soporte · rojo: aro de cierre, panel con AVO / GIRTH, tirador · TPU: tapón USB
Ejes: X a lo largo de la cinta (50 mm), Z arriba, fondo de la cápsula en Z = 0 sobre el soporte.

Componentes (medidas de los anuncios del usuario; (E) = estimado sobre la foto, confirmar con calibre):
  ESP32-C6 diymore (formato XIAO) 21 × 18, PCB 1,0; USB-C en un extremo con botones R/B a los lados; en el otro
    extremo conector U.FL, LED (E) y antena cerámica (E). Pads de soldadura en los lados de 21 mm.
  BNO085 GY (HanOaki) 25,8 × 15,5 × 1,6: 10 pines en un lado largo; 2 taladros en el lado largo OPUESTO,
    uno en cada extremo, a ~2,6 mm de los bordes (E).
  Receptor Qi 5 W: placa 15 × 18; bobina 23 × 30 con ferrita (1,0 mm, E).
  Batería EEMB LP403048: 50,8 × 30,5 × 4,3 máx., cables de 50 mm saliendo por el extremo del PCM, junto a un lado.
  Reed de plástico 14 × 3,2 con patas de 14; imanes Ø6 × 2.
"""
import json
import cadquery as cq

OUT = "out"
G = 0.20  # holgura nominal por lado de los componentes (ajustar con la placa de probetas)

# ------------------------------------------------------------------ cápsula
L, W, R = 64.0, 46.0, 10.0
H = 15.5
HB = 9.0
WALL = 2.0
IL, IW, IR = L - 2 * WALL, W - 2 * WALL, R - WALL   # interior 60 × 42
CEIL = H - 2.3                                      # techo interior de la tapa

FLOOR = 2.6
COIL = dict(lx=30.0, wy=23.0, t=1.0)
COIL_Z0 = 1.2                                       # 1,2 mm de fondo bajo la bobina (base Qi)
BAT = dict(l=50.8, w=30.5, t=4.3)
TRAY_Z0, TRAY_T = 7.2, 1.0
TRAY_TOP = TRAY_Z0 + TRAY_T
TRAY_L, TRAY_W, TRAY_R = IL - 3.1, IW - 3.1, IR - 1.55   # 56,9 × 38,9

# ESP32-C6: USB-C hacia +X. El borde del PCB hace tope en x = C6_EDGE (pared interior en 30).
C6_EDGE = 29.6
C6 = dict(l=21.0, w=18.0, pcb=1.0, usb_over=1.3, usb_w=8.94, usb_h=3.26, usb_l=7.35, shield=2.4)
C6_C = (C6_EDGE - C6["l"] / 2, 6.1)
C6_X0 = C6_EDGE - C6["l"]                          # extremo de la antena (8,6)
LED = (C6_X0 + 2.0, C6_C[1] + 1.65)                # (E) LED de usuario junto al U.FL
UFL = (C6_X0 + 1.8, C6_C[1] + 4.8)                 # (E) U.FL 2,6 × 2,6
ANT = (C6_X0 + 1.2, C6_C[1] - 3.4)                 # (E) antena cerámica 2,2 × 6,6
USB = dict(y=C6_C[1], z=TRAY_TOP + C6["pcb"] + C6["usb_h"] / 2, w=9.6, h=3.9)
USB_FRONT = C6_EDGE + C6["usb_over"]

QI = dict(l=18.0, w=15.0, pcb=1.0, parts=1.2, center=(-16.0, -11.0))     # almohadillas de la bobina en −X
BNO = dict(l=25.8, w=15.5, t=1.6, stand=1.5, hole_in=2.6, center=(-11.6, 10.75))
BX0, BX1 = BNO["center"][0] - BNO["l"] / 2, BNO["center"][0] + BNO["l"] / 2
BY0, BY1 = BNO["center"][1] - BNO["w"] / 2, BNO["center"][1] + BNO["w"] / 2       # pines en BY0 (hacia el centro)
BNO_HOLES = [(BX0 + BNO["hole_in"], BY1 - BNO["hole_in"]), (BX1 - BNO["hole_in"], BY1 - BNO["hole_in"])]
REED = dict(l=14.0, d=3.2, center=(6.0, -18.75), z0=1.0)
MAG = dict(d=6.0, t=2.0, n=2)
SCREW_X, SCREW_Y = 28.3, -6.0

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
MT = 4.6                                            # placa (con canal de 0,4 para la cinta por debajo)
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


def usb_cut(x0, x1, extra=0.0):
    """ventana USB-C (redondeada) de x0 a x1"""
    w, h = USB["w"] + 2 * extra, USB["h"] + 2 * extra
    return (cq.Workplane("YZ").workplane(offset=x0).center(USB["y"], USB["z"]).rect(w, h).extrude(x1 - x0)
            .edges("|X").fillet(min(h / 2 - 0.05, 1.4)))


def usb_window():
    # paso del conector + rebaje exterior de 0,6 mm para la funda del cable / el tapón
    return usb_cut(C6_EDGE - 0.5, L / 2 + 1).union(usb_cut(L / 2 - 0.6, L / 2 + 1, extra=1.4))


# ------------------------------------------------------------------ base
def pod_base():
    outer = rrect(L, W, R, HB).faces("<Z").edges().fillet(1.0)
    b = outer.cut(rrect(IL, IW, IR, HB, z0=FLOOR))
    b = b.cut(box(0, 0, COIL_Z0, COIL["lx"] + 2 * G, COIL["wy"] + 2 * G, FLOOR))
    # canal de los hilos de la bobina hacia −X (por debajo de la cuna) y subida junto a la pared
    b = b.cut(box(-21.95, -10.0, COIL_Z0 + 0.4, 14.9, 2.0, FLOOR))
    # cuna de la batería: marco completo de 1,0 con un hueco en +X/−Y para los cables del PCM
    bl, bw = BAT["l"] + 2 * G, BAT["w"] + 2 * G
    cr = frame(0, 0, FLOOR, bl, bw, 1.0, TRAY_Z0 - FLOOR - 0.05)
    cr = cr.cut(box(bl / 2 + 0.5, -bw / 2 + 4.0, FLOOR - 1, 2, 7.0, 10))
    b = b.union(cr)
    for x in (-15, 0, 15):
        for s in (-1, 1):
            b = b.union(box(x, s * (bw / 2 - 0.15), FLOOR, 1.2, 0.3, BAT["t"]))
    rx, ry = REED["center"]
    b = b.cut(box(rx, ry, REED["z0"], REED["l"] + 2 * G, REED["d"] + 2 * G, FLOOR))
    for sx in (-1, 1):
        b = b.union(cyl(sx * SCREW_X, SCREW_Y, 0, 4.4, HB))
        b = b.cut(cyl(sx * SCREW_X, SCREW_Y, -1, 2.3, HB + 2))
        b = b.cut(cyl(sx * SCREW_X, SCREW_Y, -1, 4.0, 2.2 + 1))
    gz, gh, gd = GROOVE["z0"], GROOVE["z1"] - GROOVE["z0"], GROOVE["depth"]
    b = b.cut(box(-L / 2 + gd / 2 - 0.5, 0, gz, gd + 1.0, 2 * LIP_Y + 1.0, gh))
    b = b.cut(box(L / 2 - gd / 2 + 0.5, sum(HOOK_Y) / 2, gz, gd + 1.0, HOOK_Y[1] - HOOK_Y[0] + 2.0, gh))
    return b.cut(usb_window())


# ------------------------------------------------------------------ tapa
def pod_lid():
    outer = rrect(L, W, R, H - HB - RING_T, z0=HB + RING_T).faces(">Z").edges().fillet(2.5)
    outer = outer.union(rrect(L - 2.4, W - 2.4, R - 1.2, RING_T + 0.5, z0=HB))
    lid = outer.cut(rrect(IL, IW, IR, CEIL - HB, z0=HB - 0.01))
    lip = rrect(IL - 0.3, IW - 0.3, IR - 0.15, HB - TRAY_TOP, z0=TRAY_TOP + 0.05).cut(
        rrect(IL - 2.7, IW - 2.7, IR - 1.35, HB, z0=TRAY_TOP - 1))
    lip = lip.union(rrect(IL + 1.0, IW + 1.0, IR + 0.5, 1.0, z0=HB).cut(rrect(IL - 2.7, IW - 2.7, IR - 1.35, 3, z0=HB - 1)))
    for sx in (-1, 1):
        lip = lip.cut(cyl(sx * SCREW_X, SCREW_Y, 0, 5.0, HB + 1))
    cx, cy = C6_C
    lip = lip.cut(box(cx, cy, TRAY_TOP - 1, C6["l"] + 1.2, C6["w"] + 1.0, 3))
    lid = lid.union(lip)
    for sx in (-1, 1):
        lid = lid.union(cyl(sx * SCREW_X, SCREW_Y, HB, 4.4, CEIL - HB + 0.5))
        lid = lid.cut(cyl(sx * SCREW_X, SCREW_Y, HB - 0.5, 1.7, 4.5))
    # postes que aprietan la bandeja (zonas libres)
    for (x, y) in ((-27.0, -0.5), (3.0, -12.0), (18.0, -12.0), (5.0, 16.5)):
        lid = lid.union(cyl(x, y, TRAY_TOP + 0.05, 2.4, CEIL - TRAY_TOP))
    # postes que sujetan el C6 por el extremo de la antena (lejos del U.FL y la antena) y la placa Qi
    for (x, y) in ((C6_X0 + 0.8, C6_C[1] - C6["w"] / 2 + 0.8), (C6_X0 + 0.8, C6_C[1] + C6["w"] / 2 - 0.8)):
        lid = lid.union(cyl(x, y, TRAY_TOP + C6["pcb"] + 0.05, 2.0, CEIL - TRAY_TOP - C6["pcb"]))
    qx, qy = QI["center"]
    for x in (qx - QI["l"] / 2 + 0.9, qx + QI["l"] / 2 - 0.9):
        lid = lid.union(cyl(x, qy + QI["w"] / 2 - 0.9, TRAY_TOP + QI["pcb"] + 0.05, 2.0, CEIL - TRAY_TOP - QI["pcb"]))
    lid = lid.cut(usb_window())
    lid = lid.cut(cyl(LED[0], LED[1], CEIL - 1, 2.6, 5))             # ventana del LED (Ø2,6: posición estimada)
    lid = lid.cut(box(-7, 0.5, CEIL - 0.4, 29, 7, 0.45))               # antena FPC opcional
    m = PANEL["margin"]
    return lid.cut(rrect(L - 2 * m, W - 2 * m, R - m, 3, z0=H - PANEL["pocket"]))


def panel():
    m = PANEL["margin"] + 0.1
    z0 = H - PANEL["pocket"]
    pn = rrect(L - 2 * m, W - 2 * m, R - m, PANEL["t"], z0=z0)
    top = z0 + PANEL["t"]
    try:
        pn = pn.union(cq.Workplane("XY").workplane(offset=top - 0.05)
                      .text("AVO", 10.0, 0.65, kind="bold", halign="center", valign="center").translate((-8, 3.5, 0)))
        pn = pn.union(cq.Workplane("XY").workplane(offset=top - 0.05)
                      .text("GIRTH", 3.4, 0.45, kind="bold", halign="center", valign="center").translate((-8, -6.5, 0)))
    except Exception as e:
        print("logo omitido:", e)
    return pn.cut(cyl(LED[0], LED[1], z0 - 1, 2.6, 4))


def ring():
    r = rrect(L, W, R, RING_T, z0=HB).cut(rrect(L - 2.4 + 0.2, W - 2.4 + 0.2, R - 1.1, 3, z0=HB - 1))
    return r.cut(usb_window())


# ------------------------------------------------------------------ bandeja
def tray():
    t = rrect(TRAY_L, TRAY_W, TRAY_R, TRAY_T, z0=TRAY_Z0)
    for sx in (-1, 1):
        t = t.cut(cyl(sx * SCREW_X, SCREW_Y, TRAY_Z0 - 1, 5.6, 3))
    # ventana bajo el C6: deja sitio a los cables soldados por debajo; el PCB apoya en 3 rebordes de 1 mm
    cx, cy = C6_C
    t = t.cut(box((C6_X0 + 1.0 + TRAY_L / 2 + 1) / 2, cy, TRAY_Z0 - 1, TRAY_L / 2 + 1 - C6_X0 - 1.0, C6["w"] - 2.0, 3))
    # pasos de cables
    t = t.cut(box(26.0, -14.0, TRAY_Z0 - 1, 4, 6, 3))                # batería (extremo +X)
    t = t.cut(box(-27.2, -10.5, TRAY_Z0 - 1, 2.6, 4, 3))             # hilos de la bobina Qi
    rx, ry = REED["center"]
    for x in (rx - REED["l"] / 2 - 1.5, rx + REED["l"] / 2 + 1.5):   # patas del reed (dobladas hacia arriba)
        t = t.cut(box(x, ry + 0.25, TRAY_Z0 - 1, 3, 3, 3))
    # C6: escuadras en las esquinas del extremo de la antena (los lados con pads quedan libres)
    for s in (-1, 1):
        yc = cy + s * (C6["w"] / 2 + G)
        t = t.union(box(C6_X0 - G - 0.5, yc - s * 1.5, TRAY_TOP, 1.0, 4.0, 1.2))
        t = t.union(box(C6_X0 - G + 1.0, yc + s * 0.5, TRAY_TOP, 4.0, 1.0, 1.2))
    # placa Qi: marco de 1,0 con huecos en −X (bobina) y +X (salida)
    qx, qy = QI["center"]
    fq = frame(qx, qy, TRAY_TOP, QI["l"] + 2 * G, QI["w"] + 2 * G, 1.0, 1.0)
    fq = fq.cut(box(qx - QI["l"] / 2, qy, TRAY_TOP - 1, 4, QI["w"] - 5, 3)).cut(box(qx + QI["l"] / 2, qy, TRAY_TOP - 1, 4, QI["w"] - 5, 3))
    t = t.union(fq)
    # BNO085: 2 postes M2 en los taladros (lado opuesto a los pines) + 2 apoyos junto a los pines
    for (hx, hy) in BNO_HOLES:
        t = t.union(cyl(hx, hy, TRAY_TOP, 4.2, BNO["stand"]))
        t = t.cut(cyl(hx, hy, TRAY_Z0 - 0.1, 1.7, TRAY_T + BNO["stand"] + 0.2))
    for hx in (BX0 + 4.0, BX1 - 4.0):
        t = t.union(cyl(hx, BY0 + 4.2, TRAY_TOP, 3.0, BNO["stand"]))
    # topes laterales del BNO (en los extremos cortos)
    for s in (-1, 1):
        xe = (BX0 - G - 0.5) if s < 0 else (BX1 + G + 0.5)
        t = t.union(box(xe, BNO["center"][1], TRAY_TOP, 1.0, 6.0, BNO["stand"] + 1.0))
    for sx in (-1, 1):                                               # holgura alrededor de las columnas de los tornillos
        t = t.cut(cyl(sx * SCREW_X, SCREW_Y, TRAY_Z0 - 1, 5.6, 6))
    return t.intersect(rrect(TRAY_L, TRAY_W, TRAY_R, 10, z0=TRAY_Z0 - 1))


def usb_plug():   # TPU 95A: tapa el rebaje exterior y entra en la ventana hasta 0,1 mm del conector
    f = usb_cut(L / 2 - 0.55, L / 2 + 0.0, extra=1.25)
    s = usb_cut(USB_FRONT + 0.1, L / 2 - 0.5, extra=-0.15)
    tab = box(L / 2 + 0.5, USB["y"] - 7.0, USB["z"] - 1.0, 1.0, 5.0, 2.0)          # lengüeta para quitarlo
    return f.union(s).union(usb_cut(L / 2 - 0.01, L / 2 + 1.0, extra=0.6)).union(tab)


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
    p = p.cut(cyl(rx, ry, -MT + STRAP["chan"] + 0.2, MAG["d"] + 0.15, MT))
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
    usb = (cq.Workplane("YZ").workplane(offset=USB_FRONT - C6["usb_l"]).center(cy, pz + C6["usb_h"] / 2)
           .rect(C6["usb_w"], C6["usb_h"]).extrude(C6["usb_l"]).edges("|X").fillet(1.3))      # USB-C: carcasa ovalada
    c6 = (box(cx, cy, TRAY_TOP + 0.02, C6["l"], C6["w"], C6["pcb"] - 0.02).union(usb)
          .union(box(C6_X0 + 3.4 + 5.2, cy + 0.1, pz, 10.4, 13.2, C6["shield"]))
          .union(box(UFL[0], UFL[1], pz, 2.6, 2.6, 1.25)).union(box(ANT[0], ANT[1], pz, 2.2, 6.6, 1.2))
          .union(box(LED[0], LED[1], pz, 1.0, 0.6, 0.4)))
    bz = TRAY_TOP + BNO["stand"] + 0.02
    bno = box(bx, by, bz, BNO["l"], BNO["w"], BNO["t"])
    for (hx, hy) in BNO_HOLES:
        bno = bno.cut(cyl(hx, hy, bz - 1, 3.0, 4))
    bno = bno.union(box(bx + 2.0, by + 0.5, bz + BNO["t"], 5.2, 5.2, 1.0))
    return {
        "bobina_Qi": box(0, 0, COIL_Z0 + 0.1, COIL["lx"], COIL["wy"], COIL["t"]),
        "bateria_LP403048": box(0, 0, FLOOR + 0.05, BAT["l"], BAT["w"], BAT["t"]),
        "ESP32_C6": c6,
        "placa_Qi": box(qx, qy, TRAY_TOP + 0.02, QI["l"], QI["w"], QI["pcb"] - 0.02).union(
            box(qx + 1.5, qy - 1.0, TRAY_TOP + QI["pcb"], 9.0, 9.0, QI["parts"])),
        "BNO085": bno,
        "reed": box(rx, ry, REED["z0"] + 0.1, REED["l"], REED["d"], REED["d"]),
        "antena_FPC": box(-7, 0.5, CEIL - 0.35, 28, 6, 0.3),
        "imanes": cyl(rx, ry, -MT + STRAP["chan"] + 0.25, MAG["d"], MAG["t"] * MAG["n"] - 0.1),
    }


def main():
    import os
    os.makedirs(OUT, exist_ok=True)
    P = "AVO_GIRTH_R3_"
    parts = {
        P + "base": pod_base(),
        P + "aro_rojo": ring(),
        P + "tapa": pod_lid(),
        P + "panel_rojo": panel(),
        P + "bandeja": tray(),
        P + "tapon_USB_TPU": usb_plug(),
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
                         "usb_frente_a_cara_exterior_mm": round(L / 2 - USB_FRONT, 2),
                         "bno_taladros": BNO_HOLES, "c6_centro": C6_C, "led": LED}
    asm = cq.Assembly(name="AVO_GIRTH_R3")
    colors = {"aro": (0.93, 0.07, 0.16), "panel": (0.85, 0.06, 0.14), "tirador": (0.93, 0.07, 0.16),
              "base": (0.09, 0.09, 0.11), "tapa": (0.09, 0.09, 0.11), "bandeja": (0.18, 0.19, 0.22),
              "tapon": (0.17, 0.18, 0.2), "soporte": (0.12, 0.13, 0.15)}
    for n, s in parts.items():
        key = next((k for k in colors if k in n), "base")
        asm.add(s, name=n, color=cq.Color(*colors[key], 1.0))
    for n, s in comps.items():
        asm.add(s, name="ref_" + n, color=cq.Color(0.8, 0.5, 0.2, 1.0))
    asm.save(f"{OUT}/AVO_GIRTH_R3_CONJUNTO.step")
    json.dump(report, open(f"{OUT}/informe.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
