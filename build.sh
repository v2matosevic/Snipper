#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Snipper"
BUNDLE_ID="com.version2.snipper"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/$APP_NAME.app"

echo "▸ Building $APP_NAME (release)…"
swift build -c release --package-path "$ROOT"

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BUILD_DIR/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key><string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleExecutable</key><string>${APP_NAME}</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Version2</string>
</dict>
</plist>
PLIST

echo "▸ Code signing (ad-hoc)…"
codesign --force --deep --sign - "$APP_DIR"

echo "✓ Built: $APP_DIR"
echo "  Run with:  open \"$APP_DIR\""
