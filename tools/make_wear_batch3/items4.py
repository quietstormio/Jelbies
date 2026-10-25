"""Batch 3 wearables (2026-10-24, Stage C): headphones, cowboy hat, beret, hair bow, bee antennae, lei, hoodie, raincoat."""
from wl import *
import items_head as IH
from items_head import shell, headband_curve, _band, ribbed
from items_other import axes, body_pt, NECK_ANCHOR, BIB_ANCHOR
from items2_head import torus, thick_sheet, eloop, hdir, uvsphere, gem, basis_to, phi_of
UP=np.array([0,1,0.]); TOP=B.top; H=(0.0,TOP,0.0)
def _lit(c,k=0.18,d=0.12): return lambda p,n: mix(deep(c,d),tint(c,k),0.5+0.5*n[1]*0.7)

# ============================ HEADPHONES =====================================
def headphones(band=INK,cup=CORAL,pad=CREAM,**k):
    reset()
    pts=headband_curve(zoff=0.0,y_start=0.93,off=0.044)
    path=_band(pts,lambda p,n: mix(deep(band,0.05),tint(band,0.22),0.5+0.5*n[1]))
    for s in (-1,1):
        phi=0.0 if s>0 else math.pi
        e=B.egg_point(0.90,phi); n=np.array([s,0,0.]); c=e+n*0.046
        Rm=basis_to(n).tolist()   # local y -> outward
        lathe_y('cup%+d'%s,[(0.0,-0.020),(0.108,-0.020),(0.126,0.0),(0.126,0.040),(0.104,0.062),(0.0,0.070)],20,_lit(cup),centre=tuple(c),scale=(1.0,0.92),rotm=Rm,sharp=70)
        lathe_y('pad%+d'%s,[(0.050,-0.034),(0.112,-0.034),(0.124,-0.020),(0.118,-0.004),(0.056,-0.004)],20,lambda p,nn: mix(pad,deep(pad,0.14),0.3),centre=tuple(c),scale=(1.0,0.92),rotm=Rm,sharp=70)
        ico_part('hub%+d'%s,tuple(c+n*0.070),(0.052,0.052,0.016),lambda p,nn: mix(deep(cup,0.22),tint(cup,0.2),0.5+0.5*nn[2]),sub=2,rot=basis_to(n).tolist())
    return dict(anchor='head_top',slot='head',tags=['cool','sporty'],price=55,title='Headphones',
      desc='Big over-ear headphones: an ink band arching over the crown and coral ear cups with cream pads, at y 0.90 on the head sides (clear of the eyes, brows, arm tops and mouth).')

# ============================ COWBOY HAT =====================================
def cowboy_hat(main=hx('#B98552'),band=hx('#7A4A2B'),star=HONEY,**k):
    reset(); segs=32
    y0=lambda phi: 1.07+0.035*math.sin(phi)
    def pinch(base):
        return lambda phi: base-0.020*math.cos(2*phi-math.pi)*0   # sides neutral (dent comes from the crease row)
    rows=[('a',0.012,0.006),('a',-0.002,0.026),('a',0.02,0.042),('a',0.075,0.046)]
    for f,o in ((0.0,0.050),(0.25,0.052),(0.55,0.052),(0.78,0.049),(0.92,0.046)): rows.append(('k',f,o))
    rows.append(('pole',0,0.040))
    def col(p,n):
        dy=p[1]-y0(phi_of(p))
        if 0.02<dy<0.085: return band
        return mix(main,tint(main,0.2),0.5*max(0,n[1]))
    shell('crown',segs,y0,rows,col)
    # centre crease: a groove stripe along the crown top front-to-back
    pts=[]
    for t in np.linspace(0.0,1.0,13):
        a=math.pi*(0.5+t); y=1.19+0.17*math.sin(math.pi*t)**0.6*0+0.0
        phi=a; ytop=1.255-0.0*t
        e=B.egg_point(min(1.318,1.215+0.10*math.sin(math.pi*t)),phi); pts.append(e+egg_n(e)*0.056)
    tube_curve('crease',pts,0.010,5,_lit(deep(main,0.18),0.10),cap=True)
    # wide brim, curled up at the sides, dipped front and back
    def lf(phi):
        w=math.cos(phi)**2; curl=0.085*w**1.2; out=0.250+0.045*w
        return [eloop(y0(phi),phi,0.030,0.022+curl*0.15),eloop(y0(phi),phi,out*0.5,0.010+curl*0.45),
                eloop(y0(phi),phi,out,-0.006+curl),eloop(y0(phi),phi,out+0.006,-0.020+curl),
                eloop(y0(phi),phi,out*0.5,-0.014+curl*0.4),eloop(y0(phi),phi,0.030,-0.010)]
    torus('brim',segs,lf,lambda p,n: mix(deep(main,0.10),tint(main,0.16),0.5+0.5*n[1]*0.6),sharp=58)
    # stitched edge cord
    pts=[]
    for i in range(segs+1):
        phi=2*math.pi*i/segs; w=math.cos(phi)**2; curl=0.085*w**1.2; out=0.250+0.045*w
        pts.append(eloop(y0(phi),phi,out+0.002,-0.006+curl+0.002))
    tube_curve('edge',pts,0.0085,3,deep(main,0.28),cap=False)
    # star conch on the band
    f=B.egg_point(y0(math.pi/2)+0.050,math.pi/2); n=egg_n(f); x,y,nn=axes(n); c=f+nn*0.058
    sp=star_poly(0.044,0.020,5,rad=0.006)
    slab_part('star',sp,0.010,star,lambda px,py,pz: tuple(c+x*px+y*py+nn*pz),cuts=0)
    return dict(anchor='head_top',slot='head',tags=['cool','sporty'],price=55,title='Cowboy hat',
      desc='Tan cowboy hat with a creased crown, a wide brim curled up at the sides, a brown band and a gold star. Front brim edge y~1.07, above the brows.')

