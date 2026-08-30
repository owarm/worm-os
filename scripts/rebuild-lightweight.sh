#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"
BACKUP="$ROOT/baseline-records"
TAG=2026081300
EXPECTED_COMMIT=84536744f0c06cccbcfa2110e9c937671ddc3278

fail() {
    trap - ERR
    echo
    echo "WORM_LIGHTWEIGHT=FAIL"
    echo "line=$1"
    exit 1
}

trap 'fail $LINENO' ERR

echo "=== worm OS: convert to lightweight checkout ==="
echo

#
# SAFETY
#

if [ "$UPSTREAM" != "/opt/Android/worm-os/upstream" ]; then
    echo "FAIL: unsafe UPSTREAM"
    exit 1
fi

test -d "$UPSTREAM/.repo/manifests/.git" || {
    echo "FAIL: existing GrapheneOS manifest missing"
    exit 1
}

if findmnt -R "$ROOT/build-env" | grep -q .; then
    echo "FAIL: active chroot mounts detected"
    findmnt -R "$ROOT/build-env"
    exit 1
fi

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

echo "baseline_identity=PASS"

#
# RECORD
#

mkdir -p "$BACKUP"

RECORD="$BACKUP/$TAG.txt"

cat > "$RECORD" <<RECORD
project=worm OS
upstream=GrapheneOS
tag=$TAG
manifest_commit=$ACTUAL_COMMIT
signature=previously_verified_PASS
checkout=full-history
conversion_target=depth-1
date=$(date -Iseconds)
RECORD

echo
echo "baseline_record=$RECORD"
cat "$RECORD"

#
# DISK BEFORE
#

echo
echo "=== BEFORE ==="

du -sh "$UPSTREAM"
df -h "$ROOT"

#
# REMOVE ONLY UPSTREAM
#

echo
echo "=== REMOVE OLD SOURCE TREE ==="
echo "target=$UPSTREAM"

rm -rf --one-file-system "$UPSTREAM"

mkdir -p "$UPSTREAM"

echo "old_upstream_removed=PASS"

echo
echo "=== DISK AFTER REMOVAL ==="

df -h "$ROOT"

#
# repo init natively on host
#
# repo/git are needed here. We intentionally use the Debian 12
# repo binary from the chroot without mounting the source tree.
#

REPO="$ROOT/build-env/usr/bin/repo"

test -x "$REPO" || {
    echo "FAIL: repo binary missing"
    exit 1
}

cd "$UPSTREAM"

echo
echo "=== LIGHTWEIGHT REPO INIT ==="

HOME="$ROOT/build-env/root" \
PATH="$ROOT/build-env/usr/bin:/usr/bin:/bin" \
"$REPO" init \
    --depth=1 \
    -u https://github.com/GrapheneOS/platform_manifest.git \
    -b "refs/tags/$TAG"

echo
echo "repo_init_depth1=PASS"

#
# Verify identity immediately
#

ACTUAL_TAG="$(
    git -C "$UPSTREAM/.repo/manifests" \
        describe --tags --exact-match
)"

ACTUAL_COMMIT="$(
    git -C "$UPSTREAM/.repo/manifests" \
        rev-parse HEAD
)"

echo
echo "=== VERIFY NEW MANIFEST ==="
echo "tag=$ACTUAL_TAG"
echo "commit=$ACTUAL_COMMIT"

test "$ACTUAL_TAG" = "$TAG"
test "$ACTUAL_COMMIT" = "$EXPECTED_COMMIT"

echo "manifest_identity=PASS"

#
# Signature verification
#

ALLOWED="$ROOT/build-env/root/.ssh/grapheneos_allowed_signers"

test -s "$ALLOWED" || {
    echo "FAIL: allowed_signers missing"
    exit 1
}

git -C "$UPSTREAM/.repo/manifests" \
    config gpg.ssh.allowedSignersFile "$ALLOWED"

git -C "$UPSTREAM/.repo/manifests" \
    verify-tag "$TAG"

echo
echo "manifest_signature=PASS"

#
# IMPORTANT: STOP BEFORE SYNC
#

echo
echo "=== CURRENT DISK ==="
df -h "$ROOT"

echo
echo "repo_sync=NOT_RUN"
echo "compile=NOT_RUN"
echo "phone=NOT_TOUCHED"
echo "worm_project=NOT_TOUCHED"

echo
echo "WORM_LIGHTWEIGHT_INIT=PASS"
