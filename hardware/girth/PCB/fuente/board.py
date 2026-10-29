"""Writes a KiCad 9 .kicad_pcb (4 layers, JLCPCB rules)."""
from fplib import uid
from sexpr import Sym, dump

S = Sym


def header(thickness):
    layers = [S("layers"),
              [0, "F.Cu", S("signal")], [4, "In1.Cu", S("power")], [6, "In2.Cu", S("power")], [2, "B.Cu", S("signal")],
              [9, "F.Adhes", S("user"), "F.Adhesive"], [11, "B.Adhes", S("user"), "B.Adhesive"],
              [13, "F.Paste", S("user")], [15, "B.Paste", S("user")],
              [5, "F.SilkS", S("user"), "F.Silkscreen"], [7, "B.SilkS", S("user"), "B.Silkscreen"],
              [1, "F.Mask", S("user")], [3, "B.Mask", S("user")],
              [17, "Dwgs.User", S("user"), "User.Drawings"], [19, "Cmts.User", S("user"), "User.Comments"],
              [21, "Eco1.User", S("user"), "User.Eco1"], [23, "Eco2.User", S("user"), "User.Eco2"],
              [25, "Edge.Cuts", S("user")], [27, "Margin", S("user")],
              [31, "F.CrtYd", S("user"), "F.Courtyard"], [29, "B.CrtYd", S("user"), "B.Courtyard"],
              [35, "F.Fab", S("user")], [33, "B.Fab", S("user")]]
    # JLC 4-layer 1.0 mm (JLC04101H-7628 style): copper 35/17.5 µm
    cu = 0.035
    d_pp = 0.2104
    core = round(thickness - 2 * cu - 2 * 0.0152 - 2 * d_pp - 2 * 0.01, 4)
    stack = [S("stackup"),
             [S("layer"), "F.SilkS", [S("type"), "Top Silk Screen"]],
             [S("layer"), "F.Paste", [S("type"), "Top Solder Paste"]],
             [S("layer"), "F.Mask", [S("type"), "Top Solder Mask"], [S("thickness"), 0.01]],
             [S("layer"), "F.Cu", [S("type"), "copper"], [S("thickness"), cu]],
             [S("layer"), "dielectric 1", [S("type"), "prepreg"], [S("thickness"), d_pp],
              [S("material"), "FR4"], [S("epsilon_r"), 4.4], [S("loss_tangent"), 0.02]],
             [S("layer"), "In1.Cu", [S("type"), "copper"], [S("thickness"), 0.0152]],
             [S("layer"), "dielectric 2", [S("type"), "core"], [S("thickness"), core],
              [S("material"), "FR4"], [S("epsilon_r"), 4.6], [S("loss_tangent"), 0.02]],
             [S("layer"), "In2.Cu", [S("type"), "copper"], [S("thickness"), 0.0152]],
             [S("layer"), "dielectric 3", [S("type"), "prepreg"], [S("thickness"), d_pp],
              [S("material"), "FR4"], [S("epsilon_r"), 4.4], [S("loss_tangent"), 0.02]],
             [S("layer"), "B.Cu", [S("type"), "copper"], [S("thickness"), cu]],
             [S("layer"), "B.Mask", [S("type"), "Bottom Solder Mask"], [S("thickness"), 0.01]],
             [S("layer"), "B.Paste", [S("type"), "Bottom Solder Paste"]],
             [S("layer"), "B.SilkS", [S("type"), "Bottom Silk Screen"]],
             [S("copper_finish"), "ENIG"], [S("dielectric_constraints"), S("no")]]
    setup = [S("setup"), stack, [S("pad_to_mask_clearance"), 0.05], [S("solder_mask_min_width"), 0.1],
             [S("allow_soldermask_bridges_in_footprints"), S("no")],
             [S("aux_axis_origin"), 0, 0], [S("grid_origin"), 0, 0],
             [S("pcbplotparams"), [S("layerselection"), S("0x00010fc_ffffffff")],
              [S("plot_on_all_layers_selection"), S("0x0000000_00000000")],
              [S("disableapertmacros"), S("no")], [S("usegerberextensions"), S("yes")],
              [S("usegerberattributes"), S("yes")], [S("usegerberadvancedattributes"), S("yes")],
              [S("creategerberjobfile"), S("yes")], [S("dashed_line_dash_ratio"), 12],
              [S("dashed_line_gap_ratio"), 3], [S("svgprecision"), 4], [S("plotframeref"), S("no")],
              [S("mode"), 1], [S("useauxorigin"), S("no")], [S("hpglpennumber"), 1],
              [S("hpglpenspeed"), 20], [S("hpglpendiameter"), 15], [S("pdf_front_fp_property_popups"), S("yes")],
              [S("pdf_back_fp_property_popups"), S("yes")], [S("pdf_metadata"), S("yes")],
              [S("dxfpolygonmode"), S("yes")], [S("dxfimperialunits"), S("no")],
              [S("dxfusepcbnewfont"), S("yes")], [S("psnegative"), S("no")], [S("psa4output"), S("no")],
              [S("plot_black_and_white"), S("yes")], [S("plotinvisibletext"), S("no")],
              [S("sketchpadsonfab"), S("no")], [S("plotpadnumbers"), S("no")], [S("hidednponfab"), S("no")],
              [S("sketchdnponfab"), S("yes")], [S("crossoutdnponfab"), S("yes")],
              [S("subtractmaskfromsilk"), S("yes")], [S("outputformat"), 1], [S("mirror"), S("no")],
              [S("drillshape"), 0], [S("scaleselection"), 1], [S("outputdirectory"), "gerber/"]]]
    return [S("kicad_pcb"), [S("version"), 20241229], [S("generator"), "pcbnew"], [S("generator_version"), "9.0"],
            [S("general"), [S("thickness"), thickness], [S("legacy_teardrops"), S("no")]],
            [S("paper"), "A4"],
            [S("title_block"), [S("title"), "AVO GIRTH · placa de la cincha"], [S("date"), "2026-10-29"],
             [S("rev"), "A"], [S("company"), "AVO Performance Horse"]],
            layers, setup]


