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

# Peek v2: a wide round head dome rising from the bottom edge (1024 space). Mirrored by ThemeIconView in ThemeColor.swift.
CX, CY, RX, RY = 512, 891, 643, 459          # dome ellipse: ~88% of the width, top at y=410 (40%)
EYE_Y, EYE_DX, EYE_RX, EYE_RY = 788, 165, 40, 52   # eyes ~23% above the bottom
BROW_Y, BROW_IN, BROW_OUT, BROW_W = 690, 105, 225, 30
OUTLINE_W = 44

def render_icon(c, S=4):
    import math
    N=1024*S; im=Image.new("RGB",(N,N),c["bg"]); d=ImageDraw.Draw(im)
    P=lambda x,y:(x*S,y*S)
    def ell(cx,cy,rx,ry,col): d.ellipse([(cx-rx)*S,(cy-ry)*S,(cx+rx)*S,(cy+ry)*S],fill=col)
    # outline = a larger dome in the line colour, then the white dome on top
    ell(CX,CY,RX+OUTLINE_W/2,RY+OUTLINE_W/2,c["line"]); ell(CX,CY,RX-OUTLINE_W/2,RY-OUTLINE_W/2,c["body"])
    # shine: an arc just inside the upper-left of the dome, with a dot beyond it
    a,b=RX-OUTLINE_W/2-55,RY-OUTLINE_W/2-55
    arc=[P(CX+a*math.cos(math.radians(t)),CY+b*math.sin(math.radians(t))) for t in [228+i*0.85 for i in range(41)]]
    d.line(arc,fill=c["shine"],width=40*S)
    for q in (arc[0],arc[-1]): r=20*S; d.ellipse([q[0]-r,q[1]-r,q[0]+r,q[1]+r],fill=c["shine"])
    q=P(CX+a*math.cos(math.radians(220)),CY+b*math.sin(math.radians(220))); r=18*S; d.ellipse([q[0]-r,q[1]-r,q[0]+r,q[1]+r],fill=c["shine"])
    for sx in (-1,1):
        x1,x2=sorted((CX+sx*BROW_IN,CX+sx*BROW_OUT)); a_,b_=P(x1,BROW_Y),P(x2,BROW_Y)
        d.line([a_,b_],fill=c["ink"],width=BROW_W*S); r=BROW_W/2*S
        for q in (a_,b_): d.ellipse([q[0]-r,q[1]-r,q[0]+r,q[1]+r],fill=c["ink"])
        ell(CX+sx*EYE_DX,EYE_Y,EYE_RX,EYE_RY,c["ink"]); ell(CX+sx*EYE_DX-sx*11,EYE_Y-20,11,13,c["hi"])
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
