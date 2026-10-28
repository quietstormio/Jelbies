"""Polish pass: knitted scarf, layered tutu, trimmed cape (see items2_other for the originals; ids/anchors/colour keys unchanged)."""
from wl import *
from items_other import body_pt
from items2_head import torus, thick_sheet, eloop, hdir, uvsphere, ico_part
import items2_head as IH2
UP=np.array([0,1,0.])
NA=(0.0,0.47,0.5055)  # unused

def _sstep(a,b,x):
    t=max(0.0,min(1.0,(x-a)/(b-a))); return t*t*(3-2*t)

def thick_sheet2(name,fn,nu,nv,thick,gcol,sharp=60):
    """closed thin slab like thick_sheet but with a per-vertex colour gcol(i,j,side) (side 0 = outer, 1 = inner)."""
    P0=[];P1=[]
    for j in range(nv):
        for i in range(nu):
            p,n=fn(i,j); p=np.array(p,float); n=np.array(n,float); n/=np.linalg.norm(n)
            P0.append(p); P1.append(p-n*thick)
    bm=bmesh.new(); v0=[bm.verts.new(tuple(map(float,p))) for p in P0]; v1=[bm.verts.new(tuple(map(float,p))) for p in P1]
    for j in range(nv-1):
        for i in range(nu-1):
            a,b,c,d=j*nu+i,j*nu+i+1,(j+1)*nu+i+1,(j+1)*nu+i
            bm.faces.new([v0[a],v0[b],v0[c],v0[d]]); bm.faces.new([v1[d],v1[c],v1[b],v1[a]])
    for i in range(nu-1):
        for (j,flip) in ((0,False),(nv-1,True)):
            a,b=j*nu+i,j*nu+i+1
            bm.faces.new([v0[a],v0[b],v1[b],v1[a]] if not flip else [v1[a],v1[b],v0[b],v0[a]])
    for j in range(nv-1):
        for (i,flip) in ((0,True),(nu-1,False)):
            a,b=j*nu+i,(j+1)*nu+i
            bm.faces.new([v0[a],v0[b],v1[b],v1[a]] if not flip else [v1[a],v1[b],v0[b],v0[a]])
    key=lambda p:(round(p[0],3),round(p[1],3),round(p[2],3))
    CM={}
    for j in range(nv):
        for i in range(nu):
            CM[key(P0[j*nu+i])]=gcol(i,j,0); CM[key(P1[j*nu+i])]=gcol(i,j,1)
    def cf(p,n):
        c=CM.get(key(p))
        if c is None:   # nearest fallback
            kk=min(CM,key=lambda q:(q[0]-p[0])**2+(q[1]-p[1])**2+(q[2]-p[2])**2); c=CM[kk]
        return c
    return closed(bm,cf,name,sharp=sharp)

def strands_part(name,strands,r,colors,taper=0.7):
    """thin 3-sided prisms: strands = [(p0,p1)]; one part."""
    P=[];F=[]
    for k,(p0,p1) in enumerate(strands):
        p0=np.array(p0,float); p1=np.array(p1,float); d=p1-p0; d/=np.linalg.norm(d)
        u=np.cross(d,np.array([0,0,1.])); 
        if np.linalg.norm(u)<1e-3: u=np.cross(d,np.array([1,0,0.]))
        u/=np.linalg.norm(u); v=np.cross(d,u); o=len(P)
        for pp,rr in ((p0,r),(p1,r*taper)):
            for a in range(3):
                t=2*math.pi*a/3; P.append(pp+(u*math.cos(t)+v*math.sin(t))*rr)
        for a in range(3):
            b=(a+1)%3; F+=[(o+a,o+b,o+3+b),(o+a,o+3+b,o+3+a)]
        F+=[(o+3,o+5,o+4)]
    C=[]
    for k in range(len(strands)): C+=[colors[k%len(colors)]]*6
    part=add_part(name,P,F,C,hint=lambda p: np.array([0,0,0.0])+np.array([p[0],0,p[2]]),flip_auto=False)
    # orientation: make every strand's faces point outward from its own axis
    Pn=np.array(part['P']); Fn=[]
    for k in range(len(strands)):
        o=k*6; cen=Pn[o:o+6].mean(0)
        for (a,b,c) in [f for f in part['F'] if o<=f[0]<o+6]:
            n=np.cross(Pn[b]-Pn[a],Pn[c]-Pn[a]); fc=(Pn[a]+Pn[b]+Pn[c])/3
            ax=Pn[o+3:o+6].mean(0)-Pn[o:o+3].mean(0); out=(fc-cen)-ax*np.dot(fc-cen,ax)/np.dot(ax,ax)
            Fn.append((a,b,c) if np.dot(n,out)>=0 else (a,c,b))
    # the end cap (o+3,o+5,o+4) points along +d; fine either way (tiny)
    part['F']=Fn; part['N']=[tuple(n) for n in __import__('wl')._norm_from_faces(part['P'],Fn)]
    return part

