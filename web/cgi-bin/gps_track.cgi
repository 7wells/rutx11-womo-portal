#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/gps_lib.sh"

QUERY="${QUERY_STRING:-}"

RANGE="1h"
FROM_DATE=""
TO_DATE=""
USE_CUSTOM_RANGE=0

get_query_value() {
  key="$1"

  printf '%s' "$QUERY" \
    | tr '&' '\n' \
    | awk -F'=' -v key="$key" '$1 == key { print $2; exit }'
}

# The frontend selects how much track history should be returned.
case "$QUERY" in
  *range=24h*)
    RANGE="24h"
    ;;
  *range=4w*)
    RANGE="4w"
    ;;
esac

FROM_DATE="$(get_query_value from)"
TO_DATE="$(get_query_value to)"

if [ -n "$FROM_DATE" ] || [ -n "$TO_DATE" ]; then
  USE_CUSTOM_RANGE=1

  if ! validate_date_range "$FROM_DATE" "$TO_DATE"; then
    send_json_error "400 Bad Request" "$GPS_ERROR"
    exit 0
  fi

  FROM_TS="$(date_start_ts "$FROM_DATE")" || {
    send_json_error "400 Bad Request" "from and to must use YYYY-MM-DD"
    exit 0
  }

  TO_TS="$(date_end_ts "$TO_DATE")" || {
    send_json_error "400 Bad Request" "from and to must use YYYY-MM-DD"
    exit 0
  }
fi

NOW="$(date +%s)"
ONE_HOUR_AGO=$((NOW - 3600))

case "$RANGE" in

  1h)
    LIMIT_TS="$ONE_HOUR_AGO"
    ;;

  24h)
    LIMIT_TS=$((NOW - 86400))
    ;;

  4w)
    LIMIT_TS=$((NOW - 2419200))
    ;;

esac

if [ "$USE_CUSTOM_RANGE" = "1" ]; then
  LIMIT_TS="$FROM_TS"
  END_TS="$TO_TS"
else
  END_TS="$NOW"
fi

printf 'Content-Type: application/json\r\n\r\n'

# Stream JSON manually to stay compatible with BusyBox ash.
printf '['

FIRST=1

emit_gps_points "$LIMIT_TS" "$END_TS" |

while IFS=',' read -r TS LAT_V LON_V
do

  [ -z "$TS" ] && continue

  if [ "$FIRST" = "0" ]; then
    printf ','
  fi

  FIRST=0

  printf '{"ts":%s,"lat":%s,"lon":%s}' \
    "$TS" \
    "$LAT_V" \
    "$LON_V"

done

printf ']\n'
