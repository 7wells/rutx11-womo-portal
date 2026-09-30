# RUTX11 WoMo Portal

Standalone local web portal for a Teltonika RUTX11 router.

Use at your own risk. This project is provided as-is and without warranty.

## TL;DR

This project installs a small local camper portal on a compatible Teltonika
RUTX11 router. It shows a mobile-friendly GPS map, GPS history/export tools,
and a local tilt/level page for an ESP32-based vehicle sensor.

ESP32 credentials are configured locally on the router after deployment with
`womo-portal-set-esp32-password`. They are never stored in this repository or
sent to the browser. See [ESP32 Main credentials](#esp32-main-credentials).

Configure local device destinations in the installed portal configuration after
installation. Keep local URLs outside this Git repository. See [Local device URLs](#local-device-urls).

The first deployment copies this repository to the router and runs one
installer script. After that, future updates need only the command
`womo-portal-update`. See [Deploy on the RUTX11](#deploy-on-the-rutx11).

The installer is designed to keep existing GPS track data under
`/usr/local/home/womo-data`. As with any router maintenance, keep a backup if
the existing data matters to you.

Open the portal after deployment using the router address reachable from your
device on port 8080, including when connected through a tunnel.

## Details

### Features

- Mobile-friendly map landing page
- OpenStreetMap live GPS map
- Browser-independent background GPS recording
- GPS tracking UI (Live / 24h / 4w)
- Date range selection and CSV/GPX export
- Local tilt/level page with authenticated ESP32 live data and explicit demo mode
- Local Leaflet asset caching
- No cloud dependency
- Lightweight CGI backend
- Flash-friendly GPS persistence design
- Local watchdog for portal and GPS service recovery

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
  - procd-managed background GPS logger
  - procd-managed portal watchdog
  - GPS track sync script
  - private data safety check

### Local device URLs

The repository ships with no local device URLs. On a new installation, the GUI,
ESP32 Main, and Smartavan navigation links stay disabled, and live tilt data is
unavailable until configured.

On the router, edit `/usr/local/home/www/womo/portal-config.js` after installation
and set `routerGuiUrl`, `esp32MainUrl`, and `trumaUrl` to the intended local HTTP
or HTTPS destinations. This installed file is outside the Git repository. The
ESP32 CGI reads its destination from the same installed configuration.

The installer and updater preserve an existing installed configuration and the
existing portal listener. For a new portal listener, the installer reads the
router's configured LAN address; it never binds to every network interface.

### ESP32 Main credentials

- Live tilt data is read server-side from `/sensor/pitch` and `/sensor/roll`.
  Curl automatically selects the HTTP authentication scheme offered by the
  ESP32, currently Basic and also compatible with Digest. The browser receives
  only the numeric JSON `value` fields through the local portal CGI.
- Run `womo-portal-set-esp32-password` as root on the router and enter the
  password at the hidden prompt. The username is fixed to `user`.
- For automated deployments, the installer also accepts the password through
  the temporary `WOMO_ESP32_PASSWORD` environment variable. Do not put its
  value in repository files, command-line arguments, or shell history.
- The generated password file is stored outside the web root at
  `/usr/local/home/womo-data/esp32-main.password`, restricted to the CGI user,
  and preserved by normal portal updates.
- Live tilt access requires the RutOS/OpenWrt commands `curl` and `jsonfilter`.
  Because the current ESP32 firmware offers Basic authentication over HTTP,
  use this only on a trusted local network. Missing credentials, failed
  authentication, invalid JSON, or unavailable endpoints are displayed as
  unavailable values; they do not activate random demo data.

### Deploy on the RUTX11

```sh
cd /tmp
wget -O womo.tar.gz "https://github.com/7wells/rutx11-womo-portal/archive/refs/heads/main.tar.gz"
tar -xzf womo.tar.gz
cd rutx11-womo-portal-main
sh scripts/install_womo_landing.sh
womo-portal-set-esp32-password
```

Configure the installed `portal-config.js` on the router after installation.

After the first successful deployment, install future versions with:

```sh
womo-portal-update
```

The update command keeps the installed `portal-config.js`; local device URLs
are never replaced by repository defaults.

### Deployment notes

- The installer recreates `/usr/local/home/www/womo`, installs the web files,
  enables the CGI scripts, prepares `/usr/local/home/womo-data`, and
  configures uhttpd on port 8080. It also enables the background GPS logger and
  portal watchdog, and installs the persistent `womo-portal-update` command
  under `/usr/local/bin`.
- Use the full deployment procedure for first setup or after a factory reset.
  Use `womo-portal-update` for normal updates.
- The update command preserves the installed `portal-config.js`. GPS history,
  ESP32 credentials, and tilt calibration already remain outside the web root
  and are not replaced by an update.
- Existing GPS history in `/usr/local/home/root/womo-data/gps_track.log` is not
  overwritten by the installer and is migrated into monthly files by the sync
  script.
- Existing monthly GPS files in `/usr/local/home/root/womo-data/gps` are copied
  to `/usr/local/home/womo-data/gps` during installation. Legacy files are not
  deleted automatically.

### Runtime data

- background GPS recording:
  the procd service checks the router position every 5 seconds and records a
  new point after at least 20 metres of movement. Recording does not depend on
  the portal or a browser being open.

- live GPS track:
  /tmp/womo/gps_track_live.log

- pending GPS persistence batch:
  /tmp/womo/gps_track_pending.log

- flash-safe persistence:
  pending points are appended to monthly files every 5 minutes. An abrupt
  power loss can therefore lose only the latest unpersisted batch, normally no
  more than about 5 minutes.

- legacy GPS track migration source:
  /usr/local/home/womo-data/gps_track.log

- persistent tilt calibration:
  /usr/local/home/womo-data/tilt_calibration.json

- private ESP32 credentials:
  /usr/local/home/womo-data/esp32-main.password

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

### Portal watchdog

- The watchdog checks the map page, local GPS CGI, background GPS logger, and
  five-minute persistence path every 60 seconds.
- A component is recovered only after three consecutive failed checks.
  Additional recovery attempts for the same component wait at least 5 minutes.
- Portal recovery restarts uhttpd, logger recovery starts the GPS logger, and
  persistence recovery restores the cron entry, restarts cron, and flushes an
  overdue pending batch.
- ESP32 availability is intentionally not part of portal health. A powered-off
  ESP32 therefore never restarts the portal.
- The watchdog never reboots the router and never downloads repository code.
  CPU, memory, storage, and notifications remain the responsibility of RutOS or
  external monitoring such as RMS.
- Inspect watchdog events with `logread -e womo-watchdog`.

### Installed paths

- web root:
  /usr/local/home/www/womo

- persistent data:
  /usr/local/home/womo-data

- persistent data permissions:
  calibration remains writable by uhttpd; GPS recording and persistence run as
  root, while the map and export CGI scripts only read recorded points.

- GPS logger service:
  /etc/init.d/womo-gps-logger

- GPS logger executable:
  /usr/local/bin/womo_gps_logger.sh

- portal watchdog service:
  /etc/init.d/womo-portal-watchdog

- portal watchdog executable:
  /usr/local/bin/womo_portal_watchdog.sh

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
  - http://ROUTER_IP:8080/cgi-bin/tilt.json

  The tilt page is optional and needs a compatible ESP32 Main endpoint for live
  values. Use `?demo=1` only to check the layout with clearly labelled random
  values. Normal mode never substitutes demo values for unavailable live data.

- Tilt calibration diagnostics:
  - http://ROUTER_IP:8080/cgi-bin/tilt_calibration.cgi
