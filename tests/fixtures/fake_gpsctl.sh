#!/bin/sh

set -eu

STATE_FILE="${WOMO_FAKE_GPS_STATE:?WOMO_FAKE_GPS_STATE is required}"
index="$(cat "$STATE_FILE" 2>/dev/null || printf '0')"

# Return a deterministic route and advance only after longitude was requested.
case "$index" in
  0)
    lat="52.000000"
    lon="13.000000"
    ;;
  1)
    lat="52.000000"
    lon="13.000000"
    ;;
  2)
    lat="52.000300"
    lon="13.000000"
    ;;
  *)
    lat="52.000600"
    lon="13.000000"
    ;;
esac

case "${1:-}" in
  -i)
    printf '%s\n' "$lat"
    ;;
  -x)
    printf '%s\n' "$lon"
    printf '%s\n' $((index + 1)) > "$STATE_FILE"
    ;;
  *)
    exit 1
    ;;
esac
