from wl import *
import items_head as IH
from items_other import axes, body_pt, fz
from items_head import shell, headband_curve, _band
TOP=B.top; UP=np.array([0,1,0.])
H=(0.0,TOP,0.0)

# ---------------- shared helpers (batch 2) -----------------------------------
def phi_of(p):
    t=(float(p[1])-B.lift)/B.bodyH; return math.atan2(float(p[2])/max(float(B.halfDepth(t)),0.05),float(p[0])/max(float(B.halfWidth(t)),0.05))
def hdir(p):
    n=egg_n(p); h=np.array([n[0],0,n[2]]); return h/max(np.linalg.norm(h),1e-9)
def eloop(y,phi,h,v):
    """point on the egg at height y, angle phi, then h outward (horizontal) and v up."""
    base=B.egg_point(y,phi); return base+hdir(base)*h+np.array([0,v,0])
def basis_to(d):
    d=np.array(d,float); d/=np.linalg.norm(d); ref=np.array([0,0,1.]) if abs(d[2])<0.9 else np.array([1,0,0.])
    x=np.cross(ref,d); x/=np.linalg.norm(x); z=np.cross(x,d); return np.stack([x,d,z],1)   # local y -> d
def _bm_grid(P,nu,nv,wrap_u,wrap_v):
    bm=bmesh.new(); vs=[bm.verts.new(tuple(map(float,p))) for p in P]
    for j in range(nv if wrap_v else nv-1):
        for i in range(nu if wrap_u else nu-1):
            i2=(i+1)%nu; j2=(j+1)%nv
            bm.faces.new([vs[j*nu+i],vs[j*nu+i2],vs[j2*nu+i2],vs[j2*nu+i]])
    return bm
def _col(color):
    return color if callable(color) else (lambda p,n: color)
def torus(name,segs,loopfn,color,sharp=55):
    """closed ring: loopfn(phi)->list of K points (closed loop). Orientation fixed by recalc_face_normals in commit."""
    P=[];K=None
    for i in range(segs):
        L=loopfn(2*math.pi*i/segs); K=len(L); P+=[tuple(q) for q in L]
    # layout index = i*K+k : treat as grid nu=K (loop), nv=segs (around)
    bm=_bm_grid(P,K,segs,True,True)
    return closed(bm,_col(color),name,sharp=sharp)
def thick_sheet(name,fn,nu,nv,thick,color_out,color_in=None,sharp=60):
    """closed thin slab from a surface fn(i,j)->(point, outward normal). outer layer = point, inner = point - n*thick."""
    P0=[];P1=[];CM={}
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
    key=lambda p:(round(p[0],4),round(p[1],4),round(p[2],4))
    for p in P1: CM[key(p)]=(color_in or color_out)
    for p in P0: CM[key(p)]=color_out
    cf=lambda p,n:(CM.get(key(p),color_out)(p,n) if callable(CM.get(key(p),color_out)) else CM.get(key(p),color_out))
    return closed(bm,cf,name,sharp=sharp)
def uvsphere(name,c,r,color,segs=8,scale=(1,1,1)):
    prof=[(0,-r*scale[1]),(r*0.80,-r*0.62*scale[1]),(r,0),(r*0.80,r*0.62*scale[1]),(0,r*scale[1])]
    return lathe_y(name,prof,segs,color,centre=tuple(c),sharp=85)
def gem(name,c,r,color,sub=1): return ico_part(name,tuple(c),(r,r,r),color,sub=sub)

