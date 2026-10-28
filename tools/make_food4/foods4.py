"""Store sweep 4 (food): the upgraded nuggets box and whole mini pizza, plus eight new foods.
Same conventions as foods.py: Blender units (x10 = game units), z up, front of the plate toward -y, bottom sits on z = 0, one piece per mesh.
Register in BUILD; run.py exports them (see make_food4/README in run4.sh)."""
import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
import foods
V = Vector
BUILD = {}

# ---------------------------------------------------------------- helpers
def blob(rx, ry, rz, sub=3):
    bm = ico(sub, 1.0)
    move(bm, lambda p: (p.x*rx, p.y*ry, p.z*rz))
    return bm

def sweep(path, rad, sides=8):
    """Closed tube along a polyline. rad: float or fn(t)->radius. Ends are tapered to a round cap."""
    n = len(path)
    pts = [V(p) for p in path]
    bm = bmesh.new(); rings = []
    prev_u = None
    for i, p in enumerate(pts):
        t = i/(n-1)
        d = (pts[min(i+1, n-1)] - pts[max(i-1, 0)]).normalized()
        a = V((0, 0, 1)) if abs(d.z) < 0.9 else V((1, 0, 0))
        u = d.cross(a).normalized(); v = d.cross(u).normalized()
        r = rad(t) if callable(rad) else rad
        if i == 0 or i == n-1: r *= 0.55
        rings.append([bm.verts.new(p + (u*math.cos(2*math.pi*k/sides) + v*math.sin(2*math.pi*k/sides))*r) for k in range(sides)])
    for i in range(n-1):
        for k in range(sides):
            j = (k+1) % sides
            bm.faces.new([rings[i][k], rings[i+1][k], rings[i+1][j], rings[i][j]])
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[-1])
    return bm

def rr_slab(w, d, z0, z1, rad, arc=4):
    return slab(poly_pts_rounded([(-w, -d), (w, -d), (w, d), (-w, d)], rad, arc), z0, z1, cuts=0)

def subdiv(bm, cuts=6):
    bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=cuts, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    return bm

def scale_all(s):
    for part in PARTS:
        part['P'] = [tuple(V(p)*s) for p in part['P']]

BEV = lambda w=0.04, seg=2, ang=40: [('BEVEL', dict(width=w, segments=seg, limit_method='ANGLE', angle_limit=math.radians(ang)))]
def bump_c(c, other, p, f=18.0, o=0, thr=0.2, amt=0.6):
    s = nz(p, f, o)
    return mix(c, other, sstep(thr, 1.0, s)*amt) if s > thr else c

# ================================================================ NUGGETS (box)
def nugget_lump(rx, ry, rz, seed):
    r = random.Random(seed); ph = [r.uniform(0, 6.28) for _ in range(3)]; off = seed*3.1
    bm = ico(3)
    def f(p):
        d = V(p).normalized(); a = math.atan2(d.y, d.x)
        rr = 1 + 0.14*math.sin(2*a+ph[0]) + 0.09*math.sin(3*a+ph[1]) + 0.05*math.sin(5*a+ph[2])
        return (d.x*rx*rr, d.y*ry*rr, d.z*rz*(0.92+0.1*nz(d, 1.3, off)))
    move(bm, f)
    displace(bm, lambda p, n: 0.03*nz(p, 6.0, off) + 0.035*(1-abs(nz(p, 12.0, off+3))) + 0.015*nz(p, 22.0, off+5))
    def col(p, n):
        top = (0.97, 0.72, 0.30); toast = (0.80, 0.44, 0.15); deep = (0.56, 0.28, 0.10)
        c = mix(top, toast, sstep(0.55, 0.0, n.z)*0.9)
        sp = nz(p, 14.0, off+9)
        if sp > 0.15: c = mix(c, (1.0, 0.86, 0.50), 0.6*(sp-0.15)/0.85)
        if sp < -0.15: c = mix(c, deep, 0.85*(-sp-0.15)/0.85)
        return c
    return bm, col

def nuggets4(v=0):
    # the box: a red-and-white striped paper tray, open top, nuggets heaped in it
    W0, W1, D0, D1, H = 0.50, 0.60, 0.34, 0.44, 0.50
    pts = [(-W0, -D0, 0), (W0, -D0, 0), (W0, D0, 0), (-W0, D0, 0), (-W1, -D1, H), (W1, -D1, H), (W1, D1, H), (-W1, D1, H)]
    bm = bmesh.new(); vs = [bm.verts.new(p) for p in pts]
    for q in [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4), (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]: bm.faces.new([vs[i] for i in q])
    subdiv(bm, 10)
    red = (0.88, 0.20, 0.22); cream = (1.0, 0.96, 0.88)
    def bc(p, n):
        if n.z > 0.6: return (0.62, 0.12, 0.15)                 # the inside, deep red
        if p.z > H-0.045: return cream                          # rolled cream rim
        k = math.floor((p.x+0.8)/0.20) % 2 if abs(n.y) > 0.5 else math.floor((p.y+0.8)/0.20) % 2
        return red if k == 0 else cream
    commit(bm, bc, mods=[], sharp=45)
    # nuggets: back row of three, front two, one on top (all different lumps)
    spec = [(-0.36, 0.10, 0.50, 0.2, (0.27, 0.23, 0.22)), (0.04, 0.16, 0.54, -0.4, (0.29, 0.24, 0.23)), (0.38, 0.08, 0.48, 0.9, (0.26, 0.22, 0.21)),
            (-0.20, -0.16, 0.58, 0.5, (0.28, 0.24, 0.22)), (0.22, -0.14, 0.60, -0.2, (0.27, 0.25, 0.23)), (0.02, 0.0, 0.80, 0.7, (0.25, 0.22, 0.2))]
    for k, (x, y, z, rot, (a, b, c)) in enumerate(spec):
        bm, col = nugget_lump(a, b, c, 60+k)
        commit(bm, col, mods=[('DECIMATE', dict(ratio=0.55))], sharp=75, xf=xf_rt((x, y, z), rotz=rot, rotx=0.1*math.sin(k), roty=0.12*math.cos(k)))
    # a little ketchup dab on the front-most nugget
    bm = blob(0.09, 0.07, 0.035, 2)
    commit(bm, (0.85, 0.15, 0.15), sharp=80, xf=xf_rt((0.22, -0.30, 0.86)))
