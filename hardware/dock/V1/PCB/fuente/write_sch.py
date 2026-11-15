"""Schematic + project + part list, generated from avo_dock_v1_pcb.py (same data as the board)."""
import json
import os

import avo_dock_v1_pcb as D
import project
import schematic as SCH

BLOCKS = {   # name: (x0, y0, x1, y1, title)
    "Red": (0, 0, 0, 0, "RED 230 V~ (ZONA AISLADA, FOSO 6,5 mm): fusible T1 A · varistor 275 V · Mean Well IRM-20-5 (5 V 4 A)"),
    "USB-C": (0, 0, 0, 0, "USB-C DEL PC: Rd 5,1 k (consumidor) · PTC 1,5 A · ESD"),
    "Selector": (0, 0, 0, 0, "SELECTOR DE ALIMENTACIÓN: prioridad a la red, sin retroalimentar el PC ni el IRM (PMOS)"),
    "3V3": (0, 0, 0, 0, "3,3 V (AMS1117-3.3)"),
    "ESP32-S3": (0, 0, 0, 0, "ESP32-S3-MINI-1U-N8: BLE + Wi-Fi con la app · USB OTG · pantalla · puertos"),
    "USB": (0, 0, 0, 0, "CONMUTADORES USB TS3USB221: modo PC (USB_SEL = 0) / modo autónomo, S3 anfitrión (USB_SEL = 1)"),
    "Hub": (0, 0, 0, 0, "HUB USB2514B: 1 = casco A · 2 = casco B · 3 = S3 · 4 desactivado · cristal 24 MHz"),
    "Casco A": (0, 0, 0, 0, "CASCO A: TPS2553 (≈ 1 A) · shunt 50 mΩ + INA180A2 · pogo 5 contactos (VBUS · D− · D+ · GND · AUX)"),
    "Casco B": (0, 0, 0, 0, "CASCO B: TPS2553 (≈ 1 A) · shunt 50 mΩ + INA180A2 · pogo 5 contactos"),
    "Cincha A": (0, 0, 0, 0, "CINCHA A: TPS2553 (≈ 0,5 A) · shunt 50 mΩ + INA180A2 · pogo 3 contactos (+5 V · GND · MTCK)"),
    "Cincha B": (0, 0, 0, 0, "CINCHA B: TPS2553 (≈ 0,5 A) · shunt 50 mΩ + INA180A2 · pogo 3 contactos"),
    "Pantalla": (0, 0, 0, 0, "PANTALLA IPS 2,0\" ST7789 (JST-GH 8) · pulsador frontal"),
    "Pruebas": (0, 0, 0, 0, "PUNTOS DE PRUEBA"),
}
BLOCK_OF = {}


def sym_for(p):
    """(lib name, lib node, pin positions)"""
    s = p["sym"]
    fp = D.fp_of(p)
    pads_with_net = []
    for pd in fp.pads:
        if pd.num and pd.num not in pads_with_net:
            pads_with_net.append(pd.num)
    if isinstance(s, dict):
        L = [(str(n), nm, "passive") for n, nm in s.get("L", [])]
        R = [(str(n), nm, "passive") for n, nm in s.get("R", [])]
        have = {x[0] for x in L + R}
        for num in pads_with_net:
            if num not in have:
                R.append((num, num, "passive"))
        import hashlib
        sig = hashlib.md5(repr((L, R)).encode()).hexdigest()[:6]      # one library symbol per pin layout
        name = p["value"].split()[0].replace(",", "_").replace(" ", "_") + "_" + p["ref"].rstrip("0123456789") + "_" + sig
        node, pos = SCH.lib_symbol(name, L, R, ref=p["ref"].rstrip("0123456789"))
        return name, node, pos
    if s in ("R", "C", "LED", "XTAL"):
        kind = {"R": "R", "C": "C", "LED": "LED", "XTAL": "XTAL"}[s]
        if s == "LED":      # footprint pad 1 = cathode, pad 2 = anode → anode on top
            pins = [("2", "A", "passive"), ("1", "K", "passive")]
        else:
            pins = [("1", "1", "passive"), ("2", "2", "passive")]
        name = {"R": "R_avo", "C": "C_avo", "LED": "LED_avo", "XTAL": "Crystal_avo"}[s]
        node, pos = SCH.lib_symbol(name, pins, [], ref={"R": "R", "C": "C", "LED": "D", "XTAL": "Y"}[s],
                                   two_pin=kind)
        return name, node, pos
    # one-pin parts (test pads, wire pads)
    node, pos = SCH.lib_symbol("Pad_avo", [("1", "1", "passive")], [], ref="TP", body_w=5.08)
    return "Pad_avo", node, pos


def lbl_len(t):
    return len(t) * 0.85 + 3.5 if t else 2.0


def cell(pos, nets):
    """Cell size (w, h) and the symbol origin inside it, labels included (sheet units, Y down)."""
    xs = [v[0] for v in pos.values()]; ys = [v[1] for v in pos.values()]
    L = max([lbl_len(nets.get(n)) for n, v in pos.items() if v[2] == 0] or [0])
    Rr = max([lbl_len(nets.get(n)) for n, v in pos.items() if v[2] == 180] or [0])
    T = max([lbl_len(nets.get(n)) for n, v in pos.items() if v[2] == 270] or [0])
    B = max([lbl_len(nets.get(n)) for n, v in pos.items() if v[2] == 90] or [0])
    body_w = max(xs) - min(xs); body_h = max(ys) - min(ys)
    extra_w = 14 if body_w < 3 else 0          # Reference/Value beside 2-pin parts
    w = L + body_w + Rr + 6 + extra_w
    h = T + body_h + B + 8
    ox = L + 3 - min(xs)
    oy = T + 4 + max(ys)
    return w, h, ox, oy