# ============================ BUCKET HAT =====================================
def bucket_hat(main=MINT,band=CREAM,stitch=None,**k):
    reset(); segs=28
    y0=lambda phi: 1.06+0.03*math.sin(phi)
    rows=[('a',0.012,0.006),('a',-0.002,0.030),('a',0.02,0.040),('a',0.08,0.044)]
    for f,o in ((0.0,0.046),(0.2,0.046),(0.45,0.043),(0.7,0.039),(0.9,0.034)): rows.append(('k',f,o))
    rows.append(('pole',0,0.030))
    def col(p,n):
        dy=p[1]-y0(phi_of(p))
        if 0.015<dy<0.075: return band
        return mix(main,tint(main,0.18),max(0,n[1])*0.5)
    shell('crown',segs,y0,rows,col)
    st=stitch or deep(main,0.22)
    loop=[(0.030,0.014),(0.100,0.004),(0.170,-0.040),(0.178,-0.054),(0.170,-0.062),(0.100,-0.020),(0.030,-0.006)]
    def lf(phi): return [eloop(y0(phi),phi,h,v) for h,v in loop]
    def bc(p,n):
        a=phi_of(p); r=math.hypot(p[0],p[2]); ring=(0.5+0.5*math.cos(18*a))
        return mix(main,tint(main,0.1),0.0) if n[1]>-0.2 else deep(main,0.10)
    torus('brim',segs,lf,bc)
    return dict(anchor='head_top',slot='head',tags=['cute','cool'],price=35,title='Bucket hat',
      desc='Soft bucket hat: contrast band on a rounded crown and a floppy drooping brim (lowest brim edge y~1.0, above the brows). Rigid; carried with the head squash.')

# ============================ CROWN / TIARA ==================================
def crown(gold=HONEY,gem_a=PINK,gem_b=SKY,**k):
    reset(); segs=32
    y0=lambda phi: 1.075+0.04*math.sin(phi)
    loop=[(0.020,0.0),(0.036,0.008),(0.040,0.046),(0.036,0.080),(0.020,0.090),(0.014,0.046)]
    def gc(p,n): return mix(deep(gold,0.18),tint(gold,0.2),0.5+0.5*n[1])
    torus('band',segs,lambda phi:[eloop(y0(phi),phi,h,v) for h,v in loop],gc)
    nsp=7
    for s in range(nsp):
        phi=math.pi/2+2*math.pi*s/nsp
        big=(s==0)
        base=eloop(y0(phi)+0.078,phi,0.034,0); d=hdir(B.egg_point(1.1,phi))*0.20+UP
        Rm=basis_to(d); hh=0.21 if big else 0.145
        prof=[(0,0.0),(0.052,0.0),(0.036,0.05),(0.0,hh)]
        lathe_y(f'spike{s}',prof,8,gc,centre=tuple(base),rotm=Rm.tolist(),sharp=70)
        tip=base+np.array(d)/np.linalg.norm(d)*(hh+0.012)
        gem(f'tip{s}',tip,0.019 if not big else 0.026,CREAM if not big else WHITE,sub=1)
        if big: ico_part('jewel',tuple(eloop(y0(phi)+0.045,phi,0.050,0)),(0.040,0.046,0.024),gem_a,sub=2)
    for s in range(nsp):
        phi=math.pi/2+2*math.pi*(s+0.5)/nsp
        if s in (1,2,4,5): ico_part(f'bead{s}',tuple(eloop(y0(phi)+0.045,phi,0.044,0)),(0.018,0.018,0.012),gem_b,sub=1)
    return dict(anchor='head_top',slot='head',tags=['sparkly','sweet'],price=75,title='Royal crown',
      desc='Gold crown band with seven spikes, pearl tips and a big pink jewel at the front. Band bottom edge y>=1.07 at the front, above the brows.')

