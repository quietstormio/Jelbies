"""Batch 4 face pieces (2026-10-27): the wayfarer pair (black + tortoise), cat-eye shades, and the thick-frame rebuilds of round glasses, star shades,
heart shades, aviator goggles and the monocle. Real thick bands (ring_loop) so they read in the shop and across the room, inside the wardrobe budget
(<= 1000 vertices, <= 1300 triangles per piece) and with temples that wrap back along the side of the head, tapering and tucking in toward the ear."""
from kit5 import *

FA = FACE_ANCHOR

def lens_part(name, c, x, y, n, poly, color, thick=0.011, z0=-0.004):
    slab_part(name, poly, thick, color, lambda px, py, pz: tuple(c + x * px + y * py + n * (pz + z0)), cuts=0, sharp=40)

def temple_bar(name, frames, s, y, col, hv=0.02, ht=0.010, off=0.018, dx=0.12, end_deg=48.0, dip=0.040):
    """A temple arm: leaves the outer rim, then follows the head round and DOWN toward the ear, tapering and hugging the skin more and more."""
    _, c, x, yy, n = [f for f in frames if f[0] == s][0]
    t = (y - B.lift) / B.bodyH
    a, d = float(B.halfWidth(t)), float(B.halfDepth(t))
    c2 = c + x * (s * dx)
    ph0 = math.atan2(c2[2] / d, c2[0] / a)
    ph0 = min(ph0, math.radians(78)) if s > 0 else max(ph0, math.radians(102))
    end = math.radians(end_deg) if s > 0 else math.radians(180 - end_deg)
    pts = []
    K = 6
    for k in range(K):
        u = k / (K - 1)
        ph = ph0 + (end - ph0) * u
        yy_ = y - dip * u ** 1.5
        p = B.egg_point(yy_, ph)
        pts.append(p + egg_n(p) * (off * (1.0 - 0.45 * u)))
    sweep(name, pts, lambda p: UP, hv, ht, col, e=3.0, sides=6, cap=True, radfn=lambda t_: 1.0 - 0.42 * t_)

def bridge_arc(name, stand, y, xi, rad, col, arch=0.020, flat=0.85):
    pts = []
    for t in np.linspace(-1, 1, 7):
        x = t * xi
        p = B.front_surface(x, y + arch * (1 - t * t))
        pts.append(p + full_n(p) * stand)
    tube_curve(name, pts, rad, 6, col, cap=True, flat=flat)

def circle_poly(R, n=28, sx=1.0, sy=1.0):
    return [(R * sx * math.cos(2 * math.pi * i / n), R * sy * math.sin(2 * math.pi * i / n)) for i in range(n)]

def rivet(name, p, r, col):
    bead(name, p, (r, r, r * 0.8), col, segs=6)

# ============================ WAYFARER (black / tortoise) =====================
def way_outline(s):
    pts = [(-0.106, 0.056), (-0.092, -0.060), (0.040, -0.084), (0.126, -0.034), (0.136, 0.080)]
    return mirror_poly(smooth_poly(pts, 0.040, arc=3), s)

