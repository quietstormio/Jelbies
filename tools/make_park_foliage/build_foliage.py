"""Build the Park's foliage (3 deciduous trees, 2 conifers, 2 flowering bushes, 1 flower-and-grass clump) in headless Blender and export OBJ+JSON.

  /Applications/Blender.app/Contents/MacOS/Blender -b -P build_foliage.py -- [ids...]
  python3 convert.py <export dir> BobV1/Room/Resources        # -> park_<id>.bin (same .bin format as decor_<id>.bin)

Game coordinates (y up, +z toward the camera, origin = trunk foot / clump centre on the ground). Parts: "bark", "leaf", "bloom".
Colours are baked per vertex: sunlit yellow-green tops, cool dark undersides, hue noise and an ambient-occlusion term from the overlapping clusters.
`bloom` parts are neutral cream so the game can tint them per bush.
"""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dk import *
from lib import nz
from mathutils import Vector

SUN = Vector((0.45, 0.8, 0.4)).normalized()
def clamp01(x): return max(0.0, min(1.0, x))

def leaf_color(clusters, y0, y1, base_lo, base_hi, tint=(1, 1, 1), seed=0.0):
    """Vertex colour fn (p, n) for a canopy: gradient by height, sun term, cool shade, hue noise, AO from the other clusters."""
    def fn(p, n):
        h = clamp01((p.y - y0) / max(0.01, y1 - y0))
        sun = clamp01(n.dot(SUN) * 0.5 + 0.5)
        q = p + n * 0.12
        occ = 0.0
        for (c, r) in clusters:
            d = (q - c).length
            if d < r: occ += (1 - d / r)
        ao = 1.0 - 0.5 * min(1.0, occ)
        base = mix(base_lo, base_hi, h)
        lit = mix(mix(base, (0.10, 0.30, 0.34), 0.45), base, sstep(0.15, 0.8, sun))
        warm = clamp01(nz(p, 2.3, seed) * 0.5 + 0.5)
        lit = mix(lit, (0.78, 0.86, 0.30), 0.22 * warm * sun)
        lit = mix(lit, (0.16, 0.50, 0.42), 0.12 * (1 - warm))
        k = (0.55 + 0.55 * sun) * (0.45 + 0.55 * ao) * (0.7 + 0.3 * h + 0.1)
        return tuple(min(1.0, c * k * t) for c, t in zip(lit, tint))
    return fn

def blob(centre, r, sub, bump, seed, squash=(1, 0.86, 1)):
    bm = sph_bm(r * squash[0], r * squash[1], r * squash[2], sub)
    for v in bm.verts:
        d = v.co.normalized()
        k = 1 + bump * (nz(d * 1.7 + Vector(centre), 1.6, seed) + 0.5 * nz(d * 3.1, 1.0, seed + 5))
        v.co = v.co * k
    return bm

BARK_LO = hx('#4A3324'); BARK_HI = hx('#8A6347')
def bark(p, n):
    h = clamp01(p.y / 2.0)
    c = mix(BARK_LO, BARK_HI, 0.35 + 0.35 * clamp01(n.dot(SUN) * 0.5 + 0.5))
    return mix(c, (0.3, 0.22, 0.16), 0.3 * (1 - h) * 0.5)

def trunk_and_branches(rng, height, lean, branch_targets, r0=0.17):
    pts = [Vector((lean[0] * (t ** 2), height * t, lean[1] * (t ** 2))) for t in [i / 7 for i in range(8)]]
    add_tube(pts, 0.1, bark, sides=8, radfn=lambda t: r0 * (1 + 1.1 * (1 - t) ** 5) * (1 - 0.55 * t))
    for (a, b) in branch_targets:
        mid = (a + b) * 0.5 + Vector((rng.uniform(-0.08, 0.08), 0.1, rng.uniform(-0.08, 0.08)))
        add_tube([a, mid, b], 0.05, bark, sides=6, radfn=lambda t: 0.055 * (1 - 0.7 * t))

