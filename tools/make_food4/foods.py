import os
import sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import *
V = Vector

# ============================ NUGGET ============================
def nugget(v=0):
    r = random.Random(40+v)
    ph = [r.uniform(0, 6.28) for _ in range(4)]
    rx, ry, rz = [(0.64,0.5,0.40),(0.57,0.55,0.40),(0.62,0.46,0.40)][v%3]
    off = v*7.3
    bm = ico(4)
    def f(p):
        d = V(p).normalized(); a = math.atan2(d.y, d.x)
        rr = 1 + 0.16*math.sin(2*a+ph[0]) + 0.11*math.sin(3*a+ph[1]) + 0.06*math.sin(5*a+ph[2])
        s = math.sqrt(max(0, 1-d.z*d.z))
        x = d.x/ max(s,1e-6)*math.pow(s, 0.5)*rx*rr if s > 1e-6 else 0
        y = d.y/ max(s,1e-6)*math.pow(s, 0.5)*ry*rr if s > 1e-6 else 0
        z = math.copysign(abs(d.z)**0.8, d.z)*rz*(0.9+0.12*nz(d, 1.3, off))
        if z < 0: z *= 0.28
        return (x, y, z)
    move(bm, f)
    def bump(p, n):
        a = 0.035*nz(p, 3.5, off) + 0.06*(1-abs(nz(p, 7.0, off+3))) + 0.03*nz(p, 13.0, off+5)
        return a
    displace(bm, bump)
    def col(p, n):
        top = (0.95, 0.66, 0.27); toast = (0.76, 0.40, 0.14); deep = (0.52, 0.26, 0.09)
        t = sstep(0.55, 0.0, n.z)                           # sides toasted
        c = mix(top, toast, t)
        sp = nz(p, 12.0, off+9)
        if sp > 0.2: c = mix(c, (1.0, 0.80, 0.42), 0.6*(sp-0.2)/0.8)   # pale crumb highs
        if sp < -0.12: c = mix(c, deep, 0.9*(-sp-0.12)/0.88)               # fried dark crumbs
        c = mix(c, deep, sstep(0.05, -0.2, n.z)*0.8)
        return c
    commit(bm, col, mods=[('DECIMATE', dict(ratio=0.7))], sharp=75, xf=xf_rt((0,0,0.0)))
    # settle on z=0
    zmin = min(q[2] for q in PARTS[-1]['P'])
    for i,q in enumerate(PARTS[-1]['P']): PARTS[-1]['P'][i] = (q[0], q[1], q[2]-zmin+0.0)

# ============================ FRIES ============================
def fry(L, w, bend, twist, col0, rseed):
    r = random.Random(rseed)
    c = w*0.34
    sec = [(w-c,w),(-(w-c),w),(-w,w-c),(-w,-(w-c)),(-(w-c),-w),(w-c,-w),(w,-(w-c)),(w,w-c)]
    sec = [(x, y) for x, y in sec]
    bm = bmesh.new(); rings = []
    for (t, sc) in [(0,0.80),(0.05,1.0),(0.5,1.0),(0.95,1.0),(1.0,0.80)]:
        z = t*L; ang = twist*t
        ca, sa = math.cos(ang), math.sin(ang)
        bx = bend*(t*t) * L
        rings.append([bm.verts.new((sc*(x*ca-y*sa)+bx, sc*(x*sa+y*ca), z)) for x, y in sec])
    for k in range(4):
        for i in range(8):
            j = (i+1) % 8
            bm.faces.new([rings[k][i], rings[k+1][i], rings[k+1][j], rings[k][j]])
    bm.faces.new(rings[0][::-1]); bm.faces.new(rings[4])
    return bm

