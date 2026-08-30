#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
ROOTFS="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"

echo "=== WOS-BUILDENV-V00.5 / unshare backend ==="

test -d "$ROOTFS"
test -x "$UPSTREAM/prebuilts/build-tools/linux-x86/bin/nsjail"

exec unshare \
  --mount \
  --uts \
  --ipc \
  --pid \
  --fork \
  --mount-proc=/proc \
  /bin/bash -c "
set -Eeuo pipefail

mount --make-rprivate /

mount --bind '$ROOTFS' '$ROOTFS'

mount --bind '$UPSTREAM' \
  '$ROOTFS/opt/Android/worm-os/upstream'

mount -t proc proc '$ROOTFS/proc'

mount --rbind /dev '$ROOTFS/dev'
mount --make-rslave '$ROOTFS/dev'

mount --rbind /sys '$ROOTFS/sys'
mount --make-rslave '$ROOTFS/sys'

chroot --userspec=1000:1000 '$ROOTFS' \
  /usr/bin/env \
    HOME=/home/wormbuild \
    USER=wormbuild \
    LOGNAME=wormbuild \
    SHELL=/bin/bash \
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    /bin/bash --noprofile --norc -c '
      set -Eeuo pipefail

      cd /opt/Android/worm-os/upstream

      echo \"=== USERNS ===\"

      unshare -Ur true
      echo \"USERNS=PASS\"

      echo
      echo \"=== NSJAIL ===\"

      NSJAIL=prebuilts/build-tools/linux-x86/bin/nsjail

      \"\$NSJAIL\" \
        -v \
        -H android-build \
        -e \
        -u nobody \
        -g nogroup \
        -B / \
        --disable_clone_newcgroup \
        -- \
        /bin/bash -c \"
          echo hostname=\\\$(hostname)
          id
          test \\\$(hostname) = android-build
          echo Android_Success
        \"

      echo
      echo \"NSJAIL_SELFTEST=PASS\"
    '
"
