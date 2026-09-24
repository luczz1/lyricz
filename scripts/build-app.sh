#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$PROJECT_DIR/dist/Lyricz.app"
# Keep the existing bundle directory when upgrading the old name.
if [ -d "$PROJECT_DIR/dist/Lyrics Bar.app" ] && [ ! -e "$APP_DIR" ]; then
    mv "$PROJECT_DIR/dist/Lyrics Bar.app" "$APP_DIR"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
if [ -f "$APP_DIR/Contents/MacOS/SpotifyLyricsBar" ] && [ ! -e "$APP_DIR/Contents/MacOS/Lyricz" ]; then
    mv "$APP_DIR/Contents/MacOS/SpotifyLyricsBar" "$APP_DIR/Contents/MacOS/Lyricz"
fi
cp "$BIN_DIR/Lyricz" "$APP_DIR/Contents/MacOS/Lyricz"
cp Resources/Info.plist "$APP_DIR/Contents/Info.plist"

swift scripts/make-icon.swift "$PROJECT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$PROJECT_DIR/.build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign "${SIGN_IDENTITY:--}" --options runtime \
    --entitlements Resources/SpotifyLyricsBar.entitlements "$APP_DIR"
codesign --verify --strict "$APP_DIR"
printf '\nApp pronto: %s\n' "$APP_DIR"
