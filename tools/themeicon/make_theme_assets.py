#!/usr/bin/env python3
"""Generates the per-theme assets: app icons (Peek design), recoloured intro videos. Mirrors ThemeMath.palette / IconPalette in Swift.
usage: make_theme_assets.py <repo-root> [sheet.png]"""
import colorsys, subprocess, sys, json, os
from PIL import Image, ImageDraw

PRESETS = {"sky":0x5A97D6,"pink":0xEE8DB6,"mint":0x5FC4A0,"lavender":0x9D8CDF,"yellow":0xF2C14E,"peach":0xF4A27A,"navy":0x26335F,"teal":0x2FA3A6}
BLUE = (141,184,223)  # the logo's original outline blue (#8DB8E0-ish)

def hsb(hx): return colorsys.rgb_to_hsv((hx>>16&255)/255,(hx>>8&255)/255,(hx&255)/255)
def rgb(h,s,b):
    r,g,bl = colorsys.hsv_to_rgb(h,min(max(s,0),1),min(max(b,0),1)); return (round(r*255),round(g*255),round(bl*255))

LOGO_RIM={"sky":0x5A97D6,"navy":0x26335F,"pink":0xD9668F,"mint":0x2E9C78,"lavender":0x7A66CC,"yellow":0xC08A1E,"peach":0xD9774A,"teal":0x1F8A8D}
def outline(pid):   # deeper logo outline; sky/navy use the palette rim
    if pid in LOGO_RIM: h=LOGO_RIM[pid]; return (h>>16&255,h>>8&255,h&255)
    if pid=="sky": return (0x8D,0xB8,0xE0)
    h,s,b = hsb(PRESETS[pid]); dark = b<0.45
    return rgb(h, s*0.64, min(1, b+0.3 if dark else b+0.04))

def icon_colors(pid, mode="light"):
    hx=PRESETS[pid]; h,s,b=hsb(hx); dark=b<0.45
    c=dict(bg=((hx>>16&255),(hx>>8&255),(hx&255)), body=(255,255,255), hi=(255,255,255),
           line=rgb(h,s,min(1,b+0.3)) if dark else rgb(h,min(1,s+0.1),b*0.72),
           ink=rgb(h,min(1,s*0.9+0.1),min(b*0.4,0.28)), shine=rgb(h,s*0.3,1.0))
    if mode=="dark": c["bg"]=rgb(h,s*0.7,0.18); c["line"]=c["bg"] if False else rgb(h,s*0.8,min(1,b+0.05) if not dark else 0.6)
    if mode=="tinted": c=dict(bg=(20,20,20),body=(235,235,235),line=(140,140,140),ink=(35,35,35),hi=(255,255,255),shine=(250,250,250))
    return c

def bez(p0,p1,p2,p3,n=60):
    return [tuple((1-t)**3*p0[i]+3*(1-t)**2*t*p1[i]+3*(1-t)*t*t*p2[i]+t**3*p3[i] for i in (0,1)) for t in [k/n for k in range(n+1)]]
BODY = (bez((0,-545),(276,-545),(500,-301),(500,0))+bez((500,0),(500,608),(276,1100),(0,1100))
        +bez((0,1100),(-276,1100),(-500,608),(-500,0))+bez((-500,0),(-500,-301),(-276,-545),(0,-545)))

# Peek v4: the TOP of the real Jelbie head, zoomed so only the crown, eyes and brows show in the bottom half (1024 space).
# Proportions come straight from BobForm in BobV1/Melon/Contracts.swift (front profile, eyes, brows); world units -> px by SC.
# Mirrored by ThemeIconView in ThemeColor.swift (which calls BobForm.halfWidth directly).
import math
F_LIFT, F_BODYH, F_HALFW = 0.1039, 1.2419, 0.5836
F_TW, F_RATIO, F_PB, F_PT = 0.4828, 0.4089, 2.8358, 2.1049     # BobForm.front
F_TOP = F_LIFT + F_BODYH
EYE_X, EYE_Y, EYE_HW, EYE_HH = 0.215, 0.82, 0.0532, 0.0623
BROW_Y, BROW_HL, BROW_HT, BROW_TILT = 0.945, 0.069, 0.0115, 0.085
def unit_front(t):
    if t <= F_TW:
        u0=(1-F_RATIO**F_PB)**(1/F_PB); A=F_TW/u0; u=(F_TW-t)/A
        return max(0,1-u**F_PB)**(1/F_PB)
    s=(t-F_TW)/(1-F_TW); return max(0,1-s**F_PT)**(1/F_PT)
