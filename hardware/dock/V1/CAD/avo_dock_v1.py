"""AVO DOCK V1 · soporte de pared cargador: caja de 2 piezas (fondo + frente) con 2 alojamientos de casco (BACK V5)
y 2 de cincha (REV 5.9.1 / 5.10), pantalla de 2,0" y pulsador.

CadQuery 2.4 (se ejecuta en el CI: .github/workflows/build-dock-v1-cad.yml). Escribe out/*.step, out/*.stl, el conjunto
out/AVO_DOCK_V1_CONJUNTO.step y out/informe.json (sólidos, volúmenes, pesos en PETG e interferencias con las referencias).

Ejes: X a la derecha, Y hacia arriba (en la pared), Z hacia fuera de la pared; z = 0 en la pared. VISTA DE FRENTE.
La PCB (pcb_mecanica.json, coordenadas vistas desde su cara F) va paralela a la pared con la cara F hacia el frente:
(X, Y)_PCB + PCB_OFF → (X, Y)_CAD, sin espejo.

Piezas (PETG, Elegoo Centauri Carbon, holgura mínima 0,2–0,3):
  fondo  z 0 … 35: placa trasera de 3 con 2 ojales de cerradura para colgar, pilares M3 de la PCB, pasacables M12
         para el cable de red (clase II, sin tierra) con brida interior, ventana del USB-C y rejillas;
  frente z 35 … 55: pared frontal de 3 con 2 alojamientos de casco y 2 de cincha (imanes y pogo de muelles empotrados,
         cara a ras del fondo del alojamiento), ventana y marco de la pantalla, agujero del pulsador de 12 mm.
  Cierre: 5 × M3 × 25 desde el frente a insertos M3 (Ø4,2 × 5,7) en el fondo. Un labio de 3 mm centra las dos piezas.
Medidas (E) = estimadas: pogo de 5 contactos del casco (no hay STEP real) y módulo de pantalla (depende del vendedor).
"""
import json
import math
import os

import cadquery as cq

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
MEC = json.load(open(os.path.join(HERE, "..", "PCB", "pcb_mecanica.json"), encoding="utf-8"))

# ---------------------------------------------------------------- parámetros generales
W, H, D = 200.0, 190.0, 55.0             # caja exterior
R_OUT = 8.0
WALL = 3.0
SPLIT = 35.0                              # unión fondo / frente
LIP = dict(off0=1.6, off1=WALL, h=3.0)   # labio del fondo sobre la mitad interior de su pared; el frente lleva
#                                           un rebaje (pared de 1,4) con 0,2 de holgura
Z_FRONT = D                               # cara frontal
Z_FIN = D - WALL                          # cara interior de la pared frontal
G = 0.3                                   # holgura de las cápsulas en sus alojamientos

PCB = MEC["placa"]
PCB_OFF = (31.0, -48.0)                   # centro de la PCB en la caja (su canto derecho junto a la pared derecha)
Z_PCB = 8.0                               # cara B de la PCB (sobre los pilares)
Z_PCB_F = Z_PCB + PCB["espesor"]
IRM = dict(h=24.0)

# ---------------------------------------------------------------- cápsulas (de sus propios CAD)
# Casco BACK V5 (hardware/back/V5_CASCO/CAD, informe 14/11/2026): 56,4 × 56,4 × 24,1, R 5,7, chaflán inferior 1,2;
# 4 imanes Ø6 × 2 en (±15,5, −22,5) y (±15, 22,5); pogo de 5 contactos en (0, −22,525), cara a ras del fondo.
CASCO = dict(side=56.4, r=5.7, h=24.1, depth=6.0,
             mags=[(-15.5, -22.5), (15.5, -22.5), (-15.0, 22.5), (15.0, 22.5)], mag=(6.0, 2.0),
             pogo=dict(y=-22.525, n=5))
# Cincha REV 5.9.1 (70 × 51) y REV 5.10 (70 × 53): el alojamiento admite las dos; imanes Ø5 × 1 en (±27,3, ±17,9)
# (polaridad alterna en diagonal, igual que el soporte); pogo de 3 contactos a medio camino entre y = −20,2 (5.9.1) y
# y = −19,7 (5.10): ±0,25 mm de error frente a contactos de Ø2 y pines de Ø0,8.
CINCHA = dict(l=70.0, w=53.0, r=10.0, h=13.8, depth=5.0,
              mags=[(sx * 27.3, sy * 17.9) for sx in (-1, 1) for sy in (-1, 1)], mag=(5.0, 1.0), mag_n=2,
              pogo=dict(y=-19.95, n=3))
