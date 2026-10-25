from dk import *
def clamp01(x): return max(0.0, min(1.0, x))
def flower(c, col, centre=HONEY, r=0.05, rot=(0,0,0), n=6):
    R = Matrix.Rotation(rot[0],3,'X') @ Matrix.Rotation(rot[1],3,'Y')
    for k in range(n):
        a = 2*math.pi*k/n
        off = R @ Vector((math.cos(a)*r*0.95, math.sin(a)*r*0.95, 0))
        add_sph(Vector(c)+off, (r*0.62, r*0.62, r*0.30), lit(col, 0.25), rot=(0,0,0), sub=1)
    add_sph(Vector(c)+R@Vector((0,0,r*0.2)), (r*0.5, r*0.5, r*0.4), lit(centre, 0.2), sub=2)

# ============================ ROUND TABLE ====================================
def roundtable():
    reset(); begin('table')
    add_cyl((0,0.70,0), 0.64, 0.085, lit(WOOD, 0.22), bevel=0.03)
    add_cyl((0,0.61,0), 0.50, 0.10, lit(WOOD2), bevel=0.02)
    add_lathe((0,0,0), [(0,0),(0.40,0),(0.42,0.03),(0.38,0.07),(0.24,0.11),(0.12,0.17),(0.095,0.30),(0.095,0.50),(0.20,0.62),(0,0.62)], lit(WOOD2), segs=32)
    add_cyl((0,0.783,0), 0.36, 0.012, lit(CREAM, 0.1), bevel=0.004)
    add_cyl((0,0.795,0), 0.30, 0.008, lit(PINK, 0.3), bevel=0.003)
    begin('vase')
    add_lathe((0.0,0.795,0.0), [(0,0),(0.075,0),(0.115,0.07),(0.105,0.15),(0.062,0.20),(0.078,0.24),(0.062,0.24),(0,0.21)], lit(SKY), segs=20)
    add_lathe((0.0,0.795,0.0), [(0.102,0.06),(0.116,0.07),(0.108,0.12),(0.098,0.115)], lit(CREAM), segs=20)
    tops = [((-0.13,1.17,0.03), PINK), ((0.0,1.24,-0.02), CORAL), ((0.13,1.15,0.05), LAV)]
    for c, col in tops:
        add_tube([(0,1.02,0),(c[0]*0.5,1.07+0.5*(c[1]-1.02)*0.5,c[2]*0.5),(c[0],c[1]-0.03,c[2])], 0.011, lit(LEAF2), sides=5)
        flower(c, col, rot=(-0.5,0,0), r=0.062)
    add_sph((-0.07,1.07,0.04), (0.06,0.025,0.03), lit(LEAF), rot=(0,0,0.6), sub=1)
    add_sph((0.09,1.05,0.0), (0.06,0.025,0.03), lit(LEAF), rot=(0,0,-0.6), sub=1)
    return dict(footprint_half=[0.64, 0.64], height=1.30, spots=1, solid=True)

# ============================ CUSHION PILE ===================================
def cushionpile():
    reset(); begin('pile', w=lambda p: clamp01(p.y/0.62))
    cush = [((0,0.15,0), (0.60,0.15,0.52), 0.0, PINK), ((0.04,0.355,0.02), (0.50,0.14,0.46), 0.5, MINT), ((-0.03,0.54,-0.02), (0.42,0.13,0.40), -0.32, HONEY)]
    for c, r, ang, col in cush:
        add_pill(c, r, lit(col, 0.22, 0.10), e=0.55, rot=(0,ang,0), sub=3)
        add_sph((c[0], c[1]+r[1]*0.93, c[2]), (0.032,0.018,0.032), lit(CREAM), sub=2)
        # piping seam round the middle
        add_pill(c, (r[0]*1.012, 0.020, r[2]*1.012), lit(deep(col,0.12), 0.1), e=0.55, rot=(0,ang,0), sub=2)
    add_cyl((0.52,0.17,0.22), 0.17, 0.52, lit(CORAL, 0.2), rot=(math.pi/2,0,0), centered=True, bevel=0.03)
    for z in (-0.02, 0.46):
        add_cyl((0.52,0.17,z), 0.178, 0.045, lit(CREAM), rot=(math.pi/2,0,0), centered=True, bevel=0.008)
    add_pill((-0.5,0.14,0.34), (0.20,0.13,0.17), lit(LAV, 0.22), e=0.55, rot=(0,0.4,0))
    add_sph((-0.5,0.26,0.34), (0.026,0.014,0.026), lit(CREAM), sub=2)
    return dict(footprint_half=[0.72, 0.62], height=0.66, spots=1, solid=True, sit_points=[[0,0.60,0]])

