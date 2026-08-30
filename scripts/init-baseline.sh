#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"
TAG=2026081300

MOUNTED_PROC=0
MOUNTED_DEV=0
MOUNTED_SYS=0
MOUNTED_UPSTREAM=0

cleanup() {
    set +e

    if [ "$MOUNTED_UPSTREAM" = 1 ]; then
        umount "$CHROOT/opt/Android/worm-os/upstream"
    fi

    if [ "$MOUNTED_SYS" = 1 ]; then
        umount "$CHROOT/sys"
    fi

    if [ "$MOUNTED_DEV" = 1 ]; then
        umount "$CHROOT/dev"
    fi

    if [ "$MOUNTED_PROC" = 1 ]; then
        umount "$CHROOT/proc"
    fi
}

fail() {
    LINE="$1"
    echo
    echo "WORM_BASELINE_INIT=FAIL"
    echo "Errore alla riga $LINE"
}

trap 'fail $LINENO' ERR
trap cleanup EXIT

echo "=== worm OS: GrapheneOS baseline init ==="
echo
echo "TAG=$TAG"
echo "UPSTREAM=$UPSTREAM"
echo

test -f "$CHROOT/etc/debian_version" || {
    echo "FAIL: Debian build environment missing"
    exit 1
}

mkdir -p \
    "$UPSTREAM" \
    "$CHROOT/opt/Android/worm-os/upstream" \
    "$CHROOT/proc" \
    "$CHROOT/sys"

# DNS
cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"

echo "=== Temporary chroot mounts ==="

if ! mountpoint -q "$CHROOT/proc"; then
    mount -t proc proc "$CHROOT/proc"
    MOUNTED_PROC=1
fi

if ! mountpoint -q "$CHROOT/dev"; then
    mount --bind /dev "$CHROOT/dev"
    MOUNTED_DEV=1
fi

if ! mountpoint -q "$CHROOT/sys"; then
    mount --bind /sys "$CHROOT/sys"
    MOUNTED_SYS=1
fi

if ! mountpoint -q "$CHROOT/opt/Android/worm-os/upstream"; then
    mount --bind \
        "$UPSTREAM" \
        "$CHROOT/opt/Android/worm-os/upstream"

    MOUNTED_UPSTREAM=1
fi

echo "mounts=PASS"

echo
echo "=== Safety check ==="

# In questa milestone upstream deve essere vuoto oppure contenere
# solamente un precedente repo init.
if [ -n "$(find "$UPSTREAM" -mindepth 1 -maxdepth 1 ! -name .repo -print -quit)" ]; then
    echo "FAIL: upstream contiene file inattesi:"
    find "$UPSTREAM" -mindepth 1 -maxdepth 1 -printf '%f\n'
    exit 1
fi

echo "upstream=PASS"

echo
echo "=== Download GrapheneOS allowed_signers ==="

chroot "$CHROOT" /bin/bash <<'CHROOT_EOF'
set -Eeuo pipefail

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root

mkdir -p /root/.ssh
chmod 700 /root/.ssh

curl \
    --fail \
    --show-error \
    --location \
    https://grapheneos.org/allowed_signers \
    -o /root/.ssh/grapheneos_allowed_signers

test -s /root/.ssh/grapheneos_allowed_signers

chmod 644 /root/.ssh/grapheneos_allowed_signers

echo "allowed_signers=PASS"
CHROOT_EOF

echo
echo "=== repo init ==="

chroot "$CHROOT" /bin/bash -c "
    set -Eeuo pipefail

    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export HOME=/root

    cd /opt/Android/worm-os/upstream

    repo init \
        -u https://github.com/GrapheneOS/platform_manifest.git \
        -b refs/tags/$TAG
"

echo
echo "repo_init=PASS"

echo
echo "=== Verify GrapheneOS manifest signature ==="

chroot "$CHROOT" /bin/bash -c "
    set -Eeuo pipefail

    export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
    export HOME=/root

    cd /opt/Android/worm-os/upstream/.repo/manifests

    git config \
        gpg.ssh.allowedSignersFile \
        /root/.ssh/grapheneos_allowed_signers

    DESCRIPTION=\$(git describe --tags --exact-match)

    echo \"manifest_tag=\$DESCRIPTION\"

    if [ \"\$DESCRIPTION\" != \"$TAG\" ]; then
        echo \"FAIL: expected tag $TAG\"
        exit 1
    fi

    git verify-tag \"\$DESCRIPTION\"
"

echo
echo "signature=PASS"

echo
echo "=== BASELINE ==="

chroot "$CHROOT" /bin/bash -c "
    cd /opt/Android/worm-os/upstream/.repo/manifests

    printf 'commit='
    git rev-parse HEAD

    printf 'tag='
    git describe --tags --exact-match
"

echo
echo "repo_sync=NOT_RUN"
echo "phone=NOT_TOUCHED"
echo "worm_project=NOT_TOUCHED"
echo
echo "WORM_BASELINE_INIT=PASS"