def nets_block(nets):
    return [[S("net"), 0, ""]] + [[S("net"), i + 1, n] for i, n in enumerate(nets)]


def gr_line(a, b, layer, w=0.1, key=""):
    return [S("gr_line"), [S("start"), a[0], a[1]], [S("end"), b[0], b[1]],
            [S("stroke"), [S("width"), w], [S("type"), S("solid")]], [S("layer"), layer],
            [S("uuid"), uid("grl", layer, a, b, key)]]


def gr_arc(a, m, b, layer, w=0.1):
    return [S("gr_arc"), [S("start"), a[0], a[1]], [S("mid"), m[0], m[1]], [S("end"), b[0], b[1]],
            [S("stroke"), [S("width"), w], [S("type"), S("solid")]], [S("layer"), layer],
            [S("uuid"), uid("gra", layer, a, m, b)]]


def gr_text(txt, x, y, layer, size=0.8, angle=0, mirror=False, bold=True, key=""):
    eff = [S("effects"), [S("font"), [S("size"), size, size], [S("thickness"), size * 0.15]]
           + ([[S("bold"), S("yes")]] if bold else [])]
    if mirror:
        eff.append([S("justify"), S("mirror")])
    return [S("gr_text"), txt, [S("at"), x, y, angle] if angle else [S("at"), x, y], [S("layer"), layer],
            [S("uuid"), uid("txt", txt, layer, x, y, key)], eff]


def segment(a, b, w, layer, net):
    return [S("segment"), [S("start"), round(a[0], 4), round(a[1], 4)], [S("end"), round(b[0], 4), round(b[1], 4)],
            [S("width"), w], [S("layer"), layer], [S("net"), net], [S("uuid"), uid("seg", a, b, layer, net)]]


def via(p, net, d=0.5, drill=0.3):
    return [S("via"), [S("at"), round(p[0], 4), round(p[1], 4)], [S("size"), d], [S("drill"), drill],
            [S("layers"), "F.Cu", "B.Cu"], [S("net"), net], [S("uuid"), uid("via", p, net)]]


def zone(net, netname, layer, poly, priority=0, clearance=0.2, min_w=0.2, thermal=(0.3, 0.3), key="",
         connect="thermal"):
    z = [S("zone"), [S("net"), net], [S("net_name"), netname], [S("layer"), layer],
         [S("uuid"), uid("zone", netname, layer, key)], [S("hatch"), S("edge"), 0.5]]
    if priority:
        z.append([S("priority"), priority])
    cp = [S("connect_pads")]
    if connect == "solid":
        cp.append(S("yes"))
    cp.append([S("clearance"), clearance])
    z += [cp, [S("min_thickness"), min_w], [S("filled_areas_thickness"), S("no")],
          [S("fill"), [S("thermal_gap"), thermal[0]], [S("thermal_bridge_width"), thermal[1]],
           [S("island_removal_mode"), 1], [S("island_area_min"), 2]],
          [S("polygon"), [S("pts")] + [[S("xy"), round(x, 4), round(y, 4)] for x, y in poly]]]
    return z


def keepout(layer_list, poly, key, tracks=True, vias=True, pads=False, copperpour=True, footprints=False):
    yn = lambda b: S("not_allowed") if b else S("allowed")
    return [S("zone"), [S("net"), 0], [S("net_name"), ""], [S("layers")] + layer_list,
            [S("uuid"), uid("keepout", key)], [S("name"), key], [S("hatch"), S("edge"), 0.5],
            [S("connect_pads"), [S("clearance"), 0]], [S("min_thickness"), 0.25],
            [S("filled_areas_thickness"), S("no")],
            [S("keepout"), [S("tracks"), yn(tracks)], [S("vias"), yn(vias)], [S("pads"), yn(pads)],
             [S("copperpour"), yn(copperpour)], [S("footprints"), yn(footprints)]],
            [S("fill"), [S("thermal_gap"), 0.5], [S("thermal_bridge_width"), 0.5]],
            [S("polygon"), [S("pts")] + [[S("xy"), round(x, 4), round(y, 4)] for x, y in poly]]]


def write(path, tree):
    with open(path, "w", encoding="utf-8") as f:
        f.write(dump(tree) + "\n")
