import bpy, bmesh, math, random, json, os
from mathutils import Vector, noise, Matrix

S = os.environ.get("FOOD4_OUT", os.path.join(os.path.dirname(os.path.abspath(__file__)), "out"))   # export/ and renders/ go under here
for _d in ("export", "renders"): os.makedirs(os.path.join(S, _d), exist_ok=True)

def s2l(c): return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def lin(c): return tuple(s2l(x) for x in c)
def mix(a, b, t):
    t = max(0.0, min(1.0, t)); return tuple(a[i]+(b[i]-a[i])*t for i in range(3))
def sstep(a, b, x):
    t = max(0.0, min(1.0, (x-a)/(b-a))); return t*t*(3-2*t)
def nz(p, f=1.0, o=0.0): return noise.noise(Vector((p[0]*f+o, p[1]*f+o*1.3, p[2]*f-o*0.7)))
def rnd_dir(r):
    while True:
        v = Vector((r.uniform(-1,1), r.uniform(-1,1), r.uniform(-1,1)))
        if 0.05 < v.length <= 1: return v.normalized()

PARTS = []   # each: dict(P=[], N=[], C=[], F=[])
def reset(): PARTS.clear()

def commit(bm, color, mods=(), sharp=50, xf=None):
    """bm -> evaluated mesh -> per-loop-split verts with sRGB colour (color: tuple or fn(p, n)->tuple)."""
    me = bpy.data.meshes.new('t'); bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new('t', me); bpy.context.scene.collection.objects.link(ob)
    for typ, kw in mods:
        m = ob.modifiers.new('m', typ)
        for k, v in kw.items(): setattr(m, k, v)
    dg = bpy.context.evaluated_depsgraph_get()
    me2 = bpy.data.meshes.new_from_object(ob.evaluated_get(dg))
    bpy.data.objects.remove(ob); bpy.data.meshes.remove(me)
    if xf is not None: me2.transform(xf)
    b2 = bmesh.new(); b2.from_mesh(me2)
    bmesh.ops.recalc_face_normals(b2, faces=b2.faces[:])
    bmesh.ops.triangulate(b2, faces=b2.faces[:])
    for e in b2.edges:
        e.smooth = not (len(e.link_faces) == 2 and e.calc_face_angle(0.0) > math.radians(sharp))
    for f in b2.faces: f.smooth = True
    b2.to_mesh(me2); b2.free()
    me2.update()
    part = dict(P=[], N=[], C=[], F=[]); idx = {}
    vn = [v.normal.copy() for v in me2.vertices]
    cn = me2.corner_normals
    for poly in me2.polygons:
        tri = []
        for li in poly.loop_indices:
            vi = me2.loops[li].vertex_index
            n = Vector(cn[li].vector).normalized()
            key = (vi, round(n.x, 2), round(n.y, 2), round(n.z, 2))
            if key not in idx:
                p = me2.vertices[vi].co.copy()
                c = color(p, vn[vi]) if callable(color) else color
                idx[key] = len(part['P'])
                part['P'].append(tuple(p)); part['N'].append(tuple(n)); part['C'].append(tuple(c))
            tri.append(idx[key])
        part['F'].append(tuple(tri))
    bpy.data.meshes.remove(me2)
    PARTS.append(part); print('PART', len(PARTS), len(part['F']))
    return part

def tri_count(): return sum(len(p['F']) for p in PARTS)

def merged():
    P=[];N=[];C=[];F=[]
    for p in PARTS:
        o=len(P); P+=p['P']; N+=p['N']; C+=p['C']; F+=[(a+o,b+o,c+o) for a,b,c in p['F']]
    return P,N,C,F

def xf_rt(loc=(0,0,0), rotz=0.0, rotx=0.0, roty=0.0, scale=(1,1,1)):
    m = Matrix.Translation(loc) @ Matrix.Rotation(rotz,4,'Z') @ Matrix.Rotation(roty,4,'Y') @ Matrix.Rotation(rotx,4,'X')
    return m @ Matrix.Diagonal((scale[0],scale[1],scale[2],1.0))