def deciduous(iid, seed, R=1.0, H=2.0, ncl=7, lean=(0.0, 0.0), base_lo=(0.18, 0.46, 0.20), base_hi=(0.52, 0.78, 0.27), flat=0.86, spread=0.62):
    rng = random.Random(seed); lib.reset(); reset()
    cy = H + R * 0.30
    cl = []                              # (centre, radius) of the main clusters
    cl.append((Vector((0, cy + R * 0.10, 0)), R * 0.80))
    off = rng.uniform(0, 6.28)
    for i in range(ncl - 1):
        a = off + i / (ncl - 1) * 2 * math.pi + rng.uniform(-0.3, 0.3)
        d = R * (spread + 0.16 * rng.random())
        cl.append((Vector((math.cos(a) * d, cy + R * rng.uniform(-0.28, 0.32), math.sin(a) * d * 0.95)), R * rng.uniform(0.50, 0.62)))
    cl.append((Vector((rng.uniform(-0.15, 0.15) * R, cy + R * 0.66, rng.uniform(-0.15, 0.15) * R)), R * 0.38))
    smalls = []                          # small leaf lumps on the canopy surface
    for k in range(7):
        c, r = cl[rng.randrange(len(cl))]
        d = Vector((rng.uniform(-1, 1), rng.uniform(-0.2, 1), rng.uniform(-1, 1))).normalized()
        smalls.append((c + d * r * 0.88, r * rng.uniform(0.30, 0.40)))
    allc = cl + smalls
    y0, y1 = min(c.y - r for c, r in cl), max(c.y + r for c, r in cl)
    begin("bark")
    tgt = [(Vector((0, H * 0.78, 0)), Vector((c.x * 0.8, c.y - r * 0.2, c.z * 0.8))) for c, r in cl[1:4]]
    trunk_and_branches(rng, H * 1.05, lean, tgt)
    begin("leaf")
    for i, (c, r) in enumerate(cl):
        col = leaf_color(allc, y0, y1, base_lo, base_hi, tint=(0.94 + 0.12 * rng.random(), 0.95 + 0.10 * rng.random(), 0.92 + 0.14 * rng.random()), seed=i * 3.1)
        commit(blob(c, r, 3, 0.10, i * 1.7, squash=(1, flat, 0.96)), col, sharp=100, xf=T(tuple(c)))
    for i, (c, r) in enumerate(smalls):
        col = leaf_color(allc, y0, y1, base_lo, base_hi, tint=(1.0, 1.02, 0.95), seed=50 + i)
        commit(blob(c, r, 2, 0.12, 40 + i), col, sharp=100, xf=T(tuple(c)))
    return dict(kind="tree", canopy_radius=R * 1.25, height=y1)

def conifer(iid, seed, tiers=5, H=3.6, R=1.0, base_lo=(0.10, 0.30, 0.26), base_hi=(0.34, 0.62, 0.34)):
    rng = random.Random(seed); lib.reset(); reset()
    begin("bark")
    add_tube([Vector((0, 0, 0)), Vector((0, 0.7, 0)), Vector((0, 1.2, 0))], 0.1, bark, sides=8, radfn=lambda t: 0.14 * (1 + 0.8 * (1 - t) ** 4))
    begin("leaf")
    tcl = []
    for t in range(tiers):
        f = t / tiers
        tcl.append((Vector((0, 0.9 + (H - 0.9) * f * 0.88, 0)), R * (1.0 - 0.72 * f)))
    for t in range(tiers):
        f = t / tiers
        rb = R * (1.0 - 0.72 * f) * rng.uniform(0.95, 1.05)
        y = 0.9 + (H - 0.9) * f * 0.88
        hgt = (H - 0.9) * 0.42
        # a soft drooping bough: round lip, thick shoulders, a blunt top; radial scallops from a cosine
        prof = [(0, y - 0.05), (rb * 0.62, y - 0.10), (rb * 0.93, y - 0.03), (rb * 1.0, y + 0.08), (rb * 0.90, y + hgt * 0.30), (rb * 0.62, y + hgt * 0.62), (rb * 0.30, y + hgt * 0.88), (0, y + hgt)]
        bm = lathe_bm(prof, 22)
        ph = rng.uniform(0, 6.28)
        for v in bm.verts:
            r = math.hypot(v.co.x, v.co.z)
            if r > 1e-4:
                a = math.atan2(v.co.z, v.co.x)
                w = 1 + (0.10 * math.cos(5 * a + ph) + 0.05 * math.cos(9 * a + ph * 2)) * clamp01(r / rb)
                v.co.x *= w; v.co.z *= w
            v.co.y += 0.05 * nz(v.co, 2.0, ph) * clamp01(r / rb)
        # the lathe's flat underside bulges up the middle (shade it dark)
        col = leaf_color(tcl, 0.9, H, base_lo, base_hi, tint=(1, 1, 1), seed=t * 2.7)
        commit(bm, col, sharp=100, xf=T((0, 0, 0)))
    return dict(kind="conifer", canopy_radius=R, height=H)

