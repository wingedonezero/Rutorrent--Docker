#!/bin/bash
# Minimal entrypoint: set up the user/dirs, point ruTorrent at rtorrent, launch the 3 services.
set -eu

PUID="${PUID:-99}"
PGID="${PGID:-100}"
TZ="${TZ:-UTC}"
SOCK="/config/.rtorrent.sock"

echo "[init] PUID=${PUID} PGID=${PGID} TZ=${TZ}"

# --- timezone (so logs use your local time) ---
if [ -f "/usr/share/zoneinfo/${TZ}" ]; then
  ln -sf "/usr/share/zoneinfo/${TZ}" /etc/localtime
  echo "${TZ}" > /etc/timezone
  sed -i "s#^date.timezone = .*#date.timezone = ${TZ}#" /etc/php/conf.d/99-rutorrent.ini
fi

# --- user/group (Unraid default = nobody:users = 99:100) ---
groupadd -o -g "${PGID}" rtorrent 2>/dev/null || groupmod -o -g "${PGID}" rtorrent
useradd -o -u "${PUID}" -g "${PGID}" -d /config -s /bin/bash rtorrent 2>/dev/null \
  || usermod -o -u "${PUID}" -g "${PGID}" rtorrent

# --- directories ---
mkdir -p /config/session /downloads /run/php-fpm /var/lib/nginx/tmp /var/log/nginx
rm -f "${SOCK}"
chown rtorrent:rtorrent /config /config/session /downloads /run/php-fpm
chown -R rtorrent:rtorrent /var/lib/nginx /var/log/nginx

# --- ruTorrent settings persist under /config (survive container recreate) ---
if [ ! -d /config/rutorrent-share ]; then
  cp -a /var/www/rutorrent/share /config/rutorrent-share
fi
rm -rf /var/www/rutorrent/share
ln -sf /config/rutorrent-share /var/www/rutorrent/share
chown -R rtorrent:rtorrent /config/rutorrent-share /var/www/rutorrent/conf

# --- point ruTorrent at rtorrent's scgi socket ---
sed -i "s#\$scgi_port = .*#\$scgi_port = 0;#" /var/www/rutorrent/conf/config.php
sed -i "s#\$scgi_host = .*#\$scgi_host = \"unix://${SOCK}\";#" /var/www/rutorrent/conf/config.php

# --- launch rtorrent in the background (system.daemon.set makes it headless,
#     but it still runs in the foreground, so we background it ourselves) ---
echo "[init] starting rtorrent"
su rtorrent -s /bin/bash -c "cd /config && exec rtorrent -n -o import=/etc/rtorrent/rtorrent.rc" &
for i in $(seq 1 30); do [ -S "${SOCK}" ] && break; sleep 1; done
if [ -S "${SOCK}" ]; then echo "[init] rtorrent scgi socket up"; else
  echo "[init] WARNING: scgi socket missing — rtorrent.log:"; tail -20 /config/rtorrent.log 2>/dev/null || true
fi

# --- php-fpm ---
echo "[init] starting php-fpm"
php-fpm --daemonize

# --- nginx in the foreground (keeps the container alive) ---
echo "[init] starting nginx → http://<host>:8080"
exec nginx -g 'daemon off;'
