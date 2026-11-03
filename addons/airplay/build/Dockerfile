
# ARMv7 Debian 9 userspace provides the intended glibc 2.24 baseline.
FROM arm32v7/debian:stretch

ENV DEBIAN_FRONTEND=noninteractive

RUN printf '%s\n' \
      'deb http://archive.debian.org/debian stretch main contrib non-free' \
      'deb http://archive.debian.org/debian-security stretch/updates main contrib non-free' \
      > /etc/apt/sources.list \
 && printf 'Acquire::Check-Valid-Until "false";\nAcquire::AllowInsecureRepositories "true";\n' \
      > /etc/apt/apt.conf.d/99archive \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends \
      ca-certificates curl xz-utils tar gzip make gcc g++ cmake patch \
      pkg-config autoconf automake libtool m4 dpkg-dev file binutils \
      patchelf xmltoman vim-common libsodium-dev uuid-dev \
      libavutil-dev libavcodec-dev libavformat-dev libswresample-dev \
      libdaemon-dev libsoxr-dev libplist-utils libasound2-dev \
      libavahi-client-dev libssl-dev libconfig-dev libpopt-dev \
      libgcrypt20-dev libxml2-dev \
 && command -v xxd \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /build

COPY build-target.sh /usr/local/bin/build-target
COPY uuid-generate-sha1-compat.c /usr/local/src/uuid-generate-sha1-compat.c
COPY check-aac-fltp.c /usr/local/src/check-aac-fltp.c
COPY check-alac-decoder.c /usr/local/src/check-alac-decoder.c
COPY patches/shairport-sync-5.6.1-require-ffmpeg-alac.patch /usr/local/src/shairport-sync-require-ffmpeg-alac.patch

RUN sed -i 's/\r$//' /usr/local/bin/build-target \
 && chmod +x /usr/local/bin/build-target

# Runtime packages are downloaded for the ARMv7 target.
RUN apt-get -o Acquire::Check-Valid-Until=false update \
 && mkdir -p /opt/htp1-debs \
 && cd /opt/htp1-debs \
 && apt-get download avahi-daemon libavahi-core7 \
 && dpkg-deb -f avahi-daemon_*.deb Package Architecture \
 && dpkg-deb -f libavahi-core7_*.deb Package Architecture \
 && rm -rf /var/lib/apt/lists/*

CMD ["/usr/local/bin/build-target"]
