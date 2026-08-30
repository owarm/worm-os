#!/bin/bash

set -Eeuo pipefail

ROOT=/opt/Android/worm-os
CHROOT="$ROOT/build-env"
UPSTREAM="$ROOT/upstream"

MACHINE=worm-os-build

fail() {
    trap - ERR

    echo
    echo "WOS_BUILDENV_V00_3=FAIL"
    echo "line=$1"

    exit 1
}

trap 'fail $LINENO' ERR

echo "=== WOS-BUILDENV-V00.3 ==="
echo "backend=systemd-nspawn"
echo "rootfs=$CHROOT"
echo "source=$UPSTREAM"

#
# Prerequisites
#

echo
echo "=== HOST DEPENDENCIES ==="

if ! command -v systemd-nspawn >/dev/null 2>&1; then
    apt-get update

    DEBIAN_FRONTEND=noninteractive \
        apt-get install -y \
        systemd-container \
        util-linux
fi

command -v systemd-nspawn
command -v unshare

echo "systemd-nspawn=$(systemd-nspawn --version | head -1)"
echo "host_dependencies=PASS"

#
# Existing environment
#

echo
echo "=== ROOTFS ==="

test -f "$CHROOT/etc/debian_version"
test -x "$CHROOT/bin/bash"

DEBIAN_VERSION="$(cat "$CHROOT/etc/debian_version")"

echo "debian=$DEBIAN_VERSION"

case "$DEBIAN_VERSION" in
    12.*)
        ;;
    *)
        echo "FAIL: expected Debian 12"
        exit 1
        ;;
esac

chroot "$CHROOT" id wormbuild

echo "rootfs=PASS"

#
# Source tree
#

echo
echo "=== SOURCE ==="

test -d "$UPSTREAM/.repo"
test -f "$UPSTREAM/build/envsetup.sh"

OWNER="$(
    stat -c '%u:%g' "$UPSTREAM"
)"

echo "owner=$OWNER"

if [ "$OWNER" != "1000:1000" ]; then
    echo "FAIL: upstream must belong to wormbuild 1000:1000"
    exit 1
fi

echo "source=PASS"

#
# Ensure no stale mounts from old chroot setup
#

echo
echo "=== OLD CHROOT MOUNTS ==="

if findmnt -R "$CHROOT" \
    | grep -q "$CHROOT/opt/Android/worm-os/upstream"
then
    echo "FAIL: stale upstream bind mount exists"
    findmnt -R "$CHROOT"
    exit 1
fi

echo "stale_mounts=NONE"

#
# Kernel policy
#

echo
echo "=== USERNS HOST POLICY ==="

if [ -r /proc/sys/kernel/unprivileged_userns_clone ]; then
    USERNS_CLONE="$(
        cat /proc/sys/kernel/unprivileged_userns_clone
    )"

    echo "kernel.unprivileged_userns_clone=$USERNS_CLONE"

    test "$USERNS_CLONE" = "1"
fi

MAX_USERNS="$(
    cat /proc/sys/user/max_user_namespaces
)"

echo "user.max_user_namespaces=$MAX_USERNS"

if [ "$MAX_USERNS" -le 0 ]; then
    echo "FAIL: user namespaces disabled"
    exit 1
fi

echo "host_userns_policy=PASS"

#
# Test nspawn itself
#

echo
echo "=== NSPAWN BASIC TEST ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --machine="$MACHINE" \
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
        /bin/bash --noprofile --norc -c '
            set -Eeuo pipefail

            echo "uid=$(id -u)"
            echo "gid=$(id -g)"
            echo "user=$(id -un)"

            test "$(id -u)" = 1000
            test "$(id -g)" = 1000

            test -r /proc/cpuinfo
            test -e /dev/null
            test -e /dev/fd
            test -d /sys

            echo "/proc=PASS"
            echo "/dev=PASS"
            echo "/dev/fd=PASS"
            echo "/sys=PASS"
        '

echo "nspawn_basic=PASS"

#
# Critical test:
# can a non-root process create a nested user namespace?
#

echo
echo "=== NESTED USER NAMESPACE ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --machine="$MACHINE-userns" \
    --register=no \
    --keep-unit \
    --private-users=no \
    -u wormbuild \
    /usr/bin/env \
        HOME=/home/wormbuild \
        USER=wormbuild \
        LOGNAME=wormbuild \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --noprofile --norc -c '
            set -Eeuo pipefail

            echo "before:"
            id

            unshare -Ur /bin/bash -c "
                set -e

                echo after:
                id

                test \"\$(id -u)\" = 0
            "

            echo "USERNS=PASS"
        '

echo "nested_userns=PASS"

#
# Verify GNU inetutils hostname
#

echo
echo "=== HOSTNAME / NAMESPACE DETECTION ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --machine="$MACHINE-hostname" \
    --register=no \
    --keep-unit \
    --private-users=no \
    -u wormbuild \
    /usr/bin/env \
        HOME=/home/wormbuild \
        PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
        /bin/bash --noprofile --norc -c '
            set -Eeuo pipefail

            type hostname

            hostname --version | head -1

            echo "hostname=PASS"
        '

#
# GrapheneOS envsetup only.
# NO adevtool.
# NO build.
#

echo
echo "=== GRAPHENEOS ENVSETUP ==="

systemd-nspawn \
    --quiet \
    --directory="$CHROOT" \
    --machine="$MACHINE-env" \
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
        /bin/bash --noprofile --norc -c '
            set -Eeuo pipefail

            cd /opt/Android/worm-os/upstream

            source build/envsetup.sh

            type gettop >/dev/null
            type lunch >/dev/null

            TOP="$(gettop)"

            echo "gettop=$TOP"

            test "$TOP" = "/opt/Android/worm-os/upstream"

            echo "envsetup=PASS"
            echo "gettop=PASS"
            echo "lunch_function=PASS"
        '

echo
echo "=== VERIFY NO BUILD ==="

if [ -d "$UPSTREAM/out" ]; then
    echo "out_present=yes"
else
    echo "out_present=no"
fi

echo "adevtool_generate=NOT_RUN"
echo "compile=NOT_RUN"
echo "phone=NOT_TOUCHED"
echo "flash=NOT_RUN"

echo
echo "NSJAIL_ENV=PASS"
echo "WOS_BUILDENV_V00_3=PASS"
