#!/bin/sh

LIVE_TRACK="/tmp/womo/gps_track_live.log"
PERSISTENT_TRACK="/usr/local/home/root/womo-data/gps_track.log"

MIN_DISTANCE=20

QUERY="${QUERY_STRING:-}"

RANGE="1h"

is_number() {
  awk -v value="$1" 'BEGIN { exit(value ~ /^-?[0-9]+(\.[0-9]+)?$/ ? 0 : 1) }'
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

LAT="$(gpsctl -i 2>/dev/null || true)"
LON="$(gpsctl -x 2>/dev/null || true)"

if [ -z "$LAT" ] || [ -z "$LON" ]; then
  printf 'Content-Type: application/json\r\n\r\n[]\n'
  exit 0
fi

if ! is_number "$LAT" || ! is_number "$LON"; then
  printf 'Content-Type: application/json\r\n\r\n[]\n'
  exit 0
fi

NOW="$(date +%s)"

mkdir -p /tmp/womo
mkdir -p /usr/local/home/root/womo-data

touch "$LIVE_TRACK"
touch "$PERSISTENT_TRACK"

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
  echo "${NOW},${LAT},${LON}" >> "$PERSISTENT_TRACK"
fi

ONE_HOUR_AGO=$((NOW - 3600))

TMP_FILE="/tmp/womo/live.tmp"

# Keep live storage small; longer history is served from persistent storage.
awk -F',' -v limit="$ONE_HOUR_AGO" '
function valid_number(value) {
  return value ~ /^-?[0-9]+(\.[0-9]+)?$/
}

NF == 3 && valid_number($1) && valid_number($2) && valid_number($3) && $1 >= limit
' "$LIVE_TRACK" > "$TMP_FILE"

mv "$TMP_FILE" "$LIVE_TRACK"

case "$RANGE" in

  1h)
    SOURCE_FILE="$LIVE_TRACK"
    LIMIT_TS="$ONE_HOUR_AGO"
    ;;

  24h)
    SOURCE_FILE="$PERSISTENT_TRACK"
    LIMIT_TS=$((NOW - 86400))
    ;;

  4w)
    SOURCE_FILE="$PERSISTENT_TRACK"
    LIMIT_TS=$((NOW - 2419200))
    ;;

esac

printf 'Content-Type: application/json\r\n\r\n'

# Stream JSON manually to stay compatible with BusyBox ash.
printf '['

FIRST=1

awk -F',' -v limit="$LIMIT_TS" '
function valid_number(value) {
  return value ~ /^-?[0-9]+(\.[0-9]+)?$/
}

NF == 3 && valid_number($1) && valid_number($2) && valid_number($3) && $1 >= limit
' "$SOURCE_FILE" |

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
