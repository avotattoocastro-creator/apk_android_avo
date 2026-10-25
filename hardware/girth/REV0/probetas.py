"""AVO GIRTH · placa de probetas REV 0 (PETG, Centauri Carbon).
Solo sólidos positivos (cajas, anillos, cilindros) solapados: el laminador los une.
Medidas de los componentes = anuncios (pendiente calibre). Holgura nominal 0,20 mm por lado salvo variantes.
"""
import numpy as np, struct, math, json

tris = []
def quad(a, b, c, d): tris.extend([(a, b, c), (a, c, d)])
def box(x0, y0, z0, x1, y1, z1):
    p = [(x0,y0,z0),(x1,y0,z0),(x1,y1,z0),(x0,y1,z0),(x0,y0,z1),(x1,y0,z1),(x1,y1,z1),(x0,y1,z1)]
    q = lambda i,j,k,l: quad(p[i],p[j],p[k],p[l])
    q(0,3,2,1); q(4,5,6,7); q(0,1,5,4); q(1,2,6,5); q(2,3,7,6); q(3,0,4,7)
def frame(cx, cy, iw, ih, wall, z0, z1, gaps=()):
    """rectangular wall around an iw x ih cavity centred at cx,cy. gaps: list of (side, centre, width) openings"""
    x0, x1, y0, y1 = cx-iw/2, cx+iw/2, cy-ih/2, cy+ih/2
    def seg(side, a, b):
        if b <= a: return
        if side == 'S': box(a, y0-wall, z0, b, y0, z1)
        if side == 'N': box(a, y1, z0, b, y1+wall, z1)
        if side == 'W': box(x0-wall, a, z0, x0, b, z1)
        if side == 'E': box(x1, a, z0, x1+wall, b, z1)
    for side, a, b in (('S', x0-wall, x1+wall), ('N', x0-wall, x1+wall), ('W', y0, y1), ('E', y0, y1)):
        cuts = sorted([(c-w/2, c+w/2) for s, c, w in gaps if s == side])
        cur = a
        for g0, g1 in cuts: seg(side, cur, g0); cur = g1
        seg(side, cur, b)
def tube(cx, cy, r_out, r_in, z0, z1, n=40):
    for i in range(n):
        a0, a1 = 2*math.pi*i/n, 2*math.pi*(i+1)/n
        po = lambda a, z, r: (cx + r*math.cos(a), cy + r*math.sin(a), z)
        quad(po(a0,z0,r_out), po(a1,z0,r_out), po(a1,z1,r_out), po(a0,z1,r_out))       # outer
        if r_in > 0:
            quad(po(a1,z0,r_in), po(a0,z0,r_in), po(a0,z1,r_in), po(a1,z1,r_in))   # inner
            quad(po(a0,z1,r_out), po(a1,z1,r_out), po(a1,z1,r_in), po(a0,z1,r_in))  # top
            quad(po(a1,z0,r_out), po(a0,z0,r_out), po(a0,z0,r_in), po(a1,z0,r_in))  # bottom
        else:
            tris.append(((cx,cy,z1), po(a0,z1,r_out), po(a1,z1,r_out)))
            tris.append(((cx,cy,z0), po(a1,z0,r_out), po(a0,z0,r_out)))
def notch_marks(x, y, n, z):      # n small bumps = variant number (readable by touch)
    for i in range(n): box(x + i*2.0, y, z, x + i*2.0 + 1.0, y + 1.0, z + 0.6)

B = 1.2          # base plate
WALL = 1.6
G = 0.20         # clearance per side (nominal)
parts = {}

# plate 172 x 86 (bed-friendly), coupons laid out left->right
box(0, 0, 0, 172, 92, B)

# P1 battery cradle (LP403048: 30.5 x 50.8 x 4.3 max) + wire exit at the PCM end
bw, bl = 30.5 + 2*G, 50.8 + 2*G
frame(32, 46, bl, bw, WALL, B, B + 3.0, gaps=[('E', 46 + 8, 5.0)])
for k in (-1, 1):                     # crush ribs 0.3 on the long walls
    for x in (32 - 15, 32, 32 + 15): box(x - 0.6, 46 + k*(bw/2) - (0.3 if k > 0 else 0), B, x + 0.6, 46 + k*(bw/2) + (0.3 if k < 0 else 0), B + 3.0)
