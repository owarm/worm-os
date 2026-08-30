#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"

TARGET="sdk_phone64_x86_64-cur-userdebug"
TAG="2026081300"

MOUNT_PROC=0
MOUNT_DEV=0
MOUNT_SYS=0
MOUNT_UPSTREAM=0

cleanup() {
    trap - ERR
    set +e

    echo
    echo "=== CLEANUP ==="

    if [ "$MOUNT_UPSTREAM" = 1 ]; then
        umount "$CHROOT/opt/Android/worm-os/upstream" 2>/dev/null ||
            umount -l "$CHROOT/opt/Android/worm-os/upstream" 2>/dev/null || true
    fi

    if [ "$MOUNT_SYS" = 1 ]; then
        umount -R "$CHROOT/sys" 2>/dev/null ||
            umount -l "$CHROOT/sys" 2>/dev/null || true
    fi

    if [ "$MOUNT_DEV" = 1 ]; then
        umount -R "$CHROOT/dev" 2>/dev/null ||
            umount -l "$CHROOT/dev" 2>/dev/null || true
    fi

    if [ "$MOUNT_PROC" = 1 ]; then
        umount "$CHROOT/proc" 2>/dev/null ||
            umount -l "$CHROOT/proc" 2>/dev/null || true
    fi

    echo "cleanup=PASS"
    return 0
}

fail() {
    trap - ERR
    echo
    echo "WORM_BUILD_TARGET=FAIL"
    echo "line=$1"
    exit 1
}

trap 'fail $LINENO' ERR
trap cleanup EXIT

echo "=== worm OS: validate GrapheneOS build target ==="
echo "tag=$TAG"
echo "target=$TARGET"

echo
echo "=== SOURCE ==="

test -f "$UPSTREAM/build/envsetup.sh"
test -d "$UPSTREAM/.repo"

ACTUAL_TAG="$(
    git -C "$UPSTREAM/.repo/manifests" \
        describe --tags --exact-match
)"

echo "manifest_tag=$ACTUAL_TAG"

test "$ACTUAL_TAG" = "$TAG"

echo "source=PASS"

echo
echo "=== STORAGE ==="

df -h "$ROOT"

AVAILABLE_KB="$(
    df --output=avail "$ROOT" |
        tail -1 |
        tr -d ' '
)"

AVAILABLE_GIB=$(( AVAILABLE_KB / 1024 / 1024 ))

echo "available_gib=$AVAILABLE_GIB"

if [ "$AVAILABLE_GIB" -lt 150 ]; then
    echo "FAIL: less than 150 GiB available"
    exit 1
fi

echo "storage=PASS"

echo
echo "=== CLEAN STALE MOUNTS ==="

# Ripulisce eventuali mount lasciati dal tentativo precedente.
umount -l "$CHROOT/opt/Android/worm-os/upstream" 2>/dev/null || true
umount -R "$CHROOT/sys" 2>/dev/null || true
umount -R "$CHROOT/dev" 2>/dev/null || true
umount "$CHROOT/proc" 2>/dev/null || true

echo "stale_mounts=PASS"

echo
echo "=== CHROOT MOUNTS ==="

mkdir -p \
    "$CHROOT/proc" \
    "$CHROOT/sys" \
    "$CHROOT/dev" \
    "$CHROOT/opt/Android/worm-os/upstream"

# /proc
mount -t proc proc "$CHROOT/proc"
MOUNT_PROC=1

# /dev + /dev/pts + /dev/fd
mount --rbind /dev "$CHROOT/dev"
mount --make-rslave "$CHROOT/dev"
MOUNT_DEV=1

# /sys
mount --rbind /sys "$CHROOT/sys"
mount --make-rslave "$CHROOT/sys"
MOUNT_SYS=1

# GrapheneOS source
mount --bind \
    "$UPSTREAM" \
    "$CHROOT/opt/Android/worm-os/upstream"

MOUNT_UPSTREAM=1

echo "mounts=PASS"

echo
echo "=== VERIFY CHROOT KERNEL FS ==="

chroot "$CHROOT" /bin/bash -c '
    set -e

    test -r /proc/cpuinfo
    test -e /dev/null
    test -e /dev/fd
    test -d /sys

    echo "/proc=PASS"
    echo "/dev=PASS"
    echo "/dev/fd=PASS"
    echo "/sys=PASS"
'

echo
echo "=== ENVSETUP + LUNCH ==="

chroot "$CHROOT" \
    /usr/bin/env \
        HOME=/root \
        USER=root \
        LOGNAME=root \
        SHELL=/bin/bash \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --noprofile --norc -c "
            set -Eeuo pipefail

            cd /opt/Android/worm-os/upstream

            source build/envsetup.sh

            lunch '$TARGET'

            echo
            echo '=== SELECTED BUILD ==='

            printf 'TARGET_PRODUCT=%s\n' \"\${TARGET_PRODUCT:-}\"
            printf 'TARGET_BUILD_VARIANT=%s\n' \"\${TARGET_BUILD_VARIANT:-}\"
            printf 'TARGET_ARCH=%s\n' \"\${TARGET_ARCH:-}\"
            printf 'TARGET_ARCH_VARIANT=%s\n' \"\${TARGET_ARCH_VARIANT:-}\"
            printf 'ANDROID_BUILD_TOP=%s\n' \"\${ANDROID_BUILD_TOP:-}\"

            test \"\${TARGET_PRODUCT:-}\" = 'sdk_phone64_x86_64'
            test \"\${TARGET_BUILD_VARIANT:-}\" = 'userdebug'

            echo
            echo 'lunch=PASS'

            if [ -n \"\${OFFICIAL_BUILD:-}\" ]; then
                echo 'FAIL: OFFICIAL_BUILD unexpectedly set'
                exit 1
            fi

            echo 'OFFICIAL_BUILD=UNSET'
            echo 'compile=NOT_RUN'
        "

echo
echo "=== RESULT ==="
echo "envsetup=PASS"
echo "target=$TARGET"
echo "compile=NOT_RUN"
echo "official_build=FALSE"
echo "release_keys=NOT_CREATED"
echo "phone=NOT_TOUCHED"
echo "worm_project=NOT_TOUCHED"

echo
echo "WORM_BUILD_TARGET=PASS"
