"""Paso 3: escala x2 con bordes suaves y genera las hojas de sprites de la página.

Entrada: work/f01.png … work/f11.png (de 02_render_bayo.py).
Salida: ../../web-muybridge/galope.webp (11 × 1240×720) y esfera.webp (11 × 410×295).
Ejecutar desde esta carpeta: python3 03_empaquetar_sprites.py
"""
import cv2, numpy as np

def ss(x, a, b):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)

big = []
for i in range(1, 12):
    f = cv2.imread(f'work/f{i:02d}.png', -1).astype(np.float32) / 255
    a = cv2.GaussianBlur(f[..., 3], (0, 0), 0.7)
    pm = f[..., :3] * a[..., None]
    A = cv2.resize(a, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
    P = cv2.resize(pm, None, fx=2, fy=2, interpolation=cv2.INTER_CUBIC)
    col = np.clip(P / np.maximum(A[..., None], 1e-3), 0, 1)
    bl = cv2.GaussianBlur(col, (0, 0), 1.6)
    col = np.clip(col + 0.5 * (col - bl), 0, 1)
    big.append(np.dstack([col * 255, ss(A, 0.2, 0.8) * 255]).astype(np.uint8))
cv2.imwrite('../../web-muybridge/galope.webp', np.hstack(big), [cv2.IMWRITE_WEBP_QUALITY, 86])
wf = [cv2.resize(b[16:396, 496:1024], (410, 295), interpolation=cv2.INTER_AREA) for b in big]
cv2.imwrite('../../web-muybridge/esfera.webp', np.hstack(wf), [cv2.IMWRITE_WEBP_QUALITY, 90])
print('Hecho.')
