"""Batch 4 neck loops (2026-10-27): every neck piece is one continuous loop round the body at the neck line (dipping at the front below the mouth,
rising at the back over Pip's tail root and between Lavender's wings): gold chain, silk scarf, pearls, whistle lanyard, cosy scarves, bow-tie band,
and the new Diamond J chain."""
from kit5 import *
import items3
import items_other as IO

NEW = ('diamond_j',)

def loop_tube(name, front, off, rad, sides, col, n=36, side=0.50, back=0.56, flat=1.0, radfn=None):
    pts = [ring_pt(2 * math.pi * i / n, front, off, side, back) for i in range(n + 1)]
    tube_curve(name, pts, rad, sides, col, cap=False, flat=flat, radfn=radfn)

def loop_beads(prefix, n, front, off, radii, col, side=0.50, back=0.56, segs=6, phase=0.5, flat_link=True):
    for k in range(n):
        phi = 2 * math.pi * (k + phase) / n
        p, t, h, up = ring_frame(phi, front, off, side, back)
        bead('%s%d' % (prefix, k), p, radii, col, rot=np.stack([t, h, up], 1), segs=segs)

# ============================ GOLD CHAIN (chunky Cuban links, full loop) =======
def chain_gold(gold=hx('#E8B84A'), **k):
    reset()
    def gcol(p, n):
        # high-polish gold: a hot highlight on the upward/outward faces, deep amber in the creases
        w = max(0.0, n[1] * 0.55 + n[2] * 0.45)
        return mix(deep(gold, 0.50), mix(tint(gold, 0.78), (1.0, 0.97, 0.80), 0.4), 0.10 + 0.90 * w ** 1.3)
    FR = 0.43
    n = 18
    for k_ in range(n):
        phi = 2 * math.pi * (k_ + 0.5) / n
        p, t, h, up = ring_frame(phi, FR, 0.044)
        if k_ % 2 == 0: r = (0.112, 0.036, 0.074)          # a flat link facing outward
        else: r = (0.112, 0.074, 0.032)                    # the next one standing on edge, interlocked through it
        bead('link%d' % k_, p, r, gcol, rot=np.stack([t, h, up], 1), segs=6)
    p, t, h, up = ring_frame(math.pi / 2, FR, 0.058)
    Rm = np.stack([t, h, -up], 1).tolist()
    pc = p - up * 0.120
    lathe_y('coin', [(0.0, -0.020), (0.100, -0.020), (0.118, -0.008), (0.118, 0.014), (0.100, 0.026), (0.0, 0.026)], 14, lambda q, nq: mix(deep(gold, 0.15), tint(gold, 0.45), 0.5 + 0.5 * nq[1]), centre=tuple(pc), rotm=Rm, sharp=45)
    sp = star_poly(0.060, 0.028, 5, rad=0.007)
    slab_part('star', sp, 0.008, lambda q, nq: tint(gold, 0.55), lambda px, py, pz: tuple(pc + t * px + up * py + h * (0.026 + pz)), cuts=0)
    bead('bail', p - up * 0.030, (0.030, 0.046, 0.018), gcol, rot=np.stack([t, h, up], 1), segs=6)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly'], price=70, title='Gold chain',
                desc='A chunky Cuban-link gold chain: eighteen bold flattened oval links, alternately flat and on edge so they interlock and touch, high-polish gold, in one continuous loop round the body at the neck line, with a big coin pendant on a bail at the front (y~0.31).')

