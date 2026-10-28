"""Batch 4 face pieces (2026-10-27): the wayfarer pair (black + tortoise), cat-eye shades, and the thick-frame rebuilds of round glasses, star shades,
heart shades, aviator goggles and the monocle. All frames are real thick bands (ring_loop) so they read in the shop and from across the room."""
from kit5 import *

FA = FACE_ANCHOR

def lens_part(name, c, x, y, n, poly, color, thick=0.011, z0=-0.004, sharp=40):
    slab_part(name, poly, thick, color, lambda px, py, pz: tuple(c + x * px + y * py + n * (pz + z0)), cuts=1, sharp=sharp)

def temple_bar(name, frames, s, y, col, hv=0.016, ht=0.008, off=0.021, dx=0.12):
    pts = temple_path(frames, s, y, off=off, dx=dx)
    sweep(name, pts, lambda p: UP, hv, ht, col, e=3.2, sides=10, cap=True)

def bridge_arc(name, stand, y, xi, rad, col, arch=0.020, flat=0.85):
    pts = []
    for t in np.linspace(-1, 1, 11):
        x = t * xi
        p = B.front_surface(x, y + arch * (1 - t * t))
        pts.append(p + full_n(p) * stand)
    tube_curve(name, pts, rad, 8, col, cap=True, flat=flat)

# ============================ WAYFARER (black / tortoise) =====================
WAY = [(-0.100, 0.066), (0.118, 0.090), (0.106, -0.040), (0.030, -0.080), (-0.080, -0.064)]   # trapezoid lens, outer top corner high, CCW? (made CCW below)

def way_outline(s):
    # CCW: inner-top -> inner-bottom -> bottom -> outer-bottom -> outer-top
    pts = [(-0.106, 0.056), (-0.092, -0.060), (0.040, -0.084), (0.126, -0.034), (0.136, 0.080)]
    pts = smooth_poly(pts, 0.040, arc=6)
    return mirror_poly(pts, s)

def tortoise(frame_c):
    base = hx('#C98430'); dark = hx('#4A2610'); light = hx('#E7B552')
    def col(p, n):
        a = nz(p, 17.0, 3.0) * 0.5 + 0.5
        b = nz(p, 41.0, 9.0) * 0.5 + 0.5
        c = mix(base, dark, smooth01(0.50, 0.64, a))
        c = mix(c, light, 0.55 * smooth01(0.60, 0.74, b) * (1 - smooth01(0.50, 0.64, a)))
        return mix(deep(c, 0.10), tint(c, 0.16), 0.5 + 0.5 * n[1] * 0.6)
    return col

