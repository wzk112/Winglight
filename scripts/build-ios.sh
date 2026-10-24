#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${IOS_BUILD_DIR:-$SOURCE_DIR/.build/ios-release}"
OUTPUT_DIR="${IOS_OUTPUT_DIR:-$SOURCE_DIR/dist/iOS}"
MODE="${1:-unsigned}"
python3 "$SOURCE_DIR/scripts/assets.py" verify
mkdir -p "$OUTPUT_DIR" "$BUILD_DIR"
PROJECT="$SOURCE_DIR/Apps/iOS/Winglight.xcodeproj"
if [ "$MODE" = "simulator" ]; then
    xcodebuild -project "$PROJECT" -scheme Winglight -configuration Release -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO build
    exit
fi
if [ "$MODE" = "signed" ]; then
    : "${DEVELOPMENT_TEAM:?Set DEVELOPMENT_TEAM to your own Apple development team ID}"
    xcodebuild -project "$PROJECT" -scheme Winglight -configuration Release -destination 'generic/platform=iOS' -archivePath "$BUILD_DIR/Winglight.xcarchive" -derivedDataPath "$BUILD_DIR" -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" archive
    APP_PATH="$BUILD_DIR/Winglight.xcarchive/Products/Applications/Winglight.app"
    IPA_NAME=Winglight-1.6.0-iOS-development.ipa
else
    if [ "$MODE" != "unsigned" ]; then echo 'Usage: build-ios.sh unsigned|signed|simulator' >&2;exit 2;fi
    xcodebuild -project "$PROJECT" -scheme Winglight -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath "$BUILD_DIR" CODE_SIGNING_ALLOWED=NO build
    APP_PATH="$BUILD_DIR/Build/Products/Release-iphoneos/Winglight.app"
    IPA_NAME=Winglight-1.6.0-iOS-unsigned.ipa
fi
STAGE_DIR="$(mktemp -d "$OUTPUT_DIR/package.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
mkdir -p "$STAGE_DIR/Payload"
ditto "$APP_PATH" "$STAGE_DIR/Payload/Winglight.app"
if [ "$MODE" = "signed" ]; then codesign --verify --deep --strict "$STAGE_DIR/Payload/Winglight.app";fi
(cd "$STAGE_DIR" && /usr/bin/zip -qry "$STAGE_DIR/package.ipa" Payload)
mv "$STAGE_DIR/package.ipa" "$OUTPUT_DIR/$IPA_NAME"
(cd "$OUTPUT_DIR" && shasum -a 256 "$IPA_NAME" > "$IPA_NAME.sha256")
echo "$OUTPUT_DIR/$IPA_NAME"
