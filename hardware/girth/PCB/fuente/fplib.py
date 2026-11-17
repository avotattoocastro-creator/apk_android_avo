"""Footprints: load KiCad 5/6+ .kicad_mod files, build custom ones, emit KiCad 9 board footprints and
give absolute pad geometry for the router and the internal checks."""
import math
import os
import uuid as _uuid

from sexpr import Sym, find, find_all, parse

LIB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib")
UUID_NS = _uuid.UUID("6f3e0d1c-52a7-4c1e-9d0c-a70a7e5a1c60")


def uid(*key):
    return str(_uuid.uuid5(UUID_NS, "/".join(str(k) for k in key)))


def rot(x, y, deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    # KiCad: positive angle rotates counter-clockwise on screen (Y axis points down)
    return x * c + y * s, -x * s + y * c


class Pad:
    def __init__(self, num, kind, shape, x, y, w, h, rot=0.0, drill=None, layers=None, rratio=None,
                 extra=None):
        self.num, self.kind, self.shape = str(num), kind, shape
        self.x, self.y, self.w, self.h, self.rot = x, y, w, h, rot
        self.drill = drill
        self.layers = layers or (["F.Cu", "F.Paste", "F.Mask"] if kind == "smd" else ["*.Cu", "*.Mask"])
        self.rratio = rratio
        self.extra = extra or []        # raw s-expr items (custom primitives, options, zone_connect...)


class Footprint:
    def __init__(self, name, pads, graphics=None, attr="smd", model=None, descr="", height=0.0, body=None):
        self.name = name
        self.pads = pads
        self.graphics = graphics or []  # raw nodes in KiCad 9 syntax
        self.attr = attr
        self.model = model
        self.descr = descr
        self.height = height            # mm above the board (for the enclosure check)
        self.body = body                # (x0, y0, x1, y1) body outline for 3D / height map

    def courtyard(self):
        xs, ys = [], []
        for g in self.graphics:
            if find(g, "layer") and find(g, "layer")[1] in ("F.CrtYd", "B.CrtYd"):
                if g[0] == "fp_circle":
                    c, e = find(g, "center"), find(g, "end")
                    r = math.hypot(e[1] - c[1], e[2] - c[2])
                    xs += [c[1] - r, c[1] + r]; ys += [c[2] - r, c[2] + r]
                    continue
                for k in ("start", "end", "center"):
                    p = find(g, k)
                    if p:
                        xs.append(p[1]); ys.append(p[2])
        if not xs:
            for p in self.pads:
                r = max(p.w, p.h) / 2 + 0.25
                xs += [p.x - r, p.x + r]; ys += [p.y - r, p.y + r]
        return min(xs), min(ys), max(xs), max(ys)


def _stroke(node):
    w = find(node, "width")
    if w is not None:
        node.remove(w)
        node.append([Sym("stroke"), [Sym("width"), w[1]], [Sym("type"), Sym("solid")]])
    return node


def load(fname, model=None, height=0.0):
    path = fname if os.path.isabs(fname) else os.path.join(LIB, fname)
    tree = parse(open(path, encoding="utf-8").read())
    name = tree[1]
    pads, gfx = [], []
    attr = "smd"
    a = find(tree, "attr")
    if a:
        attr = str(a[1])
    descr = find(tree, "descr")
    for it in tree[2:]:
        if not isinstance(it, list):
            continue
        k = it[0]
        if k == "pad":
            num, kind, shape = it[1], str(it[2]), str(it[3])
            at = find(it, "at")
            size = find(it, "size")
            dr = find(it, "drill")
            drill = None
            if dr:
                vals = [v for v in dr[1:] if isinstance(v, (int, float))]
                if vals:
                    drill = vals[0] if len(vals) == 1 else tuple(vals)  # oval
            layers = [str(x) for x in find(it, "layers")[1:]]
            rr = find(it, "roundrect_rratio")
            extra = []
            for sub in it[4:]:
                if isinstance(sub, list) and sub[0] in ("options", "primitives", "zone_connect",
                                                        "thermal_width", "thermal_gap", "solder_mask_margin",
                                                        "solder_paste_margin", "chamfer_ratio", "chamfer"):
                    extra.append(_fix_prims(sub))
            pads.append(Pad(num, kind, shape, at[1], at[2], size[1], size[2],
                            at[3] if len(at) > 3 else 0.0, drill, layers, rr[1] if rr else None, extra))
        elif k in ("fp_line", "fp_circle", "fp_arc", "fp_poly", "fp_rect"):
            it = [x for x in it if not (isinstance(x, list) and x[0] in ("tstamp", "uuid"))]
            gfx.append(_stroke(it))
    fp = Footprint(str(name), pads, gfx, attr, model, descr[1] if descr else "", height)
    m = find(tree, "model")
    if m:  # keep the library's 3D placement (e.g. Espressif: offset −6.75/−1.2/−8.45, rotate −90° about X)
        fo, fr = find(m, "offset"), find(m, "rotate")
        o, r = (find(fo, "xyz") if fo else None), (find(fr, "xyz") if fr else None)
        fp.model_xf = (list(o[1:4]) if o else [0, 0, 0], list(r[1:4]) if r else [0, 0, 0])
    return fp


def _fix_prims(node):
    if node[0] != "primitives":
        return node
    out = [Sym("primitives")]
    for g in node[1:]:
        g = [x for x in g if not (isinstance(x, list) and x[0] in ("tstamp", "uuid"))]
        out.append(_stroke(g) if find(g, "width") else g)
    return out


def line(x0, y0, x1, y1, layer, w=0.12):
    return [Sym("fp_line"), [Sym("start"), x0, y0], [Sym("end"), x1, y1],
            [Sym("stroke"), [Sym("width"), w], [Sym("type"), Sym("solid")]], [Sym("layer"), layer]]


def rect_lines(x0, y0, x1, y1, layer, w=0.05):
    return [line(x0, y0, x1, y0, layer, w), line(x1, y0, x1, y1, layer, w),
            line(x1, y1, x0, y1, layer, w), line(x0, y1, x0, y0, layer, w)]


def circle(cx, cy, r, layer, w=0.12, fill=False):
    return [Sym("fp_circle"), [Sym("center"), cx, cy], [Sym("end"), cx + r, cy],
            [Sym("stroke"), [Sym("width"), w], [Sym("type"), Sym("solid")]],
            [Sym("fill"), Sym("solid" if fill else "none")], [Sym("layer"), layer]]


# --------------------------------------------------------------------------- emission
def emit(fp, ref, value, x, y, angle, netmap, props=None, side="F", hide_value=True, refpos=None,
         ref_size=0.6):
    """netmap: pad number -> (net code, net name). Returns s-expr list (KiCad 9)."""
    props = props or {}
    lay = "F.Cu" if side == "F" else "B.Cu"
    n = [Sym("footprint"), "AVO:" + fp.name, [Sym("layer"), lay], [Sym("uuid"), uid("fp", ref)],
         [Sym("at"), x, y, angle] if angle else [Sym("at"), x, y]]
    if fp.descr:
        n.append([Sym("descr"), fp.descr])

    def prop(name, val, at, layer, hide=False, size=0.6):
        p = [Sym("property"), name, val, [Sym("at"), at[0], at[1], angle], [Sym("layer"), layer]]
        if hide:
            p.append([Sym("hide"), Sym("yes")])
        p += [[Sym("uuid"), uid("prop", ref, name)],
              [Sym("effects"), [Sym("font"), [Sym("size"), size, size], [Sym("thickness"), max(0.1, round(size * 0.15, 3))]]]]
        return p

    cx0, cy0, cx1, cy1 = fp.courtyard()
    rp = refpos if refpos is not None else (0, cy0 - 0.45)
    # references on the assembly (Fab) layer: the board is too dense for readable silkscreen designators
    n.append(prop("Reference", ref, (0, 0), "F.Fab" if side == "F" else "B.Fab", size=0.5))
    n.append(prop("Value", value, (0, cy1 + 0.6), "F.Fab", hide=hide_value))
    n.append(prop("Footprint", "AVO:" + fp.name, (0, 0), "F.Fab", hide=True))
    n.append(prop("Datasheet", "", (0, 0), "F.Fab", hide=True))
    n.append(prop("Description", "", (0, 0), "F.Fab", hide=True))
    for k, v in props.items():
        n.append(prop(k, v, (0, 0), "F.Fab", hide=True))
    # link to the schematic symbol (same UUID the schematic writer uses) → DRC schematic parity
    n.append([Sym("path"), "/" + uid("sym", ref)])
    n.append([Sym("sheetname"), "/"])
    n.append([Sym("sheetfile"), "AVO_GIRTH_PCB.kicad_sch"])
    attr = [Sym("attr"), Sym(fp.attr)]
    if props.get("DNP") == "1":
        attr.append(Sym("dnp"))
    n.append(attr)
    for g in fp.graphics:
        g2 = [x for x in g]
        g2.append([Sym("uuid"), uid("g", ref, len(n))])
        n.append(g2)
    for i, p in enumerate(fp.pads):
        a = (p.rot + angle) % 360
        pad = [Sym("pad"), p.num, Sym(p.kind), Sym(p.shape), [Sym("at"), p.x, p.y, a] if a else [Sym("at"), p.x, p.y],
               [Sym("size"), p.w, p.h]]
        if p.drill is not None:
            if isinstance(p.drill, tuple):
                pad.append([Sym("drill"), Sym("oval"), p.drill[0], p.drill[1]])
            else:
                pad.append([Sym("drill"), p.drill])
        pad.append([Sym("layers")] + list(p.layers))
        if p.rratio is not None:
            pad.append([Sym("roundrect_rratio"), p.rratio])
        if p.num in netmap and p.num != "":
            code, name = netmap[p.num]
            pad.append([Sym("net"), code, name])
        pad += p.extra
        pad.append([Sym("uuid"), uid("pad", ref, i)])
        n.append(pad)
    if fp.model:
        off, rot = getattr(fp, "model_xf", ([0, 0, 0], [0, 0, 0]))
        n.append([Sym("model"), fp.model, [Sym("offset"), [Sym("xyz")] + off],
                  [Sym("scale"), [Sym("xyz"), 1, 1, 1]], [Sym("rotate"), [Sym("xyz")] + rot]])
    return n


# --------------------------------------------------------------------------- geometry
def pad_poly(p, fx, fy, fangle, inflate=0.0, side="F"):
    """Absolute polygon (list of (x, y)) of a pad, inflated by `inflate`."""
    a = (p.rot + fangle) % 360
    w, h = p.w / 2 + inflate, p.h / 2 + inflate
    pts = []
    if p.shape == "custom":
        xs, ys = [-p.w / 2, p.w / 2], [-p.h / 2, p.h / 2]
        for e in p.extra:
            if e and e[0] == "primitives":
                for g in e[1:]:
                    pp = find(g, "pts")
                    if pp:
                        for xy in pp[1:]:
                            xs.append(xy[1]); ys.append(xy[2])
                    for k in ("start", "end", "center"):
                        q = find(g, k)
                        if q:
                            xs.append(q[1]); ys.append(q[2])
        w, h = (max(xs) - min(xs)) / 2 + inflate, (max(ys) - min(ys)) / 2 + inflate
        ox, oy = (max(xs) + min(xs)) / 2, (max(ys) + min(ys)) / 2
        pts = [(ox - w, oy - h), (ox + w, oy - h), (ox + w, oy + h), (ox - w, oy + h)]
        out = []
        for (u, v) in pts:
            rx, ry = rot(u, v, a)
            px, py = rot(p.x, p.y, fangle)
            out.append((fx + px + rx, fy + py + ry))
        return out
    if p.shape in ("circle", "oval") or (p.shape == "roundrect" and p.rratio and p.rratio >= 0.5):
        r = min(p.w, p.h) / 2 + inflate
        dx, dy = max(0.0, w - r), max(0.0, h - r)
        for cx, cy, a0 in ((dx, dy, 0), (-dx, dy, 90), (-dx, -dy, 180), (dx, -dy, 270)):
            for k in range(5):
                t = math.radians(a0 + k * 22.5)
                pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    else:
        pts = [(-w, -h), (w, -h), (w, h), (-w, h)]
    out = []
    for (u, v) in pts:
        rx, ry = rot(u, v, a)
        px, py = rot(p.x, p.y, fangle)
        out.append((fx + px + rx, fy + py + ry))
    return out


def pad_center(p, fx, fy, fangle):
    px, py = rot(p.x, p.y, fangle)
    return fx + px, fy + py


def pad_copper_layers(p, side="F"):
    ls = []
    for l in p.layers:
        if l == "*.Cu":
            return ["F.Cu", "In1.Cu", "In2.Cu", "B.Cu"]
        if l.endswith(".Cu"):
            ls.append(l)
    return ls
