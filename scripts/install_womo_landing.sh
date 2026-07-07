#!/bin/sh

set -eu

WEB_ROOT="/usr/local/home/www/womo"
CGI_DIR="$WEB_ROOT/cgi-bin"
PERSISTENT_DATA_DIR="/usr/local/home/womo-data"
LEGACY_PERSISTENT_DATA_DIR="/usr/local/home/root/womo-data"
GPS_DATA_DIR="$PERSISTENT_DATA_DIR/gps"
CGI_USER="uhttpd"
CGI_GROUP="uhttpd"
LEAFLET_DIR="$WEB_ROOT/assets/leaflet"
LEAFLET_MARKER="$LEAFLET_DIR/.leaflet-version"
SYNC_SCRIPT="/usr/local/bin/sync_womo_gps_track.sh"
CRON_FILE="/etc/crontabs/root"
CRON_ENTRY="0 * * * * $SYNC_SCRIPT"
LEAFLET_VERSION="1.9.4"
LEAFLET_BASE_URL="https://unpkg.com/leaflet@$LEAFLET_VERSION/dist"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
WEB_SOURCE="$REPO_ROOT/web"
LEAFLET_SOURCE="$WEB_SOURCE/assets/leaflet"
SYNC_SOURCE="$REPO_ROOT/scripts/sync_womo_gps_track.sh"