def bush(iid, seed, nbl=18, R=1.0):
    rng = random.Random(seed); lib.reset(); reset()
    cl = [(Vector((0, 0.42 * R, 0)), 0.52 * R)]
    n = 5
    off = rng.uniform(0, 6.28)
    for i in range(n):
        a = off + i / n * 2 * math.pi + rng.uniform(-0.3, 0.3)
        d = R * rng.uniform(0.55, 0.78)
        cl.append((Vector((math.cos(a) * d * 1.1, R * rng.uniform(0.22, 0.38), math.sin(a) * d * 0.8)), R * rng.uniform(0.32, 0.44)))
    y0, y1 = 0.0, R * 0.95
    begin("leaf")
    for i, (c, r) in enumerate(cl):
        col = leaf_color(cl, y0, y1, (0.22, 0.52, 0.24), (0.55, 0.82, 0.32), tint=(0.95 + 0.1 * rng.random(), 1.0, 0.95 + 0.1 * rng.random()), seed=i * 2.3)
        commit(blob(c, r, 3, 0.09, i * 2.1 + seed, squash=(1, 0.84, 0.94)), col, sharp=100, xf=T(tuple(c)))
    begin("bloom")
    for k in range(nbl):
        c, r = cl[rng.randrange(len(cl))]
        d = Vector((rng.uniform(-1, 1), rng.uniform(0.15, 1), rng.uniform(-1, 1))).normalized()
        p = c + d * r * 0.96
        def bcol(q, n, p=p):
            sun = clamp01(n.dot(SUN) * 0.5 + 0.5)
            return mix((0.80, 0.70, 0.72), (1.0, 0.98, 0.97), sun)
        commit(sph_bm(0.085, 0.065, 0.085, 2), bcol, sharp=100, xf=T(tuple(p)))
    return dict(kind="bush")

def flowers(iid, seed):
    rng = random.Random(seed); lib.reset(); reset()
    g0 = (0.24, 0.52, 0.22); g1 = (0.66, 0.88, 0.36)
    begin("leaf")
    def gcol(p, n): return mix(g0, g1, clamp01(p.y / 0.4))
    for _ in range(26):
        a = rng.uniform(0, 6.28); d = math.sqrt(rng.random()) * 0.42
        base = Vector((math.cos(a) * d, 0, math.sin(a) * d * 0.85))
        hgt = rng.uniform(0.16, 0.34) * (1.15 - 0.5 * d / 0.42)
        dr = a + rng.uniform(-0.7, 0.7)
        lean = Vector((math.cos(dr), 0, math.sin(dr))) * hgt * rng.uniform(0.2, 0.6)
        pts = [base, base + lean * 0.3 + Vector((0, hgt * 0.5, 0)), base + lean + Vector((0, hgt, 0))]
        add_tube(pts, 0.02, gcol, sides=3, radfn=lambda t: 0.024 * (1 - 0.92 * t))
    add_sph((0, 0.03, 0), (0.30, 0.07, 0.26), (0.20, 0.46, 0.20), sub=1)
    begin("bloom")
    for k in range(7):
        a = k / 7 * 2 * math.pi + rng.uniform(-0.3, 0.3); d = 0.06 if k == 0 else rng.uniform(0.14, 0.36)
        fh = rng.uniform(0.22, 0.36)
        pos = Vector((math.cos(a) * d, fh, math.sin(a) * d * 0.85))
        commit(sph_bm(0.075, 0.055, 0.075, 2), lambda p, n: mix((0.80, 0.70, 0.72), (1.0, 0.98, 0.97), clamp01(n.dot(SUN) * 0.5 + 0.5)), sharp=100, xf=T(tuple(pos)))
    return dict(kind="flowers")

REG = [
    ("tree_a", lambda: deciduous("tree_a", 11, R=1.0, H=1.45, ncl=7, spread=0.58)),
    ("tree_b", lambda: deciduous("tree_b", 23, R=1.05, H=1.6, ncl=7, lean=(0.12, -0.05), flat=0.8, spread=0.66, base_lo=(0.20, 0.48, 0.22), base_hi=(0.58, 0.80, 0.28))),
    ("tree_c", lambda: deciduous("tree_c", 37, R=0.92, H=1.2, ncl=6, lean=(-0.1, 0.06), flat=0.92, spread=0.52, base_lo=(0.16, 0.44, 0.24), base_hi=(0.46, 0.76, 0.30))),
    ("pine_a", lambda: conifer("pine_a", 5, tiers=5, H=3.6)),
    ("pine_b", lambda: conifer("pine_b", 9, tiers=4, H=2.9, R=0.9, base_lo=(0.12, 0.34, 0.24), base_hi=(0.40, 0.66, 0.30))),
    ("bush_a", lambda: bush("bush_a", 3, nbl=12)),
    ("bush_b", lambda: bush("bush_b", 8, nbl=10, R=0.9)),
    ("flowers", lambda: flowers("flowers", 4)),
]

if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    import lib
    for iid, fn in REG:
        if only and iid not in only: continue
        meta = fn(); info = export(iid, meta)
        print("EXPORT", iid, info["tris"], info["verts"], [(s["name"], s["tris"]) for s in info["sub_meshes"]], info["bounds_min"], info["bounds_max"], flush=True)
