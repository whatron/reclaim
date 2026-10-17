#!/bin/bash
# Builds Reclaim.app from source.
#   ./build.sh            build, then open the app
#   ./build.sh --install  build, copy to /Applications, then open it
set -euo pipefail
cd "$(dirname "$0")"

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

if [ "${1:-}" = "--install" ]; then
  rm -rf /Applications/Reclaim.app
  cp -R "$APP" /Applications/
  echo "Installed to /Applications/Reclaim.app"
  open /Applications/Reclaim.app
else
  echo "Built $APP"
  open "$APP"
fi
