"""AVO PASARELA LTE BETA V1 · PCB REV 0 (anteproyecto): colocación por bloques con medidas de hoja de datos.

No es una placa de KiCad todavía: sirve para fijar el contorno, comprobar que todo cabe sin solapes y dar al CAD
las medidas de partida. Las cotas marcadas (E) son estimadas y se confirman al generar las huellas reales.

Uso: python3 place_rev0.py
Escribe: colocacion_rev0.json, ../pcb_mecanica.json y ../../DOCS/colocacion_pcb_rev0.svg
Origen en el centro de la placa, x hacia la derecha, y hacia arriba, mm. Todo en la cara F salvo que se diga.
"""
import json
import os
import sys

AQUI = os.path.dirname(os.path.abspath(__file__))

PLACA = dict(ancho=54.0, alto=32.0, radio_esquina=2.0, espesor=1.0, capas=4, acabado="ENIG")
MARGEN_BORDE = 0.5      # cobre y cuerpos de componente al canto (salvo antena del módulo, que va a ras)
HOLGURA = 0.3           # entre envolventes de bloques (incluye pasivos propios dentro de la envolvente)
TALADROS = [(-24.0, -13.0), (24.0, -13.0)]  # 2 × Ø2,2 para M2 (los de arriba no caben junto a los módulos)
D_TALADRO = 2.2
R_TALADRO_LIBRE = 2.4   # radio libre de cobre y piezas alrededor

# (ref, descripción, x0, y0, ancho, alto, altura_mm, fuente_cota, notas)
BLOQUES = [
    ("U1", "ESP32-S3-WROOM-1-N16R8 (antena PCB a la izquierda)", -27.0, -2.0, 25.5, 18.0, 3.1, "S",
     "antena a ras del canto izquierdo; sin cobre en ninguna capa bajo los 6 mm de la antena"),
    ("U2", "Quectel EG800Q-EU (LTE Cat 1 bis)", 7.5, -0.8, 17.7, 15.8, 2.4, "S",
     "LGA, MSL 3, rayos X en JLC; tapa metálica"),
    ("U8", "TXS0108E (1,8 V del módem <-> 3,3 V) + pasivos", -1.1, 9.5, 4.2, 5.0, 1.0, "E",
     "TX, RX, RTS, CTS, DTR, RI, STATUS, NET_STATUS"),
    ("Q2Q3", "2 × NPN PWRKEY/RESET_N + resistencias", -1.1, 2.5, 4.2, 6.2, 1.1, "E",
     "colector abierto, como la referencia de Quectel"),
    ("J1", "U.FL LTE + red en pi (3 × 0402)", 20.0, -5.2, 7.0, 4.0, 1.25, "E",
     "U.FL en el canto derecho; línea de 50 ohm corta hasta ANT_MAIN"),
    ("U3", "eSIM MFF2 (DFN-8 6 × 5) + 4 × 33 pF + TVS", 9.0, -9.5, 7.0, 6.5, 0.9, "S",
     "a menos de 10 mm de los pines USIM del módem"),
    ("BULK", "VBAT del módem: 1 × 220 uF 3528 + 2 × 100 uF 1206 + Q1 PMOS + TVS", 16.5, -10.4, 9.0, 4.8, 2.1, "E",
     "pegado a los pines VBAT_BB/VBAT_RF; pista >= 2 mm"),
    ("U4", "SPI NAND W25N02KV (2 Gbit, WSON-8 8 × 6)", -1.8, -10.0, 8.2, 6.2, 0.8, "S",
     "256 MB para guardar sesiones .avr antes de subirlas"),
    ("TP", "Puntos de prueba: USB del módem, UART de depuración, BOOT", 14.5, -15.5, 6.5, 4.0, 0.0, "E",
     "pads de 1 mm; para actualizar el módem por USB en el taller"),
    ("BAT", "Pads de batería + fusible PTC 1812", 5.5, -15.5, 8.5, 4.5, 1.0, "E",
     "batería LiPo soldada bajo la placa"),
    ("U5", "Cargador BQ24072 (QFN-16 3 × 3) + pasivos", -26.5, -10.0, 6.0, 5.5, 1.0, "E", "igual que el casco V5"),
    ("U6", "Buck-boost TPS63802 + bobina 2016 (3V3)", -20.0, -10.0, 6.2, 5.5, 1.2, "E",
     "aguanta las caídas de la batería con los picos del módem"),
    ("U7", "MAX17048 (TDFN 2 × 2) + TTP223 (táctil)", -13.4, -10.0, 2.8, 5.5, 1.0, "E", "medidor e I2C 0x36"),
    ("J2", "Pogo 5 contactos por hilos (VBUS, D-, D+, GND, AUX)", -20.0, -15.5, 13.0, 3.0, 0.0, "E",
     "mismo pogo que el casco V5; compatible con el DOCK V1"),
    ("ESD", "USBLC6-2SC6 + PTC VBUS + TVS VBUS", -6.6, -15.5, 6.0, 4.5, 1.1, "E", ""),
    ("LED", "LED RGB de estado (SK6812 2020)", 0.0, -15.5, 5.0, 4.5, 0.9, "E", "luz por la cápsula"),
]


