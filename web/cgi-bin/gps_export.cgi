#!/bin/sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/gps_lib.sh"

QUERY="${QUERY_STRING:-}"

get_query_value() {
  key="$1"

  printf '%s' "$QUERY" \
    | tr '&' '\n' \
    | awk -F'=' -v key="$key" '$1 == key { print $2; exit }'
}

FROM_DATE="$(get_query_value from)"
TO_DATE="$(get_query_value to)"
FORMAT="$(get_query_value format)"

if ! validate_date_range "$FROM_DATE" "$TO_DATE"; then
  send_json_error "400 Bad Request" "$GPS_ERROR"
  exit 0
fi

case "$FORMAT" in
  csv|gpx)
    ;;
  *)
    send_json_error "400 Bad Request" "format must be csv or gpx"
    exit 0
    ;;
esac

ensure_gps_dirs

emit_points() {
  cat "$LIVE_TRACK" "$LEGACY_TRACK" "$GPS_DIR"/*.csv 2>/dev/null |
    awk -F',' -v from="$FROM_TS" -v to="$TO_TS" '
      function valid_number(value) {
        return value ~ /^-?[0-9]+(\.[0-9]+)?$/
      }

      NF == 3 && valid_number($1) && valid_number($2) && valid_number($3) && $1 >= from && $1 <= to
    ' |
    sort -t',' -k1,1n -u
}

if [ "$FORMAT" = "csv" ]; then
  printf 'Content-Type: text/csv\r\n'
  printf 'Content-Disposition: attachment; filename="womo-gps-%s_%s.csv"\r\n\r\n' "$FROM_DATE" "$TO_DATE"
  printf 'timestamp,datetime,latitude,longitude\n'

  emit_points |
    while IFS=',' read -r TS LAT LON
    do
      TIME="$(epoch_to_gpx_utc "$TS" 2>/dev/null || true)"
      printf '%s,%s,%s,%s\n' "$TS" "$TIME" "$LAT" "$LON"
    done

  exit 0
fi

printf 'Content-Type: application/gpx+xml\r\n'
printf 'Content-Disposition: attachment; filename="womo-gps-%s_%s.gpx"\r\n\r\n' "$FROM_DATE" "$TO_DATE"
printf '%s\n' '<?xml version="1.0" encoding="UTF-8"?>'
printf '%s\n' '<gpx version="1.1" creator="RUTX11 WoMo Portal" xmlns="http://www.topografix.com/GPX/1/1">'
printf '%s\n' '  <trk>'
printf '    <name>WoMo GPS %s to %s</name>\n' "$FROM_DATE" "$TO_DATE"
printf '%s\n' '    <trkseg>'

emit_points |
  while IFS=',' read -r TS LAT LON
  do
    TIME="$(epoch_to_gpx_utc "$TS" 2>/dev/null || true)"

    printf '      <trkpt lat="%s" lon="%s">' "$LAT" "$LON"
    if [ -n "$TIME" ]; then
      printf '<time>%s</time>' "$TIME"
    fi
    printf '</trkpt>\n'
  done

printf '%s\n' '    </trkseg>'
printf '%s\n' '  </trk>'
printf '%s\n' '</gpx>'
