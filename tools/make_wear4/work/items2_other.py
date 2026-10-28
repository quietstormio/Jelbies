from wl import *
import items_other as IO
from items_other import axes, body_pt, FACE_ANCHOR, NECK_ANCHOR, BIB_ANCHOR, GLOVE_FRAME, B_, _eye_frames, _bridge_and_temples
from items2_head import torus, thick_sheet, eloop, hdir, uvsphere, gem, basis_to, phi_of
UP=np.array([0,1,0.])
RED=mix(CORAL,hx('#E03C46'),0.55)

# ======================= FACE ===================================================
def heart_poly(R,n=26):
    pts=[]
    for k in range(n):
        t=2*math.pi*k/n; pts.append((16*math.sin(t)**3,13*math.cos(t)-5*math.cos(2*t)-2*math.cos(3*t)-math.cos(4*t)))
    ys=[p[1] for p in pts]; cy=(max(ys)+min(ys))/2; s=R/16
    return [(x*s,(y-cy)*s) for x,y in pts][::-1]
def heart_shades(frame=CORAL,lens=hx('#8E2F5E'),**k):
    reset(); stand=0.052
    fr=_eye_frames(stand)
    for s,c,x,y,n in fr:
        def mk(Rr,t0,t1,colr,nm):
            sp=heart_poly(Rr)
            slab_part(nm,sp,t1-t0,colr,lambda px,py,pz: tuple(c+x*px+y*py+n*(pz+t0)),cuts=0,sharp=35)
        mk(0.112,-0.014,0.012,frame,'frame%+d'%s)
        mk(0.087,0.006,0.020,lambda p,nn: mix(lens,hx('#E98AA4'),0.30*max(0,nn[1])),'lens%+d'%s)
    for s,c,x,y,n in fr:
        ico_part('glint%+d'%s,tuple(c+x*(-0.035)+y*0.035+n*0.022),(0.016,0.008,0.004),CREAM,sub=1,rot=np.stack([x,y,n],1).tolist())
    _bridge_and_temples(fr,0.0115,frame,stand,0.094,y_br=0.855)
    return dict(anchor='face',slot='face',tags=['sweet','sparkly','cute'],price=55,title='Heart sunglasses',
      desc='Coral heart-shaped sunglasses with berry lenses. Opaque lenses cover the eye beads by design (like the star shades): hide while asleep / eating. Bridge and temples are above y=0.78; lens bottoms y>=0.70 at |x|=0.215.')

def goggles(rim=HONEY,strap=CORAL,glass=hx('#7CC4D6'),**k):
    reset(); segs=28
    yl=1.075
    y0=lambda phi: 1.062+0.014*math.sin(phi)
    loop=[(0.020,-0.020),(0.040,-0.020),(0.040,0.020),(0.020,0.020)]
    torus('strap',segs,lambda phi:[eloop(y0(phi),phi,h,v) for h,v in loop],lambda p,n: mix(deep(strap,0.10),tint(strap,0.12),0.5+0.5*n[1]*0.5))
    R=0.076
    for s in (-1,1):
        c=B.front_surface(s*0.150,yl); n=full_n(c); x,y,z=axes(n); ctr=c+z*0.040
        pts=[ctr+(x*math.cos(a)+y*math.sin(a))*R for a in np.linspace(0,2*math.pi,21)]
        tube_curve('rim%+d'%s,pts,0.0165,5,lambda p,nn: mix(deep(rim,0.14),tint(rim,0.12),0.5+0.5*nn[2]*0.5),cap=False)
        ico_part('glass%+d'%s,tuple(ctr-z*0.004),(R*0.94,R*0.94,0.020),lambda p,nn: mix(glass,tint(glass,0.55),max(0,0.5+0.5*nn[1])*0.4+max(0,nn[2])*0.3),sub=2,rot=np.stack([x,y,z],1).tolist())
        ico_part('glint%+d'%s,tuple(ctr+x*(-0.03)+y*0.03+z*0.014),(0.016,0.009,0.004),CREAM,sub=1,rot=np.stack([x,y,z],1).tolist())
    pts=[]
    for t in np.linspace(-1,1,7):
        xx=t*0.074; p=B.front_surface(xx,yl+0.012*(1-t*t)); pts.append(p+full_n(p)*0.046)
    tube_curve('bridge',pts,0.011,4,rim,cap=True)
    return dict(anchor='face',slot='face',tags=['cool','sporty'],price=55,title='Aviator goggles',
      desc='Brass-rim goggles with teal glass, pushed up on the forehead on a coral strap that circles the head at y~1.06. Lens bottoms y>=0.99, above the brows (brow top 0.962) and 0.11 above the eye beads. Anchor is the standard face anchor even though it sits above it; offsets are rest-space.')

