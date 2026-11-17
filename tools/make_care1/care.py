"""Care sweep 1 (bath time): the eight Care items modelled in headless Blender and exported as OBJ (linear vertex colours) + JSON, the same
pipeline as tools/make_food4 (it reuses its lib.py). Run from the repo root:

  FOOD4_OUT=tools/make_care1/out /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/make_care1/care.py -- [ids...]
  python3 tools/convert_food_art.py tools/make_care1/out/export BobV1/Store/Resources care_lavender care_lintguard ...   (writes food_care_<id>.bin)

Conventions: Blender z up, front toward -y; export maps to game units (y up, +z toward the camera). Origin = centre of the base, bottom at y = 0,
longest side = SIZE[id] game units. One mesh per item, ids prefixed "care_" so the bundled file is food_care_<id>.bin (FoodMeshes.load / CareMeshes).
"""
import os, sys
HERE = os.path.dirname(os.path.abspath(__file__))
os.environ.setdefault("FOOD4_OUT", os.path.join(HERE, "out"))
sys.path.insert(0, os.path.join(HERE, "..", "make_food4"))
from lib import *
V = Vector
SIZE = dict(lavender=0.34, lintguard=0.42, bubblebath=0.46, shampoo=0.40, deluxe=0.50, brush=0.52, sponge=0.30, duck=0.34)
BUILD = {}

def blob(rx, ry, rz, sub=3):
    bm = ico(sub, 1.0); move(bm, lambda p: (p.x*rx, p.y*ry, p.z*rz)); return bm
def subdiv(bm, cuts=4):
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True); bmesh.ops.triangulate(bm, faces=bm.faces[:]); return bm
BEV = lambda w=0.04, seg=2, ang=40: [('BEVEL', dict(width=w, segments=seg, limit_method='ANGLE', angle_limit=math.radians(ang)))]
def bottle_prof(r, h, shoulder, neck_r, neck_h, rr=0.12):
    """a rounded-bottom bottle profile (r, z) bottom to top."""
    p = [(0.0, 0.0), (r*0.7, 0.0), (r*0.93, rr*0.35), (r, rr), (r, h - shoulder), (r*0.93, h - shoulder*0.45), (neck_r*1.25, h - shoulder*0.1), (neck_r, h), (neck_r, h + neck_h), (0.0, h + neck_h)]
    return p
def bubbles(cs, color=(0.86, 0.95, 1.0)):
    for (x, y, z, r) in cs: commit(blob(r, r, r, 2), color, sharp=80, xf=xf_rt((x, y, z)))

# ---- 1. lavender soap: a rounded lavender bar with an embossed pad and little bubbles
def lavender():
    bm = slab(poly_pts_rounded([(-0.95, -0.6), (0.95, -0.6), (0.95, 0.6), (-0.95, 0.6)], 0.28, 5), 0.0, 0.62, cuts=2)
    subdiv(bm, 1)
    commit(bm, lambda p, n: mix((0.70, 0.58, 0.90), (0.80, 0.70, 0.96), sstep(0.3, 0.62, p.z)*0.7), mods=BEV(0.09, 3), sharp=60)
    commit(blob(0.62, 0.34, 0.06, 3), (0.86, 0.80, 0.98), sharp=80, xf=xf_rt((0, 0, 0.62)))        # the embossed oval
    for k in range(5): commit(blob(0.035, 0.035, 0.012, 2), (0.54, 0.40, 0.78), sharp=80, xf=xf_rt((-0.3+0.15*k, 0, 0.675)))      # tiny lavender buds
    bubbles([(0.7, 0.28, 0.78, 0.12), (0.88, 0.1, 0.9, 0.075), (0.58, 0.4, 0.95, 0.06)])
BUILD['lavender'] = lavender

