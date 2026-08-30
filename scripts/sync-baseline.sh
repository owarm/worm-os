#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"
LOGDIR="$ROOT/logs"

TAG=2026081300
MIN_FREE_GIB=170

mkdir -p "$LOGDIR"
LOG="$LOGDIR/repo-sync-$TAG-$(date +%Y%m%d-%H%M%S).log"

MOUNTED_PROC=0
MOUNTED_DEV=0
MOUNTED_SYS=0
MOUNTED_UPSTREAM=0

cleanup() {
    trap - ERR
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

    return 0
}

fail() {
    LINE="$1"

    echo
    echo "WORM_SOURCE_SYNC=FAIL"
    echo "line=$LINE"
    echo "log=$LOG"
}

trap 'fail $LINENO' ERR
trap cleanup EXIT

echo "=== worm OS: GrapheneOS source sync ==="
echo "tag=$TAG"
echo "upstream=$UPSTREAM"
echo "log=$LOG"
echo

#
# Baseline verification
#

test -d "$UPSTREAM/.repo" || {
    echo "FAIL: repo init missing"
    exit 1
}

ACTUAL_TAG="$(
    git -C "$UPSTREAM/.repo/manifests" \
        describe --tags --exact-match
)"

if [ "$ACTUAL_TAG" != "$TAG" ]; then
    echo "FAIL: manifest tag mismatch"
    echo "expected=$TAG"
    echo "actual=$ACTUAL_TAG"
    exit 1
fi

echo "manifest_tag=$ACTUAL_TAG"
echo "baseline=PASS"

#
# Storage check
#

AVAILABLE_KB="$(
    df --output=avail "$ROOT" |
    tail -1 |
    tr -d ' '
)"

AVAILABLE_GIB=$(( AVAILABLE_KB / 1024 / 1024 ))

echo
echo "=== STORAGE BEFORE ==="
df -h "$ROOT"
echo
echo "available_gib=$AVAILABLE_GIB"

if [ "$AVAILABLE_GIB" -lt "$MIN_FREE_GIB" ]; then
    echo "FAIL: less than ${MIN_FREE_GIB} GiB free"
    exit 1
fi

echo "storage=PASS"

#
# Chroot preparation
#

mkdir -p \
    "$CHROOT/proc" \
    "$CHROOT/sys" \
    "$CHROOT/opt/Android/worm-os/upstream"

cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"

echo
echo "=== CHROOT MOUNTS ==="

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

if ! mountpoint -q \
    "$CHROOT/opt/Android/worm-os/upstream"
then
    mount --bind \
        "$UPSTREAM" \
        "$CHROOT/opt/Android/worm-os/upstream"

    MOUNTED_UPSTREAM=1
fi

echo "mounts=PASS"

#
# Sync
#

echo
echo "=== REPO SYNC ==="
echo "Starting GrapheneOS source download."
echo

chroot "$CHROOT" /usr/bin/env \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/bash -c '
        set -o pipefail

        cd /opt/Android/worm-os/upstream

        repo sync -j8
    ' 2>&1 | tee "$LOG"

#
# Verification
#

echo
echo "=== VERIFY SOURCE TREE ==="

test -f "$UPSTREAM/build/envsetup.sh" || {
    echo "FAIL: build/envsetup.sh missing"
    exit 1
}

test -d "$UPSTREAM/frameworks/base" || {
    echo "FAIL: frameworks/base missing"
    exit 1
}

test -d "$UPSTREAM/packages/apps" || {
    echo "FAIL: packages/apps missing"
    exit 1
}

echo "build/envsetup.sh=PASS"
echo "frameworks/base=PASS"
echo "packages/apps=PASS"

echo
echo "=== STORAGE AFTER ==="

df -h "$ROOT"

printf 'source_size='
du -sh "$UPSTREAM" | cut -f1

echo
echo "repo_sync=PASS"
echo "compile=NOT_RUN"
echo "phone=NOT_TOUCHED"
echo "worm_project=NOT_TOUCHED"
echo "log=$LOG"
echo
echo "WORM_SOURCE_SYNC=PASS"
