from wl import *
TOP=B.top; HEAD_ANCHOR=(0.0,TOP,0.0)
def egg_hint(p): return egg_n(p)

def shell(name,segs,y0fn,rows,colorfn,top_pole_off=None):
    """Conforming shell on the egg. rows: ('a',dy_above_hem,off[,rib]) absolute, or ('k',frac,off) fraction from the last absolute row up to the crown.
    off may be a fn(phi)->float. 'pole' = crown point."""
    # precompute last absolute dy
    cache={}
    def pt(i,j):
        phi=2*math.pi*i/segs; r=rows[j]; kind=r[0]; off=r[2]
        if callable(off): off=off(phi)
        if kind=='pole': 
            return np.array([0,TOP+off,0.0])
        y0=y0fn(phi)
        if kind=='a': y=y0+r[1]
        else:
            ya=y0+[x for x in rows if x[0]=='a'][-1][1]; y=ya+(TOP-0.004-ya)*r[1]
        extra_dy=r[3] if len(r)>3 else 0.0
        p=B.egg_point(y,phi); n=egg_n(p); return p+n*off+np.array([0,extra_dy,0])
    return grid_surface(name,lambda i,j:pt(i,j),segs,len(rows),colorfn,hint=egg_hint)

def ribbed(base,amp,n):
    return lambda phi: base+amp*math.cos(n*phi)

# ============================ BEANIE ====================================
def beanie(main=PINK,cuff=CREAM,pom=CREAM,stripe=None,**k):
    reset(); segs=28
    y0=lambda phi: 1.015+0.04*math.sin(phi)
    rows=[('a',0.010,0.006),('a',-0.002,0.022),('a',0.012,0.044),('a',0.046,ribbed(0.054,0.004,14)),('a',0.086,ribbed(0.050,0.004,14)),('a',0.096,0.038)]
    for f,o in ((0.0,0.036),(0.18,0.036),(0.38,0.034),(0.56,0.032),(0.74,0.030),(0.88,0.028),(0.965,0.026)): rows.append(('k',f,o))
    rows.append(('pole',0,0.024))
    def col(p,n):
        dy=p[1]-(y0(math.atan2(p[2],p[0]))); 
        if dy<0.1: 
            c=cuff; rib=0.5+0.5*math.cos(14*math.atan2(p[2],p[0])); return mix(c,deep(c,0.12),0.35*(1-rib))
        c=main
        if stripe is not None:
            band=(TOP-p[1]); 
            if 0.17<band<0.255: c=stripe
        return c
    shell('beanie',segs,y0,rows,col)
    ico_part('pom',(0,TOP+0.062,-0.012),(0.092,0.088,0.092),lambda p,n: mix(pom,deep(pom,0.1),0.35*max(0,0.5-0.5*n[1])),sub=2,fuzz=0.05,seed=3)
    return dict(anchor='head_top',slot='head',tags=['cute','sweet'],price=40,title='Pom-pom beanie',
      desc='Knit beanie with a ribbed cuff and a fluffy pom-pom. Sits above the brows.')

