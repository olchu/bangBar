#!/usr/bin/env bash
set -euo pipefail

PROJECT="${PROJECT:-BangBar.xcodeproj}"
SCHEME="${SCHEME:-BangBar}"
CONFIGURATION="${CONFIGURATION:-Release}"
APP_NAME="${APP_NAME:-BangBar}"
SIGNING="${SIGNING:-automatic}"

BUILD_ROOT="${BUILD_ROOT:-build/dmg}"
DERIVED_DATA="$BUILD_ROOT/DerivedData"
STAGING_DIR="$BUILD_ROOT/staging"
DIST_DIR="${DIST_DIR:-dist}"

echo "==> Building $APP_NAME ($CONFIGURATION)"

xcodebuild_args=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA"
  build
)

case "$SIGNING" in
  automatic)
    xcodebuild_args+=(CODE_SIGN_STYLE=Automatic)
    ;;
  disabled)
    xcodebuild_args+=(CODE_SIGNING_ALLOWED=NO)
    ;;
  *)
    echo "Unknown SIGNING value: $SIGNING"
    echo "Use SIGNING=automatic or SIGNING=disabled."
    exit 2
    ;;
esac

xcodebuild "${xcodebuild_args[@]}"

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/$APP_NAME.app"

if [[ ! -d "$APP_PATH" ]]; then
  echo "Built app not found at: $APP_PATH"
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "dev")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist" 2>/dev/null || echo "0")"
VOLUME_NAME="$APP_NAME $VERSION"
DMG_NAME="$APP_NAME-$VERSION-$BUILD_NUMBER.dmg"
RW_DMG="$BUILD_ROOT/$APP_NAME-rw.dmg"
FINAL_DMG="$DIST_DIR/$DMG_NAME"

echo "==> Preparing DMG contents"
rm -rf "$STAGING_DIR"
mkdir -p "$STAGING_DIR" "$DIST_DIR"

ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$RW_DMG" "$FINAL_DMG"

echo "==> Creating writable image"
hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDRW \
  "$RW_DMG"

echo "==> Compressing image"
hdiutil convert "$RW_DMG" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -o "$FINAL_DMG"

rm -f "$RW_DMG"

echo "==> DMG ready: $FINAL_DMG"
