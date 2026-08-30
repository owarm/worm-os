#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"

USER=wormbuild
UID_NUM=1000
GID_NUM=1000

echo "=== worm OS build user ==="

# Gruppo
if ! chroot "$CHROOT" getent group "$GID_NUM" >/dev/null 2>&1; then
    chroot "$CHROOT" groupadd -g "$GID_NUM" "$USER"
fi

# Utente
if ! chroot "$CHROOT" getent passwd "$UID_NUM" >/dev/null 2>&1; then
    chroot "$CHROOT" useradd \
        -m \
        -u "$UID_NUM" \
        -g "$GID_NUM" \
        -s /bin/bash \
        "$USER"
fi

echo
echo "=== OWN SOURCE TREE ==="

chown -R "$UID_NUM:$GID_NUM" "$UPSTREAM"

echo
echo "=== VERIFY ==="

chroot "$CHROOT" id "$USER"

stat -c \
    'upstream_owner=%u:%g' \
    "$UPSTREAM"

echo
echo "WORM_BUILD_USER=PASS"
