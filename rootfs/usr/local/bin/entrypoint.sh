#!/bin/bash
# Set up the user, lay out editable configs under /config (your appdata), launch the 3 services.
# Every config is copied from /defaults on FIRST run only — your edits persist and are never overwritten.
set -eu

PUID="${PUID:-99}"
PGID="${PGID:-100}"
TZ="${TZ:-UTC}"
SOCK="/config/rtorrent/.rtorrent.sock"

echo "[init] PUID=${PUID} PGID=${PGID} TZ=${TZ}"

# --- user/group (Unraid default = nobody:users = 99:100) ---
groupadd -o -g "${PGID}" rtorrent 2>/dev/null || groupmod -o -g "${PGID}" rtorrent
useradd -o -u "${PUID}" -g "${PGID}" -d /config -s /bin/bash rtorrent 2>/dev/null \
  || usermod -o -u "${PUID}" -g "${PGID}" rtorrent

# --- timezone (system-managed, kept separate from your editable php ini) ---
if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
  ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
  echo "date.timezone = ${TZ}" > /etc/php/conf.d/00-timezone.ini
fi

# --- one-time migration from the OLD flat layout (session/, rutorrent-share/, rtorrent.log at /config root) ---
mkdir -p /config/rtorrent /config/rutorrent
[ -d /config/session ]         && [ ! -e /config/rtorrent/session ]      && mv /config/session         /config/rtorrent/session
[ -f /config/rtorrent.log ]    && [ ! -e /config/rtorrent/rtorrent.log ] && mv /config/rtorrent.log    /config/rtorrent/rtorrent.log
[ -d /config/rutorrent-share ] && [ ! -e /config/rutorrent/share ]       && mv /config/rutorrent-share /config/rutorrent/share
rm -f /config/.rtorrent.sock 2>/dev/null || true

# --- folders ---
mkdir -p /config/rtorrent/session /config/rutorrent /config/nginx /config/php /downloads /run/php-fpm /var/lib/nginx/tmp /var/log/nginx

# --- editable configs: copy the baked default ONLY if you don't already have one ---
[ -f /config/rtorrent/rtorrent.rc ] || cp /defaults/rtorrent.rc      /config/rtorrent/rtorrent.rc
[ -f /config/nginx/nginx.conf ]     || cp /defaults/nginx.conf       /config/nginx/nginx.conf
[ -f /config/php/99-rutorrent.ini ] || cp /defaults/99-rutorrent.ini /config/php/99-rutorrent.ini
ln -sf /config/php/99-rutorrent.ini /etc/php/conf.d/99-rutorrent.ini

# --- ruTorrent conf + share live in /config too (editable) ---
[ -d /config/rutorrent/conf ]  || cp -a /var/www/rutorrent/conf  /config/rutorrent/conf
[ -d /config/rutorrent/share ] || cp -a /var/www/rutorrent/share /config/rutorrent/share
rm -rf /var/www/rutorrent/conf /var/www/rutorrent/share
ln -sf /config/rutorrent/conf  /var/www/rutorrent/conf
ln -sf /config/rutorrent/share /var/www/rutorrent/share
# keep ruTorrent pointed at rtorrent's socket (only touches the scgi lines; your other edits are safe)
sed -i 's#\$scgi_port = .*#\$scgi_port = 0;#; s#\$scgi_host = .*#\$scgi_host = "unix://'"${SOCK}"'";#' /config/rutorrent/conf/config.php

# --- ownership ---
chown -R rtorrent:rtorrent /config
chown -R rtorrent:rtorrent /var/lib/nginx /var/log/nginx 2>/dev/null || true
chown rtorrent:rtorrent /downloads /run/php-fpm

# --- launch rtorrent (headless but foreground, so we background it) ---
echo "[init] starting rtorrent"
su rtorrent -s /bin/bash -c "cd /config && exec rtorrent -n -o import=/config/rtorrent/rtorrent.rc" &
for i in $(seq 1 30); do [ -S "${SOCK}" ] && break; sleep 1; done
if [ -S "${SOCK}" ]; then echo "[init] rtorrent scgi socket up"; else
  echo "[init] WARNING: no socket — rtorrent.log:"; tail -20 /config/rtorrent/rtorrent.log 2>/dev/null || true
fi

# --- php-fpm + nginx (nginx config now comes from /config too) ---
echo "[init] starting php-fpm"
php-fpm --daemonize
echo "[init] starting nginx → http://<host>:8080"
exec nginx -c /config/nginx/nginx.conf -g 'daemon off;'
