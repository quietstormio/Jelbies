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

def crown(lobes, pal, sub, y0, y1, seed, bump=0.05, tones=None):
    rng = random.Random(seed)
    for i, (c, rx, ry, rz) in enumerate(lobes):
        tone = tones[i] if tones else 1.0
        commit(lobe_bm(c, rx, ry, rz, sub, bump, seed + i * 1.7), lobe_color(pal, lobes, i, y0, y1, tone * (1 + rng.uniform(-0.03, 0.03))), sharp=100)

def trunk(H, r0, flare, bfn, sides, lean=(0.0, 0.0), top_r=0.62):
    TS = [0, 0.012, 0.03, 0.055, 0.09, 0.14, 0.21, 0.3, 0.42, 0.56, 0.72, 0.86, 1.0]
    pts = [Vector((lean[0] * t * t, -0.2 + (H + 0.2) * t, lean[1] * t * t)) for t in TS]          # (starts a little below the ground)
    add_tube(pts, 0.1, bark_fn(False), sides=sides, radfn=lambda u: (lambda t: r0 * (1 + flare * math.exp(-t * 11.0)) * (1 - (1 - top_r) * t))(TS[min(len(TS) - 1, int(round(u * (len(TS) - 1))))]), cap=True)
    return pts[-1]

def L(x, y, z, rx, ry, rz): return ((x, y, z), rx, ry, rz)

def cluster(rng, yc, Rx, Ry, n, rl, f0=0.74, low=-0.45, squash=0.84):
    """A crown made of n small rounded lobes on / just inside an ellipsoid (centre y yc, radii Rx, Ry): fibonacci spiral over the upper and side surface, a few inner lobes
    to fill; lobe size rl * Rx. Returns (lobes, tones): lighter value toward the top and outside, darker underneath and inside (the original park trees' look)."""
    lobes = []; tones = []
    for i in range(n):
        y = 1 - (1 - low) * (i + 0.5) / n
        rho = math.sqrt(max(0.0, 1 - y * y)); th = i * 2.39996 + rng.uniform(-0.25, 0.25)
        f = f0 + rng.uniform(-0.06, 0.06)
        c = (Rx * rho * math.cos(th) * f, yc + Ry * y * f, Rx * rho * math.sin(th) * f * 0.95)
        r = rl * Rx * rng.uniform(0.82, 1.2)
        lobes.append((c, r, r * squash, r * 0.96))
        tones.append(0.84 + 0.24 * clamp01((y + 1) / 2) + 0.05 * (f - f0) / 0.06 * 0.2)
    for k in range(3):
        a = k * 2.1 + rng.uniform(0, 1)
        r = rl * Rx * 1.35
        lobes.append(((0.3 * Rx * math.cos(a), yc + (0.15 - 0.15 * k) * Ry, 0.3 * Rx * math.sin(a)), r, r * squash, r))
        tones.append(0.80)
    return lobes, tones

KINDS = {"oak": dict(yc=1.65, Rx=1.32, Ry=0.76, n=22, rl=0.30, far=11, seed=11, trunk=(1.45, 0.19, 0.85)),
         "beech": dict(yc=2.05, Rx=1.0, Ry=1.02, n=22, rl=0.34, far=11, seed=23, trunk=(1.9, 0.14, 0.7)),
         "small": dict(yc=2.6, Rx=0.9, Ry=0.58, n=14, rl=0.36, far=8, seed=37, trunk=None)}

def deciduous(iid, kind, lod=0):
    lib.reset(); reset()
    sub = 3
    k = KINDS[kind]; rng = random.Random(k["seed"] + (100 if lod else 0))
    begin("bark", ao_floor=0.93)
    if k["trunk"]: trunk(k["trunk"][0], k["trunk"][1], k["trunk"][2], None, 14 if not lod else 8)
    else:
        # the small tree keeps a pale trunk, a gentle lean, no stems or dark marks
        TS = [0, 0.012, 0.04, 0.1, 0.2, 0.35, 0.5, 0.7, 0.85, 1.0]
        H = 2.6; pts = [Vector((0.12 * t * t, -0.2 + (H + 0.2) * t, 0.05 * t)) for t in TS]
        add_tube(pts, 0.1, bark_fn(True), sides=12 if not lod else 7, radfn=lambda u: (lambda t: 0.105 * (1 + 0.5 * math.exp(-t * 10.0)) * (1 - 0.40 * t))(TS[min(len(TS) - 1, int(round(u * (len(TS) - 1))))]))
    begin("leaf")
    lobes, tones = cluster(rng, k["yc"], k["Rx"], k["Ry"], k["far"] if lod else k["n"], k["rl"] * (1.25 if lod else 1.0))
    y0 = min(l[0][1] - l[2] for l in lobes); y1 = max(l[0][1] + l[2] for l in lobes)
    crown(lobes, PAL_LEAF, sub, y0, y1, k["seed"] + (100 if lod else 0), tones=tones)
    return dict(kind="tree", canopy_radius=1.4, height=y1)

