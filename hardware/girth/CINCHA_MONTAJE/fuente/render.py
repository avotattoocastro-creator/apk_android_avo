"""Renders PNG de comprobación (pintor por profundidad con OpenCV, proyección ortográfica, sombreado Lambert).
Uso: python3 render.py   → ../renders/*.png"""
import math
import os
import sys

import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import avo_cad as A   # noqa: E402
import avo_cincha_montaje as M   # noqa: E402

OUTR = os.path.normpath(os.path.join(HERE, "..", "renders"))
os.makedirs(OUTR, exist_ok=True)
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"


def look(az, el):
    """dirección de la cámara (hacia la escena) a partir de acimut y elevación (grados)"""
    a, e = math.radians(az), math.radians(el)
    d = -np.array([math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)])
    up = np.array([0, 0, 1.0])
    if abs(np.dot(d, up)) > 0.98:
        up = np.array([0, 1.0, 0])
    r = np.cross(d, up); r /= np.linalg.norm(r)
    u = np.cross(r, d)
    return d, r, u


def render(meshes, path, az=-60, el=25, size=(1600, 1100), title="", notes=(), ss=2, pad=0.06, bg=(250, 250, 248),
           edge=True, labels=()):
    d, r, u = look(az, el)
    W, H = size[0] * ss, size[1] * ss
    allV = np.vstack([m.np() for m in meshes])
    X = allV @ r; Y = allV @ u
    x0, x1, y0, y1 = X.min(), X.max(), Y.min(), Y.max()
    top = 90 * ss if title else 20 * ss
    bottom = (30 + 24 * len(notes)) * ss
    sc = min((W * (1 - 2 * pad)) / (x1 - x0), (H - top - bottom) * (1 - pad) / (y1 - y0))
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2

    def proj(P):
        return np.c_[W / 2 + (P @ r - cx) * sc, top + (H - top - bottom) / 2 - (P @ u - cy) * sc]
    img = np.full((H, W, 3), bg[::-1], np.float32)
    zbuf = np.full((H, W), np.inf, np.float32)
    L1 = -d * 0.4 + u * 0.7 + r * 0.3; L1 /= np.linalg.norm(L1)
    L2 = -d; L2 /= np.linalg.norm(L2)
    edges_all = []
    for m in meshes:
        V = m.np()
        P2 = proj(V)
        depth = V @ d
        col = np.array(m.color)
        tris = m.triangles()
        fn = []
        for f in m.F:
            L = V[f[0]]
            n = np.zeros(3)
            for i in range(len(L)):
                n += np.cross(L[i], L[(i + 1) % len(L)])
            nn = np.linalg.norm(n)
            fn.append(n / nn if nn > 0 else n)
        if edge:
            emap = {}
            for fi, f in enumerate(m.F):
                for Lp in f:
                    for i in range(len(Lp)):
                        a_, b_ = Lp[i], Lp[(i + 1) % len(Lp)]
                        emap.setdefault((min(a_, b_), max(a_, b_)), []).append(fi)
            for k, fs in emap.items():
                if len(fs) != 2 or np.dot(fn[fs[0]], fn[fs[1]]) < math.cos(math.radians(25)):
                    edges_all.append((P2[k[0]], P2[k[1]], depth[k[0]], depth[k[1]], col))
        for t in tris:
            a_, b_, c_ = t
            pa, pb, pc = P2[a_], P2[b_], P2[c_]
            n = np.cross(V[b_] - V[a_], V[c_] - V[a_]); nn = np.linalg.norm(n)
            if nn == 0:
                continue
            n /= nn
            if np.dot(n, d) > 0:
                n = -n
            lam = 0.35 + 0.45 * max(0, np.dot(n, L1)) + 0.25 * max(0, np.dot(n, L2))
            c = np.clip(col * lam * 255, 0, 255)[::-1]
            xmin = max(int(math.floor(min(pa[0], pb[0], pc[0]))), 0); xmax = min(int(math.ceil(max(pa[0], pb[0], pc[0]))), W - 1)
            ymin = max(int(math.floor(min(pa[1], pb[1], pc[1]))), 0); ymax = min(int(math.ceil(max(pa[1], pb[1], pc[1]))), H - 1)
            if xmax < xmin or ymax < ymin:
                continue
            xs = np.arange(xmin, xmax + 1) + 0.5; ys = np.arange(ymin, ymax + 1) + 0.5
            X_, Y_ = np.meshgrid(xs, ys)
            den = (pb[1] - pc[1]) * (pa[0] - pc[0]) + (pc[0] - pb[0]) * (pa[1] - pc[1])
            if abs(den) < 1e-9:
                continue
            w1 = ((pb[1] - pc[1]) * (X_ - pc[0]) + (pc[0] - pb[0]) * (Y_ - pc[1])) / den
            w2 = ((pc[1] - pa[1]) * (X_ - pc[0]) + (pa[0] - pc[0]) * (Y_ - pc[1])) / den
            w3 = 1 - w1 - w2
            ins = (w1 >= -1e-6) & (w2 >= -1e-6) & (w3 >= -1e-6)
            if not ins.any():
                continue
            z = w1 * depth[a_] + w2 * depth[b_] + w3 * depth[c_]
            zb = zbuf[ymin:ymax + 1, xmin:xmax + 1]
            upd = ins & (z < zb)
            zb[upd] = z[upd]
            img[ymin:ymax + 1, xmin:xmax + 1][upd] = c
    # aristas con prueba de profundidad
    tol = 0.6 / sc + 0.05
    for p, q, dp, dq, col in edges_all:
        L = max(2, int(np.hypot(*(q - p)) * 1.5))
        t = np.linspace(0, 1, L)
        xs = (p[0] + (q[0] - p[0]) * t).astype(int); ys = (p[1] + (q[1] - p[1]) * t).astype(int)
        zs = dp + (dq - dp) * t
        ok = (xs >= 0) & (xs < W) & (ys >= 0) & (ys < H)
        xs, ys, zs = xs[ok], ys[ok], zs[ok]
        vis = zs <= zbuf[ys, xs] + tol * 3
        ec = np.clip(col * 255 * 0.25, 0, 255)[::-1]
        img[ys[vis], xs[vis]] = ec
        if ss >= 2:
            xs2 = np.clip(xs[vis] + 1, 0, W - 1)
            img[ys[vis], xs2] = ec
    img = np.clip(img, 0, 255).astype(np.uint8)
    img = cv2.resize(img, size, interpolation=cv2.INTER_AREA)
    im = Image.fromarray(img[:, :, ::-1])
    dr = ImageDraw.Draw(im)
    f1 = ImageFont.truetype(FONT, 30); f2 = ImageFont.truetype(FONT, 18)
    if title:
        dr.text((24, 18), title, fill=(20, 20, 20), font=f1)
        dr.text((24, 58), "AVO Performance Horse · diseño · NO VERIFICADO en caballo real", fill=(150, 30, 30), font=f2)
    for i, t in enumerate(notes):
        dr.text((24, size[1] - 24 * (len(notes) - i) - 8), t, fill=(60, 60, 60), font=f2)
    for (P3, text) in labels:
        q = proj(np.array([P3]))[0] / ss
        dr.ellipse((q[0] - 4, q[1] - 4, q[0] + 4, q[1] + 4), fill=(200, 30, 30))
        dr.text((q[0] + 8, q[1] - 10), text, fill=(150, 20, 20), font=f2)
    im.save(path)
    print("render:", path)


