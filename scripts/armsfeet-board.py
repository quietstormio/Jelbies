#!/usr/bin/env python3
"""armsfeet-board.py: cut fixed frames out of the board recordings and write one labelled contact sheet board.png.
Usage: python3 -I armsfeet-board.py <out dir>      (reads <out>/scenes.tsv written by armsfeet-board.sh)
scenes.tsv row: name <TAB> species list (comma; one tile per species per time) or 'fixed' <TAB> crop size in video px <TAB> times (s after the app appears) or 'spring'
Times are relative to t0 = the first frame that differs from the pre-launch frame, so a slow app start does not move the tiles. Each tile is the crop around the
creature (found by its body colour; the last known position when it is hidden) enlarged to TILE px (about 3x). Needs PIL, numpy, scipy; ffmpeg at /opt/homebrew/bin/ffmpeg."""
import sys, os, subprocess
import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi
FFMPEG = "/opt/homebrew/bin/ffmpeg"; FPS = 30; TILE = 540; COLS = 4
out = sys.argv[1]

def frames(name):
    d = f"{out}/frames/{name}"; os.makedirs(d, exist_ok=True)
    if not os.listdir(d):
        subprocess.run([FFMPEG, "-loglevel", "error", "-i", f"{out}/vid/{name}.mp4", "-vf", f"fps={FPS}", "-q:v", "2", f"{d}/f_%05d.jpg"], check=True)
    return [f"{d}/{f}" for f in sorted(os.listdir(d))]

def small(path): return np.asarray(Image.open(path).convert("L").resize((60, 130)), dtype=float)

def blue_fraction(path):
    a = np.asarray(Image.open(path).convert("RGB").resize((60, 130)), dtype=int)
    return float(((a[..., 2] - a[..., 0] > 40) & (a[..., 2] > 140)).mean())

def t0_index(fs):
    """t0 = the first frame after the blue 'Waking up your Jelmiko' loading screen (a mostly blue frame) in the first 40 s; if there is none, the first frame that
    differs from the pre-launch frame. A slow start (a busy machine) therefore does not move the tiles."""
    last = -1
    for i in range(0, min(len(fs), 40 * FPS), 3):
        if blue_fraction(fs[i]) > 0.5: last = i
    if last >= 0: return min(last + 4, len(fs) - 1)
    base = small(fs[0])
    for i in range(1, len(fs)):
        if np.abs(small(fs[i]) - base).mean() > 6: return i
    return 0

# body colour masks (r, g, b arrays); calibrated on the iPhone 17 Pro recordings, species by -NewGame name
MASKS = {
    "bob":      lambda r, g, b: (b - r > 40) & (b > 140),
    "pip":      lambda r, g, b: (r > 200) & (g > 170) & (b < 140) & (r - b > 110),
    "moss":     lambda r, g, b: (g - r > 12) & (g - b > 12),
    "lavender": lambda r, g, b: (b - g > 25) & (r - g > 10) & (b > 150),
}

