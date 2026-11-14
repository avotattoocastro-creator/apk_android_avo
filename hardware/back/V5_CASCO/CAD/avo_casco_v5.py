"""AVO BACK V5 CASCO · cápsula estanca (base + tapa + junta) y base magnética desprendible para el casco.

CadQuery 2.4 (se ejecuta en el CI: .github/workflows/build-back-v5-cad.yml). Escribe out/*.step, out/*.stl, el conjunto
y out/informe.json (sólidos, volúmenes, pesos en PETG/TPU e interferencias con las referencias).

Ejes: origen en el centro, z = 0 en la cara inferior de la cápsula, z hacia el cielo, VISTA DESDE ARRIBA.
La PCB (pcb_mecanica.json, coordenadas vistas desde su cara F) va con la cara F hacia abajo: (X, Y)_PCB → (−X, Y)_CAD.

Apilado (de abajo arriba):
  suelo 1,4 · batería ≤ 50 × 37 × 8,5 (E) · 0,4 · componentes de la cara F (≤ 2,6) · PCB 1,6 · antena 25 × 25 × 8,1 (E)
  · 0,3 · techo 1,2.
Cierre: 4 × M2,5 × 16 desde abajo por los taladros de la PCB (±22, ±22) con junta tórica 2,5 × 1 bajo la cabeza;
  insertos M2,5 (Ø3,5 × 4) en los postes de la tapa; la PCB queda pinzada entre las columnas de la base y los postes.
  Junta TPU 85A en la ranura de la cara superior de la pared de la base.
Pogo de 5 contactos (ESTIMADO a partir del STEP del de 3 contactos, paso 2,3): en el fondo, franja −Y, cara a ras.
Base del casco: anillo de PETG con 4 imanes Ø6 × 2 (frente a los 4 de la cápsula), imán Ø8 × 3 del Hall y alojamiento
  con paredes a 45° de 1,2 mm de alto (se suelta con un golpe lateral); cara inferior cóncava R = 110 (ajustable).
"""
import json
import math
import os

import cadquery as cq

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "out")
os.makedirs(OUT, exist_ok=True)
MEC = json.load(open(os.path.join(HERE, "..", "PCB", "pcb_mecanica.json"), encoding="utf-8"))

# ---------------------------------------------------------------- parámetros
PCB = dict(side=MEC["placa"]["lado"], r=MEC["placa"]["radio_esquina"], t=MEC["placa"]["espesor"])
CL = 0.3                                   # holgura PCB ↔ pared
WALL = 2.4
IN = PCB["side"] + 2 * CL                  # interior 51,6
OUTS = IN + 2 * WALL                       # exterior 56,4
R_OUT = PCB["r"] + CL + WALL
FLOOR = 1.4
BAT = dict(x=50.0, y=37.0, t=8.5)          # (E) celda 1S ≥ 2000 mAh: envolvente máxima
Z_BAT0 = FLOOR
Z_F = Z_BAT0 + BAT["t"] + 0.4 + MEC["altura_max_cara_F"]   # cara F de la PCB (hacia abajo)
Z_PCB_TOP = Z_F + PCB["t"]                 # cara B (masa) = junta base/tapa
ANT = dict(side=25.0, h=8.1)               # (E) Taoglas AHP2258
Z_CEIL = Z_PCB_TOP + ANT["h"] + 0.3
TOP_T = 1.2
H = Z_CEIL + TOP_T
SCREWS = [(-x, y) for x, y in MEC["taladros"]]
SCREW = dict(hole=2.8, cb_d=5.0, cb_h=2.6, boss=5.0, post=6.0, insert_d=3.6, insert_h=4.6)
GASKET = dict(c=WALL / 2, w_groove=1.0, depth=0.8, w=0.9, h_free=1.1)
POGO = dict(n=5, pitch=2.3, f_l=21.7, f_w=6.25, f_t=3.5, face_l=20.1, face_w=4.65, face_h=1.7, clear=0.2,
            y=-(IN / 2 - 6.25 / 2 - 0.2 + 0.05), cup_wall=0.6, cup_z=5.5)    # (E) hasta tener el STEP real
