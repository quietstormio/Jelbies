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
def viking(steel=hx('#A9B8C8'), band=hx('#6C7C8E'), horn=BONE, rivet=hx('#E1B65A'), **k):
    reset(); segs = 24
    y0 = lambda phi: 1.050 + 0.034 * math.sin(phi)
    rows = [('a', 0.012, 0.012), ('a', -0.004, 0.034), ('a', 0.016, 0.062), ('a', 0.070, 0.076)]
    for f, o in ((0.0, 0.092), (0.30, 0.140), (0.60, 0.170), (0.84, 0.170), (0.96, 0.150)): rows.append(('k', f, o))
    rows.append(('pole', 0, 0.130))
    def col(p, n):
        h = (p[1] - 1.10) / 0.40
        return mix(deep(steel, 0.30), tint(steel, 0.55), 0.20 + 0.80 * max(0.0, min(1.0, h * 0.8 + 0.5 * max(0, n[1]))))
    shell('dome', segs, y0, rows, col)
    def bl(phi):
        yb = y0(phi)
        return [eloop(yb, phi, h, v) for h, v in ((0.040, -0.026), (0.080, -0.026), (0.092, -0.006), (0.092, 0.066), (0.082, 0.084), (0.044, 0.082))]
    torus('band', segs, bl, lambda p, n: mix(deep(band, 0.22), tint(band, 0.30), 0.35 + 0.65 * max(0, n[1] * 0.5 + 0.5)), sharp=55)
    for i_, ph in enumerate((math.radians(55), math.radians(125), math.radians(20), math.radians(160))):
        bead('rivet%d' % i_, eloop(y0(ph) + 0.030, ph, 0.100, 0.0), (0.016, 0.016, 0.013), rivet, segs=6)
    pb = eloop(y0(math.pi / 2) + 0.030, math.pi / 2, 0.100, 0.0)
    lathe_y('boss', [(0.0, 0.0), (0.052, 0.0), (0.056, 0.010), (0.044, 0.026), (0.0, 0.030)], 12, lambda p, n: mix(deep(rivet, 0.15), tint(rivet, 0.25), 0.5 + 0.5 * n[1]), centre=tuple(pb), rotm=np.array(rot_x(math.pi / 2)).tolist(), sharp=60)
    for s in (-1, 1):
        phi = 0.0 if s > 0 else math.pi
        base = egg_pt(1.108, phi, 0.092)
        bead('cup%+d' % s, base + np.array([s * 0.014, 0, 0]), (0.062, 0.066, 0.060), lambda p, n: mix(deep(band, 0.2), tint(band, 0.3), 0.5 + 0.5 * n[1]), segs=8)
        pth = [base + np.array([s * dx, dy, dz]) for dx, dy, dz in ((0.0, 0.0, 0.0), (0.075, 0.020, 0.004), (0.140, 0.075, 0.016), (0.182, 0.155, 0.034), (0.196, 0.245, 0.056), (0.186, 0.325, 0.080), (0.172, 0.372, 0.092))]
        def hcol(p, n, base=base):
            t = max(0.0, min(1.0, (p[1] - base[1]) / 0.40))
            c = mix(horn, hx('#D6C396'), t * 0.6)
            return mix(deep(c, 0.12), tint(c, 0.2), 0.5 + 0.5 * n[1] * 0.5)
        tube_curve('horn%+d' % s, pth, 0.066, 8, hcol, cap=True, radfn=lambda t: 0.066 * (1 - t) ** 0.8 + 0.012, flat=0.95)
    return dict(anchor='head_top', slot='head', tags=['cool', 'sporty'], price=80, title='Viking helmet',
                desc='A proper rounded steel dome (crown about 0.12 above the head, enclosing it: CrownFit) with a thick rolled brim band (no nose guard), golden rivets and a front boss, topped by two curved bone horns on metal cups. Front band edge y~1.08, above the brows.')

# ============================ CABLE-KNIT POM BEANIE ===========================
def beanie_cable(main=hx('#F1E6D2'), cuff=hx('#E4D3B6'), pom=hx('#FBF6EE'), **k):
    reset(); segs = 28
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
    ico_part('pom', tuple(c), (0.110, 0.105, 0.110), lambda p, n: mix(deep(pom, 0.10), pom, 0.5 + 0.5 * n[1]), sub=1, fuzz=0.08, seed=7)
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

# ============================ VEST + CARDIGAN (open front, armholes) ===========
def angd(a, b):
    return abs((a - b + math.pi) % (2 * math.pi) - math.pi)

def top_edge(phi, front=0.50, back=0.60, notch=0.335, vtip=0.292, vhalf=0.50, side_half=0.44):
    """The garment's top edge round the body (phi 0 = +x, pi/2 = front): a deep V down the front (everything on the front stays below y .51), armhole
    notches round the arm nubs at the sides, and a higher back with the collar."""
    side = min(angd(phi, 0.0), angd(phi, math.pi))
    base = 0.55 - 0.05 * max(-1.0, min(1.0, math.sin(phi) * 3.0))
    y = notch + (base - notch) * smooth01(0.0, side_half, side)
    if base < 0.53:
        base_f = front
        y = min(y, vtip + (base_f - vtip) * smooth01(0.0, vhalf, angd(phi, math.pi / 2))) if angd(phi, math.pi / 2) < vhalf else y
    return y

