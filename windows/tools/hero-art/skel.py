import numpy as np, cv2
from skimage.morphology import skeletonize
from scipy.ndimage import distance_transform_edt, gaussian_filter1d
from scipy.interpolate import splprep, splev
S=4; X0,Y0=235,60
white=np.load('white.npy')
soft=np.clip((white-30)/40,0,1)
soft=cv2.GaussianBlur(soft,(0,0),2.2)
m=(soft>0.5).astype(np.uint8)
n,lab,stats,_=cv2.connectedComponentsWithStats(m,8)
keep=np.zeros_like(m)
for i in range(1,n):
    if stats[i,cv2.CC_STAT_AREA]>=250: keep[lab==i]=1
dist=distance_transform_edt(keep)
sk=skeletonize(keep>0)
H,W=sk.shape
pts=set(zip(*np.where(sk)))
def nb(p):
    y,x=p
    return [(y+dy,x+dx) for dy in (-1,0,1) for dx in (-1,0,1) if (dy or dx) and (y+dy,x+dx) in pts]
deg={p:len(nb(p)) for p in pts}
nodes={p for p in pts if deg[p]!=2}
used=set()
branches=[]
def walk(a,b):
    path=[a,b]; prev,cur=a,b
    while cur not in nodes:
        nxt=[q for q in nb(cur) if q!=prev and (min(cur,q),max(cur,q)) not in used]
        if not nxt: break
        # prefer 4-neighbours to avoid diagonal shortcuts
        nxt.sort(key=lambda q: abs(q[0]-cur[0])+abs(q[1]-cur[1]))
        q=nxt[0]
        used.add((min(cur,q),max(cur,q)))
        prev,cur=cur,q; path.append(cur)
        if cur==path[0]: break
    return path
for a in nodes:
    for b in nb(a):
        e=(min(a,b),max(a,b))
        if e in used: continue
        used.add(e)
        branches.append(walk(a,b))
# pure loops
rem=[p for p in pts if p not in nodes and all((min(p,q),max(p,q)) not in used for q in nb(p))]
seen=set()
for p in rem:
    if p in seen: continue
    q=nb(p)[0]; used.add((min(p,q),max(p,q)))
    path=walk(p,q); seen.update(path); path.append(p); branches.append(path)
print('branches',len(branches))
out=[]
for br in branches:
    a=np.array(br,float)
    if len(a)<10: continue          # spurs
    closed=np.allclose(a[0],a[-1]) and len(a)>20
    w=np.array([dist[int(y),int(x)] for y,x in a])
    # dedupe consecutive
    keepi=[0]+[i for i in range(1,len(a)) if np.any(a[i]!=a[i-1])]
    a=a[keepi]; w=w[keepi]
    if len(a)<8: continue
    x=a[:,1]; y=a[:,0]
    try:
        k=3 if len(a)>4 else 1
        tck,u=splprep([x,y,w],s=len(a)*2.0,per=1 if closed else 0,k=k)
    except Exception as ex:
        print('skip',ex); continue
    M=max(12,len(a)//6)
    uu=np.linspace(0,1,M)
    sx,sy,sw=splev(uu,tck)
    sw=gaussian_filter1d(np.maximum(sw,1.2),3,mode='wrap' if closed else 'nearest')
    out.append(dict(x=((sx/S)+X0).tolist(),y=((sy/S)+Y0).tolist(),w=(sw*2/S).tolist(),closed=bool(closed)))
import json; json.dump(out,open('strokes.json','w'))
print('strokes',len(out))
