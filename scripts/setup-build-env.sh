#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"

fail() {
    echo
    echo "WORM_BUILD_ENV=FAIL"
    echo "Errore alla riga $1"
    exit 1
}

trap 'fail $LINENO' ERR

echo "=== worm OS: configure Debian 12 build environment ==="

if [ ! -f "$CHROOT/etc/debian_version" ]; then
    echo "FAIL: chroot non trovato: $CHROOT"
    exit 1
fi

echo
echo "Debian chroot:"
cat "$CHROOT/etc/debian_version"

# DNS
cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"

# Repository Debian 12
cat > "$CHROOT/etc/apt/sources.list" <<'APT'
deb https://deb.debian.org/debian bookworm main contrib
deb https://deb.debian.org/debian bookworm-updates main contrib
deb https://security.debian.org/debian-security bookworm-security main contrib
APT

echo
echo "=== Enable i386 ==="

chroot "$CHROOT" /bin/bash -c '
    set -e
    dpkg --add-architecture i386
'

echo
echo "=== apt update ==="

chroot "$CHROOT" /usr/bin/env \
    DEBIAN_FRONTEND=noninteractive \
    apt-get update

echo
echo "=== Install packages ==="

chroot "$CHROOT" /usr/bin/env \
    DEBIAN_FRONTEND=noninteractive \
    apt-get install -y \
        ca-certificates \
        curl \
        diffutils \
        file \
        fontconfig \
        fonts-dejavu-core \
        git \
        git-lfs \
        gnupg \
        gperf \
        hostname \
        libc6:i386 \
        libgcc-s1:i386 \
        openssh-client \
        openssl \
        python3 \
        repo \
        rsync \
        unzip \
        yarnpkg \
        zip

echo
echo "=== Git LFS ==="

chroot "$CHROOT" /bin/bash -c '
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    git lfs install --system
'

echo
echo "=== VERIFY ==="

COMMANDS="
git
git-lfs
gpg
gperf
python3
repo
rsync
ssh-keygen
unzip
yarnpkg
zip
"

for CMD in $COMMANDS; do
    if chroot "$CHROOT" /bin/bash -c \
        "PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin; command -v '$CMD' >/dev/null"
    then
        printf '%-12s PASS\n' "$CMD"
    else
        printf '%-12s FAIL\n' "$CMD"
        exit 1
    fi
done

echo
echo "=== ENVIRONMENT ==="
printf 'Debian:       '
cat "$CHROOT/etc/debian_version"

printf 'Architecture: '
chroot "$CHROOT" dpkg --print-architecture

printf 'i386:         '
if chroot "$CHROOT" dpkg --print-foreign-architectures | grep -qx i386; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

echo
echo "WORM_BUILD_ENV=PASS"