# ============================ BERET ==========================================
def beret(main=hx('#C8505E'),stalk=INK,**k):
    reset(); segs=28
    y0=lambda phi: 1.085+0.030*math.sin(phi)
    rows=[('a',0.010,0.006),('a',-0.002,0.022),('a',0.014,0.036),('a',0.040,0.044)]
    for f,o in ((0.0,0.050),(0.4,0.052),(0.8,0.048)): rows.append(('k',f,o))
    rows.append(('pole',0,0.040))
    shell('band',segs,y0,rows,lambda p,n: mix(deep(main,0.10),tint(main,0.16),0.5*max(0,n[1])))
    # the soft pancake puff, leaning to one side
    tilt=Matrix.Rotation(math.radians(-14),3,'Z') @ Matrix.Rotation(math.radians(6),3,'X')
    ico_part('puff',(0.050,TOP-0.030,0.012),(0.300,0.092,0.285),lambda p,n: mix(deep(main,0.14),tint(main,0.18),0.5+0.5*n[1]*0.8),sub=3,rot=[list(r) for r in tilt])
    c=np.array([0.050,TOP-0.030,0.012])+np.array(tilt)@np.array([0,0.090,0])
    lathe_y('stalk',[(0.0,0.0),(0.026,0.0),(0.020,0.040),(0.0,0.044)],8,stalk,centre=tuple(c-np.array([0,0.006,0])),rotm=[list(r) for r in tilt],sharp=70)
    return dict(anchor='head_top',slot='head',tags=['cute','cool','sweet'],price=40,title='Beret',
      desc='Soft red beret: a snug band with a flat pancake puff tipped to one side and a little stalk. Band lower edge y~1.08, above the brows.')

# ============================ HAIR BOW =======================================
def hair_bow(main=PINK,knot=None,dots=CREAM,**k):
    reset(); knot=knot or deep(main,0.16)
    e=B.egg_point(1.255,math.radians(52)); n=egg_n(e); x,y,nn=axes(n); c=e+nn*0.030
    for s in (-1,1):
        ang=math.radians(22*s)
        loopx=x*math.cos(ang)+y*math.sin(ang)
        loopy=-x*math.sin(ang)+y*math.cos(ang)
        Rm=np.stack([loopx,loopy,nn],1).tolist()
        ico_part('loop%+d'%s,tuple(c+loopx*s*0.115+nn*0.040),(0.125,0.074,0.040),lambda p,nn_: mix(deep(main,0.12),tint(main,0.2),0.5+0.5*nn_[2]),sub=3,rot=Rm)
        ico_part('fold%+d'%s,tuple(c+loopx*s*0.100+nn*0.066),(0.070,0.040,0.014),lambda p,nn_: mix(deep(main,0.22),tint(main,0.10),0.5+0.5*nn_[2]),sub=2,rot=Rm)
        # tail
        tl=c+y*(-0.100)+x*s*0.045+nn*0.020
        ico_part('tail%+d'%s,tuple(tl),(0.030,0.085,0.012),lambda p,nn_: mix(deep(main,0.14),tint(main,0.15),0.5+0.5*nn_[2]),sub=2,rot=np.stack([x*math.cos(math.radians(14*s))+y*math.sin(math.radians(14*s)),-x*math.sin(math.radians(14*s))+y*math.cos(math.radians(14*s)),nn],1).tolist())
    ico_part('knot',tuple(c+nn*0.054),(0.050,0.056,0.044),_lit(knot),sub=3,rot=np.stack([x,y,nn],1).tolist())
    for i,(dx,dy_) in enumerate(((0.12,0.02),(-0.12,0.02),(0.095,-0.03),(-0.095,-0.03))):
        ico_part('dot%d'%i,tuple(c+x*dx+y*dy_+nn*0.074),(0.014,0.014,0.006),dots,sub=1,rot=np.stack([x,y,nn],1).tolist())
    return dict(anchor='head_top',slot='head',tags=['cute','sweet'],price=30,title='Big hair bow',
      desc='A big polka-dot ribbon bow clipped on the upper right of the head (y~1.25, well above the brows). Rigid; carried with the head squash.')

