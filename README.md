# rtorrent + ruTorrent (Arch / glibc)

A deliberately **lean, near-stock** rtorrent + ruTorrent container, built on **Arch Linux (glibc)**.

Built because the popular Alpine/`musl`-based images (e.g. crazy-max) suffer an `rtorrent-scgi`
thread that busy-loops on Cloudflare/tracker connections — the web UI freezes hard. The bug
tracks **musl vs glibc** (the maintainer confirmed it's fine on glibc hosts). This image runs the
same modern rtorrent on glibc, with a minimal config and none of the temp/complete/move/WebDAV
layering, so a *default* rtorrent does exactly what you want: download to **one** directory, seed
in place, no auto-rehash.

## What's inside
- **rtorrent + libtorrent** straight from Arch's repo (currently `0.16.x`) — no custom compile
- **nginx + php-fpm + ruTorrent** (latest)
- ruTorrent plugin helpers: `mediainfo`, `ffmpeg`, `sox`, `unrar`/`unzip`/`7z`, `dumptorrent`,
  and `python` + `cloudscraper` for the Cloudflare plugin

## Run
```bash
docker run -d --name rtorrent-rutorrent --restart unless-stopped \
  -e PUID=99 -e PGID=100 -e TZ=America/New_York \
  -p 8080:8080 -p 50000:50000 \
  -v /path/to/appdata:/config \
  -v /path/to/downloads:/downloads \
  ghcr.io/wingedonezero/rtorrent-rutorrent:latest
```
Then open `http://<host>:8080`.

| Setting | |
|---|---|
| `PUID` / `PGID` | run-as user/group (Unraid: `99` / `100`) |
| `TZ` | timezone (e.g. `America/New_York`) |
| `/config` | rtorrent session + ruTorrent settings (persist here) |
| `/downloads` | single download directory |
| `8080` | ruTorrent web UI |
| `50000` | incoming peer port (forward on router) |

## Unraid
A template is in [`unraid/unraid-template.xml`](unraid/unraid-template.xml) — drop it in
`/boot/config/plugins/dockerMan/templates-user/` and it shows up under **Add Container** with a
WebUI button + icon. **An Unassigned Devices download drive must use Access Mode `RW/Slave`.**

## Notes
- `system.umask.set = 0000` (in `rootfs/etc/rtorrent/rtorrent.rc`) makes downloads world-readable
  so other apps (Plex/Jellyfin) can use them. Change to `0022` for stock-tight perms.
- The image is pushed to GHCR automatically on every push to `main`.
