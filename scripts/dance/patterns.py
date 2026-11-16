import json, numpy as np
from common import *
HIT=0.55; JUMP=3.0
SPLIT={1:False,2:True,3:False,4:True}
def hit(M,s):   # strong hit at slot s?
    st=max(M[0,s],M[2,s]); return st>=0.75 or (st>=HIT and M[3,s]>=JUMP)
def foot_split(M,s):
    lo,hi=M[0,s],M[2,s]
    return 'L' if (lo>=HIT and lo>=hi-0.3) else 'R'
def old(n):
    g=SONGS[n]; return {b:('L' if (b-4)%2==0 else 'R') for b in range(4,g['last']+1)}
def fix_runs(P):   # never same foot >3 in a row: turn the weakest of the run into a rest (not used if not needed)
    return P
def build(n):
    g=SONGS[n]; M=np.load(f"meas_{n}.npy"); last=g['last']; notes=[]
    beats=list(range(4,last+1))
    P={}   # beat -> foot
    if SPLIT[n]:
        cand=[b for b in beats if hit(M,2*b)]
        for b in cand: P[b]=foot_split(M,2*b)
        if n==2: notes.append('song 2: the 5 rests (beats 6,10,14,18,22) are real gaps in the music (broadband level -18 to -20 dB vs -10 to -13 elsewhere, no onset). Strong bass pickups also fall a sixteenth before beats 2,6,10,14,18,22 (x.75 positions: 1.75, 5.75, 9.75, 13.75, 17.75, 21.75) i.e. between slots: they get no arrow.')
        if n==4:
            # every whole beat has a hit in song 4: take rests from the weakest clap beats (they are the quieter, odd beats)
            for b in (7,11,15): P.pop(b,None)   # the 4th beat of each bar (clap just before the next bar's kick)
            notes.append("song 4: every whole beat 4..16 has a measured hit; all 13 clap/kick values are ~equal (clap 0.96-1.11, kick 0.78-0.97); the 3 rests are a DESIGN CHOICE: the 4th beat of each bar (7, 11, 15) -> exception to 'rests only on weak slots'")
    else:
        acc={b:(M[0,2*b]+M[1,2*b]+M[2,2*b])/3 for b in beats}
        order=sorted([b for b in beats if b not in (4,last)],key=lambda b:acc[b])
        rests=[]
        for b in order:
            if len(rests)>=6: break
            if any(abs(b-r)<=1 for r in rests): continue
            rests.append(b)
        f=0
        for b in beats:
            if b in rests: continue
            P[b]='LR'[f%2]; f+=1
        notes.append(f"no bass/clap split (kick, hat and upbeat stab identical on every beat): feet alternate in prompt order; rests {sorted(rests)} = the 6 lowest-ranked beats by mean(low,mid,high) onset (spread only {min(acc.values()):.2f}..{max(acc.values()):.2f}, every beat is a full-strength hit) = DESIGN CHOICE, not a gap in the music. "+("Rest set changes with analysis window / without the mid band (sens.py): treat as arbitrary." if n==1 else "Rest set is identical for 30/40/50 ms windows with and without mid band (odd beats 7-15 + 21 are consistently a little weaker), but the difference is small."))
    # run limits for foot (same foot > 3 in prompt order) and rests (>2 in a row)
    def check(P):
        seq=[P[b] for b in sorted(P)]
        for i in range(len(seq)-3):
            if len(set(seq[i:i+4]))==1: return False
        return True
    # same foot > 3 in a row: turn the weakest hit of the run into a rest
    def runfix(P):
        while True:
            ks=sorted(P)
            for i in range(len(ks)-3):
                if len({P[k] for k in ks[i:i+4]})==1:
                    w=min(ks[i:i+4],key=lambda k:max(M[0,2*k],M[2,2*k]) if k not in (last,) else 9)
                    del P[w]; notes.append(f"beat {w}: same foot 4x in a row -> rest"); break
            else: return
    runfix(P)
    assert check(P),(n,P)
    calm=dict(P)
    # lively: add off-beat prompts, <=1 per bar (bars start at beat 4), strongest first
    live=dict((float(b),f) for b,f in calm.items())
    half=g['per']/2
    cands=[]
    for b in range(4,last):
        s=2*b+1
        if SPLIT[n]: ok=hit(M,s); strength=max(M[0,s],M[2,s])
        else: ok=(M[3,s]>=3.2 and M[1,s]>=0.6); strength=M[1,s]+M[3,s]/10
        if ok: cands.append((strength,b))
    bars={}
    for st,b in sorted(cands,reverse=True):
        bar=(b-4)//4
        if bar in bars: continue
        # no triples when half beat < 0.3 s: both neighbours prompts -> skip
        if half<0.3 and (b in calm) and ((b+1) in calm): continue
        bars[bar]=b
    for bar,b in bars.items():
        s=2*b+1
        if SPLIT[n]: ft=foot_split(M,s)
        else:
            prev=max([x for x in live if x<b+0.5]); ft='R' if live[prev]=='L' else 'L'
        live[b+0.5]=ft
    # fallback alternation re-pass for the no-split songs (alternate over the whole prompt order)
    if not SPLIT[n]:
        for i,k in enumerate(sorted(live)): live[k]='LR'[i%2]
    ks=sorted(live)
    for i in range(len(ks)-3):
        if len({live[k] for k in ks[i:i+4]})==1: raise SystemExit(f'run in lively {n}')
    return calm,{k:live[k] for k in sorted(live)},notes
def stats(P,n):
    g=SONGS[n]; ks=sorted(P); ts=[g['fb']+k*g['per'] for k in ks]
    seq=[P[k] for k in ks]
    rests=[]; run=0
    for b in range(4,g['last']+1):
        if float(b) in P or b in P: 
            rests.append(run); run=0
        else: run+=1
    rests.append(run)
    gaps=[b-a for a,b in zip(ts,ts[1:])]
    return dict(prompts=len(ks),lefts=seq.count('L'),rights=seq.count('R'),rests=sum(1 for b in range(4,g['last']+1) if b not in P and float(b) not in P),longest_rest=max(rests),shortest_gap_s=round(min(gaps),4))
def line(P,n):
    g=SONGS[n]; out=[]
    for b in range(4,g['last']+1):
        if (b-4)%4==0 and b>4: out.append('|')
        out.append(P.get(float(b),P.get(b,'.')))
        if float(b)+0.5 in P: out.append(P[float(b)+0.5].lower())
    return ' '.join(out)
if __name__=="__main__":
    res={}
    for n,g in SONGS.items():
        o=old(n); calm,live,notes=build(n)
        res[n]=dict(title=g['title'],grid=dict(first_beat_s=g['fb'],period_s=g['per'],last_beat=g['last']),notes=notes)
        for name,P in (('old',{float(b):f for b,f in o.items()}),('calm',{float(b):f for b,f in calm.items()}),('lively',live)):
            ks=sorted(P)
            res[n][name]=dict(prompts=[dict(slot=int(round(k*2)),time_s=round(g['fb']+k*g['per'],4),foot=P[k]) for k in ks],counts=stats(P,n),line=line(P,n))
            print(n,name.ljust(7),line(P,n),res[n][name]['counts'])
        print(' ',notes)
    json.dump(res,open('patterns.json','w'),indent=1)
