# -*- coding: utf-8 -*-
"""Vistas de revisión Rev D (z-buffer propio, ortográfico) a partir del teselado de los B-Rep."""
import os, sys, numpy as np
from PIL import Image, ImageDraw, ImageFont
H = os.path.dirname(os.path.abspath(__file__)); T = os.path.join(H, "salida", "_tess"); O = os.path.join(H, "salida", "IMAGENES"); os.makedirs(O, exist_ok=True)
F = lambda s: ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans%s.ttf" % ("-Bold" if s else ""), 20 if s else 16)
def load(k):
    d = np.load(os.path.join(T, k + ".npz")); return d["v"].astype(np.float64), d["f"]
COL = dict(AVO_RevD_TAPA=(0.86, 0.87, 0.90), AVO_RevD_BASE=(0.20, 0.55, 0.85), AVO_RevD_PISACABLES=(0.95, 0.55, 0.10), AVO_RevD_SUJECION_HELTEC=(0.98, 0.78, 0.15), AVO_RevD_MANGUITO_CABLE_TPU=(0.15, 0.15, 0.17),
           AVO_RevD_JUNTA_TPU=(0.1, 0.1, 0.1), AVO_RevD_PEDESTAL_ANTENA=(0.75, 0.76, 0.80), AVO_RevD_CONTRAPLACA=(0.35, 0.37, 0.42),
           _pcb=(0.08, 0.30, 0.15), _blindaje=(0.75, 0.75, 0.78), _usb_c=(0.8, 0.8, 0.82), _antena_2g4=(0.6, 0.6, 0.6), _ipex_lora=(0.85, 0.7, 0.3), _ipex_2g4=(0.85, 0.7, 0.3),
           _pulsador_RST=(0.95, 0.15, 0.15), _pulsador_USER=(0.95, 0.15, 0.15), _conector_bateria_SH125=(0.95, 0.92, 0.85),
           _zed_pcb=(0.1, 0.45, 0.2), _zed_modulo_ZED_F9P=(0.8, 0.8, 0.8), _zed_SMA_J2_cuerpo=(0.85, 0.7, 0.3), _zed_SMA_J2_rosca_y_macho=(0.85, 0.7, 0.3), _cable=(0.12, 0.12, 0.12))
ELEC = [k for k in COL if k.startswith("_")]
def render(keys, az, el, center, half, W=1200, H_=800, clip=None, alpha_keys=()):
    tris, cols = [], []
    for k in keys:
        v, f = load(k); t = v[f]
        if clip is not None:
            c = t.mean(1); m = np.all((c >= clip[0]) & (c <= clip[1]), 1); t = t[m]
        tris.append(t); cols.append(np.tile(COL[k], (len(t), 1)))
    tri = np.concatenate(tris); col = np.concatenate(cols)
    az, el = np.deg2rad(az), np.deg2rad(el)
    fwd = -np.array([np.cos(el) * np.cos(az), np.cos(el) * np.sin(az), np.sin(el)])
    right = np.cross(fwd, [0, 0, 1]); right /= np.linalg.norm(right); up = np.cross(right, fwd)
    q = tri - np.asarray(center); asp = W / H_
    sx = ((q @ right) / (half * asp) + 1) / 2 * W; sy = (1 - (q @ up) / half) / 2 * H_; dz = q @ fwd
    n = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0]); n /= np.maximum(np.linalg.norm(n, axis=1, keepdims=True), 1e-12)
    L1 = -fwd * 0.5 + up * 0.7 - right * 0.4; L1 /= np.linalg.norm(L1)
    shade = 0.30 + 0.60 * np.abs(n @ L1) + 0.10 * np.abs(n @ fwd)
    zb = np.full((H_, W), np.inf); img = np.ones((H_, W, 3)) * 0.97; tid = -np.ones((H_, W), int)
    for t in range(len(tri)):
        x, y, z = sx[t], sy[t], dz[t]
        x0, x1 = int(max(np.floor(x.min()), 0)), int(min(np.ceil(x.max()), W - 1)); y0, y1 = int(max(np.floor(y.min()), 0)), int(min(np.ceil(y.max()), H_ - 1))
        if x1 < x0 or y1 < y0: continue
        d = (y[1] - y[2]) * (x[0] - x[2]) + (x[2] - x[1]) * (y[0] - y[2])
        if abs(d) < 1e-12: continue
        X, Y = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        a = ((y[1] - y[2]) * (X - x[2]) + (x[2] - x[1]) * (Y - y[2])) / d; b = ((y[2] - y[0]) * (X - x[2]) + (x[0] - x[2]) * (Y - y[2])) / d; c = 1 - a - b
        m = (a >= -1e-6) & (b >= -1e-6) & (c >= -1e-6)
        if not m.any(): continue
        zz = a * z[0] + b * z[1] + c * z[2]; sub = zb[y0:y1 + 1, x0:x1 + 1]; upd = m & (zz < sub)
        sub[upd] = zz[upd]; img[y0:y1 + 1, x0:x1 + 1][upd] = col[t] * shade[t]; tid[y0:y1 + 1, x0:x1 + 1][upd] = t
    # contorno de silueta (cambio fuerte de profundidad)
    dzm = np.where(np.isinf(zb), 1e3, zb)
    e = (np.abs(dzm - np.roll(dzm, 1, 0)) > 1.5) | (np.abs(dzm - np.roll(dzm, 1, 1)) > 1.5)
    img[e] *= 0.35
    return Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8))
