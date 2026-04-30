#!/bin/bash
# ============================================================
# JobBus — App Store Build & Upload Script
# Builds, signs, packages, and uploads to App Store Connect
# ============================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="JobBus"
BUNDLE_ID="com.neelmani.jobbus"
VERSION=$(cat VERSION | tr -d '[:space:]')
BUILD_DIR=".build/release"
OUTPUT_DIR="dist/appstore"
SIGNING_IDENTITY="3rd Party Mac Developer Application: Viren Baid (TS6UH83Q2Q)"
INSTALLER_IDENTITY="3rd Party Mac Developer Installer: Viren Baid (TS6UH83Q2Q)"
TEAM_ID="TS6UH83Q2Q"
PROFILE_UUID="f7261a53-0614-4106-93d9-a5c5c05dfdb8"
ENTITLEMENTS="$PROJECT_ROOT/Sources/Resources/AppStore.entitlements"

# Build number from git
COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "1")

echo "📦 Building $APP_NAME v$VERSION for App Store"
echo "══════════════════════════════════════"

# ── Step 1: Create App Store entitlements (sandbox required) ──
cat > "$ENTITLEMENTS" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
    <key>com.apple.security.files.user-selected.read-write</key>
    <true/>
</dict>
</plist>
PLIST
echo "   ✅ App Store entitlements created"

# ── Step 2: Build release binary ──
echo "🔨 Building release binary..."
swift build -c release
echo "   ✅ Build complete"

# ── Step 3: Create .app bundle ──
echo "📁 Creating .app bundle..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources"

# Copy binary
cp "$BUILD_DIR/$APP_NAME" "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/"

# Copy SPM resource bundle
BUNDLE_BASENAME="${APP_NAME}_${APP_NAME}.bundle"
for candidate in \
    "$BUILD_DIR/$BUNDLE_BASENAME" \
    ".build/arm64-apple-macosx/release/$BUNDLE_BASENAME" \
    ".build/x86_64-apple-macosx/release/$BUNDLE_BASENAME"; do
    if [ -d "$candidate" ]; then
        cp -R "$candidate" "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/$BUNDLE_BASENAME"
        break
    fi
done

# Copy icon
if [ -f "Sources/Resources/AppIcon.png" ]; then
    cp "Sources/Resources/AppIcon.png" "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/"
fi

# ── Step 4: Create Info.plist ──
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
    <string>$COMMIT_COUNT</string>
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
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.productivity</string>
    <key>NSHumanReadableCopyright</key>
    <string>© 2026 Neelmani. All rights reserved.</string>
</dict>
</plist>
PLIST

# ── Step 5: Generate .icns ──
if [ -f "Sources/Resources/AppIcon.png" ]; then
    echo "🎨 Generating icon..."
    ICONSET_DIR="$OUTPUT_DIR/AppIcon.iconset"
    mkdir -p "$ICONSET_DIR"
    ICON_PNG="$OUTPUT_DIR/icon_tmp.png"
    sips -s format png "Sources/Resources/AppIcon.png" --out "$ICON_PNG" > /dev/null 2>&1
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
    iconutil -c icns "$ICONSET_DIR" -o "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
    rm -rf "$ICONSET_DIR" "$ICON_PNG"
    echo "   ✅ Icon generated"
fi

# ── Step 6: PkgInfo ──
echo -n "APPL????" > "$OUTPUT_DIR/$APP_NAME.app/Contents/PkgInfo"

# ── Step 7: Embed provisioning profile ──
cp ~/Library/MobileDevice/Provisioning\ Profiles/${PROFILE_UUID}.provisionprofile \
   "$OUTPUT_DIR/$APP_NAME.app/Contents/embedded.provisionprofile"
echo "   ✅ Provisioning profile embedded"

# ── Step 8: Code sign for App Store ──
echo "🔏 Code signing for App Store..."

# Sign the app (--deep handles nested bundles)
codesign --force --deep --options runtime \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$ENTITLEMENTS" \
    --timestamp \
    "$OUTPUT_DIR/$APP_NAME.app"

# Verify
codesign --verify --verbose=2 "$OUTPUT_DIR/$APP_NAME.app" 2>&1
echo "   ✅ Code signed for App Store"

# ── Step 9: Create .pkg for App Store ──
echo "📦 Creating installer package..."
PKG_NAME="${APP_NAME}-v${VERSION}-AppStore.pkg"

productbuild --component "$OUTPUT_DIR/$APP_NAME.app" /Applications \
    --sign "$INSTALLER_IDENTITY" \
    "$OUTPUT_DIR/$PKG_NAME"

echo "   ✅ .pkg created"

# ── Step 10: Upload to App Store Connect ──
echo "📤 Uploading to App Store Connect..."
xcrun altool --upload-app \
    --type macos \
    --file "$OUTPUT_DIR/$PKG_NAME" \
    --apiKey "" \
    --apiIssuer "" 2>/dev/null || \
xcrun altool --upload-app \
    --type macos \
    --file "$OUTPUT_DIR/$PKG_NAME" \
    --username "virenbaid.developer@gmail.com" \
    --password "gbiv-rukz-sswl-ivdh" \
    --team-id "$TEAM_ID"

echo ""
echo "══════════════════════════════════════"
echo "✅ Uploaded to App Store Connect!"
echo "  Go to appstoreconnect.apple.com to submit for review."
echo "══════════════════════════════════════"
