#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"
OUT="$UPSTREAM/out"
RECORD="$ROOT/baseline-records/emulator-2026081300.txt"

echo "=== WOS-PIXEL10-V00.1 ==="
echo "Preparing workspace for Pixel 10 / frankel"
echo

# Verifica baseline
TAG="$(git -C "$UPSTREAM/.repo/manifests" describe --tags --exact-match)"
COMMIT="$(git -C "$UPSTREAM/.repo/manifests" rev-parse HEAD)"

test "$TAG" = "2026081300"
test "$COMMIT" = "84536744f0c06cccbcfa2110e9c937671ddc3278"

echo "baseline=PASS"

# Verifica output emulator prima di rimuoverlo
PRODUCT="$OUT/target/product/emu64x"

test -f "$PRODUCT/system.img"
test -f "$PRODUCT/vendor.img"
test -f "$PRODUCT/ramdisk.img"
test -f "$PRODUCT/userdata.img"

echo "emulator_output=PASS"

mkdir -p "$ROOT/baseline-records"

cat > "$RECORD" <<RECORD
project=worm OS
upstream=GrapheneOS
tag=$TAG
manifest_commit=$COMMIT

baseline_target=sdk_phone64_x86_64-cur-userdebug
product=emu64x

build=PASS
system_img=PASS
vendor_img=PASS
ramdisk_img=PASS
userdata_img=PASS

worm_patches=0
official_build=false
release_keys=none
phone=untouched

next_device=Pixel 10
next_codename=frankel
RECORD

echo "record=$RECORD"

echo
echo "=== BEFORE ==="
du -sh "$OUT"
df -h "$ROOT"

# Safety: deve essere esattamente l'out della nostra tree.
test "$OUT" = "/opt/Android/worm-os/upstream/out"

echo
echo "=== REMOVE EMULATOR BUILD OUTPUT ==="

rm -rf --one-file-system "$OUT"

echo "out_removed=PASS"

echo
echo "=== AFTER ==="
df -h "$ROOT"

echo
echo "Pixel 10=frankel"
echo "source=UNCHANGED"
echo "worm=UNCHANGED"
echo "phone=NOT_TOUCHED"
echo
echo "WOS_PIXEL10_V00_1_CLEAN=PASS"
