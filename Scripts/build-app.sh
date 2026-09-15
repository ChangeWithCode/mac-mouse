#!/usr/bin/env bash
#
# Assembles Glide.app from the SwiftPM executable.
#
# SwiftPM produces a bare binary, but Glide needs a real bundle: an event tap
# requires Accessibility permission, and macOS grants that to a bundle
# identifier, not to a loose executable.
#
# Usage:  Scripts/build-app.sh [--debug] [--sign IDENTITY]

set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=release
IDENTITY="-"   # ad-hoc

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) CONFIG=debug; shift ;;
    --sign)  IDENTITY="$2"; shift 2 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "error: no Swift toolchain found. Install Xcode or the Swift toolchain." >&2
  exit 1
fi

echo "==> Building ($CONFIG, universal)"
swift build -c "$CONFIG" --arch arm64 --arch x86_64

BINARY=$(swift build -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)/Glide
APP=dist/Glide.app

echo "==> Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/Glide"
cp Resources/Info.plist "$APP/Contents/Info.plist"

echo "==> Signing (identity: $IDENTITY)"
codesign --force --options runtime --sign "$IDENTITY" "$APP"

cat <<NOTE

Built $APP

  open $APP

Note on Accessibility permission: macOS ties it to the code signature. With
ad-hoc signing ("-") the signature changes on every build, so the permission
must be re-granted each time — remove the stale "Glide" entry in
System Settings > Privacy & Security > Accessibility before re-adding it.
Signing with a real Developer ID makes the grant stick across builds.
NOTE
