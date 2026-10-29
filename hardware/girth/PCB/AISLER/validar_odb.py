"""Valida el ODB++ exportado por KiCad para AISLER, leyendo el ZIP tal cual (sin KiCad).

Comprueba: estructura (matrix, profile, capas), 4 capas de cobre, contorno 65,5 × 43,5 mm, taladros (vías y PTH/NPTH),
componentes (cuántos, cuáles NO_POP, tipo de montaje, propiedades) y que cada posición y giro coinciden con la placa
REV B (copia KiCad) y con el CPL entregado de JLCPCB.

Uso: validar_odb.py <odb.zip> <posiciones_kicad_copia.csv> <cpl_jlcpcb.csv> <salida_dir>
Escribe: validacion_odb.json, validacion_odb.md, componentes_odb.csv. Código de salida 1 si algo falla.
"""
import csv
import json
import math
import os
import re
import sys
import zipfile
from collections import Counter, defaultdict

ZIP, POS, CPL, OUT = sys.argv[1:5]
os.makedirs(OUT, exist_ok=True)
NO_MONTAR = {"C5"} | {"TP%d" % i for i in range(1, 9)} | {"L1", "L2", "SW1", "SW2"}
z = zipfile.ZipFile(ZIP)
names = z.namelist()
R = dict(fichero=os.path.basename(ZIP), bytes=os.path.getsize(ZIP), entradas=len(names), problemas=[], avisos=[])


def fail(m):
    R["problemas"].append(m)


def rd(n):
    return z.read(n).decode("utf-8", "replace")


# ------------------------------------------------------------------ raíz del trabajo ODB++
mats = [n for n in names if n.endswith("matrix/matrix")]
if len(mats) != 1:
    fail("no hay exactamente un matrix/matrix (%d)" % len(mats))
    root = ""
else:
    root = mats[0][:-len("matrix/matrix")]
R["raiz"] = root or "(raíz del ZIP)"
steps = sorted({n[len(root):].split("/")[1] for n in names if n.startswith(root + "steps/") and n.count("/") > len(root.split("/"))})
R["steps"] = steps
step = steps[0] if steps else None
SP = root + "steps/%s/" % step
for need in ("misc/info", "matrix/matrix"):
    if root + need not in names:
        fail("falta %s" % need)

# ------------------------------------------------------------------ matrix: capas
matrix = rd(mats[0]) if mats else ""
layers = []
for blk in re.findall(r"LAYER\s*\{(.*?)\}", matrix, re.S):
    d = dict(re.findall(r"^\s*([A-Z_]+)=(.*?)\s*$", blk, re.M))
    layers.append(d)
R["capas"] = [dict(fila=int(d.get("ROW", 0)), nombre=d.get("NAME"), tipo=d.get("TYPE"), contexto=d.get("CONTEXT"),
                   polaridad=d.get("POLARITY"), desde=d.get("START_NAME", ""), hasta=d.get("END_NAME", "")) for d in layers]
cu = [d for d in layers if d.get("TYPE") in ("SIGNAL", "POWER_GROUND", "MIXED") and d.get("CONTEXT") == "BOARD"]
R["capas_cobre"] = [d["NAME"] for d in cu]
if len(cu) != 4:
    fail("se esperaban 4 capas de cobre y hay %d" % len(cu))
R["tipos_de_capa"] = dict(Counter(d.get("TYPE") for d in layers if d.get("CONTEXT") == "BOARD"))
for tp in ("SOLDER_MASK", "SILK_SCREEN", "SOLDER_PASTE", "DRILL", "COMPONENT"):
    if not R["tipos_de_capa"].get(tp):
        fail("no hay capa de tipo %s" % tp)

# ------------------------------------------------------------------ features por capa
NUM = r"-?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?"


