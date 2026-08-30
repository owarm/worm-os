#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"

TAG=2026081300
EXPECTED_COMMIT=84536744f0c06cccbcfa2110e9c937671ddc3278

MOUNTED=0

cleanup() {
    trap - ERR
    set +e

    if [ "$MOUNTED" = 1 ]; then
        umount "$CHROOT/opt/Android/worm-os/upstream"
    fi

    return 0
}

fail() {
    trap - ERR
    echo
    echo "WORM_LIGHTWEIGHT_INIT=FAIL"
    echo "line=$1"
}

trap 'fail $LINENO' ERR
trap cleanup EXIT

echo "=== worm OS: lightweight repo init ==="

test -f "$CHROOT/etc/debian_version"
test -d "$UPSTREAM"

mkdir -p "$CHROOT/opt/Android/worm-os/upstream"

cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"

#
# upstream deve essere vuoto oppure contenere soltanto
# residui di un repo init fallito
#

echo
echo "=== CLEAN FAILED INIT ==="

rm -rf "$UPSTREAM/.repo"

echo "cleanup=PASS"

#
# Bind mount source tree dentro Debian 12
#

echo
echo "=== MOUNT ==="

mount --bind \
    "$UPSTREAM" \
    "$CHROOT/opt/Android/worm-os/upstream"

MOUNTED=1

echo "mount=PASS"

#
# Repo init --depth=1
#

echo
echo "=== REPO INIT DEPTH 1 ==="

chroot "$CHROOT" /usr/bin/env \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/bash -c "
        set -Eeuo pipefail

        cd /opt/Android/worm-os/upstream

        repo init \
            --depth=1 \
            -u https://github.com/GrapheneOS/platform_manifest.git \
            -b refs/tags/$TAG
    "

echo
echo "repo_init_depth1=PASS"

#
# Manifest identity
#

echo
echo "=== VERIFY MANIFEST ==="

ACTUAL_TAG="$(
    git -C "$UPSTREAM/.repo/manifests" \
        describe --tags --exact-match
)"

ACTUAL_COMMIT="$(
    git -C "$UPSTREAM/.repo/manifests" \
        rev-parse HEAD
)"

echo "tag=$ACTUAL_TAG"
echo "commit=$ACTUAL_COMMIT"

if [ "$ACTUAL_TAG" != "$TAG" ]; then
    echo "FAIL: tag mismatch"
    exit 1
fi

if [ "$ACTUAL_COMMIT" != "$EXPECTED_COMMIT" ]; then
    echo "FAIL: commit mismatch"
    exit 1
fi

echo "manifest_identity=PASS"

#
# Signature verification INSIDE chroot
#

echo
echo "=== VERIFY SIGNATURE ==="

chroot "$CHROOT" /usr/bin/env \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/bash -c "
        set -Eeuo pipefail

        cd /opt/Android/worm-os/upstream/.repo/manifests

        git config \
            gpg.ssh.allowedSignersFile \
            /root/.ssh/grapheneos_allowed_signers

        git verify-tag $TAG
    "

echo
echo "manifest_signature=PASS"

echo
echo "=== DISK ==="

df -h "$ROOT"

echo
echo "repo_sync=NOT_RUN"
echo "compile=NOT_RUN"
echo "phone=NOT_TOUCHED"
echo "worm_project=NOT_TOUCHED"
echo
echo "WORM_LIGHTWEIGHT_INIT=PASS"
