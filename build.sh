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
swiftc main.swift -o "$MACOS_DIR/$APP_NAME" -framework Cocoa -framework Carbon

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

# 5. Ad-hoc Sign (Helps with permissions stability)
codesign --force --deep --sign - "$APP_BUNDLE"

echo "✅ Build Successful!"
echo "📂 App located at: $APP_BUNDLE"

# 6. Create Zip for Release (Preserves permissions)
ZIP_PATH="$BUILD_DIR/$APP_NAME.app.zip"
echo "📦 Zipping for Release..."
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "✅ Build & Package Successful!"
echo "👉 Release File: $ZIP_PATH (Upload this to GitHub)"
