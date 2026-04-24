#!/bin/bash
set -e

# ── Config ──
APP_NAME="Job Bus"
BUNDLE_ID="com.neelmani.jobbus"
VERSION="1.0.0"
PROJECT_DIR="/Users/neelmani-mishra/Documents/TryingSomethingInteresting/JobBus"
BUILD_DIR="$PROJECT_DIR/.build/release"
DIST_DIR="$PROJECT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
DMG_NAME="JobBus-v${VERSION}"
DMG_PATH="$DIST_DIR/$DMG_NAME.dmg"
ICON_SOURCE="$PROJECT_DIR/Sources/Resources/AppIcon.png"

echo "🔨 Building Job Bus.app bundle..."

# Clean dist
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# ── 1. Create .app bundle structure ──
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

# ── 2. Copy binary ──
cp "$BUILD_DIR/JobBus" "$APP_BUNDLE/Contents/MacOS/JobBus"

# ── 3. Copy resource bundle (ZIPFoundation + app resources) ──
if [ -d "$BUILD_DIR/JobBus_JobBus.bundle" ]; then
    cp -R "$BUILD_DIR/JobBus_JobBus.bundle" "$APP_BUNDLE/Contents/Resources/"
fi

# ── 4. Create Info.plist ──
cat > "$APP_BUNDLE/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>JobBus</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Neelmani. All rights reserved.</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <true/>
    </dict>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
PLIST

# ── 5. Create .icns from source image ──
echo "🎨 Generating app icon..."
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
mkdir -p "$ICONSET_DIR"

# Convert source to true PNG first (source is actually JPEG despite .png extension)
ICON_PNG="$DIST_DIR/AppIcon_converted.png"
sips -s format png "$ICON_SOURCE" --out "$ICON_PNG" > /dev/null 2>&1

# Generate all required icon sizes
sips -z 16 16     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16.png"      > /dev/null 2>&1
sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png"   > /dev/null 2>&1
sips -z 32 32     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32.png"      > /dev/null 2>&1
sips -z 64 64     "$ICON_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png"   > /dev/null 2>&1
sips -z 128 128   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128.png"    > /dev/null 2>&1
sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null 2>&1
sips -z 256 256   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256.png"    > /dev/null 2>&1
sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null 2>&1
sips -z 512 512   "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512.png"    > /dev/null 2>&1
sips -z 1024 1024 "$ICON_PNG" --out "$ICONSET_DIR/icon_512x512@2x.png" > /dev/null 2>&1

iconutil -c icns "$ICONSET_DIR" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET_DIR" "$ICON_PNG"

# ── 6. Create PkgInfo ──
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# ── 7. Create DMG ──
echo "📦 Creating DMG..."

DMG_TEMP="$DIST_DIR/dmg_staging"
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app to staging area
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH" > /dev/null 2>&1

# Clean up staging
rm -rf "$DMG_TEMP"

echo ""
echo "✅ Done!"
echo "   App:  $APP_BUNDLE"
echo "   DMG:  $DMG_PATH"
echo "   Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo ""
echo "📋 To install:"
echo "   1. Double-click $DMG_NAME.dmg"
echo "   2. Drag 'Job Bus' to Applications"
echo "   3. Right-click → Open (first launch, to bypass Gatekeeper)"
