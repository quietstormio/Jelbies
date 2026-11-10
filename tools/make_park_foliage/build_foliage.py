"""Build the Park's foliage in headless Blender and export OBJ+JSON (round 2: leaf-card shells over dark cores).

  /Applications/Blender.app/Contents/MacOS/Blender -b -P build_foliage.py -- [ids...]
  python3 convert.py <export dir> BobV1/Room/Resources        # -> park_<id>.bin (same .bin format as decor_<id>.bin)

Assets: tree_a oak (wide, layered), tree_b beech/maple (tall oval), tree_c birch (airy, pale trunk), pine_a / pine_b spruce (tiers of drooping bough fans),
bush_a / bush_b shrubs, flowers (grass + small garden flowers), and cheap far-row variants <id>_far (about a third of the triangles).
Game coordinates (y up, +z toward the camera, origin = trunk foot / clump centre on the ground). Parts: "bark", "leaf", "bloom".
Every shape is CLOSED (the renderer culls back faces). Colours are baked per vertex: sun term (sun dir 0.45,0.8,0.4), AO between clumps, dark interior,
hue variation clump to clump. `bloom` parts are neutral cream so the game can tint them per bush.
"""
import sys, os, math, random
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from dk import *
from lib import nz
from mathutils import Vector
import bmesh

SUN = Vector((0.45, 0.8, 0.4)).normalized()
VIEW = Vector((0.0, 0.57, 0.82)).normalized()          # toward the park camera (elevation ~35 degrees, in front)
def clamp01(x): return max(0.0, min(1.0, x))
def rot_about(v, axis, ang):
    return Matrix.Rotation(ang, 3, axis) @ v


# ---------------------------------------------------------------- palettes (sRGB)
CORE = (0.10, 0.22, 0.11)
PAL_OAK = dict(shade=(0.10, 0.25, 0.11), mid=(0.22, 0.43, 0.15), sun=(0.42, 0.62, 0.20), hi=(0.55, 0.70, 0.26))
PAL_BEECH = dict(shade=(0.11, 0.26, 0.12), mid=(0.24, 0.45, 0.16), sun=(0.44, 0.63, 0.20), hi=(0.56, 0.71, 0.26))
PAL_BIRCH = dict(shade=(0.17, 0.33, 0.12), mid=(0.33, 0.52, 0.17), sun=(0.58, 0.72, 0.26), hi=(0.70, 0.80, 0.34))
PAL_SPRUCE = dict(shade=(0.05, 0.15, 0.11), mid=(0.12, 0.30, 0.18), sun=(0.27, 0.47, 0.23), hi=(0.36, 0.55, 0.28))
PAL_FIR = dict(shade=(0.06, 0.18, 0.12), mid=(0.15, 0.34, 0.18), sun=(0.33, 0.53, 0.23), hi=(0.42, 0.60, 0.28))
PAL_BUSH = dict(shade=(0.10, 0.25, 0.11), mid=(0.23, 0.43, 0.16), sun=(0.42, 0.62, 0.21), hi=(0.55, 0.70, 0.27))
YG = (0.42, 0.56, 0.13); BG = (0.12, 0.36, 0.26)

def pal_mix(pal, t):
    if t < 0.5: return mix(pal['shade'], pal['mid'], t * 2)
    if t < 0.88: return mix(pal['mid'], pal['sun'], (t - 0.5) / 0.38)
    return mix(pal['sun'], pal['hi'], (t - 0.88) / 0.12)

def light_t(p, n, masses, me, cc, cr, y0, y1, sunk=0.0):
    """0..1 light for a point: sun term on the (spherical) normal, height, AO from the other masses and from the crown interior."""
    s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
    h = clamp01((p.y - y0) / max(0.01, y1 - y0))
    q = p + n * 0.10
    occ = 0.0
    for i, (c, r) in enumerate(masses):
        if i == me: continue
        d = (q - c).length
        if d < r: occ += (1 - d / r)
    occ = min(1.0, occ)
    outer = clamp01((p - cc).length / cr)
    t = clamp01(0.04 + 0.70 * s01 ** 1.5 + 0.28 * h - 0.45 * occ * (1 - 0.4 * s01) - sunk)
    return t * (0.50 + 0.50 * outer)

# ---------------------------------------------------------------- shapes
def clump_bm(r, flat, sub, bump, seed, tall=1.0):
    """A lobed core / mass: displaced icosphere (smooth-shaded)."""
    bm = sph_bm(r, r * flat * tall, r, sub)
    for v in bm.verts:
        d = v.co.normalized()
        v.co = v.co * (1 + bump * (nz(d * 2.4, 1.0, seed) + 0.8 * nz(d * 5.2, 1.0, seed + 5)))
    return bm

