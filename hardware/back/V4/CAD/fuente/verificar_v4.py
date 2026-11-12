# -*- coding: utf-8 -*-
"""AVO BACK V4: comprobación geométrica del conjunto (B-Rep) → salida/verificacion_v4.json
Interferencias pieza–pieza y electrónica–pieza (volumen común), holguras mínimas, cotas exteriores, grosor del conjunto,
tornillos dentro de la junta, antena sobre la tapa, imanes del soporte frente a sus insertos.
Si existe salida/REFERENCIAS/_pcb_step.brep (STEP de KiCad), la PCB y sus componentes se comprueban con él."""
import os, json, itertools, math
import FreeCAD as App, Part
from FreeCAD import Vector as V
H = os.path.dirname(os.path.abspath(__file__))
exec(open(os.path.join(H, "avo_back_v4_freecad.py"), encoding="utf-8").read().split("# ============================================================ primitivas")[0])
def rd(p):
    s = Part.Shape(); s.read(p); return s
def vcyl(x, y, r, z0, z1): return Part.makeCylinder(r, z1 - z0, V(x, y, z0), V(0, 0, 1))
def box(a, c):
    x0, x1 = sorted([a[0], c[0]]); y0, y1 = sorted([a[1], c[1]]); z0, z1 = sorted([a[2], c[2]])
    return Part.makeBox(x1 - x0, y1 - y0, z1 - z0, V(x0, y0, z0))
B = os.path.join(H, "salida", "BREP"); R = os.path.join(H, "salida", "REFERENCIAS")
NOM = dict(tapa="TAPA", base="BASE", bandeja="BANDEJA_URTK", junta="JUNTA_TPU", soporte="SOPORTE", contraplaca="CONTRAPLACA", anillos="ANILLOS_SEPARADOR")
PZ = {k: rd(os.path.join(B, "AVO_BACK_V4_%s.brep" % n)) for k, n in NOM.items()}
EL = {os.path.basename(p)[1:-5]: rd(os.path.join(R, p)) for p in sorted(os.listdir(R)) if p.endswith(".brep")}
STEP_PCB = "pcb_step" in EL
if STEP_PCB:
    EL.pop("pcb_placa", None); EL.pop("pcb_componentes", None)
def vol(a, b):
    try: return round(a.common(b).Volume, 3)
    except Exception as ex: return "error " + str(ex)[:40]
def dist(a, b):
    try: return round(a.distToShape(b)[0], 3)
    except Exception: return None
ESPERADO = {("tapa", "junta"): "compresión de la junta por el labio (previsto)", ("base", "junta"): "junta en su ranura (previsto)"}
RES = {"pcb_fuente": "STEP de KiCad" if STEP_PCB else "placa + envolventes (patio × altura) del generador",
       "piezas_entre_si": {}, "electronica_vs_piezas": {}, "electronica_entre_si": {}, "holguras_minimas": {}}
for a, b in itertools.combinations(PZ, 2):
    v = vol(PZ[a], PZ[b])
    RES["piezas_entre_si"]["%s / %s" % (a, b)] = dict(volumen_comun_mm3=v, distancia_min_mm=dist(PZ[a], PZ[b]), nota=ESPERADO.get((a, b), ""))
OK_EL = {("imanes_soporte", "soporte"), ("imanes_capsula", "base")}
for e, s in EL.items():
    for p in PZ:
        if (e, p) in OK_EL: continue
        v = vol(s, PZ[p])
        if isinstance(v, str) or v > 1e-3: RES["electronica_vs_piezas"]["%s / %s" % (e, p)] = v
    RES["holguras_minimas"][e] = {p: dist(s, PZ[p]) for p in ("tapa", "base", "bandeja", "anillos")}
CONTACTO = {("urtk_J2_SMA", "urtk_pcb"), ("L_tuerca_y_cuerpo_hex", "urtk_J2_SMA"), ("L_cuerpo", "L_tuerca_y_cuerpo_hex"), ("L_cuerpo", "L_rosca_hembra"),
            ("pcb_componentes", "pcb_placa"), ("pcb_placa", "pcb_componentes"), ("urtk_modulo_ZED", "urtk_pcb"), ("urtk_J1_USBC_estimado", "urtk_pcb"),
            ("urtk_J3_GH6_estimado", "urtk_pcb"), ("L_rosca_hembra", "antena_GNSS_Q39")}
