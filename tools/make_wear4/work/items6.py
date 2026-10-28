"""Batch 4 new pieces (2026-10-27): Viking helmet, cable-knit pom beanie, tennis visor, quilted puffer vest, cable cardigan, silk patterned neck scarf,
chunky gold chain, quilted crossbody bag. Abstract shapes only: no logos, no brand marks."""
from kit5 import *
from items2_head import torus, thick_sheet
from items_head import shell

NEW = ('viking_hat', 'beanie_cable', 'visor_tennis', 'vest_puffer', 'cardigan_cable', 'scarf_silk', 'chain_gold', 'bag_crossbody')

def egg_pt(y, phi, off=0.0):
    p = B.egg_point(y, phi)
    return p + hdir(p) * off

# ============================ VIKING HELMET ====================================
def viking(steel=hx('#9AA9B8'), band=hx('#6C7C8E'), horn=BONE, rivet=hx('#E1B65A'), **k):
    reset(); segs = 36
    y0 = lambda phi: 1.050 + 0.034 * math.sin(phi)
    rows = [('a', 0.012, 0.012), ('a', -0.004, 0.030), ('a', 0.014, 0.050), ('a', 0.060, 0.056)]
    for f, o in ((0.0, 0.058), (0.22, 0.064), (0.45, 0.066), (0.68, 0.064), (0.86, 0.058), (0.96, 0.048)): rows.append(('k', f, o))
    rows.append(('pole', 0, 0.044))
    def col(p, n):
        return mix(deep(steel, 0.16), tint(steel, 0.30), 0.35 + 0.65 * max(0, n[1]) * 0.9)
    shell('dome', segs, y0, rows, col)
    # the rim band (no nose guard): a thick rolled metal band round the head
    def bl(phi):
        yb = y0(phi)
        return [eloop(yb, phi, h, v) for h, v in ((0.040, -0.026), (0.070, -0.026), (0.080, -0.014), (0.082, 0.062), (0.074, 0.080), (0.044, 0.080))]
    torus('band', segs, bl, lambda p, n: mix(deep(band, 0.18), tint(band, 0.30), 0.4 + 0.6 * max(0, n[1] * 0.5 + n[2] * 0.0)), sharp=55)
    # rivets along the band, and a ridge line above it
    for i in range(20):
        phi = 2 * math.pi * (i + 0.5) / 20
        ico_part('rivet%d' % i, tuple(eloop(y0(phi) + 0.034, phi, 0.088, 0.0)), (0.0145, 0.0145, 0.0145), rivet, sub=1)
    pts = [eloop(y0(phi) + 0.080, phi, 0.062, 0.0) for phi in np.linspace(0, 2 * math.pi, 49)]
    tube_curve('ridge', pts, 0.0125, 6, lambda p, n: mix(deep(band, 0.25), tint(band, 0.25), 0.5 + 0.5 * n[1]), cap=False)
    # a round boss on the front of the band
    pb = eloop(y0(math.pi / 2) + 0.034, math.pi / 2, 0.092, 0.0)
    lathe_y('boss', [(0.0, 0.0), (0.050, 0.0), (0.054, 0.010), (0.046, 0.026), (0.0, 0.032)], 20, lambda p, n: mix(deep(rivet, 0.15), tint(rivet, 0.25), 0.5 + 0.5 * n[1]), centre=tuple(pb), rotm=np.array(rot_x(math.pi / 2)).tolist(), sharp=60)
    # two curved horns from the sides of the band
    for s in (-1, 1):
        phi = 0.0 if s > 0 else math.pi
        yb = 1.112
        base = egg_pt(yb, phi, 0.074)
        d = np.array([s, 0, 0.0])
        cup_axis = basis_to(np.array([s * 1.0, 0.45, 0.0]))
        ico_part('cup%+d' % s, tuple(base + d * 0.012), (0.060, 0.064, 0.060), lambda p, n: mix(deep(band, 0.2), tint(band, 0.3), 0.5 + 0.5 * n[1]), sub=2)
        pth = [base + np.array([s * dx, dy, dz]) for dx, dy, dz in ((0.0, 0.0, 0.0), (0.070, 0.016, 0.004), (0.135, 0.070, 0.016), (0.178, 0.150, 0.034), (0.198, 0.240, 0.056), (0.192, 0.320, 0.078), (0.178, 0.372, 0.090))]
        def hcol(p, n, base=base):
            t = max(0.0, min(1.0, (p[1] - base[1]) / 0.42))
            c = mix(horn, hx('#D6C396'), t * 0.6)
            return mix(deep(c, 0.12), tint(c, 0.2), 0.5 + 0.5 * n[1] * 0.5)
        tube_curve('horn%+d' % s, pth, 0.066, 12, hcol, cap=True, radfn=lambda t: 0.066 * (1 - t) ** 0.8 + 0.012, flat=0.95)
        # a metal collar where the horn meets the cup
        ico_part('collar%+d' % s, tuple(pth[1]), (0.052, 0.052, 0.052), lambda p, n: mix(deep(rivet, 0.2), tint(rivet, 0.25), 0.5 + 0.5 * n[1]), sub=2)
    return dict(anchor='head_top', slot='head', tags=['cool', 'sporty'], price=80, title='Viking helmet',
                desc='Rounded steel helmet with a thick rolled brim band (no nose guard), a ridge line, golden rivets and a front boss, topped by two curved bone horns on metal cups. Encloses the head (CrownFit); front band edge y~1.08, above the brows.')

