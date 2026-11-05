from PIL import Image, ImageDraw, ImageFont
import numpy as np, cv2

SRC='/root/.claude/skills/synced/c48a3889-36a1-4ec2-980e-1a25ec6f33ad_3b1cf86d-490b-4138-b91c-83936ba043ba/moses2026-paper/assets/figure/figure-1.jpg'
FONT='/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf'
PAD_R, PAD_B = 170, 120
CX, CY = 980, 700
INK=(35,35,35)

src=Image.open(SRC).convert('RGB'); W,H=src.size
base=Image.new('RGB',(W+PAD_R,H+PAD_B),(255,255,255)); base.paste(src,(0,0))

LEG=[('Mechanisms that increases GvHD',(115,32,475,53)),
     ('Mechanisms that decreases GvHD',(114,72,481,93))]
RING=[
 [('MAMPs',(483,327,598,350))],
 [('MAMPs',(1441,157,1558,180)),('(e.g. LPS,',(1441,186,1575,217)),('DNA. RNA)',(1441,218,1593,249))],
 [('Microbial',(380,652,500,674)),('Peptides',(380,681,495,708)),('(Antigens)',(380,710,512,738))],
 [('Secondary',(314,950,478,983)),('Bile Acids',(315,984,467,1011))],
 [('SCFAs',(753,1291,866,1318))],
 [('Mucin-',(1080,1290,1183,1314)),('degrading',(1079,1321,1220,1351)),('bacteria',(1079,1352,1198,1377))],
 [('MHC-II-',(1324,1193,1435,1217)),('inducing',(1324,1224,1447,1254)),('bacteria',(1323,1256,1442,1280))],
 [('indole-3',(1645,933,1761,958)),('derivatives',(1644,964,1795,989))],
 [('Tryptophan',(1724,548,1882,578))],
 [('via Tryptophan',(1671,731,1870,761)),('metabolizing',(1672,763,1848,793)),('bacteria',(1672,795,1790,819))],
 [('IL-22',(1360,902,1441,925)),('induction',(1360,933,1492,957))],
]

# ---- 1. erase every original label by inpainting, so the blue ring is rebuilt ----
mask=np.zeros((H+PAD_B,W+PAD_R),np.uint8)
md=ImageDraw.Draw(Image.fromarray(mask))
def mrect(b,p=5):
    cv2.rectangle(mask,(max(0,b[0]-p),max(0,b[1]-p)),(b[2]+p,b[3]+p),255,-1)
for grp in RING:
    for _,b in grp: mrect(b)
cv2.rectangle(mask,(0,14),(500,104),255,-1)          # whole legend block incl. arrows
arr=cv2.inpaint(cv2.cvtColor(np.array(base),cv2.COLOR_RGB2BGR),mask,7,cv2.INPAINT_TELEA)
im=Image.fromarray(cv2.cvtColor(arr,cv2.COLOR_BGR2RGB))
d=ImageDraw.Draw(im)

# ---- 2. legend, redrawn larger ----
def arrow_color(y0,y1):
    reg=np.array(src).astype(int)[y0:y1,0:130]
    m=(reg.max(2)-reg.min(2))>50; px=reg[m]
    return tuple(int(v) for v in px[px.sum(1).argsort()[:max(1,len(px)//6)]].mean(0).round())
RED,GREEN=arrow_color(20,60),arrow_color(62,105)

def fit_size(text,target_w):
    lo,hi=6,220
    while lo<hi:
        mid=(lo+hi+1)//2
        if d.textlength(text,font=ImageFont.truetype(FONT,mid))<=target_w: lo=mid
        else: hi=mid-1
    return lo

LS=1.75
fs=int(round(max(fit_size(LEG[0][0],360),fit_size(LEG[1][0],367))*LS))
f=ImageFont.truetype(FONT,fs)
ax0=24; alen=int(190); shaft=max(5,int(9)); head=22
for i,(txt,_) in enumerate(LEG):
    cy=int(40+i*fs*1.95)+fs//2
    col=RED if i==0 else GREEN
    d.rectangle((ax0,cy-shaft//2,ax0+alen-head,cy+shaft//2),fill=col)
    d.polygon([(ax0+alen,cy),(ax0+alen-head,cy-head*0.62),(ax0+alen-head,cy+head*0.62)],fill=col)
    d.text((ax0+alen+28,cy-fs*0.62),txt,font=f,fill=INK)

# ---- 3. ring labels, redrawn larger, growing away from the ring centre ----
def redraw(lines,scale,grow=None,off=(0,0)):
    bx=[b for _,b in lines]
    ux0,uy0=min(b[0] for b in bx),min(b[1] for b in bx)
    ux1,uy1=max(b[2] for b in bx),max(b[3] for b in bx)
    s=max(1,int(round(np.median([fit_size(t,b[2]-b[0]) for t,b in lines])*scale)))
    f=ImageFont.truetype(FONT,s); lh=int(round(s*1.22))
    w=[d.textlength(t,font=f) for t,_ in lines]; newW=max(w); newH=lh*len(lines)
    gx,gy=grow if grow else (('left' if (ux0+ux1)/2<CX else 'right'),
                             ('up' if (uy0+uy1)/2<CY else 'down'))
    X=ux1-newW if gx=='left' else (ux0 if gx=='right' else (ux0+ux1)/2-newW/2)
    Y=uy1-newH if gy=='up'   else (uy0 if gy=='down' else (uy0+uy1)/2-newH/2)
    X+=off[0]; Y+=off[1]
    for i,(t,_) in enumerate(lines):
        x=X+(newW-w[i]) if gx=='left' else (X if gx=='right' else X+(newW-w[i])/2)
        d.text((x,Y+i*lh),t,font=f,fill=INK)

SPEC={'SCFAs':(1.55,('mid','down'),(0,0)),'Mucin-':(1.55,('mid','down'),(0,0)),
      'IL-22':(1.3,('right','down'),(-18,-62)),'MHC-II-':(1.55,('right','down'),(0,0))}
for grp in RING:
    sc,gr,of=SPEC.get(grp[0][0],(1.55,None,(0,0)))
    redraw(grp,sc,gr,of)

im.save('figure-1_edited.png',dpi=(300,300))
print('saved',im.size)
