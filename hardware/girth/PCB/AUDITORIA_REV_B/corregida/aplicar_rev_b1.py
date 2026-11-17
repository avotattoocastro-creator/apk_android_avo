"""REV B.1 propuesta por la auditoría — se genera a partir de la REV B entregada SIN tocarla.

Cambios (y solo estos):
  1. BQ24072 (U2) en modo USB500 en vez de modo ILIM (hallazgo Qi H-3): EN2 (pin 5) a GND y EN1 (pin 6) a VSYS.
     En USB500 el cargador tiene VIN-DPM (4,35/4,5/4,63 V, TI SLUS810M tabla 1 y "Input DPM"), que el BQ51013B
     necesita para que su límite de comunicación adaptativo no hunda la salida del receptor Qi; en modo ILIM
     (REV B: EN2 = 1 por R8, EN1 = 0) el BQ24072 no tiene VIN-DPM. Límite de entrada: 450–500 mA (antes 403–515 mA
     con ILIM 3,3 k); la corriente de carga sigue fijada por ISET (3,3 k → 241–295 mA). R7 (ILIM) sigue montada.
     Cobre: el pin 6 está encerrado entre el EPAD, los pines 5/7 y la vía de VSYS que tiene 0,3 mm debajo, así que
     se une directamente a esa vía (EN1 es una entrada lógica, máx. abs. 7 V; VSYS ≤ 4,4 V). El pin 5 pasa a GND
     con un tramo corto al EPAD (como ya tenían los pines 4, 6 y 8). R8 queda sin función → DNP (sus pads quedan
     entre GND y VSYS; si alguien la monta, solo consume 42 µA). No se mueve ninguna pieza.
  2. Enclavamiento (solo valores, sin tocar el cobre), por la simulación de la auditoría (spice/, variantes):
     C41 220 nF → 470 nF: el corte aguanta reinicios del ESP32 de 1,5 s en el peor caso (con 220 nF caía con 0,6 s;
     Monte Carlo 3/200 → 0/200); a cambio el apagado tarda ≈ 4 s en vez de ≈ 1,9 s y la ventana sin PWR_HOLD baja de
     2,9 a 2,6 s en el peor caso (sigue > 5 × el arranque supuesto). R40 1 M → 100 k: la fuga de Q11 en caliente
     (IDSS hasta 5 µA a 55 °C según AOS) ya no puede abrir Q10 con la placa apagada (≤ 0,5 V en vez de ≤ 5 V); cuesta
     42 µA solo con la placa encendida. La simulación no cambia con R40 (ver INFORME, sección 13).
  3. Revisión "B.1" en el cajetín (la REV B entregada lleva "A" en el cajetín → Gerber TF.ProjectId y gbrjob) y
     en la serigrafía.

Procedimiento reproducible:
  - copia ../../fuente a una carpeta de trabajo temporal y aplica los reemplazos de texto de abajo (cada uno debe
    aparecer exactamente las veces indicadas, o el script se detiene);
  - parte de la placa ENTREGADA (out/C3/KiCad/AVO_GIRTH_PCB.kicad_pcb): borra el tramo GND del pin 6 de U2, añade
    el tramo GND del pin 5 al EPAD y el tramo VSYS del pin 6 a su vía; la pista que unía el pin 5 con R8.1 se
    conserva y pasa a GND (pin 5 y R8.1 son GND ahora); fuente/repair.py comprueba que no queda nada sin unir;
  - escribe kicad/ (placa sin rellenar, esquema, proyecto, piezas.json), CAMBIOS.diff y aplicar_salida.txt.
El relleno de zonas, DRC/ERC con paridad y Gerber se hacen en el CI (KiCad 9 oficial), igual que en la REV B.
Uso: python3 aplicar_rev_b1.py"""
import copy
import difflib
import os
import shutil
import subprocess
import sys
import tempfile

H = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.normpath(os.path.join(H, "..", ".."))
SRC = os.path.join(PCB, "fuente")
ENTREGADA = os.path.join(PCB, "out", "C3", "KiCad", "AVO_GIRTH_PCB.kicad_pcb")

REEMPLAZOS = [
    ("avo_girth_pcb.py", '5: "CHG_EN2", 6: GND,', '5: GND, 6: VSYS,', 1),
    ("avo_girth_pcb.py", 'R("R8", "100k", "CHG_EN2", VSYS, (-8.6, -2.8), 90, "Cargador", note="EN2 = 1, EN1 = 0: límite por ILIM")',
     'R("R8", "100k", GND, VSYS, (-8.6, -2.8), 90, "Cargador", dnp=True,\n'
     '  note="REV B.1: sin función (EN2 = GND, EN1 = VSYS: USB500 con VIN-DPM)")', 1),
    ("avo_girth_pcb.py", 'REV, DATE = "B", "2026-10-29"', 'REV, DATE = "B.1", "2026-10-29"', 1),
    ("avo_girth_pcb.py", 'C("C41", "220n", "PWR_G", GND, (-15.6, 14.0), 0, "Corte", note="sostiene el corte durante un reinicio (τ 2,2 s)")',
     'C("C41", "470n", "PWR_G", GND, (-15.6, 14.0), 0, "Corte", lcsc=C41_LCSC,\n'
     '  note="REV B.1: sostiene el corte durante un reinicio (τ 4,7 s)")', 1),
    ("avo_girth_pcb.py", 'R("R40", "1M", "BAT_RAW", "PWR_PG", (-19.0, 13.6), 0, "Corte", note="Q10 apagado por defecto")',
     'R("R40", "100k", "BAT_RAW", "PWR_PG", (-19.0, 13.6), 0, "Corte",\n'
     '  note="REV B.1: 100 k — la fuga de Q11 en caliente no abre Q10")', 1),
    ("avo_girth_pcb.py", 'LC = {', 'C41_LCSC = "C47339"  # REV B.1: 470 nF 0402 CL05A474KP5NNNC (comprobado en el CI: existencias, encapsulado)\nLC = {', 1),
    ("build.py", '"CHG_TS", "CHG_EN2", D.VSYS', '"CHG_TS", D.VSYS', 1),
    ("build.py", '("U2", "6")', '("U2", "5")', 1),
    ("build.py", ', ("CHG_EN2", ["U2.5", "R8.1"])]', ']', 1),
    ("board.py", '[S("rev"), "A"]', '[S("rev"), "B.1"]', 1),
]
# tramo GND del pin 6 de U2 (pin en 89,85/104,4625; EPAD centrado en 90,1/103) que se quita
QUITAR = {("GND", (89.85, 104.4625), (89.85, 104.462)), ("GND", (89.85, 104.462), (89.85, 103.712)),
          ("GND", (89.619, 103.481), (89.85, 103.712))}
# tramos nuevos: GND del pin 5 (89,35/104,4625) al EPAD (borde izquierdo en x = 89,26) y al nodo del pin 4; VSYS
# del pin 6 (89,85/104,4625) a la vía de VSYS (89,775/105,425) — 0,2 mm, ≥ 0,24 mm a los pads 5 y 7
PONER = [("GND", (89.35, 104.4625), (89.35, 103.712)), ("GND", (89.35, 103.712), (89.619, 103.481)),
         ("VSYS", (89.85, 104.4625), (89.775, 105.425))]