# ---- bmesh builders -------------------------------------------------------
def lathe(profile, segs, cap_axis=True, closed_top=False):
    """profile [(r,z)...] bottom to top; revolve about z."""
    bm = bmesh.new(); rings = []
    for (r, z) in profile:
        if r < 1e-6:
            rings.append([bm.verts.new((0, 0, z))]*segs)
        else:
            rings.append([bm.verts.new((r*math.cos(2*math.pi*i/segs), r*math.sin(2*math.pi*i/segs), z)) for i in range(segs)])
    for k in range(len(profile)-1):
        for i in range(segs):
            j = (i+1) % segs
            vs = [rings[k][i], rings[k][j], rings[k+1][j], rings[k+1][i]]
            u = []
            for v in vs:
                if v not in u: u.append(v)
            if len(u) >= 3:
                try: bm.faces.new(u)
                except ValueError: pass
    return bm

def poly_pts_rounded(tri, rad, arc=4):
    """rounded polygon outline (list of 2D tuples, ccw) for a convex polygon."""
    n = len(tri); out = []
    for i in range(n):
        p0 = Vector(tri[i-1]); p1 = Vector(tri[i]); p2 = Vector(tri[(i+1) % n])
        a = (p0-p1).normalized(); b = (p2-p1).normalized()
        ang = math.acos(max(-1,min(1,a.dot(b))))
        d = rad/math.tan(ang/2)
        d = min(d, (p0-p1).length*0.48, (p2-p1).length*0.48)
        r = d*math.tan(ang/2)
        c = p1 + (a+b).normalized()*(r/math.sin(ang/2))
        s = p1 + a*d; e = p1 + b*d
        a0 = math.atan2(s.y-c.y, s.x-c.x); a1 = math.atan2(e.y-c.y, e.x-c.x)
        da = (a1-a0+math.pi) % (2*math.pi) - math.pi
        for k in range(arc+1):
            t = a0 + da*k/arc
            out.append((c.x+r*math.cos(t), c.y+r*math.sin(t)))
    return out

def slab(poly, z0, z1, cuts=1):
    """closed prism from a 2D outline (triangulated + subdivided top & bottom)."""
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z0)) for x, y in poly]
    f = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[f])
    for _ in range(cuts):
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1, use_grid_fill=True)
        bmesh.ops.triangulate(bm, faces=bm.faces[:])
    r = bmesh.ops.extrude_face_region(bm, geom=bm.faces[:])
    bmesh.ops.translate(bm, vec=(0, 0, z1-z0), verts=[v for v in r['geom'] if isinstance(v, bmesh.types.BMVert)])
    return bm

def displace(bm, fn):
    bm.normal_update()
    for v in bm.verts:
        d = fn(v.co.copy(), v.normal.copy())
        if d is not None: v.co += v.normal*d if not isinstance(d, Vector) else d

def move(bm, fn):
    for v in bm.verts:
        v.co = Vector(fn(v.co.copy()))

def ico(subdiv=2, radius=1.0):
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=subdiv, radius=radius); return bm

def tube(p0, p1, rad, sides, color, ends=True, taper=1.0, mods=()):
    p0 = Vector(p0); p1 = Vector(p1); d = (p1-p0)
    L = d.length; d.normalize()
    a = Vector((0,0,1)) if abs(d.z) < 0.9 else Vector((1,0,0))
    u = d.cross(a).normalized(); v = d.cross(u).normalized()
    bm = bmesh.new(); rings = []
    for (t, sc) in [(0, taper), (1, 1.0)] if False else [(0.0, 0.6), (0.1, 1.0), (0.9, 1.0), (1.0, 0.6)]:
        c = p0 + d*L*t
        rings.append([bm.verts.new(c + (u*math.cos(2*math.pi*i/sides) + v*math.sin(2*math.pi*i/sides))*rad*sc) for i in range(sides)])
    for k in range(3):
        for i in range(sides):
            j = (i+1) % sides
            bm.faces.new([rings[k][i], rings[k][j], rings[k+1][j], rings[k+1][i]])
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[3])
    return commit(bm, color, mods=mods, sharp=60)
