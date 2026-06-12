# WoMo Portal Project Instructions

## Project Context

- This repository provides a standalone local web portal for a Teltonika RUTX11 router.
- The installed web root is `/usr/local/home/www/womo`.
- Persistent GPS data lives under `/usr/local/home/womo-data`.
- Runtime-only GPS data lives under `/tmp/womo`.
- The portal is served by `uhttpd` on port `8080`.

## RutOS Deployment Rules

- Keep frequent writes out of persistent flash paths.
- Use `/tmp` only for runtime logs and temporary test artifacts.
- Avoid `/root` for project installs unless explicitly requested.
- Do not use USB storage for small scripts or normal runtime state.
- Do not store runtime GPS data under `/www` or `/usr/local/home/www/womo/data`.

## Frontend

- `web/index.html` is the landing page and map UI.
- There is no separate `map.html`; do not reintroduce a separate map navigation entry unless explicitly requested.
- Preserve the top navigation targets:
  - `GUI` -> `https://192.168.11.1`
  - `Main` -> `http://192.168.11.3`
  - `Smartavan` -> `http://192.168.11.4`
- When changing the map UI, verify at least the Samsung Galaxy A56 Firefox viewport from the global instructions.

## Validation

- After changing web files, check for stale references to removed pages such as `map.html`.
- After changing shell scripts, run or inspect `scripts/check_no_private_data.sh` when relevant.
- For browser checks, use Playwright when layout or interaction behavior changed.
