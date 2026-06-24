# syntax=docker/dockerfile:1
#
# Minimal, near-stock rtorrent + ruTorrent on Arch Linux (glibc).
# rtorrent + libtorrent come from Arch — but PINNED to a version strict private trackers still
# whitelist. Arch ships the bleeding-edge 0.16.x, which trackers like U2/dmhy reject as a
# "Banned Client": their allow-lists — and the popular Swizzin seedbox installer — top out at the
# 0.15.x line. So we pull a pinned 0.15.x pair from the Arch Linux Archive instead of the live
# repo. Still no custom compile.
# Bump RTORRENT_VER below only to a version your tracker actually accepts (drop the pin entirely
# once they whitelist Arch's current release).
# No temp/complete folders, no move-on-complete, no WebDAV, no opinionated layering.
#
FROM archlinux:base

# The rtorrent/libtorrent version to pin. We match Swizzin (the popular seedbox installer): its
# newest build is 0.15.5, the version proven to pass strict trackers like U2/dmhy. Arch's 0.16.x
# is newer than those trackers whitelist, so it gets banned. rtorrent + libtorrent release in
# lockstep, so this one number drives both. (Swizzin also offered 0.15.3 / 0.15.1 / 0.9.8.)
ARG RTORRENT_VER=0.15.5

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
