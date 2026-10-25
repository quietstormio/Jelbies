from dk import *
from pieces_a import clamp01

def oriented_pill(centre, radii, color, basis, e=0.7, sub=2):
    """A pill whose local x / y / z axes follow `basis` (three world-space unit vectors)."""
    bm = pill_bm(radii[0], radii[1], radii[2], e, sub)
    Mrot = Matrix([basis[0], basis[1], basis[2]]).transposed().to_4x4()
    return commit(bm, color, sharp=80, xf=Matrix.Translation(centre) @ Mrot)

def star_pts(R, r=None, n=5, rad=0.008):
    r = r or R*0.46
    return lib.poly_pts_rounded([((R if i % 2 == 0 else r)*math.cos(math.pi/2+i*math.pi/n), (R if i % 2 == 0 else r)*math.sin(math.pi/2+i*math.pi/n)) for i in range(2*n)], rad, arc=2)

# ============================ BUBBLE MACHINE =================================
BM_DIR = Vector((0, 0.435, 0.9)).normalized()
BM_NOZZLE = Vector((0, 0.66, 0.29))
def bubblemachine():
    reset(); begin('body')
    add_box((0,0.20,0), (0.62,0.40,0.44), lit(SKY), bevel=0.05)
    add_box((0,0.405,0), (0.66,0.05,0.48), lit(HONEY, 0.2), bevel=0.02)
    add_box((0,0.045,0), (0.66,0.05,0.48), lit(HONEY, 0.1), bevel=0.02)
    add_cyl((0,0.60,0.10), 0.18, 0.38, lit(CREAM, 0.2), rot=(math.pi/2-0.45,0,0), centered=True, bevel=0.02)
    add_cyl((0,0.60,0.10), 0.185, 0.07, lit(PINK, 0.2), rot=(math.pi/2-0.45,0,0), centered=True, bevel=0.012)
    u = BM_DIR; ref = Vector((1,0,0)); v = u.cross(ref).normalized()
    ring = [BM_NOZZLE + (ref*math.cos(a) + v*math.sin(a))*0.19 for a in np.linspace(0, 2*math.pi, 28, endpoint=False)]
    add_tube(ring, 0.030, lit(PINK, 0.25), sides=8, cap=False, closed=True)
    add_lathe((-0.20,0.43,0.02), [(0,0),(0.07,0),(0.09,0.06),(0.07,0.18),(0.035,0.24),(0.04,0.27),(0,0.27)], lit(MINT, 0.3), segs=18)
    add_cyl((-0.20,0.70,0.02), 0.045, 0.045, lit(CORAL), bevel=0.01)
    add_sph((0.20,0.26,0.225), 0.045, lit(CORAL), sub=2)
    add_cyl((0.20,0.26,0.222), 0.062, 0.015, lit(CREAM), rot=(math.pi/2,0,0), centered=True, bevel=0.003)
    for (x, y) in ((-0.16,0.24),(-0.06,0.14),(0.04,0.30)):
        add_sph((x,y,0.222), (0.03,0.03,0.008), lit(CREAM), sub=1)
    for sx in (-1,1):
        for sz in (-1,1): add_sph((sx*0.26,0.01,sz*0.18), 0.04, lit(HONEY), sub=1)
    cc = BM_NOZZLE - BM_DIR*0.04
    begin('fan', pivot=tuple(cc))
    for k in range(6):
        a = 2*math.pi*k/6
        d = ref*math.cos(a) + v*math.sin(a)
        oriented_pill(cc + d*0.095, (0.085, 0.032, 0.008), lit(LAV if k % 2 else SKY, 0.25), [d, d.cross(u).normalized(), u], e=0.7)
    add_sph(cc, 0.04, lit(CORAL), sub=2)
    return dict(footprint_half=[0.38, 0.30], height=0.86, spots=1, solid=True,
                nozzle=[round(x,4) for x in BM_NOZZLE], nozzle_dir=[round(x,4) for x in BM_DIR])

