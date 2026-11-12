"""AVO GIRTH REV B → copia del proyecto KiCad para exportar ODB++ a AISLER.

Parte del proyecto ENTREGADO (hardware/girth/PCB/out/C3/KiCad, commit 2a703697abf6) y escribe una copia en
AISLER/kicad/. El original no se toca.

Cambios en la copia (y solo estos; el script comprueba que no cambia nada más):
  1. TP1–TP8 (puntos de prueba), L1/L2 (pads del hilo de la bobina Qi) y SW1/SW2 (pads del hilo del reed) se
     marcan como «no montar» en la placa (atributos dnp + exclude_from_pos_files + exclude_from_bom) y en el
     esquema (dnp yes, in_bom no). Motivo: el exportador ODB++ de KiCad 9 escribe TODAS las huellas en el fichero
     de componentes y solo marca NO_POP las que tienen DNP (pcbnew/pcb_io/odbpp/odb_component.cpp); AISLER toma
     de ahí qué montar. Sin esto, AISLER vería 97 piezas para montar en vez de 85.
  2. Revisión del cajetín de la placa: «A» → «B» (la placa es la REV B; el cajetín arrastraba «A»).
  3. Campos de texto de las 85 piezas montadas (solo en la placa, que es lo que lee el ODB++): «MPN» pasa a ser la
     referencia del fabricante de la pieza LCSC de la BOM de JLCPCB (77 de 85 llevaban el valor, p. ej. «100k») y se
     añade «Manufacturer». Datos: lcsc_piezas_2026-10-29.json (consulta a JLCPCB del CI de la auditoría). Sirve para
     que la herramienta de BOM de AISLER encuentre las piezas. «Value» y «LCSC» no cambian.
Sin cambios: redes, pads, posiciones, giros, pistas, vías, zonas (con su relleno), contorno, capas, reglas.

Uso: python3 preparar_aisler.py   → AISLER/kicad/AVO_GIRTH_PCB.kicad_{pcb,sch,pro} + preparar_salida.txt
"""
import hashlib
import json
import uuid
import os
import re
import shutil
import sys

H = os.path.dirname(os.path.abspath(__file__))
PCB = os.path.normpath(os.path.join(H, ".."))
SRC = os.path.join(PCB, "out", "C3", "KiCad")
DST = os.path.join(H, "kicad")
sys.path.insert(0, os.path.join(PCB, "fuente"))
from sexpr import parse, find  # noqa: E402

NO_MONTAR = ["TP%d" % i for i in range(1, 9)] + ["L1", "L2", "SW1", "SW2"]
SHA_ESPERADO = "b0064f316f0d3d31996e2c187bec1701bb89f43442df6fff5cae6779b14f91b0"   # placa entregada en 2a70369


def sha(p):
    return hashlib.sha256(open(p, "rb").read()).hexdigest()


def bloques(texto, cabecera):
    """Posiciones (inicio, fin) de los bloques de primer nivel que empiezan por «\\n\\t(<cabecera>»."""
    out = []
    for m in re.finditer(r"\n\t\(" + cabecera + r"\b", texto):
        i = m.start() + 1
        nivel, j, en_cadena = 0, i, False
        while True:
            c = texto[j]
            if c == '"' and texto[j - 1] != "\\":
                en_cadena = not en_cadena
            elif not en_cadena:
                if c == "(":
                    nivel += 1
                elif c == ")":
                    nivel -= 1
                    if nivel == 0:
                        out.append((i, j + 1))
                        break
            j += 1
    return out


def ref_de(bloque):
    m = re.search(r'\(property "Reference" "([^"]+)"', bloque)
    return m.group(1) if m else None


