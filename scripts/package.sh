#!/bin/bash
# ============================================================
# JobBus — Package Script
# Creates a distributable .app bundle and .zip archive
#
# Version is read from the VERSION file at the project root.
# Build number is auto-generated from git (commit count + short hash).
#
# Usage:
#   ./scripts/package.sh           # Build with current VERSION
#   ./scripts/package.sh --bump    # Bump patch version, then build
# ============================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

APP_NAME="JobBus"
BUNDLE_ID="com.jobbus.app"
BUILD_DIR=".build/release"
OUTPUT_DIR="dist"
VERSION_FILE="VERSION"

# ── Version Management ─────────────────────────────────────

# Read version from VERSION file
if [ ! -f "$VERSION_FILE" ]; then
    echo "❌ VERSION file not found. Creating with 1.0.0"
    echo "1.0.0" > "$VERSION_FILE"
fi
VERSION=$(cat "$VERSION_FILE" | tr -d '[:space:]')

# Handle --bump flag: increment patch version
if [ "$1" = "--bump" ]; then
    IFS='.' read -r MAJOR MINOR PATCH <<< "$VERSION"
    PATCH=$((PATCH + 1))
    VERSION="$MAJOR.$MINOR.$PATCH"
    echo "$VERSION" > "$VERSION_FILE"
    echo "📝 Version bumped to $VERSION"
fi

# Generate build number from git (commit count + short hash)
if command -v git &> /dev/null && git rev-parse --git-dir > /dev/null 2>&1; then
    COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo "0")
    COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
    BUILD_NUMBER="${COMMIT_COUNT}.${COMMIT_HASH}"
    BUILD_DIRTY=""
    if ! git diff --quiet HEAD 2>/dev/null; then
        BUILD_DIRTY=" (dirty)"
    fi
else
    BUILD_NUMBER="0.local"
    BUILD_DIRTY=""
fi

FULL_VERSION="v${VERSION} (build ${BUILD_NUMBER}${BUILD_DIRTY})"

echo "📦 Packaging $APP_NAME $FULL_VERSION"
echo "══════════════════════════════════════"

# ── Step 1: Build ──────────────────────────────────────────

echo "🔨 Building release binary..."
swift build -c release
echo "   ✅ Build complete"

# ── Step 2: Create .app bundle ─────────────────────────────

echo "📁 Creating .app bundle..."
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources"

# Step 3: Copy binary
cp "$BUILD_DIR/$APP_NAME" "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/"
echo "   ✅ Binary copied"

# Step 4: Copy SPM resource bundle (CRITICAL — without this, Bundle.module crashes on other Macs)
# SPM generates a JobBus_JobBus.bundle containing processed resources (icons, etc.)
# Bundle.module looks for it at Bundle.main.bundleURL (= the .app root), but codesign
# requires all content inside Contents/. Solution: put it in Contents/Resources/ and
# symlink from the root so both codesign and Bundle.module are happy.
RESOURCE_BUNDLE=""
for candidate in \
    "$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle" \
    ".build/arm64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle" \
    ".build/x86_64-apple-macosx/release/${APP_NAME}_${APP_NAME}.bundle"; do
    if [ -d "$candidate" ]; then
        RESOURCE_BUNDLE="$candidate"
        break
    fi
done

BUNDLE_BASENAME="${APP_NAME}_${APP_NAME}.bundle"
if [ -n "$RESOURCE_BUNDLE" ]; then
    # Place bundle inside Contents/Resources/ (codesign-safe location)
    cp -R "$RESOURCE_BUNDLE" "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/$BUNDLE_BASENAME"
    echo "   ✅ SPM resource bundle copied to Contents/Resources/"
else
    echo "   ⚠️  WARNING: SPM resource bundle not found — app may crash on launch!"
    echo "      Searched for: $BUNDLE_BASENAME"
fi

# Step 5: Copy resources
if [ -f "Sources/Resources/AppIcon.png" ]; then
    cp "Sources/Resources/AppIcon.png" "$OUTPUT_DIR/$APP_NAME.app/Contents/Resources/"
    echo "   ✅ App icon copied"
fi

# ── Step 6: Create Info.plist ──────────────────────────────

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
    <string>$BUILD_NUMBER</string>
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
echo "   ✅ Info.plist created (v$VERSION, build $BUILD_NUMBER)"

# ── Step 7: Generate .icns ─────────────────────────────────

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

# ── Step 8: Ad-hoc code sign ───────────────────────────────
# Without ANY signature, macOS shows "damaged and can't be opened" (dead end).
# Ad-hoc signing changes this to "unidentified developer", which allows
# right-click → Open. This is FREE and doesn't need an Apple Developer cert.

echo "🔏 Ad-hoc code signing..."
codesign --force --deep --sign - "$OUTPUT_DIR/$APP_NAME.app" 2>/dev/null
if [ $? -eq 0 ]; then
    echo "   ✅ Ad-hoc signed (enables right-click → Open on other Macs)"
else
    echo "   ⚠️  Code signing failed — app may show 'damaged' on other Macs"
fi

# ── Step 9: Strip quarantine ───────────────────────────────

echo "🔓 Stripping quarantine attributes..."
xattr -cr "$OUTPUT_DIR/$APP_NAME.app" 2>/dev/null || true
echo "   ✅ Quarantine stripped"

