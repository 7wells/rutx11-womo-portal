# RUTX11 WoMo Portal

Standalone local web portal for a Teltonika RUTX11 router.

Use at your own risk. This project is provided as-is and without warranty.

## TL;DR

This project installs a small local camper portal on a compatible Teltonika
RUTX11 router. It shows a mobile-friendly GPS map, GPS history/export tools,
and a local tilt/level page for an ESP32-based vehicle sensor.

If your local device addresses differ, edit `web/portal-config.js` before
running the installer. See [Local device URLs](#local-device-urls).

The first deployment copies this repository to the router and runs one
installer script. After that, future updates need only the command
`womo-portal-update`. See [Deploy on the RUTX11](#deploy-on-the-rutx11).

The installer is designed to keep existing GPS track data under
`/usr/local/home/womo-data`. As with any router maintenance, keep a backup if
the existing data matters to you.

Open the portal after deployment:

- http://ROUTER_IP:8080/

Use the router address that is reachable from your device. For example, this
may be a LAN address such as `192.168.11.1` or a VPN address if you access the
router through a tunnel.

## Details

### Features

- Mobile-friendly map landing page
- OpenStreetMap live GPS map
- GPS tracking UI (Live / 24h / 4w)
- Date range selection and CSV/GPX export
- Local tilt/level page with demo fallback
- Local Leaflet asset caching
- No cloud dependency
- Lightweight CGI backend
- Flash-friendly GPS persistence design

### Project structure

- web/
  - HTML frontend
  - CGI scripts
  - cached Leaflet assets
- web/tilt-config.js
  - vehicle geometry and sensor axis mapping for the tilt page
- web/portal-config.js
  - local device URLs for navigation buttons and ESP32 Main access
- scripts/
  - installation script
  - one-command portal updater
  - GPS track sync script
  - private data safety check

### Local device URLs

- Edit `web/portal-config.js` before deployment if your RUTX11, ESP32 Main, or
  Truma/Smartavan use different local URLs.
- The file configures only links to local devices, not the portal URL itself.
- Open the portal through whichever router address is reachable from your
  device, for example a LAN address or a VPN address.
- The default values match one common local setup, but they may need adjustment
  for your network.

### Deploy on the RUTX11

```sh
cd /tmp
wget -O womo.tar.gz "https://github.com/7wells/rutx11-womo-portal/archive/refs/heads/main.tar.gz"
tar -xzf womo.tar.gz
cd rutx11-womo-portal-main
# Optional: edit web/portal-config.js if your device URLs differ.
sh scripts/install_womo_landing.sh
```

After the first successful deployment, install future versions with:

```sh
womo-portal-update
```

The update command keeps the currently installed `portal-config.js`, so local
device URLs are not replaced by repository defaults.

### Deployment notes

- The installer recreates `/usr/local/home/www/womo`, installs the web files,
  enables the CGI scripts, prepares `/usr/local/home/womo-data`, and
  configures uhttpd on port 8080. It also installs the persistent
  `womo-portal-update` command under `/usr/local/bin`.
- Use the full deployment procedure for first setup or after a factory reset.
  Use `womo-portal-update` for normal updates.
- The update command preserves the installed `portal-config.js`. GPS history
  and tilt calibration already remain outside the web root and are not
  replaced by an update.
- Existing GPS history in `/usr/local/home/root/womo-data/gps_track.log` is not
  overwritten by the installer and is migrated into monthly files by the sync
  script.
- Existing monthly GPS files in `/usr/local/home/root/womo-data/gps` are copied
  to `/usr/local/home/womo-data/gps` during installation. Legacy files are not
  deleted automatically.

### Runtime data

- live GPS track:
  /tmp/womo/gps_track_live.log

- persistent GPS track:
  /usr/local/home/womo-data/gps_track.log

- persistent tilt calibration:
  /usr/local/home/womo-data/tilt_calibration.json

- monthly GPS track files:
  /usr/local/home/womo-data/gps/YYYY-MM.csv

- persistent GPS retention:
  365 days.

- date range selection:
  selected days are interpreted as Europe/Berlin local days, including the
  complete end day until 23:59:59 local time.

- exports:
  CSV contains `timestamp,datetime,latitude,longitude`; GPX uses ISO timestamps
  with the Europe/Berlin UTC offset.

### Installed paths

- web root:
  /usr/local/home/www/womo

- persistent data:
  /usr/local/home/womo-data

- persistent data owner:
  uhttpd, so CGI scripts can append new GPS points while the cron sync can still
  maintain retention as root.

- legacy persistent data source:
  /usr/local/home/root/womo-data

- web data directory:
  none; runtime GPS data is not stored under `/www` or
  `/usr/local/home/www/womo/data`.

### Useful URLs

- Portal:
  - http://ROUTER_IP:8080/

- GPS diagnostics and export checks:
  - http://ROUTER_IP:8080/cgi-bin/gps_track.cgi
  - http://ROUTER_IP:8080/cgi-bin/gps_track.cgi?from=2026-06-01&to=2026-06-09
  - http://ROUTER_IP:8080/cgi-bin/gps_export.cgi?from=2026-06-01&to=2026-06-09&format=csv
  - http://ROUTER_IP:8080/cgi-bin/gps_export.cgi?from=2026-06-01&to=2026-06-09&format=gpx

- Tilt page:
  - http://ROUTER_IP:8080/tilt.html
  - http://ROUTER_IP:8080/tilt.html?demo=1

  The tilt page is optional and needs a compatible ESP32 Main endpoint for live
  values. Use `?demo=1` only to check the layout without live ESP32 data.

- Tilt calibration diagnostics:
  - http://ROUTER_IP:8080/cgi-bin/tilt_calibration.cgi
