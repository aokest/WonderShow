#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "[security] WonderShow Core tests"
swift test --package-path open-source/wondershow-core

echo "[security] App security boundary tests"
swift test --disable-sandbox --filter SecurityBoundaryTests

echo "[security] Full app test suite"
swift test --disable-sandbox

echo "[security] Build app"
./scripts/build-app.sh

echo "[security] Package open-source kit"
./scripts/package-open-source-kit.sh

echo "[security] Signature verification"
codesign --verify --deep --strict --verbose=2 "dist/灵演.app"

echo "[security] Secret scan"
SECRET_SCAN_OUTPUT="$(rg -n "sk-[A-Za-z0-9]|dev-local-token-please-change" \
  open-source/wondershow-core sidecar scripts Sources Tests \
  -g '!sidecar/models/**' \
  -g '!scripts/security-release-verify.sh' || true)"
if [[ -n "$SECRET_SCAN_OUTPUT" ]]; then
  printf "%s\n" "$SECRET_SCAN_OUTPUT"
  echo "[security] Potential hardcoded secret found" >&2
  exit 1
fi

echo "[security] Done"