def fries(v=0):
    r = random.Random(7+v)
    red = (0.90, 0.24, 0.24); redin = (0.74, 0.17, 0.19); cream = (1.0, 0.95, 0.78)
    # carton (outer trapezoid, front lower than back)
    W0, W1, D0, D1, H, T = 0.48, 0.56, 0.27, 0.34, 0.62, 0.045   # half widths bottom/top, half depth bottom/top, height, wall
    def box_pts(w, d, z): return [(-w,-d,z),(w,-d,z),(w,d,z),(-w,d,z)]
    bm = bmesh.new()
    ob = [bm.verts.new(p) for p in box_pts(W0, D0, 0)] + [bm.verts.new(p) for p in box_pts(W1, D1, H)]
    # front (y<0) wall is lower: scoop its top verts
    ob[4].co.z = H*0.66; ob[5].co.z = H*0.66
    ib = [bm.verts.new(p) for p in box_pts(W0-T, D0-T, T)] + [bm.verts.new(p) for p in box_pts(W1-T, D1-T, H)]
    ib[4].co.z = H*0.66-0.0; ib[5].co.z = H*0.66
    bm.faces.new(ob[0:4][::-1])
    for i in range(4):
        j = (i+1) % 4
        bm.faces.new([ob[i], ob[j], ob[4+j], ob[4+i]])
        bm.faces.new([ib[i], ib[4+i], ib[4+j], ib[j]])
        bm.faces.new([ob[4+i], ob[4+j], ib[4+j], ib[4+i]])
    bm.faces.new(ib[0:4])
    def ccol(p, n):
        inner = n.z > 0.2 and p.z < H*0.9 and abs(p.y) < D1-0.01
        if p.y < -0.2 and n.y < -0.5 and 0.2 < p.z < 0.40:
            # cream band with a little red heart shape feel (two dots) -> keep a clean band
            return cream
        if n.y > 0.3 and False: return redin
        # inside surfaces darker
        if (n.y > 0.35 and p.y > -0.1) or n.z > 0.5 and p.z < H*0.5: return redin
        return red
    commit(bm, ccol, mods=[('BEVEL', dict(width=0.035, segments=2, limit_method='ANGLE', angle_limit=math.radians(40)))], sharp=45, xf=xf_rt((0,0,0)))
    # fries
    gold = (0.99, 0.82, 0.34)
    spots = []
    cols = 4; rowsy = [-0.13, 0.04, 0.17]
    n = 0
    for iy, yy in enumerate(rowsy):
        for ix in range(cols):
            xx = (ix-1.5)*0.24 + r.uniform(-0.03,0.03) + (0.07 if iy==1 else 0)
            if iy==1 and ix==cols-1: continue
            L = r.choice([0.5, 0.62, 0.75, 0.86, 0.98, 1.1]) + (0.1 if iy==2 else 0.0) - (0.18 if iy==0 else 0)
            lean_x = (yy-0.0)*r.uniform(0.5,1.2) + r.uniform(-0.12,0.12)
            lean_y = xx*r.uniform(0.5,1.2) + r.uniform(-0.1,0.1)
            spots.append((xx, yy, L, lean_x, lean_y, r.uniform(-0.5,0.5), r.uniform(-0.3,0.3)))
    # two extra leaners on the sides
    spots.append((-0.4, 0.0, 0.88, 0.1, -0.52, 0.2, 0.15)); spots.append((0.4, 0.05, 0.8, -0.05, 0.5, -0.2, -0.2))
    for k, (xx, yy, L, lx, ly, tw, bend) in enumerate(spots):
        w = r.uniform(0.086, 0.098)
        bm = fry(L, w, bend*0.8, tw, gold, 100+k)
        tint = r.uniform(-1, 1)
        base = mix(gold, (1.0, 0.88, 0.45), 0.5+0.5*tint) if tint>0 else mix(gold, (0.96,0.74,0.28), -tint*0.6)
        z0 = 0.24 + (0.04 if yy<0 else 0.0)
        def fc(p, nn, L=L, base=base, k=k):
            t = p.z/ L
            c = base
            c = mix(c, (0.86, 0.56, 0.2), sstep(0.88, 1.0, t)*0.7 + sstep(0.12, 0.0, t)*0.5)   # fried tip & cut ends
            edge = 1 - max(abs(nn.x), abs(nn.y))*1.2
            c = mix(c, (0.92, 0.66, 0.24), max(0, min(1, (0.45-abs(nn.z)*0)))*0*0)
            if abs(nn.z) > 0.7: c = mix(c, (1.0, 0.92, 0.6), 0.65)    # paler potato end faces
            sp = nz(p, 12.0, k)
            if sp > 0.4: c = mix(c, (0.84, 0.55, 0.2), 0.5)
            return c
        commit(bm, fc, sharp=60, xf=xf_rt((xx, yy, z0), rotz=r.uniform(0, 6.28)*0 + 0.0, rotx=-ly*0+ -lx, roty=ly))
    return

# ============================ SUSHI ============================
def sushi(v=0):
    R, Ri, H = 0.60, 0.50, 0.62
    nori = (0.13, 0.20, 0.17); rice = (0.99, 0.98, 0.94)
    prof = [(0, 0), (R-0.05, 0), (R, 0.05), (R, H-0.05), (R-0.045, H), (Ri+0.04, H), (Ri, H-0.04), (Ri, H-0.2)]
    bm = lathe(prof, 30)
    def nc(p, n):
        c = mix(nori, (0.24, 0.32, 0.26), sstep(0.2, 0.9, nz(p, 6.0)*0.5+0.5)*0.35)
        if n.z > 0.6: c = mix(c, (0.20, 0.28, 0.22), 0.5)
        return c
    commit(bm, nc, sharp=70)
    # rice top: a low disc plus individual chunky grains (stylised but unmistakable)
    r = random.Random(3)
    bm = bmesh.new(); segs = 28
    top = H + 0.02
    ctr = bm.verts.new((0, 0, top))
    ring1 = [bm.verts.new((Ri*0.55*math.cos(2*math.pi*i/segs), Ri*0.55*math.sin(2*math.pi*i/segs), top)) for i in range(segs)]
    ring2 = [bm.verts.new((Ri*0.995*math.cos(2*math.pi*i/segs), Ri*0.995*math.sin(2*math.pi*i/segs), top-0.02)) for i in range(segs)]
    for i in range(segs):
        j = (i+1) % segs
        bm.faces.new([ctr, ring1[i], ring1[j]]); bm.faces.new([ring1[i], ring2[i], ring2[j], ring1[j]])
    commit(bm, lambda p, n: (0.90, 0.87, 0.79), sharp=80)
    grains = []
    tries = 0
    while len(grains) < 30 and tries < 600:
        tries += 1
        a = r.uniform(0, 6.28); rr = Ri*math.sqrt(r.uniform(0.0, 1.0))*0.93
        x, y = rr*math.cos(a), rr*math.sin(a)
        if all((x-g[0])**2 + (y-g[1])**2 > 0.095**2 for g in grains): grains.append((x, y, r.uniform(0, 3.14)))
    for k, (x, y, a) in enumerate(grains):
        bm = ico(1, 1.0)
        move(bm, lambda p: (p.x*0.088, p.y*0.052, p.z*0.04))
        commit(bm, lambda p, n, k=k: mix((0.99, 0.98, 0.94), (1.0, 1.0, 1.0), 0.5) if n.z > 0.2 else (0.92, 0.89, 0.82), sharp=80,
               xf=xf_rt((x, y, top-0.005), rotz=a))
    # fillings
    def dome(cx, cy, rx, ry, hh, col, rot=0.0, seg=18):
        pr = [(0, hh), (0.55, hh*0.95), (0.85, hh*0.72), (1.0, 0.3*hh), (1.0, -0.05)]
        bm = lathe([(a, b) for a, b in pr], seg)
        move(bm, lambda p: (p.x*rx, p.y*ry, p.z + H+0.0))
        return commit(bm, col, sharp=80, xf=xf_rt((cx, cy, 0), rotz=rot))
    def salmon(p, n):
        s = math.sin((p.x*math.cos(0.6)+p.y*math.sin(0.6))*34)
        c = (0.99, 0.55, 0.38)
        c = mix(c, (1.0, 0.88, 0.78), sstep(0.55, 0.95, s)*0.8)
        return mix(c, (0.95, 0.42, 0.30), sstep(0.5, 0.0, n.z)*0.6)
    dome(-0.1, -0.03, 0.25, 0.2, 0.2, salmon, rot=0.5, seg=18)
    def cuc(p, n):
        d = math.hypot(p.x-0.2, p.y-0.15)
        return mix((0.84, 0.95, 0.66), (0.28, 0.58, 0.28), sstep(0.08, 0.125, d))
    dome(0.22, 0.17, 0.15, 0.15, 0.17, cuc, seg=14)
    def avo(p, n):
        d = math.hypot(p.x-0.12, p.y+0.2)
        return mix((0.99, 0.95, 0.58), (0.50, 0.72, 0.30), sstep(0.06, 0.12, d))
    dome(0.13, -0.22, 0.14, 0.11, 0.15, avo, rot=0.4, seg=14)
    dome(-0.17, 0.27, 0.085, 0.085, 0.12, (1.0, 0.78, 0.22), seg=10)    # tamago / roe dot