def features(layer):
    p = SP + "layers/%s/features" % layer.lower()      # en matrix van en mayúsculas; las carpetas, en minúsculas
    if p not in names:
        return None
    t = rd(p)
    syms = {}
    for m in re.finditer(r"^\$(\d+)\s+(\S+)", t, re.M):
        syms[int(m.group(1))] = m.group(2)
    cnt = Counter()
    pads = []
    for line in t.splitlines():
        if not line or line[0] not in "PLASTB":
            continue
        k = line.split()[0]
        cnt[k] += 1
        if k == "P":
            f = line.split()
            pads.append((float(f[1]), float(f[2]), syms.get(int(f[3]), f[3])))
    unidades = re.search(r"^UNITS=(\w+)", t, re.M)
    return dict(cuenta=dict(cnt), pads=pads, unidades=unidades.group(1) if unidades else None, simbolos=len(syms))


R["features"] = {}
for d in layers:
    if d.get("CONTEXT") != "BOARD":
        continue
    f = features(d["NAME"])
    if f is None:
        if d.get("TYPE") != "COMPONENT":
            fail("la capa %s no tiene fichero features" % d["NAME"])
        continue
    R["features"][d["NAME"]] = dict(tipo=d.get("TYPE"), unidades=f["unidades"], **{"n_" + k: v for k, v in f["cuenta"].items()})
    if d.get("TYPE") in ("SIGNAL", "POWER_GROUND", "SOLDER_MASK", "SILK_SCREEN") and sum(f["cuenta"].values()) == 0:
        fail("la capa %s está vacía" % d["NAME"])
    if d.get("TYPE") == "DRILL":
        diam = Counter()
        for x, y, s in f["pads"]:
            m = re.match(r"r(" + NUM + ")", s)
            diam[round(float(m.group(1)), 1) if m else s] += 1
        R["features"][d["NAME"]]["taladros_por_simbolo"] = {str(k): v for k, v in sorted(diam.items(), key=lambda kv: str(kv[0]))}

drills = [d for d in layers if d.get("TYPE") == "DRILL" and d.get("CONTEXT") == "BOARD"]
n_drill = {d["NAME"]: R["features"].get(d["NAME"], {}).get("n_P", 0) for d in drills}
R["taladros"] = n_drill
tot_drill = sum(n_drill.values())
# esperado de la placa: 164 vías + 4 pads de hilo (PTH) + 2 NPTH de J1 (USB-C) + PTH de J1 si los hubiera
R["taladros_total"] = tot_drill

# ------------------------------------------------------------------ profile (contorno)
prof = SP + "profile"
if prof in names:
    t = rd(prof)
    xs, ys = [], []
    for line in t.splitlines():
        f = line.split()
        if f and f[0] in ("OB", "OS"):
            xs.append(float(f[1])); ys.append(float(f[2]))
        elif f and f[0] == "OC":
            xs += [float(f[1])]; ys += [float(f[2])]
    if xs:
        w, h = max(xs) - min(xs), max(ys) - min(ys)
        R["contorno_mm"] = dict(ancho=round(w, 3), alto=round(h, 3), xmin=round(min(xs), 3), ymin=round(min(ys), 3))
        if abs(w - 65.5) > 0.05 or abs(h - 43.5) > 0.05:
            fail("contorno %.3f × %.3f mm (esperado 65,5 × 43,5)" % (w, h))
    else:
        fail("profile sin contorno")
else:
    fail("falta steps/%s/profile" % step)

