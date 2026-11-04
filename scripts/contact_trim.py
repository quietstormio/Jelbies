#!/usr/bin/env python3
"""contact_trim.py <out> <scene> <angle> <secs>: frames -> <out>/<scene>_frames.mp4, cut to the emote (start -0.5 s .. end +2 s) when the demolog has
startEpoch / endEpoch and the test wrote <scene>.t0; the whole capture otherwise. perp / top clips are cropped to the centred band the camera tracks."""
import sys, os, re, glob, shutil, subprocess, tempfile
out, scene, angle, secs = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
d = f"{out}/{scene}"
frames = sorted(glob.glob(d + "/f_*.png"))
if not frames: sys.exit("no frames")
ms = lambda p: int(re.search(r"f_(\d+)\.png", p).group(1))
lo, hi = 0, 10**9
try:
    t0 = float(open(f"{out}/{scene}.t0").read())
    log = open(f"{out}/{scene}.demolog").read()
    s = re.findall(r"startEpoch=([\d.]+)", log); e = re.findall(r"endEpoch=([\d.]+)", log)
    if s:
        st = float(s[-1])
        tk = [(float(a), float(b)) for a, b in re.findall(r"tick t=([\d.]+) ph=-?\d+ d=([\d.]+)", log)]
        touch = [t for t, dd in tk if dd <= 1.55]          # the touching window starts when two of them are within ~1.55 u (touch distance 1.405)
        if touch: st = touch[0]; print(f"touching from {touch[0]-t0:.1f} s (session start {float(s[-1])-t0:.1f} s)")
        lo = int((st - t0 - 0.5) * 1000)
        lie = [(float(a), b) for a, b in re.findall(r" lie t=([\d.]+) (.*)", log)]          # lie-down: the demo logs each Jelbie's idle kind every 0.5 s -> cut to 1.5 s after the last one is up again
        isLying = lambda b: "[lieDown" in b or "[flop" in b          # (flop = the quick plop-down pair, same clearance)
        up = [a for a, b in lie if not isLying(b)]
        lying = [a for a, b in lie if isLying(b)]
        if lying and up and max(up) > max(lying): hi = int((st - t0 + max(lying) + 1.5) * 1000)
        if e: hi = int((float(e[-1]) - t0 + 2) * 1000)          # (no endEpoch = a lie-down / sleep pile: keep to the end of the capture)
except Exception as ex:
    print("trim: whole clip,", ex)
try: open(f"{out}/{scene}.clipstart", "w").write(f"{max(lo, 0) / 1000:.3f}")          # (scene seconds at the clip start: the sheet's time labels)
except Exception: pass
sel = [f for f in frames if lo <= ms(f) <= hi] or frames
dur = max((ms(sel[-1]) - ms(sel[0])) / 1000, 0.5)
fps = max(len(sel) / dur, 1)
tmp = tempfile.mkdtemp()
for i, f in enumerate(sel): os.symlink(f, f"{tmp}/{i:05d}.png")
vf = ("crop=iw:ih*0.42:0:ih*0.25,scale=1206:-2" if angle == "top" else "crop=iw:ih*0.36:0:ih*0.32,scale=1206:-2") if angle in ("perp", "top") else "crop=iw:ih*0.5:0:ih*0.2,scale=-2:900"
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", f"{fps:.3f}", "-i", f"{tmp}/%05d.png", "-vf", vf, "-pix_fmt", "yuv420p", f"{out}/{scene}_frames.mp4"], stdin=subprocess.DEVNULL)
shutil.rmtree(tmp)
print(f"{scene}: {len(sel)} frames, {dur:.1f} s real time (kept {lo/1000:.1f}..{hi/1000 if hi<10**9 else secs:.1f} s)")
# the measured skin gaps (ContactDemo.GapLog, cm, + apart): one summary line per cast pair, printed next to the clip so numbers and frames are reviewed together
try:
    for m in re.finditer(r" summary (pair=\S+) touchTicks=(\d+) holdPh=(-?\d+) holdTicks=(\d+) \((\S+)\) minGapFeat=(\S+) minGapBody=(\S+) medHoldFeat=(\S+) medHoldBody=(\S+) cm", open(f"{out}/{scene}.demolog").read()):
        print(f"{scene} SUMMARY {m[1]}: min gap over touching {m[6]} cm with features / {m[7]} body only; median over the hold ({m[5]}, phase {m[3]}, {m[4]} ticks at 0.2 s, of {m[2]} touching) {m[8]} / {m[9]} cm")
except Exception as ex:
    print("no gap summary:", ex)
