from wl import *
UP=np.array([0,1,0.])
def axes(n):
    n=np.array(n,float); n/=np.linalg.norm(n); x=np.cross(UP,n); x/=np.linalg.norm(x); y=np.cross(n,x); return x,y,n
def fz(x,y): return B.front_surface(x,y)

# ======================= FACE: glasses ===================================
FACE_ANCHOR=tuple(float(v) for v in B.front_surface(0.0,B.eyeY))
def _eye_frames(stand):
    out=[]
    for s in (-1,1):
        c=B.front_surface(s*B.eyeX,B.eyeY-0.006); n=full_n(c); x,y,n=axes(n); out.append((s,c+n*stand,x,y,n))
    return out
def _bridge_and_temples(frames,rad,col,stand,ring_r,y_br=0.835):
    # bridge: arc between inner edges, conforming to the face
    pts=[]
    xi=B.eyeX-ring_r*0.93
    for t in np.linspace(-1,1,9):
        x=t*xi; p=B.front_surface(x,y_br+0.022*(1-t*t)); pts.append(p+full_n(p)*(stand+0.002))
    tube_curve('bridge',pts,rad,5,col,flat=1.0)
    for s in (-1,1):
        s_,c,x,y,n=[f for f in frames if f[0]==s][0]
        outer=c+x*(ring_r*0.98*s)
        # temple: from the outer rim hug the egg round to the side
        ph0=math.atan2(outer[2]/float(B.halfDepth((outer[1]-B.lift)/B.bodyH)), outer[0]/float(B.halfWidth((outer[1]-B.lift)/B.bodyH)))
        pts=[outer]
        for ph in np.linspace(ph0,math.radians(6) if s>0 else math.radians(174),6):
            p=B.egg_point(outer[1]-0.004,ph); pts.append(p+egg_n(p)*0.026)
        if s<0: pass
        tube_curve('temple%+d'%s,pts,rad*0.9,5,col,flat=1.0)

def round_glasses(frame=HONEY,**k):
    reset(); R=0.091; stand=0.05
    fr=_eye_frames(stand)
    for s,c,x,y,n in fr:
        pts=[c+(x*math.cos(a)+y*math.sin(a))*R for a in np.linspace(0,2*math.pi,25)]
        tube_curve('rim%+d'%s,pts,0.0145,5,lambda p,nn: mix(deep(frame,0.12),tint(frame,0.1),0.5+0.5*nn[1]),cap=False)
        # little hinge studs
        ico_part('stud%+d'%s,tuple(c+x*(R*s)),(0.021,0.021,0.021),deep(frame,0.2),sub=1)
    _bridge_and_temples(fr,0.0105,frame,stand,R)
    return dict(anchor='face',slot='face',tags=['cool','cute'],price=40,title='Round glasses',
      desc='Round honey-frame glasses; frames only (no lens fill) so the eyes stay readable. Stand-off 0.05 in front of the eye beads.')

def star_shades(frame=PINK,lens=INK,**k):
    reset(); stand=0.052
    fr=_eye_frames(stand)
    for s,c,x,y,n in fr:
        def mk(Rr,rr,t0,t1,colr,nm,rad):
            sp=star_poly(Rr,rr,5,rot=math.pi/2+math.pi/5,rad=rad)
            slab_part(nm,sp,t1-t0,colr,lambda px,py,pz: tuple(c+x*px+y*py+n*(pz+t0)),cuts=0,sharp=35)
        mk(0.128,0.074,-0.014,0.012,frame,'frame%+d'%s,0.022)
        mk(0.108,0.060,0.006,0.020,lambda p,nn: mix(lens,LAV,0.25*max(0,nn[1])),'lens%+d'%s,0.018)
    # glints on the lenses
    for s,c,x,y,n in fr:
        ico_part('glint%+d'%s,tuple(c+x*(-0.03)+y*0.035+n*0.022),(0.016,0.008,0.004),CREAM,sub=1,rot=np.stack([x,y,n],1).tolist())
    _bridge_and_temples(fr,0.0125,frame,stand,0.095,y_br=0.845)
    return dict(anchor='face',slot='face',tags=['cool','sparkly'],price=60,title='Star sunglasses',
      desc='Pink star-shaped sunglasses with dark lenses and a cream glint. Opaque lenses: they cover the eyes, so Swift should fade them while he sleeps / a mouth is shown.')

