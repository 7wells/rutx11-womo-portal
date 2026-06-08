#!/bin/sh

set -eu

LIVE_TRACK="/tmp/womo/gps_track_live.log"
PERSISTENT_TRACK="/usr/local/home/root/womo-data/gps_track.log"
TMP_FILE="/tmp/womo/gps_track_sync.tmp"

NOW="$(date +%s)"
RETENTION_LIMIT=$((NOW - 15552000))

mkdir -p /tmp/womo
mkdir -p /usr/local/home/root/womo-data

touch "$LIVE_TRACK"
touch "$PERSISTENT_TRACK"

# Merge volatile live points into persistent storage and keep 180 days.
cat "$PERSISTENT_TRACK" "$LIVE_TRACK" 2>/dev/null \
  | awk -F',' -v limit="$RETENTION_LIMIT" '
      NF == 3 && $1 >= limit
    ' \
  | sort -t',' -k1,1n -u \
  > "$TMP_FILE"

mv "$TMP_FILE" "$PERSISTENT_TRACK"

echo "OK: GPS track synced."
