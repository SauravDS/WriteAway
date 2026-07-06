#!/bin/bash
set -e

APP_NAME="WriteAway"
BUILD_DIR=".build/release"
APP_DIR="$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "Building release..."
swift build -c release

echo "Creating app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

cp "$BUILD_DIR/$APP_NAME" "$MACOS_DIR/"
cp Info.plist "$CONTENTS_DIR/"

echo "Done! App bundle created at $APP_DIR"
