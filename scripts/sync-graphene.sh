#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config/frankel.conf"

echo "Worm OS upstream sync"
echo "Device: $WORM_DEVICE"
echo "GrapheneOS branch: $GRAPHENE_BRANCH"
echo "Destination: $GRAPHENE_SOURCE_DIR"

if ! command -v repo >/dev/null 2>&1; then
    echo "ERROR: Android repo tool is not installed."
    exit 1
fi

mkdir -p "$GRAPHENE_SOURCE_DIR"
cd "$GRAPHENE_SOURCE_DIR"

if [ ! -d ".repo" ]; then
    repo init \
        -u "$GRAPHENE_MANIFEST_URL" \
        -b "$GRAPHENE_BRANCH"
fi

repo sync

echo
echo "GrapheneOS synchronization complete."