# ============================ BEE ANTENNAE ===================================
def bee_antennae(band=HONEY,stalk=INK,ball=HONEY,**k):
    reset(); pts=headband_curve(); path=_band(pts,lambda p,n: mix(deep(band,0.12),tint(band,0.2),0.5+0.5*n[1]))
    for s in (-1,1):
        j=min(range(len(path)),key=lambda q: abs(path[q][0]-s*0.15)+(0 if path[q][1]>1.25 else 5)); bp=path[j]
        pth=[bp+np.array([s*dx,dy,dz]) for dx,dy,dz in ((0,0,0),(0.012,0.07,0.010),(0.040,0.140,0.028),(0.080,0.195,0.050),(0.126,0.228,0.070))]
        tube_curve('stalk%+d'%s,pth,0.0105,6,stalk,cap=True)
        tip=pth[-1]+np.array([s*0.020,0.010,0.012])
        ico_part('ball%+d'%s,tuple(tip),(0.056,0.056,0.056),lambda p,nn: mix(deep(ball,0.14),tint(ball,0.25),0.5+0.5*nn[1]),sub=3)
        ico_part('stripe%+d'%s,tuple(tip),(0.0585,0.016,0.0585),INK,sub=2)
    return dict(anchor='head_top',slot='head',tags=['cute','sweet'],price=40,title='Bee antennae',
      desc='Honey headband with two springy antennae tipped with striped bee balls.')

# ============================ FLOWER LEI =====================================
def lei(cols=None,leaf=MINT,**k):
    reset(); cols=cols or [CORAL,PINK,HONEY,LAV,CORAL,PINK,HONEY,LAV,CORAL,PINK,HONEY,LAV]
    NF=len(cols)
    def ring_y(phi):   # sags to a V at the front (below the mouth keep-out), lifts at the back
        s=max(0.0,math.sin(phi)); return 0.462-0.062*s**2+0.045*max(0.0,-math.sin(phi))
    pts=[]
    for i in range(49):
        phi=2*math.pi*i/48; e=B.egg_point(ring_y(phi),phi); pts.append(e+hdir(e)*0.038)
    tube_curve('string',pts,0.011,5,leaf,cap=False)
    for i,c in enumerate(cols):
        phi=2*math.pi*(i+0.5)/NF+math.pi/2*0   # evenly around, one centred just off the front
        phi=math.pi/2+2*math.pi*(i-NF/2+0.5)/NF
        e=B.egg_point(ring_y(phi),phi); n=egg_n(e); x,y,nn=axes(n); ctr=e+hdir(e)*0.052
        # petals
        for pI in range(5):
            a=2*math.pi*pI/5+0.4
            pc=ctr+(x*math.cos(a)+y*math.sin(a))*0.034+nn*0.004
            ico_part('p%d_%d'%(i,pI),tuple(pc),(0.030,0.030,0.011),lambda p,nn_,c=c: mix(deep(c,0.10),tint(c,0.25),0.5+0.5*nn_[2]),sub=1,rot=np.stack([x,y,nn],1).tolist())
        ico_part('c%d'%i,tuple(ctr+nn*0.010),(0.018,0.018,0.012),HONEY if c!=HONEY else CORAL,sub=1,rot=np.stack([x,y,nn],1).tolist())
        # a small leaf between blooms
        phl=phi+math.pi/NF; e2=B.egg_point(ring_y(phl),phl); n2=egg_n(e2); x2,y2,nn2=axes(n2)
        ico_part('l%d'%i,tuple(e2+hdir(e2)*0.046),(0.034,0.016,0.008),leaf,sub=1,rot=np.stack([x2,y2,nn2],1).tolist())
    return dict(anchor='neck',slot='neck',tags=['sweet','cute','sparkly'],price=45,title='Flower lei',
      desc='A garland of twelve pastel blooms and leaves circling the belly, dipping to a V on the front at y~0.40 (nothing above y 0.51, so the mouth stays clear).')

