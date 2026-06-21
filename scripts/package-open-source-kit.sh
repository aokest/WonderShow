#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_VERSION_FILE="$ROOT_DIR/BUILD_VERSION"
SOURCE_DIR="$ROOT_DIR/open-source/wondershow-core"
STAGING_ROOT="$ROOT_DIR/.build/open-source-release"

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

PACKAGE_NAME="wondershow-core-${VERSION}-${BUILD_VERSION}"
PACKAGE_DIR="$STAGING_ROOT/$PACKAGE_NAME"
OUTPUT_DIR="$ROOT_DIR/releases"
OUTPUT_ZIP="$OUTPUT_DIR/$PACKAGE_NAME.zip"
OUTPUT_SHA="$OUTPUT_ZIP.sha256"

rm -rf "$STAGING_ROOT"
mkdir -p "$PACKAGE_DIR" "$OUTPUT_DIR"

cp -R "$SOURCE_DIR"/. "$PACKAGE_DIR"/
find "$PACKAGE_DIR" -name '.DS_Store' -delete
rm -rf "$PACKAGE_DIR/.build" "$PACKAGE_DIR/.swiftpm"

(cd "$STAGING_ROOT" && zip -qry "$OUTPUT_ZIP" "$PACKAGE_NAME")
(cd "$OUTPUT_DIR" && shasum -a 256 "$(basename "$OUTPUT_ZIP")") > "$OUTPUT_SHA"

echo "$OUTPUT_ZIP"
