import numpy as np, struct, sys, matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
from matplotlib.collections import LineCollection
O="/home/claude/apk_android_avo/hardware/back/V5_CASCO/CAD/out/"
def load(f):
    b=open(f,"rb").read(); n=struct.unpack("<I",b[80:84])[0]
    a=np.frombuffer(b[84:84+n*50],dtype=np.dtype([("n","<3f4"),("v","<9f4"),("a","<u2")]))
    return a["v"].reshape(-1,3,3).astype(float)
def cut(T,ax,val,keep):
    d=T[:,:,ax]-val; segs=[]
    for t,dd in zip(T,d):
        pts=[]
        for i in range(3):
            j=(i+1)%3
            if (dd[i]<0)!=(dd[j]<0):
                s=dd[i]/(dd[i]-dd[j]); p=t[i]+s*(t[j]-t[i]); pts.append(p[keep])
        if len(pts)==2: segs.append(pts)
    return segs
P=[("AVO_CASCO_V5_base","#222"),("AVO_CASCO_V5_anillo_resina","#2aa0d0"),("AVO_CASCO_V5_tapa","#888"),("AVO_CASCO_V5_base_casco","#b03030"),
   ("ref_pcb","#1a7a30"),("ref_componentes_cara_F","#5b8bd0"),("ref_bateria","#3c78c8"),("ref_antena","#e0a100"),("ref_pogo_placa","#d4a000"),("ref_imanes_capsula","#9050c0")]
M={n:load(O+n+".stl") for n,_ in P}
fig,axs=plt.subplots(2,2,figsize=(16,12))
for ax,(a,v,keep,ttl,xl,yl) in zip(axs.flat,[(1,23.75,[0,2],"Corte Y = +23,75 (LED D10 y anillo)",(-32,32),(-13,27)),(1,-22.5,[0,2],"Corte Y = −22,5 (pogo e imanes)",(-32,32),(-13,27)),
                              (0,-22.0,[1,2],"Corte X = −22 (tornillos)",(-32,32),(-13,27)),(2,3.0,[0,1],"Planta a Z = 3 (fondo de la base)",(-32,32),(-32,32))]):
    for n,c in P:
        s=cut(M[n],a,v,keep)
        if s: ax.add_collection(LineCollection(s,colors=c,lw=1.0,label=n.replace("AVO_CASCO_V5_","")))
    ax.set_xlim(*xl); ax.set_ylim(*yl); ax.set_aspect("equal"); ax.grid(alpha=.3); ax.set_title(ttl)
axs[0,0].legend(fontsize=7,loc="upper right")
fig.suptitle("AVO BACK V5 CASCO — cápsula 56,4 × 56,4 × 24,1 + base del casco (cortes del CAD)",fontsize=13)
plt.tight_layout(); plt.savefig(sys.argv[1],dpi=110)