# ============================ SILK SCARF (full loop, knot, tails) ==============
def scarf_silk(base=hx('#2F3E6B'), ring=hx('#E8B84A'), dot=hx('#F4E9D6'), **k):
    reset()
    def pat(p, n):
        u = p[0] * 6.0 + p[1] * 2.0
        v = p[1] * 6.0 - p[0] * 2.0
        fu = u - math.floor(u) - 0.5
        fv = v - math.floor(v) - 0.5
        r = math.hypot(fu, fv)
        c = base
        if 0.26 < r < 0.38: c = ring
        elif r < 0.12: c = dot
        return mix(deep(c, 0.06), tint(c, 0.16), 0.5 + 0.5 * n[1] * 0.5)
    FR = 0.462
    def lf(phi):
        y = neck_y(phi, FR, 0.47, 0.54)
        return [eloop(y, phi, h, v) for h, v in ((0.014, 0.040), (0.042, 0.030), (0.050, 0.0), (0.042, -0.030), (0.014, -0.040))]
    torus('wrap', 32, lf, pat, sharp=60)
    kc, kn = body_pt(0.0, FR - 0.004, 0.100)
    xx, yy, nn = axes(kn)
    bead('knot', kc, (0.098, 0.074, 0.070), lambda p, n: mix(deep(base, 0.10), tint(base, 0.2), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=8)
    for s_ in (-1, 1):
        bead('ear%+d' % s_, kc + xx * (s_ * 0.080) + yy * 0.018 + nn * 0.004, (0.046, 0.052, 0.044), lambda p, n: mix(deep(base, 0.14), tint(base, 0.18), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=6)
    def tail(cx0, cx1, y0, y1, w, name, off, wav):
        nu, nv = 4, 6
        def fn(i, j):
            v = j / (nv - 1); u = i / (nu - 1) - 0.5
            cx = cx0 + (cx1 - cx0) * v + 0.016 * math.sin(4.0 * v + wav)
            y = y0 + (y1 - y0) * v
            ww = w * (1 + 0.65 * v)
            return body_pt(cx + u * ww, y, off + 0.010 * math.sin(3.0 * v + wav) * v)
        thick_sheet(name, fn, nu, nv, 0.012, lambda p, n: pat(p, n))
    tail(-0.040, -0.150, 0.430, 0.150, 0.085, 'tail_a', 0.090, 0.0)
    tail(0.040, 0.120, 0.430, 0.175, 0.078, 'tail_b', 0.094, 1.7)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly', 'sweet'], price=55, title='Silk scarf',
                desc='A silk neckerchief in navy printed with gold medallions: a thick rolled wrap in one continuous loop round the belly (y~0.46, rising at the back), a fat knot with two folded ends at the front centre (top y 0.52) and two flowing tails of fuller fabric.')

# ============================ PEARLS (full loop) ===============================
def pearls(pearl=hx('#FBF4EC'), clasp=HONEY, **k):
    reset()
    pcol = lambda q, n_v: mix(deep(pearl, 0.12), tint(pearl, 0.14), 0.5 + 0.5 * n_v[1])
    FR = 0.405
    loop_tube('string', FR, 0.040, 0.011, 4, deep(pearl, 0.25), n=32)
    n = 19
    for k_ in range(n):
        phi = 2 * math.pi * (k_ + 0.5) / n
        p, t, h, up = ring_frame(phi, FR, 0.042)
        bead('pearl%d' % k_, p, (0.046, 0.046, 0.046), pcol, segs=6)
    p, t, h, up = ring_frame(math.pi / 2, FR, 0.060)
    pd = p - up * 0.070
    bead('drop', pd, (0.046, 0.058, 0.040), lambda q, n_v: mix(deep(hx('#E98AA4'), 0.1), tint(hx('#E98AA4'), 0.25), 0.5 + 0.5 * n_v[1]), rot=np.stack([t, up, h], 1), segs=8)
    bead('cap', pd + up * 0.062, (0.026, 0.018, 0.020), clasp, rot=np.stack([t, up, h], 1), segs=6)
    return dict(anchor='neck', slot='neck', tags=['sparkly', 'sweet', 'cute'], price=65, title='Pearl necklace',
                desc='A pearl necklace in one continuous loop round the body at the neck line (nineteen big pearls on a thread), dipping to a pink drop in a gold cap at the front (y~0.34) and rising at the back. Below the mouth keep-out.')

# ============================ WHISTLE (lanyard loop) ===========================
def whistle(strap=SKY, metal=hx('#C9D3DC'), mouth=CORAL, **k):
    reset()
    scol = lambda p, n: mix(deep(strap, 0.14), tint(strap, 0.2), 0.5 + 0.5 * n[1])
    FR = 0.445
    loop_tube('strap', FR, 0.040, 0.024, 5, scol, n=40, flat=0.8)
    c, t, h, up = ring_frame(math.pi / 2, FR, 0.056)
    ring = [c - up * 0.020 + t * (0.028 * math.cos(a)) + up * (0.034 * math.sin(a)) for a in np.linspace(0, 2 * math.pi, 11)]
    tube_curve('ring', ring, 0.011, 5, deep(metal, 0.2), cap=False)
    wc = c - up * 0.110 + h * 0.020
    mcol = lambda p, nn: mix(deep(metal, 0.12), tint(metal, 0.32), 0.5 + 0.5 * nn[1])
    bead('chamber', wc, (0.088, 0.078, 0.070), mcol, segs=8)
    bead('cap', wc + up * 0.070, (0.040, 0.018, 0.034), deep(metal, 0.18), segs=6)
    lathe_y('mouthpiece', [(0.0, 0.0), (0.046, 0.0), (0.044, 0.140), (0.0, 0.142)], 10, lambda p, nn: mix(deep(mouth, 0.1), tint(mouth, 0.2), 0.5 + 0.5 * nn[1]), centre=tuple(wc + np.array([0.054, 0.0, 0.002])), rotm=np.array(rot_z(-math.pi / 2)).tolist(), sharp=70)
    bead('hole', wc + np.array([0.0, 0.024, 0.062]), (0.030, 0.013, 0.012), INK, segs=6)
    return dict(anchor='neck', slot='neck', tags=['sporty', 'cool'], price=30, title='Coach whistle',
                desc='A coach whistle on a thick rounded sky lanyard in one continuous loop round the body at the neck line, dipping to a ring at the front (y~0.44) with a big silver whistle and coral mouthpiece hanging to y~0.31; the loop rises at the back. Below the mouth keep-out.')

# ============================ COSY SCARVES + BOW TIE (full loops) ==============
def bow_tie_band(main=PINK, **k):
    meta = IO.bow_tie(main=main, **k)
    FR = 0.470
    torus('band', 28, lambda phi: [eloop(neck_y(phi, FR, 0.472, 0.54), phi, h, v) for h, v in ((0.018, 0.016), (0.034, 0.012), (0.038, 0.0), (0.034, -0.012), (0.018, -0.016))], lambda p, n: mix(deep(main, 0.2), tint(main, 0.2), 0.5 + 0.5 * n[1]), sharp=60)
    meta['desc'] += ' A slim band of the same colour continues round the sides and the back so the bow sits on a continuous loop.'
    return meta

# ============================ DIAMOND J CHAIN ==================================
def brilliant(name, c, r, color, rot, sides=6):
    """A round brilliant-cut stone: pavilion below, girdle, crown and flat table."""
    prof = [(0.0, -r * 0.62), (r * 0.98, 0.0), (r * 0.80, r * 0.24), (r * 0.46, r * 0.40), (0.0, r * 0.40)]
    return lathe_y(name, prof, sides, color, centre=tuple(c), rotm=np.array(rot).tolist(), sharp=88)

def diamond_j(**k):
    reset()
    S = 1.25
    def hdr(c, k):                                   # light lift: values above 1 so the stones never fall into grey in shade
        return tuple(x * k for x in c)
    def stone(p, n):
        # near-white base (0.94 / 0.97 / 1.0) with a faint ice-blue rim in the facets; the whole stone is lifted (emissive-like) so shade cannot grey it
        f = 0.5 + 0.5 * math.sin(p[0] * 211.0 + p[1] * 137.0 + p[2] * 89.0)
        top = max(0.0, n[1] * 0.5 + n[2] * 0.5)
        base = mix((0.94, 0.97, 1.0), (0.78, 0.90, 1.0), 0.35 * f)
        return hdr(mix(base, (1.0, 1.0, 1.0), 0.4 + 0.6 * top), 1.22)
    def plat(p, n):
        # mirror white gold: bright, with only a faint cool reflection toward the edges
        w = max(0.0, n[1] * 0.4 + n[2] * 0.6)
        return hdr(mix((0.62, 0.72, 0.86), (1.0, 1.0, 1.0), 0.15 + 0.85 * w ** 0.9), 1.0)
    def pave(p, n):
        # the pave as a fine micro-sparkle texture (hash speckle), not dots
        hsh = math.sin(p[0] * 531.0 + p[1] * 947.0 + p[2] * 173.0) * 43758.5453
        hsh -= math.floor(hsh)
        sp = 1.0 if hsh > 0.78 else 0.0
        base = mix((0.86, 0.93, 1.0), (1.0, 1.0, 1.0), 0.5 * max(0.0, n[2]))
        return hdr(mix(base, (1.0, 1.0, 1.0), sp), 1.25 if sp else 0.95)
    FR = 0.470
    n = 56
    for k_ in range(n):                            # a fine tennis chain: small round brilliants set shoulder to shoulder, no wire
        phi = 2 * math.pi * (k_ + 0.5) / n
        p, t, h, up = ring_frame(phi, FR, 0.036)
        brilliant('gemC%d' % k_, p, 0.032, stone, np.stack([t, h, up], 1))
    # the pendant: a big bold rounded J, solid mirror white gold with a polished bevel and micro-sparkle pave
    c, t, h, up = ring_frame(math.pi / 2, FR, 0.052)
    top = c - up * 0.060
    stem_x = 0.026
    path = [(stem_x * S, (0.100 - 0.0275 * i) * S) for i in range(6)]
    cy, r = -0.0375 * S, 0.052 * S
    cx = stem_x * S - r
    for k_ in range(1, 12):
        a = -math.pi * 1.06 * k_ / 11
        path.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    serif = [((stem_x - 0.050) * S, 0.100 * S), ((stem_x + 0.050) * S, 0.100 * S)]
    def xf(dz):
        return lambda px, py, pz: tuple(top + t * px + up * (py - 0.100 * S) + h * (pz + dz))
    slab_part('jbase', stroke_poly(path, 0.078 * S, 8), 0.020, plat, xf(-0.006), cuts=0, sharp=30)
    slab_part('jbevel', stroke_poly(path, 0.066 * S, 8), 0.006, lambda p_, n_: hdr(mix((0.8, 0.88, 1.0), (1, 1, 1), max(0.0, n_[1] * 0.5 + 0.5)), 1.05), xf(0.012), cuts=0, sharp=30)
    slab_part('jpave', stroke_poly(path, 0.050 * S, 8), 0.006, pave, xf(0.018), cuts=0, sharp=30)
    slab_part('serifb', stroke_poly(serif, 0.056 * S, 6), 0.020, plat, xf(-0.006), cuts=0, sharp=30)
    slab_part('serifp', stroke_poly(serif, 0.036 * S, 6), 0.006, pave, xf(0.018), cuts=0, sharp=30)
    # four bigger accent stones on the J (they also carry the glints)
    for q, (gx, gy) in enumerate(((stem_x * S, 0.100 * S), (stem_x * S, 0.030 * S), (cx, cy - r * 0.2), (cx + r * 0.9, cy - r * 0.95))):
        brilliant('gemJ%d' % q, top + t * gx + up * (gy - 0.100 * S) + h * 0.030, 0.026, stone, np.stack([t, h, up], 1))
    # the bail: a bright loop that carries the J from the front stone of the chain
    bp = []
    for a in np.linspace(0, 2 * math.pi, 13):
        bp.append(top + up * (0.060 + 0.034 * math.sin(a)) + t * (0.026 * math.cos(a)) + h * 0.010)
    tube_curve('bail', bp, 0.010, 5, plat, cap=False)
    return dict(anchor='neck', slot='neck', tags=['sparkly', 'cool'], price=450, title='Diamond J chain',
                desc='A fine iced-out tennis chain of fifty-six small round brilliants set shoulder to shoulder in one continuous loop round the body at the neck line (no wire), near-white and lifted so they never grey in shade, with a big bold J pendant in solid mirror white gold with a polished bevel and a micro-sparkle pave face, on a bail at the front centre (below the mouth keep-out). The stones and four accent stones twinkle (Swift adds the glints). The hero item: its own budget (2500 vertices / 3800 triangles).')

def pipify(fn):
    """The Pip variant of a neck loop: the same piece built with the loop arching over his tail root and back spike (kit5.pip_rise)."""
    def f(**kw):
        import kit5
        kit5.PIP_MODE = True
        try:
            return fn(**kw)
        finally:
            kit5.PIP_MODE = False
    return f

import items4
REG = [
    ('chain_gold', chain_gold, dict(), NECK_ANCHOR),
    ('scarf_silk', scarf_silk, dict(), NECK_ANCHOR),
    ('pearls', pearls, dict(), NECK_ANCHOR),
    ('whistle_coach', whistle, dict(), NECK_ANCHOR),
    ('bowtie_pink', bow_tie_band, dict(main=PINK), NECK_ANCHOR),
    ('bowtie_sky', bow_tie_band, dict(main=SKY), NECK_ANCHOR),
    ('diamond_j', diamond_j, dict(), NECK_ANCHOR),
    ('scarf_cosy', items3.scarf, dict(), NECK_ANCHOR),
    ('cowboy_hat', items4.cowboy_hat, dict(), H),
    ('hair_bow', items4.hair_bow, dict(), H),
    ('scarf_sky', items3.scarf, dict(a=SKY, b=CREAM), NECK_ANCHOR),
]

import items7
VARIANTS = [
    ('chain_gold_pip', pipify(chain_gold), dict(), NECK_ANCHOR),
    ('scarf_silk_pip', pipify(scarf_silk), dict(), NECK_ANCHOR),
    ('pearls_pip', pipify(pearls), dict(), NECK_ANCHOR),
    ('whistle_coach_pip', pipify(whistle), dict(), NECK_ANCHOR),
    ('bowtie_pink_pip', pipify(bow_tie_band), dict(main=PINK), NECK_ANCHOR),
    ('bowtie_sky_pip', pipify(bow_tie_band), dict(main=SKY), NECK_ANCHOR),
    ('diamond_j_pip', pipify(diamond_j), dict(), NECK_ANCHOR),
    ('scarf_cosy_pip', pipify(items3.scarf), dict(), NECK_ANCHOR),
    ('scarf_sky_pip', pipify(items3.scarf), dict(a=SKY, b=CREAM), NECK_ANCHOR),
    ('bandana_coral_pip', pipify(items7.bandana), dict(main=CORAL), NECK_ANCHOR),
    ('bandana_mint_pip', pipify(items7.bandana), dict(main=MINT), NECK_ANCHOR),
    ('lei_pip', pipify(items7.lei), dict(), NECK_ANCHOR),
]