def half_width(wy): return F_HALFW*unit_front(min(max((wy-F_LIFT)/F_BODYH,0),1))
Z = 1.07                    # whole Jelbie scaled by Z about the bottom-centre (512,1024)
SC = 850*Z                  # px per world unit
TOP_Y = 1024+(430-1024)*Z   # crown ~38% down
def px_y(wy): return TOP_Y+(F_TOP-wy)*SC
CX = 512
OUTLINE_W = 44*Z
def contour(n=1500, y_end=1100, k=1.0, pivot_y=1024+(900-1024)*Z):
    """left-half contour (x<=CX) from the crown down to y_end; k insets about (CX,pivot_y)."""
    pts=[]
    wy_end=F_TOP-(y_end-TOP_Y)/SC
    for i in range(n+1):
        wy=F_TOP-(F_TOP-wy_end)*(i/n)**1.0
        x=CX-half_width(wy)*SC; y=px_y(wy)
        pts.append((CX+(x-CX)*k, pivot_y+(y-pivot_y)*k))
    return pts

def render_icon(c, S=4):
    N=1024*S; im=Image.new("RGB",(N,N),c["bg"]); d=ImageDraw.Draw(im)
    P=lambda x,y:(x*S,y*S)
    def ell(cx,cy,rx,ry,col): d.ellipse([(cx-rx)*S,(cy-ry)*S,(cx+rx)*S,(cy+ry)*S],fill=col)
    L=contour(); R=[(2*CX-x,y) for x,y in L]
    # outline: a band of width OUTLINE_W centred on the contour, from offset polygons; outer and inner are each ONE closed polygon (no seam at the crown)
    def offs(side):
        outer=[];inner=[]
        for i,(x,y) in enumerate(side):
            a=side[max(i-1,0)]; b=side[min(i+1,len(side)-1)]; tx,ty=b[0]-a[0],b[1]-a[1]; n=math.hypot(tx,ty) or 1
            nx,ny=-ty/n,tx/n
            if nx*(x-CX)+ny*(y-(1024+(900-1024)*Z))<0: nx,ny=-nx,-ny
            outer.append((x+nx*OUTLINE_W/2,y+ny*OUTLINE_W/2)); inner.append((x-nx*OUTLINE_W/2,y-ny*OUTLINE_W/2))
        return outer,inner
    oL,iL=offs(L); oR=[(2*CX-x,y) for x,y in oL]; iR=[(2*CX-x,y) for x,y in iL]
    d.polygon([P(*q) for q in oL+oR[::-1]],fill=c["line"])
    d.polygon([P(*q) for q in iL+iR[::-1]],fill=c["body"])
    # shine: an arc just inside the upper-left of the head, with a dot beyond it
    I=contour(k=0.88); acc=[0.0]
    for i in range(1,len(I)): acc.append(acc[-1]+math.dist(I[i],I[i-1]))
    def at(sl):
        for i in range(len(I)):
            if acc[i]>=sl: return I[i]
    arc=[P(*at((70+i*7.5)*Z)) for i in range(41)]
    d.line(arc,fill=c["shine"],width=round(40*Z*S),joint="curve")
    for q in (arc[0],arc[-1]): r=20*Z*S; d.ellipse([q[0]-r,q[1]-r,q[0]+r,q[1]+r],fill=c["shine"])
    q=P(*at(430*Z)); r=18*Z*S; d.ellipse([q[0]-r,q[1]-r,q[0]+r,q[1]+r],fill=c["shine"])
    ey=px_y(EYE_Y); by=px_y(BROW_Y); ex=EYE_X*SC; hl=BROW_HL*SC; ht=BROW_HT*SC
    for sx in (-1,1):
        # brow: capsule, inner end raised by atan(BROW_TILT) like the in-game brow
        cx=CX+sx*ex; dy=math.sin(math.atan(BROW_TILT))*(hl-ht)
        a_,b_=P(cx-sx*(hl-ht),by-dy),P(cx+sx*(hl-ht),by+dy)
        d.line([a_,b_],fill=c["ink"],width=round(2*ht*S)); rr=ht*S
        for q in (a_,b_): d.ellipse([q[0]-rr,q[1]-rr,q[0]+rr,q[1]+rr],fill=c["ink"])
        rx,ry=EYE_HW*SC,EYE_HH*SC
        ell(cx,ey,rx,ry,c["ink"]); ell(cx-sx*0.36*rx*0.9,ey-0.40*ry*0.9,0.2*rx,0.2*rx,c["hi"])
    return im.resize((1024,1024),Image.LANCZOS)

