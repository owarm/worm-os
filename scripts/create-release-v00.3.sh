#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"
PRODUCT="$UPSTREAM/out/target/product/frankel"
WEB="$ROOT/web-installer"

VERSION=20260826-dev1
RELEASE="$WEB/releases/frankel/$VERSION"

echo "=== WOS-INSTALLER-V00.3 / RELEASE ==="

test -d "$PRODUCT"
test -f "$PRODUCT/boot.img"
test -f "$PRODUCT/vendor_boot.img"
test -f "$PRODUCT/vbmeta.img"
test -f "$PRODUCT/system.img"

test -f \
  "$PRODUCT/product/app/WormLauncher/WormLauncher.apk"

grep -q \
  '^debug.sf.nobootanimation=1$' \
  "$PRODUCT/system/build.prop"

mkdir -p "$RELEASE"

echo
echo "=== COPY ARTIFACTS ==="

IMAGES="
boot.img
vendor_boot.img
vendor_kernel_boot.img
init_boot.img
dtbo.img
vbmeta.img
vbmeta_system.img
system.img
system_ext.img
product.img
vendor.img
"

COPIED=""

for FILE in $IMAGES; do
    if [ -f "$PRODUCT/$FILE" ]; then
        cp --reflink=auto \
          "$PRODUCT/$FILE" \
          "$RELEASE/$FILE"

        COPIED="$COPIED $FILE"

        echo "$FILE=PASS"
    fi
done

echo
echo "=== REQUIREMENTS ==="

for REQUIRED in \
    boot.img \
    vendor_boot.img \
    vbmeta.img \
    system.img \
    product.img \
    vendor.img
do
    test -f "$RELEASE/$REQUIRED" || {
        echo "FAIL: missing $REQUIRED"
        exit 1
    }

    echo "$REQUIRED=PASS"
done

echo
echo "=== SHA256 ==="

cd "$RELEASE"

sha256sum $COPIED > SHA256SUMS

cat SHA256SUMS

echo
echo "=== MANIFEST ==="

python3 - "$VERSION" "$RELEASE" $COPIED <<'PY'
import hashlib
import json
import pathlib
import sys

version = sys.argv[1]
release = pathlib.Path(sys.argv[2])
files = sys.argv[3:]

artifacts = []

for name in files:
    path = release / name

    h = hashlib.sha256()

    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(8 * 1024 * 1024), b""):
            h.update(chunk)

    artifacts.append({
        "name": name,
        "size": path.stat().st_size,
        "sha256": h.hexdigest(),
    })

manifest = {
    "schema": 1,
    "project": "worm OS",
    "installer": "WOS-INSTALLER-V00.3",
    "channel": "development",

    "device": {
        "name": "Pixel 10",
        "codename": "frankel",
    },

    "build": {
        "version": version,
        "grapheneos_tag": "2026081300",
        "android": "17",
        "build_id": "CP2A.260805.005",
        "security_patch": "2026-08-05",
        "variant": "userdebug",
        "official_build": False,
        "release_keys": False,
    },

    "features": {
        "worm_launcher": True,
        "grapheneos_boot_animation": False,
    },

    "safety": {
        "unlock_enabled": False,
        "flash_enabled": False,
        "lock_enabled": False,
    },

    "artifacts": artifacts,
}

with (release / "manifest.json").open("w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY

cat manifest.json

echo
echo "=== CURRENT POINTER ==="

mkdir -p "$WEB/releases/frankel"

cat > "$WEB/releases/frankel/current.json" <<EOF_CURRENT
{
  "version": "$VERSION",
  "manifest": "/releases/frankel/$VERSION/manifest.json"
}
EOF_CURRENT

echo
echo "=== SIZE ==="
du -sh "$RELEASE"

echo
echo "release=$VERSION"
echo "target=frankel"
echo "unlock=DISABLED"
echo "flash=DISABLED"
echo "lock=DISABLED"

echo
echo "WOS_INSTALLER_V00_3_RELEASE=PASS"