def monocle(gold=HONEY,**k):
    reset(); stand=0.05; R=0.088
    fr=_eye_frames(stand)
    s,c,x,y,n=[f for f in fr if f[0]==1][0]
    pts=[c+(x*math.cos(a)+y*math.sin(a))*R for a in np.linspace(0,2*math.pi,25)]
    tube_curve('ring',pts,0.0115,5,lambda p,nn: mix(deep(gold,0.15),tint(gold,0.15),0.5+0.5*nn[1]),cap=False)
    for k_,a in enumerate((math.radians(-35),)):
        ico_part('hinge',tuple(c+(x*math.cos(a)+y*math.sin(a))*R),(0.017,0.017,0.017),deep(gold,0.15),sub=1)
    a=math.radians(-35); start=c+(x*math.cos(a)+y*math.sin(a))*R
    path=[start]
    for (px,py,off) in ((0.31,0.735,0.040),(0.36,0.690,0.040),(0.405,0.625,0.040),(0.425,0.565,0.040)):
        p,nn=body_pt(px,py,off); path.append(p)
    tube_curve('chain',path,0.0065,4,deep(gold,0.1),cap=True)
    ico_part('clip',tuple(path[-1]),(0.020,0.020,0.016),gold,sub=1)
    # little links
    for q in (1,2,3):
        m=(path[q]+path[q+1])/2; ico_part(f'link{q}',tuple(m),(0.011,0.011,0.011),tint(gold,0.1),sub=1)
    return dict(anchor='face',slot='face',tags=['cool','sweet'],price=45,title='Monocle',
      desc='Gold monocle ring around the +x eye bead (inner radius 0.077 vs bead half-height 0.062; no glass), with a chain hanging OUTWARD to a clip at (0.425,0.565): the chain never goes toward the centre line. Mirror x for the other eye.')

# ======================= NECK =====================================================
def scarf(a=CORAL,b=CREAM,**k):
    reset()
    X0=0.40; P_=0.092
    def yfn(x): return 0.488+0.020*(x/X0)**2
    xs=[-X0]
    k0=-5
    for kk in range(-6,11):
        e=-0.5+kk*P_*1.0+0.0
        if -X0+0.02<e<X0-0.02: xs+=[e-0.002,e+0.002]
    xs+=[X0]
    pts=[]
    for x in xs:
        p,nn=body_pt(x,yfn(x),0.042); pts.append(p)
    def col(p,nn):
        st=int(math.floor((p[0]+0.5)/P_))%2
        c=a if st==0 else b
        return mix(deep(c,0.10),tint(c,0.14),0.5+0.5*nn[1]*0.6)
    tube_curve('wrap',pts,0.0,8,col,radfn=lambda t:0.026+0.028*math.sin(math.pi*t)**0.6,cap=True,flat=0.85)
    kc,kn=body_pt(0.150,0.462,0.068); xx,yy,nn_=axes(kn)
    ico_part('knot',tuple(kc),(0.058,0.052,0.044),lambda p,nn: deep(a,0.16),sub=2,rot=np.stack([xx,yy,nn_],1).tolist())
    def tail(cx0,cx1,y0,y1,w,name,off):
        eps=0.012; vs=[0,0.25-eps,0.25+eps,0.5-eps,0.5+eps,0.75-eps,0.75+eps,1.0]
        def fn(i,j):
            v=vs[j]; u=i/3-0.5
            cx=cx0+(cx1-cx0)*v+0.012*math.sin(3.0*v)
            y=y0+(y1-y0)*v
            p,n=body_pt(cx+u*w*(1+0.12*v),y,off); return p,n
        def colr(p,nn):
            v=(y0-p[1])/(y0-y1); st=int(max(0,min(3.999,v*4)))%2; c=a if st==0 else b
            if v>0.93: c=deep(a,0.25)
            return mix(deep(c,0.08),tint(c,0.12),0.5+0.5*nn[1]*0.5)
        thick_sheet(name,fn,4,len(vs),0.016,colr)
    tail(0.140,0.205,0.450,0.215,0.086,'tail_a',0.050)
    tail(0.105,0.110,0.446,0.290,0.080,'tail_b',0.056)
    return dict(anchor='neck',slot='neck',tags=['sweet','cute','cool'],price=35,title='Cosy scarf',
      desc='Chunky striped scarf wrapped across the front belly at y~0.49 (top edge y<=0.54, below the mouth) with a knot at x=0.15 and two tails hanging to y~0.21. The wrap ends taper out at |x|=0.40, in front of the arm roots.')

