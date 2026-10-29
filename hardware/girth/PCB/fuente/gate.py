"""Blocking checks after KiCad's DRC/ERC (run from hardware/girth/PCB, after the KiCad step).

Pass only if: 0 DRC errors (incl. clearances, shorts, holes, edge, mask, footprints), 0 unconnected items,
0 schematic-parity problems, 0 ERC errors and 0 ERC warnings. DRC warnings are listed in the report.
Writes out/gate.json and the report (FINAL only when everything passes). Exit code 1 if it fails.
"""
import json
import os
import subprocess
import sys
from collections import Counter

OUT = "out"
drc = json.load(open(os.path.join(OUT, "drc.json")))
erc = json.load(open(os.path.join(OUT, "erc.json")))
info = json.load(open(os.path.join(OUT, "kicad_info.json"))) if os.path.exists(os.path.join(OUT, "kicad_info.json")) else {}
parts = json.load(open("kicad/piezas.json", encoding="utf-8"))
route_src = open(os.path.join(OUT, "ruteado", "ORIGEN.txt")).read().strip() if os.path.exists(
    os.path.join(OUT, "ruteado", "ORIGEN.txt")) else "desconocido"

viol = drc.get("violations", [])
unconn = drc.get("unconnected_items", [])
parity = drc.get("schematic_parity", [])
errs = [v for v in viol if v.get("severity") == "error"]
warns = [v for v in viol if v.get("severity") == "warning"]
by_type_e = Counter(v["type"] for v in errs)
by_type_w = Counter(v["type"] for v in warns)
shorts = [v for v in viol if v["type"] == "shorting_items"]
erc_v = [v for s in erc.get("sheets", []) for v in s.get("violations", [])]
erc_e = [v for v in erc_v if v.get("severity") == "error"]
erc_w = [v for v in erc_v if v.get("severity") == "warning"]

checks = [
    ("DRC: errores", len(errs) == 0, len(errs)),
    ("DRC: conexiones incompletas", len(unconn) == 0, len(unconn)),
    ("DRC: cortocircuitos", len(shorts) == 0, len(shorts)),
    ("DRC: paridad esquema ↔ placa", len(parity) == 0, len(parity)),
    ("ERC: errores", len(erc_e) == 0, len(erc_e)),
    ("ERC: advertencias", len(erc_w) == 0, len(erc_w)),
]
ok = all(c[1] for c in checks)
sha = os.environ.get("GITHUB_SHA") or subprocess.run(["git", "rev-parse", "HEAD"], capture_output=True,
                                                      text=True).stdout.strip()
run = os.environ.get("GITHUB_RUN_ID", "local")

json.dump(dict(ok=ok, checks=[dict(name=n, ok=o, n=c) for n, o, c in checks],
               drc_errors=dict(by_type_e), drc_warnings=dict(by_type_w)), open(os.path.join(OUT, "gate.json"), "w"),
          indent=1)

assembled = [p for p in parts if not p["dnp"] and not p["no_assembly"]]
dnp = [p["ref"] for p in parts if p["dnp"]]
no_lcsc = [p["ref"] for p in assembled if not p["lcsc"]]
name = "AVO_GIRTH_PCB_C3_REPORTE.md" if ok else "AVO_GIRTH_PCB_C3_DIAGNOSTICO_REPORTE.md"
state = ("**DISEÑO VERIFICADO POR SOFTWARE — APTO PARA SOLICITAR PROTOTIPOS — PENDIENTE DE VALIDACIÓN FÍSICA**"
         if ok else "**DISEÑO INCOMPLETO** — no fabricar: hay comprobaciones bloqueantes sin superar")
