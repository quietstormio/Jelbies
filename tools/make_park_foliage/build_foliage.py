"""Build the Park's foliage in headless Blender and export OBJ+JSON (round 8: soft rounded lobes, no leaf cards).

  /Applications/Blender.app/Contents/MacOS/Blender -b -P build_foliage.py -- [ids...]
  python3 convert.py <export dir> BobV1/Room/Resources        # -> park_<id>.bin (same .bin format as decor_<id>.bin)

Assets: tree_a oak (wide, 5 lobes), tree_b beech (taller, 5 lobes), tree_c small rounded tree on a pale trunk, pine_a / pine_b conifers (4 soft stacked rounded tiers),
bush_a / bush_b shrubs, hedge / hedge_low (soft clipped blocks), flowers (short soft blades + a few small blooms), and cheaper <id>_far variants for the back rows.
Game coordinates (y up, +z toward the camera, origin = trunk foot / clump centre on the ground). Parts: "bark", "leaf", "bloom".
Every crown is 3 to 6 overlapping smooth ellipsoids (slightly flattened, smooth normals, a faint low-frequency bump only): no cards, no facets, no straight edges.
Colours are baked per vertex in ONE green family (hue ~106 deg, same saturation, three value steps shade / mid / sun) with a top-light gradient and a little occlusion where lobes meet.
`bloom` parts are neutral cream so the game can tint them per bush.
"""
import sys, os, math, random, colorsys
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dk import *
from lib import nz
from mathutils import Vector
import bmesh

SUN = Vector((0.45, 0.8, 0.4)).normalized()
def clamp01(x): return max(0.0, min(1.0, x))
def fam(v, s=0.46, h=106.0): return colorsys.hsv_to_rgb(h / 360.0, s, v)

# one green family: lawn / hedges / crowns share hue and saturation, three value steps; conifers only a touch deeper
PAL_LEAF = dict(shade=fam(0.38), mid=fam(0.50), sun=fam(0.62))
PAL_CONIFER = dict(shade=fam(0.31, 0.48, 108), mid=fam(0.42, 0.48, 108), sun=fam(0.53, 0.48, 108))
PAL_BUSH = dict(shade=fam(0.37), mid=fam(0.48), sun=fam(0.60))

def pal_mix(pal, t):
    return mix(pal['shade'], pal['mid'], t * 2) if t < 0.5 else mix(pal['mid'], pal['sun'], (t - 0.5) * 2)

# ---------------------------------------------------------------- bark (soft warm neutrals, no streak noise)
BARK_SHADE = (0.33, 0.26, 0.20); BARK_SUN = (0.56, 0.46, 0.36)
def bark_fn(pale=False):
    def fn(p, n):
        s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
        if pale: return mix((0.62, 0.59, 0.53), (0.90, 0.87, 0.80), s01)
        c = mix(BARK_SHADE, BARK_SUN, s01 ** 1.2)
        low = clamp01(1 - p.y / 1.0) * 0.14
        return tuple(x * (1 - low) for x in c)
    return fn

# ---------------------------------------------------------------- lobes
def lobe_bm(c, rx, ry, rz, sub, bump, seed, e=1.0):
    """A smooth ellipsoid (or a soft block when e < 1) centred at c with a faint low-frequency bump."""
    bm = bmesh.new(); bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=1.0)
    for v in bm.verts:
        d = v.co.normalized()
        q = Vector((rx * sgn(d.x, e), ry * sgn(d.y, e), rz * sgn(d.z, e)))
        if bump: q = q * (1 + bump * nz(d * 1.3, 1.0, seed))
        v.co = q + Vector(c)
    return bm

def occlusion(p, n, lobes, me):
    q = p + n * 0.05; occ = 0.0
    for i, (c, rx, ry, rz) in enumerate(lobes):
        if i == me: continue
        d = math.sqrt(((q.x - c[0]) / rx) ** 2 + ((q.y - c[1]) / ry) ** 2 + ((q.z - c[2]) / rz) ** 2)
        occ += max(0.0, (1.06 - d) / 0.5)
    return min(1.0, occ)

def lobe_color(pal, lobes, me, y0, y1, vtone):
    def fn(p, n):
        s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
        h = clamp01((p.y - y0) / max(0.01, y1 - y0))
        t = clamp01(0.12 + 0.56 * s01 ** 1.3 + 0.32 * h - 0.30 * occlusion(p, n, lobes, me))
        return tuple(min(1.0, x * vtone) for x in pal_mix(pal, t))
    return fn

def crown(lobes, pal, sub, y0, y1, seed, bump=0.05):
    rng = random.Random(seed)
    for i, (c, rx, ry, rz) in enumerate(lobes):
        commit(lobe_bm(c, rx, ry, rz, sub + (1 if (i == 0 and sub == 3) else 0), bump, seed + i * 1.7), lobe_color(pal, lobes, i, y0, y1, 1 + rng.uniform(-0.04, 0.04)), sharp=100)