# ============================ BASEBALL CAP ===============================
def cap(crown=PINK,brim=CREAM,emblem=SKY,band=SKY,**k):
    reset(); segs=36
    y0=lambda phi: 1.0+0.075*math.sin(phi)
    def seam(base):
        def f(phi):
            d=(phi*180/math.pi)%60; return base-(0.006 if (d<0.6 or d>59.4) else 0)
        return f
    rows=[('a',0.012,0.004),('a',-0.002,0.02),('a',0.016,0.034),('a',0.05,0.037)]
    for f,o in ((0.0,0.040),(0.25,0.042),(0.5,0.041),(0.72,0.039),(0.9,0.036)): rows.append(('k',f,seam(o),0.045*math.sin(math.pi*min(1,f*1.0))**0.7))
    rows.append(('pole',0,0.032))
    def col(p,n):
        phi=math.atan2(p[2],p[0]); dy=p[1]-y0(phi)
        return band if dy<0.03 else crown
    shell('crown',segs,y0,rows,col)
    ico_part('button',(0,TOP+0.034,0),(0.036,0.028,0.036),brim,sub=2)
    # visor: a soft pillow (squashed ellipse outline, rounded rim), bent down at the sides, attached at the front of the hem
    yb=1.092; droop=0.16; A=0.31; D=0.19; d0=0.085
    prof=[(0.0,0.016),(0.45,0.018),(0.85,0.016),(1.0,0.009),(1.0,-0.009),(0.85,-0.016),(0.45,-0.018),(0.0,-0.016)]
    ac=float(B.halfWidth((yb-B.lift)/B.bodyH)); cc=float(B.halfDepth((yb-B.lift)/B.bodyH))
    def vp(i,j):
        s,h=prof[j]; t=2*math.pi*i/18
        x=A*s*math.cos(t); dd=d0+D*s*math.sin(t)
        zf=cc*math.sqrt(max(0,1-min(1,(x/ac))**2))+0.026
        return np.array([x, yb+h-math.sin(droop)*dd-0.40*x*x, zf+math.cos(droop)*dd])
    grid_surface('visor',vp,18,len(prof),lambda p,n: tint(brim,0.0) if n[1]>-0.6 else deep(brim,0.12),hint=lambda p:np.array([0,1,0.0])*0+ (p-np.array([0,yb-0.02,0.5])))
    sp=star_poly(0.062,0.027,5,rad=0.009)
    def xfs(px,py,pz):
        y=1.19+py; x=px
        z=B.halfDepth((y-B.lift)/B.bodyH)*math.sqrt(max(0,1-(x/B.halfWidth((y-B.lift)/B.bodyH))**2))
        return (x,y,z+0.066+pz-0.012)
    slab_part('emblem',sp,0.014,emblem,xfs,cuts=0)
    return dict(anchor='head_top',slot='head',tags=['sporty','cool'],price=30,title='Circuit team cap',
      desc='Baseball cap with a rounded visor and star badge; the Jelly Circuit team cap (crown = team colour).')

# ============================ FLOWER CROWN =================================
def flower_crown(vine=MINT,cols=None,**k):
    reset(); segs=22
    cols=cols or [PINK,HONEY,CREAM,LAV,PINK,HONEY,CORAL]
    ycen=lambda phi: 1.085+0.035*math.sin(phi)
    pts=[]
    for i in range(segs+1):
        phi=2*math.pi*i/segs; p=B.egg_point(ycen(phi),phi); pts.append(p+egg_n(p)*0.034)
    tube_curve('vine',pts,0.021,5,lambda p,n: mix(deep(vine,0.2),vine,0.5+0.5*n[1]),cap=False,flat=0.8)
    angs=[90,128,52,168,12,-38,205]
    for fi,(ad,c) in enumerate(zip(angs,cols)):
        phi=math.radians(ad); p=B.egg_point(ycen(phi),phi); n=egg_n(p); ctr=p+n*0.062
        z=n/np.linalg.norm(n); up=np.array([0,1,0.]); xax=np.cross(up,z); xax/=np.linalg.norm(xax); yax=np.cross(z,xax)
        r=0.082 if fi==0 else (0.074 if fi%2==0 else 0.066)
        for pi_ in range(5):
            a=2*math.pi*pi_/5+fi
            cen=ctr+(xax*math.cos(a)+yax*math.sin(a))*r*0.78
            Rm=np.stack([xax*math.cos(a)+yax*math.sin(a),-xax*math.sin(a)+yax*math.cos(a),z],1)
            ico_part(f'petal{fi}_{pi_}',cen,(r*0.64,r*0.42,r*0.24),lambda p_,n_,c=c: mix(deep(c,0.08),tint(c,0.15),0.5+0.5*n_[1]*0.4),sub=1,rot=Rm.tolist())
        ico_part(f'heart{fi}',ctr+z*0.016,(r*0.36,r*0.36,r*0.26),HONEY if c!=HONEY else CORAL,sub=1)
    for ad in (110,150,30,-30,190):
        phi=math.radians(ad); p=B.egg_point(ycen(phi),phi); n=egg_n(p); ctr=p+n*0.046
        z=n; up=np.array([0,1,0.]); xax=np.cross(up,z); xax/=np.linalg.norm(xax); yax=np.cross(z,xax)
        Rm=np.stack([xax,yax,z],1)
        ico_part(f'leaf{ad}',ctr+xax*0.05+yax*0.012,(0.06,0.026,0.014),lambda p_,n_: mix(deep(vine,0.25),vine,0.6),sub=1,rot=Rm.tolist())
    return dict(anchor='head_top',slot='head',tags=['sweet','cute','sparkly'],price=55,title='Flower crown',
      desc='A vine of seven pastel blossoms circling the head. Contest favourite.')

