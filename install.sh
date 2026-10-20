#!/bin/bash
# Installs or updates Reclaim from GitHub releases, without macOS's "unsafe app" warning.
#
#   ./install.sh            install the latest release
#   ./install.sh v0.1.0     install a specific release
#
# Why there's no warning: macOS only marks files downloaded by apps such as Safari or Chrome
# for a security check. Files fetched by command-line tools aren't marked, so Reclaim opens
# straight away. The repo is private, so the download goes through the GitHub CLI (`gh`),
# which uses your GitHub sign-in.
set -euo pipefail

REPO="whatron/reclaim"
TAG="${1:-}"
APP="/Applications/Reclaim.app"

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

[ "$(uname)" = "Darwin" ] || fail "Reclaim is a Mac app; run this on your Mac."
if [ "$(uname -m)" != "arm64" ]; then
  fail "Release builds are for Apple-silicon Macs. On an Intel Mac, clone the repo and run ./build.sh --install."
fi
if ! command -v gh >/dev/null 2>&1; then
  fail "This needs the GitHub CLI. Install it with:  brew install gh   then run:  gh auth login"
fi
gh auth status >/dev/null 2>&1 || fail "Sign in to GitHub first:  gh auth login"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

say "Downloading ${TAG:-the latest release}…"
gh release download ${TAG:+"$TAG"} --repo "$REPO" --pattern 'Reclaim-*.zip' --dir "$work" \
  || fail "Couldn't download ${TAG:-the latest release} from $REPO."
zip="$(ls "$work"/Reclaim-*.zip | head -1)"
ditto -x -k "$zip" "$work/unpacked"
[ -d "$work/unpacked/Reclaim.app" ] || fail "The download didn't contain Reclaim.app."
new="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$work/unpacked/Reclaim.app/Contents/Info.plist" 2>/dev/null || echo unknown)"

old=""
if [ -d "$APP" ]; then
  old="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo unknown)"
fi

if pgrep -x Reclaim >/dev/null; then
  say "Quitting Reclaim…"
  osascript -e 'quit app "Reclaim"' >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -x Reclaim >/dev/null || break; sleep 0.5; done
  pkill -x Reclaim 2>/dev/null || true
fi

say "Installing Reclaim $new…"
sudo_if_needed=""
[ -w /Applications ] || sudo_if_needed="sudo"
$sudo_if_needed rm -rf "$APP"
$sudo_if_needed ditto "$work/unpacked/Reclaim.app" "$APP"
# In case the zip itself was downloaded through a browser at some point.
$sudo_if_needed xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

if [ -n "$old" ] && [ "$old" != "$new" ]; then
  say "Updated Reclaim from $old to $new."
else
  say "Installed Reclaim $new."
fi
echo "Each build has a new signature, so macOS may ask for Full Disk Access again; Reclaim will walk you through it."
open "$APP"
