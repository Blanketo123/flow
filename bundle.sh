#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo ">>> swift build -c release"
swift build -c release

APP="Flow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Flow "$APP/Contents/MacOS/Flow"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Flow</string>
    <key>CFBundleIdentifier</key><string>com.tobi.flow</string>
    <key>CFBundleName</key><string>Flow</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSMicrophoneUsageDescription</key><string>Flow needs the microphone to dictate text.</string>
    <key>NSAppleEventsUsageDescription</key><string>Flow injects transcribed text via keyboard events.</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo ">>> done. Built: $(pwd)/$APP"
echo "    open Flow.app"
