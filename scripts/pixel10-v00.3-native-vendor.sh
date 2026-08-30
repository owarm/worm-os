#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"
TOOLCHAIN="$ROOT/toolchain"
LOGDIR="$ROOT/logs"

USER_NAME=wormbuild
DEVICE=frankel
TAG=2026081300

NODE_VERSION=v24.19.0
NODE_DIR="$TOOLCHAIN/node-$NODE_VERSION-linux-x64"
NODE_URL="https://nodejs.org/download/release/$NODE_VERSION"

mkdir -p "$TOOLCHAIN" "$LOGDIR"

LOG="$LOGDIR/pixel10-native-vendor-$TAG-$(date +%Y%m%d-%H%M%S).log"

fail() {
    trap - ERR
    echo
    echo "WOS_PIXEL10_V00_3=FAIL"
    echo "line=$1"
    echo "log=$LOG"
    exit 1
}

trap 'fail $LINENO' ERR

echo "=== WOS-PIXEL10-V00.3 ==="
echo "backend=Debian13-native"
echo "device=$DEVICE"
echo "log=$LOG"

#
# Baseline
#

echo
echo "=== BASELINE ==="

ACTUAL_TAG="$(
    git -C "$UPSTREAM/.repo/manifests" \
        describe --tags --exact-match
)"

echo "tag=$ACTUAL_TAG"

test "$ACTUAL_TAG" = "$TAG"
test -d "$UPSTREAM/vendor/adevtool"

echo "baseline=PASS"

#
# Build user
#

echo
echo "=== BUILD USER ==="

id "$USER_NAME"

OWNER="$(stat -c '%u:%g' "$UPSTREAM")"
echo "source_owner=$OWNER"

test "$OWNER" = "1000:1000"

echo "build_user=PASS"

#
# Node 24 local toolchain
#

echo
echo "=== NODE 24 ==="

if [ ! -x "$NODE_DIR/bin/node" ]; then

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' RETURN

    cd "$TMP"

    curl -fLO \
        "$NODE_URL/node-$NODE_VERSION-linux-x64.tar.xz"

    curl -fLO \
        "$NODE_URL/SHASUMS256.txt"

    grep \
        " node-$NODE_VERSION-linux-x64.tar.xz\$" \
        SHASUMS256.txt \
        > node.sha256

    sha256sum -c node.sha256

    tar -xJf \
        "node-$NODE_VERSION-linux-x64.tar.xz" \
        -C "$TOOLCHAIN"

    cd /
    rm -rf "$TMP"
fi

"$NODE_DIR/bin/node" --version

test "$("$NODE_DIR/bin/node" --version)" = "$NODE_VERSION"

echo "node24=PASS"

#
# Yarn
#

echo
echo "=== YARN ==="

YARN=/usr/bin/yarnpkg

test -x "$YARN"

"$YARN" --version

echo "yarn=PASS"

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

if [ "$AVAILABLE_GIB" -lt 100 ]; then
    echo "FAIL: less than 100 GiB free"
    exit 1
fi

echo "storage=PASS"

#
# Yarn dependencies as wormbuild
#

echo
echo "=== ADEVTOOL DEPENDENCIES ==="

sudo -u "$USER_NAME" \
    env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        PATH="$NODE_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        "$YARN" \
            --cwd "$UPSTREAM/vendor/adevtool" \
            install \
    2>&1 | tee "$LOG"

echo "adevtool_dependencies=PASS"

#
# Native nsjail sanity check
#

echo
echo "=== NSJAIL SANITY ==="

sudo -u "$USER_NAME" \
    env \
        HOME=/home/wormbuild \
        PATH="$NODE_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        "$UPSTREAM/prebuilts/build-tools/linux-x86/bin/nsjail" \
            -H android-build \
            -e \
            -u nobody \
            -g nogroup \
            -B / \
            --disable_clone_newcgroup \
            -- \
            /bin/bash -c '
                test "$(hostname)" = android-build
                echo "NSJAIL_NATIVE=PASS"
            '

#
# adevtool
#

echo
echo "=== GENERATE FRANKEL ==="

sudo -u "$USER_NAME" \
    env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        SHELL=/bin/bash \
        PATH="$NODE_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        /bin/bash --noprofile --norc -c "
            set -Eeuo pipefail

            cd '$UPSTREAM'

            source build/envsetup.sh

            echo 'runner=vendor/adevtool/bin/run'

            vendor/adevtool/bin/run \
                generate-all \
                -d '$DEVICE'
        " \
    2>&1 | tee -a "$LOG"

echo
echo "adevtool_generate=PASS"

#
# Verify vendor
#

echo
echo "=== VERIFY VENDOR ==="

test -d "$UPSTREAM/vendor/google_devices"

printf 'vendor_size='
du -sh "$UPSTREAM/vendor/google_devices" |
    cut -f1

echo "vendor_google_devices=PASS"

#
# Validate frankel lunch
#

echo
echo "=== LUNCH FRANKEL ==="

sudo -u "$USER_NAME" \
    env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        SHELL=/bin/bash \
        PATH="$NODE_DIR/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
        /bin/bash --noprofile --norc -c "
            set -Eeuo pipefail

            cd '$UPSTREAM'

            source build/envsetup.sh

            lunch frankel-cur-userdebug

            echo
            echo 'TARGET_PRODUCT='\${TARGET_PRODUCT:-}
            echo 'TARGET_BUILD_VARIANT='\${TARGET_BUILD_VARIANT:-}

            test \"\${TARGET_PRODUCT:-}\" = frankel
            test \"\${TARGET_BUILD_VARIANT:-}\" = userdebug

            echo 'lunch_frankel=PASS'
        "

echo
echo "=== STORAGE AFTER ==="

df -h "$ROOT"

echo
echo "=== RESULT ==="
echo "backend=Debian13-native"
echo "device=Pixel_10"
echo "codename=frankel"
echo "vendor_generation=PASS"
echo "compile=NOT_RUN"
echo "phone=NOT_TOUCHED"
echo "flash=NOT_RUN"
echo "log=$LOG"

echo
echo "WOS_PIXEL10_V00_3=PASS"
