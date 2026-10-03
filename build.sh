#!/bin/sh
# Static armv7 hard-float OpenVPN for the LG C7 (webOS 3.5). Output: out/openvpn
set -eu

OPENSSL_VER=3.5.9
OPENVPN_VER=2.6.23
CAPNG_VER=0.9.6
CAPNG_SHA256=399040138e0ca62fa2bcabd63da9af4431a246ef7a654561a0ca3cb00010a539   # unsigned upstream; pinned on first fetch
# Primary key fingerprints the release signatures must chain to.
OPENSSL_FPR=B146647E45A7B33947AB226B2A2C87D161692D40   # OpenSSL <openssl@openssl.org>, 2026 key
OPENVPN_FPR=F554A3687412CFFEBDEFE0A312F5F7B42F2B01E7   # OpenVPN - Security Mailing List

CROSS=arm-linux-musleabihf
ARCH_FLAGS="-march=armv7-a -mfpu=neon-vfpv3 -mfloat-abi=hard"

D=$(cd "$(dirname "$0")" && pwd)
B=$D/build
P=$B/prefix
mkdir -p "$B" "$D/out"
cd "$B"

export GNUPGHOME=$B/gnupg
mkdir -p -m 700 "$GNUPGHOME"

fetch() { [ -f "$2" ] || curl -fsSL -o "$2" "$1"; }

# verify <file> <sig> <pinned primary fpr>
verify() {
    gpg --batch --status-fd 1 --verify "$2" "$1" 2>/dev/null | grep -q "^\[GNUPG:\] VALIDSIG .* $3\$" \
        || { echo "signature check FAILED: $1" >&2; exit 1; }
    echo "signature OK: $1"
}

fetch https://openssl-library.org/source/pubkeys.asc openssl-keys.asc
fetch https://swupdate.openvpn.net/community/keys/security.key.asc openvpn-keys.asc
gpg --batch -q --import openssl-keys.asc openvpn-keys.asc

T=openssl-$OPENSSL_VER.tar.gz
fetch https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/$T $T
fetch https://github.com/openssl/openssl/releases/download/openssl-$OPENSSL_VER/$T.asc $T.asc
verify $T $T.asc $OPENSSL_FPR

T=openvpn-$OPENVPN_VER.tar.gz
fetch https://swupdate.openvpn.org/community/releases/$T $T
fetch https://swupdate.openvpn.org/community/releases/$T.asc $T.asc
verify $T $T.asc $OPENVPN_FPR

T=libcap-ng-$CAPNG_VER.tar.gz
fetch https://github.com/stevegrubb/libcap-ng/archive/refs/tags/v$CAPNG_VER.tar.gz $T
echo "$CAPNG_SHA256  $T" | sha256sum -c -

# Only our prefix is visible to pkg-config (keeps host x86 libs out)
export PKG_CONFIG_PATH= PKG_CONFIG_LIBDIR=$P/lib/pkgconfig

# libcap-ng: static, required by OpenVPN on Linux
rm -rf libcap-ng-$CAPNG_VER && tar -xf libcap-ng-$CAPNG_VER.tar.gz
cd libcap-ng-$CAPNG_VER
./autogen.sh
./configure --host=$CROSS --prefix="$P" --disable-shared --enable-static --without-python3 \
    CFLAGS="-O2 $ARCH_FLAGS"
make -j"$(nproc)" -C src
make -C src install
cd "$B"

# OpenSSL: static libs only
rm -rf openssl-$OPENSSL_VER && tar -xf openssl-$OPENSSL_VER.tar.gz
cd openssl-$OPENSSL_VER
./Configure linux-armv4 --cross-compile-prefix=$CROSS- --prefix="$P" --libdir=lib \
    --openssldir=/etc/ssl no-shared no-dso no-engine no-apps no-tests no-docs $ARCH_FLAGS
make -j"$(nproc)" build_libs
make install_dev
cd "$B"

# OpenVPN: static, netlink routing (no ifconfig/route), no compression/plugins/DCO
rm -rf openvpn-$OPENVPN_VER && tar -xf openvpn-$OPENVPN_VER.tar.gz
cd openvpn-$OPENVPN_VER
./configure --host=$CROSS --prefix=/ \
    --disable-lzo --disable-lz4 --disable-plugins --disable-dco --disable-unit-tests \
    CFLAGS="-O2 $ARCH_FLAGS" LDFLAGS="-static" \
    OPENSSL_CFLAGS="-I$P/include" OPENSSL_LIBS="-L$P/lib -lssl -lcrypto"
# libtool drops -static for programs; -all-static is its spelling
make -j"$(nproc)" LDFLAGS="-all-static"
$CROSS-strip -o "$D/out/openvpn" src/openvpn/openvpn

file "$D/out/openvpn"
sha256sum "$D/out/openvpn"