# ======================= NECK =====================================================
NECK_Y=0.47
NECK_ANCHOR=tuple(float(v) for v in B.front_surface(0.0,NECK_Y))
def bow_tie(main=PINK,knot=None,dots=CREAM,**k):
    reset(); knot=knot or deep(main,0.2)
    c=B.front_surface(0,NECK_Y); x,y,n=axes(full_n(c)); ctr=c+n*0.032
    outline=lib.poly_pts_rounded([(0.018,0.0),(0.17,0.085),(0.17,-0.085)],0.03,arc=4)
    for s in (-1,1):
        def xf(px,py,pz,s=s):
            bulge=0.04*math.sin(math.pi*min(1,max(0,(px-0.0)/0.17)))*(1-abs(py)/0.1)**0.5 if abs(py)<0.1 else 0
            return tuple(ctr+x*(s*px)+y*py+n*(pz+bulge-0.008))
        slab_part('wing%+d'%s,outline,0.018,lambda p,nn: mix(main,tint(main,0.18),max(0,0.5+0.5*nn[2])*0.0+0.0),xf,cuts=1,sharp=40)
        ico_part('dot%+d'%s,tuple(ctr+x*s*0.1+y*0.03+n*0.03),(0.014,0.014,0.007),dots,sub=1)
        ico_part('dotb%+d'%s,tuple(ctr+x*s*0.12+y*(-0.03)+n*0.026),(0.012,0.012,0.007),dots,sub=1)
    ico_part('knot',tuple(ctr+n*0.012),(0.038,0.04,0.034),knot,sub=2,rot=np.stack([x,y,n],1).tolist())
    return dict(anchor='neck',slot='neck',tags=['cute','cool'],price=30,title='Bow tie',
      desc='Fat bow tie pinned to the front at y=0.47, below the mouth keep-out zone (the open mouth reaches down to y~0.59).')

def bandana(main=CORAL,dots=CREAM,trim=CREAM,**k):
    reset()
    yc=0.515; nx=17; X0=0.46
    def band_pt(i,j):
        x=-X0+2*X0*i/(nx-1); taper=1-abs(x/X0)**5
        y=yc+0.022*(x/X0)**2+(j/3-0.5)*0.062*taper; off=0.025+0.012*(1-abs(j-1.5)/1.5)*taper
        p,n=body_pt(x,y,off); return p
    grid_surface('band',band_pt,nx,4,main,closed_u=False,hint=lambda p:full_n(p))
    nu,nv=9,7; y_top=yc-0.012; y_tip=0.275; hw=0.205
    def tri_pt(i,j):
        v=j/(nv-1); u=(i/(nu-1))*2-1; y=y_tip+(y_top-y_tip)*v; w=hw*v
        x=u*w; p,n=body_pt(x,y,0.030+0.012*math.sin(math.pi*(1-abs(u))*0.5)*v); return p
    grid_surface('cloth',tri_pt,nu,nv,main,closed_u=False,hint=lambda p:full_n(p))
    for s_ in (-1,1):
        pts=[]
        for v in np.linspace(0,1,9):
            y=y_tip+(y_top-y_tip)*v; x=s_*hw*v*0.97; p,n=body_pt(x,y,0.040); pts.append(p)
        tube_curve('trim%+d'%s_,pts,0.0075,4,trim,cap=True,flat=1.0)
    for k_,(x,y) in enumerate(((0.0,0.44),(-0.07,0.42),(0.07,0.42),(0.0,0.37),(-0.035,0.325),(0.035,0.325),(0.12,0.47),(-0.12,0.47))):
        p,n=body_pt(x,y,0.043); xx,yy,nn=axes(n)
        ico_part(f'pd{k_}',tuple(p),(0.017,0.017,0.0065),dots,sub=1,rot=np.stack([xx,yy,nn],1).tolist())
    for s_ in (-1,1):
        p,n=body_pt(s_*0.445,yc+0.02,0.036); ico_part('knot%+d'%s_,tuple(p),(0.042,0.042,0.034),deep(main,0.12),sub=1)
    return dict(anchor='neck',slot='neck',tags=['cool','sporty'],price=25,title='Bandana',
      desc='Neckerchief: a short band across the front belly at y~0.515 (ends tuck in front of the arm roots at |x|=0.46) and a polka-dot triangle hanging to y 0.275. Entirely below the mouth keep-out zone.')

