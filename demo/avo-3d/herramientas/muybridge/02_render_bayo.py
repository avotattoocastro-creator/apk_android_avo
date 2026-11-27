"""Paso 2: da color bayo, volumen, mantilla, cincha, riendas y jinete a cada silueta → work/fNN.png y work/anch.json
(anclas de espalda, pecho y cincha por fotograma). Ejecutar después del paso 1."""
import cv2,numpy as np,json,sys
W,H=620,360;AX,AY=300,332   # ancla: centro del torso, suelo
meta=np.load('work/meta.npy')
rng=np.random.default_rng(7)
def norm(v):return v/np.linalg.norm(v)
L=norm(np.array([-0.35,-0.75,0.55]));V=np.array([0,0,1.0]);Hh=norm(L+V)
fur=cv2.GaussianBlur(rng.standard_normal((H,W)).astype(np.float32),(0,0),sigmaX=3,sigmaY=0.8)
fur/=fur.std()
hair=cv2.GaussianBlur(rng.standard_normal((H,W)).astype(np.float32),(0,0),sigmaX=9,sigmaY=0.7);hair/=hair.std()
SILK=dict(a=(0.80,0.11,0.17),b=(0.96,0.94,0.90))
frames=[];anch=[]
for i in range(11):
  a=cv2.imread(f'work/a{i+1:02d}.png',0).astype(np.float32)/255
  gy=int(meta[i][0]);hard=(a>0.5).astype(np.uint8)
  t=cv2.erode(hard,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(45,45)));ys,xs=np.nonzero(t);cx=xs.mean()
  M=np.float32([[1,0,AX-cx],[0,1,AY-gy]])
  a=cv2.warpAffine(a,M,(W,H));hard=(a>0.5).astype(np.uint8)
  top=np.array([np.argmax(hard[:,x]) if hard[:,x].any() else 9999 for x in range(W)])
  cols=np.nonzero(top<9999)[0]
  # jinete: salto brusco del perfil superior
  rL=None
  for x in range(AX-80,AX+120):
    if top[x]<top[x-8]-22 and top[x-8]<9999: rL=x-3;break
  head=rL+np.argmin(top[rL:rL+90])
  seg=top[head:head+90];rR=head+int(np.argmax(seg[:60]))
  back=int(top[rL-10])+4
  yy,xx=np.mgrid[0:H,0:W]
  rider=(hard>0)&(xx>=rL)&(xx<=rR)&(yy<back)
  rtop=int(top[rL:rR].min());rh=back-rtop
  # cuerpo del caballo vs extremidades/pelo
  horse=hard.copy();horse[rider]=0
  body=cv2.morphologyEx(horse,cv2.MORPH_OPEN,cv2.getStructuringElement(cv2.MORPH_ELLIPSE,(31,31)))
  rem=(horse>0)&(body==0)
  db=cv2.distanceTransform((1-body).astype(np.uint8),cv2.DIST_L2,5)
  bys=np.nonzero(body[:,AX-40:AX+40].any(1))[0];belly=bys.max() if len(bys) else AY-120
  # altura (relieve) y normales
  d=cv2.distanceTransform(hard,cv2.DIST_L2,5)
  R=np.where(rider,18,46).astype(np.float32)
  q=np.clip(d/R,0,1);h=np.sqrt(1-(1-q)**2)*R*0.9
  h=cv2.GaussianBlur(h,(0,0),2.2)
  gx=cv2.Sobel(h,cv2.CV_32F,1,0,ksize=3)/8;gyy=cv2.Sobel(h,cv2.CV_32F,0,1,ksize=3)/8
  n=np.dstack([-gx,-gyy,np.ones_like(h)]);n/=np.linalg.norm(n,axis=2,keepdims=True)
  dif=np.clip(n@L,0,1);spec=np.clip(n@Hh,0,1)**28
  # color base
  bay=np.array([0.47,0.23,0.10]);dark=np.array([0.045,0.035,0.03])
  base=np.zeros((H,W,3),np.float32)+bay
  # variación del pelaje: lomo más oscuro, vientre y flanco más claros
  vt=np.clip((yy-(AY-260))/150,0,1)[...,None]
  base=base*(0.78+0.35*vt)
  hairm=rem&(yy<belly-10)          # cola y crin suelta
  legm=rem&(yy>=belly-10)
  # crin pegada al cuello: borde superior por delante del jinete
  mane=(hard>0)&(xx>rR-10)&(xx<rR+70)&(d<9)&(yy<belly-40)&(n[...,1]<-0.2)
  k=np.clip((db-18)/30,0,1)            # patas: negro por debajo de rodilla/corvejón
  legblend=np.where(legm,k,0)[...,None]
  base=base*(1-legblend)+dark*legblend
  hb=(hairm|mane)[...,None].astype(np.float32);hb=cv2.GaussianBlur(hb[...,0],(0,0),1.5)[...,None]
  base=base*(1-hb)+dark*1.4*hb
  # hocico más oscuro
  mz=np.clip((xx-(cols.max()-55))/40,0,1)*(yy<belly)
  base=base*(1-0.55*mz[...,None])
  # sudadero (mantilla) y cincha
  sx0,sx1=rL-16,rL+44
  topc=np.minimum.accumulate(np.where(top<9999,top,0)) if False else top
  tl=np.interp(np.arange(W),[sx0,sx1],[top[sx0],back-2])
  cm=((body>0)&(xx>sx0)&(xx<sx1)&(yy<tl[None,:]+34)&(~rider)).astype(np.float32)
  cm=cv2.GaussianBlur(cm,(0,0),2.5);cloth=cm>0.5
  base[cloth]=(0.07,0.10,0.26)
  inner=cv2.GaussianBlur((cm>0.5).astype(np.float32),(0,0),1)
  edge=cloth&(cv2.erode(cloth.astype(np.uint8),np.ones((5,5),np.uint8))==0)&(yy>tl[None,:]+6)
  base[edge]=(0.86,0.85,0.80)
  gx0=rL+48
  girth=(hard>0)&(xx>gx0)&(xx<gx0+9)&(yy>back+30)&(~legm)
  base[girth]=(0.82,0.79,0.72)
  # jinete
  ry=(yy-rtop)/max(rh,1)
  cap=rider&(ry<0.13);face=rider&(ry>=0.13)&(ry<0.24)
  torso=rider&(ry>=0.24)&~((ry>=0.74)&(xx<rL+0.5*(rR-rL)));leg=rider&(ry>=0.74)&(xx<rL+0.5*(rR-rL))
  base[cap]=SILK['a'];base[face]=(0.72,0.48,0.36)
  # chaquetilla a rombos fijos al torso
  u=(xx-rL)/21.0;v=(yy-rtop)/21.0;dia=((np.floor(u+v)+np.floor(u-v))%2)==0
  base[torso&dia]=SILK['a'];base[torso&~dia]=SILK['b']
  base[leg]=(0.93,0.92,0.88)
  boot=(hard>0)&(xx>rL-4)&(xx<rL+40)&(yy>=back)&(yy<back+40)&(d<12)&(~cloth)&(xx<gx0)
  # textura
  crease=legm&(db<16);aoc=np.where(crease,0.62+0.38*np.clip(db/16,0,1),1.0)
  belly_ao=np.clip(1-np.abs(yy-belly)/14,0,1)*(body>0)*0.25
  aoc=aoc*(1-belly_ao)
  tex=1+0.05*fur*(~rider)+0.16*hair*((hairm|mane)|(legblend[...,0]>0.6))
  shade=(0.30+0.85*dif)*tex*aoc
  rgb=base*shade[...,None]
  gloss=np.where(rider,0.12,0.26)[...,None]*(1-legblend*0.6)
  rgb+=spec[...,None]*gloss*np.array([1.0,0.95,0.85])
  # luz de borde superior (focos)
  rim=np.clip(1-d/3.5,0,1)*np.clip(-n[...,1],0,1)*0.55
  rgb+=rim[...,None]*np.array([1.0,0.96,0.86])
  # ojo, riendas
  mx=int(cols.max());ex=mx-48;ey=int(top[ex])+13
  cv2.ellipse(rgb,(ex,ey),(4,3),-20,0,360,(0.02,0.02,0.02),-1,cv2.LINE_AA)
  cv2.circle(rgb,(ex-1,ey-1),1,(0.8,0.8,0.8),-1,cv2.LINE_AA)
  hx,hy=rR+4,back-20;my_=int(top[mx-26])+24
  cv2.line(rgb,(hx,hy),(mx-26,my_),(0.10,0.06,0.03),2,cv2.LINE_AA)
  cv2.circle(rgb,(hx,hy),4,(0.92,0.92,0.9),-1,cv2.LINE_AA)
  a=np.maximum(a,cv2.line(np.zeros_like(a),(hx,hy),(mx-26,my_),1.0,2,cv2.LINE_AA))
  a=np.maximum(a,cv2.circle(np.zeros_like(a),(hx,hy),4,1.0,-1,cv2.LINE_AA))
  rgb=np.clip(rgb,0,1)**(1/1.08)
  out=np.dstack([rgb[...,::-1]*255,a*255]).astype(np.uint8)
  cv2.imwrite(f'work/f{i+1:02d}.png',out)
  # anclas para AVO (coordenadas del fotograma normalizado)
  rows=[y for y in range(rtop,back) if rider[y].any()]
  cy=int(rtop+0.42*rh);chest=int(np.nonzero(rider[cy])[0].max()) if rider[cy].any() else rR
  bk=int(np.nonzero(rider[cy])[0].min()) if rider[cy].any() else rL
  gys=np.nonzero(girth.any(1))[0];gyb=int(gys.max()) if len(gys) else int(belly)
  anch.append(dict(back=[bk-2,cy-6],chest=[chest-6,cy+4],girth=[gx0+4,gyb-3],head=[int(cols.max()),int(top[cols.max()-30])],ground=AY))
  frames.append(out)
json.dump(anch,open('work/anch.json','w'))
sheet=np.zeros((H*3,W*4,4),np.uint8)
for k,f in enumerate(frames):sheet[(k//4)*H:(k//4+1)*H,(k%4)*W:(k%4+1)*W]=f
bg=np.full((H*3,W*4,3),(40,60,45),np.uint8)
al=sheet[...,3:4]/255;comp=(sheet[...,:3]*al+bg*(1-al)).astype(np.uint8)
cv2.imwrite('work/shaded_sheet.jpg',cv2.resize(comp,None,fx=0.5,fy=0.5,interpolation=cv2.INTER_AREA))
print(anch[0])
