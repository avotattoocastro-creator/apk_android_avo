import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle, FancyBboxPatch
# pila en Z (mm)
Z=[("suelo + pogo",0,1.4),("batería ≥ 2000 mAh (E) 45×50×7,0",1.4,7.0),("holgura",8.4,0.4),("componentes cara inferior (ZED, S3, SD, cargador)",8.8,2.6),
   ("PCB 51×51×1,6 (4 capas, masa arriba)",11.4,1.6),("antena plana activa L1/L2 25×25×8,1",13.0,8.1),("holgura",21.1,0.3),("tapa PETG 1,2 (sin metal sobre la antena)",21.4,1.2)]
H=22.6; OUT=55.0
fig,(a,b)=plt.subplots(1,2,figsize=(15,6.8),gridspec_kw=dict(width_ratios=[1.15,1]))
cols={"batería":"#7fb77e","PCB":"#2e7d32","antena":"#e0a100","componentes":"#5b8bd0","tapa":"#bbbbbb","suelo":"#888888"}
def col(n):
    for k,v in cols.items():
        if n.startswith(k) or k in n: return v
    return "#ffffff"
# alzado (corte)
a.add_patch(Rectangle((-OUT/2,-3.0),OUT,3.0,fc="#d9d2e9",ec="k"));a.text(OUT/2+1,-1.8,"base en el casco 3,0 (imanes + cinta VHB)",va="center",fontsize=8)
a.add_patch(Rectangle((-OUT/2,0),OUT,H,fc="none",ec="k",lw=1.5))
for n,z0,h in Z:
    if n=="holgura": continue
    w={"batería":45,"PCB":51,"antena":25,"componentes":45,"tapa":OUT,"suelo":OUT}
    ww=next((v for k,v in w.items() if k in n),50)
    if n.startswith("componentes"):
        for x0,l in((-24,17),(-4,15.4),(14,9)): a.add_patch(Rectangle((x0,z0),l,h,fc=col(n),ec="k",lw=.5))
    else:
        a.add_patch(Rectangle(((-ww/2+3.0) if n.startswith("bat") else -ww/2,z0),ww,h,fc=col(n),ec="k",lw=.6))
    a.text(OUT/2+1,z0+h/2,f"{n} · z {z0:.1f}–{z0+h:.1f}",va="center",fontsize=8)
a.add_patch(Rectangle((-OUT/2+2,0),4.6,3.6,fc="#c0392b",ec="k"));a.text(-27,-4.6,"corte por el pogo: 5 contactos a ras del fondo, junto a la batería (epoxi)",fontsize=8,color="#c0392b")
a.set_xlim(-32,75);a.set_ylim(-6,25);a.set_aspect("equal");a.axis("off")
a.set_title(f"Corte (estimado): {OUT:.0f} × {OUT:.0f} × {H:.1f} mm + base 3,0 · ≈ 105 g + base ≈ 10 g",fontsize=11)
# planta
b.add_patch(FancyBboxPatch((-OUT/2+3,-OUT/2+3),OUT-6,OUT-6,boxstyle="round,pad=3",fc="none",ec="k",lw=1.5))
b.add_patch(Rectangle((-25.5,-25.5),51,51,fc="#e8f5e9",ec="#2e7d32"));b.text(-25,23.3,"PCB 51 × 51 (cara superior = plano de masa)",fontsize=7,color="#2e7d32")
b.add_patch(Rectangle((-12.5,-12.5),25,25,fc="#ffe9a8",ec="#e0a100",lw=1.5));b.text(0,0,"antena\nL1/L2\n25 × 25",ha="center",va="center",fontsize=8)
for (x,y,l,w,t) in ((-23,-23,17,22,"ZED-F9P\n(debajo)"),(8,-23,15.4,15.4,"ESP32-S3\nMINI-1U\n(debajo)"),(8,9,13,13,"microSD\n(debajo)")):
    b.add_patch(Rectangle((x,y),l,w,fc="none",ec="#5b8bd0",ls="--"));b.text(x+l/2,y+w/2,t,ha="center",va="center",fontsize=7,color="#5b8bd0")
for sx in(-1,1):
    for sy in(-1,1): b.add_patch(plt.Circle((sx*24.5,sy*24.5),1.6,fc="w",ec="k"))
b.add_patch(Rectangle((-22.5,-20),45,45,fc="none",ec="#7fb77e",lw=1.5,ls=":"));b.text(-21,22,"batería 45 × 50 (debajo)",fontsize=7,color="#3c7a3b")
b.add_patch(Rectangle((-10,-25.5),20,4.6,fc="#f5b7b1",ec="#c0392b"));b.text(0,-29.5,"pogo: VBUS · D− · D+ · GND · (libre)",ha="center",fontsize=7,color="#c0392b")
b.set_xlim(-34,34);b.set_ylim(-34,32);b.set_aspect("equal");b.grid(alpha=.25);b.set_title("Planta (estimada)",fontsize=11)
fig.suptitle("AVO BACK V5 · CASCO — concepto (nada medido: E = estimado)",fontsize=12)
plt.tight_layout();plt.savefig("AVO_BACK_V5_CASCO_concepto.png",dpi=130)
