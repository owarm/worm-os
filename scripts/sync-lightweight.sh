#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"
LOGDIR="$ROOT/logs"

TAG=2026081300
EXPECTED_COMMIT=84536744f0c06cccbcfa2110e9c937671ddc3278

mkdir -p "$LOGDIR"
LOG="$LOGDIR/repo-sync-lightweight-$TAG-$(date +%Y%m%d-%H%M%S).log"

MOUNTED=0
SUCCESS=0

cleanup() {
    trap - ERR
    set +e

    if [ "$MOUNTED" = 1 ]; then
        umount "$CHROOT/opt/Android/worm-os/upstream"
    fi

    return 0
}

on_error() {
    local line="$1"

    trap - ERR

    echo
    echo "WORM_LIGHTWEIGHT_SYNC=FAIL"
    echo "line=$line"
    echo "log=$LOG"

    exit 1
}

trap 'on_error $LINENO' ERR
trap cleanup EXIT

echo "=== worm OS: lightweight source sync ==="
echo "tag=$TAG"
echo "upstream=$UPSTREAM"
echo "log=$LOG"

#
# Verify baseline before downloading
#

echo
echo "=== VERIFY BASELINE ==="

test -d "$UPSTREAM/.repo/manifests/.git"

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
test "$ACTUAL_COMMIT" = "$EXPECTED_COMMIT"

echo "baseline=PASS"

#
# Verify this is really shallow
#

echo
echo "=== VERIFY LIGHTWEIGHT MODE ==="

SHALLOW="$(
    git -C "$UPSTREAM/.repo/manifests" \
        rev-parse --is-shallow-repository
)"

echo "manifest_shallow=$SHALLOW"

if [ "$SHALLOW" != "true" ]; then
    echo "FAIL: manifest is not shallow"
    exit 1
fi

echo "lightweight=PASS"

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

if [ "$AVAILABLE_GIB" -lt 200 ]; then
    echo "FAIL: expected at least 200 GiB free before sync"
    exit 1
fi

echo "storage=PASS"

#
# Chroot bind
#

echo
echo "=== CHROOT ==="

mkdir -p "$CHROOT/opt/Android/worm-os/upstream"

cp -L /etc/resolv.conf "$CHROOT/etc/resolv.conf"

if mountpoint -q "$CHROOT/opt/Android/worm-os/upstream"; then
    echo "FAIL: stale upstream mount already exists"
    exit 1
fi

mount --bind \
    "$UPSTREAM" \
    "$CHROOT/opt/Android/worm-os/upstream"

MOUNTED=1

echo "mount=PASS"

#
# Sync
#

echo
echo "=== REPO SYNC -j8 ==="
echo

chroot "$CHROOT" /usr/bin/env \
    HOME=/root \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/bash -c '
        set -Eeuo pipefail
        cd /opt/Android/worm-os/upstream
        repo sync -j8
    ' 2>&1 | tee "$LOG"

echo
echo "repo_sync_command=PASS"

#
# Source verification
#

echo
echo "=== VERIFY SOURCE TREE ==="

test -f "$UPSTREAM/build/envsetup.sh"
test -d "$UPSTREAM/frameworks/base"
test -d "$UPSTREAM/packages/apps"
test -d "$UPSTREAM/system/core"

echo "build/envsetup.sh=PASS"
echo "frameworks/base=PASS"
echo "packages/apps=PASS"
echo "system/core=PASS"

#
# Baseline must still be identical
#

POST_TAG="$(
    git -C "$UPSTREAM/.repo/manifests" \
        describe --tags --exact-match
)"

POST_COMMIT="$(
    git -C "$UPSTREAM/.repo/manifests" \
        rev-parse HEAD
)"

test "$POST_TAG" = "$TAG"
test "$POST_COMMIT" = "$EXPECTED_COMMIT"

echo "baseline_after_sync=PASS"

#
# Measure actual checkout
#

echo
echo "=== SIZE ==="

printf 'upstream_total='
du -sh "$UPSTREAM" | cut -f1

printf 'worktree_without_repo='
du -sh --exclude=.repo "$UPSTREAM" | cut -f1

printf 'project_objects='
du -sh "$UPSTREAM/.repo/project-objects" | cut -f1

printf 'repo_projects='
du -sh "$UPSTREAM/.repo/projects" | cut -f1

echo
echo "=== STORAGE AFTER ==="
df -h "$ROOT"

SUCCESS=1

echo
echo "repo_sync=PASS"
echo "checkout=LIGHTWEIGHT_DEPTH_1"
echo "compile=NOT_RUN"
echo "phone=NOT_TOUCHED"
echo "worm_project=NOT_TOUCHED"
echo "log=$LOG"
echo
echo "WORM_LIGHTWEIGHT_SYNC=PASS"
