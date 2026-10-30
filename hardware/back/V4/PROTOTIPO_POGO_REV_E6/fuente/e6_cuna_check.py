# -*- coding: utf-8 -*-
"""Rev E.6: interferencias de la cuna y la base nuevas con la tapa E.5, la Heltec, el ZED, la batería, el Pololu y la clavija USB."""
import os, json
import Part
from FreeCAD import Vector as V
H = os.path.dirname(os.path.abspath(__file__)); S = os.path.join(H, "salida")
def rd(p):
    s = Part.Shape(); s.read(p); return s
def box(a, c):
    return Part.makeBox(c[0] - a[0], c[1] - a[1], c[2] - a[2], V(*a))
REF = "/home/claude/v4/ref_E41/AVO_V22H_REV_E4_1_COMPLETA/REFERENCIAS_ELECTRONICA"
inf = json.load(open(os.path.join(S, "informe_modelo_revE.json")))["RE"]
PZ = {"cuna": rd(os.path.join(S, "BREP", "AVO_RevE6_CUNA_HELTEC.brep")), "base": rd(os.path.join(S, "BREP", "AVO_RevE6_BASE_POGO.brep")),
      "tapa_E5": rd("/tmp/claude-0/e5lid/BREP/AVO_RevE_TAPA.brep"), "junta": rd(os.path.join(S, "BREP", "AVO_RevE_JUNTA_TPU.brep"))}
d = inf["DERIVADOS"]; bz0, bz1 = d["BAT_Z"]; bx0, bx1 = d["BAT_X"]; by = d["BAT_Y"]
POL = inf["POLOLU_ALOJ"]; tz1 = d["TRAY_Z"][1]
EL = {"heltec": Part.read(os.path.join(REF, "HELTEC_WIRELESS_STICK_LITE_V3.step")),
      "zed_y_L": Part.read(os.path.join(REF, "ZED_F9P_Y_ADAPTADOR_L.step")),
      "bateria_654060": box((bx0 + 0.2, -by + 0.2, bz0 + 0.02), (bx1 - 0.2, by - 0.2, bz1)),
      "pololu_S7V8F3": box((POL[0] + 0.2, POL[1] + 0.2, tz1 + 0.02), (POL[2] - 0.2, POL[3] - 0.2, tz1 + 2.54)),
      "cables_cuello_y_cola": Part.makeCompound([box((4.45, -14.4, tz1 + 0.02), (6.65, -6.6, tz1 + 1.1)), box((70.0, -15.5, tz1 + 0.02), (73.0, 12.5, tz1 + 1.05))]),
      "clavija_USB_C": box((-5.0, 7.1 - 6.2, 13.2 - 3.2), (7.3, 7.1 + 6.2, 13.2 + 3.2)),
      "cables_5xAWG30": box((19.0, -5.75, tz1 + 0.02), (60.0, -4.6, tz1 + 1.2))}
res = {"piezas": {}, "electronica": {}, "holguras": {}, "cotas": dict(BAT_Z=d["BAT_Z"], TRAY_Z=d["TRAY_Z"], MCU_Z=d.get("MCU_Z"), POLOLU=POL)}
def vol(a, b):
    try: return round(a.common(b).Volume, 3)
    except Exception as e: return "error " + str(e)[:40]
for a, b in (("cuna", "base"), ("cuna", "tapa_E5"), ("base", "tapa_E5")):
    res["piezas"][a + " / " + b] = vol(PZ[a], PZ[b])
for e, s in EL.items():
    for p in ("cuna", "base", "tapa_E5"):
        res["electronica"]["%s / %s" % (e, p)] = vol(s, PZ[p])
    res["holguras"][e] = {p: round(s.distToShape(PZ[p])[0], 3) for p in ("cuna", "tapa_E5")}
res["heltec_vs_pololu"] = vol(EL["heltec"], EL["pololu_S7V8F3"])
json.dump(res, open(os.path.join(S, "verificacion_cuna_E6.json"), "w"), indent=1, ensure_ascii=False)
print("FIN", json.dumps(res, ensure_ascii=False))
