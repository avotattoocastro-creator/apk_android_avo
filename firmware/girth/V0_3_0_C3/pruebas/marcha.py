"""Simulador SINTÉTICO de señales de la cincha (paso, trote, galope y caída tras un salto) para probar la
adquisición, el empaquetado y el reenvío de los 9 canales. NO son datos medidos: amplitudes y frecuencias de
orden de magnitud para un sensor en el tórax del caballo (cincha), elegidas para cubrir el rango del firmware
(±8 g, ±2000 °/s, ±8 G) y provocar saturación a propósito en el caso «salto».

Uso: python3 marcha.py salida_dir      → escribe <marcha>.csv (t, ax, ay, az [g], gx, gy, gz [°/s], mx, my, mz [G])
"""
import math
import os
import sys

FS = 104.0          # Hz, ODR del LSM6DS3TR-C en el firmware
DUR = 20.0          # s por marcha

# zancada (Hz), aceleración vertical (g pico), longitudinal y lateral (g), cabeceo y guiñada (°/s), picos de impacto
GAITS = {
    "paso":   dict(f=0.9, beats=4, av=0.35, al=0.25, at=0.15, wp=25.0, wy=15.0, wr=10.0, imp=0.0),
    "trote":  dict(f=1.5, beats=2, av=1.4, al=0.6, at=0.3, wp=60.0, wy=25.0, wr=30.0, imp=0.8),
    "galope": dict(f=2.0, beats=3, av=2.6, al=1.4, at=0.6, wp=140.0, wy=40.0, wr=60.0, imp=1.8),
    "salto":  dict(f=2.0, beats=3, av=2.6, al=1.4, at=0.6, wp=180.0, wy=40.0, wr=80.0, imp=1.8, landing=10.5),
}
EARTH = (0.20, 0.02, -0.42)   # G, campo terrestre aproximado en España (horizontal ~0,2 G, inclinación ~60°)
CAPS_OFFSET = (0.30, -0.15, 0.55)   # G, desvío fijo supuesto por los imanes de la cápsula (calibrable)


def rot(v, pitch, roll, yaw):
    x, y, z = v
    cy, sy = math.cos(yaw), math.sin(yaw)
    x, y = cy * x - sy * y, sy * x + cy * y
    cp, sp = math.cos(pitch), math.sin(pitch)
    x, z = cp * x + sp * z, -sp * x + cp * z
    cr, sr = math.cos(roll), math.sin(roll)
    y, z = cr * y - sr * z, sr * y + cr * z
    return x, y, z


def gen(name, p, path):
    n = int(DUR * FS)
    pitch = roll = yaw = 0.0
    with open(path, "w") as f:
        f.write("t,ax,ay,az,gx,gy,gz,mx,my,mz\n")
        for k in range(n):
            t = k / FS
            ph = 2 * math.pi * p["f"] * t
            wy = p["wy"] * math.sin(ph + 0.3)
            wp = p["wp"] * math.sin(ph * 1.0 + 1.1) + 0.3 * p["wp"] * math.sin(2 * ph)
            wr = p["wr"] * math.sin(ph + 2.0)
            pitch += math.radians(wp) / FS; roll += math.radians(wr) / FS; yaw += math.radians(wy) / FS
            pitch *= 0.995; roll *= 0.995                                   # sin deriva: el tronco vuelve
            av = p["av"] * (0.5 + 0.5 * math.cos(p["beats"] * ph))          # empuje en cada apoyo
            imp = 0.0
            frac = (p["beats"] * p["f"] * t) % 1.0
            if p["imp"] and frac < 0.06:
                imp = p["imp"] * math.sin(math.pi * frac / 0.06)             # impacto corto de cada apoyo
            if "landing" in p and 9.0 <= t < 9.08:
                imp += p["landing"] * math.sin(math.pi * (t - 9.0) / 0.08)    # recepción tras el salto
            ax = p["al"] * math.sin(p["beats"] * ph + 0.7)
            ay = p["at"] * math.sin(ph + 0.4)
            az = -1.0 - av - imp                                             # eje Z hacia abajo = −1 g en reposo
            gx, gy, gz = wr, wp, wy
            m = rot(EARTH, pitch, roll, yaw)
            mx, my, mz = (m[0] + CAPS_OFFSET[0], m[1] + CAPS_OFFSET[1], m[2] + CAPS_OFFSET[2])
            f.write("%.6f,%.5f,%.5f,%.5f,%.3f,%.3f,%.3f,%.5f,%.5f,%.5f\n" % (t, ax, ay, az, gx, gy, gz, mx, my, mz))


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name, p in GAITS.items():
        gen(name, p, os.path.join(out, name + ".csv"))
        print("escrito", name)