# lado de los pines del pogo (STEP real del de 3 contactos, ref/pogo_3pin_assembly.step de la cincha): cuerpo
# 15,5 × 4,65 × 6,0; orejas 25 × 5,5 × 2,0 entre 2,5 y 4,5 de la cara; agujeros Ø2 en ±9,75; colas de 1,5.
# El de 5 contactos (E): + 2 × 2,3 de largo en cuerpo, orejas y agujeros.
POGO_PIN = dict(body_w=4.65, body_h=6.0, tail=1.5, ear_w=5.5, ear_t=2.0, ear_z0=2.5, pilot=1.6, pilot_h=2.0, clear=0.2)


def pogo_dims(n):
    extra = (n - 3) * 2.3
    return dict(body_l=15.5 + extra, ear_l=25.0 + extra, holes=9.75 + extra / 2)


BAYS = {
    "casco_A": dict(kind="casco", c=(-62.0, 50.0)),
    "casco_B": dict(kind="casco", c=(62.0, 50.0)),
    "cincha_A": dict(kind="cincha", c=(-47.0, -45.0)),
    "cincha_B": dict(kind="cincha", c=(47.0, -45.0)),
}
BACKING = 13.5                            # grueso del bloque de cada alojamiento, medido desde la cara frontal

# pantalla IPS 2,0" 240 × 320 ST7789V (E): vidrio 36,0 × 47,6 × 2,3; zona visible 31,0 × 41,0 (vertical)
LCD = dict(c=(0.0, 50.0), view=(31.5, 41.5), glass=(36.6, 52.2), frame=3.0, depth=5.0)
BTN = dict(c=(0.0, 14.0), d=12.2)          # pulsador antivandálico de 12 mm (rosca M12)

# tornillos del cierre y pilares
SCREWS = [(-27.5, 84.0), (27.5, 84.0), (-89.0, 0.0), (89.0, 0.0), (-89.0, -81.0)]
SCREW = dict(tube=8.5, hole=3.4, head=6.4, insert=4.2, insert_h=6.0)
PCB_POSTS = [(x + PCB_OFF[0], y + PCB_OFF[1]) for x, y in MEC["taladros"]]
KEYHOLES = [(-70.0, 62.0), (70.0, 62.0)]
GLAND = dict(x=-62.0, d=12.5, z=16.0)       # prensaestopas M12 × 1,5 en la pared inferior
CLAMP = [(-71.0, -74.0), (-53.0, -74.0)]    # brida del cable de red (2 pilares M3)
J3 = MEC["usb_c"]["pos"]
USB_C = dict(y=J3[1] + PCB_OFF[1], z=Z_PCB_F + 1.63, w=10.6, h=4.4)


# ---------------------------------------------------------------- ayudas
def rrect(lx, ly, r, h, z0=0.0, cx=0.0, cy=0.0):
    s = cq.Workplane("XY").workplane(offset=z0).rect(lx, ly).extrude(h)
    if r > 0.05:
        s = s.edges("|Z").fillet(r)
    return s.translate((cx, cy, 0))


def box(cx, cy, z0, lx, ly, h):
    return cq.Workplane("XY").box(lx, ly, h, centered=(True, True, False)).translate((cx, cy, z0))


def cyl(cx, cy, z0, d, h):
    return cq.Workplane("XY").circle(d / 2).extrude(h).translate((cx, cy, z0))


def cyl_dir(p, d, h, v):
    return cq.Workplane("XY").add(cq.Solid.makeCylinder(d / 2, h, cq.Vector(*p), cq.Vector(*v)))


def shell(z0, h):
    return rrect(W, H, R_OUT, h, z0)


def inner(z0, h, off=WALL):
    return rrect(W - 2 * off, H - 2 * off, R_OUT - off, h, z0)