for a, b in itertools.combinations(EL, 2):
    if (a, b) in CONTACTO or (b, a) in CONTACTO: continue
    v = vol(EL[a], EL[b])
    if isinstance(v, str) or v > 1e-3: RES["electronica_entre_si"]["%s / %s" % (a, b)] = v
RES["imanes_en_alojamiento"] = dict(capsula=vol(EL["imanes_capsula"], PZ["base"]), soporte=vol(EL["imanes_soporte"], PZ["soporte"]))
J = PZ["junta"]
RES["tornillos_dentro_de_la_junta"] = {"S%d" % (i + 1): round(Part.makeCylinder(RE["ORING_CB_D"] / 2, 3, V(x, y, 0)).distToShape(J)[0], 3) for i, (x, y) in enumerate(SCREWS)}
# imanes del soporte frente a los insertos de la contraplaca (Ø4,0) y entre sí
ins = [vcyl(x, y, RE["INS_SUP"][0] / 2, -RE["MT"], -RE["MT"] + RE["INS_SUP"][1]) for x, y in RE["SUP_SCREWS"]]
mg = [vcyl(x, y, (RE["MAG"][0] + RE["MAG_CLR"]) / 2, -RE["MAG"][1] - 0.05, 1) for x, y in list(RE["MAGS"]) + list(RE["REED_MAGS"])]
RES["imanes_soporte_vs_insertos_min_mm"] = round(min(a.distToShape(b)[0] for a in ins for b in mg), 3)
OB = {k: s.optimalBoundingBox() for k, s in PZ.items()}
ant = EL["antena_GNSS_Q39"]
top = PZ["tapa"].common(box((-5, -40, RE["TOP_Z"] - 0.01), (L + 5, 40, RE["TOP_Z"] + 0.01)))
RES["cotas"] = dict(capsula_largo=round(OB["base"].XMax - OB["base"].XMin, 3), capsula_ancho=round(OB["base"].YMax - OB["base"].YMin, 3),
                    capsula_alto=round(OB["tapa"].ZMax - OB["base"].ZMin, 3),
                    conjunto_Zmin=round(min(b.ZMin for b in OB.values()), 3), conjunto_Zmax_sin_antena=round(max(b.ZMax for b in OB.values()), 3),
                    grosor_conjunto_sin_antena=round(max(b.ZMax for b in OB.values()) - min(b.ZMin for b in OB.values()), 3),
                    antena_Zmax=round(ant.BoundBox.ZMax, 3), rosca_SMA_sobre_tapa=round(L_TIP - RE["TOP_Z"], 3),
                    antena_X=[round(ant.BoundBox.XMin, 3), round(ant.BoundBox.XMax, 3)],
                    techo_plano_X=[round(top.BoundBox.XMin, 3), round(top.BoundBox.XMax, 3)],
                    antena_dentro_del_techo_plano=bool(ant.BoundBox.XMax <= top.BoundBox.XMax + 1e-6 and ant.BoundBox.YMax <= top.BoundBox.YMax + 1e-6))
RES["volumenes_mm3"] = {k: round(s.Volume, 1) for k, s in PZ.items()}
RES["volumen_exterior_capsula_mm3"] = round(PZ["tapa"].fuse(PZ["base"]).fuse(rd(os.path.join(B, "_aux_CAV.brep")).common(box((-5, -40, 0), (L + 5, 40, RE["TOP_Z"])))).Volume, 1) if False else None
OUTER = rd(os.path.join(B, "_aux_OUTER.brep"))
RES["volumen_exterior_capsula_mm3"] = round(OUTER.Volume, 1)
CAVs = rd(os.path.join(B, "_aux_CAV.brep")).common(OUTER)
RES["volumen_interior_mm3"] = round(CAVs.Volume, 1)
fallos = [k for k, v in RES["electronica_vs_piezas"].items()] + list(RES["electronica_entre_si"].keys()) + \
         [k for k, v in RES["piezas_entre_si"].items() if (isinstance(v["volumen_comun_mm3"], str) or v["volumen_comun_mm3"] > 1e-3) and not v["nota"]]
RES["interferencias_no_previstas"] = fallos
json.dump(RES, open(os.path.join(H, "salida", "verificacion_v4.json"), "w"), indent=1, ensure_ascii=False)
print(json.dumps({k: RES[k] for k in ("pcb_fuente", "interferencias_no_previstas", "cotas", "tornillos_dentro_de_la_junta", "imanes_soporte_vs_insertos_min_mm")}, indent=1, ensure_ascii=False))
print("holguras", json.dumps(RES["holguras_minimas"], ensure_ascii=False))
