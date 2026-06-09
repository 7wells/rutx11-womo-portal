#!/bin/sh

LIVE_TRACK="${WOMO_LIVE_TRACK:-/tmp/womo/gps_track_live.log}"
TMP_DIR="${WOMO_TMP_DIR:-/tmp/womo}"
DATA_DIR="${WOMO_DATA_DIR:-/usr/local/home/root/womo-data}"
GPS_DIR="${WOMO_GPS_DIR:-$DATA_DIR/gps}"
LEGACY_TRACK="${WOMO_LEGACY_TRACK:-$DATA_DIR/gps_track.log}"
MAX_RANGE_DAYS=365

is_number() {
  awk -v value="$1" 'BEGIN { exit(value ~ /^-?[0-9]+(\.[0-9]+)?$/ ? 0 : 1) }'
}

date_to_epoch() {
  awk -v input="$1" '
function floor_div(a, b, q) {
  q = int(a / b)
  if (a < 0 && a % b != 0) q--
  return q
}

function days_from_civil(y, m, d, era, yoe, doy, doe, mp) {
  if (m <= 2) y--
  era = floor_div(y, 400)
  yoe = y - era * 400
  mp = m + (m > 2 ? -3 : 9)
  doy = int((153 * mp + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

function civil_from_days(z, out, era, doe, yoe, y, doy, mp, d, m) {
  z += 719468
  era = floor_div(z, 146097)
  doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153)
  d = doy - int((153 * mp + 2) / 5) + 1
  m = mp + (mp < 10 ? 3 : -9)
  if (m <= 2) y++
  return sprintf("%04d-%02d-%02d", y, m, d)
}

BEGIN {
  if (input !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit 1

  split(input, parts, "-")
  y = parts[1] + 0
  m = parts[2] + 0
  d = parts[3] + 0

  if (sprintf("%04d-%02d-%02d", y, m, d) != input) exit 1
  if (m < 1 || m > 12 || d < 1 || d > 31) exit 1

  days = days_from_civil(y, m, d)
  if (civil_from_days(days) != input) exit 1

  print days * 86400
}'
}

epoch_to_month() {
  awk -v ts="$1" '
function floor_div(a, b, q) {
  q = int(a / b)
  if (a < 0 && a % b != 0) q--
  return q
}

function civil_from_days(z, era, doe, yoe, y, doy, mp, d, m) {
  z += 719468
  era = floor_div(z, 146097)
  doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153)
  d = doy - int((153 * mp + 2) / 5) + 1
  m = mp + (mp < 10 ? 3 : -9)
  if (m <= 2) y++
  return sprintf("%04d-%02d", y, m)
}

BEGIN {
  if (ts !~ /^[0-9]+$/) exit 1
  print civil_from_days(int(ts / 86400))
}'
}

epoch_to_gpx_utc() {
  awk -v ts="$1" '
function floor_div(a, b, q) {
  q = int(a / b)
  if (a < 0 && a % b != 0) q--
  return q
}

function civil_from_days(z, era, doe, yoe, y, doy, mp, d, m) {
  z += 719468
  era = floor_div(z, 146097)
  doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153)
  d = doy - int((153 * mp + 2) / 5) + 1
  m = mp + (mp < 10 ? 3 : -9)
  if (m <= 2) y++
  return sprintf("%04d-%02d-%02d", y, m, d)
}

BEGIN {
  if (ts !~ /^[0-9]+$/) exit 1

  days = int(ts / 86400)
  seconds = ts - days * 86400
  h = int(seconds / 3600)
  seconds -= h * 3600
  min = int(seconds / 60)
  sec = seconds - min * 60

  printf "%sT%02d:%02d:%02dZ\n", civil_from_days(days), h, min, sec
}'
}

is_date() {
  date_to_epoch "$1" >/dev/null 2>&1
}

date_start_ts() {
  date_to_epoch "$1"
}

date_end_ts() {
  start_ts="$(date_to_epoch "$1")" || return 1
  printf '%s\n' $((start_ts + 86399))
}

json_string() {
  printf '%s' "$1" \
    | tr -d '\r\n' \
    | sed 's/\\/\\\\/g; s/"/\\"/g'
}

send_json_error() {
  status="$1"
  message="$2"

  printf 'Status: %s\r\n' "$status"
  printf 'Content-Type: application/json\r\n\r\n'
  printf '{"error":"%s"}\n' "$(json_string "$message")"
}

validate_date_range() {
  from_date="$1"
  to_date="$2"

  if [ -z "$from_date" ] || [ -z "$to_date" ]; then
    GPS_ERROR="from and to are required"
    return 1
  fi

  if ! is_date "$from_date" || ! is_date "$to_date"; then
    GPS_ERROR="from and to must use YYYY-MM-DD"
    return 1
  fi

  FROM_TS="$(date_start_ts "$from_date")"
  TO_TS="$(date_end_ts "$to_date")"

  if [ "$FROM_TS" -gt "$TO_TS" ]; then
    GPS_ERROR="from must be before or equal to to"
    return 1
  fi

  max_seconds=$((MAX_RANGE_DAYS * 86400))
  if [ $((TO_TS - FROM_TS + 1)) -gt "$max_seconds" ]; then
    GPS_ERROR="date range must not exceed 365 days"
    return 1
  fi

  return 0
}

ensure_gps_dirs() {
  mkdir -p "$TMP_DIR"
  mkdir -p "$DATA_DIR"
  mkdir -p "$GPS_DIR"
}