BUILD['nuggets'] = nuggets4

# ================================================================ MINI PIZZA (slice, more toppings) + whole pie
def pizza_extras(hl, hw):
    # slice toppings on top of foods.pizza: olive rings and a mushroom slice
    for (x, y) in [(0.06, 0.82), (-0.22, -0.05), (0.26, 0.2)]:
        bm = lathe([(0.0, 0.0), (0.2, 0.0), (0.2, 0.07), (0.11, 0.07)], 12)
        commit(bm, lambda p, n: (0.14, 0.12, 0.13) if n.z > 0.3 else (0.25, 0.22, 0.2), sharp=70, xf=xf_rt((x, y, 0.272)))
    for (x, y, a) in [(0.12, 0.2, 0.4), (-0.18, 0.5, -0.5)]:
        bm = blob(0.17, 0.12, 0.05, 2)
        commit(bm, lambda p, n: (0.93, 0.85, 0.72) if n.z > 0 else (0.7, 0.58, 0.45), sharp=80, xf=xf_rt((x, y, 0.28), rotz=a))

def pizza4(v=0):
    foods.pizza(v)
    pizza_extras(1.3, 0.8)
BUILD['minipizza'] = pizza4

def pizza_whole(v=0):
    R = 2.6
    segs = 40
    # dough disc
    prof = [(0, 0), (R-0.08, 0), (R, 0.06), (R, 0.2), (R-0.1, 0.24), (0, 0.24)]
    bm = lathe(prof, segs)
    commit(bm, lambda p, n: mix((0.93, 0.74, 0.44), (0.80, 0.52, 0.25), sstep(0.1, 0.0, p.z)*0.6), sharp=60)
    # crust: a fat ring with soft bubbles
    n = 56; R0 = R-0.20; big = 0.24
    bm = bmesh.new(); rings = []
    for i in range(n):
        a = 2*math.pi*i/n
        rr = big*(1+0.10*math.sin(i*1.9)+0.06*math.sin(i*4.3))
        ring = []
        for k in range(10):
            b = 2*math.pi*k/10
            ring.append(bm.verts.new(((R0+rr*math.cos(b)*1.05)*math.cos(a), (R0+rr*math.cos(b)*1.05)*math.sin(a), 0.2+rr*math.sin(b)*0.95)))
        rings.append(ring)
    for i in range(n):
        j = (i+1) % n
        for k in range(10):
            m = (k+1) % 10
            bm.faces.new([rings[i][k], rings[j][k], rings[j][m], rings[i][m]])
    def cc(p, n_):
        c = mix((0.90, 0.60, 0.28), (0.97, 0.76, 0.42), sstep(0.2, 0.9, n_.z)*0.85)
        return bump_c(c, (0.62, 0.34, 0.16), p, 10.0, 4, 0.3, 0.5)
    commit(bm, cc, sharp=70)
    # cheese: bumpy bubbly disc, sauce peeks at the rim
    bm = lathe([(0, 0.2), (R-0.42, 0.2), (R-0.30, 0.26), (R-0.38, 0.30), (0, 0.32)], segs)
    displace(bm, lambda p, n: (0.03*nz(p, 4.0, 2) + 0.015*nz(p, 9.0, 5)) if n.z > 0.5 else None)
    def chc(p, n):
        d = math.hypot(p.x, p.y)
        c = (1.0, 0.86, 0.42); s = nz(p, 5.0, 1)
        c = mix(c, (1.0, 0.72, 0.28), sstep(0.15, 0.7, s)*0.7); c = mix(c, (1.0, 0.94, 0.66), sstep(0.2, 0.7, -s)*0.5)
        return mix(c, (0.90, 0.30, 0.18), sstep(R-0.62, R-0.38, d)*0.8)          # tomato sauce rim
    commit(bm, chc, sharp=60)
    r = random.Random(11)
    # pepperoni
    spots = []
    for ring_r, cnt, off in [(1.75, 8, 0.2), (0.85, 5, 0.9)]:
        for i in range(cnt):
            a = off + 2*math.pi*i/cnt
            spots.append((ring_r*math.cos(a), ring_r*math.sin(a), 0.30 if ring_r > 1.2 else 0.27))
    spots.append((0.0, 0.0, 0.27))
    for k, (x, y, rr) in enumerate(spots):
        pr = [(0, 0.0), (rr, 0.0), (rr+0.03, 0.03), (rr+0.01, 0.07), (rr*0.55, 0.08), (0, 0.065)]
        pr = [(0, 0.0), (0.27, 0.0), (0.30, 0.03), (0.28, 0.075), (0.15, 0.085), (0, 0.07)]
        bm = lathe(pr, 14)
        def pc(p, n, x=x, y=y):
            d = math.hypot(p.x-x, p.y-y)
            c = (0.80, 0.22, 0.17); c = mix(c, (0.60, 0.13, 0.11), sstep(0.2, 0.3, d))
            return mix(c, (0.95, 0.62, 0.45), 0.5) if nz(p, 14.0, 3) > 0.45 else c
        commit(bm, pc, sharp=70, xf=xf_rt((x, y, 0.27 if k < 8 else 0.255), rotz=k*1.3))
    # mushrooms, olives, basil
    for k in range(7):
        a = 0.5 + k*0.9; rd = 1.2 + 0.6*math.sin(k*2.0)
        bm = blob(0.2, 0.13, 0.05, 2)
        commit(bm, lambda p, n: (0.94, 0.86, 0.73) if n.z > 0 else (0.72, 0.6, 0.47), sharp=80, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), 0.33), rotz=a*2))
    for k in range(9):
        a = 0.2 + k*0.7; rd = 0.6 + 1.5*((k*0.37) % 1.0)
        bm = lathe([(0.0, 0.0), (0.12, 0.0), (0.12, 0.07), (0.06, 0.07)], 10)
        commit(bm, lambda p, n: (0.13, 0.11, 0.12) if n.z > 0.3 else (0.23, 0.2, 0.19), sharp=70, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), 0.31)))
    for k in range(7):
        a = 0.9 + k*0.95; rd = 0.5 + 1.7*((k*0.53) % 1.0)
        bm = blob(0.17, 0.09, 0.025, 2)
        commit(bm, (0.36, 0.68, 0.28), sharp=80, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), 0.34), rotz=a*3))