def main():
    work = tempfile.mkdtemp(prefix="revb1_")
    fu = os.path.join(work, "fuente")
    shutil.copytree(SRC, fu, ignore=shutil.ignore_patterns("__pycache__"))
    os.makedirs(os.path.join(work, "kicad"))
    diff = []
    for fn, a, b, n in REEMPLAZOS:
        p = os.path.join(fu, fn)
        t = open(p, encoding="utf-8").read()
        if t.count(a) != n:
            sys.exit("%s: se esperaban %d apariciones de %r y hay %d" % (fn, n, a, t.count(a)))
        open(p, "w", encoding="utf-8").write(t.replace(a, b))
    for fn in sorted({r[0] for r in REEMPLAZOS}):
        diff += difflib.unified_diff(open(os.path.join(SRC, fn), encoding="utf-8").read().splitlines(True),
                                     open(os.path.join(fu, fn), encoding="utf-8").read().splitlines(True),
                                     "REV_B/fuente/" + fn, "REV_B1/fuente/" + fn)
    open(os.path.join(H, "CAMBIOS.diff"), "w", encoding="utf-8").writelines(diff)

    sys.path.insert(0, fu)
    from sexpr import parse, dump, find  # noqa: E402
    t = parse(open(ENTREGADA, encoding="utf-8").read())
    names = {it[1]: it[2] for it in t if isinstance(it, list) and it and str(it[0]) == "net"}
    code = {v: k for k, v in names.items()}
    keep, borradas, renombradas = [], [], []
    for it in t:
        if isinstance(it, list) and it and str(it[0]) == "segment":
            n = names[find(it, "net")[1]]
            a_, b_ = tuple(find(it, "start")[1:3]), tuple(find(it, "end")[1:3])
            if (n, a_, b_) in QUITAR or (n, b_, a_) in QUITAR:
                borradas.append("%s F.Cu %s→%s" % (n, a_, b_))
                continue
            if n == "CHG_EN2":
                find(it, "net")[1] = code["GND"]
                renombradas.append("%s→%s" % (a_, b_))
        keep.append(it)
    if len(borradas) != len(QUITAR):
        sys.exit("se esperaban %d tramos que borrar y hay %d: %s" % (len(QUITAR), len(borradas), borradas))
    seg_t = next(it for it in keep if isinstance(it, list) and it and str(it[0]) == "segment")
    if len(renombradas) != 9:
        sys.exit("se esperaban 9 tramos de CHG_EN2 y hay %d" % len(renombradas))
    log = ["Placa de partida: " + os.path.relpath(ENTREGADA, PCB), "Borrado:"] + ["  " + b for b in borradas] + \
          ["Pista pin 5 → R8.1 (9 tramos) pasa de CHG_EN2 a GND:"] + ["  " + b for b in renombradas]
    for k, (net, a, b) in enumerate(PONER):
        s = copy.deepcopy(seg_t)
        for p in s:
            if isinstance(p, list) and p:
                key = str(p[0])
                if key == "start": p[1:3] = list(a)
                elif key == "end": p[1:3] = list(b)
                elif key == "width": p[1] = 0.2
                elif key == "layer": p[1] = "F.Cu"
                elif key == "net": p[1] = code[net]
                elif key == "uuid": p[1] = "b1b1b1b1-0000-4000-8000-%012d" % k
        keep.append(s)
        log.append("Añadido: %s F.Cu 0,2 mm %s→%s" % (net, a, b))
    dst = os.path.join(work, "kicad", "AVO_GIRTH_PCB.kicad_pcb")
    open(dst, "w", encoding="utf-8").write(dump(keep))

    # comprobar con el reparador de la fuente que no queda nada sin unir (y escribir la placa con la fuente B.1)
    r = subprocess.run([sys.executable, os.path.join(fu, "repair.py")], cwd=fu, capture_output=True, text=True)
    log += ["", "fuente/repair.py (código %d):" % r.returncode, r.stdout.strip(), r.stderr.strip()]
    open(os.path.join(H, "aplicar_salida.txt"), "w").write("\n".join(log) + "\n")
    if r.returncode:
        sys.exit("repair.py falló:\n" + r.stdout + r.stderr)
    import avo_girth_pcb as D  # noqa: E402
    import write_sch  # noqa: E402
    k = os.path.join(work, "kicad")
    write_sch.write(os.path.join(k, "AVO_GIRTH_PCB.kicad_sch"), os.path.join(k, "AVO_GIRTH_PCB.kicad_pro"),
                    os.path.join(k, "piezas.json"))
    out = os.path.join(H, "kicad")
    os.makedirs(out, exist_ok=True)
    shutil.copy(os.path.join(k, "AVO_GIRTH_PCB_ruteado.kicad_pcb"), os.path.join(out, "AVO_GIRTH_PCB.kicad_pcb"))
    for f in ("AVO_GIRTH_PCB.kicad_sch", "AVO_GIRTH_PCB.kicad_pro", "piezas.json"):
        shutil.copy(os.path.join(k, f), os.path.join(out, f))
    png = os.path.join(work, "out_local_reparado.png")
    if os.path.exists(png):
        shutil.copy(png, os.path.join(H, "vista_ruteado_rev_b1.png"))
    # BOM/CPL de JLCPCB con el mismo algoritmo que fuente/jlc.py, desde el piezas.json de la B.1; las posiciones
    # (sin cambios) salen del CPL entregado
    import csv
    import json
    from collections import OrderedDict
    c3 = os.path.join(PCB, "out", "C3")
    parts = json.load(open(os.path.join(k, "piezas.json"), encoding="utf-8"))
    bom = OrderedDict()
    for p_ in parts:
        if p_.get("dnp") or not p_.get("lcsc") or p_.get("no_assembly"):
            continue
        bom.setdefault((p_["value"], p_["footprint"], p_["lcsc"]), []).append(p_["ref"])
    key = lambda r: (r.rstrip("0123456789"), int("0" + r.lstrip("ABCDEFGHIJKLMNOPQRSTUVWXYZ")))
    rows = [["Comment", "Designator", "Footprint", "LCSC Part #"]] + \
           [[v, ",".join(sorted(refs, key=key)), fp, lc] for (v, fp, lc), refs in bom.items()]
    csv.writer(open(os.path.join(H, "AVO_GIRTH_PCB_C3_REV_B1_BOM_JLCPCB.csv"), "w", newline="", encoding="utf-8"),
               lineterminator="\r\n").writerows(rows)
    mont = {r_ for refs in bom.values() for r_ in refs}
    cpl = list(csv.reader(open(os.path.join(c3, "AVO_GIRTH_PCB_C3_CPL_JLCPCB.csv"), encoding="utf-8")))
    cpl2 = [cpl[0]] + [r_ for r_ in cpl[1:] if r_[0] in mont]
    csv.writer(open(os.path.join(H, "AVO_GIRTH_PCB_C3_REV_B1_CPL_JLCPCB.csv"), "w", newline="", encoding="utf-8"),
               lineterminator="\r\n").writerows(cpl2)
    if len(cpl2) - 1 != len(mont):
        sys.exit("CPL incompleto: %d filas para %d piezas" % (len(cpl2) - 1, len(mont)))
    old = list(csv.reader(open(os.path.join(c3, "AVO_GIRTH_PCB_C3_BOM_JLCPCB.csv"), encoding="utf-8")))
    log.append("BOM REV B.1 (%d líneas, %d piezas) frente a la entregada:" % (len(rows) - 1, len(mont)))
    log += ["  - " + ",".join(r_) for r_ in old if r_ not in rows] + ["  + " + ",".join(r_) for r_ in rows if r_ not in old]
    log.append("CPL REV B.1: %d filas (entregada %d)" % (len(cpl2) - 1, len(cpl) - 1))
    log.append("REV en la fuente: %s · R8 DNP: %s" % (D.REV, next(p["dnp"] for p in D.PARTS if p["ref"] == "R8")))
    open(os.path.join(H, "aplicar_salida.txt"), "w").write("\n".join(log) + "\n")
    print("\n".join(log))
    print("escrito", out)


if __name__ == "__main__":
    main()
