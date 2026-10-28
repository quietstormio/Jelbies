"""contact sheet of renders: sheet.py out.png id1 id2 ... (reads $FOOD4_OUT/renders/<id>_hero.png and _plate.png)"""
import sys, os
from PIL import Image, ImageDraw
S = os.environ["FOOD4_OUT"]; out = sys.argv[1]; ids = sys.argv[2:]
cw = 400; cols = 4; rows = (len(ids)+cols-1)//cols
sheet = Image.new("RGB", (cw*cols, rows*(cw+210)), (247, 240, 224)); d = ImageDraw.Draw(sheet)
def load(p):
    im = Image.open(p).convert("RGBA"); bg = Image.new("RGBA", im.size, (247, 240, 224, 255)); bg.alpha_composite(im); return bg.convert("RGB")
for k, i in enumerate(ids):
    x = (k % cols)*cw; y = (k//cols)*(cw+210)
    d.text((x+8, y+4), i, fill=(77, 51, 31))
    he = load(f"{S}/renders/{i}_hero.png").crop((100, 60, 600, 560)).resize((cw, cw)); sheet.paste(he, (x, y+20))
    p = f"{S}/renders/{i}_plate.png"
    if os.path.exists(p): sheet.paste(load(p).resize((cw, int(cw*0.64))).crop((0, 0, cw, 190)), (x, y+cw+20))
sheet.save(out)
