#!/usr/bin/env bash
#
# Assembles Glide.app from the SwiftPM executable.
#
# SwiftPM produces a bare binary, but Glide needs a real bundle: an event tap
# requires Accessibility permission, and macOS grants that to a bundle
# identifier, not to a loose executable.
#
# The version comes from the top-level VERSION file and is stamped into the
# bundle's Info.plist, so a build can always be identified from the app itself.
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

# VERSION is the single source of truth. Resources/Info.plist only carries
# placeholders; the numbers are written into the bundle's copy here, which must
# happen before codesign because the signature covers Info.plist.
VERSION=$(tr -d '[:space:]' < VERSION)
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: VERSION must hold a MAJOR.MINOR.PATCH number, found '$VERSION'." >&2
  exit 1
fi

# CFBundleVersion has to increase between builds that share a marketing
# version, or macOS treats an update as the same build. The commit count does
# that on its own; it falls back to 0 outside a git checkout (a source tarball),
# where there is nothing to count.
BUILD=$(git rev-list --count HEAD 2>/dev/null || echo 0)

PLISTBUDDY=/usr/libexec/PlistBuddy
if [[ ! -x "$PLISTBUDDY" ]]; then
  echo "error: $PLISTBUDDY not found, so the version cannot be stamped." >&2
  exit 1
fi
"$PLISTBUDDY" -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
"$PLISTBUDDY" -c "Set :CFBundleVersion $VERSION.$BUILD" "$APP/Contents/Info.plist"
echo "==> Version $VERSION (build $VERSION.$BUILD)"

echo "==> Signing (identity: $IDENTITY)"
if [[ "$IDENTITY" == "-" ]]; then
  # An ad-hoc signature normally pins the Accessibility grant to this build's
  # cdhash, which changes on every compile — so the permission silently
  # evaporates each rebuild and Glide "stops working". A designated requirement
  # that names only the bundle identifier gives TCC something stable to pin;
  # a re-grant is then needed only when the identifier changes, not per build.
  if ! codesign --force --options runtime --sign "$IDENTITY" \
       --requirements 'designated => identifier "com.glide.app"' "$APP" 2>/dev/null; then
    echo "note: could not apply a stable designated requirement; falling back to a plain ad-hoc signature" >&2
    echo "note: the Accessibility grant will need re-granting after each rebuild" >&2
    codesign --force --options runtime --sign "$IDENTITY" "$APP"
  fi
else
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
fi

cat <<NOTE

Built $APP — version $VERSION ($VERSION.$BUILD)

  open $APP

Note on Accessibility permission: macOS ties it to the code signature. With
ad-hoc signing ("-") the signature changes on every build, so the permission
must be re-granted each time — remove the stale "Glide" entry in
System Settings > Privacy & Security > Accessibility before re-adding it.
Signing with a real Developer ID makes the grant stick across builds.
NOTE
