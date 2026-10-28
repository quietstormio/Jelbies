"""Batch-4 toys: beach ball, play tunnel, ring stacker, toy rocket, plush dino, kick scooter. Game coordinates (y up, +z toward the camera)."""
from dk import *

def clamp01(x): return max(0.0, min(1.0, x))
def closed_lathe_bm(profile, segs=28):
    """A lathe whose profile closes back on its first point (a torus-like ring): weld the seam."""
    bm = lathe_bm(profile + [profile[0]], segs)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    return bm
def torus_profile(R, rt, squash=1.0, n=10):
    return [(R + rt*math.cos(2*math.pi*i/n), rt*squash*math.sin(2*math.pi*i/n)) for i in range(n)]
def add_ring(c, R, rt, color, squash=1.0, rot=(0,0,0), segs=28, n=10, G=None):
    xf = T(c, *rot) if G is None else G @ T(c, *rot)
    return commit(closed_lathe_bm(torus_profile(R, rt, squash, n), segs), color, sharp=80, xf=xf)

def shell_wedge_bm(r, a0, a1, th0, th1, nph, nth, thick, ring=False):
    """A closed patch of a sphere shell (outer radius r) between azimuth a0..a1 and polar angle th0..th1 (th from +y)."""
    bm = bmesh.new(); cache = {}
    def vert(rr, th, ph):
        p = (rr*math.sin(th)*math.cos(ph), rr*math.cos(th), rr*math.sin(th)*math.sin(ph))
        k = tuple(round(x, 5) for x in p)
        if k not in cache: cache[k] = bm.verts.new(p)
        return cache[k]
    def face(*vs):
        u = []
        for v in vs:
            if v not in u: u.append(v)
        if len(u) >= 3:
            try: bm.faces.new(u)
            except ValueError: pass
    ths = [th0 + (th1-th0)*i/nth for i in range(nth+1)]; phs = [a0 + (a1-a0)*j/nph for j in range(nph+1)]
    ri = r - thick
    for i in range(nth):
        for j in range(nph):
            face(vert(r,ths[i],phs[j]), vert(r,ths[i],phs[j+1]), vert(r,ths[i+1],phs[j+1]), vert(r,ths[i+1],phs[j]))
            face(vert(ri,ths[i],phs[j]), vert(ri,ths[i+1],phs[j]), vert(ri,ths[i+1],phs[j+1]), vert(ri,ths[i],phs[j+1]))
    for j in range(nph):          # top / bottom edge walls
        for th in (th0, th1):
            face(vert(r,th,phs[j]), vert(ri,th,phs[j]), vert(ri,th,phs[j+1]), vert(r,th,phs[j+1]))
    if not ring:
        for i in range(nth):
            for ph in (a0, a1):
                face(vert(r,ths[i],ph), vert(ri,ths[i],ph), vert(ri,ths[i+1],ph), vert(r,ths[i+1],ph))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    return bm

# ============================ BEACH BALL =====================================
BB_R = 0.34
def beachball():
    reset(); begin('ball', pivot=(0, BB_R, 0))
    cols = [CORAL, CREAM, SKY, CREAM, HONEY, CREAM, MINT, CREAM]
    cap = 0.34
    n = len(cols)
    for i, c in enumerate(cols):
        a0 = 2*math.pi*i/n; a1 = 2*math.pi*(i+1)/n
        bm = shell_wedge_bm(BB_R, a0, a1, cap, math.pi-cap, 6, 10, 0.03)
        commit(bm, lit(c, 0.16, 0.10), sharp=70, xf=T((0, BB_R, 0)))
    for th0, th1, col in ((0.0, cap, PINK), (math.pi-cap, math.pi, PINK)):
        bm = shell_wedge_bm(BB_R, 0, 2*math.pi, th0, th1, 18, 4, 0.03, ring=True)
        commit(bm, lit(col, 0.18, 0.08), sharp=70, xf=T((0, BB_R, 0)))
    # the inflation valve: a little cream stopper nub in the top cap, and a ring round it
    add_cyl((0, BB_R*2 - 0.012, 0), 0.050, 0.030, lit(HONEY, 0.2), bevel=0.01)
    add_ring((0, BB_R*2 - 0.004, 0), 0.062, 0.012, lit(CREAM, 0.2), segs=20, n=6)
    return dict(footprint_half=[BB_R, BB_R], height=BB_R*2, spots=1, solid=False, roll_radius=BB_R)

