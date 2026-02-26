#!/bin/bash

APP_NAME="GetBackMyWindows"
BUILD_DIR="./Build"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "🚧 Building $APP_NAME..."

# 1. Clean and Create Directories
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# 2. Compile Swift source
# Note: We link Cocoa (AppKit) and Carbon (HotKeys)
swiftc main.swift SettingsUI.swift -o "$MACOS_DIR/$APP_NAME" -framework Cocoa -framework Carbon

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed."
    exit 1
fi

# 3. Copy Info.plist
if [ -f "Info.plist" ]; then
    cp Info.plist "$CONTENTS_DIR/Info.plist"
else
    echo "⚠️ Info.plist not found! App might not behave as LSUIElement."
fi

# 3.5 Copy Icon
if [ -f "GetBackMyWindows.icns" ]; then
    cp "GetBackMyWindows.icns" "$RESOURCES_DIR/"
else
    echo "⚠️ Icon file GetBackMyWindows.icns not found!"
fi

# 4. Remove Quarantine (Optional, for local development to avoid strict gatekeeper)
xattr -d com.apple.quarantine "$MACOS_DIR/$APP_NAME" 2>/dev/null

# 5. Codesign with Persistent Identity
# 优先使用固定的自签名证书 "GetBackMyWindowsCert"
# 如果没有找到，才回退到 Ad-hoc 签名（会导致每次更新都需要重置权限）

CERT_NAME="GetBackMyWindowsCert"

# Check if certificate exists
if ! security find-identity -v -p codesigning | grep -q "$CERT_NAME"; then
    echo "❌ ERROR: Code Signing Certificate '$CERT_NAME' not found!"
    echo "   Please create a self-signed code signing certificate named '$CERT_NAME' in Keychain Access."
    echo "   Without this persistent certificate, macOS will reset Accessibility permissions on every update."
    echo "   Build Aborted to prevent permission issues."
    exit 1
fi

# 1. Setup Build Environment (Isolate to /tmp to avoid Desktop xattrs)
TEMP_BUILD_DIR=$(mktemp -d /tmp/GBMW_Build_XXXX)
echo "🏗️  Building in temporary directory: $TEMP_BUILD_DIR"

# Define paths relative to temp dir
TEMP_APP_BUNDLE="$TEMP_BUILD_DIR/$APP_NAME.app"
TEMP_CONTENTS_DIR="$TEMP_APP_BUNDLE/Contents"
TEMP_MACOS_DIR="$TEMP_CONTENTS_DIR/MacOS"
TEMP_RESOURCES_DIR="$TEMP_CONTENTS_DIR/Resources"

mkdir -p "$TEMP_MACOS_DIR"
mkdir -p "$TEMP_RESOURCES_DIR"

# 2. Compile Swift source (Use absolute paths for source files)
SRC_DIR="$(pwd)"
swiftc "$SRC_DIR/main.swift" "$SRC_DIR/SettingsUI.swift" \
       -o "$TEMP_MACOS_DIR/$APP_NAME" \
       -framework Cocoa -framework Carbon

if [ $? -ne 0 ]; then
    echo "❌ Compilation failed."
    rm -rf "$TEMP_BUILD_DIR"
    exit 1
fi

# 3. Copy Resources
if [ -f "Info.plist" ]; then
    cp -X "Info.plist" "$TEMP_CONTENTS_DIR/Info.plist" # -X strips xattrs
else
    echo "⚠️ Info.plist not found!"
fi

if [ -f "GetBackMyWindows.icns" ]; then
    cp -X "GetBackMyWindows.icns" "$TEMP_RESOURCES_DIR/"
fi

# 4. Clean Attributes & Sign (In clean environment)
echo "🧹 Ensuring clean attributes..."
xattr -rc "$TEMP_APP_BUNDLE"

echo "🔏 Signing with identity: $CERT_NAME"
# Use explicit identifier to match Info.plist
codesign --sign "$CERT_NAME" \
         --entitlements "$SRC_DIR/GetBackMyWindows.entitlements" \
         --identifier "com.user.GetBackMyWindows" \
         --verbose \
         --force \
         "$TEMP_APP_BUNDLE"

if [ $? -ne 0 ]; then
    echo "❌ Signing Failed!"
    rm -rf "$TEMP_BUILD_DIR"
    exit 1
fi

# Verify Signature
echo "🔍 Verifying Signature..."
codesign -v --strict --deep --verbose=2 "$TEMP_APP_BUNDLE"

if [ $? -ne 0 ]; then
    echo "❌ Signature Verification Failed!"
    echo "   Check $TEMP_BUILD_DIR for details."
    exit 1
fi

# 5. Move Final Product to ./Build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
mv "$TEMP_APP_BUNDLE" "$BUILD_DIR/"

# Clean up temp
rm -rf "$TEMP_BUILD_DIR"

echo "✅ Build Successful!"
echo "📂 App located at: $APP_BUNDLE"

# 6. Create Zip for Release (Preserves permissions)
ZIP_PATH="$BUILD_DIR/$APP_NAME.app.zip"
echo "📦 Zipping for Release..."
ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "✅ Build & Package Successful!"
echo "👉 Release File: $ZIP_PATH (Upload this to GitHub)"
