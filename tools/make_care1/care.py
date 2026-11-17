"""Care sweep 1 (bath time): the six SOAP bars modelled in headless Blender and exported as OBJ (linear vertex colours) + JSON, the same
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
SIZE = dict(soap_jelly=0.34, soap_lavender=0.34, soap_mint=0.34, soap_berry=0.34, soap_honey=0.34, soap_chamomile=0.34)
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

# ---- the soap bars: one rounded bar, a scent colour, an embossed oval and a small motif per scent
SOAPS = dict(
    jelly=dict(body=(0.70, 0.82, 0.92), top=(0.84, 0.92, 0.98), motif="bubbles", acc=(0.86, 0.95, 1.0)),
    lavender=dict(body=(0.70, 0.58, 0.90), top=(0.86, 0.80, 0.98), motif="buds", acc=(0.54, 0.40, 0.78)),
    mint=dict(body=(0.56, 0.84, 0.68), top=(0.82, 0.96, 0.88), motif="leaves", acc=(0.30, 0.64, 0.42)),
    berry=dict(body=(0.95, 0.56, 0.72), top=(1.0, 0.82, 0.88), motif="berries", acc=(0.78, 0.18, 0.40)),
    honey=dict(body=(0.97, 0.78, 0.30), top=(1.0, 0.90, 0.58), motif="drops", acc=(0.80, 0.50, 0.10)),
    chamomile=dict(body=(0.97, 0.93, 0.80), top=(1.0, 0.98, 0.92), motif="daisies", acc=(0.98, 0.80, 0.20)),
)
def soap(name):
    c = SOAPS[name]
    bm = slab(poly_pts_rounded([(-0.95, -0.6), (0.95, -0.6), (0.95, 0.6), (-0.95, 0.6)], 0.28, 5), 0.0, 0.62, cuts=2)
    subdiv(bm, 1)
    commit(bm, lambda p, n: mix(c["body"], c["top"], sstep(0.3, 0.62, p.z)*0.5), mods=BEV(0.09, 3), sharp=60)
    commit(blob(0.62, 0.34, 0.06, 3), c["top"], sharp=80, xf=xf_rt((0, 0, 0.62)))        # the embossed oval
    m = c["motif"]; a = c["acc"]
    if m == "buds":
        for k in range(5): commit(blob(0.035, 0.035, 0.012, 2), a, sharp=80, xf=xf_rt((-0.3+0.15*k, 0, 0.675)))
    elif m == "leaves":
        for sx in (-1, 1): commit(blob(0.22, 0.07, 0.02, 2), a, sharp=80, xf=xf_rt((0.14*sx, 0, 0.685), rotz=0.5*sx))
    elif m == "berries":
        for k, x in enumerate((-0.22, 0.0, 0.22)): commit(blob(0.09, 0.09, 0.06, 2), a, sharp=80, xf=xf_rt((x, 0.02*(k % 2), 0.70)))
    elif m == "drops":
        for k, x in enumerate((-0.25, 0.0, 0.25)): commit(blob(0.07, 0.07, 0.05, 2), a, sharp=80, xf=xf_rt((x, -0.04*(k % 2), 0.69)))
    elif m == "daisies":
        for x in (-0.22, 0.22):
            for q in range(6): commit(blob(0.07, 0.03, 0.015, 2), (1.0, 1.0, 1.0), sharp=80, xf=xf_rt((x+0.07*math.cos(q*1.047), 0.07*math.sin(q*1.047), 0.69), rotz=q*1.047))
            commit(blob(0.035, 0.035, 0.02, 2), a, sharp=80, xf=xf_rt((x, 0, 0.7)))
    bubbles([(0.7, 0.28, 0.78, 0.12), (0.88, 0.1, 0.9, 0.075), (0.58, 0.4, 0.95, 0.06)], (0.86, 0.95, 1.0))
for _n in SOAPS: BUILD["soap_" + _n] = (lambda n=_n: soap(n))

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