# ============================ PLAY TUNNEL ====================================
TUN_X = [-0.66, -0.40, -0.14, 0.14, 0.40, 0.66]
TUN_S = [0.84, 0.94, 1.0, 1.0, 0.94, 0.84]
TUN_C = [CORAL, HONEY, MINT, SKY, LAV, PINK]
def playtunnel():
    reset(); begin('tunnel', w=lambda p: clamp01(p.y/1.0))
    for i, (x, s) in enumerate(zip(TUN_X, TUN_S)):
        R = 0.5*s
        prof = [(R*0.62, -0.17), (R*0.82, -0.175), (R*0.97, -0.12), (R*1.0+0.03, 0.0), (R*0.97, 0.12), (R*0.82, 0.175), (R*0.62, 0.17)]
        commit(closed_lathe_bm(prof, 36), lit(TUN_C[i], 0.2, 0.10), sharp=70, xf=T((x, R, 0), rz=-math.pi/2))
    # wire hoops at both mouths, and stitching dots along the crown
    for x, R, col in ((-0.84, 0.42, CREAM), (0.84, 0.42, CREAM)):
        add_ring((x, R, 0), R*0.97, 0.028, lit(col, 0.2), rot=(0,0,-math.pi/2), segs=36, n=8)
    for x, R in zip(TUN_X, TUN_S):
        add_sph((x, 0.5*R*2.0*0.5*1.0 + 0.5*R*1.03 - 0.5*R + 0.0, 0.0), 0.0001, lit(CREAM)) if False else None
    # a floor mat of pegs: two sky stakes on each side
    for x in (-0.55, 0.55):
        for s in (-1, 1):
            add_cyl((x, 0.0, s*0.46), 0.045, 0.05, lit(SKY, 0.2), bevel=0.012)
    return dict(footprint_half=[0.86, 0.52], height=1.0, spots=2, solid=True)

# ============================ RING STACKER ===================================
RS_S = 0.86
RS_COL = [CORAL, HONEY, MINT, SKY, LAV, PINK]
def rs_ring_y(i): return (0.215 + 0.125*i)*RS_S
def ringstacker():
    reset(); begin('base')
    s = RS_S
    add_lathe((0,0,0), [(0,0),(0.40*s,0),(0.43*s,0.045*s),(0.40*s,0.12*s),(0.26*s,0.19*s),(0.11*s,0.23*s),(0,0.235*s)], lit(WOOD, 0.2), segs=36)
    add_ring((0, 0.058*s, 0), 0.405*s, 0.035*s, lit(HONEY, 0.2), segs=36, n=8)
    add_lathe((0,0.2*s,0), [(0,0),(0.075*s,0),(0.068*s,0.45*s),(0.058*s,0.72*s),(0.052*s,0.80*s),(0,0.80*s)], lit(WOOD2, 0.15), segs=20)
    add_sph((0, 1.02*s, 0), 0.095*s, lit(CORAL, 0.2), sub=2)
    for i in range(6):
        begin('ring%d' % i, pivot=(0, rs_ring_y(i), 0))
        Rm = (0.30 - 0.030*i)*s
        add_ring((0, rs_ring_y(i), 0), Rm, 0.066*s, lit(RS_COL[i], 0.22, 0.10), squash=0.92, segs=32, n=10)
    return dict(footprint_half=[0.38, 0.38], height=1.12*s, spots=1, solid=False)

