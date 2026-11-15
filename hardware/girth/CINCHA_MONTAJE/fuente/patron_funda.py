"""Patrón plano de la funda de piel (escala 1:1, mm) → ../out/PATRON/*.svg y *.dxf (DXF R12, capas).

Capas: CORTE (contorno y ventanas: cuchilla/láser), PLIEGUE (doblar), COSTURA (línea de costura a 4 mm),
AGUJEROS_COSTURA (Ø1,2 cada 4 mm, para marcar con pinzas de 4 mm o cortar con láser), REBAJE (zona a rebajar a 1,0 mm),
TALADROS (sacabocados), MARCAS (velcro, soporte, canal), TEXTO.
Todas las piezas se dibujan vistas por la flor (cara exterior). La u del modelo 3D es la X del patrón
(+X = lado IZQUIERDO del caballo).
"""
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avo_cincha_montaje as M   # noqa: E402

OUT = os.path.normpath(os.path.join(HERE, "..", "out", "PATRON"))
os.makedirs(OUT, exist_ok=True)
PASO = 4.0           # paso de costura (pinzas de 4 mm)
MARGEN = 4.0         # línea de costura a 4 mm del canto


class Pieza:
    def __init__(self, nombre, ox, oy):
        self.n = nombre; self.ox = ox; self.oy = oy
        self.ents = []        # (capa, tipo, datos)

    def poly(self, capa, pts, closed=True):
        self.ents.append((capa, "poly", ([(x + self.ox, y + self.oy) for x, y in pts], closed)))

    def rect(self, capa, x0, y0, x1, y1):
        self.poly(capa, [(x0, y0), (x1, y0), (x1, y1), (x0, y1)])

    def line(self, capa, x0, y0, x1, y1):
        self.poly(capa, [(x0, y0), (x1, y1)], False)

    def circle(self, capa, x, y, r):
        self.ents.append((capa, "circle", (x + self.ox, y + self.oy, r)))

    def text(self, x, y, s, h=6.0):
        self.ents.append(("TEXTO", "text", (x + self.ox, y + self.oy, s, h)))

    def holes_along(self, pts, closed=True, r=0.6):
        """agujeros de costura cada PASO a lo largo de la polilínea"""
        segs = list(zip(pts, pts[1:] + ([pts[0]] if closed else [])))
        acc = 0.0
        for (x0, y0), (x1, y1) in segs:
            L = math.hypot(x1 - x0, y1 - y0)
            t = (PASO - acc) if acc > 0 else 0.0
            while t <= L + 1e-9:
                self.circle("AGUJEROS_COSTURA", x0 + (x1 - x0) * t / L, y0 + (y1 - y0) * t / L, r)
                t += PASO
            acc = (L - (t - PASO)) % PASO if L > 0 else acc

    def stitch_rect(self, x0, y0, x1, y1):
        pts = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        self.poly("COSTURA", pts)
        self.holes_along(pts)


