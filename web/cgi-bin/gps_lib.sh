#!/bin/sh

LIVE_TRACK="${WOMO_LIVE_TRACK:-/tmp/womo/gps_track_live.log}"
TMP_DIR="${WOMO_TMP_DIR:-/tmp/womo}"
DATA_DIR="${WOMO_DATA_DIR:-/usr/local/home/womo-data}"
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

date_to_days() {
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
  if (input !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) exit 1

  split(input, parts, "-")
  y = parts[1] + 0
  m = parts[2] + 0
  d = parts[3] + 0

  if (sprintf("%04d-%02d-%02d", y, m, d) != input) exit 1
  if (m < 1 || m > 12 || d < 1 || d > 31) exit 1

  days = days_from_civil(y, m, d)
  if (civil_from_days(days) != input) exit 1

  print days
}'
}

berlin_offset_for_local() {
  awk -v input="$1" -v hour="$2" '
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

function weekday(y, m, d) {
  return (days_from_civil(y, m, d) + 4) % 7
}

function last_sunday(year, month, day) {
  day = 31
  while (weekday(year, month, day) != 0) day--
  return day
}

BEGIN {
  split(input, parts, "-")
  y = parts[1] + 0
  m = parts[2] + 0
  d = parts[3] + 0
  hour += 0

  offset = 3600

  if (m > 3 && m < 10) {
    offset = 7200
  } else if (m == 3) {
    transition = last_sunday(y, 3)
    if (d > transition || (d == transition && hour >= 3)) offset = 7200
  } else if (m == 10) {
    transition = last_sunday(y, 10)
    if (d < transition || (d == transition && hour < 3)) offset = 7200
  }

  print offset
}'
}

berlin_offset_for_epoch() {
  awk -v ts="$1" '
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
  year = y
  month = m
  day = d
}

function weekday(y, m, d) {
  return (days_from_civil(y, m, d) + 4) % 7
}

function last_sunday(year, month, day) {
  day = 31
  while (weekday(year, month, day) != 0) day--
  return day
}

BEGIN {
  if (ts !~ /^[0-9]+$/) exit 1

  civil_from_days(int(ts / 86400))
  march = last_sunday(year, 3)
  october = last_sunday(year, 10)
  dst_start = days_from_civil(year, 3, march) * 86400 + 3600
  dst_end = days_from_civil(year, 10, october) * 86400 + 3600

  print (ts >= dst_start && ts < dst_end ? 7200 : 3600)
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

epoch_to_berlin_iso() {
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

function days_from_civil(y, m, d, era, yoe, doy, doe, mp) {
  if (m <= 2) y--
  era = floor_div(y, 400)
  yoe = y - era * 400
  mp = m + (m > 2 ? -3 : 9)
  doy = int((153 * mp + 2) / 5) + d - 1
  doe = yoe * 365 + int(yoe / 4) - int(yoe / 100) + doy
  return era * 146097 + doe - 719468
}

function split_civil_from_days(z, era, doe, yoe, y, doy, mp) {
  z += 719468
  era = floor_div(z, 146097)
  doe = z - era * 146097
  yoe = int((doe - int(doe / 1460) + int(doe / 36524) - int(doe / 146096)) / 365)
  y = yoe + era * 400
  doy = doe - (365 * yoe + int(yoe / 4) - int(yoe / 100))
  mp = int((5 * doy + 2) / 153)
  day = doy - int((153 * mp + 2) / 5) + 1
  month = mp + (mp < 10 ? 3 : -9)
  if (month <= 2) y++
  year = y
}

function weekday(y, m, d) {
  return (days_from_civil(y, m, d) + 4) % 7
}

function last_sunday(y, m, day) {
  day = 31
  while (weekday(y, m, day) != 0) day--
  return day
}

function berlin_offset(ts, march, october, dst_start, dst_end) {
  split_civil_from_days(int(ts / 86400))
  march = last_sunday(year, 3)
  october = last_sunday(year, 10)
  dst_start = days_from_civil(year, 3, march) * 86400 + 3600
  dst_end = days_from_civil(year, 10, october) * 86400 + 3600
  return (ts >= dst_start && ts < dst_end ? 7200 : 3600)
}

BEGIN {
  if (ts !~ /^[0-9]+$/) exit 1

  offset = berlin_offset(ts)
  ts += offset
  days = int(ts / 86400)
  seconds = ts - days * 86400
  h = int(seconds / 3600)
  seconds -= h * 3600
  min = int(seconds / 60)
  sec = seconds - min * 60
  sign = "+"
  offset_h = int(offset / 3600)
  offset_m = int((offset - offset_h * 3600) / 60)

  printf "%sT%02d:%02d:%02d%s%02d:%02d\n", civil_from_days(days), h, min, sec, sign, offset_h, offset_m
}'
}

is_date() {
  date_to_epoch "$1" >/dev/null 2>&1
}

date_start_ts() {
  local_ts="$(date_to_epoch "$1")" || return 1
  offset="$(berlin_offset_for_local "$1" 0)" || return 1
  printf '%s\n' $((local_ts - offset))
}

date_end_ts() {
  local_ts="$(date_to_epoch "$1")" || return 1
  offset="$(berlin_offset_for_local "$1" 23)" || return 1
  printf '%s\n' $((local_ts + 86399 - offset))
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

emit_gps_points() {
  from_ts="$1"
  to_ts="$2"

  cat "$LIVE_TRACK" "$LEGACY_TRACK" "$GPS_DIR"/*.csv 2>/dev/null |
    awk -F',' -v from="$from_ts" -v to="$to_ts" '
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

        if (valid_number(ts) && valid_number(lat) && valid_number(lon) && ts >= from && ts <= to) {
          print ts "," lat "," lon
        }
      }
    ' |
    sort -t',' -k1,1n -u
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
  FROM_DAY="$(date_to_days "$from_date")"
  TO_DAY="$(date_to_days "$to_date")"

  if [ "$FROM_TS" -gt "$TO_TS" ]; then
    GPS_ERROR="from must be before or equal to to"
    return 1
  fi

  if [ $((TO_DAY - FROM_DAY + 1)) -gt "$MAX_RANGE_DAYS" ]; then
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
