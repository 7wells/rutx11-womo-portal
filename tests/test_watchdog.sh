#!/bin/sh

set -eu

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WATCHDOG="$REPO_ROOT/scripts/womo_portal_watchdog.sh"
FETCH_FIXTURE="$REPO_ROOT/tests/fixtures/fake_watchdog_fetch.sh"
INIT_FIXTURE="$REPO_ROOT/tests/fixtures/fake_watchdog_init.sh"
SYNC_FIXTURE="$REPO_ROOT/tests/fixtures/fake_watchdog_sync.sh"
TEST_ROOT="$(mktemp -d /tmp/womo-watchdog-test.XXXXXX)"

# Remove every isolated test case after the suite completes.
cleanup_tests() {
  rm -rf "$TEST_ROOT"
}

# Create one fake RutOS environment with healthy defaults.
prepare_case() {
  case_name="$1"
  CASE_DIR="$TEST_ROOT/$case_name"
  mkdir -p "$CASE_DIR/bin" "$CASE_DIR/state"

  cp "$INIT_FIXTURE" "$CASE_DIR/bin/uhttpd"
  cp "$INIT_FIXTURE" "$CASE_DIR/bin/gps-logger"
  cp "$INIT_FIXTURE" "$CASE_DIR/bin/cron"
  cp "$SYNC_FIXTURE" "$CASE_DIR/bin/sync"
  chmod 755 "$CASE_DIR/bin/uhttpd" "$CASE_DIR/bin/gps-logger" "$CASE_DIR/bin/cron" "$CASE_DIR/bin/sync"

  ACTION_LOG="$CASE_DIR/actions.log"
  CRON_FILE="$CASE_DIR/root.cron"
  PENDING_TRACK="$CASE_DIR/pending.log"
  PENDING_FLUSH="$CASE_DIR/pending.flush"
  : > "$ACTION_LOG"
  : > "$PENDING_TRACK"
  : > "$PENDING_FLUSH"
  printf '*/5 * * * * %s\n' "$CASE_DIR/bin/sync" > "$CRON_FILE"
}

# Run a bounded watchdog loop against the current fake environment.
run_watchdog() {
  iterations="$1"

  WOMO_FAKE_ACTION_LOG="$ACTION_LOG" \
  WOMO_FAKE_FETCH_MODE="${WOMO_FAKE_FETCH_MODE:-healthy}" \
  WOMO_FAKE_FAILED_SERVICE="${WOMO_FAKE_FAILED_SERVICE:-}" \
  WOMO_WATCHDOG_PORTAL_URL="http://local/index.html" \
  WOMO_WATCHDOG_GPS_URL="http://local/cgi-bin/gps.json" \
  WOMO_WATCHDOG_UHTTPD_INIT="$CASE_DIR/bin/uhttpd" \
  WOMO_WATCHDOG_GPS_LOGGER_INIT="$CASE_DIR/bin/gps-logger" \
  WOMO_WATCHDOG_CRON_INIT="$CASE_DIR/bin/cron" \
  WOMO_WATCHDOG_SYNC_SCRIPT="$CASE_DIR/bin/sync" \
  WOMO_WATCHDOG_CRON_FILE="$CRON_FILE" \
  WOMO_WATCHDOG_PENDING_TRACK="$PENDING_TRACK" \
  WOMO_WATCHDOG_PENDING_FLUSH="$PENDING_FLUSH" \
  WOMO_WATCHDOG_STATE_DIR="$CASE_DIR/state" \
  WOMO_WATCHDOG_FETCH_COMMAND="$FETCH_FIXTURE" \
  WOMO_WATCHDOG_INTERVAL=0 \
  WOMO_WATCHDOG_FAILURE_LIMIT=3 \
  WOMO_WATCHDOG_COOLDOWN=300 \
  WOMO_WATCHDOG_PENDING_MAX_AGE=600 \
  WOMO_WATCHDOG_MAX_ITERATIONS="$iterations" \
  WOMO_WATCHDOG_DISABLE_SYSLOG=1 \
  sh "$WATCHDOG" > "$CASE_DIR/output.log"
}

# Fail with a readable message when expected recovery activity is missing.
assert_contains() {
  expected="$1"
  file="$2"
  grep -Fq "$expected" "$file" || {
    echo "FAIL: expected '$expected' in $file" >&2
    exit 1
  }
}

# Fail when recovery happens before its configured threshold.
assert_not_contains() {
  unexpected="$1"
  file="$2"
  if grep -Fq "$unexpected" "$file"; then
    echo "FAIL: unexpected '$unexpected' in $file" >&2
    exit 1
  fi
}

trap cleanup_tests 0

prepare_case healthy
run_watchdog 1
assert_not_contains 'uhttpd restart' "$ACTION_LOG"
assert_not_contains 'gps-logger start' "$ACTION_LOG"

prepare_case threshold
WOMO_FAKE_FETCH_MODE=fail
run_watchdog 2
unset WOMO_FAKE_FETCH_MODE
assert_not_contains 'uhttpd restart' "$ACTION_LOG"

prepare_case portal-recovery
WOMO_FAKE_FETCH_MODE=fail
run_watchdog 3
unset WOMO_FAKE_FETCH_MODE
assert_contains 'uhttpd restart' "$ACTION_LOG"

prepare_case logger-recovery
WOMO_FAKE_FAILED_SERVICE=gps-logger
run_watchdog 3
unset WOMO_FAKE_FAILED_SERVICE
assert_contains 'gps-logger stop' "$ACTION_LOG"
assert_contains 'gps-logger start' "$ACTION_LOG"

prepare_case persistence-recovery
: > "$CRON_FILE"
run_watchdog 3
assert_contains 'cron restart' "$ACTION_LOG"
assert_contains 'sync run' "$ACTION_LOG"
assert_contains "$CASE_DIR/bin/sync" "$CRON_FILE"

prepare_case overdue-pending
old_timestamp=$(($(date +%s) - 601))
printf '%s,51.0,10.0\n' "$old_timestamp" > "$PENDING_TRACK"
run_watchdog 3
assert_contains 'sync run' "$ACTION_LOG"

echo "OK: watchdog checks and recovery thresholds passed."