L = []
L.append("# AVO GIRTH · placa de la cincha · REV B (ESP32-C3) — informe %s" % ("de fabricación" if ok else "de diagnóstico"))
L.append("")
L.append("- Estado: %s" % state)
L.append("- Commit: `%s` · ejecución de CI: %s" % (sha, run))
L.append("- Ruteado: %s" % route_src)
L.append("- Placa: 4 capas (F.Cu señal · In1.Cu GND · In2.Cu +3V3 · B.Cu señal + GND), 1,0 mm, ENIG, cobre exterior "
         "1 oz; contorno 65,5 × 43,5 mm con 8 muescas para los tornillos y una ranura para el cable de la batería")
L.append("- Componentes: %d en total, %d para montar, %d sin montar (DNP: %s), %d a mano (pads de hilo y de prueba)"
         % (len(parts), len(assembled), len(dnp), ", ".join(dnp) or "—",
            len([p for p in parts if p["no_assembly"]])))
L.append("- Pistas: %s · vías: %s · ruteado %s" % (info.get("tracks", "?"), info.get("vias", "?"),
         "completo (0 conexiones incompletas)" if not unconn else "INCOMPLETO (%d conexiones)" % len(unconn)))
L.append("")
L.append("## Comprobaciones bloqueantes")
L.append("| Comprobación | Resultado | Cantidad |")
L.append("|---|---|---|")
for n, o, c in checks:
    L.append("| %s | %s | %d |" % (n, "correcto" if o else "**FALLA**", c))
L.append("")
if by_type_e:
    L.append("Errores de DRC por tipo: " + ", ".join("%s %d" % kv for kv in by_type_e.most_common()))
if unconn:
    L.append("")
    L.append("### Conexiones incompletas")
    for u in unconn:
        L.append("- " + " ↔ ".join(i["description"] for i in u["items"]))
if parity:
    L.append("")
    L.append("### Paridad esquema ↔ placa")
    for v in parity[:40]:
        L.append("- %s: %s" % (v["type"], v["description"]))
L.append("")
L.append("## Advertencias de DRC (no bloqueantes)")
if by_type_w:
    for t, c in by_type_w.most_common():
        L.append("- %s: %d" % (t, c))
else:
    L.append("- ninguna")
L.append("")
L.append("## Lista de materiales y posiciones")
L.append("- Piezas montadas sin número LCSC: %s" % (", ".join(no_lcsc) or "ninguna"))
L.append("- Los ficheros BOM y CPL se generan desde la misma lista que el esquema y la placa (`kicad/piezas.json`).")
L.append("- Revisar el giro de cada pieza en la vista previa de JLCPCB: el CPL sale de KiCad sin correcciones.")
L.append("")
L.append("## Modelo 3D (STEP y renders, no afecta a la fabricación)")
mp = os.path.join(OUT, "modelos3d.txt")
if os.path.exists(mp):
    ml = open(mp).read().split("\n")
    falta = [x[6:] for x in ml if x.startswith("FALTA ")]
    L.append("- Modelos de la librería de KiCad 9.0.0 descargados: %d; sin descargar: %s"
             % (len([x for x in ml if x.startswith("OK ")]), ", ".join(falta) or "ninguno"))
L.append("- ESP32-C3-MINI-1U: modelo de Espressif (`fuente/3d`). MMC5983MA y pads de hilo/prueba: sin modelo 3D.")
# REV B: elección del microcontrolador, diferencias, firmware y riesgos (texto fijo del diseño)
inf = os.path.join("DOCS", "INFORME_REV_B.md")
if os.path.exists(inf):
    L.append("")
    L += open(inf, encoding="utf-8").read().rstrip("\n").split("\n")