# ============================ CABLE-KNIT POM BEANIE ===========================
def beanie_cable(main=hx('#F1E6D2'), cuff=hx('#E4D3B6'), pom=hx('#FBF6EE'), **k):
    reset(); segs = 40
    y0 = lambda phi: 1.012 + 0.04 * math.sin(phi)
    rows = [('a', 0.010, 0.006), ('a', -0.002, 0.026), ('a', 0.012, 0.050), ('a', 0.048, ribbed(0.060, 0.005, 16)), ('a', 0.090, ribbed(0.056, 0.005, 16)), ('a', 0.100, 0.046)]
    # the cables: twisted ridges that run up the crown (a phase shift per row makes them braid)
    for j, (f, o) in enumerate(((0.0, 0.052), (0.14, 0.058), (0.28, 0.062), (0.42, 0.063), (0.56, 0.062), (0.70, 0.058), (0.82, 0.052), (0.92, 0.044), (0.975, 0.034))):
        rows.append(('k', f, (lambda ph, j=j, o=o: o + 0.012 * math.cos(8 * ph + 0.95 * j) * (1 - 0.5 * j / 8.0))))
    rows.append(('pole', 0, 0.026))
    def col(p, n):
        phi = math.atan2(p[2], p[0]); dy = p[1] - y0(phi)
        if dy < 0.10:
            rib = 0.5 + 0.5 * math.cos(16 * phi)
            return mix(cuff, deep(cuff, 0.16), 0.40 * (1 - rib))
        # cable stripes: darker valleys between braids
        v = 0.5 + 0.5 * math.cos(8 * phi + 0.95 * max(0, (p[1] - 1.1) / 0.035))
        return mix(deep(main, 0.30), tint(main, 0.10), 0.20 + 0.80 * v)
    shell('knit', segs, y0, rows, col)
    # a big fluffy pom on a short tail at the back so the crown stays clear (Moss's sprout sits on top)
    yp = 1.28
    c = egg_pt(yp, 3 * math.pi / 2, 0.040) + np.array([0, 0.060, -0.065])
    ico_part('pom', tuple(c), (0.110, 0.105, 0.110), lambda p, n: mix(deep(pom, 0.10), pom, 0.5 + 0.5 * n[1]), sub=3, fuzz=0.06, seed=7)
    return dict(anchor='head_top', slot='head', tags=['cute', 'sweet'], price=45, title='Cable-knit beanie',
                desc='Cream cable-knit beanie: braided ridges up the crown, a ribbed cuff and a fluffy pom on a tail at the back (the crown stays free for the sprout). Cuff edge above the brows.')

