#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_VERSION_FILE="$ROOT_DIR/BUILD_VERSION"

marketing_version="${APP_MARKETING_VERSION:-1.0.0}"
if [[ -f "$VERSION_FILE" ]]; then
  existing_version="$(tr -d '[:space:]' < "$VERSION_FILE")"
  if [[ -n "$existing_version" ]]; then
    marketing_version="$existing_version"
  fi
fi

build_version="${APP_BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}"

printf "%s\n" "$marketing_version" > "$VERSION_FILE"
printf "%s\n" "$build_version" > "$BUILD_VERSION_FILE"

if [[ "${1:-}" == "--stage" ]]; then
  git -C "$ROOT_DIR" add "$VERSION_FILE" "$BUILD_VERSION_FILE"
fi

echo "version $marketing_version ($build_version)"
