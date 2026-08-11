#!/bin/sh

# Return predictable portal responses or simulate a local HTTP failure.
url="$1"
target="$2"

case "${WOMO_FAKE_FETCH_MODE:-healthy}" in
  fail)
    exit 1
    ;;
  fail-backend)
    case "$url" in
      *gps.json)
        exit 1
        ;;
    esac
    ;;
esac

case "$url" in
  *gps.json)
    printf '{"historyAvailable":false}\n' > "$target"
    ;;
  *)
    printf '<!doctype html><title>WoMo Karte</title>\n' > "$target"
    ;;
esac
