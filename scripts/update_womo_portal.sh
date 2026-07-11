#!/bin/sh

set -eu

REPOSITORY="${WOMO_PORTAL_REPOSITORY:-7wells/rutx11-womo-portal}"
REF="${WOMO_PORTAL_REF:-main}"
DEFAULT_ARCHIVE_URL="https://github.com/$REPOSITORY/archive/refs/heads/$REF.tar.gz"
ARCHIVE_URL="${WOMO_PORTAL_ARCHIVE_URL:-$DEFAULT_ARCHIVE_URL}"
WEB_ROOT="${WOMO_PORTAL_WEB_ROOT:-/usr/local/home/www/womo}"
PORTAL_CONFIG="$WEB_ROOT/portal-config.js"
WORK_DIR=""
CONFIG_BACKUP=""
CONFIG_SAVED=0

# Print a short progress message for interactive router updates.
status() {
  echo "==> $*"
}

# Stop the update with a readable error message.
fail() {
  echo "ERROR: $*" >&2
  exit 1
}

# Restore the local device configuration after installing repository defaults.
restore_portal_config() {
  [ "$CONFIG_SAVED" -eq 1 ] || return 0

  cp "$CONFIG_BACKUP" "$PORTAL_CONFIG"
  chmod 644 "$PORTAL_CONFIG"
  CONFIG_SAVED=0
  status "Restored local portal configuration"
}

# Restore configuration after errors and remove all temporary update files.
cleanup() {
  result=$?
  trap - 0

  if [ "$CONFIG_SAVED" -eq 1 ] && [ -f "$CONFIG_BACKUP" ]; then
    if cp "$CONFIG_BACKUP" "$PORTAL_CONFIG"; then
      chmod 644 "$PORTAL_CONFIG" || true
      status "Restored local portal configuration after interrupted update"
    else
      echo "ERROR: Failed to restore $PORTAL_CONFIG" >&2
      result=1
    fi
  fi

  [ -z "$WORK_DIR" ] || rm -rf "$WORK_DIR"
  exit "$result"
}

# Download a file using the tools commonly available on RutOS.
download_file() {
  url="$1"
  target="$2"

  if command -v wget >/dev/null 2>&1; then
    if wget -O "$target" "$url"; then
      return
    fi
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL "$url" -o "$target"; then
      return
    fi
  fi

  fail "Download failed: $url"
}

trap cleanup 0
trap 'exit 1' 1 2 15

WORK_DIR="$(mktemp -d /tmp/womo-portal-update.XXXXXX)" || fail "Could not create temporary directory."
ARCHIVE="$WORK_DIR/womo-portal.tar.gz"
CONFIG_BACKUP="$WORK_DIR/portal-config.js"

if [ -f "$PORTAL_CONFIG" ]; then
  cp "$PORTAL_CONFIG" "$CONFIG_BACKUP"
  CONFIG_SAVED=1
  status "Saved local portal configuration"
fi

status "Downloading $REPOSITORY ($REF)"
download_file "$ARCHIVE_URL" "$ARCHIVE"

# GitHub archives contain one top-level directory whose name includes the ref.
ARCHIVE_ROOT="$(tar -tzf "$ARCHIVE" | sed -n '1s#/.*##p')"
case "$ARCHIVE_ROOT" in
  ""|.|..|*/*)
    fail "Downloaded archive has an unexpected directory structure."
    ;;
esac

status "Extracting portal update"
tar -xzf "$ARCHIVE" -C "$WORK_DIR"
INSTALLER="$WORK_DIR/$ARCHIVE_ROOT/scripts/install_womo_landing.sh"
[ -f "$INSTALLER" ] || fail "Installer missing from downloaded archive."

status "Installing portal update"
sh "$INSTALLER"
restore_portal_config

status "WoMo portal update completed."