def pearls(pearl=hx('#FBF4EC'),clasp=HONEY,**k):
    reset()
    def pxy(t): x=-0.34+0.68*t; return x,0.520-0.105*(1-(x/0.34)**2)
    ts=np.linspace(0,1,400); xy=np.array([pxy(t) for t in ts]); seg=np.linalg.norm(np.diff(xy,axis=0),axis=1); L=np.concatenate([[0],np.cumsum(seg)])
    n_=11
    for k_ in range(n_):
        d=L[-1]*(k_+0.5)/n_; i=int(np.searchsorted(L,d)); x,y=xy[min(i,len(xy)-1)]
        p,nn=body_pt(x,y,0.040)
        ico_part(f'pearl{k_}',tuple(p),(0.0345,0.0345,0.0345),lambda q,n_v: mix(deep(pearl,0.10),tint(pearl,0.12),0.5+0.5*n_v[1]),sub=2)
    p,nn=body_pt(0.0,0.392,0.054); xx,yy,z=axes(nn)
    ico_part('drop',tuple(p),(0.036,0.046,0.032),lambda q,n_v: mix(deep(hx('#E98AA4'),0.1),tint(hx('#E98AA4'),0.2),0.5+0.5*n_v[1]),sub=2,rot=np.stack([xx,yy,z],1).tolist())
    ico_part('cap',tuple(p+yy*0.052),(0.020,0.014,0.016),clasp,sub=1,rot=np.stack([xx,yy,z],1).tolist())
    return dict(anchor='neck',slot='neck',tags=['sparkly','sweet','cute'],price=65,title='Pearl necklace',
      desc='Eleven pearls on a swag from (+-0.34,0.545) down to (0,0.425) with a pink drop at y=0.405. Lowest point of the swag is at the centre line; no vertex is within the mouth keep-out (ellipse value >=1.1).')

