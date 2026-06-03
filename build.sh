#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Snipper"
BUNDLE_ID="com.version2.snipper"
ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$ROOT/.build/release"
APP_DIR="$ROOT/$APP_NAME.app"

# Stable self-signed signing identity (so macOS keeps the Screen Recording grant
# across rebuilds — ad-hoc signatures change every build and lose the grant).
# Set up once with ./trust-cert.sh. The keychain's password is random and lives
# only in .signing/keychain-pass (git-ignored) — never committed.
SIGN_KC="$HOME/Library/Keychains/snipper-codesign.keychain-db"
SIGN_ID="Snipper Code Signing"
SIGN_PASS_FILE="$ROOT/.signing/keychain-pass"

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

if [ -f "$SIGN_PASS_FILE" ]; then
  security unlock-keychain -p "$(cat "$SIGN_PASS_FILE")" "$SIGN_KC" 2>/dev/null || true
fi
if security find-identity -v -p codesigning "$SIGN_KC" 2>/dev/null | grep -q "$SIGN_ID"; then
  echo "▸ Code signing with stable identity '$SIGN_ID'…"
  # codesign only looks in the keychain search list — ensure ours is on it (idempotent).
  CURRENT=$(security list-keychains -d user | sed 's/"//g' | xargs)
  case " $CURRENT " in
    *" $SIGN_KC "*) : ;;
    *) security list-keychains -d user -s "$SIGN_KC" $CURRENT >/dev/null ;;
  esac
  codesign --force --deep --sign "$SIGN_ID" "$APP_DIR"
else
  echo "▸ Code signing (ad-hoc fallback — run ./trust-cert.sh for a stable identity)…"
  codesign --force --deep --sign - "$APP_DIR"
fi

echo "✓ Built: $APP_DIR"
echo "  Run with:  open \"$APP_DIR\""
