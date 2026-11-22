#!/usr/bin/env python3
"""Bakes Marble's vein map (Lineup id 9) from the owner's front / back / side drawings (9_marble_{front,back,side}.jpg, 768 px) into the
MSL array of BobV1/Melon/MarbleMarks.h. Same unwrap as cow_bake.py (an ellipse unwrap of the three drawings onto angle x height: column = atan2(Q.x, Q.z), row = height),
but the veins are WISPY, so the map is a soft alpha (4 bits, 0 = body ... 15 = full vein) at 256 x 128, and the drawing's own gloss oval / dot / bubbles / rim are masked out
(the renderer draws its own highlights).
Usage: marble_bake.py <drawings dir> <out words.txt>   (run with python3 -I)"""
import numpy as np, math, sys
from PIL import Image
from scipy import ndimage as ndi
D, OUT = sys.argv[1], sys.argv[2]
NU, NV = 256, 128
CY, TOP, BOT = 365, 145, 585
cfg = {"front": (382, 213), "back": (383, 213), "side": (381, 196)}
# the drawing's own gloss oval / glint dot / bubbles: (cx, cy, semi-major, semi-minor, angle deg (counter-clockwise on screen))
excl = {
    "front": [(378, 357, 82, 32, 56), (400, 421, 14, 14, 0), (260, 485, 18, 18, 0), (250, 525, 16, 16, 0), (342, 570, 17, 17, 0)],
    "back": [(378, 288, 48, 30, 25), (398, 328, 13, 13, 0)],
    "side": [(372, 315, 50, 30, 43), (383, 363, 12, 12, 0), (435, 520, 58, 58, 0), (405, 445, 20, 20, 0)],
}
def vein(v):
    im = np.asarray(Image.open(f"{D}/9_marble_{v}.jpg").convert("RGB")).astype(float)
    R = im[:, :, 0]
    # the ribbons are the bright (R) parts of the aqua body; the drawing's gloss / rim are masked below and by the edge fade in the unwrap; a 5 px grow keeps the wisps from shredding at 256 x 128
    a = np.clip((R - 150) / 45.0, 0, 1)
    a = ndi.maximum_filter(ndi.gaussian_filter(a, 0.8), size=5)
    body = ndi.binary_erosion(ndi.binary_fill_holes(im[:, :, 1] - im[:, :, 0] > 25), iterations=5)          # the cream behind the body is no vein
    a = a * ndi.gaussian_filter(body.astype(float), 1.5)
    yy, xx = np.mgrid[0:768, 0:768]
    for (cx, cy, A, B, ang) in excl[v]:
        t = math.radians(ang); dx, dy = xx - cx, -(yy - cy)
        u = dx * math.cos(t) + dy * math.sin(t); w = -dx * math.sin(t) + dy * math.cos(t)
        d = np.sqrt((u / A) ** 2 + (w / B) ** 2)
        a = a * np.clip((d - 0.9) / 0.35, 0, 1)
    return a
M = {v: vein(v) for v in cfg}
def samp(v, px, py): return ndi.map_coordinates(M[v], [[py], [px]], order=1, mode="nearest")[0]
sm = lambda a, b, x: min(1, max(0, (x - a) / (b - a)))
out = np.zeros((NV, NU))
for j in range(NV):
    t = (j + 0.5) / NV
    row = BOT - t * (BOT - TOP); ey = (row - CY) / 220.0; r = math.sqrt(max(0, 1 - ey * ey))
    for i in range(NU):
        th = -math.pi + (i + 0.5) * 2 * math.pi / NU
        s, c = math.sin(th), math.cos(th); d = math.degrees(th)
        def fade(sx): return 1.0 - (sm(0.72, 0.84, sx) if sx > 0 else sm(0.90, 0.97, -sx))          # the drawing's silhouette band (rim light on the right, arms) is not paint
        front = lambda: fade(r * s) * samp("front", cfg["front"][0] + cfg["front"][1] * r * s, row)
        back = lambda: fade(-r * s) * samp("back", cfg["back"][0] - cfg["back"][1] * r * s, row)
        side = lambda: fade(r * c) * samp("side", cfg["side"][0] + cfg["side"][1] * r * c, row)
        if d >= 0:
            w = sm(80, 100, d); val = front() * (1 - w) + back() * w
        else:
            a = -d
            if a <= 52: val = front() * (1 - sm(42, 52, a)) + side() * sm(42, 52, a)
            elif a <= 128: val = side()
            else: w = sm(128, 138, a); val = side() * (1 - w) + back() * w
        out[j, i] = val
q = np.clip(np.round(out * 15), 0, 15).astype(int)
Image.fromarray((out[::-1] * 255).astype(np.uint8)).resize((NU * 4, NV * 4), Image.NEAREST).save(OUT + ".png")
flat = q.flatten(); words = []
for k in range(0, len(flat), 8):
    w = 0
    for n in range(8): w |= int(flat[k + n]) << (4 * n)
    words.append(w)
open(OUT, "w").write(",".join(f"0x{w:08x}u" for w in words))
print(len(words))
