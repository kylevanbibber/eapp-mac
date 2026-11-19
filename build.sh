#!/bin/bash
# Build "Install eApp.app" + Install-eApp.dmg from src/. Signed, not yet notarized.
# Usage: ./build.sh       Then: ./notarize.sh
# The version comes from EAPP_MAC_VERSION in $SRC/install.sh (the one place to change it).
# An argument, if given, must match it.
set -euo pipefail
cd "$(dirname "$0")"
SRC="${SRC:-src}"; DIST="${DIST:-dist}"; APPNAME="${APPNAME:-Install eApp}"; BUNDLE_ID="${BUNDLE_ID:-com.callwithtally.eapp-mac-installer}"
VER=$(sed -nE 's/^EAPP_MAC_VERSION="([0-9.]+)"$/\1/p' "$SRC/install.sh")
[ -n "$VER" ] || { echo "EAPP_MAC_VERSION is missing in $SRC/install.sh"; exit 1; }
if [ -n "${1:-}" ] && [ "$1" != "$VER" ]; then echo "asked for $1 but $SRC/install.sh says $VER"; exit 1; fi
TAG=$(sed -nE 's/^EAPP_MAC_TAG="([^"]+)".*/\1/p' "$SRC/install.sh" | sed "s/\$EAPP_MAC_VERSION/$VER/")
ID="Developer ID Application: Kyle VanBibber (B8MFVFT62V)"
APP="$DIST/$APPNAME.app"
rm -rf "$DIST"; mkdir -p "$DIST"
bash -n "$SRC/install.sh"
osacompile -o "$APP" "$SRC/installer.applescript"
cp "$SRC/install.sh" "$APP/Contents/Resources/install.sh"; chmod 755 "$APP/Contents/Resources/install.sh"
cp "$SRC/READ ME FIRST.txt" "$APP/Contents/Resources/"
[ -f bin/wmp.dll ] || { echo "bin/wmp.dll is missing (see patches/README.md)"; exit 1; }
cp bin/wmp.dll "$APP/Contents/Resources/wmp.dll"
for f in bin/AtlasEappAddin.dll bin/0Harmony.dll fonts/atlas-toolbar-icons.ttf src/form-fix.sh; do
  [ -f "$f" ] || { echo "$f is missing"; exit 1; }
  cp "$f" "$APP/Contents/Resources/$(basename "$f")"
done
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
echo "release tag: $TAG  (the installer downloads its extra files from this tag)"
