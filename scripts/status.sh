#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/frankel.conf"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -r "$CONFIG" ] || die "missing configuration: $CONFIG"
source "$CONFIG"

PATCH_ROOT="$ROOT/$WORM_PATCH_DIR"
OVERLAY_ROOT="$ROOT/$WORM_OVERLAY_DIR"

echo "Worm OS"
echo "-------"
echo "Target:            $WORM_PRODUCT ($WORM_DEVICE)"
echo "Graphene branch:   $GRAPHENE_BRANCH"
echo "Kernel family:     $WORM_KERNEL_FAMILY"
echo "Graphene checkout: $GRAPHENE_SOURCE_DIR"
echo

if [ -d "$GRAPHENE_SOURCE_DIR/.repo" ]; then
    echo "GrapheneOS source: PRESENT"
else
    echo "GrapheneOS source: NOT DOWNLOADED"
fi

if [ -d "$PATCH_ROOT" ]; then
    PATCH_COUNT="$(find "$PATCH_ROOT" -type f -name '*.patch' | wc -l | tr -d ' ')"
    echo "Graphene patches:  $PATCH_COUNT"
else
    echo "Graphene patches:  MISSING DIRECTORY"
fi

if [ -d "$OVERLAY_ROOT" ]; then
    OVERLAY_COUNT="$(find "$OVERLAY_ROOT" -type f ! -name '.gitkeep' | wc -l | tr -d ' ')"
    echo "Frankel overlays:  $OVERLAY_COUNT"
else
    echo "Frankel overlays:  MISSING DIRECTORY"
fi

echo
echo "Worm repository:"
git -C "$ROOT" status --short --branch
