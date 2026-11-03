
#!/bin/sh
set -eu

OUT=/out
WORK=/work

SHAIRPORT_VERSION=5.6.1
NQPTP_VERSION=1.2.9
LIBPLIST_VERSION=2.3.0

mkdir -p "$OUT" "$WORK/src" "$WORK/stage-nqptp" "$WORK/stage-shairport"
cd "$WORK"

fetch() {
  url=$1
  file=$2
  [ -s "$file" ] || curl -fL --retry 3 --connect-timeout 20 "$url" -o "$file"
}

# Release 2.0.33 build; source versions remain pinned.
# Download pinned source versions.
fetch "https://github.com/mikebrady/shairport-sync/archive/refs/tags/${SHAIRPORT_VERSION}.tar.gz" "shairport-sync-${SHAIRPORT_VERSION}.tar.gz"
fetch "https://github.com/mikebrady/nqptp/archive/refs/tags/${NQPTP_VERSION}.tar.gz" "nqptp-${NQPTP_VERSION}.tar.gz"
fetch "https://github.com/libimobiledevice/libplist/archive/refs/tags/${LIBPLIST_VERSION}.tar.gz" "libplist-${LIBPLIST_VERSION}.tar.gz"

# Extract source archives.
for item in \
  "libplist-${LIBPLIST_VERSION} libplist-${LIBPLIST_VERSION}.tar.gz" \
  "nqptp-${NQPTP_VERSION} nqptp-${NQPTP_VERSION}.tar.gz" \
  "shairport-sync-${SHAIRPORT_VERSION} shairport-sync-${SHAIRPORT_VERSION}.tar.gz"
do
  set -- $item
  if [ ! -d "src/$1" ]; then
    mkdir -p "src/$1"
    tar -xzf "$2" --strip-components=1 -C "src/$1"
  fi
done

# Build and install libplist.
cd "$WORK/src/libplist-${LIBPLIST_VERSION}"
echo "$LIBPLIST_VERSION" > .tarball-version
./autogen.sh --prefix=/usr/local --without-cython
make -j2
make install

cd "$WORK"
ldconfig

# Build and stage NQPTP.
cd "$WORK/src/nqptp-${NQPTP_VERSION}"
autoreconf -fi
./configure --prefix=/usr
make -j2
DESTDIR="$WORK/stage-nqptp" make install

# Debian Stretch's libuuid lacks uuid_generate_sha1.
# Provide the UUIDv5 compatibility implementation using OpenSSL.
gcc -Wall -Wextra -Werror -c \
  /usr/local/src/uuid-generate-sha1-compat.c \
  -o "$WORK/uuid-generate-sha1-compat.o"

# Configure Shairport Sync with AirPlay 2, FFmpeg and SoXR support.
cd "$WORK/src/shairport-sync-${SHAIRPORT_VERSION}"

# Enforce the configured FFmpeg ALAC decoder: fail startup rather than silently
# falling back, and print the selected decoder during normal startup.
patch --batch --forward --fuzz=0 -p1 \
  -i /usr/local/src/shairport-sync-require-ffmpeg-alac.patch

if ! grep -Fq 'Using the FFmpeg ALAC decoder.' shairport.c ||
   ! grep -Fq 'Refusing to fall back to another ALAC decoder.' shairport.c; then
  echo "Strict FFmpeg ALAC source patch was not applied" >&2
  exit 1
fi

autoreconf -fi

PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:/usr/local/lib/arm-linux-gnueabihf/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}" \
  LIBS="$WORK/uuid-generate-sha1-compat.o -lcrypto" \
  ./configure \
    --prefix=/usr \
    --sysconfdir=/etc \
    --with-alsa \
    --with-avahi \
    --with-ssl=openssl \
    --with-pipe \
    --with-soxr \
    --with-airplay-2 \
    > "$OUT/shairport-configure.log" 2>&1
cat "$OUT/shairport-configure.log"

# Verify the generated compile-time feature switches, not just configure arguments.
if ! grep -Eq '^[[:space:]]*#define[[:space:]]+CONFIG_FFMPEG[[:space:]]+1' config.h; then
  echo "Shairport Sync was not compiled with CONFIG_FFMPEG" >&2
  exit 1
fi
if ! grep -Eq '^[[:space:]]*#define[[:space:]]+CONFIG_SOXR[[:space:]]+1' config.h; then
  echo "Shairport Sync was not compiled with CONFIG_SOXR" >&2
  exit 1
fi
echo "compile_feature_ffmpeg=enabled (CONFIG_FFMPEG)"
echo "compile_feature_soxr=enabled (CONFIG_SOXR)"

# Shairport Sync's configure script adds -lconfig and may add -lsodium.
# Force these libraries to be selected from their static archives.
# Restore dynamic linking immediately afterward for other libraries.
sed -i \
  -e 's/-lconfig/-Wl,-Bstatic -lconfig -Wl,-Bdynamic/g' \
  -e 's/-lsodium/-Wl,-Bstatic -lsodium -Wl,-Bdynamic/g' \
  Makefile

