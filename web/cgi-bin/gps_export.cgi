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

FROM_TS="$(date_start_ts "$FROM_DATE")" || {
  send_json_error "400 Bad Request" "from and to must use YYYY-MM-DD"
  exit 0
}

TO_TS="$(date_end_ts "$TO_DATE")" || {
  send_json_error "400 Bad Request" "from and to must use YYYY-MM-DD"
  exit 0
}

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
  emit_gps_points "$FROM_TS" "$TO_TS"
}

if [ "$FORMAT" = "csv" ]; then
  printf 'Content-Type: text/csv\r\n'
  printf 'Content-Disposition: attachment; filename="womo-gps-%s_%s.csv"\r\n\r\n' "$FROM_DATE" "$TO_DATE"
  printf 'timestamp,datetime,latitude,longitude\n'

  emit_points |
    while IFS=',' read -r TS LAT LON
    do
      TIME="$(epoch_to_berlin_iso "$TS" 2>/dev/null || true)"
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
    TIME="$(epoch_to_berlin_iso "$TS" 2>/dev/null || true)"

    printf '      <trkpt lat="%s" lon="%s">' "$LAT" "$LON"
    if [ -n "$TIME" ]; then
      printf '<time>%s</time>' "$TIME"
    fi
    printf '</trkpt>\n'
  done

printf '%s\n' '    </trkseg>'
printf '%s\n' '  </trk>'
printf '%s\n' '</gpx>'
