#!/bin/bash

# Replaces the running Sapphire app bundle with a freshly downloaded one.
# Runs as the current user when the install location is writable (no password).
# Falls back to root only when launched with administrator privileges.

PID=$1
NEW_APP_PATH=$2
OLD_APP_PATH=$3

LOG_FILE="${HOME}/Library/Logs/SapphireUpdate.log"
if [ "$(id -u)" -eq 0 ]; then
    CONSOLE_USER=$(stat -f "%Su" /dev/console)
    LOG_FILE=$(eval echo "~$CONSOLE_USER/Library/Logs/SapphireUpdate.log")
fi

echo "---------------------------------" >> "$LOG_FILE"
echo "Update script started at $(date) (uid=$(id -u))" >> "$LOG_FILE"
echo "PID to wait for: $PID" >> "$LOG_FILE"
echo "New app path: $NEW_APP_PATH" >> "$LOG_FILE"
echo "Old app path: $OLD_APP_PATH" >> "$LOG_FILE"

if [ -z "$OLD_APP_PATH" ] || [ "$OLD_APP_PATH" == "/" ] || [ ! -d "$OLD_APP_PATH" ]; then
    echo "ERROR: Invalid old application path provided. Aborting update." >> "$LOG_FILE"
    exit 1
fi

echo "Waiting for application (PID: $PID) to quit..." >> "$LOG_FILE"
while ps -p "$PID" > /dev/null; do
    sleep 1
done
echo "Application has quit." >> "$LOG_FILE"

echo "Removing old application at $OLD_APP_PATH..." >> "$LOG_FILE"
rm -rf "$OLD_APP_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to remove old application." >> "$LOG_FILE"
    exit 1
fi
echo "Old application removed." >> "$LOG_FILE"

echo "Moving new application into place..." >> "$LOG_FILE"
mv "$NEW_APP_PATH" "$OLD_APP_PATH"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to move new application into place." >> "$LOG_FILE"
    exit 1
fi
echo "New application moved." >> "$LOG_FILE"

if [ "$(id -u)" -eq 0 ]; then
    CURRENT_USER=$(stat -f "%Su" /dev/console)
    su - "$CURRENT_USER" -c "open \"$OLD_APP_PATH\""
else
    open "$OLD_APP_PATH"
fi

echo "Update script finished." >> "$LOG_FILE"
echo "---------------------------------" >> "$LOG_FILE"

exit 0
