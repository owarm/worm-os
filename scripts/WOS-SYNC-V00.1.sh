#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"
PATCHES="$ROOT/patches"
OVERLAYS="$ROOT/overlays"
BACKUP="$ROOT/backups/sync-$(date +%Y%m%d-%H%M%S)"

echo "=== WOS-SYNC-V00.1 ==="

mkdir -p "$BACKUP"

cd "$UPSTREAM"

echo
echo "=== PRECHECK ==="

test -d .repo
test -x "$ROOT/scripts/apply-worm-overlays.sh"

echo "repo_tree=PASS"
echo "overlay_script=PASS"

echo
echo "=== BACKUP CURRENT WORM FILES ==="

mkdir -p \
  "$BACKUP/vendor/google_devices/frankel" \
  "$BACKUP/vendor/worm/WormLauncher/prebuilt" \
  "$BACKUP/external/AppStore/prebuilt" \
  "$BACKUP/packages/apps/Updater"

cp -a \
  vendor/google_devices/frankel/frankel.mk \
  "$BACKUP/vendor/google_devices/frankel/" \
  2>/dev/null || true

cp -a \
  vendor/worm/WormLauncher/Android.bp \
  "$BACKUP/vendor/worm/WormLauncher/" \
  2>/dev/null || true

cp -a \
  vendor/worm/WormLauncher/prebuilt/WormLauncher.apk \
  "$BACKUP/vendor/worm/WormLauncher/prebuilt/" \
  2>/dev/null || true

cp -a \
  external/AppStore/prebuilt/app-release.apk \
  "$BACKUP/external/AppStore/prebuilt/" \
  2>/dev/null || true

cp -a \
  packages/apps/Updater/res/values/config.xml \
  "$BACKUP/packages/apps/Updater/" \
  2>/dev/null || true

cp -a \
  packages/apps/Updater/res/xml/network_security_config.xml \
  "$BACKUP/packages/apps/Updater/" \
  2>/dev/null || true

echo "backup=$BACKUP"
echo "backup=PASS"

echo
echo "=== REPO STATUS BEFORE ==="
repo status || true

echo
echo "=== SYNC GRAPHENEOS ==="

repo sync -j8

echo "repo_sync=PASS"

echo
echo "=== APPLY UPDATER PATCH ==="

cd "$UPSTREAM/packages/apps/Updater"

git config --add safe.directory \
  "$UPSTREAM/packages/apps/Updater" \
  2>/dev/null || true

if grep -Rq \
  'worm.estixari.com/releases' \
  res; then

  echo "Updater patch already present"

else

  PATCH_COUNT="$(
    find "$PATCHES/updater" \
      -maxdepth 1 \
      -type f \
      -name '0001-*.patch' \
      2>/dev/null |
    wc -l
  )"

  if [ "$PATCH_COUNT" -eq 0 ]; then
    echo "FAIL: updater patch missing"
    exit 1
  fi

  git am --3way \
    "$PATCHES"/updater/0001-*.patch

fi

echo "updater_patch=PASS"

echo
echo "=== APPLY WORM OVERLAYS ==="

"$ROOT/scripts/apply-worm-overlays.sh"

echo
echo "=== VERIFY LAUNCHER ==="

grep -q \
  'PRODUCT_PACKAGES -= Launcher3QuickStep' \
  "$UPSTREAM/vendor/google_devices/frankel/frankel.mk"

grep -q \
  'PRODUCT_PACKAGES += WormLauncher' \
  "$UPSTREAM/vendor/google_devices/frankel/frankel.mk"

test -s \
  "$UPSTREAM/vendor/worm/WormLauncher/prebuilt/WormLauncher.apk"

echo "launcher=PASS"

echo
echo "=== VERIFY APPSTORE ==="

test -s \
  "$UPSTREAM/external/AppStore/prebuilt/app-release.apk"

APPSTORE_STRINGS="$(mktemp)"
trap 'rm -f "$APPSTORE_STRINGS"' EXIT

strings \
  "$UPSTREAM/external/AppStore/prebuilt/app-release.apk" \
  > "$APPSTORE_STRINGS"

if grep -Fq \
  'apps.grapheneos.org' \
  "$APPSTORE_STRINGS"; then

  echo "FAIL: GrapheneOS AppStore endpoint still present"
  exit 1
fi

grep -Fq \
  'worm.estixari.com/apps' \
  "$APPSTORE_STRINGS"

rm -f "$APPSTORE_STRINGS"
trap - EXIT

echo "appstore=PASS"

echo
echo "=== VERIFY UPDATER ==="

grep -Rq \
  'worm.estixari.com/releases' \
  "$UPSTREAM/packages/apps/Updater/res"

if grep -Rq \
  'releases.grapheneos.org' \
  "$UPSTREAM/packages/apps/Updater/res"; then

  echo "FAIL: GrapheneOS updater endpoint remains"
  exit 1
fi

echo "updater=PASS"

echo
echo "=== FINAL REPO STATUS ==="

cd "$UPSTREAM"
repo status || true

echo
echo "WOS_SYNC_V00_1=PASS"
