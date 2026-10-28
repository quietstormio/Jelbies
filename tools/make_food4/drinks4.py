"""Store sweep 4 (drinks): boba milk tea, berry smoothie, pink lemonade, hot cocoa.
Run:  FOOD4_OUT=<dir> Blender -b -P drinks4.py
For each drink writes (game units, y up, origin = centre of the cup base, NOT shifted):
  <id>_shell.obj   the cup / glass body (drawn translucent by the game, opaque for the mug)
  <id>_deco.obj    static opaque parts: pearls, label band, lids, handle, fruit on the rim
  <id>_float.obj   opaque parts that ride the liquid surface (marshmallows, berries)       -> moved by (level - fullLevel)
  <id>_ice.obj     translucent parts that ride the surface (ice cubes, foam)               -> moved the same
  <id>.json        inner wall profile for the game's liquid column, levels, liquid colours
Then tools/convert_food_art.py turns each .obj into food_<name>.bin. The liquid column itself is built in Swift (it must follow the sips)."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
from foods4 import blob, sweep, subdiv, BEV
import foods
V = Vector

def grab():
    P, N, C, F = merged(); reset(); return P, N, C, F

def write(name, data):
    P, N, C, F = data
    if not F: return
    G = [(p[0]*0.1, p[2]*0.1, -p[1]*0.1) for p in P]
    GN = [(n[0], n[2], -n[1]) for n in N]
    with open(f"{S}/export/{name}.obj", "w") as fh:
        fh.write(f"# {name}: game units, y up, origin = centre of the cup base\n")
        for g, c in zip(G, C): fh.write("v %.5f %.5f %.5f %.4f %.4f %.4f\n" % (*g, *lin(c)))
        for n in GN: fh.write("vn %.4f %.4f %.4f\n" % n)
        for a, b, c in F: fh.write("f %d//%d %d//%d %d//%d\n" % (a+1, a+1, b+1, b+1, c+1, c+1))
    json.dump(dict(id=name, tris=len(F), verts=len(G)), open(f"{S}/export/{name}.json", "w"))
    print("EXPORT", name, len(F), "tris", len(G), "verts")

def closed_cup(outer, inner, segs=40):
    """outer / inner: lists of (r, z) bottom to top. Closed solid: outside up, over the rim, inside down to the axis."""
    prof = list(outer) + [(o[0]-0.0, o[1]) for o in []] + list(reversed(inner))
    return lathe(prof, segs)

# ------------------------------------------------------------------ BOBA
def boba():
    H = 3.0
    outer = [(0, 0), (0.78, 0), (0.88, 0.07), (1.10, 2.95), (1.16, 3.0)]
    inner = [(0.0, 0.14), (0.80, 0.14), (1.04, 2.9), (1.10, 3.0)]
    commit(closed_cup(outer, inner, 40), (0.9, 0.96, 1.0), sharp=70)
    shell = grab()
    # deco: a pink label band with white dots, a rolled rim ring, the pearls resting at the bottom
    def r_out(z): return 0.88 + (z-0.07)/(2.95-0.07)*(1.10-0.88)
    zs = [1.75 + 0.02*k for k in range(0, 41)]
    bm = lathe([(r_out(z)+0.035, z) for z in zs], 120)
    def bc(p, n):
        a = math.atan2(p.y, p.x); u = (a/(2*math.pi))*12; v = (p.z-1.75)/0.8*2.0
        row = math.floor(v); uu = u + (0.5 if row % 2 else 0.0)
        du = (uu - math.floor(uu)) - 0.5; dv = (v - row) - 0.5
        return (1.0, 0.98, 0.96) if du*du*1.0 + dv*dv*0.9 < 0.05 else (1.0, 0.62, 0.76)
    commit(bm, bc, sharp=70)
    commit(lathe([(1.10, 2.93), (1.19, 2.95), (1.20, 3.05), (1.12, 3.08), (1.05, 3.0)], 40), (1.0, 0.72, 0.82), sharp=60)
    r = random.Random(4)
    pearls = []
    layers = [(0.19, 0.55, 9), (0.19, 0.85, 7), (0.19, 1.16, 5)]
    tries = 0
    for (rad, z, cnt) in layers:
        placed = 0
        while placed < cnt and tries < 4000:
            tries += 1
            a = r.uniform(0, 6.28); rd = (0.80 + 0.2*(z/3.0))*0.78*math.sqrt(r.uniform(0, 1))
            x, y = rd*math.cos(a), rd*math.sin(a)
            if all((x-q[0])**2 + (y-q[1])**2 + (z-q[2])**2 > (2*rad*0.95)**2 for q in pearls):
                pearls.append((x, y, z)); placed += 1
    for (x, y, z) in pearls:
        bm = ico(2, 0.19)
        commit(bm, lambda p, n: mix((0.17, 0.10, 0.09), (0.34, 0.22, 0.17), sstep(0.2, 1.0, n.z)*0.6 + sstep(0.2, 1.0, n.y)*0.2), sharp=80, xf=xf_rt((x, y, z)))
    deco = grab()
    # float parts: none opaque; the foam cap (translucent) rides the surface
    bm = lathe([(0, 0), (0.96, 0), (1.0, 0.03), (0.96, 0.10), (0.0, 0.12)], 36)
    commit(bm, lambda p, n: (1.0, 0.96, 0.88), sharp=70, xf=xf_rt((0, 0, 2.5)))
    ice = grab()
    return dict(id="boba", shell=shell, deco=deco, float=None, ice=ice,
                wall=[(0.0, 0.14), (0.80, 0.14), (1.04, 2.9)], full=2.50, empty=0.50, top=3.0, rim=1.04, opaque=False,
                color=(0.86, 0.66, 0.44), surface=(0.92, 0.74, 0.52), alpha=0.82, shell_alpha=0.30, ice_alpha=0.75, float_scale=1.0)

# ------------------------------------------------------------------ SMOOTHIE
def smoothie():
    outer = [(0, 0), (0.95, 0), (1.05, 0.08), (1.14, 0.3), (1.14, 2.7), (1.1, 2.76)]
    inner = [(0.0, 0.2), (0.90, 0.2), (1.02, 0.34), (1.04, 2.7)]
    commit(closed_cup(outer, inner, 40), (0.88, 0.96, 1.0), sharp=70)
    shell = grab()
    # screw-band ring near the top (mason jar), and a strawberry perched on the rim with a leaf
    commit(lathe([(1.08, 2.45), (1.20, 2.47), (1.22, 2.72), (1.12, 2.78), (1.08, 2.76)], 40), (0.62, 0.84, 0.90), sharp=60)
    # strawberry on the rim
    bm = ico(3); move(bm, lambda p: (p.x*0.34*(0.62+0.38*(p.z+1)/2), p.y*0.34*(0.62+0.38*(p.z+1)/2), p.z*0.38))
    commit(bm, lambda p, n: (0.92, 0.14, 0.22) if nz(p, 40.0, 2) < 0.3 else (1.0, 0.88, 0.5), sharp=80, xf=xf_rt((0.0, 1.08, 2.62), rotx=0.0, rotz=0.4))
    commit(blob(0.18, 0.18, 0.05, 2), (0.38, 0.72, 0.30), sharp=80, xf=xf_rt((0.0, 1.08, 3.00), rotz=0.4))
    deco = grab()
    # blueberries floating on the surface
    for (x, y) in [(-0.40, 0.18), (0.10, -0.44), (0.42, 0.22)]:
        commit(ico(3, 0.17), lambda p, n: (0.30, 0.34, 0.74) if n.z < 0.9 else (0.2, 0.2, 0.45), sharp=80, xf=xf_rt((x, y, 2.45)))
    # a swirl of cream (a small dollop)
    commit(lathe([(0, 0.0), (0.22, 0.0), (0.2, 0.08), (0.14, 0.14), (0.1, 0.2), (0.0, 0.26)], 14), (1.0, 0.97, 0.94), sharp=80, xf=xf_rt((0.0, 0.05, 2.38)))
    flt = grab()
    return dict(id="smoothie", shell=shell, deco=deco, float=flt, ice=None,
                wall=[(0.0, 0.2), (0.90, 0.2), (1.02, 0.34), (1.04, 2.7)], full=2.35, empty=0.55, top=2.7, rim=1.04, opaque=True,
                color=(0.92, 0.38, 0.58), surface=(0.98, 0.52, 0.70), alpha=1.0, shell_alpha=0.30, ice_alpha=1.0, float_scale=1.0)

# ------------------------------------------------------------------ LEMONADE
def lemonade():
    outer = [(0, 0), (0.80, 0), (0.90, 0.10), (1.10, 2.7), (1.14, 2.76)]
    inner = [(0.0, 0.32), (0.76, 0.32), (1.0, 2.7), (1.06, 2.78)]
    commit(closed_cup(outer, inner, 40), (0.92, 0.97, 1.0), sharp=70)
    shell = grab()
    # a lemon wheel hooked on the rim, a mint sprig
    R = 0.72
    bm = lathe([(0.0, 0.0), (R, 0.0), (R+0.05, 0.04), (R, 0.08), (0.0, 0.08)], 28)
    def lc(p, n):
        d = math.hypot(p.x, p.y); a = math.atan2(p.y, p.x)
        if d > R: return (1.0, 0.92, 0.35)
        if d > R-0.07: return (1.0, 0.95, 0.5)
        seg = math.floor((a/(2*math.pi)*8) % 8); edge = abs(((a/(2*math.pi)*8) % 1) - 0.5)
        return (1.0, 0.98, 0.78) if edge < 0.06 else (1.0, 0.88, 0.30)
    commit(bm, lc, sharp=70, xf=xf_rt((0.55, 0.78, 2.62), rotx=math.radians(80), rotz=0.0))
    for k, (a, L) in enumerate([(0.0, 0.5), (0.9, 0.42), (-0.7, 0.4)]):
        commit(blob(0.2, 0.1, 0.02, 2), (0.30, 0.68, 0.34), sharp=80, xf=xf_rt((-0.6+0.1*k, 0.2+0.25*k, 2.95+0.05*k), rotz=a+2.0, rotx=0.3, roty=-0.4))
    # a rolled glass rim and a long highlight streak down the front-left of the glass
    commit(lathe([(0.99, 2.72), (1.08, 2.75), (1.12, 2.81), (1.07, 2.87), (0.99, 2.82)], 40), (1.0, 0.92, 0.95), sharp=60)
    ang = math.radians(215)
    def r_wall(z): return 0.90 + (z-0.10)/(2.70-0.10)*(1.10-0.90)
    path = [((r_wall(z)+0.03)*math.cos(ang), (r_wall(z)+0.03)*math.sin(ang), z) for z in [0.8 + 0.1*k for k in range(17)]]
    commit(sweep(path, 0.045, 6), (1.0, 1.0, 1.0), sharp=80)
    deco = grab()
    # ice cubes riding the surface
    r = random.Random(6)
    for (x, y, rz) in [(-0.40, 0.10, 0.3), (0.30, 0.28, 1.0), (0.10, -0.40, 0.6), (-0.1, 0.0, 0.0)]:
        bm = rr_cube(0.30, 0.07)
        commit(bm, (0.90, 0.97, 1.0), sharp=70, xf=xf_rt((x, y, 2.30 + (0.12 if x != -0.1 else 0.30)), rotz=rz, rotx=0.2, roty=0.15))
    ice = grab()
    return dict(id="lemonade", shell=shell, deco=deco, float=None, ice=ice,
                wall=[(0.0, 0.32), (0.76, 0.32), (1.0, 2.7)], full=2.30, empty=0.65, top=2.78, rim=1.0, opaque=False,
                color=(1.0, 0.42, 0.60), surface=(1.0, 0.68, 0.78), alpha=0.85, shell_alpha=0.40, ice_alpha=0.7, float_scale=1.0)

def rr_cube(h, rad):
    bm = bmesh.new(); bmesh.ops.create_cube(bm, size=2*h)
    bmesh.ops.bevel(bm, geom=bm.edges[:], offset=rad, segments=2, affect='EDGES')
    return bm

# ------------------------------------------------------------------ COCOA
def cocoa():
    outer = [(0, 0), (0.80, 0), (0.95, 0.10), (1.06, 0.4), (1.06, 1.9), (1.1, 2.0)]
    inner = [(0.0, 0.22), (0.88, 0.22), (0.96, 0.4), (0.96, 2.0)]
    commit(closed_cup(outer, inner, 40), lambda p, n: (0.99, 0.80, 0.86) if (p.z > 0.9 or True) else (1, 1, 1), sharp=70)
    # a cream heart-ish band: a thin cream stripe round the middle
    commit(lathe([(1.075, 0.8), (1.075, 1.05)], 40), (1.0, 0.97, 0.92), sharp=60)
    # handle: a fat C-shaped loop on the +x side
    path = []
    for i in range(15):
        a = -math.pi*0.55 + math.pi*1.1*i/14
        path.append((1.02 + 0.62*math.cos(a)*0.9, 0.0, 1.05 + 0.65*math.sin(a)))
    commit(sweep(path, 0.17, 8), (0.99, 0.80, 0.86), sharp=70)
    shell = grab()          # opaque ceramic: goes to the deco group in the game (see opaque flag)
    # marshmallows on the surface (3) with a dusting of cocoa on one
    for (x, y, a) in [(-0.38, 0.10, 0.4), (0.22, 0.30, 1.2), (0.12, -0.36, 2.0)]:
        bm = rr_cube(0.0, 0.0) if False else bmesh.new()
        bmesh.ops.create_cube(bm, size=1.0)
        move(bm, lambda p: (p.x*0.50, p.y*0.50, p.z*0.40))
        bmesh.ops.bevel(bm, geom=bm.edges[:], offset=0.10, segments=3, affect='EDGES')
        commit(bm, lambda p, n: mix((1.0, 0.97, 0.96), (0.98, 0.82, 0.88), sstep(0.2, 1.0, n.x)*0.3), sharp=80, xf=xf_rt((x, y, 1.75+0.12), rotz=a))
    flt = grab()
    return dict(id="cocoa", shell=None, deco=shell, float=flt, ice=None,
                wall=[(0.0, 0.22), (0.88, 0.22), (0.96, 0.4), (0.96, 2.0)], full=1.75, empty=0.55, top=2.0, rim=0.96, opaque=True,
                color=(0.42, 0.22, 0.14), surface=(0.52, 0.30, 0.20), alpha=1.0, shell_alpha=1.0, ice_alpha=1.0, float_scale=1.0)

# ------------------------------------------------------------------ run + preview
def preview(d):
    """A Blender render of the assembled drink (liquid column built here the way the game builds it) for look-dev."""
    import run as R
    R.setup_scene(520, 520)
    R.add_plate(2.4)
    def obj(data, alpha=1.0, dz=0.0, name="p"):
        if data is None or not data[3]: return
        P, N, C, F = data
        ob = R.make_mesh(([(p[0], p[1], p[2]+dz) for p in P], N, C, F), name)
        if alpha < 1.0:
            m = bpy.data.materials.new(name+"a"); m.use_nodes = True
            nt = m.node_tree; b = nt.nodes['Principled BSDF']
            cn = nt.nodes.new('ShaderNodeVertexColor'); cn.layer_name = 'Col'; nt.links.new(cn.outputs['Color'], b.inputs['Base Color'])
            b.inputs['Alpha'].default_value = alpha; b.inputs['Roughness'].default_value = 0.2
            m.surface_render_method = 'BLENDED'; m.use_backface_culling = False
            ob.data.materials.clear(); ob.data.materials.append(m)
    lvl = d["full"]*0.8
    # liquid
    wall = d["wall"]
    prof = [(0.0, wall[0][1])]
    for r_, z_ in wall[1:]:
        if z_ < lvl: prof.append((r_-0.06, z_))
    rr = wall[-1][0]
    for (r0, z0), (r1, z1) in zip(wall, wall[1:]):
        if z0 <= lvl <= z1: rr = r0 + (r1-r0)*(lvl-z0)/(z1-z0)
    prof.append((rr-0.06, lvl)); prof.append((0.0, lvl))
    commit(lathe(prof, 40), d["color"], sharp=70)
    liq = grab()
    dz = lvl - d["full"]
    obj(d["deco"], 1.0, 0, "deco"); obj(d["float"], 1.0, dz, "flt")
    if d["opaque"]: obj(liq, 1.0, 0, "liq")
    else: obj(liq, d["alpha"], 0, "liq")
    obj(d["shell"], d["shell_alpha"], 0, "shell"); obj(d["ice"], d["ice_alpha"], dz, "ice")
    R.camera((0, 0, 1.3), math.radians(25), math.radians(28), 8.0, 55, 520, 520)
    R.render(f"{S}/renders/drink_{d['id']}.png")

def main():
    for fn in (boba, smoothie, lemonade, cocoa):
        d = fn()
        i = d["id"]
        for part in ("shell", "deco", "float", "ice"):
            if d[part] is not None: write(f"drink_{i}_{part}", d[part])
        j = {k: v for k, v in d.items() if k not in ("shell", "deco", "float", "ice")}
        j["wall"] = [[round(a*0.1, 4), round(b*0.1, 4)] for a, b in j["wall"]]
        for k in ("full", "empty", "top", "rim"): j[k] = round(j[k]*0.1, 4)
        json.dump(j, open(f"{S}/export/drink_{i}.json", "w"), indent=1)
        preview(d)

main()
