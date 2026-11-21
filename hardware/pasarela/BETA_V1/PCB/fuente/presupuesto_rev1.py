"""AVO PASARELA LTE BETA V1 · REV 1 (Cat 4 + AMOLED) · paquete SOLO PARA PRESUPUESTO en JLCPCB.

NO SIRVE PARA FABRICAR: no hay esquema ni pistas. Las capas de cobre van vacías (solo una marca en una esquina).
Sirve para que JLCPCB calcule el precio real de la placa (tamaño, 4 capas, 1,0 mm, ENIG) y del montaje (BOM + CPL
con los códigos LCSC de las piezas elegidas y una posición aproximada de cada una).

Uso: python3 presupuesto_rev1.py
Escribe en ../out/PRESUPUESTO/: Gerber ZIP, BOM, CPL, colocación SVG y un resumen.
Origen en el centro de la placa, x a la derecha, y hacia arriba, mm, vista desde la cara F (componentes).
"""
import csv
import io
import os
import sys
import zipfile

AQUI = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(AQUI, "..", "out", "PRESUPUESTO")
NOMBRE = "AVO_PASARELA_BETA_V1_REV1_SOLO_PRESUPUESTO"

PLACA = dict(ancho=60.0, alto=40.0, radio=2.0, espesor=1.0, capas=4, acabado="ENIG")
TALADROS = [(-27.0, -17.0), (27.0, -17.0)]
D_TALADRO = 2.2
MARGEN, HOLGURA, R_LIBRE = 0.5, 0.3, 2.4

# Bloques en la cara F: (id, x0, y0, ancho, alto, altura, descripción)
BLOQUES = [
    ("U2", -1.0, -10.5, 30.0, 30.0, 2.9, "SIMCom SIM7600E-H (LTE Cat 4, LCC 30 × 30)"),
    ("U1", -29.5, 0.3, 18.0, 19.2, 3.2, "ESP32-S3-WROOM-1U-N16R8 (U.FL)"),
    ("LVL", -11.0, 12.0, 9.5, 7.5, 1.2, "TXS0108E + pasivos"),
    ("MDM", -11.0, 4.0, 9.5, 7.5, 1.1, "PWRKEY/RESET (2 NPN) + Q1 corte del módem"),
    ("USB", -11.0, -3.0, 9.5, 6.5, 1.0, "TS3USB221A + USBLC6"),
    ("PWR", -29.5, -10.5, 18.0, 10.3, 1.2, "BQ24072 + TPS63802 + XC6206 + MAX17048 + TTP223"),
    ("NAND", -11.0, -10.5, 9.5, 7.0, 0.8, "W25N02KV 256 MB"),
    ("BULK", -1.0, -19.5, 13.0, 8.5, 1.0, "VBAT del módem: 4 × 47 µF + TVS"),
    ("RF", 12.5, -19.5, 11.5, 8.5, 1.25, "2 × U.FL LTE + redes en pi"),
    ("POGO", -24.0, -19.5, 22.5, 8.5, 1.1, "pogo 5 contactos + PTC + TVS + LED + puntos de prueba"),
]
# Cara B: conector de la pantalla (debajo del panel AMOLED, que va pegado en B)
BLOQUES_B = [("J_LCD", -6.0, -17.0, 14.0, 4.0, 1.0, "FPC 0,5 mm de la AMOLED 2,06\" (por elegir con el panel)")]

