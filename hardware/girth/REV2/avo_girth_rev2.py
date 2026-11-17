"""AVO GIRTH REV 2 — fiel al concepto REV 0 (out_hero.png / out_mount.png) y con encaje sin juego.

Piezas (CadQuery → STEP B-Rep + STL, PETG en Elegoo Centauri Carbon, sin cambio de filamento en ninguna pieza):
  negro: base, tapa, bandeja, soporte, tapón USB (TPU)
  rojo : aro de cierre (línea roja entre base y tapa), panel superior con AVO / GIRTH en relieve, tirador de la pestaña
Ejes: X a lo largo de la cinta (50 mm), Z arriba, fondo de la cápsula en Z = 0 sobre el soporte.

Anclaje (como en el concepto: la cápsula entra en el cerco del soporte, pestaña roja en el extremo +X):
  * cerco alrededor con 0,12 mm de holgura por lado: no se mueve en X ni en Y;
  * extremo −X: labio del cerco metido en una ranura de la cápsula (no se puede levantar por ese lado);
  * extremo +X: el tramo del cerco es una pestaña elástica con diente; la cara inferior del diente es horizontal,
    así que tirar hacia arriba (galope) no abre la pestaña: solo se abre tirando del tirador rojo hacia fuera.
  Poner: inclinar la cápsula, meter el extremo −X bajo el labio y bajar el extremo +X hasta el clic.
  Quitar: tirar del tirador rojo hacia fuera (+X) y levantar el extremo +X.
Sin costillas aplastables: el ajuste lo da la holgura nominal (calibrar con la placa de probetas).
Medidas de componentes: anuncios (pendiente de calibre).
"""
import json
import cadquery as cq

OUT = "out"
G = 0.20  # holgura nominal por lado (ajustar con la placa de probetas)

# ------------------------------------------------------------------ dimensiones
L, W, R = 64.0, 46.0, 10.0        # planta de la cápsula
H = 15.5                           # altura total
HB = 9.0                           # cierre base / tapa
WALL = 2.0
IL, IW, IR = L - 2 * WALL, W - 2 * WALL, R - WALL   # interior 60 × 42

FLOOR = 2.6                        # fondo general (las ranuras de cola de milano van en él)
COIL = dict(lx=30.0, wy=23.0, t=1.0)                # bobina Qi (30 a lo largo de X)
COIL_Z0 = 1.2                                       # fondo bajo la bobina: 1,2 mm (distancia a la base Qi)
BAT = dict(l=50.8, w=30.5, t=4.3)
BAT_C = (0.0, 0.0)
TRAY_Z0, TRAY_T = 7.2, 1.0
TRAY_TOP = TRAY_Z0 + TRAY_T
C6 = dict(l=21.0, w=18.0, pcb=1.0, center=(16.9, 8.6))
QI = dict(l=15.0, w=18.0, center=(-4.0, 8.6))
BNO = dict(l=25.8, w=15.5, t=1.6, center=(-2.0, -10.5), stand=1.5, hole_in=2.5)   # taladros a 2,5 de los bordes (P)
REED = dict(l=14.0, d=3.2, center=(0.0, -18.75), z0=1.0)
MAG = dict(d=6.0, t=2.0, n=2)
SCREW_X, SCREW_Y = 28.3, -6.0       # 2 × M2 × 10, de abajo arriba, en los extremos X
USB = dict(y=8.6, z=TRAY_TOP + C6["pcb"] + 1.6, w=9.6, h=3.9)
LED = (25.5, 14.5)                 # guía de luz sobre el LED del C6 (P)

RING_T = 1.0                       # aro rojo entre base y tapa (piel exterior de 1,1 mm)
PANEL = dict(margin=3.5, t=0.9, pocket=1.2)          # panel rojo superior (marco negro de 3,5 mm alrededor)
# ranuras de anclaje en las caras X de la cápsula
GROOVE = dict(z0=3.0, z1=4.6, depth=1.0)
LIP_Y = 10.0                       # labio −X: y −10…10
HOOK_Y = (0.0, 10.0)               # diente +X: y 0…10 (cerca del extremo libre de la pestaña)
ZC = 0.10                          # holgura vertical labio / diente ↔ ranura

