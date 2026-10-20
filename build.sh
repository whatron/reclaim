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

# Version: the release number in VERSION (e.g. 0.1.0). The GitHub build check passes
# RECLAIM_VERSION in, adding a build label for builds that aren't a release.
BUILD_NUMBER="$(git rev-list --count HEAD 2>/dev/null || echo 0)"
VERSION="${RECLAIM_VERSION:-$(cat VERSION)}"
COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :ReclaimCommit string $COMMIT" "$APP/Contents/Info.plist"
echo "Version $VERSION ($COMMIT)"

# Icon: every size macOS needs, made from the 1024 px master (Support/AppIcon.png, drawn by
# Scripts/make_icon.py and rendered by Scripts/render_icon.py).
echo "Making the icon…"
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$((size * 2))" "$((size * 2))" Support/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

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
