"""Auditoría de la placa REV B con la API de KiCad 9 (pcbnew), dentro del contenedor kicad/kicad:9.0.

Uso: python3 kicad_audit.py placa.kicad_pcb netlist_esquema.net salida_dir
Comprueba y escribe salida_dir/auditoria_placa.json + auditoria_redes.csv:
 - contorno (Edge.Cuts), grosor, capas de cobre, textos de revisión, valor de U4;
 - por red: pads, pistas (longitud, ancho mín/máx por capa), vías, zonas;
 - anchos mínimos de las redes de potencia; redes con un solo pad que no son «unconnected-…»;
 - zonas: red, capa, área rellenada, espesor mínimo;
 - vías: diámetro y taladro (anillo mínimo);
 - correspondencia red a red, pad a pad, entre la netlist del esquema (kicad-cli) y la placa.
"""
import csv
import json
import os
import re
import sys
from collections import defaultdict

import pcbnew

pcb_path, net_path, out = sys.argv[1], sys.argv[2], sys.argv[3]
os.makedirs(out, exist_ok=True)
b = pcbnew.LoadBoard(pcb_path)
mm = pcbnew.ToMM
R = dict(fichero=os.path.basename(pcb_path), problemas=[])

# ---------------------------------------------------------------- contorno, capas, grosor, textos
bbox = b.GetBoardEdgesBoundingBox()
R["contorno_mm"] = dict(ancho=round(mm(bbox.GetWidth()), 3), alto=round(mm(bbox.GetHeight()), 3))
ds = b.GetDesignSettings()
R["grosor_mm"] = round(mm(ds.GetBoardThickness()), 3)
R["capas_cobre"] = b.GetCopperLayerCount()
texts = [d.GetText() for d in b.GetDrawings() if isinstance(d, pcbnew.PCB_TEXT)]
R["textos"] = texts
R["es_rev_b"] = any("REV B" in t for t in texts) and any("ESP32-C3" in t for t in texts)
fps = {f.GetReference(): f for f in b.GetFootprints()}
R["cajetin_revision"] = b.GetTitleBlock().GetRevision()
if R["cajetin_revision"] != "B":
    R["problemas"].append("el cajetín de la placa dice revisión «%s» (los Gerber llevan esa revisión en TF.ProjectId)"
                          % R["cajetin_revision"])
R["huellas"] = len(fps)
R["U4"] = fps["U4"].GetValue() if "U4" in fps else None
if not R["es_rev_b"] or R["U4"] != "ESP32-C3-MINI-1U-N4":
    R["problemas"].append("la placa no se identifica como REV B / ESP32-C3")

# ---------------------------------------------------------------- reglas (para comparar)
R["reglas"] = dict(pista_min=mm(ds.m_TrackMinWidth), separacion_min=mm(ds.m_MinClearance),
                   via_min=mm(ds.m_ViasMinSize), taladro_min=mm(ds.m_MinThroughDrill),
                   borde=mm(ds.m_CopperEdgeClearance), anillo_min=mm(ds.m_ViasMinAnnularWidth))

# ---------------------------------------------------------------- redes
nets = defaultdict(lambda: dict(pads=[], pistas=0, longitud_mm=0.0, anchos=set(), vias=0, capas=set(), zonas=[]))
for ref, f in fps.items():
    for p in f.Pads():
        nets[p.GetNetname()]["pads"].append("%s.%s" % (ref, p.GetNumber()))
for t in b.GetTracks():
    n = nets[t.GetNetname()]
    if isinstance(t, pcbnew.PCB_VIA):
        n["vias"] += 1
        continue
    n["pistas"] += 1
    n["longitud_mm"] += mm(t.GetLength())
    n["anchos"].add(round(mm(t.GetWidth()), 3))
    n["capas"].add(b.GetLayerName(t.GetLayer()))
zon = []
for z in b.Zones():
    if z.GetIsRuleArea():
        continue
    area = z.GetFilledArea() / 1e12 if hasattr(z, "GetFilledArea") else None
    item = dict(red=z.GetNetname(), capa=b.GetLayerName(z.GetFirstLayer()), area_mm2=round(area, 1) if area else 0,
                espesor_min=mm(z.GetMinThickness()), separacion=mm(z.GetLocalClearance() or 0))
    zon.append(item)
    nets[z.GetNetname()]["zonas"].append(item["capa"])
