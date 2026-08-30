#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"

NODE_VERSION=v24.19.0
FILE="node-${NODE_VERSION}-linux-x64.tar.xz"
BASE="https://nodejs.org/download/release/${NODE_VERSION}"

echo "=== WOS-PIXEL10-V00.2 / Node 24 ==="

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cd "$TMP"

echo
echo "=== DOWNLOAD ==="

curl -fLO "$BASE/$FILE"
curl -fLO "$BASE/SHASUMS256.txt"

echo
echo "=== VERIFY SHA256 ==="

grep " $FILE\$" SHASUMS256.txt > node.sha256
sha256sum -c node.sha256

echo "node_archive=PASS"

echo
echo "=== INSTALL INSIDE CHROOT ==="

mkdir -p "$CHROOT/opt/node"

rm -rf "$CHROOT/opt/node/node-${NODE_VERSION}-linux-x64"

tar -xJf "$FILE" \
    -C "$CHROOT/opt/node"

ln -sfn \
    "/opt/node/node-${NODE_VERSION}-linux-x64/bin/node" \
    "$CHROOT/usr/local/bin/node"

ln -sfn \
    "/opt/node/node-${NODE_VERSION}-linux-x64/bin/npm" \
    "$CHROOT/usr/local/bin/npm"

ln -sfn \
    "/opt/node/node-${NODE_VERSION}-linux-x64/bin/npx" \
    "$CHROOT/usr/local/bin/npx"

echo
echo "=== VERIFY ==="

NODE_ACTUAL="$(
    chroot "$CHROOT" \
        /usr/local/bin/node --version
)"

echo "node=$NODE_ACTUAL"

test "$NODE_ACTUAL" = "$NODE_VERSION"

echo -n "yarnpkg="
chroot "$CHROOT" /usr/bin/yarnpkg --version

echo
echo "Node24=PASS"
echo "yarnpkg=PASS"
echo "phone=NOT_TOUCHED"
echo
echo "WOS_PIXEL10_V00_2_NODE=PASS"