def garment(main, trim, pat, ybot, off_fn, name, segs=36, rows=9, collar=0.020, pip=False):
    """pip=True: Pip's tail leaves the lower back (y~0.47), so his garment is open at the back (a tail slot +-40 deg round the back centre, trimmed edges)."""
    if pip:
        p0, p1 = math.radians(310.0), math.radians(310.0 + 280.0)
        segs = 30
    else:
        p0, p1 = 0.0, 2 * math.pi
    def phi_i(i): return p0 + (p1 - p0) * (i / (segs - 1 if pip else segs))
    def pt(i, j):
        phi = phi_i(i)
        yt = top_edge(phi)
        f = j / (rows - 1)
        y = ybot + (yt - ybot) * f
        e = B.egg_point(y, phi)
        return e + hdir(e) * off_fn(phi, f, j)
    grid_surface(name, pt, segs, rows, None, closed_u=not pip, hint=lambda p: IH.egg_hint(p), gcol=lambda i, j: pat(i, j, segs, rows))
    pts = []
    n_t = 40 if pip else 48
    for q in range(n_t + 1):
        phi = p0 + (p1 - p0) * q / n_t
        e = B.egg_point(top_edge(phi), phi)
        pts.append(e + hdir(e) * (off_fn(phi, 1.0, rows - 1) + 0.006))
    tube_curve('edge', pts, collar, 4, lambda p, n: mix(deep(trim, 0.15), tint(trim, 0.22), 0.5 + 0.5 * n[1]), cap=True)
    if pip:
        for k_, phi in enumerate((p0, p1)):
            col_pts = []
            for f in np.linspace(0.0, 1.0, 5):
                y = ybot + (top_edge(phi) - ybot) * f
                e = B.egg_point(y, phi)
                col_pts.append(e + hdir(e) * (off_fn(phi, f, int(f * (rows - 1))) + 0.004))
            tube_curve('slot%d' % k_, col_pts, collar * 0.8, 4, lambda p, n: mix(deep(trim, 0.15), tint(trim, 0.22), 0.5 + 0.5 * n[1]), cap=True)

def vest_puffer(main=hx('#2E7C85'), trim=hx('#1F5760'), zip_=GOLD, pip=False, **k):
    reset()
    ybot = 0.215
    def off(phi, f, j): return 0.040 + 0.012 * math.cos(2 * math.pi * 3.0 * f) * (0.70 + 0.30 * math.cos(12 * phi))
    def pat(i, j, segs, rows):
        f = j / (rows - 1)
        w = math.cos(2 * math.pi * 3.0 * f)
        return mix(deep(main, 0.34), tint(main, 0.22), 0.5 + 0.5 * w * (0.7 + 0.3 * math.cos(12 * 2 * math.pi * i / segs)))
    garment(main, trim, pat, ybot, off, 'body', segs=36, rows=11, collar=0.022, pip=pip)
    # the zip runs down the right edge of the V with a gold pull at the bottom
    pts = []
    for t in np.linspace(0.0, 1.0, 8):
        phi = math.pi / 2 - 0.50 * (1 - t)
        e = B.egg_point(top_edge(phi) - 0.006, phi)
        pts.append(e + hdir(e) * 0.062)
    tube_curve('zip', pts, 0.0075, 4, zip_, cap=True)
    e = B.egg_point(0.300, math.pi / 2)
    bead('pull', e + hdir(e) * 0.074, (0.016, 0.030, 0.010), zip_, segs=6)
    return dict(anchor='chest', slot='body', tags=['cool', 'sporty'], price=65, title='Puffer vest',
                desc='A teal quilted puffer vest: a deep V open front (nothing on the front above y 0.51), armholes cut round the arm nubs, a higher back with a piped collar edge, quilted baffles, hem and a gold zip. Open sleeveless: the arms stay free.')

def cardigan(main=hx('#C97B4E'), trim=hx('#E8C8A0'), button=hx('#F4EBDD'), pip=False, **k):
    reset()
    ybot = 0.200
    def off(phi, f, j): return 0.040 + 0.0075 * math.cos(10 * phi + 5.0 * math.sin(f * 9.0)) + 0.003 * math.cos(5 * phi)
    def pat(i, j, segs, rows):
        phi = 2 * math.pi * i / segs; f = j / (rows - 1)
        v = 0.5 + 0.5 * math.cos(10 * phi + 5.0 * math.sin(f * 9.0))
        c = mix(deep(main, 0.28), tint(main, 0.14), 0.25 + 0.75 * v)
        return mix(deep(trim, 0.2), trim, 0.5) if f < 0.07 else c
    garment(main, trim, pat, ybot, off, 'body', segs=36, rows=11, collar=0.024, pip=pip)
    # button band down the right edge of the open front with five buttons
    for i_ in range(5):
        t = (i_ + 0.5) / 5
        phi = math.pi / 2 - 0.50 * (1 - t) - 0.04
        e = B.egg_point(top_edge(phi) - 0.026, phi)
        bead('button%d' % i_, e + hdir(e) * 0.062, (0.024, 0.024, 0.012), button, segs=6)
    return dict(anchor='chest', slot='body', tags=['cute', 'sweet'], price=60, title='Cable cardigan',
                desc='A rust cable-knit cardigan: an open front falling to a deep V (front never above y 0.51) with a cream button band and five buttons, armholes round the arm nubs, a higher back with a collar edge, cable ridges and a ribbed hem.')