# ============================ HOODIE =========================================
def torso_shell(name,ys,offs,col,segs=40):
    def pt(i,j):
        phi=2*math.pi*i/segs; e=B.egg_point(ys[j],phi); o=offs[j]; o=o(phi) if callable(o) else o
        return e+hdir(e)*o
    return grid_surface(name,pt,segs,len(ys),col,hint=lambda p: IH.egg_hint(p))

def hoodie(main=hx('#E8575F'),trim=CREAM,**k):
    reset()
    ys=[0.175,0.178,0.20,0.26,0.34,0.42,0.48,0.505]
    offs=[0.040,0.044,0.042,0.040,0.039,0.040,0.042,0.040]
    def col(p,n):
        base=mix(deep(main,0.10),tint(main,0.16),0.5+0.5*n[1]*0.7)
        return mix(base,deep(main,0.12),0.35) if p[1]<0.215 else base
    torso_shell('body',ys,offs,col)
    # ribbed hem band
    torus('hem',40,lambda phi:[eloop(0.186,phi,h,v) for h,v in ((0.034,0.030),(0.052,0.022),(0.056,-0.016),(0.038,-0.024))],lambda p,n: mix(deep(trim,0.28),tint(main,0.2),0.5+0.5*math.cos(26*phi_of(p)))*1 if False else mix(deep(main,0.18),tint(main,0.10),0.5+0.5*math.cos(26*phi_of(p))))
    # neckline roll under the mouth (y<=0.51)
    torus('neck',40,lambda phi:[eloop(0.498,phi,h,v) for h,v in ((0.026,0.020),(0.054,0.014),(0.056,-0.010),(0.030,-0.016))],lambda p,n: mix(deep(main,0.12),tint(main,0.2),0.5+0.5*n[1]))
    # kangaroo pocket
    def pk(i,j):
        u=i/8.0*2-1; v=j/5.0; y=0.205+0.145*v; w=0.205*(1-0.42*v)
        x=u*w; p,n=body_pt(x,y,0.050+0.006*math.sin(math.pi*v)); return p
    grid_surface('pocket',pk,9,6,lambda p,n: mix(deep(main,0.16),tint(main,0.14),0.5+0.5*n[1]*0.6),closed_u=False,hint=lambda p:full_n(p))
    for s in (-1,1):
        pts=[body_pt(s*(0.205*(1-0.42*v)),0.205+0.145*v,0.054)[0] for v in np.linspace(0,1,6)]
        tube_curve('pocketseam%+d'%s,pts,0.0075,4,deep(main,0.28),cap=True)
    # drawstrings with aglets
    for s in (-1,1):
        pts=[body_pt(s*x,y,0.058)[0] for x,y in ((0.060,0.500),(0.068,0.470),(0.074,0.440),(0.078,0.410),(0.080,0.386))]
        tube_curve('cord%+d'%s,pts,0.0085,5,trim,cap=True)
        ico_part('aglet%+d'%s,tuple(body_pt(s*0.081,0.372,0.058)[0]),(0.014,0.022,0.014),HONEY,sub=1)
    # hood bunched on the back of the shoulders
    zc=-(float(B.halfDepth((0.585-B.lift)/B.bodyH)))
    ico_part('hood',(0.0,0.585,zc+0.015),(0.285,0.118,0.105),lambda p,n: mix(deep(main,0.16),tint(main,0.14),0.5+0.5*n[1]*0.8),sub=3,fuzz=0.02,seed=5)
    pts=[]
    for i in range(25):
        phi=math.radians(188+164*i/24); e=B.egg_point(0.508,phi); pts.append(e+hdir(e)*0.074)
    tube_curve('hoodrim',pts,0.030,6,lambda p,n: mix(deep(main,0.10),tint(main,0.16),0.5+0.5*n[1]),cap=True,flat=0.85)
    return dict(anchor='chest',slot='body',tags=['cool','cute','sweet'],price=65,title='Cosy hoodie',
      desc='Red pullover hoodie: ribbed hem, a kangaroo pocket, cream drawstrings and a bunched hood resting behind the shoulders. Everything on the front sits at y<=0.51 (neckline roll top 0.51), clear of the mouth.')

