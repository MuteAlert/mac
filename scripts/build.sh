#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --arch arm64
arm_bin="$(swift build -c release --arch arm64 --show-bin-path)/MuteAlert"
swift build -c release --arch x86_64
intel_bin="$(swift build -c release --arch x86_64 --show-bin-path)/MuteAlert"
app="dist/MuteAlert.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist/AppIcon.iconset
lipo -create "$arm_bin" "$intel_bin" -output "$app/Contents/MacOS/MuteAlert"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/icon.swift dist/AppIcon.iconset
iconutil -c icns dist/AppIcon.iconset -o "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app"
codesign --verify --deep --strict "$app"
lipo -info "$app/Contents/MacOS/MuteAlert"
ditto -c -k --sequesterRsrc --keepParent "$app" dist/MuteAlert-mac-universal.zip
