#!/bin/bash
# Opens each page of the built app and saves a screenshot of its window. Used by the GitHub build check.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-shots}"
mkdir -p "$OUT"
swiftc -O Scripts/window_id.swift -o build/window_id

shoot() { # page, theme, seconds to wait
  RECLAIM_SECTION="$1" ./build/Reclaim.app/Contents/MacOS/Reclaim >/dev/null 2>&1 &
  local pid=$!
  sleep "$3"
  local wid
  wid=$(./build/window_id)
  if [ "$wid" != "0" ]; then
    screencapture -x -o -l"$wid" "$OUT/$2-$1.png"
  else
    screencapture -x "$OUT/$2-$1-screen.png"
  fi
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  sleep 1
}

system_profiler SPDisplaysDataType | grep -i resolution || true

defaults write -g AppleInterfaceStyle Dark
for page in overview:25 clean:20 map:45 projects:45 files:30 duplicates:6 apps:50 history:10; do
  shoot "${page%%:*}" dark "${page##*:}"
done

defaults delete -g AppleInterfaceStyle 2>/dev/null || true
for page in overview:20 clean:15 map:30; do
  shoot "${page%%:*}" light "${page##*:}"
done
ls -la "$OUT"