def write(path_sch, path_pro, path_parts):
    BW = 250.0
    blocks = {}
    order = sorted(D.PARTS, key=lambda p: (not isinstance(p["sym"], dict), p["ref"].rstrip("0123456789"),
                                           int("0" + p["ref"][len(p["ref"].rstrip("0123456789")):])))
    for p in order:
        if p["block"] == "Mecánica":
            continue
        blk = BLOCK_OF.get(p["block"], p["block"])
        name, node, pos = sym_for(p)
        nets = {num: (None if num in p.get("nc", ()) else p["nets"].get(num)) for num in pos}
        w, h, ox, oy = cell(pos, nets)
        blocks.setdefault(blk, []).append((p, name, node, pos, nets, w, h, ox, oy))
    # shelf packing inside each block
    placed, sizes = {}, {}
    for blk, items in blocks.items():
        x, y, row_h = 6.0, 12.0, 0.0
        out = []
        for it in items:
            w, h = it[5], it[6]
            if x + w > BW - 4 and x > 6.0:
                x, y, row_h = 6.0, y + row_h + 4, 0.0
            out.append((it, x, y))
            x += w + 4
            row_h = max(row_h, h)
        placed[blk] = out
        sizes[blk] = y + row_h + 6
    # blocks in three columns, shortest column first
    cols = [20.0, 20.0, 20.0]
    origin = {}
    for blk in BLOCKS:
        if blk not in sizes:
            continue
        c = cols.index(min(cols))
        origin[blk] = (15 + c * (BW + 10), cols[c])
        cols[c] += sizes[blk] + 10
    Wp = int(15 + 3 * (BW + 10) + 10)
    Hp = int(max(cols) + 45)
    sh = SCH.Sheet(D.TITLE + " · REV " + D.REV, (Wp, Hp))
    for blk, out in placed.items():
        bx, by = origin[blk]
        sh.box(bx, by, bx + BW, by + sizes[blk])
        sh.text(BLOCKS[blk][4], bx + 2, by + 6, 2.0)
        for (p, name, node, pos, nets, w, h, ox, oy), x, y in out:
            sh.place(name, node, pos, p["ref"], p["value"], bx + x + ox, by + y + oy, nets,
                     "AVO:" + D.fp_of(p).name, {"LCSC": p["lcsc"], "MPN": p["mpn"]}, p["dnp"],
                     side_text=(max(v[0] for v in pos.values()) - min(v[0] for v in pos.values())) < 3)
    sh.note("Generado por fuente/avo_dock_v1_pcb.py (mismo origen de datos que la placa). Las conexiones son "
            "etiquetas globales: dos pines con la misma etiqueta están unidos.", 15, Hp - 38, 1.5)
    sh.write(path_sch, D.DATE, D.REV)

    pot = ["+5V_SYS", "+5V_RED", "VBUS_PC", "VBUS_C_RAW"] + ["VSW_" + k for k in ("CA", "CB", "GA", "GB")] + \
        ["VPOGO_" + k for k in ("CA", "CB", "GA", "GB")]
    project.write(path_pro,
                  [dict(name="Default", clearance=0.15, track_width=0.2, via_diameter=0.5, via_drill=0.3),
                   # 0,3 mm: entra en los pines de 0,25 mm del QFN-36 (paso 0,5)
                   dict(name="P3V3", clearance=0.15, track_width=0.3, via_diameter=0.6, via_drill=0.3, priority=2),
                   # 0,6 mm ≈ 1,5 A en cobre exterior de 35 µm (+10 °C); los 5 V principales se refuerzan con varias vías
                   dict(name="Potencia", clearance=0.2, track_width=0.6, via_diameter=0.8, via_drill=0.4, priority=1),
                   # red 230 V: 2,5 mm entre L y N (aislamiento funcional); el aislamiento reforzado con la MBTS lo da el foso
                   dict(name="Red_230V", clearance=2.5, track_width=1.0, via_diameter=2.0, via_drill=1.0, priority=0)],
                  [("+3V3", "P3V3")] + [(n, "Potencia") for n in pot] + [("AC_*", "Red_230V")])

    rows = []
    for p in D.PARTS:
        if p["block"] == "Mecánica":
            continue
        rows.append(dict(ref=p["ref"], value=p["value"], footprint=D.fp_of(p).name, lcsc=p["lcsc"],
                         mpn=p["mpn"], block=p["block"], dnp=p["dnp"], no_assembly=p["no_assembly"],
                         note=p["note"], jlc_rot=p["jlc_rot"], x=p["pos"][0], y=p["pos"][1], rot=p["rot"]))
    json.dump(rows, open(path_parts, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    o = D.OUT
    write(os.path.join(o, "AVO_DOCK_V1_PCB.kicad_sch"), os.path.join(o, "AVO_DOCK_V1_PCB.kicad_pro"),
          os.path.join(o, "piezas.json"))
