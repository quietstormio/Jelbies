#!/usr/bin/env python3
"""Deterministic renderer for the Jelbies intro clip (Blue theme, Play once).

Loads the "Jelbies Logo Full Screen" artifact HTML, stops its live rAF loop, and for each
60 fps frame calls renderAt(t), screenshots the page (viewport == canvas, DSF 1, so it renders
at full resolution) and pipes PNGs into ffmpeg (H.264 High, yuv420p, +faststart).
Audio is NOT taken from the artifact; pass --audio to mux our own sting.

  python3 tools/render_intro/render_intro.py --html artifact.html --out out.mp4 --size 1206x2622 \
      [--audio sting.m4a --audio-offset 0.0] [--bitrate 2200k] [--frames N] [--dump DIR]
Needs: pip install playwright (+ chromium via `playwright install chromium`), ffmpeg, network for the Fredoka font.
"""
import argparse, subprocess, sys, pathlib
from playwright.sync_api import sync_playwright

ap = argparse.ArgumentParser()
ap.add_argument("--html", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--size", required=True, help="WxH, e.g. 1206x2622")
ap.add_argument("--fps", type=int, default=60)
ap.add_argument("--bitrate", default="2200k")
ap.add_argument("--audio", help="our own audio file to mux (the artifact's sound is never used)")
ap.add_argument("--audio-offset", type=float, default=0.0, help="seconds; positive delays the audio, negative skips into it")
ap.add_argument("--mode", default="loop", choices=["loop", "end"], help="loop = full timeline once (stomp, pop, fall, paper); end = stops on the built logo")
ap.add_argument("--tail-fade", type=float, default=0.5, help="seconds: fade the end of the timeline to paper")
ap.add_argument("--tail-hold", type=float, default=0.25, help="seconds of pure paper appended after the fade")
ap.add_argument("--frames", type=int, help="override frame count (debug)")
ap.add_argument("--dump", help="write frames as PNGs to this dir instead of encoding")
a = ap.parse_args()
W, H = map(int, a.size.split("x"))

with sync_playwright() as p:
    br = p.chromium.launch(args=["--force-device-scale-factor=1"])
    pg = br.new_page(viewport={"width": W, "height": H}, device_scale_factor=1)
    pg.on("console", lambda m: print("[page]", m.text, file=sys.stderr) if m.type == "error" else None)
    # theme=blue, mode=end (Play once), ui=0 hides the pill, t=0 = still mode (no live playback), dpr=1 = 1 canvas px per CSS px
    url = pathlib.Path(a.html).resolve().as_uri() + f"#theme=blue&mode={a.mode}&ui=0&dpr=1&t=0"
    pg.goto(url, wait_until="load")
    pg.evaluate("document.fonts.load('600 40px Fredoka')")
    pg.evaluate("document.fonts.ready")
    if not pg.evaluate("document.fonts.check('600 40px Fredoka')"):
        sys.exit("Fredoka did not load (need network)")
    pg.wait_for_function("typeof clipInfo==='function' && clipInfo().VW>0", timeout=60000)
    pg.wait_for_timeout(1500)
    # stop the live loop for good, hide the bar
    pg.evaluate("window.requestAnimationFrame=()=>0; const b=document.getElementById('bar'); if(b) b.style.display='none';")
    info = pg.evaluate("clipInfo()")
    print("clipInfo", info, file=sys.stderr)
    assert info["VW"] == W and info["VH"] == H, f"canvas {info['VW']}x{info['VH']} != {W}x{H}"
    assert info["mode"] == a.mode
    n = a.frames or round(info["dur"] * a.fps)
    enc = None
    if not a.dump:
        br_k = int(a.bitrate[:-1])
        cmd = ["ffmpeg", "-y", "-v", "error", "-f", "image2pipe", "-framerate", str(a.fps), "-c:v", "png", "-i", "-"]
        if a.audio:
            if a.audio_offset < 0:
                cmd += ["-ss", str(-a.audio_offset)]
            cmd += ["-i", a.audio]
        cmd += ["-map", "0:v"] + (["-map", "1:a"] if a.audio else [])
        cmd += ["-c:v", "libx264", "-profile:v", "high", "-pix_fmt", "yuv420p", "-b:v", a.bitrate,
                "-maxrate", f"{br_k * 2}k", "-bufsize", f"{br_k * 2}k",
                "-r", str(a.fps), "-g", str(a.fps),
                "-color_primaries", "bt709", "-color_trc", "bt709", "-colorspace", "bt709",
                "-vf", f"fade=t=out:st={n / a.fps - a.tail_fade}:d={a.tail_fade}:color=0xF0EFF0,"
                f"tpad=stop_mode=add:stop_duration={a.tail_hold}:color=0xF0EFF0,scale=out_color_matrix=bt709:out_range=tv"]
        if a.audio:
            dur = n / a.fps + a.tail_hold
            cmd += ["-c:a", "aac", "-b:a", "128k", "-ar", "44100", "-ac", "2",
                    "-af", (f"adelay={int(a.audio_offset * 1000)}:all=1," if a.audio_offset > 0 else "") + f"apad,atrim=0:{dur},afade=t=out:st={dur - 0.4}:d=0.4", "-t", f"{dur}"]
        cmd += ["-movflags", "+faststart", a.out]
        enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    for i in range(n):
        pg.evaluate(f"renderAt({i}/{a.fps})")
        png = pg.screenshot(type="png")
        if a.dump:
            pathlib.Path(a.dump, f"f{i:04d}.png").write_bytes(png)
        else:
            enc.stdin.write(png)
        if i % 60 == 0:
            print(f"frame {i}/{n}", file=sys.stderr)
    if enc:
        enc.stdin.close()
        assert enc.wait() == 0
    br.close()