MAG = dict(d=6.0, t=2.0, skin=0.3, pos=[(-15.5, -22.5), (15.5, -22.5), (-15.0, 22.5), (15.0, 22.5)])
U8 = next(e for e in MEC["envolventes"] if e[0] == "U8")
HALL_XY = (-(U8[1] + U8[3]) / 2, (U8[2] + U8[4]) / 2)
CHAMF = 1.2                                # chaflán inferior de la cápsula = alojamiento de la base del casco
HB = dict(t=3.5, ring=9.5, rim=1.8, recess=1.2, helmet_r=110.0, sag=8.0, hall_mag=(8.0, 3.0))


def rrect(lx, ly, r, h, z0=0.0):
    return cq.Workplane("XY").workplane(offset=z0).rect(lx, ly).extrude(h).edges("|Z").fillet(r)


def box(cx, cy, z0, lx, ly, h):
    return cq.Workplane("XY").box(lx, ly, h, centered=(True, True, False)).translate((cx, cy, z0))


def cyl(cx, cy, z0, d, h):
    return cq.Workplane("XY").circle(d / 2).extrude(h).translate((cx, cy, z0))


def shell_ring(off_out, off_in, h, z0):
    return rrect(OUTS - 2 * off_out, OUTS - 2 * off_out, R_OUT - off_out, h, z0).cut(
        rrect(OUTS - 2 * off_in, OUTS - 2 * off_in, max(R_OUT - off_in, 0.3), h + 2, z0 - 1))


# ---------------------------------------------------------------- base
def base():
    b = rrect(OUTS, OUTS, R_OUT, Z_PCB_TOP).faces("<Z").edges().chamfer(CHAMF)
    b = b.cut(rrect(IN, IN, PCB["r"] + CL, Z_PCB_TOP, z0=FLOOR))
    # columnas de los tornillos (apoyo de la PCB en la cara F)
    for (x, y) in SCREWS:
        b = b.union(cyl(x, y, 0, SCREW["boss"], Z_F))
    # pogo: zona maciza hasta la base del reborde, alojamiento del reborde, copa de epoxi y paso de la cara
    py, cl = POGO["y"], POGO["clear"]
    fl, fw = POGO["f_l"] + 2 * cl, POGO["f_w"] + 2 * cl
    zf = POGO["face_h"]
    b = b.union(box(0, py, FLOOR - 0.1, fl + 2 * POGO["cup_wall"], fw + 2 * POGO["cup_wall"], POGO["cup_z"] - FLOOR + 0.1)
                .intersect(rrect(IN, IN, PCB["r"] + CL, 20, 0)))
    stad = lambda l, w, h, z0: rrect(l, w, w / 2 - 0.01, h, z0).translate((0, py, 0))
    b = b.cut(stad(fl, fw, POGO["cup_z"] + 1 - zf, zf))                                   # reborde + copa
    b = b.cut(stad(POGO["face_l"] + 2 * cl, POGO["face_w"] + 2 * cl, zf + 1.01, -1))      # cara a ras del fondo
    # cuna de la batería: topes bajos en las 4 esquinas de la celda
    for sx in (-1, 1):
        for sy in (-1, 1):
            x0, y0 = sx * (BAT["x"] / 2 + 0.25 + 0.4), sy * (BAT["y"] / 2 + 0.25 + 0.4)
            b = b.union(box(x0, sy * (BAT["y"] / 2 - 3), FLOOR - 0.1, 0.8, 6, 2.1).intersect(rrect(IN, IN, PCB["r"] + CL, 20, 0)))
            if sy > 0:      # en −Y hace de tope la pared de la copa del pogo
                b = b.union(box(sx * (BAT["x"] / 2 - 3), y0, FLOOR - 0.1, 6, 0.8, 2.1))
    # imanes de sujeción: recrecido interior y alojamiento desde dentro (0,3 de piel abajo)
    for (x, y) in MAG["pos"]:
        b = b.union(cyl(x, y, FLOOR - 0.1, MAG["d"] + 1.6, MAG["skin"] + MAG["t"] + 0.2 - FLOOR + 0.1))
        b = b.cut(cyl(x, y, MAG["skin"], MAG["d"] + 0.15, MAG["t"] + 0.2 + 5))
    # tornillos: avellanado (cabeza + junta tórica) y paso
    for (x, y) in SCREWS:
        b = b.cut(cyl(x, y, -1, SCREW["hole"], Z_PCB_TOP + 2)).cut(cyl(x, y, -1, SCREW["cb_d"], SCREW["cb_h"] + 1))
    # ranura de la junta en la cara superior de la pared
    gc, gw = GASKET["c"], GASKET["w_groove"]
    b = b.cut(shell_ring(gc - gw / 2, gc + gw / 2, GASKET["depth"] + 1, Z_PCB_TOP - GASKET["depth"]))
    return b