def wayfarer(kind='black', **k):
    reset()
    stand = 0.046
    fr = eye_frames(stand, y_off=-0.012)
    if kind == 'black':
        fcol = lambda p, n: mix(deep(BLACK, 0.0), tint(BLACK, 0.28), 0.25 + 0.5 * max(0.0, n[1]) * 0.9)
        stud = SILVER
    else:
        fcol = tortoise(None)
        stud = GOLD
    lens_dark = hx('#14171F'); lens_hi = hx('#6D7FA6')
    def wfn(px, py): return 0.028 + 0.020 * smooth01(0.020, 0.075, py)
    for s, c, x, y, n in fr:
        pl = way_outline(s)
        ring_loop('frame%+d' % s, c, x, y, n, pl, wfn, 0.016, fcol, n=64, e=2.5, zfn=lambda px, py: 0.0)
        lens_part('lens%+d' % s, c, x, y, n, pl, lambda p, nn: mix(lens_dark, hx('#2A3550'), 0.45 * max(0.0, nn[1]) + 0.25 * max(0.0, nn[2] * 0.0)), thick=0.012, z0=-0.006)
        # a soft diagonal highlight on the upper outer lens (subtle)
        hl = lib.poly_pts_rounded([(-0.004, 0.056), (0.050, 0.060), (0.020, 0.006), (-0.034, 0.002)], 0.010, arc=3)
        hl = [(px * s, py) for px, py in hl] if s > 0 else [(-px, py) for px, py in hl][::-1]
        hl = [(px + 0.028 * s, py + 0.002) for px, py in hl]
        slab_part('shine%+d' % s, hl, 0.004, lambda p, nn: mix(lens_hi, (1, 1, 1), 0.25), lambda px, py, pz: tuple(c + x * px + y * py + n * (pz + 0.0035)), cuts=0, sharp=40)
        # rivets on the outer top corner
        for dx, dy in ((0.128, 0.092), (0.124, 0.056)):
            ico_part('rivet%+d_%d' % (s, int(dy * 1000)), tuple(c + x * (s * dx) + y * dy + n * 0.019), (0.0085, 0.0085, 0.0085), stud, sub=1)
    # keyhole bridge
    bridge_arc('bridge', stand + 0.002, 0.850, 0.120, 0.024, fcol, arch=0.020, flat=0.85)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.865, fcol, hv=0.026, ht=0.012, off=0.0205, dx=0.134)
    return dict(anchor='face', slot='face', tags=['cool', 'cute'], price=60 if kind == 'black' else 70,
                title='Classic black shades' if kind == 'black' else 'Tortoise shades',
                desc='Thick acetate trapezoid sunglasses: heavy brow edge, dark smoked lenses with a soft highlight, rivets at the outer corners, chunky temples hugging the head. Lens bottoms y>=0.74 (clear of the mouth keep-out), tops below the brows.')

# ============================ CAT-EYE ========================================
def cat_outline(s):
    pts = [(-0.098, 0.050), (-0.090, -0.050), (0.010, -0.074), (0.108, -0.016), (0.152, 0.098), (0.040, 0.078)]
    return mirror_poly(smooth_poly(pts, 0.026, arc=6), s)

def cat_eye(frame=hx('#F4ECDC'), lens=hx('#5A2C4F'), **k):
    reset()
    stand = 0.048
    fr = eye_frames(stand)
    fcol = lambda p, n: mix(deep(frame, 0.10), tint(frame, 0.2), 0.45 + 0.5 * n[1] * 0.7)
    def wfn(px, py): return 0.020 + 0.012 * smooth01(0.0, 0.09, py) + 0.008 * smooth01(0.05, 0.15, px)
    for s, c, x, y, n in fr:
        pl = cat_outline(s)
        ring_loop('frame%+d' % s, c, x, y, n, pl, wfn, 0.0145, fcol, n=64, e=2.5)
        lens_part('lens%+d' % s, c, x, y, n, pl, lambda p, nn: mix(lens, hx('#9B5C8E'), 0.4 * max(0.0, nn[1])), thick=0.011, z0=-0.006)
        hl = [(0.020 * s + 0.030 * s, 0.050), (0.020 * s + 0.070 * s, 0.062), (0.020 * s + 0.050 * s, 0.020), (0.020 * s + 0.010 * s, 0.016)]
        hl = hl if s > 0 else hl[::-1]
        slab_part('shine%+d' % s, lib.poly_pts_rounded(hl, 0.008, arc=3), 0.004, hx('#D9B8D0'), lambda px, py, pz: tuple(c + x * px + y * py + n * (pz + 0.0035)), cuts=0, sharp=40)
        # gold stud at the winged tip
        ico_part('stud%+d' % s, tuple(c + x * (s * 0.150) + y * 0.110 + n * 0.018), (0.012, 0.012, 0.009), GOLD, sub=1)
        ico_part('stud2%+d' % s, tuple(c + x * (s * 0.128) + y * 0.060 + n * 0.018), (0.008, 0.008, 0.007), GOLD, sub=1)
    bridge_arc('bridge', stand + 0.002, 0.850, 0.116, 0.014, fcol, arch=0.018, flat=0.85)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.875, fcol, hv=0.022, ht=0.010, off=0.0205, dx=0.150)
    return dict(anchor='face', slot='face', tags=['cool', 'sparkly', 'sweet'], price=75, title='Cat-eye shades',
                desc='Ivory cat-eye sunglasses with plum lenses, a winged tip with gold studs, thick frame and temples. Bottom edge y>=0.745.')