def tortoise():
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
        fcol = lambda p, n: mix(BLACK, tint(BLACK, 0.28), 0.25 + 0.5 * max(0.0, n[1]) * 0.9)
        stud = SILVER
    else:
        fcol = tortoise()
        stud = GOLD
    lens_dark = hx('#14171F'); lens_hi = hx('#6D7FA6')
    def wfn(px, py): return 0.028 + 0.020 * smooth01(0.020, 0.075, py)
    for s, c, x, y, n in fr:
        pl = way_outline(s)
        ring_loop('frame%+d' % s, c, x, y, n, pl, wfn, 0.016, fcol, n=24, e=2.5, sides=8)
        lens_part('lens%+d' % s, c, x, y, n, pl, lambda p, nn: mix(lens_dark, hx('#2A3550'), 0.45 * max(0.0, nn[1])), thick=0.012, z0=-0.006)
        hl = lib.poly_pts_rounded([(-0.004, 0.050), (0.050, 0.054), (0.020, 0.002), (-0.034, -0.002)], 0.006, arc=1)
        hl = [(px + 0.024, py) for px, py in hl] if s > 0 else [(-px - 0.024, py) for px, py in hl][::-1]
        slab_part('shine%+d' % s, hl, 0.004, lambda p, nn: mix(lens_hi, (1, 1, 1), 0.25), lambda px, py, pz: tuple(c + x * px + y * py + n * (pz + 0.0035)), cuts=0, sharp=40)
        rivet('rivet%+d' % s, c + x * (s * 0.130) + y * 0.074 + n * 0.020, 0.010, stud)
    bridge_arc('bridge', stand + 0.002, 0.842, 0.120, 0.022, fcol, arch=0.020, flat=0.85)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.852, fcol, hv=0.024, ht=0.011, off=0.018, dx=0.136)
    return dict(anchor='face', slot='face', tags=['cool', 'cute'], price=60 if kind == 'black' else 70,
                title='Classic black shades' if kind == 'black' else 'Tortoise shades',
                desc='Thick acetate trapezoid sunglasses with smoked lenses, a soft highlight and rivets; temples taper back along the side of the head toward the ear. Lens bottoms y>=0.74.')

# ============================ CAT-EYE ========================================
def cat_outline(s):
    pts = [(-0.098, 0.050), (-0.090, -0.050), (0.010, -0.074), (0.108, -0.016), (0.152, 0.098), (0.040, 0.078)]
    return mirror_poly(smooth_poly(pts, 0.026, arc=3), s)

def cat_eye(frame=hx('#F4ECDC'), lens=hx('#5A2C4F'), **k):
    reset()
    stand = 0.048
    fr = eye_frames(stand)
    fcol = lambda p, n: mix(deep(frame, 0.10), tint(frame, 0.2), 0.45 + 0.5 * n[1] * 0.7)
    def wfn(px, py): return 0.026 + 0.012 * smooth01(0.0, 0.09, py) + 0.008 * smooth01(0.05, 0.15, px)
    for s, c, x, y, n in fr:
        pl = cat_outline(s)
        ring_loop('frame%+d' % s, c, x, y, n, pl, wfn, 0.0145, fcol, n=24, e=2.5, sides=8)
        lens_part('lens%+d' % s, c, x, y, n, pl, lambda p, nn: mix(lens, hx('#9B5C8E'), 0.4 * max(0.0, nn[1])), thick=0.011, z0=-0.006)
        hl = [(0.050 * s, 0.050), (0.090 * s, 0.062), (0.070 * s, 0.020), (0.030 * s, 0.016)]
        hl = hl if s > 0 else hl[::-1]
        slab_part('shine%+d' % s, hl, 0.004, hx('#D9B8D0'), lambda px, py, pz: tuple(c + x * px + y * py + n * (pz + 0.0035)), cuts=0, sharp=40)
        rivet('stud%+d' % s, c + x * (s * 0.150) + y * 0.100 + n * 0.018, 0.011, GOLD)
    bridge_arc('bridge', stand + 0.002, 0.850, 0.116, 0.019, fcol, arch=0.018, flat=0.85)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.866, fcol, hv=0.021, ht=0.010, off=0.018, dx=0.150)
    return dict(anchor='face', slot='face', tags=['cool', 'sparkly', 'sweet'], price=75, title='Cat-eye shades',
                desc='Ivory cat-eye sunglasses with plum lenses and gold studs at the winged tips; temples wrap back along the head toward the ear. Bottom edge y>=0.745.')