# ── Step 9: Create .zip with installer ─────────────────────

ZIP_NAME="${APP_NAME}-v${VERSION}-macOS.zip"
echo "📦 Creating distributable archive..."

# Copy the double-click installer alongside the app
INSTALLER_SRC="$PROJECT_ROOT/scripts/Install JobBus.command"
if [ -f "$INSTALLER_SRC" ]; then
    cp "$INSTALLER_SRC" "$OUTPUT_DIR/"
    chmod +x "$OUTPUT_DIR/Install JobBus.command"
    xattr -cr "$OUTPUT_DIR/Install JobBus.command" 2>/dev/null || true
fi

cd "$OUTPUT_DIR"
zip -r -q "$ZIP_NAME" "$APP_NAME.app" "Install JobBus.command" 2>/dev/null || \
zip -r -q "$ZIP_NAME" "$APP_NAME.app"
cd "$PROJECT_ROOT"
echo "   ✅ Zip created (with installer)"

# ── Step 10: Create DMG ───────────────────────────────────

DMG_NAME="${APP_NAME}-v${VERSION}-macOS.dmg"
echo "💿 Creating DMG installer..."

# Create a temporary folder for DMG contents
DMG_STAGING="$OUTPUT_DIR/dmg_staging"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"

# Copy app and installer
cp -R "$OUTPUT_DIR/$APP_NAME.app" "$DMG_STAGING/"
if [ -f "$OUTPUT_DIR/Install JobBus.command" ]; then
    cp "$OUTPUT_DIR/Install JobBus.command" "$DMG_STAGING/"
fi

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_STAGING/Applications"

# Create a README for the DMG
cat > "$DMG_STAGING/How to Install.txt" << 'INSTALL_README'

   🚌  JobBus — Installation Guide


   STEP 1:  Install the App
   ─────────────────────────────────────
   Drag "JobBus" into the "Applications" folder
   in this window.


   STEP 2:  First Launch (IMPORTANT!)
   ─────────────────────────────────────
   Since this app isn't from the App Store,
   macOS blocks it by default. To open it:

   1. Open your Applications folder
   2. Find "JobBus"
   3. RIGHT-CLICK (or Control+click) on it
   4. Click "Open" from the menu
   5. Click "Open" again in the popup

   ✅ You only need to do this ONCE.
      After that, JobBus opens normally.


   ALTERNATIVE: Use the Installer Script
   ─────────────────────────────────────
   If the above doesn't work:
   1. RIGHT-CLICK "Install JobBus.command"
   2. Click "Open" → then "Open" again
   3. It will install everything automatically


   STILL STUCK? ("damaged" error)
   ─────────────────────────────────────
   1. Open Spotlight (Cmd + Space)
   2. Type "Terminal" and press Enter
   3. Paste this and press Enter:

      xattr -cr /Applications/JobBus.app

   4. Now open JobBus normally

INSTALL_README

# Build DMG
hdiutil create -volname "JobBus v${VERSION}" \
    -srcfolder "$DMG_STAGING" \
    -ov -format UDZO \
    "$OUTPUT_DIR/$DMG_NAME" > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo "   ✅ DMG created"
else
    echo "   ⚠️  DMG creation failed (zip is still available)"
fi

# Cleanup
rm -rf "$DMG_STAGING"
rm -f "$OUTPUT_DIR/Install JobBus.command"  # Already in zip/dmg

# ── Step 11: Write build manifest ──────────────────────────

cat > "$OUTPUT_DIR/BUILD_INFO.txt" << EOF
JobBus Build Manifest
═════════════════════
Version:      $VERSION
Build:        $BUILD_NUMBER${BUILD_DIRTY}
Date:         $(date '+%Y-%m-%d %H:%M:%S %z')
Machine:      $(hostname)
Swift:        $(swift --version 2>&1 | head -1)
macOS:        $(sw_vers -productVersion)
Arch:         $(uname -m)
EOF
echo "   ✅ Build manifest written"

# ── Summary ────────────────────────────────────────────────

BINARY_SIZE=$(du -sh "$OUTPUT_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME" | cut -f1)
ZIP_SIZE=$(du -sh "$OUTPUT_DIR/$ZIP_NAME" | cut -f1)
DMG_SIZE=""
if [ -f "$OUTPUT_DIR/$DMG_NAME" ]; then
    DMG_SIZE=$(du -sh "$OUTPUT_DIR/$DMG_NAME" | cut -f1)
fi

echo ""
echo "══════════════════════════════════════"
echo "✅ Package complete!"
echo ""
echo "  Version:    $FULL_VERSION"
echo "  App Bundle: $OUTPUT_DIR/$APP_NAME.app"
echo "  Archive:    $OUTPUT_DIR/$ZIP_NAME ($ZIP_SIZE)"
if [ -n "$DMG_SIZE" ]; then
echo "  DMG:        $OUTPUT_DIR/$DMG_NAME ($DMG_SIZE)"
fi
echo "  Binary:     $BINARY_SIZE"
echo ""
echo "📤 Share with users:"
echo "  • For techies:     $ZIP_NAME"
echo "  • For everyone:    $DMG_NAME (drag to Applications)"
echo "  • Both include 'Install JobBus.command' (double-click installer)"
echo ""
echo "To tag this release:"
echo "  git tag v$VERSION && git push origin v$VERSION"
echo "══════════════════════════════════════"