CORTO = {"U1": "U1 · ESP32-S3-WROOM-1", "U2": "U2 · EG800Q-EU (LTE)", "U4": "U4 · NAND 256 MB",
         "U3": "U3 · eSIM", "BULK": "VBAT módem", "J1": "J1 · U.FL", "J2": "J2 · pogo 5", "BAT": "BAT + PTC",
         "U5": "U5 · carga", "U6": "U6 · 3V3", "TP": "TP", "ESD": "ESD", "LED": "LED"}


def caja(b):
    _, _, x0, y0, w, h, *_ = b
    return x0, y0, x0 + w, y0 + h


def comprobar():
    errores = []
    W, H = PLACA["ancho"] / 2, PLACA["alto"] / 2
    for b in BLOQUES:
        x0, y0, x1, y1 = caja(b)
        m = 0.0 if b[0] in ("U1", "J1", "J2") else MARGEN_BORDE  # antenas y conectores van a ras
        if x0 < -W + m - 1e-6 or x1 > W - m + 1e-6 or y0 < -H + m - 1e-6 or y1 > H - m + 1e-6:
            errores.append(f"{b[0]} se sale de la placa o del margen: ({x0:.1f},{y0:.1f})-({x1:.1f},{y1:.1f})")
        for (tx, ty) in TALADROS:
            cx, cy = min(max(tx, x0), x1), min(max(ty, y0), y1)
            if ((cx - tx) ** 2 + (cy - ty) ** 2) ** 0.5 < R_TALADRO_LIBRE:
                errores.append(f"{b[0]} invade el taladro ({tx},{ty})")
    for i, a in enumerate(BLOQUES):
        for c in BLOQUES[i + 1:]:
            ax0, ay0, ax1, ay1 = caja(a)
            cx0, cy0, cx1, cy1 = caja(c)
            if ax0 < cx1 + HOLGURA and cx0 < ax1 + HOLGURA and ay0 < cy1 + HOLGURA and cy0 < ay1 + HOLGURA:
                sx = min(ax1, cx1) - max(ax0, cx0)
                sy = min(ay1, cy1) - max(ay0, cy0)
                if sx > -HOLGURA and sy > -HOLGURA:
                    errores.append(f"{a[0]} y {c[0]} se solapan o no respetan {HOLGURA} mm")
    return errores


def ocupacion():
    area = sum(b[4] * b[5] for b in BLOQUES)
    return area, PLACA["ancho"] * PLACA["alto"]