# soporte
CL = 0.12                          # holgura cápsula ↔ cerco (por lado)
RW = 2.6                           # pared del cerco
RH = GROOVE["z1"] - 0.15           # altura del cerco (el labio queda a ras de su borde)
MT = 4.2                           # placa del soporte
STRAP = dict(w=50.0, slot=3.6, bar=4.0, post=3.4)    # cinta de 50 mm
BEAM = dict(t=1.6, y_root=-13.5, y_free=12.3, z0=0.6)
TAB = dict(len=10.0, out=1.8, up=1.6)              # tirador rojo sobre el extremo libre


def rrect(l, w, r, h, z0=0.0):
    return cq.Workplane("XY").workplane(offset=z0).rect(l, w).extrude(h).edges("|Z").fillet(r)


def box(cx, cy, z0, l, w, h):
    return cq.Workplane("XY").box(l, w, h, centered=(True, True, False)).translate((cx, cy, z0))


def cyl(cx, cy, z0, d, h):
    return cq.Workplane("XY").circle(d / 2).extrude(h).translate((cx, cy, z0))


def frame(cx, cy, z0, il, iw, wall, h, open_sides=""):
    f = box(cx, cy, z0, il + 2 * wall, iw + 2 * wall, h).cut(box(cx, cy, z0 - 1, il, iw, h + 2))
    for s in open_sides:
        if s == "E": f = f.cut(box(cx + il / 2 + wall / 2, cy, z0 - 1, wall + 1, iw - 2, h + 2))
        if s == "W": f = f.cut(box(cx - il / 2 - wall / 2, cy, z0 - 1, wall + 1, iw - 2, h + 2))
        if s == "N": f = f.cut(box(cx, cy + iw / 2 + wall / 2, z0 - 1, il - 2, wall + 1, h + 2))
        if s == "S": f = f.cut(box(cx, cy - iw / 2 - wall / 2, z0 - 1, il - 2, wall + 1, h + 2))
    return f


# ------------------------------------------------------------------ cápsula: base
def pod_base():
    outer = rrect(L, W, R, HB).faces("<Z").edges().fillet(1.0)
    b = outer.cut(rrect(IL, IW, IR, HB, z0=FLOOR))
    # bobina Qi: rebaje en el fondo (queda 1,2 mm bajo ella)
    b = b.cut(box(0, 0, COIL_Z0, COIL["lx"] + 2 * G, COIL["wy"] + 2 * G, FLOOR))
    # cuna de la batería (paredes de 1,0 sobre el fondo) con salida de cables en +X
    bl, bw = BAT["l"] + 2 * G, BAT["w"] + 2 * G
    b = b.union(frame(BAT_C[0], BAT_C[1], FLOOR, bl, bw, 1.0, BAT["t"] + 0.3, open_sides="E"))
    # costillas de 0,3 en los lados largos (sujetan sin apretar)
    for x in (-15, 0, 15):
        for s in (-1, 1):
            b = b.union(box(x, s * (bw / 2 - 0.15), FLOOR, 1.2, 0.3, BAT["t"]))
    # canal del reed junto al fondo (lado −Y), cerca del imán del soporte
    rx, ry = REED["center"]
    b = b.cut(box(rx, ry, REED["z0"], REED["l"] + 2 * G, REED["d"] + 2 * G, FLOOR))
    # columnas de los tornillos (extremos X) con avellanado para cabeza M2 por debajo
    for sx in (-1, 1):
        b = b.union(cyl(sx * SCREW_X, SCREW_Y, 0, 4.4, HB))
        b = b.cut(cyl(sx * SCREW_X, SCREW_Y, -1, 2.3, HB + 2))
        b = b.cut(cyl(sx * SCREW_X, SCREW_Y, -1, 4.0, 2.2 + 1))
    # ranuras de anclaje: −X (labio del cerco) y +X (diente de la pestaña). Fondo liso para la base Qi.
    gz, gh, gd = GROOVE["z0"], GROOVE["z1"] - GROOVE["z0"], GROOVE["depth"]
    b = b.cut(box(-L / 2 + gd / 2 - 0.5, 0, gz, gd + 1.0, 2 * LIP_Y + 1.0, gh))
    b = b.cut(box(L / 2 - gd / 2 + 0.5, sum(HOOK_Y) / 2, gz, gd + 1.0, HOOK_Y[1] - HOOK_Y[0] + 2.0, gh))
    # salida USB-C (parte inferior de la ventana, si cae en la base)
    b = b.cut(box(L / 2, USB["y"], USB["z"] - USB["h"] / 2, 6, USB["w"], USB["h"]))
    return b