# ============================ SANDWICH ============================
TRI = [(-0.76, -0.38), (0.76, -0.38), (0.0, 0.38)]
def scale_poly(poly, s, dx=0, dy=0):
    cx = sum(p[0] for p in TRI)/3; cy = sum(p[1] for p in TRI)/3
    return [(cx+(x-cx)*s+dx, cy+(y-cy)*s+dy) for x, y in poly]

def sandwich(v=0):
    crumb = (1.0, 0.92, 0.70); crust = (0.84, 0.55, 0.26); crust_t = (0.92, 0.68, 0.34)
    outline = poly_pts_rounded(TRI, 0.09, 4)
    def bread(z0, z1, top):
        bm = slab(outline, z0, z1, cuts=0)
        def c(p, n):
            cutface = sstep(-0.35, -0.8, n.y) * sstep(-0.3, -0.37, p.y)
            col = mix(crust, crust_t, 0.5) if n.z > 0.5 else crust
            if top and n.z > 0.5: col = mix(crust_t, (0.95, 0.76, 0.42), sstep(-0.3, 0.3, nz(p, 2.5)*0.5+0.5)*0.5)
            col = mix(col, crumb, cutface*(1-sstep(0.35, 0.8, abs(n.z))))
            return col
        mods = [('BEVEL', dict(width=0.055, segments=2, limit_method='ANGLE', angle_limit=math.radians(35)))]
        return commit(bm, c, mods=mods, sharp=50)
    bread(0.0, 0.25, False)
    # cheese
    ch = scale_poly(poly_pts_rounded(TRI, 0.05, 3), 1.06, 0.0, -0.05)
    bm = slab(ch, 0.25, 0.31, cuts=1)
    def chf(p, n):
        d = (p.x-0.62)**2*0+0
        return mix((1.0, 0.82, 0.26), (1.0, 0.9, 0.42), sstep(-0.1, 0.1, n.z)*0.5)
    # droopy corner
    def droop(p):
        t = max(0.0, (p.x - 0.35)/0.6)*max(0.0, (-p.y+0.1)/0.5)
        return (p.x, p.y, p.z - 0.16*t*t - 0.02*abs(nz(p, 6.0)))
    move(bm, droop)
    commit(bm, chf, mods=[('BEVEL', dict(width=0.012, segments=1, limit_method='ANGLE', angle_limit=math.radians(40)))], sharp=60)
    # tomato slices (two, peeking past the front edge)
    for (cx, cy, rr) in [(-0.32, -0.30, 0.31), (0.34, -0.29, 0.30)]:
        pr = [(0, 0), (rr-0.05, 0), (rr, 0.04), (rr, 0.08), (rr-0.05, 0.12), (0, 0.12)]
        bm = lathe(pr, 16)
        def tc(p, n, cx=cx, cy=cy, rr=rr):
            ang = math.atan2(p.y, p.x); d = math.hypot(p.x, p.y)
            c = (0.92, 0.27, 0.22)
            if n.z > 0.5:
                if 0.55*rr < d < rr-0.04 and abs(math.sin(ang*1.5)) > 0.9: c = (1.0, 0.82, 0.62)   # seed gel wedges
                c = mix(c, (1.0, 0.75, 0.65), sstep(0.08, 0.0, abs(d-0.2*rr))*0.0)
            if d > rr-0.035: c = (0.80, 0.18, 0.15)
            return c
        commit(bm, tc, sharp=70, xf=xf_rt((cx, cy, 0.31)))
    # lettuce frill: ruffle ribbon around the outline
    n = 28; loop = []
    path = poly_pts_rounded(TRI, 0.12, 6)
    # resample the outline by arclength
    pts = [V((x, y, 0)) for x, y in path]
    seglen = [(pts[(i+1) % len(pts)]-pts[i]).length for i in range(len(pts))]
    tot = sum(seglen)
    def at(s):
        s %= tot
        for i, l in enumerate(seglen):
            if s <= l: return pts[i].lerp(pts[(i+1) % len(pts)], s/l), i
            s -= l
        return pts[0], 0
    cen = V((0, 0, 0))
    bm = bmesh.new(); rows = []
    for rowi, (inset, zb) in enumerate([(-0.16, 0.0), (-0.05, 0.02), (0.07, 0.0), (0.13, 0.0)]):
        row = []
        for i in range(n):
            p, _ = at(tot*i/n)
            d = (p - V((0, 0.0, 0))).normalized() if False else (p - V((0, -0.0, 0)))
            c0 = V((0, -0.12, 0)); dv = (p-c0).normalized()
            wave = math.sin(i*2*math.pi/n*13)
            rad = inset + 0.055*wave*(1 if rowi>=2 else 0.5)
            q = p + dv*rad
            z = 0.30 + 0.045*(rowi==1) + 0.05*(0.5+0.5*math.sin(i*2*math.pi/n*13+1.3))*(1 if rowi >= 2 else 0.4)
            z += {0:0.0, 1:0.07, 2:0.12, 3:0.075}[rowi] + 0.03*wave*(rowi>=2)
            row.append(bm.verts.new((q.x, q.y, z)))
        rows.append(row)
    for k in range(3):
        for i in range(n):
            j = (i+1) % n
            bm.faces.new([rows[k][i], rows[k][j], rows[k+1][j], rows[k+1][i]])
    lc = lambda p, nn: mix((0.50, 0.80, 0.34), (0.74, 0.92, 0.50), sstep(0.2, 0.42, p.z)*0.9)
    commit(bm, lc, mods=[('SOLIDIFY', dict(thickness=0.04, offset=0))], sharp=90)
    # lettuce core disc under the top bread
    top = bread(0.40, 0.66, True)

