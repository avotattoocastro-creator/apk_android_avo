"""Fase 9 — comprobaciones de fabricación JLCPCB de la REV B (ficheros entregados en hardware/girth/PCB/out/C3).

Uso: python3 fab_check.py <dir_existencias_con_stock_jlc.json y stock_jlc_raw/> <salida_dir>
Comprueba: Gerber (capas, contorno, grosor y acabado del .gbrjob), BOM ↔ CPL ↔ placa ↔ lista de piezas, números
LCSC, existencias y tipo, encapsulado JLC ↔ huella, DNP y piezas a mano, pin 1 de las piezas polarizadas,
giros propuestos (base comunitaria de correcciones de JLCPCB) y presupuesto de 5 PCB con 2 montadas.
"""
import csv
import io
import json
import math
import os
import re
import sys
import zipfile

H = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.join(H, "..", "..")
C3 = os.path.join(PCB, "out", "C3")
stock_dir, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
R = dict(problemas=[], avisos=[])

# ---------------------------------------------------------------- Gerber y job file
z = zipfile.ZipFile(os.path.join(C3, "AVO_GIRTH_PCB_C3_GERBER_JLCPCB.zip"))
names = z.namelist()
job = json.loads(z.read([n for n in names if n.endswith(".gbrjob")][0]))
gs = job.get("GeneralSpecs", {})
R["gerber"] = dict(ficheros=sorted(names), capas_cobre=gs.get("LayerNumber"), grosor_mm=gs.get("BoardThickness"),
                   tamano=gs.get("Size"), acabado=gs.get("Finish") or job.get("FabricationSpecs", {}).get("Finish"),
                   capas_en_job=[f.get("FileFunction") for f in job.get("FilesAttributes", [])])
need = ["F_Cu", "In1_Cu", "In2_Cu", "B_Cu", "F_Mask", "B_Mask", "F_Silkscreen", "B_Silkscreen", "F_Paste", "Edge_Cuts",
        "PTH.drl", "NPTH.drl"]
miss = [n for n in need if not any(n in x for x in names)]
if miss:
    R["problemas"].append("faltan Gerber: %s" % miss)
if gs.get("LayerNumber") != 4:
    R["problemas"].append("el job no declara 4 capas")
if abs(float(gs.get("BoardThickness", 0)) - 1.0) > 0.01:
    R["problemas"].append("grosor declarado %s ≠ 1,0 mm" % gs.get("BoardThickness"))
# contorno desde el Gerber de Edge.Cuts
edge = z.read([n for n in names if "Edge_Cuts" in n][0]).decode()
fmt = re.search(r"%FSLAX(\d)(\d)Y", edge)
dec = int(fmt.group(2)) if fmt else 6
xs, ys = [], []
for m in re.finditer(r"^X(-?\d+)Y(-?\d+)(?:I-?\d+J-?\d+)?D0[12]\*", edge, re.M):   # puntos de trazo, no centros
    x, y = int(m.group(1)) / 10 ** dec, int(m.group(2)) / 10 ** dec
    if (x, y) != (0.0, 0.0):
        xs.append(x); ys.append(y)
R["gerber"]["contorno_mm"] = dict(ancho=round(max(xs) - min(xs), 3), alto=round(max(ys) - min(ys), 3))
if abs(R["gerber"]["contorno_mm"]["ancho"] - 65.5) > 0.05 or abs(R["gerber"]["contorno_mm"]["alto"] - 43.5) > 0.05:
    R["problemas"].append("contorno del Gerber %s ≠ 65,5 × 43,5 mm" % R["gerber"]["contorno_mm"])
R["avisos"].append("ENIG no va en los Gerber: se elige en el pedido de JLCPCB (Surface Finish: ENIG)")

# ---------------------------------------------------------------- BOM / CPL / piezas / placa
parts = json.load(open(os.path.join(PCB, "kicad", "piezas.json"), encoding="utf-8"))
asm = {p["ref"]: p for p in parts if not p["dnp"] and not p["no_assembly"]}
dnp = [p["ref"] for p in parts if p["dnp"]]
hand = [p["ref"] for p in parts if p["no_assembly"]]
bom = list(csv.DictReader(open(os.path.join(C3, "AVO_GIRTH_PCB_C3_BOM_JLCPCB.csv"), encoding="utf-8")))
cpl = list(csv.DictReader(open(os.path.join(C3, "AVO_GIRTH_PCB_C3_CPL_JLCPCB.csv"), encoding="utf-8")))
bref = {x: r for r in bom for x in r["Designator"].replace(" ", "").split(",")}
cref = {r["Designator"]: r for r in cpl}
pcbtxt = open(os.path.join(C3, "KiCad", "AVO_GIRTH_PCB.kicad_pcb"), encoding="utf-8").read()
fp_blocks = {}
for blk in pcbtxt.split("\n\t(footprint ")[1:]:
    ref = re.search(r'"Reference" "([^"]+)"', blk).group(1)
    fp_blocks[ref] = blk
