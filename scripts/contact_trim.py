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
        st = float(s[-1]); en = float(e[-1]) if e else st + 12
        lo, hi = int((st - t0 - 0.5) * 1000), int((en - t0 + 2) * 1000)
except Exception as ex:
    print("trim: whole clip,", ex)
sel = [f for f in frames if lo <= ms(f) <= hi] or frames
dur = max((ms(sel[-1]) - ms(sel[0])) / 1000, 0.5)
fps = max(len(sel) / dur, 1)
tmp = tempfile.mkdtemp()
for i, f in enumerate(sel): os.symlink(f, f"{tmp}/{i:05d}.png")
vf = ("crop=iw:ih*0.42:0:ih*0.25,scale=-2:720" if angle == "top" else "crop=iw:ih*0.36:0:ih*0.32,scale=-2:720") if angle in ("perp", "top") else "crop=iw:ih*0.5:0:ih*0.2,scale=-2:900"
subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-framerate", f"{fps:.3f}", "-i", f"{tmp}/%05d.png", "-vf", vf, "-pix_fmt", "yuv420p", f"{out}/{scene}_frames.mp4"], stdin=subprocess.DEVNULL)
shutil.rmtree(tmp)
print(f"{scene}: {len(sel)} frames, {dur:.1f} s real time (kept {lo/1000:.1f}..{hi/1000 if hi<10**9 else secs:.1f} s)")