def piezas():
    e = M.P["cuero"]
    L = M.P["funda_largo"]
    VF_D, VF_T = M.VF_D, M.VF_T
    # alturas de los pliegues (fibra neutra, a mitad del grosor de la piel)
    h_del = (M.W_OUT0 + e / 2) - (M.W_IN0 + e / 2)
    W_S1 = M.W_OUT1 + 1.5 + 1.5 + e
    h_tras = (W_S1 - e / 2) - (M.W_IN0 + e / 2)
    Wo = (VF_T - e) + VF_D - e / 2           # panel exterior: del canto libre (trasero) al pliegue delantero
    Wi = VF_D + VF_T - e                     # panel interior
    solapa = 30.0
    y_del = Wo; y_int = Wo + h_del; y_tras = y_int + Wi; y_sol = y_tras + h_tras; y_fin = y_sol + solapa
    P = []
    c = Pieza("A · cuerpo de la funda (1 pieza)", 0, 0)
    x0, x1 = -L / 2, L / 2
    c.rect("CORTE", x0, 0, x1, y_fin)
    for y in (y_del, y_int, y_tras, y_sol):
        c.line("PLIEGUE", x0, y, x1, y)
    # panel exterior: y = (VF_T − e) − v
    def y_ext(v):
        return (VF_T - e) - v

    def y_in(v):
        return y_int + (v + VF_D)
    V_OFF = M.sop_v_off()
    S = M.sop_contours()
    for cx, cy in S["chic"]:
        c.circle("TALADROS", cx, y_ext(cy + V_OFF), 2.5)
    xe = M.CAP["pogo_x"]["ECG"]; ys = M.CAP["pogo_y"] + V_OFF
    c.rect("CORTE", xe - 7.0, y_ext(ys + 3.5), xe + 7.0, y_ext(ys - 3.5))
    c.text(xe + 9, y_ext(ys), "ranura cable ECG 14×7", 4)
    fx0, fx1 = S["fx"]; fy0, fy1 = S["fy"]
    c.rect("MARCAS", fx0, y_ext(fy1 + V_OFF), fx1, y_ext(fy0 + V_OFF))
    c.text(fx0, y_ext(fy0 + V_OFF) + 3, "contorno del ala del soporte (REV 6.2, sin bolsillo)", 4)
    # velcro (rizo) sobre el panel exterior, junto al canto libre
    ucut = max(abs(fx0), abs(fx1)) + 8.0
    for (a, b) in ((-L / 2, -ucut), (ucut, L / 2)):
        c.rect("MARCAS", a + 5, y_ext(VF_T - 5.0), b - 5, y_ext(VF_T - 30.0))
        c.text((a + b) / 2 - 30, y_ext(VF_T - 17.0), "velcro rizo 25 mm (coser)", 4)
    # pliegue delantero: ventana de la pestaña de la anilla D
    yw0 = y_del + (M.W_G1 - 1.0 - e / 2); yw1 = y_del + (M.W_G1 + 3.0 - e / 2)
    c.rect("CORTE", -20, yw0, 20, yw1)
    c.text(22, yw0, "paso anilla D", 4)
    # panel interior: ventanas, rebaje y costuras
    mg = M.P["e_ventana_margen"]
    for k, (ue, ve) in M.P["e_pos"].items():
        Le, We = M.P["e_tam"][k]
        wx0, wx1 = ue - Le / 2 + mg, ue + Le / 2 - mg
        wy0, wy1 = sorted((y_in(ve - We / 2 + mg), y_in(ve + We / 2 - mg)))
        c.rect("CORTE", wx0, wy0, wx1, wy1)
        rx0, rx1 = ue - Le / 2 - 1.0, ue + Le / 2 + 1.0
        ry0, ry1 = sorted((y_in(ve - We / 2 - 1.0), y_in(ve + We / 2 + 1.0)))
        c.rect("REBAJE", rx0 - 6, ry0 - 6, rx1 + 6, ry1 + 6)
        c.stitch_rect(wx0 - mg / 2, wy0 - mg / 2, wx1 + mg / 2, wy1 + mg / 2)
        c.text(wx0, wy1 + 9, "%s: ventana %d×%d, electrodo %d×%d detrás" % (k, wx1 - wx0, wy1 - wy0, Le, We), 4)
    # canal del cable (marca en el pliegue delantero, por dentro)
    for (a, b) in M.CANAL_TRAMOS:
        c.rect("MARCAS", a, y_del + 0.6, b, y_del + h_del - 0.6)
    c.text(-L / 2 + 10, y_del + h_del / 2 - 2, "canal cosido por dentro (tramos marcados)", 3.5)
    # costura de los cantos (refuerzo) a lo largo de los extremos
    for xx in (x0 + MARGEN, x1 - MARGEN):
        pts = [(xx, MARGEN), (xx, y_fin - MARGEN)]
        c.poly("COSTURA", pts, False); c.holes_along(pts, False)
    c.text(x0 + 10, -12, "A · CUERPO DE LA FUNDA · piel curtido vegetal 2,0 mm · 1 pieza · vista por la flor · "
           "+X = lado izquierdo del caballo", 7)
    c.text(x0 + 10, y_fin + 8, "solapa de cierre (velcro gancho por el lado carne)", 5)
    P.append(c)
    oy = y_fin + 60
    ph = 0.0
    # C · canal del cable
    oy2 = oy + ph + 50
    x = -L / 2
    for i, (a, bb) in enumerate(M.CANAL_TRAMOS):
        ln = bb - a
        cp = Pieza("C%d" % (i + 1), x, oy2)
        cp.rect("CORTE", 0, 0, ln, 22)
        for yy in (MARGEN, 22 - MARGEN):
            pts = [(0, yy), (ln, yy)]
            cp.poly("COSTURA", pts, False); cp.holes_along(pts, False)
        cp.text(0, -6, "C%d canal %.0f×22 (piel 1,2 mm)" % (i + 1, ln), 4)
        P.append(cp)
        x += ln + 20
    # D · trabillas
    sec = 2 * (VF_D + VF_T + 4.4) + 2 * (W_S1 + 4.4)
    for i in range(2):
        d = Pieza("D%d" % (i + 1), x + i * 40, oy2)
        d.rect("CORTE", 0, 0, 25, sec + 15)
        d.text(0, -6, "D%d trabilla 25×%.0f" % (i + 1, sec + 15), 4)
        P.append(d)
    return P, dict(ancho_cuerpo=y_fin, largo=L, h_pliegue_delantero=h_del, h_pliegue_trasero=h_tras, panel_ext=Wo,
                   panel_int=Wi)


