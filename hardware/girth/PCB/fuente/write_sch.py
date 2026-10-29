"""Schematic + project + part list, generated from avo_girth_pcb.py (same data as the board)."""
import json
import os

import avo_girth_pcb as D
import project
import schematic as SCH

BLOCKS = {   # name: (x0, y0, x1, y1, title) — hoja A2
    "Qi": (15, 22, 200, 205, "RECEPTOR Qi (BQ51013B) · bobina Ø25 · USB por AD/AD-EN"),
    "USB": (205, 22, 370, 205, "USB-C (programación) · ESD · entrada AD"),
    "Cargador": (375, 22, 580, 205, "CARGADOR CON CAMINO DE POTENCIA (BQ24072) · batería 1S 500 mAh"),
    "ESP32-C6": (15, 210, 200, 405, "ESP32-C6-MINI-1U · arranque · LED · pruebas"),
    "IMU": (205, 210, 370, 405, "IMU BNO085 (SPI) · alimentación conmutada"),
    "3V3": (375, 210, 470, 405, "3,3 V (RT9080) · REED · BATERÍA (ADC)"),
    "Corte": (475, 210, 580, 405, "CORTE DE BATERÍA: relé biestable G6KU"),
}
BLOCK_OF = {"Batería": "3V3", "Reed": "3V3", "Pruebas": "ESP32-C6"}


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
        name = p["value"].split()[0].replace(",", "_").replace(" ", "_") + "_" + p["ref"].rstrip("0123456789")
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


def write(path_sch, path_pro, path_parts):
    sh = SCH.Sheet("AVO GIRTH · placa de la cincha · REV " + D.REV, "A2")
    for k, (x0, y0, x1, y1, title) in BLOCKS.items():
        sh.box(x0, y0, x1, y1)
        sh.text(title, x0 + 2, y0 + 5, 2.0)
    cursor = {k: [BLOCKS[k][0] + 8, BLOCKS[k][1] + 14, 0] for k in BLOCKS}
    # ICs first
    order = sorted(D.PARTS, key=lambda p: (not isinstance(p["sym"], dict), p["ref"]))
    ic_y = {}
    for p in order:
        blk = BLOCK_OF.get(p["block"], p["block"])
        x0, y0, x1, y1, _ = BLOCKS[blk]
        name, node, pos = sym_for(p)
        nets = {num: p["nets"].get(num) for num in pos}
        if isinstance(p["sym"], dict):
            h = max(abs(v[1]) for v in pos.values()) * 2 + 6
            w = max(abs(v[0]) for v in pos.values()) * 2
            cx = x0 + 30 + (ic_y.get(blk, 0) and 0)
            cy = y0 + 18 + ic_y.get(blk, 0) + h / 2
            if blk == "ESP32-C6" or blk == "IMU":
                cx = x0 + 45
            sh.place(name, node, pos, p["ref"], p["value"], cx, cy, nets, "AVO:" + D.fp_of(p).name,
                     {"LCSC": p["lcsc"], "MPN": p["mpn"]}, p["dnp"])
            ic_y[blk] = ic_y.get(blk, 0) + h + 8
            cursor[blk][0] = max(cursor[blk][0], cx + w / 2 + 22)
            continue
        cx, cy, n = cursor[blk]
        if cx > x1 - 12:
            cx = cursor[blk][0] = x0 + 8
            cursor[blk][1] += 0
        # 2-pin parts on a grid of 13 × 17 mm to the right of the IC
        col_x0 = cursor[blk][0]
        sh.place(name, node, pos, p["ref"], p["value"], col_x0, cursor[blk][1] + 6, nets,
                 "AVO:" + D.fp_of(p).name, {"LCSC": p["lcsc"], "MPN": p["mpn"]}, p["dnp"])
        cursor[blk][1] += 17
        if cursor[blk][1] > y1 - 18:
            cursor[blk][1] = y0 + 14
            cursor[blk][0] += 22
    sh.note("Generado por fuente/avo_girth_pcb.py (mismo origen de datos que la placa). Todas las conexiones "
            "son etiquetas de red: dos pines con la misma etiqueta están unidos.", 15, 410, 1.5)
    sh.write(path_sch, D.DATE, D.REV)

    project.write(path_pro,
                  [dict(name="Default", clearance=0.15, track_width=0.2, via_diameter=0.5, via_drill=0.3),
                   # 0,3 mm: entra en los pines de 0,24 mm de las QFN (paso 0,5) sin estrechamientos; ≈ 1 A en cobre exterior
                   dict(name="Potencia", clearance=0.15, track_width=0.3, via_diameter=0.6, via_drill=0.3,
                        priority=1),
                   dict(name="Qi_AC", clearance=0.15, track_width=0.3, via_diameter=0.6, via_drill=0.3,
                        priority=0)],
                  [("QI_AC*", "Qi_AC"), ("QI_COIL*", "Qi_AC"), ("VBUS", "Potencia"), ("VIN5", "Potencia"),
                   ("VSYS", "Potencia"), ("VBAT", "Potencia"), ("QI_RECT", "Potencia")])

    rows = []
    for p in D.PARTS:
        rows.append(dict(ref=p["ref"], value=p["value"], footprint=D.fp_of(p).name, lcsc=p["lcsc"],
                         mpn=p["mpn"], block=p["block"], dnp=p["dnp"], no_assembly=p["no_assembly"],
                         note=p["note"], jlc_rot=p["jlc_rot"], x=p["pos"][0], y=p["pos"][1], rot=p["rot"]))
    json.dump(rows, open(path_parts, "w", encoding="utf-8"), ensure_ascii=False, indent=1)


if __name__ == "__main__":
    o = D.OUT
    write(os.path.join(o, "AVO_GIRTH_PCB.kicad_sch"), os.path.join(o, "AVO_GIRTH_PCB.kicad_pro"),
          os.path.join(o, "piezas.json"))
