#!/bin/bash
# Runs the app's screenshot tour and photographs each page. Used by the GitHub build check.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-shots}"
TOUR="$PWD/build/tour"
rm -rf "$TOUR" && mkdir -p "$TOUR" "$OUT"
swiftc -O Scripts/window_id.swift -o build/window_id

RECLAIM_TOUR="$TOUR" ./build/Reclaim.app/Contents/MacOS/Reclaim >/dev/null 2>&1 &
pid=$!
last=""
end=$((SECONDS + 480))
while [ $SECONDS -lt $end ]; do
  now=$(cat "$TOUR/now" 2>/dev/null || true)
  [ "$now" = "finished" ] && break
  if [ -n "$now" ] && [ "$now" != "$last" ]; then
    wid=$(./build/window_id)
    if [[ "$now" == *access* || "$now" == *update* ]]; then
      screencapture -x -R"$(./build/window_id bounds)" "$OUT/$now.png"
    elif [ "$wid" != "0" ]; then
      screencapture -x -o -l"$wid" "$OUT/$now.png"
    else
      screencapture -x "$OUT/$now-screen.png"
    fi
    touch "$TOUR/$now.done"
    echo "Captured $now"
    last="$now"
  fi
  sleep 0.5
done
kill "$pid" 2>/dev/null || true
ls -la "$OUT"
