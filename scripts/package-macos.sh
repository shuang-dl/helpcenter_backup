#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$PROJECT_DIR/dist"
BUILD_PATH="/tmp/helpcenterbackup-release-build"
APP_NAME="HelpCenterBackup"
APP_VERSION="${APP_VERSION:-1.05}"
APP_BUILD="${APP_BUILD:-2}"
APP_BUNDLE="$DIST_DIR/${APP_NAME}.app"
APP_BIN_NAME="HelpCenterBackup"
APP_EXECUTABLE="$APP_BUNDLE/Contents/MacOS/$APP_BIN_NAME"
ICON_SOURCE="${1:-/Users/samuelhuang/Desktop/icon.jpg}"
BG_SOURCE="${2:-$ICON_SOURCE}"
ICONSET_DIR="/tmp/${APP_NAME}.iconset"
ICNS_PATH="$PROJECT_DIR/Resources/AppIcon.icns"
DMG_STAGING="$DIST_DIR/dmg-staging"
DMG_BG_DIR="$DMG_STAGING/.background"
DMG_BG_FILE="$DMG_BG_DIR/background.png"
RW_DMG="$DIST_DIR/${APP_NAME}-temp.dmg"
FINAL_DMG="$DIST_DIR/${APP_NAME}.dmg"
VOLUME_NAME="$APP_NAME"

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Icon file not found: $ICON_SOURCE"
  exit 1
fi

if [[ ! -f "$BG_SOURCE" ]]; then
  echo "Background image not found: $BG_SOURCE"
  exit 1
fi

echo "Building release binary..."
cd "$PROJECT_DIR"
swift build -c release --build-path "$BUILD_PATH"

echo "Preparing app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_PATH/release/HelpCenterBackupApp" "$APP_EXECUTABLE"
chmod +x "$APP_EXECUTABLE"

echo "Generating .icns from $ICON_SOURCE ..."
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

sips -s format png -z 16 16     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -s format png -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -s format png -z 32 32     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -s format png -z 64 64     "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -s format png -z 128 128   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -s format png -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -s format png -z 256 256   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -s format png -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -s format png -z 512 512   "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -s format png -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null

iconutil -c icns "$ICONSET_DIR" -o "$ICNS_PATH"
cp "$ICNS_PATH" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>com.samuelhuang.helpcenterbackup</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD}</string>
  <key>CFBundleShortVersionString</key>
  <string>${APP_VERSION}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleExecutable</key>
  <string>${APP_BIN_NAME}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_BUNDLE"

echo "Preparing DMG staging folder..."
rm -rf "$DMG_STAGING" "$RW_DMG" "$FINAL_DMG"
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
mkdir -p "$DMG_BG_DIR"
sips -s format png "$BG_SOURCE" --out "$DMG_BG_FILE" >/dev/null

osascript <<APPLESCRIPT
 tell application "Finder"
   set stagingFolder to POSIX file "$DMG_STAGING" as alias
   if exists item "Applications" of stagingFolder then
     try
       delete item "Applications" of stagingFolder
     end try
   end if
   make new alias file at stagingFolder to POSIX file "/Applications" with properties {name:"Applications"}
 end tell
APPLESCRIPT

echo "Creating temporary DMG..."
hdiutil create -quiet -srcfolder "$DMG_STAGING" -volname "$VOLUME_NAME" -fs HFS+ -fsargs "-c c=64,a=16,e=16" -format UDRW "$RW_DMG"

ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW_DMG")
DEVICE=$(echo "$ATTACH_OUTPUT" | awk '/Apple_HFS/ {print $1; exit}')
MOUNT_POINT="/Volumes/$VOLUME_NAME"

if [[ -z "$DEVICE" ]]; then
  echo "Failed to mount DMG"
  exit 1
fi

echo "Configuring Finder layout..."
osascript <<APPLESCRIPT
 tell application "Finder"
   tell disk "$VOLUME_NAME"
     open
     delay 1
     set current view of container window to icon view
     set toolbar visible of container window to false
     set statusbar visible of container window to false
     set bounds of container window to {120, 120, 640, 440}
     set theViewOptions to the icon view options of container window
     set arrangement of theViewOptions to not arranged
     set icon size of theViewOptions to 120
     set text size of theViewOptions to 14
     set background picture of theViewOptions to file ".background:background.png"
     try
       set position of item "$APP_NAME.app" of container window to {170, 170}
     end try
     try
       set position of item "Applications" of container window to {430, 170}
     on error
       try
         set position of item "Applications" of disk "$VOLUME_NAME" to {430, 170}
       end try
     end try
     close
     open
     update without registering applications
   end tell
 end tell
APPLESCRIPT

sync
hdiutil detach "$DEVICE" -quiet

hdiutil convert "$RW_DMG" -quiet -format UDZO -imagekey zlib-level=9 -o "$FINAL_DMG"
rm -f "$RW_DMG"

echo "Done"
echo "App: $APP_BUNDLE"
echo "DMG: $FINAL_DMG"