# existencias y coste: los de la última consulta del CI (con su fecha), no los de este momento
stk = os.path.join("out_stock", "stock_jlc.json")
if os.path.exists(stk):
    st = json.load(open(stk, encoding="utf-8"))
    L.append("")
    L.append("## Existencias en JLCPCB (consulta del CI: %s)" % st.get("date_utc"))
    L.append("| LCSC | Pieza | Por placa | Existencias | Tipo | Precio (1 ud.) |")
    L.append("|---|---|---|---|---|---|")
    count = Counter(p["lcsc"] for p in assembled)
    for code, n in sorted(count.items(), key=lambda kv: -((st["parts"].get(kv[0], {}).get("prices") or [[0, 0]])[0][1] or 0)):
        v = st["parts"].get(code, {})
        pr = (v.get("prices") or [[None, None]])[0][1]
        L.append("| %s | %s | %d | %s | %s | %s |" % (code, v.get("mpn", "?"), n, v.get("stock", "sin respuesta"),
                 "Basic" if v.get("library") == "base" else "Extended", ("%.4f US$" % pr) if pr is not None else "?"))
    short = [code for code, n in count.items() if (st["parts"].get(code, {}).get("stock") or 0) < n * 5]
    L.append("")
    L.append("- Piezas sin existencias para 5 placas: %s" % (", ".join(short) or "ninguna"))
cst = os.path.join("out_stock", "COSTE.md")
if os.path.exists(cst):
    rows = [l for l in open(cst, encoding="utf-8").read().split("\n") if l.startswith("| ") and "placas" in l]
    L.append("")
    L.append("## Coste por placa frente a la REV A (componentes + cargo de piezas Extended; detalle en out_stock/COSTE.md)")
    L.append("| Pedido | REV A componentes | REV A Extended | REV A total | REV B componentes | REV B Extended | REV B total | Reducción |")
    L.append("|---|---|---|---|---|---|---|---|")
    L += rows
fw = os.path.join("..", "..", "..", "firmware", "girth", "V0_3_0_C3", "out")
fz = os.path.join(fw, "AVO_GIRTH_PCB_C3_FIRMWARE.zip")
L.append("")
L.append("## Firmware incluido")
if os.path.exists(fz):
    import hashlib
    L.append("- `AVO_GIRTH_PCB_C3_FIRMWARE.zip` (compilado por `build-girth-c3.yml`), SHA256 `%s`"
             % hashlib.sha256(open(fz, "rb").read()).hexdigest())
    mem = os.path.join(fw, "bin", "memoria.txt")
    if os.path.exists(mem):
        for l in open(mem, encoding="utf-8"):
            L.append("- " + l.strip())
    L.append("- Compila; **no probado en placa**.")
else:
    L.append("- **Falta**: no hay firmware compilado en la rama.")
L.append("")
L.append("## Estado de fabricación")
L.append("- Diseño verificado por software (KiCad 9 en el CI): %s" % ("**sí**" if ok else "**no**"))
L.append("- Apto para solicitar prototipos: %s" % ("**sí, pendiente de validación física**" if ok else "**no**"))
L.append("- Validado físicamente: **no** (no se ha fabricado ni medido ninguna placa)")
L.append("")
L.append("## Limitaciones pendientes (ver README)")
for t in ("Inductancia de la bobina Qi sin medir: C1–C5 con valores supuestos (DOCS/AJUSTE_QI.md).",
          "Existencias consultadas en el CI (out_stock/stock_jlc.json): volver a comprobarlas el día del pedido.",
          "Enclavamiento de la batería (Q10/Q11) calculado, no medido: comprobar tiempos de encendido y de apagado.",
          "Tensión de umbral de Q11 (AO3400A, 0,65–1,45 V) y tiempos de C40/C41: medir en el prototipo.",
          "Antena externa con conector del módulo (U.FL / MHF I del ESP32-C3-MINI-1U).",
          "Cambios en la carcasa (cuna +0,6 mm, ranura del cable, postes de la tapa); ya no hace falta el rebaje del relé.",
          "Nada de esto se ha fabricado ni medido: no es un prototipo validado."):
    L.append("- " + t)
open(os.path.join(OUT, name), "w", encoding="utf-8").write("\n".join(L) + "\n")
print("\n".join(L))
print("::notice title=Puerta de fabricación::%s" % ("SUPERADA" if ok else "NO SUPERADA"))
sys.exit(0 if ok else 1)
