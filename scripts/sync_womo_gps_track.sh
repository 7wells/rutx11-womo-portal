#!/bin/sh

set -eu

GPS_LIB="${WOMO_GPS_LIB:-/usr/local/home/www/womo/cgi-bin/gps_lib.sh}"

if [ ! -f "$GPS_LIB" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_LIB="$SCRIPT_DIR/../web/cgi-bin/gps_lib.sh"

  if [ -f "$REPO_LIB" ]; then
    GPS_LIB="$REPO_LIB"
  fi
fi

. "$GPS_LIB"

LIVE_TRACK="${WOMO_LIVE_TRACK:-/tmp/womo/gps_track_live.log}"
DATA_DIR="${WOMO_DATA_DIR:-/usr/local/home/root/womo-data}"
GPS_DIR="${WOMO_GPS_DIR:-$DATA_DIR/gps}"
LEGACY_TRACK="${WOMO_LEGACY_TRACK:-$DATA_DIR/gps_track.log}"
TMP_DIR="${WOMO_TMP_DIR:-/tmp/womo}"
TMP_SORTED="$TMP_DIR/gps_track_sync_sorted.tmp"
TMP_LIVE="$TMP_DIR/gps_track_live.tmp"

NOW="$(date +%s)"
RETENTION_LIMIT=$((NOW - 31536000))
LIVE_LIMIT=$((NOW - 3600))

mkdir -p "$TMP_DIR"
mkdir -p "$DATA_DIR"
mkdir -p "$GPS_DIR"

touch "$LIVE_TRACK"
touch "$LEGACY_TRACK"

# Merge all known track sources and keep 365 days.
cat "$LEGACY_TRACK" "$LIVE_TRACK" "$GPS_DIR"/*.csv 2>/dev/null \
  | awk -F',' -v limit="$RETENTION_LIMIT" '
      function valid_number(value) {
        return value ~ /^-?[0-9]+(\.[0-9]+)?$/
      }

      NF == 3 && valid_number($1) && valid_number($2) && valid_number($3) && $1 >= limit
    ' \
  | sort -t',' -k1,1n -u \
  > "$TMP_SORTED"

rm -f "$GPS_DIR"/*.csv

while IFS=',' read -r TS LAT LON
do
  month="$(epoch_to_month "$TS")" || continue
  printf '%s,%s,%s\n' "$TS" "$LAT" "$LON" >> "$GPS_DIR/$month.csv"
done < "$TMP_SORTED"

# Keep live storage small; longer history is served from monthly files.
awk -F',' -v limit="$LIVE_LIMIT" '
  function valid_number(value) {
    return value ~ /^-?[0-9]+(\.[0-9]+)?$/
  }

  NF == 3 && valid_number($1) && valid_number($2) && valid_number($3) && $1 >= limit
' "$LIVE_TRACK" > "$TMP_LIVE"

mv "$TMP_LIVE" "$LIVE_TRACK"
rm -f "$TMP_SORTED"

echo "OK: GPS track synced."
