#!/bin/sh

set -u

# Monitor the local portal and GPS services without depending on external devices.
PORTAL_PAGE_URL="${WOMO_WATCHDOG_PORTAL_URL:-http://127.0.0.1:8080/index.html}"
GPS_BACKEND_URL="${WOMO_WATCHDOG_GPS_URL:-http://127.0.0.1:8080/cgi-bin/gps.json}"
UHTTPD_INIT="${WOMO_WATCHDOG_UHTTPD_INIT:-/etc/init.d/uhttpd}"
GPS_LOGGER_INIT="${WOMO_WATCHDOG_GPS_LOGGER_INIT:-/etc/init.d/womo-gps-logger}"
CRON_INIT="${WOMO_WATCHDOG_CRON_INIT:-/etc/init.d/cron}"
SYNC_SCRIPT="${WOMO_WATCHDOG_SYNC_SCRIPT:-/usr/local/bin/sync_womo_gps_track.sh}"
CRON_FILE="${WOMO_WATCHDOG_CRON_FILE:-/etc/crontabs/root}"
PENDING_TRACK="${WOMO_WATCHDOG_PENDING_TRACK:-/tmp/womo/gps_track_pending.log}"
PENDING_FLUSH="${WOMO_WATCHDOG_PENDING_FLUSH:-/tmp/womo/gps_track_pending.flush}"
STATE_DIR="${WOMO_WATCHDOG_STATE_DIR:-/tmp/womo/watchdog}"
CHECK_INTERVAL="${WOMO_WATCHDOG_INTERVAL:-60}"
FAILURE_LIMIT="${WOMO_WATCHDOG_FAILURE_LIMIT:-3}"
RECOVERY_COOLDOWN="${WOMO_WATCHDOG_COOLDOWN:-300}"
PENDING_MAX_AGE="${WOMO_WATCHDOG_PENDING_MAX_AGE:-600}"
MAX_ITERATIONS="${WOMO_WATCHDOG_MAX_ITERATIONS:-0}"
FETCH_COMMAND="${WOMO_WATCHDOG_FETCH_COMMAND:-}"
LOG_STDOUT="${WOMO_WATCHDOG_LOG_STDOUT:-0}"
DISABLE_SYSLOG="${WOMO_WATCHDOG_DISABLE_SYSLOG:-0}"
FRONTEND_RESPONSE="$STATE_DIR/frontend-response.$$"
BACKEND_RESPONSE="$STATE_DIR/backend-response.$$"
RUNNING=1
ITERATIONS=0

# Stop after the current health-check cycle when procd terminates the service.
request_stop() {
  RUNNING=0
}

# Remove request bodies while keeping failure counters across service restarts.
cleanup_watchdog() {
  rm -f "$FRONTEND_RESPONSE" "$BACKEND_RESPONSE"
}

# Write concise recovery information to the router log and optionally stdout.
log_message() {
  priority="$1"
  shift
  message="$*"

  if [ "$DISABLE_SYSLOG" -ne 1 ] && command -v logger >/dev/null 2>&1; then
    logger -t womo-watchdog -p "daemon.$priority" "$message" 2>/dev/null || true
  fi

  if [ "$LOG_STDOUT" -eq 1 ]; then
    printf '%s: %s\n' "$priority" "$message"
  fi
}

# Reject invalid numeric settings before entering the permanent service loop.
validate_settings() {
  for setting in "$CHECK_INTERVAL" "$FAILURE_LIMIT" "$RECOVERY_COOLDOWN" "$PENDING_MAX_AGE" "$MAX_ITERATIONS"; do
    case "$setting" in
      ''|*[!0-9]*)
        log_message err "Watchdog configuration contains a non-numeric value."
        return 1
        ;;
    esac
  done

  [ "$FAILURE_LIMIT" -gt 0 ] || return 1
}

# Fetch one local URL with strict timeouts and no retained response cache.
fetch_url() {
  url="$1"
  target="$2"

  if [ -n "$FETCH_COMMAND" ]; then
    "$FETCH_COMMAND" "$url" "$target"
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsS --connect-timeout 3 --max-time 5 "$url" -o "$target"
    return
  fi

  if command -v wget >/dev/null 2>&1; then
    wget -q -T 5 -t 1 -O "$target" "$url"
    return
  fi

  return 1
}

# Verify that both the map page and its local GPS CGI return recognizable data.
check_portal() {
  rm -f "$FRONTEND_RESPONSE" "$BACKEND_RESPONSE"

  fetch_url "$PORTAL_PAGE_URL" "$FRONTEND_RESPONSE" || return 1
  grep -Fq '<title>WoMo Karte</title>' "$FRONTEND_RESPONSE" || return 1

  fetch_url "$GPS_BACKEND_URL" "$BACKEND_RESPONSE" || return 1
  grep -Fq '"historyAvailable":' "$BACKEND_RESPONSE" || return 1
}

# Ask the installed init script whether the independent GPS logger is running.
check_gps_logger() {
  [ -x "$GPS_LOGGER_INIT" ] || return 1
  "$GPS_LOGGER_INIT" status >/dev/null 2>&1
}

# Confirm that one pending batch has not waited far beyond the five-minute cycle.
pending_file_is_fresh() {
  pending_file="$1"
  [ -s "$pending_file" ] || return 0

  first_timestamp="$(sed -n '1s/,.*//p' "$pending_file" 2>/dev/null || true)"
  case "$first_timestamp" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  now="$(date +%s)"
  age=$((now - first_timestamp))
  [ "$age" -le "$PENDING_MAX_AGE" ]
}