def bough_bm(L, W, droop, thick=0.45, sides=6, segs=4, jag=0.0):
    """One tapered, down-curved spruce bough along +x (closed, pointed tip): the dark core of a spray."""
    bm = bmesh.new(); rings = []
    for k in range(segs + 1):
        t = k / segs
        c = Vector((L * t, -droop * t * t, 0))
        w = W * (0.55 + 0.45 * math.sin(math.pi * min(1.0, 0.28 + t * 0.62))) * (1 - t) ** 0.55 if k < segs else 0.0
        w *= 1 + jag * (1 if k % 2 else -1)
        if k == segs: rings.append([bm.verts.new(c + Vector((0.02 * L, -0.05 * droop, 0)))] * sides)
        else: rings.append([bm.verts.new(c + Vector((0, math.sin(2 * math.pi * i / sides) * w * thick, math.cos(2 * math.pi * i / sides) * w))) for i in range(sides)])
    for k in range(segs):
        for i in range(sides):
            j = (i + 1) % sides
            vs = [rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]]
            u = []
            for v in vs:
                if v not in u: u.append(v)
            if len(u) >= 3:
                try: bm.faces.new(u)
                except ValueError: pass
    bm.faces.new(rings[0][::-1])
    return bm

# ---------------------------------------------------------------- bark
BARK_SHADE = (0.25, 0.20, 0.16); BARK_SUN = (0.60, 0.51, 0.41)
def bark_fn(pale=False, seed=0.0):
    def fn(p, n):
        s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
        if pale:
            c = mix((0.46, 0.45, 0.42), (0.93, 0.92, 0.86), s01)
            m = nz(Vector((p.x * 3, p.y * 16, p.z * 3)), 1.0, seed)
            if m > 0.18 and p.y > 0.2: c = mix(c, (0.12, 0.10, 0.09), clamp01((m - 0.18) * 5))
            return c
        c = mix(BARK_SHADE, BARK_SUN, s01 ** 1.2)
        streak = 1 + 0.16 * nz(Vector((p.x * 22, p.y * 1.4, p.z * 22)), 1.0, seed)          # vertical value streaks
        fork = 1 - 0.30 * clamp01((p.y - 0.5) / 1.5) ** 2 * 0.0
        low = clamp01(1 - p.y / 1.2) * 0.18
        return tuple(max(0, min(1, x * streak * fork * (1 - low))) for x in c)
    return fn

# ---------------------------------------------------------------- leaf cards
def commit_raw(P, N, C, F):
    import dk as _dk; _dk.CUR['parts'].append(dict(P=P, N=N, C=C, F=F))

class Leaves:
    """Accumulates single-sided leaf cards (a pointed oval folded along its midrib: 2 triangles) with spherical-blend normals and baked colours."""
    def __init__(self): self.P = []; self.N = []; self.C = []; self.F = []
    def add(self, stem, axis, width_dir, L, W, n_shade, col, fold=0.12, soft=False):
        n_face = width_dir.cross(axis).normalized()
        if n_face.dot(n_shade) < 0: n_face = -n_face
        dark = tuple(c * 0.90 for c in col); lite = tuple(min(1.0, c * 1.04) for c in col)
        base = len(self.P)
        if soft:
            # a rounded, slightly cupped oval with a soft point: 4 triangles (base, two shoulders, tip); normal 85% mass-spherical / 15% leaf face
            nrm = (n_shade * 0.85 + n_face * 0.15).normalized()
            lift = L * fold
            pts = [stem,
                   stem + axis * (L * 0.38) + width_dir * (W * 0.5) + n_face * lift,
                   stem + axis * (L * 0.38) - width_dir * (W * 0.5) + n_face * lift,
                   stem + axis * (L * 0.74) + width_dir * (W * 0.34) + n_face * (lift * 0.8),
                   stem + axis * (L * 0.74) - width_dir * (W * 0.34) + n_face * (lift * 0.8),
                   stem + axis * L - n_face * (L * 0.02)]
            cols = [dark, col, col, col, col, lite]
            tris = ((0, 1, 2), (1, 3, 2), (2, 3, 4), (3, 5, 4))
        else:
            mid = stem + axis * (L * 0.46)
            pts = [stem, mid + width_dir * (W * 0.5) + n_face * (L * fold), mid - width_dir * (W * 0.5) + n_face * (L * fold), stem + axis * L + n_face * (L * 0.02)]
            cols = [tuple(c * 0.86 for c in col), col, col, lite]
            nrm = (n_shade * 0.7 + n_face * 0.3).normalized()
            tris = ((0, 1, 3), (0, 3, 2))
        for p, c in zip(pts, cols):
            self.P.append(tuple(p)); self.N.append(tuple(nrm)); self.C.append(c)
        for tri in tris:
            a, b, c2 = [self.P[base + i] for i in tri]
            nn = (Vector(b) - Vector(a)).cross(Vector(c2) - Vector(a))
            if nn.dot(n_face) >= 0: self.F.append((base + tri[0], base + tri[1], base + tri[2]))
            else: self.F.append((base + tri[0], base + tri[2], base + tri[1]))
    def flush(self):
        if self.P: commit_raw(self.P, self.N, self.C, self.F)
        self.__init__()

