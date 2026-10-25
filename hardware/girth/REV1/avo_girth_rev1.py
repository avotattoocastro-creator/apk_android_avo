"""AVO GIRTH REV 1 — caja de la cincha (cápsula + bandeja + tapa + tapón USB) y soporte para cinta de 50 mm.

CadQuery (OpenCascade): STEP B-Rep por pieza + conjunto, STL para imprimir. PETG, Elegoo Centauri Carbon.
Ejes: X a lo largo de la cinta, Y = dirección de entrada de la cápsula en el soporte (entra de +Y hacia −Y),
Z arriba. Cápsula con el fondo en Z = 0 (en el conjunto, sobre el soporte).

Medidas de componentes: anuncios (P = provisional, pendiente de calibre):
  ESP32-C6 XIAO 21 × 18 · LiPo LP403048 30,5 × 50,8 × 4,3 máx · bobina Qi 23 × 30 · placa Qi 15 × 18
  GY-BNO085 25,8 × 15,5 (taladros P) · reed 14 × 3,2 · imán Ø6 × 2 (dos apilados)

Seguridad del anclaje (galope):
  * 2 colas de milano (soporte) en 2 ranuras del fondo de la cápsula: no puede levantarse ni moverse en X.
  * Las ranuras están cerradas en −Y: tope.
  * Gancho elástico del soporte en un rebaje del fondo: no puede salir hacia +Y.
  Para soltar: pulsar la pestaña (fuera de la cápsula) Y deslizar hacia +Y. Dos acciones: no se suelta sola.
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

DOVE = dict(x=22.0, w_face=5.6, w_deep=6.8, depth=1.8, y_open=W / 2 + 1, y_stop=-W / 2 + 4)
LATCH = dict(x=4.0, y0=15.0, y1=19.0, depth=1.5)   # rebaje abierto hasta el borde +Y (aloja la rampa)

# soporte
ML, MW, MT = 84.0, 60.0, 4.4
STRAP = dict(w=52.0, slot=3.6, x0=L / 2 + 2.5)
BEAM = dict(w=10.0, y_anchor=8.0, y_end=MW / 2, t=2.0, slot=1.0)


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


def dovetail(x, y_from, y_to, w_top, w_bottom, z0, h):
    """trapezoid prism along Y: width w_bottom at z0, w_top at z0 + h"""
    pts = [(x - w_bottom / 2, z0), (x + w_bottom / 2, z0), (x + w_top / 2, z0 + h), (x - w_top / 2, z0 + h)]
    return cq.Workplane("XZ", origin=(0, y_from, 0)).polyline(pts).close().extrude(y_from - y_to)


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
    # ranuras de cola de milano en el fondo (abiertas en +Y, cerradas en −Y = tope)
    for sx in (-1, 1):
        b = b.cut(dovetail(sx * DOVE["x"], DOVE["y_open"], DOVE["y_stop"], DOVE["w_deep"], DOVE["w_face"], -0.01, DOVE["depth"]))
    # rebaje del gancho de seguridad
    b = b.cut(box(0, (LATCH["y0"] + W / 2 + 1) / 2, -0.01, 2 * LATCH["x"], W / 2 + 1 - LATCH["y0"], LATCH["depth"]))
    # salida USB-C (parte inferior de la ventana, si cae en la base)
    b = b.cut(box(L / 2, USB["y"], USB["z"] - USB["h"] / 2, 6, USB["w"], USB["h"]))
    return b


# ------------------------------------------------------------------ cápsula: tapa
def pod_lid():
    outer = rrect(L, W, R, H - HB, z0=HB).faces(">Z").edges().fillet(3.0)
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
    try:
        logo = (cq.Workplane("XY").workplane(offset=H).text("AVO", 9.0, -0.5, kind="bold", halign="center", valign="center")
                .translate((-6, 4, 0)))
        lid = lid.cut(logo)
        sub = (cq.Workplane("XY").workplane(offset=H).text("GIRTH", 3.2, -0.4, halign="center", valign="center")
               .translate((-6, -5, 0)))
        lid = lid.cut(sub)
    except Exception as e:   # sin fuente en el sistema: tapa sin logo
        print("logo omitido:", e)
    return lid


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
def mount():
    p = rrect(ML, MW, 8.0, MT, z0=-MT).faces("<Z or >Z").edges().chamfer(0.6)
    # pasos para la cinta de 50 mm
    for sx in (-1, 1):
        p = p.cut(box(sx * (STRAP["x0"] + STRAP["slot"] / 2), 0, -MT - 1, STRAP["slot"], STRAP["w"], MT + 2))
    # colas de milano (macho), del borde +Y hasta 0,3 antes del tope de la ranura
    cl = 0.25
    for sx in (-1, 1):
        p = p.union(dovetail(sx * DOVE["x"], MW / 2 - 0.5, DOVE["y_stop"] + 0.3,
                             DOVE["w_deep"] - 2 * cl, DOVE["w_face"] - 2 * cl, 0, DOVE["depth"] - 0.25))
    # gancho elástico: viga recortada en U, anclada en −Y, libre en el borde +Y
    bw, ya, ye = BEAM["w"], BEAM["y_anchor"], BEAM["y_end"]
    p = p.cut(box(0, (ya + ye) / 2 + 0.5, -MT - 1, bw + 2 * BEAM["slot"], ye - ya + 1, MT + 2))
    beam = box(0, (ya + ye) / 2, -BEAM["t"], bw, ye - ya, BEAM["t"])
    p = p.union(beam)
    p = p.union(box(0, ya - 0.5, -MT, bw + 2 * BEAM["slot"] + 0.01, 1.2, MT))   # raíz de la viga, unida a la placa
    # diente: cara vertical hacia −Y (bloquea), rampa hacia +Y (deja entrar)
    hook = (cq.Workplane("YZ").polyline([(LATCH["y0"] + 0.4, 0), (LATCH["y1"] + 3.0, 0), (LATCH["y1"] - 0.3, 1.2), (LATCH["y0"] + 0.4, 1.2)])
            .close().extrude(2 * LATCH["x"] - 0.8).translate((-(LATCH["x"] - 0.4), 0, 0)))
    p = p.union(hook)
    # pulsador de la pestaña, fuera de la cápsula
    p = p.union(box(0, ye - 3.0, 0, bw - 1.0, 5.0, 1.6).edges("|Z").fillet(1.0))
    # imanes bajo el reed (Ø6,15 a presión, 2 × 2 mm, piel de 0,3 abajo)
    rx, ry = REED["center"]
    p = p.cut(cyl(rx, ry, -MT + 0.3, MAG["d"] + 0.15, MT))
    return p


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
        "imanes": cyl(rx, ry, -MT + 0.35, MAG["d"], MAG["t"] * MAG["n"]),
    }


def main():
    import os
    os.makedirs(OUT, exist_ok=True)
    parts = {
        "AVO_GIRTH_R1_base": pod_base(),
        "AVO_GIRTH_R1_tapa": pod_lid(),
        "AVO_GIRTH_R1_bandeja": tray(),
        "AVO_GIRTH_R1_tapon_USB_TPU": usb_plug(),
        "AVO_GIRTH_R1_soporte": mount(),
    }
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
                v = parts[names[i]].intersect(parts[names[j]]).val().Volume()
            except Exception:
                v = 0.0
            if v > 0.01:
                report["interferencias"][f"{names[i]} × {names[j]}"] = round(v, 3)
    # conjunto
    asm = cq.Assembly(name="AVO_GIRTH_R1")
    colors = {"base": (0.09, 0.09, 0.11), "tapa": (0.09, 0.09, 0.11), "bandeja": (0.18, 0.19, 0.22),
              "tapon": (0.17, 0.18, 0.2), "soporte": (0.16, 0.17, 0.2)}
    for n, s in parts.items():
        key = next((k for k in colors if k in n), "base")
        asm.add(s, name=n, color=cq.Color(*colors[key], 1.0))
    for n, s in comps.items():
        asm.add(s, name="ref_" + n, color=cq.Color(0.8, 0.5, 0.2, 1.0))
    asm.save(f"{OUT}/AVO_GIRTH_R1_CONJUNTO.step")
    json.dump(report, open(f"{OUT}/informe.json", "w"), ensure_ascii=False, indent=1)
    print(json.dumps(report, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