def whistle(strap=SKY,metal=hx('#C9D3DC'),mouth=CORAL,**k):
    reset()
    for s in (-1,1):
        def fn(i,j,s=s):
            v=j/9; u=i/2-0.5
            x=s*(0.30*(1-v)+0.012*v); y=0.515+(0.446-0.515)*v-0.008*math.sin(math.pi*v)
            # strap direction ~ (-s*0.3,-0.09): offset across
            d=np.array([-s*0.30,-0.069]); d/=np.linalg.norm(d); perp=np.array([-d[1],d[0]])
            q=np.array([x,y])+perp*u*0.052
            p,n=body_pt(q[0],q[1],0.036); return p,n
        thick_sheet('strap%+d'%s,fn,3,10,0.014,lambda p,nn: strap if abs(p[0])>0.003 else strap)
    ring=[]
    c,cn=body_pt(0.0,0.436,0.056)
    for a in np.linspace(0,2*math.pi,13): ring.append(c+np.array([0.016*math.cos(a),0.020*math.sin(a),0.0]))
    tube_curve('ring',ring,0.0055,4,deep(metal,0.2),cap=False)
    wc,wn=body_pt(0.0,0.372,0.062)
    ico_part('chamber',tuple(wc),(0.054,0.048,0.042),lambda p,nn: mix(deep(metal,0.12),tint(metal,0.3),0.5+0.5*nn[1]),sub=2)
    lathe_y('mouthpiece',[(0.0,0.0),(0.027,0.0),(0.025,0.095),(0.0,0.097)],10,lambda p,nn: mouth,centre=tuple(wc+np.array([0.030,0.0,0.002])),rotm=np.array(rot_z(-math.pi/2)).tolist(),sharp=70)
    ico_part('hole',tuple(wc+np.array([0.0,0.016,0.038])),(0.016,0.008,0.008),INK,sub=1)
    return dict(anchor='neck',slot='neck',tags=['sporty','cool'],price=30,title='Coach whistle',
      desc='Sky lanyard in a V from the shoulders (+-0.30,0.535) to a ring at (0,0.44) with a silver whistle (coral mouthpiece) hanging to y~0.35. Everything is below the mouth (ellipse value >=1.1).')

# ======================= BODY ===================================================
WAIST_ANCHOR=(0.0,0.28,0.0)
def tutu(pink=PINK,lav=LAV,band=None,**k):
    reset(); segs=32; yb=0.255
    band=band or deep(pink,0.22)
    loop=[(0.014,0.026),(0.036,0.026),(0.036,-0.024),(0.014,-0.024)]
    torus('waistband',segs,lambda phi:[eloop(yb,phi,h,v) for h,v in loop],lambda p,n: mix(band,tint(band,0.2),0.5+0.5*n[1]*0.6))
    layers=[(0.13,0.070,deep(pink,0.06),0.0),(0.19,0.108,tint(pink,0.55),0.5),(0.25,0.150,tint(lav,0.15),1.0)]
    for li,(fl,dr,c,ph) in enumerate(layers):
        def lf(phi,fl=fl,dr=dr,ph=ph):
            sc=1+0.07*math.cos(10*phi+ph*math.pi); dd=dr*(1+0.10*math.cos(10*phi+ph*math.pi))
            return [eloop(yb+0.020,phi,0.038,0.0),eloop(yb+0.020,phi,fl*sc,-dd),eloop(yb+0.020,phi,fl*sc-0.012,-dd-0.003),eloop(yb+0.020,phi,0.030,-0.004)]
        torus(f'layer{li}',segs,lf,lambda p,n,c=c: mix(deep(c,0.14),tint(c,0.18),min(1,max(0,(0.275-p[1])/0.14))))
    return dict(anchor='waist',slot='body',tags=['cute','sweet','sparkly'],price=60,title='Ballet tutu',
      desc='Three-layer tulle tutu on a waistband around the egg at y 0.23..0.28 (hem y~0.12 at radius +0.24, scalloped). Full ring, clear of the arm bulbs (arm bottom y~0.31) and the feet. Front/back vertices all y<=0.28.')