def flat(groups, skip=()):
    return [m for g, ms in groups.items() if g not in skip for m in ms]


def main():
    gC = M.conjunto(True)
    tor = A.layered([(-350.0, -8.0, [A.polygon(M.TX.outline(360))])], "torax", (0.80, 0.70, 0.60))
    tor.transform(A.swap_axes(("x", "z", "y"))); M.fix_orient(tor)
    allC = flat(gC)
    render(allC + [tor], os.path.join(OUTR, "01_conjunto_en_torax.png"), az=65, el=-10,
           title="REV 7.0: cincha con soporte, cápsula y 2 satélites IMU sobre la sección del tórax (188 cm)",
           notes=["Vista desde delante-izquierda. Tórax de referencia: superelipse 48 × 69 cm, n = 2,15 (estimado).",
                  "Cincha Decathlon 110 cm: soporte + cápsula en el centro; IMU 2 en u = +%d e IMU 3 en u = −%d sobre la funda." % (M.SAT["u"], M.SAT["u"])])
    render(allC, os.path.join(OUTR, "02_conjunto_curvado_desde_abajo.png"), az=-70, el=-35,
           title="Conjunto curvado visto desde abajo (lado exterior de la cincha)",
           notes=["REV 6.4: sin bolsillo; la cápsula queda a la vista, sujeta por 2 balancines magnéticos empotrados; cierre de velcro + solapa en el canto trasero."])
    render(allC, os.path.join(OUTR, "03_conjunto_curvado_lado_caballo.png"), az=110, el=55,
           title="Lado del caballo: ventanas de los electrodos en la cara interior",
           notes=["REV 7.0: ECG+ bajo IMU 2 (u = +345), REF bajo el soporte (u = 0) y ECG− bajo IMU 3 (u = −345)."],
           labels=[(M.bend_curvo(np.array([[u, v, -2]]))[0], k) for k, (u, v) in M.P["e_pos"].items()])
    gR = M.conjunto(False)
    allR = flat(gR)
    render(allR, os.path.join(OUTR, "04_conjunto_recto.png"), az=-60, el=35,
           title="Versión recta (cincha tumbada, cara interior abajo)", size=(1800, 900),
           notes=["Cincha 1100 mm; funda 860 mm; cables: %s mm." % (
               ", ".join("%s %d" % kv for kv in M.cables.longitudes.items()))])
    render(allR, os.path.join(OUTR, "05_conjunto_recto_cara_interior.png"), az=-90, el=-89.5, size=(1800, 700),
           title="Cara interior (piel del caballo) de la versión recta",
           notes=["Ventanas de 75 × 50 (ECG±) y 50 × 30 (REF); los electrodos asoman 1 mm por debajo de la piel rebajada."])
    # REV 7.0: satélite IMU 2 de cerca y corte del soporte por la PCB de sensores
    sat = [m for m in gR["Satelites_impresos"] + gR["Satelites_electronica"] + gR["Cables"] + gR["Funda"]]
    u0 = M.SAT["u"]
    near = []
    for m in sat:
        V = m.np()
        F = [f for f in m.F if V[f[0]][:, 0].min() > u0 - 70 and V[f[0]][:, 0].max() < u0 + 70]
        if F:
            idx = sorted({i for f in F for L in f for i in L})
            remap = {i: k for k, i in enumerate(idx)}
            mm = A.Mesh(m.name, m.color); mm.V = [m.V[i] for i in idx]
            mm.F = [[[remap[i] for i in L] for L in f] for f in F]; near.append(mm)
    render([m for m in near if not m.name.startswith("Funda_pasador")], os.path.join(OUTR, "20_satelite_IMU2.png"), az=-35, el=35, size=(1500, 1000),
           title="REV 7.0: satélite IMU 2 sobre la funda (u = +%d)" % u0,
           notes=["Caja PETG 48 × 26 × 9 con aristas redondeadas, 2 Chicago a la funda; PCB LSM6DSV16X en resina.",
                  "Cable fijo de 6 hilos al soporte por dentro de la funda; el electrodo ECG+ debajo, en la cara del caballo."])
    # cápsula y soporte (local)
    imp, com = M.capsula_local()
    simp, scom = M.soporte_local()
    caps = imp + com
    soporte = [m.copy() for m in simp + scom]
    for m in soporte:
        m.transform(A.T_translate(0, 0, -M.SOP["cama"] - M.SOP["precarga"]))
    render(caps + soporte, os.path.join(OUTR, "06_capsula_en_soporte.png"), az=-50, el=30,
           title="REV 6.4: cápsula en el soporte con 2 balancines magnéticos empotrados",
           notes=["Extremos de la cápsula 5 mm más largos; balancín a ras en la pared, eje en cojinetes; diente en la cama del soporte.",
                  "Imanes Ø5 × 1 (2 + 2 por lado) entre balancín y pared."])
    # explosionado
    ex = []
    off = {"AVO_CINCHA_R7_0_tapa": 34, "Tornillo_ISO7380_M2x6_inox_x6": 56, "Arandela_DIN433_M2_inox_x6": 50,
           "Antena_Molex_146153-0050": 34, "Coaxial_1.13_50mm": 26, "AVO_CINCHA_R7_0_junta_TPU85A": 18,
           "PCB_REV_D_46x30": 24, "PCB_componentes": 24, "PCB_pasivos": 24, "UFL_conector": 24, "LED_SK6812SIDE-A_x4": 24,
           "Tornillo_ISO7380_M2x5_inox_x4_PCB": 24, "AVO_CINCHA_R7_0_separador_TPU85A": 12, "Hilos_AWG28_pogo": 8,
           "Hilos_bateria": 8, "U4_ESP32-C6-MINI-1U": 24, "LiPo_603450_1000mAh": 4}
    for m in caps:
        mm = m.copy()
        mm.transform(A.T_translate(0, 0, off.get(m.name, 0)))
        ex.append(mm)
    for m in soporte:
        mm = m.copy(); mm.transform(A.T_translate(0, 0, -16)); ex.append(mm)
    render(ex, os.path.join(OUTR, "07_capsula_explosionada.png"), az=-55, el=22, size=(1400, 1600),
           title="Cápsula REV 7.0 explosionada",
           notes=["De arriba abajo: tornillos M2×6 + arandela, tapa opaca con antena Molex 146153, junta TPU 85A en ranura,",
                  "PCB REV D (46 × 30) con 4 LED laterales, colgada de la tapa con 4 M2×5, separador TPU, celda 603450,",
                  "base translúcida (aro de luz) con la ranura de la junta y 2 placas pogo selladas con epoxi,",
                  "2 balancines con sus pasadores Ø2 × 6 e imanes, y el soporte con los 2 conectores de pines y 4 Chicago."])
    # corte: solo caras con todos los vértices en y < corte
    cut = M.CAP["pogo_y"]
    sec = []
    for m in caps + soporte:
        mm = A.Mesh(m.name, m.color); mm.V = m.V
        V = m.np()
        mm.F = [f for f in m.F if V[f[0]][:, 1].max() <= cut + 0.01 or V[f[0]][:, 1].min() >= cut + 0.01 and False]
        if mm.F:
            sec.append(mm)
    render(sec, os.path.join(OUTR, "08_capsula_recortada_por_pogos.png"), az=90, el=8, size=(1500, 900),
           title="Cápsula + soporte recortados por el eje de los pogos (y = −21,4)", edge=True,
           notes=["Vista recortada (se quitan las caras con y > −21,4): placas de contactos a ras del fondo, pines con muelle en el soporte."])
    # piezas impresas
    pz = []
    x = 0
    bse = M.pieza_base()
    for e_ in (M.pieza_cojinetes(1), M.pieza_cojinetes(-1)):
        bse.merge(e_)
    for m in [bse, M.pieza_tapa(), M.pieza_junta(False), M.pieza_separador(), M.pieza_soporte(),
              M.pieza_balancin(1, True), M.pieza_balancin(-1, True), M.pieza_portaimanes_bal_x2(), M.pieza_portaimanes_x2(), M.pieza_tacos(True)]:
        mm = M.stl_print(m, m.name, m.name.endswith("tapa"))
        lo, hi = mm.bbox()
        mm.transform(A.T_translate(x - lo[0], 0, 0)); x += (hi[0] - lo[0]) + 12
        pz.append(mm)
    render(pz, os.path.join(OUTR, "09_piezas_impresas.png"), az=-70, el=40, size=(1800, 800),
           title="Piezas impresas en posición de impresión (Elegoo Centauri Carbon)",
           notes=["Base PETG natural con cojinetes (aro de luz) · tapa PETG opaco (boca abajo) · junta y separador TPU 85A · soporte PETG · 2 balancines PETG (cara exterior abajo) · 2 tapas de imán · 2 portaimanes PETG · 4 tacos TPU 85A."])
    render(flat({"F": gC["Funda"], "E": gC["Electrodos"], "C": gC["Cables"]}) + soporte_world(gC) + gC["Capsula_impresa"],
           os.path.join(OUTR, "10_funda_detalle.png"), az=75, el=-30, size=(1600, 1000),
           title="Funda de piel con el sistema (sin la cincha)",
           notes=["Canal cosido por dentro del pliegue delantero; trabillas en los extremos; ventana para la anilla D central."])
    extra(caps, soporte)