# ============================ CHEF HAT =======================================
def chef_hat(main=CREAM,**k):
    reset(); segs=28
    y0=lambda phi: 1.05+0.035*math.sin(phi)
    loop=[(0.022,0.0),(0.040,0.008),(0.044,0.045),(0.040,0.086),(0.022,0.092),(0.016,0.045)]
    torus('band',segs,lambda phi:[eloop(y0(phi),phi,h,v) for h,v in loop],lambda p,n: mix(main,deep(main,0.10),0.4*max(0,-n[1])+0.0))
    from items_other import catmull
    prof=[(max(0.0,float(q[0])),float(q[1])) for q in catmull([(1.0,0.0),(1.03,0.07),(1.10,0.20),(1.20,0.36),(1.16,0.50),(0.84,0.60),(0.0,0.63)],2)]
    prof[-1]=(0.0,0.63)
    def pt(i,j):
        phi=2*math.pi*i/segs; yb=y0(phi)+0.08
        rim=eloop(yb,phi,0.040,0.0); ax=np.array([0,yb,-0.01]); rv=rim-ax; rv[1]=0
        sc,hh=prof[j]; lump=1+0.075*math.sin(math.pi*min(1,j/5))*math.cos(5*phi+0.6)
        return np.array([0,yb,-0.01])+rv*sc*lump+np.array([0,hh,0])
    grid_surface('pouf',pt,segs,len(prof),lambda p,n: mix(deep(main,0.10+0.08*(0.5+0.5*math.cos(5*phi_of(p)+0.6))),tint(main,0.15),0.5+0.5*n[1]),hint=lambda p:(p-np.array([0,1.28,-0.01])))
    return dict(anchor='head_top',slot='head',tags=['cute','sweet'],price=40,title='Chef hat',
      desc='Tall puffy white toque on a band. Rigid; tall piece (top y~1.52).')

# ============================ PIRATE HAT =====================================
def pirate_hat(main=INK,trim=HONEY,**k):
    reset(); segs=28
    y0=lambda phi: 1.07+0.035*math.sin(phi)
    rows=[('a',0.012,0.006),('a',-0.002,0.026),('a',0.02,0.040),('a',0.07,0.044)]
    for f,o in ((0.0,0.046),(0.3,0.047),(0.6,0.043),(0.85,0.036)): rows.append(('k',f,o))
    rows.append(('pole',0,0.030))
    shell('crown',segs,y0,rows,lambda p,n: mix(main,tint(main,0.22),0.5*max(0,n[1])))
    # bicorne brim: raised wings at the sides (phi=0, pi), low at front/back
    def lf(phi):
        w=math.cos(phi)**2; lift=0.20*w**1.2
        out=0.15+0.07*w
        return [eloop(y0(phi)+0.0,phi,0.030,0.020+lift*0.20),eloop(y0(phi),phi,out*0.5,0.012+lift*0.55),
                eloop(y0(phi),phi,out,-0.004+lift),eloop(y0(phi),phi,out+0.004,-0.016+lift),
                eloop(y0(phi),phi,out*0.5,-0.014+lift*0.5),eloop(y0(phi),phi,0.030,-0.010)]
    def bc(p,n):
        a=phi_of(p); r=math.hypot(p[0],p[2])
        return trim if (r>0.57 and abs(math.cos(a))<0.97 and False) else mix(main,tint(main,0.18),0.5*max(0,n[1]))
    torus('brim',segs,lf,lambda p,n: mix(main,tint(main,0.2),0.5*max(0,n[1])),sharp=55)
    # gold trim cord around the outer brim edge
    pts=[]
    for i in range(segs+1):
        phi=2*math.pi*i/segs; w=math.cos(phi)**2; lift=0.20*w**1.2; out=0.15+0.07*w
        pts.append(eloop(y0(phi),phi,out+0.002,-0.004+lift+0.002))
    tube_curve('cord',pts,0.0085,3,trim,cap=False)
    # skull + crossbones on the front of the crown
    f=B.egg_point(1.185,math.pi/2); n=egg_n(f); x,y,nn=axes(n); c=f+nn*0.050
    Rm=np.stack([x,y,nn],1).tolist()
    ico_part('skull',tuple(c+y*0.012),(0.050,0.046,0.030),CREAM,sub=2,rot=Rm)
    ico_part('jaw',tuple(c-y*0.040),(0.030,0.020,0.022),CREAM,sub=1,rot=Rm)
    for s in (-1,1): ico_part(f'socket{s}',tuple(c+y*0.020+x*s*0.021+nn*0.020),(0.014,0.016,0.008),INK,sub=1,rot=Rm)
    for s in (-1,1):
        st=c-y*0.02-x*0.085+y*0.062*s-nn*0.010; en=c-y*0.02+x*0.085-y*0.062*s-nn*0.010
        tube_curve(f'bone{s}',[st,en],0.011,5,CREAM,cap=True)
    return dict(anchor='head_top',slot='head',tags=['cool','sporty'],price=60,title='Pirate hat',
      desc='Black bicorne with up-swept wings, gold cord and a skull-and-crossbones badge. Front brim edge y~1.07, above the brows.')

