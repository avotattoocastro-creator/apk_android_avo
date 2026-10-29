"""Compara los Gerber/taladros entregados (zip) con los regenerados ahora desde la placa entregada.
Ignora solo las líneas que llevan fecha u hora o la versión del programa. Uso: comparar_gerber.py zip dir salida.txt"""
import os
import re
import sys
import zipfile

zp, gdir, out = sys.argv[1:4]
IGN = re.compile(r"(CreationDate|GenerationSoftware|G04 Created by|G04 #@! TF\.|^; #@! TF\.|^;\s*(DRILL file|FORMAT|Created)|"
                 r"date|Date|\d{4}-\d{2}-\d{2})")
z = zipfile.ZipFile(zp)
L = []
ok = True
names = sorted(z.namelist())
regen = sorted(os.listdir(gdir))
L.append("entregados: %d ficheros · regenerados: %d" % (len(names), len(regen)))
for n in names:
    if n not in regen:
        L.append("FALTA al regenerar: %s" % n); ok = False; continue
    a = [l for l in z.read(n).decode("utf-8", "replace").splitlines() if not IGN.search(l)]
    b = [l for l in open(os.path.join(gdir, n), encoding="utf-8", errors="replace").read().splitlines() if not IGN.search(l)]
    same = a == b
    ok &= same
    L.append("%-45s %s (%d líneas comparadas)" % (n, "IGUAL" if same else "DISTINTO", len(a)))
    if not same:
        for i, (x, y) in enumerate(zip(a, b)):
            if x != y:
                L.append("   primera diferencia en la línea %d: %r ≠ %r" % (i, x[:80], y[:80])); break
for n in regen:
    if n not in names:
        L.append("de más al regenerar: %s" % n)
L.append("RESULTADO: %s" % ("los Gerber entregados corresponden a la placa entregada" if ok else "HAY DIFERENCIAS"))
open(out, "w").write("\n".join(L) + "\n")
print("\n".join(L))