# ============================ RAINCOAT =======================================
def raincoat(main=hx('#F4C13E'),trim=CREAM,toggle=hx('#7A4A2B'),**k):
    reset()
    ys=[0.190,0.215,0.26,0.32,0.39,0.45,0.490,0.505]
    offs=[0.108,0.092,0.074,0.060,0.050,0.046,0.044,0.042]
    def col(p,n):
        if 0.255<p[1]<0.285: return trim
        return mix(deep(main,0.10),tint(main,0.22),0.5+0.5*n[1]*0.8)
    torso_shell('coat',ys,offs,col)
    torus('collar',40,lambda phi:[eloop(0.500,phi,h,v) for h,v in ((0.028,0.018),(0.058,0.012),(0.060,-0.012),(0.032,-0.018))],lambda p,n: mix(deep(main,0.16),tint(main,0.2),0.5+0.5*n[1]))
    # front placket and toggles
    pts=[body_pt(0.0,y,0.058)[0] for y in np.linspace(0.205,0.492,9)]
    tube_curve('placket',pts,0.012,5,lambda p,n: mix(deep(main,0.2),tint(main,0.1),0.5),cap=True)
    for i,y in enumerate((0.235,0.300,0.365,0.430)):
        p,n=body_pt(0.0,y,0.072); xx,yy,nn=axes(n)
        ico_part('button%d'%i,tuple(p),(0.022,0.022,0.010),toggle,sub=2,rot=np.stack([xx,yy,nn],1).tolist())
    # chest pockets with flaps
    for s in (-1,1):
        p,n=body_pt(s*0.215,0.355,0.060); xx,yy,nn=axes(n)
        ico_part('pocket%+d'%s,tuple(p),(0.075,0.058,0.014),lambda q,nq: mix(deep(main,0.14),tint(main,0.15),0.5+0.5*nq[2]),sub=2,rot=np.stack([xx,yy,nn],1).tolist())
        p2,n2=body_pt(s*0.215,0.385,0.068); x2,y2,nn2=axes(n2)
        ico_part('flap%+d'%s,tuple(p2),(0.082,0.026,0.012),lambda q,nq: mix(deep(main,0.20),tint(main,0.1),0.5+0.5*nq[2]),sub=2,rot=np.stack([x2,y2,nn2],1).tolist())
    # peaked hood resting back
    zc=-(float(B.halfDepth((0.60-B.lift)/B.bodyH)))
    d=np.array([0,0.55,-1.0]); d/=np.linalg.norm(d)
    base=np.array([0.0,0.585,zc+0.010])
    lathe_y('hood',[(0.0,-0.02),(0.150,0.0),(0.158,0.030),(0.110,0.140),(0.052,0.235),(0.0,0.285)],16,lambda p,n: mix(deep(main,0.14),tint(main,0.2),0.5+0.5*n[1]*0.8),centre=tuple(base),scale=(1.15,0.75),rotm=basis_to(d).tolist(),sharp=70)
    pts=[]
    for i in range(25):
        phi=math.radians(188+164*i/24); e=B.egg_point(0.508,phi); pts.append(e+hdir(e)*0.078)
    tube_curve('hoodrim',pts,0.028,6,lambda p,n: mix(deep(main,0.12),tint(main,0.2),0.5+0.5*n[1]),cap=True,flat=0.85)
    return dict(anchor='chest',slot='body',tags=['cute','cool'],price=60,title='Yellow raincoat',
      desc='Glossy yellow slicker flaring to the hem (y 0.19), a cream reflective stripe, toggle buttons, chest pockets and a peaked hood resting behind the shoulders. Collar top 0.51: clear of the mouth.')

REG=[
 ('headphones',headphones,dict(),H),
 ('cowboy_hat',cowboy_hat,dict(),H),
 ('beret',beret,dict(),H),
 ('hair_bow',hair_bow,dict(),H),
 ('bee_antennae',bee_antennae,dict(),H),
 ('lei',lei,dict(),NECK_ANCHOR),
 ('hoodie',hoodie,dict(),BIB_ANCHOR),
 ('raincoat',raincoat,dict(),BIB_ANCHOR),
]