# ------------------------------------------------------------------ cápsula: tapa
def pod_lid():
    outer = rrect(L, W, R, H - HB - RING_T, z0=HB + RING_T).faces(">Z").edges().fillet(2.5)
    outer = outer.union(rrect(L - 2.4, W - 2.4, R - 1.2, RING_T + 0.5, z0=HB))     # escalón interior: el aro va por fuera
    lid = outer.cut(rrect(IL, IW, IR, (H - 2.3) - HB, z0=HB - 0.01))
    # labio interior que baja hasta la bandeja y la sujeta
    lip = rrect(IL - 0.3, IW - 0.3, IR - 0.15, HB - TRAY_TOP, z0=TRAY_TOP + 0.05).cut(
        rrect(IL - 2.7, IW - 2.7, IR - 1.35, HB, z0=TRAY_TOP - 1))
    # puente que une el labio con la pared de la tapa (REV1.1: el labio quedaba suelto)
    lip = lip.union(rrect(IL + 1.0, IW + 1.0, IR + 0.5, 1.0, z0=HB).cut(rrect(IL - 2.7, IW - 2.7, IR - 1.35, 3, z0=HB - 1)))
    for sx in (-1, 1):
        lip = lip.cut(cyl(sx * SCREW_X, SCREW_Y, 0, 5.0, HB + 1))
    cx, cy = C6["center"]
    lip = lip.cut(box(cx, cy, TRAY_TOP - 1, C6["l"] + 1.0, C6["w"] + 1.0, 3))   # el C6 llega a la esquina
    lid = lid.union(lip)
    # columnas para los M2 (agujero piloto Ø1,7, 4 mm)
    for sx in (-1, 1):
        lid = lid.union(cyl(sx * SCREW_X, SCREW_Y, HB, 4.4, H - 2.3 - HB + 0.5))
        lid = lid.cut(cyl(sx * SCREW_X, SCREW_Y, HB - 0.5, 1.7, 4.5))
    # postes que aprietan la bandeja (sin juego vertical)
    for (x, y) in ((-24, 15), (-24, -15), (15, -5.5), (-22, -1.0)):
        lid = lid.union(cyl(x, y, TRAY_TOP + 0.05, 2.4, H - 2.3 - TRAY_TOP))
    # ventana USB-C, guía de luz, alojamiento de la antena FPC y logo
    lid = lid.cut(box(L / 2, USB["y"], USB["z"] - USB["h"] / 2, 6, USB["w"], USB["h"]))
    lid = lid.cut(cyl(LED[0], LED[1], H - 3, 2.0, 4))
    lid = lid.cut(box(6, 0, H - 2.3 - 0.4, 31, 7, 0.45))
    # alojamiento del panel rojo
    m = PANEL["margin"]
    lid = lid.cut(rrect(L - 2 * m, W - 2 * m, R - m, 3, z0=H - PANEL["pocket"]))
    return lid


# ------------------------------------------------------------------ panel rojo superior
def panel():
    m = PANEL["margin"] + 0.1
    z0 = H - PANEL["pocket"]
    pn = rrect(L - 2 * m, W - 2 * m, R - m, PANEL["t"], z0=z0)
    top = z0 + PANEL["t"]
    try:
        pn = pn.union(cq.Workplane("XY").workplane(offset=top - 0.05)
                      .text("AVO", 10.0, 0.65, kind="bold", halign="center", valign="center").translate((-4, 3.5, 0)))
        pn = pn.union(cq.Workplane("XY").workplane(offset=top - 0.05)
                      .text("GIRTH", 3.4, 0.45, kind="bold", halign="center", valign="center").translate((-4, -6.5, 0)))
    except Exception as e:   # sin fuente en el sistema: panel sin logo
        print("logo omitido:", e)
    return pn.cut(cyl(LED[0], LED[1], z0 - 1, 2.0, 4))          # ventana del LED (punto verde del concepto)