# ---------------------------------------------------------------- fondo
def fondo():
    f = shell(0, SPLIT).cut(inner(WALL, SPLIT))
    # labio de centrado
    lip = inner(SPLIT - 0.01, LIP["h"], LIP["off0"]).cut(inner(SPLIT - 1, LIP["h"] + 2, LIP["off1"] - 0.01))
    f = f.union(lip)
    # pilares de la PCB (insertos M3)
    for (x, y) in PCB_POSTS:
        f = f.union(cyl(x, y, WALL - 0.01, 7.0, Z_PCB - WALL + 0.01))
        f = f.cut(cyl(x, y, Z_PCB - 5.7, SCREW["insert"], 6.0))
    # pilares del cierre (inserto arriba)
    for (x, y) in SCREWS:
        f = f.union(cyl(x, y, WALL - 0.01, SCREW["tube"], SPLIT - WALL + 0.01))
        f = f.cut(cyl(x, y, SPLIT - SCREW["insert_h"], SCREW["insert"], SCREW["insert_h"] + 0.1))
    # ojales de cerradura para colgar (tornillo de cabeza ≤ Ø8,5 que entra por abajo y sube 10 mm)
    for (x, y) in KEYHOLES:
        f = f.union(box(x, y - 1.0, WALL - 0.01, 22.0, 30.0, 7.0))
        f = f.cut(cyl(x, y - 6.0, -1, 9.0, WALL + 1.01))                       # entrada de la cabeza
        f = f.cut(box(x, y - 1.0, -1, 4.6, 10.0, WALL + 1.01))                 # ranura del cuello
        f = f.cut(cyl(x, y + 4.0, -1, 4.6, WALL + 1.01))
        f = f.cut(cyl(x, y - 6.0, WALL - 0.01, 9.4, 4.0))                     # bolsa de la cabeza
        f = f.cut(box(x, y - 1.0, WALL - 0.01, 9.4, 10.0, 4.0))
        f = f.cut(cyl(x, y + 4.0, WALL - 0.01, 9.4, 4.0))
    # pasacables M12 del cable de red (pared inferior) y brida interior
    f = f.cut(cyl_dir((GLAND["x"], -H / 2 - 1, GLAND["z"]), GLAND["d"], WALL + 2, (0, 1, 0)))
    for (x, y) in CLAMP:
        f = f.union(cyl(x, y, WALL - 0.01, 7.0, 12.0))
        f = f.cut(cyl(x, y, WALL + 12.0 - 5.7, SCREW["insert"], 6.0))
    # USB-C en la pared derecha
    usb = cq.Workplane("XY").box(WALL + 2, USB_C["w"], USB_C["h"]).edges("|X").fillet(1.5) \
        .translate((W / 2 - WALL / 2, USB_C["y"], USB_C["z"]))
    f = f.cut(usb)
    f = f.cut(box(W / 2 - 0.6, USB_C["y"], USB_C["z"] - 4.0, 1.4, 14.0, 8.0))   # rebaje del conector del cable
    # rejillas arriba y abajo (convección sobre el IRM-20)
    for k in range(9):
        x = -30.0 + k * 6.5
        for yw in (-H / 2 + WALL / 2, H / 2 - WALL / 2):
            f = f.cut(box(x, yw, 10.0, 2.2, WALL + 2, 16.0))
    return f


# ---------------------------------------------------------------- frente
def pogo_cut(cx, cy, z_floor, n):
    """lado de los pines del pogo: cara a ras del fondo del alojamiento; cuerpo y orejas abiertos por detrás."""
    d = pogo_dims(n)
    cl = POGO_PIN["clear"]
    zb = min(z_floor - POGO_PIN["body_h"] - POGO_PIN["tail"] - 0.2, Z_FRONT - BACKING - 1.0)   # abierto por detrás
    body = rrect(d["body_l"] + 2 * cl, POGO_PIN["body_w"] + 2 * cl, POGO_PIN["body_w"] / 2, z_floor - zb + 0.01, zb,
                 cx, cy)
    ear_top = z_floor - POGO_PIN["ear_z0"] + 0.1
    ears = rrect(d["ear_l"] + 2 * cl, POGO_PIN["ear_w"] + 2 * cl, POGO_PIN["ear_w"] / 2, ear_top - zb, zb, cx, cy)
    pil = cyl(cx - d["holes"], cy, ear_top - 0.01, POGO_PIN["pilot"], POGO_PIN["pilot_h"]).union(
        cyl(cx + d["holes"], cy, ear_top - 0.01, POGO_PIN["pilot"], POGO_PIN["pilot_h"]))
    return body.union(ears).union(pil)


def bay_geom(b):
    if b["kind"] == "casco":
        c = CASCO
        lx = ly = c["side"] + 2 * G
        r = c["r"] + G
    else:
        c = CINCHA
        lx, ly, r = c["l"] + 2 * G, c["w"] + 2 * G, c["r"] + G
    return c, lx, ly, r


