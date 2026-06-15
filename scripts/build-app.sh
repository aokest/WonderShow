#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="灵演"
APP_VERSION="0.6.0"
BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE="PresenterDirectorApp"
BUILD_EXECUTABLE="$ROOT_DIR/.build/arm64-apple-macosx/debug/$EXECUTABLE"

cd "$ROOT_DIR"
# SwiftPM manifest evaluation is sandboxed by default on macOS and fails in this repo path.
# Keep the bundle build path aligned with the verified local run command.
swift build --disable-sandbox

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"
cp "$BUILD_EXECUTABLE" "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE"
cp "$ROOT_DIR/examples/wondershow-demo.html" "$BUNDLE_DIR/Contents/Resources/wondershow-demo.html"
cp "$ROOT_DIR/Sources/PresenterDirectorApp/Resources/AppIcon.icns" "$BUNDLE_DIR/Contents/Resources/AppIcon.icns"

plutil -create xml1 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleExecutable -string "$EXECUTABLE" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "com.local.LingYan" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleName -string "$APP_NAME" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "$APP_NAME" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleIconFile -string "AppIcon" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleVersion -string "$APP_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string "$APP_VERSION" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert NSCameraUsageDescription -string "灵演需要访问摄像头，用于接入外接或内置输入设备并识别演讲手势。" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert NSAppleEventsUsageDescription -string "灵演需要控制 Google Chrome、PowerPoint、Keynote 等演示软件，用于根据手势执行翻页和播放控制。" "$BUNDLE_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$BUNDLE_DIR"

echo "$BUNDLE_DIR"