# ============================ TENNIS VISOR ====================================
def visor(band=hx('#F7F3EA'), brim=hx('#F7F3EA'), under=hx('#3C6E8F'), trim=hx('#E96C6C'), **k):
    reset(); segs = 40
    y0 = lambda phi: 1.050 + 0.026 * math.sin(phi)
    def lp(phi):
        yb = y0(phi)
        return [eloop(yb, phi, h, v) for h, v in ((0.030, -0.026), (0.052, -0.030), (0.062, -0.016), (0.062, 0.036), (0.050, 0.050), (0.030, 0.046))]
    torus('band', segs, lp, lambda p, n: mix(deep(band, 0.10), tint(band, 0.1), 0.5 + 0.5 * n[1] * 0.6), sharp=60)
    # sweat stripe
    torus('stripe', segs, lambda phi: [eloop(y0(phi) + 0.014, phi, h, v) for h, v in ((0.0625, -0.003), (0.0665, 0.0), (0.0665, 0.014), (0.0625, 0.017))], trim, sharp=60)
    # the brim: a curved bill that sweeps forward and a little down, rounded front corners
    nu, nv = 17, 6
    def fn(i, j):
        u = i / (nu - 1) * 2 - 1                     # across, -1..1
        v = j / (nv - 1)                              # 0 at the band, 1 at the edge
        phi = math.pi / 2 - u * math.radians(62)
        base = B.egg_point(y0(phi) + 0.020, phi)
        h = hdir(base)
        reach = (0.040 + 0.250 * (v ** 1.0)) * (1 - 0.30 * abs(u) ** 2.6) * (1.0)
        drop = -0.050 * v ** 1.6 - 0.030 * v * abs(u) ** 2
        p = base + h * (0.056 + reach) + np.array([0, drop, 0])
        n = h * 0.4 + np.array([0, 1.0, 0])
        return p, n / np.linalg.norm(n)
    thick_sheet('bill', fn, nu, nv, 0.026, lambda p, n: brim, color_in=lambda p, n: under)
    return dict(anchor='head_top', slot='head', tags=['sporty', 'cute'], price=35, title='Tennis visor',
                desc='White tennis visor: a soft headband with a coral sweat stripe and a curved bill with a blue underside, open on top so the crown (and the sprout) stay free. Perching piece (never moved by CrownFit). Bill edge above the brows.')

# ============================ PUFFER VEST =====================================
def vest_puffer(main=hx('#2E7C85'), trim=hx('#1F5760'), zip_=GOLD, **k):
    reset()
    ys = list(np.linspace(0.225, 0.505, 22))
    wave = lambda y: math.cos(2 * math.pi * (y - 0.225) / 0.070)
    offs = []
    for y in ys:
        offs.append(lambda phi, y=y: 0.040 + 0.0125 * wave(y) * (0.65 + 0.35 * math.cos(14 * phi)))
    def col(p, n):
        y = p[1]
        w = wave(y)
        base = mix(deep(main, 0.22), tint(main, 0.20), 0.5 + 0.5 * n[1] * 0.6)
        return mix(base, deep(main, 0.38), 0.55 * smooth01(0.55, 1.0, -w))
    plate_shell('body', ys, offs, col, segs=40)
    # ribbed hem and stand-up collar roll (top 0.51: clear of the mouth)
    torus('hem', 40, lambda phi: [eloop(0.230, phi, h, v) for h, v in ((0.034, 0.030), (0.050, 0.022), (0.052, -0.016), (0.038, -0.026))], lambda p, n: mix(deep(trim, 0.2), tint(trim, 0.2), 0.5 + 0.5 * math.cos(30 * phi_of(p))))
    torus('collar', 40, lambda phi: [eloop(0.498, phi, h, v) for h, v in ((0.028, 0.020), (0.058, 0.014), (0.062, -0.010), (0.034, -0.018))], lambda p, n: mix(deep(trim, 0.15), tint(trim, 0.22), 0.5 + 0.5 * n[1]))
    # zip line + pull
    pts = [body_pt(0.0, y, 0.062)[0] for y in np.linspace(0.236, 0.496, 10)]
    tube_curve('zip', pts, 0.0095, 5, zip_, cap=True)
    p, n = body_pt(0.0, 0.468, 0.070)
    xx, yy, nn = axes(n)
    ico_part('pull', tuple(p - yy * 0.014), (0.016, 0.030, 0.010), lambda q, nq: mix(deep(zip_, 0.12), tint(zip_, 0.3), 0.5 + 0.5 * nq[1]), sub=2, rot=np.stack([xx, yy, nn], 1).tolist())
    # two zipped pockets on the sides of the belly
    for s in (-1, 1):
        pp = [body_pt(s * (0.200 + 0.012 * t), 0.250 + 0.062 * t, 0.060)[0] for t in np.linspace(0, 1, 6)]
        tube_curve('pocket%+d' % s, pp, 0.0075, 5, zip_, cap=True)
    return dict(anchor='chest', slot='body', tags=['cool', 'sporty'], price=65, title='Puffer vest',
                desc='Teal quilted puffer vest: horizontal baffles with vertical seams, ribbed hem, stand-up collar (top 0.51), gold zip and pull, two zip pockets. Sleeveless: the arms stay free. Nothing on the front above y 0.51.')

