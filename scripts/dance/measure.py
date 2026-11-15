# Onset strength per half-beat slot.
# low = 30-150 Hz, mid = 150-2000 Hz (extra, used only for the "no split" fallback), high = 2-12 kHz.
# envelope = |band-passed|, low-passed (80/150/300 Hz); rise(t) = env(t+15ms) - env(t-25ms) (attack height);
# slot value = max rise within +-40 ms of the slot; divided by the song's own 90th percentile over all slots (1.0 = typical strong hit).
# jump_db = broadband level of [t, t+50ms] minus level of [t-60ms, t-10ms] (a "did anything hit here" check); level_db = broadband level [t, t+50ms].
import numpy as np
from scipy import signal
from common import *
def env(m,sr,lo,hi,lp):
    sos=signal.butter(4,[lo,hi],'band',fs=sr,output='sos'); y=signal.sosfilt(sos,m)
    return signal.sosfilt(signal.butter(2,lp,'low',fs=sr,output='sos'),np.abs(y))
def rise(e,sr):
    a=int(.015*sr); b=int(.025*sr); r=np.zeros_like(e); r[b:len(e)-a]=e[b+a:]-e[:len(e)-a-b]; return np.maximum(r,0)
def measure(n,win=0.04):
    g=SONGS[n]; x,sr=load(n); m=x.mean(1)
    rs=[rise(env(m,sr,30,150,80),sr),rise(env(m,sr,150,2000,150),sr),rise(env(m,sr,2000,12000,300),sr)]
    ns=2*g['last']+1; out=[]
    for r in rs:
        v=[]
        for s in range(ns):
            c=int(round(slot_t(n,s)*sr)); w=int(win*sr); v.append(r[max(c-w,0):c+w+1].max())
        v=np.array(v); out.append(v/np.percentile(v,90))
    lv=[];jp=[]
    for s in range(ns):
        a=int(slot_t(n,s)*sr); w=int(.05*sr)
        e1=np.sqrt(np.mean(m[a:a+w]**2)+1e-12); e0=np.sqrt(np.mean(m[max(a-int(.06*sr),0):a-int(.01*sr)]**2)+1e-12)
        lv.append(20*np.log10(e1+1e-9)); jp.append(20*np.log10(e1/e0))
    out+= [np.array(jp),np.array(lv)]
    return np.array(out)   # rows: low, mid, high, jump_db, level_db
if __name__=="__main__":
    for n,g in SONGS.items():
        M=measure(n); np.save(f"meas_{n}.npy",M)
        with open(f"measure_{n}.txt","w") as f:
            f.write(f"# song {n} {g['title']}; grid first {g['fb']} period {g['per']}; slot = half beats from beat 0 (even = on the beat)\n# low (<150 Hz), mid (150-2k, extra), high (>2 kHz): onset height / the song's own 90th percentile (1.0 = a typical strong hit); jump_db, level_db = broadband check\nslot\ttime_s\tlow\tmid\thigh\tjump_db\tlevel_db\n")
            for s in range(M.shape[1]): f.write(f"{s}\t{slot_t(n,s):.4f}\t{M[0,s]:.2f}\t{M[1,s]:.2f}\t{M[2,s]:.2f}\t{M[3,s]:.1f}\t{M[4,s]:.1f}\n")
