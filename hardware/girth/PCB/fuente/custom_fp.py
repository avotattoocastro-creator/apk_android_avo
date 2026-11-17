"""Footprints drawn here from datasheet/reference dimensions."""
from fplib import Footprint, Pad, circle, line, rect_lines


def bno085():
    """CEVA BNO085/BNO086 LGA-28, 5.2 × 3.8 × 1.1 mm, pitch 0.5 mm. Pin positions from the Adafruit BNO08x
    and SparkFun BNO086 boards (identical numbering; Eagle Y-up converted to KiCad Y-down). Pads lengthened
    0.1 mm outward (toe) for inspection. Pin 1: top-left corner of a long side, next to short-side pins 2–5."""
    pads = []
    w = 0.26
    # long sides (5.2 mm along X): rows at y = ±1.6, pads 0.26 × 0.75
    top = {1: -2.25, 28: -1.75, 27: -1.25, 26: -0.75, 25: -0.25, 24: 0.25, 23: 0.75, 22: 1.25, 21: 1.75, 20: 2.25}
    bot = {6: -2.25, 7: -1.75, 8: -1.25, 9: -0.75, 10: -0.25, 11: 0.25, 12: 0.75, 13: 1.25, 14: 1.75, 15: 2.25}
    for n, x in top.items():
        pads.append(Pad(n, "smd", "roundrect", x, -1.6125, w, 0.75, rratio=0.2))
    for n, x in bot.items():
        pads.append(Pad(n, "smd", "roundrect", x, 1.6125, w, 0.75, rratio=0.2))
    # short sides (3.8 mm along Y): columns at x = ±2.35, pads 0.65 × 0.26
    left = {2: -0.75, 3: -0.25, 4: 0.25, 5: 0.75}
    right = {19: -0.75, 18: -0.25, 17: 0.25, 16: 0.75}
    for n, y in left.items():
        pads.append(Pad(n, "smd", "roundrect", -2.3625, y, 0.675, w, rratio=0.2))
    for n, y in right.items():
        pads.append(Pad(n, "smd", "roundrect", 2.3625, y, 0.675, w, rratio=0.2))
    g = rect_lines(-2.6, -1.9, 2.6, 1.9, "F.Fab", 0.1)
    g += rect_lines(-3.0, -2.25, 3.0, 2.25, "F.CrtYd", 0.05)
    g += [line(-2.95, -2.15, -2.3, -2.15, "F.SilkS"), line(-2.95, -2.15, -2.95, -1.5, "F.SilkS"),
          circle(-3.2, -2.45, 0.12, "F.SilkS", 0.1, True)]
    return Footprint("CEVA_BNO08x_LGA-28_5.2x3.8mm_P0.5mm", pads, g, "smd", None,
                     "BNO085/BNO086 LGA-28 (CEVA 1000-3927); land pattern after Adafruit 4754 / SparkFun BNO086",
                     height=1.1, body=(-2.6, -1.9, 2.6, 1.9))


def wire_pad(label, drill=0.8, d=1.5):
    """Plated hole to solder a wire coming from below the board (coil, reed)."""
    pads = [Pad("1", "thru_hole", "circle", 0, 0, d, d, drill=drill, layers=["*.Cu", "*.Mask"])]
    g = [circle(0, 0, d / 2 + 0.25, "F.CrtYd", 0.05)]
    return Footprint("WirePad_D%.1f_Drill%.1f" % (d, drill), pads, g, "through_hole", None,
                     "Wire solder pad " + label, height=0.0)


def test_pad(d=1.0):
    pads = [Pad("1", "smd", "circle", 0, 0, d, d, layers=["F.Cu", "F.Mask"])]
    g = [circle(0, 0, d / 2 + 0.2, "F.CrtYd", 0.05)]
    return Footprint("TestPoint_Pad_D%.1fmm" % d, pads, g, "smd", None, "Test pad (no paste)", height=0.0)


