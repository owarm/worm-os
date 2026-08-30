#!/bin/bash

set -Eeuo pipefail

WEB=/opt/Android/worm-os/web-installer

cd "$WEB"

echo "=== worm OS Web Installer ==="
echo
echo "Version: WOS-INSTALLER-V00.1"
echo "URL:     http://localhost:8080"
echo
echo "FLASH_ENABLED=false"
echo

exec python3 \
    -m http.server \
    8080 \
    --bind 127.0.0.1
