#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config/frankel.conf"

echo "Worm OS"
echo "-------"
echo "Target:          $WORM_DEVICE"
echo "Graphene branch: $GRAPHENE_BRANCH"
echo "Kernel target:   $GRAPHENE_KERNEL_TARGET"
echo "Source:          $GRAPHENE_SOURCE_DIR"
echo

if [ -d "$GRAPHENE_SOURCE_DIR/.repo" ]; then
    echo "GrapheneOS source: PRESENT"
else
    echo "GrapheneOS source: NOT DOWNLOADED"
fi

echo
echo "Worm repository:"
git -C "$ROOT" status --short --branch