chk = dict(montadas=len(asm), en_bom=len(bref), en_cpl=len(cref), en_placa=len(fp_blocks),
           bom_sin_cpl=sorted(set(bref) - set(cref)), cpl_sin_bom=sorted(set(cref) - set(bref)),
           montadas_sin_bom=sorted(set(asm) - set(bref)), bom_no_montadas=sorted(set(bref) - set(asm)),
           dnp=dnp, dnp_en_bom=[r for r in dnp if r in bref or r in cref],
           a_mano=hand, a_mano_en_bom=[r for r in hand if r in bref or r in cref],
           lcsc_distinto=[r for r in asm if bref.get(r, {}).get("LCSC Part #") != asm[r]["lcsc"]],
           sin_huella_en_placa=[r for r in asm if r not in fp_blocks])
R["referencias"] = chk
for k in ("bom_sin_cpl", "cpl_sin_bom", "montadas_sin_bom", "bom_no_montadas", "dnp_en_bom", "a_mano_en_bom",
          "lcsc_distinto", "sin_huella_en_placa"):
    if chk[k]:
        R["problemas"].append("%s: %s" % (k, chk[k]))

# capa: todo por la cara de arriba
bottom = [r["Designator"] for r in cpl if r["Layer"].lower().startswith("b")]
R["cara_inferior"] = bottom

# ---------------------------------------------------------------- existencias, tipo, encapsulado ↔ huella
st = json.load(open(os.path.join(stock_dir, "stock_jlc.json"), encoding="utf-8"))
R["existencias_fecha"] = st["date_utc"]
raw = {}
for code in {p["lcsc"] for p in asm.values()}:
    f = os.path.join(stock_dir, "stock_jlc_raw", code + ".json")
    if os.path.exists(f):
        lst = json.load(open(f))["data"]["componentPageInfo"]["list"]
        hit = [c for c in lst if c.get("componentCode") == code]
        raw[code] = hit[0] if hit else {}
PKG = [  # (huella KiCad, patrón del encapsulado que publica JLCPCB)
    (r"^R_0402", r"0402"), (r"^C_0402", r"0402"), (r"^C_0603", r"0603"), (r"^C_0805", r"0805"), (r"^C_1206", r"1206"),
    (r"^R_0805", r"0805"), (r"^LED_0603", r"0603"), (r"^SOT-23-5", r"SOT-23-5"), (r"^SOT-23-6", r"SOT-23-6"),
    (r"^SOT-23$", r"SOT-23|TO-236"), (r"RHL-20", r"QFN-20|RHL"), (r"VQFN-16", r"QFN-16"), (r"USB_C", r"SMD|USB"),
    (r"JST_SH", r"SMD|1mm|P=1"), (r"ESP32-C3-MINI-1U", r"13\.2x12\.5"), (r"LGA-14", r"LGA-14"), (r"MMC5983MA", r"LGA-16"),
]
rows = []
for code in sorted({p["lcsc"] for p in asm.values()}):
    refs = sorted(r for r, p in asm.items() if p["lcsc"] == code)
    fpk = asm[refs[0]]["footprint"]
    v = st["parts"].get(code, {}); rr = raw.get(code, {})
    pkg = v.get("package") or rr.get("componentSpecificationEn") or ""
    pat = next((jp for fp_re, jp in PKG if re.search(fp_re, fpk)), None)
    ok_pkg = bool(re.search(pat, pkg or "")) if pat else None
    need_n = 2 * len(refs)
    rows.append(dict(lcsc=code, mpn=v.get("mpn"), refs=refs, huella=fpk, encapsulado_jlc=pkg, coincide=ok_pkg,
                     tipo="Basic" if v.get("library") == "base" else "Extended", existencias=v.get("stock"),
                     compra_minima=rr.get("minPurchaseNum"), merma=rr.get("lossNumber"),
                     precio=(v.get("prices") or [[None, None]])[0][1], suficiente_2_placas=(v.get("stock") or 0) >= need_n))
    if ok_pkg is False:
        R["problemas"].append("encapsulado JLC «%s» no casa con la huella %s (%s)" % (pkg, fpk, code))
    if (v.get("stock") or 0) < need_n:
        R["problemas"].append("sin existencias para 2 placas: %s %s" % (code, v.get("mpn")))
