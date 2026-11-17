from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
import json
F='/tmp/fonts/m/fonts/ttf/Montserrat-%s.ttf'
def line(text, weight, x0, x1, base, cap):
    f=TTFont(F%weight); gs=f.getGlyphSet(); cmap=f.getBestCmap(); upm=f['head'].unitsPerEm
    capH=f['OS/2'].sCapHeight
    s=cap/capH
    glyphs=[cmap[ord(c)] for c in text]
    adv=[f['hmtx'][g][0] for g in glyphs]
    # ink bounds of first and last glyph to align ink to x0/x1
    from fontTools.pens.boundsPen import BoundsPen
    def bounds(g):
        bp=BoundsPen(gs); gs[g].draw(bp); return bp.bounds
    lb=bounds(glyphs[0])[0]; rb=bounds(glyphs[-1])[2]
    natural=(sum(adv[:-1])+rb-lb)*s
    track=(x1-x0-natural)/(len(text)-1)
    pen=SVGPathPen(gs, ntos=lambda v: f"{v:.2f}")
    x=x0-lb*s
    for g,a in zip(glyphs,adv):
        tp=TransformPen(pen,(s,0,0,-s,x,base))
        gs[g].draw(tp)
        x+=a*s+track
    return pen.getCommands(), track
out={}
for k,(t,w,x0,x1,b,c) in {
  'perf':("PERFORMANCE HORSE","Medium",82,597,495.0,29.5),
  'train':("TRAINING ANALYSIS","SemiBold",156,527,554.5,21.0),
  'motto':("CIENCIA  ·  TECNOLOGÍA  ·  RENDIMIENTO","SemiBold",78,908,1027.5,23.0)}.items():
    d,tr=line(t,w,x0,x1,b,c); out[k]=d; print(k,'tracking',round(tr,2))
json.dump(out,open('text_paths.json','w'))
