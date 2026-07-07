# RUTX11 WoMo Portal

Standalone local web portal for a Teltonika RUTX11 router.

Use at your own risk. This project is provided as-is and without warranty.

Features:
- Mobile-friendly map landing page
- OpenStreetMap live GPS map
- GPS tracking UI (Live / 24h / 4w)
- Date range selection and CSV/GPX export
- Local Leaflet asset caching
- No cloud dependency
- Lightweight CGI backend
- Flash-friendly GPS persistence design

Project structure:
- web/
  - HTML frontend
  - CGI scripts
  - cached Leaflet assets
- scripts/
  - installation script
  - GPS track sync script
  - private data safety check

Emergency recovery on the RUTX11:
```sh
cd /tmp
wget -O womo.tar.gz "https://github.com/7wells/rutx11-womo-portal/archive/refs/heads/main.tar.gz"
tar -xzf womo.tar.gz
cd rutx11-womo-portal-main
sh scripts/install_womo_landing.sh
```

Restore after a firmware update:
- Copy or download this repository to the router again.
- Run `sh scripts/install_womo_landing.sh`.
- The installer recreates `/usr/local/home/www/womo`, installs the web files,
  enables the CGI scripts, prepares `/usr/local/home/womo-data`, and
  configures uhttpd on port 8080.
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

Test URLs:
- http://10.10.10.2:8080/
- http://10.10.10.2:8080/cgi-bin/gps_track.cgi
- http://10.10.10.2:8080/cgi-bin/gps_track.cgi?from=2026-06-01&to=2026-06-09
- http://10.10.10.2:8080/cgi-bin/gps_export.cgi?from=2026-06-01&to=2026-06-09&format=csv
- http://10.10.10.2:8080/cgi-bin/gps_export.cgi?from=2026-06-01&to=2026-06-09&format=gpx

Planned:
- Optional map display improvements for large exported ranges.