# ============================ PIZZA ============================
def pizza(v=0):
    hl, hw = 1.3, 0.8
    TRIP = [(0.0, -hl), (hw, hl), (-hw, hl)]
    outl = poly_pts_rounded(TRIP, 0.12, 4)
    dough = (0.93, 0.74, 0.44); crustc = (0.90, 0.60, 0.28)
    bm = slab(outl, 0.0, 0.2, cuts=0)
    commit(bm, lambda p, n: mix(dough, (0.80, 0.52, 0.25), sstep(0.1, 0.0, p.z)*0.6),
           mods=[('BEVEL', dict(width=0.05, segments=2, limit_method='ANGLE', angle_limit=math.radians(40)))], sharp=50)
    # cheese
    ins = poly_pts_rounded([(0.0, -hl+0.2), (hw-0.2, hl-0.28), (-hw+0.2, hl-0.28)], 0.10, 4)
    bm = slab(ins, 0.18, 0.26, cuts=1)
    r = random.Random(5)
    def bumpy(p, n):
        return (0.022*nz(p, 4.0, 2) + 0.012*nz(p, 9.0, 5)) if n.z > 0.5 else None
    displace(bm, bumpy)
    # distance to cheese boundary for sauce ring
    def chcol(p, n):
        # sauce peeking at the boundary
        c = (1.0, 0.86, 0.42)
        s = nz(p, 6.0, 1)
        c = mix(c, (1.0, 0.72, 0.28), sstep(0.15, 0.7, s)*0.7)
        c = mix(c, (1.0, 0.93, 0.62), sstep(0.2, 0.7, -s)*0.5)
        if n.z < 0.6: c = mix(c, (0.93, 0.45, 0.2), 0.6)
        return c
    commit(bm, chcol, mods=[('BEVEL', dict(width=0.025, segments=1, limit_method='ANGLE', angle_limit=math.radians(40)))], sharp=60)
    # crust: fat bar on the base
    bm = lathe([(0, -0.9*hw-0.06), ], 8) if False else bmesh.new()
    # build capsule along x
    segs, rings, Lc, rc_ = 12, 8, hw*0.98, 0.2
    cv = []
    for k in range(rings+1):
        a = math.pi*k/rings
        x = (-Lc+ (0)*1) if False else None
    bm = bmesh.new()
    grid = []
    xs = [(-Lc) + 2*Lc*i/10 for i in range(11)]
    for xi, x in enumerate(xs):
        e = abs(x)/Lc
        rr = rc_*(math.sqrt(max(0.0, 1-max(0, (e-0.78)/0.22)**2)) if e > 0.78 else 1.0)*(1 + 0.05*math.sin(xi*2.1))
        ring = []
        for i in range(10):
            a = 2*math.pi*i/10
            ring.append(bm.verts.new((x, hl-0.1 + rr*math.cos(a)*1.05, 0.17 + rr*math.sin(a)*0.95)))
        grid.append(ring)
    for xi in range(10):
        for i in range(10):
            j = (i+1) % 10
            bm.faces.new([grid[xi][i], grid[xi+1][i], grid[xi+1][j], grid[xi][j]])
    bm.faces.new(grid[0][::-1]); bm.faces.new(grid[10])
    def cc(p, n):
        c = mix(crustc, (0.96, 0.74, 0.40), sstep(0.2, 0.9, n.z)*0.8)
        c = mix(c, (0.62, 0.34, 0.16), sstep(0.15, 0.0, p.z)*0.0 + max(0, nz(p, 8.0, 4)-0.3)*0.6)
        if n.y > 0.3: c = mix(c, (0.78, 0.48, 0.22), 0.5)
        return c
    commit(bm, cc, sharp=70)
    # pepperoni
    for k, (x, y, rr) in enumerate([(0.0, -0.5, 0.27), (-0.26, 0.15, 0.30), (0.30, 0.5, 0.25)]):
        pr = [(0, 0.0), (rr-0.03, 0.0), (rr, 0.03), (rr-0.02, 0.07), (rr*0.55, 0.075), (0, 0.06)]
        bm = lathe(pr, 14)
        def pc(p, n, rr=rr):
            d = math.hypot(p.x, p.y)
            c = (0.80, 0.22, 0.17)
            c = mix(c, (0.62, 0.14, 0.11), sstep(rr*0.7, rr, d))
            if nz(p, 14.0, 3) > 0.45: c = mix(c, (0.95, 0.62, 0.45), 0.5)
            return c
        commit(bm, pc, sharp=70, xf=xf_rt((x, y, 0.255), rotz=k*1.3))
    # basil / green pepper bits
    for (x, y, a) in [(0.18, -0.15, 0.6), (-0.3, -0.55, 2.0), (0.02, 0.62, 1.2), (-0.12, 0.45, 0.2)]:
        bm = ico(1, 1.0)
        move(bm, lambda p: (p.x*0.12, p.y*0.07, p.z*0.03))
        commit(bm, (0.36, 0.68, 0.28), sharp=80, xf=xf_rt((x, y, 0.275), rotz=a))