def rand_perp(rng, n):
    a = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1)))
    a = a - n * a.dot(n)
    return a.normalized() if a.length > 1e-4 else Vector((1, 0, 0))

def shell_leaves(lv, rng, masses, pal, cc, cr, y0, y1, Lm, Wr, dens, down=0.75, tilt=0.30, cover_top=0.97, cover_bot=0.65, sunk=0.0, hang=0.0, soft=False, ell=None, view=None, vs=0.0):
    """Leaf cards over every mass surface: tilted outward and downward, stem end toward the mass, sticking past the surface; coverage heavier on top."""
    cols = [(rng.uniform(-1, 1)) for _ in masses]
    for i, m in enumerate(masses):
        c, r, fl, tl = m
        ry = r * fl * tl
        area = 4 * math.pi * ((r * r * r * ry) ** (2 / 3))
        topness = clamp01((c.y - y0) / max(0.01, y1 - y0)) if view else 0.0
        n_try = int(area * dens * ((1 + 0.55 * vs) * (1 + 1.0 * vs * topness - 0.35 * vs * (1 - topness)) if view else 1))          # (and more on the top masses, fewer on the low ones)          # (more attempts where the camera looks: the rejected back / underside ones are not lost)
        hue = cols[i]
        for _ in range(n_try):
            d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
            n_out = Vector((d.x / r, d.y / ry, d.z / r)).normalized()
            keep = cover_bot + (cover_top - cover_bot) * clamp01(n_out.y * 0.5 + 0.5)
            if view:
                vis = clamp01((n_out.dot(view) + 0.35) / 1.0)
                keep *= (1 - vs) + vs * (0.12 + 0.88 * vis ** 0.8)          # the park camera pans but never orbits: leaves go to the top and the camera-facing side
            if rng.random() > keep: continue
            if soft and ell and rng.random() < 0.0: continue
            lump = 1 + 0.10 * nz(d * 2.6, 1.0, i * 1.7)
            p = c + Vector((d.x * r, d.y * ry, d.z * r)) * lump
            if any((p - c2).length < r2 * 0.80 for j, (c2, r2, f2, t2) in enumerate(masses) if j != i): continue
            down_v = Vector((0, -1, 0)); tg = down_v - n_out * down_v.dot(n_out)
            tg = tg.normalized() if tg.length > 0.15 else rand_perp(rng, n_out)
            axis = (tg * (down + hang * (1 - n_out.y)) + n_out * (0.16 if soft else tilt) + rand_perp(rng, n_out) * 0.35).normalized()
            wd = n_out.cross(axis)
            if wd.length < 1e-3: wd = rand_perp(rng, axis)
            wd = wd.normalized()
            roll = rng.uniform(-0.6, 0.6)
            wd = (wd * math.cos(roll) + n_out * math.sin(roll)).normalized()
            L = Lm * rng.uniform(0.8, 1.25)
            if view: L *= 1 + 0.22 * vs * max(0.0, n_out.y)          # somewhat larger leaves on the top shell
            if ell:
                q = math.sqrt(((p.x - cc.x) / ell[0]) ** 2 + ((p.z - cc.z) / ell[0]) ** 2 + ((p.y - cc.y) / ell[1]) ** 2)          # 1 = the crown's outer surface
                rim = clamp01((q - 0.82) / 0.18)
            else: rim = 0.0          # toward the crown's outer boundary (sides AND top): smaller, rounder leaves break the outline
            L *= 1 - (0.40 if soft else 0.38) * rim
            stem = p - n_out * (L * 0.18)
            t = light_t(p, n_out, [(m2[0], m2[1]) for m2 in masses], i, cc, cr, y0, y1, sunk)
            jit = 0.03 if soft else 0.07
            t = clamp01(t + rng.uniform(-jit, jit))
            if t > 0.8 and not (soft and n_out.y > 0.55 and rng.random() < 0.25) and rng.random() < 0.7: t = 0.8
            col = pal_mix(pal, t)
            hs = 0.12 if soft else 0.22
            if hue > 0: col = mix(col, YG, hs * hue * (0.4 + t))
            else: col = mix(col, BG, hs * -hue * (0.4 + t))
            v = 1 + rng.uniform(-(0.03 if soft else 0.06), 0.03 if soft else 0.06)
            col = tuple(min(1.0, x * v) for x in col)
            lv.add(stem, axis, wd, L, L * (Wr + 0.15 * rim if soft else Wr - 0.30 * rim), n_out, col, soft=soft)          # (far kites turn narrow and pointed at the rim: no square corners against the sky)