def extra(caps, soporte):
    # corte por el plano de los LED D11/D12 (x = 14), visto desde +X
    sec = []
    for m in caps + soporte:
        V = m.np()
        F = [f for f in m.F if V[f[0]][:, 0].max() <= 14.01]
        if F:
            mm = A.Mesh(m.name, m.color); mm.V = m.V; mm.F = F; sec.append(mm)
    zl = M.Z_LED
    render(sec, os.path.join(OUTR, "12_corte_por_LED.png"), az=0, el=3, size=(1500, 800),
           title="Corte por los LED D11/D12 (x = 14): la luz sale por la pared translúcida de 4 mm",
           notes=["Junta TPU en ranura sobre el canto de la base (z 11,8–13,0); tapa opaca con tope duro; LED con centro a z = %.1f." % zl,
                  "Vista recortada (se quitan las caras con x > 14)."],
           labels=[((14.0, 14.66, zl), "lente D11"), ((14.0, -14.66, zl), "lente D12")])
    # corte por un diente del balancín +X y por el imán, vistos desde −Y
    K = M.bal_x()
    xi, xl, yc = K["px"], K["xl"], K["yc"]
    zc0 = -M.SOP["precarga"]
    for (yy, fn, tt) in ((yc + (M.BAL["ty0"] + M.BAL["w"][1] / 2 - M.BAL["tyend"]) / 2, "13_corte_por_diente.png",
                          "Corte por un diente del balancín +X (REV 7.0, empotrado)"),
                         (yc, "13b_corte_por_imanes.png", "Corte por los imanes del balancín +X (atracción; portaimanes REV 6.5)")):
        sec = []
        for m in caps + soporte:
            V = m.np()
            F = [f for f in m.F if V[f[0]][:, 1].min() >= yy - 0.01]
            if F:
                mm = A.Mesh(m.name, m.color); mm.V = m.V; mm.F = F; sec.append(mm)
        render(sec, os.path.join(OUTR, fn), az=-90, el=2, size=(1500, 1000), title=tt,
               notes=["Balancín empotrado a ras en la pared; eje Ø2 en (%.1f; %.1f) de la cápsula; diente recto en la cama del soporte." % (
                   xi, M.BAL["pz_c"]),
                      "Imanes 2 + 2 Ø5 × 1: en el balancín (con tapa) y en el portaimanes de la pared (entra por abajo, a ras). Abrir: empujar hacia abajo y apretar arriba (suelta a ~4°)."],
               labels=[((xl - 0.5, yy, M.BAL["top_c"]), "diente"), ((xi, yy, M.BAL["pz_c"]), "eje"),
                       ((xl + 1.5, yy, M.BAL["mag_c"]), "imán")])
    render(caps + soporte, os.path.join(OUTR, "14_capsula_en_soporte_vista_balancin.png"), az=-20, el=25,
           size=(1500, 1000), title="REV 7.0: balancín +X empotrado y pared a ras del soporte",
           notes=["Pared del extremo plana (5 mm más larga) con el balancín empotrado; nada sobresale."])
    # REV 6.5: portaimanes. Cápsula vista desde abajo: lado +X montado y lado −X con el portaimanes y sus imanes fuera
    G = M.portaiman_geo()
    vis = []
    for m in caps:
        mm = m.copy()
        if m.name in ("AVO_CINCHA_R7_0_portaiman_Xneg",):
            mm.transform(A.T_translate(0, 0, -12))
        vis.append(mm)
    mg = A.Mesh("Imanes_sueltos_Xneg", M.C_IMAN)
    for k in range(2):
        x = -(G["xs0"] + 0.04 + k * 1.0)
        mg.merge(A.tube([(x, G["yc"], M.BAL["mag_c"] - 12), (x - 1.0, G["yc"], M.BAL["mag_c"] - 12)], 2.5, 20))
    M.fix_orient(mg)
    vis = [m for m in vis if m.name != "Imanes_5x1_x8_cierre"] + [mg]
    render(vis, os.path.join(OUTR, "15_portaimanes_desde_abajo.png"), az=-120, el=-35, size=(1500, 1000),
           title="REV 7.0: portaimanes (abajo, +X montado a ras; −X fuera con sus 2 imanes)",
           notes=["Portaimanes PETG %.1f × %.1f × %.1f mm, cuna de 2 imanes Ø5 × 1 abierta solo hacia el balancín." % (
               G["xc1"] - G["xc0"], 2 * G["hy_c"], G["zc1"]),
                  "Entra por la cara inferior en una abertura con 0,1 mm por lado; esquinas interiores achaflanadas (una sola posición). Se pega a ras."],
           labels=[((-(G["xc0"] + G["xc1"]) / 2, G["yc"], -12 + G["zc1"]), "portaimanes −X"),
                   (((G["xc0"] + G["xc1"]) / 2, G["yc"], 0.0), "portaimanes +X (a ras)")])
    # corte por el eje Y de los imanes, solo cápsula, de cerca
    sec = []
    for m in caps:
        V = m.np()
        F = [f for f in m.F if V[f[0]][:, 1].min() >= G["yc"] - 0.01]
        if F:
            mm = A.Mesh(m.name, m.color); mm.V = m.V; mm.F = F; sec.append(mm)
    render(sec, os.path.join(OUTR, "15b_corte_portaimanes.png"), az=-90, el=2, size=(1500, 1000),
           title="REV 7.0: corte por el portaimanes +X y los imanes",
           notes=["De izquierda a derecha: interior · pared 0,95 · portaimanes (pared 0,6) · 2 imanes · piel 0,65 · balancín con sus 2 imanes y tapa."],
           labels=[(((G["xc0"] + G["xc1"]) / 2, G["yc"], G["zc1"]), "portaimanes"), ((G["xs0"] + 1.0, G["yc"], M.BAL["mag_c"]), "imanes")])
    # REV 7.0: pared a ras del soporte
    render(caps + soporte, os.path.join(OUTR, "16_pared_a_ras_del_soporte.png"), az=-75, el=12, size=(1500, 1000),
           title="REV 7.0: pared de la cápsula a ras del cerco del soporte",
           notes=["Por encima del cerco la base engorda hasta su cara exterior (envolvente de las columnas): sin entrantes.",
                  "Rendija de %.2f mm entre el canto del cerco y el escalón de la base (0,25 de recorrido al abrir)." % M.RAS["junta_z"]])
    sec = []
    for m in caps + soporte:
        V = m.np()
        F = [f for f in m.F if V[f[0]][:, 0].max() <= 0.01]
        if F:
            mm = A.Mesh(m.name, m.color); mm.V = m.V; mm.F = F; sec.append(mm)
    render(sec, os.path.join(OUTR, "16b_corte_pared_a_ras.png"), az=0, el=3, size=(1500, 800),
           title="REV 7.0: corte por x = 0 (columnas centrales): escalón de la base sobre el cerco",
           notes=["Parte baja de la base sin cambios dentro del cerco; parte alta a ras de la cara exterior del cerco."])
    render(caps + soporte, os.path.join(OUTR, "17_extremo_a_ras_y_redondeo.png"), az=-15, el=30, size=(1500, 1000),
           title="REV 7.0: extremo +X a ras del cerco y borde de la tapa redondeado R%.1f" % M.RAS["r_tapa"],
           notes=["El balancín engorda por encima del escalón y sigue a ras de la pared; su borde superior lleva el mismo redondeo.",
                  "Esquinas de la cápsula iguales a las del cerco (envolvente común)."])
    render(caps + soporte, os.path.join(OUTR, "18_acabado_comercial.png"), az=-35, el=22, size=(1500, 1000),
           title="REV 7.0: cápsula rectangular con aristas redondeadas (acabado comercial)",
           notes=["Rectángulo con esquinas R%.1f (parte alta y cerco) y columnas de los tornillos dentro de la pared." % (M.RAS["r_low"] + 3.25),
                  "Redondeos: tapa R%.1f, arista del escalón R%.1f, canto del cerco R%.1f; balancines a juego." % (
                      M.RAS["r_tapa"], M.RAS["r_esc"], M.RAS["r_cerco"])])
    render(soporte, os.path.join(OUTR, "19_soporte_continuo.png"), az=-30, el=35, size=(1500, 1000),
           title="REV 7.0: soporte continuo (cuerpo a ras del cerco, sin corte en ±X)",
           notes=["El paso del balancín es un rebaje por dentro del cerco con piel exterior de %.2f mm; por fuera el cerco es continuo." % M.RAS_SOP["piel_cerco"],
                  "Canto exterior del cerco R%.1f." % M.RAS["r_cerco"]])
    sec = []
    for m in soporte:
        V = m.np()
        F = [f for f in m.F if V[f[0]][:, 1].min() >= M.SOP_PCB["cy"] - 0.01]
        if F:
            mm = A.Mesh(m.name, m.color); mm.V = m.V; mm.F = F; sec.append(mm)
    render(sec, os.path.join(OUTR, "21_soporte_PCB_sensores.png"), az=-90, el=12, size=(1500, 900),
           title="REV 7.0: soporte cortado por la PCB de sensores (alojamiento inferior relleno de resina)",
           notes=["PCB SOP REV A (40 × 22, PROVISIONAL): MCU, ADS1292, IMU 1 y MMC5983MA; un solo pogo de 6 pines hacia la cápsula."])
    sec = []
    K = M.bal_x()
    for m in caps:
        V = m.np()
        F = [f for f in m.F if V[f[0]][:, 1].min() >= K["yc"] - 0.01]
        if F:
            mm = A.Mesh(m.name, m.color); mm.V = m.V; mm.F = F; sec.append(mm)
    render(sec, os.path.join(OUTR, "22_balancin_portaimanes_y_lenguetas.png"), az=-90, el=2, size=(1500, 1000),
           title="REV 7.0: portaimanes del balancín y lengüetas de la tapa en media caña sobre el pasador",
           notes=["Portaimanes del balancín 6 × 6 × 2,6 con la cara hacia la pared cerrada (imanes ocultos, misma distancia).",
                  "El agujero del pasador en el balancín es en gota a propósito: se imprime sin soportes (cara exterior en la cama)."],
           labels=[((K["xl"] + 1.3, K["yc"], M.BAL["mag_c"]), "portaimanes"), ((K["px"], K["yc"], M.BAL["pz_c"]), "pasador")])

def soporte_world(g):
    return g["Soporte_impreso"] + g["Soporte_compra"]


if __name__ == "__main__":
    main()
