"""Comprobación de fabricación: vías dentro de un pad SMD (o a menos de 0,10 mm de su borde).

Motivo: pedido PCBA 13966268A (23/11/2026). JLCPCB avisó de que las vías abiertas dentro de los pads se tragan la
pasta de soldar (piezas torcidas, tombstoning, juntas abiertas). Se permiten solo las vías térmicas del EPAD del
módulo (pads con «41» en U4), que van entre los cuadrados del EPAD y no dentro de ellos. Solo cuentan los pads con
pasta (F.Paste / B.Paste): un punto de prueba sin pasta no se suelda y una vía junto a él no roba soldadura.

Uso: python3 via_en_pad.py placa.kicad_pcb  → imprime las vías en pad; código 1 si hay alguna.
Sin dependencias de KiCad (lee el S-expr directamente), para usarlo también en la cincha, el DOCK y la espalda.
"""
import math
import re
import sys

# Las vías van tapadas por la máscara (los Gerber F/B_Mask no tienen aberturas de vía; comprobado en 711b097). La
# abertura de un pad es su cobre + 0,05 mm (pad_to_mask_clearance), así que basta con que el cobre de la vía quede
# fuera de esa abertura con margen: 0,075 mm.
MARGEN = 0.075


def _parse(s):
    tok = re.findall(r'\(|\)|"(?:[^"\\]|\\.)*"|[^\s()]+', s)
    st = [[]]
    for t in tok:
        if t == "(":
            st.append([])
        elif t == ")":
            x = st.pop()
            st[-1].append(x)
        else:
            st[-1].append(t[1:-1] if t.startswith('"') else t)
    return st[0][0]


def _all(n, k):
    return [c for c in n if isinstance(c, list) and c and c[0] == k]


def _one(n, k):
    r = _all(n, k)
    return r[0] if r else None


def vias_en_pad(path, margen=MARGEN):
    b = _parse(open(path, encoding="utf-8").read())
    vias = []
    for v in _all(b, "via"):
        at = _one(v, "at")
        vias.append((float(at[1]), float(at[2]), float(_one(v, "size")[1])))
    hits = []
    for fp in _all(b, "footprint"):
        at = _one(fp, "at")
        fx, fy = float(at[1]), float(at[2])
        fr = float(at[3]) if len(at) > 3 else 0.0
        ref = next((p[2] for p in _all(fp, "property") if p[1] == "Reference"), "?")
        for pad in _all(fp, "pad"):
            if pad[2] != "smd":
                continue
            capas = _one(pad, "layers") or []
            if not any(str(c).endswith("Paste") for c in capas[1:]):
                continue
            pa = _one(pad, "at")
            px, py = float(pa[1]), float(pa[2])
            pr = float(pa[3]) if len(pa) > 3 else 0.0
            w, h = float(_one(pad, "size")[1]), float(_one(pad, "size")[2])
            a = math.radians(-fr)
            gx = fx + px * math.cos(a) - py * math.sin(a)
            gy = fy + px * math.sin(a) + py * math.cos(a)
            ang = math.radians(-pr)
            for vx, vy, vs in vias:
                dx, dy = vx - gx, vy - gy
                lx = dx * math.cos(-ang) - dy * math.sin(-ang)
                ly = dx * math.sin(-ang) + dy * math.cos(-ang)
                d = math.hypot(max(abs(lx) - w / 2, 0), max(abs(ly) - h / 2, 0)) - vs / 2
                if d < margen - 1e-6:
                    hits.append((ref, pad[1], round(vx, 3), round(vy, 3), round(d, 3)))
    return hits


if __name__ == "__main__":
    h = vias_en_pad(sys.argv[1])
    for x in h:
        print("%s.%s  vía (%.3f, %.3f)  separación %.3f mm" % x)
    print("vías en pad:", len(h))
    sys.exit(1 if h else 0)