# ============================ ROCKING HORSE ==================================
RH_R = 1.3
def rockinghorse():
    reset(); begin('horse')
    def runner(z):
        pts = [(x, 0.05 + RH_R - math.sqrt(RH_R**2 - x**2), z) for x in np.linspace(-0.72, 0.72, 15)]
        add_tube(pts, 0.05, lit(WOOD2), sides=8)
        add_sph(pts[0], 0.055, lit(WOOD2), sub=2); add_sph(pts[-1], 0.055, lit(WOOD2), sub=2)
    runner(0.20); runner(-0.20)
    for x, dx in ((0.38, 0.06), (-0.38, -0.06)):
        for z in (0.20, -0.20):
            y0 = 0.05 + RH_R - math.sqrt(RH_R**2 - x**2)
            add_tube([(x,y0,z),(x+dx*0.5,0.38,z*0.88),(x+dx,0.62,z*0.78)], 0.052, lit(CREAM, 0.2), sides=8, radfn=lambda t: 0.05-0.012*t)
    add_pill((0,0.78,0), (0.52,0.25,0.22), lambda p, n: mix(deep(CREAM,0.12), tint(CREAM,0.15), 0.5+0.5*n.y), e=0.75)
    add_pill((0,0.90,0), (0.24,0.07,0.20), lit(CORAL, 0.2), e=0.6)
    add_pill((-0.20,0.93,0), (0.07,0.07,0.20), lit(CORAL, 0.2), e=0.7)
    for s in (-1,1):
        add_tube([(0.0,0.86,s*0.20),(0.0,0.74,s*0.23),(0.02,0.62,s*0.22)], 0.012, lit(INK, 0.1), sides=5)
        add_pill((0.02,0.60,s*0.22), (0.045,0.012,0.03), lit(HONEY), e=0.7)
    add_tube([(0.36,0.84,0),(0.50,1.00,0),(0.58,1.13,0)], 0.14, lit(CREAM, 0.2), sides=10, radfn=lambda t: 0.17-0.05*t)
    add_pill((0.68,1.17,0), (0.19,0.14,0.13), lit(CREAM, 0.22), e=0.8, rot=(0,0,-0.25))
    add_pill((0.83,1.09,0), (0.10,0.085,0.10), lit(PINK, 0.35), e=0.8, rot=(0,0,-0.25))
    for s in (-1,1):
        add_sph((0.66,1.22,s*0.115), (0.036,0.042,0.02), lit(CREAM, 0.4), sub=1)
        add_sph((0.665,1.23,s*0.128), (0.022,0.03,0.012), lit(INK), sub=1)
        add_sph((0.90,1.12,s*0.04), (0.012,0.015,0.012), lit(deep(PINK,0.4)), sub=1)
        add_lathe((0.54,1.29,s*0.075), [(0,0),(0.05,0),(0.04,0.08),(0,0.15)], lit(CREAM, 0.2), segs=10, rot=(0,0,-0.2), sharp=70)
        add_lathe((0.545,1.285,s*0.075), [(0,0.01),(0.03,0.01),(0.022,0.07),(0,0.11)], lit(PINK, 0.3), segs=10, rot=(0,0,-0.2), sharp=70)
        add_tube([(0.74,1.17,s*0.11),(0.84,1.10,s*0.07),(0.88,1.07,s*0.04)], 0.012, lit(CORAL), sides=5)
        add_tube([(0.60,1.07,s*0.16),(0.66,0.97,s*0.20)], 0.018, lit(WOOD2), sides=5)
    for k in range(6):
        t = k/5; x = 0.40+0.16*t; y = 0.98+0.20*t
        add_sph((x-0.03,y,0.0), (0.075,0.075,0.07), lit(MINT, 0.25), sub=2)
    add_sph((0.58,1.32,0), (0.07,0.08,0.06), lit(MINT, 0.3), sub=2)
    begin('tail', pivot=(-0.50,0.88,0), w=lambda p: clamp01(math.hypot(p.x+0.50, p.y-0.88)/0.35))
    add_tube([(-0.50,0.88,0),(-0.62,0.90,0),(-0.72,0.80,0),(-0.76,0.64,0)], 0.06, lit(MINT, 0.2), sides=8, radfn=lambda t: 0.055*(1-0.55*t))
    add_sph((-0.76,0.58,0), (0.07,0.11,0.07), lit(MINT, 0.3), sub=2)
    return dict(footprint_half=[0.78, 0.30], height=1.40, spots=1, solid=True, rock_radius=RH_R)

