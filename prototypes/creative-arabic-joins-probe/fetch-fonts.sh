#!/usr/bin/env bash
# Downloads the three Google Fonts faces the probe adds to the system's Noto
# and IBM Plex Arabic faces (Ubuntu: fonts-noto-core, fonts-ibm-plex).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p fonts
base=https://github.com/google/fonts/raw/main/ofl
curl -sfL "$base/amiri/Amiri-Regular.ttf" -o fonts/Amiri-Regular.ttf
curl -sfL "$base/cairo/Cairo%5Bslnt,wght%5D.ttf" -o fonts/Cairo.ttf
curl -sfL "$base/tajawal/Tajawal-Regular.ttf" -o fonts/Tajawal-Regular.ttf
