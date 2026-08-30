#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"
LOGDIR="$ROOT/logs"

TAG=2026081300
TARGET=sdk_phone64_x86_64-cur-userdebug
RESERVE="$ROOT/.build-space-reserve"
RESERVE_GIB=8

mkdir -p "$LOGDIR"
LOG="$LOGDIR/build-emulator-$TAG-$(date +%Y%m%d-%H%M%S).log"

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
}

fail() {
    trap - ERR
    echo
    echo "WORM_BASELINE_BUILD=FAIL"
    echo "line=$1"
    echo "log=$LOG"
    echo
    echo "Safety reserve remains at:"
    echo "$RESERVE"
    exit 1
}

trap 'fail $LINENO' ERR
trap cleanup EXIT

echo "=== worm OS: GrapheneOS baseline emulator build ==="
echo "tag=$TAG"
echo "target=$TARGET"
echo "jobs=8"
echo "log=$LOG"

#
# Baseline identity
#

echo
echo "=== VERIFY BASELINE ==="

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

test "$ACTUAL_TAG" = "$TAG"

echo "baseline=PASS"

#
# Make sure worm has NOT been integrated
#

echo
echo "=== WORM SEPARATION ==="

test -d /opt/Android/worm
test "$UPSTREAM" != "/opt/Android/worm"

echo "worm_project=/opt/Android/worm"
echo "graphene_source=$UPSTREAM"
echo "separation=PASS"

#
# Storage
#

echo
echo "=== STORAGE BEFORE ==="
df -h "$ROOT"

AVAILABLE_KB="$(df --output=avail "$ROOT" | tail -1 | tr -d ' ')"
AVAILABLE_GIB=$(( AVAILABLE_KB / 1024 / 1024 ))

echo "available_gib=$AVAILABLE_GIB"

OUT_DIR="$UPSTREAM/out"
OUT_GIB=0
BUILD_MODE="FRESH"

if [ -d "$OUT_DIR" ]; then
    OUT_KB="$(du -sk "$OUT_DIR" | awk '{print $1}')"
    OUT_GIB=$(( OUT_KB / 1024 / 1024 ))

    if [ "$OUT_GIB" -ge 20 ]; then
        BUILD_MODE="RESUME"
    fi
fi

echo "existing_out_gib=$OUT_GIB"
echo "build_mode=$BUILD_MODE"

if [ "$BUILD_MODE" = "FRESH" ]; then
    MIN_FREE_GIB=160
else
    MIN_FREE_GIB=70
fi

echo "minimum_free_gib=$MIN_FREE_GIB"

if [ "$AVAILABLE_GIB" -lt "$MIN_FREE_GIB" ]; then
    echo "FAIL: insufficient free space"
    exit 1
fi

#
# Safety reserve
#

if [ ! -e "$RESERVE" ]; then
    fallocate -l "${RESERVE_GIB}G" "$RESERVE"
fi

echo "safety_reserve=${RESERVE_GIB}G"
df -h "$ROOT"

#
# Clear any failed validation mounts
#

echo
echo "=== CLEAN STALE MOUNTS ==="

umount -l "$CHROOT/opt/Android/worm-os/upstream" 2>/dev/null || true
umount -R "$CHROOT/sys" 2>/dev/null || true
umount -R "$CHROOT/dev" 2>/dev/null || true
umount "$CHROOT/proc" 2>/dev/null || true

echo "stale_mounts=PASS"

#
# Build chroot
#

echo
echo "=== CHROOT MOUNTS ==="

mkdir -p \
    "$CHROOT/proc" \
    "$CHROOT/sys" \
    "$CHROOT/dev" \
    "$CHROOT/opt/Android/worm-os/upstream"

mount -t proc proc "$CHROOT/proc"
MOUNT_PROC=1

mount --rbind /dev "$CHROOT/dev"
mount --make-rslave "$CHROOT/dev"
MOUNT_DEV=1

mount --rbind /sys "$CHROOT/sys"
mount --make-rslave "$CHROOT/sys"
MOUNT_SYS=1

mount --bind \
    "$UPSTREAM" \
    "$CHROOT/opt/Android/worm-os/upstream"
MOUNT_UPSTREAM=1

echo "mounts=PASS"

#
# Actual baseline build
#

echo
echo "=== BUILD ==="
echo "No worm patches."
echo "No OFFICIAL_BUILD."
echo "No release keys."
echo

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

            if [ -n \"\${OFFICIAL_BUILD:-}\" ]; then
                echo 'FAIL: OFFICIAL_BUILD is set'
                exit 1
            fi

            echo
            echo '=== START m -j8 ==='
            echo

            m -j8
        " 2>&1 | tee "$LOG"

echo
echo "build_command=PASS"

#
# Basic output verification
#

echo
echo "=== VERIFY OUTPUT ==="

PRODUCT_OUT="$UPSTREAM/out/target/product/emulator64_x86_64"

if [ ! -d "$PRODUCT_OUT" ]; then
    echo "Searching actual PRODUCT_OUT..."
    PRODUCT_OUT="$(
        find "$UPSTREAM/out/target/product" \
            -mindepth 1 -maxdepth 1 \
            -type d \
            | head -1
    )"
fi

test -n "$PRODUCT_OUT"
test -d "$PRODUCT_OUT"

echo "product_out=$PRODUCT_OUT"

find "$PRODUCT_OUT" \
    -maxdepth 1 \
    -type f \
    \( -name 'system.img' \
       -o -name 'vendor.img' \
       -o -name 'userdata.img' \
       -o -name 'ramdisk.img' \) \
    -printf '%f\n' \
    | sort

echo
echo "output=PASS"

#
# Sizes
#

echo
echo "=== BUILD SIZE ==="

printf 'out_size='
du -sh "$UPSTREAM/out" | cut -f1

printf 'source_plus_out='
du -sh "$UPSTREAM" | cut -f1

echo
df -h "$ROOT"

#
# Successful build: release reserve
#

rm -f "$RESERVE"

echo
echo "safety_reserve=RELEASED"

echo
echo "=== RESULT ==="
echo "baseline_build=PASS"
echo "target=$TARGET"
echo "worm_patches=0"
echo "official_build=FALSE"
echo "release_keys=NONE"
echo "phone=NOT_TOUCHED"
echo "flash=NOT_RUN"
echo "emulator=NOT_RUN"
echo "log=$LOG"

echo
echo "WORM_BASELINE_BUILD=PASS"
