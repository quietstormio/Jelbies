"""Batch-5 toys (2026-11-04, "toys are too baby"): hacky sack, frisbee, mini skateboard, basketball hoop. Game coordinates (y up, +z toward the camera)."""
from dk import *

def clamp01(x): return max(0.0, min(1.0, x))

def shell_wedge_bm(r, a0, a1, th0, th1, nph, nth, thick):
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
    for j in range(nph):
        for th in (th0, th1):
            face(vert(r,th,phs[j]), vert(ri,th,phs[j]), vert(ri,th,phs[j+1]), vert(r,th,phs[j+1]))
    for i in range(nth):
        for ph in (a0, a1):
            face(vert(r,ths[i],ph), vert(ri,ths[i],ph), vert(ri,ths[i+1],ph), vert(r,ths[i+1],ph))
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    return bm

def closed_lathe_bm(profile, segs=28):
    bm = lathe_bm(profile + [profile[0]], segs)
    bmesh.ops.remove_doubles(bm, verts=bm.verts[:], dist=1e-5)
    return bm

# ============================ HACKY SACK =====================================
HB_R = 0.17
def footbag():
    """A six-panel suede footbag (two-tone panels, stitched seams) rolling on the floor."""
    reset(); begin('ball', pivot=(0, HB_R, 0))
    cols = [CORAL, HONEY, SKY, HONEY, CORAL, MINT]
    n = len(cols)
    for i, c in enumerate(cols):
        a0 = 2*math.pi*i/n; a1 = 2*math.pi*(i+1)/n
        for (th0, th1, cc) in ((0.0, math.pi/2, c), (math.pi/2, math.pi, cols[(i+3) % n])):
            bm = shell_wedge_bm(HB_R, a0, a1, th0, th1, 5, 5, 0.02)
            commit(bm, lit(cc, 0.14, 0.10), sharp=80, xf=T((0, HB_R, 0)))
    return dict(footprint_half=[HB_R, HB_R], height=HB_R*2, spots=1, solid=False, roll_radius=HB_R)

# ============================ FRISBEE ========================================
FR_R = 0.34
def frisbee():
    """A flying disc: domed top, raised rim lip, a cream ring and a star mark. Pivot at its centre so it spins flat."""
    reset(); begin('disc', pivot=(0, 0.07, 0))
    prof = [(0.0, 0.10), (FR_R*0.35, 0.115), (FR_R*0.72, 0.105), (FR_R*0.90, 0.085), (FR_R, 0.06), (FR_R*1.0, 0.03),
            (FR_R*0.94, 0.012), (FR_R*0.80, 0.045), (FR_R*0.40, 0.055), (0.0, 0.06)]
    def col(p, n):
        r = math.hypot(p[0], p[2]) / FR_R
        base = CORAL
        if 0.62 < r < 0.70 or r > 0.93: base = CREAM
        return mix(deep(base, 0.10), tint(base, 0.18), 0.5 + 0.5*n.y*0.7)
    commit(lathe_bm(prof, 40), col, mods=BEV(0.008, 2), sharp=70, xf=T((0, 0, 0)))
    # a little star stamped in the middle
    pts = []
    for k in range(10):
        a = math.pi/2 + k*math.pi/5; rr = 0.085 if k % 2 == 0 else 0.037
        pts.append((rr*math.cos(a), rr*math.sin(a)))
    add_slab(pts, 0.012, lit(SKY, 0.2, 0.05), T((0, 0.107, 0), rx=-math.pi/2), bevel=0)
    return dict(footprint_half=[FR_R, FR_R], height=0.13, spots=1, solid=False, roll_radius=0.16)

# ============================ MINI SKATEBOARD ================================
SK_WR = 0.085
def skate_wheel(x, z, name):
    begin(name, pivot=(x, SK_WR, z))
    add_cyl((x + (0.03 if x > 0 else -0.03), SK_WR, z), SK_WR, 0.085, lit(CREAM, 0.15, 0.04), rot=(0, 0, math.pi/2), centered=True, bevel=0.012, segs=16)
    add_cyl((x + (0.075 if x > 0 else -0.075), SK_WR, z), SK_WR*0.45, 0.012, lit(CORAL, 0.2), rot=(0, 0, math.pi/2), centered=True, bevel=0, segs=10)
def skateboard():
    reset(); begin('deck')
    L, W = 0.54, 0.17          # half length (along z), half width
    DY = 0.20
    # a flat deck with upturned nose and tail (two tilted end plates) and grip tape on top
    add_box((0, DY, 0), (2*W, 0.035, 2*L - 0.22), lit(SKY, 0.22, 0.08), bevel=0.016)
    for s in (-1, 1):
        add_box((0, DY + 0.035, s*(L - 0.08)), (2*W, 0.035, 0.20), lit(SKY, 0.22, 0.08), bevel=0.016, rot=(-s*0.38, 0, 0))
    add_box((0, DY + 0.026, 0), (2*W - 0.03, 0.012, 2*L - 0.20), lit(INK, 0.18, 0.0), bevel=0.003)          # grip tape
    for s in (-1, 1):
        add_box((0, DY + 0.050, s*(L - 0.06)), (2*W - 0.03, 0.012, 0.15), lit(INK, 0.18, 0.0), bevel=0.003, rot=(-s*0.38, 0, 0))
    # two coral stripes under the nose and a star sticker
    for s in (-1, 1):
        add_box((0, DY - 0.020, s*0.20), (2*W - 0.02, 0.006, 0.05), lit(CORAL, 0.25, 0.05), bevel=0.001)
    # trucks and bolts
    for s in (-1, 1):
        z = s*0.30
        add_box((0, DY - 0.040, z), (0.20, 0.045, 0.085), lit(CREAM, 0.1, 0.18), bevel=0.012)
        add_cyl((0, SK_WR, z), 0.017, 2*W + 0.06, lit(CREAM, 0.1, 0.25), rot=(0, 0, math.pi/2), centered=True, bevel=0, segs=8)
    for sx in (-1, 1):
        for sz in (-1, 1):
            skate_wheel(sx*(W + 0.025), sz*0.30, 'wheel%d%d' % (sx > 0, sz > 0))
    # scale it up a little so it reads next to a Jelbie
    S = 1.25
    for g in GROUPS:
        g['pivot'] = tuple(x*S for x in g['pivot'])
        for p in g['parts']: p['P'] = [tuple(x*S for x in q) for q in p['P']]
    return dict(footprint_half=[0.30, 0.78], height=0.34, spots=1, solid=False, roll_radius=0.42)

