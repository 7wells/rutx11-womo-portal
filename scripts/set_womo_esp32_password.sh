#!/bin/sh

set -eu

DATA_DIR="${WOMO_DATA_DIR:-/usr/local/home/womo-data}"
PASSWORD_FILE="${WOMO_ESP32_PASSWORD_FILE:-$DATA_DIR/esp32-main.password}"
LEGACY_CREDENTIALS_FILE="$DATA_DIR/esp32-main.curl.conf"
CGI_USER="${WOMO_CGI_USER:-uhttpd}"
CGI_GROUP="${WOMO_CGI_GROUP:-uhttpd}"
PASSWORD="${WOMO_ESP32_PASSWORD:-}"
TTY_STATE=""
TEMPORARY=""

# Stop without printing any credential content.
fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# Restore terminal echo and remove the password from this process on every exit.
cleanup() {
  if [ -n "$TTY_STATE" ]; then
    stty "$TTY_STATE" 2>/dev/null || true
    printf '\n' >&2
  fi
  [ -z "$TEMPORARY" ] || rm -f "$TEMPORARY"
  PASSWORD=""
}

# Read the password without echo when it was not supplied through the environment.
read_password() {
  [ -z "$PASSWORD" ] || return 0
  [ -t 0 ] || fail "Set WOMO_ESP32_PASSWORD or run this command in an interactive terminal."

  TTY_STATE="$(stty -g)" || fail "Could not disable terminal echo."
  printf 'ESP32 Main password: ' >&2
  stty -echo
  IFS= read -r PASSWORD || fail "Could not read the password."
  stty "$TTY_STATE"
  TTY_STATE=""
  printf '\n' >&2
}

# Write the password outside the web root with owner-only permissions.
store_password() {
  line_feed='
'
  carriage_return="$(printf '\r')"
  case "$PASSWORD" in
    *"$line_feed"*|*"$carriage_return"*) fail "The password must not contain line breaks." ;;
  esac
  [ -n "$PASSWORD" ] || fail "The password must not be empty."

  mkdir -p "$DATA_DIR"
  umask 077
  TEMPORARY="$PASSWORD_FILE.tmp.$$"
  printf '%s' "$PASSWORD" > "$TEMPORARY"

  chmod 600 "$TEMPORARY"
  if grep -q "^$CGI_USER:" /etc/passwd 2>/dev/null; then
    if grep -q "^$CGI_GROUP:" /etc/group 2>/dev/null; then
      chown "$CGI_USER:$CGI_GROUP" "$TEMPORARY"
    else
      chown "$CGI_USER" "$TEMPORARY"
    fi
  fi
  mv -f "$TEMPORARY" "$PASSWORD_FILE"
  TEMPORARY=""

  # Remove the superseded curl config only after the new password file is safe.
  rm -f "$LEGACY_CREDENTIALS_FILE"
}

trap cleanup 0
trap 'exit 1' 1 2 15

read_password
store_password
echo "ESP32 Main credentials saved outside the portal web root."
