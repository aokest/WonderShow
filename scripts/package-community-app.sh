#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_VERSION_FILE="$ROOT_DIR/BUILD_VERSION"
STAGING_ROOT="$ROOT_DIR/.build/community-release"
OUTPUT_DIR="$ROOT_DIR/releases"

read_version_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tr -d '[:space:]' < "$file"
  fi
}

VERSION="$(read_version_file "$VERSION_FILE")"
BUILD_VERSION="$(read_version_file "$BUILD_VERSION_FILE")"
VERSION="${VERSION:-1.0.0}"
BUILD_VERSION="${BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"

APP_EDITION=community "$ROOT_DIR/scripts/build-app.sh" >/tmp/wondershow-community-build.log

APP_NAME="灵演社区版"
APP_PATH="$ROOT_DIR/dist/$APP_NAME.app"
PACKAGE_NAME="wondershow-community-${VERSION}-${BUILD_VERSION}-macos"
PACKAGE_DIR="$STAGING_ROOT/$PACKAGE_NAME"
OUTPUT_ZIP="$OUTPUT_DIR/$PACKAGE_NAME.zip"
OUTPUT_SHA="$OUTPUT_ZIP.sha256"

rm -rf "$STAGING_ROOT"
mkdir -p "$PACKAGE_DIR" "$OUTPUT_DIR"
cp -R "$APP_PATH" "$PACKAGE_DIR/"
find "$PACKAGE_DIR" -name '.DS_Store' -delete
find "$PACKAGE_DIR" -name '__MACOSX' -type d -prune -exec rm -rf {} +

(cd "$STAGING_ROOT" && zip -qry "$OUTPUT_ZIP" "$PACKAGE_NAME")
shasum -a 256 "$OUTPUT_ZIP" > "$OUTPUT_SHA"

echo "$OUTPUT_ZIP"