BACK_ANCHOR=tuple(float(v) for v in B.egg_point(0.55,3*math.pi/2))
def cape(main=RED,lining=HONEY,trim=CREAM,**k):
    reset(); nu=15; nv=10
    y_top=0.68; y_bot=0.16
    def fn(i,j):
        u=i/(nu-1); v=j/(nv-1)
        phi=math.radians(200+140*u)
        y=y_top+(y_bot-y_top)*v-0.025*v**3*math.cos(math.pi*(u*4))
        off=0.034+0.215*v**1.5
        base=B.egg_point(y,phi); h=hdir(base); p=base+h*off
        n=h+np.array([0,0.15*v,0]); return p,n
    def col(p,nn):
        # outer vs inner by horizontal-outward test against the egg
        r=np.array([p[0],0,p[2]]); outer=float(np.dot(np.array([nn[0],nn[1],nn[2]]),r))>0
        c=main if outer else lining
        if p[1]<0.215: c=trim if outer else tint(lining,0.2)
        return c
    thick_sheet('panel',fn,nu,nv,0.016,col)
    pts=[]
    for i in range(nu*2):
        phi=math.radians(200+140*i/(nu*2-1)); base=B.egg_point(y_top+0.004,phi); pts.append(base+hdir(base)*0.044)
    tube_curve('collar',pts,0.030,6,lambda p,nn: mix(deep(trim,0.10),tint(trim,0.1),0.5+0.5*nn[1]),cap=True,flat=0.9)
    for ph in (340,200):
        base=B.egg_point(y_top+0.004,math.radians(ph)); c=base+hdir(base)*0.060
        ico_part(f'clasp{ph}',tuple(c),(0.038,0.038,0.030),lambda p,nn: mix(deep(HONEY,0.12),tint(HONEY,0.2),0.5+0.5*nn[1]),sub=2)
    sp=star_poly(0.115,0.050,5,rad=0.012)
    yst=0.43; vst=(y_top-yst)/(y_top-y_bot); zst=-(float(B.halfDepth((yst-B.lift)/B.bodyH))+0.034+0.215*vst**1.5+0.014)
    slab_part('emblem',sp,0.012,HONEY,lambda px,py,pz:(px,yst+py,zst-pz),cuts=0)
    return dict(anchor='back',slot='body',tags=['cool','sparkly','cute'],price=70,title='Hero cape',
      desc='Coral cape (honey lining, cream trim) hanging from a collar across the shoulders at y 0.68, behind the arms (back arc 200..340 deg, z<0 beyond the arm roots), flaring to y~0.16 and +0.25 behind the egg. Two gold clasps sit on the sides above the arm tops. Nothing on the front (z>0.15).')

def sgn_pow(v,e): return math.copysign(abs(v)**e,v)
def sellip(name,c,abc,e,color,nu=18,nv=9):
    a,b,cc=abc
    def pt(i,j):
        phi=2*math.pi*i/nu; th=-math.pi/2+math.pi*j/(nv-1)
        return np.array([c[0]+a*sgn_pow(math.cos(th)*math.cos(phi),e),c[1]+b*sgn_pow(math.sin(th),e),c[2]+cc*sgn_pow(math.cos(th)*math.sin(phi),e)])
    return grid_surface(name,pt,nu,nv,color,hint=lambda p:p-np.array(c))
def backpack(main=SKY,flap=CORAL,strap=None,**k):
    reset(); strap=strap or deep(main,0.28)
    zc=-0.625
    sellip('pack',(0,0.42,zc),(0.235,0.290,0.125),0.5,lambda p,n: mix(deep(main,0.12),tint(main,0.15),0.5+0.5*n[1]*0.6),nu=18,nv=9)
    sellip('flap',(0,0.565,zc-0.006),(0.240,0.125,0.134),0.5,lambda p,n: mix(deep(flap,0.12),tint(flap,0.15),0.5+0.5*n[1]*0.6),nu=18,nv=7)
    sellip('pocket',(0,0.31,zc-0.116),(0.155,0.100,0.056),0.5,lambda p,n: mix(deep(flap,0.18),tint(flap,0.1),0.5+0.5*n[1]*0.5),nu=14,nv=7)
    ico_part('buckle',(0,0.47,zc-0.142),(0.036,0.026,0.014),HONEY,sub=1)
    tube_curve('handle',[(-0.06,0.69,zc),(-0.06,0.75,zc),(0.06,0.75,zc),(0.06,0.69,zc)],0.012,5,strap,cap=True)
    for s in (1,-1):
        spec=[(0.58,282,0.040),(0.64,298,0.042),(0.690,318,0.046),(0.715,336,0.050),(0.712,346,0.054),(0.700,353,0.058)]
        Pc=[]
        for y,ph,off in spec:
            phi=math.radians(ph); phi=phi if s>0 else math.pi-phi
            p=B.egg_point(y,phi); Pc.append(p+hdir(p)*off)
        tg=[(Pc[min(j+1,len(Pc)-1)]-Pc[max(j-1,0)]) for j in range(len(Pc))]
        def fn(i,j,Pc=Pc,tg=tg):
            u=i/2-0.5; c=Pc[j]; t=tg[j]/np.linalg.norm(tg[j]); n=hdir(c)
            ac=np.cross(n,t); ac/=np.linalg.norm(ac); return c+ac*u*0.075,n
        thick_sheet('strap%+d'%s,fn,3,len(Pc),0.020,lambda p,nn: mix(deep(strap,0.05),tint(strap,0.12),0.5+0.5*nn[1]*0.5))
    return dict(anchor='back',slot='body',tags=['cute','sporty'],price=50,title='Little backpack',
      desc='Rounded backpack on the back (pack centre y 0.42, z -0.585) with a flap, pocket, buckle and top handle. Two shoulder straps run up the back and over the shoulders (above the arm tops, y~0.71) and END tucked behind the arm roots at z<0.1 - they never reach the front, so nothing on the front exceeds the y<=0.51 rule.')

