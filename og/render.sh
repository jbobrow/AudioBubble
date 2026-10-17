#!/bin/sh
# Renders og-image.html to docs/og-image.png (2400x1260).
# After re-rendering, bump ?v= on the og:image / twitter:image tags.
cd "$(dirname "$0")" || exit 1
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  --headless --hide-scrollbars \
  --window-size=1200,630 --force-device-scale-factor=2 \
  --virtual-time-budget=3000 \
  --screenshot="$PWD/../docs/og-image.png" \
  "file://$PWD/og-image.html"
# Shrink it (about a third the size, no visible change) if pngquant is installed: brew install pngquant
command -v pngquant >/dev/null && pngquant --quality=80-95 --speed 1 --force --output "../docs/og-image.png" "../docs/og-image.png"
