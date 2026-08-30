#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os/upstream

cd "$ROOT"

echo "=== WORM OS UPSTREAM SYNC ==="

echo
echo "1. Check local tree"

repo status

echo
echo "2. Update GrapheneOS manifest"

repo init \
  -u https://github.com/GrapheneOS/platform_manifest.git \
  -b 17

echo
echo "3. Sync GrapheneOS"

repo sync -j8

echo
echo "4. GrapheneOS sync complete"

echo "WORM_SYNC=PASS"