# ============================ BUNNY EARS =====================================
def bunny_ears(band=PINK,ear=CREAM,inner=PINK,**k):
    reset(); pts=headband_curve(); path=_band(pts,band)
    for s in (-1,1):
        j=min(range(len(path)),key=lambda q: abs(path[q][0]-s*0.20)+(0 if path[q][1]>1.22 else 5)); bp=path[j]
        lean=np.array([s*(0.10 if s<0 else 0.62),1,0.10 if s<0 else 0.30]); lean=lean/np.linalg.norm(lean)
        z=lean; up=np.array([0,0,1.]); x=np.cross(up,z); x/=np.linalg.norm(x); y=np.cross(z,x)
        Rm=np.stack([x,z,y],1)
        prof=[(0.0,-0.03),(0.078,-0.02),(0.095,0.02),(0.090,0.14),(0.075,0.25),(0.045,0.34),(0.0,0.385)]
        lathe_y('ear%+d'%s,prof,14,lambda p,nn: mix(deep(ear,0.08),tint(ear,0.2),0.5+0.5*nn[2]*0.4),centre=tuple(bp-lean*0.012),scale=(1.0,0.50),rotm=Rm.tolist(),sharp=80)
        prof2=[(0.0,0.02),(0.055,0.03),(0.048,0.14),(0.030,0.25),(0.0,0.31)]
        lathe_y('inner%+d'%s,prof2,12,lambda p,nn: mix(inner,tint(inner,0.3),0.4),centre=tuple(bp-lean*0.012),scale=(1.0,0.54),rotm=Rm.tolist(),sharp=80)
        PARTS[-1]['P']=[tuple(np.array(q)+z*0.0+np.array([0,0,0.0])+(np.cross(x,y))*0.0+np.array([0,0,0.0])+np.array([0,0,0.018])) for q in PARTS[-1]['P']]
    return dict(anchor='head_top',slot='head',tags=['cute','sweet'],price=45,title='Bunny-ear headband',
      desc='Headband with two long bunny ears, one floppy. Tall piece (ear tips y~1.7).')

# ============================ SWEATBAND ======================================
def sweatband(main=CREAM,stripe=SKY,**k):
    reset(); segs=32
    y0=lambda phi: 1.045+0.05*math.sin(phi)
    loop=[(0.020,0.0),(0.038,0.008),(0.044,0.026),(0.044,0.070),(0.038,0.088),(0.020,0.096),(0.016,0.048)]
    def col(p,n):
        a=phi_of(p); rib=0.5+0.5*math.cos(70*a); return mix(main,deep(main,0.10),0.25*rib)
    torus('band',segs,lambda phi:[eloop(y0(phi),phi,h,v) for h,v in loop],col)
    for nm,(v0,v1) in (('stripe_a',(0.026,0.040)),('stripe_b',(0.056,0.070))):
        sl=[(0.0435,v0),(0.0475,v0+0.002),(0.0475,v1-0.002),(0.0435,v1)]
        torus(nm,segs,lambda phi,sl=sl:[eloop(y0(phi),phi,h,v) for h,v in sl]+[eloop(y0(phi),phi,0.040,(v0+v1)/2)],lambda p,n: stripe)
    return dict(anchor='head_top',slot='head',tags=['sporty','cool'],price=20,title='Sweatband',
      desc='Terry sweatband with two raised team-colour stripes, worn across the forehead. Bottom edge y>=1.045 at the front, above the brows.')