# ============================ TACO ============================
def taco(v=0):
    R = 0.78
    nu, nt = 10, 12
    bm = bmesh.new(); g = []
    al = math.radians(30)
    for ti in range(nt+1):
        t = -1 + 2*ti/nt
        h = R*math.sqrt(max(0.0, 1-t*t)) + 0.02
        row = []
        for ui in range(nu+1):
            u = -1 + 2*ui/nu
            eps = 0.12
            s = math.sqrt(u*u + eps*eps) - eps
            x = u*h*math.sin(al)*(1 - 0.14*u*u) + 0.0
            z = s*h*math.cos(al)*1.0 + 0.04
            y = R*t + 0.1*(u*u)*0.0
            row.append(bm.verts.new((x, y, z)))
        g.append(row)
    for ti in range(nt):
        for ui in range(nu):
            try: bm.faces.new([g[ti][ui], g[ti][ui+1], g[ti+1][ui+1], g[ti+1][ui]])
            except ValueError: pass
    def shc(p, n):
        c = (0.98, 0.79, 0.38)
        c = mix(c, (0.88, 0.60, 0.22), max(0, nz(p, 5.0, 2)-0.1)*0.9)
        if nz(p, 13.0, 1) > 0.5: c = mix(c, (0.78, 0.5, 0.18), 0.5)
        c = mix(c, (1.0, 0.88, 0.55), sstep(0.35, 0.8, p.z)*0.5)
        if n.z > 0.0 and p.z < 0.25: c = mix(c, (0.9, 0.7, 0.35), 0.0)
        return c
    commit(bm, shc, mods=[('SOLIDIFY', dict(thickness=0.055, offset=0))], sharp=70)
    # fillings: mince mound
    r = random.Random(2)
    bm = bmesh.new(); rows = []
    nn = 12
    for i in range(nn+1):
        t = -0.74 + 1.48*i/nn
        e = math.sqrt(max(0.0, 1-(t/0.8)**2))
        rows.append([bm.verts.new((rr*math.cos(a), t, 0.36 + 0.14*rr*math.sin(a)*0 + rr*0.7*math.sin(a))) for a, rr in
                     [(2*math.pi*k/8, 0.2*e+0.001) for k in range(8)]])
    for i in range(nn):
        for k in range(8):
            j = (k+1) % 8
            try: bm.faces.new([rows[i][k], rows[i][j], rows[i+1][j], rows[i+1][k]])
            except ValueError: pass
    displace(bm, lambda p, n: 0.05*nz(p, 8.0, 3))
    commit(bm, lambda p, n: mix((0.52, 0.31, 0.19), (0.66, 0.42, 0.26), sstep(-0.3, 0.7, nz(p, 12.0, 1))), sharp=70)
    # lettuce ruffle on top
    bm = bmesh.new(); gg = []
    for i in range(0, 17):
        t = -0.72 + 1.44*i/16
        e = math.sqrt(max(0.0, 1-(t/0.8)**2))
        row = []
        for k, w in enumerate([-0.34, -0.17, 0.0, 0.17, 0.34]):
            ww = w*(0.4+0.6*e)
            z = 0.52 + 0.17*e*(1 - (w/0.34)**2*0.5) + 0.05*math.sin(i*1.9+k*1.3)
            row.append(bm.verts.new((ww+0.04*math.sin(i*1.3), t, z)))
        gg.append(row)
    for i in range(16):
        for k in range(4):
            bm.faces.new([gg[i][k], gg[i][k+1], gg[i+1][k+1], gg[i+1][k]])
    commit(bm, lambda p, n: mix((0.42, 0.74, 0.30), (0.70, 0.90, 0.46), sstep(0.5, 0.75, p.z)), mods=[('SOLIDIFY', dict(thickness=0.03, offset=0))], sharp=90)
    # tomato cubes & cheese shreds
    for k, (y, x, z) in enumerate([(-0.4, 0.1, 0.62), (0.0, -0.12, 0.68), (0.3, 0.1, 0.66), (-0.1, 0.16, 0.56)]):
        bm = bmesh.new(); bmesh.ops.create_cube(bm, size=0.15)
        commit(bm, (0.92, 0.26, 0.22), mods=[('BEVEL', dict(width=0.04, segments=1))], sharp=70, xf=xf_rt((x, y, z), rotz=k*0.9, rotx=k*0.4))
    for k, (y, x, z, a) in enumerate([(-0.5, -0.1, 0.66, 0.4), (0.15, 0.0, 0.74, 1.4), (0.5, -0.05, 0.64, 2.2), (-0.15, 0.12, 0.72, 0.9)]):
        p0 = V((x-0.12*math.cos(a), y-0.12*math.sin(a), z)); p1 = V((x+0.12*math.cos(a), y+0.12*math.sin(a), z+0.02))
        tube(p0, p1, 0.028, 5, (1.0, 0.80, 0.22))