def hero_patch(field=RED,inner=HONEY,bolt=SKY,**k):
    reset(); cy=0.352
    def xfp(zoff):
        def xf(px,py,pz):
            p,n=body_pt(px,cy+py,0.0); return tuple(p+n*(zoff+pz+0.004))
        return xf
    shield=lib.poly_pts_rounded([(-0.125,0.120),(0.125,0.120),(0.125,-0.012),(0.0,-0.128),(-0.125,-0.012)],0.032,arc=3)
    shield_in=lib.poly_pts_rounded([(-0.100,0.095),(0.100,0.095),(0.100,-0.010),(0.0,-0.100),(-0.100,-0.010)],0.026,arc=3)
    slab_part('shield',shield,0.016,field,xfp(0.0),cuts=1,sharp=40)
    slab_part('inner',shield_in,0.008,inner,xfp(0.014),cuts=1,sharp=40)
    bolt_pts=[(-0.012,0.075),(0.040,0.075),(0.008,0.015),(0.046,0.015),(-0.032,-0.080),(-0.010,-0.003),(-0.046,-0.003)]
    slab_part('bolt',bolt_pts,0.008,bolt,xfp(0.020),cuts=0,sharp=40)
    return dict(anchor='chest',slot='body',tags=['cool','sporty','cute'],price=30,title='Hero emblem patch',
      desc='Shield-shaped hero patch with a lightning bolt, centred on the belly at (0,0.352), spanning y 0.225..0.472 (top below 0.51). Surface-bound: conform each vertex to the body surface.')

# ======================= HANDS (arm-local frame) =====================================
LOCAL=dict(origin='arm tip centre B (BobForm.armTip for the +x arm at rest; the posed capsule tip B when posed)',
        x='outward across the arm',y='toward the shoulder = unit(A - B)',z='body forward (+z)',
        rest_matrix_columns=[[round(float(v),4) for v in GLOVE_FRAME[:,i]] for i in range(3)],
        scale='multiply mesh by (arm tip radius / 0.15)')
def wristbands(main=CREAM,stripe=SKY,stripe2=PINK,**k):
    reset(); segs=28; sq=0.90
    loop=[(0.124,0.016),(0.148,0.022),(0.156,0.036),(0.156,0.084),(0.148,0.098),(0.100,0.104),(0.098,0.060),(0.108,0.020)]
    def lf(phi): return [np.array([r*math.cos(phi),y,r*math.sin(phi)*sq]) for r,y in loop]
    def col(p,n):
        a=math.atan2(p[2]/sq,p[0]); y=p[1]
        c=main
        if 0.040<y<0.054: c=stripe
        if 0.066<y<0.080: c=stripe2
        return mix(c,deep(c,0.12),0.28*(0.5-0.5*math.cos(36*a)))
    torus('band',segs,lf,col,sharp=60)
    return dict(anchor='wrist',slot='hands',tags=['sporty','cute'],price=20,title='Wristbands',
      desc='Terry wristband on the arm neck (local y 0.016..0.104, outer radius 0.156 = 1.04x the arm tip). Authored for the +x arm in arm-local frame; mirror x (flip winding) for the -x arm.',
      anchor_rest=[float(v) for v in B_], authored_local=True,local_frame=LOCAL)

