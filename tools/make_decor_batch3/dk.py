"""Decor kit (batch 3): Blender (bpy) soft-toy props in GAME coordinates (y up, +z toward the camera, origin = footprint centre on the floor).
Parts with pivot / material / per-vertex w; exports OBJ+JSON in the format tools/convert_decor_art.py reads."""
import sys, os, math, json
sys.path.insert(0, "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gi/wear_art/work")
import bpy, bmesh
import numpy as np
from mathutils import Vector, Matrix
import lib
from lib import lin, mix, sstep

OUT = "/private/tmp/claude-501/-Users-dmarshall94-Desktop-BobV1/9cd2e159-911b-4a04-879f-e5e34721a64a/scratchpad/gi/decor_art/export"
def hx(h): return tuple(int(h[i:i+2], 16)/255 for i in (1, 3, 5))
CREAM=hx('#F7F0E0'); INK=hx('#4D331F'); SKY=hx('#6EB3D1'); PINK=hx('#E98AA4'); HONEY=hx('#F9CC59'); MINT=hx('#9FD9B0'); LAV=hx('#B9A3E6'); CORAL=hx('#F58B6E')
WOOD=hx('#D9A066'); WOOD2=hx('#B97A47'); TERRA=hx('#D9825B'); LEAF=hx('#6FBF7B'); LEAF2=hx('#4E9A5E'); WATER=hx('#8FD0E8'); SAND=hx('#F0DDB0'); WHITE=(1,1,1)
def tint(c,k): return mix(c,(1,1,1),k)
def deep(c,k=0.25): return mix(c,INK,k)
def lit(c,k=0.18,d=0.12):
    return lambda p,n: mix(deep(c,d),tint(c,k),0.5+0.5*n.y*0.7)

GROUPS = []      # [name, pivot, material, wfn, [parts]]
CUR = None
def reset(): GROUPS.clear()
def begin(name, pivot=(0,0,0), material=0, w=None):
    global CUR
    CUR = dict(name=name, pivot=tuple(pivot), material=material, w=w, parts=[]); GROUPS.append(CUR)
def commit(bm, color, mods=(), sharp=50, xf=None):
    p = lib.commit(bm, color, mods=mods, sharp=sharp, xf=xf); lib.PARTS.pop(); CUR['parts'].append(p); return p
BEV = lambda w, seg=3: [('BEVEL', dict(width=w, segments=seg, limit_method='ANGLE', angle_limit=math.radians(35)))]

# ---- bmesh primitives (size baked in; placement via xf) ----
def T(loc=(0,0,0), rx=0, ry=0, rz=0): return Matrix.Translation(loc) @ Matrix.Rotation(rz,4,'Z') @ Matrix.Rotation(ry,4,'Y') @ Matrix.Rotation(rx,4,'X')
def box_bm(sx, sy, sz):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts: v.co = Vector((v.co.x*sx, v.co.y*sy, v.co.z*sz))
    return bm
def sph_bm(rx, ry, rz, sub=3):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    for v in bm.verts: v.co = Vector((v.co.x*rx, v.co.y*ry, v.co.z*rz))
    return bm
def sgn(v, e): return math.copysign(abs(v)**e, v)
def pill_bm(rx, ry, rz, e=0.6, sub=3):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    for v in bm.verts:
        d = v.co.normalized(); v.co = Vector((rx*sgn(d.x,e), ry*sgn(d.y,e), rz*sgn(d.z,e)))
    return bm
def lathe_bm(profile, segs=24, scale=(1,1)):
    """profile [(r,y)...] bottom to top revolved about y (r=0 = pole)."""
    bm = bmesh.new(); rings = []
    for r, y in profile:
        if r < 1e-6: rings.append([bm.verts.new((0, y, 0))]*segs)
        else: rings.append([bm.verts.new((r*math.cos(2*math.pi*i/segs)*scale[0], y, r*math.sin(2*math.pi*i/segs)*scale[1])) for i in range(segs)])
    for k in range(len(profile)-1):
        for i in range(segs):
            j = (i+1) % segs; vs = [rings[k][i], rings[k][j], rings[k+1][j], rings[k+1][i]]; u = []
            for v in vs:
                if v not in u: u.append(v)
            if len(u) >= 3:
                try: bm.faces.new(u)
                except ValueError: pass
    return bm
