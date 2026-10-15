#!/usr/bin/env bash
# PROTOTYPE, throwaway (#664): copy the shared narration, timing and the OFL fonts into each variant project.
set -euo pipefail
cd "$(dirname "$0")"
for v in v1-claude-dark v2-chalkboard v3-flat-world v4-editorial v5-kinetic; do
  mkdir -p "$v/fonts"
  cp shared/narration.wav "$v/narration.wav"
  printf 'window.TIMING = %s;\n' "$(cat shared/timing.json)" >"$v/timing.js"
  for f in node_modules/@fontsource/*/files/*-{latin,arabic}-{300,400,500,600,700,800}-normal.woff2; do
    [ -e "$f" ] && cp "$f" "$v/fonts/"
  done
done
