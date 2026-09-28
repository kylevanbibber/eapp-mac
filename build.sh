#!/bin/bash
# Build "Install eApp.app" + Install-eApp.dmg from src/. Signed, not yet notarized.
# Usage: ./build.sh [version]       Then: ./notarize.sh
set -euo pipefail
cd "$(dirname "$0")"
VER="${1:-1.0}"
ID="Developer ID Application: Kyle VanBibber (B8MFVFT62V)"
APP="dist/Install eApp.app"
rm -rf dist; mkdir -p dist
bash -n src/install.sh
osacompile -o "$APP" src/installer.applescript
cp src/install.sh "$APP/Contents/Resources/install.sh"; chmod 755 "$APP/Contents/Resources/install.sh"
cp "src/READ ME FIRST.txt" "$APP/Contents/Resources/"
PL="$APP/Contents/Info.plist"
pb(){ /usr/libexec/PlistBuddy -c "$1" "$PL" >/dev/null 2>&1 || true; }
pb "Set :CFBundleIdentifier com.callwithtally.eapp-mac-installer"
pb "Set :CFBundleName Install eApp"
pb "Add :CFBundleDisplayName string Install eApp"
pb "Add :CFBundleShortVersionString string $VER"; pb "Set :CFBundleShortVersionString $VER"
pb "Add :CFBundleVersion string $VER";            pb "Set :CFBundleVersion $VER"
pb "Add :LSMinimumSystemVersion string 12.0"
pb "Add :NSAppleEventsUsageDescription string Install eApp opens Terminal to run the installer and show its progress."
codesign --force --deep --options runtime --timestamp --entitlements src/entitlements.plist --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"
# DMG is rebuilt by notarize.sh after the app is stapled; this one is for local inspection.
STAGE=dist/stage; rm -rf "$STAGE"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; cp "src/READ ME FIRST.txt" "$STAGE/Read Me First.txt"
hdiutil create -quiet -volname "Install eApp" -srcfolder "$STAGE" -ov -format UDZO dist/Install-eApp.dmg
codesign --force --timestamp --sign "$ID" dist/Install-eApp.dmg
rm -rf "$STAGE"
echo "built: $APP  (v$VER)  and dist/Install-eApp.dmg  (not notarized yet)"