def medal(ribbon_a=SKY,ribbon_b=PINK,gold=HONEY,**k):
    reset(); n_pts=9
    # ribbon V: two strips from the sides of the chest converging at the medal
    cen=(0.0,0.50)
    for s in (-1,1):
        for half,(ca) in enumerate((ribbon_a,ribbon_b)):
            pass
    def strip(s):
        a=np.array([s*0.30,0.628]); b=np.array([s*0.02,0.495]); d=b-a; d/=np.linalg.norm(d); perp=np.array([-d[1],d[0]])
        for half,ca in ((0,ribbon_a),(1,ribbon_b)):
            def pt(i,j,half=half):
                t=i/(n_pts-1); w=(half*0.5+j*0.5-0.5)*0.05
                q=a+(b-a)*t+perp*w; p,nn=body_pt(q[0],q[1],0.022); return p
            grid_surface('ribbon%+d_%d'%(s,half),pt,n_pts,2,ca,closed_u=False,hint=lambda p:full_n(p))
    for s in (-1,1): strip(s)
    c=B.front_surface(0,0.425); x,y,n=axes(full_n(c)); mc=c+n*0.056
    R=np.stack([x,y,n],1)
    # medal disc: a lathe about local z -> build about y then rotate so its axis = n
    Rm=np.stack([x,n,-y],1)       # y-axis -> n
    prof=[(0.0,-0.012),(0.066,-0.012),(0.078,-0.006),(0.078,0.008),(0.066,0.016),(0.0,0.016)]
    lathe_y('disc',prof,28,lambda p,nn: mix(deep(gold,0.12),tint(gold,0.15),0.5+0.5*(nn[1])),centre=tuple(mc),rotm=Rm.tolist(),sharp=45)
    ring=[(0.0,0.0)]
    # inner ring + star
    sp=star_poly(0.046,0.021,5,rad=0.007)
    slab_part('star',sp,0.010,CREAM,lambda px,py,pz: tuple(mc+x*px+y*py+n*(0.016+pz-0.002)),cuts=0)
    # loop
    pts=[mc+y*0.078+x*0.0+n*0.0]; loop=[mc+y*(0.07+0.03*math.sin(a))+x*(0.022*math.cos(a)) for a in np.linspace(0,2*math.pi,9)]
    tube_curve('loop',loop,0.007,4,deep(gold,0.2),cap=False)
    return dict(anchor='neck',slot='neck',tags=['sporty','sparkly'],price=0,title='Winner medal',
      desc='Gold medal on a sky/pink ribbon. Earned only: awarded for a Circuit win (suggested shop price 80 if ever sold).',suggested_price_if_sold=80)

