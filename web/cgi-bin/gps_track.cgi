#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/gps_lib.sh"

MIN_DISTANCE=20

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
CURRENT_MONTH="$(date +%Y-%m)"
CURRENT_MONTH_TRACK="$GPS_DIR/$CURRENT_MONTH.csv"

ensure_gps_dirs

touch "$LIVE_TRACK"
touch "$CURRENT_MONTH_TRACK"

record_current_gps() {
  LAT="$(gpsctl -i 2>/dev/null || true)"
  LON="$(gpsctl -x 2>/dev/null || true)"
  HAVE_FIX=1

  if [ -z "$LAT" ] || [ -z "$LON" ]; then
    HAVE_FIX=0
  fi

  if ! is_number "$LAT" || ! is_number "$LON"; then
    HAVE_FIX=0
  fi

  [ "$HAVE_FIX" = "1" ] || return 0

  LAST_LINE="$(tail -n 1 "$LIVE_TRACK" 2>/dev/null || true)"

  LAST_LAT="$(echo "$LAST_LINE" | awk -F',' '{print $2}')"
  LAST_LON="$(echo "$LAST_LINE" | awk -F',' '{print $3}')"

  ADD_POINT=1

  # Avoid writing near-duplicate points while the vehicle is stationary.
  if [ -n "$LAST_LAT" ] && [ -n "$LAST_LON" ]; then

    if is_number "$LAST_LAT" && is_number "$LAST_LON"; then
      DISTANCE="$(awk \
        -v lat1="$LAT" \
        -v lon1="$LON" \
        -v lat2="$LAST_LAT" \
        -v lon2="$LAST_LON" '
BEGIN {
  dlat=(lat1-lat2)*111320;
  dlon=(lon1-lon2)*111320*cos(lat1/57.29578);
  dist=sqrt(dlat*dlat + dlon*dlon);
  print dist;
}')"

      DISTANCE_INT="${DISTANCE%.*}"

      if [ "$DISTANCE_INT" -lt "$MIN_DISTANCE" ]; then
        ADD_POINT=0
      fi
    fi
  fi

  if [ "$ADD_POINT" = "1" ]; then
    echo "${NOW},${LAT},${LON}" >> "$LIVE_TRACK"
    echo "${NOW},${LAT},${LON}" >> "$CURRENT_MONTH_TRACK"
  fi
}

ONE_HOUR_AGO=$((NOW - 3600))

trim_live_track() {
  TMP_FILE="$TMP_DIR/live.tmp"

  # Keep live storage small; longer history is served from persistent storage.
  awk -F',' -v limit="$ONE_HOUR_AGO" '
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

  if (valid_number(ts) && valid_number(lat) && valid_number(lon) && ts >= limit) {
    print ts "," lat "," lon
  }
}
' "$LIVE_TRACK" > "$TMP_FILE"

  mv "$TMP_FILE" "$LIVE_TRACK"
}

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

record_current_gps >/dev/null 2>&1 || true
trim_live_track >/dev/null 2>&1 || true
