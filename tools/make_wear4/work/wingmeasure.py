#!/usr/bin/env python3
"""Lavender wing clearance vs a worn piece. Calibrated on the OLD scarf_cosy against the shipped feature_compat.json table, then applied to the new art."""
import json, struct, sys, subprocess, numpy as np, os
R=os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','..'))
def load_bin(b):
    vc,ic,pc=struct.unpack_from('<III',b,0); o=12; parts=[]
    for _ in range(pc):
        name=b[o:o+16].split(b'\0')[0].decode(); fi,icnt,mat=struct.unpack_from('<III',b,o+16); piv=struct.unpack_from('<fff',b,o+28); parts.append((name,fi,icnt)); o+=40
    V=np.frombuffer(b,dtype='<f4',count=vc*11,offset=o).reshape(vc,11)
    I=np.frombuffer(b,dtype='<u2',count=ic,offset=o+vc*44)
    return V[:,:3].astype(float),I,parts
def piece_world(obj_text,anchor):
    v=[[float(t[1])+anchor[0],float(t[2])+anchor[1],float(t[3])+anchor[2]] for t in (l.split() for l in obj_text.splitlines() if l.startswith('v '))]
    return np.array(v)
spec=json.load(open(R+'/BobV1/Features/Resources/feature_compat.json'))
wing=spec['wings']; anc=np.array(wing['anchor'])
WV,WI,WP=load_bin(open(R+'/BobV1/Features/Resources/feature_lav_a_final.bin','rb').read())
WV=WV+anc
def wing_pts(dy,flap,sign):
    out=[]
    for s,side in wing['sides'].items():
        names=side['parts']; idx=set()
        for (n,fi,ic) in WP:
            if n in names: idx|=set(WI[fi:fi+ic].tolist())
        P=WV[sorted(idx)]
        h=np.array(side['hinge']); ax=np.array(side['flapAxis']); ax/=np.linalg.norm(ax)
        a=np.radians(flap*sign); k=ax
        Q=P-h; Q=Q*np.cos(a)+np.cross(k,Q)*np.sin(a)+k*(Q@k)[:,None]*(1-np.cos(a))
        out.append(Q+h+np.array([0,dy,0]))
    return np.vstack(out)
def min_dist(piece,dy,flap,sign):
    W=wing_pts(dy,flap,sign)
    d=np.sqrt(((W[:,None,:]-piece[None,::2,:])**2).sum(2)).min()
    return d
def table(piece,tau,sign):
    res={}
    for dy in spec['dys']:
        ok=[f for f in range(-40,76,5) if min_dist(piece,dy,f,sign)>tau]
        res[dy]=(min(ok),max(ok)) if ok else None
    return res
if __name__=='__main__':
    old=subprocess.run(['git','-C',R,'show','361e09cf:tools/make_wear4/art/export/scarf_cosy.obj'],capture_output=True,text=True).stdout
    oj=json.loads(subprocess.run(['git','-C',R,'show','361e09cf:tools/make_wear4/art/export/scarf_cosy.json'],capture_output=True,text=True).stdout)
    P=piece_world(old,oj['anchor_rest'])
    want=spec['wingLimits']['scarf_cosy']
    best=None
    for sign in (1,-1):
        for tau in (0.0,0.005,0.01,0.015,0.02,0.03):
            t=table(P,tau,sign); err=0
            for dy in spec['dys']:
                w=want[('%.2f'%dy).replace('-0.00','0.0') if False else str(dy) if str(dy) in want else ('%g'%dy if '%g'%dy in want else str(float(dy)))] if False else None
            # compare ok/null pattern and bounds
            sc=0
            for dy in spec['dys']:
                key=[k for k in want if abs(float(k)-dy)<1e-6][0]; w=want[key]; m=t[dy]
                if (w is None)==(m is None): sc+=1
                if w is not None and m is not None: sc+=2-abs(w[0]-m[0])/40-abs(w[1]-m[1])/40
            if best is None or sc>best[0]: best=(sc,sign,tau,t)
    print('calibration best score',round(best[0],2),'sign',best[1],'tau',best[2]); print('model',best[3]); print('shipped',want)
    sign,tau=best[1],best[2]
    json.dump(dict(sign=sign,tau=tau),open(os.path.join(os.path.dirname(os.path.abspath(__file__)),'wingcal.json'),'w'))
