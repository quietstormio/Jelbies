"""Build the Park's foliage in headless Blender and export OBJ+JSON (2026-11-09 redesign: structured trees, not cotton-ball canopies).

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
def clamp01(x): return max(0.0, min(1.0, x))
def rot_about(v, axis, ang):
    return Matrix.Rotation(ang, 3, axis) @ v

# ---------------------------------------------------------------- palettes (sRGB)
PAL_OAK = dict(shade=(0.10, 0.25, 0.11), mid=(0.22, 0.43, 0.15), sun=(0.46, 0.62, 0.20))
PAL_BEECH = dict(shade=(0.11, 0.27, 0.12), mid=(0.25, 0.46, 0.16), sun=(0.50, 0.66, 0.21))
PAL_BIRCH = dict(shade=(0.17, 0.34, 0.13), mid=(0.33, 0.52, 0.17), sun=(0.60, 0.72, 0.27))
PAL_SPRUCE = dict(shade=(0.06, 0.18, 0.14), mid=(0.12, 0.31, 0.19), sun=(0.28, 0.48, 0.24))
PAL_FIR = dict(shade=(0.07, 0.20, 0.13), mid=(0.15, 0.35, 0.18), sun=(0.34, 0.54, 0.24))
PAL_BUSH = dict(shade=(0.11, 0.26, 0.12), mid=(0.23, 0.43, 0.16), sun=(0.44, 0.62, 0.21))
YG = (0.42, 0.56, 0.13); BG = (0.12, 0.36, 0.26)

def pal_mix(pal, t):
    return mix(pal['shade'], pal['mid'], t * 2) if t < 0.5 else mix(pal['mid'], pal['sun'], (t - 0.5) * 2)

def leaf_color(pal, clumps, me, cc, cr, y0, y1, hue=0.0, seed=0.0, sunk=0.0):
    """Vertex colour fn for a leaf clump: sun term, AO from the other clumps, dark interior, hue drift, fine speckle."""
    def fn(p, n):
        s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
        h = clamp01((p.y - y0) / max(0.01, y1 - y0))
        q = p + n * 0.10
        occ = 0.0
        for i, (c, r) in enumerate(clumps):
            if i == me: continue
            d = (q - c).length
            if d < r: occ += (1 - d / r)
        occ = min(1.0, occ)
        outer = clamp01((p - cc).length / cr)
        t = clamp01(0.06 + 0.62 * s01 ** 1.4 + 0.30 * h - 0.42 * occ * (1 - 0.4 * s01) - sunk)
        t *= 0.58 + 0.42 * outer
        col = pal_mix(pal, t)
        if hue > 0: col = mix(col, YG, 0.28 * hue * (0.4 + t))
        elif hue < 0: col = mix(col, BG, 0.28 * -hue * (0.4 + t))
        sp = 1 + 0.07 * nz(p, 9.0, seed)
        return tuple(min(1.0, c * sp) for c in col)
    return fn

# ---------------------------------------------------------------- shapes
def clump_bm(r, flat, sub, bump, seed, tall=1.0):
    """A lobed, faceted leaf mass: displaced icosphere with strong medium-frequency breakup."""
    bm = sph_bm(r, r * flat * tall, r, sub)
    for v in bm.verts:
        d = v.co.normalized()
        k = 1 + bump * (nz(d * 2.1, 1.0, seed) + 0.55 * nz(d * 4.6, 1.0, seed + 5) + 0.3 * nz(d * 9.0, 1.0, seed + 9))
        v.co = v.co * k
    return bm

def bough_bm(L, W, droop, thick=0.45, sides=6, segs=4, jag=0.0):
    """One tapered, down-curved spruce bough along +x (closed, pointed tip)."""
    bm = bmesh.new(); rings = []
    for k in range(segs + 1):
        t = k / segs
        c = Vector((L * t, -droop * t * t, 0))
        w = W * (0.55 + 0.45 * math.sin(math.pi * min(1.0, 0.28 + t * 0.62))) * (1 - t) ** 0.55 if k < segs else 0.0
        w *= 1 + jag * (1 if k % 2 else -1)
        if k == segs: rings.append([bm.verts.new(c + Vector((0.02 * L, -0.05 * droop, 0)))] * sides)
        else: rings.append([bm.verts.new(c + Vector((0, math.sin(2 * math.pi * i / sides) * w * thick, math.cos(2 * math.pi * i / sides) * w)) ) for i in range(sides)])
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
BARK_SHADE = (0.20, 0.16, 0.13); BARK_SUN = (0.46, 0.38, 0.30)
def bark_fn(pale=False, seed=0.0):
    def fn(p, n):
        s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
        if pale:
            c = mix((0.46, 0.45, 0.42), (0.93, 0.92, 0.86), s01)
            m = nz(Vector((p.x * 3, p.y * 9, p.z * 3)), 1.0, seed)
            if m > 0.30 and p.y > 0.25: c = mix(c, (0.14, 0.12, 0.11), clamp01((m - 0.30) * 4))
            return c
        c = mix(BARK_SHADE, BARK_SUN, s01 ** 1.2)
        k = 1 + 0.10 * nz(Vector((p.x * 7, p.y * 2.2, p.z * 7)), 1.0, seed)
        low = clamp01(1 - p.y / 1.2) * 0.18
        return tuple(max(0, min(1, x * k * (1 - low))) for x in c)
    return fn

def limb(p0, p1, r0, r1, bend, rng, bfn, sides, flare=0.0):
    mid = (p0 + p1) * 0.5 + bend
    pts = [p0, p0 + (mid - p0) * 0.66 + (p1 - p0) * 0.0, mid, p1] if False else [p0, p0 + (mid - p0) * 1.0 * 0.7 + (p1 - p0) * 0.15, mid + (p1 - mid) * 0.5, p1]
    add_tube(pts, 0.05, bfn, sides=sides, radfn=lambda t: (r0 + (r1 - r0) * t) * (1 + flare * (1 - t) ** 6), cap=True)

lod_bark = True
def grow(rng, p, d, L, r, depth, maxd, spec, bfn, sides, tips, mids):
    droop = spec.get('droop', 0.25)
    end = p + d * L + Vector((0, -droop * L * 0.35 * (1 - depth / (maxd + 1)), 0))
    bend = Vector((rng.uniform(-1, 1), rng.uniform(-0.3, 0.5), rng.uniform(-1, 1))) * L * 0.10
    r1 = r * spec.get('taper', 0.55)
    limb(p, end, r, r1, bend, rng, bfn, (sides if depth < 2 else max(4, sides - 2)) if lod_bark else 4)
    dn = (end - p).normalized()
    if depth >= maxd:
        tips.append((end, dn, r1))
        return
    if depth >= maxd - 1: mids.append((p + (end - p) * 0.5, dn, r))
    n = rng.choice(spec['nchild'][min(depth, len(spec['nchild']) - 1)])
    az0 = rng.uniform(0, 6.283)
    for i in range(n):
        az = az0 + i / n * 6.283 + rng.uniform(-0.4, 0.4)
        ang = rng.uniform(*spec['spread'])
        side = Vector((math.cos(az), 0, math.sin(az)))
        ax = dn.cross(side) if abs(dn.y) < 0.95 else Vector((1, 0, 0))
        if ax.length < 1e-4: ax = Vector((1, 0, 0))
        nd = rot_about(dn, ax.normalized(), -ang if rng.random() < 0.5 else ang) if False else (dn * math.cos(ang) + side * math.sin(ang))
        nd = (nd + Vector((0, spec.get('up', 0.12), 0))).normalized()
        if i == 0 and n > 1 and rng.random() < 0.7: nd = (dn * 0.8 + Vector((0, 0.2, 0))).normalized()          # a continuing leader
        grow(rng, end, nd, L * rng.uniform(*spec['shrink']), r1 * spec.get('child_r', 0.78), depth + 1, maxd, spec, bfn, sides, tips, mids)

# ---------------------------------------------------------------- deciduous trees
def deciduous(iid, seed, spec, pal, lod=0, pale=False):
    rng = random.Random(seed); lib.reset(); reset()
    global lod_bark
    lod_bark = lod == 0
    sides = 7 if lod == 0 else 4
    bfn = bark_fn(pale, seed)
    begin("bark")
    H = spec['trunk']
    lean = Vector((rng.uniform(-1, 1), 0, rng.uniform(-1, 1))) * spec.get('lean', 0.06)
    pts = [Vector((lean.x * t * t, H * t, lean.z * t * t)) for t in [i / 5 for i in range(6)]]
    r0 = spec['r0']
    add_tube(pts, 0.1, bfn, sides=sides + 1, radfn=lambda t: r0 * (1 + spec.get('flare', 1.0) * (1 - t * 3.0 if t < 0.33 else 0) ** 2) * (1 - 0.40 * t), cap=True)
    top = pts[-1]
    tips = []; mids = []
    nm = spec['nmain']
    az0 = rng.uniform(0, 6.283)
    maxd = spec['depth'] - (1 if lod else 0)
    for i in range(nm):
        az = az0 + i / nm * 6.283 + rng.uniform(-0.35, 0.35)
        el = math.radians(rng.uniform(*spec['elev']))
        d = Vector((math.cos(az) * math.cos(el), math.sin(el), math.sin(az) * math.cos(el)))
        grow(rng, top - Vector((0, 0.05, 0)), d, spec['L'] * rng.uniform(0.85, 1.15), r0 * 0.62, 0, maxd, spec, bfn, sides, tips, mids)
    # a leader on the straight-up trunk for upright species
    if spec.get('leader', 0) > 0:
        grow(rng, top - Vector((0, 0.05, 0)), Vector((rng.uniform(-0.15, 0.15), 1, rng.uniform(-0.15, 0.15))).normalized(), spec['L'] * spec['leader'], r0 * 0.5, 0, maxd, spec, bfn, sides, tips, mids)
    # leaf anchors
    anchors = []
    for (e, dn, r) in tips:
        c = e + dn * spec['cr'] * 0.25 + Vector((0, spec['cr'] * spec.get('lift', 0.3), 0))
        anchors.append((c, spec['cr'] * rng.uniform(0.85, 1.15)))
    for (m, dn, r) in mids:
        if rng.random() < spec.get('midp', 0.4) and lod == 0:
            anchors.append((m + Vector((0, spec['cr'] * 0.30, 0)), spec['cr'] * rng.uniform(0.6, 0.85)))
    if lod:
        anchors = [(c, r * 1.3) for c, r in anchors]
    ctr = Vector((0, 0, 0)); 
    for c, r in anchors: ctr += c
    ctr /= max(1, len(anchors))
    cr = max((c - ctr).length + r for c, r in anchors)
    y0 = min(c.y - r * spec['flat'] for c, r in anchors); y1 = max(c.y + r * spec['flat'] * spec.get('tall', 1) for c, r in anchors)
    begin("leaf")
    ntuft = 1 if lod == 0 else 0
    for i, (c, r) in enumerate(anchors):
        sub = 3 if (lod == 0 and r > spec['cr'] * 1.12) else 2
        col = leaf_color(pal, anchors, i, ctr, cr, y0, y1, hue=rng.uniform(-1, 1), seed=i * 3.1)
        commit(clump_bm(r, spec['flat'], sub, spec.get('bump', 0.20), seed + i * 1.7, spec.get('tall', 1)), col, sharp=spec.get('sharp', 38), xf=T(tuple(c), ry=rng.uniform(0, 6.28)))
        for k in range(ntuft):
            d = Vector((rng.uniform(-1, 1), rng.uniform(-0.1, 1), rng.uniform(-1, 1))).normalized()
            tr = r * rng.uniform(0.26, 0.38)
            tp = c + Vector((d.x * r, d.y * r * spec['flat'], d.z * r)) * 0.9
            col2 = leaf_color(pal, anchors, i, ctr, cr, y0, y1, hue=rng.uniform(-1, 1), seed=60 + i)
            commit(clump_bm(tr, 0.7, 1, 0.25, seed + 40 + i * 5 + k), col2, sharp=40, xf=T(tuple(tp), ry=rng.uniform(0, 6.28)))
    return dict(kind="tree", canopy_radius=cr, height=y1)

OAK = dict(trunk=1.05, r0=0.15, flare=1.3, nmain=4, elev=(26, 46), L=0.80, depth=3, nchild=[(2, 3), (2, 2), (2, 2)], spread=(0.55, 0.95), shrink=(0.62, 0.8),
           up=0.10, droop=0.35, cr=0.40, flat=0.62, lift=0.10, midp=0.75, bump=0.24, lean=0.08, taper=0.62, child_r=0.72)
BEECH = dict(trunk=1.35, r0=0.13, flare=0.9, nmain=4, elev=(52, 70), L=0.80, depth=3, nchild=[(2, 3), (2, 2), (2, 2)], spread=(0.35, 0.7), shrink=(0.65, 0.85),
             up=0.22, droop=0.1, cr=0.36, flat=0.78, tall=1.15, lift=0.12, midp=0.75, bump=0.22, leader=1.0, lean=0.06, taper=0.6, child_r=0.7)
BIRCH = dict(trunk=1.9, r0=0.085, flare=0.6, nmain=3, elev=(58, 74), L=0.85, depth=3, nchild=[(2, 3), (2, 2), (2, 2)], spread=(0.3, 0.7), shrink=(0.6, 0.78),
             up=0.15, droop=0.45, cr=0.24, flat=0.9, tall=1.5, lift=-0.06, midp=0.6, bump=0.26, leader=0.9, lean=0.14, taper=0.55, child_r=0.65, sharp=44)

# ---------------------------------------------------------------- conifers
def conifer(iid, seed, tiers=9, H=3.8, R=1.15, pal=PAL_SPRUCE, lod=0, trunk_h=0.8):
    rng = random.Random(seed); lib.reset(); reset()
    begin("bark")
    bfn = bark_fn(False, seed)
    add_tube([Vector((0, 0, 0)), Vector((0, 0.5, 0)), Vector((0, 1.4, 0)), Vector((0, H * 0.8, 0)), Vector((0, H, 0))], 0.1, bfn, sides=6 if lod else 8,
             radfn=lambda t: 0.15 * (1 + 0.9 * max(0, 1 - t * 8) ** 2) * (1 - 0.88 * t))
    begin("leaf")
    ytop = H
    ring = []
    for t in range(tiers):
        f = t / (tiers - 1)
        y = trunk_h + (H * 0.93 - trunk_h) * f
        rr = R * (1 - f) ** 0.85 * 1.0 + 0.10
        nb = max(5, int(round((10 - 3 * f) * (0.7 if lod else 1.0))))
        ring.append((y, rr, nb))
    def cfn(y, rr):
        def fn(p, n):
            s01 = clamp01(n.dot(SUN) * 0.5 + 0.5)
            h = clamp01((p.y - trunk_h) / (H - trunk_h))
            outer = clamp01(math.hypot(p.x, p.z) / max(0.1, rr))
            under = clamp01(1 - (p.y - (y - 0.5)) * 0.0)
            t = clamp01(0.04 + 0.60 * s01 ** 1.5 + 0.22 * h) * (0.42 + 0.58 * outer ** 0.8)
            col = pal_mix(pal, t)
            col = mix(col, YG, 0.10 * t) if t > 0.5 else col
            return tuple(min(1, c * (1 + 0.07 * nz(p, 8.0, y))) for c in col)
        return fn
    for ti, (y, rr, nb) in enumerate(ring):
        ph = rng.uniform(0, 6.28)
        for i in range(nb):
            a = ph + i / nb * 6.283 + rng.uniform(-0.12, 0.12)
            L = rr * rng.uniform(0.82, 1.12)
            W = max(0.10, rr * 0.40) * rng.uniform(0.9, 1.2)
            dr = L * rng.uniform(0.28, 0.42)
            bm = bough_bm(L, W, dr, thick=0.42, sides=5 if lod else 6, segs=3 if lod else 4, jag=0.10)
            # roll slightly so the fan's top planes face up and out
            commit(bm, cfn(y, rr), sharp=50, xf=T((0, y + rng.uniform(-0.04, 0.04), 0), ry=-a, rz=rng.uniform(0.05, 0.22)))
            if lod == 0 and rr > 0.55 and i % 2 == 0:
                # shorter, higher inner boughs fill the middle and give the tier thickness
                bm2 = bough_bm(L * 0.62, W * 0.9, dr * 0.5, thick=0.5, sides=5, segs=3, jag=0.06)
                commit(bm2, cfn(y + 0.14, rr), sharp=50, xf=T((0, y + 0.13, 0), ry=-(a + 0.5 / nb * 6.283), rz=rng.uniform(0.12, 0.3)))
    # a pointed leader
    lead = lathe_bm([(0, ring[-1][0] - 0.1), (0.13, ring[-1][0] - 0.02), (0.09, ring[-1][0] + 0.3), (0.0, H + 0.12)], 6)
    commit(lead, cfn(H, 0.2), sharp=60)
    return dict(kind="conifer", canopy_radius=R, height=H + 0.12)

# ---------------------------------------------------------------- shrubs
def bush(iid, seed, R=1.0, nbl=14, hedge=False, lod=0):
    rng = random.Random(seed); lib.reset(); reset()
    cl = []
    if hedge:
        for i in range(7):
            cl.append((Vector(((i - 3) * 0.26 * R, 0.30 * R + rng.uniform(-0.02, 0.04), rng.uniform(-0.05, 0.05))), 0.24 * R))
    else:
        cl.append((Vector((0, 0.42 * R, 0)), 0.40 * R))
        for i in range(10):
            a = rng.uniform(0, 6.28); d = R * rng.uniform(0.25, 0.80)
            hh = R * (0.20 + 0.45 * (1 - d / R))
            cl.append((Vector((math.cos(a) * d * 1.1, hh * rng.uniform(0.7, 1.1), math.sin(a) * d * 0.85)), R * rng.uniform(0.20, 0.30)))
    ctr = Vector((0, 0.4 * R, 0))
    begin("bark")
    for k in range(3):
        a = rng.uniform(0, 6.28)
        add_tube([Vector((math.cos(a) * 0.08, 0, math.sin(a) * 0.08)), Vector((math.cos(a) * 0.14, 0.2 * R, math.sin(a) * 0.14))], 0.02, bark_fn(False, seed), sides=4, radfn=lambda t: 0.035 * (1 - 0.4 * t))
    begin("leaf")
    allc = [(c, r) for c, r in cl]
    for i, (c, r) in enumerate(cl):
        col = leaf_color(PAL_BUSH, allc, i, ctr, R * 1.1, 0.0, R * 0.95, hue=rng.uniform(-1, 1), seed=i * 2.3, sunk=0.03)
        commit(clump_bm(r, 0.80, 3 if i == 0 else 2, 0.24, seed + i * 2.1), col, sharp=38, xf=T(tuple(c), ry=rng.uniform(0, 6.28)))
        for k in range(3 if not hedge else 2):
            d = Vector((rng.uniform(-1, 1), rng.uniform(0.0, 1), rng.uniform(-1, 1))).normalized()
            col2 = leaf_color(PAL_BUSH, allc, i, ctr, R * 1.1, 0.0, R * 0.95, hue=rng.uniform(-1, 1), seed=90 + i, sunk=0.0)
            commit(clump_bm(r * 0.38, 0.7, 1, 0.28, seed + 30 + i * 4 + k), col2, sharp=40, xf=T(tuple(c + Vector((d.x * r, d.y * r * 0.8, d.z * r)) * 0.95), ry=rng.uniform(0, 6)))
    begin("bloom")
    if not hedge:
        for k in range(nbl):
            c, r = cl[rng.randrange(len(cl))]
            d = Vector((rng.uniform(-1, 1), rng.uniform(0.3, 1), rng.uniform(-1, 1))).normalized()
            p = c + Vector((d.x * r, d.y * r * 0.8, d.z * r)) * 1.05
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
    ("pine_a", lambda: conifer("pine_a", 5, tiers=9, H=3.9, R=1.15, pal=PAL_SPRUCE)),
    ("pine_b", lambda: conifer("pine_b", 9, tiers=8, H=3.1, R=1.0, pal=PAL_FIR)),
    ("tree_a_far", lambda: deciduous("tree_a_far", 11, OAK, PAL_OAK, lod=1)),
    ("tree_b_far", lambda: deciduous("tree_b_far", 23, BEECH, PAL_BEECH, lod=1)),
    ("tree_c_far", lambda: deciduous("tree_c_far", 37, BIRCH, PAL_BIRCH, lod=1, pale=True)),
    ("pine_a_far", lambda: conifer("pine_a_far", 5, tiers=8, H=3.9, R=1.15, pal=PAL_SPRUCE, lod=1)),
    ("pine_b_far", lambda: conifer("pine_b_far", 9, tiers=7, H=3.1, R=1.0, pal=PAL_FIR, lod=1)),
    ("bush_a", lambda: bush("bush_a", 3, nbl=12)),
    ("bush_b", lambda: bush("bush_b", 8, nbl=10, R=0.9)),
    ("hedge", lambda: bush("hedge", 5, R=1.0, hedge=True)),
    ("flowers", lambda: flowers("flowers", 4)),
]

if __name__ == "__main__":
    only = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    import lib
    for iid, fn in REG:
        if only and iid not in only: continue
        meta = fn(); info = export(iid, meta)
        print("EXPORT", iid, info["tris"], info["verts"], [(s["name"], s["tris"]) for s in info["sub_meshes"]], info["bounds_min"], info["bounds_max"], flush=True)
