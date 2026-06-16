#!/usr/bin/env bash
# Build RecallNotifier.app (ad-hoc signed) from main.swift.
# Usage: ./build.sh [output_dir]   (default: ./build)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
OUT="${1:-$HERE/build}"
APP="$OUT/RecallNotifier.app"
BIN="$APP/Contents/MacOS/RecallNotifier"

command -v swiftc >/dev/null || { echo "swiftc not found — install Xcode Command Line Tools (xcode-select --install)"; exit 1; }

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -o "$BIN" "$HERE/main.swift" -framework Cocoa -framework UserNotifications

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Recall Notifier</string>
  <key>CFBundleDisplayName</key><string>Recall</string>
  <key>CFBundleIdentifier</key><string>com.alielzei.recall.notifier</string>
  <key>CFBundleExecutable</key><string>RecallNotifier</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>11.0</string>
</dict>
</plist>
PLIST

codesign -s - --force --deep "$APP" >/dev/null 2>&1 || codesign -s - --force "$APP"
echo "built $APP"
