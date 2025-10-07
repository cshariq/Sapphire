#
//  install.sh
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-13.
//


#!/bin/bash

# The bundle identifier of your main application.
APP_BUNDLE_IDENTIFIER="com.shariq.sapphire"

# The name of your helper executable.
HELPER_EXECUTABLE_NAME="SapphireAudioHelper"

# The label of your launchd service.
LAUNCHD_PLIST_LABEL="com.shariq.sapphire.SapphireAudioHelper"

# --- Paths ---

# The path to the helper executable inside your app bundle's Resources folder.
# The '$1' is the path to the app bundle, which we'll pass from AppleScript.
APP_BUNDLE_PATH="$1"
HELPER_EXECUTABLE_PATH="$APP_BUNDLE_PATH/Contents/Resources/$HELPER_EXECUTABLE_NAME"
LAUNCHD_PLIST_PATH="$APP_BUNDLE_PATH/Contents/Resources/$LAUNCHD_PLIST_LABEL.plist"

# The destination paths for the helper and its launchd.plist.
PRIVILEGED_HELPER_DIR="/Library/PrivilegedHelperTools"
LAUNCHDAEMONS_DIR="/Library/LaunchDaemons"

INSTALLED_HELPER_PATH="$PRIVILEGED_HELPER_DIR/$(basename "$HELPER_EXECUTABLE_PATH")"
INSTALLED_LAUNCHD_PLIST_PATH="$LAUNCHDAEMONS_DIR/$LAUNCHD_PLIST_LABEL.plist"


# --- Installation Logic ---

echo "Starting installation..."

# Unload the service if it's already running.
if [ -f "$INSTALLED_LAUNCHD_PLIST_PATH" ]; then
    echo "Service already installed. Unloading existing service..."
    launchctl unload "$INSTALLED_LAUNCHD_PLIST_PATH"
fi

# Copy the helper executable to /Library/PrivilegedHelperTools/
echo "Copying helper executable to $INSTALLED_HELPER_PATH"
cp "$HELPER_EXECUTABLE_PATH" "$INSTALLED_HELPER_PATH"
chown root:wheel "$INSTALLED_HELPER_PATH"
chmod 755 "$INSTALLED_HELPER_PATH"

# Copy the launchd.plist to /Library/LaunchDaemons/
echo "Copying launchd.plist to $INSTALLED_LAUNCHD_PLIST_PATH"
cp "$LAUNCHD_PLIST_PATH" "$INSTALLED_LAUNCHD_PLIST_PATH"
chown root:wheel "$INSTALLED_LAUNCHD_PLIST_PATH"
chmod 644 "$INSTALLED_LAUNCHD_PLIST_PATH"

# Load the new service into launchd.
echo "Loading new service with launchctl..."
launchctl load "$INSTALLED_LAUNCHD_PLIST_PATH"

echo "Installation complete."

exit 0