R["piezas_jlc"] = rows

# ---------------------------------------------------------------- pin 1 y giros
db = []
dbp = os.path.join(H, "cpl_rotations_db.csv")
for r in csv.reader(open(dbp)):
    if r and not r[0].startswith("Footprint") and r[0] != "Footprint pattern":
        try:
            db.append((r[0], float(r[1])))
        except ValueError:
            pass
POLAR = ("U", "Q", "D", "J", "RT")
pin1 = []
prop = []
for r in cpl:
    ref = r["Designator"]
    blk = fp_blocks[ref]
    fpname = blk.split('"')[1].split(":")[-1]
    at = re.search(r"\n\t\t\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)", blk)
    rot = float(at.group(3) or 0)
    corr = next((c for p, c in db if re.search(p, fpname)), 0.0)
    prop.append(dict(r, Rotation=str(int((float(r["Rotation"]) + corr) % 360))))
    if ref.startswith(POLAR) and not ref.startswith("RT"):
        m = re.search(r'\(pad "1" \w+ \w+\s*\(at ([-\d.]+) ([-\d.]+)', blk)
        if m:
            px, py = float(m.group(1)), float(m.group(2))
            a = math.radians(rot)
            bx, by = px * math.cos(a) + py * math.sin(a), -px * math.sin(a) + py * math.cos(a)   # convenio KiCad
            ang = math.degrees(math.atan2(-by, bx)) % 360                                    # ángulo con Y hacia arriba
            pin1.append(dict(ref=ref, huella=fpname, giro_kicad=rot, giro_cpl=r["Rotation"], correccion_comunitaria=corr,
                             giro_propuesto=int((float(r["Rotation"]) + corr) % 360), pin1_dx=round(bx, 2),
                             pin1_dy=round(-by, 2), pin1_angulo=round(ang)))
R["pin1"] = pin1
with open(os.path.join(out, "AVO_GIRTH_PCB_C3_CPL_JLCPCB_giros_propuestos.csv"), "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=list(cpl[0].keys())); w.writeheader(); w.writerows(prop)
R["avisos"].append("Giros: las correcciones salen de la base comunitaria cpl_rotations_db.csv (JLCKicadTools, la usa "
                   "el complemento kicad-jlcpcb-tools); no son de JLCPCB. Hay que confirmarlas en la vista previa del pedido.")

# ---------------------------------------------------------------- presupuesto 5 PCB, 2 montadas
FEES = dict(setup=25.56, stencil=8.21, loading=1.53, joint=0.0016, prereflow=0.016, handling=14.93, packing=0.5,
            xray=0.82)  # US$, tarifas publicadas por JLCPCB (Standard PCBA), consultadas el 2026-10-29
N = 2
joints = 0
for ref in asm:
    joints += len(re.findall(r'\n\t\t\(pad "', fp_blocks[ref]))
comp = 0.0
lines = []
for row in rows:
    v = st["parts"].get(row["lcsc"], {})
    q_need = len(row["refs"]) * N + (row["merma"] or 0)
    q_buy = max(q_need, row["compra_minima"] or 1)
    price = None
    for n, pr in v.get("prices") or []:
        if n is not None and q_buy >= n:
            price = pr
    cost = (price or 0) * q_buy
    comp += cost
    lines.append((row["lcsc"], row["mpn"], q_buy, price, round(cost, 2)))
leadless = [r for r in asm if re.search(r"QFN|MINI-1U|LGA", asm[r]["footprint"])]
asmb = (FEES["setup"] + FEES["stencil"] + FEES["loading"] * len(rows) + joints * N * (FEES["joint"] + FEES["prereflow"])
        + FEES["handling"] + FEES["packing"] + FEES["xray"] * len(leadless) * N)
R["presupuesto"] = dict(placas_pcb=5, placas_montadas=N, soldaduras_por_placa=joints, referencias_bom=len(rows),
                        piezas_sin_patas_rayos_x=leadless, componentes_usd=round(comp, 2), montaje_usd=round(asmb, 2),
                        pcb_desnuda_usd="NO VERIFICADO (precio de 4 capas 65,5×43,5 mm ENIG 1,0 mm: solo en el presupuesto de JLCPCB)",
                        total_sin_pcb_ni_envio_usd=round(comp + asmb, 2), lineas=lines, tarifas=FEES)
json.dump(R, open(os.path.join(out, "fab_check.json"), "w"), indent=1, ensure_ascii=False, default=str)
print(json.dumps({k: v for k, v in R.items() if k not in ("piezas_jlc", "pin1")}, indent=1, ensure_ascii=False, default=str))
sys.exit(1 if R["problemas"] else 0)
