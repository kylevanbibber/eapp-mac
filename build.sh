#!/bin/bash
# Build "Install eApp.app" + Install-eApp.dmg from src/. Signed, not yet notarized.
# Usage: ./build.sh [version]       Then: ./notarize.sh
set -euo pipefail
cd "$(dirname "$0")"
VER="${1:-1.0}"
SRC="${SRC:-src}"; DIST="${DIST:-dist}"; APPNAME="${APPNAME:-Install eApp}"; BUNDLE_ID="${BUNDLE_ID:-com.callwithtally.eapp-mac-installer}"
ID="Developer ID Application: Kyle VanBibber (B8MFVFT62V)"
APP="$DIST/$APPNAME.app"
rm -rf "$DIST"; mkdir -p "$DIST"
bash -n "$SRC/install.sh"
osacompile -o "$APP" "$SRC/installer.applescript"
cp "$SRC/install.sh" "$APP/Contents/Resources/install.sh"; chmod 755 "$APP/Contents/Resources/install.sh"
cp "$SRC/READ ME FIRST.txt" "$APP/Contents/Resources/"
PL="$APP/Contents/Info.plist"
pb(){ /usr/libexec/PlistBuddy -c "$1" "$PL" >/dev/null 2>&1 || true; }
pb "Add :CFBundleIdentifier string $BUNDLE_ID"; pb "Set :CFBundleIdentifier $BUNDLE_ID"
pb "Add :CFBundleName string $APPNAME"; pb "Set :CFBundleName $APPNAME"
pb "Add :CFBundleDisplayName string $APPNAME"; pb "Set :CFBundleDisplayName $APPNAME"
pb "Add :CFBundleShortVersionString string $VER"; pb "Set :CFBundleShortVersionString $VER"
pb "Add :CFBundleVersion string $VER";            pb "Set :CFBundleVersion $VER"
pb "Add :LSMinimumSystemVersion string 12.0"
pb "Add :NSAppleEventsUsageDescription string Install eApp opens Terminal to run the installer and show its progress."
codesign --force --deep --options runtime --timestamp --entitlements "$SRC/entitlements.plist" --sign "$ID" "$APP"
codesign --verify --deep --strict "$APP"
# DMG is rebuilt by notarize.sh after the app is stapled; this one is for local inspection.
STAGE="$DIST/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; cp "$SRC/READ ME FIRST.txt" "$STAGE/Read Me First.txt"
hdiutil create -quiet -volname "$APPNAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Install-eApp.dmg"
codesign --force --timestamp --sign "$ID" "$DIST/Install-eApp.dmg"
rm -rf "$STAGE"
echo "built: $APP  (v$VER)  and $DIST/Install-eApp.dmg  (not notarized yet)"