def core_masses(masses, cc, cr, y0, y1, pal, seed, sub=2, frac=0.68, bump=0.25, core=None, topsub=0):
    """The dark cores under the leaf shells. Colour is a leaf-shadow green, lighter toward the top (a top-light gradient), so a patch that shows reads as leaf mass in shade, not as a dark block."""
    lo = core or CORE
    hi = (min(1.0, lo[0] * 1.9), min(1.0, lo[1] * 1.7), min(1.0, lo[2] * 1.6))
    for i, (c, r, fl, tl) in enumerate(masses):
        def fn(p, n, c=c, r=r):
            t = clamp01(n.y * 0.5 + 0.5) ** 1.3
            col = mix(lo, hi, t)
            s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
            return tuple(min(1.0, x * (0.9 + 0.25 * s01)) for x in col)
        top = (c.y - y0) / max(0.01, y1 - y0)
        s_i, f_i = (topsub, frac * 0.85) if (topsub and top > 0.72) else (sub, frac)          # the top cores are rounder (more faces) and smaller: no straight-edged polygon under the camera
        commit(clump_bm(r * f_i, fl, s_i, bump, seed + i * 1.3, tl), fn, sharp=100, xf=T(tuple(c), ry=i * 1.3))

# ---------------------------------------------------------------- crowns + limbs
def crown_dome(rng, Rh, yb, Hc, nbig, rbig, tiers, droop):
    out = [(Vector((0, yb + Hc * 0.93, 0)), rbig * 1.05)]
    for i in range(nbig):
        a = rng.uniform(0, 6.283); rho = min(1.0, rng.random() ** 0.62)
        prof = math.sqrt(max(0, 1 - rho * rho)) ** 0.8
        v = rng.choice(tiers)
        y = yb + Hc * prof * v - droop * Hc * max(0, rho - 0.7) / 0.3
        r = rbig * (0.72 + 0.6 * (1 - rho)) * rng.uniform(0.85, 1.15)
        out.append((Vector((math.cos(a) * rho * Rh, y, math.sin(a) * rho * Rh * 0.95)), r))
    return out

def crown_oval(rng, Rh, yb, Hc, nbig, rbig, droop=0.0, shell=0.0):
    yc = yb + Hc / 2; out = []
    for i in range(nbig):
        d = Vector((rng.gauss(0, 1), rng.gauss(0, 1), rng.gauss(0, 1))).normalized()
        f = shell + (1 - shell) * rng.random() ** 0.45
        p = Vector((d.x * Rh * f, yc + d.y * Hc / 2 * f, d.z * Rh * f))
        rho = math.hypot(p.x, p.z) / Rh
        p.y -= droop * Hc * 0.5 * rho * rho
        out.append((p, rbig * (0.7 + 0.5 * (1 - f)) * rng.uniform(0.85, 1.15)))
    return out

def limbs(rng, top, Rh, yb, Hc, nm, r0, bfn, sides, lod, sub_n=(2, 3), up=0.0):
    tips = []
    az0 = rng.uniform(0, 6.283)
    sd = max(4, sides - (2 if lod else 0))
    for i in range(nm):
        az = az0 + i / nm * 6.283 + rng.uniform(-0.3, 0.3)
        dx, dz = math.cos(az), math.sin(az)
        M = Vector((dx * Rh * 0.42, yb + Hc * (0.30 + up) + rng.uniform(-0.1, 0.1), dz * Rh * 0.42))
        mid = (top + M) * 0.5 + Vector((0, 0.05, 0)) + Vector((dz, 0, -dx)) * rng.uniform(-0.12, 0.12)
        add_tube([top, mid, M], 0.05, bfn, sides=sd + 1, radfn=lambda t: r0 * 0.62 * (1 - 0.35 * t))
        tips.append(M)
        for j in range(rng.choice(sub_n)):
            az2 = az + rng.uniform(-0.8, 0.8)
            E = Vector((math.cos(az2) * Rh * rng.uniform(0.70, 0.92), yb + Hc * rng.uniform(0.28, 0.62 + up), math.sin(az2) * Rh * rng.uniform(0.70, 0.92)))
            mid2 = (M + E) * 0.5 + Vector((0, 0.08, 0))
            add_tube([M, mid2, E], 0.04, bfn, sides=max(4, sd - 1), radfn=lambda t: r0 * 0.34 * (1 - 0.55 * t))
            tips.append(E)
    return tips