# ============================ PROPELLER BEANIE ===============================
def propeller_beanie(sky=SKY,pink=PINK,honey=HONEY,mint=MINT,**k):
    reset(); segs=24
    y0=lambda phi: 1.03+0.04*math.sin(phi)
    rows=[('a',0.010,0.006),('a',-0.002,0.024),('a',0.02,0.040),('a',0.07,0.044)]
    for f,o in ((0.0,0.045),(0.25,0.046),(0.5,0.042),(0.75,0.036),(0.92,0.030)): rows.append(('k',f,o))
    rows.append(('pole',0,0.026))
    pan=[pink,sky,honey,mint]
    def col(p,n):
        a=(phi_of(p)+math.pi/4)%(2*math.pi); k=int(a/(math.pi/2))%4
        dy=p[1]-y0(phi_of(p))
        if dy<0.07: return deep(CREAM,0.0)
        return pan[k]
    shell('cap',segs,y0,rows,col)
    ico_part('button',(0,TOP+0.040,0),(0.036,0.030,0.036),honey,sub=1)
    tube_curve('stem',[(0,TOP+0.04,0),(0,TOP+0.085,0)],0.012,6,deep(CREAM,0.15),cap=True)
    ico_part('hub',(0,TOP+0.095,0),(0.026,0.022,0.026),CREAM,sub=1)
    tilt=math.radians(10)
    for k_,(ang,colr) in enumerate(((20,honey),(110,sky))):
        a=math.radians(ang)
        Rm=(Matrix.Rotation(a,3,'Y')@Matrix.Rotation(0.22,3,'X')).to_4x4() if False else None
        R=np.array(rot_y(a))@np.array(rot_z(0.18 if k_==0 else -0.18))
        ico_part(f'blade{k_}',(0,TOP+0.112,0),(0.27,0.014,0.062),lambda p,n,c=colr: mix(deep(c,0.08),tint(c,0.22),0.5+0.5*n[1]),sub=2,rot=R.tolist())
        # blade is symmetric about the hub: two sides in one ellipsoid
    return dict(anchor='head_top',slot='head',tags=['cute','cool'],price=35,title='Propeller beanie',
      desc='Four-panel rainbow beanie with a propeller on a stem (the blades can spin about y at the crown, anchor (0,1.3458+0.095,0)). Rigid.')

# ============================ FLOWER HAIR CLIP ================================
def flower_clip(petal=CORAL,centre=HONEY,leaf=MINT,**k):
    reset()
    phi=math.radians(58); yy=1.10
    p=B.egg_point(yy,phi); n=egg_n(p); x,y,z=axes(n); c=p+n*0.058
    Rm=np.stack([x,y,z],1)
    # clip bar (little barrette) hugging the egg
    pts=[]
    for dp in np.linspace(-0.34,0.34,7):
        q=B.egg_point(yy+0.02*dp*dp*0,phi+dp*0.0+dp*0.0); pass
    bar=[B.egg_point(yy-0.002,phi+d)+egg_n(B.egg_point(yy-0.002,phi+d))*0.022 for d in np.linspace(-0.22,0.22,7)]
    tube_curve('clip',bar,0.011,5,deep(centre,0.15),cap=True)
    for pi_ in range(5):
        a=2*math.pi*pi_/5+0.3
        cen=c+(x*math.cos(a)+y*math.sin(a))*0.068
        R2=np.stack([x*math.cos(a)+y*math.sin(a),-x*math.sin(a)+y*math.cos(a),z],1)
        ico_part(f'petal{pi_}',tuple(cen),(0.070,0.046,0.026),lambda q,nn: mix(deep(petal,0.10),tint(petal,0.2),0.5+0.5*nn[1]*0.5),sub=2,rot=R2.tolist())
    ico_part('heart',tuple(c+z*0.016),(0.040,0.040,0.028),centre,sub=2)
    for s,(ox,oy) in enumerate(((-0.11,-0.07),(0.04,-0.12))):
        ico_part(f'leaf{s}',tuple(c+x*ox+y*oy-z*0.012),(0.055,0.024,0.012),lambda q,nn: mix(deep(leaf,0.25),leaf,0.6),sub=1,rot=np.stack([x*math.cos(0.5+s)+y*math.sin(0.5+s),-x*math.sin(0.5+s)+y*math.cos(0.5+s),z],1).tolist())
    return dict(anchor='head_top',slot='head',tags=['sweet','cute','sparkly'],price=25,title='Flower hair clip',
      desc='One big coral blossom on a barrette, clipped high on the right side of the head (phi=58deg, y=1.10). Mirror x for the other side.')