# ---------------------------------------------------------------- tapa
def lid():
    t = rrect(OUTS, OUTS, R_OUT, H - Z_PCB_TOP, Z_PCB_TOP).faces(">Z").edges().chamfer(1.0)
    t = t.cut(rrect(IN, IN, PCB["r"] + CL, Z_CEIL - Z_PCB_TOP, Z_PCB_TOP - 0.01))
    for (x, y) in SCREWS:
        t = t.union(cyl(x, y, Z_PCB_TOP, SCREW["post"], Z_CEIL - Z_PCB_TOP + 0.01))
        t = t.cut(cyl(x, y, Z_PCB_TOP - 0.1, SCREW["insert_d"], SCREW["insert_h"] + 0.1))
    # 4 topes cortos que sujetan la antena contra la PCB (en sus esquinas, a 0,3 de su cara superior)
    a = ANT["side"] / 2
    for sx in (-1, 1):
        for sy in (-1, 1):
            t = t.union(cyl(sx * (a - 2.0), sy * (a - 2.0), Z_PCB_TOP + ANT["h"] + 0.0, 2.0, Z_CEIL - Z_PCB_TOP - ANT["h"] + 0.01))
    return t


def gasket():
    c, w = GASKET["c"], GASKET["w"]
    return shell_ring(c - w / 2, c + w / 2, GASKET["h_free"], Z_PCB_TOP - GASKET["depth"])


# ---------------------------------------------------------------- base del casco
def _hb_common(curved):
    o = OUTS + 2 * HB["rim"] + 0.4
    z0 = -(HB["t"] + (HB["sag"] if curved else 0.0))
    hb = rrect(o, o, R_OUT + HB["rim"], HB["recess"] - z0, z0)
    # alojamiento de la cápsula: su chaflán inferior de 45° (1,2) con 0,2 de holgura; se suelta con un golpe lateral
    pocket = rrect(OUTS + 0.4, OUTS + 0.4, R_OUT + 0.2, 3.0, 0).faces("<Z").edges().chamfer(CHAMF)
    hb = hb.cut(pocket)
    hb = hb.cut(rrect(OUTS - 2 * HB["ring"], OUTS - 2 * HB["ring"], 3.0, 40, -20))      # ventana central: anillo
    if curved:   # la carcasa del casco (esfera de radio helmet_r) no puede quedar dentro de la base
        R = HB["helmet_r"]
        hb = hb.cut(cq.Workplane("XY").sphere(R).translate((0, 0, -HB["t"] - R)))
    for (x, y) in MAG["pos"]:   # imanes frente a los de la cápsula: alojamiento desde arriba, 0,3 bajo el fondo
        hb = hb.cut(cyl(x, y, -MAG["t"] - 0.3, MAG["d"] + 0.15, MAG["t"] + 0.31))
    d, t = HB["hall_mag"]       # imán del Hall bajo el DRV5032 (despierta la placa)
    hb = hb.cut(cyl(HALL_XY[0], HALL_XY[1], -t - 0.3, d + 0.15, t + 0.31))
    return hb


def helmet_base_safe():
    try:
        hb = _hb_common(True)
        if len(hb.solids().vals()) == 1:
            return hb, "cóncava R%.0f (sobre el casco)" % HB["helmet_r"]
    except Exception as e:  # noqa: BLE001
        print("base cóncava:", e)
    return _hb_common(False), "plana"


# ---------------------------------------------------------------- referencias
def refs():
    r = {}
    r["bateria"] = box(0, 0, Z_BAT0 + 0.02, BAT["x"], BAT["y"], BAT["t"] - 0.04)
    pcb = rrect(PCB["side"], PCB["side"], PCB["r"], PCB["t"], Z_F)
    for (x, y) in SCREWS:
        pcb = pcb.cut(cyl(x, y, Z_F - 1, 2.8, 4))
    r["pcb"] = pcb
    comp = None
    for ref, x0, y0, x1, y1, h in MEC["envolventes"]:
        if h <= 0:
            continue
        bx = box(-(x0 + x1) / 2, (y0 + y1) / 2, Z_F - h, x1 - x0, y1 - y0, h - 0.02)
        comp = bx if comp is None else comp.union(bx)
    r["componentes_cara_F"] = comp
    r["antena"] = box(0, 0, Z_PCB_TOP + 0.02, ANT["side"], ANT["side"], ANT["h"] - 0.04)
    py = POGO["y"]
    r["pogo_placa"] = (rrect(POGO["face_l"], POGO["face_w"], POGO["face_w"] / 2 - 0.01, POGO["face_h"], 0.02)
                       .union(rrect(POGO["f_l"], POGO["f_w"], POGO["f_w"] / 2 - 0.01, POGO["f_t"] - POGO["face_h"], POGO["face_h"] + 0.02))
                       .translate((0, py, 0)))
    m = None
    for (x, y) in MAG["pos"]:
        c = cyl(x, y, MAG["skin"] + 0.02, MAG["d"], MAG["t"])
        m = c if m is None else m.union(c)
    r["imanes_capsula"] = m
    return r


