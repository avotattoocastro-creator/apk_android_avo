# -*- coding: utf-8 -*-
"""AVO BACK V4: comprobación rápida del STEP de KiCad (salida/REFERENCIAS/_pcb_step.brep, ya en Z de montaje) contra las
piezas de la carcasa y la electrónica vecina. Sólido a sólido con prefiltro de caja → salida/verificacion_pcb_step_v4.json"""
import os, json
import Part
H = os.path.dirname(os.path.abspath(__file__))
B = os.path.join(H, "salida", "BREP"); R = os.path.join(H, "salida", "REFERENCIAS")


def rd(p):
    s = Part.Shape(); s.read(p); return s


PZ = {k: rd(os.path.join(B, "AVO_BACK_V4_%s.brep" % n)) for k, n in
      dict(tapa="TAPA", base="BASE", bandeja="BANDEJA_URTK", anillos="ANILLOS_SEPARADOR", junta="JUNTA_TPU").items()}
for e in ("bateria_654060", "qi_bobina", "urtk_pcb", "urtk_modulo_ZED", "urtk_J1_USBC_estimado", "urtk_J3_GH6_estimado",
          "urtk_J2_SMA", "L_cuerpo", "L_tuerca_y_cuerpo_hex", "antena_FPC_2G4"):
    p = os.path.join(R, "_%s.brep" % e)
    if os.path.exists(p):
        PZ[e] = rd(p)
S = rd(os.path.join(R, "_pcb_step.brep"))
sol = S.Solids
res = dict(solidos_step=len(sol), interferencias={}, holgura_min_mm={},
           nota="Sólidos del STEP de KiCad (placa + modelos 3D disponibles) desplazados a Z = PCB_Z (2,5 mm). Sin modelo 3D "
                "en el STEP: USB-C, JST SH, RHL-20 y VQFN-16 (comprobados con las envolventes del generador).")
for k, p in PZ.items():
    pb = p.BoundBox
    dmin = None
    vtot = 0.0
    for s in sol:
        sb = s.BoundBox
        if not sb.isValid():
            continue
        if pb.intersect(sb):
            try:
                v = s.common(p).Volume
            except Exception:
                v = 0.0
            if v > 1e-3:
                vtot += v
        near = (sb.XMin - 3 < pb.XMax and sb.XMax + 3 > pb.XMin and sb.YMin - 3 < pb.YMax and sb.YMax + 3 > pb.YMin
                and sb.ZMin - 3 < pb.ZMax and sb.ZMax + 3 > pb.ZMin)
        if near:
            try:
                d = s.distToShape(p)[0]
            except Exception:
                d = None
            if d is not None and (dmin is None or d < dmin):
                dmin = d
    if vtot > 1e-3:
        res["interferencias"][k] = round(vtot, 3)
    res["holgura_min_mm"][k] = None if dmin is None else round(dmin, 3)
    print(k, res["holgura_min_mm"][k], res["interferencias"].get(k, 0), flush=True)
json.dump(res, open(os.path.join(H, "salida", "verificacion_pcb_step_v4.json"), "w"), indent=1, ensure_ascii=False)
print("FIN", json.dumps(res, ensure_ascii=False))