def write_svg(P, path):
    xs, ys = [], []
    for p in P:
        for capa, t, dat in p.ents:
            if t == "poly":
                for x, y in dat[0]:
                    xs.append(x); ys.append(y)
            elif t == "circle":
                xs.append(dat[0]); ys.append(dat[1])
            else:
                xs.append(dat[0]); ys.append(dat[1])
    x0, x1, y0, y1 = min(xs) - 20, max(xs) + 20, min(ys) - 20, max(ys) + 20
    W, H = x1 - x0, y1 - y0
    sty = {"CORTE": "stroke:#000;stroke-width:0.35;fill:none", "PLIEGUE": "stroke:#06c;stroke-width:0.3;fill:none;stroke-dasharray:6,3",
           "COSTURA": "stroke:#c00;stroke-width:0.2;fill:none;stroke-dasharray:1.5,1.5",
           "AGUJEROS_COSTURA": "stroke:#c00;stroke-width:0.1;fill:none", "REBAJE": "stroke:#a60;stroke-width:0.3;fill:none;stroke-dasharray:4,1,1,1",
           "TALADROS": "stroke:#000;stroke-width:0.3;fill:none", "MARCAS": "stroke:#080;stroke-width:0.25;fill:none;stroke-dasharray:2,2"}
    out = ['<?xml version="1.0" encoding="UTF-8"?>',
           '<svg xmlns="http://www.w3.org/2000/svg" width="%.1fmm" height="%.1fmm" viewBox="%.2f %.2f %.2f %.2f">' % (W, H, x0, -y1, W, H),
           '<title>AVO cincha · patrón de la funda de piel (1:1, mm) · diseño NO VERIFICADO</title>']
    for p in P:
        out.append('<g id="%s">' % p.n.replace(" ", "_").replace("·", ""))
        for capa, t, dat in p.ents:
            if t == "poly":
                pts, closed = dat
                d = " ".join("%.3f,%.3f" % (x, -y) for x, y in pts)
                out.append('<%s points="%s" style="%s"/>' % ("polygon" if closed else "polyline", d, sty[capa]))
            elif t == "circle":
                out.append('<circle cx="%.3f" cy="%.3f" r="%.3f" style="%s"/>' % (dat[0], -dat[1], dat[2], sty[capa]))
            else:
                x, y, s, h = dat
                out.append('<text x="%.2f" y="%.2f" font-family="DejaVu Sans, Arial" font-size="%.1f" fill="#333">%s</text>' % (
                    x, -y, h, s.replace("&", "&amp;").replace("<", "&lt;")))
        out.append("</g>")
    out.append("</svg>")
    open(path, "w", encoding="utf-8").write("\n".join(out))


def write_dxf(P, path):
    """DXF R12 (AC1009) mínimo: LAYER + LINE/POLYLINE/CIRCLE/TEXT. Texto en ASCII (sin acentos)."""
    import unicodedata

    def asc(s):
        return unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode("ascii")
    capas = ["CORTE", "PLIEGUE", "COSTURA", "AGUJEROS_COSTURA", "REBAJE", "TALADROS", "MARCAS", "TEXTO"]
    col = {"CORTE": 7, "PLIEGUE": 5, "COSTURA": 1, "AGUJEROS_COSTURA": 1, "REBAJE": 30, "TALADROS": 7, "MARCAS": 3, "TEXTO": 8}
    o = ["0", "SECTION", "2", "HEADER", "9", "$ACADVER", "1", "AC1009", "9", "$INSUNITS", "70", "4", "0", "ENDSEC",
         "0", "SECTION", "2", "TABLES", "0", "TABLE", "2", "LAYER", "70", str(len(capas))]
    for c in capas:
        o += ["0", "LAYER", "2", c, "70", "0", "62", str(col[c]), "6", "CONTINUOUS"]
    o += ["0", "ENDTAB", "0", "ENDSEC", "0", "SECTION", "2", "ENTITIES"]
    for p in P:
        for capa, t, dat in p.ents:
            if t == "poly":
                pts, closed = dat
                o += ["0", "POLYLINE", "8", capa, "66", "1", "70", "1" if closed else "0"]
                for x, y in pts:
                    o += ["0", "VERTEX", "8", capa, "10", "%.4f" % x, "20", "%.4f" % y, "30", "0.0"]
                o += ["0", "SEQEND", "8", capa]
            elif t == "circle":
                o += ["0", "CIRCLE", "8", capa, "10", "%.4f" % dat[0], "20", "%.4f" % dat[1], "30", "0.0", "40", "%.4f" % dat[2]]
            else:
                x, y, s, h = dat
                o += ["0", "TEXT", "8", "TEXTO", "10", "%.3f" % x, "20", "%.3f" % y, "30", "0.0", "40", "%.2f" % h, "1", asc(s)]
    o += ["0", "ENDSEC", "0", "EOF"]
    open(path, "w", encoding="ascii").write("\n".join(o) + "\n")


def main():
    P, info = piezas()
    write_svg(P, os.path.join(OUT, "AVO_CINCHA_funda_piel_patron.svg"))
    write_dxf(P, os.path.join(OUT, "AVO_CINCHA_funda_piel_patron.dxf"))
    print("patrón:", {k: round(v, 1) for k, v in info.items()})
    return info


if __name__ == "__main__":
    main()