# ---- 2. lint-guard spray: a sky-blue pump bottle with a white trigger head and a wind label
def lintguard():
    R, H = 0.42, 1.15
    commit(lathe(bottle_prof(R, H, 0.28, 0.17, 0.08), 28), lambda p, n: (0.96, 0.98, 1.0) if 0.35 < p.z < 0.78 and abs(n.z) < 0.5 else (0.52, 0.76, 0.95), sharp=55)
    for z in (0.40, 0.74): commit(lathe([(R+0.003, z), (R+0.012, z), (R+0.012, z+0.03), (R+0.003, z+0.03)], 28), (0.36, 0.62, 0.88), sharp=60)
    cap = lathe([(0.0, 0.0), (0.2, 0.0), (0.2, 0.14), (0.15, 0.2), (0.0, 0.2)], 20)
    commit(cap, (0.97, 0.97, 0.98), sharp=50, xf=xf_rt((0, 0, H+0.08)))
    # head: a bar with a nozzle toward -y and a trigger underneath
    commit(slab(poly_pts_rounded([(-0.17, -0.2), (0.17, -0.2), (0.17, 0.2), (-0.17, 0.2)], 0.1, 4), 0, 0.2, 0), (0.97, 0.97, 0.98), mods=BEV(0.04, 2), sharp=50, xf=xf_rt((0, -0.02, H+0.24)))
    commit(lathe([(0.0, 0.0), (0.05, 0.0), (0.05, 0.3), (0.0, 0.3)], 10), (0.3, 0.55, 0.82), sharp=50, xf=xf_rt((0, -0.2, H+0.34), rotx=math.pi/2))
    commit(slab(poly_pts_rounded([(-0.05, -0.04), (0.05, -0.04), (0.05, 0.04), (-0.05, 0.04)], 0.02, 3), 0, 0.3, 0), (0.30, 0.55, 0.82), mods=BEV(0.015, 2), sharp=50, xf=xf_rt((0, -0.22, H+0.05), rotx=0.35))
    # a little swirl of wind on the label: three arcs
    for k, z in enumerate((0.48, 0.58, 0.68)):
        commit(blob(0.12-0.02*k, 0.012, 0.012, 2), (0.40, 0.64, 0.90), sharp=80, xf=xf_rt((0.02*k, -R-0.012, z)))
BUILD['lintguard'] = lintguard

# ---- 3. bubble bath: a tall pink bottle with a heart cap and a heap of foam
def bubblebath():
    R, H = 0.36, 1.15
    commit(lathe(bottle_prof(R, H, 0.3, 0.2, 0.06, 0.14), 28), lambda p, n: (0.99, 0.84, 0.90) if 0.3 < p.z < 0.8 and abs(n.z) < 0.5 else (0.95, 0.56, 0.74), sharp=55)
    commit(lathe([(0.0, 0.0), (0.23, 0.0), (0.23, 0.26), (0.18, 0.3), (0.0, 0.3)], 24), (0.70, 0.88, 0.98), sharp=45, xf=xf_rt((0, 0, H+0.04)))
    for (x, y, z, r) in [(0.0, 0.0, H+0.36, 0.2), (0.17, 0.05, H+0.28, 0.15), (-0.16, -0.03, H+0.3, 0.14), (0.05, 0.14, H+0.46, 0.12), (-0.06, -0.1, H+0.5, 0.11),
                          (0.24, -0.1, H+0.44, 0.08), (-0.26, 0.08, H+0.44, 0.09)]:
        commit(blob(r, r, r, 2), (0.99, 0.99, 1.0), sharp=80, xf=xf_rt((x, y, z)))
    heart = lambda x, z, r: [commit(blob(r, 0.014, r, 2), (0.92, 0.30, 0.46), sharp=80, xf=xf_rt((x, -R-0.01, z)))]
    heart(-0.05, 0.62, 0.06); heart(0.05, 0.62, 0.06); commit(blob(0.07, 0.014, 0.07, 2), (0.92, 0.30, 0.46), sharp=80, xf=xf_rt((0, -R-0.01, 0.55)))
    bubbles([(0.55, -0.2, 0.55, 0.1), (0.62, -0.05, 0.9, 0.07), (-0.58, -0.1, 0.4, 0.08), (-0.5, 0.1, 0.8, 0.06)], (0.86, 0.95, 1.0))
BUILD['bubblebath'] = bubblebath

# ---- 4. gentle shampoo: a squat mint bottle with a flip cap and a leaf label
def shampoo():
    R, H = 0.5, 0.95
    commit(lathe(bottle_prof(R, H, 0.25, 0.22, 0.04, 0.16), 28), lambda p, n: (0.98, 0.99, 0.96) if 0.28 < p.z < 0.7 and abs(n.z) < 0.5 else (0.62, 0.86, 0.72), sharp=55)
    commit(lathe([(0.0, 0.0), (0.27, 0.0), (0.27, 0.22), (0.24, 0.27), (0.0, 0.27)], 24), (0.98, 0.98, 0.97), sharp=50, xf=xf_rt((0, 0, H+0.01)))
    commit(slab(poly_pts_rounded([(-0.1, -0.05), (0.1, -0.05), (0.1, 0.05), (-0.1, 0.05)], 0.03, 3), 0, 0.09, 0), (0.62, 0.86, 0.72), mods=BEV(0.02, 2), sharp=50, xf=xf_rt((0, -0.2, H+0.27)))
    for k, a in enumerate((-0.5, 0.5)):             # a two-leaf sprig on the label
        commit(blob(0.14, 0.012, 0.06, 2), (0.34, 0.66, 0.46), sharp=80, xf=xf_rt((0.1*(1 if k else -1), -R-0.004, 0.5), roty=a*0.8))
    commit(blob(0.012, 0.012, 0.12, 2), (0.34, 0.66, 0.46), sharp=80, xf=xf_rt((0, -R-0.004, 0.42)))
    bubbles([(0.62, -0.1, 0.5, 0.09), (0.68, 0.05, 0.76, 0.06)], (0.88, 0.97, 0.92))