# ============================ AQUARIUM =======================================
FISH = [((-0.22,1.02,0.04), HONEY, 1.0), ((0.12,0.86,-0.06), CORAL, 0.9), ((0.30,1.14,0.06), SKY, 0.8)]
def aquarium():
    reset(); begin('stand')
    add_box((0,0.25,0), (1.10,0.50,0.54), lit(WOOD2), bevel=0.035)
    add_box((0,0.515,0), (1.20,0.045,0.62), lit(WOOD, 0.22), bevel=0.02)
    for s in (-1,1):
        add_box((s*0.27,0.25,0.275), (0.47,0.38,0.02), lit(WOOD, 0.2), bevel=0.012)
        add_sph((s*0.07,0.25,0.30), 0.028, lit(HONEY), sub=2)
    begin('tank')
    add_box((0,0.60,0), (1.04,0.06,0.46), lit(SAND, 0.2), bevel=0.02)
    wc = lambda p, n: mix(deep(SKY, 0.0), tint(WATER, 0.55), sstep(0.62, 1.32, p.y))
    add_box((0,0.98,-0.22), (1.06,0.76,0.04), wc, bevel=0.01)
    for s in (-1,1): add_box((s*0.52,0.98,0.0), (0.04,0.76,0.48), lambda p, n: mix(tint(WATER,0.15), tint(WATER,0.7), sstep(0.62,1.32,p.y)), bevel=0.01)
    for sx in (-1,1):
        for sz in (-1,1): add_box((sx*0.55,0.98,sz*0.245), (0.055,0.80,0.055), lit(CREAM), bevel=0.015)
    add_box((0,1.375,-0.245), (1.16,0.05,0.06), lit(CREAM), bevel=0.015)
    add_box((0,1.375,0.245), (1.16,0.05,0.06), lit(CREAM), bevel=0.015)
    for s in (-1,1): add_box((s*0.55,1.375,0.0), (0.06,0.05,0.50), lit(CREAM), bevel=0.015)
    add_box((0,0.64,0.25), (1.16,0.045,0.05), lit(CREAM), bevel=0.015)
    # castle, rock
    add_box((0.30,0.75,-0.02), (0.22,0.18,0.15), lit(PINK, 0.25), bevel=0.02)
    for s in (-1,1):
        add_lathe((0.30+s*0.12,0.66,-0.02), [(0,0),(0.05,0),(0.05,0.28),(0.065,0.30),(0.0,0.40)], lit(CREAM), segs=12)
    add_box((0.30,0.70,0.06), (0.07,0.10,0.02), lit(INK), bevel=0.01)
    add_sph((-0.34,0.66,0.12), (0.12,0.075,0.10), lit(hx('#B9A3A8')), sub=2)
    add_sph((-0.20,0.65,0.18), (0.07,0.05,0.06), lit(hx('#C9B7B0')), sub=2)
    begin('plants', pivot=(0,0.62,0), w=lambda p: clamp01((p.y-0.64)/0.5))
    for k, (x, z, h, col) in enumerate([(-0.40,-0.10,0.62,LEAF), (-0.33,-0.02,0.50,LEAF2), (-0.46,0.04,0.44,LEAF), (0.43,0.10,0.5,LEAF2), (0.38,0.16,0.38,LEAF)]):
        pts = [(x+0.04*math.sin(t*3+k)*t*2, 0.63+h*t, z+0.02*math.cos(t*2+k)) for t in np.linspace(0,1,9)]
        add_tube(pts, 0.022, lit(col), sides=6, radfn=lambda t: 0.024*(1-0.7*t))
        for t in (0.35, 0.55, 0.75):
            q = pts[int(t*8)]
            add_sph((q[0]+0.045,q[1],q[2]), (0.06,0.025,0.03), lit(col, 0.25), rot=(0,0,0.5), sub=1)
            add_sph((q[0]-0.045,q[1]+0.03,q[2]), (0.06,0.025,0.03), lit(col, 0.25), rot=(0,0,-0.5), sub=1)
    for i, (c, col, sc) in enumerate(FISH):
        c = Vector(c)
        begin(f'fish{i}', pivot=c, w=(lambda cc: (lambda p: clamp01((cc.x - p.x - 0.06)/0.14)))(c))
        add_sph(c, (0.125*sc, 0.075*sc, 0.05*sc), lambda p, n, col=col: mix(deep(col,0.1), tint(col,0.35), 0.5+0.5*n.y), sub=2)
        add_sph(c + Vector((-0.135*sc, 0, 0)), (0.075*sc, 0.075*sc, 0.012), lit(deep(col,0.05)), rot=(0,0,0), sub=2)
        add_sph(c + Vector((-0.04*sc, 0.075*sc, 0)), (0.05*sc, 0.04*sc, 0.012), lit(deep(col,0.1)), sub=2)
        for sz in (-1,1):
            add_sph(c + Vector((0.07*sc, 0.018*sc, sz*0.040*sc)), 0.022*sc, lit(CREAM), sub=2)
            add_sph(c + Vector((0.078*sc, 0.018*sc, sz*0.054*sc)), 0.012*sc, lit(INK), sub=1)
    return dict(footprint_half=[0.62, 0.34], height=1.42, spots=2, solid=True, front_only=True)