# ============================ JACK-IN-THE-BOX ================================
JB_HEAD_Y = 1.06
def jackinbox():
    reset(); begin('box')
    add_box((0,0.23,0), (0.58,0.46,0.58), lit(SKY, 0.2), bevel=0.04)
    for y in (0.04, 0.42): add_box((0,y,0), (0.60,0.06,0.60), lit(HONEY, 0.2), bevel=0.02)
    add_slab(star_pts(0.16, 0.074, rad=0.01), 0.014, lit(HONEY, 0.3), T((0,0.23,0.292)), bevel=0.003)
    for (x, y, c) in ((-0.17,0.12,PINK),(0.17,0.12,MINT),(-0.17,0.34,MINT),(0.17,0.34,PINK)):
        add_sph((x,y,0.292), (0.032,0.032,0.01), lit(c, 0.3), sub=1)
    add_cyl((0.30,0.23,0), 0.04, 0.03, lit(HONEY), rot=(0,0,math.pi/2), centered=True, bevel=0.006)
    begin('crank', pivot=(0.32,0.23,0))
    add_tube([(0.32,0.23,0),(0.32,0.23,0.11)], 0.016, lit(CORAL), sides=6)
    add_sph((0.32,0.23,0.125), 0.036, lit(CORAL), sub=2)
    add_tube([(0.31,0.23,0.0),(0.34,0.23,0.0)], 0.02, lit(CORAL), sides=6)
    begin('lid', pivot=(0,0.46,-0.29))
    add_box((0,0.49,0), (0.60,0.05,0.60), lit(PINK, 0.2), bevel=0.02)
    add_box((0,0.525,0.18), (0.60,0.03,0.24), lit(HONEY, 0.2), bevel=0.012)
    begin('jester', pivot=(0,0.46,0))
    n = 36; pts = [(0.075*math.cos(t*2*math.pi*4.2), 0.46+0.52*t, 0.075*math.sin(t*2*math.pi*4.2)) for t in np.linspace(0,1,n)]
    add_tube(pts, 0.014, lit(hx('#C9D3DC'), 0.2), sides=6)
    HY = JB_HEAD_Y
    add_sph((0,HY,0.02), (0.17,0.17,0.16), lit(hx('#FBE3D0'), 0.2), sub=3)
    for s in (-1,1):
        add_sph((s*0.065,HY+0.03,0.165), (0.026,0.034,0.012), INK, sub=1)
        add_sph((s*0.065+0.008,HY+0.042,0.175), 0.008, WHITE, sub=1)
        add_sph((s*0.105,HY-0.03,0.14), (0.034,0.022,0.012), lit(PINK, 0.4), sub=1)
    add_sph((0,HY-0.01,0.18), (0.028,0.028,0.026), lit(CORAL), sub=2)
    add_tube([(-0.06,HY-0.07,0.158),(-0.03,HY-0.092,0.166),(0.03,HY-0.092,0.166),(0.06,HY-0.07,0.158)], 0.007, lit(deep(CORAL,0.3)), sides=5)
    add_lathe((0,HY+0.12,0.0), [(0.17,0),(0.17,0.03),(0.12,0.08),(0.05,0.17),(0,0.20)], lit(HONEY, 0.15), segs=18)
    for s, col in ((-1, CORAL), (1, SKY)):
        add_tube([(s*0.10,HY+0.20,0.0),(s*0.20,HY+0.26,0.0),(s*0.27,HY+0.22,0.0)], 0.04, lit(col, 0.2), sides=8, radfn=lambda t: 0.05-0.025*t)
        add_sph((s*0.28,HY+0.20,0.0), 0.04, lit(HONEY), sub=2)
    add_cyl((0,HY-0.12,0.0), 0.12, 0.04, lit(CREAM, 0.1), bevel=0.01)
    return dict(footprint_half=[0.31, 0.31], height=0.78, spots=1, solid=True, jester_head_y=HY, hinge=[0,0.46,-0.29])