# ======================= SCARF ====================================================
def scarf(a=CORAL,b=CREAM,**k):
    reset()
    K=12; NS=33; PH0=-62.0; PH1=298.0
    TN=0.052; VH=0.060
    def yfn(ph): return 0.466+0.046*math.cos(ph)**2+__import__('kit5').pip_rise(ph)
    def rr_k(kk): return 1.0 if kk%2==0 else 0.80
    def pt(i,j):
        ph=math.radians(PH0+(PH1-PH0)*j/(NS-1)); u=j/(NS-1)
        tap=1.0
        th=2*math.pi*i/K; r=rr_k(i)*tap
        base=B.egg_point(yfn(ph),ph); h=hdir(base)
        return base+h*(0.012+TN*tap+TN*r*math.cos(th))+np.array([0,VH*r*math.sin(th),0])
    def gc(i,j):
        u=j/(NS-1); crest=(i%2==0)
        st=False
        c=b if st else a
        c=tint(c,0.14) if crest else deep(c,0.20)
        return c
    grid_surface('wrap',pt,K,NS,None,closed_u=True,hint=lambda p:np.array([p[0],0,p[2]]),gcol=gc)
    # knot at the side-front (phi ~ 62 deg, x ~ +0.27)
    kph=math.radians(62); ky=yfn(kph); kb=B.egg_point(ky,kph); kh=hdir(kb)
    kc=kb+kh*0.084+np.array([0,0.002,0])
    tg=np.cross(UP,kh); tg/=np.linalg.norm(tg)
    R3=np.stack([tg,UP,kh],1)
    KR=(0.098,0.086,0.066); NK=12; NV=7
    def kpt(i,j):
        th=2*math.pi*i/NK; v=-math.pi/2+math.pi*j/(NV-1)
        rib=1+0.075*math.cos(6*th)
        # axes: x along the tangent (wide), y up, z outward
        q=np.array([KR[0]*math.cos(v)*math.cos(th)*rib,KR[1]*math.sin(v),KR[2]*math.cos(v)*math.sin(th)*rib])
        return kc+R3@q
    def kcg(i,j):
        th=2*math.pi*i/NK; rib=math.cos(6*th)
        c=mix(deep(a,0.18),tint(a,0.22),0.5+0.5*rib)
        return c
    grid_surface('knot',kpt,NK,NV,None,closed_u=True,hint=lambda p:p-kc,gcol=kcg)
    kx=float(kc[0])
    def tail(cx0,cx1,y0,y1,w0,name,off,nvv):
        NU=5; vs=[j/(nvv-1) for j in range(nvv)]
        def fn(i,j):
            v=vs[j]; u=i/(NU-1)-0.5
            cx=cx0+(cx1-cx0)*v+0.010*math.sin(3.0*v); y=y0+(y1-y0)*v
            w=w0*(1+0.26*v)
            p,n=body_pt(cx+u*w,y,off+0.020*v+(0.007 if i%2==1 else 0.0)); return p,n
        def gc(i,j,side):
            v=vs[j]; crest=(i%2==1)
            c=b if ((0.50<v<0.62) or (0.74<v<0.86)) else a
            if side==1: return deep(c,0.22)
            return tint(c,0.14) if crest else deep(c,0.16)
        thick_sheet2(name,fn,NU,nvv,0.016,gc)
        # fringe along the hem
        strands=[];cols=[]
        vend=vs[-1]; nf=7
        for q in range(nf):
            u=q/(nf-1)-0.5; cx=cx0+(cx1-cx0)*vend+0.010*math.sin(3.0*vend); w=w0*(1+0.26*vend)
            p,n=body_pt(cx+u*w*0.92,y1,off+0.020*vend-0.002)
            sw=0.006*math.sin(q*1.7)
            strands.append((p+np.array([0,0.006,0]),p+np.array([sw,-0.056,0.010]))); cols.append(deep(a,0.06) if q%2==0 else tint(b,0.0))
        strands_part(name+'_fringe',strands,0.0085,cols)
    tail(kx-0.010,kx+0.030,0.440,0.222,0.082,'tail_a',0.050,7)
    tail(kx-0.085,kx-0.098,0.440,0.290,0.076,'tail_b',0.054,6)
    return dict(anchor='neck',slot='neck',tags=['sweet','cute','cool'],price=35,title='Cosy scarf',
      desc='Soft knitted wrap: a ribbed (lengthwise ribs, geometry + vertex colour) ring around the belly at y~0.47..0.50 that curves round the sides and ends behind the arms, a chunky ribbed knot at the side-front (x~+0.27), and two ribbed tails (slight flare) with a fringe hanging to y~0.22 / 0.29. Top of the wrap at the centre is y<=0.54, below the mouth keep-out.')