BUILD['minipizza_whole'] = pizza_whole

# ================================================================ CHEESEBURGER
def cheeseburger(v=0):
    R = 0.66
    z = 0.0
    # bottom bun
    prof = [(0, 0), (R-0.14, 0), (R-0.04, 0.05), (R, 0.14), (R, 0.22), (R-0.06, 0.27), (0, 0.28)]
    commit(lathe(prof, 32), lambda p, n: mix((0.96, 0.72, 0.36), (0.86, 0.58, 0.26), sstep(0.2, 0.0, p.z)*0.7), sharp=60)
    z = 0.26
    # patty
    prof = [(0, z), (R+0.05, z), (R+0.10, z+0.05), (R+0.10, z+0.17), (R+0.05, z+0.22), (0, z+0.23)]
    bm = lathe(prof, 32); displace(bm, lambda p, n: 0.014*nz(p, 9.0, 3) if abs(n.z) < 0.9 else 0.01*nz(p, 14.0, 3))
    commit(bm, lambda p, n: bump_c((0.50, 0.28, 0.17), (0.34, 0.17, 0.10), p, 12.0, 2, 0.0, 0.8), sharp=60)
    z = 0.46
    # lettuce: a frilly disc
    bm = lathe([(0, z), (R+0.02, z), (R+0.10, z+0.04), (R+0.12, z+0.10), (R+0.06, z+0.15), (0, z+0.14)], 48)
    move(bm, lambda p: (p.x, p.y, p.z + 0.045*math.sin(math.atan2(p.y, p.x)*9)*max(0, math.hypot(p.x, p.y)-0.35)))
    commit(bm, lambda p, n: mix((0.52, 0.80, 0.34), (0.74, 0.92, 0.46), sstep(0.5, 1.0, math.sin(math.atan2(p.y, p.x)*9)*0.5+0.5)*0.7), sharp=70)
    # tomato
    z = 0.60
    commit(lathe([(0, z), (R-0.02, z), (R, z+0.04), (R-0.02, z+0.10), (0, z+0.10)], 32), lambda p, n: mix((0.90, 0.22, 0.20), (0.97, 0.45, 0.35), sstep(0.4, 1.0, nz(p, 5.0, 1)*0.5+0.5)*0.4), sharp=60)
    # cheese: a square rotated 45 deg with drooping corners
    z = 0.70
    sq = rr_slab(0.74, 0.74, z, z+0.04, 0.26)
    def droop(p):
        c = abs(p.x)+abs(p.y)
        d = max(0.0, c-0.95)
        return (p.x, p.y, p.z - 0.9*d)
    # subdivide so the corners can sag
    bmesh.ops.subdivide_edges(sq, edges=sq.edges[:], cuts=3, use_grid_fill=True); bmesh.ops.triangulate(sq, faces=sq.faces[:])
    move(sq, droop)
    commit(sq, lambda p, n: mix((1.0, 0.78, 0.16), (1.0, 0.88, 0.40), sstep(0.3, 1.0, n.z)*0.5), sharp=70, xf=xf_rt((0, 0, 0), rotz=math.radians(45)))
    # top bun (dome) with sesame
    z = 0.72
    prof = [(0, z), (R-0.04, z), (R+0.02, z+0.06)]
    for k in range(1, 9):
        a = k/8*math.pi/2
        prof.append(((R+0.02)*math.cos(a), z+0.06+0.56*math.sin(a)))
    bm = lathe(prof, 36)
    commit(bm, lambda p, n: mix((0.94, 0.66, 0.30), (0.98, 0.78, 0.42), sstep(0.2, 0.9, n.z)*0.8) if p.z > z+0.1 else (0.88, 0.60, 0.28), sharp=60)
    r = random.Random(9)
    for k in range(18):
        a = r.uniform(0, 6.28); rd = 0.52*math.sqrt(r.uniform(0.05, 1.0))
        zz = z+0.06+0.56*math.sqrt(max(0.0, 1-(rd/(R+0.02))**2))
        bm = blob(0.05, 0.026, 0.018, 1)
        commit(bm, (1.0, 0.95, 0.80), sharp=80, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), zz-0.004), rotz=a))
    # ketchup/mustard peek: a little yellow drip over the front of the patty
    bm = blob(0.13, 0.06, 0.04, 2)
    commit(bm, (0.95, 0.80, 0.18), sharp=80, xf=xf_rt((0.28, -R-0.04, 0.42)))
    scale_all(0.74)
