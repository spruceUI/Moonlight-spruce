#!/bin/bash
set -e

MOONLIGHT_COMMIT="${MOONLIGHT_COMMIT:-274d3db34da764344a7a402ee74e6080350ac0cd}"
OPENSSL_VERSION="${OPENSSL_VERSION:-3.3.1}"
CURL_VERSION="${CURL_VERSION:-8.7.1}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
CROSS=aarch64-linux-gnu
SYSROOT=/usr/lib/${CROSS}

export STRIP=${CROSS}-strip
export PKG_CONFIG_PATH=/usr/lib/${CROSS}/pkgconfig
export PKG_CONFIG_LIBDIR=/usr/lib/${CROSS}/pkgconfig

export OPTFLAGS="-O3 -ffunction-sections -fdata-sections -flto=auto"
export LDFLAGS="-Wl,--gc-sections -flto=auto"

# ccache setup
export CCACHE_DIR="${CCACHE_DIR:-/ccache}"
export PATH="/usr/lib/ccache:$PATH"
ln -sf /usr/bin/ccache /usr/local/bin/${CROSS}-gcc
ln -sf /usr/bin/ccache /usr/local/bin/${CROSS}-g++
ccache --max-size=500M
ccache --zero-stats

# Local install prefix for OpenSSL and curl
PREFIX=/build/local
mkdir -p "$PREFIX"

# ============================================================
# Build OpenSSL 3.x from source
# (Don't set CC/CXX — OpenSSL's --cross-compile-prefix handles it)
# ============================================================
echo "=== Building OpenSSL ${OPENSSL_VERSION} ==="
wget -q "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
tar xf "openssl-${OPENSSL_VERSION}.tar.gz"
cd "openssl-${OPENSSL_VERSION}"
./Configure linux-aarch64 \
    --cross-compile-prefix=${CROSS}- \
    --prefix="$PREFIX" \
    --libdir=lib \
    shared \
    no-tests \
    -O3
make -j$(nproc)
make install_sw
cd /build

# Set CC/CXX/AR for curl and moonlight builds
export CC=${CROSS}-gcc
export CXX=${CROSS}-g++
export AR=${CROSS}-ar

# ============================================================
# Build curl from source (against our OpenSSL)
# ============================================================
echo "=== Building curl ${CURL_VERSION} ==="
wget -q "https://curl.se/download/curl-${CURL_VERSION}.tar.xz"
tar xf "curl-${CURL_VERSION}.tar.xz"
cd "curl-${CURL_VERSION}"
./configure \
    --host=${CROSS} \
    --prefix="$PREFIX" \
    --with-openssl="$PREFIX" \
    --without-libpsl \
    --disable-manual \
    --disable-ldap \
    --enable-shared \
    --disable-static \
    CFLAGS="$OPTFLAGS" \
    LDFLAGS="$LDFLAGS -Wl,-rpath-link,$PREFIX/lib"
make -j$(nproc)
make install
cd /build

# ============================================================
# Build moonlight-embedded
# ============================================================
echo "=== Building moonlight-embedded ==="
git clone https://github.com/moonlight-stream/moonlight-embedded.git moonlight
cd moonlight
git checkout "$MOONLIGHT_COMMIT"
git submodule update --init --recursive