# ============================ WITCH HAT ======================================
def witch_hat(main=hx('#6E4FA8'),band=CORAL,gold=HONEY,**k):
    reset(); segs=28
    y0=lambda phi: 1.075+0.035*math.sin(phi)
    def lf(phi):
        pts=[(0.026,0.022),(0.12,0.008),(0.205,-0.016),(0.212,-0.032),(0.200,-0.040),(0.12,-0.018),(0.026,-0.004)]
        return [eloop(y0(phi),phi,h,v) for h,v in pts]
    torus('brim',segs,lf,lambda p,n: mix(deep(main,0.16),tint(main,0.1),0.5+0.5*n[1]))
    yb=y0(0)+0.012; apex=np.array([0.0,1.58,-0.14])
    rim=[eloop(y0(2*math.pi*i/segs)+0.012,2*math.pi*i/segs,0.030,0) for i in range(segs)]
    cuts=[0.0,0.10,0.1001,0.16,0.35,0.55,0.75,0.9,1.0]
    def pt(i,j):
        t=cuts[j]; r0=rim[i]; sc=1-t**1.45
        q=np.array([r0[0]*sc, yb+(apex[1]-yb)*t-0.10*t**4, r0[2]*sc-0.16*t**2.2])
        # taper: pull toward the (bent) spine so the tip stays slim
        return q
    def cf(p,n):
        t=(p[1]-yb)/(apex[1]-yb)
        return band if 0.0<=t<0.10 else mix(main,tint(main,0.16),0.5+0.5*n[1]*0.6)
    grid_surface('cone',pt,segs,len(cuts),lambda p,n:(0,0,0),hint=lambda p:(p-np.array([0,1.3,-0.03])),gcol=lambda i,j: band if j<=1 else main) if False else None
    grid_surface('cone',pt,segs,len(cuts),None,hint=lambda p:(p-np.array([0,1.3,-0.03])),gcol=lambda i,j: band if j<=1 else mix(main,tint(main,0.12),min(1,cuts[j])*0.5))
    # gold buckle on the band
    f=rim[segs//4]; n=hdir(f); fp=B.egg_point(yb+0.035,math.pi/2)
    nn=egg_n(fp); x,y,z=axes(nn)
    outer=lib.poly_pts_rounded([(-0.040,-0.040),(0.040,-0.040),(0.040,0.040),(-0.040,0.040)],0.012,arc=2)
    inner=lib.poly_pts_rounded([(-0.022,-0.020),(0.022,-0.020),(0.022,0.020),(-0.022,0.020)],0.006,arc=2)
    slab_part('buckle',outer,0.014,gold,lambda px,py,pz: tuple(fp+nn*(0.054+pz)+x*px+y*py),cuts=0)
    slab_part('buckle_hole',inner,0.012,main,lambda px,py,pz: tuple(fp+nn*(0.066+pz)+x*px+y*py),cuts=0)
    return dict(anchor='head_top',slot='head',tags=['cool','sparkly'],price=50,title='Little witch hat',
      desc='Purple witch hat with a curled tip, coral band and gold buckle. Front brim edge y>=1.07, above the brows. Tall piece.')

REG=[
 ('bucket_hat',bucket_hat,dict(),H),
 ('bucket_hat_pink',bucket_hat,dict(main=PINK,band=CREAM),H),
 ('crown_gold',crown,dict(),H),
 ('chef_hat',chef_hat,dict(),H),
 ('pirate_hat',pirate_hat,dict(),H),
 ('bunny_ears',bunny_ears,dict(),H),
 ('sweatband',sweatband,dict(),H),
 ('propeller_beanie',propeller_beanie,dict(),H),
 ('flower_clip',flower_clip,dict(),H),
 ('witch_hat',witch_hat,dict(),H),
]