# ============================ ROUND GLASSES (rebuild) ==========================
def circle_poly(R, n=40, sx=1.0, sy=1.0):
    return [(R * sx * math.cos(2 * math.pi * i / n), R * sy * math.sin(2 * math.pi * i / n)) for i in range(n)]

def round_glasses(frame=HONEY, **k):
    reset()
    R = 0.088
    stand = 0.050
    fr = eye_frames(stand)
    fcol = lambda p, n: mix(deep(frame, 0.14), tint(frame, 0.16), 0.45 + 0.5 * n[1] * 0.7)
    for s, c, x, y, n in fr:
        ring_loop('rim%+d' % s, c, x, y, n, circle_poly(R), lambda px, py: 0.044, 0.022, fcol, n=56, e=2.4)
        # little end-piece block where the temple hinges on
        ico_part('hinge%+d' % s, tuple(c + x * (s * (R + 0.006)) + y * 0.006 + n * 0.0), (0.018, 0.020, 0.018), deep(frame, 0.22), sub=1)
        # a pale glint arc inside the lower rim so the ring reads as glossy acetate
        ico_part('glint%+d' % s, tuple(c + x * (-0.040 * s) + y * 0.066 + n * 0.013), (0.020, 0.0075, 0.004), tint(frame, 0.7), sub=1, rot=np.stack([x, y, n], 1).tolist())
    bridge_arc('bridge', stand, 0.838, 0.118, 0.021, fcol, arch=0.020, flat=0.9)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.820, fcol, hv=0.022, ht=0.0105, off=0.022, dx=0.110)
    return dict(anchor='face', slot='face', tags=['cool', 'cute'], price=40, title='Round glasses',
                desc='Round honey acetate glasses: thick glossy rims (0.027 wide, 0.031 deep), end-piece hinges and flat chunky temples. Frames only, no lens fill, so the eyes stay readable.')

# ============================ STAR / HEART SHADES (rebuild) =====================
def star_shades(frame=PINK, lens=INK, **k):
    reset()
    stand = 0.052
    fr = eye_frames(stand)
    fcol = lambda p, n: mix(deep(frame, 0.10), tint(frame, 0.2), 0.45 + 0.5 * n[1] * 0.7)
    for s, c, x, y, n in fr:
        outl = star_poly(0.134, 0.082, 5, rot=math.pi / 2 + math.pi / 5, rad=0.026)
        outl = [(px, py) for px, py in outl]
        ring_loop('frame%+d' % s, c, x, y, n, outl, lambda px, py: 0.054, 0.024, fcol, n=80, e=2.4)
        lens_part('lens%+d' % s, c, x, y, n, star_poly(0.122, 0.070, 5, rot=math.pi / 2 + math.pi / 5, rad=0.022), lambda p, nn: mix(lens, LAV, 0.3 * max(0, nn[1])), thick=0.014, z0=-0.006)
        hl = [(-0.060, 0.040), (-0.014, 0.060), (-0.030, 0.010), (-0.064, 0.002)]
        slab_part('shine%+d' % s, lib.poly_pts_rounded(hl, 0.008, arc=3), 0.004, hx('#C9B5E6'), lambda px, py, pz: tuple(c + x * px + y * py + n * (pz + 0.0075)), cuts=0, sharp=40)
        ico_part('glint%+d' % s, tuple(c + x * (-0.03) + y * 0.035 + n * 0.012), (0.014, 0.007, 0.004), CREAM, sub=1, rot=np.stack([x, y, n], 1).tolist())
    bridge_arc('bridge', stand, 0.846, 0.100, 0.022, fcol, arch=0.020, flat=0.85)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.846, fcol, hv=0.022, ht=0.0105, off=0.022, dx=0.135)
    return dict(anchor='face', slot='face', tags=['cool', 'sparkly'], price=60, title='Star sunglasses',
                desc='Pink star sunglasses: a thick glossy star frame (0.030 wide) round dark plum lenses, a soft highlight, chunky temples.')

