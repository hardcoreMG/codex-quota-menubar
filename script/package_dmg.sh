#!/usr/bin/env bash
set -euo pipefail

APP_NAME="CodexQuotaBar"
DISPLAY_NAME="Codex额度菜单显示小工具"
BUNDLE_ID="com.kevinchin.CodexQuotaBar"
VERSION="0.1.5"
MIN_SYSTEM_VERSION="13.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/$APP_NAME-release-build.XXXXXX")"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
STAGING_DIR="$DIST_DIR/dmg"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
ICON_FILE="$ROOT_DIR/Assets/AppIcon.icns"
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon-Source.png"

trap 'rm -rf "$BUILD_DIR"' EXIT

cd "$ROOT_DIR"

swift build -c release --scratch-path "$BUILD_DIR"
BUILD_BINARY="$(swift build -c release --scratch-path "$BUILD_DIR" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE" "$STAGING_DIR" "$DMG_PATH"
mkdir -p "$APP_MACOS" "$APP_RESOURCES" "$STAGING_DIR"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ICON_FILE" "$APP_RESOURCES/AppIcon.icns"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$DISPLAY_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE"

cp -R "$APP_BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$ICON_FILE" "$STAGING_DIR/.VolumeIcon.icns"
if command -v SetFile >/dev/null 2>&1; then
  SetFile -a C "$STAGING_DIR"
  SetFile -a V "$STAGING_DIR/.VolumeIcon.icns"
fi

hdiutil create \
  -volname "$DISPLAY_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if command -v sips >/dev/null 2>&1 &&
  command -v DeRez >/dev/null 2>&1 &&
  command -v Rez >/dev/null 2>&1 &&
  command -v SetFile >/dev/null 2>&1; then
  DMG_ICON_SOURCE="$(mktemp /tmp/$APP_NAME-dmg-icon.XXXXXX.png)"
  DMG_ICON_RSRC="$(mktemp /tmp/$APP_NAME-dmg-icon.XXXXXX.rsrc)"
  cp "$ICON_SOURCE" "$DMG_ICON_SOURCE"
  sips -i "$DMG_ICON_SOURCE" >/dev/null
  DeRez -only icns "$DMG_ICON_SOURCE" >"$DMG_ICON_RSRC"
  Rez -append "$DMG_ICON_RSRC" -o "$DMG_PATH"
  SetFile -a C "$DMG_PATH"
  rm -f "$DMG_ICON_SOURCE" "$DMG_ICON_RSRC"
fi

codesign --force --sign - "$DMG_PATH"

echo "$DMG_PATH"