def base_tufts(rng, rb, n, lod):
    """Low grass / leaf blades ringed round a trunk's foot: they hide the trunk's polygon rim against the lawn, so it reads as growing out of the ground (round, soft, no hard cut)."""
    lv = Leaves()
    for k in range(n):
        a = k / n * 2 * math.pi + rng.uniform(-0.12, 0.12)
        rad = rb * rng.uniform(0.95, 1.30)
        pw = Vector((math.cos(a) * rad, 0.0, math.sin(a) * rad))
        axis = Vector((math.cos(a) * 0.45, 1.0, math.sin(a) * 0.45)).normalized()
        n_out = Vector((math.cos(a) * 0.5, 1.0, math.sin(a) * 0.5)).normalized()
        wd = n_out.cross(axis)
        wd = wd.normalized() if wd.length > 1e-3 else Vector((1, 0, 0))
        Lc = rng.uniform(0.15, 0.26) * (1.2 if lod else 1.0) * (rb / 0.3)
        v = rng.uniform(0.9, 1.1)
        col = (0.20 * v, 0.40 * v, 0.14 * v)
        lv.add(pw - axis * Lc * 0.15, axis, wd, Lc, Lc * 0.30, n_out, col, fold=0.05)
    lv.flush()

def deciduous(iid, seed, spec, pal, lod=0, pale=False):
    rng = random.Random(seed); lib.reset(); reset()
    sides = 10 if lod == 0 else 5
    bfn = bark_fn(pale, seed)
    kind = spec['kind']
    begin("bark", ao_floor=0.93)
    H = spec['trunk']; r0 = spec['r0']; Rh = spec['Rh']; Hc = spec['Hc']; yb = spec.get('yb', H + 0.1)
    if pale:
        for k in range(spec['stems']):
            a = k / spec['stems'] * 6.283 + 0.6
            lean = Vector((math.cos(a), 0, math.sin(a))) * (0.10 + 0.08 * k)
            pts = [Vector((lean.x * (t ** 1.5) * 1.2, H * t, lean.z * (t ** 1.5) * 1.2)) for t in [i / 13 for i in range(14)]]
            add_tube(pts, 0.1, bfn, sides=6 if lod == 0 else 5, radfn=lambda t, k=k: r0 * (1 + 0.5 * max(0, 1 - t * 8) ** 2) * (1 - 0.55 * t) * (1 - 0.08 * k), cap=True)
        top = Vector((0.04, H, 0.02))
    else:
        TS = [0, 0.012, 0.03, 0.06, 0.11, 0.18, 0.3, 0.5, 0.7, 0.85, 1.0]
        pts = [Vector((0, -0.2 + (H + 0.2) * t, 0)) for t in TS]          # (starts a little below the ground)
        add_tube(pts, 0.1, bfn, sides=20 if lod == 0 else 16, radfn=lambda u: (lambda t: r0 * (1 + spec["flare"] * math.exp(-t * 12.0)) * (1 - 0.34 * t))(TS[min(len(TS) - 1, int(round(u * (len(TS) - 1))))]), cap=True)          # a smooth, round root flare into the ground
        top = pts[-1]
        Rb = r0 * (1 + spec['flare'])
    tips = limbs(rng, top, Rh, yb, Hc, spec['nm'], r0, bfn, sides, lod, up=spec.get('up', 0.0))
    nb = spec['nbig'] if not lod else max(10, int(spec['nbig'] * 0.55))
    if kind == 'dome': cl = crown_dome(rng, Rh, yb, Hc, nb, spec['rbig'] * (1.2 if lod else 1), spec['tiers'], spec['droop'])
    else: cl = crown_oval(rng, Rh, yb, Hc, nb, spec['rbig'] * (1.2 if lod else 1), spec.get('droop', 0.0), spec.get('shell', 0.0))
    flat = spec['flat']; tall = spec.get('tall', 1.0)
    masses = [(c, r, flat * rng.uniform(0.9, 1.1), tall) for c, r in cl]
    # thin twigs from the nearest limb end into the masses (seen in the gaps)
    if not lod:
        for i, m in enumerate(masses):
            if i % 2: continue
            e = min(tips, key=lambda t: (t - m[0]).length)
            if (e - m[0]).length < 1.0:
                add_tube([e, (e + m[0]) * 0.5 + Vector((0, 0.05, 0)), m[0]], 0.02, bfn, sides=4, radfn=lambda t: r0 * 0.13 * (1 - 0.6 * t))
    ctr = Vector((0, yb + Hc * 0.5, 0)); cr = max(Rh, Hc * 0.5) * 1.15
    y0 = yb; y1 = yb + Hc
    begin("leaf")
    core_masses(masses, ctr, cr, y0, y1, pal, seed, sub=2 if not lod else 1, frac=0.44 if lod else 0.60, core=(0.12, 0.26, 0.12) if lod else (0.11, 0.24, 0.11), topsub=2 if lod else 0)          # (a far core that peeks through reads as a leaf mass in shade, not a black polygon)
    lv = Leaves()
    dens = spec.get('dens_far', spec['dens'] * 0.45) if lod else spec['dens']
    Lm = spec['leaf'] * (1.65 if lod else 1.0)
    shell_leaves(lv, rng, masses, pal, ctr, cr, y0, y1, Lm, spec['wr'], dens, down=spec.get('down', 0.75), hang=spec.get('hang', 0.0), soft=bool(spec.get('soft')) and not lod, ell=(Rh, Hc / 2) if spec.get('soft') else None, view=VIEW if spec.get('soft') else None, vs=(0.7 if lod else 0.4))
    nleaf = len(lv.P) // 4
    lv.flush()
    return dict(kind="tree", canopy_radius=Rh, height=y1, leaves=nleaf)