# Lista de piezas: (designadores, valor, huella, código LCSC o "", bloque)
PIEZAS = [
    (["U1"], "ESP32-S3-WROOM-1U-N16R8", "ESP32-S3-WROOM-1U", "C3013946", "U1"),
    (["U2"], "SIM7600E-H", "SIMCom_LCC_30x30", "C5338795", "U2"),
    (["U3"], "W25N02KVZEIR", "WSON-8-EP_6x8", "C3010298", "NAND"),
    (["U4"], "BQ24072RGTR", "VQFN-16_3x3", "C140288", "PWR"),
    (["U5"], "TPS63802DLAR", "VSON-10_2x3", "C2845237", "PWR"),
    (["U6"], "MAX17048G+T10", "TDFN-8_2x2", "C2682616", "PWR"),
    (["U7"], "TTP223-BA6-TD", "SOT-23-6", "C42422127", "PWR"),
    (["U8"], "XC6206P332MR", "SOT-23", "C5446", "PWR"),
    (["U9"], "TXS0108EPWR", "TSSOP-20", "C17206", "LVL"),
    (["U10"], "TS3USB221ARSER", "UQFN-10_1.5x2", "C128396", "USB"),
    (["U11"], "USBLC6-2SC6", "SOT-23-6", "C7519", "USB"),
    (["Q1", "Q2"], "AO3401A", "SOT-23", "C15127", "MDM"),
    (["Q3", "Q4"], "MMBT3904", "SOT-23", "C20526", "MDM"),
    (["D1", "D2"], "BAT54C", "SOT-23", "C2135", "PWR"),
    (["D3", "D4"], "TVS 5 V", "D_SOD-323", "C2827694", "POGO"),
    (["F1"], "PTC 1,5 A", "Fuse_1206", "C20802", "POGO"),
    (["L1"], "1 µH 2016", "IND_2016", "C97016", "PWR"),
    (["J1", "J2"], "U.FL LTE (principal, diversidad)", "U.FL", "C88373", "RF"),
    (["J3"], "U.FL 2,4 GHz", "U.FL", "C88373", "U1"),
    (["LED1"], "SK6812SIDE-A", "SK6812SIDE-A", "C5378721", "POGO"),
    (["C1", "C2", "C3", "C4"], "47u 6V3", "C_0805", "C16780", "BULK"),
    (["C%d" % i for i in range(5, 11)], "22u 10V", "C_0805", "C45783", "PWR"),
    (["C%d" % i for i in range(11, 17)], "10u 25V", "C_0603", "C96446", "PWR"),
    (["C%d" % i for i in range(17, 25)], "1u", "C_0402", "C52923", "LVL"),
    (["C%d" % i for i in range(25, 51)], "100n", "C_0402", "C1525", "MDM"),
    (["C%d" % i for i in range(51, 55)], "10n", "C_0402", "C15195", "RF"),
    (["R%d" % i for i in range(1, 15)], "10k", "R_0402", "C25744", "MDM"),
    (["R%d" % i for i in range(15, 25)], "100k", "R_0402", "C25741", "PWR"),
    (["R%d" % i for i in range(25, 31)], "1k", "R_0402", "C11702", "LVL"),
    (["R%d" % i for i in range(31, 35)], "22R", "R_0402", "C25092", "USB"),
    (["R%d" % i for i in range(35, 41)], "0R (redes en pi)", "R_0402", "C17168", "RF"),
    (["R41", "R42"], "2k2", "R_0402", "C25879", "PWR"),
    (["R43", "R44"], "1M", "R_0402", "C26083", "PWR"),
    (["R45"], "68k", "R_0402", "C36871", "PWR"),
    (["R46"], "1k5", "R_0402", "C25867", "PWR"),
    (["R47"], "2k", "R_0402", "C4109", "PWR"),
    (["RT1"], "NTC 10k B3380", "R_0402", "C77131", "PWR"),
]
# Fuera del montaje de JLCPCB (se compran aparte o los pone el operador)
APARTE = [
    ("eSIM MFF2 (U12)", "la suministra el operador elegido; se suelda en JLC como pieza consignada"),
    ("Pantalla AMOLED 2,06\" 410 × 502 CO5300 con táctil y cristal", "se compra aparte; define el conector J_LCD"),
    ("Conector FPC de la pantalla (J_LCD, cara B)", "se elige con el panel concreto"),
    ("2 antenas LTE flexibles + 1 antena 2,4 GHz FPC (U.FL)", "se compran aparte"),
    ("Batería LiPo ≈ 1500 mAh", "se compra aparte"),
]


def comprobar():
    err = []
    W, H = PLACA["ancho"] / 2, PLACA["alto"] / 2
    for cara, lista in (("F", BLOQUES), ("B", BLOQUES_B)):
        for b in lista:
            i, x0, y0, w, h = b[:5]
            x1, y1 = x0 + w, y0 + h
            if x0 < -W + MARGEN - 1e-6 or x1 > W - MARGEN + 1e-6 or y0 < -H + MARGEN - 1e-6 or y1 > H - MARGEN + 1e-6:
                err.append(f"{cara}:{i} fuera del margen")
            for tx, ty in TALADROS:
                cx, cy = min(max(tx, x0), x1), min(max(ty, y0), y1)
                if ((cx - tx) ** 2 + (cy - ty) ** 2) ** 0.5 < R_LIBRE:
                    err.append(f"{cara}:{i} invade el taladro ({tx}, {ty})")
        for a in range(len(lista)):
            for c in range(a + 1, len(lista)):
                A, C = lista[a], lista[c]
                if (A[1] < C[1] + C[3] + HOLGURA and C[1] < A[1] + A[3] + HOLGURA and
                        A[2] < C[2] + C[4] + HOLGURA and C[2] < A[2] + A[4] + HOLGURA):
                    err.append(f"{cara}:{A[0]} y {C[0]} se solapan o no respetan {HOLGURA} mm")
    return err


