"""Vías dentro de pads SMD o pegadas a ellos (24/11/2026: JLCPCB paró el pedido W2026112308485306 por «hole in pad»).

Lee la placa KiCad tal cual se fabrica (no el generador) y lista cada vía cuyo centro queda a menos de VIA_PAD_GAP del
borde de un pad SMD, de cualquier red. Con una vía así, la soldadura se escapa por el taladro: piezas torcidas,
«tombstoning», LGA/DFN sin soldar.

Uso:  python vias_en_pad.py <placa.kicad_pcb>   → lista; código 1 si hay alguna
"""
import math
import re
import sys

VIA_PAD_GAP = 0.45   # = build.VIA_PAD_GAP: radio 0,25 + máscara 0,05 + franja ≥ 0,10 + margen 0,05 (objetivo)
GATE_GAP = 0.35      # puerta: el anillo de la vía (Ø 0,5) a ≥ 0,10 mm del cobre del pad (vía tapada con máscara)


def _blocks(text, key):
    out = []
    for m in re.finditer(r"\(" + key + r"\s", text):
        j = k = m.start()
        d = 0
        while True:
            c = text[k]
            if c == "(":
                d += 1
            elif c == ")":
                d -= 1
                if d == 0:
                    break
            k += 1
        out.append(text[j:k + 1])
    return out


def smd_pads(text):
    pads = []
    for f in _blocks(text, "footprint"):
        ref = re.search(r'\(property\s+"Reference"\s+"([^"]+)"', f).group(1)
        m = re.search(r'\n\s*\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)', f)
        fx, fy, fr = float(m.group(1)), float(m.group(2)), float(m.group(3) or 0)
        for p in _blocks(f, "pad"):
            pm = re.match(r'\(pad\s+"([^"]*)"\s+(\w+)\s+(\w+)', p)
            if pm.group(2) != "smd":
                continue
            a = re.search(r'\(at ([-\d.]+) ([-\d.]+)(?: ([-\d.]+))?\)', p)
            sz = re.search(r'\(size ([-\d.]+) ([-\d.]+)\)', p)
            px, py, pr = float(a.group(1)), float(a.group(2)), float(a.group(3) or 0)
            r = math.radians(-fr)
            x = fx + px * math.cos(r) - py * math.sin(r)
            y = fy + px * math.sin(r) + py * math.cos(r)
            net = re.search(r'\(net\s+\d+\s+"([^"]*)"\s*\)', p)
            pads.append(dict(ref=ref, pin=pm.group(1), x=x, y=y, w=float(sz.group(1)), h=float(sz.group(2)),
                             rot=pr, net=net.group(1) if net else "", circle=pm.group(3) == "circle"))
    return pads


def vias(text):
    out = []
    for v in _blocks(text, "via"):
        a = re.search(r"\(at ([-\d.]+) ([-\d.]+)\)", v)
        sz = re.search(r"\(size ([-\d.]+)\)", v)
        out.append((float(a.group(1)), float(a.group(2)), float(sz.group(1))))
    return out


def gap(pad, vx, vy):
    """Distancia del punto al rectángulo del pad (0 si está dentro)."""
    dx, dy = vx - pad["x"], vy - pad["y"]
    if pad["circle"]:
        return max(math.hypot(dx, dy) - pad["w"] / 2, 0)
    ang = math.radians(pad["rot"])
    lx = dx * math.cos(ang) + dy * math.sin(ang)
    ly = -dx * math.sin(ang) + dy * math.cos(ang)
    return math.hypot(max(abs(lx) - pad["w"] / 2, 0), max(abs(ly) - pad["h"] / 2, 0))


def check(path, limit=GATE_GAP):
    text = open(path, encoding="utf-8").read()
    pads = smd_pads(text)
    bad = []
    for (vx, vy, vd) in vias(text):
        for pad in pads:
            g = gap(pad, vx, vy)
            if g < limit - 1e-3:
                bad.append(dict(ref=pad["ref"], pin=pad["pin"], net=pad["net"], via=(round(vx, 3), round(vy, 3)),
                                gap=round(g, 3), inside=g == 0))
    return bad, len(pads)


if __name__ == "__main__":
    bad, n = check(sys.argv[1])
    inside = sum(1 for b in bad if b["inside"])
    print("Pads SMD: %d · vías dentro de pad: %d · vías a < %.2f mm de un pad: %d" % (n, inside, GATE_GAP, len(bad)))
    for b in bad:
        print("  %s.%s (%s) vía %s a %.3f mm%s" % (b["ref"], b["pin"], b["net"], b["via"], b["gap"],
                                                   " — DENTRO" if b["inside"] else ""))
    sys.exit(1 if bad else 0)
