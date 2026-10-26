#!/usr/bin/env bash
# Renders the Pace Off app icon SVGs into the three asset catalogs.
#
#   python3 scripts/app-icon/make_icon_svgs.py   # regenerate the SVGs
#   scripts/app-icon/render.sh                   # render them to PNG
#
# Renderer: rsvg-convert if installed (brew install librsvg), otherwise a
# headless Chrome or Chromium named by $CHROME. App Store icons must be opaque,
# so the light icon is flattened with ImageMagick when it is available.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

IOS="$ROOT/PaceOff/Assets.xcassets/AppIcon.appiconset"
WIDGET="$ROOT/PaceOffWidget/Assets.xcassets/AppIcon.appiconset"
WATCH="$ROOT/PaceOffWatch Watch App/Assets.xcassets/AppIcon.appiconset"

render() { # render <svg> <png>
  if command -v rsvg-convert >/dev/null; then
    rsvg-convert -w 1024 -h 1024 "$1" -o "$2"
  elif [[ -n "${CHROME:-}" ]]; then
    "$CHROME" --headless --no-sandbox --disable-gpu --hide-scrollbars \
      --force-device-scale-factor=1 --window-size=1024,1024 \
      --default-background-color=00000000 --screenshot="$2" "file://$1" >/dev/null 2>&1
  else
    echo "Need rsvg-convert (brew install librsvg) or CHROME=/path/to/chrome" >&2
    exit 1
  fi
}

flatten() { # drop the alpha channel; the light icon's ground is already opaque
  if command -v magick >/dev/null; then magick "$1" -alpha off "$1"
  elif command -v convert >/dev/null; then convert "$1" -alpha off "$1"
  fi
}

render "$HERE/PaceOffIcon.svg" "$IOS/1024.png"
flatten "$IOS/1024.png"
render "$HERE/PaceOffIcon-dark.svg" "$IOS/1024-dark.png"
render "$HERE/PaceOffIcon-tinted.svg" "$IOS/1024-tinted.png"

for dir in "$WIDGET" "$WATCH"; do
  cp "$IOS/1024.png" "$dir/1024.png"
done
cp "$IOS/1024-dark.png" "$IOS/1024-tinted.png" "$WIDGET/"

echo "Rendered icons into the iOS, widget and watch asset catalogs."
