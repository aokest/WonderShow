#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="灵演手势采样器"
APP_VERSION="0.1.0"
BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE="WonderShowGestureSampler"
PYTHON_BIN="$ROOT_DIR/.venv-mediapipe/bin/python"

if [[ ! -x "$PYTHON_BIN" ]]; then
  echo "[WonderShow] 未找到 .venv-mediapipe/bin/python，请先运行 scripts/setup-mediapipe-sidecar.sh"
  exit 1
fi

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"

if [[ -f "$ROOT_DIR/Sources/WonderShowApp/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Sources/WonderShowApp/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE" <<EOF
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$ROOT_DIR"
cd "\$ROOT_DIR"
exec "$PYTHON_BIN" "\$ROOT_DIR/scripts/capture_gesture_samples.py" --camera auto --label "剑指"
EOF
chmod +x "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE"

plutil -create xml1 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleExecutable -string "$EXECUTABLE" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "com.wondershow.gesture-sampler" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleName -string "$APP_NAME" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "$APP_NAME" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleIconFile -string "AppIcon" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$APP_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert NSCameraUsageDescription -string "灵演手势采样器需要访问摄像头，用于采集你的真实手势训练样本。" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert NSHighResolutionCapable -bool true "$BUNDLE_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$BUNDLE_DIR"

echo "$BUNDLE_DIR"
