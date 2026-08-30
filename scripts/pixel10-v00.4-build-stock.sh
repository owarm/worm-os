#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"
LOGDIR="$ROOT/logs"

BUILD_USER=wormbuild
TAG=2026081300
TARGET=frankel-cur-userdebug
PRODUCT=frankel
JOBS=8

RESERVE="$ROOT/.pixel10-build-reserve"
RESERVE_GIB=4

mkdir -p "$LOGDIR"

LOG="$LOGDIR/pixel10-stock-$TAG-$(date +%Y%m%d-%H%M%S).log"

BUILD_SUCCESS=0


cleanup() {
    trap - ERR
    set +e

    if [ "$BUILD_SUCCESS" = 1 ]; then
        rm -f "$RESERVE"
        echo
        echo "safety_reserve=RELEASED"
    fi

    return 0
}


fail() {
    trap - ERR

    echo
    echo "WOS_PIXEL10_V00_4=FAIL"
    echo "line=$1"
    echo "log=$LOG"

    if [ -e "$RESERVE" ]; then
        echo
        echo "Emergency space reserve still available:"
        ls -lh "$RESERVE"
        echo
        echo "To release it:"
        echo "rm -f $RESERVE"
    fi

    exit 1
}


trap 'fail $LINENO' ERR
trap cleanup EXIT


echo "=== WOS-PIXEL10-V00.4 ==="
echo "build=stock-development"
echo "device=Pixel_10"
echo "codename=$PRODUCT"
echo "target=$TARGET"
echo "jobs=$JOBS"
echo "backend=Debian13-native"
echo "log=$LOG"


#
# Baseline
#

echo
echo "=== BASELINE ==="

test -d "$UPSTREAM/.repo"
test -f "$UPSTREAM/build/envsetup.sh"

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
# Pixel 10 vendor files
#

echo
echo "=== PIXEL 10 VENDOR ==="

test -d "$UPSTREAM/vendor/google_devices"

VENDOR_SIZE="$(
    du -sh "$UPSTREAM/vendor/google_devices" |
        cut -f1
)"

echo "vendor_google_devices=$VENDOR_SIZE"

echo "vendor=PASS"


#
# worm separation
#

echo
echo "=== WORM SEPARATION ==="

test -d /opt/Android/worm
test "$UPSTREAM" != "/opt/Android/worm"

if [ -L "$UPSTREAM/packages/apps/worm" ] 2>/dev/null; then
    echo "FAIL: worm already linked into GrapheneOS"
    exit 1
fi

echo "worm_project=/opt/Android/worm"
echo "worm_patches=0"
echo "integration=NONE"
echo "separation=PASS"


#
# Build user
#

echo
echo "=== BUILD USER ==="

id "$BUILD_USER"

OWNER="$(
    stat -c '%u:%g' "$UPSTREAM"
)"

echo "source_owner=$OWNER"

test "$OWNER" = "1000:1000"

echo "build_user=PASS"


#
# Native host dependencies
#

echo
echo "=== HOST TOOLS ==="

TOOLS="
git
repo
python3
java
yarnpkg
rsync
zip
unzip
git-lfs
gperf
openssl
ssh-keygen
curl
"

for TOOL in $TOOLS; do

    if command -v "$TOOL" >/dev/null 2>&1; then
        printf '%-12s PASS\n' "$TOOL"
    else
        printf '%-12s MISSING\n' "$TOOL"
        exit 1
    fi

done

echo "host_tools=PASS"


#
# nsjail sanity
#

echo
echo "=== NSJAIL ==="

NSJAIL="$UPSTREAM/prebuilts/build-tools/linux-x86/bin/nsjail"

test -x "$NSJAIL"

sudo -u "$BUILD_USER" \
    "$NSJAIL" \
        -H android-build \
        -e \
        -u nobody \
        -g nogroup \
        -B / \
        --disable_clone_newcgroup \
        -- \
        /bin/bash -c '
            set -e

            test "$(hostname)" = android-build

            echo "NSJAIL_NATIVE=PASS"
        '

echo "nsjail=PASS"


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

OUT_DIR="$UPSTREAM/out"
OUT_GIB=0
BUILD_MODE="FRESH"

if [ -d "$OUT_DIR" ]; then
    OUT_KB="$(du -sk "$OUT_DIR" | awk '{print $1}')"
    OUT_GIB=$(( OUT_KB / 1024 / 1024 ))

    if [ "$OUT_GIB" -ge 40 ]; then
        BUILD_MODE="RESUME"
    fi
fi

echo "existing_out_gib=$OUT_GIB"
echo "build_mode=$BUILD_MODE"

if [ "$BUILD_MODE" = "FRESH" ]; then
    MIN_FREE_GIB=140
else
    MIN_FREE_GIB=45
fi

echo "minimum_free_gib=$MIN_FREE_GIB"

if [ "$AVAILABLE_GIB" -lt "$MIN_FREE_GIB" ]; then
    echo "FAIL: insufficient free space"
    exit 1
fi

