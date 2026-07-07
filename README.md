# RUTX11 WoMo Portal

Standalone local web portal for a Teltonika RUTX11 router.

Use at your own risk. This project is provided as-is and without warranty.

## TL;DR

This project installs a small local camper portal on a compatible Teltonika
RUTX11 router. It shows a mobile-friendly GPS map, GPS history/export tools,
and a local tilt/level page for an ESP32-based vehicle sensor.

Deploying the portal means copying this repository to the router and running
one installer script. The same deploy command is used for first setup, later
updates, and redeployment after router changes:

```sh
cd /tmp
wget -O womo.tar.gz "https://github.com/7wells/rutx11-womo-portal/archive/refs/heads/main.tar.gz"
tar -xzf womo.tar.gz
cd rutx11-womo-portal-main
# Optional: edit web/portal-config.js if your device URLs differ.
sh scripts/install_womo_landing.sh
```

If your local device addresses differ, edit `web/portal-config.js` before
running the installer. See [Local device URLs](#local-device-urls).

The installer is designed to keep existing GPS track data under
`/usr/local/home/womo-data`. As with any router maintenance, keep a backup if
the existing data matters to you.

Open the portal after deployment:

- http://ROUTER_IP:8080/

Use the router address that is reachable from your device. For example, this
may be a LAN address such as `192.168.11.1` or a VPN address if you access the
router through a tunnel.

## Details

Features:
- Mobile-friendly map landing page
- OpenStreetMap live GPS map
- GPS tracking UI (Live / 24h / 4w)
- Date range selection and CSV/GPX export
- Local tilt/level page with demo fallback
- Local Leaflet asset caching
- No cloud dependency
- Lightweight CGI backend
- Flash-friendly GPS persistence design

Project structure:
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
  - GPS track sync script
  - private data safety check

Local device URLs:
- Edit `web/portal-config.js` before deployment if your RUTX11, ESP32 Main, or
  Truma/Smartavan use different local URLs.
- The file configures only links to local devices, not the portal URL itself.
- Open the portal through whichever router address is reachable from your
  device, for example a LAN address or a VPN address.
- The default values match one common local setup, but they may need adjustment
  for your network.

Deploy on the RUTX11:
```sh
cd /tmp
wget -O womo.tar.gz "https://github.com/7wells/rutx11-womo-portal/archive/refs/heads/main.tar.gz"
tar -xzf womo.tar.gz
cd rutx11-womo-portal-main
sh scripts/install_womo_landing.sh
```

Deployment notes:
- The installer recreates `/usr/local/home/www/womo`, installs the web files,
  enables the CGI scripts, prepares `/usr/local/home/womo-data`, and
  configures uhttpd on port 8080.
- Use the same deploy command for first setup, later updates, and redeployment
  after router changes.
- Existing GPS history in `/usr/local/home/root/womo-data/gps_track.log` is not
  overwritten by the installer and is migrated into monthly files by the sync
  script.
- Existing monthly GPS files in `/usr/local/home/root/womo-data/gps` are copied
  to `/usr/local/home/womo-data/gps` during installation. Legacy files are not
  deleted automatically.

Runtime data:
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

Installed paths:
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

Useful URLs:
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