# ============================ CABLE CARDIGAN ===================================
def cardigan(main=hx('#C97B4E'), trim=hx('#E8C8A0'), button=hx('#F4EBDD'), **k):
    reset()
    ys = list(np.linspace(0.175, 0.505, 24))
    offs = []
    for j, y in enumerate(ys):
        offs.append(lambda phi, y=y: 0.040 + 0.0065 * math.cos(10 * phi + 5.0 * math.sin((y - 0.175) * 9.0)) + 0.004 * math.cos(5 * phi))
    def col(p, n):
        phi = phi_of(p)
        v = 0.5 + 0.5 * math.cos(10 * phi + 5.0 * math.sin((p[1] - 0.175) * 9.0))
        return mix(deep(main, 0.20), tint(main, 0.14), 0.30 + 0.70 * v * (0.7 + 0.3 * n[1]))
    plate_shell('body', ys, offs, col, segs=60)
    torus('hem', 60, lambda phi: [eloop(0.182, phi, h, v) for h, v in ((0.034, 0.030), (0.056, 0.022), (0.058, -0.016), (0.040, -0.026))], lambda p, n: mix(deep(trim, 0.26), tint(trim, 0.16), 0.5 + 0.5 * math.cos(30 * phi_of(p))))
    # shawl collar rolls down the front into the button band (top 0.51)
    torus('collar', 60, lambda phi: [eloop(0.497, phi, h, v) for h, v in ((0.030, 0.022), (0.060, 0.016), (0.066, -0.012), (0.036, -0.022))], lambda p, n: mix(deep(trim, 0.22), tint(trim, 0.22), 0.5 + 0.5 * n[1]))
    # button band down the front, with five buttons
    pts = [body_pt(0.0, y, 0.054)[0] for y in np.linspace(0.200, 0.494, 12)]
    tube_curve('placket', pts, 0.0175, 7, lambda p, n: mix(deep(trim, 0.2), tint(trim, 0.2), 0.5 + 0.5 * n[1]), cap=True, flat=0.8)
    for i, y in enumerate(np.linspace(0.238, 0.470, 5)):
        p, n = body_pt(0.0, float(y), 0.074)
        xx, yy, nn = axes(n)
        ico_part('button%d' % i, tuple(p), (0.0235, 0.0235, 0.010), button, sub=2, rot=np.stack([xx, yy, nn], 1).tolist())
        ico_part('hole%d' % i, tuple(p + nn * 0.007), (0.007, 0.007, 0.004), deep(button, 0.45), sub=1, rot=np.stack([xx, yy, nn], 1).tolist())
    # patch pockets
    for s in (-1, 1):
        p, n = body_pt(s * 0.205, 0.290, 0.058)
        xx, yy, nn = axes(n)
        ico_part('pocket%+d' % s, tuple(p), (0.072, 0.056, 0.012), lambda q, nq: mix(deep(main, 0.14), tint(main, 0.16), 0.5 + 0.5 * nq[2]), sub=2, rot=np.stack([xx, yy, nn], 1).tolist())
    return dict(anchor='chest', slot='body', tags=['cute', 'sweet'], price=60, title='Cable cardigan',
                desc='Rust cable-knit cardigan: braided ridges, ribbed hem, a shawl collar (top 0.51), a cream button band with five buttons and two patch pockets. Sleeveless over the belly; arms stay free.')