# ============================ SILK NECK SCARF ==================================
def silk_pattern(base, ring, dot):
    def col(p, n):
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
    pat = silk_pattern(base, ring, dot)
    yc = 0.462
    torus('wrap', 28, lambda phi: [eloop(yc + 0.004 * math.cos(phi), phi, h, v) for h, v in ((0.018, 0.034), (0.046, 0.026), (0.056, 0.0), (0.046, -0.026), (0.018, -0.034))], pat, sharp=60)
    # a fat knot at the front with two folded ends, and two flowing tails of fuller fabric
    kc, kn = body_pt(0.0, yc - 0.004, 0.082)
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
        thick_sheet(name, fn, nu, nv, 0.012, pat)
    tail(-0.030, -0.130, 0.440, 0.190, 0.060, 'tail_a', 0.074, 0.0)
    tail(0.030, 0.095, 0.440, 0.215, 0.054, 'tail_b', 0.078, 1.7)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly', 'sweet'], price=55, title='Silk scarf',
                desc='A silk neckerchief in navy printed with gold medallions: a thick rolled wrap round the belly at y~0.46, a fat knot with two folded ends at the front centre (top y 0.52, below the mouth keep-out) and two flowing tails of fuller fabric.')

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
    nlink = 13
    gcol = lambda p, n: mix(deep(gold, 0.25), tint(gold, 0.40), 0.35 + 0.65 * max(0, n[1] * 0.7 + 0.3))
    for k_ in range(nlink):
        d = L[-1] * (k_ + 0.5) / nlink
        i = min(int(np.searchsorted(L, d)), len(xy) - 2)
        x, y = xy[i]
        tx, ty = xy[i + 1] - xy[i]
        p, nn = body_pt(x, y, 0.044)
        xx, yy, z = axes(nn)
        tdir = xx * tx + yy * ty
        tdir /= np.linalg.norm(tdir)
        side = np.cross(z, tdir); side /= np.linalg.norm(side)
        if k_ % 2 == 0:
            bead('link%d' % k_, p, (0.046, 0.030, 0.013), gcol, rot=np.stack([tdir, z, side], 1), segs=8)
        else:
            bead('link%d' % k_, p, (0.046, 0.013, 0.030), gcol, rot=np.stack([tdir, z, side], 1), segs=8)
    p, nn = body_pt(0.0, 0.392, 0.058)
    xx, yy, z = axes(nn)
    Rm = np.stack([xx, z, -yy], 1).tolist()
    lathe_y('coin', [(0.0, -0.014), (0.070, -0.014), (0.080, -0.006), (0.080, 0.010), (0.070, 0.018), (0.0, 0.018)], 14, lambda q, nq: mix(deep(gold, 0.15), tint(gold, 0.32), 0.5 + 0.5 * nq[1]), centre=tuple(p), rotm=Rm, sharp=45)
    sp = star_poly(0.034, 0.016, 5, rad=0.005)
    slab_part('star', sp, 0.006, lambda q, nq: tint(gold, 0.35), lambda px, py, pz: tuple(p + xx * px + yy * py + z * (0.015 + pz)), cuts=0)
    bead('bail', p + yy * 0.086, (0.020, 0.020, 0.016), deep(gold, 0.1), segs=6)
    return dict(anchor='neck', slot='neck', tags=['cool', 'sparkly'], price=70, title='Gold chain',
                desc='A chunky gold curb chain in a swag from (+-0.34,0.52) down to a coin pendant at y~0.39: thirteen big alternating links. Lowest point on the centre line; nothing near the mouth keep-out.')

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

VARIANTS = [('vest_puffer_pip', vest_puffer, dict(pip=True), BIB_ANCHOR), ('cardigan_cable_pip', cardigan, dict(pip=True), BIB_ANCHOR)]
REG = [
    ('viking_hat', viking, dict(), H),
    ('beanie_cable', beanie_cable, dict(), H),
    ('visor_tennis', visor, dict(), H),
    ('vest_puffer', vest_puffer, dict(), BIB_ANCHOR),
    ('cardigan_cable', cardigan, dict(), BIB_ANCHOR),
    ('bag_crossbody', bag_crossbody, dict(), BIB_ANCHOR),
]
