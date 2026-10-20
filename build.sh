#!/bin/bash
# Builds Reclaim.app from source.
#   ./build.sh             build, then open the app
#   ./build.sh --install   build, copy to /Applications, then open it
#   ./build.sh --no-open   build only (used by the GitHub build check)
set -euo pipefail
cd "$(dirname "$0")"
MODE="${1:-}"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift isn't installed. Run:  xcode-select --install   then try again."
  exit 1
fi

echo "Building Reclaim…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Reclaim"

APP="build/Reclaim.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Reclaim"
cp Support/Info.plist "$APP/Contents/Info.plist"

# Version: the major.minor in VERSION, then the number of commits, e.g. 1.1.24.
# The GitHub build check passes RECLAIM_VERSION in; local builds work it out the same way.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
VERSION="${RECLAIM_VERSION:-$(cat VERSION).$BUILD_NUMBER}"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :ReclaimCommit string $COMMIT" "$APP/Contents/Info.plist"
echo "Version $VERSION ($COMMIT)"

echo "Drawing the icon…"
rm -rf build/AppIcon.iconset
if swift Scripts/make_icon.swift build/AppIcon.iconset >/dev/null 2>&1 \
   && iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"; then
  :
else
  echo "(Skipped the icon; the app works without it.)"
fi

# Ad-hoc signature so macOS will launch it. Built locally, so Gatekeeper doesn't quarantine it.
codesign --force --sign - "$APP" >/dev/null

case "$MODE" in
  --install)
    rm -rf /Applications/Reclaim.app
    cp -R "$APP" /Applications/
    echo "Installed to /Applications/Reclaim.app"
    open /Applications/Reclaim.app
    ;;
  --no-open)
    echo "Built $APP"
    ;;
  *)
    echo "Built $APP"
    open "$APP"
    ;;
esac