# ============================ SILK NECK SCARF ==================================
def silk_pattern(base, ring, dot):
    def col(p, n):
        # abstract medallions: a rotated grid of rings and dots (no letters or marks)
        u = p[0] * 6.0 + p[1] * 2.0
        v = p[1] * 6.0 - p[0] * 2.0
        fu = u - math.floor(u) - 0.5
        fv = v - math.floor(v) - 0.5
        r = math.hypot(fu, fv)
        c = base
        if 0.26 < r < 0.38: c = ring
        elif r < 0.12: c = dot
        return mix(deep(c, 0.06), tint(c, 0.16), 0.5 + 0.5 * n[1] * 0.5)
    return col

def scarf_silk(base=hx('#2F3E6B'), ring=hx('#E8B84A'), dot=hx('#F4E9D6'), **k):
    reset()
    X0 = 0.40
    pat = silk_pattern(base, ring, dot)
    pts = [body_pt(x, 0.488 + 0.018 * (x / X0) ** 2, 0.040)[0] for x in np.linspace(-X0, X0, 21)]
    tube_curve('wrap', pts, 0.0, 8, pat, radfn=lambda t: 0.032 + 0.026 * math.sin(math.pi * t) ** 0.6, cap=True, flat=0.75)
    kc, kn = body_pt(-0.140, 0.466, 0.062)
    xx, yy, nn = axes(kn)
    ico_part('knot', tuple(kc), (0.052, 0.046, 0.040), lambda p, n: mix(deep(base, 0.10), tint(base, 0.2), 0.5 + 0.5 * n[2]), sub=2, rot=np.stack([xx, yy, nn], 1).tolist())
    def tail(cx0, cx1, y0, y1, w, name, off, wav):
        eps = 0.0
        nu, nv = 4, 9
        def fn(i, j):
            v = j / (nv - 1); u = i / (nu - 1) - 0.5
            cx = cx0 + (cx1 - cx0) * v + 0.016 * math.sin(4.0 * v + wav)
            y = y0 + (y1 - y0) * v
            ww = w * (1 + 0.5 * v) * (1 - 0.18 * math.cos(math.pi * v * 3 + wav) * v)
            p, n = body_pt(cx + u * ww, y, off + 0.010 * math.sin(3.0 * v + wav) * v)
            return p, n
        thick_sheet(name, fn, nu, nv, 0.012, pat)
    tail(-0.150, -0.230, 0.452, 0.190, 0.072, 'tail_a', 0.056, 0.0)
    tail(-0.120, -0.060, 0.446, 0.240, 0.068, 'tail_b', 0.062, 1.7)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly', 'sweet'], price=55, title='Silk scarf',
                desc='A silky neck scarf in navy printed with gold medallions (abstract rings and dots): a slim wrap across the belly at y~0.49 (top <=0.54), a side knot and two fluttering tails. Everything below the mouth keep-out.')

