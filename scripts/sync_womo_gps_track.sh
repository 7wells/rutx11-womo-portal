#!/bin/sh

set -eu

GPS_LIB="${WOMO_GPS_LIB:-/usr/local/home/www/womo/cgi-bin/gps_lib.sh}"

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
PENDING_FLUSH="${WOMO_PENDING_FLUSH:-/tmp/womo/gps_track_pending.flush}"
SYNC_LOCK_DIR="${WOMO_SYNC_LOCK_DIR:-/tmp/womo/gps_sync.lock}"
RETENTION_STAMP="${WOMO_RETENTION_STAMP:-/tmp/womo/gps_retention_day}"
IMPORT_EXISTING=0
SYNC_LOCK_HELD=0
STAGE_DIR=""
TMP_LIVE="$TMP_DIR/gps_track_live.tmp.$$"
TMP_IMPORT="$TMP_DIR/gps_track_import.tmp.$$"

[ "${1:-}" != "--import-existing" ] || IMPORT_EXISTING=1

NOW="$(date +%s)"
RETENTION_LIMIT=$((NOW - 31536000))
LIVE_LIMIT=$((NOW - 3600))

# Prevent overlapping cron, shutdown, and installer sync runs.
acquire_sync_lock() {
  missing_owner_waits=0
  mkdir -p "$TMP_DIR"

  while ! mkdir "$SYNC_LOCK_DIR" 2>/dev/null; do
    sync_owner="$(cat "$SYNC_LOCK_DIR/pid" 2>/dev/null || true)"

    case "$sync_owner" in
      ''|*[!0-9]*)
        missing_owner_waits=$((missing_owner_waits + 1))
        if [ "$missing_owner_waits" -ge 3 ]; then
          rm -rf "$SYNC_LOCK_DIR"
          missing_owner_waits=0
          continue
        fi
        sleep 1
        ;;
      *)
        if kill -0 "$sync_owner" 2>/dev/null; then
          return 1
        fi
        rm -rf "$SYNC_LOCK_DIR"
        ;;
    esac
  done

  printf '%s\n' "$$" > "$SYNC_LOCK_DIR/pid"
  SYNC_LOCK_HELD=1
}

# Remove temporary files and only locks owned by this process.
cleanup_sync() {
  release_gps_lock
  rm -f "$TMP_LIVE" "$TMP_IMPORT"
  [ -z "$STAGE_DIR" ] || rm -rf "$STAGE_DIR"

  if [ "$SYNC_LOCK_HELD" -eq 1 ]; then
    sync_owner="$(cat "$SYNC_LOCK_DIR/pid" 2>/dev/null || true)"
    [ "$sync_owner" != "$$" ] || rm -rf "$SYNC_LOCK_DIR"
  fi
}

# Keep the live display file small and rotate pending points for persistence.
rotate_runtime_tracks() {
  acquire_gps_lock
  touch "$LIVE_TRACK" "$PENDING_TRACK"

  if [ -s "$PENDING_TRACK" ]; then
    if [ -f "$PENDING_FLUSH" ]; then
      cat "$PENDING_TRACK" >> "$PENDING_FLUSH"
      : > "$PENDING_TRACK"
    else
      mv "$PENDING_TRACK" "$PENDING_FLUSH"
      touch "$PENDING_TRACK"
    fi
  fi

  awk -F',' -v limit="$LIVE_LIMIT" '
function trim(value) {
  gsub(/^[ \t\r]+|[ \t\r]+$/, "", value)
  return value
}

function valid_number(value) {
  return value ~ /^-?[0-9]+(\.[0-9]+)?$/
}

NF == 3 {
  ts = trim($1)
  lat = trim($2)
  lon = trim($3)

  if (valid_number(ts) && valid_number(lat) && valid_number(lon) && ts >= limit) {
    print ts "," lat "," lon
  }
}
' "$LIVE_TRACK" > "$TMP_LIVE"

  mv "$TMP_LIVE" "$LIVE_TRACK"
  chmod 644 "$LIVE_TRACK" "$PENDING_TRACK"
  release_gps_lock
}