def heart_shades(frame=CORAL, lens=hx('#8E2F5E'), **k):
    reset()
    stand = 0.052
    fr = eye_frames(stand)
    from items2_other import heart_poly
    fcol = lambda p, n: mix(deep(frame, 0.10), tint(frame, 0.2), 0.45 + 0.5 * n[1] * 0.7)
    for s, c, x, y, n in fr:
        outl = [(px, py) for px, py in heart_poly(0.116)]
        ring_loop('frame%+d' % s, c, x, y, n, outl, lambda px, py: 0.052, 0.024, fcol, n=80, e=2.4)
        lens_part('lens%+d' % s, c, x, y, n, [(px * 0.88, py * 0.88) for px, py in heart_poly(0.104)], lambda p, nn: mix(lens, hx('#E98AA4'), 0.30 * max(0, nn[1])), thick=0.014, z0=-0.006)
        hl = [(-0.050, 0.044), (-0.012, 0.060), (-0.026, 0.014), (-0.056, 0.008)]
        slab_part('shine%+d' % s, lib.poly_pts_rounded(hl, 0.008, arc=3), 0.004, hx('#F2BCCB'), lambda px, py, pz: tuple(c + x * px + y * py + n * (pz + 0.0075)), cuts=0, sharp=40)
    bridge_arc('bridge', stand, 0.855, 0.100, 0.022, fcol, arch=0.020, flat=0.85)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.846, fcol, hv=0.022, ht=0.0105, off=0.022, dx=0.118)
    return dict(anchor='face', slot='face', tags=['sweet', 'sparkly', 'cute'], price=55, title='Heart sunglasses',
                desc='Coral heart sunglasses: thick glossy heart frame (0.029 wide), berry lenses with a highlight, chunky temples.')

# ============================ AVIATOR GOGGLES (rebuild) ========================
def goggles(rim=HONEY, strap=CORAL, glass=hx('#7CC4D6'), **k):
    reset()
    segs = 28
    yl = 1.075
    y0 = lambda phi: 1.062 + 0.014 * math.sin(phi)
    loop = [(0.020, -0.026), (0.044, -0.026), (0.044, 0.026), (0.020, 0.026)]
    torus('strap', segs, lambda phi: [eloop(y0(phi), phi, h, v) for h, v in loop], lambda p, n: mix(deep(strap, 0.10), tint(strap, 0.12), 0.5 + 0.5 * n[1] * 0.5))
    R = 0.080
    rimc = lambda p, nn: mix(deep(rim, 0.16), tint(rim, 0.16), 0.5 + 0.5 * nn[1] * 0.7)
    for s in (-1, 1):
        c = B.front_surface(s * 0.150, yl)
        n = full_n(c)
        x, y, z = axes(n)
        ctr = c + z * 0.040
        ring_loop('rim%+d' % s, ctr, x, y, z, circle_poly(R, 40), lambda px, py: 0.034, 0.021, rimc, n=56, e=2.3)
        ring_loop('ridge%+d' % s, ctr, x, y, z, circle_poly(R + 0.014, 40), lambda px, py: 0.008, 0.026, lambda p, nn: deep(rim, 0.3), n=56, e=2.3)
        ico_part('glass%+d' % s, tuple(ctr - z * 0.003), (R * 0.97, R * 0.97, 0.021), lambda p, nn: mix(glass, tint(glass, 0.55), max(0, 0.5 + 0.5 * nn[1]) * 0.4 + max(0, nn[2]) * 0.3), sub=2, rot=np.stack([x, y, z], 1).tolist())
        ico_part('glint%+d' % s, tuple(ctr + x * (-0.032) + y * 0.034 + z * 0.019), (0.018, 0.009, 0.004), CREAM, sub=1, rot=np.stack([x, y, z], 1).tolist())
        # screws / buckle studs on the outer rim
        ico_part('screw%+d' % s, tuple(ctr + x * (s * (R + 0.016)) + y * 0.0 + z * 0.0), (0.014, 0.014, 0.014), deep(rim, 0.1), sub=1)
    bridge_pts = []
    for t in np.linspace(-1, 1, 9):
        xx = t * 0.074
        p = B.front_surface(xx, yl + 0.012 * (1 - t * t))
        bridge_pts.append(p + full_n(p) * 0.046)
    tube_curve('bridge', bridge_pts, 0.0145, 8, rim, cap=True, flat=0.9)
    return dict(anchor='face', slot='face', tags=['cool', 'sporty'], price=55, title='Aviator goggles',
                desc='Brass-rim goggles with teal glass pushed up on the forehead on a wide coral strap at y~1.06; thick rims (0.034 wide) with a ridge ring, studs and a chunky bridge. Lens bottoms y>=0.98, above the brows.')