def frente():
    f = shell(SPLIT, D - SPLIT).cut(inner(SPLIT - 0.01, D - SPLIT - WALL + 0.01))
    f = f.faces(">Z").edges().chamfer(1.5)
    # rebaje del labio: la pared del frente queda en 1,4 mm en sus 3,2 mm inferiores
    f = f.cut(inner(SPLIT - 1, LIP["h"] + 0.2 + 1, LIP["off0"] - 0.2))
    # bloques de los alojamientos (por dentro)
    for b in BAYS.values():
        c, lx, ly, r = bay_geom(b)
        f = f.union(rrect(lx + 9.0, ly + 9.0, r + 4.5, BACKING - WALL + 0.01, Z_FRONT - BACKING, *b["c"]))
    # marco de la pantalla
    gx, gy = LCD["glass"]
    fr = rrect(gx + 2 * LCD["frame"], gy + 2 * LCD["frame"], 2.0, LCD["depth"] + 0.01, Z_FIN - LCD["depth"], *LCD["c"])
    fr = fr.cut(rrect(gx, gy, 1.0, LCD["depth"] + 1, Z_FIN - LCD["depth"] - 0.5, *LCD["c"]))
    f = f.union(fr)
    # tubos del cierre
    for (x, y) in SCREWS:
        f = f.union(cyl(x, y, SPLIT + LIP["h"] + 0.3, SCREW["tube"], Z_FIN - SPLIT - LIP["h"] - 0.3 + 0.01))
    # --- vaciados
    for b in BAYS.values():
        c, lx, ly, r = bay_geom(b)
        cx, cy = b["c"]
        zf = Z_FRONT - c["depth"]
        f = f.cut(rrect(lx, ly, r, c["depth"] + 1, zf, cx, cy))                         # alojamiento
        f = f.cut(cyl(cx, cy + ly / 2, zf, 24.0, c["depth"] + 1))                     # muesca para sacarla con el dedo
        md, mt = c["mag"]
        n = c.get("mag_n", 1)
        for (x, y) in c["mags"]:                                                     # imanes por detrás, 0,3 de piel
            f = f.cut(cyl(cx + x, cy + y, Z_FRONT - BACKING - 1, md + 0.15, BACKING - c["depth"] - 0.3 + 1))
        f = f.cut(pogo_cut(cx, cy + c["pogo"]["y"], zf, c["pogo"]["n"]))
    # pantalla: ventana con chaflán y pulsador
    f = f.cut(rrect(LCD["view"][0], LCD["view"][1], 1.0, WALL + 2, Z_FIN - 1, *LCD["c"]))
    f = f.cut(cyl(BTN["c"][0], BTN["c"][1], Z_FIN - 1, BTN["d"], WALL + 2))
    # tornillos del cierre: paso y cajera de la cabeza
    for (x, y) in SCREWS:
        f = f.cut(cyl(x, y, SPLIT, SCREW["hole"], D - SPLIT + 1))
        f = f.cut(cyl(x, y, Z_FIN - 1.2, SCREW["head"], WALL + 2))
    return f


# ---------------------------------------------------------------- referencias (no se imprimen)
def refs():
    r = {}
    r["pcb"] = rrect(PCB["ancho"], PCB["alto"], PCB["radio_esquina"], PCB["espesor"], Z_PCB, *PCB_OFF)
    comp = None
    for ref, x0, y0, x1, y1, h in MEC["envolventes"]:
        if h < 0.5:
            continue
        s = box((x0 + x1) / 2 + PCB_OFF[0], (y0 + y1) / 2 + PCB_OFF[1], Z_PCB_F + 0.02, x1 - x0, y1 - y0, h - 0.04)
        comp = s if comp is None else comp.union(s)
    r["componentes_pcb"] = comp
    for name, b in BAYS.items():
        c, lx, ly, rr = bay_geom(b)
        cx, cy = b["c"]
        zf = Z_FRONT - c["depth"]
        if b["kind"] == "casco":
            cap = rrect(c["side"], c["side"], c["r"], c["h"], zf + 0.02, cx, cy)
        else:
            cap = rrect(c["l"], c["w"], c["r"], c["h"], zf + 0.02, cx, cy)
        r["capsula_" + name] = cap
        d = pogo_dims(c["pogo"]["n"])
        py = cy + c["pogo"]["y"]
        body = rrect(d["body_l"], POGO_PIN["body_w"], POGO_PIN["body_w"] / 2 - 0.01, POGO_PIN["body_h"],
                     zf - POGO_PIN["body_h"], cx, py)
        ears = rrect(d["ear_l"], POGO_PIN["ear_w"], POGO_PIN["ear_w"] / 2 - 0.01, POGO_PIN["ear_t"],
                     zf - POGO_PIN["ear_z0"] - POGO_PIN["ear_t"], cx, py)
        r["pogo_" + name] = body.union(ears)
        mags = None
        md, mt = c["mag"]
        for (x, y) in c["mags"]:
            m = cyl(cx + x, cy + y, zf - 0.3 - mt * c.get("mag_n", 1), md, mt * c.get("mag_n", 1) - 0.02)
            mags = m if mags is None else mags.union(m)
        r["imanes_" + name] = mags
    r["pantalla"] = box(LCD["c"][0], LCD["c"][1], Z_FIN - 2.3, LCD["glass"][0] - 0.6, LCD["glass"][1] - 0.6, 2.28)
    return r