def main():
    log = []
    src_pcb = os.path.join(SRC, "AVO_GIRTH_PCB.kicad_pcb")
    if sha(src_pcb) != SHA_ESPERADO:
        sys.exit("la placa de partida no es la entregada en 2a70369 (SHA-256 distinto)")
    log.append("Placa de partida: out/C3/KiCad/AVO_GIRTH_PCB.kicad_pcb  SHA-256 %s (= entregada en 2a70369)" % SHA_ESPERADO)
    os.makedirs(DST, exist_ok=True)

    # ---------------------------------------------------------------- placa
    t = open(src_pcb, encoding="utf-8").read()
    hechos = []
    partes, last = [], 0
    for i, j in bloques(t, "footprint"):
        b = t[i:j]
        r = ref_de(b)
        if r in NO_MONTAR:
            m = re.search(r"\(attr ([a-z_ ]+)\)", b)
            if not m:
                sys.exit("%s sin (attr ...)" % r)
            base = m.group(1).split()
            nuevo = [base[0]] + ["exclude_from_pos_files", "exclude_from_bom", "dnp"]
            b = b[:m.start()] + "(attr %s)" % " ".join(nuevo) + b[m.end():]
            hechos.append("%s: (attr %s) → (attr %s)" % (r, " ".join(base), " ".join(nuevo)))
        partes += [t[last:i], b]
        last = j
    partes.append(t[last:])
    t2 = "".join(partes)
    # 3. MPN/Manufacturer de las piezas montadas
    lcsc = json.load(open(os.path.join(H, "lcsc_piezas_2026-10-29.json"), encoding="utf-8"))["parts"]
    partes, last, mpn_log = [], 0, []
    for i, j in bloques(t2, "footprint"):
        b = t2[i:j]
        r = ref_de(b)
        at = re.search(r"\(attr ([a-z_ ]+)\)", b).group(1).split()
        lc = re.search(r'\(property "LCSC" "([^"]*)"', b)
        if "dnp" not in at and lc and lc.group(1):
            info = lcsc[lc.group(1)]
            m = re.search(r'\n\t\t\(property "MPN" "([^"]*)"', b)
            k0 = m.start() + 1
            nivel, k = 0, k0
            while True:                                   # fin del bloque de la propiedad MPN
                if b[k] == "(":
                    nivel += 1
                elif b[k] == ")":
                    nivel -= 1
                    if nivel == 0:
                        break
                k += 1
            prop = b[k0:k + 1]
            nuevo_mpn = prop.replace('"MPN" "%s"' % m.group(1), '"MPN" "%s"' % info["mpn"].replace('"', "'"), 1)
            fab = prop.replace('"MPN" "%s"' % m.group(1), '"Manufacturer" "%s"' % info["maker"].replace('"', "'"), 1)
            fab = re.sub(r'\(uuid "[^"]+"\)', '(uuid "%s")' % uuid.uuid5(uuid.NAMESPACE_URL, "avo-aisler-fab-" + r), fab)
            b = b[:k0] + nuevo_mpn + "\n" + fab + b[k + 1:]
            mpn_log.append("%s,%s,%s,%s,%s" % (r, lc.group(1), m.group(1).replace(",", ";"), info["mpn"], info["maker"].replace(",", ";")))
        partes += [t2[last:i], b]
        last = j
    partes.append(t2[last:])
    t2 = "".join(partes)
    if len(mpn_log) != 85:
        sys.exit("MPN: se esperaban 85 piezas montadas con LCSC y hay %d" % len(mpn_log))
    open(os.path.join(H, "mpn_aplicados.csv"), "w", encoding="utf-8").write(
        "ref,lcsc,mpn_antes,mpn_ahora,fabricante\n" + "\n".join(sorted(mpn_log)) + "\n")
    if len(hechos) != len(NO_MONTAR):
        sys.exit("no se encontraron todas las huellas: %s" % hechos)
    n = t2.count('\t\t(rev "A")')
    if n != 1:
        sys.exit("cajetín: se esperaba un (rev \"A\")")
    t2 = t2.replace('\t\t(rev "A")', '\t\t(rev "B")')
    open(os.path.join(DST, "AVO_GIRTH_PCB.kicad_pcb"), "w", encoding="utf-8").write(t2)
    log.append("Placa: cajetín rev «A» → «B»")
    log += ["Placa: " + h for h in hechos]
    log.append("Placa: MPN de fabricante y campo Manufacturer en %d piezas montadas (mpn_aplicados.csv)" % len(mpn_log))

    # ---------------------------------------------------------------- esquema
    s = open(os.path.join(SRC, "AVO_GIRTH_PCB.kicad_sch"), encoding="utf-8").read()
    partes, last, hechos_s = [], 0, []
    for i, j in bloques(s, "symbol"):
        b = s[i:j]
        r = ref_de(b)
        if r in NO_MONTAR:
            if b.count("(in_bom yes)") != 1 or b.count("(dnp no)") != 1:
                sys.exit("símbolo %s: banderas inesperadas" % r)
            b = b.replace("(in_bom yes)", "(in_bom no)").replace("(dnp no)", "(dnp yes)")
            hechos_s.append(r)
        partes += [s[last:i], b]
        last = j
    partes.append(s[last:])
    if sorted(hechos_s) != sorted(NO_MONTAR):
        sys.exit("esquema: símbolos encontrados %s" % hechos_s)
    open(os.path.join(DST, "AVO_GIRTH_PCB.kicad_sch"), "w", encoding="utf-8").write("".join(partes))
    log.append("Esquema: dnp yes + in_bom no en " + ", ".join(NO_MONTAR))
    shutil.copy(os.path.join(SRC, "AVO_GIRTH_PCB.kicad_pro"), os.path.join(DST, "AVO_GIRTH_PCB.kicad_pro"))
    shutil.copy(os.path.join(H, "aisler_4l.kicad_dru"), os.path.join(DST, "AVO_GIRTH_PCB.kicad_dru"))
    log.append("Proyecto: .kicad_pro sin cambios; .kicad_dru = reglas de AISLER 4 capas 35 µm ENIG (solo para el DRC)")

    # ---------------------------------------------------------------- comprobación: nada más ha cambiado
    def canon(path, quitar_attr):
        tree = parse(open(path, encoding="utf-8").read())
        out = []
        for it in tree:
            if isinstance(it, list) and it and str(it[0]) == "title_block":
                continue
            if quitar_attr and isinstance(it, list) and it and str(it[0]) == "footprint":
                it = [p for p in it if not (isinstance(p, list) and p and (str(p[0]) == "attr" or (
                    str(p[0]) == "property" and p[1] in ("MPN", "Manufacturer"))))]
            out.append(repr(it))
        return out
    a, b = canon(src_pcb, True), canon(os.path.join(DST, "AVO_GIRTH_PCB.kicad_pcb"), True)
    if a != b:
        dif = sum(1 for x, y in zip(a, b) if x != y) + abs(len(a) - len(b))
        sys.exit("la copia difiere del original en %d elementos además de attr/cajetín" % dif)
    log.append("Comprobado: quitando (attr), los campos MPN/Manufacturer de las huellas y el cajetín, la placa copiada es idéntica a la original "
               "(%d elementos de primer nivel: huellas, pistas, vías, zonas con relleno, contorno, textos)" % len(a))

    # posiciones/giros/caras de las 98 huellas (lectura de la copia)
    tree = parse(t2)
    fps = []
    for it in tree:
        if isinstance(it, list) and it and str(it[0]) == "footprint":
            at = find(it, "at")
            attr = [str(x) for x in find(it, "attr")[1:]]
            fps.append((ref_de_t(it), at[1], at[2], at[3] if len(at) > 3 else 0, find(it, "layer")[1], attr))
    montar = [f for f in fps if "dnp" not in f[5]]
    log.append("Huellas: %d · para montar: %d · DNP: %d (%s)" % (
        len(fps), len(montar), len(fps) - len(montar), ", ".join(sorted(f[0] for f in fps if "dnp" in f[5]))))
    open(os.path.join(H, "posiciones_kicad_copia.csv"), "w", encoding="utf-8").write(
        "ref,x_mm,y_mm,giro,capa,atributos\n" + "".join("%s,%s,%s,%s,%s,%s\n" % (r, x, y, g, c, " ".join(at))
                                                      for r, x, y, g, c, at in sorted(fps)))
    for f in ("AVO_GIRTH_PCB.kicad_pcb", "AVO_GIRTH_PCB.kicad_sch", "AVO_GIRTH_PCB.kicad_pro", "AVO_GIRTH_PCB.kicad_dru"):
        log.append("SHA-256 kicad/%s %s" % (f, sha(os.path.join(DST, f))))
    open(os.path.join(H, "preparar_salida.txt"), "w", encoding="utf-8").write("\n".join(log) + "\n")
    print("\n".join(log))


def ref_de_t(fp):
    return [p for p in fp if isinstance(p, list) and p and str(p[0]) == "property" and p[1] == "Reference"][0][2]


if __name__ == "__main__":
    main()
