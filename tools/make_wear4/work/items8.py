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

# ============================ GOLD CHAIN (full loop) ===========================
def chain_gold(gold=hx('#E8B84A'), **k):
    reset()
    gcol = lambda p, n: mix(deep(gold, 0.25), tint(gold, 0.40), 0.35 + 0.65 * max(0, n[1] * 0.7 + 0.3))
    FR = 0.43
    n = 20
    loop_tube('wire', FR, 0.040, 0.014, 4, lambda p, nn: mix(deep(gold, 0.30), tint(gold, 0.2), 0.5), n=30)
    for k_ in range(n):
        phi = 2 * math.pi * (k_ + 0.5) / n
        p, t, h, up = ring_frame(phi, FR, 0.040)
        if k_ % 2 == 0: r = (0.060, 0.022, 0.040)          # flat link: wide along the loop, thin outward
        else: r = (0.060, 0.040, 0.022)
        bead('link%d' % k_, p, (r[0], r[1], r[2]), gcol, rot=np.stack([t, h, up], 1), segs=6)
    p, t, h, up = ring_frame(math.pi / 2, FR, 0.058)
    Rm = np.stack([t, h, -up], 1).tolist()
    pc = p - up * 0.075
    lathe_y('coin', [(0.0, -0.014), (0.070, -0.014), (0.080, -0.006), (0.080, 0.010), (0.070, 0.018), (0.0, 0.018)], 12, lambda q, nq: mix(deep(gold, 0.15), tint(gold, 0.32), 0.5 + 0.5 * nq[1]), centre=tuple(pc), rotm=Rm, sharp=45)
    sp = star_poly(0.034, 0.016, 5, rad=0.005)
    slab_part('star', sp, 0.006, lambda q, nq: tint(gold, 0.35), lambda px, py, pz: tuple(pc + t * px + up * py + h * (0.016 + pz)), cuts=0)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly'], price=70, title='Gold chain',
                desc='A chunky gold curb chain in one continuous loop round the body at the neck line (twenty big alternating links), dipping to a coin pendant at the front (y~0.40) and rising at the back. Nothing near the mouth keep-out.')

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
        return [eloop(y, phi, h, v) for h, v in ((0.018, 0.046), (0.056, 0.036), (0.072, 0.0), (0.056, -0.036), (0.018, -0.046))]
    torus('wrap', 32, lf, pat, sharp=60)
    kc, kn = body_pt(0.0, FR - 0.004, 0.082)
    xx, yy, nn = axes(kn)
    bead('knot', kc, (0.066, 0.050, 0.048), lambda p, n: mix(deep(base, 0.10), tint(base, 0.2), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=8)
    for s_ in (-1, 1):
        bead('ear%+d' % s_, kc + xx * (s_ * 0.050) + yy * 0.012 + nn * 0.004, (0.030, 0.034, 0.030), lambda p, n: mix(deep(base, 0.14), tint(base, 0.18), 0.5 + 0.5 * n[2]), rot=np.stack([xx, yy, nn], 1), segs=6)
    def tail(cx0, cx1, y0, y1, w, name, off, wav):
        nu, nv = 4, 6
        def fn(i, j):
            v = j / (nv - 1); u = i / (nu - 1) - 0.5
            cx = cx0 + (cx1 - cx0) * v + 0.016 * math.sin(4.0 * v + wav)
            y = y0 + (y1 - y0) * v
            ww = w * (1 + 0.65 * v)
            return body_pt(cx + u * ww, y, off + 0.010 * math.sin(3.0 * v + wav) * v)
        thick_sheet(name, fn, nu, nv, 0.012, lambda p, n: pat(p, n))
    tail(-0.030, -0.130, 0.440, 0.190, 0.060, 'tail_a', 0.074, 0.0)
    tail(0.030, 0.095, 0.440, 0.215, 0.054, 'tail_b', 0.078, 1.7)
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
def diamond_j(**k):
    reset()
    ICE = hx('#F4FAFF'); ICE2 = hx('#8DBBF0'); PLAT = hx('#CFE0F2'); PLAT2 = hx('#9DB9D8'); S = 1.28
    pcol = lambda p, n: mix(deep(PLAT, 0.20), tint(PLAT, 0.55), 0.35 + 0.65 * max(0.0, n[1] * 0.5 + 0.5))
    FR = 0.470
    n = 24
    loop_tube('wire', FR, 0.038, 0.010, 3, deep(PLAT, 0.3), n=24)
    for k_ in range(n):                            # a tennis-chain of chunky gems that wraps the whole body
        phi = 2 * math.pi * (k_ + 0.5) / n
        p, t, h, up = ring_frame(phi, FR, 0.040, side=0.505, back=0.56)
        gem('gemC%d' % k_, p, 0.046, (lambda p_, n_, k_=k_: ICE if k_ % 2 == 0 else ICE2), rot=np.stack([t, h, up], 1), sides=5)
    # the pendant: a bold rounded J (platinum, bevelled rim) set with pave gems, hanging at the front centre
    c, t, h, up = ring_frame(math.pi / 2, FR, 0.052, side=0.505, back=0.56)
    top = c - up * 0.045
    stem_x = 0.026
    path = [(stem_x, 0.100 - 0.0 * i) for i in range(1)]
    path = [(stem_x * S, (0.100 - 0.0275 * i) * S) for i in range(6)]                   # the stem, top to bottom (y 0.10 .. -0.0375)
    cy, r = -0.0375 * S, 0.052 * S
    cx = stem_x * S - r
    for k_ in range(1, 12):
        a = -math.pi * 1.06 * k_ / 11
        path.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    serif = [((stem_x - 0.050) * S, 0.100 * S), ((stem_x + 0.050) * S, 0.100 * S)]
    def xf(dz):
        return lambda px, py, pz: tuple(top + t * px + up * (py - 0.100 * S) + h * (pz + dz))
    base_poly = stroke_poly(path, 0.074 * S, 6)
    slab_part('jbase', base_poly, 0.016, pcol, xf(-0.006), cuts=0, sharp=30)
    slab_part('jtop', stroke_poly(path, 0.056 * S, 6), 0.007, lambda p, n_: mix(deep(PLAT2, 0.1), tint(PLAT2, 0.4), 0.5 + 0.5 * n_[1]), xf(0.010), cuts=0, sharp=30)
    slab_part('serifb', stroke_poly(serif, 0.052 * S, 5), 0.016, pcol, xf(-0.006), cuts=0, sharp=30)
    # pave: a grid of tiny gems over the strokes
    P = [np.array(q) for q in path]
    def dist_path(q, pts):
        best = 9
        for i in range(len(pts) - 1):
            a, b = pts[i], pts[i + 1]
            ab = b - a
            tt = max(0.0, min(1.0, np.dot(q - a, ab) / np.dot(ab, ab)))
            best = min(best, np.linalg.norm(q - (a + ab * tt)))
        return best
    gi = 0
    SER = [np.array(q) for q in serif]
    for gx in np.arange(-0.094, 0.092, 0.029 * S):
        for gy in np.arange(-0.128, 0.138, 0.029 * S):
            q = np.array([gx, gy])
            if dist_path(q, P) < 0.012 * S or (abs(gy - 0.100 * S) < 0.004 * S and -0.022 * S <= gx <= 0.076 * S):
                gem('gemJ%d' % gi, top + t * gx + up * (gy - 0.100 * S) + h * 0.026, 0.0125 * S, (lambda p_, n_, gi=gi: ICE if gi % 2 == 0 else ICE2), rot=np.stack([t, h, up], 1), sides=5)
                gi += 1
    gem('gemBail', c + up * 0.004 + h * 0.004, 0.028, ICE, rot=np.stack([t, h, up], 1), sides=5)
    return dict(anchor='neck', slot='neck', tags=['sparkly', 'cool'], price=450, title='Diamond J chain',
                desc='An icy tennis chain of chunky faceted gems in one continuous loop round the body at the neck line, with a big bold rounded J pendant (platinum, bevelled rim) paved with tiny gems hanging at the front centre (J top y~0.43, bottom y~0.28), below the mouth keep-out. The gems twinkle (Swift adds the glints).')

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
