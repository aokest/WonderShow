#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="灵演"
VERSION_FILE="$ROOT_DIR/VERSION"
BUILD_VERSION_FILE="$ROOT_DIR/BUILD_VERSION"

read_version_file() {
  local file="$1"
  if [[ -f "$file" ]]; then
    tr -d '[:space:]' < "$file"
  fi
}

DEFAULT_MARKETING_VERSION="$(read_version_file "$VERSION_FILE")"
DEFAULT_BUILD_VERSION="$(read_version_file "$BUILD_VERSION_FILE")"
APP_MARKETING_VERSION="${APP_MARKETING_VERSION:-${DEFAULT_MARKETING_VERSION:-1.0.0}}"
APP_BUILD_VERSION="${APP_BUILD_VERSION:-${DEFAULT_BUILD_VERSION:-$(date +%Y%m%d%H%M%S)}}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-release}"
BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE="PresenterDirectorApp"
BUILD_EXECUTABLE="$ROOT_DIR/.build/arm64-apple-macosx/$BUILD_CONFIGURATION/$EXECUTABLE"

cd "$ROOT_DIR"
# SwiftPM manifest evaluation is sandboxed by default on macOS and fails in this repo path.
# Release builds keep DEBUG-only local telemetry out of the app bundle.
swift build -c "$BUILD_CONFIGURATION" --disable-sandbox

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"
cp "$BUILD_EXECUTABLE" "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE"
cp "$ROOT_DIR/examples/wondershow-demo.html" "$BUNDLE_DIR/Contents/Resources/wondershow-demo.html"
cp "$ROOT_DIR/Sources/PresenterDirectorApp/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
if [[ -f "$ROOT_DIR/sidecar/models/wondershow_gesture_model.json" ]]; then
  mkdir -p "$BUNDLE_DIR/Contents/Resources/sidecar/models"
  cp "$ROOT_DIR/sidecar/models/wondershow_gesture_model.json" "$BUNDLE_DIR/Contents/Resources/sidecar/models/wondershow_gesture_model.json"
fi

plutil -create xml1 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleExecutable -string "$EXECUTABLE" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "com.local.LingYan" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleName -string "$APP_NAME" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "$APP_NAME" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleIconFile -string "AppIcon" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$APP_BUILD_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$APP_MARKETING_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert NSCameraUsageDescription -string "灵演需要访问摄像头，用于接入外接或内置输入设备并识别演讲手势。" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert NSMicrophoneUsageDescription -string "灵演需要访问麦克风，用于录制讲者声音并合成演讲或培训视频。" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert NSAppleEventsUsageDescription -string "灵演需要控制 Google Chrome、PowerPoint、Keynote 等演示软件，用于根据手势执行翻页和播放控制。" "$BUNDLE_DIR/Contents/Info.plist"

printf "APPL????" > "$BUNDLE_DIR/Contents/PkgInfo"

codesign --force --deep --sign - \
  --requirements '=designated => identifier "com.local.LingYan"' \
  "$BUNDLE_DIR"

touch "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"
touch "$BUNDLE_DIR/Contents/Info.plist"
touch "$BUNDLE_DIR/Contents/PkgInfo"
touch "$BUNDLE_DIR"

echo "$BUNDLE_DIR"
echo "version $APP_MARKETING_VERSION ($APP_BUILD_VERSION), configuration $BUILD_CONFIGURATION"
