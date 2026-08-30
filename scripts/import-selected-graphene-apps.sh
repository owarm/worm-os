#!/bin/bash
set -Eeuo pipefail

UPSTREAM=/opt/Android/worm-os/graphene-app-repo-upstream
WORM=/opt/Android/worm-os/worm-app-repo

PACKAGES=(
  app.attestation.auditor
  app.grapheneos.AppCompatConfig
  app.grapheneos.apps
  app.grapheneos.camera
  app.grapheneos.gmscompat.config
  app.grapheneos.gmscompat.lib
  app.grapheneos.info
  app.grapheneos.pdfviewer
  app.grapheneos.speechservices
  app.vanadium.browser
  app.vanadium.config
  app.vanadium.trichromelibrary
  app.vanadium.webview
  com.android.messaging
)

for pkg in "${PACKAGES[@]}"; do
    echo
    echo "=== $pkg ==="

    SRC="$UPSTREAM/apps/packages/$pkg"
    DST="$WORM/apps/packages/$pkg"

    test -d "$SRC" || {
        echo "SKIP: metadata missing"
        continue
    }

    mkdir -p "$DST"

    # common package metadata
    for f in common-props.toml icon.webp; do
        if [ -f "$SRC/$f" ]; then
            cp -f "$SRC/$f" "$DST/$f"
        fi
    done

    # newest numeric version declared upstream
    VERSION="$(
      find "$SRC" \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -printf '%f\n' \
      | grep -E '^[0-9]+$' \
      | sort -n \
      | tail -1
    )"

    if [ -z "$VERSION" ]; then
        echo "SKIP: no version directory"
        continue
    fi

    echo "version=$VERSION"

    mkdir -p "$DST/$VERSION"

    for f in channel.toml props.toml; do
        if [ -f "$SRC/$VERSION/$f" ]; then
            cp -f \
              "$SRC/$VERSION/$f" \
              "$DST/$VERSION/$f"
        fi
    done

    URL="https://apps.grapheneos.org/packages/$pkg/$VERSION/base.apk"

    echo "download=$URL"

    curl -fL \
      --retry 3 \
      --retry-delay 2 \
      "$URL" \
      -o "$DST/$VERSION/base.apk"

    test -s "$DST/$VERSION/base.apk"

    echo "$pkg/$VERSION=PASS"
done

echo
echo "GRAPHENE_SELECTED_IMPORT=PASS"