# ============================ PLUSH BEAR =====================================
FUR = hx('#E3B27A')
def plushbear():
    reset(); begin('body', w=lambda p: clamp01(p.y/1.0))
    add_pill((0,0.36,0), (0.34,0.35,0.30), lambda p, n: mix(deep(FUR,0.15), tint(FUR,0.22), 0.5+0.5*n.y), e=0.8, sub=3)
    add_pill((0,0.34,0.20), (0.21,0.23,0.12), lit(CREAM, 0.1), e=0.8)
    for s in (-1,1):
        add_pill((s*0.36,0.46,0.10), (0.10,0.19,0.11), lit(FUR, 0.2), e=0.85, rot=(0,0,s*-0.35))
        add_pill((s*0.19,0.09,0.24), (0.15,0.12,0.20), lit(FUR, 0.2), e=0.8)
        add_sph((s*0.19,0.075,0.395), (0.085,0.07,0.012), lit(PINK, 0.35), sub=2)
    add_sph((0,0.30,0.315), (0.07,0.07,0.012), lit(PINK, 0.3), sub=2)
    begin('head', pivot=(0,0.68,0.02), w=lambda p: clamp01((p.y-0.62)/0.5))
    add_pill((0,0.88,0.03), (0.27,0.25,0.25), lambda p, n: mix(deep(FUR,0.15), tint(FUR,0.22), 0.5+0.5*n.y), e=0.85, sub=3)
    for s in (-1,1):
        add_sph((s*0.2,1.08,0.0), (0.095,0.095,0.06), lit(FUR, 0.2), sub=2)
        add_sph((s*0.2,1.08,0.04), (0.058,0.058,0.03), lit(PINK, 0.35), sub=2)
        add_sph((s*0.105,0.93,0.248), (0.034,0.04,0.016), INK, sub=2)
        add_sph((s*0.098,0.945,0.262), 0.010, WHITE, sub=1)
        add_sph((s*0.16,0.84,0.22), (0.045,0.03,0.014), lit(PINK, 0.4), sub=1)
        add_sph((s*0.085,0.64,0.215), (0.08,0.055,0.03), lit(CORAL, 0.2), rot=(0,0,s*-0.25), sub=2)
    add_pill((0,0.82,0.235), (0.13,0.10,0.09), lit(CREAM, 0.1), e=0.85)
    add_sph((0,0.855,0.315), (0.045,0.032,0.03), INK, sub=2)
    add_tube([(0,0.838,0.318),(0,0.80,0.322)], 0.007, INK, sides=4)
    add_tube([(-0.05,0.78,0.31),(-0.025,0.765,0.322),(0.025,0.765,0.322),(0.05,0.78,0.31)], 0.007, INK, sides=4)
    add_sph((0,0.64,0.23), 0.04, lit(deep(CORAL,0.2)), sub=2)
    return dict(footprint_half=[0.44, 0.40], height=1.18, spots=1, solid=True)