def trunk(H, r0, flare, bfn, sides, lean=(0.0, 0.0), top_r=0.62):
    TS = [0, 0.012, 0.03, 0.055, 0.09, 0.14, 0.21, 0.3, 0.42, 0.56, 0.72, 0.86, 1.0]
    pts = [Vector((lean[0] * t * t, -0.2 + (H + 0.2) * t, lean[1] * t * t)) for t in TS]          # (starts a little below the ground)
    add_tube(pts, 0.1, bark_fn(False), sides=sides, radfn=lambda u: (lambda t: r0 * (1 + flare * math.exp(-t * 11.0)) * (1 - (1 - top_r) * t))(TS[min(len(TS) - 1, int(round(u * (len(TS) - 1))))]), cap=True)
    return pts[-1]

def L(x, y, z, rx, ry, rz): return ((x, y, z), rx, ry, rz)

OAK_LOBES = [L(0, 2.35, 0, 1.0, 0.75, 1.0), L(-0.78, 1.95, 0.1, 0.82, 0.62, 0.8), L(0.8, 2.0, -0.15, 0.82, 0.62, 0.8), L(0.1, 1.9, 0.78, 0.8, 0.58, 0.74), L(-0.2, 1.95, -0.78, 0.78, 0.58, 0.74)]
BEECH_LOBES = [L(0, 3.15, 0, 0.78, 0.72, 0.78), L(0.15, 2.45, 0.1, 1.0, 0.78, 0.95), L(-0.45, 2.85, 0.3, 0.62, 0.55, 0.6), L(-0.3, 1.95, -0.1, 0.9, 0.66, 0.85), L(0.42, 1.9, 0.3, 0.76, 0.6, 0.74)]
SMALL_LOBES = [L(0.05, 3.3, 0, 0.82, 0.66, 0.8), L(-0.55, 2.75, 0.1, 0.66, 0.55, 0.64), L(0.58, 2.7, -0.1, 0.66, 0.55, 0.64), L(0.1, 2.75, 0.5, 0.56, 0.5, 0.56)]

def deciduous(iid, kind, lod=0):
    lib.reset(); reset()
    sub = 4 if not lod else 3
    lobes = {"oak": OAK_LOBES, "beech": BEECH_LOBES, "small": SMALL_LOBES}[kind]
    if lod: lobes = lobes[:4] if kind != "small" else lobes[:3]
    begin("bark", ao_floor=0.93)
    if kind == "oak": trunk(1.55, 0.19, 0.85, None, 14 if not lod else 8, lean=(0.0, 0.0))
    elif kind == "beech": trunk(2.1, 0.14, 0.7, None, 14 if not lod else 8)
    else:
        # the small tree keeps a pale trunk, a gentle lean, no stems or dark marks
        TS = [0, 0.012, 0.04, 0.1, 0.2, 0.35, 0.5, 0.7, 0.85, 1.0]
        H = 3.0; pts = [Vector((0.12 * t * t, -0.2 + (H + 0.2) * t, 0.05 * t)) for t in TS]
        add_tube(pts, 0.1, bark_fn(True), sides=12 if not lod else 7, radfn=lambda u: (lambda t: 0.105 * (1 + 0.5 * math.exp(-t * 10.0)) * (1 - 0.40 * t))(TS[min(len(TS) - 1, int(round(u * (len(TS) - 1))))]))
    begin("leaf")
    y0 = min(l[0][1] - l[2] for l in lobes); y1 = max(l[0][1] + l[2] for l in lobes)
    crown(lobes, PAL_LEAF, sub, y0, y1, {"oak": 11, "beech": 23, "small": 37}[kind] + (100 if lod else 0))
    return dict(kind="tree", canopy_radius=1.4, height=y1)

def conifer(iid, seed, H=3.9, R=1.2, lod=0):
    lib.reset(); reset()
    sub = 4 if not lod else 3
    begin("bark", ao_floor=0.93)
    trunk(1.2, 0.13 * R / 1.2, 0.9, None, 12 if not lod else 7, top_r=0.5)
    begin("leaf")
    k = R / 1.2; kh = H / 3.9
    # four soft stacked tiers, each a flattened rounded dome that overlaps the next; the top one is the rounded tip
    lobes = [L(0, 1.2 * kh, 0, 1.2 * k, 0.72 * kh, 1.2 * k), L(0, 1.9 * kh, 0, 0.98 * k, 0.66 * kh, 0.98 * k), L(0, 2.6 * kh, 0, 0.74 * k, 0.6 * kh, 0.74 * k), L(0, 3.3 * kh, 0, 0.47 * k, 0.56 * kh, 0.47 * k)]
    crown(lobes, PAL_CONIFER, sub, lobes[0][0][1] - lobes[0][2], lobes[-1][0][1] + lobes[-1][2], seed, bump=0.04)
    return dict(kind="conifer", canopy_radius=R, height=H)

