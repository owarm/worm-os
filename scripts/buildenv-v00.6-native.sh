#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os
UPSTREAM="$ROOT/upstream"
USER_NAME=wormbuild
UID_NUM=1000
GID_NUM=1000

echo "=== WOS-BUILDENV-V00.6 ==="
echo "backend=Debian13-native"

echo
echo "=== HOST ==="
cat /etc/os-release | grep -E '^(PRETTY_NAME|VERSION_ID)='
uname -r

echo
echo "=== BUILD USER ==="

EXISTING_UID="$(getent passwd "$UID_NUM" || true)"
EXISTING_USER="$(getent passwd "$USER_NAME" || true)"

if [ -n "$EXISTING_UID" ]; then
    echo "UID $UID_NUM already exists:"
    echo "$EXISTING_UID"

    EXISTING_NAME="$(printf '%s' "$EXISTING_UID" | cut -d: -f1)"

    if [ "$EXISTING_NAME" != "$USER_NAME" ]; then
        echo
        echo "STOP: UID 1000 belongs to $EXISTING_NAME"
        echo "No changes made."
        exit 2
    fi
fi

if [ -z "$EXISTING_USER" ]; then

    if ! getent group "$GID_NUM" >/dev/null; then
        groupadd \
            --gid "$GID_NUM" \
            "$USER_NAME"
    fi

    useradd \
        --uid "$UID_NUM" \
        --gid "$GID_NUM" \
        --create-home \
        --shell /bin/bash \
        "$USER_NAME"
fi

id "$USER_NAME"

echo "build_user=PASS"

echo
echo "=== SOURCE OWNERSHIP ==="

OWNER="$(stat -c '%u:%g' "$UPSTREAM")"
echo "owner=$OWNER"

test "$OWNER" = "1000:1000"

echo "ownership=PASS"

echo
echo "=== HOST USERNS ==="

su -s /bin/bash "$USER_NAME" -c '
    set -Eeuo pipefail

    unshare -Ur true
    echo "USERNS=PASS"

    unshare -Urmuipfn true
    echo "ALL_NAMESPACES=PASS"
'

echo
echo "=== NSJAIL NATIVE ==="

su -s /bin/bash "$USER_NAME" -c "
    set -Eeuo pipefail

    cd '$UPSTREAM'

    NSJAIL=prebuilts/build-tools/linux-x86/bin/nsjail

    test -x \"\$NSJAIL\"

    \"\$NSJAIL\" \
        -v \
        -H android-build \
        -e \
        -u nobody \
        -g nogroup \
        -B / \
        --disable_clone_newcgroup \
        -- \
        /bin/bash -c '
            echo \"hostname=\$(hostname)\"
            id

            test \"\$(hostname)\" = android-build

            echo \"Android Success\"
        '

    echo \"NSJAIL_NATIVE=PASS\"
"

echo
echo "=== SOURCE ENVSETUP NATIVE ==="

su -s /bin/bash "$USER_NAME" -c "
    set -Eeuo pipefail

    cd '$UPSTREAM'

    source build/envsetup.sh

    TOP=\"\$(gettop)\"

    echo \"gettop=\$TOP\"

    test \"\$TOP\" = '$UPSTREAM'

    type lunch >/dev/null

    echo 'envsetup=PASS'
    echo 'lunch_function=PASS'
"

echo
echo "=== RESULT ==="
echo "backend=Debian13-native"
echo "adevtool=NOT_RUN"
echo "compile=NOT_RUN"
echo "phone=NOT_TOUCHED"
echo "flash=NOT_RUN"

echo
echo "WOS_NATIVE_NSJAIL=PASS"
echo "WOS_BUILDENV_V00_6=PASS"
