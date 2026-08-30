#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"
OVERLAYS="$ROOT/overlays"

echo "=== APPLY WORM OS OVERLAYS ==="

rsync -a \
  "$OVERLAYS/" \
  "$UPSTREAM/"

test -f \
  "$UPSTREAM/vendor/worm/WormLauncher/prebuilt/WormLauncher.apk"

test -f \
  "$UPSTREAM/external/AppStore/prebuilt/app-release.apk"

grep -q \
  'WormLauncher' \
  "$UPSTREAM/vendor/google_devices/frankel/frankel.mk"

echo "WORM_OVERLAYS=PASS"