# ------------------------------------------------------------------ componentes
comp_layers = [d["NAME"] for d in layers if d.get("TYPE") == "COMPONENT"]
R["capas_componentes"] = comp_layers
comps = []
for cl in comp_layers:
    p = SP + "layers/%s/components" % cl.lower()
    if p not in names:
        continue
    t = rd(p)
    attr_names = {int(m.group(1)): m.group(2) for m in re.finditer(r"^@(\d+)\s+(\S+)", t, re.M)}
    attr_texts = {int(m.group(1)): m.group(2) for m in re.finditer(r"^&(\d+)\s+(.+)$", t, re.M)}
    cur = None
    for line in t.splitlines():
        if line.startswith("CMP "):
            head, _, at = line.partition(";")
            f = head.split()
            cur = dict(capa=cl, pkg=int(f[1]), x=float(f[2]), y=float(f[3]), giro=float(f[4]), espejo=f[5],
                       ref=f[6], parte=f[7] if len(f) > 7 else "", attrs={}, props={})
            for a in filter(None, at.strip().split(",")):
                k, _, v = a.partition("=")
                nm = attr_names.get(int(k), "@" + k)
                if nm == ".comp_mount_type" and v.isdigit():      # opciones en el orden de KiCad (odb_attribute.h)
                    cur["attrs"][nm] = ["other", "smt", "thmt", "pressfit"][int(v)]
                else:
                    cur["attrs"][nm] = attr_texts.get(int(v), v) if v.isdigit() else (v or True)
            comps.append(cur)
        elif line.startswith("PRP ") and cur is not None:
            m = re.match(r"PRP\s+(\S+)\s+'(.*)'", line)
            if m:
                cur["props"][m.group(1)] = m.group(2)
    R.setdefault("atributos_definidos", {})[cl] = attr_names

R["componentes_total"] = len(comps)


def no_pop(c):
    v = c["attrs"].get(".no_pop")
    return v is not None and str(v) not in ("0", "False", "false")


pop = [c for c in comps if not no_pop(c)]
nop = [c for c in comps if no_pop(c)]
R["componentes_para_montar"] = len(pop)
R["componentes_no_pop"] = sorted(c["ref"] for c in nop)
R["tipo_de_montaje"] = dict(Counter(str(c["attrs"].get(".comp_mount_type", "?")) for c in pop))
R["capa_componentes_montar"] = dict(Counter(c["capa"] for c in pop))
if len(comps) != 98:
    fail("el ODB++ tiene %d componentes (la placa tiene 98 huellas)" % len(comps))
if len(pop) != 85:
    fail("componentes para montar: %d (esperados 85)" % len(pop))
if set(R["componentes_no_pop"]) != NO_MONTAR:
    fail("NO_POP = %s (esperado %s)" % (R["componentes_no_pop"], sorted(NO_MONTAR)))
if "C5" not in R["componentes_no_pop"]:
    fail("C5 no está marcado NO_POP")
bad_mt = [c["ref"] for c in pop if str(c["attrs"].get(".comp_mount_type", "")).lower() not in ("smt", "smd", "mt_smd")]
if bad_mt:
    fail("componentes para montar que no son SMT: %s" % bad_mt)
dup = [k for k, v in Counter(c["ref"] for c in comps).items() if v > 1]
if dup:
    fail("referencias repetidas: %s" % dup)

