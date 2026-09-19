#!/usr/bin/env bash
# Shoot a set of screens on the simulator, for looking at them side by side (PD-173).
#
# The founder's standing rule is to look at every changed screen before calling it done, and the thing
# that makes that rule get skipped is how long it takes by hand: launch, wait for the opening, wait for
# the screen to settle, screenshot, scale, repeat. This does that, and waits for the screen to STOP
# CHANGING rather than sleeping a guessed number of seconds — the app needs about eleven seconds past
# launch, and a fixed sleep either wastes time or photographs the opening.
#
#   tools/shoot.sh out/before tab/home tab/play tab/live
#   tools/shoot.sh out/opening --opening 0.15 0.90 1.85 2.90 4.20
#
# With --opening the remaining arguments are times in seconds and each is held with -ThroOpeningAt.
# Otherwise they are thro:// routes without the scheme, exactly as -ThroScreen takes them.
#
# THRO_DEVICE overrides the simulator; the default is the iPhone 17 Pro this project shoots on.
set -euo pipefail

DEVICE="${THRO_DEVICE:-938C4A6C-45A7-4366-B94B-208B795D8819}"
APP=app.thro.darts
OUT="${1:?usage: tools/shoot.sh <out-dir> [--opening] <route|seconds>...}"
shift

MODE=screen
if [ "${1:-}" = "--opening" ]; then MODE=opening; shift; fi
mkdir -p "$OUT"

settle() {   # screenshot until two consecutive captures are byte-identical
  local path="$1" prev=0 cur stable=0
  until [ "$stable" -ge 2 ]; do
    xcrun simctl io "$DEVICE" screenshot "$path" >/dev/null 2>&1 || true
    cur=$(wc -c < "$path" | tr -d ' ')
    if [ "$cur" = "$prev" ]; then stable=$((stable + 1)); else stable=0; fi
    prev=$cur
    sleep 1
  done
}

for arg in "$@"; do
  name=$(printf '%s' "$arg" | tr '/.' '__')
  xcrun simctl terminate "$DEVICE" "$APP" >/dev/null 2>&1 || true
  if [ "$MODE" = opening ]; then
    xcrun simctl launch "$DEVICE" "$APP" -ThroScreenshotAccount adult -ThroOpeningAt "$arg" >/dev/null
  else
    xcrun simctl launch "$DEVICE" "$APP" -ThroScreenshotAccount adult -ThroScreen "$arg" >/dev/null
  fi
  settle "$OUT/$name.png"
  # A second copy, scaled, because a full-resolution phone screenshot is more pixels than any eye or
  # any reader needs to judge a layout by.
  sips -Z 640 "$OUT/$name.png" --out "$OUT/${name}_small.png" >/dev/null 2>&1 || true
  echo "  $arg -> $OUT/$name.png"
done
