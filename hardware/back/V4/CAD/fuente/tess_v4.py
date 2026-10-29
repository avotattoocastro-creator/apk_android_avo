import os, glob, numpy as np, Part
H = os.path.dirname(os.path.abspath(__file__)); D = os.path.join(H, "salida", "_tess"); os.makedirs(D, exist_ok=True)
srcs = glob.glob(os.path.join(H, "salida", "BREP", "AVO_BACK_V4_*.brep")) + glob.glob(os.path.join(H, "salida", "REFERENCIAS", "_*.brep")) + glob.glob(os.path.join(H, "salida", "PROBETAS", "*.brep"))
for p in srcs:
    s = Part.Shape(); s.read(p)
    v, f = s.tessellate(0.03)
    k = os.path.basename(p)[:-5]
    np.savez_compressed(os.path.join(D, k + ".npz"), v=np.array([[q.x, q.y, q.z] for q in v], np.float32), f=np.array(f, np.int32))
    print(k, len(f))