make -j2
DESTDIR="$WORK/stage-shairport" make install

cd "$WORK"

# Stage Shairport Sync.
install -m 0755 \
  "$WORK/stage-shairport/usr/bin/shairport-sync" \
  "$OUT/shairport-sync"

# Confirm the fail-closed and selected-decoder messages are present in the
# actual executable that will be packaged.
if ! strings "$OUT/shairport-sync" | grep -Fq 'Using the FFmpeg ALAC decoder.'; then
  echo "Built Shairport Sync binary lacks the FFmpeg ALAC selection message" >&2
  exit 1
fi
if ! strings "$OUT/shairport-sync" | grep -Fq 'Refusing to fall back to another ALAC decoder.'; then
  echo "Built Shairport Sync binary lacks the strict FFmpeg ALAC fallback guard" >&2
  exit 1
fi
echo "alac_decoder_enforcement=FFmpeg required; startup logs selected decoder"

# Locate and stage NQPTP.
NQPTP_BIN="$WORK/stage-nqptp/usr/bin/nqptp"

if [ ! -x "$NQPTP_BIN" ]; then
  NQPTP_BIN=$(find "$WORK/stage-nqptp" -type f -name nqptp -perm /111 | head -n 1)
fi

if [ -z "$NQPTP_BIN" ] || [ ! -x "$NQPTP_BIN" ]; then
  echo "Could not find built nqptp executable" >&2
  exit 1
fi

install -m 0755 "$NQPTP_BIN" "$OUT/nqptp"

# Bundle the runtime shared objects used by Shairport Sync.
mkdir -p "$OUT/lib"
cp -a /usr/local/lib/libplist-2.0.so* "$OUT/lib/"
cp -a /usr/lib/arm-linux-gnueabihf/libsoxr.so* "$OUT/lib/"

if ! ls "$OUT"/lib/libplist-2.0.so* >/dev/null 2>&1; then
  echo "Bundled libplist shared objects are missing" >&2
  exit 1
fi

if ! ls "$OUT"/lib/libsoxr.so* >/dev/null 2>&1; then
  echo "Bundled libsoxr shared objects are missing" >&2
  exit 1
fi

# Verify ARM architecture.
file "$OUT/shairport-sync" > "$OUT/shairport-file.txt"
file "$OUT/nqptp" > "$OUT/nqptp-file.txt"
cat "$OUT/shairport-file.txt" "$OUT/nqptp-file.txt" > "$OUT/file-report.txt"
cat "$OUT/file-report.txt"

if ! grep -q 'ARM' "$OUT/shairport-file.txt"; then
  echo "Shairport Sync binary is not ARM" >&2
  exit 1
fi

if ! grep -q 'ARM' "$OUT/nqptp-file.txt"; then
  echo "NQPTP binary is not ARM" >&2
  exit 1
fi

# Check shared-library resolution.
LD_LIBRARY_PATH="$OUT/lib" ldd "$OUT/shairport-sync" > "$OUT/shairport-ldd.txt"
ldd "$OUT/nqptp" > "$OUT/nqptp-ldd.txt"

cat "$OUT/shairport-ldd.txt"
cat "$OUT/nqptp-ldd.txt"

# Verify the exact AAC decoder exposed by the libavcodec used by this build.
# AirPlay 2 buffered AAC requires planar floating-point (fltp) output.
gcc -Wall -Wextra -Werror \
  $(pkg-config --cflags libavcodec libavutil) \
  /usr/local/src/check-aac-fltp.c \
  -o "$WORK/check-aac-fltp" \
  $(pkg-config --libs libavcodec libavutil)
"$WORK/check-aac-fltp"

# Confirm Shairport Sync itself uses the same dynamically linked libavcodec.
if ! grep -q 'libavcodec' "$OUT/shairport-ldd.txt"; then
  echo "Shairport Sync is not dynamically linked to libavcodec; AAC check may not describe its decoder" >&2
  exit 1
fi

# Verify that the build's libavcodec provides an ALAC decoder and advertises
# its supported PCM output formats. This is a library capability check, not
# proof that Shairport Sync routes a particular input stream through FFmpeg.
gcc -Wall -Wextra -Werror \
  $(pkg-config --cflags libavcodec libavutil) \
  /usr/local/src/check-alac-decoder.c \
  -o "$WORK/check-alac-decoder" \
  $(pkg-config --libs libavcodec libavutil)
"$WORK/check-alac-decoder"

