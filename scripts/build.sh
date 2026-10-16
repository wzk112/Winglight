#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$SOURCE_DIR/.build}"
APP_PATH="${APP_PATH:-$SOURCE_DIR/dist/Winglight.app}"
python3 "$SOURCE_DIR/scripts/assets.py" verify
mkdir -p "$BUILD_DIR"
xcrun -sdk macosx metal -std=metal3.1 -mmacosx-version-min=15.0 -c "$SOURCE_DIR/Sources/Winglight/Resources/Lights.metal" -o "$BUILD_DIR/Lights.air"
xcrun -sdk macosx metallib "$BUILD_DIR/Lights.air" -o "$SOURCE_DIR/Sources/Winglight/Resources/Lights.metallib"
swift build --package-path "$SOURCE_DIR" --scratch-path "$BUILD_DIR" -c release
BIN_DIR="$(swift build --package-path "$SOURCE_DIR" --scratch-path "$BUILD_DIR" -c release --show-bin-path)"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_DIR/Winglight" "$APP_PATH/Contents/MacOS/Winglight"
ditto "$BIN_DIR/Winglight_Winglight.bundle" "$APP_PATH/Contents/Resources/Winglight_Winglight.bundle"
ditto "$BIN_DIR/Winglight_WinglightCore.bundle" "$APP_PATH/Contents/Resources/Winglight_WinglightCore.bundle"
mkdir -p "$APP_PATH/Contents/Resources/Legal"
cp "$SOURCE_DIR/LICENSE" "$SOURCE_DIR/NOTICE" "$SOURCE_DIR/THIRD_PARTY.md" "$SOURCE_DIR/ThirdParty/NOTICE.txt" "$APP_PATH/Contents/Resources/Legal/"
ditto "$SOURCE_DIR/ThirdParty/Licenses" "$APP_PATH/Contents/Resources/Legal/Upstream"
cat > "$APP_PATH/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Winglight</string>
<key>CFBundleDisplayName</key><string>Winglight</string>
<key>CFBundleIdentifier</key><string>local.winglight.simulator</string>
<key>CFBundleExecutable</key><string>Winglight</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.5.0</string>
<key>CFBundleVersion</key><string>9</string>
<key>NSLocationUsageDescription</key><string>根据所在位置计算日出、日落和太阳方向，使场景日照跟随当前时间。位置仅在本机用于计算。</string>
<key>NSLocationWhenInUseUsageDescription</key><string>根据所在位置计算日出、日落和太阳方向，使场景日照跟随当前时间。位置仅在本机用于计算。</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>CFBundleIconFile</key><string>Winglight</string>
<key>LSApplicationCategoryType</key><string>public.app-category.entertainment</string>
</dict></plist>
PLIST
if [ -f "$SOURCE_DIR/Resources/Winglight.icns" ]; then cp "$SOURCE_DIR/Resources/Winglight.icns" "$APP_PATH/Contents/Resources/"; fi
codesign --force --deep --sign "${SIGNING_IDENTITY:--}" --timestamp=none --options runtime --entitlements "$SOURCE_DIR/Resources/Winglight.entitlements" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
echo "$APP_PATH"