OAK = dict(kind='dome', trunk=0.95, r0=0.19, flare=0.85, Rh=1.55, Hc=1.85, yb=1.2, nm=5, nbig=24, rbig=0.46, flat=0.66, tiers=[0.42, 0.62, 0.80, 0.97], droop=0.12,
           leaf=0.15, wr=0.80, dens=190, dens_far=104, soft=True)
BEECH = dict(kind='oval', trunk=1.2, r0=0.14, flare=0.7, Rh=1.1, Hc=2.7, yb=1.15, nm=4, nbig=36, rbig=0.34, flat=0.84, tall=1.1, up=0.1, shell=0.25, droop=0.15,
             leaf=0.12, wr=0.70, dens=340, dens_far=152, soft=True)
BIRCH = dict(kind='oval', trunk=2.2, r0=0.085, flare=0.4, Rh=1.15, Hc=2.5, yb=1.45, nm=4, nbig=60, rbig=0.19, flat=0.9, tall=2.2, up=0.1, shell=0.45, droop=1.0,
             leaf=0.12, wr=0.55, dens=520, stems=3, hang=0.9, down=1.0)

# ---------------------------------------------------------------- conifers
def conifer(iid, seed, tiers=10, H=3.9, R=1.2, pal=PAL_SPRUCE, lod=0, trunk_h=0.7):
    rng = random.Random(seed); lib.reset(); reset()
    begin("bark", ao_floor=0.93)
    bfn = bark_fn(False, seed)
    add_tube([Vector((0, 0, 0)), Vector((0, 0.5, 0)), Vector((0, 1.4, 0)), Vector((0, H * 0.8, 0)), Vector((0, H, 0))], 0.1, bfn, sides=6 if lod else 8,
             radfn=lambda t: 0.15 * (1 + 0.9 * max(0, 1 - t * 8) ** 2) * (1 - 0.88 * t))
    begin("leaf")
    lv = Leaves()
    ring = []
    for t in range(tiers):
        f = t / (tiers - 1)
        y = trunk_h + (H * 0.93 - trunk_h) * f
        rr = R * (1 - f) ** 0.8 + 0.10
        nb = max(6, int(round((13 - 4 * f) * (0.62 if lod else 1.0))))
        ring.append((y, rr, nb))
    cc = Vector((0, H * 0.5, 0)); cr = R * 1.1
    for ti, (y, rr, nb) in enumerate(ring):
        ph = rng.uniform(0, 6.28)
        for i in range(nb):
            a = ph + i / nb * 6.283 + rng.uniform(-0.12, 0.12)
            L = rr * rng.uniform(0.82, 1.12)
            W = max(0.10, rr * 0.40) * rng.uniform(0.9, 1.2)
            dr = L * rng.uniform(0.28, 0.42)
            xm = T((0, y + rng.uniform(-0.04, 0.04), 0), ry=-a, rz=rng.uniform(0.05, 0.22))
            bm = bough_bm(L, W * 0.62, dr, thick=0.55, sides=5, segs=3 if lod else 4, jag=0.0)
            commit(bm, lambda p, n: CORE, sharp=100, xf=xm)
            R3 = xm.to_3x3()
            ncard = (10 if lod else 26)
            for kk in range(ncard):
                t = rng.uniform(0.08, 0.98); sd = rng.uniform(-1, 1)
                loc = Vector((L * t, -dr * t * t + 0.02, sd * W * 0.55 * (1 - t) ** 0.5))
                pw = xm @ loc
                nloc = Vector((0.0, 0.55, sd * 0.6)).normalized()
                n_out = (R3 @ nloc).normalized()
                axis = (R3 @ Vector((0.75, -0.45, sd * 0.55 + rng.uniform(-0.3, 0.3)))).normalized()
                wd = n_out.cross(axis)
                if wd.length < 1e-3: wd = rand_perp(rng, axis)
                wd = wd.normalized()
                Lc = (0.24 if not lod else 0.34) * rng.uniform(0.8, 1.25)
                tt = light_t(pw, n_out, [], -1, cc, cr, trunk_h, H, 0.0) * (0.55 + 0.45 * clamp01(t * 1.3))
                tt = clamp01(tt + rng.uniform(-0.07, 0.07))
                col = pal_mix(pal, tt)
                col = tuple(min(1.0, x * (1 + rng.uniform(-0.06, 0.06))) for x in col)
                lv.add(pw - axis * Lc * 0.1, axis, wd, Lc, Lc * 0.24, n_out, col, fold=0.08)
    nleaf = len(lv.P) // 4
    lv.flush()
    # a real pointed leader: a fine needle-coloured cone (no dark disc) with a spray of upward needle cards round it
    topy = ring[-1][0]
    tip = H + 0.20
    lead = lathe_bm([(0, topy - 0.12), (0.10, topy - 0.04), (0.06, topy + (tip - topy) * 0.45), (0.025, topy + (tip - topy) * 0.8), (0, tip)], 8)
    commit(lead, lambda p, n: pal_mix(pal, 0.50 + 0.2 * clamp01(n.y)), sharp=100)
    lv = Leaves()
    for kk in range(26 if not lod else 12):
        a = kk / (26 if not lod else 12) * 6.283 + rng.uniform(-0.2, 0.2)
        yy = topy - 0.02 + (tip - topy) * rng.uniform(0.0, 0.7)
        rad = 0.05 * (1 - (yy - topy) / (tip - topy + 0.01))
        pw = Vector((math.cos(a) * rad, yy, math.sin(a) * rad))
        axis = Vector((math.cos(a) * 0.55, 1.0, math.sin(a) * 0.55)).normalized()
        n_out = Vector((math.cos(a), 0.6, math.sin(a))).normalized()
        wd = n_out.cross(axis).normalized()
        Lc = (0.24 if not lod else 0.32) * rng.uniform(0.85, 1.25) * (1 - 0.35 * (yy - topy) / (tip - topy + 0.01))
        col = pal_mix(pal, clamp01(0.55 + rng.uniform(-0.1, 0.12)))
        lv.add(pw - axis * Lc * 0.1, axis, wd, Lc, Lc * 0.30, n_out, col, fold=0.06)
    nleaf += len(lv.P) // 4
    lv.flush()
    return dict(kind="conifer", canopy_radius=R, height=H + 0.12, leaves=nleaf)