def svg(ruta):
    esc = 12.0
    W, H = PLACA["ancho"], PLACA["alto"]
    pad = 40
    ancho_px, alto_px = W * esc + 2 * pad, H * esc + 2 * pad + 60
    tx = lambda x: pad + (x + W / 2) * esc
    ty = lambda y: pad + (H / 2 - y) * esc
    colores = {"U1": "#cfe3ff", "U2": "#ffe0c2", "J1": "#ffd0d0", "BULK": "#ffe9a8", "U3": "#e2d4ff",
               "U4": "#d6f5d6", "J2": "#dddddd"}
    s = [f'<svg xmlns="http://www.w3.org/2000/svg" width="{ancho_px:.0f}" height="{alto_px:.0f}" '
         f'font-family="DejaVu Sans, Arial" font-size="10">',
         f'<rect width="100%" height="100%" fill="white"/>',
         f'<rect x="{tx(-W/2)}" y="{ty(H/2)}" width="{W*esc}" height="{H*esc}" rx="{PLACA["radio_esquina"]*esc}" '
         f'fill="#2f6b3a" stroke="black" stroke-width="1.5"/>']
    # zona sin cobre de la antena del ESP32 y de la antena LTE
    for b in BLOQUES:
        ref, desc, x0, y0, w, h, alt, fuente, _ = b
        col = colores.get(ref, "#f4f4f4")
        s.append(f'<rect x="{tx(x0):.1f}" y="{ty(y0+h):.1f}" width="{w*esc:.1f}" height="{h*esc:.1f}" '
                 f'fill="{col}" stroke="#222" stroke-width="0.8"/>')
        etiqueta = CORTO.get(ref, ref) if w * esc >= 60 else ref
        s.append(f'<text x="{tx(x0)+3:.1f}" y="{ty(y0+h)+12:.1f}" font-weight="bold">{etiqueta}</text>')
        s.append(f'<text x="{tx(x0)+3:.1f}" y="{ty(y0+h)+23:.1f}" font-size="8">{w:.1f}×{h:.1f}×{alt:.1f}'
                 f'{" (E)" if fuente == "E" else ""}</text>')
    s.append(f'<rect x="{tx(-27)}" y="{ty(16)}" width="{6*esc}" height="{18*esc}" fill="#ff4040" fill-opacity="0.15" stroke="#ff4040" '
             f'stroke-dasharray="4,3" stroke-width="1.5"/>')
    for (x, y) in TALADROS:
        s.append(f'<circle cx="{tx(x)}" cy="{ty(y)}" r="{D_TALADRO/2*esc}" fill="white" stroke="black"/>')
    s.append(f'<text x="{tx(-27)+2}" y="{ty(16)-6}" fill="#c00000">antena BLE/Wi-Fi: sin cobre 6 mm</text>')
    s.append(f'<text x="{tx(27)-230}" y="{ty(-16)+16}" fill="#c00000">U.FL LTE → antena flexible en la cápsula</text>')
    s.append(f'<text x="{pad}" y="{alto_px-34}" font-size="12" font-weight="bold">AVO PASARELA LTE BETA V1 · PCB REV 0 '
             f'(anteproyecto) · {W:.0f} × {H:.0f} × {PLACA["espesor"]:.1f} mm, {PLACA["capas"]} capas, cara F</text>')
    a, t = ocupacion()
    s.append(f'<text x="{pad}" y="{alto_px-16}" font-size="10">Envolventes: {a:.0f} de {t:.0f} mm² ({100*a/t:.0f} %). '
             f'Altura máx. de componentes 3,1 mm (U1). (E) = cota estimada.</text>')
    # cotas
    s.append(f'<text x="{tx(0)-15}" y="{ty(16)-20}" font-size="11">← {W:.0f} mm →</text>')
    s.append('</svg>')
    with open(ruta, "w", encoding="utf-8") as f:
        f.write("\n".join(s))


def main():
    err = comprobar()
    a, t = ocupacion()
    print(f"Placa {PLACA['ancho']} × {PLACA['alto']} mm · envolventes {a:.0f}/{t:.0f} mm² ({100*a/t:.0f} %)")
    for e in err:
        print("ERROR:", e)
    datos = dict(placa=PLACA, taladros=TALADROS, diametro_taladro=D_TALADRO,
                 bloques=[dict(ref=b[0], descripcion=b[1], x0=b[2], y0=b[3], ancho=b[4], alto=b[5], altura=b[6],
                               cota=("hoja de datos" if b[7] == "S" else "estimada"), notas=b[8]) for b in BLOQUES],
                 altura_max_componentes=max(b[6] for b in BLOQUES), errores=err)
    with open(os.path.join(AQUI, "colocacion_rev0.json"), "w", encoding="utf-8") as f:
        json.dump(datos, f, ensure_ascii=False, indent=1)
    mec = dict(placa=dict(PLACA, vista="cara F (componentes)"), taladros=TALADROS, diametro_taladro=D_TALADRO,
               altura_max_cara_F=datos["altura_max_componentes"],
               conectores=dict(UFL_LTE=[26.0, -3.2], POGO_5=[-13.5, -14.0]),
               antena_esp32_sin_cobre=dict(x0=-27.0, x1=-21.0, y0=-2.0, y1=16.0))
    with open(os.path.join(AQUI, "..", "pcb_mecanica.json"), "w", encoding="utf-8") as f:
        json.dump(mec, f, ensure_ascii=False, indent=1)
    docs = os.path.join(AQUI, "..", "..", "DOCS")
    os.makedirs(docs, exist_ok=True)
    svg(os.path.join(docs, "colocacion_pcb_rev0.svg"))
    return 1 if err else 0


if __name__ == "__main__":
    sys.exit(main())
