import struct,zlib,sys,collections
def parse(path):
    b=open(path,'rb').read();ver=struct.unpack('<I',b[23:27])[0];big=ver>=7500
    def rd(o):
        if big:end,np,pl=struct.unpack('<QQQ',b[o:o+24]);o+=24
        else:end,np,pl=struct.unpack('<III',b[o:o+12]);o+=12
        if end==0:return None,o
        nl=b[o];name=b[o+1:o+1+nl].decode('latin1');o+=1+nl
        props=[]
        for _ in range(np):
            t=chr(b[o]);o+=1
            if t=='S' or t=='R':l=struct.unpack('<I',b[o:o+4])[0];v=b[o+4:o+4+l];o+=4+l;props.append(v.decode('latin1','replace') if t=='S' else v)
            elif t in 'YCIFDL':sz={'Y':2,'C':1,'I':4,'F':4,'D':8,'L':8}[t];fmt={'Y':'<h','C':'?','I':'<i','F':'<f','D':'<d','L':'<q'}[t];props.append(struct.unpack(fmt,b[o:o+sz])[0]);o+=sz
            else:
                n,enc,cl=struct.unpack('<III',b[o:o+12]);o+=12;props.append(('arr',t,n));o+=cl
        kids=[]
        while o<end:
            k,o2=rd(o)
            if k is None:o=o2;break
            kids.append(k);o=o2
        return (name,props,kids),end
    o=27;top=[]
    while o<len(b)-200:
        n,o2=rd(o)
        if n is None:break
        top.append(n);o=o2
    return top
t=parse(sys.argv[1])
objs=[n for n in t if n[0]=='Objects'][0][2]
c=collections.Counter((k[0],k[1][2] if len(k[1])>2 else '') for k in objs);print(c)
for k in objs:
    if k[0] in('Model','AnimationStack','Geometry','Material','Texture','Video') and (k[0]!='Model' or k[1][2]=='Mesh'):
        print(k[0],repr(k[1][1].split('\x00')[0]),k[1][2] if len(k[1])>2 else '')
# duración de las pilas
for k in objs:
    if k[0]=='AnimationStack':
        p=[x for x in k[2] if x[0]=='Properties70']
        for q in (p[0][2] if p else []):
            if q[1][0] in('LocalStop','ReferenceStop'):print('  ',k[1][1].split('\x00')[0],q[1][0],q[1][-1]/46186158000,'s')
print('---modelos')
skinned=set()
conns=[n for n in t if n[0]=='Connections'][0][2]
ids={k[1][0]:(k[0],k[1][1].split('\x00')[0],k[1][2] if len(k[1])>2 else '') for k in objs}
for c in conns:
    a,bb=c[1][1],c[1][2]
    if ids.get(a,('',))[0]=='Geometry' and ids.get(bb,('',))[0]=='Model':pass
for k in objs:
    if k[0]=='Deformer' and k[1][2]=='Skin':
        for c in conns:
            if c[1][1]==k[1][0]:print('skin->',ids.get(c[1][2]))
gs=[n for n in t if n[0]=='GlobalSettings']
for q in gs[0][2][1][2] if gs else []:
    if q[1][0] in('UpAxis','UnitScaleFactor','TimeMode','CustomFrameRate','FrontAxis','CoordAxis'):print(q[1][0],q[1][-1])