# ------------------------------------------------------------------ aro rojo
def ring():
    r = rrect(L, W, R, RING_T, z0=HB).cut(rrect(L - 2.4 + 0.2, W - 2.4 + 0.2, R - 1.1, 3, z0=HB - 1))
    r = r.cut(box(L / 2, USB["y"], USB["z"] - USB["h"] / 2, 6, USB["w"], USB["h"]))
    return r


# ------------------------------------------------------------------ bandeja
def tray():
    t = rrect(IL - 2.7 - 0.4, IW - 2.7 - 0.4, IR - 1.55, TRAY_T, z0=TRAY_Z0)
    for sx in (-1, 1):
        t = t.cut(cyl(sx * SCREW_X, SCREW_Y, TRAY_Z0 - 1, 5.6, 3))
    # pasos de cables (batería, bobina, reed)
    t = t.cut(box(26.0, -14, TRAY_Z0 - 1, 4, 6, 3))     # cables de la batería (extremo +X)
    t = t.cut(box(-14, 3, TRAY_Z0 - 1, 6, 3.5, 3))      # bobina Qi
    t = t.cut(box(16, -17, TRAY_Z0 - 1, 3, 3, 3)).cut(box(-20, -17, TRAY_Z0 - 1, 3, 3, 3))  # patas del reed
    # marcos de las placas
    cx, cy = C6["center"]
    t = t.union(frame(cx, cy, TRAY_TOP, C6["l"] + 2 * G, C6["w"] + 2 * G, 1.0, 1.2, open_sides="E"))
    qx, qy = QI["center"]
    t = t.union(frame(qx, qy, TRAY_TOP, QI["l"] + 2 * G, QI["w"] + 2 * G, 1.0, 1.2))
    bx, by = BNO["center"]
    t = t.union(frame(bx, by, TRAY_TOP, BNO["l"] + 2 * G, BNO["w"] + 2 * G, 1.0, BNO["stand"] + 1.0, open_sides="W"))
    for (hx, hy) in ((-BNO["l"] / 2 + BNO["hole_in"], -BNO["w"] / 2 + BNO["hole_in"]), (BNO["l"] / 2 - BNO["hole_in"], BNO["w"] / 2 - BNO["hole_in"])):
        t = t.union(cyl(bx + hx, by + hy, TRAY_TOP, 4.2, BNO["stand"]))
        t = t.cut(cyl(bx + hx, by + hy, TRAY_TOP - 1.1, 1.7, BNO["stand"] + 1.2))
    return t.intersect(rrect(IL - 2.7 - 0.4, IW - 2.7 - 0.4, IR - 1.55, 10, z0=TRAY_Z0 - 1))


def usb_plug():   # TPU 95A
    p = cq.Workplane("XY").box(1.0, 12.0, 6.0).edges("|X").fillet(1.5)
    p = p.union(cq.Workplane("XY").box(3.0, USB["w"] - 0.4, USB["h"] - 0.4).edges("|X").fillet(1.2).translate((-2.0, 0, 0)))
    return p.translate((L / 2 + 0.5, USB["y"], USB["z"]))


# ------------------------------------------------------------------ soporte (mount)
def _mount_geom():
    il, iw, ir = L + 2 * CL, W + 2 * CL, R + CL                    # hueco = silueta de la cápsula + holgura
    ol, ow, orr = il + 2 * RW, iw + 2 * RW, ir + RW                  # exterior del cerco
    return il, iw, ir, ol, ow, orr


