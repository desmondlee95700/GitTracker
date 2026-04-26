#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/GitTracker.app"
MACOS_DIR="$APP_DIR/Contents/MacOS"

mkdir -p "$MACOS_DIR"
env SWIFT_MODULECACHE_PATH=/tmp/swift-module-cache CLANG_MODULE_CACHE_PATH=/tmp/swift-clang-cache swiftc "$ROOT_DIR/GitTracker.swift" -o "$MACOS_DIR/GitTracker"
cp "$ROOT_DIR/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --deep --sign - "$APP_DIR"

echo "Built $APP_DIR"