BUILD['cheeseburger'] = cheeseburger

# ================================================================ RAMEN
def ramen(v=0):
    R = 0.78
    # bowl: a closed solid profile (outside, rim, inside)
    prof = [(0, 0), (0.30, 0), (0.42, 0.02), (0.62, 0.20), (R-0.02, 0.50), (R, 0.62), (R-0.07, 0.66), (R-0.14, 0.64), (R-0.16, 0.5), (0.52, 0.22), (0, 0.16)]
    bm = lathe(prof, 40)
    def bc(p, n):
        if n.z > 0.2 and p.z > 0.2 and math.hypot(p.x, p.y) < R-0.1: return (0.97, 0.94, 0.88)          # inside cream
        if 0.30 < p.z < 0.46 and n.z < 0.5:                                                            # a red band with a pale wave stripe
            return (0.80, 0.16, 0.18) if 0.34 < p.z < 0.42 else (0.97, 0.94, 0.88)
        if p.z > 0.58: return (0.80, 0.16, 0.18)                                                       # red rim
        return (0.96, 0.92, 0.84)
    commit(bm, bc, sharp=60)
    # broth
    zb = 0.50
    bm = lathe([(0, zb), (R-0.14, zb), (R-0.14, zb+0.01), (0, zb+0.01)], 40)
    commit(bm, lambda p, n: mix((0.82, 0.55, 0.24), (0.9, 0.66, 0.30), sstep(0.2, 0.9, nz(p, 4.0, 2)*0.5+0.5)), sharp=70)
    # noodles: curly loops heaped in the middle
    r = random.Random(5)
    for k in range(9):
        a0 = r.uniform(0, 6.28); cx = r.uniform(-0.22, 0.22); cy = r.uniform(-0.22, 0.22); rad = r.uniform(0.18, 0.34)
        path = []
        for i in range(25):
            t = i/24
            a = a0 + t*r.choice([3.4, 4.2, 5.0])
            path.append((cx + rad*math.cos(a)*(0.6+0.5*t), cy + rad*math.sin(a)*(0.6+0.5*t), zb + 0.04 + 0.10*t + 0.05*math.sin(a*2) + 0.02*k))
        bm = sweep(path, 0.030, 6)
        commit(bm, lambda p, n: mix((1.0, 0.86, 0.45), (0.96, 0.74, 0.30), sstep(-0.3, 0.8, nz(p, 6.0, 1))*0.8), sharp=70)
    # toppings: soft egg half, naruto swirl, chashu, nori, green onion
    # egg half (white ellipsoid cut-ish with yolk)
    bm = blob(0.24, 0.17, 0.15, 3)
    commit(bm, lambda p, n: (0.99, 0.97, 0.92), sharp=80, xf=xf_rt((0.38, -0.20, zb+0.10), rotz=0.5))
    bm = blob(0.115, 0.085, 0.075, 3)
    commit(bm, (1.0, 0.66, 0.12), sharp=80, xf=xf_rt((0.38, -0.20, zb+0.20), rotz=0.5))
    # chashu slice
    bm = slab(poly_pts_rounded([(-0.26, -0.18), (0.26, -0.18), (0.26, 0.18), (-0.26, 0.18)], 0.10, 4), 0, 0.045, cuts=0)
    commit(bm, lambda p, n: mix((0.88, 0.66, 0.52), (0.62, 0.38, 0.26), sstep(0.3, 0.9, abs(p.x-(-0.30))*1.0)*0.0 + (0.8 if (n.z < 0.5) else 0.0)) , mods=BEV(0.02, 1), sharp=60,
           xf=xf_rt((-0.34, 0.14, zb+0.10), rotz=0.35, roty=0.12))
    # narutomaki: white disc with a pink swirl
    pr = [(0, 0), (0.17, 0), (0.18, 0.04), (0.17, 0.08), (0, 0.085)]
    bm = lathe(pr, 20)
    def nc(p, n):
        d = math.hypot(p.x-0.0, p.y-0.0); a = math.atan2(p.y, p.x)
        sw = math.sin(a*1.0 + d*26) 
        return (0.96, 0.52, 0.62) if (n.z > 0.5 and sw > 0.35 and d < 0.15) else (0.99, 0.97, 0.93)
    commit(bm, nc, sharp=70, xf=xf_rt((-0.05, -0.38, zb+0.05), rotx=0.35))
    # nori sheet standing at the back
    bm = slab(poly_pts_rounded([(-0.20, 0), (0.20, 0), (0.20, 0.42), (-0.20, 0.42)], 0.04, 3), 0, 0.03, cuts=0)
    commit(bm, lambda p, n: (0.10, 0.17, 0.14), sharp=60, xf=xf_rt((0.0, 0.38, zb+0.0), rotx=math.radians(70), rotz=0.15))
    # green onion rings
    for k in range(7):
        a = r.uniform(0, 6.28); rd = r.uniform(0.1, 0.55)
        bm = lathe([(0.055, 0.0), (0.075, 0.0), (0.075, 0.035), (0.055, 0.035)], 10)
        commit(bm, lambda p, n: (0.48, 0.78, 0.30) if n.z > 0.5 else (0.70, 0.90, 0.50), sharp=70, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), zb+0.075)))
