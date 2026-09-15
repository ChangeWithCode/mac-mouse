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

# A universal build goes through XCBuild, which ships with Xcode and not with
# the Command Line Tools alone. Rather than failing on a machine that has a
# perfectly good Swift toolchain, fall back to this Mac's own architecture.
ARCH_FLAGS=(--arch arm64 --arch x86_64)
XCBUILD="$(xcode-select -p 2>/dev/null)/../SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild"
if [[ ! -x "$XCBUILD" && ! -x "/Library/Developer/SharedFrameworks/XCBuild.framework/Versions/A/Support/xcbuild" ]]; then
  ARCH_FLAGS=()
  echo "note: no Xcode found (only Command Line Tools), so this build is" >&2
  echo "      $(uname -m)-only. Install Xcode for a universal binary." >&2
fi

if [[ ${#ARCH_FLAGS[@]} -gt 0 ]]; then
  echo "==> Building ($CONFIG, universal)"
else
  echo "==> Building ($CONFIG, $(uname -m))"
fi
swift build -c "$CONFIG" ${ARCH_FLAGS+"${ARCH_FLAGS[@]}"}

BINARY=$(swift build -c "$CONFIG" ${ARCH_FLAGS+"${ARCH_FLAGS[@]}"} --show-bin-path)/Glide
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
