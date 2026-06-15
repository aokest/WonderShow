#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PATH="${PROJECT_ROOT}/.venv-mediapipe"

if [[ ! -d "${VENV_PATH}" ]]; then
  echo "[WonderShow] 未找到 .venv-mediapipe，请先运行 scripts/setup-mediapipe-sidecar.sh"
  exit 1
fi

source "${VENV_PATH}/bin/activate"
cd "${PROJECT_ROOT}"
python sidecar/server.py "$@"