# ============================ TOY ROCKET =====================================
RK_R = 1.3
RK_T = 0.5                        # tilt of the rocket's axis above horizontal (nose up, toward +x)
RK_C = Vector((0.0, 0.84, 0.0))   # centre of the body on its axis
def rk_G(): return T(RK_C, rz=-(math.pi/2 - RK_T))
def toyrocket():
    reset(); begin('rocket')
    G = rk_G()
    def runner(z):
        pts = [(x, 0.05 + RK_R - math.sqrt(RK_R**2 - x**2), z) for x in np.linspace(-0.66, 0.66, 15)]
        add_tube(pts, 0.05, lit(WOOD2), sides=8)
        add_sph(pts[0], 0.055, lit(WOOD2), sub=2); add_sph(pts[-1], 0.055, lit(WOOD2), sub=2)
    runner(0.22); runner(-0.22)
    # body (local y = along the rocket, nose at +y)
    body = [(0,-0.50),(0.12,-0.505),(0.21,-0.47),(0.255,-0.36),(0.268,-0.15),(0.268,0.12),(0.252,0.26),(0.205,0.38)]
    commit(lathe_bm(body + [(0.205,0.38),(0,0.38)], 36), lambda p, n: mix(deep(CREAM,0.10), tint(CREAM,0.2), 0.5+0.5*n.y*0.6), sharp=60, xf=G)
    nose = [(0.208,0.37),(0.19,0.45),(0.155,0.53),(0.105,0.60),(0.055,0.655),(0.012,0.68),(0,0.683)]
    commit(lathe_bm([(0,0.37)] + nose, 36), lit(CORAL, 0.2, 0.08), sharp=60, xf=G)
    add_ring((0,0.378,0), 0.208, 0.020, lit(HONEY, 0.2), rot=(0,0,0), segs=36, n=8, G=G)
    add_ring((0,-0.30,0), 0.270, 0.022, lit(SKY, 0.2), segs=36, n=8, G=G)
    add_ring((0,-0.19,0), 0.272, 0.016, lit(SKY, 0.2), segs=36, n=8, G=G)
    # tail nozzle
    commit(lathe_bm([(0.0,-0.47),(0.13,-0.47),(0.15,-0.53),(0.17,-0.60),(0.14,-0.62),(0.0,-0.60)], 28), lit(HONEY, 0.2), sharp=60, xf=G)
    # porthole on the camera side (+z)
    add_ring((0, 0.12, 0.262), 0.095, 0.022, lit(HONEY, 0.25), segs=28, n=8, G=G, rot=(math.pi/2,0,0))
    commit(sph_bm(0.088, 0.088, 0.03, 2), lit(SKY, 0.45, 0.0), sharp=90, xf=G @ T((0,0.12,0.262)))
    add_sph((0.0, 0.0, 0.0), 0.0001, lit(CREAM)) if False else None
    # fins (three round-edged paddles round the tail)
    for a, col in ((math.pi/2, CORAL), (math.pi/2 + 2*math.pi/3, SKY), (math.pi/2 - 2*math.pi/3, SKY)):
        d = Vector((math.cos(a), 0, math.sin(a))); tang = Vector((0,1,0)).cross(d).normalized()
        basis = [d, Vector((0,1,0)), tang]
        bm = pill_bm(0.15, 0.22, 0.035, 0.7, 2)
        Mrot = Matrix([basis[0], basis[1], basis[2]]).transposed().to_4x4()
        commit(bm, lit(col, 0.22, 0.10), sharp=80, xf=G @ Matrix.Translation(Vector((0,-0.31,0)) + d*0.30) @ Mrot @ Matrix.Rotation(0.0,4,'X'))
    # saddle seat on top (local -x is up), grip bar in front of it
    add_pill((-0.30, -0.12, 0), (0.10, 0.17, 0.15), lit(HONEY, 0.22), e=0.65, rot=(0,0,0), sub=2) if False else None
    commit(pill_bm(0.085, 0.17, 0.15, 0.65, 2), lit(HONEY, 0.22, 0.10), sharp=80, xf=G @ T((-0.285, -0.10, 0)))
    for z in (-1, 1):
        commit(tube_bm([(-0.22, 0.14, z*0.06), (-0.34, 0.20, z*0.14), (-0.38, 0.22, z*0.24)], 0.022, 6), lit(INK, 0.2, 0.0), sharp=70, xf=G)
        commit(cyl_bm(0.032, 0.11, 12, -0.055), lit(CORAL, 0.2), sharp=60, xf=G @ T((-0.385, 0.22, z*0.26), rx=math.pi/2))
    # struts from the runners up to the belly
    for z in (-0.22, 0.22):
        for x, up in ((-0.30, 0.0), (0.30, 0.0)):
            y0 = 0.05 + RK_R - math.sqrt(RK_R**2 - x**2)
            top = Vector(RK_C) + Vector((x*0.9, 0, 0)) + Vector((0, -0.22, z*0.55))
            add_tube([(x, y0, z), ((x+top.x)/2, (y0+top.y)/2, (z+top.z)/2 + 0.0), (top.x, top.y, top.z)], 0.04, lit(WOOD, 0.2), sides=8)
    # little rivets / star decal
    for k in range(3):
        add_sph((0, 0, 0), 0.0001, lit(CREAM)) if False else None
    begin('flame', pivot=tuple(RK_C + G.to_3x3() @ Vector((0, -0.62, 0))))
    for r, h, col in ((0.12, 0.42, CORAL), (0.075, 0.30, HONEY)):
        prof = [(0,0),(r,0),(r*0.8,-h*0.35),(r*0.4,-h*0.75),(0,-h)]
        commit(lathe_bm([(0,0.0)] + prof[1:], 20), lit(col, 0.25, 0.0), sharp=60, xf=G @ T((0, -0.62, 0)))
    return dict(footprint_half=[0.84, 0.30], height=1.36, spots=2, solid=True, rock_radius=RK_R)