BUILD['ramen'] = ramen

# ================================================================ MAC & CHEESE
def elbow(rad_arc, tube, ang, seed):
    path = []
    for i in range(13):
        a = ang*i/12
        path.append((rad_arc*math.cos(a), rad_arc*math.sin(a), 0))
    return sweep(path, tube, 8)

def mac(v=0):
    R = 0.72
    prof = [(0, 0), (0.30, 0), (0.42, 0.02), (R-0.18, 0.22), (R, 0.50), (R-0.04, 0.54), (R-0.12, 0.52), (R-0.14, 0.40), (0.44, 0.22), (0, 0.18)]
    bm = lathe(prof, 36)
    commit(bm, lambda p, n: (0.62, 0.80, 0.94) if (p.z > 0.0 and not (n.z > 0.3 and p.z > 0.2)) else (0.98, 0.95, 0.88), sharp=60)   # sky-blue bowl, cream inside
    # white dots on the bowl are skipped; cheese sauce heap
    zc = 0.34
    bm = lathe([(0, zc), (R-0.2, zc), (R-0.2, zc+0.10), (0.5, zc+0.22), (0, zc+0.32)], 36)
    commit(bm, lambda p, n: mix((1.0, 0.70, 0.14), (1.0, 0.82, 0.30), sstep(0.3, 1.0, n.z)*0.6), sharp=70)
    r = random.Random(8)
    placed = 0
    for k in range(22):
        a = r.uniform(0, 6.28); rd = (0.44*math.sqrt(r.uniform(0, 1)))
        hz = zc + 0.30*(1-(rd/0.55)**2) + 0.06
        bm = elbow(0.115, 0.06, r.uniform(2.6, 3.4), k)
        col = lambda p, n, k=k: mix((1.0, 0.80, 0.30), (0.98, 0.68, 0.16), sstep(-0.3, 0.8, nz(p, 5.0, k))*0.8)
        commit(bm, col, sharp=70, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), hz + 0.05*(k % 3)), rotz=r.uniform(0, 6.28), rotx=r.uniform(-0.8, 0.8), roty=r.uniform(-0.8, 0.8)))
    # breadcrumb crunch + parsley on top
    for k in range(14):
        a = r.uniform(0, 6.28); rd = 0.40*math.sqrt(r.uniform(0, 1))
        bm = blob(0.035, 0.03, 0.022, 1)
        commit(bm, (0.86, 0.60, 0.30) if k % 3 else (0.45, 0.72, 0.30), sharp=80, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), zc+0.36-0.4*rd*rd+0.04), rotz=a))
BUILD['macncheese'] = mac