def conifer(iid, seed, H=3.9, R=1.2, lod=0):
    """Four scalloped tiers (a soft lip, a rising cone, a soft rounded tip), wobbling radius, dark-to-light gradient, all smooth."""
    lib.reset(); reset()
    rng = random.Random(seed)
    begin("bark", ao_floor=0.93)
    trunk(1.0, 0.13 * R / 1.2, 0.9, None, 12 if not lod else 7, top_r=0.5)
    begin("leaf")
    k = R / 1.2; kh = H / 3.9; segs = 48 if not lod else 36
    tiers = [(0.8, 1.2, 1.2), (1.55, 0.98, 1.15), (2.3, 0.75, 1.05), (3.0, 0.5, 0.9)]
    tops = []
    for ti, (y0, rb, hh) in enumerate(tiers):
        y0 *= kh; rb *= k; hh *= kh
        prof = [(0.0, y0 - 0.10 * kh), (0.55 * rb, y0 - 0.07 * kh), (0.92 * rb, y0 - 0.02 * kh), (rb, y0 + 0.05 * kh)]
        for j in range(1, 11):          # a convex, dome-like flank rising to a soft rounded tip (no straight cone lines)
            u = j / 10.0
            prof.append((max(rb * (1 - u ** 1.7) ** 0.62 * 0.98, 0.07 * rb if u == 1 else 0.0), y0 + 0.05 * kh + (hh - 0.05 * kh) * u))
        prof.append((0.0, y0 + hh + 0.03 * kh))
        bm = lathe_bm(prof, segs)
        ph = rng.uniform(0, 6.28)
        for v in bm.verts:
            rad = math.hypot(v.co.x, v.co.z)
            if rad > 1e-5:
                ang = math.atan2(v.co.z, v.co.x)
                w = 1 + (0.13 * math.sin(ang * 3 + ph) + 0.07 * math.sin(ang * 7 + ph * 2)) * min(1.0, rad / rb)
                v.co.x *= w; v.co.z *= w
        ytop = y0 + hh
        def col(p, n, y0=y0, ytop=ytop, ti=ti):
            s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
            h = clamp01((p.y - y0) / max(0.01, ytop - y0))
            t = clamp01(0.04 + 0.36 * s01 ** 1.3 + 0.44 * h + 0.12 * ti / 3 - (0.12 if n.y < -0.3 else 0))
            return pal_mix(PAL_CONIFER, t)
        commit(bm, col, sharp=100)
    return dict(kind="conifer", canopy_radius=R, height=H)

def row_hedge(rng, nlow, sub):
    L_ = []
    for i in range(nlow):
        x = (i - (nlow - 1) / 2) * (1.8 / max(1, nlow - 1)) * 1.0
        r = 0.30 * rng.uniform(0.92, 1.1)
        L_.append(((x, 0.26, rng.uniform(-0.03, 0.03)), r, r * 0.9, r))
    return L_

def bush(iid, seed, R=1.0, nbl=6, hedge=False, lod=0):
    rng = random.Random(seed); lib.reset(); reset()
    begin("leaf")
    tones = None
    if hedge:
        lobes = row_hedge(rng, 8, 3)
        top = []
        for i in range(7):
            x = (i - 3) * 0.28; r = 0.25 * rng.uniform(0.9, 1.1)
            top.append(((x, 0.40, rng.uniform(-0.04, 0.04)), r, r * 0.85, r * 0.95))
        if iid == "hedge_low": top = []
        lobes += top
        tones = [0.92] * 8 + [1.06] * len(top)
        crown(lobes, PAL_BUSH, 3, 0.0, 0.62, seed, bump=0.04, tones=tones)
    else:
        lobes = [L(0, 0.40 * R, 0, 0.42 * R, 0.36 * R, 0.4 * R)]
        tones = [0.9]
        for i in range(7):
            a = i / 7 * 6.283 + rng.uniform(-0.3, 0.3)
            r = rng.uniform(0.26, 0.32) * R
            lobes.append(L(math.cos(a) * 0.50 * R, 0.24 * R + rng.uniform(0, 0.1) * R, math.sin(a) * 0.48 * R, r, r * 0.86, r)); tones.append(0.92)
        for i in range(2):
            a = rng.uniform(0, 6.28); r = 0.26 * R
            lobes.append(L(math.cos(a) * 0.22 * R, 0.66 * R, math.sin(a) * 0.2 * R, r, r * 0.86, r)); tones.append(1.1)
        crown(lobes, PAL_BUSH, 3, 0.0, 0.85 * R, seed, bump=0.05, tones=tones)
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
