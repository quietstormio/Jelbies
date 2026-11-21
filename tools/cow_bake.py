import numpy as np, math, sys
from PIL import Image
from scipy import ndimage as ndi
D="/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/4c5ade4b-a768-4e5e-a1b1-52f2de759290/scratchpad/cowdraw/img/now/"
def mask(v, name="13_moo"):
    im=np.asarray(Image.open(f"{D}{name}_{v}.jpg").convert("RGB")).astype(float)/255
    lum=im@np.array([.3,.59,.11])
    m=lum<0.42
    m=ndi.binary_closing(m,iterations=2); m=ndi.binary_opening(m,iterations=1)
    return m.astype(float)
M={v:ndi.gaussian_filter(mask(v),1.0) for v in ["front","back","side"]}
CY,TOP,BOT=365,145,585
cfg={"front":(382,213),"back":(383,213),"side":(381,196)}
def samp(v,px,py):
    return ndi.map_coordinates(M[v],[[py],[px]],order=1,mode="nearest")[0]
NU,NV=128,64
out=np.zeros((NV,NU))
for j in range(NV):
    t=(j+0.5)/NV
    row=BOT-t*(BOT-TOP); ey=(row-CY)/220.0; r=math.sqrt(max(0,1-ey*ey))
    for i in range(NU):
        th=-math.pi+(i+0.5)*2*math.pi/NU
        s,c=math.sin(th),math.cos(th); d=math.degrees(th)
        def front(): return samp("front",cfg["front"][0]+cfg["front"][1]*r*s,row)
        def back(): return samp("back",cfg["back"][0]-cfg["back"][1]*r*s,row)
        def side(): return samp("side",cfg["side"][0]+cfg["side"][1]*r*c,row)
        sm=lambda a,b,x: min(1,max(0,(x-a)/(b-a)))
        if d>=0:
            w=sm(75,105,d); val=front()*(1-w)+back()*w
        else:
            a=-d  # 0..180
            if a<=60: val=front()*(1-sm(35,60,a))+side()*sm(35,60,a)
            elif a<=120: val=side()
            else: w=sm(120,150,a); val=side()*(1-w)+back()*w
        out[j,i]=val
# face clear
for j in range(NV):
    t=(j+0.5)/NV
    for i in range(NU):
        d=math.degrees(-math.pi+(i+0.5)*2*math.pi/NU)
        if abs(d)<38 and 0.40<t<0.80: out[j,i]=0
q=np.clip(np.round(out*15),0,15).astype(int)
np.save("q.npy",q)
Image.fromarray((out[::-1]*255).astype(np.uint8)).resize((NU*6,NV*6),Image.NEAREST).save("unwrap.png")
# MSL: 128*64 4-bit = 1024 uints, row-major j then i, 8 nibbles per uint
flat=q.flatten(); words=[]
for k in range(0,len(flat),8):
    w=0
    for n in range(8): w|=int(flat[k+n])<<(4*n)
    words.append(w)
open("words.txt","w").write(",".join(f"0x{w:08x}u" for w in words))
print(len(words))