# Add pre-upgrade runtime and legacy points to the next persistent batch.
queue_existing_sources() {
  [ "$IMPORT_EXISTING" -eq 1 ] || return 0

  acquire_gps_lock
  cat "$LEGACY_TRACK" "$LIVE_TRACK" "$PENDING_TRACK" "$PENDING_FLUSH" 2>/dev/null |
    awk -F',' -v limit="$RETENTION_LIMIT" '
function trim(value) {
  gsub(/^[ \t\r]+|[ \t\r]+$/, "", value)
  return value
}

function valid_number(value) {
  return value ~ /^-?[0-9]+(\.[0-9]+)?$/
}

NF == 3 {
  ts = trim($1)
  lat = trim($2)
  lon = trim($3)

  if (valid_number(ts) && valid_number(lat) && valid_number(lon) && ts >= limit) {
    print ts "," lat "," lon
  }
}
' | sort -t',' -k1,1n -k2,2n -k3,3n -u > "$TMP_IMPORT"

  mv "$TMP_IMPORT" "$PENDING_FLUSH"
  : > "$PENDING_TRACK"
  release_gps_lock
}

# Append one rotated RAM batch to the matching persistent month files.
persist_pending_points() {
  [ -s "$PENDING_FLUSH" ] || {
    rm -f "$PENDING_FLUSH"
    return 0
  }

  STAGE_DIR="$(mktemp -d "$TMP_DIR/gps-persist.XXXXXX")"

  while IFS=',' read -r ts lat lon
  do
    case "$ts" in
      ''|*[!0-9]*)
        continue
        ;;
    esac
    is_valid_latitude "$lat" || continue
    is_valid_longitude "$lon" || continue
    [ "$ts" -ge "$RETENTION_LIMIT" ] || continue

    month="$(epoch_to_month "$ts" 2>/dev/null || true)"
    [ -n "$month" ] || continue
    printf '%s,%s,%s\n' "$ts" "$lat" "$lon" >> "$STAGE_DIR/$month.csv"
  done < "$PENDING_FLUSH"

  for staged_file in "$STAGE_DIR"/*.csv
  do
    [ -f "$staged_file" ] || continue
    target="$GPS_DIR/$(basename "$staged_file")"
    delta_file="$staged_file.delta"

    if [ -f "$target" ]; then
      awk 'NR == FNR { seen[$0] = 1; next } !seen[$0]++' "$target" "$staged_file" > "$delta_file"
    else
      cp "$staged_file" "$delta_file"
    fi

    [ -s "$delta_file" ] || continue

    if [ ! -e "$target" ]; then
      : > "$target"
      chmod 644 "$target"
    fi

    cat "$delta_file" >> "$target"
  done

  rm -f "$PENDING_FLUSH"
  rm -rf "$STAGE_DIR"
  STAGE_DIR=""

  if [ "$IMPORT_EXISTING" -eq 1 ] && [ -f "$LEGACY_TRACK" ]; then
    : > "$LEGACY_TRACK"
  fi
}

# Remove expired or duplicate persistent points at most once per day.
maintain_retention() {
  today="$(date +%Y-%m-%d)"
  [ "$(cat "$RETENTION_STAMP" 2>/dev/null || true)" != "$today" ] || return 0

  for track_file in "$GPS_DIR"/*.csv
  do
    [ -f "$track_file" ] || continue
    cleaned_file="$TMP_DIR/gps-clean.$$.csv"

    awk -F',' -v limit="$RETENTION_LIMIT" '
function trim(value) {
  gsub(/^[ \t\r]+|[ \t\r]+$/, "", value)
  return value
}

function valid_number(value) {
  return value ~ /^-?[0-9]+(\.[0-9]+)?$/
}

NF == 3 {
  ts = trim($1)
  lat = trim($2)
  lon = trim($3)

  if (valid_number(ts) && valid_number(lat) && valid_number(lon) && ts >= limit) {
    print ts "," lat "," lon
  }
}
' "$track_file" | sort -t',' -k1,1n -k2,2n -k3,3n -u > "$cleaned_file"

    if [ ! -s "$cleaned_file" ]; then
      rm -f "$track_file"
    elif ! cmp -s "$cleaned_file" "$track_file"; then
      replacement="$track_file.tmp.$$"
      cp "$cleaned_file" "$replacement"
      chmod 644 "$replacement"
      mv -f "$replacement" "$track_file"
    fi

    rm -f "$cleaned_file"
  done

  printf '%s\n' "$today" > "$RETENTION_STAMP"
}

trap cleanup_sync 0
trap 'exit 1' 1 2 15

mkdir -p "$TMP_DIR" "$DATA_DIR" "$GPS_DIR"
[ -f "$LIVE_TRACK" ] || : > "$LIVE_TRACK"
[ -f "$PENDING_TRACK" ] || : > "$PENDING_TRACK"

if ! acquire_sync_lock; then
  echo "OK: GPS sync already running."
  exit 0
fi

queue_existing_sources
rotate_runtime_tracks
persist_pending_points
maintain_retention

echo "OK: GPS track synced."