# ============================ MONOCLE (rebuild) ===============================
def monocle(gold=HONEY, **k):
    reset()
    stand = 0.050
    R = 0.088
    fr = eye_frames(stand)
    s, c, x, y, n = [f for f in fr if f[0] == 1][0]
    gcol = lambda p, nn: mix(deep(gold, 0.16), tint(gold, 0.2), 0.45 + 0.5 * nn[1] * 0.7)
    ring_loop('ring', c, x, y, n, circle_poly(R), lambda px, py: 0.042, 0.021, gcol, n=56, e=2.3)
    ring_loop('inner', c, x, y, n, circle_poly(R - 0.014), lambda px, py: 0.006, 0.0165, lambda p, nn: deep(gold, 0.3), n=64, e=2.3)
    a = math.radians(-35)
    start = c + (x * math.cos(a) + y * math.sin(a)) * (R + 0.012)
    ico_part('hinge', tuple(start), (0.021, 0.021, 0.021), deep(gold, 0.15), sub=1)
    path = [start]
    for (px, py, off) in ((0.31, 0.735, 0.040), (0.36, 0.690, 0.040), (0.405, 0.625, 0.040), (0.425, 0.565, 0.040)):
        p, nn = body_pt(px, py, off)
        path.append(p)
    # chain: alternating oval links
    for i in range(len(path) - 1):
        a_, b_ = path[i], path[i + 1]
        steps = 3
        for q in range(steps):
            m = a_ + (b_ - a_) * (q + 0.5) / steps
            d = (b_ - a_) / np.linalg.norm(b_ - a_)
            ref = np.array([0, 0, 1.0]) if q % 2 == 0 else np.array([1.0, 0, 0])
            xx = np.cross(d, ref)
            xx /= np.linalg.norm(xx)
            zz = np.cross(d, xx)
            ico_part('link%d_%d' % (i, q), tuple(m), (0.0075, 0.018, 0.0105) if q % 2 == 0 else (0.0105, 0.018, 0.0075), tint(gold, 0.1), sub=1, rot=np.stack([xx, d, zz], 1).tolist())
    ico_part('clip', tuple(path[-1]), (0.026, 0.026, 0.020), gold, sub=1)
    return dict(anchor='face', slot='face', tags=['cool', 'sweet'], price=45, title='Monocle',
                desc='Gold monocle: a thick glossy ring (0.026 wide) with an inner bead line round the +x eye bead, a hinge and a chunky oval-link chain hanging OUTWARD to a clip at (0.425,0.565).')

REG = [
    ('wayfarer_black', wayfarer, dict(kind='black'), FA),
    ('wayfarer_tortoise', wayfarer, dict(kind='tortoise'), FA),
    ('cat_eye_shades', cat_eye, dict(), FA),
    ('glasses_round', round_glasses, dict(), FA),
    ('sunglasses_star', star_shades, dict(), FA),
    ('heart_shades', heart_shades, dict(), FA),
    ('goggles_aviator', goggles, dict(), FA),
    ('monocle_gold', monocle, dict(), FA),
]
