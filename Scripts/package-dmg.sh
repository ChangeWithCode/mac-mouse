#!/usr/bin/env bash
#
# Packages dist/Glide.app into a drag-to-install disk image.
#
# The result is the thing a person actually downloads: open it, drag Glide to
# the Applications alias sitting next to it, done. Run Scripts/build-app.sh
# first.

set -euo pipefail
cd "$(dirname "$0")/.."

APP=dist/Glide.app
STAGING=dist/dmg
DMG=dist/Glide.dmg

if [[ ! -d "$APP" ]]; then
  echo "error: $APP not found. Run Scripts/build-app.sh first." >&2
  exit 1
fi

echo "==> Staging"
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
# The Applications alias is what makes the window a drag-to-install target
# rather than a folder someone has to figure out.
ln -s /Applications "$STAGING/Applications"

echo "==> Creating $DMG"
hdiutil create \
  -volname "Glide" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG"

rm -rf "$STAGING"

SIZE=$(du -h "$DMG" | cut -f1)
cat <<NOTE

Built $DMG ($SIZE)

This image is not notarised, so macOS will refuse to open it on first launch.
To get past that, right-click Glide in Applications and choose Open, then
confirm — this only has to be done once.

To distribute it without that step, notarise with an Apple Developer account:

  Scripts/build-app.sh --sign "Developer ID Application: YOUR NAME (TEAMID)"
  xcrun notarytool submit dist/Glide.dmg --keychain-profile NOTARY --wait
  xcrun stapler staple dist/Glide.dmg
NOTE
