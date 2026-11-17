import numpy as np, json
T,B=325.0,432.0
def quad(bl,br,tr,tl):   # clockwise in screen coords: tl,tr,br,bl
    pts=[tl,tr,br,bl]
    return "M"+" L".join(f"{x:.2f},{y:.2f}" for x,y in pts)+" Z"
def leg(xb,xt,hw):   # bottom-left x, top-left x
    return quad((xb,B),(xb+hw,B),(xt+hw,T),(xt,T))
hw=22.0
A = leg(165,220,hw)+" "+leg(271,220,hw)+" "+quad((173.6,415.5),(249,415.5),(249,399.5),(181.8,399.5))
V = leg(263,319,hw).replace("","")  # left leg goes down-right: top 263, bottom 319
V = quad((319,B),(341,B),(287,T),(263,T))+" "+quad((319,B),(341,B),(398,T),(376,T))
def superellipse(cx,cy,a,b,n,cw=True,N=180):
    t=np.linspace(0,2*np.pi,N,endpoint=False)
    if not cw: t=t[::-1]
    x=cx+a*np.sign(np.cos(t))*np.abs(np.cos(t))**(2/n); y=cy+b*np.sign(np.sin(t))*np.abs(np.sin(t))**(2/n)
    return "M"+" L".join(f"{xx:.2f},{yy:.2f}" for xx,yy in zip(x,y))+" Z"
cx,cy=461.0,378.5
O = superellipse(cx,cy,56,53.5,2.35)+" "+superellipse(cx,cy,56-19.5,53.5-17.5,2.35)
json.dump({'A':A,'V':V,'O':O},open('avo2.json','w'))
import base64
img=base64.b64encode(open('/tmp/hero/avo_home_hero.jpg','rb').read()).decode()
body=f'<path d="{A}" fill="none" stroke="red" stroke-width="0.6"/><path d="{V}" fill="none" stroke="red" stroke-width="0.6"/><path d="{O}" fill="none" stroke="red" stroke-width="0.6"/>'
open('cmp_avo.html','w').write(f'<html><body style="margin:0"><svg width="1200" height="420" viewBox="150 310 400 140"><image href="data:image/jpeg;base64,{img}" x="0" y="0" width="2004" height="1098"/>{body}</svg></body></html>')