# ======================= HANDS: mitten glove (arm-local frame) =================
A_=np.array(B.armTop); B_=np.array(B.armTip)
_up=(A_-B_)/np.linalg.norm(A_-B_); _z=np.array([0,0,1.0]); _x=np.cross(_up,_z)
GLOVE_FRAME=np.stack([_x,_up,_z],1)    # columns = local x (outward), y (toward shoulder), z (forward) expressed in rest space
def glove(mitt=SKY,cuff=CREAM,stripe=PINK,**k):
    reset()
    sq=0.90
    prof=[(0.0,-0.160),(0.060,-0.154),(0.112,-0.130),(0.146,-0.088),(0.162,-0.040),(0.164,0.004),(0.156,0.046),(0.140,0.078),(0.130,0.092)]
    # bulb
    lathe_y('mitt',[(r,y) for r,y in prof],28,lambda p,n: mix(deep(mitt,0.10),tint(mitt,0.12),0.5+0.5*n[1]*0.5),scale=(1.0,sq),sharp=70)
    # thumb: bump hugging the front-inner side of the bulb
    d=np.array([-0.16,0.36,0.92]); d/=np.linalg.norm(d); c=d*0.118
    z=d; xax=np.cross(np.array([0,1,0.]),z); xax/=np.linalg.norm(xax); yax=np.cross(z,xax)
    ico_part('thumb',tuple(c),(0.048,0.062,0.046),lambda p,n: mix(deep(mitt,0.08),tint(mitt,0.14),0.5+0.5*n[1]*0.5),sub=2,rot=np.stack([xax,yax,z],1).tolist())
    # cuff (ribbed ring) + a thin stripe ring
    cp=[(0.112,0.060),(0.140,0.066),(0.152,0.082),(0.152,0.112),(0.146,0.132),(0.124,0.140),(0.108,0.136)]
    def ribs(p,n):
        a=math.atan2(p[2],p[0]); return mix(cuff,deep(cuff,0.14),0.30*(0.5-0.5*math.cos(12*a)))
    lathe_y('cuff',cp+[(0.0,0.136)],24,ribs,scale=(1.0,sq),sharp=60)
    lathe_y('stripe',[(0.1535,0.093),(0.1555,0.098),(0.1555,0.106),(0.1535,0.111)],24,stripe,scale=(1.0,sq),sharp=60)
    return dict(anchor='wrist',slot='hands',tags=['cute','sporty','sweet'],price=35,title='Mitten gloves',
      desc='Chunky mittens: a rounded mitt (max radius 0.164 = 1.09 x the 0.15 arm-end radius) with a ribbed cuff and a thumb bump kept inside 1.15 x. Authored for the +x arm in arm-local frame; mirror x for the -x arm.',
      anchor_rest=[float(v) for v in B_], authored_local=True,
      local_frame=dict(origin='arm tip centre B (BobForm.armTip for the +x arm at rest; the posed capsule tip B when posed)',
        x='outward across the arm (rest: (%.3f,%.3f,0))'%(_x[0],_x[1]), y='toward the shoulder = unit(A - B) (rest: (%.3f,%.3f,0))'%(_up[0],_up[1]), z='body forward (+z)',
        rest_matrix_columns=[[round(float(v),4) for v in GLOVE_FRAME[:,i]] for i in range(3)],
        scale='multiply mesh by (arm tip radius / 0.15); the cuff sits on the neck of the capsule 0.06..0.14 from B along +y'))

# ======================= BODY: bib, digits, sash ====================================
BIB_C=(0.0,0.355)
BIB_ANCHOR=tuple(float(v) for v in B.front_surface(*BIB_C))
def bib(field=CREAM,trim=SKY,**k):
    reset(); segs=32; hw,hh=0.20,0.125
    ctr=B.front_surface(*BIB_C)
    rings=[(1.0,0.0035,'trim'),(0.985,0.017,'trim'),(0.905,0.017,'trim'),(0.9045,0.0125,'field'),(0.55,0.0145,'field'),(0.0,0.0155,'field')]
    def pt(i,j):
        s,off,_=rings[j]; a=2*math.pi*i/segs
        c,sn=math.cos(a),math.sin(a)
        x=hw*s*np.sign(c)*abs(c)**0.5; y=BIB_C[1]+hh*s*np.sign(sn)*abs(sn)**0.5
        p,n=body_pt(x,y,off+0.004); return p
    def col(p,n):
        # field vs trim by distance to bib centre in x/y super-ellipse coords
        xn=abs(p[0]/hw); yn=abs((p[1]-BIB_C[1])/hh); r=(xn**4+yn**4)**0.25
        return trim if r>0.885 else field
    grid_surface('plate',pt,segs,len(rings),None,hint=lambda p:full_n(p),gcol=lambda i,j: trim if rings[j][2]=='trim' else field)
    # number anchor: where digit local origin goes
    nc,nn=body_pt(0.0,BIB_C[1]+0.0,0.0155+0.004)
    return dict(anchor='chest',slot='body',tags=['sporty'],price=20,title='Jersey bib (number plate)',
      desc='Rounded number plate pinned to the belly, coloured with the team colour; trim ring is cream. Digits are separate meshes (digit_0..digit_9) that Swift places on number_anchor.',
      number_anchor_rest=[round(float(v),4) for v in nc], number_height=0.18, number_normal=[round(float(v),4) for v in nn],
      plate_half_size=[hw,hh])