def main():
    parts = {"AVO_CASCO_V5_base": base(), "AVO_CASCO_V5_tapa": lid(), "AVO_CASCO_V5_junta_TPU": gasket()}
    hb, kind = helmet_base_safe()
    parts["AVO_CASCO_V5_base_casco"] = hb
    rf = refs()
    rep = {"piezas": {}, "interferencias": {}, "medidas": {}}
    dens = {"junta": 1.20}
    for n, s in parts.items():
        nsol = len(s.solids().vals())
        v = s.val().Volume() if nsol == 1 else sum(x.Volume() for x in s.solids().vals())
        bb = s.val().BoundingBox()
        d = 1.20 if "junta" in n else 1.27
        rep["piezas"][n] = dict(solidos=nsol, volumen_mm3=round(v, 1), peso_g=round(v * d / 1000, 1),
                                caja=[round(bb.xlen, 2), round(bb.ylen, 2), round(bb.zlen, 2)])
        cq.exporters.export(s, os.path.join(OUT, n + ".step"))
        cq.exporters.export(s, os.path.join(OUT, n + ".stl"), tolerance=0.02, angularTolerance=0.1)
    for n, s in rf.items():
        cq.exporters.export(s, os.path.join(OUT, "ref_" + n + ".stl"), tolerance=0.05)
    fixed = {k: v for k, v in parts.items() if "base_casco" not in k and "junta" not in k}
    for rn, r in rf.items():
        for pn, p in fixed.items():
            try:
                v = r.intersect(p).val().Volume()
            except Exception:  # noqa: BLE001
                v = 0.0
            if v > 0.01:
                rep["interferencias"]["%s × %s" % (rn, pn)] = round(v, 3)
    rep["medidas"] = dict(capsula_mm=[round(OUTS, 2), round(OUTS, 2), round(H, 2)], interior_mm=round(IN, 2),
                          z_cara_F=round(Z_F, 2), z_junta=round(Z_PCB_TOP, 2), z_techo=round(Z_CEIL, 2),
                          bateria_max_mm=[BAT["x"], BAT["y"], BAT["t"]], base_casco=kind,
                          altura_total_sobre_casco_mm=round(H + HB["t"] - HB["recess"], 2),
                          tornillos="4 × M2,5 × 16 (cabeza cilíndrica) + junta tórica 2,5 × 1 + inserto M2,5 Ø3,5 × 4",
                          hall_xy=[round(HALL_XY[0], 2), round(HALL_XY[1], 2)])
    asm = cq.Assembly(name="AVO_CASCO_V5")
    col = {"base": (0.12, 0.12, 0.14), "tapa": (0.85, 0.85, 0.88), "junta": (0.2, 0.2, 0.2), "base_casco": (0.8, 0.1, 0.1)}
    for n, s in parts.items():
        k = next((c for c in ("base_casco", "junta", "tapa", "base") if c in n), "base")
        asm.add(s, name=n, color=cq.Color(*col[k], 1.0))
    rc = {"pcb": (0.1, 0.45, 0.2), "antena": (0.9, 0.7, 0.1), "bateria": (0.3, 0.5, 0.8)}
    for n, s in rf.items():
        asm.add(s, name="ref_" + n, color=cq.Color(*rc.get(n, (0.8, 0.5, 0.2)), 1.0))
    asm.save(os.path.join(OUT, "AVO_CASCO_V5_CONJUNTO.step"))
    json.dump(rep, open(os.path.join(OUT, "informe.json"), "w"), ensure_ascii=False, indent=1)
    print(json.dumps(rep, ensure_ascii=False, indent=1))


if __name__ == "__main__":
    main()
