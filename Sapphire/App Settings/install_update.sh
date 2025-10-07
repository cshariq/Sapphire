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

# Log file for debugging
LOG_FILE=~/Library/Logs/SapphireUpdate.log
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

# 2. Remove the old application bundle.
echo "Removing old application at $OLD_APP_PATH..." >> "$LOG_FILE"
rm -rf "$OLD_APP_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to remove old application." >> "$LOG_FILE"
    exit 1
fi
echo "Old application removed." >> "$LOG_FILE"

# 3. Move the new application from the temporary directory to the original location.
echo "Moving new application into place..." >> "$LOG_FILE"
mv "$NEW_APP_PATH" "$OLD_APP_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to move new application into place." >> "$LOG_FILE"
    exit 1
fi
echo "New application moved." >> "$LOG_FILE"

# 4. Relaunch the new, updated application.
# 'open' command should be run as the logged-in user, not as root.
CURRENT_USER=$(stat -f "%Su" /dev/console)
su - "$CURRENT_USER" -c "open \"$OLD_APP_PATH\""

echo "Update script finished." >> "$LOG_FILE"
echo "---------------------------------" >> "$LOG_FILE"

exit 0
