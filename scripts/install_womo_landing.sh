#!/bin/sh

set -eu

WEB_ROOT="/usr/local/home/www/womo"
CGI_DIR="$WEB_ROOT/cgi-bin"
DATA_DIR="$WEB_ROOT/data"
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
    wget -qO "$target" "$url"
    status "Downloading $label done."
    return
  fi

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$target"
    status "Downloading $label done."
    return
  fi

  fail "Neither curl nor wget is available for downloading Leaflet."
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

  if [ -f "$LEAFLET_MARKER" ] &&
     [ "$(cat "$LEAFLET_MARKER")" = "$LEAFLET_VERSION" ] &&
     [ -f "$LEAFLET_DIR/leaflet.css" ] &&
     [ -f "$LEAFLET_DIR/leaflet.js" ] &&
     [ -f "$LEAFLET_DIR/images/marker-icon.png" ] &&
     [ -f "$LEAFLET_DIR/images/marker-icon-2x.png" ] &&
     [ -f "$LEAFLET_DIR/images/marker-shadow.png" ]; then
    return
  fi

  download_file "$LEAFLET_BASE_URL/leaflet.css" "$LEAFLET_DIR/leaflet.css" "leaflet.css"
  download_file "$LEAFLET_BASE_URL/leaflet.js" "$LEAFLET_DIR/leaflet.js" "leaflet.js"

  for image in marker-icon.png marker-icon-2x.png marker-shadow.png; do
    download_file "$LEAFLET_BASE_URL/images/$image" "$LEAFLET_DIR/images/$image" "$image"
  done

  printf '%s\n' "$LEAFLET_VERSION" > "$LEAFLET_MARKER"
}

install_sync_script() {
  status "Installing GPS track sync script"

  cp "$SYNC_SOURCE" "$SYNC_SCRIPT"
  chmod 755 "$SYNC_SCRIPT"
}

set_permissions() {
  status "Setting executable permissions"

  chmod 755 "$CGI_DIR/gps.json"
  chmod 755 "$CGI_DIR/gps_track.cgi"
  chmod 755 "$SYNC_SCRIPT"
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
need_file "$WEB_SOURCE/map.html"
need_file "$WEB_SOURCE/cgi-bin/gps.json"
need_file "$WEB_SOURCE/cgi-bin/gps_track.cgi"
need_file "$SYNC_SOURCE"

status "Creating target directories"
mkdir -p "$WEB_ROOT" "$CGI_DIR" "$DATA_DIR" "$LEAFLET_DIR" "$(dirname "$SYNC_SCRIPT")" /tmp/womo

install_web_files
install_leaflet
install_sync_script
set_permissions
install_cron
configure_uhttpd

status "WoMo portal installation completed."
status "Open http://<router-ip>:8080/"
