#!/bin/bash
# Notarize + staple the app, then rebuild, notarize and staple the DMG.
# Needs a keychain profile made once with:
#   xcrun notarytool store-credentials eapp-mac-notary --apple-id YOU@EXAMPLE.COM --team-id B8MFVFT62V
# (it prompts for an app-specific password from appleid.apple.com; nothing is stored in this repo)
set -euo pipefail
cd "$(dirname "$0")"
PROFILE="${NOTARY_PROFILE:-eapp-mac-notary}"
ID="Developer ID Application: Kyle VanBibber (B8MFVFT62V)"
SRC="${SRC:-src}"; DIST="${DIST:-dist}"; APPNAME="${APPNAME:-Install eApp}"
APP="$DIST/$APPNAME.app"
[ -d "$APP" ] || { echo "run ./build.sh first"; exit 1; }
echo "== 1/4 notarize the app"
ditto -c -k --keepParent "$APP" "$DIST/app.zip"
xcrun notarytool submit "$DIST/app.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"
rm -f "$DIST/app.zip"
echo "== 2/4 rebuild the DMG around the stapled app"
STAGE="$DIST/stage"; rm -rf "$STAGE"; mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; cp "$SRC/READ ME FIRST.txt" "$STAGE/Read Me First.txt"
hdiutil create -quiet -volname "$APPNAME" -srcfolder "$STAGE" -ov -format UDZO "$DIST/Install-eApp.dmg"
codesign --force --timestamp --sign "$ID" "$DIST/Install-eApp.dmg"
rm -rf "$STAGE"
echo "== 3/4 notarize the DMG"
xcrun notarytool submit "$DIST/Install-eApp.dmg" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DIST/Install-eApp.dmg"
echo "== 4/4 verify like a fresh Mac would"
xcrun stapler validate "$DIST/Install-eApp.dmg"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DIST/Install-eApp.dmg"
spctl --assess --type execute --verbose=2 "$APP"
echo "READY: $DIST/Install-eApp.dmg"