# ============================ DONUT ============================
def donut(v=0):
    Rm, rm, zs = 0.52, 0.27, 0.92
    nmaj, nmin = 24, 10
    def surf(rad, theta_fn, nm, steps, off_fn=lambda i, th: 0.0, z0=0.0):
        pass
    bm = bmesh.new(); g = []
    for i in range(nmaj):
        a = 2*math.pi*i/nmaj; row = []
        for k in range(nmin):
            th = 2*math.pi*k/nmin
            rr = Rm + rm*math.cos(th)
            row.append(bm.verts.new((rr*math.cos(a), rr*math.sin(a), rm*zs + rm*math.sin(th)*zs)))
        g.append(row)
    for i in range(nmaj):
        for k in range(nmin):
            bm.faces.new([g[i][k], g[(i+1) % nmaj][k], g[(i+1) % nmaj][(k+1) % nmin], g[i][(k+1) % nmin]])
    displace(bm, lambda p, n: 0.012*nz(p, 6.0, 1))
    def dc(p, n):
        c = (0.93, 0.74, 0.44)
        c = mix(c, (0.80, 0.55, 0.27), sstep(0.2, -0.8, n.z)*0.9)
        return c
    commit(bm, dc, sharp=80)
    # icing
    def cut(i):
        a = 2*math.pi*i/nmaj*1.0
        return 1.02 + 0.22*math.sin(a*3+0.4)*0.6 + 0.17*math.sin(a*7+1.0)*0.5 + 0.1*math.sin(a*11) + (0.25 if (i % 9) == 3 else 0.0)
    ni = 32; ns = 5
    bm = bmesh.new(); g = []
    icing_surf = {}
    for i in range(ni):
        a = 2*math.pi*i/ni
        th_out = 1.04 + 0.2*math.sin(a*3+0.4) + 0.13*math.sin(a*7+1.0) + 0.07*math.sin(a*11) + (0.28 if (i % 13) == 4 else 0.0)
        th_in = 1.04 + 0.12*math.sin(a*4+1.1) + 0.1*math.sin(a*9)
        row = []
        # from inner edge (theta = pi/2 + th_in) over the top to outer edge (pi/2 - th_out)
        for k in range(ns+1):
            f = k/ns
            th = (math.pi/2 + th_in)*(1-f) + (math.pi/2 - th_out)*f
            fade = 1 - sstep(0.7, 1.0, abs(2*f-1))*0.0
            rad = rm*(1.0 + 0.085*(1 - (abs(2*f-1))**3) - 0.0)
            edge = sstep(0.0, 0.18, f)*sstep(1.0, 0.82, f)
            rad = rm*(1.0 + 0.09*edge)
            rr = Rm + rad*math.cos(th)
            row.append(bm.verts.new((rr*math.cos(a), rr*math.sin(a), rm*zs + rad*math.sin(th)*zs)))
        g.append(row)
    for i in range(ni):
        for k in range(ns):
            bm.faces.new([g[i][k], g[i][k+1], g[(i+1) % ni][k+1], g[(i+1) % ni][k]])
    pink = (0.98, 0.58, 0.72)
    def ic(p, n):
        c = mix(pink, (1.0, 0.8, 0.88), sstep(0.5, 1.0, n.z)*0.45)
        c = mix(c, (0.93, 0.46, 0.62), sstep(0.5, 0.0, n.z)*0.5)
        return c
    commit(bm, ic, sharp=80)
    # sprinkles
    r = random.Random(11)
    scol = [(1.0, 1.0, 1.0), (1.0, 0.92, 0.35), (0.45, 0.72, 1.0), (0.55, 0.88, 0.55), (1.0, 0.65, 0.3)]
    for k in range(10):
        a = r.uniform(0, 6.28); th = r.uniform(0.3, 1.5)*(1 if True else 1)
        rad = rm*1.09
        c0 = V(((Rm + rad*math.cos(math.pi/2-th*0.7))*math.cos(a), (Rm + rad*math.cos(math.pi/2-th*0.7))*math.sin(a), rm*zs + rad*math.sin(math.pi/2-th*0.7)*zs))
        # random tangent
        n = (c0 - V((Rm*math.cos(a), Rm*math.sin(a), rm*zs))).normalized()
        t1 = V((-math.sin(a), math.cos(a), 0)); t2 = n.cross(t1).normalized()
        ang = r.uniform(0, 6.28); d = (t1*math.cos(ang) + t2*math.sin(ang)).normalized()
        tube(c0 - d*0.085 + n*0.012, c0 + d*0.085 + n*0.012, 0.027, 6, scol[k % 5])

