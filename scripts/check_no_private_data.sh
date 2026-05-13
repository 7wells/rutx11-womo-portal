#!/bin/sh

set -eu

failures=0

# Guard public releases against accidentally tracked GPS/runtime files.
fail() {
  echo "ERROR: $*" >&2
  failures=$((failures + 1))
}

check_tracked_path() {
  pattern="$1"
  message="$2"

  if git ls-files | grep -Eq "$pattern"; then
    fail "$message"
    git ls-files | grep -E "$pattern" >&2 || true
  fi
}

check_tracked_path '^web/data(/|$)' "Runtime data must not be tracked."
check_tracked_path '(^|/)gps_track[^/]*\.log$' "GPS track logs must not be tracked."
check_tracked_path '\.(gpx|kml)$' "GPS export files must not be tracked."

if [ "$failures" -ne 0 ]; then
  echo "Private data check failed." >&2
  exit 1
fi

echo "OK: no tracked private GPS/runtime data found."