def locate(im, sp, last):
    a = np.asarray(im); h, w = a.shape[:2]
    m = MASKS[sp](*[a[..., i].astype(int) for i in range(3)])
    m[: int(h * .12)] = False; m[int(h * .92):] = False              # the HUD rows
    m = ndi.binary_dilation(ndi.binary_opening(m, iterations=2), iterations=8)
    lab, k = ndi.label(m)
    if k:
        areas = ndi.sum(m, lab, range(1, k + 1)); j = int(np.argmax(areas)) + 1
        if areas[j - 1] > 2500:
            ys, xs = np.where(lab == j); return ((xs.min() + xs.max()) // 2, (ys.min() + ys.max()) // 2)
    return last

def species_pages(name, fs):
    """first frame of each Jelly Spring page. The UI test writes a wall-clock mark per tap (spring_marks/marks.txt); the script wrote the recording's start time
    (vstart.txt; a page shows ~0.7 s after its tap mark). Around each mark the page background (a patch left of the creature) must settle on its new colour: the first
    frame from 0.5 s before the mark whose patch matches the patch 1.8 s after the mark. Returns (starts, how many of 7 were found)."""
    md = f"{out}/spring_marks"
    try: vstart = float(open(f"{md}/vstart.txt").read())
    except Exception: return [], 0
    marks = [(float(l.split()[0]), " ".join(l.split()[1:])) for l in open(f"{md}/marks.txt") if l.strip()]
    pm = [m for m in marks if m[1] == "start" or m[1].startswith("fwd")][:7]
    def patch(i):
        im = Image.open(fs[i]).convert("RGB"); w, h = im.size
        return np.asarray(im.crop((int(w * .02), int(h * .26), int(w * .12), int(h * .30))), dtype=float).reshape(-1, 3).mean(0)
    starts = []
    for k, (t, lab) in enumerate(pm):
        m = int((t - vstart) * FPS) - (int(2.3 * FPS) if lab == "start" else 0)          # (page 0: its colour is settled well before the first tap; search from the start of the video)
        if m < 0 or m + 2 * FPS >= len(fs): continue
        stable = patch(min(len(fs) - 1, m + int(1.8 * FPS)))
        for f in range(0 if lab == "start" else max(0, m - FPS // 2), m + int(1.8 * FPS)):
            if np.linalg.norm(patch(f) - stable) < 8 and np.linalg.norm(patch(min(len(fs) - 1, f + 4)) - stable) < 8: starts.append(f); break
    return starts, len(pm)

tiles = []
for line in open(f"{out}/scenes.tsv"):
    f = line.rstrip("\n").split("\t")
    if len(f) < 4 or f[0].startswith("#"): continue
    name, spl, size, times = f[0], f[1], int(f[2]), f[3]
    if not os.path.exists(f"{out}/vid/{name}.mp4"): tiles.append((f"{name}: NO VIDEO", None)); continue
    fs = frames(name); t0 = t0_index(fs)
    if times == "spring":
        starts, _ = species_pages(name, fs)
        for k, s in enumerate(starts[:7]):
            for dt in (0.5, 0.9, 1.3):
                im = Image.open(fs[min(len(fs) - 1, s + int(round(dt * FPS)))]).convert("RGB"); w, h = im.size
                cx, cy, hs = w // 2, int(h * .42), size // 2        # the Spring page: the creature stands at a fixed spot
                tiles.append((f"spring page {k} +{dt}s", im.crop((cx - hs, cy - hs, cx + hs, cy + hs)).resize((TILE, TILE), Image.LANCZOS)))
        if len(starts) != 7: tiles.append((f"spring: found {len(starts)} pages, expected 7", None))
        continue
    last = {}
    for t in times.split(","):
        im = Image.open(fs[min(len(fs) - 1, t0 + int(float(t) * FPS))]).convert("RGB"); w, h = im.size
        for sp in spl.split(","):
            last[sp] = locate(im, sp, last.get(sp, (w // 2, h // 2))); cx, cy = last[sp]; hs = size // 2
            x0 = min(max(cx - hs, 0), w - size); y0 = min(max(cy - hs, 0), h - size)
            tiles.append((f"{name} {sp} t0+{t}s", im.crop((x0, y0, x0 + size, y0 + size)).resize((TILE, TILE), Image.LANCZOS)))
if not tiles: tiles = [("no scene was recorded (see the script output)", None)]
rows = (len(tiles) + COLS - 1) // COLS
sheet = Image.new("RGB", (COLS * TILE, rows * (TILE + 18)), (30, 30, 30)); d = ImageDraw.Draw(sheet)
for k, (lab, im) in enumerate(tiles):
    x, y = (k % COLS) * TILE, (k // COLS) * (TILE + 18)
    d.text((x + 4, y + 3), lab, fill=(255, 255, 0))
    if im: sheet.paste(im, (x, y + 18))
sheet.save(f"{out}/board.png"); print(f"{out}/board.png", sheet.size, len(tiles), "tiles")