# ================================================================ FRUIT CUP
def fruitcup(v=0):
    # a pastel plastic cup (tapered) with a white lip, heaped with fruit
    prof = [(0, 0), (0.34, 0), (0.40, 0.03), (0.54, 0.62), (0.58, 0.66), (0.57, 0.70), (0.52, 0.70), (0.50, 0.58), (0.0, 0.58)]
    bm = lathe(prof, 32)
    def cc(p, n):
        if p.z > 0.64: return (1.0, 0.98, 0.94)
        k = math.floor(math.atan2(p.y, p.x)/(2*math.pi)*10) % 2
        return (0.62, 0.84, 0.96) if k == 0 else (0.80, 0.92, 0.98)
    commit(bm, cc, sharp=60)
    r = random.Random(3)
    # heap base of orange wedges + melon cubes
    for k in range(5):
        a = k*1.256 + 0.3; rd = 0.30
        bm = blob(0.20, 0.12, 0.08, 2)
        # half-moon: flatten one side
        move(bm, lambda p: (p.x, p.y if p.y > -0.05 else -0.05 + (p.y+0.05)*0.1, p.z))
        commit(bm, lambda p, n: (1.0, 0.62, 0.14) if n.z > -0.3 else (1.0, 0.8, 0.45), sharp=80, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), 0.62), rotz=a+1.2, rotx=0.3))
    for k in range(4):
        a = 0.5 + k*1.6; rd = 0.30
        bm = rr_slab(0.09, 0.09, 0, 0.18, 0.04)
        commit(bm, (0.78, 0.92, 0.46), mods=BEV(0.03, 2), sharp=60, xf=xf_rt((rd*math.cos(a)+0.05, rd*math.sin(a), 0.68), rotz=a, rotx=0.2))
    # strawberries
    for (x, y, a) in [(-0.18, -0.14, 0.4), (0.22, 0.05, 2.0), (0.0, 0.24, 4.1)]:
        bm = ico(3)
        move(bm, lambda p: (p.x*0.19*(0.62+0.38*(p.z+1)/2), p.y*0.19*(0.62+0.38*(p.z+1)/2), p.z*0.21))
        def sc(p, n, a=a):
            c = (0.92, 0.14, 0.22)
            if (nz(p, 55.0, 2) > 0.30) and n.z > -0.7: c = (1.0, 0.88, 0.50)
            return mix(c, (0.99, 0.35, 0.40), sstep(0.3, 1.0, n.z)*0.4)
        commit(bm, sc, sharp=80, xf=xf_rt((x, y, 0.80), rotz=a, rotx=0.5*math.sin(a)))
        bm = blob(0.10, 0.10, 0.025, 2)
        commit(bm, (0.38, 0.72, 0.30), sharp=80, xf=xf_rt((x, y, 0.98), rotz=a, rotx=0.5*math.sin(a)))
    # blueberries
    for (x, y) in [(0.02, -0.28), (-0.34, 0.10), (0.34, -0.12), (0.12, 0.14), (-0.10, 0.06)]:
        bm = ico(3, 0.12)
        commit(bm, lambda p, n: (0.30, 0.34, 0.74) if n.z < 0.92 else (0.2, 0.2, 0.45), sharp=80, xf=xf_rt((x, y, 0.78 + 0.1*(1 - (x*x+y*y)*3))))
    # grapes + a mint leaf
    for (x, y, z) in [(-0.32, -0.06, 0.84), (-0.22, 0.28, 0.74)]:
        bm = ico(3, 0.13); move(bm, lambda p: (p.x, p.y, p.z*1.1))
        commit(bm, (0.64, 0.86, 0.42), sharp=80, xf=xf_rt((x, y, z)))
    bm = blob(0.14, 0.07, 0.015, 2)
    commit(bm, (0.30, 0.66, 0.34), sharp=80, xf=xf_rt((0.08, -0.04, 0.96), rotz=0.7, rotx=-0.3))
BUILD['fruitcup'] = fruitcup

# ================================================================ PANCAKE STACK
def pancakes(v=0):
    R = 0.72
    z = 0.0
    r = random.Random(2)
    for k in range(4):
        rr = R*(1.0 - 0.015*k) + 0.02*math.sin(k*3)
        prof = [(0, z), (rr-0.10, z), (rr-0.02, z+0.03), (rr, z+0.08), (rr-0.02, z+0.14), (rr-0.10, z+0.17), (0, z+0.17)]
        bm = lathe(prof, 36)
        def pc(p, n, z=z):
            top = n.z > 0.5 and p.z > z+0.16
            c = (0.94, 0.72, 0.38)
            if top: c = mix((0.88, 0.58, 0.26), (0.96, 0.74, 0.40), sstep(0.0, 1.0, nz(p, 3.0, k)*0.5+0.5))
            if abs(n.z) < 0.6: c = mix((0.99, 0.88, 0.62), (0.97, 0.80, 0.50), 0.4)           # the pale sides
            return c
        commit(bm, pc, sharp=70, xf=xf_rt((0.02*math.sin(k*2.0), 0.02*math.cos(k*2.5), 0)))
        z += 0.15
    top = z + 0.02
    # syrup: a glossy amber pool with drips down the front/sides
    bm = lathe([(0, top), (0.56, top), (0.62, top+0.03), (0.54, top+0.07), (0, top+0.09)], 28)
    move(bm, lambda p: (p.x*(1+0.18*math.sin(math.atan2(p.y, p.x)*3)), p.y, p.z))
    commit(bm, lambda p, n: mix((0.78, 0.34, 0.08), (0.92, 0.55, 0.14), sstep(0.5, 1.0, n.z)*0.8), sharp=80)
    for (a, L) in [(-1.3, 0.22), (-0.6, 0.16), (-2.0, 0.17), (0.5, 0.15)]:
        bm = blob(0.085, 0.05, L, 3)
        commit(bm, lambda p, n: mix((0.78, 0.34, 0.08), (0.92, 0.55, 0.14), sstep(0.2, 1.0, n.z)*0.4), sharp=80,
               xf=xf_rt((0.60*math.cos(a), 0.60*math.sin(a), top-L*0.7), rotz=a))
    # butter pat
    bm = rr_slab(0.17, 0.17, 0, 0.11, 0.05)
    commit(bm, lambda p, n: (1.0, 0.92, 0.55) if n.z > 0.5 else (0.99, 0.86, 0.42), mods=BEV(0.04, 2), sharp=60, xf=xf_rt((0.04, 0.02, top+0.07), rotz=0.5))
    # strawberry + blueberries
    bm = ico(3); move(bm, lambda p: (p.x*0.17*(0.62+0.38*(p.z+1)/2), p.y*0.17*(0.62+0.38*(p.z+1)/2), p.z*0.19))
    commit(bm, lambda p, n: (0.92, 0.14, 0.22) if nz(p, 55.0, 2) < 0.3 else (1.0, 0.88, 0.5), sharp=80, xf=xf_rt((-0.20, -0.14, top+0.20), rotx=0.3))
    bm = blob(0.09, 0.09, 0.022, 2); commit(bm, (0.38, 0.72, 0.30), sharp=80, xf=xf_rt((-0.20, -0.14, top+0.38), rotx=0.3))
    for (x, y) in [(0.26, -0.10), (0.30, 0.12)]:
        commit(ico(3, 0.10), lambda p, n: (0.30, 0.34, 0.74), sharp=80, xf=xf_rt((x, y, top+0.15)))