# ============================ FERN STAND =====================================
def plantstand():
    reset(); begin('stand')
    for a in (math.pi/2, math.pi/2+2*math.pi/3, math.pi/2+4*math.pi/3):
        top = (0.19*math.cos(a), 0.82, 0.19*math.sin(a)); bot = (0.34*math.cos(a), 0.0, 0.34*math.sin(a))
        add_tube([bot, (top[0]*0.5+bot[0]*0.5, 0.41, top[2]*0.5+bot[2]*0.5), top], 0.036, lit(WOOD2), sides=8, radfn=lambda t: 0.034-0.008*t)
    add_cyl((0,0.80,0), 0.31, 0.05, lit(WOOD, 0.22), bevel=0.02)
    add_cyl((0,0.34,0), 0.22, 0.03, lit(WOOD), bevel=0.01)
    begin('pot')
    add_lathe((0,0,0), [(0,0.85),(0.16,0.85),(0.21,0.95),(0.245,1.06),(0.262,1.10),(0.262,1.14),(0.235,1.14),(0.235,1.13),(0,1.125)], lit(TERRA), segs=28)
    add_lathe((0,0,0), [(0.246,1.05),(0.268,1.065),(0.268,1.115),(0.250,1.115)], lit(tint(TERRA, 0.2)), segs=28)
    add_cyl((0,1.12,0), 0.235, 0.02, lit(hx('#6B4A33')), bevel=0)
    begin('leaves', pivot=(0,1.12,0), w=lambda p: clamp01((p.y-1.12)/0.5))
    nf = 9
    for k in range(nf):
        a = 2*math.pi*k/nf + 0.3; reach = 0.52 + 0.12*((k*7) % 3); h = 0.50 + 0.10*((k*5) % 3)
        pts = []
        for t in np.linspace(0, 1, 10):
            r = reach*t*(0.9); y = 1.13 + h*math.sin(math.pi*0.52*t)*(1 - 0.35*t) - 0.20*t*t
            pts.append((r*math.cos(a), y, r*math.sin(a)))
        add_tube(pts, 0.014, lit(LEAF2), sides=5, radfn=lambda t: 0.016*(1-0.6*t))
        for i in range(2, 10):
            q = Vector(pts[i]); t = i/9
            d = (Vector(pts[min(i+1,9)]) - Vector(pts[i-1])).normalized(); side = Vector((-math.sin(a), 0, math.cos(a)))
            L = 0.15*(1-0.55*t)
            for s in (-1,1):
                add_sph(q + side*s*L*0.8 + Vector((0,-0.02,0)), (L*0.55, 0.014, 0.032*(1-0.4*t)), lit(LEAF if (i+k)%2 else LEAF2, 0.22),
                        rot=(0, -a + (0.25*s), 0), sub=1)
    for k, a in enumerate((0.9, 3.7)):
        pts = [(0.25*math.cos(a), 1.06, 0.25*math.sin(a)), (0.31*math.cos(a), 0.95, 0.31*math.sin(a)), (0.33*math.cos(a)+0.04, 0.78, 0.33*math.sin(a)), (0.31*math.cos(a)+0.07, 0.60, 0.31*math.sin(a)+0.02)]
        add_tube(pts, 0.010, lit(LEAF2), sides=5)
        for q in pts[1:]: add_sph(q, (0.05,0.03,0.05), lit(LEAF, 0.2), sub=1)
    return dict(footprint_half=[0.33, 0.33], height=1.72, spots=1, solid=True)