# Check the cron job, cron service, sync script, and age of unpersisted GPS data.
check_gps_persistence() {
  [ -x "$SYNC_SCRIPT" ] || return 1
  [ -f "$CRON_FILE" ] || return 1
  awk -v command="$SYNC_SCRIPT" '
    $0 !~ /^[[:space:]]*#/ && index($0, command) { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$CRON_FILE" || return 1
  [ -x "$CRON_INIT" ] || return 1
  "$CRON_INIT" status >/dev/null 2>&1 || return 1
  pending_file_is_fresh "$PENDING_TRACK" || return 1
  pending_file_is_fresh "$PENDING_FLUSH"
}

# Restart uhttpd so all configured instances, including the portal, are rebuilt.
recover_portal() {
  [ -x "$UHTTPD_INIT" ] || return 1
  "$UHTTPD_INIT" restart >/dev/null 2>&1
}

# Start a missing GPS logger without issuing another stop for an absent service.
recover_gps_logger() {
  [ -x "$GPS_LOGGER_INIT" ] || return 1
  "$GPS_LOGGER_INIT" stop >/dev/null 2>&1 || true
  "$GPS_LOGGER_INIT" start >/dev/null 2>&1
}

# Restore the known persistence cron entry if it has disappeared.
ensure_persistence_cron() {
  mkdir -p "$(dirname "$CRON_FILE")"
  touch "$CRON_FILE"

  if awk -v command="$SYNC_SCRIPT" '
    $0 !~ /^[[:space:]]*#/ && index($0, command) { found = 1 }
    END { exit(found ? 0 : 1) }
  ' "$CRON_FILE"; then
    return 0
  fi

  cron_tmp="$CRON_FILE.tmp.$$"
  grep -Fv "$SYNC_SCRIPT" "$CRON_FILE" > "$cron_tmp" || true
  printf '*/5 * * * * %s\n' "$SYNC_SCRIPT" >> "$cron_tmp"
  mv -f "$cron_tmp" "$CRON_FILE"
}

# Restart cron and flush overdue points only after persistence repeatedly fails.
recover_gps_persistence() {
  [ -x "$SYNC_SCRIPT" ] || return 1
  [ -x "$CRON_INIT" ] || return 1
  ensure_persistence_cron || return 1
  "$CRON_INIT" restart >/dev/null 2>&1 || return 1
  "$SYNC_SCRIPT" >/dev/null 2>&1
}

# Run the recovery action assigned to one fixed, internal component name.
recover_component() {
  component="$1"

  case "$component" in
    portal)
      recover_portal
      ;;
    gps-logger)
      recover_gps_logger
      ;;
    gps-persistence)
      recover_gps_persistence
      ;;
    *)
      return 1
      ;;
  esac
}

# Read a numeric state value while treating damaged runtime state as empty.
read_state_number() {
  state_file="$1"
  state_value="$(cat "$state_file" 2>/dev/null || true)"

  case "$state_value" in
    ''|*[!0-9]*)
      printf '0\n'
      ;;
    *)
      printf '%s\n' "$state_value"
      ;;
  esac
}

# Clear failures and cooldown after a component becomes healthy again.
record_success() {
  component="$1"
  failures_file="$STATE_DIR/$component.failures"
  cooldown_file="$STATE_DIR/$component.cooldown"
  failures="$(read_state_number "$failures_file")"

  if [ "$failures" -gt 0 ]; then
    log_message notice "$component is healthy again."
  fi

  rm -f "$failures_file" "$cooldown_file"
}

# Count failures and recover only after the threshold and cooldown permit it.
record_failure() {
  component="$1"
  failures_file="$STATE_DIR/$component.failures"
  cooldown_file="$STATE_DIR/$component.cooldown"
  failures="$(read_state_number "$failures_file")"
  failures=$((failures + 1))
  printf '%s\n' "$failures" > "$failures_file"

  if [ "$failures" -eq 1 ]; then
    log_message warning "$component health check failed."
  fi

  [ "$failures" -ge "$FAILURE_LIMIT" ] || return 0

  now="$(date +%s)"
  cooldown_until="$(read_state_number "$cooldown_file")"
  [ "$now" -ge "$cooldown_until" ] || return 0

  if recover_component "$component"; then
    log_message warning "$component recovery started after $failures failed checks."
  else
    log_message err "$component recovery failed after $failures failed checks."
  fi

  printf '%s\n' $((now + RECOVERY_COOLDOWN)) > "$cooldown_file"
}

# Check all local components once; ESP32 availability is intentionally excluded.
run_health_checks() {
  if check_portal; then
    record_success portal
  else
    record_failure portal
  fi

  if check_gps_logger; then
    record_success gps-logger
  else
    record_failure gps-logger
  fi

  if check_gps_persistence; then
    record_success gps-persistence
  else
    record_failure gps-persistence
  fi
}

trap request_stop 1 2 15
trap cleanup_watchdog 0

mkdir -p "$STATE_DIR"
validate_settings || exit 1
log_message notice "WoMo portal watchdog started."

while [ "$RUNNING" -eq 1 ]; do
  run_health_checks
  ITERATIONS=$((ITERATIONS + 1))

  if [ "$MAX_ITERATIONS" -gt 0 ] && [ "$ITERATIONS" -ge "$MAX_ITERATIONS" ]; then
    break
  fi

  sleep "$CHECK_INTERVAL"
done

log_message notice "WoMo portal watchdog stopped."
