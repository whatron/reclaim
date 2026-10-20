#!/bin/bash
# End-to-end test of updating in place, used by the GitHub build check.
# Copies the freshly built app somewhere temporary, opens it in test mode, and lets it install the
# latest release over itself with the update sheet open, as a person would. Passes when the old copy
# quits, the release's version is on disk, and the new copy is running. Publishes an "Update test" check.
set -uo pipefail
cd "$(dirname "$0")/.."

dir="$(mktemp -d)/apps"
mkdir -p "$dir"
ditto build/Reclaim.app "$dir/Reclaim.app"
plist="$dir/Reclaim.app/Contents/Info.plist"
before="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")"
latest="$(gh api "repos/$GITHUB_REPOSITORY/releases/latest" --jq .tag_name | sed 's/^v//')"
log="$HOME/Library/Logs/Reclaim/update.log"
rm -f "$log"

RECLAIM_TEST_UPDATE=1 "$dir/Reclaim.app/Contents/MacOS/Reclaim" >/dev/null 2>&1 &
pid=$!
result=failure
detail="Timed out."
for _ in $(seq 1 90); do
  sleep 1
  after="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || echo missing)"
  if ! kill -0 "$pid" 2>/dev/null && [ "$after" = "$latest" ] && pgrep -f "$dir/Reclaim.app/Contents/MacOS/Reclaim" >/dev/null; then
    result=success
    detail="Updated $before to $after in place; the old copy quit and the new one is running."
    break
  fi
done
if [ "$result" = failure ]; then
  still=$(kill -0 "$pid" 2>/dev/null && echo "still running" || echo "quit")
  detail="Didn't finish within 90 seconds. Old copy: $still. Version on disk: $after (expected $latest)."
fi
pkill -f "$dir/Reclaim.app/Contents/MacOS/Reclaim" 2>/dev/null || true
kill "$pid" 2>/dev/null || true
echo "$detail"
{ echo "$detail"; echo; echo "## Update log"; cat "$log" 2>/dev/null || echo "(no log)"; } > update-test.txt

gh api "repos/$GITHUB_REPOSITORY/check-runs" -f name="Update test" -f head_sha="$GITHUB_SHA" \
  -f status=completed -f conclusion="$result" -f "output[title]=$detail" -f "output[summary]=$detail" \
  -F "output[text]=@update-test.txt" >/dev/null || true
[ "$result" = success ]