# ============================ GOLD CHAIN ======================================
def chain_gold(gold=hx('#E8B84A'), **k):
    reset()
    def pxy(t):
        x = -0.34 + 0.68 * t
        return x, 0.520 - 0.112 * (1 - (x / 0.34) ** 2)
    ts = np.linspace(0, 1, 500)
    xy = np.array([pxy(t) for t in ts])
    seg = np.linalg.norm(np.diff(xy, axis=0), axis=1)
    L = np.concatenate([[0], np.cumsum(seg)])
    nlink = 15
    gcol = lambda p, n: mix(deep(gold, 0.25), tint(gold, 0.40), 0.35 + 0.65 * max(0, n[1] * 0.7 + 0.3))
    for k_ in range(nlink):
        d = L[-1] * (k_ + 0.5) / nlink
        i = int(np.searchsorted(L, d)); i = min(i, len(xy) - 2)
        x, y = xy[i]
        tx, ty = xy[i + 1] - xy[i]
        p, nn = body_pt(x, y, 0.042)
        xx, yy, z = axes(nn)
        tdir = xx * tx + yy * ty
        tdir /= np.linalg.norm(tdir)
        if k_ % 2 == 0:       # flat link, seen face-on
            side = np.cross(z, tdir); side /= np.linalg.norm(side)
            ico_part('link%d' % k_, tuple(p), (0.044, 0.028, 0.011), gcol, sub=2, rot=np.stack([tdir, side, z], 1).tolist())
            ico_part('hole%d' % k_, tuple(p + z * 0.0045), (0.022, 0.011, 0.006), deep(gold, 0.55), sub=1, rot=np.stack([tdir, side, z], 1).tolist())
        else:                 # edge-on link
            ico_part('link%d' % k_, tuple(p), (0.044, 0.011, 0.026), gcol, sub=2, rot=np.stack([tdir, z, np.cross(tdir, z)], 1).tolist())
    # coin pendant at the lowest point
    p, nn = body_pt(0.0, 0.392, 0.056)
    xx, yy, z = axes(nn)
    Rm = np.stack([xx, z, -yy], 1).tolist()
    lathe_y('coin', [(0.0, -0.014), (0.070, -0.014), (0.080, -0.006), (0.080, 0.010), (0.070, 0.018), (0.0, 0.018)], 24, lambda q, nq: mix(deep(gold, 0.15), tint(gold, 0.32), 0.5 + 0.5 * nq[1]), centre=tuple(p), rotm=Rm, sharp=45)
    lathe_y('coinring', [(0.046, 0.017), (0.053, 0.022), (0.063, 0.022), (0.067, 0.017)], 24, lambda q, nq: deep(gold, 0.30), centre=tuple(p), rotm=Rm, sharp=45)
    sp = star_poly(0.034, 0.016, 5, rad=0.005)
    slab_part('star', sp, 0.006, lambda q, nq: tint(gold, 0.35), lambda px, py, pz: tuple(p + xx * px + yy * py + z * (0.015 + pz)), cuts=0)
    ico_part('bail', tuple(p + yy * 0.086), (0.020, 0.020, 0.016), deep(gold, 0.1), sub=1)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly'], price=70, title='Gold chain',
                desc='A chunky gold curb chain in a swag from (+-0.34,0.52) down to a coin pendant at y~0.39: nineteen big alternating links. Lowest point on the centre line; nothing near the mouth keep-out.')

