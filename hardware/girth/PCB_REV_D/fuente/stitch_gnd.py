"""Vías GND de cosido para islas del relleno de F.Cu sin vía (lee la placa del CI con rellenos, escribe en _ruteado con --write)."""
import re, sys, numpy as np, uuid
from matplotlib.path import Path
import repair, build, avo_girth_revd_pcb as D
ci=open('../kicad/AVO_GIRTH_REVD_PCB.kicad_pcb').read()
polys=[]
for m in re.finditer(r'\(filled_polygon\s*\(layer "F\.Cu"\)\s*\(pts(.*?)\n\t\t\t\)',ci,re.S):
    polys.append(np.array([(float(a),float(b)) for a,b in re.findall(r'\(xy ([\d.\-]+) ([\d.\-]+)\)',m.group(1))]))
gv=[(float(a),float(b)) for a,b,n in re.findall(r'\(via\s+\(at ([\d.\-]+) ([\d.\-]+)\).*?\(net (\d+)\)',ci,re.S) if n=='3']
src='../kicad/AVO_GIRTH_REVD_PCB_ruteado.kicad_pcb'
segs,vias,fps=repair.read_board(src); pads=build.collect_pads()
r=repair.make_router(pads,segs,vias)
nid=D.CODE['GND']
vm=r.via_mask(nid) & ~build.drill_block(r,pads)
cand=np.argwhere(vm)
xy=np.array([r.xy(i,j) for i,j in cand])
ang=np.linspace(0,2*np.pi,12,endpoint=False); ring=np.stack([np.cos(ang),np.sin(ang)],1)*0.32
added=[]
for k,pl in enumerate(polys):
    P=Path(pl)
    if any(P.contains_point(v) for v in gv): continue
    inside=P.contains_points(xy)
    pts=xy[inside]
    pts=[p for p in pts if P.contains_points(p+ring).all()]
    if not pts: print('poly',k,'sin sitio', pl.min(0).round(1), pl.max(0).round(1)); continue
    c=pl.mean(0); p=min(pts,key=lambda q: np.hypot(*(q-c)))
    print('poly',k,'vía en',np.round(p,3)); added.append(tuple(p))
s=open(src).read()
gid=re.search(r'\(net (\d+) "GND"\)',s).group(1)
txt=''.join('\t(via\n\t\t(at %.4f %.4f)\n\t\t(size 0.5)\n\t\t(drill 0.3)\n\t\t(layers "F.Cu" "B.Cu")\n\t\t(net %s)\n\t\t(uuid "%s")\n\t)\n'%(x,y,gid,uuid.uuid4()) for x,y in added)
i=s.find('\t(via\n')
s=s[:i]+txt+s[i:]
if '--write' in sys.argv: open(src,'w').write(s); print('escritas',len(added))
