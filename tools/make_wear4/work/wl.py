"""Wearable kit. All geometry is authored in the Jelly's REST space (y up, floor y=0, +z = face, world units), like EyeMaskModel.
Parts are kept in lib.PARTS (name tagged). Export: local = rest - anchor_rest."""
import sys, os
HERE=os.path.dirname(os.path.abspath(__file__)); W=os.path.join(HERE,"..","art")
sys.path.insert(0, HERE)
import bpy, bmesh, math, json, random
import numpy as np
from mathutils import Vector, Matrix, noise
import lib
from lib import lin, mix, sstep, nz, PARTS, reset, tri_count
import body as B

def hx(h): return tuple(int(h[i:i+2],16)/255 for i in (1,3,5))
CREAM=hx('#F7F0E0'); INK=hx('#4D331F'); SKY=hx('#6EB3D1'); PINK=hx('#E98AA4'); HONEY=hx('#F9CC59'); MINT=hx('#9FD9B0')
LAV=hx('#B9A3E6'); CORAL=hx('#F58B6E'); WHITE=(1,1,1)
def shade(c,k): return tuple(max(0,min(1,x*k)) for x in c)
def tint(c,k): return mix(c,(1,1,1),k)
def deep(c,k=0.25): return mix(c,INK,k)

# ---------- generic part makers ------------------------------------------------
def _norm_from_faces(P,F):
    P=np.asarray(P); N=np.zeros_like(P)
    for a,b,c in F:
        n=np.cross(P[b]-P[a],P[c]-P[a]); N[a]+=n;N[b]+=n;N[c]+=n
    L=np.linalg.norm(N,axis=1,keepdims=True); return N/np.maximum(L,1e-12)

def add_part(name,P,F,color,N=None,hint=None,flip_auto=True):
    """Open or closed mesh (rest space). color: rgb or fn(p,n)->rgb. hint: fn(p)->outward dir used to orient normals/winding."""
    P=[tuple(map(float,p)) for p in P]; F=[tuple(f) for f in F]
    Nn=_norm_from_faces(P,F)
    if hint is not None and flip_auto:
        h=np.array([hint(np.array(p)) for p in P]); s=(Nn*h).sum(1).sum()
        if s<0: F=[(a,c,b) for a,b,c in F]; Nn=-Nn
    if N is not None: Nn=np.asarray(N)
    C=list(color) if isinstance(color,list) else [(color(np.array(p),n) if callable(color) else color) for p,n in zip(P,Nn)]
    part=dict(name=name,P=P,N=[tuple(n) for n in Nn],C=[tuple(c) for c in C],F=F)
    PARTS.append(part); return part

def closed(bm,color,name,mods=(),sharp=50):
    p=lib.commit(bm,color,mods=mods,sharp=sharp); p['name']=name; return p

