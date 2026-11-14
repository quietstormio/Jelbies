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
def scarf_y(phi, front=0.5025, side=0.700, back=0.650):
    """Centre-line height of the scarf band at azimuth phi (pi/2 = front): low on the chest (top edge 0.545 under the mouth keep-out), rising over the arm roots (arm top
    ~0.66, so the band's lower edge clears it) between 0.44 and 1.48 rad off the front (the same window WearRules.neckLift used), then staying HIGH round the back where the
    egg narrows (0.65: it wraps the back of the head, not the belly)."""
    az = abs((phi - math.pi / 2 + math.pi) % (2 * math.pi) - math.pi)                    # 0 at the front, pi at the back
    return front + (side - front) * _sstep(0.44, 1.48, az) + (back - side) * _sstep(1.48, math.pi, az)

def scarf(a=CORAL,b=CREAM,**k):
    """A knitted scarf wrapped round the neck just under the mouth: a flat ribbed band (0.085 tall, ~0.03 thick, ~1 cm off the skin) in two wraps (a groove between them),
    a small knot slightly right of centre and two tails of different length lying on the chest with a connected fringe (part of the tail mesh, so it swings with the tail).
    Shared by scarf_cosy / scarf_sky / scarf_plum. Everything is on the all-round surface sampler (wl.surface_at)."""
    reset()
    NA_=64; HH=0.0425; R_=0.52
    # (across-band position w, stand-off from the skin): two rounded wraps with a groove between them
    ROWS=[(-1.0,0.010),(-0.80,0.030),(-0.50,0.038),(0.0,0.026),(0.50,0.038),(0.80,0.030),(1.0,0.010)]
    def skin(phi,w,off):
        d=1e-3; y0=scarf_y(phi); dy=(scarf_y(phi+d)-scarf_y(phi-d))/(2*d)
        t=np.array([R_,dy]); t/=np.linalg.norm(t); perp=np.array([-t[1],t[0]])
        return surface_at(y0+perp[1]*w*HH, phi+perp[0]*w*HH/R_, off=off)
    cols=[2*math.pi*i/NA_ for i in range(NA_)]
    def pt(i,j):
        w,off=ROWS[j]; return skin(cols[i],w,off)[0]
    def gc(i,j):
        w=ROWS[j][0]; stripe=(i%16)<2
        base=mix(a,b,0.55) if stripe and abs(w)<0.9 else a
        if abs(w)>=0.95: return deep(base,0.24)
        if abs(w)<0.2: return deep(base,0.30)
        return tint(base,0.12) if abs(abs(w)-0.5)<0.15 else deep(base,0.08)
    grid_surface('wrap',pt,NA_,len(ROWS),None,closed_u=True,hint=lambda p:full_n(p),gcol=gc)
    # knot: slightly right of the chest centre, on the band
    kph=math.pi/2-0.30; kc,kn=skin(kph,0.0,0.040)
    kc=kc+kn*0.012
    tg=np.cross(UP,kn); tg/=np.linalg.norm(tg); up2=np.cross(kn,tg)
    R3=np.stack([tg,up2,kn],1)
    KR=(0.058,0.048,0.040); NK=10; NV=6
    def kpt(i,j):
        th=2*math.pi*i/NK; v=-math.pi/2+math.pi*j/(NV-1)
        rib=1+0.07*math.cos(5*th)
        q=np.array([KR[0]*math.cos(v)*math.cos(th)*rib,KR[1]*math.sin(v),KR[2]*math.cos(v)*math.sin(th)*rib])
        return kc+R3@q
    def kcg(i,j):
        th=2*math.pi*i/NK; rib=math.cos(5*th)
        return mix(deep(a,0.18),tint(a,0.22),0.5+0.5*rib)
    grid_surface('knot',kpt,NK,NV,None,closed_u=True,hint=lambda p:p-kc,gcol=kcg)
    kx=float(kc[0]); ky=float(kc[1])
    def tail(cx0,cx1,y0,y1,w0,name,off,nvv=7,NU=7):
        """nvv-1 rows down to the hem, then one row of fringe teeth (even columns long, odd short) that belongs to the SAME mesh (connected, one part)."""
        rows=nvv-1; vs=[j/(rows-1) for j in range(rows)]
        def fn(i,j):
            u=i/(NU-1)-0.5
            if j<rows: v=vs[j]; yy=y0+(y1-y0)*v
            else:
                v=1.0; yy=y1-(0.050 if i%2==0 else 0.014)
            cx=cx0+(cx1-cx0)*v+0.010*math.sin(3.0*v); w=w0*(1+0.22*v)
            return body_pt(cx+u*w,yy,off+0.018*v+(0.006 if (i%2==1 and j<rows) else 0.0))
        def g(i,j,side):
            v=vs[min(j,rows-1)]; crest=(i%2==1)
            c=b if ((0.52<v<0.62) or (0.74<v<0.84)) else a
            if j>=rows: c=deep(a,0.06) if i%2==0 else deep(b,0.05)
            if side==1: return deep(c,0.22)
            return tint(c,0.14) if crest and j<rows else deep(c,0.14)
        thick_sheet2(name,fn,NU,nvv,0.014,g)
    tail(kx-0.004,kx+0.030,ky-0.030,0.240,0.068,'tail_a',0.046)
    tail(kx-0.062,kx-0.074,ky-0.030,0.300,0.062,'tail_b',0.052)
    return dict(anchor='neck',slot='neck',tags=['sweet','cute','cool'],price=35,title='Cosy scarf',
      desc='A knitted scarf wrapped round the neck: a flat ribbed band 0.085 tall in two wraps, ~1 cm off the skin all the way round, low on the chest (top edge 0.545, under the mouth keep-out), rising over the arm roots at the sides (centre 0.70) and staying high round the back (0.65), with a small knot just right of centre and two ribbed tails (hems y~0.24 / 0.30) with a connected fringe, lying on the chest.')

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
