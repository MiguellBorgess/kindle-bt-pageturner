#!/bin/sh
# Listens for Bluetooth earbud button presses (AVRCP commands) and appends
# a line to a file for each one. The KOReader plugin watches that file and
# turns the page.
#
# Usage: sh listener.sh /path/to/events_file

FLAG="$1"
CHILD=""

# When the plugin asks us to stop (TERM signal), also stop lipc-wait-event
trap 'kill $CHILD 2>/dev/null; exit 0' TERM INT

while true; do
    # Wait for ONE button event. Without "-m", lipc-wait-event exits right
    # after the first event, which avoids output buffering issues.
    lipc-wait-event com.lab126.btfd BTavrcpCommand > /dev/null 2>&1 &
    CHILD=$!
    if wait $CHILD; then
        echo 1 >> "$FLAG"      # a tap arrived: record it
    else
        sleep 2                # Bluetooth service unavailable: wait and retry
    fi
done