def recolor(im,pid):
    A=outline(pid); W=(255,255,255); v=[W[i]-BLUE[i] for i in range(3)]; vv=sum(x*x for x in v)
    px=im.convert("RGBA"); out=[]
    for r,g,b,a in px.getdata():
        t=sum((W[i]-p)*v[i] for i,p in enumerate((r,g,b)))/vv; t=min(max(t,0),1)
        out.append(tuple(round(W[i]+(A[i]-W[i])*t) for i in range(3))+(a,))
    px.putdata(out); return px

def main():
    root=sys.argv[1]; cat=f"{root}/BobV1/Assets.xcassets"; names={}
    for pid in PRESETS:
        name="AppIcon" if pid=="sky" else "AppIcon-"+pid.capitalize()
        d=f"{cat}/{name}.appiconset"; os.makedirs(d,exist_ok=True)
        render_icon(icon_colors(pid)).save(f"{d}/icon_light.png")
        imgs=[{"filename":"icon_light.png","idiom":"universal","platform":"ios","size":"1024x1024"}]
        if pid=="sky":
            render_icon(icon_colors(pid,"dark")).save(f"{d}/icon_dark.png"); render_icon(icon_colors(pid,"tinted")).convert("L").convert("RGB").save(f"{d}/icon_tinted.png")
            imgs+=[{"appearances":[{"appearance":"luminosity","value":"dark"}],"filename":"icon_dark.png","idiom":"universal","platform":"ios","size":"1024x1024"},
                   {"appearances":[{"appearance":"luminosity","value":"tinted"}],"filename":"icon_tinted.png","idiom":"universal","platform":"ios","size":"1024x1024"}]
        json.dump({"images":imgs,"info":{"author":"xcode","version":1}},open(f"{d}/Contents.json","w"),indent=2)
    # intro videos
    src=f"{root}/BobV1/Start/Resources/jelbies_intro.mp4"
    for pid in PRESETS:
        A=outline(pid); W=255; v=[W-BLUE[i] for i in range(3)]; vv=sum(x*x for x in v)
        t="clip(((255-r(X,Y))*%d+(255-g(X,Y))*%d+(255-b(X,Y))*%d)/%d,0,1)"%(v[0],v[1],v[2],vv)
        ch=lambda i:"255+(%d-255)*%s"%(A[i],t)
        vf=f"format=gbrp,geq=r='{ch(0)}':g='{ch(1)}':b='{ch(2)}',format=yuv420p"
        subprocess.run(["ffmpeg","-v","error","-y","-i",src,"-vf",vf,"-c:v","libx264","-crf","27","-preset","slow","-c:a","copy","-movflags","+faststart",f"{root}/BobV1/Start/Resources/jelbies_intro_{pid}.mp4"],check=True)
if __name__=="__main__": main()
