"""Polish for two flat pieces that read thin in thumbnails: the small rug (a raised border, a woven field, diamonds, fringe) and the bouncy mat (a padded
frame with ties, a tufted jump surface that dips). Same ids, parts and pivots as the originals (`rug`: one part; `bouncymat`: `frame` + `top`)."""
from dk import *
from pieces_toys import clamp01, add_ring

def rrect(hx, hz, r, arc=6):
    pts = []
    for cx, cz, a0 in ((hx-r, hz-r, 0), (-(hx-r), hz-r, 90), (-(hx-r), -(hz-r), 180), (hx-r, -(hz-r), 270)):
        for k in range(arc+1):
            a = math.radians(a0 + 90*k/arc); pts.append((cx + r*math.cos(a), cz + r*math.sin(a)))
    return pts
FLAT = Matrix.Rotation(-math.pi/2, 4, 'X')          # a slab's thickness (+z) becomes +y (its outline y becomes -z)
def flat_slab(hx, hz, r, y0, th, color, cuts=0, bevel=0.012, c=(0, 0)):
    bm = lib.slab(rrect(hx, hz, r), 0.0, th, cuts=cuts)
    return commit(bm, color, mods=BEV(bevel, 2) if bevel else (), sharp=45, xf=Matrix.Translation((c[0], y0, c[1])) @ FLAT)

def rug():
    reset(); begin('rug')
    # outer pile border, a raised cream band, the woven field, diamonds, fringe
    flat_slab(0.86, 0.60, 0.16, 0.0, 0.050, lit(PINK, 0.22, 0.10), bevel=0.016)
    flat_slab(0.78, 0.52, 0.13, 0.0, 0.060, lit(CREAM, 0.15, 0.06), bevel=0.012)
    flat_slab(0.72, 0.46, 0.11, 0.0, 0.066, lit(SKY, 0.22, 0.08), bevel=0.01)
    def field(p, n):                # a soft woven weft: faint stripes across the field
        k = 0.5 + 0.5*math.sin(p.x*46.0)
        return mix(tint(SKY, 0.25), tint(MINT, 0.35), 0.25*k)
    flat_slab(0.62, 0.36, 0.09, 0.0, 0.071, field, cuts=2, bevel=0.008)
    for dx, col, r in ((-0.36, PINK, 0.13), (0.0, CREAM, 0.16), (0.36, PINK, 0.13)):
        d = [(0, r), (r*0.75, 0), (0, -r), (-r*0.75, 0)]
        poly = lib.poly_pts_rounded(d, 0.025, arc=3)
        commit(lib.slab(poly, 0.0, 0.012, cuts=0), lit(col, 0.2, 0.06), sharp=45, xf=Matrix.Translation((dx, 0.071, 0)) @ FLAT)
        add_sph((dx, 0.083, 0), (0.035, 0.012, 0.035), lit(HONEY if col == CREAM else CREAM, 0.2), sub=2)
    for k in range(10):             # stitched dots round the border
        t = (k + 0.5)/10
        for sgn in (-1, 1):
            add_sph((-0.72 + 1.44*t, 0.056, sgn*0.555), (0.022, 0.010, 0.022), lit(CREAM, 0.3), sub=1)
    for k in range(5):
        for sgn in (-1, 1): add_sph((sgn*0.82, 0.056, -0.40 + 0.20*k), (0.022, 0.010, 0.022), lit(CREAM, 0.3), sub=1)
    # fringe tassels on the two short ends (lying flat, pointing out)
    for sgn in (-1, 1):
        for k in range(13):
            z = -0.50 + 1.0*k/12
            add_tube([(sgn*0.84, 0.020, z), (sgn*0.90, 0.016, z + 0.004*(k % 3 - 1)), (sgn*0.945, 0.014, z + 0.01*(k % 3 - 1))], 0.013, lit(CREAM if k % 2 == 0 else tint(PINK, 0.4), 0.2), sides=5)
    return dict(footprint_half=[0.95, 0.67], height=0.075, spots=1, solid=False)

def bouncymat():
    reset(); begin('frame')
    path = [(0.78*math.copysign(abs(math.cos(a))**0.38, math.cos(a)), 0.07, 0.78*math.copysign(abs(math.sin(a))**0.38, math.sin(a))) for a in np.linspace(0, 2*math.pi, 96, endpoint=False)]
    add_tube(path, 0.068, lambda p, n: mix(deep(SKY, 0.10), tint(SKY, 0.30), 0.5 + 0.5*n.y), sides=14, cap=False, closed=True)
    # cream ties straddling the padded frame
    for k in range(16):
        a = 2*math.pi*(k + 0.5)/16
        x = 0.78*math.copysign(abs(math.cos(a))**0.38, math.cos(a)); z = 0.78*math.copysign(abs(math.sin(a))**0.38, math.sin(a))
        yaw = math.atan2(-z, x) if abs(x) > abs(z) else math.atan2(-z, x)
        horiz = abs(x) > abs(z)
        add_box((x, 0.075, z), (0.05, 0.145, 0.10) if horiz else (0.10, 0.145, 0.05), lit(CREAM, 0.15), bevel=0.012)
    # the spring skirt under the frame, and little feet
    flat_slab(0.78, 0.78, 0.30, 0.0, 0.035, lit(deep(SKY, 0.35), 0.0, 0.1), bevel=0.01)
    for sx in (-1, 1):
        for sz in (-1, 1): add_sph((sx*0.66, 0.046, sz*0.66), 0.045, lit(HONEY, 0.1), sub=1)
    begin('top', pivot=(0, 0.078, 0), w=lambda p: clamp01(1.0 - sstep(0.18, 0.80, max(abs(p.x), abs(p.z)))))
    flat_slab(0.76, 0.76, 0.30, 0.060, 0.034, lambda p, n: mix(tint(PINK, 0.0), tint(PINK, 0.28), 0.5 + 0.5*n.y*0.6), cuts=3, bevel=0.0)
    ring = lambda r, col, w: add_ring((0, 0.098, 0), r, w, lit(col, 0.25, 0.05), squash=0.4, segs=48, n=6)
    ring(0.50, CREAM, 0.022); ring(0.28, CREAM, 0.018)
    for ang in range(8):            # tufting buttons on a ring, plus the centre
        a = math.pi*ang/4 + math.pi/8
        add_sph((0.40*math.cos(a), 0.099, 0.40*math.sin(a)), (0.032, 0.013, 0.032), lit(HONEY, 0.25), sub=1)
    add_sph((0, 0.101, 0), (0.07, 0.016, 0.07), lit(HONEY, 0.3), sub=2)
    return dict(footprint_half=[0.88, 0.88], height=0.14, spots=2, solid=False)

REG = [('rug', rug), ('bouncymat', bouncymat)]
