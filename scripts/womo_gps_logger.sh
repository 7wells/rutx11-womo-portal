#!/bin/sh

set -u

GPS_LIB="${WOMO_GPS_LIB:-/usr/local/home/www/womo/cgi-bin/gps_lib.sh}"
GPSCTL="${WOMO_GPSCTL:-gpsctl}"
POLL_INTERVAL="${WOMO_GPS_POLL_INTERVAL:-5}"
MIN_DISTANCE="${WOMO_GPS_MIN_DISTANCE:-20}"
MAX_ITERATIONS="${WOMO_GPS_MAX_ITERATIONS:-0}"
SYNC_ON_EXIT="${WOMO_GPS_SYNC_ON_EXIT:-1}"
SYNC_SCRIPT="${WOMO_GPS_SYNC_SCRIPT:-/usr/local/bin/sync_womo_gps_track.sh}"

if [ ! -f "$GPS_LIB" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
  REPO_LIB="$SCRIPT_DIR/../web/cgi-bin/gps_lib.sh"
  [ ! -f "$REPO_LIB" ] || GPS_LIB="$REPO_LIB"
fi

[ -f "$GPS_LIB" ] || {
  echo "ERROR: GPS library missing: $GPS_LIB" >&2
  exit 1
}

# shellcheck source=../web/cgi-bin/gps_lib.sh
. "$GPS_LIB"

LIVE_TRACK="${WOMO_LIVE_TRACK:-/tmp/womo/gps_track_live.log}"
PENDING_TRACK="${WOMO_PENDING_TRACK:-/tmp/womo/gps_track_pending.log}"
RUNNING=1
ITERATIONS=0
LAST_LAT=""
LAST_LON=""

# Ask the main loop to finish after the current GPS read.
request_stop() {
  RUNNING=0
}

# Release locks and persist the final pending batch during a clean stop.
cleanup_logger() {
  release_gps_lock
  if [ "$SYNC_ON_EXIT" -eq 1 ] && [ -x "$SYNC_SCRIPT" ]; then
    "$SYNC_SCRIPT" >/dev/null 2>&1 || true
  fi
}

# Seed distance filtering from the newest runtime or persistent point.
load_last_point() {
  last_line="$(tail -n 1 "$LIVE_TRACK" 2>/dev/null || true)"
  if [ -z "$last_line" ]; then
    last_line="$(emit_gps_points 0 "$(date +%s)" 2>/dev/null | tail -n 1 || true)"
  fi

  LAST_LAT="$(printf '%s\n' "$last_line" | awk -F',' '{ print $2 }')"
  LAST_LON="$(printf '%s\n' "$last_line" | awk -F',' '{ print $3 }')"
}

# Record one valid point in RAM when it is far enough from the previous point.
record_current_point() {
  lat="$("$GPSCTL" -i 2>/dev/null || true)"
  lon="$("$GPSCTL" -x 2>/dev/null || true)"

  [ "$RUNNING" -eq 1 ] || return 0
  is_valid_latitude "$lat" || return 0
  is_valid_longitude "$lon" || return 0

  if is_valid_latitude "$LAST_LAT" && is_valid_longitude "$LAST_LON"; then
    distance="$(gps_distance_metres "$lat" "$lon" "$LAST_LAT" "$LAST_LON")"
    distance_int="${distance%.*}"
    [ "$distance_int" -ge "$MIN_DISTANCE" ] || return 0
  fi

  timestamp="$(date +%s)"
  acquire_gps_lock
  printf '%s,%s,%s\n' "$timestamp" "$lat" "$lon" >> "$PENDING_TRACK"
  printf '%s,%s,%s\n' "$timestamp" "$lat" "$lon" >> "$LIVE_TRACK"
  release_gps_lock

  LAST_LAT="$lat"
  LAST_LON="$lon"
}

trap request_stop 1 2 15
trap cleanup_logger 0

mkdir -p "$TMP_DIR"
touch "$LIVE_TRACK" "$PENDING_TRACK"
chmod 644 "$LIVE_TRACK" "$PENDING_TRACK"
load_last_point

echo "WoMo GPS logger started: ${POLL_INTERVAL}s interval, ${MIN_DISTANCE}m minimum distance."

while [ "$RUNNING" -eq 1 ]; do
  record_current_point
  ITERATIONS=$((ITERATIONS + 1))

  if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATIONS" -ge "$MAX_ITERATIONS" ]; then
    break
  fi

  sleep "$POLL_INTERVAL"
done

echo "WoMo GPS logger stopped."