# ============================ TOY PIANO ======================================
PIANO_KEYS = 8
PIANO_BLACK = [0, 1, 3, 4, 5]
PIANO_KW = 0.115
def toypiano():
    reset(); begin('body')
    for sx in (-1,1):
        for sz in (-1,1):
            add_tube([(sx*0.44,0,sz*0.20),(sx*0.42,0.2,sz*0.19),(sx*0.40,0.42,sz*0.18)], 0.04, lit(WOOD2), sides=8, radfn=lambda t: 0.045-0.012*t)
    add_box((0,0.50,0), (1.06,0.20,0.54), lit(PINK, 0.2), bevel=0.04)
    add_box((0,0.615,-0.04), (1.08,0.03,0.58), lit(CREAM, 0.1), bevel=0.012)
    add_box((0,0.78,-0.22), (1.06,0.30,0.08), lit(PINK, 0.15), bevel=0.03)
    add_box((0,0.60,-0.21), (0.9,0.05,0.12), lit(deep(PINK,0.15)), bevel=0.01)
    for i, c in enumerate((HONEY, SKY, MINT)):
        add_sph((-0.32+0.32*i,0.80,-0.175), (0.045,0.045,0.014), lit(c, 0.3), sub=2)
    add_slab(star_pts(0.05, rad=0.004), 0.01, lit(HONEY, 0.3), T((0.0,0.92,-0.175)), bevel=0.002)
    add_sph((0.0,0.455,0.275), (0.30,0.02,0.01), lit(HONEY, 0.3), sub=1)
    kw = PIANO_KW; x0 = -kw*(PIANO_KEYS-1)/2
    for i in range(PIANO_KEYS):
        x = x0 + i*kw
        begin(f'key{i}', pivot=(x, 0.65, -0.12))
        add_box((x,0.65,0.07), (kw*0.93,0.04,0.40), lit(CREAM, 0.15, 0.06), bevel=0.01)
    for j, b in enumerate(PIANO_BLACK):
        x = x0 + (b+0.5)*kw
        begin(f'bkey{j}', pivot=(x, 0.70, -0.12))
        add_box((x,0.705,0.0), (kw*0.52,0.05,0.24), lit(INK, 0.25, 0.0), bevel=0.01)
    return dict(footprint_half=[0.56, 0.32], height=0.98, spots=1, solid=True, keys=PIANO_KEYS, black=PIANO_BLACK, key_pitch=kw)

# ============================ PINWHEEL =======================================
PW_HUB = (0.0, 1.12, 0.06)
def pinwheel():
    reset(); begin('base')
    add_lathe((0,0,0), [(0,0),(0.20,0),(0.26,0.04),(0.28,0.16),(0.25,0.27),(0.28,0.30),(0.24,0.30),(0,0.28)], lit(MINT, 0.25), segs=28)
    add_cyl((0,0.27,0), 0.23, 0.02, lit(hx('#6B4A33')), bevel=0)
    for k in range(7):
        a = 2*math.pi*k/7; add_sph((0.165*math.cos(a),0.31,0.165*math.sin(a)), (0.05,0.035,0.05), lit(LEAF, 0.2), sub=1)
    add_tube([(0,0.28,0),(0,0.7,0.02),(0,1.10,0.05)], 0.024, lit(WOOD), sides=8)
    add_sph((0,0.08,0.27), (0.03,0.03,0.01), lit(CORAL), sub=1)
    begin('wheel', pivot=PW_HUB)
    hub = Vector(PW_HUB)
    cols = [SKY, PINK, HONEY, MINT]
    for k in range(4):
        a = k*math.pi/2 + 0.2
        d = Vector((math.cos(a), math.sin(a), 0)); perp = Vector((-d.y, d.x, 0))
        tip = hub + d*0.40; side = hub + perp*0.30 + d*0.30
        bm = bmesh.new()
        vs = [bm.verts.new(hub), bm.verts.new(tip), bm.verts.new(side), bm.verts.new(hub + d*0.17 + perp*0.14 + Vector((0,0,0.075)))]
        bm.faces.new([vs[0], vs[1], vs[3]]); bm.faces.new([vs[1], vs[2], vs[3]]); bm.faces.new([vs[2], vs[0], vs[3]])
        bm.faces.new([vs[0], vs[2], vs[1]])
        commit(bm, lit(cols[k], 0.25), sharp=40)
        add_sph(tip, 0.016, lit(deep(cols[k],0.1)), sub=1)
    add_sph(hub + Vector((0,0,0.05)), (0.06,0.06,0.05), lit(HONEY, 0.3), sub=2)
    return dict(footprint_half=[0.30, 0.30], height=1.55, spots=1, solid=True, hub=list(PW_HUB))

REG = [('bubblemachine', bubblemachine), ('rockinghorse', rockinghorse), ('jackinbox', jackinbox), ('plushbear', plushbear), ('toypiano', toypiano), ('pinwheel', pinwheel)]