# ======================= TUTU =====================================================
WAIST_ANCHOR=(0.0,0.28,0.0)
def tutu(pink=PINK,lav=LAV,band=None,**k):
    reset(); yb=0.255; NS=40; NSC=8
    band=band or deep(pink,0.22)
    loop=[(0.014,0.026),(0.036,0.026),(0.036,-0.024),(0.014,-0.024)]
    torus('waistband',28,lambda phi:[eloop(yb,phi,h,v) for h,v in loop],lambda p,n: mix(band,tint(band,0.2),0.5+0.5*n[1]*0.6))
    prof=lambda h: 0.285-0.22*h-0.25*h*h
    # (name, colour, hem radius, vertical shift, attach h)
    LAY=[('layer2',mix(tint(pink,0.40),CREAM,0.10),0.150,0.0),('layer1',mix(CREAM,tint(pink,0.5),0.32),0.250,-0.050),('layer0',tint(lav,0.22),0.350,-0.100)]
    for li,(nm,c,hh,dy) in enumerate(LAY):
        ph0=0.6*li
        def pt(i,j,hh=hh,dy=dy,ph0=ph0):
            phi=2*math.pi*i/NS
            sc=math.sin(math.pi*(i%5)/5)
            t=j/2.0
            h=0.030+(hh-0.030)*t**0.9
            y=prof(h)+dy*(0.5+0.5*math.sqrt(t))
            if j==2: y+=0.038*(1-sc)
            if j==1: y+=0.010*(1-sc)
            return eloop(y,phi,h,0.0)
        def gc(i,j,c=c,li=li):
            t=j/2.0; sc=math.sin(math.pi*(i%5)/5)
            cc=mix(deep(c,0.22),tint(c,0.20),t)
            if j==2: cc=mix(cc,tint(c,0.45),0.5)
            return cc
        grid_surface(nm+'_top',pt,NS,3,None,closed_u=True,hint=lambda p:np.array([p[0],0.6,p[2]]),gcol=gc)
        # underside: same shape pushed 0.006 down, reversed
        def pt2(i,j,pt=pt): return pt(i,j)-np.array([0,0.007,0])
        part=grid_surface(nm+'_under',pt2,NS,3,None,closed_u=True,hint=lambda p:-np.array([p[0],0.6,p[2]]),gcol=lambda i,j,c=c: deep(tint(c,0.05),0.10+0.04*(j/2.0)))
    return dict(anchor='waist',slot='body',tags=['cute','sweet','sparkly'],price=60,title='Ballet tutu',
      desc='Three clearly separate tulle layers (top pink short, middle cream-pink, bottom lavender longest; hems y~0.22 / 0.17 / 0.08 at radius +0.15 / 0.25 / 0.35, about 0.05-0.09 vertical gap between hems) with 8 scalloped arcs each, on a waistband at y 0.23..0.28. Full ring, clear of the arm bulbs (arm bottom y~0.31) and feet. All vertices y<=0.29.')

# ======================= CAPE =====================================================
BACK_ANCHOR=tuple(float(v) for v in B.egg_point(0.55,3*math.pi/2))
RED=mix(CORAL,hx('#E03C46'),0.55)
def cape(main=RED,lining=HONEY,trim=CREAM,**k):
    reset(); nu=13; nv=8
    y_top=0.68; y_bot=0.16
    def fn(i,j):
        u=i/(nu-1); v=j/(nv-1)
        phi=math.radians(200+140*u)
        y=y_top+(y_bot-y_top)*v-0.025*v**3*math.cos(math.pi*(u*4))
        off=0.034+0.215*v**1.5
        base=B.egg_point(y,phi); h=hdir(base); p=base+h*off
        n=h+np.array([0,0.15*v,0]); return p,n
    def col(p,nn):
        r=np.array([p[0],0,p[2]]); outer=float(np.dot(np.array([nn[0],nn[1],nn[2]]),r))>0
        c=main if outer else lining
        if p[1]<0.215: c=trim if outer else tint(lining,0.2)
        return c
    thick_sheet('panel',fn,nu,nv,0.016,col)
    pts=[]
    for i in range(18):
        phi=math.radians(200+140*i/17); base=B.egg_point(y_top+0.004,phi); pts.append(base+hdir(base)*0.044)
    tube_curve('collar',pts,0.030,5,lambda p,nn: mix(deep(trim,0.10),tint(trim,0.1),0.5+0.5*nn[1]),cap=True,flat=0.9)
    for ph in (340,200):
        base=B.egg_point(y_top+0.004,math.radians(ph)); c=base+hdir(base)*0.060
        ico_part(f'clasp{ph}',tuple(c),(0.038,0.038,0.030),lambda p,nn: mix(deep(HONEY,0.12),tint(HONEY,0.2),0.5+0.5*nn[1]),sub=1)
    sp=star_poly(0.115,0.050,5,rad=0.012)
    yst=0.43; vst=(y_top-yst)/(y_top-y_bot); zst=-(float(B.halfDepth((yst-B.lift)/B.bodyH))+0.034+0.215*vst**1.5+0.014)
    slab_part('emblem',sp,0.012,HONEY,lambda px,py,pz:(px,yst+py,zst-pz),cuts=0)
    return dict(anchor='back',slot='body',tags=['cool','sparkly','cute'],price=70,title='Hero cape',
      desc='Coral cape (honey lining, cream trim) hanging from a collar across the shoulders at y 0.68, behind the arms (back arc 200..340 deg, z<0 beyond the arm roots), flaring to y~0.16 and +0.25 behind the egg. Two gold clasps sit on the sides above the arm tops. Nothing on the front (z>0.15). Trimmed to <=1.2k tris.')
