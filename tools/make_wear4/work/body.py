"""Port of BobForm (Contracts.swift, LOCKED body) to numpy. Rest space: y up, floor y=0, +z = face, symmetric in x. World units."""
import numpy as np, math
lift=0.1039; bodyH=1.2419; top=lift+bodyH; halfW=0.5836; halfD=0.5200
front=dict(tw=0.4828,ratio=0.4089,pb=2.8358,pt=2.1049); side=dict(tw=0.4167,ratio=0.3954,pb=2.1793,pt=2.1664)
def unit(t,p):
    t=np.asarray(t,float); out=np.zeros_like(t)
    u0=(1-p['ratio']**p['pb'])**(1/p['pb']); A=p['tw']/u0
    lo=t<=p['tw']; u=(p['tw']-t)/A
    out=np.where(lo,np.maximum(0,1-np.abs(u)**p['pb'])**(1/p['pb']),0.0)
    s=(t-p['tw'])/(1-p['tw'])
    out=np.where(~lo,np.maximum(0,1-np.abs(s)**p['pt'])**(1/p['pt']),out)
    return out
_T=np.linspace(0,1,4097); _A=halfW*unit(_T,front); _C=halfD*unit(_T,side)
def halfWidth(t): return np.interp(np.clip(t,0,1),_T,_A)
def halfDepth(t): return np.interp(np.clip(t,0,1),_T,_C)
armTop=np.array([0.517,0.605,0.06]); armTip=np.array([0.55,0.46,0.06]); armTopR=0.058; armTipR=0.15; armFlatten=1.15
armC=np.array([0.545,0.4516,0.07])
footX=0.2154; footZ=0.075; footRadii=np.array([0.155,0.18,0.135])
armBlend=0.04; armTipBlend=0.02; footBlend=0.045; bellyRise=0.0306
footToeLen=0.185; footToeSpring=0.006; footToeFrom=0.45; footHeelTop=0.260; footToeTop=0.104; footExpXZ=2.1; footExpY=2.6; footEdge=0.02
eyeX=0.215; eyeY=0.82; eyeHalfW=0.0532; eyeHalfH=0.0623; browY=0.945; browHalfLen=0.069; browHalfThick=0.0115; browTilt=0.085
def smin(a,b,k):
    h=np.maximum(k-np.abs(a-b),0)/k; return np.minimum(a,b)-h*h*k*0.25
def bodySDF(x,y,z):
    t=(y-lift)/bodyH; a=np.maximum(halfWidth(t),1e-3); c=np.maximum(halfDepth(t),1e-3)
    rho=np.sqrt((x/a)**2+(z/c)**2); f=(rho-1)*np.minimum(a,c)
    q=np.minimum((x/0.389)**2+(z/0.341)**2,2.5); bottom=lift+bellyRise*q
    return np.maximum(f,np.maximum(bottom-y,y-top))
def roundCone(P,a,b,r1,r2):
    ba=b-a; l2=ba@ba; rr=r1-r2; a2=l2-rr*rr; il2=1/l2
    pa=P-a; y=pa@ba; z=y-l2
    w=pa*l2-y[...,None]*ba
    x2=(w*w).sum(-1); y2=y*y*l2; z2=z*z*l2
    k=np.sign(rr+1e-30)*rr*rr*x2
    c1=np.where(z<0,-1.0,1.0)*a2*z2>k; c2=np.where(y<0,-1.0,1.0)*a2*y2<k
    d1=np.sqrt(x2+z2)*il2-r2; d2=np.sqrt(x2+y2)*il2-r1; d3=(np.sqrt(x2*a2*il2)+y*rr)*il2-r1
    return np.where(c1,d1,np.where(c2,d2,d3))
def armSDF(x,y,z):
    a=np.array([armTop[0],armTop[1],armTop[2]*armFlatten]); b=np.array([armTip[0],armTip[1],armTip[2]*armFlatten])
    P=np.stack([x,y,z*armFlatten],-1); ba=b-a
    h=np.clip(((P-a)@ba)/(ba@ba),0,1)
    return roundCone(P,a,b,armTopR,armTipR)/math.sqrt(armFlatten),h
def s01(t): u=np.clip(t,0,1); return u*u*(3-2*u)
def footSole(z):
    v=np.where(z>=footZ,(z-footZ)/footToeLen,(z-footZ)/footRadii[2])
    t=np.clip((v-footToeFrom)/(1-footToeFrom),0,1.3); return footToeSpring*t*t
def footSDF(x,y,z):
    yy=y-footSole(z); v=np.where(z>=footZ,(z-footZ)/footToeLen,(z-footZ)/footRadii[2])
    taper=(1-0.20*s01(yy/0.13))*(1-0.08*s01((v-0.1)/0.9))
    u=(x-footX)/(footRadii[0]*taper); arch=s01((v+0.1)/1.1)
    tp=footHeelTop+(footToeTop-footHeelTop)*arch; hh=tp/2; cy=hh*0.8; w=(yy-cy)/hh
    kxz=(np.abs(u)**footExpXZ+np.abs(v)**footExpXZ)**(1/footExpXZ)
    kn=(kxz**footExpY+np.abs(w)**footExpY)**(1/footExpY)
    return -smin(-(kn-1)*0.10,yy,footEdge)
def sdf(x,y,z):
    x=np.asarray(x,float);y=np.asarray(y,float);z=np.asarray(z,float); ax=np.abs(x)
    ad,h=armSDF(ax,y,z); u=1-np.clip(h/0.55,0,1); k=armTipBlend+(armBlend-armTipBlend)*(u*u*(3-2*u))
    d=smin(bodySDF(x,y,z),ad,k); return smin(d,footSDF(ax,y,z),footBlend)
def sdf_pts(P):
    P=np.asarray(P,float); return sdf(P[...,0],P[...,1],P[...,2])
def grad(P,e=0.0015):
    P=np.asarray(P,float); g=np.zeros_like(P)
    for i in range(3):
        d=np.zeros(3); d[i]=e; g[...,i]=(sdf_pts(P+d)-sdf_pts(P-d))/(2*e)
    return g/np.maximum(np.linalg.norm(g,axis=-1,keepdims=True),1e-9)
def egg_grad(P,e=0.0015):
    P=np.asarray(P,float); g=np.zeros_like(P)
    f=lambda Q: bodySDF(Q[...,0],Q[...,1],Q[...,2])
    for i in range(3):
        d=np.zeros(3); d[i]=e; g[...,i]=(f(P+d)-f(P-d))/(2*e)
    return g/np.maximum(np.linalg.norm(g,axis=-1,keepdims=True),1e-9)
def egg_point(y,phi):
    """point on the egg surface at height y, angle phi (0=+x, pi/2=+z front)."""
    t=(y-lift)/bodyH; a=float(halfWidth(t)); c=float(halfDepth(t)); return np.array([a*math.cos(phi),y,c*math.sin(phi)])
def front_surface(x,y):
    lo,hi=0.0,1.2
    for _ in range(40):
        m=(lo+hi)/2
        if sdf(x,y,m)<0: lo=m
        else: hi=m
    return np.array([x,y,(lo+hi)/2])
