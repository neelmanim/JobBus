#!/bin/bash
# ============================================================
# JobBus — Package Script
# Creates a distributable .app bundle and .zip archive
# Usage: ./scripts/package.sh
# ============================================================

set -e

APP_NAME="JobBus"
VERSION="1.0.0"
BUNDLE_ID="com.jobbus.app"
BUILD_DIR=".build/release"
OUTPUT_DIR="dist"

echo "📦 Packaging $APP_NAME v$VERSION"
echo "══════════════════════════════════════"

# Step 1: Build release binary
echo "🔨 Building release binary..."
swift build -c release
echo "   ✅ Build complete"

# Step 2: Create .app bundle structure
echo "📁 Creating .app bundle..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources"

# Step 3: Copy binary
cp "$BUILD_DIR/$APP_NAME" "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/"
echo "   ✅ Binary copied"

# Step 4: Copy resources
if [ -f "Sources/Resources/AppIcon.png" ]; then
    cp "Sources/Resources/AppIcon.png" "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/"
    echo "   ✅ App icon copied"
fi

# Step 5: Create Info.plist
cat > "$OUTPUT_DIR/$APP_NAME.app/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>Job Bus</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST
echo "   ✅ Info.plist created"

# Step 6: Create .icns from PNG (if iconutil is available)
if command -v iconutil &> /dev/null && [ -f "Sources/Resources/AppIcon.png" ]; then
    echo "🎨 Generating .icns icon set..."
    ICONSET_DIR="$OUTPUT_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    
    sips -z 16 16     "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_16x16.png"      > /dev/null 2>&1
    sips -z 32 32     "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_16x16@2x.png"   > /dev/null 2>&1
    sips -z 32 32     "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_32x32.png"      > /dev/null 2>&1
    sips -z 64 64     "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_32x32@2x.png"   > /dev/null 2>&1
    sips -z 128 128   "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_128x128.png"    > /dev/null 2>&1
    sips -z 256 256   "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
    sips -z 256 256   "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_256x256.png"    > /dev/null 2>&1
    sips -z 512 512   "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
    sips -z 512 512   "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_512x512.png"    > /dev/null 2>&1
    sips -z 1024 1024 "Sources/Resources/AppIcon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1
    
    iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR"
    echo "   ✅ .icns icon generated"
fi

# Step 7: Create distributable .zip
echo "📦 Creating distributable archive..."
cd "$OUTPUT_DIR"
zip -r -q "${APP_NAME}-v${VERSION}-macOS.zip" "$APP_NAME.app"
cd ..

# Step 8: Summary
BINARY_SIZE=$(du -sh "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" | cut -f1)
ZIP_SIZE=$(du -sh "$OUTPUT_DIR/${APP_NAME}-v${VERSION}-macOS.zip" | cut -f1)

echo ""
echo "══════════════════════════════════════"
echo "✅ Package complete!"
echo ""
echo "  App Bundle: $OUTPUT_DIR/$APP_NAME.app"
echo "  Archive:    $OUTPUT_DIR/${APP_NAME}-v${VERSION}-macOS.zip"
echo "  Binary:     $BINARY_SIZE"
echo "  Archive:    $ZIP_SIZE"
echo ""
echo "To install:"
echo "  cp -r $OUTPUT_DIR/$APP_NAME.app /Applications/"
echo ""
echo "To distribute:"
echo "  Share $OUTPUT_DIR/${APP_NAME}-v${VERSION}-macOS.zip"
echo "══════════════════════════════════════"