# Apply patches
for patch in /patches/*.py; do
    [ -f "$patch" ] && python3 "$patch" && echo "Applied: $(basename $patch)"
done
for patch in /patches/*.patch; do
    [ -f "$patch" ] && git apply "$patch" && echo "Applied: $(basename $patch)"
done

mkdir -p build && cd build

# Moonlight's cmake/Find*.cmake modules use find_path/find_library directly,
# so we need to help cmake find arm64 multiarch paths
SYSROOT=/usr/${CROSS}
cmake .. \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_SYSTEM_PROCESSOR=aarch64 \
    -DCMAKE_C_COMPILER=${CROSS}-gcc \
    -DCMAKE_CXX_COMPILER=${CROSS}-g++ \
    -DCMAKE_FIND_ROOT_PATH="${SYSROOT};${PREFIX};/usr" \
    -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=ONLY \
    -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
    -DCMAKE_FIND_ROOT_PATH_MODE_PROGRAM=NEVER \
    -DCMAKE_LIBRARY_PATH="/usr/lib/${CROSS}" \
    -DCMAKE_INCLUDE_PATH="/usr/include" \
    -DCMAKE_PREFIX_PATH="$PREFIX" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_FLAGS="$OPTFLAGS -I${PREFIX}/include" \
    -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS -L${PREFIX}/lib -L/usr/lib/${CROSS} -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath-link,/usr/lib/${CROSS}" \
    -DCMAKE_SHARED_LINKER_FLAGS="$LDFLAGS -L${PREFIX}/lib -L/usr/lib/${CROSS} -Wl,-rpath-link,${PREFIX}/lib -Wl,-rpath-link,/usr/lib/${CROSS}" \
    -DENABLE_X11=OFF
make -j$(nproc)
cd /build

# ============================================================
# Collect output
# ============================================================
echo "=== Collecting output ==="
mkdir -p "$OUTPUT_DIR/libs"

# moonlight binary
cp moonlight/build/moonlight "$OUTPUT_DIR/"
${STRIP} -s "$OUTPUT_DIR/moonlight"

# Libraries built by moonlight-embedded
for lib in moonlight/build/libmoonlight-common.so* moonlight/build/libgamestream.so*; do
    [ -f "$lib" ] && cp "$lib" "$OUTPUT_DIR/libs/"
done

# OpenSSL and curl libs we built
cp "$PREFIX"/lib/libssl.so.3 "$OUTPUT_DIR/libs/"
cp "$PREFIX"/lib/libcrypto.so.3 "$OUTPUT_DIR/libs/"
cp "$PREFIX"/lib/libcurl.so.4 "$OUTPUT_DIR/libs/"

# System arm64 libs moonlight needs at runtime
LIBDIR=/usr/lib/${CROSS}
collect_lib() {
    local name="$1"
    local src
    # Find the actual .so file (resolve symlinks)
    src=$(find "$LIBDIR" /lib/${CROSS} -maxdepth 1 -name "${name}" 2>/dev/null | head -1)
    if [ -n "$src" ]; then
        cp -L "$src" "$OUTPUT_DIR/libs/"
        echo "  Collected: $name"
    else
        echo "  WARNING: $name not found"
    fi
}

# FFmpeg / codec
collect_lib "libavcodec.so.58"
collect_lib "libavutil.so.56"
collect_lib "libswresample.so.3"

# Audio
collect_lib "libopus.so.0"
collect_lib "libpulse.so.0"
collect_lib "libpulse-simple.so.0"
collect_lib "libasound.so.2"

# Input
collect_lib "libevdev.so.2"

# Network / service discovery
collect_lib "libavahi-client.so.3"
collect_lib "libavahi-common.so.3"
collect_lib "libnghttp2.so.14"

# Transitive dependencies commonly missing on embedded devices
collect_lib "libexpat.so.1"
collect_lib "libsndfile.so.1"
collect_lib "libasyncns.so.0"
collect_lib "libdbus-1.so.3"
collect_lib "libsystemd.so.0"
collect_lib "liblz4.so.1"
collect_lib "liblzma.so.5"
collect_lib "libgcrypt.so.20"
collect_lib "libgpg-error.so.0"
collect_lib "libbsd.so.0"
collect_lib "libapparmor.so.1"
collect_lib "libwrap.so.0"
collect_lib "libnsl.so.1"
collect_lib "libtinfo.so.6"
collect_lib "libFLAC.so.8"
collect_lib "libvorbis.so.0"
collect_lib "libvorbisenc.so.2"
collect_lib "libogg.so.0"

# X11 libs needed by SDL platform backend
collect_lib "libX11.so.6"
collect_lib "libxcb.so.1"
collect_lib "libXau.so.6"
collect_lib "libXdmcp.so.6"

# Strip all collected libs
for so in "$OUTPUT_DIR"/libs/*.so*; do
    ${STRIP} -s "$so" 2>/dev/null || true
done

echo "=== ccache stats ==="
ccache --show-stats

echo "=== Build complete ==="
ls -la "$OUTPUT_DIR/"
ls -la "$OUTPUT_DIR/libs/"
