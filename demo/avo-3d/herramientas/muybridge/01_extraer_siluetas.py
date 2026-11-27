"""Paso 1: recorta los 11 fotogramas de galope de «The Horse in Motion» (Muybridge, 1878, dominio público),
quita rejilla y suelo y guarda máscaras con borde suave en work/aNN.png y work/meta.npy.
Ejecutar desde esta carpeta (necesita src/muybridge.jpg y la carpeta work/)."""
import cv2,numpy as np
im=cv2.imread('src/muybridge.jpg',0)
R=[(66,446),(467,849),(870,1254)];C=[(61,654),(677,1272),(1293,1888),(1911,2508)]
m=8;res=[]
for r in range(3):
  for c in range(4):
    if r==2 and c==3: continue
    y0,y1=R[r];x0,x1=C[c]
    p=im[y0+m:y1-m,x0+m:x1-m].astype(np.float32)
    h,w=p.shape
    t,_=cv2.threshold(p.astype(np.uint8),0,255,cv2.THRESH_BINARY+cv2.THRESH_OTSU)
    # papel por filas (gradiente vertical): mediana de los claros en cada banda
    paper=np.array([np.median(row[row>t]) if (row>t).sum()>20 else t+40 for row in p])
    paper=cv2.GaussianBlur(paper.reshape(-1,1),(1,0),sigmaX=1,sigmaY=15).ravel()[:,None]
    ink=np.percentile(p[p<t],20)
    a=np.clip((paper-p)/(paper-ink-8),0,1)
    hard=(a>0.55).astype(np.uint8)
    op=cv2.morphologyEx(hard,cv2.MORPH_OPEN,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(6,6)))
    # suelo: filas con mucha cobertura en la mitad inferior
    cov=op.mean(1);gy=h
    for y in range(int(h*0.78),h):
      if cov[y]>0.3: gy=y;break
    rowg={0:329,1:336,2:336}[r]
    if gy>rowg+6: gy=rowg
    op[gy-2:]=0
    n,lab,st,_=cv2.connectedComponentsWithStats(op)
    i=1+np.argmax(st[1:,4]);main=(lab==i).astype(np.uint8)
    near=cv2.dilate(main,np.ones((15,15),np.uint8))
    for j in range(1,n):
      if j!=i and st[j,4]>30 and near[lab==j].any(): main[lab==j]=1
    reg=cv2.dilate(main,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(5,5)))
    reg[gy-2:]=0
    al=(a*reg)
    res.append(dict(a=al,gy=gy-2,x0=x0+m,y0=y0+m))
    cv2.imwrite(f'work/a{len(res):02d}.png',(al*255).astype(np.uint8))
np.save('work/meta.npy',np.array([(d['gy'],d['x0'],d['y0']) for d in res]))
print([d['gy'] for d in res])
