import wave, numpy as np
SONGS={1:dict(title="Bubble Pop Stage",fb=0.0202,per=0.50002,last=24),
       2:dict(title="Groove On The One",fb=0.0554,per=0.53578,last=24),
       3:dict(title="Pixel Party",fb=0.0188,per=0.50005,last=24),
       4:dict(title="Block Party",fb=0.0435,per=0.63159,last=16)}
def load(n):
    w=wave.open(f"s{n}.wav"); sr=w.getframerate()
    x=np.frombuffer(w.readframes(w.getnframes()),dtype=np.int16).reshape(-1,w.getnchannels()).astype(float)/32768
    return x,sr
def slot_t(n,s):
    g=SONGS[n]; return g['fb']+s*g['per']/2
