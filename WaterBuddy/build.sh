#!/bin/bash
# Builds WaterBuddy.app (macOS 13+). Needs Xcode Command Line Tools: xcode-select --install
set -euo pipefail
cd "$(dirname "$0")"

APP=build/WaterBuddy.app
rm -rf build
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "Compiling..."
for arch in arm64 x86_64; do
  swiftc -O -target "$arch-apple-macos13" Sources/main.swift -o "build/WaterBuddy-$arch"
done
lipo -create build/WaterBuddy-arm64 build/WaterBuddy-x86_64 -output "$APP/Contents/MacOS/WaterBuddy"
rm build/WaterBuddy-*

cp -R Resources/sprites "$APP/Contents/Resources/"
cp Resources/Info.plist "$APP/Contents/"

echo "Making icon..."
ICONSET=build/AppIcon.iconset
mkdir -p "$ICONSET"
sips --padToHeightWidth 362 362 Resources/sprites/wave_2.png --out build/icon_src.png >/dev/null
for s in 16 32 128 256 512; do
  sips -z $s $s build/icon_src.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) build/icon_src.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET" build/icon_src.png

codesign --force --sign - "$APP"
echo "Done: $APP"
echo "Run it:      open $APP"
echo "Install it:  cp -R $APP /Applications/"
