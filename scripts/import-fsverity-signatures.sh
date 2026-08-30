#!/bin/bash
set -Eeuo pipefail

ROOT=/opt/Android/worm-os/worm-app-repo
PACKAGES="$ROOT/apps/packages"

echo "=== IMPORT FS-VERITY SIGNATURES ==="

for props in "$PACKAGES"/*/common-props.toml; do

    [ -f "$props" ] || continue

    if ! grep -q \
      'hasFsVeritySignatures = true' \
      "$props"; then
        continue
    fi

    pkg="$(basename "$(dirname "$props")")"

    echo
    echo "=== $pkg ==="

    for dir in "$PACKAGES/$pkg"/*; do

        [ -d "$dir" ] || continue

        version="$(basename "$dir")"

        case "$version" in
            *[!0-9]*)
                continue
                ;;
        esac

        apk="$dir/base.apk"

        [ -f "$apk" ] || continue

        sig="$dir/base.apk.0.fsv_sig"

        url="https://apps.grapheneos.org/packages/$pkg/$version/base.apk.0.fsv_sig"

        echo "version=$version"
        echo "url=$url"

        curl -fL \
          --retry 3 \
          --retry-delay 2 \
          "$url" \
          -o "$sig"

        test -s "$sig"

        echo "$(basename "$sig")=$(stat -c %s "$sig") bytes"
        echo "$pkg/$version=FSVERITY_PASS"
    done
done

echo
echo "FSVERITY_IMPORT=PASS"