# ---------------------------------------------------------------- shrubs
def bush(iid, seed, R=1.0, nbl=14, hedge=False, lod=0, lite=False):
    rng = random.Random(seed); lib.reset(); reset()
    masses = []
    if hedge:
        for i in range(7): masses.append((Vector(((i - 3) * 0.30, 0.27, 0)), 0.30, 0.9, 1.0))
    else:
        masses.append((Vector((0, 0.42 * R, 0)), 0.42 * R, 0.85, 1.0))
        for i in range(8):
            a = rng.uniform(0, 6.28); d = R * rng.uniform(0.25, 0.80)
            hh = R * (0.20 + 0.45 * (1 - d / R))
            masses.append((Vector((math.cos(a) * d * 1.1, hh * rng.uniform(0.7, 1.1), math.sin(a) * d * 0.85)), R * rng.uniform(0.24, 0.34), 0.85, 1.0))
    ctr = Vector((0, 0.4 * R, 0)); cr = R * 1.2
    begin("bark", ao_floor=0.93)
    for k in range(3):
        a = rng.uniform(0, 6.28)
        add_tube([Vector((math.cos(a) * 0.08, 0, math.sin(a) * 0.08)), Vector((math.cos(a) * 0.14, 0.2 * R, math.sin(a) * 0.14))], 0.02, bark_fn(False, seed), sides=4, radfn=lambda t: 0.035 * (1 - 0.4 * t))
    begin("leaf")
    core_masses(masses, ctr, cr, 0.0, R * 0.95, PAL_BUSH, seed, sub=2, frac=0.82, bump=0.22)
    lv = Leaves()
    shell_leaves(lv, rng, masses, PAL_BUSH, ctr, cr, 0.0, R * 0.95, 0.10, 0.60, 540 if not hedge else (250 if lite else 600), down=0.5, tilt=0.55, cover_top=0.95, cover_bot=0.8, sunk=0.03)
    lv.flush()
    begin("bloom")
    if not hedge:
        for k in range(nbl):
            c, r, f, t = masses[rng.randrange(len(masses))]
            d = Vector((rng.uniform(-1, 1), rng.uniform(0.3, 1), rng.uniform(-1, 1))).normalized()
            p = c + Vector((d.x * r, d.y * r * 0.8, d.z * r)) * 1.08
            def bcol(q, n): return mix((0.72, 0.68, 0.64), (1.0, 0.99, 0.96), clamp01(n.dot(SUN) * 0.5 + 0.5))
            commit(sph_bm(0.045, 0.035, 0.045, 1), bcol, sharp=100, xf=T(tuple(p)))
    return dict(kind="bush")

