#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/config/frankel.conf"

PATCH_ROOT="$ROOT/$WORM_PATCH_DIR"

if [ ! -d "$GRAPHENE_SOURCE_DIR/.repo" ]; then
    echo "ERROR: GrapheneOS source tree not found:"
    echo "$GRAPHENE_SOURCE_DIR"
    exit 1
fi

if [ ! -d "$PATCH_ROOT" ]; then
    echo "No Worm patches found."
    exit 0
fi

find "$PATCH_ROOT" -type f -name '*.patch' -print0 |
while IFS= read -r -d '' PATCH_FILE; do
    RELATIVE="${PATCH_FILE#$PATCH_ROOT/}"
    PROJECT="${RELATIVE%%/*}"

    if [ "$PROJECT" = "$RELATIVE" ]; then
        echo "Skipping malformed patch path: $PATCH_FILE"
        continue
    fi

    PATCH_NAME="${RELATIVE#*/}"
    PROJECT_DIR="$GRAPHENE_SOURCE_DIR/$PROJECT"

    if [ ! -d "$PROJECT_DIR/.git" ]; then
        echo "ERROR: project does not exist: $PROJECT"
        exit 1
    fi

    echo "Applying: $PROJECT / $PATCH_NAME"

    git -C "$PROJECT_DIR" apply \
        --check \
        "$PATCH_FILE"

    git -C "$PROJECT_DIR" apply \
        "$PATCH_FILE"
done

echo "Worm patches applied."