BUILD['shampoo'] = shampoo

# ---- 5. deluxe shampoo: a tall pearl-violet bottle with gold bands and a gem cap
def deluxe():
    R, H = 0.4, 1.3
    commit(lathe(bottle_prof(R, H, 0.38, 0.17, 0.1, 0.16), 32), lambda p, n: mix((0.62, 0.48, 0.86), (0.86, 0.76, 0.98), sstep(0.2, 1.2, p.z)*0.55), sharp=55)
    gold = (0.95, 0.78, 0.30)
    for z, w in ((0.30, 0.05), (0.82, 0.05), (H+0.02, 0.09)): commit(lathe([(R*(0.995 if z < H else 0.17)+0.012, z), (R*(0.995 if z < H else 0.17)+0.02, z), (R*(0.995 if z < H else 0.17)+0.02, z+w), (R*(0.995 if z < H else 0.17)+0.012, z+w)], 32), gold, sharp=60)
    commit(lathe([(0.0, 0.0), (0.2, 0.0), (0.2, 0.18), (0.14, 0.3), (0.0, 0.32)], 28), gold, sharp=45, xf=xf_rt((0, 0, H+0.08)))
    commit(ico(1, 0.12), (0.98, 0.94, 0.99), sharp=30, xf=xf_rt((0, 0, H+0.5)))                         # the gem
    commit(blob(0.2, 0.012, 0.14, 2), gold, sharp=80, xf=xf_rt((0, -R-0.008, 0.58)))                      # label plaque
    for k, a in enumerate(range(5)):                                                                      # five little stars of foam around the base
        commit(blob(0.06, 0.06, 0.06, 2), (0.96, 0.92, 1.0), sharp=80, xf=xf_rt((0.62*math.cos(0.9*k+0.5), 0.62*math.sin(0.9*k+0.5) - 0.3, 0.06 + 0.02*(k % 2))))
BUILD['deluxe'] = deluxe

# ---- 6. soft brush: an oval wooden brush with a handle and a field of cream bristles
def brush():
    wood = (0.86, 0.66, 0.42); cream = (0.99, 0.93, 0.80)
    head = slab([(1.0*math.cos(2*math.pi*i/32)*0.78, 1.0*math.sin(2*math.pi*i/32)*0.52) for i in range(32)], 0.0, 0.2, 1)
    commit(head, wood, mods=BEV(0.05, 2), sharp=55, xf=xf_rt((0.0, 0.0, 0.3)))
    h = lathe([(0.0, 0.0), (0.13, 0.0), (0.16, 0.5), (0.2, 1.4), (0.16, 1.55), (0.0, 1.6)], 18)
    commit(h, wood, sharp=55, xf=xf_rt((0.72, 0, 0.48), roty=math.pi/2*0.93))
    commit(ico(2, 0.2), (0.80, 0.34, 0.30), sharp=50, xf=xf_rt((2.35, 0, 0.62)))        # a red bobble at the handle end
    for ix in range(-5, 6):
        for iy in range(-3, 4):
            x, y = ix*0.13, iy*0.12
            if (x/0.70)**2 + (y/0.46)**2 > 1.0: continue
            commit(lathe([(0.0, 0.0), (0.046, 0.0), (0.042, 0.28), (0.02, 0.34), (0.0, 0.35)], 6), lambda p, n: mix(cream, (1.0, 0.8, 0.84), sstep(0.15, 0.35, p.z)*0.7), sharp=80, xf=xf_rt((x, y, 0.0)))
    # bristles hang below the head: the model sits on the bristle tips
BUILD['brush'] = brush