def mmc5983ma():
    """MEMSIC MMC5983MA LGA-16, 3.0 × 3.0 × 1.0 mm, pitch 0.5 mm (datasheet Rev A, 2019-04-03, p. 20).
    Package pads 0.325 × 0.250 mm, rows/columns centred at ±1.2625 mm, pins at ±0.25 / ±0.75 mm.
    Top view (KiCad, Y down): pins 4-3-2-1 along the top (pin 1 top right), 5–8 down the left side,
    9–12 along the bottom (left → right), 16–13 down the right side (16 at the top).
    Land pads 0.25 × 0.45 mm centred 0.05 mm inside the package pad centre (toe 0.06 mm outside the body)."""
    pads = []
    c, w, L = 1.2125, 0.25, 0.45
    top = {4: -0.75, 3: -0.25, 2: 0.25, 1: 0.75}
    bot = {9: -0.75, 10: -0.25, 11: 0.25, 12: 0.75}
    left = {5: -0.75, 6: -0.25, 7: 0.25, 8: 0.75}
    right = {16: -0.75, 15: -0.25, 14: 0.25, 13: 0.75}
    for n, x in top.items():
        pads.append(Pad(n, "smd", "roundrect", x, -c, w, L, rratio=0.2))
    for n, x in bot.items():
        pads.append(Pad(n, "smd", "roundrect", x, c, w, L, rratio=0.2))
    for n, y in left.items():
        pads.append(Pad(n, "smd", "roundrect", -c, y, L, w, rratio=0.2))
    for n, y in right.items():
        pads.append(Pad(n, "smd", "roundrect", c, y, L, w, rratio=0.2))
    g = rect_lines(-1.5, -1.5, 1.5, 1.5, "F.Fab", 0.1)
    g += rect_lines(-1.8, -1.8, 1.8, 1.8, "F.CrtYd", 0.05)
    g += [circle(1.9, -1.95, 0.12, "F.SilkS", 0.1, True)]
    return Footprint("MEMSIC_MMC5983MA_LGA-16_3x3mm_P0.5mm", pads, g, "smd", None,
                     "MMC5983MA LGA-16 3x3 mm (MEMSIC datasheet Rev A, land pattern p. 20)",
                     height=1.0, body=(-1.5, -1.5, 1.5, 1.5))


def lga14_st():
    """ST LGA-14L 2.5 × 3.0 × 0.83 mm, pitch 0.5 mm (LSM6DS3TR-C / LSM6DSV16X / LSM6DSO). Pad centres as in
    Adafruit's LSM6DS3TR-C / LSM6DSOX boards (Eagle Y-up converted to KiCad Y-down): sides at x = ±1.1625,
    top/bottom rows at y = ±0.9125. Pads 0.475 × 0.25 mm: 0.25 mm between pads (the generic KiCad land with
    0.4 mm pads leaves 0.1 mm, below the 0.15 mm JLCPCB clearance). Pin 1 top-left, counter-clockwise."""
    pads = []
    side = {1: (-1.1625, -0.75), 2: (-1.1625, -0.25), 3: (-1.1625, 0.25), 4: (-1.1625, 0.75),
            8: (1.1625, 0.75), 9: (1.1625, 0.25), 10: (1.1625, -0.25), 11: (1.1625, -0.75)}
    rows = {5: (-0.5, 0.9125), 6: (0.0, 0.9125), 7: (0.5, 0.9125),
            12: (0.5, -0.9125), 13: (0.0, -0.9125), 14: (-0.5, -0.9125)}
    for n, (x, y) in side.items():
        pads.append(Pad(n, "smd", "roundrect", x, y, 0.475, 0.25, rratio=0.2))
    for n, (x, y) in rows.items():
        pads.append(Pad(n, "smd", "roundrect", x, y, 0.25, 0.475, rratio=0.2))
    g = rect_lines(-1.5, -1.25, 1.5, 1.25, "F.Fab", 0.1)   # body 3.0 (X, across the 4-pin sides) × 2.5 (Y)
    g += rect_lines(-1.75, -1.5, 1.75, 1.5, "F.CrtYd", 0.05)
    g += [circle(-1.85, -1.4, 0.12, "F.SilkS", 0.1, True)]
    return Footprint("ST_LGA-14L_2.5x3mm_P0.5mm", pads, g, "smd", None,
                     "ST LGA-14L 2.5x3x0.83 mm, pads 0.475x0.25 (Adafruit LSM6DS3TR-C / LSM6DSOX land)",
                     height=0.86, body=(-1.5, -1.25, 1.5, 1.25))