def lab(im, t, sub=None):
    d = ImageDraw.Draw(im); d.text((14, 10), t, fill=(15, 15, 25), font=F(1))
    if sub: d.text((14, 38), sub, fill=(60, 60, 70), font=F(0))
    return im
if __name__ == "__main__":
    which = sys.argv[1:] or ["all"]
    PARTS = ["AVO_RevD_TAPA", "AVO_RevD_BASE", "AVO_RevD_PISACABLES", "AVO_RevD_SUJECION_HELTEC", "AVO_RevD_MANGUITO_CABLE_TPU", "AVO_RevD_PEDESTAL_ANTENA", "AVO_RevD_CONTRAPLACA"]
    jobs = {
     "01_conjunto": (PARTS, -125, 28, (83, 0, 10), 62, None, "Rev D — conjunto montado", "tapa abombada sin cabeza GX16 · salida directa del cable con manguito TPU (lateral −Y)"),
     "02_tapa_superior": (["AVO_RevD_TAPA", "AVO_RevD_PEDESTAL_ANTENA", "AVO_RevD_MANGUITO_CABLE_TPU"], -90, 62, (83, 0, 10), 48, None, "Tapa — vista superior", "logotipo AVO.PERFORMANCE en relieve 0,6 siguiendo el techo"),
     "03_conjunto_lateral": (PARTS, -90, 0, (83, 0, 12), 40, None, "Vista lateral (desde −Y)", "altura de la tapa 22,1 en el asiento (RevC 35,0 en la cabeza GX16)"),
     "04_base_electronica": (["AVO_RevD_BASE", "AVO_RevD_PISACABLES", "AVO_RevD_SUJECION_HELTEC", "AVO_RevD_MANGUITO_CABLE_TPU"] + ELEC, -130, 45, (70, 0, 5), 55, None, "Base con Heltec, ZED-F9P, cable y pisa-cables", "sujeción desmontable de la Heltec (amarillo, 2 × M2) · punto de masa GND (inserto M3) · columnas C6/C7"),
     "05_base_sin_electronica": (["AVO_RevD_BASE", "AVO_RevD_PISACABLES"], -130, 50, (70, 0, 5), 55, None, "Base sin electrónica", "Heltec más al centro · columnas nuevas C6/C7 en el lado +Y · guías fuera de los pulsadores · cuna del pisa-cables"),
     "06_heltec_pulsadores": (["AVO_RevD_BASE"] + ELEC, -150, 40, (10, 13, 6), 13, ((-5, -5, -5), (30, 40, 40)), "Detalle extremo USB: pulsadores RST/USER (rojo)", "sin pestañas junto a los pulsadores · primera guía a 1,2 mm del cuerpo del pulsador"),
     "07_pisacables": (["AVO_RevD_BASE", "AVO_RevD_PISACABLES", "AVO_RevD_MANGUITO_CABLE_TPU", "_cable"], -140, 38, (21, -21, 7), 16, ((-5, -50, -5), (45, -5, 40)), "Pisa-cables + manguito TPU", "abrazadera desmontable con 2 × M3 + insertos · mordaza curva con nervios"),
     "08_salida_cable_exterior": (["AVO_RevD_TAPA", "AVO_RevD_BASE", "AVO_RevD_MANGUITO_CABLE_TPU", "_cable"], -110, 20, (21, -30, 8), 18, None, "Salida directa del cable (antigua posición GX16)", "manguito TPU 95A: brida adaptada a la curvatura + cono antidoblado 12 mm"),
     "16_sujecion_gnd": (["AVO_RevD_BASE", "AVO_RevD_PISACABLES", "AVO_RevD_SUJECION_HELTEC"] + ELEC, -125, 40, (40, 2, 6), 22, ((-5, -45, -5), (75, 45, 40)), "Sujeción desmontable de la Heltec + punto de masa GND", "puente sobre el blindaje (0,2 + almohadilla EVA 0,5) · 2 × M2×6 en insertos M2×4 · GND: inserto M3×4 en columna Ø8 (X 48, Y −12)"),
     "17_base_sin_electronica_gnd": (["AVO_RevD_BASE"], -125, 45, (45, 0, 4), 30, ((-5, -45, -5), (95, 45, 40)), "Base: columnas de la sujeción y del punto GND", "columnas Ø6 (M2, Z 7,0) a ambos lados de la Heltec · columna GND Ø8 (M3, Z 5,5)"),
     "09_tapa_interior": (["AVO_RevD_TAPA"], -120, -60, (83, 0, 10), 55, None, "Tapa — interior", "7 columnas de cierre (C6 y C7 nuevas, lado +Y) · topes y pisador del extremo USB"),
    }
    for k, (keys, az, el, c, half, clip, t1, t2) in jobs.items():
        if which != ["all"] and k not in which: continue
        im = render(keys, az, el, c, half, clip=clip); lab(im, t1, t2).save(os.path.join(O, k + ".png")); print(k)
