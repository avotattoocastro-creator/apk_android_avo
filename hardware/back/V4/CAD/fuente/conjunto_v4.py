# -*- coding: utf-8 -*-
"""AVO BACK V4: conjunto montado y explosionado en STEP, con las piezas y la electrónica (referencias o el STEP de la
PCB de KiCad si está en salida/REFERENCIAS/_pcb_step.brep). Solo para ver: las piezas para imprimir son los STEP sueltos."""
import os
import FreeCAD as App, Part, Import
from FreeCAD import Vector as V
H = os.path.dirname(os.path.abspath(__file__)); S = os.path.join(H, "salida")
def rd(p):
    s = Part.Shape(); s.read(p); return s
P = {n: rd(os.path.join(S, "BREP", "AVO_BACK_V4_%s.brep" % n)) for n in ("TAPA", "BASE", "BANDEJA_URTK", "JUNTA_TPU", "SOPORTE", "CONTRAPLACA", "ANILLOS_SEPARADOR")}
R = {os.path.basename(p)[1:-5]: rd(os.path.join(S, "REFERENCIAS", p)) for p in os.listdir(os.path.join(S, "REFERENCIAS")) if p.endswith(".brep")}
if "pcb_step" in R:
    R.pop("pcb_placa", None); R.pop("pcb_componentes", None)
EXPL = {"TAPA": 62, "JUNTA_TPU": 50, "ANILLOS_SEPARADOR": 22, "BANDEJA_URTK": 20, "BASE": 0, "SOPORTE": -22, "CONTRAPLACA": -40}
EXPL_R = {"antena_GNSS_Q39": 95, "antena_FPC_2G4": 55, "pcb_step": 12, "pcb_placa": 12, "pcb_componentes": 12, "bateria_654060": 6, "contactos_M2": -8, "juntas_contactos": 4, "pines_pogo_soporte": -22,
          "imanes_soporte": -22, "imanes_capsula": 0}
for k in R:
    if k.startswith("urtk") or k.startswith("L_"): EXPL_R[k] = 34
OUT = os.path.join(S, "STEP_SHAPR3D"); os.makedirs(OUT, exist_ok=True)
for nombre, desp in (("MONTADO_CON_ELECTRONICA", False), ("EXPLOSIONADO", True)):
    doc = App.newDocument(nombre); objs = []
    for k, s in list(P.items()) + list(R.items()):
        s = s.copy()
        if desp: s.translate(V(0, 0, EXPL.get(k, EXPL_R.get(k, 0))))
        o = doc.addObject("Part::Feature", k); o.Shape = s; o.Label = k; objs.append(o)
    Import.export(objs, os.path.join(OUT, "AVO_BACK_V4_CONJUNTO_%s.step" % nombre))
    App.closeDocument(doc.Name)
print("ok")