def mount():
    il, iw, ir, ol, ow, orr = _mount_geom()
    pl, pw = ol + 3.0, ow + 3.0                                      # placa con un escalón de 1,5 alrededor del cerco
    p = rrect(pl, pw, orr + 1.5, MT, z0=-MT).faces("<Z").edges().chamfer(0.6)
    p = p.faces(">Z").edges().fillet(0.6)
    # pasadores de la cinta en los extremos X (como en el concepto): barra + dos patas, hueco de 3,6 mm
    xe, sl, bw, pt = pl / 2, STRAP["slot"], STRAP["bar"], STRAP["post"]
    yi = STRAP["w"] / 2 + 1.0                                        # cinta de 50 → paso de 52
    for sx in (-1, 1):
        xb0 = xe + sl
        bar = box(sx * (xb0 + bw / 2), 0, -MT, bw, 2 * (yi + pt), MT).edges("|Y").fillet(1.4)
        p = p.union(bar)
        for sy in (-1, 1):
            x0 = 25.0                                                # las patas abrazan las esquinas del cerco
            post = box(sx * (x0 + (xb0 + bw - x0) / 2), sy * (yi + pt / 2), -MT, xb0 + bw - x0, pt, MT).edges("|X").fillet(1.0)
            p = p.union(post)
    # cerco (silueta de la cápsula + 0,12)
    rim = rrect(ol, ow, orr, RH).cut(rrect(il, iw, ir, RH + 2, z0=-1))
    rim = rim.faces(">Z").edges().fillet(0.8)
    bx0 = il / 2                                                     # cara interior del tramo +X
    rim = rim.cut(box(bx0 + RW / 2, (BEAM["y_root"] + BEAM["y_free"] + 1.2) / 2, -1,
                      RW + 2, BEAM["y_free"] + 1.2 - BEAM["y_root"], RH + 3))
    p = p.union(rim)
    # labio −X: entra 0,6 mm en la ranura de la cápsula
    gz, gz1 = GROOVE["z0"], GROOVE["z1"]
    lip_in = -il / 2 + 0.71
    p = p.union(box((-il / 2 - 0.3 + lip_in) / 2, 0, gz + ZC, lip_in + il / 2 + 0.3, 2 * LIP_Y - 0.4, RH - gz - ZC))
    # pestaña: viga vertical de 1,6 mm anclada en y_root, libre en y_free, 0,6 mm por encima de la placa
    beam = box(bx0 + BEAM["t"] / 2, (BEAM["y_root"] - 1.5 + BEAM["y_free"]) / 2, BEAM["z0"],
               BEAM["t"], BEAM["y_free"] - BEAM["y_root"] + 1.5, RH - BEAM["z0"])
    p = p.union(beam)
    # diente: cara inferior horizontal (bloquea al levantar) y rampa superior (la cápsula la empuja al bajar)
    tip = bx0 - 0.88
    hook = (cq.Workplane("XZ", origin=(0, HOOK_Y[1], 0))
            .polyline([(bx0 + 0.3, gz + ZC), (tip, gz + ZC), (tip, gz + 0.5), (bx0, RH), (bx0 + 0.3, RH)])
            .close().extrude(HOOK_Y[1] - HOOK_Y[0]))
    p = p.union(hook)
    # espiga para el tirador rojo (cara exterior del extremo libre)
    p = p.union(box(bx0 + BEAM["t"] + 0.5, BEAM["y_free"] - TAB["len"] / 2, 1.6, 1.0, TAB["len"] - 4.0, RH - 2.0))
    # imanes bajo el reed: alojamiento Ø6,15, 2 × (Ø6 × 2), abierto arriba, piel de 0,2 abajo
    rx, ry = REED["center"]
    p = p.cut(cyl(rx, ry, -MT + 0.2, MAG["d"] + 0.15, MT))
    return p


def tab():
    """tirador rojo: cubre el extremo libre de la pestaña por arriba y por fuera (pegado con cianoacrilato)"""
    il = _mount_geom()[0]
    bx0 = il / 2
    y0, y1 = BEAM["y_free"] - TAB["len"], BEAM["y_free"]
    t = box(bx0 + 0.1 + (BEAM["t"] + TAB["out"] - 0.1) / 2, (y0 + y1) / 2, 1.4,
            BEAM["t"] + TAB["out"] - 0.1, y1 - y0, RH + TAB["up"] - 1.4)
    t = t.edges("|Y").fillet(0.7)
    # hueco = extremo de la viga + espiga (+0,05)
    t = t.cut(box(bx0 + BEAM["t"] / 2, (y0 + y1) / 2, 0, BEAM["t"] + 0.1, y1 - y0 + 2, RH + 0.05))
    t = t.cut(box(bx0 + BEAM["t"] + 0.5, BEAM["y_free"] - TAB["len"] / 2, 1.0, 1.1, TAB["len"] - 4.0 + 0.1, RH - 2.0 + 0.65))
    return t