# ============================ EASEL ==========================================
def easel():
    reset(); begin('easel')
    for s in (-1,1):
        add_tube([(s*0.36,0,0.36),(s*0.22,0.75,0.17),(s*0.07,1.52,0.0)], 0.036, lit(WOOD), sides=8)
    add_tube([(0,0,-0.46),(0,0.75,-0.22),(0,1.50,-0.02)], 0.036, lit(WOOD2), sides=8)
    add_box((0,0.30,0.26), (0.68,0.05,0.05), lit(WOOD2), bevel=0.012, rot=(0.0,0,0))
    add_box((0,0.46,0.205), (0.96,0.05,0.17), lit(WOOD, 0.2), bevel=0.015)
    add_box((0,1.53,-0.01), (0.32,0.06,0.06), lit(WOOD2), bevel=0.015)
    for i, (x, col) in enumerate(((-0.30, CORAL), (-0.18, SKY), (-0.06, HONEY), (0.06, MINT))):
        add_cyl((x,0.485,0.215), 0.042, 0.05, lit(CREAM), bevel=0.008)
        add_cyl((x,0.532,0.215), 0.034, 0.016, lit(col, 0.2), bevel=0.004)
    add_tube([(0.34,0.485,0.2),(0.43,0.50,0.22),(0.50,0.52,0.24)], 0.011, lit(WOOD2), sides=5)
    add_sph((0.52,0.525,0.245), (0.02,0.014,0.018), lit(CORAL), sub=2)
    begin('canvas', pivot=(0,1.42,0.03))
    M = T((0,0.98,0.075), rx=-0.13)
    def part(bm, color, local, rot=(0,0,0), mods=(), sharp=60):
        commit(bm, color, mods=mods, sharp=sharp, xf=M @ T(local, *rot))
    part(box_bm(0.82,0.94,0.03), lit(CREAM, 0.1), (0,0,0), mods=BEV(0.008,2), sharp=35)
    part(box_bm(0.74,0.86,0.012), lambda p, n: mix(tint(SKY,0.55), tint(SKY,0.82), sstep(-0.1,0.45,(p.y-0.98)*1.0)), (0,0,0.020), mods=BEV(0.004,2), sharp=35)
    part(pill_bm(0.46,0.14,0.02,0.6,2), lit(MINT, 0.2), (-0.14,-0.30,0.032))
    part(pill_bm(0.40,0.12,0.02,0.6,2), lit(LEAF, 0.2), (0.20,-0.33,0.040))
    part(sph_bm(0.11,0.11,0.02,2), lit(HONEY, 0.3), (0.20,0.28,0.034))
    for k in range(8):
        a = 2*math.pi*k/8; part(pill_bm(0.05,0.012,0.012,0.7,2), lit(HONEY), (0.20+0.16*math.cos(a), 0.28+0.16*math.sin(a), 0.032), rot=(0,0,a))
    part(pill_bm(0.15,0.06,0.02,0.6,2), lit(CREAM, 0.3), (-0.20,0.22,0.034))
    part(pill_bm(0.11,0.05,0.02,0.6,2), lit(CREAM, 0.3), (-0.08,0.28,0.034))
    part(sph_bm(0.115,0.12,0.04,2), lit(PINK, 0.25), (-0.18,-0.08,0.044))
    for s in (-1,1): part(sph_bm(0.014,0.018,0.01,2), INK, (-0.18+s*0.04,-0.05,0.080))
    part(pill_bm(0.03,0.012,0.008,0.7,2), deep(CORAL,0.3), (-0.18,-0.11,0.082))
    for x, col in ((0.12,CORAL),(0.24,LAV),(0.34,PINK)):
        part(tube_bm([(x,-0.22,0.03),(x,-0.12,0.03)], 0.008, 5), lit(LEAF2), (0,0,0))
        part(sph_bm(0.034,0.034,0.015,2), lit(col,0.25), (x,-0.10,0.040))
    return dict(footprint_half=[0.55, 0.48], height=1.56, spots=1, solid=True)

