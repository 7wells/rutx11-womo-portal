# RUTX11 WoMo Portal

Standalone local web portal for a Teltonika RUTX11 router.

Use at your own risk. This project is provided as-is and without warranty.

Features:
- Mobile-friendly landing page
- OpenStreetMap live GPS map
- GPS tracking UI (Live / 24h / 4w)
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
./scripts/install_womo_landing.sh
```

Restore after a firmware update:
- Copy or download this repository to the router again.
- Run `./scripts/install_womo_landing.sh`.
- The installer recreates `/usr/local/home/www/womo`, installs the web files,
  enables the CGI scripts, prepares `/usr/local/home/root/womo-data`, and
  configures uhttpd on port 8080.
- Existing GPS history in `/usr/local/home/root/womo-data/gps_track.log` is not
  overwritten by the installer.

Runtime data:
- live GPS track:
  /tmp/womo/gps_track_live.log

- persistent GPS track:
  /usr/local/home/root/womo-data/gps_track.log

- persistent GPS retention:
  180 days internally; the current UI still shows Live, 24h, and 4w.

Installed paths:
- web root:
  /usr/local/home/www/womo

- persistent data:
  /usr/local/home/root/womo-data

Test URLs:
- http://10.10.10.2:8080/
- http://10.10.10.2:8080/map.html
- http://10.10.10.2:8080/cgi-bin/gps_track.cgi

Planned:
- Date range selection from/to.
- Export for the selected range, for example GPX or CSV.