echo "storage=PASS"


#
# Safety reserve
#

echo
echo "=== SAFETY RESERVE ==="

rm -f "$RESERVE"

fallocate \
    -l "${RESERVE_GIB}G" \
    "$RESERVE"

echo "reserve=${RESERVE_GIB}G"
df -h "$ROOT"


#
# Validate lunch before actual build
#

echo
echo "=== VALIDATE FRANKEL ==="

sudo -u "$BUILD_USER" \
    env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        SHELL=/bin/bash \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --noprofile --norc -c "
            set -Eeuo pipefail

            cd '$UPSTREAM'

            source build/envsetup.sh

            lunch '$TARGET'

            echo
            echo TARGET_PRODUCT=\${TARGET_PRODUCT:-}
            echo TARGET_BUILD_VARIANT=\${TARGET_BUILD_VARIANT:-}

            test \"\${TARGET_PRODUCT:-}\" = frankel
            test \"\${TARGET_BUILD_VARIANT:-}\" = userdebug

            if [ -n \"\${OFFICIAL_BUILD:-}\" ]; then
                echo 'FAIL: OFFICIAL_BUILD unexpectedly set'
                exit 1
            fi

            echo 'lunch_frankel=PASS'
            echo 'OFFICIAL_BUILD=UNSET'
        "

echo "target_validation=PASS"


#
# Build
#

echo
echo "========================================"
echo "=== FIRST STOCK PIXEL 10 BUILD       ==="
echo "========================================"
echo
echo "worm_patches=0"
echo "official_build=false"
echo "release_keys=none"
echo "flash=false"
echo

sudo -u "$BUILD_USER" \
    env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        SHELL=/bin/bash \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --noprofile --norc -c "
            set -Eeuo pipefail

            cd '$UPSTREAM'

            source build/envsetup.sh

            lunch '$TARGET'

            if [ -n \"\${OFFICIAL_BUILD:-}\" ]; then
                echo 'FAIL: OFFICIAL_BUILD is set'
                exit 1
            fi

            echo
            echo '=== START m -j$JOBS ==='
            echo

            m -j$JOBS
        " \
    2>&1 | tee "$LOG"


echo
echo "build_command=PASS"


#
# Output verification
#

echo
echo "=== VERIFY PIXEL 10 OUTPUT ==="

PRODUCT_OUT="$UPSTREAM/out/target/product/frankel"

test -d "$PRODUCT_OUT"

echo "product_out=$PRODUCT_OUT"

REQUIRED_IMAGES="
boot.img
system.img
vendor.img
vendor_boot.img
vbmeta.img
"

for IMAGE in $REQUIRED_IMAGES; do

    if [ -f "$PRODUCT_OUT/$IMAGE" ]; then
        printf '%-20s PASS\n' "$IMAGE"
    else
        printf '%-20s MISSING\n' "$IMAGE"
        exit 1
    fi

done


echo
echo "=== OTHER IMAGES ==="

find "$PRODUCT_OUT" \
    -maxdepth 1 \
    -type f \
    -name '*.img' \
    -printf '%f\n' \
    | sort


echo
echo "output=PASS"


#
# Build information
#

echo
echo "=== BUILD INFO ==="

if [ -f "$PRODUCT_OUT/system/build.prop" ]; then

    grep -E \
        '^(ro.build.id|ro.build.version.release|ro.build.version.security_patch|ro.product.device)=' \
        "$PRODUCT_OUT/system/build.prop" \
        || true

fi


#
# Size / disk
#

echo
echo "=== BUILD SIZE ==="

printf 'out_size='
du -sh "$UPSTREAM/out" |
    cut -f1

printf 'product_out_size='
du -sh "$PRODUCT_OUT" |
    cut -f1

echo
echo "=== STORAGE AFTER BUILD ==="

df -h "$ROOT"


#
# Record milestone
#

RECORD="$ROOT/baseline-records/pixel10-stock-$TAG.txt"

cat > "$RECORD" <<RECORD
project=worm OS
milestone=WOS-PIXEL10-V00.4

upstream=GrapheneOS
tag=$TAG
manifest_commit=$ACTUAL_COMMIT

device=Pixel 10
codename=frankel
target=frankel-cur-userdebug

backend=Debian13-native
build=PASS

worm_patches=0
worm_integration=none

official_build=false
release_keys=none

phone=untouched
flash=not_run

log=$LOG
RECORD

chown 1000:1000 "$RECORD"

echo
echo "record=$RECORD"

BUILD_SUCCESS=1


echo
echo "========================================"
echo "=== RESULT                           ==="
echo "========================================"

echo "pixel10_stock_build=PASS"
echo "device=Pixel_10"
echo "codename=frankel"
echo "target=$TARGET"
echo "worm_patches=0"
echo "official_build=FALSE"
echo "release_keys=NONE"
echo "phone=NOT_TOUCHED"
echo "flash=NOT_RUN"
echo "log=$LOG"

echo
echo "WOS_PIXEL10_V00_4=PASS"
