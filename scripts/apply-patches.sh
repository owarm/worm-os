#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="$ROOT/config/frankel.conf"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

warn() {
    echo "WARN: $*" >&2
}

refuse_signing_path() {
    local path="$1"
    case "$path" in
        *"/keys"|*"/keys/"*|*"/secrets"|*"/secrets/"*|*.pem|*.key|*.keystore|*.jks|*.p12|*.pfx)
            die "refusing to operate on signing material or secret path: $path"
            ;;
    esac
}

refuse_repo_path() {
    local path="$1"
    case "$path" in
        "$ROOT"|"$ROOT"/*)
            die "GrapheneOS checkout must be outside this Git repository: $path"
            ;;
    esac
}

patch_touches_protected_path() {
    local patch_file="$1"
    grep -E '^(---|\+\+\+) [ab]/.*(keys/|secrets/|\.pem$|\.key$|\.keystore$|\.jks$|\.p12$|\.pfx$)' "$patch_file" >/dev/null
}

validate_relative_path() {
    local kind="$1"
    local path="$2"

    [ -n "$path" ] || die "empty $kind path"

    case "$path" in
        /*|*//*)
            die "invalid $kind path: $path"
            ;;
    esac

    local IFS='/'
    local component
    for component in $path; do
        case "$component" in
            ''|.|..)
                die "invalid $kind path component in: $path"
                ;;
        esac
    done
}

[ -r "$CONFIG" ] || die "missing configuration: $CONFIG"
source "$CONFIG"

PATCH_ROOT="$ROOT/$WORM_PATCH_DIR"
ROOT="$(cd "$ROOT" && pwd -P)"
PATCH_ROOT="$(cd "$PATCH_ROOT" 2>/dev/null && pwd -P || true)"
GRAPHENE_SOURCE_DIR="$(cd "$GRAPHENE_SOURCE_DIR" 2>/dev/null && pwd -P || true)"

[ -n "$PATCH_ROOT" ] || die "patch directory not found: $ROOT/$WORM_PATCH_DIR"
[ -n "$GRAPHENE_SOURCE_DIR" ] || die "GrapheneOS source tree not found"
[ -d "$GRAPHENE_SOURCE_DIR/.repo" ] || die "GrapheneOS source tree not found: $GRAPHENE_SOURCE_DIR"
refuse_repo_path "$GRAPHENE_SOURCE_DIR"
refuse_signing_path "$GRAPHENE_SOURCE_DIR"

if ! find "$PATCH_ROOT" -type f -name '*.patch' -print -quit | grep -q .; then
    echo "No Worm GrapheneOS patches found in $PATCH_ROOT."
    exit 0
fi

echo "Applying Worm patches from $PATCH_ROOT"
echo "GrapheneOS checkout: $GRAPHENE_SOURCE_DIR"
echo

find "$PATCH_ROOT" -type f -name '*.patch' -print0 | sort -z |
while IFS= read -r -d '' PATCH_FILE; do
    RELATIVE="${PATCH_FILE#$PATCH_ROOT/}"
    validate_relative_path "patch" "$RELATIVE"

    PATCH_NAME="$(basename "$RELATIVE")"
    PROJECT="$(dirname "$RELATIVE")"

    if [ "$PROJECT" = "." ]; then
        warn "skipping malformed patch path, expected patches/graphene/<project>/<file>.patch: $PATCH_FILE"
        continue
    fi

    validate_relative_path "project" "$PROJECT"
    validate_relative_path "patch name" "$PATCH_NAME"

    PROJECT_DIR="$GRAPHENE_SOURCE_DIR/$PROJECT"
    refuse_signing_path "$PATCH_FILE"

    if patch_touches_protected_path "$PATCH_FILE"; then
        die "patch touches protected signing or secret path: $PATCH_FILE"
    fi

    [ -d "$PROJECT_DIR/.git" ] || die "GrapheneOS project does not exist: $PROJECT_DIR"

    echo "Applying: $PROJECT / $PATCH_NAME"

    if ! git -C "$PROJECT_DIR" apply --check "$PATCH_FILE"; then
        echo
        echo "PATCH CONFLICT: $RELATIVE"
        echo "The patch did not apply cleanly to upstream GrapheneOS."
        echo "Review upstream changes and refresh the patch manually; it was not force-applied."
        exit 1
    fi

    git -C "$PROJECT_DIR" apply \
        "$PATCH_FILE"
done

echo "Worm patches applied."
