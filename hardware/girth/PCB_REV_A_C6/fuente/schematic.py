"""Writes a KiCad 9 schematic (.kicad_sch) from the netlist: every pin gets a local net label at its end,
so the drawing is generated from the same data as the board (no hand-drawn wires to get out of sync)."""
from fplib import uid
from sexpr import Sym, dump

S = Sym
PIN_LEN = 2.54
G = 1.27          # schematic grid


def snap(v):
    return round(round(v / G) * G, 4)


def _font(size=1.27):
    return [S("effects"), [S("font"), [S("size"), size, size]]]


def lib_symbol(name, pins_left, pins_right, pins_top=(), pins_bottom=(), ref="U", body_w=None, two_pin=None):
    """pins_*: lists of (number, name, etype). Returns (lib_symbol node, pin positions dict num->(x, y, angle))
    in symbol coordinates (Y up, as KiCad symbol libraries)."""
    pos = {}
    if two_pin:                              # passive 2-pin: vertical, pins 1 top / 2 bottom
        kind = two_pin
        body = []
        if kind in ("R", "C", "L", "D", "LED", "F", "XTAL", "SW", "TP"):
            body = _two_pin_body(kind)
        pins = []
        n1, n2 = pins_left[0], pins_left[1]
        for (num, pname, et), y, ang in ((n1, 3.81, 270), (n2, -3.81, 90)):
            pins.append([S("pin"), S(et), S("line"), [S("at"), 0, y, ang], [S("length"), 1.27],
                         [S("name"), pname, _font()], [S("number"), num, _font()]])
            yy = y
            pos[num] = (0, yy, ang)
        unit = [S("symbol"), name + "_1_1"] + pins
        unit0 = [S("symbol"), name + "_0_1"] + body
        node = [S("symbol"), name, [S("pin_numbers"), [S("hide"), S("yes")]],
                [S("pin_names"), [S("offset"), 0], [S("hide"), S("yes")]],
                [S("exclude_from_sim"), S("no")], [S("in_bom"), S("yes")], [S("on_board"), S("yes")],
                [S("property"), "Reference", ref, [S("at"), 2.03, 0.6, 0], _font()],
                [S("property"), "Value", name, [S("at"), 2.03, -1.2, 0], _font()],
                [S("property"), "Footprint", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
                [S("property"), "Datasheet", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
                [S("property"), "Description", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
                unit0, unit]
        return node, pos
    nl, nr = len(pins_left), len(pins_right)
    nt, nb = len(pins_top), len(pins_bottom)
    rows = max(nl, nr, 1)
    cols = max(nt, nb, 0)
    longest = max([len(p[1]) for p in list(pins_left) + list(pins_right)] + [4])
    w = body_w or max(snap(longest * 1.27 * 2 + 5.08), snap(cols * 2.54 + 5.08), 10.16)
    w = snap(w)
    h = snap(rows * 2.54 + 2.54)
    top = snap(h / 2)
    pins = []
    for k, (num, pname, et) in enumerate(pins_left):
        y = snap(top - 2.54 - k * 2.54)
        x = -w / 2 - PIN_LEN
        pins.append([S("pin"), S(et), S("line"), [S("at"), x, y, 0], [S("length"), PIN_LEN],
                     [S("name"), pname, _font()], [S("number"), num, _font()]])
        pos[num] = (x, y, 0)
    for k, (num, pname, et) in enumerate(pins_right):
        y = snap(top - 2.54 - k * 2.54)
        x = w / 2 + PIN_LEN
        pins.append([S("pin"), S(et), S("line"), [S("at"), x, y, 180], [S("length"), PIN_LEN],
                     [S("name"), pname, _font()], [S("number"), num, _font()]])
        pos[num] = (x, y, 180)
    for k, (num, pname, et) in enumerate(pins_top):
        x = snap(-((nt - 1) * 2.54) / 2 + k * 2.54)
        y = top + PIN_LEN
        pins.append([S("pin"), S(et), S("line"), [S("at"), x, y, 270], [S("length"), PIN_LEN],
                     [S("name"), pname, _font()], [S("number"), num, _font()]])
        pos[num] = (x, y, 270)
    for k, (num, pname, et) in enumerate(pins_bottom):
        x = snap(-((nb - 1) * 2.54) / 2 + k * 2.54)
        y = -top - PIN_LEN
        pins.append([S("pin"), S(et), S("line"), [S("at"), x, y, 90], [S("length"), PIN_LEN],
                     [S("name"), pname, _font()], [S("number"), num, _font()]])
        pos[num] = (x, y, 90)
    rect = [S("rectangle"), [S("start"), -w / 2, top], [S("end"), w / 2, -top],
            [S("stroke"), [S("width"), 0.254], [S("type"), S("default")]], [S("fill"), [S("type"), S("background")]]]
    node = [S("symbol"), name, [S("pin_names"), [S("offset"), 1.016]],
            [S("exclude_from_sim"), S("no")], [S("in_bom"), S("yes")], [S("on_board"), S("yes")],
            [S("property"), "Reference", ref, [S("at"), -w / 2, top + 1.27 + (PIN_LEN if nt else 0), 0],
             [S("effects"), [S("font"), [S("size"), 1.27, 1.27]], [S("justify"), S("left"), S("bottom")]]],
            [S("property"), "Value", name, [S("at"), w / 2, top + 1.27 + (PIN_LEN if nt else 0), 0],
             [S("effects"), [S("font"), [S("size"), 1.27, 1.27]], [S("justify"), S("right"), S("bottom")]]],
            [S("property"), "Footprint", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
            [S("property"), "Datasheet", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
            [S("property"), "Description", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
            [S("symbol"), name + "_0_1", rect], [S("symbol"), name + "_1_1"] + pins]
    return node, pos


def _poly(pts, fill="none", w=0.254):
    return [S("polyline"), [S("pts")] + [[S("xy"), x, y] for x, y in pts],
            [S("stroke"), [S("width"), w], [S("type"), S("default")]], [S("fill"), [S("type"), S(fill)]]]


def _two_pin_body(kind):
    if kind == "R":
        return [[S("rectangle"), [S("start"), -0.762, 2.54], [S("end"), 0.762, -2.54],
                 [S("stroke"), [S("width"), 0.254], [S("type"), S("default")]], [S("fill"), [S("type"), S("none")]]]]
    if kind == "C":
        return [_poly([(-1.778, 0.508), (1.778, 0.508)], w=0.4), _poly([(-1.778, -0.508), (1.778, -0.508)], w=0.4),
                _poly([(0, 2.54), (0, 0.508)]), _poly([(0, -0.508), (0, -2.54)])]
    if kind == "L":
        return [[S("arc"), [S("start"), 0, 2.54 - k * 1.27], [S("mid"), 0.635, 1.905 - k * 1.27],
                 [S("end"), 0, 1.27 - k * 1.27], [S("stroke"), [S("width"), 0.254], [S("type"), S("default")]],
                 [S("fill"), [S("type"), S("none")]]] for k in range(4)]
    if kind in ("D", "LED"):   # anode = pin 1 (top) for our use (current flows down)
        return [_poly([(-1.27, 1.016), (1.27, 1.016), (0, -1.016), (-1.27, 1.016)]),
                _poly([(-1.27, -1.016), (1.27, -1.016)]), _poly([(0, 2.54), (0, 1.016)]),
                _poly([(0, -1.016), (0, -2.54)])]
    if kind == "XTAL":
        return [[S("rectangle"), [S("start"), -1.143, 0.762], [S("end"), 1.143, -0.762],
                 [S("stroke"), [S("width"), 0.254], [S("type"), S("default")]], [S("fill"), [S("type"), S("none")]]],
                _poly([(-1.778, 1.27), (1.778, 1.27)]), _poly([(-1.778, -1.27), (1.778, -1.27)]),
                _poly([(0, 2.54), (0, 1.27)]), _poly([(0, -1.27), (0, -2.54)])]
    if kind == "TP":
        return [[S("circle"), [S("center"), 0, 0], [S("radius"), 0.762],
                 [S("stroke"), [S("width"), 0.254], [S("type"), S("default")]], [S("fill"), [S("type"), S("none")]]]]
    return [_poly([(0, 2.54), (0, -2.54)])]


def power_flag():
    return [S("symbol"), "power:PWR_FLAG", [S("power")], [S("pin_numbers"), [S("hide"), S("yes")]],
            [S("pin_names"), [S("offset"), 0], [S("hide"), S("yes")]],
            [S("exclude_from_sim"), S("no")], [S("in_bom"), S("yes")], [S("on_board"), S("yes")],
            [S("property"), "Reference", "#FLG", [S("at"), 0, 1.905, 0], [S("hide"), S("yes")], _font()],
            [S("property"), "Value", "PWR_FLAG", [S("at"), 0, 3.81, 0], _font()],
            [S("property"), "Footprint", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
            [S("property"), "Datasheet", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
            [S("property"), "Description", "", [S("at"), 0, 0, 0], [S("hide"), S("yes")], _font()],
            [S("symbol"), "PWR_FLAG_0_0", [S("pin"), S("power_out"), S("line"), [S("at"), 0, 0, 90],
                                           [S("length"), 0], [S("name"), "~", _font()], [S("number"), "1", _font()]]],
            [S("symbol"), "PWR_FLAG_0_1", _poly([(0, 0), (0, 1.27), (-1.016, 1.905), (0, 2.54), (1.016, 1.905), (0, 1.27)])]]


class Sheet:
    def __init__(self, title, paper="A3"):
        self.title = title
        self.paper = paper
        self.libs = {}
        self.items = []
        self.instances = []
        self.root = uid("sheet-root")

    def place(self, libname, libnode, pinpos, ref, value, x, y, netmap, footprint="", props=None, dnp=False,
              side_text=False):
        """x, y: sheet coordinates (Y down). netmap: pin -> net name (None = no connect)."""
        if libname not in self.libs:
            self.libs[libname] = libnode
        x, y = snap(x), snap(y)
        u = uid("sym", ref)
        node = [S("symbol"), [S("lib_id"), "AVO:" + libname], [S("at"), x, y, 0], [S("unit"), 1],
                [S("exclude_from_sim"), S("no")], [S("in_bom"), S("yes")], [S("on_board"), S("yes")],
                [S("dnp"), S("yes" if dnp else "no")], [S("uuid"), u],
                [S("property"), "Reference", ref, [S("at"), x + (2.54 if side_text else 0), y - 1.27, 0],
                 [S("effects"), [S("font"), [S("size"), 1.27, 1.27]]] + ([[S("justify"), S("left")]] if side_text else [])],
                [S("property"), "Value", value, [S("at"), x + (2.54 if side_text else 0), y + 1.27, 0],
                 [S("effects"), [S("font"), [S("size"), 1.0, 1.0]]] + ([[S("justify"), S("left")]] if side_text else [])],
                [S("property"), "Footprint", footprint, [S("at"), x, y, 0], [S("hide"), S("yes")], _font()],
                [S("property"), "Datasheet", "", [S("at"), x, y, 0], [S("hide"), S("yes")], _font()],
                [S("property"), "Description", "", [S("at"), x, y, 0], [S("hide"), S("yes")], _font()]]
        for k, v in (props or {}).items():
            node.append([S("property"), k, v, [S("at"), x, y, 0], [S("hide"), S("yes")], _font()])
        for num in pinpos:
            node.append([S("pin"), num, [S("uuid"), uid("pin", ref, num)]])
        node.append([S("instances"), [S("project"), "AVO_GIRTH_PCB",
                                      [S("path"), "/" + self.root, [S("reference"), ref], [S("unit"), 1]]]])
        # fix: Reference/Value placed beside the body for 2-pin parts
        self.items.append(node)
        for num, (px, py, ang) in pinpos.items():
            ax, ay = snap(x + px), snap(y - py)        # symbol Y up -> sheet Y down
            net = netmap.get(num)
            if net is None:
                self.items.append([S("no_connect"), [S("at"), ax, ay], [S("uuid"), uid("nc", ref, num)]])
                continue
            # label orientation: text away from the symbol
            lang = {0: 180, 180: 0, 270: 90, 90: 270}[ang]
            just = S("right") if lang == 180 else S("left")
            if lang in (90, 270):
                just = S("left")
            # global labels: the net keeps its bare name (same as on the board) → schematic parity holds
            self.items.append([S("global_label"), net, [S("shape"), S("passive")], [S("at"), ax, ay, lang],
                               [S("fields_autoplaced"), S("yes")],
                               [S("effects"), [S("font"), [S("size"), 1.0, 1.0]], [S("justify"), just]],
                               [S("uuid"), uid("lbl", ref, num)],
                               [S("property"), "Intersheetrefs", "${INTERSHEET_REFS}", [S("at"), ax, ay, 0],
                                [S("hide"), S("yes")], [S("effects"), [S("font"), [S("size"), 1.0, 1.0]]]]])

    def flag(self, net, x, y):
        if "power:PWR_FLAG" not in self.libs:
            self.libs["power:PWR_FLAG"] = power_flag()
        x, y = snap(x), snap(y)
        n = len([i for i in self.items if i[0] == "symbol"])
        ref = "#FLG%02d" % n
        self.items.append([S("symbol"), [S("lib_id"), "power:PWR_FLAG"], [S("at"), x, y, 0], [S("unit"), 1],
                           [S("exclude_from_sim"), S("no")], [S("in_bom"), S("yes")], [S("on_board"), S("yes")],
                           [S("dnp"), S("no")], [S("uuid"), uid("flag", net)],
                           [S("property"), "Reference", ref, [S("at"), x, y + 1.9, 0], [S("hide"), S("yes")], _font()],
                           [S("property"), "Value", "PWR_FLAG", [S("at"), x, y - 3.8, 0], [S("hide"), S("yes")], _font()],
                           [S("property"), "Footprint", "", [S("at"), x, y, 0], [S("hide"), S("yes")], _font()],
                           [S("property"), "Datasheet", "", [S("at"), x, y, 0], [S("hide"), S("yes")], _font()],
                           [S("property"), "Description", "", [S("at"), x, y, 0], [S("hide"), S("yes")], _font()],
                           [S("pin"), "1", [S("uuid"), uid("flagpin", net)]],
                           [S("instances"), [S("project"), "AVO_GIRTH_PCB",
                                             [S("path"), "/" + self.root, [S("reference"), ref], [S("unit"), 1]]]]])
        self.items.append([S("label"), net, [S("at"), x, y, 0],
                           [S("effects"), [S("font"), [S("size"), 1.0, 1.0]], [S("justify"), S("left"), S("bottom")]],
                           [S("uuid"), uid("flaglbl", net)]])

    def text(self, txt, x, y, size=2.0):
        self.items.append([S("text"), txt, [S("exclude_from_sim"), S("no")], [S("at"), snap(x), snap(y), 0],
                           [S("effects"), [S("font"), [S("size"), size, size], [S("bold"), S("yes")]],
                            [S("justify"), S("left"), S("bottom")]], [S("uuid"), uid("txt", txt, x, y)]])

    def note(self, txt, x, y, size=1.27):
        self.items.append([S("text"), txt, [S("exclude_from_sim"), S("no")], [S("at"), snap(x), snap(y), 0],
                           [S("effects"), [S("font"), [S("size"), size, size]], [S("justify"), S("left"), S("top")]],
                           [S("uuid"), uid("note", txt[:40], x, y)]])

    def box(self, x0, y0, x1, y1):
        self.items.append([S("rectangle"), [S("start"), snap(x0), snap(y0)], [S("end"), snap(x1), snap(y1)],
                           [S("stroke"), [S("width"), 0.2], [S("type"), S("dash")]], [S("fill"), [S("type"), S("none")]],
                           [S("uuid"), uid("box", x0, y0, x1, y1)]])

    def write(self, path, date, rev):
        lib = [S("lib_symbols")]
        for k, v in self.libs.items():
            if k.startswith("power:"):
                lib.append(v)
            else:
                v2 = list(v)
                v2[1] = "AVO:" + k
                # sub-symbol names keep the bare name
                lib.append(v2)
        paper = [S("paper"), "User", self.paper[0], self.paper[1]] if isinstance(self.paper, tuple) else \
            [S("paper"), self.paper]
        tree = [S("kicad_sch"), [S("version"), 20250114], [S("generator"), "eeschema"],
                [S("generator_version"), "9.0"], [S("uuid"), self.root], paper,
                [S("title_block"), [S("title"), self.title], [S("date"), date], [S("rev"), rev],
                 [S("company"), "AVO Performance Horse"]],
                lib] + self.items + [[S("sheet_instances"), [S("path"), "/", [S("page"), "1"]]],
                                     [S("embedded_fonts"), S("no")]]
        with open(path, "w", encoding="utf-8") as f:
            f.write(dump(tree) + "\n")
