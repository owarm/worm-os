#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
PRODUCT="$ROOT/upstream/out/target/product/frankel"
WEB="$ROOT/web-installer"

VERSION=20260826-dev1
RELEASE="$WEB/releases/frankel/$VERSION"

INNER="$RELEASE/image-frankel-$VERSION.zip"
OUTER="$RELEASE/frankel-install-$VERSION.zip"

echo "=== WOS-INSTALLER-V00.4A ==="
echo "device=frankel"
echo "version=$VERSION"

mkdir -p "$RELEASE"

#
# Required files
#

FILES="
android-info.txt
super_empty.img
boot.img
init_boot.img
dtbo.img
vendor_kernel_boot.img
pvmfw.img
vbmeta.img
system.img
system_dlkm.img
system_ext.img
product.img
vendor.img
vendor_dlkm.img
"

echo
echo "=== VERIFY INPUT ==="

for f in $FILES; do
    test -f "$PRODUCT/$f" || {
        echo "FAIL: missing $f"
        exit 1
    }

    echo "$f=PASS"
done

test -f "$PRODUCT/bootloader.img"
test -f "$PRODUCT/radio.img"

echo "bootloader.img=PASS"
echo "radio.img=PASS"

#
# Build inner image ZIP.
#
# Use store (-0): images are already compressed/sparse-like
# and avoiding deflate significantly reduces browser extraction cost.
#

echo
echo "=== BUILD IMAGE ZIP ==="

rm -f "$INNER" "$OUTER"

(
    cd "$PRODUCT"

    zip -0 \
        "$INNER" \
        $FILES
)

test -s "$INNER"

echo "inner_zip=PASS"

#
# Factory outer ZIP
#

echo
echo "=== BUILD FACTORY ZIP ==="

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp "$PRODUCT/bootloader.img" "$TMP/"
cp "$PRODUCT/radio.img" "$TMP/"
cp "$INNER" "$TMP/"

(
    cd "$TMP"

    zip -0 \
        "$OUTER" \
        bootloader.img \
        radio.img \
        "$(basename "$INNER")"
)

test -s "$OUTER"

echo "factory_zip=PASS"

#
# Verify layout
#

echo
echo "=== VERIFY LAYOUT ==="

unzip -l "$OUTER"

echo
echo "--- nested ---"

unzip -p \
    "$OUTER" \
    "$(basename "$INNER")" \
    > "$TMP/image.zip"

unzip -l "$TMP/image.zip"

for f in $FILES; do
    unzip -Z1 "$TMP/image.zip" |
        grep -qx "$f"
done

echo "factory_layout=PASS"

#
# Hashes
#

echo
echo "=== SHA256 ==="

sha256sum \
    "$OUTER" \
    > "$OUTER.sha256"

cat "$OUTER.sha256"

SIZE="$(stat -c %s "$OUTER")"
SHA="$(sha256sum "$OUTER" | awk '{print $1}')"

#
# Extend current manifest
#

python3 - \
    "$RELEASE/manifest.json" \
    "$(basename "$OUTER")" \
    "$SIZE" \
    "$SHA" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
name = sys.argv[2]
size = int(sys.argv[3])
sha = sys.argv[4]

data = json.loads(path.read_text())

data["factory_package"] = {
    "name": name,
    "size": size,
    "sha256": sha,
    "format": "fastboot.js-factory-zip",
    "wipe": True,
}

data["safety"]["unlock_enabled"] = False
data["safety"]["flash_enabled"] = False
data["safety"]["lock_enabled"] = False

path.write_text(
    json.dumps(data, indent=2) + "\n"
)
PY

echo
echo "=== RELEASE ==="
echo "factory=$(basename "$OUTER")"
echo "size=$SIZE"
echo "sha256=$SHA"

echo
echo "unlock=DISABLED"
echo "flash=DISABLED"
echo "lock=DISABLED"

echo
echo "WOS_INSTALLER_V00_4A=PASS"