R["zonas"] = zon

POWER = {"VBAT": 0.3, "VSYS": 0.3, "VIN5": 0.3, "VBUS": 0.3, "BAT_RAW": 0.3, "QI_RECT": 0.3, "QI_AC1": 0.3,
         "QI_AC2": 0.3, "QI_COIL1": 0.3}
rows = []
for name, n in sorted(nets.items()):
    if not name:
        continue
    single = len(n["pads"]) == 1 and not name.startswith("unconnected-")
    wmin = min(n["anchos"]) if n["anchos"] else None
    flag = []
    if single:
        flag.append("un solo pad")
    if name in POWER and wmin is not None and wmin < POWER[name] - 1e-6:
        flag.append("pista de potencia de %.2f mm < %.2f" % (wmin, POWER[name]))
    rows.append(dict(red=name, pads=len(n["pads"]), lista_pads=" ".join(sorted(n["pads"])), pistas=n["pistas"],
                     longitud_mm=round(n["longitud_mm"], 1), ancho_min=wmin,
                     ancho_max=max(n["anchos"]) if n["anchos"] else None, vias=n["vias"],
                     capas=" ".join(sorted(n["capas"])), zonas=" ".join(n["zonas"]), aviso="; ".join(flag)))
    for fl in flag:
        R["problemas"].append("%s: %s" % (name, fl))
with open(os.path.join(out, "auditoria_redes.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
    w.writeheader(); w.writerows(rows)
R["redes"] = len(rows)
R["redes_sin_conectar_nc"] = sum(1 for r in rows if r["red"].startswith("unconnected-"))

# ---------------------------------------------------------------- vías
vias = [t for t in b.GetTracks() if isinstance(t, pcbnew.PCB_VIA)]
if vias:
    sizes = sorted({(round(mm(v.GetWidth(pcbnew.F_Cu)), 3), round(mm(v.GetDrillValue()), 3)) for v in vias})
    R["vias"] = dict(total=len(vias), tipos=sizes,
                     anillo_min=round(min((mm(v.GetWidth(pcbnew.F_Cu)) - mm(v.GetDrillValue())) / 2 for v in vias), 3))

# ---------------------------------------------------------------- esquema ↔ placa, pad a pad
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "fuente"))
from sexpr import parse, find, find_all   # noqa: E402  (mismo analizador que genera los ficheros)
sch = defaultdict(set)
tree = parse(open(net_path, encoding="utf-8").read())
for net in find_all(find(tree, "nets"), "net"):
    name = str(find(net, "name")[1]).lstrip("/")
    for node in find_all(net, "node"):
        sch[name].add("%s.%s" % (find(node, "ref")[1], find(node, "pin")[1]))
pcbmap = {}
for name, n in nets.items():
    for pad in n["pads"]:
        pcbmap[pad] = name
schmap = {pad: name for name, pads in sch.items() for pad in pads}
diff = []
for pad, name in schmap.items():
    if pad not in pcbmap:
        diff.append("%s en el esquema (%s) no está en la placa" % (pad, name))
    elif pcbmap[pad].lstrip("/") != name:
        diff.append("%s: esquema %s ≠ placa %s" % (pad, name, pcbmap[pad]))
for pad, name in pcbmap.items():
    ref = pad.split(".")[0]
    if pad not in schmap and name and not ref.startswith("TP") and not name.startswith("unconnected-"):
        # pads repetidos de una misma patilla (EP de la QFN, patas del USB-C) comparten número: ya cubiertos
        if pad.split(".")[0] + "." + pad.split(".")[1] not in schmap:
            diff.append("%s (%s) en la placa no está en el esquema" % (pad, name))
R["esquema_pads"] = len(schmap)
R["placa_pads"] = len(pcbmap)
R["diferencias_esquema_placa"] = diff[:200]
R["n_diferencias_esquema_placa"] = len(diff)
if diff:
    R["problemas"].append("%d diferencias pad a pad entre esquema y placa" % len(diff))

json.dump(R, open(os.path.join(out, "auditoria_placa.json"), "w"), indent=1, ensure_ascii=False, default=list)
print(json.dumps({k: v for k, v in R.items() if k not in ("textos", "zonas", "diferencias_esquema_placa")}, indent=1,
                 ensure_ascii=False, default=list))
