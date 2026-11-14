#!/usr/bin/env python3
"""python3 montage.py OUT.png TILE_DIR PREFIX1[,PREFIX2...] VIEWS(comma)  -> rows = prefixes, columns = views, labelled"""
import sys, os
from PIL import Image, ImageDraw
out, d, pre, views = sys.argv[1], sys.argv[2], sys.argv[3].split(','), sys.argv[4].split(',')
tiles = [[Image.open(f"{d}/{p}_{v}.png").convert('RGB') for v in views] for p in pre]
w, h = tiles[0][0].size
S = Image.new('RGB', (w * len(views), h * len(pre)))
dr = ImageDraw.Draw(S)
for r, row in enumerate(tiles):
    for c, t in enumerate(row):
        S.paste(t, (c * w, r * h)); dr.rectangle([c * w, r * h, c * w + 330, r * h + 18], fill=(0, 0, 0)); dr.text((c * w + 4, r * h + 3), f"{pre[r]} {views[c]}", fill=(255, 255, 255))
S.save(out)