BUILD['pancakestack'] = pancakes

# ================================================================ STRAWBERRY CAKE SLICE
def cakeslice(v=0):
    # a wedge lying flat: tip toward +y (back), wide cut face to the front? keep: wedge outline, layers by height
    outl = poly_pts_rounded([(-0.62, -0.62), (0.62, -0.62), (0.0, 0.78)], 0.10, 4)
    H = 0.62
    bm = slab(outl, 0.0, H, cuts=0)
    subdiv(bm, 8)
    def cc(p, n):
        z = p.z
        if n.z > 0.6: return (1.0, 0.62, 0.72)                                       # pink glaze on top
        if p.y < -0.5 and abs(n.y) > 0.5 or True:
            # sponge / cream layers by height
            bands = [(0.0, 0.14, (0.98, 0.84, 0.62)), (0.14, 0.21, (1.0, 0.97, 0.92)), (0.21, 0.36, (1.0, 0.72, 0.78)), (0.36, 0.43, (1.0, 0.97, 0.92)),
                     (0.43, 0.58, (0.98, 0.84, 0.62)), (0.58, 0.9, (1.0, 0.62, 0.72))]
            for a, b, col in bands:
                if a <= z < b: return col
            return (1.0, 0.62, 0.72)
    # side walls (not the cut face) get cream frosting
    def cc2(p, n):
        c = cc(p, n)
        if abs(n.y) < 0.5 and n.z < 0.6 and p.y > -0.5:
            return (1.0, 0.94, 0.90) if True else c
        return c
    commit(bm, cc2, mods=[], sharp=50)
    # piped cream rosettes along the back edge and strawberry on the wide end
    for (x, y) in [(-0.30, -0.40), (0.0, -0.40), (0.30, -0.40)]:
        prof = [(0.0, 0.0), (0.12, 0.0), (0.13, 0.04), (0.10, 0.10), (0.11, 0.14), (0.06, 0.18), (0.07, 0.22), (0.02, 0.28), (0.0, 0.30)]
        bm = lathe(prof, 14)
        commit(bm, lambda p, n: (1.0, 0.98, 0.94), sharp=80, xf=xf_rt((x, y, H-0.01)))
    bm = ico(3); move(bm, lambda p: (p.x*0.17*(0.62+0.38*(p.z+1)/2), p.y*0.17*(0.62+0.38*(p.z+1)/2), p.z*0.19))
    commit(bm, lambda p, n: (0.92, 0.14, 0.22) if nz(p, 55.0, 2) < 0.3 else (1.0, 0.88, 0.5), sharp=80, xf=xf_rt((0.0, 0.05, H+0.17), rotx=0.0))
    bm = blob(0.09, 0.09, 0.022, 2); commit(bm, (0.38, 0.72, 0.30), sharp=80, xf=xf_rt((0.0, 0.05, H+0.34)))
    # a sliced strawberry fan on the right? keep: two small hearts of berry on the glaze
    for (x, y) in [(-0.22, 0.20), (0.22, 0.22)]:
        bm = blob(0.07, 0.07, 0.07, 2)
        commit(bm, (0.95, 0.30, 0.40), sharp=80, xf=xf_rt((x, y, H+0.04)))
BUILD['cakeslice'] = cakeslice