def flowers(iid, seed):
    rng = random.Random(seed); lib.reset(); reset()
    g0 = (0.10, 0.27, 0.10); g1 = (0.42, 0.62, 0.20)
    begin("leaf")
    def gcol(p, n): return mix(g0, g1, clamp01(p.y / 0.34) ** 0.8)
    for _ in range(34):
        a = rng.uniform(0, 6.28); d = math.sqrt(rng.random()) * 0.40
        base = Vector((math.cos(a) * d, 0, math.sin(a) * d * 0.85))
        hgt = rng.uniform(0.14, 0.32) * (1.15 - 0.5 * d / 0.4)
        dr = a + rng.uniform(-0.9, 0.9)
        lean = Vector((math.cos(dr), 0, math.sin(dr))) * hgt * rng.uniform(0.25, 0.7)
        pts = [base, base + lean * 0.3 + Vector((0, hgt * 0.55, 0)), base + lean + Vector((0, hgt, 0))]
        add_tube(pts, 0.02, gcol, sides=3, radfn=lambda t: 0.020 * (1 - 0.95 * t))
    begin("bloom")
    for k in range(7):
        a = k / 7 * 2 * math.pi + rng.uniform(-0.3, 0.3); d = 0.06 if k == 0 else rng.uniform(0.12, 0.34)
        fh = rng.uniform(0.20, 0.34)
        pos = Vector((math.cos(a) * d, fh, math.sin(a) * d * 0.85))
        commit(sph_bm(0.062, 0.045, 0.062, 1), lambda p, n: mix((0.70, 0.66, 0.62), (1.0, 0.99, 0.96), clamp01(n.dot(SUN) * 0.5 + 0.5)), sharp=100, xf=T(tuple(pos)))
    return dict(kind="flowers")

REG = [
    ("tree_a", lambda: deciduous("tree_a", 11, OAK, PAL_OAK)),
    ("tree_b", lambda: deciduous("tree_b", 23, BEECH, PAL_BEECH)),
    ("tree_c", lambda: deciduous("tree_c", 37, BIRCH, PAL_BIRCH, pale=True)),
    ("pine_a", lambda: conifer("pine_a", 5, tiers=10, H=3.9, R=1.2, pal=PAL_SPRUCE)),
    ("pine_b", lambda: conifer("pine_b", 9, tiers=9, H=3.1, R=1.05, pal=PAL_FIR)),
    ("tree_a_far", lambda: deciduous("tree_a_far", 11, OAK, PAL_OAK, lod=1)),
    ("tree_b_far", lambda: deciduous("tree_b_far", 23, BEECH, PAL_BEECH, lod=1)),
    ("tree_c_far", lambda: deciduous("tree_c_far", 37, BIRCH, PAL_BIRCH, lod=1, pale=True)),
    ("pine_a_far", lambda: conifer("pine_a_far", 5, tiers=9, H=3.9, R=1.2, pal=PAL_SPRUCE, lod=1)),
    ("pine_b_far", lambda: conifer("pine_b_far", 9, tiers=8, H=3.1, R=1.05, pal=PAL_FIR, lod=1)),
    ("bush_a", lambda: bush("bush_a", 3, nbl=12)),
    ("bush_b", lambda: bush("bush_b", 8, nbl=10, R=0.9)),
    ("hedge", lambda: bush("hedge", 5, R=1.0, hedge=True)),
    ("hedge_low", lambda: bush("hedge_low", 7, R=1.0, hedge=True, lite=True)),
    ("flowers", lambda: flowers("flowers", 4)),
]

if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    import lib
    for iid, fn in REG:
        if only and iid not in only: continue
        meta = fn(); info = export(iid, meta)
        print("EXPORT", iid, info["tris"], info["verts"], meta.get("leaves", ""), [(s["name"], s["tris"]) for s in info["sub_meshes"]], flush=True)