def bush(iid, seed, R=1.0, nbl=6, hedge=False, lod=0):
    rng = random.Random(seed); lib.reset(); reset()
    begin("leaf")
    if hedge:
        lobes = [L(0, 0.30, 0, 1.0, 0.32, 0.32)]
        commit(lobe_bm(lobes[0][0], 1.0, 0.32, 0.32, 4, 0.0, seed, e=0.6), lobe_color(PAL_BUSH, lobes, 0, 0.0, 0.62, 1.0), sharp=100)
    else:
        lobes = [L(0, 0.40 * R, 0, 0.52 * R, 0.42 * R, 0.5 * R)]
        for i in range(4):
            a = i / 4 * 6.283 + rng.uniform(-0.3, 0.3)
            lobes.append(L(math.cos(a) * 0.48 * R, 0.30 * R, math.sin(a) * 0.46 * R, 0.34 * R, 0.30 * R, 0.33 * R))
        crown(lobes, PAL_BUSH, 4, 0.0, 0.85 * R, seed, bump=0.05)
    begin("bloom")
    if not hedge:
        for kk in range(nbl):
            c, rx, ry, rz = lobes[rng.randrange(len(lobes))]
            d = Vector((rng.uniform(-1, 1), rng.uniform(0.3, 1), rng.uniform(-1, 1))).normalized()
            p = Vector((c[0] + d.x * rx, c[1] + d.y * ry, c[2] + d.z * rz)) * 1.02
            def bcol(q, n): return mix((0.78, 0.75, 0.70), (0.97, 0.95, 0.90), clamp01(n.dot(SUN) * 0.5 + 0.5))
            commit(sph_bm(0.034, 0.028, 0.034, 1), bcol, sharp=100, xf=T(tuple(p)))
    return dict(kind="bush")

def flowers(iid, seed):
    """A small clump: short soft grass blades in the lawn green and a few small blooms (about half the old count and size)."""
    rng = random.Random(seed); lib.reset(); reset()
    begin("leaf")
    pal = PAL_LEAF
    def gcol(p, n): return mix(pal['shade'], pal['mid'], clamp01(p.y / 0.18) ** 0.8)
    for _ in range(16):
        a = rng.uniform(0, 6.28); d = math.sqrt(rng.random()) * 0.34
        base = Vector((math.cos(a) * d, 0, math.sin(a) * d * 0.85))
        hgt = rng.uniform(0.08, 0.17) * (1.15 - 0.5 * d / 0.34)
        dr = a + rng.uniform(-0.9, 0.9)
        lean = Vector((math.cos(dr), 0, math.sin(dr))) * hgt * rng.uniform(0.2, 0.5)
        pts = [base, base + lean * 0.3 + Vector((0, hgt * 0.55, 0)), base + lean + Vector((0, hgt, 0))]
        add_tube(pts, 0.02, gcol, sides=5, radfn=lambda t: 0.024 * (1 - 0.8 * t))
    begin("bloom")
    for k in range(4):
        a = k / 4 * 2 * math.pi + rng.uniform(-0.3, 0.3); d = 0.05 if k == 0 else rng.uniform(0.10, 0.26)
        fh = rng.uniform(0.15, 0.24)
        pos = Vector((math.cos(a) * d, fh, math.sin(a) * d * 0.85))
        commit(sph_bm(0.040, 0.030, 0.040, 1), lambda p, n: mix((0.78, 0.75, 0.70), (0.97, 0.95, 0.90), clamp01(n.dot(SUN) * 0.5 + 0.5)), sharp=100, xf=T(tuple(pos)))
    return dict(kind="flowers")

REG = [
    ("tree_a", lambda: deciduous("tree_a", "oak")),
    ("tree_b", lambda: deciduous("tree_b", "beech")),
    ("tree_c", lambda: deciduous("tree_c", "small")),
    ("pine_a", lambda: conifer("pine_a", 5, H=3.9, R=1.2)),
    ("pine_b", lambda: conifer("pine_b", 9, H=3.1, R=1.05)),
    ("tree_a_far", lambda: deciduous("tree_a_far", "oak", lod=1)),
    ("tree_b_far", lambda: deciduous("tree_b_far", "beech", lod=1)),
    ("tree_c_far", lambda: deciduous("tree_c_far", "small", lod=1)),
    ("pine_a_far", lambda: conifer("pine_a_far", 5, H=3.9, R=1.2, lod=1)),
    ("pine_b_far", lambda: conifer("pine_b_far", 9, H=3.1, R=1.05, lod=1)),
    ("bush_a", lambda: bush("bush_a", 3, nbl=6)),
    ("bush_b", lambda: bush("bush_b", 8, nbl=5, R=0.9)),
    ("hedge", lambda: bush("hedge", 5, R=1.0, hedge=True)),
    ("hedge_low", lambda: bush("hedge_low", 7, R=1.0, hedge=True)),
    ("flowers", lambda: flowers("flowers", 4)),
]

if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    import lib
    for iid, fn in REG:
        if only and iid not in only: continue
        meta = fn(); info = export(iid, meta)
        print("EXPORT", iid, info["tris"], info["verts"], [(s["name"], s["tris"]) for s in info["sub_meshes"]], flush=True)