# ============================ BASKETBALL HOOP ================================
def hoop():
    """A free-standing hoop: weighted base, pole, backboard and an orange rim with a swaying net (w = depth below the rim)."""
    reset(); begin('frame')
    BASE = hx('#5B6B7A')
    add_cyl((0, 0, -0.10), 0.34, 0.09, lit(BASE, 0.1, 0.12), bevel=0.03, segs=24)
    add_cyl((0, 0.09, -0.10), 0.07, 1.50, lit(hx('#D8DDE3'), 0.1, 0.08), bevel=0.008, segs=14)          # pole
    # backboard (white with a red-orange target square), padded frame
    BY = 1.52
    add_box((0, BY, -0.10), (0.88, 0.58, 0.05), lit(hx('#F4F6F8'), 0.1, 0.04), bevel=0.02)
    add_box((0, BY - 0.07, -0.072), (0.30, 0.22, 0.012), lit(hx('#E8573A'), 0.15, 0.05), bevel=0.003)
    add_box((0, BY - 0.07, -0.066), (0.26, 0.18, 0.012), lit(hx('#F4F6F8'), 0.1, 0.04), bevel=0.003)
    for s in (-1, 1): add_box((s*0.44, BY, -0.10), (0.04, 0.60, 0.06), lit(hx('#2F3E6B'), 0.15, 0.06), bevel=0.012)
    add_box((0, BY + 0.30, -0.10), (0.92, 0.04, 0.06), lit(hx('#2F3E6B'), 0.15, 0.06), bevel=0.012)
    add_box((0, BY - 0.30, -0.10), (0.92, 0.04, 0.06), lit(hx('#2F3E6B'), 0.15, 0.06), bevel=0.012)
    # rim: an orange ring standing out of the board toward the camera, joined by a bracket
    RZ, RR, RY = 0.20, 0.23, BY - 0.20
    n = 28
    pts = [(RR*math.cos(2*math.pi*i/n), RY, RZ + RR*math.sin(2*math.pi*i/n)) for i in range(n)]
    add_tube(pts, 0.021, lit(hx('#F26B21'), 0.2, 0.05), sides=6, cap=False, closed=True)
    add_box((0, RY, -0.02), (0.07, 0.03, 0.26), lit(hx('#F26B21'), 0.2, 0.05), bevel=0.008)
    # net: a lattice of cords hanging from the rim, narrowing toward the bottom (its own part so it sways)
    begin('net', pivot=(0, RY, RZ), w=lambda p: clamp01((RY - p.y) / 0.34))
    L = 12
    for i in range(L):
        a0 = 2*math.pi*i/L
        a1 = 2*math.pi*(i + 1.5)/L
        cord = [(RR*0.96*math.cos(a0), RY - 0.01, RZ + RR*0.96*math.sin(a0)),
                (RR*0.80*math.cos((a0 + a1)/2), RY - 0.17, RZ + RR*0.80*math.sin((a0 + a1)/2)),
                (RR*0.62*math.cos(a1), RY - 0.34, RZ + RR*0.62*math.sin(a1))]
        add_tube(cord, 0.0075, lit(CREAM, 0.2, 0.02), sides=4, cap=False)
        cord2 = [(RR*0.96*math.cos(a0), RY - 0.01, RZ + RR*0.96*math.sin(a0)),
                 (RR*0.80*math.cos((a0 + a1 - 4*math.pi/L)/2 - 0.0), RY - 0.17, RZ + RR*0.80*math.sin((a0 + a1 - 4*math.pi/L)/2)),
                 (RR*0.62*math.cos(a0 - 1.5*2*math.pi/L), RY - 0.34, RZ + RR*0.62*math.sin(a0 - 1.5*2*math.pi/L))]
        add_tube(cord2, 0.0075, lit(CREAM, 0.2, 0.02), sides=4, cap=False)
    add_ring_net = [(RR*0.80*math.cos(2*math.pi*i/20), RY - 0.17, RZ + RR*0.80*math.sin(2*math.pi*i/20)) for i in range(20)]
    add_tube(add_ring_net, 0.006, lit(CREAM, 0.2, 0.02), sides=4, cap=False, closed=True)
    # a ball resting in the base's tray: not separate; the game's own ball toys do that
    S = 1.12
    for g in GROUPS:
        g['pivot'] = tuple(x*S for x in g['pivot'])
        for p in g['parts']: p['P'] = [tuple(x*S for x in q) for q in p['P']]
    return dict(footprint_half=[0.45, 0.45], height=2.25, spots=1, solid=True)

REG = [('footbag', footbag), ('frisbee', frisbee), ('skateboard', skateboard), ('hoop', hoop)]