# ============================ PLUSH DINO =====================================
def dino_skin(c): return lambda p, n: mix(deep(c,0.14), tint(c,0.20), 0.5+0.5*n.y*0.8)
def plushdino():
    G = LEAF; reset(); begin('body', w=lambda p: clamp01(p.y/1.0))
    add_pill((0, 0.50, 0), (0.42, 0.46, 0.38), dino_skin(G), e=0.72, sub=3)
    add_pill((0, 0.46, 0.22), (0.29, 0.34, 0.20), dino_skin(CREAM), e=0.7, sub=2)
    for k in range(3):          # belly stitch lines
        add_pill((0, 0.30 + 0.12*k, 0.405), (0.16, 0.012, 0.012), lit(deep(CREAM,0.25), 0.1), e=0.8, sub=1)
    for s in (-1, 1):           # stubby arms with a little paw
        add_pill((s*0.43, 0.56, 0.17), (0.11, 0.15, 0.11), dino_skin(G), e=0.75, rot=(0,0,-s*0.5), sub=2)
        add_sph((s*0.50, 0.44, 0.22), 0.065, lit(CREAM, 0.3), sub=1)
        add_pill((s*0.22, 0.10, 0.22), (0.17, 0.11, 0.21), dino_skin(G), e=0.7, sub=2)          # feet
        for t in (-1, 0, 1): add_sph((s*0.22 + t*0.09, 0.07, 0.42), (0.045,0.04,0.035), lit(CREAM, 0.3), sub=1)
    for k, (y, z, sz) in enumerate(((0.80, -0.30, 0.11), (0.60, -0.38, 0.13), (0.38, -0.40, 0.11))):          # back plates
        add_pill((0, y, z), (0.04, sz, sz*0.8), lit(CORAL if k % 2 == 0 else HONEY, 0.22), e=0.6, rot=(0.7 if k == 0 else (0.35 if k == 1 else 0.0),0,0), sub=2)
    begin('head', pivot=(0, 0.92, 0.0))
    add_pill((0, 1.02, 0.06), (0.35, 0.31, 0.32), dino_skin(G), e=0.78, sub=3)
    add_pill((0, 0.93, 0.32), (0.21, 0.145, 0.19), dino_skin(tint(G,0.12)), e=0.7, sub=2)
    for s in (-1, 1):
        add_sph((s*0.075, 0.97, 0.505), (0.022,0.014,0.012), lit(deep(G,0.5)), sub=1)          # nostrils
        add_sph((s*0.155, 1.09, 0.33), (0.058,0.07,0.035), lit(INK, 0.1, 0.0), sub=2)          # eyes
        add_sph((s*0.145, 1.115, 0.358), 0.018, lit(WHITE, 0.0, 0.0), sub=1)
        add_sph((s*0.235, 0.96, 0.27), (0.07,0.045,0.03), lit(PINK, 0.3), sub=2)               # cheeks
        add_pill((s*0.10, 1.31, 0.02), (0.045, 0.12, 0.045), lit(CORAL if s > 0 else HONEY, 0.22), e=0.6, rot=(0,0,-s*0.3), sub=2)     # head spikes
    add_tube([(-0.09,0.89,0.505),(-0.04,0.865,0.515),(0.04,0.865,0.515),(0.09,0.89,0.505)], 0.011, lit(INK, 0.1, 0.0), sides=5)
    add_pill((0, 1.31, -0.05), (0.04, 0.10, 0.045), lit(HONEY, 0.22), e=0.6, sub=2)
    begin('tail', pivot=(0, 0.33, -0.34), w=lambda p: clamp01(math.hypot(p.x, p.z+0.34)/0.7))
    ctrl = [Vector(q) for q in ((0, 0.36, -0.28), (0.02, 0.30, -0.50), (0.20, 0.25, -0.66), (0.46, 0.30, -0.64), (0.62, 0.44, -0.50))]
    def bez(t):                       # a smooth curve through the control points (Catmull-Rom style blend of de Casteljau on the polyline)
        pts = ctrl[:]
        while len(pts) > 1: pts = [pts[i]*(1-t) + pts[i+1]*t for i in range(len(pts)-1)]
        return pts[0]
    N = 14; pts = [tuple(bez(i/N)) for i in range(N+1)]
    rad = lambda t: 0.235*(1-t)**0.9 + 0.045
    add_tube(pts, 0.2, dino_skin(G), sides=14, radfn=rad, cap=False)
    add_sph(pts[-1], rad(1.0)*1.02, dino_skin(G), sub=2)          # a soft rounded tip
    for k, t in enumerate((0.12, 0.30, 0.48, 0.66, 0.82)):
        q = Vector(bez(t)); r = rad(t); sz = 0.12*(1-t)+0.045
        add_pill((q.x, q.y + r*0.95, q.z), (0.04, sz, 0.05), lit(CORAL if k % 2 == 0 else HONEY, 0.22), e=0.6, rot=(0.25, 0, 0), sub=2)
    return dict(footprint_half=[0.56, 0.52], height=1.42, spots=1, solid=True)