parts['P1'] = 'cuna batería 51,2 × 30,9 (holgura 0,2) + costillas 0,3 + salida de cables'

# P2 BNO085 pocket (25.8 x 15.5) with two standoffs at the diagonal holes (provisional: 2.5 mm from the edges)
nx, ny = 25.8 + 2*G, 15.5 + 2*G
cx, cy = 84, 70
frame(cx, cy, nx, ny, WALL, B, B + 3.2, gaps=[('W', cy, 8.0)])          # wire exit on the pin side
for (hx, hy) in ((-25.8/2 + 2.5, -15.5/2 + 2.5), (25.8/2 - 2.5, 15.5/2 - 2.5)):
    tube(cx + hx, cy + hy, 2.3, 0.85, B, B + 1.5)                       # standoff 1.5, pilot Ø1.7 for M2 self-tap
parts['P2'] = 'alojamiento BNO085 26,2 × 15,9, 2 postes 1,5 mm con agujero Ø1,7 (M2 rosca chapa) en diagonal — POSICIÓN DE TALADROS PROVISIONAL'

# P3 ESP32-C6 pockets, three clearances (0.10 / 0.20 / 0.30) + USB-C opening 9.4 wide
for i, g in enumerate((0.10, 0.20, 0.30)):
    cx, cy = 74 + i*27, 26
    frame(cx, cy, 21 + 2*g, 18 + 2*g, WALL, B, B + 2.5, gaps=[('N', cx, 9.4)])
    notch_marks(cx - 9, cy - 9 - g - WALL - 1.6, i + 1, B)
parts['P3'] = 'C6 21 × 18 con holguras 0,10 / 0,20 / 0,30 (1, 2 y 3 marcas) y salida USB-C 9,4'

# P4 Qi coil pocket (23 x 30) depth 1.4 + Qi PCB pocket (15 x 18)
frame(126, 64, 23 + 2*G, 30 + 2*G, WALL, B, B + 1.4, gaps=[('E', 64 + 10, 3.0)])
frame(150, 64, 15 + 2*G, 18 + 2*G, WALL, B, B + 2.5, gaps=[('W', 64 + 4, 4.0)])
parts['P4'] = 'bobina Qi 23,4 × 30,4 prof. 1,4 · placa Qi 15,4 × 18,4'

# P5 reed channel (body 14 x 3.2) with lead grooves
frame(152, 42, 14 + 2*G, 3.2 + 2*G, 1.2, B, B + 3.4, gaps=[('W', 42, 1.2), ('E', 42, 1.2)])
box(152 - 7 - 9.2, 42 - 1.6 - 1.2, B, 152 - 7 - 1.2, 42 - 0.6, B + 1.2)   # lead guide W
box(152 + 7 + 1.2, 42 - 1.6 - 1.2, B, 152 + 7 + 9.2, 42 - 0.6, B + 1.2)   # lead guide E
parts['P5'] = 'canal reed 14,4 × 3,6 con guías para las patas'

# P6 magnet pockets Ø6 x 2: press fit (Ø6.15) and slip (Ø6.35), both 4.2 deep for two magnets
tube(150, 10, 5.0, 6.15/2, B, B + 4.2)
tube(163, 10, 5.0, 6.35/2, B, B + 4.2)
notch_marks(147, 3.5, 1, B); notch_marks(160, 3.5, 2, B)
parts['P6'] = 'imán Ø6: a presión Ø6,15 (1 marca) y deslizante Ø6,35 (2 marcas), prof. 4,2 para 2 imanes'

# write binary STL
def write(path):
    with open(path, 'wb') as f:
        f.write(b'AVO GIRTH probetas REV0'.ljust(80, b' ')); f.write(struct.pack('<I', len(tris)))
        for a, b, c in tris:
            a, b, c = map(np.array, (a, b, c)); n = np.cross(b - a, c - a); l = np.linalg.norm(n)
            n = n / l if l else n
            f.write(struct.pack('<12fH', *n, *a, *b, *c, 0))
write('AVO_GIRTH_PROBETAS_REV0.stl')
json.dump(parts, open('probetas.json', 'w'), ensure_ascii=False, indent=1)
print(len(tris), 'triangles')
