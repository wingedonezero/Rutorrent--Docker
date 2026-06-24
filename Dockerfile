# syntax=docker/dockerfile:1
#
# Minimal, near-stock rtorrent + ruTorrent on Arch Linux (glibc).
# rtorrent + libtorrent come from Arch — but PINNED to a version strict private trackers still
# whitelist. Arch's newest (0.16.15+) gets rejected as a "Banned Client" on e.g. U2/dmhy, whose
# accepted-client list lags a release or two behind. So we pull the matching pinned pair from the
# Arch Linux Archive instead of the live repo. Still no custom compile.
# Bump RTORRENT_VER below as trackers add newer versions (and once they catch up to Arch's current
# release you can drop the pin and go back to a plain `pacman -S rtorrent`).
# No temp/complete folders, no move-on-complete, no WebDAV, no opinionated layering.
#
FROM archlinux:base

# The rtorrent/libtorrent version to pin. U2/dmhy's FAQ currently lists 0.16.13–0.16.14 as
# acceptable; 0.16.15 is too new. rtorrent + libtorrent are released in lockstep, so this one
# number drives both. (If your tracker only accepts 0.16.13, change this to 0.16.13.)
ARG RTORRENT_VER=0.16.14

# Update the keyring first (avoids signature errors on a stale base), then install the web stack +
# tools. rtorrent/libtorrent are installed separately just below — pinned, straight from the Arch
# Linux Archive, both in the same transaction so rtorrent uses the pinned libtorrent (not 0.16.15).
RUN pacman -Syu --noconfirm --needed archlinux-keyring \
 && pacman -S --noconfirm --needed \
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
 && pacman -U --noconfirm \
      https://archive.archlinux.org/packages/l/libtorrent/libtorrent-${RTORRENT_VER}-1-x86_64.pkg.tar.zst \
      https://archive.archlinux.org/packages/r/rtorrent/rtorrent-${RTORRENT_VER}-1-x86_64.pkg.tar.zst \
 && sed -i '/^\[options\]/a IgnorePkg = rtorrent libtorrent' /etc/pacman.conf \
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