# ---- 7. sea sponge: a lumpy golden sponge with pores
def sponge():
    bm = ico(4, 1.0)
    ph = (0.7, 2.1, 4.0)
    def f(p):
        d = V(p).normalized(); a = math.atan2(d.y, d.x)
        r = 1 + 0.09*math.sin(2*a+ph[0]) + 0.07*math.sin(3*a+ph[1]) + 0.04*math.sin(5*a+ph[2])
        return (d.x*1.0*r, d.y*0.78*r, d.z*0.62*(0.9+0.12*nz(d, 1.6, 3.0)))
    move(bm, f)
    displace(bm, lambda p, n: 0.05*nz(p, 4.0, 1.0) - 0.07*max(0.0, nz(p, 9.0, 5.0)) + 0.02*nz(p, 18.0, 8.0))
    def col(p, n):
        c = mix((0.98, 0.80, 0.34), (0.96, 0.68, 0.24), sstep(-0.3, 0.6, nz(p, 2.0, 2.0)))
        s = nz(p, 9.0, 5.0)
        return mix(c, (0.66, 0.40, 0.14), 0.85*sstep(0.12, 0.5, s))             # pores
    commit(bm, col, sharp=75, xf=xf_rt((0, 0, 0.62)))
BUILD['sponge'] = sponge

# ---- 8. rubber duck: classic yellow, orange beak, black eyes, little wings
def duck():
    y = (1.0, 0.82, 0.18); y2 = (1.0, 0.90, 0.40); org = (0.98, 0.52, 0.12)
    def body(p, n): return mix(y, y2, sstep(0.0, 1.2, p.z)*0.4)
    b = blob(1.0, 0.82, 0.72, 4)
    move(b, lambda p: (p.x + (0.0 if p.y > 0 else 0.0), p.y, p.z*(1.0 + 0.0)))
    # the tail kicks up at the back (+y)
    bm = b; move(bm, lambda p: (p.x, p.y, p.z + 0.38*sstep(0.1, 0.8, p.y)*sstep(0.0, 0.6, p.z+0.3)))
    commit(bm, body, sharp=80, xf=xf_rt((0, 0.15, 0.78)))
    commit(blob(0.62, 0.62, 0.62, 4), body, sharp=80, xf=xf_rt((0, -0.55, 1.62)))                          # head
    commit(blob(0.42, 0.34, 0.14, 3), org, sharp=80, xf=xf_rt((0, -1.1, 1.52), rotx=-0.12))               # beak
    for sx in (-1, 1):
        commit(blob(0.075, 0.07, 0.085, 2), (0.08, 0.07, 0.09), sharp=80, xf=xf_rt((sx*0.27, -1.0, 1.82)))   # eyes
        commit(blob(0.022, 0.02, 0.026, 2), (1.0, 1.0, 1.0), sharp=80, xf=xf_rt((sx*0.29, -1.06, 1.85)))     # glints
        commit(blob(0.12, 0.42, 0.34, 3), y, sharp=80, xf=xf_rt((sx*0.86, 0.15, 0.95), rotz=sx*0.25))        # wings
        commit(blob(0.12, 0.1, 0.05, 2), (1.0, 0.62, 0.62), sharp=80, xf=xf_rt((sx*0.4, -0.88, 1.56)))        # cheeks
BUILD['duck'] = duck

# ---------------------------------------------------------------- export
def build(i):
    reset(); BUILD[i]()
    P, N, C, F = merged()
    mn = [min(p[k] for p in P) for k in range(3)]; mx = [max(p[k] for p in P) for k in range(3)]
    cx, cy = (mn[0]+mx[0])/2, (mn[1]+mx[1])/2
    s = SIZE[i] / max(mx[k]-mn[k] for k in range(3))
    G = [((p[0]-cx)*s, (p[2]-mn[2])*s, -(p[1]-cy)*s) for p in P]            # y up, +z toward the camera, base centre at the origin
    GN = [(n[0], n[2], -n[1]) for n in N]
    name = "care_" + i
    with open(f"{S}/export/{name}.obj", "w") as fh:
        fh.write(f"# {name}: game units, base centre at origin, bottom y=0\n# v x y z r g b (r g b = LINEAR vertex colour)\n")
        for g, c in zip(G, C): fh.write("v %.5f %.5f %.5f %.4f %.4f %.4f\n" % (*g, *lin(c)))
        for n in GN: fh.write("vn %.4f %.4f %.4f\n" % n)
        for a, b, c in F: fh.write("f %d//%d %d//%d %d//%d\n" % (a+1, a+1, b+1, b+1, c+1, c+1))
    size = [round(max(g[k] for g in G)-min(g[k] for g in G), 4) for k in range(3)]
    json.dump(dict(id=name, tris=len(F), verts=len(G), size=size, pivot="base centre, bottom at y=0", color_space="linear RGB in extra v columns"), open(f"{S}/export/{name}.json", "w"), indent=1)
    return len(F), len(G), size

if __name__ == "__main__":
    ids = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else list(BUILD)
    for i in ids: print("EXPORT", i, *build(i), flush=True)
