#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"
LOGDIR="$ROOT/logs"

TAG=2026081300
DEVICE=frankel
TARGET=frankel-cur-userdebug

mkdir -p "$LOGDIR"
LOG="$LOGDIR/pixel10-vendor-$TAG-$(date +%Y%m%d-%H%M%S).log"

MOUNT_PROC=0
MOUNT_DEV=0
MOUNT_SYS=0
MOUNT_UPSTREAM=0

cleanup() {
    trap - ERR
    set +e

    echo
    echo "=== CLEANUP ==="
    echo "manual_mounts=NONE"
    echo "cleanup=PASS"
}

fail() {
    trap - ERR
    echo
    echo "WOS_PIXEL10_V00_2_VENDOR=FAIL"
    echo "line=$1"
    echo "log=$LOG"
    exit 1
}

trap 'fail $LINENO' ERR
trap cleanup EXIT

echo "=== WOS-PIXEL10-V00.2 / Vendor ==="
echo "device=$DEVICE"
echo "target=$TARGET"
echo "tag=$TAG"
echo "log=$LOG"

#
# Verify source baseline
#

echo
echo "=== BASELINE ==="

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
# Verify adevtool source exists
#

echo
echo "=== ADEVTOOL SOURCE ==="

test -d "$UPSTREAM/vendor/adevtool"
test -f "$UPSTREAM/vendor/adevtool/package.json"

echo "vendor/adevtool=PASS"

#
# Storage
#

echo
echo "=== STORAGE BEFORE ==="

df -h "$ROOT"

AVAILABLE_KB="$(
    df --output=avail "$ROOT" |
        tail -1 |
        tr -d ' '
)"

AVAILABLE_GIB=$(( AVAILABLE_KB / 1024 / 1024 ))

echo "available_gib=$AVAILABLE_GIB"

if [ "$AVAILABLE_GIB" -lt 140 ]; then
    echo "FAIL: less than 140 GiB free"
    exit 1
fi

echo "storage=PASS"

#
# Remove stale mounts
#

echo
echo "=== NSPAWN MODE ==="
echo "manual_mounts=DISABLED"
echo

echo "=== ADEVTOOL YARN INSTALL ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --register=no \
    --keep-unit \
    --private-users=no \
    --bind="$UPSTREAM:/opt/Android/worm-os/upstream" \
    -u wormbuild \
    /usr/bin/env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        SHELL=/bin/bash \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --noprofile --norc -c '
            set -Eeuo pipefail

            cd /opt/Android/worm-os/upstream

            node --version
            yarnpkg --version

            yarnpkg --cwd vendor/adevtool/ install
        ' 2>&1 | tee "$LOG"

echo
echo "adevtool_dependencies=PASS"

#
# Generate Pixel 10 vendor files
#

echo
echo "=== ADEVTOOL GENERATE FRANKEL ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --register=no \
    --keep-unit \
    --private-users=no \
    --bind="$UPSTREAM:/opt/Android/worm-os/upstream" \
    -u wormbuild \
    /usr/bin/env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        SHELL=/bin/bash \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --noprofile --norc -c "
            set -Eeuo pipefail

            cd /opt/Android/worm-os/upstream

            source build/envsetup.sh

            echo "adevtool_runner=vendor/adevtool/bin/run"

            test -x vendor/adevtool/bin/run

            vendor/adevtool/bin/run generate-all -d $DEVICE
        " 2>&1 | tee -a "$LOG"

echo
echo "adevtool_generate=PASS"

#
# Check generated vendor tree
#

echo
echo "=== VERIFY VENDOR OUTPUT ==="

test -d "$UPSTREAM/vendor/google_devices"

du -sh "$UPSTREAM/vendor/google_devices"

echo "vendor_google_devices=PASS"

#
# Validate Pixel 10 target
#

echo
echo "=== LUNCH FRANKEL ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --register=no \
    --keep-unit \
    --private-users=no \
    --bind="$UPSTREAM:/opt/Android/worm-os/upstream" \
    -u wormbuild \
    /usr/bin/env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        SHELL=/bin/bash \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --noprofile --norc -c "
            set -Eeuo pipefail

            cd /opt/Android/worm-os/upstream

            source build/envsetup.sh

            lunch '$TARGET'

            echo
            echo '=== PIXEL 10 TARGET ==='

            printf 'TARGET_PRODUCT=%s\n' \"\${TARGET_PRODUCT:-}\"
            printf 'TARGET_BUILD_VARIANT=%s\n' \"\${TARGET_BUILD_VARIANT:-}\"
            printf 'ANDROID_BUILD_TOP=%s\n' \"\${ANDROID_BUILD_TOP:-}\"

            test \"\${TARGET_PRODUCT:-}\" = 'frankel'
            test \"\${TARGET_BUILD_VARIANT:-}\" = 'userdebug'

            if [ -n \"\${OFFICIAL_BUILD:-}\" ]; then
                echo 'FAIL: OFFICIAL_BUILD unexpectedly set'
                exit 1
            fi

            echo 'lunch_frankel=PASS'
            echo 'OFFICIAL_BUILD=UNSET'
        "

echo
echo "=== STORAGE AFTER ==="

df -h "$ROOT"

printf 'vendor_size='
du -sh "$UPSTREAM/vendor/google_devices" | cut -f1

echo
echo "=== RESULT ==="
echo "device=Pixel_10"
echo "codename=frankel"
echo "target=$TARGET"
echo "vendor_generation=PASS"
echo "compile=NOT_RUN"
echo "release_keys=NOT_CREATED"
echo "phone=NOT_TOUCHED"
echo "flash=NOT_RUN"
echo "log=$LOG"

echo
echo "WOS_PIXEL10_V00_2_VENDOR=PASS"