# ---- digits ---------------------------------------------------------------------
def catmull(pts,sub=6,closed=False):
    P=[np.array(p,float) for p in pts]; out=[]
    n=len(P)
    for i in range(n if closed else n-1):
        p0=P[(i-1)%n] if (closed or i>0) else P[0]; p1=P[i]; p2=P[(i+1)%n]; p3=P[(i+2)%n] if (closed or i+2<n) else P[-1]
        for t in np.linspace(0,1,sub,endpoint=False):
            out.append(0.5*((2*p1)+(-p0+p2)*t+(2*p0-5*p1+4*p2-p3)*t*t+(-p0+3*p1-3*p2+p3)*t**3))
    out.append(P[0] if closed else P[-1]); return out
def ell(cx,cy,rx,ry,n=14): return [(cx+rx*math.cos(a),cy+ry*math.sin(a)) for a in np.linspace(math.pi/2,math.pi/2+2*math.pi,n+1)]
DIG={
 0:[(ell(0.5,0.5,0.25,0.44,14),False)],
 1:[([(0.16,0.74),(0.46,0.95),(0.46,0.05)],False)],
 2:[([(0.1,0.74),(0.16,0.92),(0.38,0.97),(0.58,0.88),(0.62,0.7),(0.5,0.52),(0.1,0.07),(0.66,0.07)],True)],
 3:[([(0.1,0.9),(0.38,0.97),(0.58,0.86),(0.54,0.66),(0.3,0.54)],True),([(0.3,0.54),(0.6,0.42),(0.62,0.2),(0.4,0.04),(0.1,0.1)],True)],
 4:[([(0.55,0.05),(0.55,0.95),(0.07,0.3),(0.72,0.3)],False)],
 5:[([(0.6,0.95),(0.18,0.95),(0.12,0.55),(0.4,0.62),(0.6,0.45),(0.58,0.18),(0.36,0.04),(0.1,0.12)],True)],
 6:[([(0.58,0.93),(0.3,0.86),(0.12,0.56),(0.14,0.2),(0.36,0.04),(0.58,0.16),(0.58,0.4),(0.36,0.52),(0.14,0.4)],True)],
 7:[([(0.08,0.95),(0.64,0.95),(0.24,0.05)],False)],
 8:[(ell(0.5,0.73,0.2,0.21,12),False),(ell(0.5,0.27,0.25,0.23,12),False)],
}
def _rot180(strokes): return [([(1-x,1-y) for x,y in pts],sm) for pts,sm in strokes]
DIG[9]=_rot180(DIG[6])
def digit_old(d,col=CREAM,**k):
    reset()
    strokes=DIG[d]
    for si,(pts,smooth) in enumerate(strokes):
        if smooth is True: P=catmull(pts,5)
        elif smooth is False and len(pts)>3: P=catmull(pts,1) if False else [np.array(p) for p in pts]
        else: P=[np.array(p) for p in pts]
        if d in (0,8) : P=[np.array(p) for p in pts]
        if d in (1,4,7): P=catmull(pts,4) if False else [np.array(p) for p in pts]
        P3=[(p[0]-0.5,p[1]-0.5,0.0) for p in P]
        # subdivide straight segments a bit so the tube joins stay round
        tube_curve(f'stroke{si}',P3,0.125,8,col,cap=False,flat=0.5)
    for si,(pts,smooth) in enumerate(strokes):
        ends=pts if (d in (1,4,7)) else [pts[0],pts[-1]]
        for p in ends: ico_part(f'j{si}_{p[0]:.2f}_{p[1]:.2f}',(p[0]-0.5,p[1]-0.5,0.0),(0.125,0.125,0.0625),col,sub=2)
    return dict(anchor='number',slot='body',tags=['sporty'],price=0,title=f'Digit {d}',
      desc='Unit digit (height 1, width ~0.7, centred on its box, +z out of the plate, depth ~0.05); scale by number_height and tint by replacing vertex colours.',
      anchor_rest=[0,0,0])