# Capture binary metadata that helps identify the actual ALAC decode path.
# FFmpeg may be dynamically linked or statically linked, so absence from ldd
# alone is not treated as proof that FFmpeg is unused.
readelf -d "$OUT/shairport-sync" > "$OUT/shairport-dynamic-section.txt" 2>&1 || true
nm -D "$OUT/shairport-sync" > "$OUT/shairport-dynamic-symbols.txt" 2>&1 || true
strings "$OUT/shairport-sync" | grep -Ei 'avcodec|avformat|ffmpeg|alac' > "$OUT/shairport-codec-strings.txt" || true
{
  echo "=== Dynamic dependencies ==="
  cat "$OUT/shairport-ldd.txt"
  echo "=== Dynamic section ==="
  cat "$OUT/shairport-dynamic-section.txt"
  echo "=== Matching dynamic symbols ==="
  grep -Ei 'avcodec|avformat|ffmpeg|alac' "$OUT/shairport-dynamic-symbols.txt" || true
  echo "=== Codec-related strings (indicative only) ==="
  cat "$OUT/shairport-codec-strings.txt"
} > "$OUT/alac-verification-evidence.txt"

if grep -q 'not found' "$OUT/shairport-ldd.txt" "$OUT/nqptp-ldd.txt"; then
  echo "One or more shared-library dependencies are missing" >&2
  exit 1
fi

# Keep this compatibility check enabled.
if grep -Eq 'lib(config|sodium)\.so' "$OUT/shairport-ldd.txt"; then
  echo "libconfig/libsodium should be statically linked for HTP-1 compatibility" >&2
  exit 1
fi

if ! grep -Fq "$OUT/lib/libplist-2.0.so" "$OUT/shairport-ldd.txt"; then
  echo "Shairport Sync is not resolving libplist from the staged addon library directory" >&2
  exit 1
fi

if ! grep -Fq "$OUT/lib/libsoxr.so" "$OUT/shairport-ldd.txt"; then
  echo "Shairport Sync is not resolving libsoxr from the staged addon library directory" >&2
  exit 1
fi

# Check executable startup and versions.
LD_LIBRARY_PATH="$OUT/lib" "$OUT/shairport-sync" -V > "$OUT/shairport-version.txt"
LD_LIBRARY_PATH="$OUT/lib" "$OUT/nqptp" -V > "$OUT/nqptp-version.txt"

cat "$OUT/shairport-version.txt"
cat "$OUT/nqptp-version.txt"

if ! grep -qi 'smi11' "$OUT/shairport-version.txt"; then
  echo "Shairport Sync does not report smi11" >&2
  exit 1
fi

if ! grep -qi 'smi11' "$OUT/nqptp-version.txt"; then
  echo "NQPTP does not report smi11" >&2
  exit 1
fi

# Stage the Debian 9 ARMHF Avahi runtime packages.
mkdir -p "$OUT/debs"
cp -a /opt/htp1-debs/avahi-daemon_*.deb \
  /opt/htp1-debs/libavahi-core7_*.deb "$OUT/debs/"

for deb in "$OUT"/debs/*.deb; do
  [ -f "$deb" ] || {
    echo "Missing required Avahi package: $deb" >&2
    exit 1
  }
  dpkg-deb -f "$deb" Package Architecture
done

# Record build results. Hardware playback is not tested here.
{
  echo "result=PASS: build, architecture, dynamic-link and version checks passed"
  echo "runtime_htp1_shared_libraries=NOT_VERIFIED"
  echo "runtime_smi_handshake=NOT_VERIFIED"
  echo "physical_htp1_playback=NOT_VERIFIED"
  echo "shairport_sync_source=${SHAIRPORT_VERSION}"
  echo "nqptp_source=${NQPTP_VERSION}"
  echo "shared_memory_interface=smi11"
  echo "libplist_source=${LIBPLIST_VERSION}"
  echo "avahi_runtime_packages=avahi-daemon,libavahi-core7"
  echo "target=armhf / Debian 9 / glibc 2.24 baseline"
  echo "configure_flags=--with-alsa --with-avahi --with-ssl=openssl --with-pipe --with-soxr --with-airplay-2"
  echo "soxr_runtime=libsoxr bundled in addon/lib and resolved by shairport-sync"
  if grep -Eq 'libavcodec|libavformat' "$OUT/shairport-ldd.txt"; then
    echo "ffmpeg_linkage=dynamic (libavcodec/libavformat found by ldd)"
  elif grep -Eiq 'avcodec|avformat|ffmpeg' "$OUT/shairport-dynamic-symbols.txt" "$OUT/shairport-codec-strings.txt"; then
    echo "ffmpeg_linkage=possible-static-or-embedded (binary evidence found; review alac-verification-evidence.txt)"
  else
    echo "ffmpeg_linkage=not-confirmed-by-binary-inspection (review alac-verification-evidence.txt and configure log)"
  fi
  echo "aac_decoder_verification=passed; decoder details printed in this Actions log"
  echo "alac_decoder_verification=passed; decoder details printed in this Actions log"
  echo "alac_runtime_path=not_confirmed; decoder availability does not prove Shairport Sync selects it"
  sha256sum "$OUT/shairport-sync" "$OUT/nqptp"
} > "$OUT/BUILD-REPORT.txt"

cat "$OUT/BUILD-REPORT.txt"
cat "$OUT/alac-verification-evidence.txt"