# ============================ ROUND GLASSES (rebuild) ==========================
def round_glasses(frame=HONEY, **k):
    reset()
    R = 0.088
    stand = 0.050
    fr = eye_frames(stand)
    fcol = lambda p, n: mix(deep(frame, 0.14), tint(frame, 0.16), 0.45 + 0.5 * n[1] * 0.7)
    for s, c, x, y, n in fr:
        ring_loop('rim%+d' % s, c, x, y, n, circle_poly(R, 28), lambda px, py: 0.044, 0.022, fcol, n=28, e=2.4, sides=8)
        bead('hinge%+d' % s, c + x * (s * (R + 0.010)) + y * 0.006, (0.020, 0.022, 0.018), deep(frame, 0.22), segs=6)
    bridge_arc('bridge', stand, 0.838, 0.118, 0.021, fcol, arch=0.020, flat=0.9)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.834, fcol, hv=0.021, ht=0.010, off=0.019, dx=0.118)
    return dict(anchor='face', slot='face', tags=['cool', 'cute'], price=40, title='Round glasses',
                desc='Round honey acetate glasses with thick glossy rims, end-piece hinges and temples that wrap back along the head. Frames only, no lens fill, so the eyes stay readable.')

# ============================ STAR / HEART SHADES (rebuild) =====================
def star_shades(frame=PINK, lens=INK, **k):
    reset()
    stand = 0.052
    fr = eye_frames(stand)
    fcol = lambda p, n: mix(deep(frame, 0.10), tint(frame, 0.2), 0.45 + 0.5 * n[1] * 0.7)
    for s, c, x, y, n in fr:
        outl = star_poly(0.134, 0.082, 5, rot=math.pi / 2 + math.pi / 5, rad=0.026)
        ring_loop('frame%+d' % s, c, x, y, n, outl, lambda px, py: 0.052, 0.022, fcol, n=30, e=2.4, sides=6)
        lens_part('lens%+d' % s, c, x, y, n, star_poly(0.120, 0.068, 5, rot=math.pi / 2 + math.pi / 5, rad=0.022), lambda p, nn: mix(lens, LAV, 0.3 * max(0, nn[1])), thick=0.014, z0=-0.006)
    bridge_arc('bridge', stand, 0.846, 0.100, 0.019, fcol, arch=0.020, flat=0.85)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.846, fcol, hv=0.021, ht=0.010, off=0.019, dx=0.130)
    return dict(anchor='face', slot='face', tags=['cool', 'sparkly'], price=60, title='Star sunglasses',
                desc='Pink star sunglasses: a thick glossy star frame round dark plum lenses, temples wrapping back along the head.')

def heart_shades(frame=CORAL, lens=hx('#8E2F5E'), **k):
    reset()
    stand = 0.052
    fr = eye_frames(stand)
    from items2_other import heart_poly
    fcol = lambda p, n: mix(deep(frame, 0.10), tint(frame, 0.2), 0.45 + 0.5 * n[1] * 0.7)
    for s, c, x, y, n in fr:
        outl = [(px, py) for px, py in heart_poly(0.116, 22)]
        ring_loop('frame%+d' % s, c, x, y, n, outl, lambda px, py: 0.050, 0.022, fcol, n=30, e=2.4, sides=6)
        lens_part('lens%+d' % s, c, x, y, n, [(px * 0.88, py * 0.88) for px, py in heart_poly(0.104, 18)], lambda p, nn: mix(lens, hx('#E98AA4'), 0.30 * max(0, nn[1])), thick=0.014, z0=-0.006)
    bridge_arc('bridge', stand, 0.855, 0.100, 0.019, fcol, arch=0.020, flat=0.85)
    for s in (-1, 1):
        temple_bar('temple%+d' % s, fr, s, 0.846, fcol, hv=0.021, ht=0.010, off=0.019, dx=0.118)
    return dict(anchor='face', slot='face', tags=['sweet', 'sparkly', 'cute'], price=55, title='Heart sunglasses',
                desc='Coral heart sunglasses: a thick glossy heart frame, berry lenses, temples wrapping back along the head.')

