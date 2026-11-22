#!/bin/bash
# Builds a release binary and wraps it in DLiveRemote.app (run on macOS with Xcode/CLT installed).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/DLiveRemote"
APP="build/DLiveRemote.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DLiveRemote"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>dLive Remote</string>
    <key>CFBundleDisplayName</key><string>dLive Remote</string>
    <key>CFBundleIdentifier</key><string>local.dliveremote</string>
    <key>CFBundleExecutable</key><string>DLiveRemote</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>dLive Remote connects to your Allen &amp; Heath dLive MixRack or Surface on the local network.</string>
</dict>
</plist>
PLIST

# Ad-hoc sign so macOS will launch it locally.
codesign --force --deep --sign - "$APP"
echo "Built $APP"