# ------------------------------------------------------------------ posiciones frente a la placa REV B y el CPL
kic = {r["ref"]: r for r in csv.DictReader(open(POS, encoding="utf-8"))}
cpl = {r["Designator"]: r for r in csv.DictReader(open(CPL, encoding="utf-8"))}
# transformación KiCad → ODB++ deducida de los datos (desplazamiento constante; y invertida o no; giro CCW o CW)
pairs = [(c, kic[c["ref"]]) for c in comps if c["ref"] in kic]
best = None
for sy in (1, -1):
    for sr in (1, -1):
        dx = [c["x"] - float(k["x_mm"]) for c, k in pairs]
        dy = [c["y"] - sy * float(k["y_mm"]) for c, k in pairs]
        ox, oy = sorted(dx)[len(dx) // 2], sorted(dy)[len(dy) // 2]
        err = [math.hypot(a - ox, b - oy) for a, b in zip(dx, dy)]
        rot_ok = sum(1 for c, k in pairs if abs(((c["giro"] - sr * float(k["giro"])) + 180) % 360 - 180) < 0.01)
        sc = (max(err), -rot_ok)
        if best is None or sc < best[0]:
            best = (sc, sy, sr, ox, oy, err, rot_ok)
(_, sy, sr, ox, oy, err, rot_ok) = best
R["transformacion"] = dict(x_odb="x_kicad %+.4f" % ox, y_odb="%sy_kicad %+.4f" % ("" if sy == 1 else "−", oy),
                           giro_odb="%sgiro_kicad" % ("" if sr == 1 else "−"))
R["transformacion_num"] = dict(ox=ox, oy=oy, sy=sy, sr=sr)
R["posicion_error_max_mm"] = round(max(err), 6)
R["giros_coinciden"] = "%d/%d" % (rot_ok, len(pairs))
if len(pairs) != len(comps) or len(kic) != len(comps):
    fail("referencias distintas entre ODB++ (%d) y la placa (%d)" % (len(comps), len(kic)))
if max(err) > 0.001:
    fail("posiciones distintas de la placa: error máx. %.4f mm" % max(err))
if rot_ok != len(pairs):
    fail("giros que no coinciden: %d de %d" % (len(pairs) - rot_ok, len(pairs)))
# frente al CPL de JLCPCB (Mid X, Mid Y en mm con y negada; giro de KiCad sin correcciones)
cpl_err, cpl_rot = [], 0
for c in pop:
    r = cpl.get(c["ref"])
    if not r:
        fail("%s se monta según el ODB++ pero no está en el CPL entregado" % c["ref"]); continue
    xk, yk = float(r["Mid X"].replace("mm", "")), -float(r["Mid Y"].replace("mm", ""))
    cpl_err.append(math.hypot(c["x"] - (xk + ox), c["y"] - (sy * yk + oy)))
    cpl_rot += abs(((c["giro"] - sr * float(r["Rotation"])) + 180) % 360 - 180) < 0.01
extra = sorted(set(cpl) - {c["ref"] for c in pop})
R["cpl"] = dict(filas=len(cpl), en_odb_para_montar=len(cpl_err), error_max_mm=round(max(cpl_err), 6) if cpl_err else None,
                giros_iguales=cpl_rot, en_cpl_no_montados_en_odb=extra)
if extra:
    fail("en el CPL pero NO_POP o ausentes en el ODB++: %s" % extra)
if cpl_err and max(cpl_err) > 0.001:
    fail("posiciones distintas del CPL entregado: %.4f mm" % max(cpl_err))

# propiedades útiles para la lista de materiales de AISLER
R["propiedades"] = dict(Counter(k for c in pop for k in c["props"]))
sin_mpn = [c["ref"] for c in pop if not c["props"].get("MPN")]
# MPN y fabricante frente a la pieza LCSC de la BOM (datos de JLCPCB): deben coincidir en las 85 piezas montadas
_lc = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "lcsc_piezas_2026-10-29.json"),
                     encoding="utf-8"))["parts"]
mpn_mal = [c["ref"] for c in pop if _lc.get(c["props"].get("LCSC", ""), {}).get("mpn", "").replace('"', "'") != c["props"].get("MPN")]
sin_fab = [c["ref"] for c in pop if not c["props"].get("Manufacturer")]
R["mpn_frente_a_lcsc"] = dict(distintos=mpn_mal, sin_fabricante=sin_fab)
if mpn_mal or sin_fab:
    fail("MPN/fabricante no coinciden con la pieza LCSC de la BOM en %s / sin fabricante en %s" % (mpn_mal, sin_fab))
mpn_es_valor = sorted(c["ref"] for c in pop if c["props"].get("MPN") and c["props"].get("MPN") == c["props"].get("Value"))
R["mpn"] = dict(sin_mpn=sin_mpn, mpn_igual_al_valor=len(mpn_es_valor), ejemplos=mpn_es_valor[:12])
if mpn_es_valor:
    R["avisos"].append("%d piezas montadas llevan en MPN el valor (p. ej. «100n»), no un número de fabricante: AISLER "
                       "las tendrá que emparejar por valor/huella en su herramienta de BOM" % len(mpn_es_valor))