def posiciones():
    """Reparte cada pieza dentro de su bloque en una rejilla (posición orientativa para el CPL)."""
    bloq = {b[0]: b for b in BLOQUES}
    cont = {k: 0 for k in bloq}
    filas = []
    for desig, val, fp, lcsc, blk in PIEZAS:
        _, x0, y0, w, h = bloq[blk][:5]
        for d in desig:
            if d in ("U1", "U2"):
                x, y = x0 + w / 2, y0 + h / 2
            else:
                n = cont[blk]; cont[blk] += 1
                cols = max(1, int(w // 2.2))
                x = x0 + 1.1 + (n % cols) * 2.2
                y = y0 + h - 1.1 - (n // cols) * 1.8
                y = max(y, y0 + 0.6)
            filas.append((d, round(x, 2), round(y, 2), "Top", 0))
    return filas


def gerber_outline():
    W, H, r = PLACA["ancho"] / 2, PLACA["alto"] / 2, PLACA["radio"]
    f = lambda v: f"{int(round(v * 1e6)):d}"
    g = ["%FSLAX46Y46*%", "%MOMM*%", "%LPD*%", "%ADD10C,0.100*%", "D10*", "G75*"]
    pts = [(-W + r, -H), (W - r, -H)]
    g.append(f"X{f(-W + r)}Y{f(-H)}D02*")
    g.append(f"G01*X{f(W - r)}Y{f(-H)}D01*")
    g.append(f"G03*X{f(W)}Y{f(-H + r)}I0J{f(r)}D01*")
    g.append(f"G01*X{f(W)}Y{f(H - r)}D01*")
    g.append(f"G03*X{f(W - r)}Y{f(H)}I{f(-r)}J0D01*")
    g.append(f"G01*X{f(-W + r)}Y{f(H)}D01*")
    g.append(f"G03*X{f(-W)}Y{f(H - r)}I0J{f(-r)}D01*")
    g.append(f"G01*X{f(-W)}Y{f(-H + r)}D01*")
    g.append(f"G03*X{f(-W + r)}Y{f(-H)}I{f(r)}J0D01*")
    g.append("M02*")
    return "\n".join(g) + "\n"


def gerber_marca(capa):
    f = lambda v: f"{int(round(v * 1e6)):d}"
    W, H = PLACA["ancho"] / 2, PLACA["alto"] / 2
    return "\n".join(["%FSLAX46Y46*%", "%MOMM*%", f"G04 {capa} SOLO PRESUPUESTO - sin pistas*", "%LPD*%",
                      "%ADD10R,1.000X1.000*%", "D10*", f"X{f(W - 3)}Y{f(H - 3)}D03*", "M02*"]) + "\n"


def gerber_vacia(capa):
    return "\n".join(["%FSLAX46Y46*%", "%MOMM*%", f"G04 {capa} SOLO PRESUPUESTO*", "%LPD*%", "M02*"]) + "\n"


def taladros():
    lineas = ["M48", "; SOLO PRESUPUESTO - taladros NPTH de la caja", "METRIC,TZ", f"T1C{D_TALADRO:.3f}", "%", "G90", "T1"]
    for x, y in TALADROS:
        lineas.append(f"X{x:.3f}Y{y:.3f}")
    lineas.append("M30")
    return "\n".join(lineas) + "\n"


def svg(ruta):
    esc, pad = 11.0, 40
    W, H = PLACA["ancho"], PLACA["alto"]
    tx = lambda x: pad + (x + W / 2) * esc
    ty = lambda y: pad + (H / 2 - y) * esc
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{W*esc+2*pad:.0f}" height="{H*esc+2*pad+50:.0f}" '
         f'font-family="DejaVu Sans, Arial" font-size="10"><rect width="100%" height="100%" fill="white"/>',
         f'<rect x="{tx(-W/2)}" y="{ty(H/2)}" width="{W*esc}" height="{H*esc}" rx="{PLACA["radio"]*esc}" fill="#2f6b3a" stroke="black"/>']
    col = {"U2": "#ffe0c2", "U1": "#cfe3ff", "RF": "#ffd0d0", "BULK": "#ffe9a8", "NAND": "#d6f5d6", "POGO": "#dddddd"}
    for i, x0, y0, w, h, alt, d in BLOQUES:
        s.append(f'<rect x="{tx(x0):.1f}" y="{ty(y0+h):.1f}" width="{w*esc:.1f}" height="{h*esc:.1f}" fill="{col.get(i, "#f4f4f4")}" stroke="#222"/>')
        s.append(f'<text x="{tx(x0)+3:.1f}" y="{ty(y0+h)+12:.1f}" font-weight="bold">{i}</text>')
        s.append(f'<text x="{tx(x0)+3:.1f}" y="{ty(y0+h)+23:.1f}" font-size="8">{w:.1f}×{h:.1f}×{alt:.1f}</text>')
    # pantalla en B (contorno discontinuo)
    s.append(f'<rect x="{tx(-21.55):.1f}" y="{ty(17.4):.1f}" width="{43.1*esc:.1f}" height="{34.8*esc:.1f}" fill="none" '
             f'stroke="#40a0ff" stroke-width="2" stroke-dasharray="6,4"/>')
    s.append(f'<text x="{tx(-21.2):.1f}" y="{ty(-17.4)+14:.1f}" fill="#40a0ff" font-weight="bold">AMOLED 2,06" en la cara B (43,1 × 34,8)</text>')
    for x, y in TALADROS:
        s.append(f'<circle cx="{tx(x)}" cy="{ty(y)}" r="{D_TALADRO/2*esc}" fill="white" stroke="black"/>')
    s.append(f'<text x="{pad}" y="{H*esc+2*pad+20:.0f}" font-size="11" font-weight="bold">AVO PASARELA LTE BETA V1 · REV 1 '
             f'(Cat 4 + AMOLED) · {W:.0f} × {H:.0f} × {PLACA["espesor"]:.1f} mm · 4 capas · SOLO PRESUPUESTO</text>')
    s.append("</svg>")
    with open(ruta, "w", encoding="utf-8") as fh:
        fh.write("\n".join(s))


def main():
    err = comprobar()
    for e in err:
        print("ERROR:", e)
    if err:
        return 1
    os.makedirs(OUT, exist_ok=True)
    # Gerber
    zpath = os.path.join(OUT, NOMBRE + "_GERBER.zip")
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        z.writestr(NOMBRE + ".GKO", gerber_outline())
        z.writestr(NOMBRE + ".GTL", gerber_marca("F.Cu"))
        z.writestr(NOMBRE + ".G1", gerber_vacia("In1.Cu"))
        z.writestr(NOMBRE + ".G2", gerber_vacia("In2.Cu"))
        z.writestr(NOMBRE + ".GBL", gerber_marca("B.Cu"))
        for ext in ("GTS", "GBS", "GTO", "GBO", "GTP"):
            z.writestr(NOMBRE + "." + ext, gerber_vacia(ext))
        z.writestr(NOMBRE + ".DRL", taladros())
        z.writestr("LEEME.txt", "SOLO PARA PRESUPUESTO. Sin esquema ni pistas. NO FABRICAR.\n"
                   "Pedido de referencia: 4 capas, 1,0 mm, ENIG, 60 x 40 mm.\n")
    # BOM
    with open(os.path.join(OUT, NOMBRE + "_BOM_JLCPCB.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["Comment", "Designator", "Footprint", "LCSC Part #"])
        for desig, val, fp, lcsc, _ in PIEZAS:
            w.writerow([val, ",".join(desig), fp, lcsc])
    # CPL
    with open(os.path.join(OUT, NOMBRE + "_CPL_JLCPCB.csv"), "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["Designator", "Mid X", "Mid Y", "Layer", "Rotation"])
        for d, x, y, l, r in posiciones():
            w.writerow([d, f"{x}mm", f"{y}mm", l, r])
    svg(os.path.join(OUT, NOMBRE + "_COLOCACION.svg"))
    n = sum(len(p[0]) for p in PIEZAS)
    unicas = len(PIEZAS)
    with open(os.path.join(OUT, "LEEME.md"), "w", encoding="utf-8") as fh:
        fh.write(f"# {NOMBRE}\n\n**SOLO PARA PRESUPUESTO. NO FABRICAR** (sin esquema ni pistas).\n\n"
                 f"- Placa: {PLACA['ancho']:.0f} × {PLACA['alto']:.0f} mm, {PLACA['capas']} capas, {PLACA['espesor']} mm, {PLACA['acabado']}.\n"
                 f"- Montaje: {n} piezas, {unicas} referencias distintas, una cara (F).\n\n## Aparte (no los monta JLCPCB)\n")
        for a, b in APARTE:
            fh.write(f"- {a}: {b}\n")
    print(f"OK · {n} piezas, {unicas} referencias · {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