def boxing_gloves(mitt=RED,cuff=CREAM,lace=SKY,**k):
    reset(); sq=0.90
    prof=[(0.0,-0.168),(0.070,-0.162),(0.124,-0.140),(0.154,-0.100),(0.162,-0.050),(0.162,0.006),(0.154,0.056),(0.138,0.086),(0.124,0.094)]
    def mc(p,n):
        c=mix(deep(mitt,0.10),tint(mitt,0.14),0.5+0.5*n[1]*0.5)
        if abs(p[1]-(-0.056))<0.0045: c=deep(mitt,0.35)
        return c
    sm=[(max(0.0,float(q[0])),float(q[1])) for q in IO.catmull(prof,2)]
    lathe_y('mitt',sm,20,mc,scale=(1.0,sq),sharp=75)
    d=np.array([-0.25,0.30,0.92]); d/=np.linalg.norm(d); c=d*0.108
    z=d; xax=np.cross(UP,z); xax/=np.linalg.norm(xax); yax=np.cross(z,xax)
    ico_part('thumb',tuple(c+np.array([0,-0.01,0])),(0.050,0.064,0.048),lambda p,n: mix(deep(mitt,0.10),tint(mitt,0.16),0.5+0.5*n[1]*0.5),sub=2,rot=np.stack([xax,yax,z],1).tolist())
    cp=[(0.112,0.062),(0.138,0.068),(0.148,0.084),(0.148,0.112),(0.142,0.130),(0.124,0.138),(0.0,0.138)]
    def ribs(p,n):
        a=math.atan2(p[2],p[0]); return mix(cuff,deep(cuff,0.14),0.28*(0.5-0.5*math.cos(12*a)))
    lathe_y('cuff',cp,20,ribs,scale=(1.0,sq),sharp=60)
    lathe_y('lace',[(0.1495,0.094),(0.1515,0.099),(0.1515,0.107),(0.1495,0.112)],20,lace,scale=(1.0,sq),sharp=60)
    # glossy knuckle highlight
    ico_part('shine',(0.0,-0.05,0.128),(0.050,0.032,0.014),lambda p,n: tint(mitt,0.55),sub=1,rot=None)
    return dict(anchor='wrist',slot='hands',tags=['sporty','cool'],price=45,title='Boxing mitts',
      desc='Round fat boxing mitts (max radius 0.162 = 1.08x the arm tip; thumb bump inside 1.15x) with a cream cuff and a sky lace band. Authored for the +x arm in arm-local frame; mirror x for the -x arm.',
      anchor_rest=[float(v) for v in B_], authored_local=True,local_frame=LOCAL)

from items3 import scarf, tutu, cape
FA=FACE_ANCHOR; NA=NECK_ANCHOR; BA=BIB_ANCHOR; WR=tuple(float(v) for v in B_)
REG=[
 ('heart_shades',heart_shades,dict(),FA),
 ('goggles_aviator',goggles,dict(),FA),
 ('monocle_gold',monocle,dict(),FA),
 ('scarf_cosy',scarf,dict(),NA),
 ('scarf_sky',scarf,dict(a=SKY,b=CREAM),NA),
 ('pearls',pearls,dict(),NA),
 ('whistle_coach',whistle,dict(),NA),
 ('tutu_pink',tutu,dict(),WAIST_ANCHOR),
 ('cape_hero',cape,dict(),BACK_ANCHOR),
 ('backpack_sky',backpack,dict(),BACK_ANCHOR),
 ('hero_patch',hero_patch,dict(),BA),
 ('wristbands_sky',wristbands,dict(),WR),
 ('boxing_mitts',boxing_gloves,dict(),WR),
]
