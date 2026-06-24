# syntax=docker/dockerfile:1
#
# Minimal, near-stock rtorrent + ruTorrent on Arch Linux (glibc).
# rtorrent + libtorrent come straight from Arch's repos (currently 0.16.15) — no custom compile.
# No temp/complete folders, no move-on-complete, no WebDAV, no opinionated layering.
# The whole point: a *default* rtorrent already does what we want. We just plumb it to ruTorrent.
#
FROM archlinux:base

# Update the keyring first (avoids signature errors on a stale base), then install
# rtorrent (pulls libtorrent), the web stack, and a couple of tools.
RUN pacman -Syu --noconfirm --needed archlinux-keyring \
 && pacman -S --noconfirm --needed \
      rtorrent \
      nginx \
      php php-fpm php-gd \
      curl \
      git \
      shadow \
      python python-pip \
      tzdata \
      mediainfo \
      ffmpeg \
      sox \
      unzip unrar 7zip \
      dumptorrent \
 && pacman -Scc --noconfirm \
 && rm -rf /var/cache/pacman/pkg/* /var/lib/pacman/sync/*

# cloudscraper: the _cloudflare plugin uses it to fetch .torrents from Cloudflare-protected
# trackers (e.g. privatehd.to). pip-only; --break-system-packages is fine inside a container.
RUN pip install --break-system-packages --no-cache-dir cloudscraper

# ruTorrent web UI (latest from upstream)
RUN git clone --depth 1 https://github.com/Novik/ruTorrent.git /var/www/rutorrent \
 && rm -rf /var/www/rutorrent/.git /var/www/rutorrent/conf/users

# Our minimal config overlay + entrypoint
COPY rootfs/ /
RUN chmod +x /usr/local/bin/entrypoint.sh

# 8080 = ruTorrent web UI · 50000/tcp = incoming peers · 50000/udp = DHT (public torrents)
EXPOSE 8080 50000/tcp 50000/udp

# Unraid integration: gives the container a clickable WebUI button + an icon in the Docker tab,
# the same as any other managed container.
LABEL net.unraid.docker.webui="http://[IP]:[PORT:8080]/" \
      net.unraid.docker.icon="https://raw.githubusercontent.com/Novik/ruTorrent/master/images/favicon-196x196.png"

# Healthy only when the whole chain works: nginx → php → rtorrent reports started.
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s \
  CMD curl -fsS http://localhost:8080/php/getplugins.php 2>/dev/null | grep -q '"started":true\|started:true' || exit 1

VOLUME ["/downloads", "/config"]
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