# ============================ AVIATOR GOGGLES (rebuild) ========================
def goggles(rim=HONEY, strap=CORAL, glass=hx('#7CC4D6'), **k):
    reset()
    segs = 24
    y0 = lambda phi: 1.062 + 0.014 * math.sin(phi)
    loop = [(0.020, -0.026), (0.044, -0.026), (0.044, 0.026), (0.020, 0.026)]
    torus('strap', segs, lambda phi: [eloop(y0(phi), phi, h, v) for h, v in loop], lambda p, n: mix(deep(strap, 0.10), tint(strap, 0.12), 0.5 + 0.5 * n[1] * 0.5))
    R = 0.080
    rimc = lambda p, nn: mix(deep(rim, 0.16), tint(rim, 0.16), 0.5 + 0.5 * nn[1] * 0.7)
    for s in (-1, 1):
        c = B.front_surface(s * 0.150, 1.075)
        n = full_n(c)
        x, y, z = axes(n)
        ctr = c + z * 0.040
        ring_loop('rim%+d' % s, ctr, x, y, z, circle_poly(R, 22), lambda px, py: 0.034, 0.021, rimc, n=22, e=2.3, sides=6)
        bead('glass%+d' % s, ctr - z * 0.003, (R * 0.97, 0.021, R * 0.97), lambda p, nn: mix(glass, tint(glass, 0.55), max(0, 0.5 + 0.5 * nn[1]) * 0.4 + max(0, nn[2]) * 0.3), rot=np.stack([x, z, y], 1), segs=12)
    bridge_pts = []
    for t in np.linspace(-1, 1, 5):
        p = B.front_surface(t * 0.074, 1.075 + 0.012 * (1 - t * t))
        bridge_pts.append(p + full_n(p) * 0.046)
    tube_curve('bridge', bridge_pts, 0.0145, 6, rim, cap=True, flat=0.9)
    return dict(anchor='face', slot='face', tags=['cool', 'sporty'], price=55, title='Aviator goggles',
                desc='Brass-rim goggles with teal glass pushed up on the forehead on a wide coral strap at y~1.06; thick rims (0.034 wide). Lens bottoms y>=0.98, above the brows.')

# ============================ MONOCLE (rebuild) ===============================
def monocle(gold=HONEY, **k):
    reset()
    stand = 0.050
    R = 0.088
    fr = eye_frames(stand)
    s, c, x, y, n = [f for f in fr if f[0] == 1][0]
    gcol = lambda p, nn: mix(deep(gold, 0.16), tint(gold, 0.2), 0.45 + 0.5 * nn[1] * 0.7)
    ring_loop('ring', c, x, y, n, circle_poly(R, 28), lambda px, py: 0.042, 0.021, gcol, n=28, e=2.3, sides=8)
    a = math.radians(-35)
    start = c + (x * math.cos(a) + y * math.sin(a)) * (R + 0.012)
    bead('hinge', start, (0.021, 0.021, 0.021), deep(gold, 0.15), segs=6)
    path = [start]
    for (px, py, off) in ((0.31, 0.735, 0.040), (0.36, 0.690, 0.040), (0.405, 0.625, 0.040), (0.425, 0.565, 0.040)):
        p, nn = body_pt(px, py, off)
        path.append(p)
    for i in range(len(path) - 1):
        a_, b_ = path[i], path[i + 1]
        for q in range(2):
            m = a_ + (b_ - a_) * (q + 0.5) / 2
            d = (b_ - a_) / np.linalg.norm(b_ - a_)
            ref = np.array([0, 0, 1.0]) if q % 2 == 0 else np.array([1.0, 0, 0])
            xx = np.cross(d, ref); xx /= np.linalg.norm(xx)
            zz = np.cross(d, xx)
            bead('link%d_%d' % (i, q), m, (0.011, 0.024, 0.0075) if q % 2 == 0 else (0.0075, 0.024, 0.011), tint(gold, 0.1), rot=np.stack([xx, d, zz], 1), segs=6)
    bead('clip', path[-1], (0.026, 0.026, 0.020), gold, segs=8)
    return dict(anchor='face', slot='face', tags=['cool', 'sweet'], price=45, title='Monocle',
                desc='Gold monocle: a thick glossy ring round the +x eye bead with a hinge and a chunky oval-link chain hanging OUTWARD to a clip at (0.425,0.565).')

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