def cyl_bm(r, h, segs=28, y0=0.0): return lathe_bm([(0,y0),(r,y0),(r,y0+h),(0,y0+h)], segs)
def tube_bm(pts, rad, sides=8, radfn=None, cap=True, closed=False):
    pts = [Vector(p) for p in pts]; n = len(pts); bm = bmesh.new(); rings = []; prev = None
    for k, p in enumerate(pts):
        d = (pts[min(k+1,n-1)] - pts[max(k-1,0)]).normalized()
        if prev is None:
            ref = Vector((0,1,0)) if abs(d.y) < 0.9 else Vector((1,0,0)); u = d.cross(ref)
        else: u = prev - d*prev.dot(d)
        u.normalize(); v = d.cross(u); prev = u
        r = radfn(k/(n-1)) if radfn else rad
        rings.append([bm.verts.new(p + (u*math.cos(2*math.pi*i/sides) + v*math.sin(2*math.pi*i/sides))*r) for i in range(sides)])
    for k in range(n if closed else n-1):
        k2 = (k+1) % n
        for i in range(sides):
            j = (i+1) % sides; bm.faces.new([rings[k][i], rings[k][j], rings[k2][j], rings[k2][i]])
    if cap and not closed:
        bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    return bm
def slab_bm(poly, thick):
    """2D outline (x,y) extruded 0..thick along +z."""
    return lib.slab(poly, 0.0, thick, cuts=0)
# ---- shorthand adders ----
def add_box(c, size, color, bevel=0.03, rot=(0,0,0), seg=3, sharp=40):
    return commit(box_bm(*size), color, mods=BEV(bevel, seg) if bevel else (), sharp=sharp, xf=T(c, *rot))
def add_pill(c, r, color, e=0.6, rot=(0,0,0), sub=2):
    return commit(pill_bm(r[0], r[1], r[2], e, sub), color, sharp=80, xf=T(c, *rot))
def add_sph(c, r, color, rot=(0,0,0), sub=2):
    r = (r, r, r) if not isinstance(r, (tuple, list)) else r
    return commit(sph_bm(r[0], r[1], r[2], sub), color, sharp=90, xf=T(c, *rot))
def add_lathe(c, profile, color, segs=28, scale=(1,1), rot=(0,0,0), sharp=60):
    return commit(lathe_bm(profile, segs, scale), color, sharp=sharp, xf=T(c, *rot))
def add_cyl(c, r, h, color, rot=(0,0,0), segs=28, bevel=0.015, centered=False):
    bm = cyl_bm(r, h, segs, y0=-h/2 if centered else 0.0)
    return commit(bm, color, mods=BEV(bevel, 2) if bevel else (), sharp=50, xf=T(c, *rot))
def add_tube(pts, rad, color, sides=8, radfn=None, cap=True, closed=False):
    return commit(tube_bm(pts, rad, sides, radfn, cap, closed), color, sharp=70)
def add_slab(poly, thick, color, xf, bevel=0.006):
    return commit(slab_bm(poly, thick), color, mods=BEV(bevel, 2) if bevel else (), sharp=40, xf=xf)

# ---- export ----
def export(iid, meta):
    P=[]; N=[]; C=[]; W=[]; groups=[]
    for g in GROUPS:
        o = len(P); nf = 0
        for p in g['parts']:
            base = len(P) - o
            for q, n, c in zip(p['P'], p['N'], p['C']):
                P.append(q); N.append(n); C.append(c); W.append(g['w'](Vector(q)) if g['w'] else 0.0)
        faces = []; off = o
        for p in g['parts']:
            faces += [(a+off, b+off, c+off) for a, b, c in p['F']]; off += len(p['P'])
        groups.append((g['name'], g['pivot'], g['material'], faces))
    P = np.array(P); Nn = np.array(N)
    y = P[:,1]; ao = 0.60 + 0.40*np.vectorize(lambda t: sstep(0, 0.40, t))(y)
    ao = ao*(0.88 + 0.12*(Nn[:,1]*0.5+0.5)); ao = np.clip(ao, 0.5, 1.0)
    os.makedirs(OUT, exist_ok=True)
    with open(f"{OUT}/{iid}.obj", "w") as fh:
        fh.write(f"# {iid}: game coordinates (y up, +z toward the camera, origin = footprint centre on the floor). v x y z r g b ao w (rgb LINEAR)\n")
        for q, c, a, w in zip(P, C, ao, W): fh.write("v %.5f %.5f %.5f %.4f %.4f %.4f %.3f %.3f\n" % (*q, *lin(c), a, w))
        for n in Nn: fh.write("vn %.4f %.4f %.4f\n" % tuple(n))
        for name, piv, mat, faces in groups:
            fh.write(f"o {name}\n")
            for a, b, c in faces: fh.write("f %d//%d %d//%d %d//%d\n" % (a+1,a+1,b+1,b+1,c+1,c+1))
    mn = P.min(0); mx = P.max(0)
    info = dict(id=iid, tris=sum(len(g[3]) for g in groups), verts=len(P),
                sub_meshes=[dict(name=n, pivot=[round(float(x),4) for x in piv], material=("lamp" if mat == 5 else "plain"), tris=len(f)) for n, piv, mat, f in groups],
                bounds_min=[round(float(x),4) for x in mn], bounds_max=[round(float(x),4) for x in mx], anchor_rest=[0,0,0])
    info.update(meta)
    json.dump(info, open(f"{OUT}/{iid}.json", "w"), indent=1)
    return info