def main():
    parts = {"AVO_DOCK_V1_fondo": fondo(), "AVO_DOCK_V1_frente": frente()}
    rf = refs()
    rep = {"piezas": {}, "interferencias": {}, "medidas": {}}
    for n, s in parts.items():
        nsol = len(s.solids().vals())
        if nsol != 1:
            print("AVISO %s: %d sólidos" % (n, nsol), [round(x.Volume(), 2) for x in s.solids().vals()])
        v = s.val().Volume() if nsol == 1 else sum(x.Volume() for x in s.solids().vals())
        bb = s.val().BoundingBox()
        rep["piezas"][n] = dict(solidos=nsol, volumen_mm3=round(v, 1), peso_PETG_g=round(v * 1.27 / 1000, 1),
                                caja=[round(bb.xlen, 2), round(bb.ylen, 2), round(bb.zlen, 2)])
        cq.exporters.export(s, os.path.join(OUT, n + ".step"))
        cq.exporters.export(s, os.path.join(OUT, n + ".stl"), tolerance=0.03, angularTolerance=0.1)
    for n, s in rf.items():
        if s is not None:
            cq.exporters.export(s, os.path.join(OUT, "ref_" + n + ".stl"), tolerance=0.05)
    # interferencias: referencias contra piezas y fondo contra frente
    for rn, r in rf.items():
        if r is None:
            continue
        for pn, p in parts.items():
            try:
                v = r.intersect(p).val().Volume()
            except Exception:  # noqa: BLE001
                v = 0.0
            if v > 0.01:
                rep["interferencias"]["%s × %s" % (rn, pn)] = round(v, 3)
    try:
        v = parts["AVO_DOCK_V1_fondo"].intersect(parts["AVO_DOCK_V1_frente"]).val().Volume()
    except Exception:  # noqa: BLE001
        v = 0.0
    if v > 0.01:
        rep["interferencias"]["fondo × frente"] = round(v, 3)
    rep["medidas"] = dict(
        caja_mm=[W, H, D], union_z=SPLIT, pared=WALL, pcb_centro=list(PCB_OFF), pcb_z=[Z_PCB, Z_PCB_F],
        alojamientos={k: dict(tipo=b["kind"], centro=list(b["c"]), hondo=bay_geom(b)[0]["depth"],
                              hueco=[round(bay_geom(b)[1], 2), round(bay_geom(b)[2], 2)]) for k, b in BAYS.items()},
        tornillos="5 × M3 × 25 (cabeza cilíndrica) desde el frente + 5 insertos M3 Ø4,2 × 5,7; PCB: 4 × M3 × 6 + 4 insertos",
        colgar="2 ojales de cerradura a 140 mm (tornillo de cabeza ≤ Ø8,5, cuello ≤ Ø4,5)",
        red="prensaestopas M12 × 1,5 (cable 2 × 0,75 mm² de doble aislamiento) + brida M3 interior",
        imanes="casco: 4 × Ø6 × 2 N52 por alojamiento; cincha: 4 × (2 × Ø5 × 1) por alojamiento, polaridad opuesta a la cápsula")
    asm = cq.Assembly(name="AVO_DOCK_V1")
    col = {"fondo": (0.15, 0.15, 0.17), "frente": (0.88, 0.88, 0.9)}
    for n, s in parts.items():
        asm.add(s, name=n, color=cq.Color(*col["fondo" if "fondo" in n else "frente"], 1.0))
    rc = {"pcb": (0.1, 0.45, 0.2), "componentes_pcb": (0.6, 0.6, 0.6), "pantalla": (0.05, 0.05, 0.05)}
    for n, s in rf.items():
        if s is None:
            continue
        k = "capsula" if n.startswith("capsula") else n
        c = rc.get(k, (0.8, 0.1, 0.1) if k == "capsula" else (0.8, 0.5, 0.2))
        asm.add(s, name="ref_" + n, color=cq.Color(*c, 1.0))
    asm.save(os.path.join(OUT, "AVO_DOCK_V1_CONJUNTO.step"))
    json.dump(rep, open(os.path.join(OUT, "informe.json"), "w"), ensure_ascii=False, indent=1)
    print(json.dumps(rep, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
