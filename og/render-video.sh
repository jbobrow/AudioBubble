#!/bin/sh
# Records og-video.html to docs/og-video.mp4 (1200x630, 8s loop).
# Needs: pip3 install playwright && python3 -m playwright install chromium, and ffmpeg.
# After re-rendering, bump ?v= on the og:video tags.
cd "$(dirname "$0")" || exit 1
python3 record.py og-video.html ../docs/og-video.mp4 --seconds 8
