#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="灵演"
BUNDLE_DIR="$ROOT_DIR/dist/$APP_NAME.app"
EXECUTABLE="PresenterDirectorApp"
BUILD_EXECUTABLE="$ROOT_DIR/.build/arm64-apple-macosx/debug/$EXECUTABLE"

cd "$ROOT_DIR"
swift build

rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS" "$BUNDLE_DIR/Contents/Resources"
cp "$BUILD_EXECUTABLE" "$BUNDLE_DIR/Contents/MacOS/$EXECUTABLE"
cp "$ROOT_DIR/examples/wondershow-demo.html" "$BUNDLE_DIR/Contents/Resources/wondershow-demo.html"

plutil -create xml1 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleExecutable -string "$EXECUTABLE" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "com.local.LingYan" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleName -string "$APP_NAME" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleDisplayName -string "$APP_NAME" "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundlePackageType -string APPL "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleVersion -string 0.2.0 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert CFBundleShortVersionString -string 0.2.0 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string 14.0 "$BUNDLE_DIR/Contents/Info.plist"
plutil -insert NSCameraUsageDescription -string "灵演需要访问摄像头，用于接入 DJI Osmo Pocket 3 的演讲画面。" "$BUNDLE_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$BUNDLE_DIR"

echo "$BUNDLE_DIR"