# ============================ HEADBANDS (cat / frog) =========================
def headband_curve(zoff=-0.03,y_start=0.985,off=0.026):
    L=[];R=[]
    for side in (-1,1):
        for y in np.linspace(y_start,TOP-0.002,11):
            c=float(B.halfDepth((y-B.lift)/B.bodyH)); s=max(-1,min(1,zoff/c)); ph=math.asin(s)
            phi=ph if side==1 else math.pi-ph
            p=B.egg_point(y,phi); (R if side==1 else L).append(p+egg_n(p)*off)
    return L+R[::-1][::-1][::-1] if False else L+R[::-1][::-1]
def _band(pts,col,rad=0.026):
    # L runs low->high on the left, R runs low->high on the right: order = L (low->high), then R reversed (high->low)
    L=pts[:11]; R=pts[11:]
    path=L+R[::-1]
    tube_curve('band',path,rad,6,col,cap=True,flat=0.8)
    return path
def cat_ears(band=PINK,ear=PINK,inner=CREAM,**k):
    reset(); pts=headband_curve(); path=_band(pts,band)
    for s in (-1,1):
        j=min(range(len(path)),key=lambda q: abs(path[q][0]-s*0.28)+(0 if path[q][1]>1.2 else 5)); bp=path[j]
        lean=np.array([s*0.34,1,0.22]); lean=lean/np.linalg.norm(lean)
        z=lean; up=np.array([0,0,1.]); x=np.cross(up,z); x/=np.linalg.norm(x); y=np.cross(z,x)
        Rm=np.stack([x,z,y],1)
        prof=[(0.0,-0.03),(0.125,-0.02),(0.14,0.0),(0.115,0.07),(0.07,0.16),(0.025,0.25),(0.0,0.275)]
        lathe_y('ear%+d'%s,prof,18,lambda p,nn: ear,centre=tuple(bp-lean*0.012),scale=(1.0,0.6),rotm=Rm.tolist(),sharp=80)
        prof2=[(0.0,0.0),(0.088,0.004),(0.066,0.08),(0.026,0.16),(0.0,0.185)]
        lathe_y('inner%+d'%s,prof2,14,inner,centre=tuple(bp-lean*0.012+(lean*0.0)+np.array([0,0,0.0])+np.cross(lean,x)*0.0+np.array([0,0,0.0])),scale=(1.0,0.5),rotm=Rm.tolist(),sharp=80)
        # nudge inner forward (toward +z-ish axis of the lathe's y)
        PARTS[-1]['P']=[tuple(np.array(q)+np.array([0,0,0.026])) for q in PARTS[-1]['P']]
    return dict(anchor='head_top',slot='head',tags=['cute','cool'],price=45,title='Cat-ear headband',
      desc='Soft headband with two rounded cat ears.')
def frog_ears(band=MINT,ear=MINT,inner=CREAM,**k):
    reset(); pts=headband_curve(); path=_band(pts,band)
    for s in (-1,1):
        j=min(range(len(path)),key=lambda q: abs(path[q][0]-s*0.27)+(0 if path[q][1]>1.22 else 5)); bp=path[j]
        c=bp+np.array([s*0.04,0.085,0.0])
        ico_part('bulb%+d'%s,tuple(c),(0.115,0.108,0.108),lambda p,nn: mix(deep(ear,0.12),tint(ear,0.2),0.5+0.5*nn[1]),sub=2)
        fc=c+np.array([0,0.004,0.088]); ico_part('eyewhite%+d'%s,tuple(fc),(0.07,0.072,0.032),CREAM,sub=2)
        ico_part('pupil%+d'%s,tuple(fc+np.array([0,0,0.02])),(0.038,0.042,0.02),INK,sub=2)
        ico_part('glint%+d'%s,tuple(fc+np.array([0.012,0.014,0.036])),(0.011,0.011,0.008),WHITE,sub=1)
    return dict(anchor='head_top',slot='head',tags=['cute','sweet'],price=45,title='Frog-ear headband',
      desc='Headband with two round froggy bulbs and sleepy frog eyes.')

