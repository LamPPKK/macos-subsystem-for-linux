#!/usr/bin/env bash
set -euo pipefail

ROOT_DIRECTORY=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ARCHIVE_PATH="${1:-$ROOT_DIRECTORY/dist/MSL-Settings-macOS.zip}"
STAGING_DIRECTORY=$(mktemp -d "${TMPDIR:-/tmp}/msl-settings-package.XXXXXX")

cleanup() {
  rm -rf "$STAGING_DIRECTORY"
}
trap cleanup EXIT

mkdir -p "$(dirname "$ARCHIVE_PATH")"
"$ROOT_DIRECTORY/scripts/build-app.sh" "$STAGING_DIRECTORY/MSL Settings.app"
ditto -c -k --sequesterRsrc --keepParent \
  "$STAGING_DIRECTORY/MSL Settings.app" \
  "$ARCHIVE_PATH"
unzip -t "$ARCHIVE_PATH" >/dev/null
printf 'Packaged %s\n' "$ARCHIVE_PATH"
