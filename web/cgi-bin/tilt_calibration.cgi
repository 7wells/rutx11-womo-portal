#!/bin/sh

set -eu

DATA_DIR="${WOMO_DATA_DIR:-/usr/local/home/womo-data}"
RUNTIME_DIR="${WOMO_RUNTIME_DIR:-/tmp/womo}"

respond() {
  status="$1"
  body="$2"
  printf 'Status: %s\r\n' "$status"
  printf 'Content-Type: application/json\r\n'
  printf 'Cache-Control: no-store\r\n\r\n'
  printf '%s\n' "$body"
}

calibration_file() {
  case "${QUERY_STRING:-}" in
    demo=1|demo=1\&*) printf '%s/tilt_calibration_demo.json\n' "$DATA_DIR" ;;
    *) printf '%s/tilt_calibration.json\n' "$DATA_DIR" ;;
  esac
}

valid_value() {
  awk -v value="$1" 'BEGIN {
    if (value == "null") exit 0
    if (value !~ /^-?[0-9]+([.][0-9]+)?$/) exit 1
    number = value + 0
    exit !(number >= -90 && number <= 90)
  }'
}

file="$(calibration_file)"

case "${REQUEST_METHOD:-GET}" in
  GET)
    if [ -f "$file" ]; then
      respond "200 OK" "$(cat "$file")"
    else
      respond "200 OK" '{"longitudinal":null,"transverse":null}'
    fi
    ;;
  POST)
    length="${CONTENT_LENGTH:-0}"
    case "$length" in
      ''|*[!0-9]*) respond "400 Bad Request" '{"error":"invalid content length"}'; exit 0 ;;
    esac
    [ "$length" -le 256 ] || { respond "413 Payload Too Large" '{"error":"payload too large"}'; exit 0; }

    body="$(dd bs=1 count="$length" 2>/dev/null)"
    longitudinal="$(printf '%s' "$body" | tr '&' '\n' | sed -n 's/^longitudinal=//p' | head -n 1)"
    transverse="$(printf '%s' "$body" | tr '&' '\n' | sed -n 's/^transverse=//p' | head -n 1)"

    valid_value "$longitudinal" && valid_value "$transverse" || {
      respond "400 Bad Request" '{"error":"invalid calibration values"}'
      exit 0
    }

    mkdir -p "$DATA_DIR" "$RUNTIME_DIR"
    temporary="$DATA_DIR/.tilt_calibration.$$"
    trap 'rm -f "$temporary"' EXIT HUP INT TERM
    umask 077
    printf '{"longitudinal":%s,"transverse":%s}\n' "$longitudinal" "$transverse" > "$temporary"
    mv "$temporary" "$file"
    trap - EXIT HUP INT TERM
    respond "200 OK" "$(cat "$file")"
    ;;
  *)
    respond "405 Method Not Allowed" '{"error":"method not allowed"}'
    ;;
esac
