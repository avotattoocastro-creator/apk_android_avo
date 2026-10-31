import json, numpy as np, sys
st=json.load(open('strokes.json'))
def seg(q, closed=False, start=True):
    N=len(q); d=(f"M{q[0][0]:.2f},{q[0][1]:.2f}" if start else "")
    rng=range(N) if closed else range(N-1)
    for i in rng:
        p0=q[i-1] if (closed or i>0) else q[i]; p1=q[i]; p2=q[(i+1)%N]
        p3=q[(i+2)%N] if (closed or i+2<N) else q[(i+1)%N]
        c1=p1+(p2-p0)/6; c2=p2-(p3-p1)/6
        d+=f" C{c1[0]:.2f},{c1[1]:.2f} {c2[0]:.2f},{c2[1]:.2f} {p2[0]:.2f},{p2[1]:.2f}"
    return d
def outline(s, scale, taper):
    p=np.stack([s['x'],s['y']],1); w=np.array(s['w'])*scale; closed=s['closed']
    if closed and np.allclose(p[0],p[-1]): p=p[:-1]; w=w[:-1]
    seglen=np.linalg.norm(np.diff(p,axis=0),axis=1); L=seglen.sum()
    if not closed and L<6: return None
    t=(np.roll(p,-1,0)-np.roll(p,1,0)) if closed else np.gradient(p,axis=0)
    t/=np.linalg.norm(t,axis=1,keepdims=True)+1e-9
    nrm=np.stack([-t[:,1],t[:,0]],1)
    if not closed and taper>0:
        s_=np.concatenate([[0],np.cumsum(seglen)])/L
        f=np.minimum(1,np.minimum(s_,1-s_)/taper)
        f=0.45+0.55*(f*f*(3-2*f))
        w=w*f
    w=np.maximum(w,0.9)
    Lp=p+nrm*(w[:,None]/2); Rp=p-nrm*(w[:,None]/2)
    if closed:
        return seg(Lp,True)+" Z "+seg(Rp[::-1],True)+" Z", 'EvenOdd'
    r1=w[-1]/2; r0=w[0]/2
    d=seg(Lp)
    d+=f" A{r1:.2f},{r1:.2f} 0 0 0 {Rp[-1][0]:.2f},{Rp[-1][1]:.2f}"
    d+=seg(Rp[::-1],start=False)
    d+=f" A{r0:.2f},{r0:.2f} 0 0 0 {Lp[0][0]:.2f},{Lp[0][1]:.2f} Z"
    return d,'Nonzero'
sc=float(sys.argv[1]); tp=float(sys.argv[2])
paths=[o for o in (outline(s,sc,tp) for s in st) if o]
json.dump(paths,open('outlines.json','w'))
body="".join(f'<path d="{d}" fill="white" fill-rule="{r.lower()}"/>' for d,r in paths)
open('prev3.html','w').write(f'<html><body style="margin:0;background:#3a3a44"><svg width="1240" height="1040" viewBox="235 60 310 260">{body}</svg></body></html>')
print(len(paths))
