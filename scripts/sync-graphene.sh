#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/frankel.conf"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

realpath_existing_parent() {
    local target="$1"
    local parent
    parent="$(dirname "$target")"
    [ -d "$parent" ] || die "parent directory does not exist: $parent"
    (cd "$parent" && printf '%s/%s\n' "$(pwd -P)" "$(basename "$target")")
}

refuse_repo_path() {
    local path="$1"
    case "$path" in
        "$ROOT"|"$ROOT"/*)
            die "GrapheneOS checkout must be outside this Git repository: $path"
            ;;
    esac
}

refuse_signing_path() {
    local path="$1"
    case "$path" in
        *"/keys"|*"/keys/"*|*"/secrets"|*"/secrets/"*|*.pem|*.key|*.keystore|*.jks|*.p12|*.pfx)
            die "refusing to operate on signing material or secret path: $path"
            ;;
    esac
}

[ -r "$CONFIG" ] || die "missing configuration: $CONFIG"
source "$CONFIG"

[ -n "${GRAPHENE_SOURCE_DIR:-}" ] || die "GRAPHENE_SOURCE_DIR is empty"
[ -n "${GRAPHENE_BRANCH:-}" ] || die "GRAPHENE_BRANCH is empty"
[ -n "${GRAPHENE_MANIFEST_URL:-}" ] || die "GRAPHENE_MANIFEST_URL is empty"

ROOT="$(cd "$ROOT" && pwd -P)"
GRAPHENE_SOURCE_DIR="$(realpath_existing_parent "$GRAPHENE_SOURCE_DIR")"
refuse_repo_path "$GRAPHENE_SOURCE_DIR"
refuse_signing_path "$GRAPHENE_SOURCE_DIR"

if ! command -v repo >/dev/null 2>&1; then
    die "Android repo tool is not installed"
fi

echo "Worm OS upstream sync"
echo "Device:             $WORM_PRODUCT ($WORM_DEVICE)"
echo "GrapheneOS branch:  $GRAPHENE_BRANCH"
echo "Kernel family:      $WORM_KERNEL_FAMILY"
echo "Destination:        $GRAPHENE_SOURCE_DIR"
echo

mkdir -p "$GRAPHENE_SOURCE_DIR"
cd "$GRAPHENE_SOURCE_DIR"

if [ ! -d ".repo" ]; then
    [ -z "$(find . -mindepth 1 -maxdepth 1 -print -quit)" ] || \
        die "destination exists but is not an empty repo checkout: $GRAPHENE_SOURCE_DIR"
    repo init \
        -u "$GRAPHENE_MANIFEST_URL" \
        -b "$GRAPHENE_BRANCH" \
        --current-branch
else
    [ -d ".repo/manifests" ] || die "invalid repo checkout: missing .repo/manifests"
fi

repo sync

echo
echo "GrapheneOS synchronization complete."
