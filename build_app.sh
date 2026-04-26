#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/GitTracker.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"
RESOURCES_DIR="$APP_DIR/Contents/Resources"

mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Compile the app
env SWIFT_MODULECACHE_PATH=/tmp/swift-module-cache CLANG_MODULE_CACHE_PATH=/tmp/swift-clang-cache swiftc "$ROOT_DIR/GitTracker.swift" -o "$MACOS_DIR/GitTracker"

# Generate Icon
swift "$ROOT_DIR/generate_icon.swift"
ICONSET="$ROOT_DIR/AppIcon.iconset"
mkdir -p "$ICONSET"
sips -z 16 16     "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_16x16.png"
sips -z 32 32     "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_16x16@2x.png"
sips -z 32 32     "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_32x32.png"
sips -z 64 64     "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_32x32@2x.png"
sips -z 128 128   "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_128x128.png"
sips -z 256 256   "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_128x128@2x.png"
sips -z 256 256   "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_256x256.png"
sips -z 512 512   "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_256x256@2x.png"
sips -z 512 512   "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_512x512.png"
sips -z 1024 1024 "$ROOT_DIR/AppIcon.png" --out "$ICONSET/icon_512x512@2x.png"
iconutil -c icns "$ICONSET" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET" "$ROOT_DIR/AppIcon.png"

# Copy Info.plist
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"

# Sign the app
codesign --force --deep --sign - "$APP_DIR"

# Ensure the /Applications link is correct
rm -f /Applications/GitTracker.app
ln -s "$APP_DIR" /Applications/GitTracker.app

echo "Built and Linked $APP_DIR"
