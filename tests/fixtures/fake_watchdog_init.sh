#!/bin/sh

# Mimic a RutOS init script and record every requested action for assertions.
service_name="${0##*/}"
action="${1:-}"

printf '%s %s\n' "$service_name" "$action" >> "${WOMO_FAKE_ACTION_LOG:?}"

if [ "$action" = "status" ] && [ "$service_name" = "${WOMO_FAKE_FAILED_SERVICE:-}" ]; then
  exit 1
fi

exit 0