# ============================ PARTY CONE ====================================
def party(main=LAV,stripe=PINK,dots=HONEY,**k):
    reset(); segs=32; yb=1.225
    apex=np.array([0.0,yb+0.50,-0.035])
    rim=[]
    for i in range(segs):
        phi=2*math.pi*i/segs; p=B.egg_point(yb,phi); rim.append(p+egg_n(p)*0.016)
    cuts=[0.0,0.17,0.1701,0.38,0.3801,0.59,0.5901,0.80,0.8001,0.93,1.0]
    def pt(i,j):
        t=cuts[j]
        if j==0: return rim[i]+np.array([0,-0.014,0])+(rim[i]-np.array([0,rim[i][1],0]))*0.05
        return rim[i]*(1-t)+apex*t
    def colfn(p,n):
        h=(p[1]-yb)/0.50
        if h<-0.001: return HONEY
        band=int(sum(1 for b in (0.17,0.38,0.59,0.80) if h>b+0.00005))
        return stripe if band%2==0 else main
    grid_surface('cone',pt,segs,len(cuts),colfn,hint=lambda p:(p-np.array([0,yb+0.2,0])))
    # confetti dots (little spheres) and a pom
    for k_,(ang,h) in enumerate(((30,0.28),(130,0.30),(215,0.5),(300,0.24),(80,0.66),(250,0.7),(345,0.55))):
        t=h; a=math.radians(ang); p=B.egg_point(yb,a); p=p+egg_n(p)*0.016; q=p*(1-t)+apex*t
        d=np.array([math.cos(a),0.25,math.sin(a)]); d/=np.linalg.norm(d)
        ico_part(f'dot{k_}',tuple(q+d*0.01),(0.017,0.017,0.017),[HONEY,CREAM,MINT,SKY][k_%4],sub=1)
    ico_part('pom',tuple(apex+np.array([0,0.016,0])),(0.058,0.058,0.058),HONEY,sub=2,fuzz=0.07,seed=5)
    return dict(anchor='head_top',slot='head',tags=['cute','sparkly','sweet'],price=35,title='Party cone hat',
      desc='Striped party hat with confetti dots and a fluffy gold pom on the tip.')

# ============================ TOP HAT ======================================
def tophat(main=INK,band=PINK,star=HONEY,**k):
    reset(); yb=1.315
    a=0.245; c=0.215
    # brim: flat rounded disc (lathe) ; tube: slightly tapered cylinder ; band
    brim=[(0.0,0.0),(0.34,0.0),(0.355,0.008),(0.36,0.02),(0.352,0.03),(0.336,0.034),(0.0,0.034)]
    lathe_y('brim',brim,36,lambda p,nn: mix(main,tint(main,0.12),0.5),scale=(1.0,0.9),centre=(0,yb,0),sharp=50)
    tube=[(0.0,0.03),(0.255,0.03),(0.262,0.05),(0.255,0.22),(0.265,0.236),(0.245,0.252),(0.0,0.255)]
    lathe_y('crown',tube,36,lambda p,nn: mix(main,tint(main,0.16),max(0,nn[1])*0.5),scale=(1.0,0.88),centre=(0,yb,0),sharp=50)
    ribbon=[(0.0,0.06),(0.2655,0.06),(0.2680,0.07),(0.2680,0.118),(0.2655,0.126),(0.0,0.126)]
    lathe_y('ribbon',[(r,y) for r,y in [(0.262,0.058),(0.272,0.064),(0.272,0.118),(0.262,0.124)]],36,band,scale=(1.0,0.88),centre=(0,yb,0),sharp=50)
    sp=star_poly(0.04,0.018,5,rad=0.006)
    slab_part('star',sp,0.014,star,lambda px,py,pz:(px*1.0,yb+0.092+py,0.88*0.274+pz-0.002),cuts=0)
    # tilt jauntily: roll about z (tilt toward +x), nod back slightly; pivot at the crown
    th=math.radians(11); R=np.array(rot_z(-th))@np.array(rot_x(math.radians(-6)))
    post_transform(R,pivot=(0,TOP,0))
    sh=autofit(0.004,0.003,(0,1,0))
    return dict(anchor='head_top',slot='head',tags=['cool','cute','sparkly'],price=70,title='Tiny top hat',
      desc='A tiny ink-black top hat with a pink ribbon, perched at a jaunty tilt. Rigid; carried with the head squash.',fit_shift=round(sh,4))

H=(0.0,B.top,0.0)
REG=[
 ('beanie_pink',beanie,dict(main=PINK,cuff=CREAM,pom=CREAM),H),
 ('beanie_honey',beanie,dict(main=HONEY,cuff=MINT,pom=CREAM,stripe=CREAM),H),
 ('cap_team_pink',cap,dict(crown=PINK,brim=CREAM,emblem=SKY,band=SKY),H),
 ('cap_team_sky',cap,dict(crown=SKY,brim=CREAM,emblem=PINK,band=PINK),H),
 ('flower_crown',flower_crown,dict(),H),
 ('tophat',tophat,dict(),H),
 ('cat_ears',cat_ears,dict(),H),
 ('frog_ears',frog_ears,dict(),H),
 ('party_hat',party,dict(),H),
]
