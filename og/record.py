#!/usr/bin/env python3
"""Records an HTML page to a looping MP4 for og:video (the moving link preview).

Steps headless Chrome one frame at a time on a frozen clock, so timers, CSS and
Web Animations land on exact frame times and the loop closes cleanly.

    python3 record.py og-video.html out.mp4 --seconds 8

Optional:
    --overlay img.png --overlay-width 1400   paste the left 1400px (at 2x) of a
                                             still over every frame, e.g. to keep
                                             a Mac-rendered headline's fonts
    --css "..."                              extra CSS added after the page loads

Needs: pip3 install playwright && python3 -m playwright install chromium, and ffmpeg.
"""
import argparse, pathlib, shutil, subprocess, tempfile

from playwright.sync_api import sync_playwright

W, H, SCALE = 1200, 630, 2

# Each frame: pause every animation and put it at the clock's time. A CSS
# transition that started between frames is timed from the frame it appeared in.
SEEK = """(ms) => {
  window.__frozen = true;   // stop the page playing itself; we set every frame
  for (const a of document.getAnimations()) {
    if (a.__start === undefined) a.__start = ms;
    a.pause();
    a.currentTime = ms - a.__start;
  }
  if (window.seek) window.seek(ms / 1000);
}"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("page")
    ap.add_argument("out")
    ap.add_argument("--seconds", type=float, required=True)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--crf", type=int, default=24)
    ap.add_argument("--overlay")
    ap.add_argument("--overlay-width", type=int, default=0)
    ap.add_argument("--css")
    args = ap.parse_args()

    frames = round(args.seconds * args.fps)
    tmp = pathlib.Path(tempfile.mkdtemp(prefix="ogvideo-"))
    try:
        with sync_playwright() as p:
            browser = p.chromium.launch()
            page = browser.new_page(viewport={"width": W, "height": H}, device_scale_factor=SCALE,
                                    reduced_motion="no-preference")
            page.clock.install(time=0)
            page.clock.pause_at(1000)
            page.goto(pathlib.Path(args.page).resolve().as_uri(), wait_until="networkidle")
            if args.css:
                page.add_style_tag(content=args.css)
            page.evaluate("document.fonts.ready.then(() => true)")
            # Wait for the images in view (not ones below the fold, like an animated GIF
            # that never settles on a frozen clock)
            page.evaluate("""Promise.all([...document.images]
                .filter(i => { const r = i.getBoundingClientRect(); return r.bottom > 0 && r.top < innerHeight && r.right > 0 && r.left < innerWidth; })
                .map(i => i.decode().catch(() => 0)))""")
            now = 0
            for i in range(frames):
                ms = round(i * 1000 / args.fps)
                if ms > now:
                    page.clock.run_for(ms - now)
                    now = ms
                page.evaluate(SEEK, ms)
                page.screenshot(path=str(tmp / f"{i:05d}.png"))
            browser.close()

        vf = f"scale={W}:{H}:flags=lanczos,format=yuv420p"
        cmd = ["ffmpeg", "-y", "-loglevel", "error", "-framerate", str(args.fps), "-i", str(tmp / "%05d.png")]
        if args.overlay:
            cmd += ["-i", args.overlay, "-filter_complex",
                    f"[1]crop={args.overlay_width}:{H * SCALE}:0:0[o];[0][o]overlay=0:0,{vf}"]
        else:
            cmd += ["-vf", vf]
        cmd += ["-c:v", "libx264", "-preset", "veryslow", "-crf", str(args.crf), "-profile:v", "high",
                "-tune", "animation", "-movflags", "+faststart", "-an", args.out]
        subprocess.run(cmd, check=True)
        print(f"{args.out}: {frames} frames, {pathlib.Path(args.out).stat().st_size // 1024} KB")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