def grid_surface(name,fn,nu,nv,color,closed_u=True,hint=None,pole_top=False,pole_bot=False,gcol=None):
    """fn(i,j)->rest point; i in 0..nu-1 (around, wraps if closed_u) j in 0..nv-1 (profile)."""
    P=[];idx={}
    for j in range(nv):
        for i in range(nu):
            idx[(i,j)]=len(P); P.append(fn(i,j))
    F=[]
    for j in range(nv-1):
        for i in range(nu if closed_u else nu-1):
            i2=(i+1)%nu
            a,b,c,d=idx[(i,j)],idx[(i2,j)],idx[(i2,j+1)],idx[(i,j+1)]
            F+=[(a,b,c),(a,c,d)]
    # weld coincident verts (poles), drop degenerate faces
    key={};remap=[];Q=[];Cq=[]
    for vi,p in enumerate(P):
        k=tuple(np.round(p,6))
        if k not in key:
            key[k]=len(Q);Q.append(p)
            if gcol is not None: Cq.append(gcol(vi%nu,vi//nu))
        remap.append(key[k])
    F2=[]
    for a,b,c in F:
        a,b,c=remap[a],remap[b],remap[c]
        if a!=b and b!=c and a!=c: F2.append((a,b,c))
    return add_part(name,Q,F2,(Cq if gcol is not None else color),hint=hint)

def ico_part(name,centre,radii,color,sub=1,rot=None,fuzz=0.0,seed=0,hint=None):
    bm=bmesh.new(); bmesh.ops.create_icosphere(bm,subdivisions=sub,radius=1.0)
    rr=random.Random(seed)
    for v in bm.verts:
        d=v.co.copy().normalized(); k=1+fuzz*(rr.uniform(-1,1))
        v.co=Vector((d.x*radii[0]*k,d.y*radii[1]*k,d.z*radii[2]*k))
    if rot is not None:
        m=Matrix(rot).to_4x4() if not isinstance(rot,Matrix) else rot
        bmesh.ops.transform(bm,matrix=m,verts=bm.verts)
    bmesh.ops.translate(bm,vec=Vector(centre),verts=bm.verts)
    return closed(bm,color,name,sharp=179)

def lathe_y(name,profile,segs,color,centre=(0,0,0),scale=(1,1),rotm=None,sharp=60,fuzz=None):
    """profile [(r,y)...] bottom->top, revolved about y; elliptical via scale=(sx,sz). closed (poles at r=0)."""
    bm=bmesh.new(); rings=[]
    for r,y in profile:
        if r<1e-6: rings.append([bm.verts.new((0,y,0))]*segs)
        else: rings.append([bm.verts.new((r*math.cos(2*math.pi*i/segs)*scale[0],y,r*math.sin(2*math.pi*i/segs)*scale[1])) for i in range(segs)])
    for k in range(len(profile)-1):
        for i in range(segs):
            j=(i+1)%segs; vs=[rings[k][i],rings[k][j],rings[k+1][j],rings[k+1][i]]
            u=[]
            for v in vs:
                if v not in u: u.append(v)
            if len(u)>=3:
                try: bm.faces.new(u)
                except ValueError: pass
    # cap open ends
    for ring in (rings[0],rings[-1]):
        if len(set(ring))>2:
            try: bm.faces.new(ring)
            except ValueError: pass
    if rotm is not None: bmesh.ops.transform(bm,matrix=Matrix(rotm).to_4x4(),verts=bm.verts)
    bmesh.ops.translate(bm,vec=Vector(centre),verts=bm.verts)
    return closed(bm,color,name,sharp=sharp)

def tube_curve(name,pts,rad,sides,color,cap=True,radfn=None,flat=1.0,hint=None):
    """tube along polyline pts (rest). radius rad or radfn(t)."""
    pts=[np.array(p,float) for p in pts]; n=len(pts); P=[]; F=[]
    prev_u=None
    for k,p in enumerate(pts):
        d=(pts[min(k+1,n-1)]-pts[max(k-1,0)]); d/=np.linalg.norm(d)+1e-12
        if prev_u is None:
            ref=np.array([0,1,0.]) if abs(d[1])<0.9 else np.array([1,0,0.])
            u=np.cross(d,ref)
        else: u=prev_u-d*np.dot(prev_u,d)
        if np.linalg.norm(u)<1e-6: u=np.cross(d,np.array([0,0,1.]))
        u/=np.linalg.norm(u); v=np.cross(d,u); prev_u=u
        r=radfn(k/(n-1)) if radfn else rad
        for i in range(sides):
            a=2*math.pi*i/sides; P.append(p+(u*math.cos(a)+v*math.sin(a)*flat)*r)
    for k in range(n-1):
        for i in range(sides):
            j=(i+1)%sides; a,b,c,d=k*sides+i,k*sides+j,(k+1)*sides+j,(k+1)*sides+i; F+=[(a,b,c),(a,c,d)]
    if cap:
        for ring,rev in ((0,True),(n-1,False)):
            c=len(P); P.append(pts[ring]); base=ring*sides
            for i in range(sides):
                j=(i+1)%sides; F.append((c,base+j,base+i) if rev else (c,base+i,base+j))
    ctr=np.mean(pts,0)
    # orientation: outward from curve axis -> use sign of signed volume
    part=add_part(name,P,F,color,flip_auto=False)
    vol=sum(np.dot(np.array(part['P'][a]),np.cross(np.array(part['P'][b]),np.array(part['P'][c]))) for a,b,c in F)
    if vol<0:
        part['F']=[(a,c,b) for a,b,c in part['F']]; part['N']=[tuple(-np.array(x)) for x in part['N']]
    return part

def slab_part(name,poly,thick,color,xf,cuts=1,rounded=0.0,sharp=40):
    """2D outline (x,y) extruded 0..thick along z, then xf(x,y,z)->rest point per vertex."""
    bm=lib.slab(poly,0.0,thick,cuts=cuts)
    for v in bm.verts: v.co=Vector(xf(v.co.x,v.co.y,v.co.z))
    return closed(bm,color,name,sharp=sharp)

def star_poly(R,r,n=5,rot=math.pi/2,rad=0.012):
    pts=[]
    for i in range(2*n):
        a=rot+math.pi*i/n; rr=R if i%2==0 else r; pts.append((rr*math.cos(a),rr*math.sin(a)))
    return lib.poly_pts_rounded(pts,rad,arc=3)

def rot_x(a): return Matrix.Rotation(a,3,'X')
def rot_y(a): return Matrix.Rotation(a,3,'Y')
def rot_z(a): return Matrix.Rotation(a,3,'Z')

# ---------- body-surface helpers --------------------------------------------------
def egg_n(p): return B.egg_grad(np.array(p,float))
def full_n(p): return B.grad(np.array(p,float))
def shell_pt(y,phi,off,dy=0.0):
    p=B.egg_point(y,phi); n=egg_n(p); return p+n*off+np.array([0,dy,0])
def body_pt(x,y,off,mirror=False):
    """front surface of the WHOLE body (arms and fillets included) at (x,y) pushed `off` along its normal."""
    p=B.front_surface(x,y); n=full_n(p); return p+n*off, n
def squash_face_hint(p): return egg_n(p)

# ---------- scene transforms -------------------------------------------------
def post_transform(rot3=None, trans=(0,0,0), pivot=(0,0,0)):
    """rotate all current PARTS about pivot then translate (rest space)."""
    R=np.array(rot3 if rot3 is not None else np.eye(3)); pv=np.array(pivot); tr=np.array(trans)
    for p in PARTS:
        p['P']=[tuple(R@(np.array(x)-pv)+pv+tr) for x in p['P']]
        p['N']=[tuple(R@np.array(n)) for n in p['N']]

def autofit(min_clear=0.004, step=0.004, direction=(0,1,0), maxit=60, skip=()):
    """Move all parts along `direction` until no vertex is inside the body (sdf >= min_clear); returns total shift."""
    d=np.array(direction,float); d/=np.linalg.norm(d); tot=0
    for _ in range(maxit):
        m=min(float(B.sdf_pts(np.array(p['P'])).min()) for p in PARTS if p['name'] not in skip)
        if m>=min_clear: break
        for p in PARTS: p['P']=[tuple(np.array(x)+d*step) for x in p['P']]
        tot+=step
    return tot

def srgb_lin(c): return lin(c)

# ---------- export ------------------------------------------------------------
def export(item_id, anchor_rest, meta, outdir=W+"/export", ao_body=True, mirror_ready=True):
    ar=np.array(anchor_rest,float); sub=np.zeros(3) if meta.get('authored_local') else ar; allP=[];allN=[];allC=[];allF=[];groups=[]
    for p in PARTS:
        o=len(allP); P=np.array(p['P'])-sub; allP+=list(P); allN+=p['N']; allC+=p['C']
        allF+=[(a+o,b+o,c+o) for a,b,c in p['F']]; groups.append((p['name'],o,len(p['F']),len(p['P'])))
    Pabs=np.array(allP)+sub
    if meta.get('authored_local') or meta.get('anchor')=='number': ao_body=False
    sd=B.sdf_pts(Pabs) if ao_body else np.ones(len(Pabs))
    ao=0.6+0.4*np.clip(sd/0.09,0,1); ao=np.where(np.array([0]*len(ao))==1,1,ao)
    # parts that have nothing to do with the body (gloves' far side etc.) just get mild ao; fine.
    os.makedirs(outdir,exist_ok=True)
    with open(f"{outdir}/{item_id}.obj","w") as fh:
        fh.write(f"# {item_id}: REST space local to anchor '{meta['anchor']}' (y up, +z face, world units). v x y z r g b ao w  (rgb LINEAR, w = RoomMaterial.plain = 0)\n")
        for p,c,a in zip(allP,allC,ao): fh.write("v %.5f %.5f %.5f %.4f %.4f %.4f %.3f 0\n"%(*p,*lin(c),a))
        for n in allN: fh.write("vn %.4f %.4f %.4f\n"%tuple(n))
        # faces per part group
        fo=0
        for name,vo,nf,nv in groups:
            fh.write(f"o {name}\n")
            for a,b,c in allF[fo:fo+nf]: fh.write("f %d//%d %d//%d %d//%d\n"%(a+1,a+1,b+1,b+1,c+1,c+1))
            fo+=nf
    mn=np.array(allP).min(0); mx=np.array(allP).max(0)
    info=dict(id=item_id,tris=len(allF),verts=len(allP),parts=[dict(name=n,tris=nf,verts=nv) for n,vo,nf,nv in groups],
              anchor_rest=[round(float(x),4) for x in ar],
              bounds_local_min=[round(float(x),4) for x in mn],bounds_local_max=[round(float(x),4) for x in mx],
              size=[round(float(x),4) for x in (mx-mn)])
    info.update(meta)
    json.dump(info,open(f"{outdir}/{item_id}.json","w"),indent=1)
    return info
