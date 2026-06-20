#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_PATH="${PROJECT_ROOT}/.venv-mediapipe"
MODEL_DIR="${PROJECT_ROOT}/sidecar/models"
MODEL_PATH="${MODEL_DIR}/gesture_recognizer.task"
MODEL_URL="https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/1/gesture_recognizer.task"
HAND_MODEL_PATH="${MODEL_DIR}/hand_landmarker.task"
HAND_MODEL_URL="https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/1/hand_landmarker.task"
FACE_MODEL_PATH="${MODEL_DIR}/face_landmarker.task"
FACE_MODEL_URL="https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"
SEGMENTER_MODEL_PATH="${MODEL_DIR}/selfie_multiclass_256x256.tflite"
SEGMENTER_MODEL_URL="https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_multiclass_256x256/float32/latest/selfie_multiclass_256x256.tflite"

echo "[WonderShow] 创建 MediaPipe 虚拟环境..."
python3 -m venv "${VENV_PATH}"

echo "[WonderShow] 安装依赖..."
source "${VENV_PATH}/bin/activate"
python -m pip install --upgrade pip
python -m pip install -r "${PROJECT_ROOT}/sidecar/requirements.txt"

echo "[WonderShow] 检查手势模型..."
mkdir -p "${MODEL_DIR}"
if [[ -f "${MODEL_PATH}" ]]; then
  echo "[WonderShow] 已存在模型文件：${MODEL_PATH}"
else
  echo "[WonderShow] 下载官方 gesture_recognizer.task ..."
  curl -L "${MODEL_URL}" -o "${MODEL_PATH}"
  echo "[WonderShow] 模型已下载到：${MODEL_PATH}"
fi

if [[ -f "${HAND_MODEL_PATH}" ]]; then
  echo "[WonderShow] 已存在模型文件：${HAND_MODEL_PATH}"
else
  echo "[WonderShow] 下载官方 hand_landmarker.task ..."
  curl -L "${HAND_MODEL_URL}" -o "${HAND_MODEL_PATH}"
  echo "[WonderShow] 模型已下载到：${HAND_MODEL_PATH}"
fi

if [[ -f "${FACE_MODEL_PATH}" ]]; then
  echo "[WonderShow] 已存在模型文件：${FACE_MODEL_PATH}"
else
  echo "[WonderShow] 下载官方 face_landmarker.task ..."
  curl -L "${FACE_MODEL_URL}" -o "${FACE_MODEL_PATH}"
  echo "[WonderShow] 模型已下载到：${FACE_MODEL_PATH}"
fi

if [[ -f "${SEGMENTER_MODEL_PATH}" ]]; then
  echo "[WonderShow] 已存在模型文件：${SEGMENTER_MODEL_PATH}"
else
  echo "[WonderShow] 下载官方 selfie_multiclass_256x256.tflite ..."
  curl -L "${SEGMENTER_MODEL_URL}" -o "${SEGMENTER_MODEL_PATH}"
  echo "[WonderShow] 模型已下载到：${SEGMENTER_MODEL_PATH}"
fi

cat <<'EOF'

[WonderShow] 安装完成。

下一步：
1. 执行：

   source .venv-mediapipe/bin/activate
   python sidecar/server.py

EOF
