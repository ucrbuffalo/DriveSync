#!/bin/bash

set -euo pipefail

PROJECT_ROOT="/Users/Cameron.Phillips/Documents/DriveSync App/DriveSync"
INSTALLER_DIR="$PROJECT_ROOT/Installer"

echo "========================================"
echo "DriveSync Installer Build"
echo "========================================"
echo

# ------------------------------------------------------------
# Find the newest DriveSync Xcode archive
# ------------------------------------------------------------

ARCHIVE_PATH="$(
    find "$HOME/Library/Developer/Xcode/Archives" \
        -type d \
        -name "DriveSync*.xcarchive" \
        -print0 |
    xargs -0 stat -f '%m %N' |
    sort -rn |
    head -1 |
    cut -d' ' -f2-
)"

if [[ -z "$ARCHIVE_PATH" || ! -d "$ARCHIVE_PATH" ]]; then
    echo "ERROR: Could not find a DriveSync Xcode archive."
    exit 1
fi

echo "Archive:"
echo "  $ARCHIVE_PATH"
echo

# ------------------------------------------------------------
# Required archived products
# ------------------------------------------------------------

DRIVESYNC_APP="$ARCHIVE_PATH/Products/Applications/DriveSync.app"
UNINSTALLER_APP="$ARCHIVE_PATH/Products/Applications/DriveSync Uninstaller.app"
UNINSTALL_HELPER="$ARCHIVE_PATH/Products/usr/local/bin/DriveSync Uninstall Helper"

# ------------------------------------------------------------
# Required project resources
# ------------------------------------------------------------

HELPER_PLIST="$PROJECT_ROOT/DriveSync Uninstaller/com.drivesync.uninstall-helper.plist"

# ------------------------------------------------------------
# Validate everything before doing any packaging work
# ------------------------------------------------------------

check_exists() {
    local path="$1"
    local description="$2"

    if [[ ! -e "$path" ]]; then
        echo "ERROR: Missing $description:"
        echo "  $path"
        exit 1
    fi

    echo "✓ $description"
}

echo "Checking required inputs..."
echo

check_exists "$DRIVESYNC_APP" "DriveSync.app"
check_exists "$UNINSTALLER_APP" "DriveSync Uninstaller.app"
check_exists "$UNINSTALL_HELPER" "DriveSync Uninstall Helper"
check_exists "$HELPER_PLIST" "Uninstall Helper LaunchDaemon plist"

echo
echo "All required inputs found."
echo

# ------------------------------------------------------------
# Assemble package payload
# ------------------------------------------------------------

PAYLOAD_ROOT="$INSTALLER_DIR/build/payload"

echo "Preparing package payload..."

rm -rf "$PAYLOAD_ROOT"

mkdir -p \
    "$PAYLOAD_ROOT/Applications/DriveSync" \
    "$PAYLOAD_ROOT/Library/PrivilegedHelperTools" \
    "$PAYLOAD_ROOT/Library/LaunchDaemons"

ditto "$DRIVESYNC_APP" \
    "$PAYLOAD_ROOT/Applications/DriveSync/DriveSync.app"

ditto "$UNINSTALLER_APP" \
    "$PAYLOAD_ROOT/Applications/DriveSync/DriveSync Uninstaller.app"

cp "$UNINSTALL_HELPER" \
    "$PAYLOAD_ROOT/Library/PrivilegedHelperTools/com.drivesync.uninstall-helper"

cp "$HELPER_PLIST" \
    "$PAYLOAD_ROOT/Library/LaunchDaemons/com.drivesync.uninstall-helper.plist"

chmod 755 \
    "$PAYLOAD_ROOT/Library/PrivilegedHelperTools/com.drivesync.uninstall-helper"

chmod 644 \
    "$PAYLOAD_ROOT/Library/LaunchDaemons/com.drivesync.uninstall-helper.plist"

# Remove stray AppleDouble files if any exist as real payload files.
find "$PAYLOAD_ROOT" -name '._*' -delete

echo
echo "========================================"
echo "Package payload assembled successfully."
echo "========================================"
echo
echo "Payload:"
find "$PAYLOAD_ROOT" -maxdepth 4 -print

# ------------------------------------------------------------
# Build component package
# ------------------------------------------------------------

PACKAGE_PATH="$INSTALLER_DIR/build/DriveSync.pkg"
COMPONENT_PLIST="$INSTALLER_DIR/build/DriveSync-components.plist"

echo
echo "Analyzing app bundle components..."

/usr/bin/pkgbuild --analyze \
    --root "$PAYLOAD_ROOT" \
    "$COMPONENT_PLIST"

# Keep both apps in /Applications/DriveSync rather than relocating
# them to a previously discovered installation location.
/usr/libexec/PlistBuddy -c "Set :0:BundleIsRelocatable false" "$COMPONENT_PLIST"
/usr/libexec/PlistBuddy -c "Set :1:BundleIsRelocatable false" "$COMPONENT_PLIST"

echo
echo "Building DriveSync package..."

rm -f "$PACKAGE_PATH"

/usr/bin/pkgbuild \
    --root "$PAYLOAD_ROOT" \
    --component-plist "$COMPONENT_PLIST" \
    --scripts "$INSTALLER_DIR/scripts" \
    --ownership recommended \
    --identifier "com.drivesync.app.pkg" \
    --version "1.0" \
    --install-location "/" \
    "$PACKAGE_PATH"

echo
echo "========================================"
echo "DriveSync package built successfully."
echo "========================================"
echo
echo "Package:"
echo "  $PACKAGE_PATH"