# ================================================================ FROSTED CUPCAKE
def cupcake(v=0):
    # pleated paper wrapper
    prof = [(0, 0), (0.30, 0), (0.34, 0.02), (0.50, 0.46), (0.52, 0.50), (0.46, 0.50), (0, 0.40)]
    bm = lathe(prof, 48)
    displace(bm, lambda p, n: 0.022*math.sin(math.atan2(p.y, p.x)*12) if n.z < 0.5 else None)
    commit(bm, lambda p, n: (1.0, 0.72, 0.80) if math.sin(math.atan2(p.y, p.x)*12) > 0 else (0.96, 0.58, 0.70), sharp=70)
    # cake dome peeking at the rim
    prof = [(0, 0.42), (0.48, 0.44), (0.52, 0.52)]
    for k in range(1, 6):
        a = k/5*math.pi/2; prof.append((0.52*math.cos(a), 0.52 + 0.14*math.sin(a)))
    commit(lathe(prof, 36), (0.98, 0.84, 0.58), sharp=60)
    # swirl frosting: stacked rings getting smaller, wobbling (soft-serve swirl)
    z = 0.58; rings = [(0.50, 0.12), (0.42, 0.12), (0.33, 0.11), (0.24, 0.10), (0.15, 0.09)]
    for i, (rr, tt) in enumerate(rings):
        bm = bmesh.new(); n = 28; m = 10; grid = []
        ox = 0.03*math.sin(i*1.3); oy = 0.03*math.cos(i*1.3)
        for a_i in range(n):
            a = 2*math.pi*a_i/n
            ring = []
            for k in range(m):
                b = 2*math.pi*k/m
                R = rr + tt*math.cos(b)
                ring.append(bm.verts.new((ox + R*math.cos(a), oy + R*math.sin(a), z + tt*math.sin(b)*0.95 + 0.02*math.sin(a*3+i))))
            grid.append(ring)
        for a_i in range(n):
            j = (a_i+1) % n
            for k in range(m):
                q = (k+1) % m
                bm.faces.new([grid[a_i][k], grid[j][k], grid[j][q], grid[a_i][q]])
        def fc(p, n_, i=i):
            c = mix((1.0, 0.70, 0.80), (1.0, 0.86, 0.90), sstep(0.2, 1.0, n_.z)*0.8)
            return mix(c, (0.93, 0.55, 0.70), sstep(0.0, -0.8, n_.z)*0.6)
        commit(bm, fc, sharp=80)
        z += 0.10
    # cherry on top and sprinkles
    commit(ico(3, 0.12), lambda p, n: (0.85, 0.08, 0.16) if n.z < 0.8 else (0.55, 0.05, 0.1), sharp=80, xf=xf_rt((0, 0, z+0.06)))
    path = [(0, 0, z+0.16), (0.04, 0.02, z+0.28), (0.12, 0.02, z+0.33)]
    commit(sweep(path, 0.012, 5), (0.35, 0.6, 0.28), sharp=80)
    r = random.Random(1)
    cols = [(0.4, 0.7, 1.0), (1.0, 0.9, 0.3), (1.0, 1.0, 1.0), (0.6, 0.9, 0.5)]
    for k in range(26):
        a = r.uniform(0, 6.28); rd = r.uniform(0.12, 0.46); zz = 0.58 + 0.10 + (0.5-rd)*0.35 + r.uniform(-0.02, 0.1)
        bm = blob(0.055, 0.016, 0.016, 1)
        # outward-ish normal sits on the rings
        commit(bm, cols[k % 4], sharp=80, xf=xf_rt((rd*math.cos(a), rd*math.sin(a), 0.66 + 0.62*(0.5-rd)*0.35 + 0.30*(1-rd/0.5)*0.0 + 0.2*(0.5-rd)), rotz=r.uniform(0, 3.14)))
BUILD['cupcake'] = cupcake

# ================================================================ DUMPLINGS (in a steamer)
def dumpling(seed):
    bm = ico(3)
    move(bm, lambda p: (p.x*0.34, p.y*0.20*(1.0 if p.z > -0.1 else 0.8), p.z*0.22 if p.z > 0 else p.z*0.10))
    # pleats along the crest: a ridge of small folds
    displace(bm, lambda p, n: 0.022*math.sin(p.x*45)*max(0.0, p.z/0.22) if p.z > 0.05 else None)
    def dc(p, n):
        c = (1.0, 0.96, 0.88)
        c = mix(c, (0.96, 0.82, 0.62), sstep(0.15, 0.0, p.z)*0.5)
        if p.z > 0.14 and abs(p.y) < 0.05: c = mix(c, (1.0, 1.0, 0.97), 0.6)
        if nz(p, 20.0, seed) > 0.55: c = mix(c, (0.98, 0.78, 0.62), 0.5)             # a few steamed freckles
        return c
    return bm, dc

def dumplings(v=0):
    R = 0.74
    # bamboo steamer: a wide short basket with bands
    prof = [(0, 0), (R-0.1, 0), (R, 0.05), (R, 0.40), (R-0.06, 0.44), (R-0.14, 0.42), (R-0.14, 0.12), (0, 0.10)]
    bm = lathe(prof, 40)
    def bc(p, n):
        if n.z > 0.3 and p.z > 0.1: return (0.80, 0.60, 0.34)                         # the inside
        k = math.floor(p.z/0.09)
        return (0.88, 0.70, 0.42) if k % 2 == 0 else (0.78, 0.58, 0.32)
    commit(bm, bc, sharp=60)
    # a cabbage leaf liner
    commit(lathe([(0, 0.12), (R-0.15, 0.12), (R-0.12, 0.15), (0, 0.15)], 30), lambda p, n: mix((0.62, 0.84, 0.42), (0.80, 0.94, 0.56), sstep(0.3, 1.0, nz(p, 5.0)*0.5+0.5)), sharp=70)
    spots = [(-0.26, -0.18, 0.5), (0.26, -0.16, -0.5), (0.0, 0.26, 3.4), (0.02, -0.02, 1.2)]
    for k, (x, y, a) in enumerate(spots):
        bm, dc = dumpling(k)
        commit(bm, dc, sharp=75, xf=xf_rt((x, y, 0.22 + (0.0 if k < 3 else 0.12)), rotz=a, scale=(1.25, 1.25, 1.35)))
    # a green onion and a sesame dot or two sprinkled
    for (x, y) in [(0.05, -0.30), (-0.34, 0.10)]:
        commit(blob(0.04, 0.025, 0.018, 1), (0.14, 0.12, 0.10), sharp=80, xf=xf_rt((x, y, 0.20)))
BUILD['dumplings'] = dumplings

foods.BUILD.update(BUILD)
