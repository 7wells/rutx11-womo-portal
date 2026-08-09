#!/bin/sh

set -eu

CONFIG_FILE=""
URL=""

# Capture the protected curl config and requested ESP32 URL.
while [ "$#" -gt 0 ]; do
  case "$1" in
    --config)
      shift
      CONFIG_FILE="${1:-}"
      ;;
    http://*|https://*)
      URL="$1"
      ;;
  esac
  shift
done

[ -r "$CONFIG_FILE" ] || exit 1
[ -n "$URL" ] || exit 1
grep -Fxq 'anyauth' "$CONFIG_FILE" || exit 22
grep -Fxq "user = \"user:${WOMO_FAKE_CURL_PASSWORD:-TEST_ONLY}\"" "$CONFIG_FILE" || exit 22
[ -z "${WOMO_FAKE_TILT_CURL_LOG:-}" ] || printf '%s\n' "$URL" >> "$WOMO_FAKE_TILT_CURL_LOG"

case "$URL" in
  */sensor/pitch)
    [ "${WOMO_FAKE_TILT_FAILURE:-}" != "pitch" ] || exit 22
    printf '%s\n' "${WOMO_FAKE_PITCH_JSON:-{\"value\":1.25}}"
    ;;
  */sensor/roll)
    [ "${WOMO_FAKE_TILT_FAILURE:-}" != "roll" ] || exit 22
    printf '%s\n' "${WOMO_FAKE_ROLL_JSON:-{\"value\":-2.5}}"
    ;;
  *)
    exit 22
    ;;
esac
