#!/bin/sh

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d /tmp/womo-gps-test.XXXXXX)"
RUNTIME_DIR="$TEST_ROOT/runtime"
DATA_DIR="$TEST_ROOT/data"
GPS_DIR="$DATA_DIR/gps"
LIVE_TRACK="$RUNTIME_DIR/gps_track_live.log"
PENDING_TRACK="$RUNTIME_DIR/gps_track_pending.log"
LEGACY_TRACK="$DATA_DIR/gps_track.log"
FAKE_STATE="$TEST_ROOT/fake-gps-state"

# Remove isolated test data even when an assertion fails.
cleanup() {
  rm -rf "$TEST_ROOT"
}

# Stop the test with a concise failure message.
fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Count normalized track records in a file that may not exist yet.
count_points() {
  [ -f "$1" ] || {
    printf '0\n'
    return
  }
  awk -F',' 'NF == 3 { count++ } END { print count + 0 }' "$1"
}

trap cleanup 0 1 2 15

mkdir -p "$RUNTIME_DIR" "$GPS_DIR"

export WOMO_GPS_LIB="$REPO_ROOT/web/cgi-bin/gps_lib.sh"
export WOMO_GPSCTL="$REPO_ROOT/tests/fixtures/fake_gpsctl.sh"
export WOMO_GPS_POLL_INTERVAL=0
export WOMO_GPS_MIN_DISTANCE=20
export WOMO_GPS_MAX_ITERATIONS=4
export WOMO_GPS_SYNC_ON_EXIT=0
export WOMO_FAKE_GPS_STATE="$FAKE_STATE"
export WOMO_TMP_DIR="$RUNTIME_DIR"
export WOMO_DATA_DIR="$DATA_DIR"
export WOMO_GPS_DIR="$GPS_DIR"
export WOMO_LIVE_TRACK="$LIVE_TRACK"
export WOMO_PENDING_TRACK="$PENDING_TRACK"
export WOMO_PENDING_FLUSH="$RUNTIME_DIR/gps_track_pending.flush"
export WOMO_LEGACY_TRACK="$LEGACY_TRACK"
export WOMO_GPS_LOCK_DIR="$RUNTIME_DIR/gps_track.lock"
export WOMO_SYNC_LOCK_DIR="$RUNTIME_DIR/gps_sync.lock"
export WOMO_RETENTION_STAMP="$RUNTIME_DIR/gps_retention_day"

"$REPO_ROOT/scripts/womo_gps_logger.sh" >/dev/null

[ "$(count_points "$LIVE_TRACK")" -eq 3 ] || fail "logger did not keep exactly three moving points"
[ "$(count_points "$PENDING_TRACK")" -eq 3 ] || fail "logger did not queue exactly three points"

"$REPO_ROOT/scripts/sync_womo_gps_track.sh" >/dev/null

month_file="$GPS_DIR/$(date +%Y-%m).csv"
[ "$(count_points "$month_file")" -eq 3 ] || fail "sync did not persist all queued points"
[ "$(count_points "$PENDING_TRACK")" -eq 0 ] || fail "sync did not clear the persisted queue"

before_live="$(cksum "$LIVE_TRACK")"
before_month="$(cksum "$month_file")"
QUERY_STRING='range=24h' "$REPO_ROOT/web/cgi-bin/gps_track.cgi" > "$TEST_ROOT/track-response"

[ "$before_live" = "$(cksum "$LIVE_TRACK")" ] || fail "track CGI modified the live track"
[ "$before_month" = "$(cksum "$month_file")" ] || fail "track CGI modified persistent history"
[ "$(grep -o '"ts"' "$TEST_ROOT/track-response" | wc -l)" -eq 3 ] || fail "track CGI did not return all points"

today="$(date +%Y-%m-%d)"
QUERY_STRING="from=$today&to=$today&format=csv" "$REPO_ROOT/web/cgi-bin/gps_export.cgi" > "$TEST_ROOT/export-response"
[ "$(grep -c '^[0-9]' "$TEST_ROOT/export-response")" -eq 3 ] || fail "CSV export did not contain all points"

"$REPO_ROOT/scripts/sync_womo_gps_track.sh" >/dev/null
[ "$(count_points "$month_file")" -eq 3 ] || fail "a second sync duplicated points"

printf '%s,%s,%s\n' "$(date +%s)" "52.000900" "13.000000" > "$LEGACY_TRACK"
"$REPO_ROOT/scripts/sync_womo_gps_track.sh" --import-existing >/dev/null
[ "$(count_points "$month_file")" -eq 4 ] || fail "upgrade import did not preserve a legacy point"
[ ! -s "$LEGACY_TRACK" ] || fail "upgrade import did not clear the migrated legacy source"

echo "OK: background GPS recording, persistence, read-only CGI, and export verified."