# ============================ ICE POP ============================
def popsicle(v=0):
    W, L, T = 0.46, 1.55, 0.42
    # outline: rounded rect, big radius at the far end (top of the pop = +y? keep the round end away from camera? stick to +y)
    pts = [(-W, -L/2), (W, -L/2), (W, L/2), (-W, L/2)]
    # rounded: small radius at the stick-side... top (round) end toward camera (-y)
    outl = []
    def arc(cx, cy, r, a0, a1, n=8):
        return [(cx+r*math.cos(a0+(a1-a0)*k/n), cy+r*math.sin(a0+(a1-a0)*k/n)) for k in range(n+1)]
    rb = 0.14; rt = 0.43
    outl += arc(-W+rb, L/2-rb, rb, math.pi/2, math.pi, 4)[::-1][::-1]
    # build ccw: start bottom-right
    outl = []
    outl += arc(W-rb, L/2-rb, rb, 0, math.pi/2, 4)            # stick side right-top ... (y=+ is away)
    outl += arc(-W+rb, L/2-rb, rb, math.pi/2, math.pi, 4)
    outl += arc(-W+rt, -L/2+rt, rt, math.pi, 1.5*math.pi, 8)
    outl += arc(W-rt, -L/2+rt, rt, 1.5*math.pi, 2*math.pi, 8)
    bm = slab(outl, 0.0, T, cuts=0)
    A = (1.0, 0.55, 0.24); B = (1.0, 0.93, 0.82); C = (0.98, 0.42, 0.62)
    def pc(p, n):
        t = (p.y + L/2)/L           # 0 round end .. 1 stick end
        c = mix(A, C, sstep(0.18, 0.62, t))
        c = mix(c, B, sstep(0.07, 0.04, abs(t-0.42)) )
        # glossy highlight stripe
        if n.z > 0.2: c = mix(c, (1.0, 1.0, 0.98), sstep(0.09, 0.0, abs(p.x+0.2))*sstep(0.05, 0.3, t)*sstep(0.95, 0.7, t)*0.45)
        c = mix(c, (c[0]*0.93, c[1]*0.9, c[2]*0.92), sstep(0.5, 0.0, n.z)*0.5)
        return c
    commit(bm, pc, mods=[('BEVEL', dict(width=0.16, segments=4, limit_method='ANGLE', angle_limit=math.radians(35)))], sharp=60, xf=xf_rt((0, 0, 0)))
    # stick
    so = []
    so += arc(0.1, 0.0, 0.1, 0, math.pi, 5)
    so += [(-0.1, 0.0)] + [(-0.1, 0.0)]
    so = [(0.1, 0.4), (-0.1, 0.4)]
    so = arc(0.0, 0.95, 0.1, 0.0, math.pi, 6) + [(-0.1, 0.35), (0.1, 0.35)]
    bm = slab(so, 0.12, 0.2, cuts=0)
    commit(bm, lambda p, n: mix((0.95, 0.82, 0.58), (0.85, 0.66, 0.42), sstep(0.2, 0.6, nz(V((p.x*40, p.y*3, p.z*40)), 1.0)*0.5+0.5)*0.6),
           mods=[('BEVEL', dict(width=0.018, segments=1, limit_method='ANGLE', angle_limit=math.radians(40)))], sharp=60, xf=xf_rt((0, L/2-0.9+0.9-0.0, 0)))
    # drip
    bm = ico(2, 1.0)
    move(bm, lambda p: (p.x*0.09, p.y*0.11, p.z*0.07))
    commit(bm, C, sharp=80, xf=xf_rt((0.2, -L/2+0.55, 0.0)))

# ============================ ONIGIRI ============================
def tri_r(th):
    # radial distance of a rounded triangle (tip +y, flat base at y = -0.5), width +-0.76
    P = [V((0.0, 0.88)), V((-0.76, -0.5)), V((0.76, -0.5))]
    d = V((math.cos(th), math.sin(th)))
    best = 9
    for i in range(3):
        a = P[i]; b = P[(i+1) % 3]; e = b-a
        den = d.x*e.y - d.y*e.x
        if abs(den) < 1e-6: continue
        t = (a.x*e.y - a.y*e.x)/den*-1
        # solve a + s e = t d
        s = (d.x*a.y - d.y*a.x)/(d.y*e.x - d.x*e.y) if False else None
        # cramer
        det = d.x*(-e.y) - d.y*(-e.x)
        if abs(det) < 1e-9: continue
        tt = (a.x*(-e.y) - a.y*(-e.x))/det
        ss = (d.x*a.y - d.y*a.x)/det
        if tt > 0 and -1e-6 <= ss <= 1+1e-6: best = min(best, tt)
    return best

def onigiri(v=0):
    # triangle centroid offset: shift so that centre is origin
    H = 0.40
    bm = ico(4)
    cy = (0.88-0.5-0.5)/3
    def f(p):
        d = V(p).normalized()
        s = math.sqrt(max(0.0, 1-d.z*d.z))
        if s < 1e-6: return (0, 0, math.copysign(H, d.z))
        th = math.atan2(d.y, d.x)
        rt = tri_r(th)
        rr = rt*0.62 + 0.70*0.38*1.0          # soften toward round
        x = d.x/s*math.pow(s, 0.52)*rr*0.97; y = d.y/s*math.pow(s, 0.52)*rr*0.97
        z = math.copysign(abs(d.z)**0.78, d.z)*H*(1.0 if d.z > 0 else 0.55)
        return (x, y - cy*0.0, z)
    move(bm, f)
    bm.normal_update()
    # nori band first (needs the clean normals): copy faces in front band
    nbm = bmesh.new()
    rice_snapshot = [(v_.co.copy(), v_.normal.copy()) for v_ in bm.verts]
    displace(bm, lambda p, n: 0.018*nz(p, 10.0, 1) + 0.012*(1-abs(nz(p, 22.0, 3))) + 0.008*nz(p, 5.0, 8))
    def thr(x): return -0.02 + 0.04*math.sin(x*6.0)
    # nori from the same surface
    for_nori = ico(4)
    move(for_nori, f)
    for_nori.normal_update()
    dele = []
    for face in for_nori.faces:
        c = face.calc_center_median()
        if c.y > thr(c.x) - 0.12 and False: dele.append(face)
        pass
    bmesh.ops.bisect_plane(for_nori, geom=for_nori.verts[:]+for_nori.edges[:]+for_nori.faces[:], plane_co=(0, -0.12, 0), plane_no=(0, 1, 0), clear_outer=True)
    for vv in for_nori.verts: vv.co += vv.normal*0.035
    def rc(p, n):
        c = (1.0, 0.99, 0.95)
        s = nz(p, 24.0, 2)
        c = mix(c, (0.90, 0.88, 0.80), sstep(-0.1, -0.8, s)*0.7)
        c = mix(c, (1.0, 1.0, 1.0), sstep(0.3, 0.8, s)*0.4)
        c = mix(c, (0.93, 0.90, 0.82), sstep(0.4, -0.6, n.z)*0.6)
        return c
    commit(bm, rc, mods=[('DECIMATE', dict(ratio=0.5))], sharp=70)
    commit(for_nori, lambda p, n: mix((0.12, 0.19, 0.16), (0.2, 0.28, 0.23), sstep(0.0, 0.8, nz(p, 9.0, 1)*0.5+0.5)*0.5), mods=[('DECIMATE', dict(ratio=0.5))], sharp=70)
    # umeboshi dab + sesame on the top
    bm = ico(2, 1.0)
    move(bm, lambda p: (p.x*0.15, p.y*0.12, p.z*0.06))
    commit(bm, (0.86, 0.26, 0.36), sharp=80, xf=xf_rt((0.0, 0.34, H*0.95)))
    r = random.Random(4)
    for k in range(5):
        a = r.uniform(0, 6.28); rr = r.uniform(0.0, 0.3)
        bm = ico(1, 1.0); move(bm, lambda p: (p.x*0.034, p.y*0.02, p.z*0.016))
        commit(bm, (0.1, 0.1, 0.1), sharp=80, xf=xf_rt((rr*math.cos(a)*0.9, 0.1+rr*math.sin(a)*0.9, H*0.97), rotz=a))
    rotate_parts(Matrix.Rotation(math.radians(82), 4, 'X'))