R["avisos"].append("El ODB++ no lleva espesor ni acabado: 1,0 mm y ENIG se eligen en el pedido de AISLER")

# paquetes y nets (eda/data, netlist)
eda = SP + "eda/data"
if eda in names:
    t = rd(eda)
    R["eda_paquetes"] = len(re.findall(r"^PKG ", t, re.M))
    R["eda_redes"] = len(re.findall(r"^NET ", t, re.M))
else:
    fail("falta eda/data")
nl = [n for n in names if n.startswith(SP + "netlists/") and n.endswith("/netlist")]
R["netlist"] = nl[0][len(SP):] if nl else None
if not nl:
    R["avisos"].append("no hay netlist en el ODB++")
R["texto_espesor"] = [n for n in names if "thick" in rd(n).lower()][:5] if len(names) < 400 else "no buscado"

# ------------------------------------------------------------------ salida
with open(os.path.join(OUT, "componentes_odb.csv"), "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["ref", "capa", "x_mm", "y_mm", "giro", "no_pop", "montaje", "Value", "MPN", "Manufacturer", "LCSC", "paquete"])
    for c in sorted(comps, key=lambda c: (re.sub(r"\d", "", c["ref"]), int(re.sub(r"\D", "", c["ref"]) or 0))):
        w.writerow([c["ref"], c["capa"], c["x"], c["y"], c["giro"], no_pop(c), c["attrs"].get(".comp_mount_type", ""),
                    c["props"].get("Value", ""), c["props"].get("MPN", ""), c["props"].get("Manufacturer", ""),
                    c["props"].get("LCSC", ""), c["parte"]])
R["resultado"] = "VÁLIDO" if not R["problemas"] else "CON PROBLEMAS"
json.dump(R, open(os.path.join(OUT, "validacion_odb.json"), "w", encoding="utf-8"), indent=1, ensure_ascii=False)
L = ["# Validación del ODB++ para AISLER — %s" % R["resultado"], "",
     "- Fichero: `%s` (%d B, %d entradas), raíz `%s`, step `%s`" % (R["fichero"], R["bytes"], R["entradas"], R["raiz"], step),
     "- Capas de cobre: %s" % ", ".join(R["capas_cobre"]),
     "- Tipos de capa: %s" % R["tipos_de_capa"],
     "- Contorno: %s" % R.get("contorno_mm"),
     "- Taladros por capa de taladro: %s (total %d)" % (R["taladros"], tot_drill),
     "- Componentes: %d en total · **%d para montar** · NO_POP: %s" % (len(comps), len(pop), ", ".join(R["componentes_no_pop"])),
     "- Tipo de montaje (para montar): %s · capas: %s" % (R["tipo_de_montaje"], R["capa_componentes_montar"]),
     "- Transformación KiCad → ODB++: %s · error de posición máx. %.6f mm · giros iguales %s" % (
         R["transformacion"], R["posicion_error_max_mm"], R["giros_coinciden"]),
     "- Frente al CPL de JLCPCB entregado: %s" % R["cpl"],
     "- Propiedades de los componentes montados: %s" % R["propiedades"],
     "- eda/data: %s paquetes, %s redes · netlist: %s" % (R.get("eda_paquetes"), R.get("eda_redes"), R["netlist"]), ""]
L += ["## Problemas", ""] + (["- " + p for p in R["problemas"]] or ["- ninguno"]) + ["", "## Avisos", ""] + ["- " + a for a in R["avisos"]]
L += ["", "## Features por capa", "", "| Capa | Tipo | Unidades | Recuento |", "|---|---|---|---|"]
for k, v in R["features"].items():
    L.append("| %s | %s | %s | %s |" % (k, v["tipo"], v["unidades"], {a: b for a, b in v.items() if a.startswith("n_") or a == "taladros_por_simbolo"}))
open(os.path.join(OUT, "validacion_odb.md"), "w", encoding="utf-8").write("\n".join(L) + "\n")
print("\n".join(L))
sys.exit(1 if R["problemas"] else 0)
