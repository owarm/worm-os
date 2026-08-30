#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"

echo "=== WOS-BUILDENV-V00.4 / NSJAIL CHECK ==="

test -x \
  "$UPSTREAM/prebuilts/build-tools/linux-x86/bin/nsjail"

echo
echo "=== 1. EXTENDED NAMESPACE TEST ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --register=no \
    --keep-unit \
    --private-users=no \
    -u wormbuild \
    /usr/bin/env \
      HOME=/home/wormbuild \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      /bin/bash --noprofile --norc -c '
        set -Eeuo pipefail

        echo "user:"
        unshare -Ur true
        echo "USER=PASS"

        echo "user+mount:"
        unshare -Urm true
        echo "USER_MOUNT=PASS"

        echo "user+mount+uts:"
        unshare -Urmu true
        echo "USER_MOUNT_UTS=PASS"

        echo "user+mount+uts+ipc:"
        unshare -Urmui true
        echo "USER_MOUNT_UTS_IPC=PASS"

        echo "user+mount+uts+ipc+pid:"
        unshare -Urmuipf true
        echo "USER_MOUNT_UTS_IPC_PID=PASS"

        echo "all + network:"
        unshare -Urmuipfn true
        echo "USER_MOUNT_UTS_IPC_PID_NET=PASS"
      '

echo
echo "=== 2. NSJAIL SELF TEST ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --register=no \
    --keep-unit \
    --private-users=no \
    --bind="$UPSTREAM:/opt/Android/worm-os/upstream" \
    -u wormbuild \
    /usr/bin/env \
      HOME=/home/wormbuild \
      USER=wormbuild \
      LOGNAME=wormbuild \
      SHELL=/bin/bash \
      PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
      /bin/bash --noprofile --norc <<'NSPAWN'
set -Eeuo pipefail

cd /opt/Android/worm-os/upstream

NSJAIL=prebuilts/build-tools/linux-x86/bin/nsjail

echo "nsjail=$NSJAIL"
"$NSJAIL" --version || true

echo
echo "--- nobody / nogroup ---"
id nobody || true
getent group nogroup || true

echo
echo "--- exact Soong-style test ---"

set +e

"$NSJAIL" \
    -v \
    -H android-build \
    -e \
    -u nobody \
    -g nogroup \
    -B / \
    --disable_clone_newcgroup \
    -- \
    /bin/bash -c '
        echo "hostname=$(hostname)"
        id

        if [ "$(hostname)" = "android-build" ]; then
            echo "Android Success"
        else
            echo "Android Failure"
            exit 1
        fi
    '

RC=$?

set -e

echo
echo "nsjail_rc=$RC"

if [ "$RC" -eq 0 ]; then
    echo "NSJAIL_SELFTEST=PASS"
else
    echo "NSJAIL_SELFTEST=FAIL"
fi

exit "$RC"
NSPAWN

echo
echo "WOS_NSJAIL_ENV=PASS"