def rotate_parts(M):
    from lib import PARTS
    M3 = M.to_3x3()
    for part in PARTS:
        part['P'] = [tuple(M @ V(p)) for p in part['P']]
        part['N'] = [tuple((M3 @ V(n)).normalized()) for n in part['N']]

# ============================ COOKIE ============================
def cookie(v=0):
    H = 0.30
    bm = ico(4); r = random.Random(8)
    ph = [r.uniform(0, 6.28) for _ in range(5)]
    def f(p):
        d = V(p).normalized(); s = math.sqrt(max(0.0, 1-d.z*d.z))
        th = math.atan2(d.y, d.x)
        rr = 0.68*(1 + 0.04*math.sin(3*th+ph[0]) + 0.035*math.sin(5*th+ph[1]) + 0.02*math.sin(8*th+ph[2]))
        if s < 1e-6: return (0, 0, H)
        x = d.x/s*math.pow(s, 0.45)*rr; y = d.y/s*math.pow(s, 0.45)*rr
        z = math.copysign(abs(d.z)**0.9, d.z)*H*(1.0 if d.z > 0 else 0.5)
        return (x, y, z)
    move(bm, f)
    def bump(p, n):
        if n.z < 0.3: return 0.01*nz(p, 6.0)
        crack = abs(nz(p, 3.2, 4))
        return 0.035*nz(p, 6.0, 1) + 0.014*nz(p, 14.0, 2) - 0.05*sstep(0.09, 0.0, crack)
    displace(bm, bump)
    def cc(p, n):
        d = math.hypot(p.x, p.y)
        c = mix((0.95, 0.76, 0.46), (0.80, 0.53, 0.25), sstep(0.35, 0.68, d))
        c = mix(c, (0.72, 0.45, 0.2), sstep(0.2, -0.5, n.z)*0.8)
        if abs(nz(p, 3.2, 4)) < 0.07 and n.z > 0.3: c = mix(c, (0.9, 0.7, 0.42), 0.0) ; c = mix(c, (0.99, 0.84, 0.58), 0.5)
        if nz(p, 16.0, 7) > 0.45: c = mix(c, (0.99, 0.85, 0.6), 0.35)
        return c
    commit(bm, cc, mods=[('DECIMATE', dict(ratio=0.5))], sharp=70, xf=xf_rt((0, 0, 0.0)))
    chips = [(-0.30, 0.22, 0.17), (0.2, 0.34, 0.15), (0.38, -0.12, 0.17), (-0.05, -0.3, 0.16), (0.02, 0.0, 0.18), (-0.42, -0.14, 0.14), (0.22, -0.40, 0.12), (-0.14, 0.5, 0.11)]
    for k, (x, y, s) in enumerate(chips):
        bm = bmesh.new(); bmesh.ops.create_cube(bm, size=1.0)
        rr = random.Random(30+k)
        move(bm, lambda p: (p.x*s*1.4*(1+0.2*rr.uniform(-1, 1)), p.y*s*1.3*(1+0.2*rr.uniform(-1, 1)), p.z*s*0.8))
        dist = math.hypot(x, y)
        zt = H*(1 - (dist/0.68)**2)**0.45*0.94 + 0.012
        def chc(p, n, k=k):
            return mix((0.31, 0.18, 0.12), (0.48, 0.30, 0.21), sstep(0.5, 1.0, n.z)*0.8)
        commit(bm, chc, mods=[('BEVEL', dict(width=0.035, segments=1, limit_method='NONE'))], sharp=60, xf=xf_rt((x, y, zt), rotz=k*1.1, rotx=rr.uniform(-.15, .15), roty=rr.uniform(-.15, .15)))

BUILD = dict(nuggets=nugget, fries=fries, sushi=sushi, sandwich=sandwich, minipizza=pizza, taco=taco, donut=donut, popsicle=popsicle, onigiri=onigiri, cookie=cookie)
