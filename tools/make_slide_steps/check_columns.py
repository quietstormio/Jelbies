"""Phantom-solid check for decor_slide.bin: replays ClipProbe.Field's float32 column crossings and lists the 2 cm columns whose signed crossings do not cancel (z < 1.0 = the stair / deck; the chute tail has a few from before).
usage: check_columns.py decor_slide.bin"""
import sys,numpy as np
import struct
def load(path, scale=1.25):
    d = open(path, "rb").read()
    nv, ni, npart = struct.unpack_from("<III", d, 0); o = 12 + 40 * npart
    V = np.array([struct.unpack_from("<11f", d, o + 44 * i) for i in range(nv)], dtype=np.float64); o += 44 * nv
    I = np.array(struct.unpack_from("<%dH" % ni, d, o)).reshape(-1, 3)
    V[:, :3] *= scale
    return V, I
def bad_columns(path,h=0.02):
    V,I=load(path)
    P=V[:,:3].astype(np.float32);N=V[:,3:6].astype(np.float32);f32=np.float32;h=f32(h)
    lo=(P.min(0)-2*h).astype(np.float32);hi=(P.max(0)+2*h).astype(np.float32)
    n=(np.floor((hi-lo)/h)+1).astype(int);cols={}
    for t in I:
        a,b,c=P[t];nr=N[t].sum(0)
        if abs(nr[1])<1e-4: continue
        if abs(np.cross(b-a,c-a)[1])<1e-9: continue
        s=1 if nr[1]<0 else -1
        x0=max(0,int((min(a[0],b[0],c[0])-lo[0])/h));x1=min(n[0]-1,int((max(a[0],b[0],c[0])-lo[0])/h)+1)
        z0=max(0,int((min(a[2],b[2],c[2])-lo[2])/h));z1=min(n[2]-1,int((max(a[2],b[2],c[2])-lo[2])/h)+1)
        for zi in range(z0,z1+1):
            for xi in range(x0,x1+1):
                px=lo[0]+(f32(xi)+f32(.5))*h;pz=lo[2]+(f32(zi)+f32(.5))*h
                d=(b[2]-c[2])*(a[0]-c[0])+(c[0]-b[0])*(a[2]-c[2])
                if abs(d)<1e-12: continue
                l1=((b[2]-c[2])*(px-c[0])+(c[0]-b[0])*(pz-c[2]))/d
                l2=((c[2]-a[2])*(px-c[0])+(a[0]-c[0])*(pz-c[2]))/d
                l3=1-l1-l2
                if l1<0 or l2<0 or l3<0: continue
                cols[(xi,zi)]=cols.get((xi,zi),0)+s
    return [(round(float(lo[0]+(xi+.5)*h),3),round(float(lo[2]+(zi+.5)*h),3),w) for (xi,zi),w in cols.items() if w!=0]
if __name__=="__main__":
    b=bad_columns(sys.argv[1]);print(len(b),[x for x in b if x[1]<1.0])