# ============================ STANDING MIRROR ================================
def mirror():
    reset(); begin('frame')
    rx, ry, cy = 0.36, 0.62, 1.02
    ring = [(rx*math.cos(a), cy+ry*math.sin(a), 0.0) for a in np.linspace(0, 2*math.pi, 40, endpoint=False)]
    add_tube(ring, 0.050, lit(HONEY, 0.22), sides=10, cap=False, closed=True)
    for s in (-1,1):
        add_tube([(s*0.30,0.52,-0.02),(s*0.27,0.30,-0.22),(s*0.24,0.0,-0.46)], 0.032, lit(WOOD2), sides=8)
        add_box((s*0.24,0.03,-0.05), (0.09,0.06,0.74), lit(WOOD2), bevel=0.02)
    add_tube([(-0.28,0.40,-0.06),(0.28,0.40,-0.06)], 0.026, lit(WOOD2), sides=8)
    add_sph((0,cy+ry+0.05,0), 0.055, lit(CORAL), sub=2)
    begin('glass')
    gl = lambda p, n: mix(tint(SKY,0.72), tint(SKY,0.9), 0.5+0.5*math.sin((p.x+p.y)*3.4))
    commit(lathe_bm([(0,0),(1,0),(1,0.03),(0,0.03)], 36, scale=(rx-0.02, ry-0.02)), gl, sharp=60, xf=T((0,cy,-0.012), rx=math.pi/2))
    for x, w, h in ((-0.12, 0.05, 0.62), (0.02, 0.025, 0.46)):
        add_box((x,cy+0.04,0.025), (w,h,0.006), tint(WHITE,0.0), bevel=0.0, rot=(0,0,-0.46))
    return dict(footprint_half=[0.40, 0.42], height=1.70, spots=1, solid=True, front_only=True)

# ============================ GRANDFATHER CLOCK ==============================
CLOCK_PIVOT = (0.0, 0.97, 0.205)
def clock():
    reset(); begin('case')
    add_box((0,0.10,0), (0.74,0.20,0.52), lit(WOOD2), bevel=0.03)
    add_box((0,0.575,0), (0.56,0.75,0.40), lit(WOOD), bevel=0.03)
    add_box((0,0.575,0.202), (0.42,0.66,0.012), lit(CREAM, 0.1), bevel=0.004)
    add_box((0,0.575,0.208), (0.36,0.58,0.012), lambda p, n: mix(hx('#3A2A1E'), hx('#6B4A33'), sstep(0.3,1.0,p.y)), bevel=0.004)
    add_box((0,1.215,0), (0.66,0.52,0.46), lit(WOOD2), bevel=0.03)
    add_pill((0,1.47,0), (0.33,0.16,0.23), lit(WOOD2), e=0.7)
    add_sph((0,1.66,0), 0.05, lit(HONEY), sub=2)
    for s in (-1,1): add_box((s*0.30,0.575,0.17), (0.04,0.70,0.08), lit(WOOD2, 0.1), bevel=0.012)
    begin('face')
    add_cyl((0,1.22,0.232), 0.235, 0.018, lit(HONEY, 0.15), rot=(math.pi/2,0,0), centered=True, bevel=0.004)
    add_cyl((0,1.22,0.243), 0.205, 0.016, lit(CREAM, 0.05), rot=(math.pi/2,0,0), centered=True, bevel=0.004)
    for k in range(12):
        a = 2*math.pi*k/12; r = 0.168
        add_sph((r*math.sin(a), 1.22+r*math.cos(a), 0.257), (0.016 if k%3 else 0.024,)*2+(0.008,), INK, sub=1)
    add_box((0.04,1.275,0.262), (0.028,0.12,0.008), INK, bevel=0.0, rot=(0,0,-0.5))
    add_box((-0.02,1.255,0.265), (0.020,0.17,0.008), INK, bevel=0.0, rot=(0,0,0.35))
    add_sph((0,1.22,0.268), 0.022, lit(HONEY), sub=1)
    begin('pendulum', pivot=CLOCK_PIVOT)
    add_tube([(0,0.97,0.22),(0,0.50,0.22)], 0.011, lit(HONEY), sides=6)
    add_cyl((0,0.46,0.224), 0.095, 0.03, lit(HONEY, 0.3, 0.05), rot=(math.pi/2,0,0), centered=True, bevel=0.01)
    add_sph((0,0.46,0.245), 0.030, lit(CORAL), sub=2)
    return dict(footprint_half=[0.38, 0.28], height=1.70, spots=1, solid=True, front_only=False)

REG = [('roundtable', roundtable), ('cushionpile', cushionpile), ('aquarium', aquarium), ('plantstand', plantstand), ('easel', easel), ('mirror', mirror), ('clock', clock)]
