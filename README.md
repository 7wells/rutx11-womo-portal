# RUTX11 WoMo Portal

Standalone local web portal for a Teltonika RUTX11 router.

Use at your own risk. This project is provided as-is and without warranty.

Features:
- Mobile-friendly landing page
- OpenStreetMap live GPS map
- GPS tracking (1h / 24h / 4w)
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

Runtime data:
- live GPS track:
  /tmp/womo/gps_track_live.log

- persistent GPS track:
  /usr/local/home/www/womo/data/gps_track.log
