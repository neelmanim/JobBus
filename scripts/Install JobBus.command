#!/bin/bash
# ═══════════════════════════════════════════════════════
#  JobBus Installer — Double-click to install!
# ═══════════════════════════════════════════════════════
#
# This script:
#   1. Removes macOS quarantine (fixes "damaged" error)
#   2. Copies JobBus.app to /Applications
#   3. Launches the app
#

clear
echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║        🚌  JobBus Installer  🚌          ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""

# Find the .app bundle next to this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$SCRIPT_DIR/JobBus.app"

if [ ! -d "$APP_PATH" ]; then
    echo "  ❌ Error: JobBus.app not found!"
    echo ""
    echo "  Make sure this installer is in the same"
    echo "  folder as JobBus.app"
    echo ""
    echo "  Press Enter to close..."
    read
    exit 1
fi

echo "  📍 Found: $APP_PATH"
echo ""

# Step 1: Remove quarantine
echo "  🔓 Step 1/3: Removing macOS security block..."
xattr -cr "$APP_PATH" 2>/dev/null
echo "     ✅ Done"

# Step 2: Copy to Applications
echo "  📁 Step 2/3: Installing to /Applications..."

if [ -d "/Applications/JobBus.app" ]; then
    echo ""
    echo "  ⚠️  JobBus is already installed."
    echo -n "  Replace with this version? (y/n): "
    read -r REPLY
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo ""
        echo "  Installation cancelled."
        echo "  Press Enter to close..."
        read
        exit 0
    fi
    rm -rf "/Applications/JobBus.app"
fi

cp -R "$APP_PATH" /Applications/
if [ $? -eq 0 ]; then
    echo "     ✅ Installed to /Applications/JobBus.app"
else
    echo ""
    echo "  ❌ Could not copy to /Applications."
    echo "  Try dragging JobBus.app to Applications manually,"
    echo "  then right-click → Open."
    echo ""
    echo "  Press Enter to close..."
    read
    exit 1
fi

# Step 3: Launch
echo "  🚀 Step 3/3: Launching JobBus..."
open /Applications/JobBus.app

echo ""
echo "  ╔══════════════════════════════════════════╗"
echo "  ║     ✅  Installation Complete!            ║"
echo "  ║                                          ║"
echo "  ║  JobBus is now in your Applications.     ║"
echo "  ║  You can delete this installer folder.   ║"
echo "  ╚══════════════════════════════════════════╝"
echo ""
echo "  Press Enter to close this window..."
read
