"""contact_sheet.py <scene>_frames.mp4 [scene seconds at the clip start]: 8 frames spread across the clip (the touching phase, from 0.5 s before to 2 s after) -> <scene>_sheet.png, time-labelled (scene time when the offset is given)."""
import sys,subprocess,tempfile,os
from PIL import Image,ImageDraw,ImageFont
mp4=sys.argv[1]; off=float(sys.argv[2]) if len(sys.argv)>2 else 0.0; out=mp4.replace("_frames.mp4","_sheet.png")
dur=float(subprocess.check_output(["ffprobe","-v","error","-show_entries","format=duration","-of","csv=p=0",mp4]))
n=8; ts=[dur*(i+0.5)/n for i in range(n)]
d=tempfile.mkdtemp(); ims=[]
for i,t in enumerate(ts):
    f=f"{d}/{i}.png"; subprocess.run(["ffmpeg","-loglevel","error","-y","-ss",f"{t:.3f}","-i",mp4,"-frames:v","1",f,],stdin=subprocess.DEVNULL); ims.append(Image.open(f).convert("RGB"))
w=700; ims=[im.resize((w,int(im.height*w/im.width))) for im in ims]; h=ims[0].height
cols=2; rows=4; sh=Image.new("RGB",(cols*w,rows*h),"white")
try: font=ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc",28)
except: font=ImageFont.load_default()
for i,im in enumerate(ims):
    dr=ImageDraw.Draw(im); dr.rectangle([0,0,150,38],fill="black"); dr.text((8,4),f"t={off+ts[i]:.1f}s",fill="white",font=font)
    sh.paste(im,((i%cols)*w,(i//cols)*h))
sh.save(out); print(out,dur)