# ============================ KICK SCOOTER ===================================
SC_WR = 0.15
SC_TOP = (0.30, 1.02, 0.0)
SC_HUB = (0.50, SC_WR, 0.0)
def wheel(c, name, col=INK, hub=CREAM):
    begin(name, pivot=tuple(c))
    add_cyl((c[0], c[1], c[2]), SC_WR, 0.12, lit(col, 0.12, 0.0), rot=(math.pi/2,0,0), centered=True, bevel=0.025)
    add_cyl((c[0], c[1], c[2]), SC_WR*0.62, 0.135, lit(hub, 0.25), rot=(math.pi/2,0,0), centered=True, bevel=0.01)
    add_sph((c[0], c[1], c[2] + 0.07), (0.03, 0.03, 0.012), lit(CORAL), sub=1)
    add_sph((c[0], c[1], c[2] - 0.07), (0.03, 0.03, 0.012), lit(CORAL), sub=1)
def kickscooter():
    reset(); begin('frame')
    add_box((-0.08, 0.235, 0.0), (0.72, 0.075, 0.31), lit(PINK, 0.25, 0.10), bevel=0.025)
    add_box((-0.08, 0.277, 0.0), (0.58, 0.014, 0.25), lit(INK, 0.18, 0.0), bevel=0.004)          # grip tape
    for k in range(4): add_box((-0.26 + 0.12*k, 0.285, 0.0), (0.05, 0.007, 0.25), lit(HONEY, 0.25, 0.05), bevel=0.002)
    add_box((0.30, 0.235, 0.0), (0.14, 0.075, 0.24), lit(PINK, 0.25, 0.10), bevel=0.02)
    # rear fender over the back wheel
    add_box((-0.45, 0.34, 0.0), (0.26, 0.04, 0.21), lit(SKY, 0.25), bevel=0.012, rot=(0,0,0.0))
    # steering column (raked back) and the fork
    add_tube([(0.43, 0.20, 0.0), (0.38, 0.55, 0.0), SC_TOP], 0.05, lit(SKY, 0.25), sides=12)
    for z in (-0.075, 0.075): add_tube([SC_HUB[:2] + (z,), (0.45, 0.17, z), (0.43, 0.24, z*0.4)], 0.032, lit(SKY, 0.2), sides=8)
    add_box((-0.45, 0.17, 0.0), (0.10, 0.04, 0.17), lit(SKY, 0.2), bevel=0.012)
    for z in (-0.075, 0.075): add_tube([(-0.45, 0.17, z), (-0.45, SC_WR, z)], 0.03, lit(SKY, 0.2), sides=8)
    add_cyl((0.395, 0.30, 0.0), 0.07, 0.04, lit(CORAL, 0.2), bevel=0.01)          # steering head collar
    wheel((0.50, SC_WR, 0.0), 'wheelF'); wheel((-0.45, SC_WR, 0.0), 'wheelR')
    begin('bars', pivot=SC_TOP)
    add_tube([(SC_TOP[0], SC_TOP[1], -0.31), (SC_TOP[0]+0.015, SC_TOP[1]+0.0, -0.20), (SC_TOP[0]+0.015, SC_TOP[1], 0.20), (SC_TOP[0], SC_TOP[1], 0.31)], 0.04, lit(SKY, 0.25), sides=10)
    add_cyl((SC_TOP[0], SC_TOP[1]-0.03, 0.0), 0.058, 0.07, lit(CORAL, 0.2), bevel=0.012)
    for z in (-1, 1):
        add_cyl((SC_TOP[0], SC_TOP[1], z*0.27), 0.055, 0.20, lit(CORAL, 0.25), rot=(math.pi/2,0,0), centered=True, bevel=0.016)
        add_sph((SC_TOP[0], SC_TOP[1], z*0.38), 0.056, lit(CORAL, 0.25), sub=2)
        for k in range(3): add_tube([(SC_TOP[0], SC_TOP[1], z*0.37), (SC_TOP[0]+0.0, SC_TOP[1]-0.10-0.06*k, z*(0.40+0.015*k)), (SC_TOP[0]-0.02, SC_TOP[1]-0.22-0.07*k, z*(0.42+0.02*k))], 0.012, lit([HONEY, MINT, LAV][k], 0.3), sides=4)
    # bell
    add_lathe((SC_TOP[0]+0.02, SC_TOP[1]+0.02, 0.10), [(0,0),(0.06,0),(0.065,0.012),(0.05,0.045),(0.025,0.065),(0,0.07)], lit(HONEY, 0.3), segs=20)
    add_sph((SC_TOP[0]+0.02, SC_TOP[1]+0.095, 0.10), 0.014, lit(CREAM), sub=1)
    # chunkier and bigger: scale the whole model up (parts and pivots), so it reads next to a Jelbie
    S = 1.2
    for g in GROUPS:
        g['pivot'] = tuple(x*S for x in g['pivot'])
        for p in g['parts']: p['P'] = [tuple(x*S for x in q) for q in p['P']]
    return dict(footprint_half=[0.76, 0.52], height=1.36, spots=1, solid=True)

REG = [('beachball', beachball), ('playtunnel', playtunnel), ('ringstacker', ringstacker), ('toyrocket', toyrocket), ('plushdino', plushdino), ('kickscooter', kickscooter)]