# ============================ CROSSBODY BAG ====================================
def bag_crossbody(main=hx('#F0D9B5'), strap=hx('#8B5A3C'), gold=GOLD, **k):
    reset()
    # strap: from the left shoulder (ends tucked behind the arm root) down across the belly to the bag at the right hip
    a = np.array([-0.42, 0.600]); b = np.array([0.300, 0.282])
    d = (b - a) / np.linalg.norm(b - a); perp = np.array([-d[1], d[0]])
    nL = 17; W_ = 0.052
    rows = [(-1.0, 0.016), (-0.7, 0.026), (-0.3, 0.030), (0.3, 0.030), (0.7, 0.026), (1.0, 0.016)]
    def pt(i, j):
        t = i / (nL - 1); w, off = rows[j]
        q = a + (b - a) * t + perp * W_ * w
        p, n = body_pt(q[0], q[1], off); return p
    grid_surface('strap', pt, nL, len(rows), strap, closed_u=False, hint=lambda p: full_n(p), gcol=lambda i, j: mix(deep(strap, 0.12), tint(strap, 0.14), 0.5 + 0.1 * (j - 2.5)))
    for t in np.linspace(0.06, 0.94, 13):
        q = a + (b - a) * t
        p, n = body_pt(q[0] + perp[0] * W_ * 0.9, q[1] + perp[1] * W_ * 0.9, 0.032)
    for s in (-1, 1):
        pts = []
        for t in np.linspace(0.0, 1.0, 14):
            q = a + (b - a) * t + perp * W_ * 0.80 * s
            pts.append(body_pt(q[0], q[1], 0.030)[0])
        tube_curve('stitch%+d' % s, pts, 0.0035, 4, deep(strap, 0.3), cap=True)
    # the bag: a puffy quilted pouch at the right hip, hung on the strap end
    c, n = body_pt(0.290, 0.222, 0.0)
    xx, yy, z = axes(n)
    ctr = c + z * 0.056
    Rm = np.stack([xx, yy, z], 1)
    nu, nv = 14, 12
    hw, hh, dp = 0.150, 0.114, 0.062
    def bp(i, j):
        ph = 2 * math.pi * i / nu; th = -math.pi / 2 + math.pi * j / (nv - 1)
        e = 0.42
        ux = spow(math.cos(th) * math.cos(ph), 2 / (2 * e) * 1.0) if False else math.copysign(abs(math.cos(th) * math.cos(ph)) ** 0.45, math.cos(th) * math.cos(ph))
        uy = math.copysign(abs(math.cos(th) * math.sin(ph)) ** 0.45, math.cos(th) * math.sin(ph))
        uz = math.copysign(abs(math.sin(th)) ** 0.5, math.sin(th))
        quilt = 1 + 0.07 * math.cos(2 * math.pi * ux * 2.0) * math.cos(2 * math.pi * uy * 2.0) * (abs(uz) > 0.2)
        return ctr + Rm @ np.array([hw * ux, hh * uy, dp * uz * quilt])
    def bcol(p, n_):
        q = Rm.T @ (np.array(p) - ctr)
        qx = (q[0] / hw) * 2.0; qy = (q[1] / hh) * 2.0
        v = 0.5 + 0.5 * math.cos(2 * math.pi * qx) * math.cos(2 * math.pi * qy)
        return mix(deep(main, 0.22), tint(main, 0.16), 0.30 + 0.70 * v)
    grid_surface('pouch', bp, nu, nv, bcol, hint=lambda p: np.array(p) - ctr)
    # flap + gold clasp + hanging ring where the strap joins
    fl = [ctr + Rm @ np.array([hw * 1.0 * math.cos(a_), hh * 0.30 + hh * 0.70 * math.sin(a_), dp * 0.96]) for a_ in np.linspace(math.pi * 1.05, math.pi * 1.95, 9)]
    tube_curve('flap', [ctr + Rm @ np.array([x_, hh * 0.18 - 0.02 * (1 - (x_ / hw) ** 2), dp * 0.98]) for x_ in np.linspace(-hw * 0.96, hw * 0.96, 13)], 0.0085, 6, deep(main, 0.30), cap=True)
    p_cl = ctr + Rm @ np.array([0, hh * 0.18 - 0.02, dp * 1.06])
    lathe_y('clasp', [(0.0, 0.0), (0.030, 0.0), (0.033, 0.008), (0.026, 0.016), (0.0, 0.019)], 16, lambda q, nq: mix(deep(gold, 0.15), tint(gold, 0.3), 0.5 + 0.5 * nq[1]), centre=tuple(p_cl), rotm=np.stack([xx, z, -yy], 1).tolist(), sharp=55)
    p_ring = ctr + Rm @ np.array([-hw * 0.78, hh * 0.80, dp * 0.35])
    ico_part('ring', tuple(p_ring), (0.024, 0.024, 0.016), gold, sub=1)
    return dict(anchor='chest', slot='body', tags=['cute', 'sweet', 'sparkly'], price=75, title='Quilted crossbody bag',
                desc='A small quilted cream bag with a gold clasp, hung at the right hip on a brown strap that crosses the belly from the left shoulder (ends tucked behind the arm root). Strap top y 0.60 at the side, 0.45 at the centre line: below the mouth keep-out.')

REG = [
    ('viking_hat', viking, dict(), H),
    ('beanie_cable', beanie_cable, dict(), H),
    ('visor_tennis', visor, dict(), H),
    ('vest_puffer', vest_puffer, dict(), BIB_ANCHOR),
    ('cardigan_cable', cardigan, dict(), BIB_ANCHOR),
    ('scarf_silk', scarf_silk, dict(), NECK_ANCHOR),
    ('chain_gold', chain_gold, dict(), NECK_ANCHOR),
    ('bag_crossbody', bag_crossbody, dict(), BIB_ANCHOR),
]