def sash(field=SKY,trim=CREAM,star=PINK,**k):
    reset(); nL=15; W_=0.050
    a=np.array([-0.42,0.600]); b=np.array([0.42,0.225]); d=(b-a)/np.linalg.norm(b-a); perp=np.array([-d[1],d[0]])
    rows=[(-1.0,0.014),(-0.86,0.022),(-0.70,0.0235),(-0.6999,0.0235),(0.6999,0.0235),(0.70,0.0235),(0.86,0.022),(1.0,0.014)]
    def pt(i,j):
        t=i/(nL-1); w,off=rows[j]; q=a+(b-a)*t+perp*W_*w
        # taper both ends to a point-ish end
        p,n=body_pt(q[0],q[1],off); return p
    def col(p,n):
        # trim by distance from the centreline
        q=np.array([p[0],p[1]])-a; w=abs(np.dot(q,perp))/W_
        return trim if w>0.69995 else field
    grid_surface('band',pt,nL,len(rows),None,closed_u=False,hint=lambda p:full_n(p),gcol=lambda i,j: trim if abs(rows[j][0])>=0.70 else field)
    for k_,t in enumerate((0.2,0.5,0.8)):
        q=a+(b-a)*t; p,n=body_pt(q[0],q[1],0.030); xx,yy,nn=axes(n)
        sp=star_poly(0.030,0.0135,5,rad=0.005)
        # orient star along the sash
        ang=math.atan2(d[1],d[0])
        slab_part(f'star{k_}',sp,0.008,star,lambda px,py,pz,p=p,xx=xx,yy=yy,nn=nn,ang=ang: tuple(p+xx*(px*math.cos(ang)-py*math.sin(ang))+yy*(px*math.sin(ang)+py*math.cos(ang))+nn*(pz-0.002)),cuts=0)
    return dict(anchor='chest',slot='body',tags=['sporty','sparkly'],price=50,title='Racing sash',
      desc='Diagonal racing sash, upper left to lower right across the belly, with three stars. Cream piping, team-colour field. Ends stop at |x|=0.42; the whole sash is below the mouth keep-out zone. Ends stop at |x|=0.42 so they clear the arm bulbs.')

from digits_font import digit
H=(0.0,B.top,0.0)
REG=[
 ('glasses_round',round_glasses,dict(),FACE_ANCHOR),
 ('sunglasses_star',star_shades,dict(),FACE_ANCHOR),
 ('bowtie_pink',bow_tie,dict(main=PINK),NECK_ANCHOR),
 ('bowtie_sky',bow_tie,dict(main=SKY),NECK_ANCHOR),
 ('bandana_coral',bandana,dict(main=CORAL),NECK_ANCHOR),
 ('bandana_mint',bandana,dict(main=MINT),NECK_ANCHOR),
 ('medal_gold',medal,dict(),NECK_ANCHOR),
 ('glove_sky',glove,dict(mitt=SKY,cuff=CREAM,stripe=PINK),tuple(float(v) for v in B_)),
 ('glove_pink',glove,dict(mitt=PINK,cuff=CREAM,stripe=SKY),tuple(float(v) for v in B_)),
 ('bib_sky',bib,dict(field=CREAM,trim=SKY),BIB_ANCHOR),
 ('bib_pink',bib,dict(field=CREAM,trim=PINK),BIB_ANCHOR),
 ('sash_sky',sash,dict(field=SKY,star=PINK),BIB_ANCHOR),
 ('sash_pink',sash,dict(field=PINK,star=SKY),BIB_ANCHOR),
]+[(f'digit_{d}',digit,dict(d=d),(0,0,0)) for d in range(10)]
