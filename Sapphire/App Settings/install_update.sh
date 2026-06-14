#!/bin/bash

# This script is responsible for replacing the old application bundle with the new one.
# It is launched via AppleScript with administrator privileges.

# Arguments passed from the Swift app:
# $1: The Process ID (PID) of the running application to wait for.
# $2: The path to the new, unzipped .app bundle (e.g., in /tmp/).
# $3: The path to the old, currently running .app bundle that needs to be replaced.

PID=$1
NEW_APP_PATH=$2
OLD_APP_PATH=$3

# Log file for debugging (use $HOME of the console user, not root)
CONSOLE_USER=$(stat -f "%Su" /dev/console)
LOG_FILE=$(eval echo "~$CONSOLE_USER/Library/Logs/SapphireUpdate.log")
echo "---------------------------------" >> "$LOG_FILE"
echo "Update script started as root at $(date)" >> "$LOG_FILE"
echo "PID to wait for: $PID" >> "$LOG_FILE"
echo "New app path: $NEW_APP_PATH" >> "$LOG_FILE"
echo "Old app path: $OLD_APP_PATH" >> "$LOG_FILE"

# --- SAFETY CHECK ---
# Ensure the old app path is a valid, non-empty path and not the root directory.
if [ -z "$OLD_APP_PATH" ] || [ "$OLD_APP_PATH" == "/" ] || [ ! -d "$OLD_APP_PATH" ]; then
    echo "ERROR: Invalid old application path provided. Aborting update." >> "$LOG_FILE"
    exit 1
fi

# 1. Wait for the main application to completely terminate.
echo "Waiting for application (PID: $PID) to quit..." >> "$LOG_FILE"
while ps -p $PID > /dev/null; do
    sleep 1
done
echo "Application has quit." >> "$LOG_FILE"

# 2. Remove the old application bundle contents, preserving the .app wrapper.
#    Using ditto to overlay instead of rm+mv preserves the wrapper's inode,
#    creation date, and extended attributes — preventing macOS from treating
#    the update as a brand-new app that needs all permissions re-granted.
echo "Removing old Contents at $OLD_APP_PATH/Contents..." >> "$LOG_FILE"
rm -rf "$OLD_APP_PATH/Contents"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to remove old application Contents." >> "$LOG_FILE"
    exit 1
fi
echo "Old Contents removed." >> "$LOG_FILE"

# 3. Overlay the new application into the preserved wrapper.
echo "Overlaying new application into existing wrapper..." >> "$LOG_FILE"
/usr/bin/ditto "$NEW_APP_PATH" "$OLD_APP_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to overlay new application." >> "$LOG_FILE"
    exit 1
fi
echo "New application overlaid." >> "$LOG_FILE"

# Clean up the temporary new app bundle.
rm -rf "$NEW_APP_PATH"

# 4. Relaunch the new, updated application.
# 'open' command should be run as the logged-in user, not as root.
CURRENT_USER=$(stat -f "%Su" /dev/console)
su - "$CURRENT_USER" -c "open \"$OLD_APP_PATH\""

echo "Update script finished." >> "$LOG_FILE"
echo "---------------------------------" >> "$LOG_FILE"

exit 0
