#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
PRODUCT="$ROOT/upstream/out/target/product/frankel"
RELEASE="$ROOT/web-installer/releases/frankel/20260826-dev1"
DEST="$RELEASE/images"

echo "=== WOS-INSTALLER-V00.9 / IMAGES ==="

mkdir -p "$DEST"

FILES=(
  bootloader.img
  radio.img
  super_empty.img
  boot.img
  init_boot.img
  dtbo.img
  vendor_kernel_boot.img
  pvmfw.img
  vendor_boot.img
  vbmeta.img
  system.img
  system_dlkm.img
  system_ext.img
  product.img
  vendor.img
  vendor_dlkm.img
)

for f in "${FILES[@]}"; do
    test -f "$PRODUCT/$f" || {
        echo "FAIL: missing $f"
        exit 1
    }

    cp --reflink=auto \
      "$PRODUCT/$f" \
      "$DEST/$f"

    echo "$f=PASS"
done

echo
echo "=== IMAGE MANIFEST ==="

python3 - "$DEST" "$RELEASE" <<'PY'
import hashlib
import json
import pathlib
import sys

images = pathlib.Path(sys.argv[1])
release = pathlib.Path(sys.argv[2])

names = [
    "bootloader.img",
    "radio.img",
    "super_empty.img",
    "boot.img",
    "init_boot.img",
    "dtbo.img",
    "vendor_kernel_boot.img",
    "pvmfw.img",
    "vendor_boot.img",
    "vbmeta.img",
    "system.img",
    "system_dlkm.img",
    "system_ext.img",
    "product.img",
    "vendor.img",
    "vendor_dlkm.img",
]

out = []

for name in names:
    p = images / name

    h = hashlib.sha256()

    with p.open("rb") as f:
        for chunk in iter(
            lambda: f.read(8 * 1024 * 1024),
            b""
        ):
            h.update(chunk)

    out.append({
        "name": name,
        "url": f"images/{name}",
        "size": p.stat().st_size,
        "sha256": h.hexdigest(),
    })

manifest = {
    "schema": 1,
    "installer": "WOS-INSTALLER-V00.9",
    "device": "frankel",

    "policy": {
        "unlock": True,
        "flash": True,
        "relock": False,
    },

    "sequence": [
        {
            "op": "flash",
            "partition": "boot",
            "image": "boot.img"
        },
        {
            "op": "flash",
            "partition": "init_boot",
            "image": "init_boot.img"
        },
        {
            "op": "flash",
            "partition": "dtbo",
            "image": "dtbo.img"
        },
        {
            "op": "flash",
            "partition": "vendor_kernel_boot",
            "image": "vendor_kernel_boot.img"
        },
        {
            "op": "flash",
            "partition": "pvmfw",
            "image": "pvmfw.img"
        },
        {
            "op": "flash",
            "partition": "vendor_boot",
            "image": "vendor_boot.img"
        },
        {
            "op": "flash-vbmeta",
            "partition": "vbmeta",
            "image": "vbmeta.img"
        },
        {
            "op": "reboot-fastboot"
        },
        {
            "op": "update-super",
            "image": "super_empty.img"
        },
        {
            "op": "flash",
            "partition": "system",
            "image": "system.img"
        },
        {
            "op": "flash",
            "partition": "system_dlkm",
            "image": "system_dlkm.img"
        },
        {
            "op": "flash",
            "partition": "system_ext",
            "image": "system_ext.img"
        },
        {
            "op": "flash",
            "partition": "product",
            "image": "product.img"
        },
        {
            "op": "flash",
            "partition": "vendor",
            "image": "vendor.img"
        },
        {
            "op": "flash",
            "partition": "vendor_dlkm",
            "image": "vendor_dlkm.img"
        },
        {
            "op": "erase",
            "partition": "userdata"
        },
        {
            "op": "erase",
            "partition": "metadata"
        }
    ],

    "images": out,
}

(release / "images-v009.json").write_text(
    json.dumps(manifest, indent=2) + "\n"
)

print("images =", len(out))
print("manifest=PASS")
PY

echo
echo "WOS_INSTALLER_V00_9_IMAGES=PASS"