status() {
  echo "==> $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

need_file() {
  [ -f "$1" ] || fail "Required file missing: $1"
}

download_file() {
  url="$1"
  target="$2"
  label="$3"

  status "Downloading $label ..."

  if command -v wget >/dev/null 2>&1; then
    wget -qO "$target" "$url" || fail "Failed to download $label from $url."
    status "Downloading $label done."
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$target" || fail "Failed to download $label from $url."
    status "Downloading $label done."
    return
  fi

  fail "Neither curl nor wget is available for downloading Leaflet."
}

leaflet_assets_present() {
  base="$1"

  [ -f "$base/leaflet.css" ] &&
    [ -f "$base/leaflet.js" ] &&
    [ -f "$base/images/marker-icon.png" ] &&
    [ -f "$base/images/marker-icon-2x.png" ] &&
    [ -f "$base/images/marker-shadow.png" ]
}

install_web_files() {
  status "Installing web files to $WEB_ROOT"

  cd "$WEB_SOURCE"

  find . -mindepth 1 -type d | while IFS= read -r dir; do
    case "$dir" in
      ./data|./data/*)
        continue
        ;;
    esac

    mkdir -p "$WEB_ROOT/${dir#./}"
  done

  find . -type f | while IFS= read -r file; do
    case "$file" in
      ./data/*)
        continue
        ;;
    esac

    target="$WEB_ROOT/${file#./}"
    mkdir -p "$(dirname "$target")"
    cp "$file" "$target"
  done
}

install_leaflet() {
  status "Ensuring Leaflet $LEAFLET_VERSION assets"

  mkdir -p "$LEAFLET_DIR/images"

  if leaflet_assets_present "$LEAFLET_DIR"; then
    printf '%s\n' "$LEAFLET_VERSION" > "$LEAFLET_MARKER"
    return
  fi

  if leaflet_assets_present "$LEAFLET_SOURCE"; then
    cp "$LEAFLET_SOURCE/leaflet.css" "$LEAFLET_DIR/leaflet.css"
    cp "$LEAFLET_SOURCE/leaflet.js" "$LEAFLET_DIR/leaflet.js"
    cp "$LEAFLET_SOURCE/images/marker-icon.png" "$LEAFLET_DIR/images/marker-icon.png"
    cp "$LEAFLET_SOURCE/images/marker-icon-2x.png" "$LEAFLET_DIR/images/marker-icon-2x.png"
    cp "$LEAFLET_SOURCE/images/marker-shadow.png" "$LEAFLET_DIR/images/marker-shadow.png"
  else
    status "Local Leaflet assets are incomplete; using download fallback."

    download_file "$LEAFLET_BASE_URL/leaflet.css" "$LEAFLET_DIR/leaflet.css" "leaflet.css"
    download_file "$LEAFLET_BASE_URL/leaflet.js" "$LEAFLET_DIR/leaflet.js" "leaflet.js"

    for image in marker-icon.png marker-icon-2x.png marker-shadow.png; do
      download_file "$LEAFLET_BASE_URL/images/$image" "$LEAFLET_DIR/images/$image" "$image"
    done
  fi

  leaflet_assets_present "$LEAFLET_DIR" || fail "Leaflet assets are incomplete after install."

  printf '%s\n' "$LEAFLET_VERSION" > "$LEAFLET_MARKER"
}

install_sync_script() {
  status "Installing GPS track sync script"

  cp "$SYNC_SOURCE" "$SYNC_SCRIPT"
  chmod 755 "$SYNC_SCRIPT"
}

migrate_legacy_data() {
  status "Migrating legacy GPS data if needed"

  [ -d "$LEGACY_PERSISTENT_DATA_DIR" ] || return 0

  if [ -f "$LEGACY_PERSISTENT_DATA_DIR/gps_track.log" ] && [ ! -f "$PERSISTENT_DATA_DIR/gps_track.log" ]; then
    cp "$LEGACY_PERSISTENT_DATA_DIR/gps_track.log" "$PERSISTENT_DATA_DIR/gps_track.log"
  fi

  if [ -d "$LEGACY_PERSISTENT_DATA_DIR/gps" ]; then
    find "$LEGACY_PERSISTENT_DATA_DIR/gps" -type f -name '*.csv' | while IFS= read -r file; do
      target="$GPS_DATA_DIR/$(basename "$file")"

      if [ -f "$target" ]; then
        cat "$file" >> "$target"
      else
        cp "$file" "$target"
      fi
    done
  fi
}

set_permissions() {
  status "Setting executable permissions"

  chmod 755 "$CGI_DIR/gps.json"
  chmod 755 "$CGI_DIR/gps_export.cgi"
  chmod 755 "$CGI_DIR/gps_track.cgi"
  chmod 755 "$CGI_DIR/tilt_calibration.cgi"
  chmod 644 "$CGI_DIR/gps_lib.sh"
  chmod 755 "$SYNC_SCRIPT"
  chmod 755 "$PERSISTENT_DATA_DIR"
  chmod 755 "$GPS_DATA_DIR"
  find "$GPS_DATA_DIR" -type f -name '*.csv' -exec chmod 644 {} \; 2>/dev/null || true
  [ ! -f "$PERSISTENT_DATA_DIR/gps_track.log" ] || chmod 644 "$PERSISTENT_DATA_DIR/gps_track.log"

  if grep -q "^$CGI_USER:" /etc/passwd 2>/dev/null; then
    if grep -q "^$CGI_GROUP:" /etc/group 2>/dev/null; then
      chown -R "$CGI_USER:$CGI_GROUP" "$PERSISTENT_DATA_DIR"
    else
      chown -R "$CGI_USER" "$PERSISTENT_DATA_DIR"
    fi
  fi
}

install_cron() {
  status "Ensuring hourly GPS sync cron job"

  mkdir -p "$(dirname "$CRON_FILE")"
  touch "$CRON_FILE"

  if ! grep -Fqx "$CRON_ENTRY" "$CRON_FILE"; then
    printf '%s\n' "$CRON_ENTRY" >> "$CRON_FILE"
  fi

  /etc/init.d/cron reload >/dev/null 2>&1 || /etc/init.d/cron restart >/dev/null 2>&1 || true
}

configure_uhttpd() {
  status "Configuring uhttpd.womo on port 8080"

  command -v uci >/dev/null 2>&1 || fail "uci command not found."

  uci -q delete uhttpd.womo || true
  uci set uhttpd.womo="uhttpd"
  uci add_list uhttpd.womo.listen_http="0.0.0.0:8080"
  uci set uhttpd.womo.home="$WEB_ROOT"
  uci set uhttpd.womo.cgi_prefix="/cgi-bin"
  uci commit uhttpd

  status "Reloading uhttpd"
  /etc/init.d/uhttpd reload >/dev/null 2>&1 || /etc/init.d/uhttpd restart
}

need_file "$WEB_SOURCE/index.html"
need_file "$WEB_SOURCE/portal-config.js"
need_file "$WEB_SOURCE/tilt.html"
need_file "$WEB_SOURCE/tilt-config.js"
need_file "$WEB_SOURCE/cgi-bin/gps.json"
need_file "$WEB_SOURCE/cgi-bin/gps_export.cgi"
need_file "$WEB_SOURCE/cgi-bin/gps_lib.sh"
need_file "$WEB_SOURCE/cgi-bin/gps_track.cgi"
need_file "$WEB_SOURCE/cgi-bin/tilt_calibration.cgi"
need_file "$SYNC_SOURCE"

status "Creating target directories"
mkdir -p "$WEB_ROOT" "$CGI_DIR" "$PERSISTENT_DATA_DIR" "$GPS_DATA_DIR" "$LEAFLET_DIR" "$(dirname "$SYNC_SCRIPT")" /tmp/womo

install_web_files
migrate_legacy_data
install_leaflet
install_sync_script
"$SYNC_SCRIPT" >/dev/null 2>&1 || true
set_permissions
install_cron
configure_uhttpd

status "WoMo portal installation completed."
status "Open http://<router-ip>:8080/"
