#!/usr/bin/env bash
set -euo pipefail

ROOT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PACKAGE_DIRECTORY="$ROOT_DIRECTORY/App/MSLSettings"
BUILD_DIRECTORY="${MSL_APP_BUILD_ROOT:-$ROOT_DIRECTORY/.build/msl-settings}"
APP_DIRECTORY="${1:-$ROOT_DIRECTORY/dist/MSL Settings.app}"
TARGET_TRIPLE="${MSL_APP_TRIPLE:-arm64-apple-macosx13.0}"

APP_BASENAME=$(basename "$APP_DIRECTORY")
APP_PARENT_INPUT=$(dirname "$APP_DIRECTORY")
if [[ "$APP_BASENAME" != *.app || "$APP_BASENAME" == ".app" ]]; then
  printf 'error: app output must be a named .app bundle\n' >&2
  exit 1
fi
mkdir -p "$APP_PARENT_INPUT"
APP_PARENT=$(cd "$APP_PARENT_INPUT" && pwd -P)
APP_DIRECTORY="$APP_PARENT/$APP_BASENAME"
case "$APP_DIRECTORY" in
  /|"$HOME"|"$ROOT_DIRECTORY"|"$PACKAGE_DIRECTORY"|"$BUILD_DIRECTORY")
    printf 'error: refusing unsafe app output path: %s\n' "$APP_DIRECTORY" >&2
    exit 1
    ;;
esac
if [[ -L "$APP_DIRECTORY" || ( -e "$APP_DIRECTORY" && ! -d "$APP_DIRECTORY" ) ]]; then
  printf 'error: app output must not be a symlink or regular file: %s\n' "$APP_DIRECTORY" >&2
  exit 1
fi
CONTENTS_DIRECTORY="$APP_DIRECTORY/Contents"

command -v xcrun >/dev/null 2>&1 || { printf 'error: Xcode or Command Line Tools are required\n' >&2; exit 1; }
command -v codesign >/dev/null 2>&1 || { printf 'error: codesign is required\n' >&2; exit 1; }

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

mkdir -p "$BUILD_DIRECTORY/module-cache"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIRECTORY/module-cache"
export SWIFT_MODULECACHE_PATH="$BUILD_DIRECTORY/module-cache"

xcrun swift build --disable-sandbox \
  --package-path "$PACKAGE_DIRECTORY" \
  --scratch-path "$BUILD_DIRECTORY/swift" \
  --triple "$TARGET_TRIPLE" \
  --configuration release

BIN_DIRECTORY=$(xcrun swift build --disable-sandbox \
  --package-path "$PACKAGE_DIRECTORY" \
  --scratch-path "$BUILD_DIRECTORY/swift" \
  --triple "$TARGET_TRIPLE" \
  --configuration release \
  --show-bin-path)

rm -rf -- "$APP_DIRECTORY"
mkdir -p \
  "$CONTENTS_DIRECTORY/MacOS" \
  "$CONTENTS_DIRECTORY/Resources/bin" \
  "$CONTENTS_DIRECTORY/Resources/images/ubuntu-machine"
install -m 0755 "$BIN_DIRECTORY/MSLSettingsApp" "$CONTENTS_DIRECTORY/MacOS/MSLSettings"
install -m 0644 "$PACKAGE_DIRECTORY/Resources/Info.plist" "$CONTENTS_DIRECTORY/Info.plist"
install -m 0755 "$ROOT_DIRECTORY/bin/msl-arm" "$CONTENTS_DIRECTORY/Resources/bin/msl-arm"
install -m 0644 \
  "$ROOT_DIRECTORY/images/ubuntu-machine/Containerfile" \
  "$CONTENTS_DIRECTORY/Resources/images/ubuntu-machine/Containerfile"

if command -v xattr >/dev/null 2>&1; then
  xattr -cr "$APP_DIRECTORY"
  xattr -d com.apple.FinderInfo "$APP_DIRECTORY" 2>/dev/null || true
fi
codesign --force --deep --sign - "$APP_DIRECTORY"
printf 'Built %s\n' "$APP_DIRECTORY"