# ------------------------------------------------------------------ componentes (referencia, no se imprimen)
def components():
    cx, cy = C6["center"]; qx, qy = QI["center"]; bx, by = BNO["center"]; rx, ry = REED["center"]
    return {
        "bobina_Qi": box(0, 0, COIL_Z0 + 0.1, COIL["lx"], COIL["wy"], COIL["t"]),
        "bateria_LP403048": box(BAT_C[0], BAT_C[1], FLOOR + 0.05, BAT["l"], BAT["w"], BAT["t"]),
        "ESP32_C6": box(cx, cy, TRAY_TOP + 0.05, C6["l"], C6["w"], C6["pcb"]).union(
            box(cx - 1.5, cy, TRAY_TOP + 1.05, 12.5, 13.5, 2.3)).union(box(cx + C6["l"] / 2 - 3.6, cy, TRAY_TOP + 1.05, 7.4, 9.0, 3.2)),
        "placa_Qi": box(qx, qy, TRAY_TOP + 0.05, QI["l"], QI["w"], 2.5),
        "BNO085": box(bx, by, TRAY_TOP + BNO["stand"] + 0.05, BNO["l"], BNO["w"], BNO["t"]).union(
            box(bx + 1, by + 1, TRAY_TOP + BNO["stand"] + BNO["t"] + 0.05, 5.2, 3.8, 1.1)),
        "reed": box(rx, ry, REED["z0"] + 0.1, REED["l"], REED["d"], REED["d"]),
        "antena_FPC": box(6, 0, H - 2.3 - 0.35, 30, 6, 0.3),
        "imanes": cyl(rx, ry, -MT + 0.25, MAG["d"], MAG["t"] * MAG["n"] - 0.1),
    }


def main():
    import os
    os.makedirs(OUT, exist_ok=True)
    parts = {
        "AVO_GIRTH_R2_base": pod_base(),
        "AVO_GIRTH_R2_aro_rojo": ring(),
        "AVO_GIRTH_R2_tapa": pod_lid(),
        "AVO_GIRTH_R2_panel_rojo": panel(),
        "AVO_GIRTH_R2_bandeja": tray(),
        "AVO_GIRTH_R2_tapon_USB_TPU": usb_plug(),
        "AVO_GIRTH_R2_soporte": mount(),
        "AVO_GIRTH_R2_tirador_rojo": tab(),
    }
    check = dict(parts)
    comps = components()
    report = {"piezas": {}, "interferencias": {}}
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
    # interferencias componente ↔ pieza (deben ser 0)
    for cn, c in comps.items():
        for pn, p in parts.items():
            p = check[pn]
            try:
                v = c.intersect(p).val().Volume()
            except Exception:
                v = 0.0
            if v > 0.01 and not (cn.startswith("bateria") and pn.endswith("base") and v < 4):   # costillas: 0,1 mm de apriete a propósito
                report["interferencias"][f"{cn} × {pn}"] = round(v, 3)
    # piezas entre sí (base/tapa/bandeja/soporte)
    names = list(parts)
    for i in range(len(names)):
        for j in range(i + 1, len(names)):
            try:
                v = check[names[i]].intersect(check[names[j]]).val().Volume()
            except Exception:
                v = 0.0
            if v > 0.01:
                report["interferencias"][f"{names[i]} × {names[j]}"] = round(v, 3)
    # conjunto
    asm = cq.Assembly(name="AVO_GIRTH_R2")
    colors = {"aro": (0.93, 0.07, 0.16), "panel": (0.85, 0.06, 0.14), "tirador": (0.93, 0.07, 0.16), "base": (0.09, 0.09, 0.11), "tapa": (0.09, 0.09, 0.11), "bandeja": (0.18, 0.19, 0.22),
              "tapon": (0.17, 0.18, 0.2), "soporte": (0.16, 0.17, 0.2)}
    for n, s in parts.items():
        key = next((k for k in colors if k in n), "base")
        asm.add(s, name=n, color=cq.Color(*colors[key], 1.0))
    for n, s in comps.items():
        asm.add(s, name="ref_" + n, color=cq.Color(0.8, 0.5, 0.2, 1.0))
    asm.save(f"{OUT}/AVO_GIRTH_R2_CONJUNTO.step")
    json.dump(report, open(f"{OUT}/informe.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
