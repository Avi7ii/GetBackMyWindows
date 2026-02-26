#!/bin/bash
set -euo pipefail

APP_NAME="GetBackMyWindows"
BUILD_DIR="./Build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CERT_NAME="GetBackMyWindowsCert"
DEPLOY_TARGET="15.0"

echo "🚧 Building $APP_NAME (macOS $DEPLOY_TARGET+, universal: arm64+x86_64)..."

if ! security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "❌ ERROR: Code Signing Certificate '$CERT_NAME' not found!"
    echo "   Please create a self-signed code signing certificate named '$CERT_NAME' in Keychain Access."
    exit 1
fi

SRC_DIR="$(pwd)"
TEMP_BUILD_DIR=$(mktemp -d /tmp/GBMW_Build_XXXX)
echo "🏗️  Building in temporary directory: $TEMP_BUILD_DIR"

TEMP_APP_BUNDLE="$TEMP_BUILD_DIR/$APP_NAME.app"
TEMP_CONTENTS_DIR="$TEMP_APP_BUNDLE/Contents"
TEMP_MACOS_DIR="$TEMP_CONTENTS_DIR/MacOS"
TEMP_RESOURCES_DIR="$TEMP_CONTENTS_DIR/Resources"
TEMP_BIN_ARM64="$TEMP_BUILD_DIR/$APP_NAME.arm64"
TEMP_BIN_X64="$TEMP_BUILD_DIR/$APP_NAME.x86_64"

mkdir -p "$TEMP_MACOS_DIR" "$TEMP_RESOURCES_DIR"

echo "🧱 Compiling arm64 target..."
swiftc "$SRC_DIR/main.swift" "$SRC_DIR/SettingsUI.swift" \
       -target "arm64-apple-macos$DEPLOY_TARGET" \
       -o "$TEMP_BIN_ARM64" \
       -framework Cocoa -framework Carbon

echo "🧱 Compiling x86_64 target..."
swiftc "$SRC_DIR/main.swift" "$SRC_DIR/SettingsUI.swift" \
       -target "x86_64-apple-macos$DEPLOY_TARGET" \
       -o "$TEMP_BIN_X64" \
       -framework Cocoa -framework Carbon

echo "🧩 Creating universal binary..."
lipo -create "$TEMP_BIN_ARM64" "$TEMP_BIN_X64" -output "$TEMP_MACOS_DIR/$APP_NAME"

if [ -f "$SRC_DIR/Info.plist" ]; then
    cp -X "$SRC_DIR/Info.plist" "$TEMP_CONTENTS_DIR/Info.plist"
else
    echo "❌ Info.plist not found!"
    rm -rf "$TEMP_BUILD_DIR"
    exit 1
fi

if [ -f "$SRC_DIR/GetBackMyWindows.icns" ]; then
    cp -X "$SRC_DIR/GetBackMyWindows.icns" "$TEMP_RESOURCES_DIR/"
else
    echo "❌ Icon file GetBackMyWindows.icns not found!"
    rm -rf "$TEMP_BUILD_DIR"
    exit 1
fi

echo "🧹 Ensuring clean attributes..."
xattr -rc "$TEMP_APP_BUNDLE"

echo "🔏 Signing with identity: $CERT_NAME"
codesign --sign "$CERT_NAME" \
         --entitlements "$SRC_DIR/GetBackMyWindows.entitlements" \
         --identifier "com.user.GetBackMyWindows" \
         --verbose \
         --force \
         "$TEMP_APP_BUNDLE"

echo "🔍 Verifying Signature..."
codesign -v --strict --deep --verbose=2 "$TEMP_APP_BUNDLE"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mv "$TEMP_APP_BUNDLE" "$BUILD_DIR/"
rm -rf "$TEMP_BUILD_DIR"

echo "✅ Build Successful!"
echo "📂 App located at: $APP_BUNDLE"

ZIP_PATH="$BUILD_DIR/$APP_NAME.app.zip"
echo "📦 Zipping for Release..."
ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "✅ Build & Package Successful!"
echo "👉 Release File: $ZIP_PATH (Upload this to GitHub)"
