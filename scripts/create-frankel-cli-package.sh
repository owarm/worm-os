#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
OUT="$ROOT/upstream/out/target/product/frankel"
PKG="$ROOT/releases/worm-frankel-cli-20260826-dev1"
ZIP="$ROOT/releases/worm-frankel-cli-20260826-dev1.zip"

echo "=== WORM FRANKEL CLI PACKAGE ==="

rm -rf "$PKG"
mkdir -p "$PKG"

FILES=(
  android-info.txt
  fastboot-info.txt

  boot.img
  init_boot.img
  dtbo.img
  vendor_kernel_boot.img
  pvmfw.img
  vendor_boot.img
  vbmeta.img

  super_empty.img

  system.img
  system_dlkm.img
  system_ext.img
  product.img
  vendor.img
  vendor_dlkm.img
)

for f in "${FILES[@]}"; do
    test -f "$OUT/$f" || {
        echo "FAIL: missing $f"
        exit 1
    }

    cp --reflink=auto "$OUT/$f" "$PKG/$f"
    echo "$f=PASS"
done

cat > "$PKG/FLASH-WINDOWS.cmd" <<'EOF'
@echo off
setlocal

echo === worm OS / Pixel 10 frankel ===
echo.

fastboot.exe devices
if errorlevel 1 goto fail

echo.
fastboot.exe getvar product 2>&1
fastboot.exe getvar unlocked 2>&1

echo.
echo This will erase userdata and metadata.
echo Bootloader must already be unlocked.
echo Press Ctrl+C now to cancel.
pause

set ANDROID_PRODUCT_OUT=%~dp0

fastboot.exe -w flashall
if errorlevel 1 goto fail

echo.
echo ======================================
echo worm OS flash completed successfully
echo Bootloader relock: DISABLED
echo ======================================
goto end

:fail
echo.
echo FLASH FAILED - DO NOT RELOCK BOOTLOADER
exit /b 1

:end
endlocal
EOF

(
  cd "$PKG"
  sha256sum \
    "${FILES[@]}" \
    > SHA256SUMS
)

rm -f "$ZIP"

(
  cd "$(dirname "$PKG")"
  zip -0 -r \
    "$(basename "$ZIP")" \
    "$(basename "$PKG")"
)

sha256sum "$ZIP" > "$ZIP.sha256"

echo
ls -lh "$ZIP"
cat "$ZIP.sha256"

echo
echo "WORM_FRANKEL_CLI_PACKAGE=PASS"
